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

/// BasicFile — file handle
pub const BasicFile = extern struct {
    fp: ?*anyopaque,
    file_number: i32,
    filename: ?[*:0]u8,
    mode: ?[*:0]u8,
    is_open: bool,
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
        basic_error_msg("Invalid file open parameters");
        return null;
    }

    // Convert string descriptors to C strings
    const fname_data = string_to_utf8(filename);
    const mode_str = string_to_utf8(mode);

    // Map BASIC modes to C fopen modes
    // INPUT -> "r", OUTPUT -> "w", APPEND -> "a"
    var mode_data: [*:0]const u8 = "r";
    if (std.mem.eql(u8, std.mem.span(mode_str), "INPUT")) {
        mode_data = "r";
    } else if (std.mem.eql(u8, std.mem.span(mode_str), "OUTPUT")) {
        mode_data = "w";
    } else if (std.mem.eql(u8, std.mem.span(mode_str), "APPEND")) {
        mode_data = "a";
    } else {
        // Assume it's already a C mode
        mode_data = mode_str;
    }

    const raw = c.malloc(@sizeOf(BasicFile)) orelse {
        basic_error_msg("Out of memory (file allocation)");
        return null;
    };
    const file: *BasicFile = @ptrCast(@alignCast(raw));

    file.filename = strdup(fname_data);
    file.mode = strdup(mode_data);
    file.file_number = 0;
    file.is_open = false;

    file.fp = fopen(fname_data, mode_data);
    if (file.fp == null) {
        if (file.filename) |fn_ptr| c.free(fn_ptr);
        if (file.mode) |m_ptr| c.free(m_ptr);
        c.free(raw);

        var err_msg: [256]u8 = undefined;
        _ = snprintf(&err_msg, err_msg.len, "Cannot open file: %s", fname_data);
        basic_error_msg(@ptrCast(&err_msg));
        return null;
    }

    file.is_open = true;
    _basic_register_file(file);

    return file;
}

export fn file_close(file: ?*BasicFile) callconv(.c) void {
    const f = file orelse return;

    if (f.is_open) {
        if (f.fp) |fp| {
            _ = fclose(fp);
            f.fp = null;
            f.is_open = false;
        }
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

export fn file_print_string(file: ?*BasicFile, str: ?*BasicString) callconv(.c) void {
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

    const s = str orelse return;
    const data = s.data orelse return;
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

export fn file_read_line(file: ?*BasicFile) callconv(.c) ?*anyopaque {
    const f = file orelse {
        basic_error_msg("File not open for reading");
        return str_new("");
    };
    if (!f.is_open) {
        basic_error_msg("File not open for reading");
        return str_new("");
    }
    const fp = f.fp orelse {
        basic_error_msg("File not open for reading");
        return str_new("");
    };

    var buffer: [4096]u8 = undefined;
    if (fgets(&buffer, 4096, fp) == null) {
        return str_new("");
    }

    const len = strlen(@ptrCast(&buffer));
    if (len > 0 and buffer[len - 1] == '\n') {
        buffer[len - 1] = 0;
    }

    return str_new(@ptrCast(&buffer));
}

export fn file_eof(file: ?*BasicFile) callconv(.c) bool {
    const f = file orelse return true;
    if (!f.is_open) return true;
    const fp = f.fp orelse return true;
    return feof(fp) != 0;
}

// =========================================================================
// File Handle Management by Number
// =========================================================================

const MAX_FILE_HANDLES = 256;
var file_handles: [MAX_FILE_HANDLES]?*BasicFile = [_]?*BasicFile{null} ** MAX_FILE_HANDLES;

export fn file_get_handle(file_number: i32) callconv(.c) ?*BasicFile {
    if (file_number < 0 or file_number >= MAX_FILE_HANDLES) {
        basic_error_msg("Invalid file number");
        return null;
    }
    return file_handles[@intCast(file_number)];
}

export fn file_set_handle(file_number: i32, file: ?*BasicFile) callconv(.c) void {
    if (file_number < 0 or file_number >= MAX_FILE_HANDLES) {
        basic_error_msg("Invalid file number");
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
