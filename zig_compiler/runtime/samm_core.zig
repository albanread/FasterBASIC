//! samm_core.zig
//! FasterBASIC Runtime — SAMM (Scope Aware Memory Management) Core
//!
//! Phase 3 Zig rewrite of samm_core.c.
//! Provides scope-aware memory management with:
//!   1. Scope stack (delegated to samm_scope.zig)
//!   2. Bloom filter — lazily allocated double-free detector
//!   3. Cleanup queue — bounded ring buffer of pointer batches
//!   4. Background worker thread that drains the cleanup queue
//!   5. Atomic metrics/diagnostics
//!
//! All public functions are `export fn ... callconv(.c)` to maintain
//! the C ABI declared in samm_bridge.h.
//!
//! Thread safety:
//!   - scope_mutex protects scope stack + Bloom filter writes
//!   - queue_mutex + queue_cv protect the cleanup ring buffer
//!   - Stats use std.atomic.Value for lock-free access

const std = @import("std");
const c_allocator = std.heap.c_allocator;

// =========================================================================
// Constants — must match samm_bridge.h and samm_pool.h
// =========================================================================

const SAMM_MAX_SCOPE_DEPTH: c_int = 256;
const SAMM_MAX_QUEUE_DEPTH: usize = 1024;

// Bloom filter
const SAMM_BLOOM_BITS: usize = 524288;
const SAMM_BLOOM_BYTES: usize = (SAMM_BLOOM_BITS + 7) / 8;
const SAMM_BLOOM_HASH_COUNT: usize = 7;

// FNV-1a 64-bit
const SAMM_FNV_PRIME: u64 = 0x00000100000001b3;
const SAMM_FNV_OFFSET_BASIS: u64 = 0xcbf29ce484222325;

// Object size classes
const SAMM_OBJECT_SIZE_CLASSES: usize = 6;
const SAMM_SIZE_CLASS_NONE: u8 = 0xFF;

// SAMMAllocType — matches the C enum in samm_bridge.h
const SAMM_ALLOC_UNKNOWN: u8 = 0;
const SAMM_ALLOC_OBJECT: u8 = 1;
const SAMM_ALLOC_STRING: u8 = 2;
const SAMM_ALLOC_ARRAY: u8 = 3;
const SAMM_ALLOC_LIST: u8 = 4;
const SAMM_ALLOC_LIST_ATOM: u8 = 5;
const SAMM_ALLOC_GENERIC: u8 = 6;

// Struct sizes (for byte accounting)
const SIZEOF_LIST_HEADER: u64 = 32;
const SIZEOF_LIST_ATOM: u64 = 24;
const SIZEOF_STRING_DESCRIPTOR: u64 = 40;

// Object slot sizes (must match samm_pool.h samm_object_slot_sizes[])
const object_slot_sizes: [SAMM_OBJECT_SIZE_CLASSES]u32 = .{ 32, 64, 128, 256, 512, 1024 };

// =========================================================================
// Extern C functions — defined in other runtime .c files
// =========================================================================

// string_descriptor.h → string_utf32.c
const StringDescriptor = opaque {};
extern fn string_release(str: *StringDescriptor) void;

// string_pool.h — string_desc_alloc is a static inline in C that calls
// samm_slab_pool_alloc(g_string_desc_pool) then sets defaults.
// We replicate that logic directly using the pool extern.

// list_ops.h → list_ops.c
extern fn list_free_from_samm(header_ptr: *anyopaque) void;
extern fn list_atom_free_from_samm(atom_ptr: *anyopaque) void;

// samm_pool.zig (exported with C linkage)
const SammSlabPool = opaque {};
extern fn samm_slab_pool_init(pool: *SammSlabPool, slot_size: u32, slots_per_slab: u32, name: [*:0]const u8) void;
extern fn samm_slab_pool_destroy(pool: *SammSlabPool) void;
extern fn samm_slab_pool_alloc(pool: *SammSlabPool) ?*anyopaque;
extern fn samm_slab_pool_free(pool: *SammSlabPool, ptr: *anyopaque) void;
extern fn samm_slab_pool_print_stats(pool: *const SammSlabPool) void;
extern fn samm_slab_pool_total_allocs(pool: *const SammSlabPool) usize;

// samm_scope.zig (exported with C linkage)
extern fn samm_scope_ensure_init() void;
extern fn samm_scope_reset(depth: c_int) void;
extern fn samm_scope_add(depth: c_int, ptr: *anyopaque, type_id: u8, sc: u8) void;
extern fn samm_scope_remove(depth: c_int, ptr: *anyopaque, out_type: ?*u8, out_sc: ?*u8) bool;
extern fn samm_scope_detach(depth: c_int, out_ptrs: *?[*]?*anyopaque, out_types: *?[*]u8, out_sc: *?[*]u8, out_count: *usize) bool;

// Global pool instances (defined in samm_pool.zig)
extern var g_string_desc_pool: *SammSlabPool;
extern var g_list_header_pool: *SammSlabPool;
extern var g_list_atom_pool: *SammSlabPool;
extern var g_object_pools: [SAMM_OBJECT_SIZE_CLASSES]*SammSlabPool;

// =========================================================================
// C library imports
// =========================================================================

const c = struct {
    extern fn getenv(name: [*:0]const u8) ?[*:0]const u8;
    extern fn nanosleep(req: *const Timespec, rem: ?*Timespec) c_int;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn calloc(nmemb: usize, size: usize) ?*anyopaque;
    extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
    extern fn abort() noreturn;
    // clock_gettime
    extern fn clock_gettime(clk_id: c_int, tp: *Timespec) c_int;

    // stderr — on macOS the symbol is __stderrp, on Linux it's stderr.
    // Using the platform-appropriate extern name.
    extern const __stderrp: *anyopaque;
    fn getStderr() *anyopaque {
        return __stderrp;
    }

    const CLOCK_MONOTONIC = 6; // macOS: CLOCK_MONOTONIC = 6
};

const Timespec = extern struct {
    tv_sec: isize,
    tv_nsec: isize,
};

// =========================================================================
// SAMMStats — matches the C struct in samm_bridge.h
// =========================================================================

const SAMMStats = extern struct {
    scopes_entered: u64,
    scopes_exited: u64,
    objects_allocated: u64,
    objects_freed: u64,
    objects_cleaned: u64,
    cleanup_batches: u64,
    double_free_attempts: u64,
    bloom_false_positives: u64,
    retain_calls: u64,
    total_bytes_allocated: u64,
    total_bytes_freed: u64,
    strings_tracked: u64,
    strings_cleaned: u64,
    current_scope_depth: c_int,
    peak_scope_depth: c_int,
    bloom_memory_bytes: usize,
    total_cleanup_time_ms: f64,
    background_worker_active: c_int,
};

// =========================================================================
// Cleanup function type — matches samm_cleanup_fn in samm_bridge.h
// =========================================================================

const CleanupFn = ?*const fn (ptr: *anyopaque) callconv(.c) void;

// =========================================================================
// Cleanup Batch
// =========================================================================

const CleanupBatch = struct {
    ptrs: ?[*]?*anyopaque = null,
    types: ?[*]u8 = null,
    size_classes: ?[*]u8 = null,
    count: usize = 0,
};

// =========================================================================
// Bloom Filter — lazily allocated
// =========================================================================

const BloomFilter = struct {
    bits: ?[*]u8 = null,
    size_bits: usize = 0,
    size_bytes: usize = 0,
    items_added: usize = 0,

    fn init() BloomFilter {
        return .{};
    }

    fn ensureAllocated(self: *BloomFilter) void {
        if (self.bits != null) return;

        self.size_bits = SAMM_BLOOM_BITS;
        self.size_bytes = SAMM_BLOOM_BYTES;

        const ptr = c.calloc(1, self.size_bytes);
        if (ptr == null) {
            _ = c.fprintf(c.getStderr(), "SAMM WARNING: Bloom filter alloc failed (%zu bytes), " ++
                "double-free detection disabled for overflow objects\n", self.size_bytes);
            self.size_bits = 0;
            self.size_bytes = 0;
            return;
        }
        self.bits = @ptrCast(ptr);
        self.items_added = 0;
    }

    fn destroy(self: *BloomFilter) void {
        if (self.bits) |b| {
            c.free(@ptrCast(b));
        }
        self.bits = null;
        self.size_bits = 0;
        self.size_bytes = 0;
        self.items_added = 0;
    }

    fn generateHashes(self: *const BloomFilter, ptr: *const anyopaque) [SAMM_BLOOM_HASH_COUNT]u64 {
        const h1 = fnv1a(std.mem.asBytes(&ptr));
        const h2 = fnv1a(std.mem.asBytes(&h1));
        var hashes: [SAMM_BLOOM_HASH_COUNT]u64 = undefined;
        for (0..SAMM_BLOOM_HASH_COUNT) |i| {
            hashes[i] = (h1 +% @as(u64, @intCast(i)) *% h2) % self.size_bits;
        }
        return hashes;
    }

    fn add(self: *BloomFilter, ptr: *const anyopaque) void {
        self.ensureAllocated();
        const bits = self.bits orelse return;

        const hashes = self.generateHashes(ptr);
        for (hashes) |h| {
            const byte_idx = h / 8;
            const bit_off: u3 = @intCast(h % 8);
            bits[byte_idx] |= @as(u8, 1) << bit_off;
        }
        self.items_added += 1;
    }

    fn check(self: *const BloomFilter, ptr: *const anyopaque) bool {
        const bits = self.bits orelse return false;

        const hashes = self.generateHashes(ptr);
        for (hashes) |h| {
            const byte_idx = h / 8;
            const bit_off: u3 = @intCast(h % 8);
            if ((bits[byte_idx] & (@as(u8, 1) << bit_off)) == 0) {
                return false;
            }
        }
        return true;
    }
};

fn fnv1a(data: []const u8) u64 {
    var hash: u64 = SAMM_FNV_OFFSET_BASIS;
    for (data) |byte| {
        hash ^= byte;
        hash *%= SAMM_FNV_PRIME;
    }
    return hash;
}

// =========================================================================
// SAMM State — singleton
// =========================================================================

const SAMMState = struct {
    // Scope stack
    scope_depth: c_int = 0,
    peak_scope_depth: c_int = 0,
    scope_mutex: std.Thread.Mutex = .{},

    // Bloom filter (lazily allocated)
    bloom: BloomFilter = BloomFilter.init(),

    // Cleanup queue (bounded ring buffer)
    queue: [SAMM_MAX_QUEUE_DEPTH]CleanupBatch = [_]CleanupBatch{.{}} ** SAMM_MAX_QUEUE_DEPTH,
    queue_head: usize = 0,
    queue_tail: usize = 0,
    queue_count: usize = 0,
    queue_mutex: std.Thread.Mutex = .{},
    queue_cv: std.Thread.Condition = .{},

    // Background worker
    worker_thread: ?std.Thread = null,
    worker_running: bool = false,
    shutdown_flag: bool = false,

    // Custom cleanup functions (indexed by alloc type)
    cleanup_fns: [8]CleanupFn = [_]CleanupFn{null} ** 8,

    // Configuration
    enabled: bool = false,
    trace: bool = false,
    initialised: bool = false,

    // Metrics (atomics)
    stat_scopes_entered: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_scopes_exited: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_objects_allocated: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_objects_freed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_objects_cleaned: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_cleanup_batches: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_double_free_attempts: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_retain_calls: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_total_bytes_allocated: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_total_bytes_freed: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_strings_tracked: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_strings_cleaned: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    stat_total_cleanup_time_ms: f64 = 0.0, // protected by queue_mutex
};

var g_samm: SAMMState = .{};

// =========================================================================
// Thread-local: last object size class (communication between alloc/track)
// =========================================================================

threadlocal var g_last_object_size_class: u8 = SAMM_SIZE_CLASS_NONE;

// =========================================================================
// Internal: size-to-class mapping (matches samm_pool.h samm_size_to_class)
// =========================================================================

fn sizeToClass(size: usize) i32 {
    if (size <= 32) return 0;
    if (size <= 64) return 1;
    if (size <= 128) return 2;
    if (size <= 256) return 3;
    if (size <= 512) return 4;
    if (size <= 1024) return 5;
    return -1; // overflow → malloc
}

// =========================================================================
// Internal: default cleanup for CLASS objects via vtable destructor
// =========================================================================

fn defaultObjectCleanup(ptr: *anyopaque) void {
    // Load vtable pointer from obj[0]
    const obj: [*]*anyopaque = @ptrCast(@alignCast(ptr));
    const vtable_ptr = obj[0];

    if (@intFromPtr(vtable_ptr) != 0) {
        const vtable: [*]*anyopaque = @ptrCast(@alignCast(vtable_ptr));
        const dtor_ptr = vtable[3];
        if (@intFromPtr(dtor_ptr) != 0) {
            const dtor: *const fn (*anyopaque) callconv(.c) void = @ptrCast(@alignCast(dtor_ptr));
            dtor(ptr);
        }
    }
    // Phase 3: do NOT free here — caller returns to pool or frees
}

// =========================================================================
// Internal: clean up a batch of pointers immediately
// =========================================================================

fn cleanupBatch(batch: *CleanupBatch) void {
    const ptrs = batch.ptrs orelse return;
    const types = batch.types orelse return;

    var i: usize = 0;
    while (i < batch.count) : (i += 1) {
        const ptr_opt = ptrs[i];
        const ptr = ptr_opt orelse continue;

        const alloc_type = types[i];
        const sc: u8 = if (batch.size_classes) |scs| scs[i] else SAMM_SIZE_CLASS_NONE;

        // Use registered cleanup function if available
        var custom_fn: CleanupFn = null;
        if (alloc_type < 8) {
            custom_fn = g_samm.cleanup_fns[alloc_type];
        }

        if (custom_fn) |cfn| {
            cfn(ptr);
        } else {
            // Fallback: type-specific default cleanup
            switch (alloc_type) {
                SAMM_ALLOC_OBJECT => {
                    // Run destructor via vtable (does NOT free)
                    defaultObjectCleanup(ptr);

                    // Return object shell to size-class pool or free
                    if (sc < SAMM_OBJECT_SIZE_CLASSES) {
                        const slot_sz: u64 = object_slot_sizes[sc];
                        _ = g_samm.stat_total_bytes_freed.fetchAdd(slot_sz, .monotonic);
                        samm_slab_pool_free(g_object_pools[sc], ptr);
                    } else {
                        // Overflow object (> 1024 B) — return to system
                        c.free(ptr);
                    }
                },
                SAMM_ALLOC_LIST => {
                    list_free_from_samm(ptr);
                    _ = g_samm.stat_total_bytes_freed.fetchAdd(SIZEOF_LIST_HEADER, .monotonic);
                },
                SAMM_ALLOC_LIST_ATOM => {
                    list_atom_free_from_samm(ptr);
                    _ = g_samm.stat_total_bytes_freed.fetchAdd(SIZEOF_LIST_ATOM, .monotonic);
                },
                SAMM_ALLOC_STRING => {
                    // string_release decrements refcount and frees when it reaches 0
                    string_release(@ptrCast(ptr));
                    _ = g_samm.stat_strings_cleaned.fetchAdd(1, .monotonic);
                },
                else => {
                    // Generic cleanup: just free
                    c.free(ptr);
                },
            }
        }

        // Mark as freed in Bloom filter — only for overflow-class objects
        if (alloc_type == SAMM_ALLOC_OBJECT and sc >= SAMM_OBJECT_SIZE_CLASSES) {
            g_samm.scope_mutex.lock();
            g_samm.bloom.add(ptr);
            g_samm.scope_mutex.unlock();
        }

        _ = g_samm.stat_objects_cleaned.fetchAdd(1, .monotonic);
    }

    // Free the batch arrays (allocated by c_allocator in samm_scope_detach)
    c.free(@ptrCast(ptrs));
    c.free(@ptrCast(types));
    if (batch.size_classes) |scs| {
        c.free(@ptrCast(scs));
    }
    batch.ptrs = null;
    batch.types = null;
    batch.size_classes = null;
    batch.count = 0;
}

// =========================================================================
// Background cleanup worker thread
// =========================================================================

fn workerFn() void {
    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Background cleanup worker started\n");
    }

    while (true) {
        var batch = CleanupBatch{};

        // Wait for work
        g_samm.queue_mutex.lock();
        while (g_samm.queue_count == 0 and !g_samm.shutdown_flag) {
            g_samm.queue_cv.wait(&g_samm.queue_mutex);
        }

        if (g_samm.queue_count == 0 and g_samm.shutdown_flag) {
            g_samm.queue_mutex.unlock();
            break;
        }

        // Dequeue one batch
        batch = g_samm.queue[g_samm.queue_head];
        g_samm.queue[g_samm.queue_head] = .{};
        g_samm.queue_head = (g_samm.queue_head + 1) % SAMM_MAX_QUEUE_DEPTH;
        g_samm.queue_count -= 1;
        g_samm.queue_mutex.unlock();

        // Process the batch
        if (batch.count > 0) {
            // Time the cleanup
            var t_start = Timespec{ .tv_sec = 0, .tv_nsec = 0 };
            _ = c.clock_gettime(c.CLOCK_MONOTONIC, &t_start);

            if (g_samm.trace) {
                _ = c.fprintf(c.getStderr(), "SAMM: Worker processing batch of %zu objects\n", batch.count);
            }

            cleanupBatch(&batch);
            _ = g_samm.stat_cleanup_batches.fetchAdd(1, .monotonic);

            var t_end = Timespec{ .tv_sec = 0, .tv_nsec = 0 };
            _ = c.clock_gettime(c.CLOCK_MONOTONIC, &t_end);
            const ms: f64 = @as(f64, @floatFromInt(t_end.tv_sec - t_start.tv_sec)) * 1000.0 +
                @as(f64, @floatFromInt(t_end.tv_nsec - t_start.tv_nsec)) / 1.0e6;
            g_samm.queue_mutex.lock();
            g_samm.stat_total_cleanup_time_ms += ms;
            g_samm.queue_mutex.unlock();
        }
    }

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Background cleanup worker stopped\n");
    }
}

// =========================================================================
// Internal: enqueue a scope's pointers for background cleanup
// =========================================================================

fn enqueueForCleanup(ptrs: [*]?*anyopaque, types: [*]u8, size_classes: [*]u8, count: usize) void {
    if (count == 0) {
        c.free(@ptrCast(ptrs));
        c.free(@ptrCast(types));
        c.free(@ptrCast(size_classes));
        return;
    }

    g_samm.queue_mutex.lock();

    if (g_samm.queue_count >= SAMM_MAX_QUEUE_DEPTH) {
        // Queue full — clean up synchronously as fallback
        g_samm.queue_mutex.unlock();

        if (g_samm.trace) {
            _ = c.fprintf(c.getStderr(), "SAMM: Queue full, cleaning %zu objects synchronously\n", count);
        }

        var batch = CleanupBatch{
            .ptrs = ptrs,
            .types = types,
            .size_classes = size_classes,
            .count = count,
        };
        cleanupBatch(&batch);
        _ = g_samm.stat_cleanup_batches.fetchAdd(1, .monotonic);
        return;
    }

    const slot = g_samm.queue_tail;
    g_samm.queue[slot] = .{
        .ptrs = ptrs,
        .types = types,
        .size_classes = size_classes,
        .count = count,
    };
    g_samm.queue_tail = (g_samm.queue_tail + 1) % SAMM_MAX_QUEUE_DEPTH;
    g_samm.queue_count += 1;

    g_samm.queue_cv.signal();
    g_samm.queue_mutex.unlock();
}

// =========================================================================
// Internal: drain the queue synchronously (for shutdown / samm_wait)
// =========================================================================

fn drainQueueSync() void {
    while (true) {
        var batch = CleanupBatch{};

        g_samm.queue_mutex.lock();
        if (g_samm.queue_count == 0) {
            g_samm.queue_mutex.unlock();
            break;
        }
        batch = g_samm.queue[g_samm.queue_head];
        g_samm.queue[g_samm.queue_head] = .{};
        g_samm.queue_head = (g_samm.queue_head + 1) % SAMM_MAX_QUEUE_DEPTH;
        g_samm.queue_count -= 1;
        g_samm.queue_mutex.unlock();

        if (batch.count > 0) {
            cleanupBatch(&batch);
            _ = g_samm.stat_cleanup_batches.fetchAdd(1, .monotonic);
        }
    }
}

// =========================================================================
// Public API: Initialisation & Shutdown
// =========================================================================

const pool_init_table = struct {
    // String descriptor pool: 40 B slots, 256/slab
    const string_slot_size: u32 = 40;
    const string_slots_per_slab: u32 = 256;

    // List header pool: 32 B slots, 256/slab
    const list_header_slot_size: u32 = 32;
    const list_header_slots_per_slab: u32 = 256;

    // List atom pool: 24 B slots, 512/slab
    const list_atom_slot_size: u32 = 24;
    const list_atom_slots_per_slab: u32 = 512;

    // Object pool slots per slab
    const object_slots_per_slab: [SAMM_OBJECT_SIZE_CLASSES]u32 = .{ 128, 128, 128, 128, 64, 32 };
    const object_pool_names: [SAMM_OBJECT_SIZE_CLASSES][*:0]const u8 = .{
        "Object_32",
        "Object_64",
        "Object_128",
        "Object_256",
        "Object_512",
        "Object_1024",
    };
};

export fn samm_init() callconv(.c) void {
    if (g_samm.initialised) return;

    // Reset state to defaults
    g_samm = .{};

    // Initialise Bloom filter (lazy — no memory allocated yet)
    g_samm.bloom = BloomFilter.init();

    // Initialise string descriptor pool
    samm_slab_pool_init(
        g_string_desc_pool,
        pool_init_table.string_slot_size,
        pool_init_table.string_slots_per_slab,
        "StringDesc",
    );

    // Initialise list pools
    samm_slab_pool_init(
        g_list_header_pool,
        pool_init_table.list_header_slot_size,
        pool_init_table.list_header_slots_per_slab,
        "ListHeader",
    );
    samm_slab_pool_init(
        g_list_atom_pool,
        pool_init_table.list_atom_slot_size,
        pool_init_table.list_atom_slots_per_slab,
        "ListAtom",
    );

    // Initialise object size-class pools
    for (0..SAMM_OBJECT_SIZE_CLASSES) |sc| {
        samm_slab_pool_init(
            g_object_pools[sc],
            object_slot_sizes[sc],
            pool_init_table.object_slots_per_slab[sc],
            pool_init_table.object_pool_names[sc],
        );
    }

    // Initialise global scope (depth 0)
    samm_scope_ensure_init();
    samm_scope_reset(0);
    g_samm.scope_depth = 0;
    g_samm.peak_scope_depth = 0;

    // Initialise cleanup queue
    g_samm.queue_head = 0;
    g_samm.queue_tail = 0;
    g_samm.queue_count = 0;

    // Start background worker
    g_samm.shutdown_flag = false;
    g_samm.worker_running = false;

    g_samm.worker_thread = std.Thread.spawn(.{}, workerFn, .{}) catch blk: {
        _ = c.fprintf(c.getStderr(), "SAMM WARNING: Failed to create background worker. " ++
            "Cleanup will be synchronous.\n");
        break :blk null;
    };
    if (g_samm.worker_thread != null) {
        g_samm.worker_running = true;
    }

    g_samm.enabled = true;
    g_samm.initialised = true;

    // Auto-enable trace from environment variable
    g_samm.trace = (c.getenv("SAMM_TRACE") != null);

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Initialised (Bloom filter: lazy, max scopes: %d)\n", SAMM_MAX_SCOPE_DEPTH);
    }
}

export fn samm_shutdown() callconv(.c) void {
    if (!g_samm.initialised) return;

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Shutting down...\n");
    }

    // Signal worker to stop
    g_samm.queue_mutex.lock();
    g_samm.shutdown_flag = true;
    g_samm.queue_cv.signal();
    g_samm.queue_mutex.unlock();

    // Join worker thread
    if (g_samm.worker_thread) |thread| {
        thread.join();
        g_samm.worker_running = false;
        g_samm.worker_thread = null;
    }

    // Drain any remaining items in the queue synchronously
    drainQueueSync();

    // Clean up all remaining scopes (including global)
    {
        var d: c_int = g_samm.scope_depth;
        while (d >= 0) : (d -= 1) {
            var batch_ptrs: ?[*]?*anyopaque = null;
            var batch_types: ?[*]u8 = null;
            var batch_sc: ?[*]u8 = null;
            var batch_count: usize = 0;

            if (samm_scope_detach(d, &batch_ptrs, &batch_types, &batch_sc, &batch_count)) {
                if (g_samm.trace) {
                    _ = c.fprintf(c.getStderr(), "SAMM: Cleaning up %zu objects from scope depth %d\n", batch_count, d);
                }
                var batch = CleanupBatch{
                    .ptrs = batch_ptrs,
                    .types = batch_types,
                    .size_classes = batch_sc,
                    .count = batch_count,
                };
                cleanupBatch(&batch);
            }
        }
    }

    // Print stats if tracing enabled or SAMM_STATS env var is set
    const should_print_stats = g_samm.trace or c.getenv("SAMM_STATS") != null or c.getenv("BASIC_MEMORY_STATS") != null;
    if (should_print_stats) {
        samm_print_stats();
    }

    // Destroy string descriptor pool
    if (should_print_stats) {
        samm_slab_pool_print_stats(g_string_desc_pool);
    }
    samm_slab_pool_destroy(g_string_desc_pool);

    // Destroy list pools
    if (should_print_stats) {
        samm_slab_pool_print_stats(g_list_header_pool);
        samm_slab_pool_print_stats(g_list_atom_pool);
        for (0..SAMM_OBJECT_SIZE_CLASSES) |sc| {
            if (samm_slab_pool_total_allocs(g_object_pools[sc]) > 0) {
                samm_slab_pool_print_stats(g_object_pools[sc]);
            }
        }
    }
    samm_slab_pool_destroy(g_list_header_pool);
    samm_slab_pool_destroy(g_list_atom_pool);

    // Destroy object size-class pools
    for (0..SAMM_OBJECT_SIZE_CLASSES) |sc| {
        samm_slab_pool_destroy(g_object_pools[sc]);
    }

    // Destroy Bloom filter
    g_samm.bloom.destroy();

    g_samm.initialised = false;
    g_samm.enabled = false;
}

// =========================================================================
// Public API: Enable / Disable
// =========================================================================

export fn samm_set_enabled(enabled: c_int) callconv(.c) void {
    if (enabled != 0 and !g_samm.initialised) {
        samm_init();
    }
    g_samm.enabled = (enabled != 0);
}

export fn samm_is_enabled() callconv(.c) c_int {
    return if (g_samm.enabled) 1 else 0;
}

// =========================================================================
// Public API: Scope Management
// =========================================================================

export fn samm_enter_scope() callconv(.c) void {
    if (!g_samm.enabled) return;

    g_samm.scope_mutex.lock();

    const new_depth = g_samm.scope_depth + 1;
    if (new_depth >= SAMM_MAX_SCOPE_DEPTH) {
        g_samm.scope_mutex.unlock();
        _ = c.fprintf(c.getStderr(), "SAMM FATAL: Maximum scope depth (%d) exceeded\n", SAMM_MAX_SCOPE_DEPTH);
        c.abort();
    }

    samm_scope_reset(new_depth);
    g_samm.scope_depth = new_depth;
    if (new_depth > g_samm.peak_scope_depth) {
        g_samm.peak_scope_depth = new_depth;
    }

    g_samm.scope_mutex.unlock();

    _ = g_samm.stat_scopes_entered.fetchAdd(1, .monotonic);

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Enter scope (depth: %d)\n", new_depth);
    }
}

export fn samm_exit_scope() callconv(.c) void {
    if (!g_samm.enabled) return;

    var ptrs_to_clean: ?[*]?*anyopaque = null;
    var types_to_clean: ?[*]u8 = null;
    var sc_to_clean: ?[*]u8 = null;
    var count_to_clean: usize = 0;

    g_samm.scope_mutex.lock();

    if (g_samm.scope_depth <= 0) {
        // Cannot exit global scope
        g_samm.scope_mutex.unlock();
        if (g_samm.trace) {
            _ = c.fprintf(c.getStderr(), "SAMM: Cannot exit global scope (depth 0)\n");
        }
        return;
    }

    // Detach array storage from Zig scope manager
    _ = samm_scope_detach(g_samm.scope_depth, &ptrs_to_clean, &types_to_clean, &sc_to_clean, &count_to_clean);

    g_samm.scope_depth -= 1;

    g_samm.scope_mutex.unlock();

    _ = g_samm.stat_scopes_exited.fetchAdd(1, .monotonic);

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Exit scope (depth now: %d, cleaning: %zu objects)\n", g_samm.scope_depth, count_to_clean);
    }

    // Enqueue for background cleanup (or sync if no worker)
    if (count_to_clean > 0) {
        if (g_samm.worker_running) {
            enqueueForCleanup(ptrs_to_clean.?, types_to_clean.?, sc_to_clean.?, count_to_clean);
        } else {
            // No worker — clean synchronously
            var batch = CleanupBatch{
                .ptrs = ptrs_to_clean,
                .types = types_to_clean,
                .size_classes = sc_to_clean,
                .count = count_to_clean,
            };
            cleanupBatch(&batch);
            _ = g_samm.stat_cleanup_batches.fetchAdd(1, .monotonic);
        }
    }
}

// Query the current scope nesting depth.
// Named with a Zig-friendly identifier since "samm_scope_depth" could
// potentially collide with extern names, but there is no such extern
// in samm_scope.zig so we export it directly.
comptime {
    @export(&samm_scope_depth_fn, .{ .name = "samm_scope_depth", .linkage = .strong });
}

fn samm_scope_depth_fn() callconv(.c) c_int {
    if (!g_samm.enabled) return 0;
    g_samm.scope_mutex.lock();
    const depth = g_samm.scope_depth;
    g_samm.scope_mutex.unlock();
    return depth;
}

// =========================================================================
// Public API: Object Allocation (size-class pools)
// =========================================================================

export fn samm_alloc_object(size: usize) callconv(.c) ?*anyopaque {
    const sc = sizeToClass(size);

    var ptr: ?*anyopaque = null;
    if (sc >= 0) {
        // Allocate from size-class pool
        ptr = samm_slab_pool_alloc(g_object_pools[@intCast(sc)]);
        g_last_object_size_class = @intCast(sc);
    } else {
        // Overflow object (> 1024 B) — fall back to calloc
        ptr = c.calloc(1, size);
        g_last_object_size_class = SAMM_SIZE_CLASS_NONE;
    }

    if (ptr != null) {
        _ = g_samm.stat_objects_allocated.fetchAdd(1, .monotonic);
        _ = g_samm.stat_total_bytes_allocated.fetchAdd(@intCast(size), .monotonic);
    }
    return ptr;
}

export fn samm_free_object(ptr: ?*anyopaque) callconv(.c) void {
    const p = ptr orelse return;

    var sc: u8 = SAMM_SIZE_CLASS_NONE;

    if (g_samm.enabled) {
        g_samm.scope_mutex.lock();

        // Try to untrack from whichever scope owns this pointer
        var found = false;
        var t_u8: u8 = 0;
        var d: c_int = g_samm.scope_depth;
        while (d >= 0) : (d -= 1) {
            if (samm_scope_remove(d, p, &t_u8, &sc)) {
                if (g_samm.trace) {
                    _ = c.fprintf(c.getStderr(), "SAMM: samm_free_object untracked %p from scope %d (sc=%u)\n", p, d, @as(c_uint, sc));
                }
                found = true;
                break;
            }
        }

        if (!found) {
            // Not tracked. For overflow objects, consult Bloom filter.
            if (sc == SAMM_SIZE_CLASS_NONE) {
                if (g_samm.bloom.check(p)) {
                    g_samm.scope_mutex.unlock();
                    _ = g_samm.stat_double_free_attempts.fetchAdd(1, .monotonic);
                    if (g_samm.trace) {
                        _ = c.fprintf(c.getStderr(), "SAMM WARNING: Possible double-free on %p " ++
                            "(Bloom filter hit, not tracked)\n", p);
                    }
                    return;
                }
            }
            if (g_samm.trace) {
                _ = c.fprintf(c.getStderr(), "SAMM: samm_free_object freeing untracked %p\n", p);
            }
        }

        // Record in Bloom filter — only for overflow-class objects
        if (sc == SAMM_SIZE_CLASS_NONE) {
            g_samm.bloom.add(p);
        }
        g_samm.scope_mutex.unlock();
    }

    // Return object to correct size-class pool, or free for overflow
    if (sc < SAMM_OBJECT_SIZE_CLASSES) {
        const slot_sz: u64 = object_slot_sizes[sc];
        _ = g_samm.stat_total_bytes_freed.fetchAdd(slot_sz, .monotonic);
        samm_slab_pool_free(g_object_pools[sc], p);
    } else {
        c.free(p);
    }
    _ = g_samm.stat_objects_freed.fetchAdd(1, .monotonic);
}

// =========================================================================
// Public API: Scope Tracking
// =========================================================================

export fn samm_track(ptr: ?*anyopaque, alloc_type: c_int) callconv(.c) void {
    if (!g_samm.enabled) return;
    const p = ptr orelse return;

    g_samm.scope_mutex.lock();
    if (g_samm.scope_depth >= 0 and g_samm.scope_depth < SAMM_MAX_SCOPE_DEPTH) {
        samm_scope_add(g_samm.scope_depth, p, @intCast(alloc_type), SAMM_SIZE_CLASS_NONE);
        if (g_samm.trace) {
            _ = c.fprintf(c.getStderr(), "SAMM: Tracked %p (type=%d) in scope %d\n", p, alloc_type, g_samm.scope_depth);
        }
    }
    g_samm.scope_mutex.unlock();
}

export fn samm_track_object(obj: ?*anyopaque) callconv(.c) void {
    if (!g_samm.enabled) return;
    const p = obj orelse return;

    // Read the size class stashed by samm_alloc_object()
    const sc = g_last_object_size_class;

    g_samm.scope_mutex.lock();
    if (g_samm.scope_depth >= 0 and g_samm.scope_depth < SAMM_MAX_SCOPE_DEPTH) {
        samm_scope_add(g_samm.scope_depth, p, SAMM_ALLOC_OBJECT, sc);
        if (g_samm.trace) {
            _ = c.fprintf(c.getStderr(), "SAMM: Tracked object %p (sc=%u) in scope %d\n", p, @as(c_uint, sc), g_samm.scope_depth);
        }
    }
    g_samm.scope_mutex.unlock();
}

export fn samm_untrack(ptr: ?*anyopaque) callconv(.c) void {
    if (!g_samm.enabled) return;
    const p = ptr orelse return;

    g_samm.scope_mutex.lock();
    // Search from innermost scope outward
    var d: c_int = g_samm.scope_depth;
    while (d >= 0) : (d -= 1) {
        if (samm_scope_remove(d, p, null, null)) {
            if (g_samm.trace) {
                _ = c.fprintf(c.getStderr(), "SAMM: Untracked %p from scope %d\n", p, d);
            }
            break;
        }
    }
    g_samm.scope_mutex.unlock();
}

// =========================================================================
// Public API: RETAIN
// =========================================================================

export fn samm_retain(ptr: ?*anyopaque, parent_offset: c_int) callconv(.c) void {
    if (!g_samm.enabled) return;
    const p = ptr orelse return;
    if (parent_offset <= 0) return;

    _ = g_samm.stat_retain_calls.fetchAdd(1, .monotonic);

    g_samm.scope_mutex.lock();

    const current = g_samm.scope_depth;
    var found = false;
    var t_u8: u8 = 0;
    var sc_u8: u8 = 0;

    // Search from current scope outward
    var d: c_int = current;
    while (d >= 0) : (d -= 1) {
        if (samm_scope_remove(d, p, &t_u8, &sc_u8)) {
            // Found! Move to target scope.
            var target = d - parent_offset;
            if (target < 0) target = 0; // Clamp to global scope

            samm_scope_add(target, p, t_u8, sc_u8);

            if (g_samm.trace) {
                _ = c.fprintf(c.getStderr(), "SAMM: Retained %p from scope %d to scope %d\n", p, d, target);
            }
            found = true;
            break;
        }
    }

    if (!found and g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: Retain failed — %p not found in any scope\n", p);
    }

    g_samm.scope_mutex.unlock();
}

export fn samm_retain_parent(ptr: ?*anyopaque) callconv(.c) void {
    samm_retain(ptr, 1);
}

// =========================================================================
// Public API: Double-Free Detection
// =========================================================================

export fn samm_is_probably_freed(ptr: ?*anyopaque) callconv(.c) c_int {
    if (!g_samm.enabled) return 0;
    const p = ptr orelse return 0;

    g_samm.scope_mutex.lock();
    const result = g_samm.bloom.check(p);
    g_samm.scope_mutex.unlock();
    return if (result) 1 else 0;
}

// =========================================================================
// Public API: List Support (pool-based allocation)
// =========================================================================

export fn samm_alloc_list() callconv(.c) ?*anyopaque {
    const ptr = samm_slab_pool_alloc(g_list_header_pool) orelse return null;
    _ = g_samm.stat_total_bytes_allocated.fetchAdd(SIZEOF_LIST_HEADER, .monotonic);
    return ptr;
}

export fn samm_track_list(list_header_ptr: ?*anyopaque) callconv(.c) void {
    samm_track(list_header_ptr, SAMM_ALLOC_LIST);
}

export fn samm_alloc_list_atom() callconv(.c) ?*anyopaque {
    const ptr = samm_slab_pool_alloc(g_list_atom_pool) orelse return null;
    _ = g_samm.stat_total_bytes_allocated.fetchAdd(SIZEOF_LIST_ATOM, .monotonic);
    return ptr;
}

// =========================================================================
// Public API: String Tracking
// =========================================================================

export fn samm_track_string(string_desc_ptr: ?*anyopaque) callconv(.c) void {
    const p = string_desc_ptr orelse return;
    samm_track(p, SAMM_ALLOC_STRING);
    _ = g_samm.stat_strings_tracked.fetchAdd(1, .monotonic);
}

// =========================================================================
// Public API: String Allocation (pool + track)
// =========================================================================

/// Replicates the logic of the C static inline string_desc_alloc() from
/// string_pool.h, since we can't call a C static inline from Zig.
export fn samm_alloc_string() callconv(.c) ?*anyopaque {
    const raw = samm_slab_pool_alloc(g_string_desc_pool) orelse return null;

    // Set non-zero defaults (samm_slab_pool_alloc returns zeroed memory).
    // StringDescriptor layout:
    //   [0..8)   data (ptr)     — already 0
    //   [8..16)  length (i64)   — already 0
    //   [16..24) capacity (i64) — already 0
    //   [24..28) refcount (i32) — set to 1
    //   [28]     encoding (u8)  — set to ASCII (0) — already 0
    //   [29]     dirty (u8)     — set to 1
    //   [30..32) _padding       — already 0
    //   [32..40) utf8_cache     — already 0
    const bytes: [*]u8 = @ptrCast(raw);
    // refcount = 1 (little-endian i32 at offset 24)
    bytes[24] = 1;
    bytes[25] = 0;
    bytes[26] = 0;
    bytes[27] = 0;
    // encoding = 0 (ASCII) — already zeroed
    // dirty = 1 at offset 29
    bytes[29] = 1;

    _ = g_samm.stat_total_bytes_allocated.fetchAdd(SIZEOF_STRING_DESCRIPTOR, .monotonic);

    if (g_samm.enabled) {
        samm_track_string(raw);
    }
    return raw;
}

// =========================================================================
// Public API: Destructor Registration
// =========================================================================

export fn samm_register_cleanup(alloc_type: c_int, cleanup_fn: CleanupFn) callconv(.c) void {
    if (alloc_type >= 0 and alloc_type < 8) {
        g_samm.cleanup_fns[@intCast(alloc_type)] = cleanup_fn;
    }
}

// =========================================================================
// Public API: Diagnostics
// =========================================================================

export fn samm_get_stats(out: ?*SAMMStats) callconv(.c) void {
    const s = out orelse return;

    s.scopes_entered = g_samm.stat_scopes_entered.load(.monotonic);
    s.scopes_exited = g_samm.stat_scopes_exited.load(.monotonic);
    s.objects_allocated = g_samm.stat_objects_allocated.load(.monotonic);
    s.objects_freed = g_samm.stat_objects_freed.load(.monotonic);
    s.objects_cleaned = g_samm.stat_objects_cleaned.load(.monotonic);
    s.cleanup_batches = g_samm.stat_cleanup_batches.load(.monotonic);
    s.double_free_attempts = g_samm.stat_double_free_attempts.load(.monotonic);
    s.bloom_false_positives = 0; // TODO: estimate from Bloom filter fill ratio
    s.retain_calls = g_samm.stat_retain_calls.load(.monotonic);
    s.total_bytes_allocated = g_samm.stat_total_bytes_allocated.load(.monotonic);
    s.total_bytes_freed = g_samm.stat_total_bytes_freed.load(.monotonic);
    s.strings_tracked = g_samm.stat_strings_tracked.load(.monotonic);
    s.strings_cleaned = g_samm.stat_strings_cleaned.load(.monotonic);

    g_samm.scope_mutex.lock();
    s.current_scope_depth = g_samm.scope_depth;
    s.peak_scope_depth = g_samm.peak_scope_depth;
    g_samm.scope_mutex.unlock();

    s.bloom_memory_bytes = g_samm.bloom.size_bytes;

    g_samm.queue_mutex.lock();
    s.total_cleanup_time_ms = g_samm.stat_total_cleanup_time_ms;
    g_samm.queue_mutex.unlock();

    s.background_worker_active = if (g_samm.worker_running) 1 else 0;
}

export fn samm_print_stats() callconv(.c) void {
    var s: SAMMStats = undefined;
    samm_get_stats(&s);

    _ = c.fprintf(c.getStderr(), "\n");
    _ = c.fprintf(c.getStderr(), "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    _ = c.fprintf(c.getStderr(), "  SAMM Memory Statistics\n");
    _ = c.fprintf(c.getStderr(), "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
    _ = c.fprintf(c.getStderr(), "  Scopes entered:       %llu\n", @as(c_ulonglong, s.scopes_entered));
    _ = c.fprintf(c.getStderr(), "  Scopes exited:        %llu\n", @as(c_ulonglong, s.scopes_exited));
    _ = c.fprintf(c.getStderr(), "  Objects allocated:    %llu\n", @as(c_ulonglong, s.objects_allocated));
    _ = c.fprintf(c.getStderr(), "  Objects freed (DEL):  %llu\n", @as(c_ulonglong, s.objects_freed));
    _ = c.fprintf(c.getStderr(), "  Objects cleaned (bg): %llu\n", @as(c_ulonglong, s.objects_cleaned));
    _ = c.fprintf(c.getStderr(), "  Strings tracked:      %llu\n", @as(c_ulonglong, s.strings_tracked));
    _ = c.fprintf(c.getStderr(), "  Strings cleaned:      %llu\n", @as(c_ulonglong, s.strings_cleaned));
    _ = c.fprintf(c.getStderr(), "  Cleanup batches:      %llu\n", @as(c_ulonglong, s.cleanup_batches));
    _ = c.fprintf(c.getStderr(), "  Double-free catches:  %llu\n", @as(c_ulonglong, s.double_free_attempts));
    _ = c.fprintf(c.getStderr(), "  RETAIN calls:         %llu\n", @as(c_ulonglong, s.retain_calls));
    _ = c.fprintf(c.getStderr(), "  Bytes allocated:      %llu\n", @as(c_ulonglong, s.total_bytes_allocated));
    _ = c.fprintf(c.getStderr(), "  Bytes freed:          %llu\n", @as(c_ulonglong, s.total_bytes_freed));

    // Calculate leaks using signed arithmetic to avoid underflow
    const allocated: i64 = @intCast(s.objects_allocated);
    const freed_and_cleaned: i64 = @intCast(s.objects_freed + s.objects_cleaned);
    const leaked_objects: i64 = allocated - freed_and_cleaned;

    const bytes_allocated: i64 = @intCast(s.total_bytes_allocated);
    const bytes_freed: i64 = @intCast(s.total_bytes_freed);
    const leaked_bytes: i64 = bytes_allocated - bytes_freed;

    if (leaked_objects > 0) {
        _ = c.fprintf(c.getStderr(), "  Leaked objects:       %lld\n", @as(c_longlong, leaked_objects));
    } else {
        _ = c.fprintf(c.getStderr(), "  Leaked objects:       0\n");
    }

    if (leaked_bytes > 0) {
        _ = c.fprintf(c.getStderr(), "  Leaked bytes:         %lld\n", @as(c_longlong, leaked_bytes));
    } else {
        _ = c.fprintf(c.getStderr(), "  Leaked bytes:         0\n");
    }

    if (leaked_objects > 0 or leaked_bytes > 0) {
        _ = c.fprintf(c.getStderr(), "  ⚠️  WARNING: Memory leaks detected!\n");
    } else {
        _ = c.fprintf(c.getStderr(), "  ✓ All allocations freed\n");
    }

    _ = c.fprintf(c.getStderr(), "  Current scope depth:  %d\n", s.current_scope_depth);
    _ = c.fprintf(c.getStderr(), "  Peak scope depth:     %d\n", s.peak_scope_depth);
    if (s.bloom_memory_bytes > 0) {
        _ = c.fprintf(c.getStderr(), "  Bloom filter memory:  %zu bytes (%.1f KB)\n", s.bloom_memory_bytes, @as(f64, @floatFromInt(s.bloom_memory_bytes)) / 1024.0);
    } else {
        _ = c.fprintf(c.getStderr(), "  Bloom filter:         not allocated (no overflow objects)\n");
    }
    _ = c.fprintf(c.getStderr(), "  Cleanup time:         %.3f ms\n", s.total_cleanup_time_ms);
    _ = c.fprintf(c.getStderr(), "  Background worker:    %s\n", if (s.background_worker_active != 0) @as([*:0]const u8, "active") else @as([*:0]const u8, "stopped"));
    _ = c.fprintf(c.getStderr(), "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n");
}

/// Print SAMM statistics unconditionally (for use in program cleanup)
export fn samm_print_stats_always() callconv(.c) void {
    samm_print_stats();
    _ = c.fprintf(c.getStderr(), "\n");
}

export fn samm_set_trace(enabled: c_int) callconv(.c) void {
    g_samm.trace = (enabled != 0);
}

export fn samm_wait() callconv(.c) void {
    if (!g_samm.enabled) return;

    if (g_samm.worker_running) {
        // Spin until the queue is empty
        while (true) {
            // Give the worker time to process
            var ts = Timespec{ .tv_sec = 0, .tv_nsec = 1000000 }; // 1ms
            _ = c.nanosleep(&ts, null);

            g_samm.queue_mutex.lock();
            const remaining = g_samm.queue_count;
            g_samm.queue_mutex.unlock();
            if (remaining == 0) break;
        }
    } else {
        // No worker — drain synchronously
        drainQueueSync();
    }

    if (g_samm.trace) {
        _ = c.fprintf(c.getStderr(), "SAMM: All pending cleanup complete\n");
    }
}

export fn samm_record_bytes_freed(bytes: u64) callconv(.c) void {
    _ = g_samm.stat_total_bytes_freed.fetchAdd(bytes, .monotonic);
}

// =========================================================================
// Unit Tests
// =========================================================================

test "fnv1a basic" {
    const data = "hello";
    const hash = fnv1a(data);
    // Just verify it produces a non-zero result and is deterministic
    try std.testing.expect(hash != 0);
    try std.testing.expectEqual(hash, fnv1a(data));
}

test "bloom filter add and check" {
    var bf = BloomFilter.init();
    defer bf.destroy();

    // Before adding, check should return false
    const dummy: usize = 0xDEADBEEF;
    const ptr: *const anyopaque = @ptrFromInt(dummy);
    try std.testing.expect(!bf.check(ptr));

    // After adding, check should return true
    bf.add(ptr);
    try std.testing.expect(bf.check(ptr));

    // A different pointer should (probably) not match
    const other: usize = 0xCAFEBABE;
    const other_ptr: *const anyopaque = @ptrFromInt(other);
    // This is probabilistic but with only 1 item in 512K bits, false positive is ~0
    try std.testing.expect(!bf.check(other_ptr));
}

test "sizeToClass mapping" {
    try std.testing.expectEqual(@as(i32, 0), sizeToClass(1));
    try std.testing.expectEqual(@as(i32, 0), sizeToClass(32));
    try std.testing.expectEqual(@as(i32, 1), sizeToClass(33));
    try std.testing.expectEqual(@as(i32, 1), sizeToClass(64));
    try std.testing.expectEqual(@as(i32, 2), sizeToClass(128));
    try std.testing.expectEqual(@as(i32, 3), sizeToClass(256));
    try std.testing.expectEqual(@as(i32, 4), sizeToClass(512));
    try std.testing.expectEqual(@as(i32, 5), sizeToClass(1024));
    try std.testing.expectEqual(@as(i32, -1), sizeToClass(1025));
    try std.testing.expectEqual(@as(i32, -1), sizeToClass(4096));
}
