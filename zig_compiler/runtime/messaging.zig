// messaging.zig
// FasterBASIC Runtime — Worker Messaging Support (Zig)
//
// Implements safe, marshalled bidirectional message passing between
// the main program and WORKER threads.
//
// Architecture:
//   - Each messaging-enabled worker gets two MessageQueues:
//       outbox (main → worker) and inbox (worker → main)
//   - Messages are MessageBlob values with a type tag + payload
//   - Queues are bounded ring buffers with mutex + condvar
//   - All data crossing the boundary is deep-copied (no aliasing)
//
// Exported symbols maintain C ABI compatibility for QBE codegen.

const std = @import("std");

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn malloc(size: usize) ?*anyopaque;
    extern fn calloc(count: usize, size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
    extern fn nanosleep(req: *const Timespec, rem: ?*Timespec) c_int;

    // macOS uses __stderrp; match the pattern in samm_core.zig.
    extern const __stderrp: *anyopaque;
    fn getStderr() *anyopaque {
        return __stderrp;
    }
};

const Timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

// =========================================================================
// External runtime — marshalling (reuse existing infrastructure)
// =========================================================================
extern fn marshall_udt(udt_ptr: ?*const anyopaque, size: i32) callconv(.c) ?*anyopaque;
extern fn unmarshall_udt(blob: ?*anyopaque, udt_ptr: ?*anyopaque, size: i32) callconv(.c) void;
extern fn marshall_udt_deep(
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) ?*anyopaque;
extern fn unmarshall_udt_deep(
    blob: ?*anyopaque,
    udt_ptr: ?*anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) void;
extern fn marshall_array(desc: ?*const anyopaque) callconv(.c) ?*anyopaque;
extern fn unmarshall_array(blob: ?*anyopaque, desc: ?*anyopaque) callconv(.c) void;

// External runtime — string deep copy / release
const StringDescriptor = anyopaque;
extern fn string_clone(str: ?*const StringDescriptor) ?*StringDescriptor;
extern fn string_release(str: ?*StringDescriptor) callconv(.c) void;

// =========================================================================
// Message type tags
// =========================================================================
pub const MSG_DOUBLE: u8 = 0;
pub const MSG_INTEGER: u8 = 1;
pub const MSG_STRING: u8 = 2;
pub const MSG_UDT: u8 = 3;
pub const MSG_ARRAY: u8 = 4;
pub const MSG_CLASS: u8 = 5;
pub const MSG_MARSHALLED: u8 = 6;
pub const MSG_SIGNAL: u8 = 7;

// Signal codes
pub const SIGNAL_CANCEL: i32 = -1;

// =========================================================================
// MessageBlob — a tagged, self-contained message
// =========================================================================
//
// Layout:
//   tag          : u8    — type code (MSG_DOUBLE, MSG_INTEGER, etc.)
//   flags        : u8    — reserved for future use
//   type_id      : i16   — UDT type_id or class class_id (0 = untyped)
//   payload_len  : u32   — byte count of payload
//   payload      : [*]u8 — heap-allocated payload data (or inline for small)
//
// For scalars (DOUBLE, INTEGER), the payload is stored inline in
// inline_value to avoid a separate heap allocation.

pub const MessageBlob = extern struct {
    tag: u8,
    flags: u8,
    /// UDT type_id or CLASS class_id.  0 = untyped / scalar.
    type_id: i16,
    payload_len: u32,
    payload: ?*anyopaque,
    // Inline storage for scalar values (avoids malloc for common case)
    inline_value: u64,
};

// =========================================================================
// MessageMetrics — thread-safe counters for memory tracking & leak detection
// =========================================================================
//
// All counters use atomics so they are safe to update from multiple
// worker threads concurrently.  The metrics are always collected (the
// overhead of a few atomic increments is negligible compared to the
// cost of marshalling / queue operations).  Display is gated behind
// the BASIC_MEMORY_STATS environment variable, same as basic_mem_stats.

pub const MessageMetrics = struct {
    // ── Blob lifecycle ──────────────────────────────────────────────
    blobs_created: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    blobs_freed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    blobs_forwarded: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── Payload lifecycle ───────────────────────────────────────────
    payloads_allocated: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    payloads_freed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    total_payload_bytes: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── String lifecycle (message-owned clones) ─────────────────────
    strings_cloned: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    strings_released: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── Per-type counters (how many of each tag were created) ────────
    count_double: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_integer: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_string: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_udt: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_class: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_array: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_signal: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    count_marshalled: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── Queue traffic ───────────────────────────────────────────────
    messages_pushed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    messages_popped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    messages_dropped: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── Back-pressure indicators ────────────────────────────────────
    push_waits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    pop_waits: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── High-water mark ─────────────────────────────────────────────
    peak_outstanding: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    // ── Queue lifecycle ─────────────────────────────────────────────
    queues_created: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    queues_destroyed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Atomically increment a counter by 1.
    fn inc(counter: *std.atomic.Value(u64)) void {
        _ = counter.fetchAdd(1, .monotonic);
    }

    /// Atomically add a value to a counter.
    fn add(counter: *std.atomic.Value(u64), value: u64) void {
        _ = counter.fetchAdd(value, .monotonic);
    }

    /// Read a counter's current value.
    fn get(counter: *const std.atomic.Value(u64)) u64 {
        return counter.load(.monotonic);
    }

    /// Update peak_outstanding if the current outstanding count is higher.
    fn updatePeak(self: *MessageMetrics) void {
        const created = self.blobs_created.load(.monotonic);
        const freed = self.blobs_freed.load(.monotonic);
        const outstanding = if (created > freed) created - freed else 0;
        // Simple CAS loop to update peak
        var current_peak = self.peak_outstanding.load(.monotonic);
        while (outstanding > current_peak) {
            const result = self.peak_outstanding.cmpxchgWeak(
                current_peak,
                outstanding,
                .monotonic,
                .monotonic,
            );
            if (result) |actual| {
                current_peak = actual;
            } else {
                break; // CAS succeeded
            }
        }
    }

    /// Record a blob creation, updating per-type counter and peak.
    fn recordCreate(self: *MessageMetrics, tag: u8) void {
        inc(&self.blobs_created);
        switch (tag) {
            MSG_DOUBLE => inc(&self.count_double),
            MSG_INTEGER => inc(&self.count_integer),
            MSG_STRING => inc(&self.count_string),
            MSG_UDT => inc(&self.count_udt),
            MSG_CLASS => inc(&self.count_class),
            MSG_ARRAY => inc(&self.count_array),
            MSG_SIGNAL => inc(&self.count_signal),
            MSG_MARSHALLED => inc(&self.count_marshalled),
            else => {},
        }
        self.updatePeak();
    }
};

/// Global metrics instance — always active, negligible overhead.
var g_msg_metrics: MessageMetrics = .{};

// =========================================================================
// MessageQueue — bounded, thread-safe ring buffer
// =========================================================================
pub const MSG_QUEUE_CAPACITY: usize = 256;

pub const MessageQueue = struct {
    slots: [MSG_QUEUE_CAPACITY]?*MessageBlob,
    head: usize, // read index
    tail: usize, // write index
    count: usize, // current size
    closed: bool, // no more pushes allowed
    cancel_flag: std.atomic.Value(bool), // atomic cancel signal

    mutex: std.Thread.Mutex,
    not_empty_cv: std.Thread.Condition,
    not_full_cv: std.Thread.Condition,
};

// =========================================================================
// Queue management — exported C ABI
// =========================================================================

/// Create a new message queue with default capacity.
export fn msg_queue_create() callconv(.c) ?*MessageQueue {
    const q_raw = c.calloc(1, @sizeOf(MessageQueue)) orelse return null;
    const q: *MessageQueue = @ptrCast(@alignCast(q_raw));

    q.head = 0;
    q.tail = 0;
    q.count = 0;
    q.closed = false;
    q.cancel_flag = std.atomic.Value(bool).init(false);
    q.mutex = .{};
    q.not_empty_cv = .{};
    q.not_full_cv = .{};

    // Zero all slots
    for (&q.slots) |*slot| {
        slot.* = null;
    }

    MessageMetrics.inc(&g_msg_metrics.queues_created);
    return q;
}

/// Destroy a queue, freeing all unconsumed messages.
export fn msg_queue_destroy(q: ?*MessageQueue) callconv(.c) void {
    const queue = q orelse return;

    // Drain any remaining messages
    queue.mutex.lock();
    while (queue.count > 0) {
        const blob = queue.slots[queue.head];
        queue.slots[queue.head] = null;
        queue.head = (queue.head + 1) % MSG_QUEUE_CAPACITY;
        queue.count -= 1;
        queue.mutex.unlock();
        MessageMetrics.inc(&g_msg_metrics.messages_dropped);
        msg_blob_free(blob);
        queue.mutex.lock();
    }
    queue.mutex.unlock();

    MessageMetrics.inc(&g_msg_metrics.queues_destroyed);
    c.free(@ptrCast(queue));
}

/// Push a message blob onto the queue.
/// Blocks if the queue is full (back-pressure).
/// Returns 1 on success, 0 if the queue is closed.
export fn msg_queue_push(q: ?*MessageQueue, blob: ?*MessageBlob) callconv(.c) i32 {
    const queue = q orelse {
        // Queue is null — free the blob to avoid leak
        msg_blob_free(blob);
        return 0;
    };
    const b = blob orelse return 0;

    queue.mutex.lock();

    // Wait until there's space or queue is closed
    var waited = false;
    while (queue.count >= MSG_QUEUE_CAPACITY and !queue.closed) {
        if (!waited) {
            MessageMetrics.inc(&g_msg_metrics.push_waits);
            waited = true;
        }
        // Use a timed wait to periodically check closed status
        // This prevents indefinite blocking if the consumer exits
        queue.not_full_cv.timedWait(&queue.mutex, 100_000_000) catch {
            // Timeout — loop will re-check condition
        };
    }

    if (queue.closed) {
        queue.mutex.unlock();
        // Queue closed — free the blob, warn, and return failure
        msg_blob_free(blob);
        return 0;
    }

    // Enqueue
    queue.slots[queue.tail] = b;
    queue.tail = (queue.tail + 1) % MSG_QUEUE_CAPACITY;
    queue.count += 1;

    // Signal a waiting consumer
    queue.not_empty_cv.signal();
    queue.mutex.unlock();

    MessageMetrics.inc(&g_msg_metrics.messages_pushed);
    return 1;
}

/// Pop a message from the queue. Blocks if empty.
/// Returns null if the queue is closed and empty (no more messages).
export fn msg_queue_pop(q: ?*MessageQueue) callconv(.c) ?*MessageBlob {
    const queue = q orelse return null;

    queue.mutex.lock();

    // Wait until there's a message or queue is closed+empty
    var waited = false;
    while (queue.count == 0) {
        if (queue.closed) {
            queue.mutex.unlock();
            return null;
        }
        if (!waited) {
            MessageMetrics.inc(&g_msg_metrics.pop_waits);
            waited = true;
        }
        // Timed wait: check every 100ms so we can detect close/cancel
        queue.not_empty_cv.timedWait(&queue.mutex, 100_000_000) catch {
            // Timeout — loop will re-check
        };
    }

    // Dequeue
    const blob = queue.slots[queue.head];
    queue.slots[queue.head] = null;
    queue.head = (queue.head + 1) % MSG_QUEUE_CAPACITY;
    queue.count -= 1;

    // Signal a waiting producer
    queue.not_full_cv.signal();
    queue.mutex.unlock();

    MessageMetrics.inc(&g_msg_metrics.messages_popped);
    return blob;
}

/// Non-blocking check: returns 1 if at least one message is queued.
export fn msg_queue_has_message(q: ?*MessageQueue) callconv(.c) i32 {
    const queue = q orelse return 0;

    queue.mutex.lock();
    const has = queue.count > 0;
    queue.mutex.unlock();

    return if (has) 1 else 0;
}

/// Close the queue: no more pushes allowed.
/// Wakes up any blocked consumers so they can see the close.
export fn msg_queue_close(q: ?*MessageQueue) callconv(.c) void {
    const queue = q orelse return;

    queue.mutex.lock();
    queue.closed = true;
    // Wake everyone: consumers will see closed+empty, producers will see closed
    queue.not_empty_cv.broadcast();
    queue.not_full_cv.broadcast();
    queue.mutex.unlock();
}

// =========================================================================
// MessageBlob construction — scalars
// =========================================================================

/// Allocate a MessageBlob on the heap.
fn allocBlob(tag: u8, payload_len: u32) ?*MessageBlob {
    const raw = c.calloc(1, @sizeOf(MessageBlob)) orelse return null;
    const blob: *MessageBlob = @ptrCast(@alignCast(raw));
    blob.tag = tag;
    blob.flags = 0;
    blob.type_id = 0;
    blob.payload_len = payload_len;
    blob.payload = null;
    blob.inline_value = 0;
    g_msg_metrics.recordCreate(tag);
    return blob;
}

/// Marshall a double into a message blob.
/// The value is stored inline (no separate heap allocation).
export fn msg_marshall_double(value: f64) callconv(.c) ?*MessageBlob {
    const blob = allocBlob(MSG_DOUBLE, 8) orelse return null;
    // Store double bits in inline_value
    blob.inline_value = @bitCast(value);
    return blob;
}

/// Marshall an int32 into a message blob.
/// The value is stored inline.
export fn msg_marshall_int(value: i32) callconv(.c) ?*MessageBlob {
    const blob = allocBlob(MSG_INTEGER, 4) orelse return null;
    // Store int32 in inline_value (zero-extended to u64)
    const u: u32 = @bitCast(value);
    blob.inline_value = @as(u64, u);
    return blob;
}

/// Marshall a string (deep copy) into a message blob.
/// The payload is a cloned StringDescriptor pointer.
export fn msg_marshall_string(str_desc: ?*const StringDescriptor) callconv(.c) ?*MessageBlob {
    const blob = allocBlob(MSG_STRING, 8) orelse return null;
    // Deep-copy the string
    const cloned = string_clone(str_desc);
    // Store the cloned pointer in inline_value
    if (cloned) |ptr| {
        blob.inline_value = @intFromPtr(ptr);
        MessageMetrics.inc(&g_msg_metrics.strings_cloned);
    } else {
        blob.inline_value = 0;
    }
    return blob;
}

/// Marshall a UDT (flat — no string fields) into a message blob.
/// Uses the existing marshall_udt from marshalling.zig.
export fn msg_marshall_udt(
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) ?*MessageBlob {
    return msg_marshall_udt_typed(udt_ptr, size, string_offsets, num_offsets, 0);
}

/// Marshall a UDT with a specific type_id for MATCH RECEIVE dispatch.
export fn msg_marshall_udt_typed(
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
    type_id: i32,
) callconv(.c) ?*MessageBlob {
    if (size <= 0) return null;

    const blob = allocBlob(MSG_UDT, @intCast(@as(u32, @bitCast(size)))) orelse return null;
    blob.type_id = @intCast(type_id & 0x7FFF);

    // Use deep marshall if there are string fields, shallow otherwise
    const marshalled = if (num_offsets > 0)
        marshall_udt_deep(udt_ptr, size, string_offsets, num_offsets)
    else
        marshall_udt(udt_ptr, size);

    if (marshalled == null) {
        c.free(@ptrCast(blob));
        // Undo the blob_created count from allocBlob since we're
        // freeing the envelope without going through msg_blob_free
        _ = g_msg_metrics.blobs_created.fetchSub(1, .monotonic);
        _ = g_msg_metrics.count_udt.fetchSub(1, .monotonic);
        return null;
    }
    blob.payload = marshalled;
    MessageMetrics.inc(&g_msg_metrics.payloads_allocated);
    MessageMetrics.add(&g_msg_metrics.total_payload_bytes, @intCast(@as(u32, @bitCast(size))));
    return blob;
}

/// Marshall a CLASS instance with its class_id for MATCH RECEIVE dispatch.
/// The object is deep-copied (marshalled as a UDT with tag MSG_CLASS).
export fn msg_marshall_class(
    obj_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
    class_id: i32,
) callconv(.c) ?*MessageBlob {
    if (size <= 0) return null;

    const blob = allocBlob(MSG_CLASS, @intCast(@as(u32, @bitCast(size)))) orelse return null;
    blob.type_id = @intCast(class_id & 0x7FFF);

    // Deep-copy the object memory (same as UDT marshalling)
    const marshalled = if (num_offsets > 0)
        marshall_udt_deep(obj_ptr, size, string_offsets, num_offsets)
    else
        marshall_udt(obj_ptr, size);

    if (marshalled == null) {
        c.free(@ptrCast(blob));
        _ = g_msg_metrics.blobs_created.fetchSub(1, .monotonic);
        _ = g_msg_metrics.count_class.fetchSub(1, .monotonic);
        return null;
    }
    blob.payload = marshalled;
    MessageMetrics.inc(&g_msg_metrics.payloads_allocated);
    MessageMetrics.add(&g_msg_metrics.total_payload_bytes, @intCast(@as(u32, @bitCast(size))));
    return blob;
}

/// Marshall an array into a message blob.
/// Uses the existing marshall_array from marshalling.zig.
export fn msg_marshall_array(array_desc: ?*const anyopaque) callconv(.c) ?*MessageBlob {
    const marshalled = marshall_array(array_desc) orelse return null;

    // We don't know the exact size, but the blob is self-contained
    const blob = allocBlob(MSG_ARRAY, 0) orelse {
        c.free(marshalled);
        return null;
    };
    blob.payload = marshalled;
    MessageMetrics.inc(&g_msg_metrics.payloads_allocated);
    return blob;
}

/// Marshall a pre-marshalled opaque blob (wrap it in a message envelope).
export fn msg_marshall_blob(blob_ptr: ?*anyopaque, size: i32) callconv(.c) ?*MessageBlob {
    const ptr = blob_ptr orelse return null;
    if (size <= 0) return null;

    const blob = allocBlob(MSG_MARSHALLED, @intCast(@as(u32, @bitCast(size)))) orelse return null;
    blob.payload = ptr;
    MessageMetrics.inc(&g_msg_metrics.payloads_allocated);
    MessageMetrics.add(&g_msg_metrics.total_payload_bytes, @intCast(@as(u32, @bitCast(size))));
    return blob;
}

/// Convenience send: UDT with type_id (marshall + push in one call).
export fn msg_send_udt_typed(
    q: ?*MessageQueue,
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
    type_id: i32,
) callconv(.c) i32 {
    const blob = msg_marshall_udt_typed(udt_ptr, size, string_offsets, num_offsets, type_id) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Convenience send: CLASS with class_id (marshall + push in one call).
export fn msg_send_class(
    q: ?*MessageQueue,
    obj_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
    class_id: i32,
) callconv(.c) i32 {
    const blob = msg_marshall_class(obj_ptr, size, string_offsets, num_offsets, class_id) orelse return 0;
    return msg_queue_push(q, blob);
}

// =========================================================================
// MessageBlob accessors — for MATCH RECEIVE tag dispatch
// =========================================================================

/// Read the tag from a message blob (non-destructive).
/// Returns -1 if the blob pointer is null.
export fn msg_blob_tag(blob: ?*MessageBlob) callconv(.c) i32 {
    const b = blob orelse return -1;
    return @as(i32, b.tag);
}

/// Read the type_id from a message blob (non-destructive).
/// Returns 0 if the blob pointer is null or untyped.
export fn msg_blob_type_id(blob: ?*MessageBlob) callconv(.c) i32 {
    const b = blob orelse return 0;
    return @as(i32, b.type_id);
}

/// Create a zero-length signal message.
export fn msg_marshall_signal(signal_code: i32) callconv(.c) ?*MessageBlob {
    const blob = allocBlob(MSG_SIGNAL, 0) orelse return null;
    const u: u32 = @bitCast(signal_code);
    blob.inline_value = @as(u64, u);
    return blob;
}

// =========================================================================
// MessageBlob extraction
// =========================================================================

/// Unmarshall a double from a message blob.
/// Frees the blob after extraction.
export fn msg_unmarshall_double(blob: ?*MessageBlob) callconv(.c) f64 {
    const b = blob orelse return 0.0;

    if (b.tag != MSG_DOUBLE) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_DOUBLE (tag 0) but got tag %d\n", @as(c_int, b.tag));
        msg_blob_free(blob);
        return 0.0;
    }

    const value: f64 = @bitCast(b.inline_value);
    // Inline-only blob — no payload to free, just the envelope.
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
    return value;
}

/// Unmarshall an int32 from a message blob.
/// Frees the blob after extraction.
export fn msg_unmarshall_int(blob: ?*MessageBlob) callconv(.c) i32 {
    const b = blob orelse return 0;

    if (b.tag != MSG_INTEGER) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_INTEGER (tag 1) but got tag %d\n", @as(c_int, b.tag));
        msg_blob_free(blob);
        return 0;
    }

    const truncated: u32 = @truncate(b.inline_value);
    const value: i32 = @bitCast(truncated);
    // Inline-only blob — no payload to free, just the envelope.
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
    return value;
}

/// Unmarshall a string from a message blob.
/// Returns the StringDescriptor pointer (caller owns it).
/// Frees the blob after extraction.
export fn msg_unmarshall_string(blob: ?*MessageBlob) callconv(.c) ?*StringDescriptor {
    const b = blob orelse return null;

    if (b.tag != MSG_STRING) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_STRING (tag 2) but got tag %d\n", @as(c_int, b.tag));
        msg_blob_free(blob);
        return null;
    }

    // The string pointer is stored in inline_value
    const ptr_val = b.inline_value;
    const result: ?*StringDescriptor = if (ptr_val != 0)
        @ptrFromInt(ptr_val)
    else
        null;

    // Don't free the string — caller now owns it.
    // Only free the blob envelope.
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
    return result;
}

/// Unmarshall a UDT from a message blob into target memory.
/// Frees the blob after extraction.
export fn msg_unmarshall_udt(
    blob: ?*MessageBlob,
    target: ?*anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) void {
    const b = blob orelse return;

    if (b.tag != MSG_UDT and b.tag != MSG_CLASS) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_UDT (tag 3) but got tag %d\n", @as(c_int, b.tag));
        msg_blob_free(blob);
        return;
    }

    const payload = b.payload;

    // Use the existing unmarshall functions.
    // These free the payload blob, so we only need to free our envelope.
    if (num_offsets > 0) {
        unmarshall_udt_deep(payload, target, size, string_offsets, num_offsets);
    } else {
        unmarshall_udt(payload, target, size);
    }

    // The unmarshall functions freed the payload. Clear our pointer and free envelope.
    // (unmarshall_udt / unmarshall_udt_deep call c.free on their blob argument)
    MessageMetrics.inc(&g_msg_metrics.payloads_freed);
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
}

/// Unmarshall an array from a message blob into a descriptor.
/// Frees the blob after extraction.
export fn msg_unmarshall_array(blob: ?*MessageBlob, array_desc: ?*anyopaque) callconv(.c) void {
    const b = blob orelse return;

    if (b.tag != MSG_ARRAY) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_ARRAY (tag 4) but got tag %d\n", @as(c_int, b.tag));
        msg_blob_free(blob);
        return;
    }

    const payload = b.payload;

    // unmarshall_array frees the payload
    unmarshall_array(payload, array_desc);

    // Free envelope
    MessageMetrics.inc(&g_msg_metrics.payloads_freed);
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
}

/// Free a message blob and its payload.
export fn msg_blob_free(blob: ?*MessageBlob) callconv(.c) void {
    const b = blob orelse return;

    // Free payload if it was heap-allocated (not inline)
    switch (b.tag) {
        MSG_DOUBLE, MSG_INTEGER, MSG_SIGNAL => {
            // Inline storage — no payload to free
        },
        MSG_STRING => {
            // String pointer is in inline_value — it's a slab-pool allocation
            // from samm_alloc_string (via string_clone), NOT a malloc.
            // Must use string_release which knows about the slab pool.
            if (b.inline_value != 0) {
                const str_ptr: *StringDescriptor = @ptrFromInt(b.inline_value);
                string_release(str_ptr);
            }
            // A string is always cloned at creation time for MSG_STRING
            // blobs.  If inline_value is 0 here, the string was already
            // extracted by the MATCH RECEIVE trampoline (ownership
            // transferred to a local binding variable; SAMM will free it
            // when the scope exits).  Either way the string has left
            // messaging ownership, so count it as released.
            MessageMetrics.inc(&g_msg_metrics.strings_released);
        },
        MSG_UDT, MSG_CLASS, MSG_ARRAY, MSG_MARSHALLED => {
            // Heap-allocated payload.  A payload is always allocated for
            // these tags at creation time.  If payload is null here, it
            // was already freed externally (e.g. by unmarshall_udt in
            // the MATCH RECEIVE trampoline which nulls the pointer to
            // prevent double-free).  Either way, count it as freed.
            if (b.payload) |p| {
                c.free(p);
            }
            MessageMetrics.inc(&g_msg_metrics.payloads_freed);
        },
        else => {
            // Unknown tag — try to free payload if present
            if (b.payload) |p| {
                c.free(p);
                MessageMetrics.inc(&g_msg_metrics.payloads_freed);
            }
        },
    }

    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(b));
}

// =========================================================================
// Zero-copy forwarding — ping-pong ownership transfer
// =========================================================================
//
// These primitives support the common pattern where two loops (main +
// worker) exchange the same typed data back and forth, modifying it
// each round without destroying and recreating the blob.
//
// Normal flow (4 copies per round-trip):
//   SEND:    malloc envelope → malloc payload → memcpy → push
//   RECEIVE: pop → memcpy out → free payload → free envelope
//
// Zero-copy flow (0 copies per bounce):
//   Initial SEND:  marshal once (1 copy)
//   Each bounce:   pop → modify payload in-place → push same blob (0 copies)
//   Final RECEIVE: unmarshal once (1 copy)
//
// The blob's payload buffer is malloc'd and independent of any thread's
// stack or SAMM scope.  String fields inside UDT payloads were cloned
// during the initial marshal (string_clone), so they're heap-resident
// and safe to read/modify across thread boundaries — as long as strict
// alternation is maintained (only one thread touches the payload at a
// time, which the queue handoff guarantees).

/// Return a mutable pointer to the blob's heap payload (UDT/CLASS/ARRAY).
/// The blob retains ownership — caller must not free the pointer.
/// Returns null for inline-only types (DOUBLE, INTEGER, SIGNAL) or if
/// the payload is null.
export fn msg_blob_payload_ptr(blob: ?*MessageBlob) callconv(.c) ?*anyopaque {
    const b = blob orelse return null;
    return b.payload;
}

/// Return a pointer to the blob's inline_value field for in-place
/// modification of scalars or direct access to the string pointer.
/// Useful for DOUBLE/INTEGER ping-pong without marshal/unmarshal.
export fn msg_blob_inline_ptr(blob: ?*MessageBlob) callconv(.c) ?*u64 {
    const b = blob orelse return null;
    return &b.inline_value;
}

/// Overwrite the blob's inline_value.  For DOUBLE ping-pong: cast the
/// new f64 to u64 bits and store.  For INTEGER: zero-extend i32 to u64.
export fn msg_blob_set_inline(blob: ?*MessageBlob, value: u64) callconv(.c) void {
    const b = blob orelse return;
    b.inline_value = value;
}

/// Forward (re-send) an existing blob to a queue WITHOUT copying or
/// freeing anything.  Ownership of the blob transfers to the queue.
/// The caller MUST NOT use the blob pointer after this call.
///
/// Returns 1 on success, 0 on failure (null args or closed queue).
/// On failure the blob is freed to prevent leaks (same as msg_queue_push).
export fn msg_blob_forward(blob: ?*MessageBlob, q: ?*MessageQueue) callconv(.c) i32 {
    MessageMetrics.inc(&g_msg_metrics.blobs_forwarded);
    return msg_queue_push(q, blob);
}

/// Pop a blob, copy its payload into `target`, then forward the same
/// blob to `dest_q` — single-copy bounce.  The receiver gets a local
/// copy to read while the blob continues its journey to the other side.
/// For UDT/CLASS with string fields, use the deep variant.
export fn msg_bounce_udt(
    src_q: ?*MessageQueue,
    dest_q: ?*MessageQueue,
    target: ?*anyopaque,
    size: i32,
) callconv(.c) i32 {
    const blob = msg_queue_pop(src_q) orelse return 0;
    const b = blob;

    if (b.tag != MSG_UDT and b.tag != MSG_CLASS) {
        msg_blob_free(blob);
        return 0;
    }

    // Copy payload into caller's target (read-only snapshot)
    if (target != null and b.payload != null and size > 0) {
        const sz: usize = @intCast(@as(u32, @bitCast(size)));
        const dst: [*]u8 = @ptrCast(target.?);
        const src: [*]const u8 = @ptrCast(b.payload.?);
        @memcpy(dst[0..sz], src[0..sz]);
    }

    // Forward the original blob — zero copy for the payload
    return msg_blob_forward(blob, dest_q);
}

// =========================================================================
// Cancellation — uses an atomic flag, not the message queue
// =========================================================================

/// Send a cancellation signal to a worker via its outbox queue's atomic flag.
/// This is a side-channel: it doesn't go through the message queue.
export fn msg_cancel(outbox: ?*MessageQueue) callconv(.c) void {
    const queue = outbox orelse return;
    queue.cancel_flag.store(true, .release);

    // Also push a signal message so RECEIVE unblocks
    const sig = msg_marshall_signal(SIGNAL_CANCEL);
    if (sig) |s| {
        _ = msg_queue_push(queue, s);
    }
}

/// Check if cancellation was requested (non-blocking, reads atomic flag).
/// Intended to be called from inside a worker with its outbox (main→worker) queue.
export fn msg_is_cancelled(outbox: ?*MessageQueue) callconv(.c) i32 {
    const queue = outbox orelse return 0;
    return if (queue.cancel_flag.load(.acquire)) 1 else 0;
}

// =========================================================================
// Convenience: send/receive doubles directly (most common case)
//
// These combine marshall + push or pop + unmarshall into single calls
// for the codegen to use. They reduce the number of emitted QBE
// instructions for the common scalar messaging pattern.
// =========================================================================

/// Send a double value to a queue (marshall + push in one call).
export fn msg_send_double(q: ?*MessageQueue, value: f64) callconv(.c) i32 {
    const blob = msg_marshall_double(value) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Send an int32 value to a queue (marshall + push in one call).
export fn msg_send_int(q: ?*MessageQueue, value: i32) callconv(.c) i32 {
    const blob = msg_marshall_int(value) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Send a string to a queue (deep-copy + push in one call).
export fn msg_send_string(q: ?*MessageQueue, str_desc: ?*const StringDescriptor) callconv(.c) i32 {
    const blob = msg_marshall_string(str_desc) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Send a UDT to a queue (marshall + push in one call).
export fn msg_send_udt(
    q: ?*MessageQueue,
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) i32 {
    const blob = msg_marshall_udt(udt_ptr, size, string_offsets, num_offsets) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Send a pre-marshalled blob to a queue (wrap + push in one call).
export fn msg_send_marshalled(q: ?*MessageQueue, blob_ptr: ?*anyopaque, size: i32) callconv(.c) i32 {
    const blob = msg_marshall_blob(blob_ptr, size) orelse return 0;
    return msg_queue_push(q, blob);
}

/// Receive a double from a queue (pop + unmarshall in one call).
/// Blocks until a message is available.
export fn msg_receive_double(q: ?*MessageQueue) callconv(.c) f64 {
    const blob = msg_queue_pop(q) orelse return 0.0;
    return msg_unmarshall_double(blob);
}

/// Receive an int32 from a queue (pop + unmarshall in one call).
/// Blocks until a message is available.
export fn msg_receive_int(q: ?*MessageQueue) callconv(.c) i32 {
    const blob = msg_queue_pop(q) orelse return 0;
    return msg_unmarshall_int(blob);
}

/// Receive a string from a queue (pop + unmarshall in one call).
/// Blocks until a message is available.
export fn msg_receive_string(q: ?*MessageQueue) callconv(.c) ?*StringDescriptor {
    const blob = msg_queue_pop(q) orelse return null;
    return msg_unmarshall_string(blob);
}

/// Receive a UDT from a queue (pop + unmarshall in one call).
/// Blocks until a message is available.
export fn msg_receive_udt(
    q: ?*MessageQueue,
    target: ?*anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) void {
    const blob = msg_queue_pop(q) orelse return;
    msg_unmarshall_udt(blob, target, size, string_offsets, num_offsets);
}

/// Receive a marshalled blob from a queue (pop + extract in one call).
/// Returns the raw payload pointer; caller owns it.
/// Blocks until a message is available.
export fn msg_receive_marshalled(q: ?*MessageQueue) callconv(.c) ?*anyopaque {
    const raw_blob = msg_queue_pop(q) orelse return null;
    // For marshalled blobs, extract the payload and free only the envelope
    if (raw_blob.tag != MSG_MARSHALLED) {
        _ = c.fprintf(c.getStderr(), "Runtime error: RECEIVE expected MSG_MARSHALLED (tag 6) but got tag %d\n", @as(c_int, raw_blob.tag));
        msg_blob_free(raw_blob);
        return null;
    }
    const payload = raw_blob.payload;
    // Don't free the payload — caller owns it. Only free envelope.
    MessageMetrics.inc(&g_msg_metrics.blobs_freed);
    c.free(@ptrCast(raw_blob));
    return payload;
}

// =========================================================================
// FutureHandle messaging extensions
//
// The FutureHandle struct is defined in worker_runtime.c. We operate on
// it via known byte offsets rather than importing the struct, to avoid
// circular dependencies between C and Zig.
//
// FutureHandle layout (from worker_runtime.c):
//   ... existing fields ...
//   outbox: *MessageQueue  (at offset FUTURE_OUTBOX_OFFSET)
//   inbox:  *MessageQueue  (at offset FUTURE_INBOX_OFFSET)
//
// These offsets are defined in worker_runtime.c and exported as
// extern constants. For now we provide helper functions that take
// the queue pointers directly — the codegen extracts the right
// queue from the handle.
// =========================================================================

/// Get the outbox queue (main→worker) from a raw handle pointer.
/// The handle + offset approach is used by codegen.
/// outbox_offset is the byte offset of the outbox field in FutureHandle.
export fn msg_get_outbox(handle: ?*anyopaque, outbox_offset: i32) callconv(.c) ?*MessageQueue {
    const h = handle orelse return null;
    if (outbox_offset < 0) return null;
    const base: [*]u8 = @ptrCast(h);
    const off: usize = @intCast(outbox_offset);
    const slot: *?*MessageQueue = @ptrCast(@alignCast(base + off));
    return slot.*;
}

/// Get the inbox queue (worker→main) from a raw handle pointer.
export fn msg_get_inbox(handle: ?*anyopaque, inbox_offset: i32) callconv(.c) ?*MessageQueue {
    const h = handle orelse return null;
    if (inbox_offset < 0) return null;
    const base: [*]u8 = @ptrCast(h);
    const off: usize = @intCast(inbox_offset);
    const slot: *?*MessageQueue = @ptrCast(@alignCast(base + off));
    return slot.*;
}

// =========================================================================
// Drain helper — used by worker_await to clean up
// =========================================================================

/// Drain and destroy both message queues. Called during AWAIT cleanup.
export fn msg_drain_and_destroy(outbox: ?*MessageQueue, inbox: ?*MessageQueue) callconv(.c) void {
    // Close both queues first so any blocked threads unblock
    msg_queue_close(outbox);
    msg_queue_close(inbox);

    // Small delay to let blocked threads wake up
    var ts = Timespec{ .tv_sec = 0, .tv_nsec = 1_000_000 }; // 1ms
    _ = c.nanosleep(&ts, null);

    // Destroy (which drains remaining messages)
    msg_queue_destroy(outbox);
    msg_queue_destroy(inbox);
}

// =========================================================================
// Message Metrics — Report & Leak Detection
// =========================================================================

/// Print a formatted report of all message memory metrics.
/// Callable from C: msg_metrics_report()
export fn msg_metrics_report() callconv(.c) void {
    const m = &g_msg_metrics;
    const stdio = @cImport(@cInclude("stdio.h"));

    const created = MessageMetrics.get(&m.blobs_created);
    const freed = MessageMetrics.get(&m.blobs_freed);
    const forwarded = MessageMetrics.get(&m.blobs_forwarded);
    const p_alloc = MessageMetrics.get(&m.payloads_allocated);
    const p_freed = MessageMetrics.get(&m.payloads_freed);
    const p_bytes = MessageMetrics.get(&m.total_payload_bytes);
    const s_cloned = MessageMetrics.get(&m.strings_cloned);
    const s_released = MessageMetrics.get(&m.strings_released);
    const pushed = MessageMetrics.get(&m.messages_pushed);
    const popped = MessageMetrics.get(&m.messages_popped);
    const dropped = MessageMetrics.get(&m.messages_dropped);
    const push_w = MessageMetrics.get(&m.push_waits);
    const pop_w = MessageMetrics.get(&m.pop_waits);
    const peak = MessageMetrics.get(&m.peak_outstanding);
    const q_created = MessageMetrics.get(&m.queues_created);
    const q_destroyed = MessageMetrics.get(&m.queues_destroyed);

    const blob_leak = if (created > freed) created - freed else 0;
    const payload_leak = if (p_alloc > p_freed) p_alloc - p_freed else 0;
    const string_leak = if (s_cloned > s_released) s_cloned - s_released else 0;
    const queue_leak = if (q_created > q_destroyed) q_created - q_destroyed else 0;

    _ = stdio.printf("\n");
    _ = stdio.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    _ = stdio.printf("  Message Memory Metrics\n");
    _ = stdio.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");

    _ = stdio.printf("  Blob envelopes:\n");
    _ = stdio.printf("    Created:           %llu\n", created);
    _ = stdio.printf("    Freed:             %llu\n", freed);
    _ = stdio.printf("    Forwarded (0-cp):  %llu\n", forwarded);
    _ = stdio.printf("    Peak outstanding:  %llu\n", peak);
    if (blob_leak > 0) {
        _ = stdio.printf("    ⚠️  LEAKED:         %llu\n", blob_leak);
    } else {
        _ = stdio.printf("    ✓ No blob leaks\n");
    }

    _ = stdio.printf("  Payloads:\n");
    _ = stdio.printf("    Allocated:         %llu\n", p_alloc);
    _ = stdio.printf("    Freed:             %llu\n", p_freed);
    _ = stdio.printf("    Total bytes:       %llu\n", p_bytes);
    if (payload_leak > 0) {
        _ = stdio.printf("    ⚠️  LEAKED:         %llu\n", payload_leak);
    } else {
        _ = stdio.printf("    ✓ No payload leaks\n");
    }

    _ = stdio.printf("  Message strings:\n");
    _ = stdio.printf("    Cloned:            %llu\n", s_cloned);
    _ = stdio.printf("    Released:          %llu\n", s_released);
    if (string_leak > 0) {
        _ = stdio.printf("    ⚠️  LEAKED:         %llu\n", string_leak);
    } else {
        _ = stdio.printf("    ✓ No string leaks\n");
    }

    _ = stdio.printf("  By type:\n");
    _ = stdio.printf("    DOUBLE:    %llu\n", MessageMetrics.get(&m.count_double));
    _ = stdio.printf("    INTEGER:   %llu\n", MessageMetrics.get(&m.count_integer));
    _ = stdio.printf("    STRING:    %llu\n", MessageMetrics.get(&m.count_string));
    _ = stdio.printf("    UDT:       %llu\n", MessageMetrics.get(&m.count_udt));
    _ = stdio.printf("    CLASS:     %llu\n", MessageMetrics.get(&m.count_class));
    _ = stdio.printf("    ARRAY:     %llu\n", MessageMetrics.get(&m.count_array));
    _ = stdio.printf("    SIGNAL:    %llu\n", MessageMetrics.get(&m.count_signal));
    _ = stdio.printf("    MARSHALLED:%llu\n", MessageMetrics.get(&m.count_marshalled));

    _ = stdio.printf("  Queue traffic:\n");
    _ = stdio.printf("    Pushed:            %llu\n", pushed);
    _ = stdio.printf("    Popped:            %llu\n", popped);
    _ = stdio.printf("    Dropped (drained): %llu\n", dropped);
    _ = stdio.printf("    Push back-pressure waits: %llu\n", push_w);
    _ = stdio.printf("    Pop empty waits:          %llu\n", pop_w);

    _ = stdio.printf("  Queues:\n");
    _ = stdio.printf("    Created:           %llu\n", q_created);
    _ = stdio.printf("    Destroyed:         %llu\n", q_destroyed);
    if (queue_leak > 0) {
        _ = stdio.printf("    ⚠️  LEAKED:         %llu\n", queue_leak);
    } else {
        _ = stdio.printf("    ✓ No queue leaks\n");
    }

    _ = stdio.printf("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
}

/// Check for message memory leaks.  Returns 0 if clean, 1 if leaks detected.
/// Prints a summary to stderr when leaks are found.
/// Callable from C: msg_metrics_check_leaks()
export fn msg_metrics_check_leaks() callconv(.c) i32 {
    const m = &g_msg_metrics;

    const created = MessageMetrics.get(&m.blobs_created);
    const freed = MessageMetrics.get(&m.blobs_freed);
    const p_alloc = MessageMetrics.get(&m.payloads_allocated);
    const p_freed = MessageMetrics.get(&m.payloads_freed);
    const s_cloned = MessageMetrics.get(&m.strings_cloned);
    const s_released = MessageMetrics.get(&m.strings_released);
    const q_created = MessageMetrics.get(&m.queues_created);
    const q_destroyed = MessageMetrics.get(&m.queues_destroyed);

    const blob_leak = created > freed;
    const payload_leak = p_alloc > p_freed;
    const string_leak = s_cloned > s_released;
    const queue_leak = q_created > q_destroyed;

    if (!blob_leak and !payload_leak and !string_leak and !queue_leak) {
        return 0; // Clean
    }

    // Print leak details to stderr
    _ = c.fprintf(c.getStderr(), "⚠️  Message memory leaks detected:\n");
    if (blob_leak) {
        _ = c.fprintf(c.getStderr(), "    Blob envelopes: %llu created, %llu freed, %llu leaked\n", created, freed, created - freed);
    }
    if (payload_leak) {
        _ = c.fprintf(c.getStderr(), "    Payloads: %llu allocated, %llu freed, %llu leaked\n", p_alloc, p_freed, p_alloc - p_freed);
    }
    if (string_leak) {
        _ = c.fprintf(c.getStderr(), "    Msg strings: %llu cloned, %llu released, %llu leaked\n", s_cloned, s_released, s_cloned - s_released);
    }
    if (queue_leak) {
        _ = c.fprintf(c.getStderr(), "    Queues: %llu created, %llu destroyed, %llu leaked\n", q_created, q_destroyed, q_created - q_destroyed);
    }

    return 1; // Leaks found
}

/// Reset all metrics to zero.  Useful for test isolation.
/// Callable from C: msg_metrics_reset()
export fn msg_metrics_reset() callconv(.c) void {
    g_msg_metrics = .{};
}
