// conversion_ops.zig
// FasterBASIC Runtime — Type Conversion Operations (Zig port)
//
// Implements conversions between different data types:
//   int/long/float/double → string
//   string → int/long/float/double
//
// Replaces conversion_ops.c — all exported symbols maintain C ABI compatibility.

const std = @import("std");

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
    extern fn atoi(s: [*:0]const u8) c_int;
    extern fn atoll(s: [*:0]const u8) c_longlong;
    extern fn atof(s: [*:0]const u8) f64;
};

// =========================================================================
// External runtime functions
// =========================================================================

// BasicString type — opaque from our perspective, we just pass pointers.
// The actual struct is: { data: *u8, length: usize, capacity: usize, refcount: i32 }
const BasicString = anyopaque;

extern fn str_new(cstr: [*:0]const u8) ?*BasicString;

// =========================================================================
// Number → String conversions
// =========================================================================

export fn int_to_str(value: i32) ?*BasicString {
    var buffer: [32]u8 = undefined;
    _ = c.snprintf(&buffer, buffer.len, "%d", value);
    return str_new(@ptrCast(&buffer));
}

export fn long_to_str(value: i64) ?*BasicString {
    var buffer: [32]u8 = undefined;
    _ = c.snprintf(&buffer, buffer.len, "%lld", @as(c_longlong, value));
    return str_new(@ptrCast(&buffer));
}

export fn float_to_str(value: f32) ?*BasicString {
    if (std.math.isNan(value)) {
        return str_new("NaN");
    }
    if (std.math.isInf(value)) {
        return str_new(if (value > 0) "Infinity" else "-Infinity");
    }
    var buffer: [64]u8 = undefined;
    // Promote to f64 for the variadic call (C promotes float to double)
    _ = c.snprintf(&buffer, buffer.len, "%g", @as(f64, value));
    return str_new(@ptrCast(&buffer));
}

export fn double_to_str(value: f64) ?*BasicString {
    if (std.math.isNan(value)) {
        return str_new("NaN");
    }
    if (std.math.isInf(value)) {
        return str_new(if (value > 0) "Infinity" else "-Infinity");
    }
    var buffer: [64]u8 = undefined;
    _ = c.snprintf(&buffer, buffer.len, "%g", value);
    return str_new(@ptrCast(&buffer));
}

// =========================================================================
// String → Number conversions
// =========================================================================

// BasicString layout offsets (matches C struct):
//   offset 0:  data pointer (8 bytes)
//   offset 8:  length (8 bytes)
//   offset 16: capacity (8 bytes)
//   offset 24: refcount (4 bytes)

fn getStringData(str: *const anyopaque) ?[*:0]const u8 {
    // Read the data pointer from offset 0
    const data_ptr: *const ?[*:0]const u8 = @ptrCast(@alignCast(str));
    return data_ptr.*;
}

fn getStringLength(str: *const anyopaque) usize {
    // Read length from offset 8
    const base: [*]const u8 = @ptrCast(str);
    const len_ptr: *const usize = @ptrCast(@alignCast(base + 8));
    return len_ptr.*;
}

/// Skip leading whitespace and return a pointer suitable for atoi/atof.
fn skipWhitespace(data: [*:0]const u8) [*:0]const u8 {
    var p = data;
    while (p[0] == ' ' or p[0] == '\t') {
        p += 1;
    }
    return p;
}

export fn str_to_int(str: ?*const BasicString) i32 {
    const s = str orelse return 0;
    if (getStringLength(s) == 0) return 0;
    const data = getStringData(s) orelse return 0;
    return @intCast(c.atoi(skipWhitespace(data)));
}

export fn str_to_long(str: ?*const BasicString) i64 {
    const s = str orelse return 0;
    if (getStringLength(s) == 0) return 0;
    const data = getStringData(s) orelse return 0;
    return @intCast(c.atoll(skipWhitespace(data)));
}

export fn str_to_float(str: ?*const BasicString) f32 {
    const s = str orelse return 0.0;
    if (getStringLength(s) == 0) return 0.0;
    const data = getStringData(s) orelse return 0.0;
    return @floatCast(c.atof(skipWhitespace(data)));
}

export fn str_to_double(str: ?*const BasicString) f64 {
    const s = str orelse return 0.0;
    if (getStringLength(s) == 0) return 0.0;
    const data = getStringData(s) orelse return 0.0;
    return c.atof(skipWhitespace(data));
}

// =========================================================================
// Unit tests
// =========================================================================

test "skipWhitespace skips spaces and tabs" {
    const input: [*:0]const u8 = "  \t42";
    const result = skipWhitespace(input);
    try std.testing.expectEqual(@as(u8, '4'), result[0]);
}
