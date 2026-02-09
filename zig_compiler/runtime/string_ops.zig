// string_ops.zig
// FasterBASIC Runtime — Legacy String Operations (Zig port)
//
// Implements BasicString management with reference counting.
// BasicString is the legacy byte-oriented string type (UTF-8 data, refcounted).
// The newer StringDescriptor (UTF-32) is in string_utf32.c.
//
// Exported functions:
//   str_new, str_new_length, str_new_capacity
//   str_retain, str_release
//   str_cstr, str_length
//   str_concat, str_substr, str_left, str_right
//   str_compare, str_upper, str_lower, str_trim
//   str_instr, str_replace
//   basic_string_len, basic_string_concat, basic_string_compare
//   basic_mid, basic_left, basic_right
//
// Replaces string_ops.c — all exported symbols maintain C ABI compatibility.

const std = @import("std");

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn malloc(size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
    extern fn strcmp(a: [*:0]const u8, b: [*:0]const u8) c_int;
    extern fn strstr(haystack: [*:0]const u8, needle: [*:0]const u8) ?[*]const u8;
    extern fn strlen(s: [*:0]const u8) usize;
    extern fn strcpy(dest: [*]u8, src: [*:0]const u8) [*]u8;
};

// =========================================================================
// External runtime functions
// =========================================================================
extern fn basic_error_msg(msg: [*:0]const u8) void;

// StringDescriptor is opaque here — used by basic_mid/left/right wrappers
const StringDescriptor = anyopaque;
extern fn string_mid(str: ?*const StringDescriptor, start: i64, length: i64) ?*StringDescriptor;
extern fn string_left(str: ?*const StringDescriptor, count: i64) ?*StringDescriptor;
extern fn string_right(str: ?*const StringDescriptor, count: i64) ?*StringDescriptor;

// =========================================================================
// BasicString struct layout — must match C definition exactly
// =========================================================================
// typedef struct BasicString {
//     char* data;        // offset 0
//     size_t length;     // offset 8
//     size_t capacity;   // offset 16
//     int32_t refcount;  // offset 24
// } BasicString;
const BasicString = extern struct {
    data: ?[*]u8,
    length: usize,
    capacity: usize,
    refcount: i32,
};

// =========================================================================
// Helper: allocate a BasicString struct
// =========================================================================
fn allocBasicString() ?*BasicString {
    const ptr = c.malloc(@sizeOf(BasicString)) orelse {
        basic_error_msg("Out of memory (string allocation)");
        return null;
    };
    return @ptrCast(@alignCast(ptr));
}

fn allocData(size: usize) ?[*]u8 {
    const ptr = c.malloc(size) orelse {
        basic_error_msg("Out of memory (string data)");
        return null;
    };
    return @ptrCast(ptr);
}

// =========================================================================
// String Creation
// =========================================================================

export fn str_new(cstr: ?[*:0]const u8) ?*BasicString {
    const s = cstr orelse "";
    const len = c.strlen(s);

    const str = allocBasicString() orelse return null;
    str.length = len;
    str.capacity = len + 1;
    str.data = allocData(str.capacity) orelse {
        c.free(@ptrCast(str));
        return null;
    };
    _ = c.memcpy(@ptrCast(str.data), @as(?*const anyopaque, @ptrCast(s)), len);
    str.data.?[len] = 0;
    str.refcount = 1;
    return str;
}

export fn str_new_length(data: ?[*]const u8, length: usize) ?*BasicString {
    if (data == null) return str_new("");

    const str = allocBasicString() orelse return null;
    str.length = length;
    str.capacity = length + 1;
    str.data = allocData(str.capacity) orelse {
        c.free(@ptrCast(str));
        return null;
    };
    _ = c.memcpy(@ptrCast(str.data), @as(?*const anyopaque, @ptrCast(data)), length);
    str.data.?[length] = 0;
    str.refcount = 1;
    return str;
}

export fn str_new_capacity(capacity: usize) ?*BasicString {
    const str = allocBasicString() orelse return null;
    str.length = 0;
    str.capacity = capacity + 1;
    str.data = allocData(str.capacity) orelse {
        c.free(@ptrCast(str));
        return null;
    };
    str.data.?[0] = 0;
    str.refcount = 1;
    return str;
}

// =========================================================================
// Reference Counting
// =========================================================================

export fn str_retain(str: ?*BasicString) ?*BasicString {
    const s = str orelse return null;
    s.refcount += 1;
    return s;
}

export fn str_release(str_ptr: ?*BasicString) void {
    const s = str_ptr orelse return;
    s.refcount -= 1;
    if (s.refcount <= 0) {
        if (s.data) |d| {
            c.free(@ptrCast(d));
        }
        c.free(@ptrCast(s));
    }
}

// =========================================================================
// String Access
// =========================================================================

export fn str_cstr(str: ?*const BasicString) [*:0]const u8 {
    const s = str orelse return "";
    if (s.data) |d| {
        return @ptrCast(d);
    }
    return "";
}

export fn str_length(str: ?*const BasicString) i32 {
    const s = str orelse return 0;
    return @intCast(s.length);
}

// =========================================================================
// String Concatenation
// =========================================================================

export fn str_concat(a: ?*BasicString, b: ?*BasicString) ?*BasicString {
    if (a == null and b == null) return str_new("");
    if (a == null) return str_retain(b);
    if (b == null) return str_retain(a);

    const sa = a.?;
    const sb = b.?;
    const new_len = sa.length + sb.length;
    const result = str_new_capacity(new_len) orelse return null;

    const rd = result.data.?;
    _ = c.memcpy(@ptrCast(rd), @as(?*const anyopaque, @ptrCast(sa.data)), sa.length);
    _ = c.memcpy(@ptrCast(rd + sa.length), @as(?*const anyopaque, @ptrCast(sb.data)), sb.length);
    rd[new_len] = 0;
    result.length = new_len;

    return result;
}

// =========================================================================
// Substring Operations
// =========================================================================

export fn str_substr(str: ?*BasicString, start_1based: i32, length: i32) ?*BasicString {
    const s = str orelse return str_new("");

    // Convert to 0-based
    var start: i32 = start_1based - 1;
    if (start < 0) start = 0;
    const slen: i32 = @intCast(s.length);
    if (start >= slen) return str_new("");

    var len = length;
    if (len < 0) len = 0;
    if (start + len > slen) len = slen - start;

    const data = s.data orelse return str_new("");
    return str_new_length(@ptrCast(data + @as(usize, @intCast(start))), @intCast(len));
}

export fn str_left(str: ?*BasicString, n: i32) ?*BasicString {
    const s = str orelse return str_new("");
    if (n <= 0) return str_new("");
    if (n >= @as(i32, @intCast(s.length))) return str_retain(str);

    const data = s.data orelse return str_new("");
    return str_new_length(@ptrCast(data), @intCast(n));
}

export fn str_right(str: ?*BasicString, n: i32) ?*BasicString {
    const s = str orelse return str_new("");
    if (n <= 0) return str_new("");
    if (n >= @as(i32, @intCast(s.length))) return str_retain(str);

    const start = s.length - @as(usize, @intCast(n));
    const data = s.data orelse return str_new("");
    return str_new_length(@ptrCast(data + start), @intCast(n));
}

// =========================================================================
// String Comparison
// =========================================================================

export fn str_compare(a: ?*const BasicString, b: ?*const BasicString) i32 {
    if (a == null and b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;

    const ad: [*:0]const u8 = if (a.?.data) |d| @ptrCast(d) else "";
    const bd: [*:0]const u8 = if (b.?.data) |d| @ptrCast(d) else "";

    const result = c.strcmp(ad, bd);
    if (result < 0) return -1;
    if (result > 0) return 1;
    return 0;
}

// =========================================================================
// Case Conversion
// =========================================================================

fn toUpper(ch: u8) u8 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

fn toLower(ch: u8) u8 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}

export fn str_upper(str: ?*const BasicString) ?*BasicString {
    const s = str orelse return str_new("");
    const result = str_new_capacity(s.length) orelse return null;
    result.length = s.length;

    const src = s.data orelse {
        result.data.?[0] = 0;
        return result;
    };
    const dst = result.data.?;

    for (0..s.length) |i| {
        dst[i] = toUpper(src[i]);
    }
    dst[s.length] = 0;
    return result;
}

export fn str_lower(str: ?*const BasicString) ?*BasicString {
    const s = str orelse return str_new("");
    const result = str_new_capacity(s.length) orelse return null;
    result.length = s.length;

    const src = s.data orelse {
        result.data.?[0] = 0;
        return result;
    };
    const dst = result.data.?;

    for (0..s.length) |i| {
        dst[i] = toLower(src[i]);
    }
    dst[s.length] = 0;
    return result;
}

// =========================================================================
// String Trimming
// =========================================================================

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0b or ch == 0x0c;
}

export fn str_trim(str: ?*const BasicString) ?*BasicString {
    const s = str orelse return str_new("");
    if (s.length == 0) return str_new("");

    const data = s.data orelse return str_new("");

    // Find first non-whitespace
    var start: usize = 0;
    while (start < s.length and isSpace(data[start])) {
        start += 1;
    }

    // All whitespace?
    if (start >= s.length) return str_new("");

    // Find last non-whitespace
    var end: usize = s.length;
    while (end > start and isSpace(data[end - 1])) {
        end -= 1;
    }

    const new_len = end - start;
    return str_new_length(@ptrCast(data + start), new_len);
}

// =========================================================================
// String Search
// =========================================================================

export fn str_instr(haystack: ?*const BasicString, needle: ?*const BasicString) i32 {
    const h = haystack orelse return 0;
    const n = needle orelse return 0;

    if (n.length == 0) return 1; // Empty needle found at position 1
    if (n.length > h.length) return 0;

    const hd: [*:0]const u8 = if (h.data) |d| @ptrCast(d) else return 0;
    const nd: [*:0]const u8 = if (n.data) |d| @ptrCast(d) else return 0;

    const found = c.strstr(hd, nd) orelse return 0;

    // Return 1-based position
    const offset = @intFromPtr(found) - @intFromPtr(hd);
    return @as(i32, @intCast(offset)) + 1;
}

// =========================================================================
// String Replacement
// =========================================================================

export fn str_replace(str: ?*BasicString, find: ?*BasicString, replace_str: ?*BasicString) ?*BasicString {
    const s = str orelse return str_new("");
    const f = find orelse return str_retain(str);
    if (f.length == 0) return str_retain(str);

    // Use empty string if replace is null
    const r_data: [*]const u8 = if (replace_str) |r| (r.data orelse @as([*]const u8, "")) else @as([*]const u8, "");
    const r_len: usize = if (replace_str) |r| r.length else 0;

    const sd: [*:0]const u8 = if (s.data) |d| @ptrCast(d) else return str_retain(str);
    const fd: [*:0]const u8 = if (f.data) |d| @ptrCast(d) else return str_retain(str);

    // Count occurrences
    var count: usize = 0;
    var pos: [*]const u8 = sd;
    while (c.strstr(@ptrCast(pos), fd)) |found| {
        count += 1;
        pos = found + f.length;
    }

    if (count == 0) return str_retain(str);

    // Calculate new length
    const new_len = s.length + count * r_len - count * f.length;
    const result = str_new_capacity(new_len) orelse return null;

    // Build result string
    const dst = result.data.?;
    var src_pos: usize = 0;
    var dst_pos: usize = 0;
    const src_data = s.data.?;

    while (src_pos < s.length) {
        // Check for match at current position
        const remaining: [*:0]const u8 = @ptrCast(src_data + src_pos);
        const match = c.strstr(remaining, fd);

        if (match) |m| {
            if (@intFromPtr(m) == @intFromPtr(remaining)) {
                // Match at current position — copy replacement
                if (r_len > 0) {
                    _ = c.memcpy(@ptrCast(dst + dst_pos), @as(?*const anyopaque, @ptrCast(r_data)), r_len);
                    dst_pos += r_len;
                }
                src_pos += f.length;
                continue;
            }
        }

        // Copy one byte
        dst[dst_pos] = src_data[src_pos];
        dst_pos += 1;
        src_pos += 1;
    }

    dst[dst_pos] = 0;
    result.length = dst_pos;
    return result;
}

// =========================================================================
// BASIC Intrinsic Function Wrappers
// =========================================================================

export fn basic_string_len(str: ?*const BasicString) i32 {
    return str_length(str);
}

export fn basic_string_concat(a: ?*BasicString, b: ?*BasicString) ?*BasicString {
    return str_concat(a, b);
}

export fn basic_string_compare(a: ?*const BasicString, b: ?*const BasicString) i32 {
    return str_compare(a, b);
}

// MID$(string$, start, length) — BASIC 1-based to 0-based conversion
export fn basic_mid(str: ?*const StringDescriptor, start: i32, length: i32) ?*StringDescriptor {
    return string_mid(str, @as(i64, start) - 1, @as(i64, length));
}

// LEFT$(string$, count)
export fn basic_left(str: ?*const StringDescriptor, count: i32) ?*StringDescriptor {
    return string_left(str, @as(i64, count));
}

// RIGHT$(string$, count)
export fn basic_right(str: ?*const StringDescriptor, count: i32) ?*StringDescriptor {
    return string_right(str, @as(i64, count));
}

// =========================================================================
// Unit tests
// =========================================================================

test "toUpper and toLower" {
    try std.testing.expectEqual(@as(u8, 'A'), toUpper('a'));
    try std.testing.expectEqual(@as(u8, 'A'), toUpper('A'));
    try std.testing.expectEqual(@as(u8, 'z'), toLower('Z'));
    try std.testing.expectEqual(@as(u8, '1'), toUpper('1'));
}

test "isSpace" {
    try std.testing.expect(isSpace(' '));
    try std.testing.expect(isSpace('\t'));
    try std.testing.expect(isSpace('\n'));
    try std.testing.expect(!isSpace('a'));
}
