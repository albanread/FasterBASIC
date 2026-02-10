//
// io_ops_format.zig
// FasterBASIC Runtime — PRINT USING Implementation
//
// Full numeric formatting support: masks with #, commas, $$, **,
// +, trailing -, and ^^^^ (scientific notation).
//

const std = @import("std");
const c = std.c;

// =========================================================================
// Extern declarations
// =========================================================================

extern fn basic_error_msg(msg: [*:0]const u8) void;
extern fn string_to_utf8(str: ?*anyopaque) [*:0]const u8;

// C library
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn strtod(nptr: [*:0]const u8, endptr: ?*[*:0]const u8) f64;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern fn printf(fmt: [*:0]const u8, ...) c_int;
extern fn putchar(ch: c_int) c_int;
extern fn fflush(stream: ?*anyopaque) c_int;
extern fn strchr(s: [*:0]const u8, ch: c_int) ?[*:0]const u8;
extern fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*:0]const u8;
extern fn strncmp(s1: [*:0]const u8, s2: [*:0]const u8, n: usize) c_int;
extern fn strlen(s: [*:0]const u8) usize;
extern fn isspace(ch: c_int) c_int;

// Zig std.c imports
extern fn fabs(x: f64) f64;

// stdout
extern const __stdoutp: *anyopaque;

// Paint mode query from terminal_io.zig — when paint mode is active,
// we skip per-call fflush to allow output batching (BEGINPAINT/ENDPAINT).
extern fn basic_is_paint_mode() i32;

fn flushIfNeeded() void {
    if (basic_is_paint_mode() == 0) {
        _ = fflush(__stdoutp);
    }
}

// =========================================================================
// StringDescriptor — opaque to this module, accessed via string_to_utf8
// =========================================================================

const StringDescriptor = anyopaque;

// =========================================================================
// Internal helpers
// =========================================================================

/// Reverse a byte slice in place
fn reverseSlice(s: []u8) void {
    if (s.len <= 1) return;
    var i: usize = 0;
    var j: usize = s.len - 1;
    while (i < j) {
        const tmp = s[i];
        s[i] = s[j];
        s[j] = tmp;
        i += 1;
        j -= 1;
    }
}

/// Find length of a null-terminated C string in a buffer
fn cstrLen(buf: [*]const u8, max: usize) usize {
    var i: usize = 0;
    while (i < max and buf[i] != 0) : (i += 1) {}
    return i;
}

/// Check if a character is whitespace
fn isSpaceChar(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r';
}

/// Format a numeric value according to a mask pattern
fn formatNumeric(output: [*]u8, output_size: usize, mask: [*:0]const u8, value_str: [*:0]const u8) void {
    // Try to parse value as a number
    var endptr: [*:0]const u8 = undefined;
    const value = strtod(value_str, &endptr);
    const is_numeric = (endptr[0] == 0 or isspace(@intCast(endptr[0])) != 0);

    if (!is_numeric) {
        // Not a number - just copy the value
        _ = snprintf(output, output_size, "%s", value_str);
        return;
    }

    const is_neg = (value < 0);
    const abs_val = fabs(value);

    // Analyze mask features
    const mask_len = strlen(mask);
    const has_comma = (strchr(mask, ',') != null);
    const has_plus = (mask[0] == '+');
    const has_minus_suffix = (mask_len > 0 and mask[mask_len - 1] == '-');
    const has_exp = (strstr(mask, "^^^^") != null);
    const has_dollar = (strstr(mask, "$$") != null);
    const has_asterisk = (strstr(mask, "**") != null);

    // Determine precision
    var precision: c_int = 0;
    const dot = strchr(mask, '.');
    if (dot) |dot_ptr| {
        var p: [*:0]const u8 = @ptrCast(dot_ptr);
        p += 1; // skip '.'
        while (p[0] == '#' or p[0] == '^') {
            precision += 1;
            p += 1;
        }
    }

    // Core conversion
    var work: [128]u8 = undefined;
    if (has_exp) {
        _ = snprintf(&work, work.len, "%.*E", precision, value);
    } else {
        _ = snprintf(&work, work.len, "%.*f", precision, abs_val);
    }
    const work_len = cstrLen(&work, work.len);

    // Manual comma insertion (integer part only)
    var comma_buf: [128]u8 = undefined;
    if (has_comma and !has_exp) {
        // Find the dot in work
        var dot_pos: usize = work_len;
        for (work[0..work_len], 0..) |ch, idx| {
            if (ch == '.') {
                dot_pos = idx;
                break;
            }
        }
        const int_len = dot_pos;

        // Build reversed with commas
        var temp: [128]u8 = .{0} ** 128;
        var dst: usize = 0;
        var count: usize = 0;
        var src_i: usize = int_len;
        while (src_i > 0) {
            src_i -= 1;
            if (count > 0 and count % 3 == 0 and dst < temp.len - 1) {
                temp[dst] = ',';
                dst += 1;
            }
            if (dst < temp.len - 1) {
                temp[dst] = work[src_i];
                dst += 1;
            }
            count += 1;
        }
        temp[dst] = 0;
        reverseSlice(temp[0..dst]);

        // Append decimal part
        if (dot_pos < work_len) {
            var k: usize = dot_pos;
            while (k < work_len and dst < temp.len - 1) {
                temp[dst] = work[k];
                dst += 1;
                k += 1;
            }
            temp[dst] = 0;
        }

        @memcpy(comma_buf[0..dst], temp[0..dst]);
        comma_buf[dst] = 0;
        @memcpy(work[0 .. dst + 1], comma_buf[0 .. dst + 1]);
    }

    // Decorations (Sign, $, *)
    var decorated: [256]u8 = .{0} ** 256;
    var dec_pos: usize = 0;

    // Prefix: sign
    if (has_plus) {
        if (is_neg) {
            decorated[dec_pos] = '-';
        } else {
            decorated[dec_pos] = '+';
        }
        dec_pos += 1;
    } else if (is_neg and !has_minus_suffix) {
        decorated[dec_pos] = '-';
        dec_pos += 1;
    }

    // Prefix: dollar
    if (has_dollar) {
        decorated[dec_pos] = '$';
        dec_pos += 1;
    }

    // Copy work string
    const final_work_len = cstrLen(&work, work.len);
    for (work[0..final_work_len]) |ch| {
        if (dec_pos < decorated.len - 1) {
            decorated[dec_pos] = ch;
            dec_pos += 1;
        }
    }

    // Suffix: trailing minus
    if (is_neg and has_minus_suffix) {
        if (dec_pos < decorated.len - 1) {
            decorated[dec_pos] = '-';
            dec_pos += 1;
        }
    }
    decorated[dec_pos] = 0;

    // Padding logic
    const actual_len = dec_pos;
    if (actual_len > mask_len) {
        // Overflow - prefix with %
        output[0] = '%';
        var i: usize = 0;
        while (i < actual_len and i + 1 < output_size - 1) {
            output[i + 1] = decorated[i];
            i += 1;
        }
        output[i + 1] = 0;
    } else {
        const pad = mask_len - actual_len;
        const pad_char: u8 = if (has_asterisk) '*' else ' ';
        var i: usize = 0;
        while (i < pad and i < output_size - 1) {
            output[i] = pad_char;
            i += 1;
        }
        var j: usize = 0;
        while (j < actual_len and i < output_size - 1) {
            output[i] = decorated[j];
            i += 1;
            j += 1;
        }
        output[i] = 0;
    }
}

/// Extract a format pattern starting at position p.
/// Returns the length of the pattern (0 if not a pattern).
fn extractPattern(p: [*:0]const u8, pattern: [*]u8, pattern_size: usize) usize {
    var offset: usize = 0;
    var len: usize = 0;

    // Check for leading +, $$, or **
    if (p[0] == '+') {
        pattern[0] = '+';
        len = 1;
        offset = 1;
    } else if (p[0] == '$' and p[1] == '$') {
        pattern[0] = '$';
        pattern[1] = '$';
        len = 2;
        offset = 2;
    } else if (p[0] == '*' and p[1] == '*') {
        pattern[0] = '*';
        pattern[1] = '*';
        len = 2;
        offset = 2;
    }

    // Collect #, comma, and decimal point
    while (true) {
        const ch = p[offset];
        if (ch != '#' and ch != ',' and ch != '.') break;
        if (len < pattern_size - 1) {
            pattern[len] = ch;
            len += 1;
        }
        offset += 1;
    }

    // Check for ^^^^
    if (strncmp(@ptrCast(p + offset), "^^^^", 4) == 0) {
        if (len + 4 < pattern_size) {
            pattern[len] = '^';
            pattern[len + 1] = '^';
            pattern[len + 2] = '^';
            pattern[len + 3] = '^';
            len += 4;
        }
        offset += 4;
    }

    // Check for trailing -
    if (p[offset] == '-') {
        if (len < pattern_size - 1) {
            pattern[len] = '-';
            len += 1;
        }
        offset += 1;
    }

    pattern[len] = 0;

    // Return length only if we found at least one #
    var has_hash = false;
    for (pattern[0..len]) |ch| {
        if (ch == '#') {
            has_hash = true;
            break;
        }
    }
    // Also check for @ in original (though @ is handled separately)
    if (has_hash) return offset;

    return 0;
}

// =========================================================================
// Exported function
// =========================================================================

/// PRINT USING implementation with full numeric formatting support
export fn basic_print_using(format: ?*StringDescriptor, count: i64, args: ?[*]?*StringDescriptor) callconv(.c) void {
    const fmt_desc = format orelse return;

    // Extract format string UTF-8
    const fmt = string_to_utf8(fmt_desc);
    const fmt_copy = strdup(fmt) orelse {
        basic_error_msg("Out of memory in basic_print_using");
        return;
    };
    defer c.free(fmt_copy);

    // Collect argument UTF-8 strings
    const arg_count: usize = if (count > 0) @intCast(count) else 0;
    var arg_strings_buf: [64]?[*:0]u8 = .{null} ** 64;
    const effective_count = @min(arg_count, arg_strings_buf.len);

    if (effective_count > 0) {
        if (args) |arg_ptrs| {
            for (0..effective_count) |i| {
                if (arg_ptrs[i]) |arg| {
                    const s = string_to_utf8(arg);
                    arg_strings_buf[i] = strdup(s);
                }
            }
        }
    }
    defer {
        for (0..effective_count) |i| {
            if (arg_strings_buf[i]) |s| c.free(s);
        }
    }

    // Process the format string with collected arguments
    var argIndex: usize = 0;
    var p: [*:0]const u8 = fmt_copy;

    while (p[0] != 0) {
        if (p[0] == '@') {
            // String substitution
            if (argIndex < effective_count) {
                if (arg_strings_buf[argIndex]) |s| {
                    _ = printf("%s", s);
                }
            }
            argIndex += 1;
            p += 1;
        } else if (p[0] == '#' or p[0] == '+' or
            (p[0] == '$' and p[1] == '$') or
            (p[0] == '*' and p[1] == '*'))
        {
            var pattern: [128]u8 = undefined;
            const pattern_len = extractPattern(p, &pattern, pattern.len);

            if (pattern_len > 0) {
                if (argIndex < effective_count) {
                    if (arg_strings_buf[argIndex]) |arg_str| {
                        var formatted: [256]u8 = undefined;
                        formatNumeric(&formatted, formatted.len, @ptrCast(&pattern), arg_str);
                        _ = printf("%s", &formatted);
                    }
                }
                argIndex += 1;
                p += pattern_len;
            } else {
                _ = putchar(@intCast(p[0]));
                p += 1;
            }
        } else {
            _ = putchar(@intCast(p[0]));
            p += 1;
        }
    }

    flushIfNeeded();
}
