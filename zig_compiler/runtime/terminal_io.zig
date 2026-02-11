//! Terminal I/O module for FasterBASIC
//! Provides LOCATE, CLS, cursor control, color support, keyboard input, and mouse support
//!
//! This module provides BASIC-style terminal I/O functions including cursor
//! positioning (LOCATE), screen clearing (CLS), color/style control,
//! keyboard input (KBGET, KBHIT, INKEY$), and mouse support.

const std = @import("std");
const builtin = @import("builtin");

// String runtime functions
extern fn string_to_utf8(desc: ?*anyopaque) callconv(.c) [*:0]const u8;

// Terminal state
var terminal_initialized: bool = false;
var raw_mode_enabled: bool = false;
var mouse_enabled: bool = false;

// Current cursor position (1-based, like BASIC)
var current_row: i32 = 1;
var current_col: i32 = 1;

// Paint mode: when true, suppress per-call fflush for batched output.
// Use basic_begin_draw() / basic_end_draw() to bracket screen redraws.
var paint_mode: bool = false;

// Original terminal settings (for restoration)
var original_termios: if (builtin.os.tag != .windows) std.posix.termios else void = undefined;

// Input buffer for escape sequences and keyboard input
var input_buffer: [256]u8 = undefined;
var input_buffer_len: usize = 0;
var input_buffer_pos: usize = 0;

// Mouse state
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;
var mouse_buttons: i32 = 0; // Bit flags: 1=left, 2=middle, 4=right

// Signal state — set by signal handler, checked by kbget
var signal_received: bool = false;

// ═══════════════════════════════════════════════════════════════════════════
// Low-level write functions
// ═══════════════════════════════════════════════════════════════════════════

// C stdio functions for consistent output
extern fn fflush(stream: ?*anyopaque) c_int;
extern fn fprintf(stream: ?*anyopaque, format: [*:0]const u8, ...) c_int;
extern fn fwrite(ptr: [*]const u8, size: usize, nmemb: usize, stream: ?*anyopaque) usize;
extern const __stdoutp: *anyopaque;

// C atexit for registering cleanup on program exit
extern fn atexit(func: *const fn () callconv(.c) void) c_int;

// C signal handling for SIGWINCH (terminal resize)
const SIGWINCH: c_int = 28; // macOS and Linux
extern fn signal(sig: c_int, handler: *const fn (c_int) callconv(.c) void) ?*const fn (c_int) callconv(.c) void;

fn sigwinchHandler(_: c_int) callconv(.c) void {
    signal_received = true;
}

fn writeStdout(bytes: []const u8) void {
    // CRITICAL FIX: Use C stdio for ALL output!
    // This ensures PRINT (which uses printf) and terminal control sequences
    // (LOCATE, colors, etc.) all go through the SAME buffered stream.
    // Mixing printf() with posix.write() causes output reordering because
    // they are different streams (C stdio buffer vs raw file descriptor).

    if (bytes.len == 0) return;

    // Use fwrite instead of fprintf — handles arbitrary lengths, no
    // null-termination needed, and doesn't interpret format specifiers.
    _ = fwrite(bytes.ptr, 1, bytes.len, __stdoutp);

    // In normal mode, flush immediately so ANSI sequences take effect.
    // In paint mode (between begin_draw/end_draw), skip the flush —
    // output accumulates in C stdio's buffer and gets flushed once at
    // the end of the redraw for dramatically fewer syscalls.
    if (!paint_mode) {
        _ = fflush(__stdoutp);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Initialization
// ═══════════════════════════════════════════════════════════════════════════

/// Initialize terminal I/O (called once at program start)
pub export fn terminal_init() void {
    if (terminal_initialized) return;
    terminal_initialized = true;

    // On Windows, enable VT100 escape sequence support
    if (builtin.os.tag == .windows) {
        enableWindowsVTS() catch {};
    } else {
        // Save original terminal settings on Unix
        original_termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return;

        // Install SIGWINCH handler for terminal resize detection
        _ = signal(SIGWINCH, &sigwinchHandler);
    }

    // Register atexit handler so terminal state is ALWAYS restored,
    // even if the program crashes, calls exit(), or forgets to clean up.
    // This prevents leaving the terminal in raw mode with cursor hidden.
    _ = atexit(&atexit_cleanup);
}

/// atexit callback — restores terminal to a sane state on program exit.
/// Safe to call multiple times (terminal_cleanup checks initialized flag).
fn atexit_cleanup() callconv(.c) void {
    terminal_cleanup();
}

/// Cleanup terminal I/O (called at program exit)
pub export fn terminal_cleanup() void {
    if (!terminal_initialized) return;

    // Disable raw mode if enabled
    if (raw_mode_enabled) {
        basic_kbraw(0);
    }

    // Disable mouse if enabled
    if (mouse_enabled) {
        basic_mouse_disable();
    }

    // Show cursor if it was hidden
    basic_cursor_show();

    terminal_initialized = false;
}

// ═══════════════════════════════════════════════════════════════════════════
// BASIC Terminal Functions
// ═══════════════════════════════════════════════════════════════════════════

/// LOCATE row, col - Move cursor to specified position (1-based)
/// In BASIC: LOCATE 10, 20 moves to row 10, column 20
pub export fn basic_locate(row: i32, col: i32) void {
    if (!terminal_initialized) terminal_init();

    current_row = row;
    current_col = col;

    // ANSI escape sequence: ESC[row;colH (1-based coordinates)
    // BASIC uses 0-based coordinates, but ANSI requires 1-based, so we add 1
    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}H", .{ row + 1, col + 1 }) catch return;
    writeStdout(seq);
}

/// CLS - Clear screen and move cursor to home position
pub export fn basic_cls() void {
    if (!terminal_initialized) terminal_init();

    // ANSI: ESC[2J (clear entire screen) + ESC[H (move to home)
    writeStdout("\x1b[2J\x1b[H");
    current_row = 1;
    current_col = 1;
}

/// GCLS - Graphics CLS (alias for CLS in text mode)
pub export fn basic_gcls() void {
    basic_cls();
}

/// Clear from cursor to end of line
pub export fn basic_clear_eol() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[0K");
}

/// Clear from cursor to end of screen
pub export fn basic_clear_eos() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[0J");
}

// ═══════════════════════════════════════════════════════════════════════════
// Cursor Control
// ═══════════════════════════════════════════════════════════════════════════

/// Hide cursor
pub export fn basic_cursor_hide() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[?25l");
}

/// Show cursor
pub export fn basic_cursor_show() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[?25h");
}

/// Save cursor position
pub export fn basic_cursor_save() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[s");
}

/// Restore cursor position
pub export fn basic_cursor_restore() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[u");
}

/// Move cursor up by n rows
pub export fn cursorUp(n: i32) void {
    if (!terminal_initialized) terminal_init();
    if (n <= 0) return;

    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d}A", .{n}) catch return;
    writeStdout(seq);
}

/// Move cursor down by n rows
pub export fn cursorDown(n: i32) void {
    if (!terminal_initialized) terminal_init();
    if (n <= 0) return;

    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d}B", .{n}) catch return;
    writeStdout(seq);
}

/// Move cursor left by n columns
pub export fn cursorLeft(n: i32) void {
    if (!terminal_initialized) terminal_init();
    if (n <= 0) return;

    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d}D", .{n}) catch return;
    writeStdout(seq);
}

/// Move cursor right by n columns
pub export fn cursorRight(n: i32) void {
    if (!terminal_initialized) terminal_init();
    if (n <= 0) return;

    var buf: [32]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d}C", .{n}) catch return;
    writeStdout(seq);
}

// ═══════════════════════════════════════════════════════════════════════════
// Color and Style Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Set foreground color (0-15 for 16-color mode)
pub export fn basic_color(fg: i32) void {
    if (!terminal_initialized) terminal_init();

    var buf: [32]u8 = undefined;
    const code = if (fg >= 8) 90 + (fg - 8) else 30 + fg;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d}m", .{code}) catch return;
    writeStdout(seq);
}

/// Set foreground and background color
pub export fn basic_color_bg(fg: i32, bg: i32) void {
    if (!terminal_initialized) terminal_init();

    var buf: [64]u8 = undefined;
    const fg_code = if (fg >= 8) 90 + (fg - 8) else 30 + fg;
    const bg_code = if (bg >= 8) 100 + (bg - 8) else 40 + bg;
    const seq = std.fmt.bufPrint(&buf, "\x1b[{d};{d}m", .{ fg_code, bg_code }) catch return;
    writeStdout(seq);
}

/// Set RGB foreground color (24-bit true color)
pub export fn basic_color_rgb(r: i32, g: i32, b: i32) void {
    if (!terminal_initialized) terminal_init();

    var buf: [64]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[38;2;{d};{d};{d}m", .{ r, g, b }) catch return;
    writeStdout(seq);
}

/// Set RGB background color (24-bit true color)
pub export fn basic_color_rgb_bg(r: i32, g: i32, b: i32) void {
    if (!terminal_initialized) terminal_init();

    var buf: [64]u8 = undefined;
    const seq = std.fmt.bufPrint(&buf, "\x1b[48;2;{d};{d};{d}m", .{ r, g, b }) catch return;
    writeStdout(seq);
}

/// Reset all colors and styles to default
pub export fn basic_color_reset() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[0m");
}

// ═══════════════════════════════════════════════════════════════════════════
// Text Style Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Enable bold text
pub export fn basic_style_bold() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[1m");
}

/// Enable dim text
pub export fn basic_style_dim() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[2m");
}

/// Enable italic text
pub export fn basic_style_italic() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[3m");
}

/// Enable underline text
pub export fn basic_style_underline() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[4m");
}

/// Enable blinking text
pub export fn basic_style_blink() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[5m");
}

/// Enable reverse video (swap fg/bg)
pub export fn basic_style_reverse() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[7m");
}

/// Disable all text styles
pub export fn basic_style_reset() void {
    basic_color_reset();
}

// ═══════════════════════════════════════════════════════════════════════════
// Screen Buffer Management (Alternate Screen)
// ═══════════════════════════════════════════════════════════════════════════

/// Switch to alternate screen buffer
pub export fn basic_screen_alternate() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[?1049h");
}

/// Switch back to main screen buffer
pub export fn basic_screen_main() void {
    if (!terminal_initialized) terminal_init();
    writeStdout("\x1b[?1049l");
}

// ═══════════════════════════════════════════════════════════════════════════
// Utility Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Get current cursor position (returns row in upper 16 bits, col in lower 16 bits)
/// Note: This requires the terminal to be in raw mode for reading the response
pub export fn basic_get_cursor_pos() i32 {
    // This is a simplified version - full implementation would need terminal raw mode
    // For now, return the tracked position
    return (@as(i32, current_row) << 16) | (@as(i32, current_col) & 0xFFFF);
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Size Detection
// ═══════════════════════════════════════════════════════════════════════════

// C ioctl for terminal size query
extern fn ioctl(fd: c_int, request: c_ulong, ...) c_int;

// TIOCGWINSZ request code (platform-specific)
const TIOCGWINSZ: c_ulong = if (builtin.os.tag == .macos)
    0x40087468 // macOS
else if (builtin.os.tag == .linux)
    0x5413 // Linux
else
    0;

// struct winsize layout: { unsigned short ws_row, ws_col, ws_xpixel, ws_ypixel }
const Winsize = extern struct {
    ws_row: u16,
    ws_col: u16,
    ws_xpixel: u16,
    ws_ypixel: u16,
};

/// Get terminal width (columns). Returns 80 as fallback if detection fails.
pub export fn terminal_get_width() i32 {
    if (builtin.os.tag == .windows) return 80;
    var ws: Winsize = .{ .ws_row = 0, .ws_col = 0, .ws_xpixel = 0, .ws_ypixel = 0 };
    const ret = ioctl(@as(c_int, std.posix.STDOUT_FILENO), TIOCGWINSZ, &ws);
    if (ret == 0 and ws.ws_col > 0) {
        return @intCast(ws.ws_col);
    }
    return 80;
}

/// Get terminal height (rows). Returns 24 as fallback if detection fails.
pub export fn terminal_get_height() i32 {
    if (builtin.os.tag == .windows) return 24;
    var ws: Winsize = .{ .ws_row = 0, .ws_col = 0, .ws_xpixel = 0, .ws_ypixel = 0 };
    const ret = ioctl(@as(c_int, std.posix.STDOUT_FILENO), TIOCGWINSZ, &ws);
    if (ret == 0 and ws.ws_row > 0) {
        return @intCast(ws.ws_row);
    }
    return 24;
}

/// Flush stdout buffer — pushes all pending output to the terminal.
/// Call this after a sequence of WRSTR/WRCH/LOCATE/COLOR calls to
/// ensure everything is visible, especially in paint mode.
pub export fn terminal_flush() void {
    _ = fflush(__stdoutp);
}

/// Explicit flush callable from BASIC as FLUSH
pub export fn basic_flush() void {
    _ = fflush(__stdoutp);
}

/// Begin a batched paint operation.
/// Suppresses per-call fflush so all output (LOCATE, COLOR, WRSTR, WRCH, etc.)
/// accumulates in C stdio's buffer. Call basic_end_draw() when done to flush
/// everything in one go. This dramatically reduces syscalls during screen redraws.
pub export fn basic_begin_draw() void {
    if (!terminal_initialized) terminal_init();
    paint_mode = true;
}

/// End a batched paint operation and flush all accumulated output.
pub export fn basic_end_draw() void {
    paint_mode = false;
    _ = fflush(__stdoutp);
}

/// Query whether paint mode is active (for use by other runtime modules).
/// Returns 1 if in paint mode, 0 otherwise.
pub export fn basic_is_paint_mode() i32 {
    return if (paint_mode) 1 else 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Platform-Specific Support
// ═══════════════════════════════════════════════════════════════════════════

/// Enable Windows VT100 escape sequence support
fn enableWindowsVTS() !void {
    if (builtin.os.tag != .windows) return;

    const windows = std.os.windows;
    const kernel32 = windows.kernel32;

    // Get stdout handle
    const stdout_handle = try windows.GetStdHandle(windows.STD_OUTPUT_HANDLE);

    // Get current console mode
    var mode: windows.DWORD = 0;
    if (kernel32.GetConsoleMode(stdout_handle, &mode) == 0) {
        return error.GetConsoleModeFailed;
    }

    // Enable VT100 processing (ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004)
    const ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
    mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;

    if (kernel32.SetConsoleMode(stdout_handle, mode) == 0) {
        return error.SetConsoleModeFailed;
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Character Output Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Write a single character to stdout (like BBC BASIC WRCH or VDU)
/// Does NOT add newline - writes character as-is
pub export fn basic_wrch(ch: i32) void {
    if (!terminal_initialized) terminal_init();

    var buf: [1]u8 = undefined;
    buf[0] = @intCast(@mod(ch, 256));
    writeStdout(&buf);
}

/// Write a string to stdout without any newline.
/// Uses string_to_utf8 to get the C string from the descriptor,
/// then writes it directly via writeStdout. No printf, no newline.
pub export fn basic_wrstr(desc: ?*anyopaque) void {
    if (!terminal_initialized) terminal_init();
    if (desc == null) return;

    const utf8: [*:0]const u8 = string_to_utf8(desc);
    // Walk the null-terminated string to find length
    var len: usize = 0;
    while (utf8[len] != 0) : (len += 1) {}
    if (len > 0) {
        writeStdout(utf8[0..len]);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Keyboard Input Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Enable/disable raw mode for keyboard input
/// In raw mode: no buffering, no echo, immediate character availability
pub export fn basic_kbraw(enable: i32) void {
    if (!terminal_initialized) terminal_init();

    if (builtin.os.tag == .windows) {
        setWindowsRawMode(enable != 0) catch {};
    } else {
        setUnixRawMode(enable != 0) catch {};
    }

    raw_mode_enabled = (enable != 0);
    signal_received = false;
}

/// Enable/disable keyboard echo
pub export fn basic_kbecho(enable: i32) void {
    if (!terminal_initialized) terminal_init();

    if (builtin.os.tag == .windows) {
        setWindowsEcho(enable != 0) catch {};
    } else {
        setUnixEcho(enable != 0) catch {};
    }
}

/// Check if a key is available (non-blocking)
/// Returns 1 if key available, 0 otherwise
/// Returns -1 if a signal (e.g. SIGWINCH resize) was received
pub export fn basic_kbhit() i32 {
    if (!terminal_initialized) terminal_init();

    // Check for signal first (e.g. SIGWINCH terminal resize)
    if (signal_received) {
        return -1;
    }

    // Check if we have buffered input
    if (input_buffer_pos < input_buffer_len) {
        return 1;
    }

    // Try to read without blocking
    if (builtin.os.tag == .windows) {
        return checkWindowsKeyAvailable();
    } else {
        return checkUnixKeyAvailable();
    }
}

/// Clear the signal flag (call after handling resize etc.)
pub export fn basic_signal_clear() void {
    signal_received = false;
}

/// Check if a signal was received (e.g. SIGWINCH)
pub export fn basic_signal_check() i32 {
    return if (signal_received) 1 else 0;
}

/// Get a single character from keyboard (blocking)
/// Returns ASCII code, or special key codes for function keys, arrows, etc.
/// Returns 0 if interrupted by a signal (e.g. SIGWINCH for terminal resize)
/// Returns -1 on error
pub export fn basic_kbget() i32 {
    if (!terminal_initialized) terminal_init();

    // Return buffered character if available
    if (input_buffer_pos < input_buffer_len) {
        const ch = input_buffer[input_buffer_pos];
        input_buffer_pos += 1;
        if (input_buffer_pos >= input_buffer_len) {
            input_buffer_len = 0;
            input_buffer_pos = 0;
        }
        return @intCast(ch);
    }

    // Read from stdin — with VMIN=0, VTIME=1 this will return after
    // 0.1 seconds if no data is available, allowing signal handling
    var buf: [1]u8 = undefined;

    if (builtin.os.tag == .windows) {
        const stdin = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return -1;
        var bytes_read: std.os.windows.DWORD = 0;
        if (std.os.windows.kernel32.ReadFile(stdin, &buf, 1, &bytes_read, null) == 0) return -1;
        if (bytes_read == 0) return -1;
    } else {
        // Loop until we get a character, handling signals (EINTR) and
        // VTIME timeouts (read returns 0) gracefully
        while (true) {
            // Check for pending signal before blocking
            if (signal_received) {
                return 0; // Signal received — caller should handle (e.g. resize)
            }

            const n = std.posix.read(std.posix.STDIN_FILENO, &buf) catch |err| {
                if (err == std.posix.ReadError.WouldBlock) {
                    // VTIME timeout — no data yet, loop and check signals
                    continue;
                }
                // For EINTR (signal during read), Zig's posix.read retries
                // automatically, but if we get here it's a real error
                return -1;
            };
            if (n == 0) {
                // VTIME timeout expired with no data — check for signals
                // and loop back to try again (this is normal with VMIN=0, VTIME=1)
                if (signal_received) {
                    return 0;
                }
                continue;
            }
            break; // Got a character
        }
    }

    const ch = buf[0];

    // Handle escape sequences (arrow keys, function keys, mouse events)
    if (ch == 0x1B) { // ESC
        return parseEscapeSequence();
    }

    return @intCast(ch);
}

/// Peek at the next character without consuming it
/// Returns ASCII code, or -1 if no character available
pub export fn basic_kbpeek() i32 {
    if (!terminal_initialized) terminal_init();

    if (input_buffer_pos < input_buffer_len) {
        return @intCast(input_buffer[input_buffer_pos]);
    }

    if (basic_kbhit() == 0) return -1;

    // Read and buffer the character
    const ch = basic_kbget();
    if (ch >= 0) {
        // Put it back in the buffer
        input_buffer[0] = @intCast(ch);
        input_buffer_len = 1;
        input_buffer_pos = 0;
    }
    return ch;
}

/// Get special key code from last key press
/// Returns key code for function keys, arrows, etc.
pub export fn basic_kbcode() i32 {
    // This would return the last special key code
    // For now, use basic_kbget() which returns special codes directly
    return 0;
}

/// Check if last key was a special key (arrow, function key, etc.)
/// Returns 1 if special, 0 if normal ASCII
pub export fn basic_kbspecial() i32 {
    // Special keys have codes > 255
    return 0;
}

/// Get modifier key state (Shift, Ctrl, Alt)
/// Returns bit flags: 1=Shift, 2=Ctrl, 4=Alt
pub export fn basic_kbmod() i32 {
    // This would require tracking modifier state from escape sequences
    // Not implemented in basic version
    return 0;
}

/// Flush keyboard input buffer
pub export fn basic_kbflush() void {
    if (!terminal_initialized) terminal_init();

    input_buffer_len = 0;
    input_buffer_pos = 0;

    // Drain any pending input
    if (builtin.os.tag != .windows) {
        var buf: [256]u8 = undefined;
        while (checkUnixKeyAvailable() > 0) {
            _ = std.posix.read(std.posix.STDIN_FILENO, &buf) catch break;
        }
    }
}

/// Clear keyboard input buffer (alias for flush)
pub export fn basic_kbclear() void {
    basic_kbflush();
}

/// Get count of characters in keyboard buffer
pub export fn basic_kbcount() i32 {
    if (input_buffer_pos < input_buffer_len) {
        return @intCast(input_buffer_len - input_buffer_pos);
    }
    return 0;
}

/// INKEY$ - Get a character if available, empty string otherwise
/// Returns pointer to static string buffer (single character or empty)
var inkey_buffer: [2:0]u8 = [_:0]u8{ 0, 0 };
pub export fn basic_inkey() [*:0]const u8 {
    if (basic_kbhit() > 0) {
        const ch = basic_kbget();
        if (ch >= 0 and ch <= 255) {
            inkey_buffer[0] = @intCast(ch);
            inkey_buffer[1] = 0;
            return @ptrCast(&inkey_buffer);
        }
    }
    inkey_buffer[0] = 0;
    return @ptrCast(&inkey_buffer);
}

// ═══════════════════════════════════════════════════════════════════════════
// Terminal Position Query Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Get current cursor column position (1-based)
pub export fn basic_pos() i32 {
    return current_col;
}

/// Get current cursor row position (1-based)
pub export fn basic_row() i32 {
    return current_row;
}

/// Get current cursor row (alias for ROW, QBasic style)
pub export fn basic_csrlin() i32 {
    return current_row;
}

// ═══════════════════════════════════════════════════════════════════════════
// Mouse Support Functions
// ═══════════════════════════════════════════════════════════════════════════

/// Enable mouse reporting
pub export fn basic_mouse_enable() void {
    if (!terminal_initialized) terminal_init();

    // Enable mouse tracking (X10 mode + button event tracking + any event tracking)
    writeStdout("\x1b[?1000h"); // Basic mouse tracking
    writeStdout("\x1b[?1002h"); // Button event tracking
    writeStdout("\x1b[?1003h"); // Any event tracking
    writeStdout("\x1b[?1006h"); // SGR extended mode

    mouse_enabled = true;
}

/// Disable mouse reporting
pub export fn basic_mouse_disable() void {
    if (!terminal_initialized) return;

    writeStdout("\x1b[?1000l");
    writeStdout("\x1b[?1002l");
    writeStdout("\x1b[?1003l");
    writeStdout("\x1b[?1006l");

    mouse_enabled = false;
}

/// Get mouse X position (column, 1-based)
pub export fn basic_mouse_x() i32 {
    return mouse_x;
}

/// Get mouse Y position (row, 1-based)
pub export fn basic_mouse_y() i32 {
    return mouse_y;
}

/// Get mouse button state
/// Returns bit flags: 1=left, 2=middle, 4=right, 8=motion, 16=wheel_up, 32=wheel_down
pub export fn basic_mouse_buttons() i32 {
    return mouse_buttons;
}

/// Check if mouse button is pressed
/// button: 1=left, 2=middle, 3=right
pub export fn basic_mouse_button(button: i32) i32 {
    const mask: i32 = switch (button) {
        1 => 1, // left
        2 => 2, // middle
        3 => 4, // right
        else => 0,
    };
    return if ((mouse_buttons & mask) != 0) 1 else 0;
}

/// Poll for mouse events (non-blocking)
/// Returns 1 if mouse event occurred, 0 otherwise
pub export fn basic_mouse_poll() i32 {
    if (!mouse_enabled) return 0;

    // Check if escape sequence is available
    if (basic_kbhit() > 0) {
        const ch = basic_kbpeek();
        if (ch == 0x1B) {
            // Might be mouse event - try to parse it
            _ = basic_kbget(); // consume ESC
            _ = parseEscapeSequence();
            return 1;
        }
    }

    return 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Platform-Specific Keyboard Support
// ═══════════════════════════════════════════════════════════════════════════

fn setUnixRawMode(enable: bool) !void {
    if (builtin.os.tag == .windows) return;

    if (enable) {
        var raw = original_termios;

        // Disable canonical mode, echo, signals
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;

        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;

        // Keep output processing enabled so ANSI escape codes work
        // (cursor positioning, colors, etc.)
        raw.oflag.OPOST = true;

        // Enable ONLCR: map NL to CR-NL on output (required for proper line breaks)
        raw.oflag.ONLCR = true;

        // Set character size to 8 bits
        raw.cflag.CSIZE = .CS8;

        // CRITICAL FIX: Match the working C++ terminal_io settings.
        // VMIN=0, VTIME=1 means:
        //   - read() returns immediately if data is available
        //   - read() returns 0 after 0.1 seconds if no data (timeout)
        //   - read() NEVER blocks forever
        // This enables responsive signal handling (SIGWINCH for resize),
        // proper escape sequence parsing, and event-loop-style architecture.
        //
        // The old VMIN=1, VTIME=0 caused read() to block forever, making
        // it impossible to handle signals, timeouts, or build an editor.
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 0;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 0.1 second timeout

        // Use TCSANOW for immediate effect (better for macOS than FLUSH)
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw);
    } else {
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, original_termios);
    }
}

fn setUnixEcho(enable: bool) !void {
    if (builtin.os.tag == .windows) return;

    var current = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    current.lflag.ECHO = enable;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, current);
}

fn checkUnixKeyAvailable() i32 {
    if (builtin.os.tag == .windows) return 0;

    // Check for pending signal (e.g. SIGWINCH)
    if (signal_received) return -1;

    var fds: [1]std.posix.pollfd = [_]std.posix.pollfd{
        .{
            .fd = std.posix.STDIN_FILENO,
            .events = std.posix.POLL.IN,
            .revents = 0,
        },
    };

    const result = std.posix.poll(&fds, 0) catch return 0;
    return if (result > 0 and (fds[0].revents & std.posix.POLL.IN) != 0) 1 else 0;
}

fn setWindowsRawMode(enable: bool) !void {
    if (builtin.os.tag != .windows) return;

    const windows = std.os.windows;
    const stdin_handle = try windows.GetStdHandle(windows.STD_INPUT_HANDLE);

    var mode: windows.DWORD = 0;
    if (windows.kernel32.GetConsoleMode(stdin_handle, &mode) == 0) return;

    if (enable) {
        // Disable line input, echo input, and processed input
        mode &= ~@as(windows.DWORD, 0x0002); // ENABLE_LINE_INPUT
        mode &= ~@as(windows.DWORD, 0x0004); // ENABLE_ECHO_INPUT
        mode &= ~@as(windows.DWORD, 0x0001); // ENABLE_PROCESSED_INPUT
        mode |= 0x0200; // ENABLE_VIRTUAL_TERMINAL_INPUT
    } else {
        mode |= 0x0002 | 0x0004 | 0x0001;
    }

    _ = windows.kernel32.SetConsoleMode(stdin_handle, mode);
}

fn setWindowsEcho(enable: bool) !void {
    if (builtin.os.tag != .windows) return;

    const windows = std.os.windows;
    const stdin_handle = try windows.GetStdHandle(windows.STD_INPUT_HANDLE);

    var mode: windows.DWORD = 0;
    if (windows.kernel32.GetConsoleMode(stdin_handle, &mode) == 0) return;

    if (enable) {
        mode |= 0x0004; // ENABLE_ECHO_INPUT
    } else {
        mode &= ~@as(windows.DWORD, 0x0004);
    }

    _ = windows.kernel32.SetConsoleMode(stdin_handle, mode);
}

fn checkWindowsKeyAvailable() i32 {
    if (builtin.os.tag != .windows) return 0;

    const windows = std.os.windows;
    const stdin_handle = windows.GetStdHandle(windows.STD_INPUT_HANDLE) catch return 0;

    var num_events: windows.DWORD = 0;
    if (windows.kernel32.GetNumberOfConsoleInputEvents(stdin_handle, &num_events) == 0) {
        return 0;
    }

    return if (num_events > 0) 1 else 0;
}

// ═══════════════════════════════════════════════════════════════════════════
// Escape Sequence Parsing
// ═══════════════════════════════════════════════════════════════════════════

// Special key codes (compatible with many BASIC implementations)
const KEY_UP: i32 = 256 + 72;
const KEY_DOWN: i32 = 256 + 80;
const KEY_LEFT: i32 = 256 + 75;
const KEY_RIGHT: i32 = 256 + 77;
const KEY_HOME: i32 = 256 + 71;
const KEY_END: i32 = 256 + 79;
const KEY_PAGEUP: i32 = 256 + 73;
const KEY_PAGEDOWN: i32 = 256 + 81;
const KEY_INSERT: i32 = 256 + 82;
const KEY_DELETE: i32 = 256 + 83;
const KEY_F1: i32 = 256 + 59;
const KEY_F2: i32 = 256 + 60;
const KEY_F3: i32 = 256 + 61;
const KEY_F4: i32 = 256 + 62;
const KEY_F5: i32 = 256 + 63;
const KEY_F6: i32 = 256 + 64;
const KEY_F7: i32 = 256 + 65;
const KEY_F8: i32 = 256 + 66;
const KEY_F9: i32 = 256 + 67;
const KEY_F10: i32 = 256 + 68;
const KEY_F11: i32 = 256 + 133;
const KEY_F12: i32 = 256 + 134;

fn parseEscapeSequence() i32 {
    // Parse escape sequence after ESC (0x1B) has been read.
    //
    // ARCHITECTURE: Use poll() to check for data availability BEFORE each
    // read, just like the working C++ shell does with kbhit()+select().
    // This is instant (no 100ms delay for standalone ESC) and doesn't
    // require changing terminal settings back and forth.
    //
    // With VMIN=0, VTIME=1 already set in raw mode, reads will also
    // time out naturally, but poll() gives us a faster path.

    var buf: [16]u8 = undefined;
    var len: usize = 0;

    // Read up to 16 bytes for the escape sequence
    while (len < buf.len) {
        var ch: [1]u8 = undefined;

        if (builtin.os.tag == .windows) {
            const stdin = std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return 0x1B;
            var bytes_read: std.os.windows.DWORD = 0;
            if (std.os.windows.kernel32.ReadFile(stdin, &ch, 1, &bytes_read, null) == 0) break;
            if (bytes_read == 0) break;
        } else {
            // Use poll() with a short timeout to check if more data is available.
            // This mirrors the C++ kbhit() pattern: instant return if no data,
            // no need to temporarily change VMIN/VTIME terminal settings.
            //
            // First byte after ESC: use a slightly longer timeout (50ms) to
            // allow escape sequences from arrow keys to arrive.
            // Subsequent bytes: use a very short timeout (10ms) since they
            // should arrive almost immediately if they're coming.
            const timeout_ms: i32 = if (len == 0) 50 else 10;
            var fds: [1]std.posix.pollfd = [_]std.posix.pollfd{
                .{
                    .fd = std.posix.STDIN_FILENO,
                    .events = std.posix.POLL.IN,
                    .revents = 0,
                },
            };

            const poll_result = std.posix.poll(&fds, timeout_ms) catch break;
            if (poll_result == 0 or (fds[0].revents & std.posix.POLL.IN) == 0) {
                // Timeout — no more data coming, sequence is complete
                break;
            }

            // Data is available, read it (should not block)
            const n = std.posix.read(std.posix.STDIN_FILENO, &ch) catch break;
            if (n == 0) break;
        }

        buf[len] = ch[0];
        len += 1;

        // Check if we have a complete sequence
        if (len >= 2) {
            // CSI sequences: ESC [ ...
            if (buf[0] == '[') {
                // Mouse event: ESC [ < Cb ; Cx ; Cy M/m
                if (len >= 2 and buf[1] == '<') {
                    return parseMouseEvent(buf[0..len]);
                }

                // Arrow keys and other sequences
                if (len >= 2) {
                    const last = buf[len - 1];

                    // Single char sequences (complete when letter or ~ is found)
                    if ((last >= 'A' and last <= 'Z') or (last >= 'a' and last <= 'z') or last == '~') {
                        return parseCSISequence(buf[0..len]);
                    }
                }
            }
            // SS3 sequences: ESC O ...
            else if (buf[0] == 'O' and len >= 2) {
                return parseSS3Sequence(buf[0..len]);
            }
        }

        // Safety limit to avoid reading too much
        if (len >= 8) break;
    }

    // If we only got ESC or couldn't parse, return ESC
    // This happens when ESC is pressed alone (poll times out with len == 0)
    return 0x1B;
}

fn parseCSISequence(seq: []const u8) i32 {
    if (seq.len < 2 or seq[0] != '[') return 0x1B;

    const last = seq[seq.len - 1];

    // Arrow keys: ESC [ A/B/C/D
    switch (last) {
        'A' => return KEY_UP,
        'B' => return KEY_DOWN,
        'C' => return KEY_RIGHT,
        'D' => return KEY_LEFT,
        'H' => return KEY_HOME,
        'F' => return KEY_END,
        else => {},
    }

    // Sequences ending with ~
    if (last == '~' and seq.len >= 3) {
        const num_start: usize = 1;
        var num_end: usize = 1;
        while (num_end < seq.len - 1 and seq[num_end] >= '0' and seq[num_end] <= '9') {
            num_end += 1;
        }

        const num_str = seq[num_start..num_end];
        const num = std.fmt.parseInt(i32, num_str, 10) catch return 0x1B;

        return switch (num) {
            1 => KEY_HOME,
            2 => KEY_INSERT,
            3 => KEY_DELETE,
            4 => KEY_END,
            5 => KEY_PAGEUP,
            6 => KEY_PAGEDOWN,
            11 => KEY_F1,
            12 => KEY_F2,
            13 => KEY_F3,
            14 => KEY_F4,
            15 => KEY_F5,
            17 => KEY_F6,
            18 => KEY_F7,
            19 => KEY_F8,
            20 => KEY_F9,
            21 => KEY_F10,
            23 => KEY_F11,
            24 => KEY_F12,
            else => 0x1B,
        };
    }

    return 0x1B;
}

fn parseSS3Sequence(seq: []const u8) i32 {
    if (seq.len < 2 or seq[0] != 'O') return 0x1B;

    // Function keys: ESC O P/Q/R/S = F1-F4
    switch (seq[1]) {
        'P' => return KEY_F1,
        'Q' => return KEY_F2,
        'R' => return KEY_F3,
        'S' => return KEY_F4,
        'H' => return KEY_HOME,
        'F' => return KEY_END,
        else => return 0x1B,
    }
}

fn parseMouseEvent(seq: []const u8) i32 {
    // Mouse event format: ESC [ < Cb ; Cx ; Cy M/m
    // Cb = button code, Cx = x coordinate, Cy = y coordinate
    // M = button press, m = button release

    if (seq.len < 7 or seq[0] != '[' or seq[1] != '<') return 0x1B;

    // Find the M or m at the end
    const last = seq[seq.len - 1];
    const is_press = (last == 'M');
    const is_release = (last == 'm');

    if (!is_press and !is_release) return 0x1B;

    // Parse the three numbers: Cb;Cx;Cy
    var pos: usize = 2; // Skip "ESC [ <"
    var nums: [3]i32 = [_]i32{ 0, 0, 0 };
    var num_idx: usize = 0;

    while (pos < seq.len - 1 and num_idx < 3) {
        const start = pos;
        while (pos < seq.len - 1 and seq[pos] >= '0' and seq[pos] <= '9') {
            pos += 1;
        }

        if (pos > start) {
            nums[num_idx] = std.fmt.parseInt(i32, seq[start..pos], 10) catch 0;
            num_idx += 1;
        }

        if (pos < seq.len - 1 and seq[pos] == ';') {
            pos += 1;
        } else {
            break;
        }
    }

    if (num_idx == 3) {
        const button_code = nums[0];
        mouse_x = nums[1];
        mouse_y = nums[2];

        // Decode button code
        const button = button_code & 0x03;
        const modifiers = button_code & 0xFC;

        if (is_press) {
            mouse_buttons = switch (button) {
                0 => 1, // left
                1 => 2, // middle
                2 => 4, // right
                3 => if ((modifiers & 0x40) != 0) 16 else 32, // wheel up/down
                else => 0,
            };
        } else {
            mouse_buttons = 0;
        }

        // Return a special mouse event code
        return 0x10000 + button_code;
    }

    return 0x1B;
}

// ═══════════════════════════════════════════════════════════════════════════
// Testing
// ═══════════════════════════════════════════════════════════════════════════

/// Wait for a key with timeout (in milliseconds).
/// Returns the key code, 0 if timeout expired, or -1 on error.
/// This is useful for editor main loops that need to poll for keys
/// while also handling signals and redraws.
pub export fn basic_kbwait(timeout_ms: i32) i32 {
    if (!terminal_initialized) terminal_init();

    // Check buffered input first
    if (input_buffer_pos < input_buffer_len) {
        return basic_kbget();
    }

    // Check for pending signal
    if (signal_received) return 0;

    if (builtin.os.tag != .windows) {
        var fds: [1]std.posix.pollfd = [_]std.posix.pollfd{
            .{
                .fd = std.posix.STDIN_FILENO,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };

        const poll_result = std.posix.poll(&fds, timeout_ms) catch return -1;
        if (poll_result == 0) {
            // Timeout — check for signal
            if (signal_received) return 0;
            return 0; // No key available
        }

        if ((fds[0].revents & std.posix.POLL.IN) != 0) {
            return basic_kbget();
        }

        return 0;
    } else {
        // Windows: just use basic_kbget for now
        if (basic_kbhit() > 0) {
            return basic_kbget();
        }
        return 0;
    }
}

test "terminal_io basic functions" {
    // These are export functions that will be called from compiled BASIC programs
    // We just verify they compile correctly
    const testing = std.testing;
    _ = testing;
}
