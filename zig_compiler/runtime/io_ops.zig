//
// io_ops.zig
// FasterBASIC Runtime — Console & File I/O Operations
//
// Console output (print int/float/string/newline/tab/hex/pointer),
// terminal control (CLS, LOCATE, COLOR, WIDTH),
// console input (INPUT, LINE INPUT, INKEY$),
// file operations (OPEN, CLOSE, PRINT#, READ LINE, EOF),
// command-line arguments (COMMAND$).
//

const std = @import("std");
const c = std.c;

// =========================================================================
// Command-line arguments storage
// =========================================================================

var g_argc: i32 = 0;
var g_argv: [*][*:0]u8 = undefined;

// =========================================================================
// Extern declarations
// =========================================================================

// basic_runtime.c
extern fn basic_error_msg(msg: [*:0]const u8) void;
extern fn basic_throw(error_code: c_int) void;

// string functions (string_utf32.zig / string_ops.zig)
extern fn string_to_utf8(desc: ?*anyopaque) [*:0]const u8;
extern fn string_new_utf8(s: ?[*:0]const u8) ?*anyopaque;
extern fn string_new_capacity(cap: i64) ?*anyopaque;
extern fn string_retain(desc: ?*anyopaque) ?*anyopaque;
extern fn string_release(desc: ?*anyopaque) void;

// legacy string (BasicString) functions — still in basic_runtime.c
extern fn str_new(cstr: [*:0]const u8) ?*anyopaque;
extern fn str_release(s: ?*anyopaque) void;
extern fn str_to_int(s: ?*anyopaque) i32;
extern fn str_to_double(s: ?*anyopaque) f64;

// File management (basic_runtime.c)
extern fn _basic_register_file(file: ?*BasicFile) void;
extern fn _basic_unregister_file(file: ?*BasicFile) void;

// C library
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn fflush(stream: ?*anyopaque) c_int;
extern fn fgets(buf: [*]u8, size: c_int, stream: *anyopaque) ?[*]u8;
extern fn fopen(path: [*:0]const u8, mode: [*:0]const u8) ?*anyopaque;
extern fn fclose(stream: *anyopaque) c_int;
extern fn feof(stream: *anyopaque) c_int;
extern fn fseek(stream: *anyopaque, offset: c_long, whence: c_int) c_int;
extern fn ftell(stream: *anyopaque) c_long;
extern fn fread(ptr: *anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn fwrite(ptr: *const anyopaque, size: usize, nmemb: usize, stream: *anyopaque) usize;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn strlen(s: [*:0]const u8) usize;
extern fn putchar(ch: c_int) c_int;

const SEEK_SET: c_int = 0;
const SEEK_END: c_int = 2;

// stdout
extern const __stdoutp: *anyopaque;
extern const __stdinp: *anyopaque;

// Paint mode query from terminal_io.zig — when paint mode is active,
// we skip per-call fflush to allow output batching (BEGINPAINT/ENDPAINT).
extern fn basic_is_paint_mode() i32;

fn flushIfNeeded() void {
    if (basic_is_paint_mode() == 0) {
        _ = fflush(__stdoutp);
    }
}

// =========================================================================
// Thread-safe PRINT — statement-level mutex
// =========================================================================
//
// A single PRINT statement (e.g. PRINT "x="; x; " y="; y) compiles to
// multiple basic_print_* calls.  Without protection, concurrent PRINT
// from workers and main interleave mid-line, producing garbled output.
//
// basic_print_lock / basic_print_unlock bracket an entire PRINT statement
// so all its items, separators, and trailing newline appear atomically.
// The codegen emits lock() before the first item and unlock() after the
// last (including the newline if present).
//
// The mutex is a simple non-recursive std.Thread.Mutex.  PRINT items are
// expressions that cannot themselves contain PRINT statements, so
// recursive acquisition is not needed.

var g_print_mutex: std.Thread.Mutex = .{};

export fn basic_print_lock() callconv(.c) void {
    g_print_mutex.lock();
}

export fn basic_print_unlock() callconv(.c) void {
    g_print_mutex.unlock();
}

// POSIX (for INKEY$)
extern fn fcntl(fd: c_int, cmd: c_int, ...) c_int;
extern fn read(fd: c_int, buf: [*]u8, count: usize) isize;

const STDIN_FILENO: c_int = 0;
const F_GETFL: c_int = 3;
const F_SETFL: c_int = 4;
const O_NONBLOCK: c_int = 0x0004; // macOS

// =========================================================================
// Types matching basic_runtime.h
// =========================================================================

/// BasicString — legacy string type (still used by some codegen paths)
pub const BasicString = extern struct {
    data: ?[*:0]u8,
    length: usize,
    capacity: usize,
    refcount: i32,
};

/// BasicFile — file handle with buffered reader for INPUT mode.
///
/// On OPEN FOR INPUT the entire file is slurped into `read_buf`.
/// `file_read_line` then scans that buffer recognising CR+LF, LF, CR
/// and end-of-buffer as line terminators.  Any file that contains at
/// least one byte of data contains at least one line.
pub const BasicFile = extern struct {
    // ── original fields (ABI-stable, must match basic_runtime.h) ──
    fp: ?*anyopaque,
    file_number: i32,
    filename: ?[*:0]u8,
    mode: ?[*:0]u8,
    is_open: bool,
    // ── buffered reader fields (appended, invisible to legacy C code) ──
    read_buf: ?[*]u8 = null,
    read_buf_size: usize = 0,
    read_pos: usize = 0,
};

// =========================================================================
// Console Output
// =========================================================================

export fn basic_print_int(value: i64) callconv(.c) void {
    _ = printf("%lld", value);
    flushIfNeeded();
}

export fn basic_print_long(value: i64) callconv(.c) void {
    _ = printf("%lld", value);
    flushIfNeeded();
}

export fn basic_print_float(value: f32) callconv(.c) void {
    _ = printf("%g", @as(f64, value));
    flushIfNeeded();
}

export fn basic_print_double(value: f64) callconv(.c) void {
    _ = printf("%g", value);
    flushIfNeeded();
}

export fn basic_print_string(str: ?*BasicString) callconv(.c) void {
    const s = str orelse return;
    const data = s.data orelse return;
    _ = printf("%s", data);
    flushIfNeeded();
}

export fn basic_print_cstr(str: ?[*:0]const u8) callconv(.c) void {
    const s = str orelse return;
    _ = printf("%s", s);
    flushIfNeeded();
}

export fn basic_print_string_desc(desc: ?*anyopaque) callconv(.c) void {
    const d = desc orelse return;
    const utf8 = string_to_utf8(d);
    _ = printf("%s", utf8);
    flushIfNeeded();
}

export fn basic_print_hex(value: i64) callconv(.c) void {
    _ = printf("0x%llx", value);
    flushIfNeeded();
}

export fn basic_print_pointer(ptr: ?*anyopaque) callconv(.c) void {
    _ = printf("0x%llx", @intFromPtr(ptr));
    flushIfNeeded();
}

export fn debug_print_hashmap(map: ?*anyopaque) callconv(.c) void {
    _ = printf("[HASHMAP@");
    basic_print_pointer(map);
    _ = printf("]");
    flushIfNeeded();
}

export fn basic_print_newline() callconv(.c) void {
    _ = printf("\n");
    flushIfNeeded();
}

export fn basic_print_tab() callconv(.c) void {
    _ = printf("\t");
    flushIfNeeded();
}

export fn basic_print_at(row: i32, col: i32, str: ?*BasicString) callconv(.c) void {
    _ = printf("\x1b[%d;%dH", row, col);
    if (str) |s| {
        if (s.data) |data| {
            _ = printf("%s", data);
        }
    }
    flushIfNeeded();
}

// =========================================================================
// Terminal Control
// =========================================================================
// NOTE: CLS, LOCATE, and COLOR functions moved to terminal_io.zig
// The terminal_io module provides a complete terminal I/O implementation
// with cursor control, colors, styles, and more.

var g_terminal_width: i32 = 80;

export fn basic_width(columns: i32) callconv(.c) void {
    if (columns > 0) g_terminal_width = columns;
}

export fn basic_get_width() callconv(.c) i32 {
    return g_terminal_width;
}

var g_cursor_row: i32 = 1;
var g_cursor_col: i32 = 1;

// NOTE: basic_csrlin, basic_pos, and basic_inkey are now in terminal_io.zig
// to avoid duplication and to support enhanced keyboard input features.

export fn _basic_update_cursor_pos(row: i32, col: i32) callconv(.c) void {
    g_cursor_row = row;
    g_cursor_col = col;
}

// =========================================================================
// LINE INPUT — Read entire line
// =========================================================================

export fn basic_line_input(prompt: ?[*:0]const u8) callconv(.c) ?*anyopaque {
    if (prompt) |p| {
        if (p[0] != 0) {
            _ = printf("%s", p);
            _ = fflush(__stdoutp);
        }
    }

    var buffer: [4096]u8 = undefined;
    if (fgets(&buffer, 4096, __stdinp) == null) {
        return string_new_utf8("");
    }

    // Remove trailing newline
    const len = strlen(@ptrCast(&buffer));
    if (len > 0 and buffer[len - 1] == '\n') {
        buffer[len - 1] = 0;
    }

    return string_new_utf8(@ptrCast(&buffer));
}

// =========================================================================
// Console Input
// =========================================================================

export fn basic_input_string() callconv(.c) ?*anyopaque {
    var buffer: [4096]u8 = undefined;
    if (fgets(&buffer, 4096, __stdinp) == null) {
        return str_new("");
    }

    const len = strlen(@ptrCast(&buffer));
    if (len > 0 and buffer[len - 1] == '\n') {
        buffer[len - 1] = 0;
    }

    return str_new(@ptrCast(&buffer));
}

export fn basic_input_prompt(prompt: ?*BasicString) callconv(.c) ?*anyopaque {
    if (prompt) |p| {
        if (p.length > 0) {
            if (p.data) |data| {
                _ = printf("%s", data);
                _ = fflush(__stdoutp);
            }
        }
    }

    return basic_input_string();
}

export fn basic_input_int() callconv(.c) i32 {
    const str = basic_input_string();
    const result = str_to_int(str);
    str_release(str);
    return result;
}

export fn basic_input_double() callconv(.c) f64 {
    const str = basic_input_string();
    const result = str_to_double(str);
    str_release(str);
    return result;
}

export fn basic_input_line() callconv(.c) ?*anyopaque {
    var buffer: [4096]u8 = undefined;
    if (fgets(&buffer, 4096, __stdinp) == null) {
        return string_new_utf8("");
    }

    const len = strlen(@ptrCast(&buffer));
    if (len > 0 and buffer[len - 1] == '\n') {
        buffer[len - 1] = 0;
    }

    return string_new_utf8(@ptrCast(&buffer));
}

// =========================================================================
// File Operations
// =========================================================================

export fn file_open(filename: ?*anyopaque, mode: ?*anyopaque) callconv(.c) ?*BasicFile {
    if (filename == null or mode == null) {
        basic_throw(52); // ERR_BAD_FILE
        return null;
    }

    // Convert string descriptors to C strings
    const fname_data = string_to_utf8(filename);
    const mode_str = string_to_utf8(mode);

    // Map BASIC modes to C fopen modes
    var mode_data: [*:0]const u8 = "r";
    const mode_span = std.mem.span(mode_str);

    const is_input_mode = std.mem.eql(u8, mode_span, "INPUT") or
        std.mem.eql(u8, mode_span, "BINARY INPUT");

    if (std.mem.eql(u8, mode_span, "INPUT")) {
        mode_data = "rb"; // always binary so we control line-ending logic ourselves
    } else if (std.mem.eql(u8, mode_span, "OUTPUT")) {
        mode_data = "w";
    } else if (std.mem.eql(u8, mode_span, "APPEND")) {
        mode_data = "a";
    } else if (std.mem.eql(u8, mode_span, "BINARY INPUT")) {
        mode_data = "rb";
    } else if (std.mem.eql(u8, mode_span, "BINARY OUTPUT")) {
        mode_data = "wb";
    } else if (std.mem.eql(u8, mode_span, "BINARY APPEND")) {
        mode_data = "ab";
    } else if (std.mem.eql(u8, mode_span, "RANDOM")) {
        mode_data = "r+b";
    } else if (std.mem.eql(u8, mode_span, "BINARY RANDOM")) {
        mode_data = "r+b";
    } else {
        mode_data = mode_str;
    }

    const raw = c.malloc(@sizeOf(BasicFile)) orelse {
        basic_throw(7); // ERR_OUT_OF_MEMORY
        return null;
    };
    const file: *BasicFile = @ptrCast(@alignCast(raw));

    file.filename = strdup(fname_data);
    file.mode = strdup(mode_data);
    file.file_number = 0;
    file.is_open = false;
    file.read_buf = null;
    file.read_buf_size = 0;
    file.read_pos = 0;

    file.fp = fopen(fname_data, mode_data);

    // Special handling for RANDOM mode: if r+b fails, try w+b (create new file)
    if (file.fp == null and (std.mem.eql(u8, mode_span, "RANDOM") or
        std.mem.eql(u8, mode_span, "BINARY RANDOM")))
    {
        mode_data = "w+b";
        file.fp = fopen(fname_data, mode_data);
    }

    if (file.fp == null) {
        if (file.filename) |fn_ptr| c.free(fn_ptr);
        if (file.mode) |m_ptr| c.free(m_ptr);
        c.free(raw);

        const err_code: c_int = if (is_input_mode)
            53 // ERR_FILE_NOT_FOUND
        else
            75; // ERR_PERMISSION_DENIED

        basic_throw(err_code);
        return null;
    }

    file.is_open = true;

    // ── Buffered reader: slurp entire file into memory for INPUT modes ──
    if (is_input_mode) {
        const fp = file.fp.?;
        // Determine file size
        _ = fseek(fp, 0, SEEK_END);
        const size_long = ftell(fp);
        _ = fseek(fp, 0, SEEK_SET);
        const file_size: usize = if (size_long > 0) @intCast(size_long) else 0;

        if (file_size > 0) {
            const buf_raw = c.malloc(file_size) orelse {
                basic_throw(7); // ERR_OUT_OF_MEMORY
                return null;
            };
            const buf: [*]u8 = @ptrCast(buf_raw);
            const bytes_read = fread(buf_raw, 1, file_size, fp);
            file.read_buf = buf;
            file.read_buf_size = bytes_read;
        } else {
            file.read_buf = null;
            file.read_buf_size = 0;
        }
        file.read_pos = 0;

        // We no longer need the FILE* for reading — close it now so we
        // don't hold OS handles while the program processes data.
        _ = fclose(fp);
        file.fp = null;
    }

    _basic_register_file(file);

    return file;
}

export fn file_close(file: ?*BasicFile) callconv(.c) void {
    const f = file orelse return;

    if (f.is_open) {
        if (f.fp) |fp| {
            _ = fclose(fp);
            f.fp = null;
        }
        // Free the read buffer if we slurped the file.
        if (f.read_buf) |buf| {
            c.free(buf);
            f.read_buf = null;
            f.read_buf_size = 0;
            f.read_pos = 0;
        }
        f.is_open = false;
    }

    _basic_unregister_file(f);

    if (f.filename) |fn_ptr| {
        c.free(fn_ptr);
        f.filename = null;
    }
    if (f.mode) |m_ptr| {
        c.free(m_ptr);
        f.mode = null;
    }

    c.free(f);
}

export fn file_print_string(file: ?*BasicFile, str_desc: ?*anyopaque) callconv(.c) void {
    const f = file orelse {
        basic_error_msg("File not open for writing");
        return;
    };
    if (!f.is_open) {
        basic_error_msg("File not open for writing");
        return;
    }
    const fp = f.fp orelse {
        basic_error_msg("File not open for writing");
        return;
    };

    if (str_desc == null) return;
    const data = string_to_utf8(str_desc);
    _ = fprintf(fp, "%s", data);
    _ = fflush(fp);
}

export fn file_print_int(file: ?*BasicFile, value: i32) callconv(.c) void {
    const f = file orelse {
        basic_error_msg("File not open for writing");
        return;
    };
    if (!f.is_open) {
        basic_error_msg("File not open for writing");
        return;
    }
    const fp = f.fp orelse {
        basic_error_msg("File not open for writing");
        return;
    };

    _ = fprintf(fp, "%d", value);
    _ = fflush(fp);
}

export fn file_print_newline(file: ?*BasicFile) callconv(.c) void {
    const f = file orelse {
        basic_error_msg("File not open for writing");
        return;
    };
    if (!f.is_open) {
        basic_error_msg("File not open for writing");
        return;
    }
    const fp = f.fp orelse {
        basic_error_msg("File not open for writing");
        return;
    };

    _ = fprintf(fp, "\n");
    _ = fflush(fp);
}

/// Read the next line from a buffered file.
///
/// Scans `read_buf` from `read_pos` forward, recognising three line-ending
/// conventions:
///   • CR+LF  (Windows)
///   • LF     (Unix / macOS)
///   • CR     (classic Mac)
///
/// End-of-buffer is also treated as a line terminator, so a file that
/// contains data but no trailing newline still yields its last line.
///
/// Returns a `StringDescriptor*` (via `string_new_utf8`) for the line
/// content *without* the terminator.  At true end-of-file (read_pos ≥
/// read_buf_size) returns an empty string.
export fn file_read_line(file: ?*BasicFile) callconv(.c) ?*anyopaque {
    const f = file orelse {
        basic_error_msg("File not open for reading");
        return string_new_utf8("");
    };
    if (!f.is_open) {
        basic_error_msg("File not open for reading");
        return string_new_utf8("");
    }

    const buf = f.read_buf orelse {
        // No buffer — file was opened for writing or is empty.
        return string_new_utf8("");
    };
    const size = f.read_buf_size;
    const pos = f.read_pos;

    // Already past the end — nothing left to read.
    if (pos >= size) return string_new_utf8("");

    // Scan for the next line terminator (CR, LF, or CR+LF).
    var end = pos;
    while (end < size) : (end += 1) {
        const ch = buf[end];
        if (ch == '\n' or ch == '\r') break;
    }

    // `end` now points at the terminator byte, or == size (end of buffer).
    const line_start = buf + pos;
    const line_len = end - pos;

    // Build a NUL-terminated copy for string_new_utf8.
    const copy_raw = c.malloc(line_len + 1) orelse {
        basic_throw(7);
        return string_new_utf8("");
    };
    const copy: [*]u8 = @ptrCast(copy_raw);
    if (line_len > 0) {
        @memcpy(copy[0..line_len], line_start[0..line_len]);
    }
    copy[line_len] = 0;

    // Advance past the terminator.  CR+LF counts as one terminator.
    var new_pos = end;
    if (new_pos < size) {
        if (buf[new_pos] == '\r') {
            new_pos += 1;
            if (new_pos < size and buf[new_pos] == '\n') {
                new_pos += 1; // CR+LF
            }
        } else {
            // must be '\n'
            new_pos += 1;
        }
    }
    f.read_pos = new_pos;

    const result = string_new_utf8(@ptrCast(copy));
    c.free(copy_raw);
    return result;
}

/// Low-level EOF predicate on a BasicFile pointer (used by binary_io).
export fn file_eof(file: ?*BasicFile) callconv(.c) bool {
    const f = file orelse return true;
    if (!f.is_open) return true;

    // Buffered reader path — authoritative for INPUT mode files.
    if (f.read_buf != null) {
        return f.read_pos >= f.read_buf_size;
    }

    // Fallback for write-mode files that still have an fp.
    const fp = f.fp orelse return true;
    return feof(fp) != 0;
}

/// `EOF(file_number)` — callable directly from generated code.
/// Returns BASIC true (-1) when at end-of-file, BASIC false (0) otherwise.
export fn basic_eof(file_number: i32) callconv(.c) i32 {
    const handle = file_get_handle(file_number);
    const f = handle orelse return -1;
    if (!f.is_open) return -1;

    // Buffered reader path.
    if (f.read_buf != null) {
        return if (f.read_pos >= f.read_buf_size) @as(i32, -1) else @as(i32, 0);
    }

    // Fallback (write-mode file with fp).
    const fp = f.fp orelse return -1;
    return if (feof(fp) != 0) @as(i32, -1) else @as(i32, 0);
}

// =========================================================================
// File Handle Management by Number
// =========================================================================

const MAX_FILE_HANDLES = 256;
var file_handles: [MAX_FILE_HANDLES]?*BasicFile = [_]?*BasicFile{null} ** MAX_FILE_HANDLES;

export fn file_get_handle(file_number: i32) callconv(.c) ?*BasicFile {
    if (file_number < 0 or file_number >= MAX_FILE_HANDLES) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return null;
    }
    return file_handles[@intCast(file_number)];
}

export fn file_set_handle(file_number: i32, file: ?*BasicFile) callconv(.c) void {
    if (file_number < 0 or file_number >= MAX_FILE_HANDLES) {
        basic_throw(64); // ERR_BAD_FILE_NUMBER
        return;
    }
    file_handles[@intCast(file_number)] = file;
}

export fn file_print_double(file: ?*BasicFile, value: f64) callconv(.c) void {
    const f = file orelse {
        basic_error_msg("File not open for writing");
        return;
    };
    if (!f.is_open) {
        basic_error_msg("File not open for writing");
        return;
    }
    const fp = f.fp orelse {
        basic_error_msg("File not open for writing");
        return;
    };
    _ = fprintf(fp, "%g", value);
    _ = fflush(fp);
}

// =========================================================================
// Process Execution
// =========================================================================

extern fn system(command: [*:0]const u8) c_int;

export fn basic_system(command: ?*anyopaque) callconv(.c) i32 {
    if (command == null) return -1;
    const cmd_str = string_to_utf8(command);
    _ = fflush(__stdoutp);
    const result = system(cmd_str);
    return @intCast(result);
}

export fn basic_shell(command: ?*anyopaque) callconv(.c) void {
    _ = basic_system(command);
}

// =========================================================================
// Whole File Operations (SLURP / SPIT)
// =========================================================================

/// SLURP(filename$) — Read entire file into a string
export fn basic_slurp(filename: ?*anyopaque) callconv(.c) ?*anyopaque {
    if (filename == null) {
        basic_error_msg("SLURP: filename cannot be null");
        return string_new_utf8("");
    }

    const fname_data = string_to_utf8(filename);

    // Open file in binary mode to preserve exact content
    const fp = fopen(fname_data, "rb") orelse {
        var err_msg: [256]u8 = undefined;
        _ = snprintf(&err_msg, err_msg.len, "SLURP: Cannot open file: %s", fname_data);
        basic_error_msg(@ptrCast(&err_msg));
        return string_new_utf8("");
    };
    defer _ = fclose(fp);

    // Get file size
    if (fseek(fp, 0, SEEK_END) != 0) {
        basic_error_msg("SLURP: Cannot seek to end of file");
        return string_new_utf8("");
    }

    const file_size = ftell(fp);
    if (file_size < 0) {
        basic_error_msg("SLURP: Cannot determine file size");
        return string_new_utf8("");
    }

    if (fseek(fp, 0, SEEK_SET) != 0) {
        basic_error_msg("SLURP: Cannot seek to beginning of file");
        return string_new_utf8("");
    }

    // Allocate buffer (+1 for null terminator)
    const buffer_size: usize = @intCast(file_size + 1);
    const buffer = c.malloc(buffer_size) orelse {
        basic_error_msg("SLURP: Out of memory");
        return string_new_utf8("");
    };
    defer c.free(buffer);

    // Read entire file
    const bytes_read = fread(buffer, 1, @intCast(file_size), fp);
    if (bytes_read != @as(usize, @intCast(file_size))) {
        basic_error_msg("SLURP: Failed to read entire file");
        return string_new_utf8("");
    }

    // Null-terminate the buffer
    const buf_ptr: [*]u8 = @ptrCast(buffer);
    buf_ptr[@intCast(file_size)] = 0;

    // Create string from buffer
    const result = string_new_utf8(@ptrCast(buffer));
    return result;
}

/// SPIT(filename$, content$) — Write entire string to file
export fn basic_spit(filename: ?*anyopaque, content: ?*anyopaque) callconv(.c) void {
    if (filename == null) {
        basic_error_msg("SPIT: filename cannot be null");
        return;
    }

    const fname_data = string_to_utf8(filename);

    // Open file in binary mode to preserve exact content
    const fp = fopen(fname_data, "wb") orelse {
        var err_msg: [256]u8 = undefined;
        _ = snprintf(&err_msg, err_msg.len, "SPIT: Cannot open file: %s", fname_data);
        basic_error_msg(@ptrCast(&err_msg));
        return;
    };
    defer _ = fclose(fp);

    // Handle empty/null content
    if (content == null) {
        // Write empty file
        return;
    }

    const content_data = string_to_utf8(content);
    const content_len = strlen(content_data);

    if (content_len > 0) {
        const bytes_written = fwrite(content_data, 1, content_len, fp);
        if (bytes_written != content_len) {
            basic_error_msg("SPIT: Failed to write entire file");
            return;
        }
    }

    _ = fflush(fp);
}

// =========================================================================
// Command-line Arguments
// =========================================================================

/// Initialize command-line arguments (called from generated main)
export fn basic_init_args(argc: i32, argv: [*][*:0]u8) callconv(.c) void {
    g_argc = argc;
    g_argv = argv;
}

/// Get number of command-line arguments (includes program name at index 0)
export fn basic_command_count() callconv(.c) i32 {
    return g_argc;
}

/// Get command-line argument at index n as a string
/// COMMAND$(0) returns program name
/// COMMAND$(1) returns first argument, etc.
export fn basic_command(index: i32) callconv(.c) ?*anyopaque {
    if (index < 0 or index >= g_argc) {
        return string_new_utf8("");
    }
    return string_new_utf8(g_argv[@intCast(index)]);
}
