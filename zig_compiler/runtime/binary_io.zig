//! Binary file I/O operations and data conversion functions.
//!
//! Implements the classic BASIC binary file operations:
//! - MKI$, MKS$, MKD$ : Convert numbers to binary strings
//! - CVI, CVS, CVD    : Convert binary strings back to numbers
//! - INPUT$           : Read N bytes from a file
//! - LOC, LOF         : File position and length queries
//!
//! These functions are essential for Random and Binary file modes.

const std = @import("std");
const c = @cImport({
    @cInclude("stdio.h");
    @cInclude("stdlib.h");
    @cInclude("string.h");
    @cInclude("stdint.h");
});

// Import string operations for string creation
extern fn string_new_utf8(data: [*:0]const u8) ?*anyopaque;
extern fn string_new_ascii_len(data: ?*const anyopaque, length: i64) ?*anyopaque;
extern fn string_to_utf8(str: ?*anyopaque) [*:0]const u8;
extern fn basic_error_msg(msg: [*:0]const u8) void;
extern fn basic_throw(error_code: c_int) void;
extern fn file_get_handle(file_num: c_int) ?*anyopaque;

// StringDescriptor layout — must match string_utf32.zig (40 bytes).
// We only need this to access .data and .length for binary CV* functions
// so that we can read raw bytes without going through string_to_utf8
// (which uses strlen and breaks on binary data containing 0x00).
const STRING_ENCODING_ASCII: u8 = 0;

const StringDescriptor = extern struct {
    data: ?*anyopaque,
    length: i64,
    capacity: i64,
    refcount: i32,
    encoding: u8,
    dirty: u8,
    _padding: [2]u8,
    utf8_cache: ?[*]u8,
};

// BasicFile structure — must match io_ops.zig and basic_runtime.h field order.
const BasicFile = extern struct {
    fp: ?*anyopaque,
    file_number: c_int,
    filename: ?[*:0]u8,
    mode: ?[*:0]u8,
    is_open: bool,
    // Buffered reader fields (appended after legacy fields).
    read_buf: ?[*]u8,
    read_buf_size: usize,
    read_pos: usize,

    /// Cast the opaque fp to the C FILE* that libc functions expect.
    inline fn asFILE(self: *const BasicFile) ?[*c]c.FILE {
        const raw = self.fp orelse return null;
        return @ptrCast(@alignCast(raw));
    }
};

// ============================================================================
// MK* Functions: Convert numbers to binary string representation
// ============================================================================

/// MKI$ - Make Integer String (2 bytes, little-endian)
/// Converts a 16-bit integer to a 2-byte string
export fn basic_mki(value: c_int) callconv(.c) ?*anyopaque {
    var buffer: [2]u8 = undefined;
    const val16: i16 = @intCast(@as(i32, value) & 0xFFFF);

    // Little-endian encoding
    buffer[0] = @intCast(val16 & 0xFF);
    buffer[1] = @intCast((val16 >> 8) & 0xFF);

    return string_new_ascii_len(&buffer, 2);
}

/// MKS$ - Make Single String (4 bytes, IEEE 754 single precision)
/// Accepts f64 (the codegen always passes doubles) and truncates to f32
/// before extracting the 4-byte IEEE 754 representation.
export fn basic_mks(value: f64) callconv(.c) ?*anyopaque {
    const single: f32 = @floatCast(value);
    var buffer: [4]u8 = undefined;
    const bytes: *const [4]u8 = @ptrCast(&single);

    // Copy bytes (architecture-dependent endianness)
    @memcpy(&buffer, bytes);

    return string_new_ascii_len(&buffer, 4);
}

/// MKD$ - Make Double String (8 bytes, IEEE 754 double precision)
/// Converts a double to an 8-byte string
export fn basic_mkd(value: f64) callconv(.c) ?*anyopaque {
    var buffer: [8]u8 = undefined;
    const bytes: *const [8]u8 = @ptrCast(&value);

    // Copy bytes (architecture-dependent endianness)
    @memcpy(&buffer, bytes);

    return string_new_ascii_len(&buffer, 8);
}

// ============================================================================
// CV* Functions: Convert binary strings back to numbers
// ============================================================================

/// CVI - Convert binary string to Integer (16-bit)
/// Reads 2 bytes from string and converts to integer.
/// Accesses the StringDescriptor directly so binary data containing
/// 0x00 bytes is handled correctly (strlen would truncate).
export fn basic_cvi(str: ?*anyopaque) callconv(.c) c_int {
    if (str == null) {
        basic_throw(5);
        return 0;
    }
    const desc: *const StringDescriptor = @ptrCast(@alignCast(str.?));
    const slen: usize = if (desc.length > 0) @intCast(desc.length) else 0;
    if (slen < 2) {
        basic_throw(5);
        return 0;
    }

    var raw_ptr: [*]const u8 = undefined;
    var raw_len: usize = slen;
    if (desc.encoding == STRING_ENCODING_ASCII) {
        raw_ptr = @ptrCast(@alignCast(desc.data.?));
    } else {
        const u8p = string_to_utf8(str);
        raw_ptr = @ptrCast(u8p);
        raw_len = c.strlen(u8p);
        if (raw_len < 2) {
            basic_throw(5);
            return 0;
        }
    }

    // Little-endian decode
    const byte0: i32 = @intCast(raw_ptr[0]);
    const byte1: i32 = @intCast(raw_ptr[1]);
    var result: i32 = byte0 | (byte1 << 8);

    // Sign extend from 16-bit to 32-bit
    if ((result & 0x8000) != 0) {
        result |= @as(i32, @bitCast(@as(u32, 0xFFFF0000)));
    }

    return @intCast(result);
}

/// CVS - Convert binary string to Single precision float
/// Reads 4 bytes from string and converts to double (promoted from single).
/// Accesses the StringDescriptor directly for binary safety.
export fn basic_cvs(str: ?*anyopaque) callconv(.c) f64 {
    if (str == null) {
        basic_throw(5);
        return 0.0;
    }
    const desc: *const StringDescriptor = @ptrCast(@alignCast(str.?));
    const slen: usize = if (desc.length > 0) @intCast(desc.length) else 0;
    if (slen < 4) {
        basic_throw(5);
        return 0.0;
    }

    var raw_ptr: [*]const u8 = undefined;
    if (desc.encoding == STRING_ENCODING_ASCII) {
        raw_ptr = @ptrCast(@alignCast(desc.data.?));
    } else {
        const u8p = string_to_utf8(str);
        raw_ptr = @ptrCast(u8p);
        const raw_len = c.strlen(u8p);
        if (raw_len < 4) {
            basic_throw(5);
            return 0.0;
        }
    }

    var buffer: [4]u8 = undefined;
    @memcpy(&buffer, raw_ptr[0..4]);
    const result: *const f32 = @ptrCast(@alignCast(&buffer));
    return @floatCast(result.*);
}

/// CVD - Convert binary string to Double precision float
/// Reads 8 bytes from string and converts to double.
/// Accesses the StringDescriptor directly for binary safety.
export fn basic_cvd(str: ?*anyopaque) callconv(.c) f64 {
    if (str == null) {
        basic_throw(5);
        return 0.0;
    }
    const desc: *const StringDescriptor = @ptrCast(@alignCast(str.?));
    const slen: usize = if (desc.length > 0) @intCast(desc.length) else 0;
    if (slen < 8) {
        basic_throw(5);
        return 0.0;
    }

    var raw_ptr: [*]const u8 = undefined;
    if (desc.encoding == STRING_ENCODING_ASCII) {
        raw_ptr = @ptrCast(@alignCast(desc.data.?));
    } else {
        const u8p = string_to_utf8(str);
        raw_ptr = @ptrCast(u8p);
        const raw_len = c.strlen(u8p);
        if (raw_len < 8) {
            basic_throw(5);
            return 0.0;
        }
    }

    var buffer: [8]u8 = undefined;
    @memcpy(&buffer, raw_ptr[0..8]);
    const result: *const f64 = @ptrCast(@alignCast(&buffer));
    return result.*;
}

// ============================================================================
// File Position and Length Functions
// ============================================================================

/// LOC - Returns current position in file
/// For random access: returns current record number
/// For binary/sequential: returns current byte position / 128
export fn basic_loc(file_num: c_int) callconv(.c) c_long {
    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return 0;
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return 0;
    }

    const cfp = file.asFILE() orelse {
        basic_throw(56);
        return 0;
    };
    const pos = c.ftell(cfp);
    if (pos < 0) {
        return 0;
    }

    // Return position in 128-byte blocks (compatible with most BASIC variants)
    return @intCast(@divTrunc(pos, 128));
}

/// LOF - Returns length of file in bytes
export fn basic_lof(file_num: c_int) callconv(.c) c_long {
    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return 0;
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return 0;
    }

    const cfp = file.asFILE() orelse {
        basic_throw(56);
        return 0;
    };

    // Save current position
    const current_pos = c.ftell(cfp);
    if (current_pos < 0) {
        return 0;
    }

    // Seek to end
    if (c.fseek(cfp, 0, c.SEEK_END) != 0) {
        return 0;
    }

    // Get end position (file length)
    const length = c.ftell(cfp);

    // Restore original position
    _ = c.fseek(cfp, current_pos, c.SEEK_SET);

    if (length < 0) {
        return 0;
    }

    return @intCast(length);
}

// ============================================================================
// INPUT$ Function - Read N bytes from file
// ============================================================================

/// INPUT$ - Read specified number of bytes from file
/// Syntax: INPUT$(n, #filenum)
/// Returns a string containing n bytes from the file
export fn basic_input_file(num_bytes: c_int, file_num: c_int) callconv(.c) ?*anyopaque {
    if (num_bytes <= 0) {
        return string_new_utf8("");
    }

    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return string_new_utf8("");
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return string_new_utf8("");
    }

    // Allocate buffer for reading
    const size: usize = @intCast(num_bytes);
    const buffer = c.malloc(size + 1) orelse {
        basic_throw(7); // ERR_OUT_OF_MEMORY
        return string_new_utf8("");
    };

    // Read bytes from file
    const cfp = file.asFILE() orelse {
        c.free(buffer);
        basic_throw(56);
        return string_new_utf8("");
    };
    const bytes_ptr: [*]u8 = @ptrCast(buffer);
    const bytes_read = c.fread(buffer, 1, size, cfp);

    // Null-terminate
    bytes_ptr[bytes_read] = 0;

    // Create string from buffer
    const result = string_new_ascii_len(bytes_ptr, @intCast(bytes_read));

    // Free temporary buffer
    c.free(buffer);

    return result;
}

// ============================================================================
// File Seeking (used by SEEK statement)
// ============================================================================

/// Seek to specific byte position in file
/// Used internally by the SEEK statement
export fn file_seek(file_num: c_int, position: c_long) callconv(.c) c_int {
    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return -1;
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return -1;
    }

    // BASIC positions are 1-based, C is 0-based
    const c_position: c_long = if (position > 0) position - 1 else 0;

    const cfp = file.asFILE() orelse {
        basic_throw(56);
        return -1;
    };

    if (c.fseek(cfp, c_position, c.SEEK_SET) != 0) {
        basic_throw(62); // ERR_INPUT_PAST_END
        return -1;
    }

    return 0;
}

// ============================================================================
// FIELD Statement Support (Record Buffer Management)
// ============================================================================

// Global record buffer for FIELD statements
// Each file can have its own record buffer
const MAX_FILES = 256;
const MAX_RECORD_SIZE = 32768;

var record_buffers: [MAX_FILES]?[*]u8 = [_]?[*]u8{null} ** MAX_FILES;
var record_buffer_sizes: [MAX_FILES]usize = [_]usize{0} ** MAX_FILES;

/// Initialize record buffer for a file
export fn field_init_buffer(file_num: c_int, size: c_int) callconv(.c) c_int {
    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return -1;
    }

    const buffer_size: usize = @intCast(if (size > 0) size else 128);
    if (buffer_size > MAX_RECORD_SIZE) {
        basic_throw(81); // ERR_INVALID_RECORD_LENGTH
        return -1;
    }

    // Free existing buffer if any
    if (record_buffers[@intCast(file_num)]) |existing| {
        c.free(existing);
    }

    // Allocate new buffer
    const buffer = c.malloc(buffer_size) orelse {
        basic_throw(7); // ERR_OUT_OF_MEMORY
        return -1;
    };

    // Zero-initialize
    @memset(@as([*]u8, @ptrCast(buffer))[0..buffer_size], 0);

    record_buffers[@intCast(file_num)] = @ptrCast(buffer);
    record_buffer_sizes[@intCast(file_num)] = buffer_size;

    return 0;
}

/// Get pointer to record buffer for a file
export fn field_get_buffer(file_num: c_int) callconv(.c) ?*anyopaque {
    if (file_num < 0 or file_num >= MAX_FILES) {
        return null;
    }

    return record_buffers[@intCast(file_num)];
}

/// Free record buffer for a file
export fn field_free_buffer(file_num: c_int) callconv(.c) void {
    if (file_num < 0 or file_num >= MAX_FILES) {
        return;
    }

    if (record_buffers[@intCast(file_num)]) |buffer| {
        c.free(buffer);
        record_buffers[@intCast(file_num)] = null;
        record_buffer_sizes[@intCast(file_num)] = 0;
    }
}

/// Extract a substring from the record buffer at a given offset and length.
/// Used by FIELD statement: each FIELD variable maps to (offset, length) in the buffer.
/// Returns a new BASIC string.
export fn field_extract(file_num: c_int, offset: c_int, length: c_int) callconv(.c) ?*anyopaque {
    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return string_new_utf8("");
    }

    const buf = record_buffers[@intCast(file_num)] orelse {
        basic_throw(5); // ERR_ILLEGAL_CALL - no FIELD buffer
        return string_new_utf8("");
    };

    const buf_size = record_buffer_sizes[@intCast(file_num)];
    const off: usize = @intCast(if (offset >= 0) offset else 0);
    const len: usize = @intCast(if (length > 0) length else 0);

    if (off + len > buf_size) {
        basic_throw(5); // ERR_ILLEGAL_CALL - out of bounds
        return string_new_utf8("");
    }

    return string_new_ascii_len(buf + off, @intCast(len));
}

// ============================================================================
// LSET / RSET - Write data into the record buffer
// ============================================================================

/// LSET - Left-justify a string into the record buffer at offset/length.
/// Pads with spaces on the right if the string is shorter than the field.
/// Truncates if the string is longer than the field.
export fn field_lset(file_num: c_int, offset: c_int, length: c_int, value: ?*anyopaque) callconv(.c) void {
    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64);
        return;
    }

    const buf = record_buffers[@intCast(file_num)] orelse {
        basic_throw(5);
        return;
    };

    const buf_size = record_buffer_sizes[@intCast(file_num)];
    const off: usize = @intCast(if (offset >= 0) offset else 0);
    const len: usize = @intCast(if (length > 0) length else 0);

    if (off + len > buf_size) {
        basic_throw(5);
        return;
    }

    // Get the source string data
    const src_data = string_to_utf8(value);
    const src_len = c.strlen(src_data);

    // Copy source into buffer (left-justified)
    const copy_len = if (src_len < len) src_len else len;
    var i: usize = 0;
    while (i < copy_len) : (i += 1) {
        buf[off + i] = @intCast(src_data[i]);
    }

    // Pad remainder with spaces
    while (i < len) : (i += 1) {
        buf[off + i] = ' ';
    }
}

/// RSET - Right-justify a string into the record buffer at offset/length.
/// Pads with spaces on the left if the string is shorter than the field.
/// Truncates from the left if the string is longer than the field.
export fn field_rset(file_num: c_int, offset: c_int, length: c_int, value: ?*anyopaque) callconv(.c) void {
    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64);
        return;
    }

    const buf = record_buffers[@intCast(file_num)] orelse {
        basic_throw(5);
        return;
    };

    const buf_size = record_buffer_sizes[@intCast(file_num)];
    const off: usize = @intCast(if (offset >= 0) offset else 0);
    const len: usize = @intCast(if (length > 0) length else 0);

    if (off + len > buf_size) {
        basic_throw(5);
        return;
    }

    const src_data = string_to_utf8(value);
    const src_len = c.strlen(src_data);

    if (src_len >= len) {
        // String is longer or equal: take rightmost `len` chars
        const start = src_len - len;
        var i: usize = 0;
        while (i < len) : (i += 1) {
            buf[off + i] = @intCast(src_data[start + i]);
        }
    } else {
        // String is shorter: pad with spaces on the left
        const pad = len - src_len;
        var i: usize = 0;
        while (i < pad) : (i += 1) {
            buf[off + i] = ' ';
        }
        i = 0;
        while (i < src_len) : (i += 1) {
            buf[off + pad + i] = @intCast(src_data[i]);
        }
    }
}

// ============================================================================
// PUT / GET - Write / Read records from random access files
// ============================================================================

/// PUT - Write the record buffer to a specific record number in the file.
/// record_num is 1-based. If record_num <= 0, writes at current position.
export fn file_put_record(file_num: c_int, record_num: c_int) callconv(.c) void {
    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return;
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return;
    }

    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64);
        return;
    }

    const buf = record_buffers[@intCast(file_num)] orelse {
        basic_throw(5); // ERR_ILLEGAL_CALL - no FIELD buffer
        return;
    };

    const buf_size = record_buffer_sizes[@intCast(file_num)];

    const cfp = file.asFILE() orelse {
        basic_throw(56);
        return;
    };

    // Seek to record position if record_num > 0 (1-based)
    if (record_num > 0) {
        const byte_offset: c_long = @intCast((@as(i64, record_num) - 1) * @as(i64, @intCast(buf_size)));
        if (c.fseek(cfp, byte_offset, c.SEEK_SET) != 0) {
            basic_throw(82); // ERR_RECORD_OUT_OF_RANGE
            return;
        }
    }

    // Write the buffer
    const written = c.fwrite(buf, 1, buf_size, cfp);
    if (written != buf_size) {
        basic_throw(61); // ERR_DISK_FULL
        return;
    }

    _ = c.fflush(cfp);
}

/// GET - Read a record from the file into the record buffer.
/// record_num is 1-based. If record_num <= 0, reads from current position.
export fn file_get_record(file_num: c_int, record_num: c_int) callconv(.c) void {
    const handle = file_get_handle(file_num);
    if (handle == null) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return;
    }

    const file: *BasicFile = @ptrCast(@alignCast(handle));
    if (file.fp == null or !file.is_open) {
        basic_throw(56); // ERR_FILE_NOT_OPEN
        return;
    }

    if (file_num < 0 or file_num >= MAX_FILES) {
        basic_throw(64);
        return;
    }

    const buf = record_buffers[@intCast(file_num)] orelse {
        basic_throw(5); // ERR_ILLEGAL_CALL - no FIELD buffer
        return;
    };

    const buf_size = record_buffer_sizes[@intCast(file_num)];

    const cfp = file.asFILE() orelse {
        basic_throw(56);
        return;
    };

    // Seek to record position if record_num > 0 (1-based)
    if (record_num > 0) {
        const byte_offset: c_long = @intCast((@as(i64, record_num) - 1) * @as(i64, @intCast(buf_size)));
        if (c.fseek(cfp, byte_offset, c.SEEK_SET) != 0) {
            basic_throw(82); // ERR_RECORD_OUT_OF_RANGE
            return;
        }
    }

    // Read into the buffer
    const bytes_read = c.fread(buf, 1, buf_size, cfp);

    // Zero-fill any remainder (short read at end of file)
    if (bytes_read < buf_size) {
        @memset(buf[bytes_read..buf_size], 0);
    }
}
