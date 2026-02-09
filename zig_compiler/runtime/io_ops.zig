//
// io_ops.zig
// FasterBASIC Runtime — Console & File I/O Operations
//
// Console output (print int/float/string/newline/tab/hex/pointer),
// terminal control (CLS, LOCATE, COLOR, WIDTH),
// console input (INPUT, LINE INPUT, INKEY$),
// file operations (OPEN, CLOSE, PRINT#, READ LINE, EOF).
//

const std = @import("std");
const c = std.c;

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
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn strlen(s: [*:0]const u8) usize;
extern fn putchar(ch: c_int) c_int;

// stdout
extern const __stdoutp: *anyopaque;
extern const __stdinp: *anyopaque;

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
    _ = fflush(__stdoutp);
}

export fn basic_print_long(value: i64) callconv(.c) void {
    _ = printf("%lld", value);
    _ = fflush(__stdoutp);
}

export fn basic_print_float(value: f32) callconv(.c) void {
    _ = printf("%g", @as(f64, value));
    _ = fflush(__stdoutp);
}

export fn basic_print_double(value: f64) callconv(.c) void {
    _ = printf("%g", value);
    _ = fflush(__stdoutp);
}

export fn basic_print_string(str: ?*BasicString) callconv(.c) void {
    const s = str orelse return;
    const data = s.data orelse return;
    _ = printf("%s", data);
    _ = fflush(__stdoutp);
}

export fn basic_print_cstr(str: ?[*:0]const u8) callconv(.c) void {
    const s = str orelse return;
    _ = printf("%s", s);
    _ = fflush(__stdoutp);
}

export fn basic_print_string_desc(desc: ?*anyopaque) callconv(.c) void {
    const d = desc orelse return;
    const utf8 = string_to_utf8(d);
    _ = printf("%s", utf8);
    _ = fflush(__stdoutp);
}

export fn basic_print_hex(value: i64) callconv(.c) void {
    _ = printf("0x%llx", value);
    _ = fflush(__stdoutp);
}

export fn basic_print_pointer(ptr: ?*anyopaque) callconv(.c) void {
    _ = printf("0x%llx", @intFromPtr(ptr));
    _ = fflush(__stdoutp);
}

export fn debug_print_hashmap(map: ?*anyopaque) callconv(.c) void {
    _ = printf("[HASHMAP@");
    basic_print_pointer(map);
    _ = printf("]");
    _ = fflush(__stdoutp);
}

export fn basic_print_newline() callconv(.c) void {
    _ = printf("\n");
    _ = fflush(__stdoutp);
}

export fn basic_print_tab() callconv(.c) void {
    _ = printf("\t");
    _ = fflush(__stdoutp);
}

export fn basic_print_at(row: i32, col: i32, str: ?*BasicString) callconv(.c) void {
    _ = printf("\x1b[%d;%dH", row, col);
    if (str) |s| {
        if (s.data) |data| {
            _ = printf("%s", data);
        }
    }
    _ = fflush(__stdoutp);
}

export fn basic_cls() callconv(.c) void {
    _ = printf("\x1b[2J\x1b[H");
    _ = fflush(__stdoutp);
}

// =========================================================================
// Terminal Control
// =========================================================================

export fn basic_locate(row: i32, col: i32) callconv(.c) void {
    _ = printf("\x1b[%d;%dH", row, col);
    _ = fflush(__stdoutp);
}

export fn basic_color(foreground: i32, background: i32) callconv(.c) void {
    var fg: i32 = 30;
    var bg: i32 = 40;

    if (foreground >= 8) {
        fg = 90 + (foreground - 8);
    } else if (foreground >= 0) {
        fg = 30 + foreground;
    }

    if (background >= 8) {
        bg = 100 + (background - 8);
    } else if (background >= 0) {
        bg = 40 + background;
    }

    _ = printf("\x1b[%d;%dm", fg, bg);
    _ = fflush(__stdoutp);
}

var g_terminal_width: i32 = 80;

export fn basic_width(columns: i32) callconv(.c) void {
    if (columns > 0) g_terminal_width = columns;
}

export fn basic_get_width() callconv(.c) i32 {
    return g_terminal_width;
}

var g_cursor_row: i32 = 1;
var g_cursor_col: i32 = 1;

export fn basic_csrlin() callconv(.c) i32 {
    return g_cursor_row;
}

export fn basic_pos(dummy: i32) callconv(.c) i32 {
    _ = dummy;
    return g_cursor_col;
}

export fn _basic_update_cursor_pos(row: i32, col: i32) callconv(.c) void {
    g_cursor_row = row;
    g_cursor_col = col;
}

// =========================================================================
// INKEY$ — Non-blocking keyboard input
// =========================================================================

export fn basic_inkey() callconv(.c) ?*anyopaque {
    // Set stdin to non-blocking mode
    const flags = fcntl(STDIN_FILENO, F_GETFL, @as(c_int, 0));
    _ = fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);

    // Try to read one character
    var ch: [1]u8 = undefined;
    const n = read(STDIN_FILENO, &ch, 1);

    // Restore blocking mode
    _ = fcntl(STDIN_FILENO, F_SETFL, flags);

    if (n == 1) {
        var str_buf: [2]u8 = .{ ch[0], 0 };
        return string_new_utf8(@ptrCast(&str_buf));
    }

    return string_new_utf8("");
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

export fn file_open(filename: ?*BasicString, mode: ?*BasicString) callconv(.c) ?*BasicFile {
    const fname = filename orelse {
        basic_error_msg("Invalid file open parameters");
        return null;
    };
    const m = mode orelse {
        basic_error_msg("Invalid file open parameters");
        return null;
    };
    const fname_data = fname.data orelse {
        basic_error_msg("Invalid file open parameters");
        return null;
    };
    const mode_data = m.data orelse {
        basic_error_msg("Invalid file open parameters");
        return null;
    };

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
