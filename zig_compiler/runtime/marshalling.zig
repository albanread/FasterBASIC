// marshalling.zig
// FasterBASIC Runtime — MARSHALL / UNMARSHALL support (Zig)
//
// Implements serialisation of UDTs, class objects, and arrays into
// self-contained blobs for safe transfer across WORKER thread boundaries.
//
// Key design:
//   - marshall_udt / unmarshall_udt: flat memcpy for scalar-only types
//   - marshall_udt_deep: memcpy + deep-copy string fields at known offsets
//   - marshall_array / unmarshall_array: descriptor + element data as one blob
//
// String deep copy:
//   When a UDT or class contains STRING fields the flat memcpy creates
//   aliased StringDescriptor pointers.  marshall_udt_deep takes a table
//   of byte-offsets (one per string field) and calls string_clone() for
//   each, so the blob owns independent copies.
//
// Replaces the C implementations in worker_runtime.c.
// All exported symbols maintain C ABI compatibility.

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn malloc(size: usize) ?*anyopaque;
    extern fn calloc(count: usize, size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
};

// =========================================================================
// External runtime — string deep copy
// =========================================================================
const StringDescriptor = anyopaque;
extern fn string_clone(str: ?*const StringDescriptor) ?*StringDescriptor;

// =========================================================================
// ArrayDescriptor — must match array_descriptor.h (64 bytes)
// =========================================================================
const ArrayDescriptor = extern struct {
    data: ?*anyopaque,
    lowerBound1: i64,
    upperBound1: i64,
    lowerBound2: i64,
    upperBound2: i64,
    elementSize: i64,
    dimensions: i32,
    base: i32,
    typeSuffix: u8,
    _padding: [7]u8,
};

// =========================================================================
// UDT / class object marshalling
// =========================================================================

/// Shallow marshall — flat memcpy.  Use only for types with no string
/// or reference fields.
export fn marshall_udt(udt_ptr: ?*const anyopaque, size: i32) callconv(.c) ?*anyopaque {
    const ptr = udt_ptr orelse return null;
    if (size <= 0) return null;

    const sz: usize = @intCast(size);
    const blob = c.malloc(sz) orelse return null;

    const dst: [*]u8 = @ptrCast(blob);
    const src: [*]const u8 = @ptrCast(ptr);
    @memcpy(dst[0..sz], src[0..sz]);

    return blob;
}

/// Shallow unmarshall — memcpy from blob into target, then free blob.
export fn unmarshall_udt(blob: ?*anyopaque, udt_ptr: ?*anyopaque, size: i32) callconv(.c) void {
    const b = blob orelse return;
    const ptr = udt_ptr orelse {
        c.free(b);
        return;
    };
    if (size <= 0) {
        c.free(b);
        return;
    }

    const sz: usize = @intCast(size);
    const dst: [*]u8 = @ptrCast(ptr);
    const src: [*]const u8 = @ptrCast(b);
    @memcpy(dst[0..sz], src[0..sz]);

    c.free(b);
}

/// Deep marshall — flat memcpy, then clone every string field listed
/// in the offsets table.
///
/// `string_offsets` is a pointer to an array of i32 byte-offsets within
/// the struct where StringDescriptor* fields live.  `num_offsets` is the
/// count of entries in that table.
///
/// After the memcpy the blob contains shallow copies of the caller's
/// string pointers.  We replace each one with an independent clone so
/// the blob is fully self-contained.
export fn marshall_udt_deep(
    udt_ptr: ?*const anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) ?*anyopaque {
    const ptr = udt_ptr orelse return null;
    if (size <= 0) return null;

    const sz: usize = @intCast(size);
    const blob = c.malloc(sz) orelse return null;

    // Flat copy
    const dst: [*]u8 = @ptrCast(blob);
    const src: [*]const u8 = @ptrCast(ptr);
    @memcpy(dst[0..sz], src[0..sz]);

    // Deep-copy each string field
    if (string_offsets) |offsets| {
        if (num_offsets > 0) {
            const n: usize = @intCast(num_offsets);
            for (0..n) |i| {
                deepCopyStringAt(dst, offsets[i]);
            }
        }
    }

    return blob;
}

/// Deep unmarshall — memcpy from blob into target, deep-copy the string
/// fields in the *target* (since the blob's cloned pointers will be freed
/// along with the blob, we need fresh clones in the target), then free
/// the blob.
///
/// Wait — actually, after memcpy the target has the blob's string pointers.
/// Those were cloned during marshall, so they are independent allocations.
/// When we free the blob we only free the blob allocation itself, not the
/// strings it points to (they are separate heap objects).  So the target
/// now owns those cloned strings.  No extra clone needed on unmarshall.
///
/// However, if we want a symmetrical API for safety (e.g. unmarshalling
/// the same blob twice), we clone on unmarshall too.
export fn unmarshall_udt_deep(
    blob: ?*anyopaque,
    udt_ptr: ?*anyopaque,
    size: i32,
    string_offsets: ?[*]const i32,
    num_offsets: i32,
) callconv(.c) void {
    const b = blob orelse return;
    const ptr = udt_ptr orelse {
        c.free(b);
        return;
    };
    if (size <= 0) {
        c.free(b);
        return;
    }

    const sz: usize = @intCast(size);
    const dst: [*]u8 = @ptrCast(ptr);
    const src: [*]const u8 = @ptrCast(b);
    @memcpy(dst[0..sz], src[0..sz]);

    // The target now holds the blob's string pointers (which are
    // independent clones from marshall_udt_deep).  Clone them again
    // into the target so the target is fully independent and the
    // blob's copies can be safely discarded.
    if (string_offsets) |offsets| {
        if (num_offsets > 0) {
            const n: usize = @intCast(num_offsets);
            for (0..n) |i| {
                deepCopyStringAt(dst, offsets[i]);
            }
        }
    }

    c.free(b);
}

/// Clone the StringDescriptor* at `base + offset` in place.
fn deepCopyStringAt(base: [*]u8, offset: i32) void {
    if (offset < 0) return;
    const off: usize = @intCast(offset);

    // The slot at base+offset is an 8-byte pointer to StringDescriptor.
    const slot: *?*StringDescriptor = @ptrCast(@alignCast(base + off));
    const old_str = slot.* orelse return;

    // Clone and replace
    const new_str = string_clone(old_str);
    slot.* = new_str;
}

// =========================================================================
// Array marshalling
// =========================================================================

/// Marshall an array into a self-contained blob.
///
/// Blob layout:
///   [ArrayDescriptor (64 bytes)] [element data (N bytes)]
///
/// The data pointer inside the blob's descriptor is patched to point
/// into the blob itself, making the whole thing one contiguous allocation.
export fn marshall_array(desc: ?*const ArrayDescriptor) callconv(.c) ?*anyopaque {
    const d = desc orelse return null;
    const data_ptr = d.data orelse return null;

    // Compute element count
    var count: i64 = d.upperBound1 - d.lowerBound1 + 1;
    if (d.dimensions >= 2 and d.upperBound2 >= d.lowerBound2) {
        const count2 = d.upperBound2 - d.lowerBound2 + 1;
        count *= count2;
    }
    if (count <= 0) return null;

    const data_size: usize = @intCast(count * d.elementSize);
    const blob_size = @sizeOf(ArrayDescriptor) + data_size;

    const blob_raw = c.malloc(blob_size) orelse return null;
    const blob: *ArrayDescriptor = @ptrCast(@alignCast(blob_raw));

    // Copy the descriptor
    blob.* = d.*;

    // Copy element data right after the descriptor
    const blob_data: [*]u8 = @as([*]u8, @ptrCast(blob_raw)) + @sizeOf(ArrayDescriptor);
    const src_data: [*]const u8 = @ptrCast(data_ptr);
    @memcpy(blob_data[0..data_size], src_data[0..data_size]);

    // Patch data pointer to point inside the blob
    blob.data = @ptrCast(blob_data);

    return blob_raw;
}

/// Unmarshall a blob back into an array descriptor.
/// Allocates new storage for element data (fully independent),
/// then frees the blob.
export fn unmarshall_array(blob: ?*anyopaque, desc: ?*ArrayDescriptor) callconv(.c) void {
    const b = blob orelse return;
    const d = desc orelse {
        c.free(b);
        return;
    };

    const src: *const ArrayDescriptor = @ptrCast(@alignCast(b));

    // Copy descriptor metadata
    d.lowerBound1 = src.lowerBound1;
    d.upperBound1 = src.upperBound1;
    d.lowerBound2 = src.lowerBound2;
    d.upperBound2 = src.upperBound2;
    d.elementSize = src.elementSize;
    d.dimensions = src.dimensions;
    d.base = src.base;
    d.typeSuffix = src.typeSuffix;

    // Compute data size
    var count: i64 = src.upperBound1 - src.lowerBound1 + 1;
    if (src.dimensions >= 2 and src.upperBound2 >= src.lowerBound2) {
        const count2 = src.upperBound2 - src.lowerBound2 + 1;
        count *= count2;
    }

    if (count <= 0) {
        d.data = null;
        c.free(b);
        return;
    }

    const data_size: usize = @intCast(count * src.elementSize);

    // Free existing data in target
    if (d.data) |old| {
        c.free(old);
    }

    // Allocate fresh data and copy from blob
    const new_data = c.malloc(data_size) orelse {
        d.data = null;
        c.free(b);
        return;
    };

    // The blob's data sits right after the descriptor
    const blob_data: [*]const u8 = @as([*]const u8, @ptrCast(b)) + @sizeOf(ArrayDescriptor);
    const dst: [*]u8 = @ptrCast(new_data);
    @memcpy(dst[0..data_size], blob_data[0..data_size]);

    d.data = new_data;

    c.free(b);
}
