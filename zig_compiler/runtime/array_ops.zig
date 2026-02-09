//
// array_ops.zig
// FasterBASIC Runtime — Dynamic Array Operations
//
// Multi-dimensional array management with bounds checking.
// Supports OPTION BASE 0/1, typed get/set, REDIM PRESERVE,
// ERASE, NEON vectorisation helpers, and convenience wrappers.
//

const std = @import("std");
const c = std.c;

// =========================================================================
// Extern declarations
// =========================================================================

extern fn basic_error_msg(msg: [*:0]const u8) void;
extern fn string_retain(desc: ?*anyopaque) ?*anyopaque;
extern fn string_release(desc: ?*anyopaque) void;
extern fn string_new_capacity(cap: i64) ?*anyopaque;
extern fn samm_untrack(ptr: ?*anyopaque) void;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;

// =========================================================================
// Types matching basic_runtime.h
// =========================================================================

pub const BasicArray = extern struct {
    data: ?*anyopaque,
    element_size: usize,
    dimensions: i32,
    bounds: ?[*]i32,
    strides: ?[*]i32,
    base: i32,
    type_suffix: u8,
};

// =========================================================================
// Array Creation
// =========================================================================

export fn array_new(type_suffix_raw: u8, dimensions: i32, bounds: ?[*]i32, base: i32) callconv(.c) ?*BasicArray {
    if (dimensions <= 0 or dimensions > 8) {
        basic_error_msg("Invalid array dimensions");
        return null;
    }

    const bnd = bounds orelse {
        basic_error_msg("Array bounds not specified");
        return null;
    };

    const raw = c.malloc(@sizeOf(BasicArray)) orelse {
        basic_error_msg("Out of memory (array allocation)");
        return null;
    };
    const array: *BasicArray = @ptrCast(@alignCast(raw));

    array.dimensions = dimensions;
    array.base = base;
    var ts = type_suffix_raw;

    // Determine element size based on type suffix
    const element_size: usize = switch (ts) {
        'b' => 1, // BYTE
        'h' => 2, // SHORT
        '%' => @sizeOf(i32), // INTEGER
        '&' => @sizeOf(i64), // LONG
        '!' => @sizeOf(f32), // SINGLE
        '#' => @sizeOf(f64), // DOUBLE
        '$' => @sizeOf(?*anyopaque), // STRING (StringDescriptor*)
        else => blk: {
            ts = '#';
            break :blk @sizeOf(f64);
        },
    };
    array.type_suffix = ts;
    array.element_size = element_size;

    const dims_u: usize = @intCast(dimensions);

    // Allocate bounds: [lower1, upper1, lower2, upper2, ...]
    const bounds_bytes = dims_u * 2 * @sizeOf(i32);
    const bounds_raw = c.malloc(bounds_bytes) orelse {
        c.free(raw);
        basic_error_msg("Out of memory (array bounds)");
        return null;
    };
    const bounds_ptr: [*]i32 = @ptrCast(@alignCast(bounds_raw));
    @memcpy(bounds_ptr[0 .. dims_u * 2], bnd[0 .. dims_u * 2]);
    array.bounds = bounds_ptr;

    // Allocate strides
    const strides_raw = c.malloc(dims_u * @sizeOf(i32)) orelse {
        c.free(bounds_raw);
        c.free(raw);
        basic_error_msg("Out of memory (array strides)");
        return null;
    };
    const strides_ptr: [*]i32 = @ptrCast(@alignCast(strides_raw));
    array.strides = strides_ptr;

    // Calculate total elements and strides (last dimension → first)
    var total_elements: usize = 1;
    {
        var i: i32 = dimensions - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            const lower = bnd[idx * 2];
            const upper = bnd[idx * 2 + 1];
            const dim_size = upper - lower + 1;

            if (dim_size <= 0) {
                c.free(strides_raw);
                c.free(bounds_raw);
                c.free(raw);
                basic_error_msg("Invalid array bounds");
                return null;
            }

            strides_ptr[idx] = @intCast(total_elements);
            total_elements *= @intCast(dim_size);

            if (i == 0) break;
        }
    }

    // Allocate data (zeroed)
    const data_size = total_elements * element_size;
    const data_raw = c.malloc(data_size) orelse {
        c.free(strides_raw);
        c.free(bounds_raw);
        c.free(raw);
        basic_error_msg("Out of memory (array data)");
        return null;
    };
    const data_slice: [*]u8 = @ptrCast(data_raw);
    @memset(data_slice[0..data_size], 0);
    array.data = data_raw;

    return array;
}

/// Create array with custom element size (for UDTs)
export fn array_new_custom(element_size: usize, dimensions: i32, bounds: ?[*]i32, base: i32) callconv(.c) ?*BasicArray {
    if (dimensions <= 0 or dimensions > 8) {
        basic_error_msg("Invalid array dimensions");
        return null;
    }

    const bnd = bounds orelse {
        basic_error_msg("Array bounds not specified");
        return null;
    };

    if (element_size == 0) {
        basic_error_msg("Invalid element size");
        return null;
    }

    const raw = c.malloc(@sizeOf(BasicArray)) orelse {
        basic_error_msg("Out of memory (array allocation)");
        return null;
    };
    const array: *BasicArray = @ptrCast(@alignCast(raw));

    array.dimensions = dimensions;
    array.base = base;
    array.type_suffix = 'U'; // UDT marker
    array.element_size = element_size;

    const dims_u: usize = @intCast(dimensions);

    // Allocate bounds
    const bounds_bytes = dims_u * 2 * @sizeOf(i32);
    const bounds_raw = c.malloc(bounds_bytes) orelse {
        c.free(raw);
        basic_error_msg("Out of memory (array bounds)");
        return null;
    };
    const bounds_ptr: [*]i32 = @ptrCast(@alignCast(bounds_raw));
    @memcpy(bounds_ptr[0 .. dims_u * 2], bnd[0 .. dims_u * 2]);
    array.bounds = bounds_ptr;

    // Allocate strides
    const strides_raw = c.malloc(dims_u * @sizeOf(i32)) orelse {
        c.free(bounds_raw);
        c.free(raw);
        basic_error_msg("Out of memory (array strides)");
        return null;
    };
    const strides_ptr: [*]i32 = @ptrCast(@alignCast(strides_raw));
    array.strides = strides_ptr;

    // Calculate total elements and strides
    var total_elements: usize = 1;
    {
        var i: i32 = dimensions - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            const lower = bnd[idx * 2];
            const upper = bnd[idx * 2 + 1];
            const dim_size = upper - lower + 1;

            if (dim_size <= 0) {
                c.free(strides_raw);
                c.free(bounds_raw);
                c.free(raw);
                basic_error_msg("Invalid array bounds");
                return null;
            }

            strides_ptr[idx] = @intCast(total_elements);
            total_elements *= @intCast(dim_size);

            if (i == 0) break;
        }
    }

    // Allocate data (zeroed)
    const data_size = total_elements * element_size;
    const data_raw = c.malloc(data_size) orelse {
        c.free(strides_raw);
        c.free(bounds_raw);
        c.free(raw);
        basic_error_msg("Out of memory (array data)");
        return null;
    };
    const data_slice: [*]u8 = @ptrCast(data_raw);
    @memset(data_slice[0..data_size], 0);
    array.data = data_raw;

    return array;
}

// =========================================================================
// Array Destruction
// =========================================================================

export fn array_free(array: ?*BasicArray) callconv(.c) void {
    const arr = array orelse return;

    // If string array, release all strings
    if (arr.type_suffix == '$') {
        if (arr.data) |data| {
            const total = totalElements(arr);
            const strings: [*]?*anyopaque = @ptrCast(@alignCast(data));
            for (0..total) |i| {
                if (strings[i]) |s| {
                    string_release(s);
                }
            }
        }
    }

    if (arr.data) |d| c.free(d);
    if (arr.bounds) |b| c.free(b);
    if (arr.strides) |s| c.free(s);
    c.free(arr);
}

// =========================================================================
// Index Calculation (internal)
// =========================================================================

fn calculateOffset(array: *BasicArray, indices: [*]i32) usize {
    const bnd = array.bounds orelse return 0;
    const strides = array.strides orelse return 0;
    var offset: usize = 0;
    const dims_u: usize = @intCast(array.dimensions);

    for (0..dims_u) |i| {
        const lower = bnd[i * 2];
        const upper = bnd[i * 2 + 1];
        const index = indices[i];

        if (index < lower or index > upper) {
            var msg: [256]u8 = undefined;
            _ = snprintf(&msg, msg.len, "Array subscript out of range (dimension %d: %d not in [%d, %d])", @as(i32, @intCast(i)) + 1, index, lower, upper);
            basic_error_msg(@ptrCast(&msg));
            return 0;
        }

        offset += @intCast(@as(i64, index - lower) * @as(i64, strides[i]));
    }

    return offset;
}

/// Helper: count total elements in array
fn totalElements(arr: *BasicArray) usize {
    const bnd = arr.bounds orelse return 0;
    const dims_u: usize = @intCast(arr.dimensions);
    var total: usize = 1;
    for (0..dims_u) |i| {
        const lower = bnd[i * 2];
        const upper = bnd[i * 2 + 1];
        const dim_size: usize = @intCast(upper - lower + 1);
        total *= dim_size;
    }
    return total;
}

// =========================================================================
// Get Element Address
// =========================================================================

export fn array_get_address(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) ?*anyopaque {
    const arr = array orelse return null;
    const idx = indices orelse return null;

    const offset = calculateOffset(arr, idx);
    const data: [*]u8 = @ptrCast(arr.data orelse return null);
    return @ptrCast(data + offset * arr.element_size);
}

// =========================================================================
// Integer Array Operations
// =========================================================================

export fn array_get_int(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) i32 {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array access");
        return 0;
    };
    if (arr.type_suffix != '%') {
        basic_error_msg("Type mismatch in array access");
        return 0;
    }
    const idx = indices orelse return 0;

    const offset = calculateOffset(arr, idx);
    const data: [*]i32 = @ptrCast(@alignCast(arr.data orelse return 0));
    return data[offset];
}

export fn array_set_int(array: ?*BasicArray, indices: ?[*]i32, value: i32) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array assignment");
        return;
    };
    if (arr.type_suffix != '%') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    const idx = indices orelse return;

    const offset = calculateOffset(arr, idx);
    const data: [*]i32 = @ptrCast(@alignCast(arr.data orelse return));
    data[offset] = value;
}

// =========================================================================
// Long Array Operations
// =========================================================================

export fn array_get_long(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) i64 {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array access");
        return 0;
    };
    if (arr.type_suffix != '&') {
        basic_error_msg("Type mismatch in array access");
        return 0;
    }
    const idx = indices orelse return 0;

    const offset = calculateOffset(arr, idx);
    const data: [*]i64 = @ptrCast(@alignCast(arr.data orelse return 0));
    return data[offset];
}

export fn array_set_long(array: ?*BasicArray, indices: ?[*]i32, value: i64) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array assignment");
        return;
    };
    if (arr.type_suffix != '&') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    const idx = indices orelse return;

    const offset = calculateOffset(arr, idx);
    const data: [*]i64 = @ptrCast(@alignCast(arr.data orelse return));
    data[offset] = value;
}

// =========================================================================
// Float Array Operations
// =========================================================================

export fn array_get_float(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) f32 {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array access");
        return 0.0;
    };
    if (arr.type_suffix != '!') {
        basic_error_msg("Type mismatch in array access");
        return 0.0;
    }
    const idx = indices orelse return 0.0;

    const offset = calculateOffset(arr, idx);
    const data: [*]f32 = @ptrCast(@alignCast(arr.data orelse return 0.0));
    return data[offset];
}

export fn array_set_float(array: ?*BasicArray, indices: ?[*]i32, value: f32) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array assignment");
        return;
    };
    if (arr.type_suffix != '!') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    const idx = indices orelse return;

    const offset = calculateOffset(arr, idx);
    const data: [*]f32 = @ptrCast(@alignCast(arr.data orelse return));
    data[offset] = value;
}

// =========================================================================
// Double Array Operations
// =========================================================================

export fn array_get_double(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) f64 {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array access");
        return 0.0;
    };
    if (arr.type_suffix != '#') {
        basic_error_msg("Type mismatch in array access");
        return 0.0;
    }
    const idx = indices orelse return 0.0;

    const offset = calculateOffset(arr, idx);
    const data: [*]f64 = @ptrCast(@alignCast(arr.data orelse return 0.0));
    return data[offset];
}

export fn array_set_double(array: ?*BasicArray, indices: ?[*]i32, value: f64) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array assignment");
        return;
    };
    if (arr.type_suffix != '#') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    const idx = indices orelse return;

    const offset = calculateOffset(arr, idx);
    const data: [*]f64 = @ptrCast(@alignCast(arr.data orelse return));
    data[offset] = value;
}

// =========================================================================
// String Array Operations
// =========================================================================

export fn array_get_string(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) ?*anyopaque {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array access");
        return string_new_capacity(0);
    };
    if (arr.type_suffix != '$') {
        basic_error_msg("Type mismatch in array access");
        return string_new_capacity(0);
    }
    const idx = indices orelse return string_new_capacity(0);

    const offset = calculateOffset(arr, idx);
    const data: [*]?*anyopaque = @ptrCast(@alignCast(arr.data orelse return string_new_capacity(0)));
    return string_retain(data[offset]);
}

export fn array_set_string(array: ?*BasicArray, indices: ?[*]i32, value: ?*anyopaque) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Type mismatch in array assignment");
        return;
    };
    if (arr.type_suffix != '$') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    const idx = indices orelse return;

    const offset = calculateOffset(arr, idx);
    const data: [*]?*anyopaque = @ptrCast(@alignCast(arr.data orelse return));

    if (data[offset]) |old| {
        string_release(old);
    }

    data[offset] = string_retain(value);
}

// =========================================================================
// Array Bounds Inquiry
// =========================================================================

export fn array_lbound(array: ?*BasicArray, dimension: i32) callconv(.c) i32 {
    const arr = array orelse {
        basic_error_msg("Invalid dimension in LBOUND");
        return 0;
    };
    if (dimension < 1 or dimension > arr.dimensions) {
        basic_error_msg("Invalid dimension in LBOUND");
        return 0;
    }
    const bnd = arr.bounds orelse return 0;
    return bnd[@intCast((dimension - 1) * 2)];
}

export fn array_ubound(array: ?*BasicArray, dimension: i32) callconv(.c) i32 {
    const arr = array orelse {
        basic_error_msg("Invalid dimension in UBOUND");
        return 0;
    };
    if (dimension < 1 or dimension > arr.dimensions) {
        basic_error_msg("Invalid dimension in UBOUND");
        return 0;
    }
    const bnd = arr.bounds orelse return 0;
    return bnd[@intCast((dimension - 1) * 2 + 1)];
}

// =========================================================================
// Array Redimension
// =========================================================================

export fn array_redim(array: ?*BasicArray, new_bounds: ?[*]i32, preserve: bool) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("Invalid REDIM parameters");
        return;
    };
    const nb = new_bounds orelse {
        basic_error_msg("Invalid REDIM parameters");
        return;
    };
    const bnd = arr.bounds orelse {
        basic_error_msg("Invalid REDIM parameters");
        return;
    };
    const strides = arr.strides orelse {
        basic_error_msg("Invalid REDIM parameters");
        return;
    };

    const dims_u: usize = @intCast(arr.dimensions);

    // Save old state if preserving
    var old_data: ?*anyopaque = null;
    var old_bounds: ?[*]i32 = null;
    var old_strides: ?[*]i32 = null;

    if (preserve and arr.data != null) {
        old_data = arr.data;

        const ob_raw = c.malloc(dims_u * 2 * @sizeOf(i32));
        const os_raw = c.malloc(dims_u * @sizeOf(i32));
        if (ob_raw == null or os_raw == null) {
            if (ob_raw) |p| c.free(p);
            if (os_raw) |p| c.free(p);
            basic_error_msg("Out of memory (REDIM PRESERVE)");
            return;
        }
        const ob: [*]i32 = @ptrCast(@alignCast(ob_raw.?));
        const os: [*]i32 = @ptrCast(@alignCast(os_raw.?));
        @memcpy(ob[0 .. dims_u * 2], bnd[0 .. dims_u * 2]);
        @memcpy(os[0..dims_u], strides[0..dims_u]);
        old_bounds = ob;
        old_strides = os;
    } else {
        // Not preserving — free old data
        if (arr.data) |data| {
            if (arr.type_suffix == '$') {
                const total = totalElements(arr);
                const strings: [*]?*anyopaque = @ptrCast(@alignCast(data));
                for (0..total) |i| {
                    if (strings[i]) |s| {
                        samm_untrack(s);
                        string_release(s);
                    }
                }
            }
            c.free(data);
            arr.data = null;
        }
    }

    // Update bounds
    @memcpy(bnd[0 .. dims_u * 2], nb[0 .. dims_u * 2]);

    // Recalculate strides and total size
    var new_total: usize = 1;
    {
        var i: i32 = arr.dimensions - 1;
        while (i >= 0) : (i -= 1) {
            const idx: usize = @intCast(i);
            const lower = nb[idx * 2];
            const upper = nb[idx * 2 + 1];
            const dim_size = upper - lower + 1;

            if (dim_size <= 0) {
                if (old_bounds) |ob| c.free(ob);
                if (old_strides) |os| c.free(os);
                if (old_data) |od| c.free(od);
                basic_error_msg("Invalid array bounds in REDIM");
                return;
            }

            strides[idx] = @intCast(new_total);
            new_total *= @intCast(dim_size);

            if (i == 0) break;
        }
    }

    // Allocate new data
    const new_data_size = new_total * arr.element_size;
    const new_data_raw = c.malloc(new_data_size) orelse {
        if (old_bounds) |ob| c.free(ob);
        if (old_strides) |os| c.free(os);
        if (old_data) |od| {
            arr.data = od; // Restore
        }
        basic_error_msg("Out of memory (REDIM)");
        return;
    };
    const nd_slice: [*]u8 = @ptrCast(new_data_raw);
    @memset(nd_slice[0..new_data_size], 0);

    // If preserving, copy overlapping elements
    if (preserve and old_data != null) {
        const od = old_data.?;
        const ob = old_bounds.?;
        const os = old_strides.?;

        if (arr.dimensions == 1) {
            // 1D — simple linear copy
            const old_lower = ob[0];
            const old_upper = ob[1];
            const new_lower = nb[0];
            const new_upper = nb[1];

            const start = if (old_lower > new_lower) old_lower else new_lower;
            const end = if (old_upper < new_upper) old_upper else new_upper;

            var idx = start;
            while (idx <= end) : (idx += 1) {
                const old_offset: usize = @intCast(@as(i64, idx - old_lower) * @as(i64, os[0]));
                const new_offset: usize = @intCast(@as(i64, idx - new_lower) * @as(i64, strides[0]));

                const old_byte: usize = old_offset * arr.element_size;
                const new_byte: usize = new_offset * arr.element_size;

                const old_ptr: [*]u8 = @ptrCast(od);
                const new_ptr: [*]u8 = @ptrCast(new_data_raw);

                if (arr.type_suffix == '$') {
                    const old_str: *?*anyopaque = @ptrCast(@alignCast(old_ptr + old_byte));
                    const new_str: *?*anyopaque = @ptrCast(@alignCast(new_ptr + new_byte));
                    if (old_str.*) |s| {
                        new_str.* = string_retain(s);
                    }
                } else {
                    @memcpy((new_ptr + new_byte)[0..arr.element_size], (old_ptr + old_byte)[0..arr.element_size]);
                }
            }
        } else {
            // Multi-dimensional — iterate through overlapping indices
            const overlap_start_raw = c.malloc(dims_u * @sizeOf(i32));
            const overlap_end_raw = c.malloc(dims_u * @sizeOf(i32));
            const current_idx_raw = c.malloc(dims_u * @sizeOf(i32));

            if (overlap_start_raw == null or overlap_end_raw == null or current_idx_raw == null) {
                if (overlap_start_raw) |p| c.free(p);
                if (overlap_end_raw) |p| c.free(p);
                if (current_idx_raw) |p| c.free(p);
                c.free(new_data_raw);
                c.free(od);
                c.free(ob);
                c.free(os);
                basic_error_msg("Out of memory (REDIM PRESERVE copy)");
                return;
            }

            const overlap_start: [*]i32 = @ptrCast(@alignCast(overlap_start_raw.?));
            const overlap_end: [*]i32 = @ptrCast(@alignCast(overlap_end_raw.?));
            const current_idx: [*]i32 = @ptrCast(@alignCast(current_idx_raw.?));

            for (0..dims_u) |d| {
                const old_lower = ob[d * 2];
                const old_upper = ob[d * 2 + 1];
                const new_lower = nb[d * 2];
                const new_upper = nb[d * 2 + 1];

                overlap_start[d] = if (old_lower > new_lower) old_lower else new_lower;
                overlap_end[d] = if (old_upper < new_upper) old_upper else new_upper;
                current_idx[d] = overlap_start[d];
            }

            // Iterate through all overlapping elements
            var done = false;
            while (!done) {
                // Calculate offsets
                var old_offset: usize = 0;
                var new_offset: usize = 0;
                for (0..dims_u) |d| {
                    old_offset += @intCast(@as(i64, current_idx[d] - ob[d * 2]) * @as(i64, os[d]));
                    new_offset += @intCast(@as(i64, current_idx[d] - nb[d * 2]) * @as(i64, strides[d]));
                }

                // Copy element
                const old_byte = old_offset * arr.element_size;
                const new_byte = new_offset * arr.element_size;
                const old_ptr: [*]u8 = @ptrCast(od);
                const new_ptr: [*]u8 = @ptrCast(new_data_raw);

                if (arr.type_suffix == '$') {
                    const old_str: *?*anyopaque = @ptrCast(@alignCast(old_ptr + old_byte));
                    const new_str: *?*anyopaque = @ptrCast(@alignCast(new_ptr + new_byte));
                    if (old_str.*) |s| {
                        new_str.* = string_retain(s);
                    }
                } else {
                    @memcpy((new_ptr + new_byte)[0..arr.element_size], (old_ptr + old_byte)[0..arr.element_size]);
                }

                // Increment indices (rightmost dimension first)
                var d_idx: i32 = arr.dimensions - 1;
                while (d_idx >= 0) : (d_idx -= 1) {
                    const du: usize = @intCast(d_idx);
                    current_idx[du] += 1;
                    if (current_idx[du] <= overlap_end[du]) break;
                    current_idx[du] = overlap_start[du];
                    if (d_idx == 0) {
                        done = true;
                        break;
                    }
                }
                if (d_idx < 0) done = true;
            }

            c.free(overlap_start_raw.?);
            c.free(overlap_end_raw.?);
            c.free(current_idx_raw.?);
        }

        // Free old data — release strings (copied ones have increased refcount)
        if (arr.type_suffix == '$') {
            var old_total: usize = 1;
            for (0..dims_u) |i| {
                const lower = ob[i * 2];
                const upper = ob[i * 2 + 1];
                old_total *= @intCast(upper - lower + 1);
            }
            const strings: [*]?*anyopaque = @ptrCast(@alignCast(od));
            for (0..old_total) |i| {
                if (strings[i]) |s| {
                    samm_untrack(s);
                    string_release(s);
                }
            }
        }
        c.free(od);
        c.free(ob);
        c.free(os);
    }

    // Update array data pointer
    arr.data = new_data_raw;
}

// =========================================================================
// Bounds Checking
// =========================================================================

export fn basic_check_bounds(array: ?*BasicArray, indices: ?[*]i32) callconv(.c) void {
    const arr = array orelse return;
    const idx = indices orelse return;
    const bnd = arr.bounds orelse return;
    const dims_u: usize = @intCast(arr.dimensions);

    for (0..dims_u) |i| {
        const lower = bnd[i * 2];
        const upper = bnd[i * 2 + 1];
        const index = idx[i];

        if (index < lower or index > upper) {
            var msg: [256]u8 = undefined;
            _ = snprintf(&msg, msg.len, "Array subscript out of range (dimension %d: %d not in [%d, %d])", @as(i32, @intCast(i)) + 1, index, lower, upper);
            basic_error_msg(@ptrCast(&msg));
            return;
        }
    }
}

// =========================================================================
// Convenience Wrappers for Codegen
// =========================================================================

/// Simple array creation wrapper for codegen.
/// Creates a 1D array with default type (double '#').
/// Uses C varargs to accept dimension sizes.
export fn array_create(dimensions: i32, ...) callconv(.c) ?*BasicArray {
    if (dimensions <= 0 or dimensions > 8) {
        basic_error_msg("Invalid array dimensions in array_create");
        return null;
    }

    const dims_u: usize = @intCast(dimensions);

    // Allocate bounds on stack (max 8 dimensions)
    var bounds_buf: [16]i32 = undefined;

    var ap = @cVaStart();
    for (0..dims_u) |i| {
        const size: i32 = @cVaArg(&ap, i32);
        bounds_buf[i * 2] = 0; // Lower bound (OPTION BASE 0)
        bounds_buf[i * 2 + 1] = size; // Upper bound
    }
    @cVaEnd(&ap);

    return array_new('#', dimensions, &bounds_buf, 0);
}

// =========================================================================
// NEON Loop Vectorization Support
// =========================================================================

export fn array_get_data_ptr(array: ?*BasicArray) callconv(.c) ?*anyopaque {
    const arr = array orelse return null;
    return arr.data;
}

export fn array_get_element_size(array: ?*BasicArray) callconv(.c) usize {
    const arr = array orelse return 0;
    return arr.element_size;
}

/// Validate that a contiguous range [start_idx, end_idx] is within bounds
/// for dimension 0. Called once before a NEON-vectorized loop.
export fn array_check_range(array: ?*BasicArray, start_idx: i32, end_idx: i32) callconv(.c) void {
    const arr = array orelse {
        basic_error_msg("NEON loop: null array pointer");
        return;
    };
    if (arr.data == null) {
        basic_error_msg("NEON loop: array has no data (not allocated?)");
        return;
    }
    if (arr.dimensions < 1) {
        basic_error_msg("NEON loop: array has no dimensions");
        return;
    }
    const bnd = arr.bounds orelse return;
    const lower = bnd[0];
    const upper = bnd[1];
    if (start_idx < lower or end_idx > upper) {
        var msg: [256]u8 = undefined;
        _ = snprintf(&msg, msg.len, "NEON loop: array range [%d, %d] out of bounds [%d, %d]", start_idx, end_idx, lower, upper);
        basic_error_msg(@ptrCast(&msg));
    }
}

// =========================================================================
// Erase
// =========================================================================

export fn array_erase(array: ?*BasicArray) callconv(.c) void {
    const arr = array orelse return;

    if (arr.data) |data| {
        // Release strings (untrack from SAMM first)
        if (arr.type_suffix == '$') {
            const total = totalElements(arr);
            const strings: [*]?*anyopaque = @ptrCast(@alignCast(data));
            for (0..total) |i| {
                if (strings[i]) |s| {
                    samm_untrack(s);
                    string_release(s);
                }
            }
        }

        c.free(data);
        arr.data = null;
    }

    // Set bounds to indicate empty array (0, -1 → size 0)
    if (arr.bounds) |bnd| {
        const dims_u: usize = @intCast(arr.dimensions);
        for (0..dims_u) |i| {
            bnd[i * 2] = 0;
            bnd[i * 2 + 1] = -1;
        }
    }
}
