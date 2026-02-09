//
// basic_data.zig
// FasterBASIC Runtime — DATA/READ/RESTORE Support
//
// Runtime support for BASIC DATA, READ, and RESTORE statements.
// References compiler-generated symbols (__basic_data, __basic_data_types,
// __basic_data_ptr) which are emitted in the QBE IL.
//
// For programs without DATA statements, weak default symbols are provided.
//

const std = @import("std");

// =========================================================================
// Extern declarations
// =========================================================================

extern fn basic_throw(error_code: i32) void;

const ERR_ILLEGAL_CALL: i32 = 5;
const ERR_TYPE_MISMATCH: i32 = 13;

// =========================================================================
// DATA type tags (matching codegen)
// =========================================================================

const DATA_TYPE_INT: u8 = 0;
const DATA_TYPE_DOUBLE: u8 = 1;
const DATA_TYPE_STRING: u8 = 2;

// =========================================================================
// External DATA section references
//
// These symbols are defined in the generated QBE IL code.
// For programs without DATA statements, we provide weak defaults.
// =========================================================================

// Weak default symbols for programs without DATA statements.
// If the compiled program defines these, the linker picks those instead.
export var __basic_data: [1]i64 linksection("__DATA,__data") = .{0};
export var __basic_data_types: [1]u8 linksection("__DATA,__data") = .{0};
export var __basic_data_ptr: i64 = 0;

// =========================================================================
// READ Functions
// =========================================================================

/// Read an integer value from DATA
export fn basic_read_int() callconv(.c) i32 {
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }

    const idx: usize = @intCast(__basic_data_ptr);
    const data_type = __basic_data_types[idx];

    if (data_type != DATA_TYPE_INT) {
        basic_throw(ERR_TYPE_MISMATCH);
    }

    const value: i32 = @intCast(__basic_data[idx]);
    __basic_data_ptr += 1;

    return value;
}

/// Read a double value from DATA
export fn basic_read_double() callconv(.c) f64 {
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }

    const idx: usize = @intCast(__basic_data_ptr);
    const data_type = __basic_data_types[idx];

    if (data_type == DATA_TYPE_INT) {
        // Allow INT to be read as DOUBLE
        const value: i32 = @intCast(__basic_data[idx]);
        __basic_data_ptr += 1;
        return @floatFromInt(value);
    } else if (data_type == DATA_TYPE_DOUBLE) {
        // Reinterpret the bits as double
        const value: f64 = @bitCast(__basic_data[idx]);
        __basic_data_ptr += 1;
        return value;
    } else {
        basic_throw(ERR_TYPE_MISMATCH);
        unreachable;
    }
}

/// Read a string value from DATA
export fn basic_read_string() callconv(.c) ?[*:0]const u8 {
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }

    const idx: usize = @intCast(__basic_data_ptr);
    const data_type = __basic_data_types[idx];

    if (data_type != DATA_TYPE_STRING) {
        basic_throw(ERR_TYPE_MISMATCH);
    }

    // Read pointer value (stored as int64, reinterpret as pointer)
    const str: ?[*:0]const u8 = @ptrFromInt(@as(usize, @intCast(__basic_data[idx])));
    __basic_data_ptr += 1;

    return str;
}

// =========================================================================
// RESTORE Functions
// =========================================================================

/// Restore DATA pointer to a specific position
export fn basic_restore(index: i64) callconv(.c) void {
    __basic_data_ptr = index;
}

/// Restore DATA pointer to the beginning
export fn basic_restore_start() callconv(.c) void {
    __basic_data_ptr = 0;
}
