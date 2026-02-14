//
// fbc_bridge.zig
// FasterBASIC Runtime — QBE Codegen Bridge
//
// Non-inline wrapper functions for ArrayDescriptor operations.
// QBE IL cannot call static inline functions, so these thin wrappers
// expose the functionality from array_descriptor.h.
//
// The static inline functions from array_descriptor.h are reimplemented
// here in Zig since they are not available as linkable symbols.
//

const std = @import("std");
const c = std.c;

// =========================================================================
// Extern declarations
// =========================================================================

extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern const __stderrp: *anyopaque;
extern fn exit(status: c_int) noreturn;
extern fn array_descriptor_erase(desc: ?*ArrayDescriptor) void;

// =========================================================================
// ArrayDescriptor layout (must match array_descriptor.h — 64 bytes)
// =========================================================================

pub const ArrayDescriptor = extern struct {
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
// Reimplemented inline helpers from array_descriptor.h
// =========================================================================

fn arrayDescriptorInit(
    desc: *ArrayDescriptor,
    lowerBound: i64,
    upperBound: i64,
    elementSize: i64,
    base_val: i32,
    typeSuffix: u8,
) i32 {
    if (upperBound < lowerBound or elementSize <= 0) return -1;

    const count = upperBound - lowerBound + 1;
    const totalSize: usize = @intCast(count * elementSize);

    const ptr = c.malloc(totalSize) orelse return -1;
    @memset(@as([*]u8, @ptrCast(ptr))[0..totalSize], 0);

    desc.data = ptr;
    desc.lowerBound1 = lowerBound;
    desc.upperBound1 = upperBound;
    desc.lowerBound2 = 0;
    desc.upperBound2 = 0;
    desc.elementSize = elementSize;
    desc.dimensions = 1;
    desc.base = base_val;
    desc.typeSuffix = typeSuffix;
    desc._padding = .{ 0, 0, 0, 0, 0, 0, 0 };

    return 0;
}

fn arrayDescriptorCheckBounds(desc: *const ArrayDescriptor, index: i64) bool {
    return desc.dimensions == 1 and
        index >= desc.lowerBound1 and
        index <= desc.upperBound1;
}

fn arrayDescriptorGetElementPtr(desc: *const ArrayDescriptor, index: i64) *anyopaque {
    const offset: usize = @intCast((index - desc.lowerBound1) * desc.elementSize);
    const base: [*]u8 = @ptrCast(desc.data.?);
    return @ptrCast(base + offset);
}

fn arrayDescriptorRedim(desc: *ArrayDescriptor, newLower: i64, newUpper: i64) i32 {
    if (newUpper < newLower) return -1;

    if (desc.data) |ptr| {
        c.free(ptr);
        desc.data = null;
    }

    const newCount = newUpper - newLower + 1;
    const totalSize: usize = @intCast(newCount * desc.elementSize);

    const ptr = c.malloc(totalSize) orelse {
        desc.lowerBound1 = 0;
        desc.upperBound1 = -1;
        return -1;
    };
    @memset(@as([*]u8, @ptrCast(ptr))[0..totalSize], 0);

    desc.data = ptr;
    desc.lowerBound1 = newLower;
    desc.upperBound1 = newUpper;
    desc.lowerBound2 = 0;
    desc.upperBound2 = 0;
    desc.dimensions = 1;

    return 0;
}

fn arrayDescriptorRedimPreserve(desc: *ArrayDescriptor, newLower: i64, newUpper: i64) i32 {
    if (newUpper < newLower) return -1;

    const oldCount = desc.upperBound1 - desc.lowerBound1 + 1;
    const newCount = newUpper - newLower + 1;
    const oldSize: usize = @intCast(oldCount * desc.elementSize);
    const newSize: usize = @intCast(newCount * desc.elementSize);

    const newData = c.realloc(desc.data, newSize) orelse return -1;
    desc.data = newData;

    // Zero-fill new area if growing
    if (newSize > oldSize) {
        const base: [*]u8 = @ptrCast(newData);
        @memset(base[oldSize..newSize], 0);
    }

    desc.lowerBound1 = newLower;
    desc.upperBound1 = newUpper;

    return 0;
}

// =========================================================================
// Exported bridge functions
// =========================================================================

export fn fbc_array_create(
    ndims: i32,
    desc: ?*ArrayDescriptor,
    upper_bound: i32,
    elem_size: i32,
) callconv(.c) void {
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: fbc_array_create called with NULL descriptor\n");
        exit(1);
    };

    // Zero the descriptor first
    const raw: *[64]u8 = @ptrCast(d);
    @memset(raw, 0);

    var rc: i32 = undefined;
    _ = ndims; // Currently only 1D emitted by codegen
    rc = arrayDescriptorInit(d, 0, @intCast(upper_bound), @intCast(elem_size), 0, 0);

    if (rc != 0) {
        _ = fprintf(__stderrp, "ERROR: fbc_array_create failed (upper=%d, elem_size=%d)\n", upper_bound, elem_size);
        exit(1);
    }
}

export fn fbc_array_bounds_check(desc: ?*ArrayDescriptor, index: i32) callconv(.c) void {
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: array bounds check on NULL descriptor\n");
        exit(1);
    };

    if (d.data == null) {
        _ = fprintf(__stderrp, "ERROR: array not initialised (DIM not executed?)\n");
        exit(1);
    }

    if (!arrayDescriptorCheckBounds(d, @intCast(index))) {
        _ = fprintf(__stderrp, "ERROR: array index %d out of bounds [%lld..%lld]\n", index, d.lowerBound1, d.upperBound1);
        exit(1);
    }
}

export fn fbc_array_element_addr(desc: ?*ArrayDescriptor, index: i32) callconv(.c) ?*anyopaque {
    const d = desc orelse return null;
    return arrayDescriptorGetElementPtr(d, @intCast(index));
}

// =========================================================================
// 2D array bridge functions
// =========================================================================

fn arrayDescriptorInit2D(
    desc: *ArrayDescriptor,
    lowerBound1: i64,
    upperBound1: i64,
    lowerBound2: i64,
    upperBound2: i64,
    elementSize: i64,
    base_val: i32,
    typeSuffix: u8,
) i32 {
    if (upperBound1 < lowerBound1 or upperBound2 < lowerBound2 or elementSize <= 0) return -1;

    const count1 = upperBound1 - lowerBound1 + 1;
    const count2 = upperBound2 - lowerBound2 + 1;
    const totalCount = count1 * count2;
    const totalSize: usize = @intCast(totalCount * elementSize);

    const ptr = c.malloc(totalSize) orelse return -1;
    @memset(@as([*]u8, @ptrCast(ptr))[0..totalSize], 0);

    desc.data = ptr;
    desc.lowerBound1 = lowerBound1;
    desc.upperBound1 = upperBound1;
    desc.lowerBound2 = lowerBound2;
    desc.upperBound2 = upperBound2;
    desc.elementSize = elementSize;
    desc.dimensions = 2;
    desc.base = base_val;
    desc.typeSuffix = typeSuffix;
    desc._padding = .{ 0, 0, 0, 0, 0, 0, 0 };

    return 0;
}

fn arrayDescriptorCheckBounds2D(desc: *const ArrayDescriptor, index1: i64, index2: i64) bool {
    return desc.dimensions == 2 and
        index1 >= desc.lowerBound1 and index1 <= desc.upperBound1 and
        index2 >= desc.lowerBound2 and index2 <= desc.upperBound2;
}

fn arrayDescriptorGetElementPtr2D(desc: *const ArrayDescriptor, index1: i64, index2: i64) *anyopaque {
    const dim2_size = desc.upperBound2 - desc.lowerBound2 + 1;
    const offset: usize = @intCast(((index1 - desc.lowerBound1) * dim2_size + (index2 - desc.lowerBound2)) * desc.elementSize);
    const base: [*]u8 = @ptrCast(desc.data.?);
    return @ptrCast(base + offset);
}

export fn fbc_array_create_2d(
    ndims: i32,
    desc: ?*ArrayDescriptor,
    upper_bound1: i32,
    upper_bound2: i32,
    elem_size: i32,
) callconv(.c) void {
    _ = ndims;
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: fbc_array_create_2d called with NULL descriptor\n");
        exit(1);
    };

    // Zero the descriptor first
    const raw: *[64]u8 = @ptrCast(d);
    @memset(raw, 0);

    const rc = arrayDescriptorInit2D(d, 0, @intCast(upper_bound1), 0, @intCast(upper_bound2), @intCast(elem_size), 0, 0);

    if (rc != 0) {
        _ = fprintf(__stderrp, "ERROR: fbc_array_create_2d failed (upper1=%d, upper2=%d, elem_size=%d)\n", upper_bound1, upper_bound2, elem_size);
        exit(1);
    }
}

export fn fbc_array_bounds_check_2d(desc: ?*ArrayDescriptor, index1: i32, index2: i32) callconv(.c) void {
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: 2D array bounds check on NULL descriptor\n");
        exit(1);
    };

    if (d.data == null) {
        _ = fprintf(__stderrp, "ERROR: 2D array not initialised (DIM not executed?)\n");
        exit(1);
    }

    if (!arrayDescriptorCheckBounds2D(d, @intCast(index1), @intCast(index2))) {
        _ = fprintf(__stderrp, "ERROR: 2D array index (%d, %d) out of bounds [%lld..%lld, %lld..%lld]\n", index1, index2, d.lowerBound1, d.upperBound1, d.lowerBound2, d.upperBound2);
        exit(1);
    }
}

export fn fbc_array_element_addr_2d(desc: ?*ArrayDescriptor, index1: i32, index2: i32) callconv(.c) ?*anyopaque {
    const d = desc orelse return null;
    return arrayDescriptorGetElementPtr2D(d, @intCast(index1), @intCast(index2));
}

export fn fbc_array_redim(desc: ?*ArrayDescriptor, new_upper: i32) callconv(.c) void {
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: fbc_array_redim called with NULL descriptor\n");
        exit(1);
    };

    const rc = arrayDescriptorRedim(d, 0, @intCast(new_upper));
    if (rc != 0) {
        _ = fprintf(__stderrp, "ERROR: fbc_array_redim failed (new_upper=%d)\n", new_upper);
        exit(1);
    }
}

export fn fbc_array_redim_preserve(desc: ?*ArrayDescriptor, new_upper: i32) callconv(.c) void {
    const d = desc orelse {
        _ = fprintf(__stderrp, "ERROR: fbc_array_redim_preserve called with NULL descriptor\n");
        exit(1);
    };

    const rc = arrayDescriptorRedimPreserve(d, 0, @intCast(new_upper));
    if (rc != 0) {
        _ = fprintf(__stderrp, "ERROR: fbc_array_redim_preserve failed (new_upper=%d)\n", new_upper);
        exit(1);
    }
}

export fn fbc_array_erase(desc: ?*ArrayDescriptor) callconv(.c) void {
    if (desc) |d| {
        array_descriptor_erase(d);
    }
}

export fn fbc_array_lbound(desc: ?*ArrayDescriptor) callconv(.c) i32 {
    const d = desc orelse return 0;
    return @intCast(d.lowerBound1);
}

export fn fbc_array_ubound(desc: ?*ArrayDescriptor) callconv(.c) i32 {
    const d = desc orelse return -1;
    return @intCast(d.upperBound1);
}
