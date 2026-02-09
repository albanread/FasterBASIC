//
// array_descriptor_runtime.zig
// FasterBASIC Runtime — Array Descriptor ERASE / DESTROY helpers
//
// Provides erase helpers that release string elements before freeing data.
// These are the non-inline runtime helpers declared in array_descriptor.h.
//

const c = @import("std").c;

// =========================================================================
// Extern declarations
// =========================================================================

extern fn string_release(str: ?*anyopaque) void;

// =========================================================================
// ArrayDescriptor layout — must match array_descriptor.h (64 bytes)
// =========================================================================

pub const ArrayDescriptor = extern struct {
    data: ?*anyopaque, // Pointer to array data
    lowerBound1: i64, // Lower index bound for dimension 1
    upperBound1: i64, // Upper index bound for dimension 1
    lowerBound2: i64, // Lower index bound for dimension 2 (0 if 1D)
    upperBound2: i64, // Upper index bound for dimension 2 (0 if 1D)
    elementSize: i64, // Size per element in bytes
    dimensions: i32, // Number of dimensions (1 or 2)
    base: i32, // OPTION BASE (0 or 1)
    typeSuffix: u8, // BASIC type suffix ('$', '%', etc.) or 0
    _padding: [7]u8, // Padding for alignment
};

// =========================================================================
// Exported functions
// =========================================================================

/// Erase array contents: release string elements (if '$' type), free data
export fn array_descriptor_erase(desc: ?*ArrayDescriptor) callconv(.c) void {
    const d = desc orelse return;

    // Release string elements if this is a string array
    if (d.data != null and d.typeSuffix == '$') {
        var count: i64 = undefined;
        if (d.dimensions == 2) {
            const count1 = d.upperBound1 - d.lowerBound1 + 1;
            const count2 = d.upperBound2 - d.lowerBound2 + 1;
            count = count1 * count2;
        } else {
            count = d.upperBound1 - d.lowerBound1 + 1;
        }

        if (count > 0) {
            // data is an array of pointers (StringDescriptor*)
            const elems: [*]?*anyopaque = @ptrCast(@alignCast(d.data.?));
            var i: i64 = 0;
            while (i < count) : (i += 1) {
                const idx: usize = @intCast(i);
                if (elems[idx] != null) {
                    string_release(elems[idx]);
                }
            }
        }
    }

    if (d.data) |ptr| {
        c.free(ptr);
        d.data = null;
    }

    // Mark empty
    d.lowerBound1 = 0;
    d.upperBound1 = -1;
    d.lowerBound2 = 0;
    d.upperBound2 = -1;
    d.dimensions = 0;
}

/// Fully destroy a descriptor: erase contents and free descriptor itself
export fn array_descriptor_destroy(desc: ?*ArrayDescriptor) callconv(.c) void {
    const d = desc orelse return;
    array_descriptor_erase(d);
    c.free(d);
}
