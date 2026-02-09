//
// string_utf32.zig
// FasterBASIC Runtime — UTF-32 String Implementation (Zig port)
//
// Zig port of string_utf32.c.  Provides O(1) character access via
// dual-encoding (ASCII 1-byte or UTF-32 4-byte per codepoint) with
// lazy UTF-8 cache for C interop.
//
// All exported functions use callconv(.c) for ABI compatibility with
// the rest of the runtime (QBE-emitted code calls these via C ABI).
//

const std = @import("std");
const c = std.c;

// =========================================================================
// StringDescriptor layout  (must match string_descriptor.h — 40 bytes)
// =========================================================================
pub const STRING_ENCODING_ASCII: u8 = 0;
pub const STRING_ENCODING_UTF32: u8 = 1;

pub const StringDescriptor = extern struct {
    data: ?*anyopaque, // Pointer to data buffer (uint8_t* or uint32_t*)
    length: i64,
    capacity: i64,
    refcount: i32,
    encoding: u8,
    dirty: u8,
    _padding: [2]u8,
    utf8_cache: ?[*]u8, // Cached UTF-8 representation
};

// =========================================================================
// ArrayDescriptor layout  (must match array_descriptor.h — 64 bytes)
// =========================================================================
pub const ArrayDescriptor = extern struct {
    data: ?*anyopaque,
    lowerBound1: i64,
    upperBound1: i64,
    lowerBound2: i64,
    upperBound2: i64,
    elementSize: i64,
    dimensions: i32,
    base: i32,
    typeSuffix: u8,
    _padding: [7]u8,
};

// =========================================================================
// Extern declarations — functions provided by other runtime modules
// =========================================================================
extern fn samm_alloc_string() ?*anyopaque;
extern fn samm_untrack(ptr: ?*anyopaque) void;
extern fn samm_record_bytes_freed(bytes: u64) void;
extern fn samm_slab_pool_alloc(pool: ?*anyopaque) ?*anyopaque;
extern fn samm_slab_pool_free(pool: ?*anyopaque, ptr: ?*anyopaque) void;
extern var g_string_desc_pool: ?*anyopaque;
// array_descriptor_init — reimplemented in Zig (originally static inline in C header)
fn arrayDescriptorInit(
    desc: *ArrayDescriptor,
    lower: i64,
    upper: i64,
    elem_size: i64,
    base_val: i32,
    type_suffix: u8,
) c_int {
    if (upper < lower or elem_size <= 0) return -1;

    const count: usize = @intCast(upper - lower + 1);
    const total_size: usize = count * @as(usize, @intCast(elem_size));

    const raw = c.malloc(total_size) orelse return -1;
    const ptr: [*]u8 = @ptrCast(raw);
    @memset(ptr[0..total_size], 0);

    desc.data = raw;
    desc.lowerBound1 = lower;
    desc.upperBound1 = upper;
    desc.lowerBound2 = 0;
    desc.upperBound2 = 0;
    desc.elementSize = elem_size;
    desc.dimensions = 1;
    desc.base = base_val;
    desc.typeSuffix = type_suffix;
    desc._padding = .{ 0, 0, 0, 0, 0, 0, 0 };

    return 0;
}

// C standard library functions not exposed by std.c
extern fn strtoll(str: [*:0]const u8, endptr: ?*?[*]u8, base: c_int) c_longlong;
extern fn strtod(str: [*:0]const u8, endptr: ?*?[*]u8) f64;
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
extern fn strlen(str: [*:0]const u8) usize;
extern var __stdoutp: *anyopaque;

// =========================================================================
// Inline helpers — encoding-aware character access
// =========================================================================

inline fn strChar(str: *const StringDescriptor, i: i64) u32 {
    if (str.encoding == STRING_ENCODING_ASCII) {
        const data: [*]const u8 = @ptrCast(@alignCast(str.data orelse return 0));
        return data[@intCast(i)];
    } else {
        const data: [*]const u32 = @ptrCast(@alignCast(str.data orelse return 0));
        return data[@intCast(i)];
    }
}

inline fn strSetChar(str: *StringDescriptor, i: i64, ch: u32) void {
    if (str.encoding == STRING_ENCODING_ASCII) {
        const data: [*]u8 = @ptrCast(@alignCast(str.data orelse return));
        data[@intCast(i)] = @truncate(ch);
    } else {
        const data: [*]u32 = @ptrCast(@alignCast(str.data orelse return));
        data[@intCast(i)] = ch;
    }
}

inline fn charIsWhitespace(ch: u32) bool {
    return ch == ' ' or ch == '\t' or ch == '\n' or ch == '\r' or ch == 0x0B or ch == 0x0C;
}

inline fn charToUpper(ch: u32) u32 {
    if (ch >= 'a' and ch <= 'z') return ch - 32;
    return ch;
}

inline fn charToLower(ch: u32) u32 {
    if (ch >= 'A' and ch <= 'Z') return ch + 32;
    return ch;
}

// =========================================================================
// Pool-based descriptor allocation helpers (inlined from string_pool.h)
// =========================================================================

fn stringDescAlloc() ?*StringDescriptor {
    const raw = samm_slab_pool_alloc(g_string_desc_pool) orelse return null;
    const desc: *StringDescriptor = @ptrCast(@alignCast(raw));
    desc.refcount = 1;
    desc.encoding = STRING_ENCODING_ASCII;
    desc.dirty = 1;
    return desc;
}

fn stringDescFreeData(desc: *StringDescriptor) void {
    if (desc.data) |d| {
        c.free(d);
        desc.data = null;
    }
    if (desc.utf8_cache) |cache| {
        c.free(cache);
        desc.utf8_cache = null;
    }
    desc.length = 0;
    desc.capacity = 0;
    desc.dirty = 1;
}

fn stringDescFree(desc: *StringDescriptor) void {
    if (desc.data) |d| {
        c.free(d);
        desc.data = null;
    }
    if (desc.utf8_cache) |cache| {
        c.free(cache);
        desc.utf8_cache = null;
    }
    samm_slab_pool_free(g_string_desc_pool, @ptrCast(desc));
}

// =========================================================================
// Centralised descriptor allocation via SAMM
// =========================================================================

fn allocDescriptor() ?*StringDescriptor {
    const raw = samm_alloc_string() orelse return null;
    return @ptrCast(@alignCast(raw));
}

// =========================================================================
// UTF-8 ↔ UTF-32 Conversion
// =========================================================================

/// Get length of UTF-8 string in code points
export fn utf8_length_in_codepoints(utf8_str: ?[*:0]const u8) callconv(.c) i64 {
    const p_init = utf8_str orelse return 0;
    var p = p_init;
    var count: i64 = 0;

    while (p[0] != 0) {
        const b = p[0];
        if (b & 0x80 == 0) {
            p += 1;
        } else if (b & 0xE0 == 0xC0) {
            p += 2;
        } else if (b & 0xF0 == 0xE0) {
            p += 3;
        } else if (b & 0xF8 == 0xF0) {
            p += 4;
        } else {
            p += 1;
            continue;
        }
        count += 1;
    }
    return count;
}

/// Convert UTF-8 to UTF-32
export fn utf8_to_utf32(utf8_str: ?[*:0]const u8, out_utf32: ?[*]u32, out_capacity: i64) callconv(.c) i64 {
    const p_init = utf8_str orelse return -1;
    const out = out_utf32 orelse return -1;
    var p = p_init;
    var count: i64 = 0;

    while (p[0] != 0 and count < out_capacity) {
        var codepoint: u32 = undefined;
        const b = p[0];

        if (b & 0x80 == 0) {
            codepoint = b;
            p += 1;
        } else if (b & 0xE0 == 0xC0) {
            codepoint = (@as(u32, b & 0x1F) << 6) | @as(u32, p[1] & 0x3F);
            p += 2;
        } else if (b & 0xF0 == 0xE0) {
            codepoint = (@as(u32, b & 0x0F) << 12) | (@as(u32, p[1] & 0x3F) << 6) | @as(u32, p[2] & 0x3F);
            p += 3;
        } else if (b & 0xF8 == 0xF0) {
            codepoint = (@as(u32, b & 0x07) << 18) | (@as(u32, p[1] & 0x3F) << 12) |
                (@as(u32, p[2] & 0x3F) << 6) | @as(u32, p[3] & 0x3F);
            p += 4;
        } else {
            p += 1;
            continue;
        }

        out[@intCast(count)] = codepoint;
        count += 1;
    }
    return count;
}

/// Get required buffer size for UTF-32 → UTF-8 conversion
export fn utf32_to_utf8_size(utf32_data: ?[*]const u32, length: i64) callconv(.c) i64 {
    const data = utf32_data orelse return 1;
    if (length <= 0) return 1;

    var size: i64 = 0;
    var i: i64 = 0;
    while (i < length) : (i += 1) {
        const cp = data[@intCast(i)];
        if (cp < 0x80) {
            size += 1;
        } else if (cp < 0x800) {
            size += 2;
        } else if (cp < 0x10000) {
            size += 3;
        } else if (cp < 0x110000) {
            size += 4;
        }
    }
    return size + 1; // Include null terminator
}

/// Convert UTF-32 to UTF-8
export fn utf32_to_utf8(utf32_data: ?[*]const u32, length: i64, out_utf8: ?[*]u8, out_capacity: i64) callconv(.c) i64 {
    const data = utf32_data orelse return -1;
    const out = out_utf8 orelse return -1;
    if (out_capacity == 0) return -1;

    var written: i64 = 0;
    var i: i64 = 0;
    while (i < length) : (i += 1) {
        const cp = data[@intCast(i)];
        if (cp < 0x80) {
            if (written + 1 >= out_capacity) break;
            out[@intCast(written)] = @truncate(cp);
            written += 1;
        } else if (cp < 0x800) {
            if (written + 2 >= out_capacity) break;
            out[@intCast(written)] = @truncate(0xC0 | (cp >> 6));
            out[@intCast(written + 1)] = @truncate(0x80 | (cp & 0x3F));
            written += 2;
        } else if (cp < 0x10000) {
            if (written + 3 >= out_capacity) break;
            out[@intCast(written)] = @truncate(0xE0 | (cp >> 12));
            out[@intCast(written + 1)] = @truncate(0x80 | ((cp >> 6) & 0x3F));
            out[@intCast(written + 2)] = @truncate(0x80 | (cp & 0x3F));
            written += 3;
        } else if (cp < 0x110000) {
            if (written + 4 >= out_capacity) break;
            out[@intCast(written)] = @truncate(0xF0 | (cp >> 18));
            out[@intCast(written + 1)] = @truncate(0x80 | ((cp >> 12) & 0x3F));
            out[@intCast(written + 2)] = @truncate(0x80 | ((cp >> 6) & 0x3F));
            out[@intCast(written + 3)] = @truncate(0x80 | (cp & 0x3F));
            written += 4;
        }
    }
    out[@intCast(written)] = 0;
    return written + 1; // Include null terminator
}

// =========================================================================
// String Creation and Management
// =========================================================================

/// Create new ASCII string from 7-bit ASCII C string
export fn string_new_ascii(ascii_str: ?[*:0]const u8) callconv(.c) ?*StringDescriptor {
    const str = ascii_str orelse {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_ASCII;
        return desc;
    };
    if (str[0] == 0) {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_ASCII;
        return desc;
    }

    var len: usize = 0;
    while (str[len] != 0) len += 1;

    const desc = allocDescriptor() orelse return null;
    const buf: ?*anyopaque = c.malloc(len);
    if (buf == null) {
        string_release(desc);
        return null;
    }
    desc.data = buf;

    const dst: [*]u8 = @ptrCast(@alignCast(buf.?));
    const src: [*]const u8 = str;
    @memcpy(dst[0..len], src[0..len]);

    desc.length = @intCast(len);
    desc.capacity = @intCast(len);
    desc.encoding = STRING_ENCODING_ASCII;
    return desc;
}

/// Create new ASCII string from buffer and length
export fn string_new_ascii_len(data: ?*const anyopaque, length: i64) callconv(.c) ?*StringDescriptor {
    if (data == null or length <= 0) {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_ASCII;
        return desc;
    }

    const desc = allocDescriptor() orelse return null;
    const byte_len: usize = @intCast(length);
    const buf = c.malloc(byte_len);
    if (buf == null) {
        string_release(desc);
        return null;
    }
    desc.data = buf;

    const dst: [*]u8 = @ptrCast(@alignCast(buf.?));
    const src: [*]const u8 = @ptrCast(@alignCast(data.?));
    @memcpy(dst[0..byte_len], src[0..byte_len]);

    desc.length = length;
    desc.capacity = length;
    desc.encoding = STRING_ENCODING_ASCII;
    return desc;
}

/// Create new string from UTF-8 C string (auto-detects ASCII vs UTF-32)
export fn string_new_utf8(utf8_str: ?[*:0]const u8) callconv(.c) ?*StringDescriptor {
    const str = utf8_str orelse {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_UTF32;
        return desc;
    };
    if (str[0] == 0) {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_UTF32;
        return desc;
    }

    // Check if pure ASCII and measure length
    var is_ascii = true;
    var len: usize = 0;
    {
        var p = str;
        while (p[0] != 0) {
            if (p[0] >= 128) is_ascii = false;
            p += 1;
            len += 1;
        }
    }

    if (is_ascii) {
        return string_new_ascii(utf8_str);
    }

    // Non-ASCII: convert to UTF-32
    const cp_len = utf8_length_in_codepoints(utf8_str);
    if (cp_len == 0) {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_UTF32;
        return desc;
    }

    const desc = allocDescriptor() orelse return null;
    const ucp_len: usize = @intCast(cp_len);
    const buf = c.malloc(ucp_len * @sizeOf(u32));
    if (buf == null) {
        string_release(desc);
        return null;
    }
    desc.data = buf;

    const out_ptr: [*]u32 = @ptrCast(@alignCast(buf.?));
    const converted = utf8_to_utf32(utf8_str, out_ptr, cp_len);
    desc.length = converted;
    desc.capacity = cp_len;
    desc.encoding = STRING_ENCODING_UTF32;
    return desc;
}

/// Create new string from UTF-32 data
export fn string_new_utf32(data: ?*const anyopaque, length: i64) callconv(.c) ?*StringDescriptor {
    if (data == null or length <= 0) {
        const desc = allocDescriptor() orelse return null;
        desc.encoding = STRING_ENCODING_UTF32;
        return desc;
    }

    const desc = allocDescriptor() orelse return null;
    const ulen: usize = @intCast(length);
    const buf = c.malloc(ulen * @sizeOf(u32));
    if (buf == null) {
        string_release(desc);
        return null;
    }
    desc.data = buf;

    const dst: [*]u8 = @ptrCast(buf.?);
    const src: [*]const u8 = @ptrCast(@alignCast(data.?));
    @memcpy(dst[0 .. ulen * @sizeOf(u32)], src[0 .. ulen * @sizeOf(u32)]);

    desc.length = length;
    desc.capacity = length;
    desc.encoding = STRING_ENCODING_UTF32;
    return desc;
}

/// Create empty string with reserved capacity (UTF-32)
export fn string_new_capacity(capacity: i64) callconv(.c) ?*StringDescriptor {
    const desc = allocDescriptor() orelse return null;

    if (capacity > 0) {
        const ucap: usize = @intCast(capacity);
        const buf = c.malloc(ucap * @sizeOf(u32));
        if (buf == null) {
            string_release(desc);
            return null;
        }
        desc.data = buf;
        desc.capacity = capacity;
    }
    desc.encoding = STRING_ENCODING_UTF32;
    return desc;
}

/// Create empty ASCII string with reserved capacity
export fn string_new_ascii_capacity(capacity: i64) callconv(.c) ?*StringDescriptor {
    const desc = allocDescriptor() orelse return null;

    if (capacity > 0) {
        const ucap: usize = @intCast(capacity);
        const buf = c.malloc(ucap);
        if (buf == null) {
            string_release(desc);
            return null;
        }
        desc.data = buf;
        desc.capacity = capacity;
    }
    desc.encoding = STRING_ENCODING_ASCII;
    return desc;
}

/// Create string by repeating a codepoint
export fn string_new_repeat(codepoint: u32, count: i64) callconv(.c) ?*StringDescriptor {
    if (count <= 0) return string_new_capacity(0);

    const desc = string_new_capacity(count) orelse return null;

    if (codepoint < 128) {
        // ASCII — reallocate to 1 byte per char
        desc.encoding = STRING_ENCODING_ASCII;
        const ucount: usize = @intCast(count);
        const ascii_buf = c.realloc(desc.data, ucount);
        if (ascii_buf != null) {
            desc.data = ascii_buf;
            desc.capacity = count;
            const dst: [*]u8 = @ptrCast(@alignCast(ascii_buf.?));
            var i: usize = 0;
            while (i < ucount) : (i += 1) {
                dst[i] = @truncate(codepoint);
            }
        }
    } else {
        desc.encoding = STRING_ENCODING_UTF32;
        const ucount: usize = @intCast(count);
        const dst: [*]u32 = @ptrCast(@alignCast(desc.data orelse return null));
        var i: usize = 0;
        while (i < ucount) : (i += 1) {
            dst[i] = codepoint;
        }
    }
    desc.length = count;
    return desc;
}

/// Promote ASCII string to UTF-32 in-place
export fn string_promote_to_utf32(str: ?*StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return null;
    if (s.encoding == STRING_ENCODING_UTF32) return s;

    const len = s.length;
    if (len == 0) {
        s.encoding = STRING_ENCODING_UTF32;
        return s;
    }

    const ulen: usize = @intCast(len);
    const utf32_buf = c.malloc(ulen * @sizeOf(u32));
    if (utf32_buf == null) return s;

    const ascii_data: [*]const u8 = @ptrCast(@alignCast(s.data orelse return s));
    const utf32_data: [*]u32 = @ptrCast(@alignCast(utf32_buf.?));

    var i: usize = 0;
    while (i < ulen) : (i += 1) {
        utf32_data[i] = @as(u32, ascii_data[i]);
    }

    c.free(s.data);
    s.data = utf32_buf;
    s.capacity = len;
    s.encoding = STRING_ENCODING_UTF32;
    s.dirty = 1;
    return s;
}

// =========================================================================
// Clone / Retain / Release
// =========================================================================

/// Deep copy a string
export fn string_clone(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len(s.data, s.length);
    } else {
        return string_new_utf32(s.data, s.length);
    }
}

/// Increment refcount
export fn string_retain(str: ?*StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return null;
    s.refcount += 1;
    return s;
}

/// Decrement refcount, free if 0
export fn string_release(str: ?*StringDescriptor) callconv(.c) void {
    const s = str orelse return;
    s.refcount -= 1;
    if (s.refcount <= 0) {
        samm_untrack(@ptrCast(s));
        stringDescFreeData(s);
        stringDescFree(s);
        samm_record_bytes_freed(@sizeOf(StringDescriptor));
    }
}

// =========================================================================
// UTF-8 Conversion (cached)
// =========================================================================

/// Get UTF-8 representation (cached).  Returns pointer to internal cache.
export fn string_to_utf8(str: ?*StringDescriptor) callconv(.c) [*:0]const u8 {
    const s = str orelse return "";
    if (s.length == 0) return "";

    // Cache valid?
    if (s.dirty == 0) {
        if (s.utf8_cache) |cache| {
            return @ptrCast(cache);
        }
    }

    // Free old cache
    if (s.utf8_cache) |cache| {
        c.free(cache);
        s.utf8_cache = null;
    }

    if (s.encoding == STRING_ENCODING_ASCII) {
        const ulen: usize = @intCast(s.length);
        const buf = c.malloc(ulen + 1) orelse return "";
        const dst: [*]u8 = @ptrCast(buf);
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return ""));
        @memcpy(dst[0..ulen], src[0..ulen]);
        dst[ulen] = 0;
        s.utf8_cache = dst;
        s.dirty = 0;
        return @ptrCast(dst);
    }

    // UTF-32 → UTF-8
    const utf32_data: [*]const u32 = @ptrCast(@alignCast(s.data orelse return ""));
    const utf8_size = utf32_to_utf8_size(utf32_data, s.length);
    const buf = c.malloc(@intCast(utf8_size)) orelse return "";
    const dst: [*]u8 = @ptrCast(buf);
    _ = utf32_to_utf8(utf32_data, s.length, dst, utf8_size);
    s.utf8_cache = dst;
    s.dirty = 0;
    return @ptrCast(dst);
}

// =========================================================================
// String Manipulation Operations
// =========================================================================

/// Concatenate two strings
export fn string_concat(a: ?*const StringDescriptor, b: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const sa = a orelse return string_new_capacity(0);
    const sb = b orelse return string_new_capacity(0);

    const total_len = sa.length + sb.length;
    if (total_len == 0) return string_new_capacity(0);

    const result_ascii = (sa.encoding == STRING_ENCODING_ASCII and sb.encoding == STRING_ENCODING_ASCII);

    if (result_ascii) {
        const result = string_new_ascii_capacity(total_len) orelse return null;
        const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse return null));
        if (sa.length > 0) {
            const src_a: [*]const u8 = @ptrCast(@alignCast(sa.data orelse unreachable));
            const alen: usize = @intCast(sa.length);
            @memcpy(dst[0..alen], src_a[0..alen]);
        }
        if (sb.length > 0) {
            const src_b: [*]const u8 = @ptrCast(@alignCast(sb.data orelse unreachable));
            const blen: usize = @intCast(sb.length);
            const offset: usize = @intCast(sa.length);
            @memcpy(dst[offset .. offset + blen], src_b[0..blen]);
        }
        result.length = total_len;
        return result;
    }

    // Mixed encodings → UTF-32
    const result = string_new_capacity(total_len) orelse return null;
    const dst: [*]u32 = @ptrCast(@alignCast(result.data orelse return null));
    var pos: usize = 0;

    if (sa.length > 0) {
        if (sa.encoding == STRING_ENCODING_ASCII) {
            const src: [*]const u8 = @ptrCast(@alignCast(sa.data orelse unreachable));
            const alen: usize = @intCast(sa.length);
            var i: usize = 0;
            while (i < alen) : (i += 1) {
                dst[pos + i] = @as(u32, src[i]);
            }
        } else {
            const src: [*]const u32 = @ptrCast(@alignCast(sa.data orelse unreachable));
            const alen: usize = @intCast(sa.length);
            @memcpy(dst[pos .. pos + alen], src[0..alen]);
        }
        pos += @intCast(sa.length);
    }

    if (sb.length > 0) {
        if (sb.encoding == STRING_ENCODING_ASCII) {
            const src: [*]const u8 = @ptrCast(@alignCast(sb.data orelse unreachable));
            const blen: usize = @intCast(sb.length);
            var i: usize = 0;
            while (i < blen) : (i += 1) {
                dst[pos + i] = @as(u32, src[i]);
            }
        } else {
            const src: [*]const u32 = @ptrCast(@alignCast(sb.data orelse unreachable));
            const blen: usize = @intCast(sb.length);
            @memcpy(dst[pos .. pos + blen], src[0..blen]);
        }
    }
    result.length = total_len;
    return result;
}

/// Substring (MID$) — 0-based start, length
export fn string_mid(str: ?*const StringDescriptor, start: i64, length: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (start < 0 or start >= s.length or length <= 0) return string_new_capacity(0);

    var len = length;
    if (start + len > s.length) len = s.length - start;

    if (s.encoding == STRING_ENCODING_ASCII) {
        const base: [*]const u8 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(start);
        return string_new_ascii_len(@ptrCast(&base[offset]), len);
    } else {
        const base: [*]const u32 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(start);
        return string_new_utf32(@ptrCast(&base[offset]), len);
    }
}

/// Left substring
export fn string_left(str: ?*const StringDescriptor, count: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (count <= 0) return string_new_capacity(0);
    var cnt = count;
    if (cnt > s.length) cnt = s.length;

    if (s.encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len(s.data, cnt);
    } else {
        return string_new_utf32(s.data, cnt);
    }
}

/// Right substring
export fn string_right(str: ?*const StringDescriptor, count: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (count <= 0) return string_new_capacity(0);
    var cnt = count;
    if (cnt > s.length) cnt = s.length;

    if (s.encoding == STRING_ENCODING_ASCII) {
        const base: [*]const u8 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(s.length - cnt);
        return string_new_ascii_len(@ptrCast(&base[offset]), cnt);
    } else {
        const base: [*]const u32 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(s.length - cnt);
        return string_new_utf32(@ptrCast(&base[offset]), cnt);
    }
}

/// String slicing (1-based start TO end, inclusive; -1 = to end)
export fn string_slice(str: ?*const StringDescriptor, start_arg: i64, end_arg: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (start_arg < 1 or (end_arg != -1 and end_arg < start_arg) or start_arg > s.length) {
        return string_new_capacity(0);
    }

    var end = end_arg;
    if (end == -1) end = s.length;

    // Convert 1-based → 0-based
    const start0 = start_arg - 1;
    var end0 = end - 1;
    if (end0 >= s.length) end0 = s.length - 1;

    const length = end0 - start0 + 1;
    if (length <= 0) return string_new_capacity(0);

    if (s.encoding == STRING_ENCODING_ASCII) {
        const base: [*]const u8 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(start0);
        return string_new_ascii_len(@ptrCast(&base[offset]), length);
    } else {
        const base: [*]const u32 = @ptrCast(@alignCast(s.data orelse return string_new_capacity(0)));
        const offset: usize = @intCast(start0);
        return string_new_utf32(@ptrCast(&base[offset]), length);
    }
}

/// Find substring (0-based, returns 0-based index or -1)
export fn string_instr(haystack: ?*const StringDescriptor, needle: ?*const StringDescriptor, start_pos: i64) callconv(.c) i64 {
    const h = haystack orelse return -1;
    const n = needle orelse return -1;
    if (n.length == 0) return -1;
    var sp = start_pos;
    if (sp < 0) sp = 0;
    if (sp >= h.length) return -1;
    if (n.length > h.length - sp) return -1;

    const max_pos = h.length - n.length;
    var pos = sp;
    while (pos <= max_pos) : (pos += 1) {
        var match = true;
        var i: i64 = 0;
        while (i < n.length) : (i += 1) {
            if (strChar(h, pos + i) != strChar(n, i)) {
                match = false;
                break;
            }
        }
        if (match) return pos;
    }
    return -1;
}

/// String comparison (-1, 0, 1)
export fn string_compare(a: ?*const StringDescriptor, b: ?*const StringDescriptor) callconv(.c) c_int {
    const sa = a orelse return 0;
    const sb = b orelse return 0;

    const min_len = if (sa.length < sb.length) sa.length else sb.length;
    var i: i64 = 0;
    while (i < min_len) : (i += 1) {
        const ac = strChar(sa, i);
        const bc = strChar(sb, i);
        if (ac < bc) return -1;
        if (ac > bc) return 1;
    }
    if (sa.length < sb.length) return -1;
    if (sa.length > sb.length) return 1;
    return 0;
}

/// Case-insensitive string comparison
export fn string_compare_nocase(a: ?*const StringDescriptor, b: ?*const StringDescriptor) callconv(.c) c_int {
    const sa = a orelse return 0;
    const sb = b orelse return 0;

    const min_len = if (sa.length < sb.length) sa.length else sb.length;
    var i: i64 = 0;
    while (i < min_len) : (i += 1) {
        const ca = charToLower(strChar(sa, i));
        const cb = charToLower(strChar(sb, i));
        if (ca < cb) return -1;
        if (ca > cb) return 1;
    }
    if (sa.length < sb.length) return -1;
    if (sa.length > sb.length) return 1;
    return 0;
}

/// Convert to uppercase
export fn string_upper(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    const result = string_clone(s) orelse return null;
    var i: i64 = 0;
    while (i < result.length) : (i += 1) {
        strSetChar(result, i, charToUpper(strChar(result, i)));
    }
    return result;
}

/// Convert to lowercase
export fn string_lower(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    const result = string_clone(s) orelse return null;
    var i: i64 = 0;
    while (i < result.length) : (i += 1) {
        strSetChar(result, i, charToLower(strChar(result, i)));
    }
    return result;
}

/// Trim whitespace (both sides)
export fn string_trim(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.length == 0) return string_new_capacity(0);

    var start: i64 = 0;
    while (start < s.length and charIsWhitespace(strChar(s, start))) start += 1;
    if (start >= s.length) return string_new_capacity(0);

    var end: i64 = s.length;
    while (end > start and charIsWhitespace(strChar(s, end - 1))) end -= 1;

    const new_len = end - start;
    const result = string_new_capacity(new_len) orelse return null;
    result.encoding = s.encoding;
    result.length = new_len;

    if (s.encoding == STRING_ENCODING_ASCII) {
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
        const offset: usize = @intCast(start);
        const ulen: usize = @intCast(new_len);
        const dst_buf = c.realloc(result.data, ulen);
        if (dst_buf != null) {
            result.data = dst_buf;
            const dst: [*]u8 = @ptrCast(@alignCast(dst_buf.?));
            @memcpy(dst[0..ulen], src[offset .. offset + ulen]);
        }
    } else {
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
        const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse return result));
        const offset: usize = @intCast(start);
        const ulen: usize = @intCast(new_len);
        @memcpy(dst[0 .. ulen * 4], src[offset * 4 .. (offset + ulen) * 4]);
    }
    return result;
}

/// Trim left whitespace
export fn string_ltrim(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.length == 0) return string_new_capacity(0);

    var start: i64 = 0;
    while (start < s.length and charIsWhitespace(strChar(s, start))) start += 1;
    if (start >= s.length) return string_new_capacity(0);

    const new_len = s.length - start;
    const result = string_new_capacity(new_len) orelse return null;
    result.encoding = s.encoding;
    result.length = new_len;

    if (s.encoding == STRING_ENCODING_ASCII) {
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
        const offset: usize = @intCast(start);
        const ulen: usize = @intCast(new_len);
        const dst_buf = c.realloc(result.data, ulen);
        if (dst_buf != null) {
            result.data = dst_buf;
            const dst: [*]u8 = @ptrCast(@alignCast(dst_buf.?));
            @memcpy(dst[0..ulen], src[offset .. offset + ulen]);
        }
    } else {
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
        const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse return result));
        const offset: usize = @intCast(start);
        const ulen: usize = @intCast(new_len);
        @memcpy(dst[0 .. ulen * 4], src[offset * 4 .. (offset + ulen) * 4]);
    }
    return result;
}

/// Trim right whitespace
export fn string_rtrim(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.length == 0) return string_new_capacity(0);

    var end_idx = s.length;
    while (end_idx >= 1 and charIsWhitespace(strChar(s, end_idx - 1))) end_idx -= 1;
    if (end_idx <= 0) return string_new_capacity(0);

    const new_len = end_idx;
    const result = string_new_capacity(new_len) orelse return null;
    result.encoding = s.encoding;
    result.length = new_len;

    if (s.encoding == STRING_ENCODING_ASCII) {
        const ulen: usize = @intCast(new_len);
        const dst_buf = c.realloc(result.data, ulen);
        if (dst_buf != null) {
            result.data = dst_buf;
            const dst: [*]u8 = @ptrCast(@alignCast(dst_buf.?));
            const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
            @memcpy(dst[0..ulen], src[0..ulen]);
        }
    } else {
        const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse return result));
        const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse return result));
        const ulen: usize = @intCast(new_len);
        @memcpy(dst[0 .. ulen * 4], src[0 .. ulen * 4]);
    }
    return result;
}

/// Reverse string
export fn string_reverse(str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    const result = string_new_capacity(s.length) orelse return null;
    var i: i64 = 0;
    while (i < s.length) : (i += 1) {
        strSetChar(result, i, strChar(s, s.length - 1 - i));
    }
    result.length = s.length;
    return result;
}

/// Count occurrences of pattern (non-overlapping)
export fn string_tally(str: ?*const StringDescriptor, pattern: ?*const StringDescriptor) callconv(.c) i64 {
    const s = str orelse return 0;
    const p = pattern orelse return 0;
    if (p.length == 0 or s.length == 0) return 0;

    var count: i64 = 0;
    var pos: i64 = 0;
    while (pos <= s.length - p.length) {
        const found = string_instr(s, p, pos);
        if (found < 0) break;
        count += 1;
        pos = found + p.length;
    }
    return count;
}

/// Find substring from the right
export fn string_instrrev(haystack: ?*const StringDescriptor, needle: ?*const StringDescriptor, start_pos: i64) callconv(.c) i64 {
    const h = haystack orelse return -1;
    const n = needle orelse return -1;
    if (n.length == 0) return -1;
    if (h.length == 0 or n.length > h.length) return -1;

    var start = start_pos;
    if (start < 0 or start > h.length - n.length) {
        start = h.length - n.length;
    }

    var pos = start;
    while (pos >= 0) : (pos -= 1) {
        var match = true;
        var i: i64 = 0;
        while (i < n.length) : (i += 1) {
            if (strChar(h, pos + i) != strChar(n, i)) {
                match = false;
                break;
            }
        }
        if (match) return pos;
        if (pos == 0) break;
    }
    return -1;
}

/// Insert substring at 1-based position
export fn string_insert(str: ?*const StringDescriptor, pos_arg: i64, insert_str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_clone(insert_str);
    const ins = insert_str orelse return string_clone(s);
    if (ins.length == 0) return string_clone(s);

    var pos = pos_arg;
    if (pos < 1) pos = 1;
    if (pos > s.length + 1) pos = s.length + 1;

    const prefix_len = pos - 1;
    const new_len = s.length + ins.length;
    const result = string_new_capacity(new_len) orelse return null;

    var i: i64 = 0;
    while (i < prefix_len) : (i += 1) strSetChar(result, i, strChar(s, i));
    i = 0;
    while (i < ins.length) : (i += 1) strSetChar(result, prefix_len + i, strChar(ins, i));
    i = prefix_len;
    while (i < s.length) : (i += 1) strSetChar(result, ins.length + i, strChar(s, i));

    result.length = new_len;
    return result;
}

/// Delete substring at 1-based position for given length
export fn string_delete(str: ?*const StringDescriptor, pos_arg: i64, len_arg: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_clone(str);
    if (s.length == 0 or len_arg <= 0) return string_clone(s);
    var pos = pos_arg;
    if (pos < 1) pos = 1;
    const start = pos - 1;
    if (start >= s.length) return string_clone(s);
    var len = len_arg;
    if (start + len > s.length) len = s.length - start;

    const new_len = s.length - len;
    const result = string_new_capacity(new_len) orelse return null;

    var i: i64 = 0;
    while (i < start) : (i += 1) strSetChar(result, i, strChar(s, i));
    i = start + len;
    while (i < s.length) : (i += 1) strSetChar(result, i - len, strChar(s, i));

    result.length = new_len;
    return result;
}

/// Remove all occurrences of pattern
export fn string_remove(str: ?*const StringDescriptor, pattern: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.length == 0) return string_new_capacity(0);
    const p = pattern orelse return string_clone(s);
    if (p.length == 0) return string_clone(s);

    const empty = string_new_capacity(0);
    const replaced = string_replace(s, p, empty);
    string_release(empty);
    return replaced;
}

/// Extract substring by inclusive 1-based start/end
export fn string_extract(str: ?*const StringDescriptor, start_pos: i64, end_pos: i64) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (s.length == 0) return string_new_capacity(0);
    var sp = start_pos;
    if (sp < 1) sp = 1;
    if (end_pos < sp) return string_new_capacity(0);
    var ep = end_pos;
    if (ep > s.length) ep = s.length;
    return string_slice(s, sp, ep);
}

/// Left pad
export fn string_lpad(str: ?*const StringDescriptor, width: i64, pad_str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (width <= s.length) return string_clone(s);

    var pad: u32 = 0x20;
    if (pad_str) |ps| {
        if (ps.length > 0) pad = strChar(ps, 0);
    }

    const pad_len = width - s.length;
    const pad_seg = string_new_repeat(pad, pad_len) orelse return null;
    const result = string_concat(pad_seg, s);
    string_release(pad_seg);
    return result;
}

/// Right pad
export fn string_rpad(str: ?*const StringDescriptor, width: i64, pad_str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (width <= s.length) return string_clone(s);

    var pad: u32 = 0x20;
    if (pad_str) |ps| {
        if (ps.length > 0) pad = strChar(ps, 0);
    }

    const pad_len = width - s.length;
    const pad_seg = string_new_repeat(pad, pad_len) orelse return null;
    const result = string_concat(s, pad_seg);
    string_release(pad_seg);
    return result;
}

/// Center string within width
export fn string_center(str: ?*const StringDescriptor, width: i64, pad_str: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    if (width <= s.length) return string_clone(s);

    var pad: u32 = 0x20;
    if (pad_str) |ps| {
        if (ps.length > 0) pad = strChar(ps, 0);
    }

    const total_pad = width - s.length;
    const left_pad = @divTrunc(total_pad, 2);
    const right_pad = total_pad - left_pad;

    const left = string_new_repeat(pad, left_pad);
    const right = string_new_repeat(pad, right_pad);
    if (left == null or right == null) {
        if (left) |l| string_release(l);
        if (right) |r| string_release(r);
        return null;
    }

    const tmp = string_concat(left, s);
    const result = string_concat(tmp, right);

    string_release(left);
    string_release(right);
    string_release(tmp);
    return result;
}

/// Create string of spaces
export fn string_space(count: i64) callconv(.c) ?*StringDescriptor {
    return string_new_repeat(0x20, count);
}

/// Repeat a whole string pattern count times
export fn string_repeat(pattern: ?*const StringDescriptor, count: i64) callconv(.c) ?*StringDescriptor {
    if (count <= 0) return string_new_capacity(0);
    const p = pattern orelse return string_new_capacity(0);
    if (p.length == 0) return string_new_capacity(0);

    const new_len = p.length * count;
    const result = string_new_capacity(new_len) orelse return null;

    var i: i64 = 0;
    while (i < count) : (i += 1) {
        var j: i64 = 0;
        while (j < p.length) : (j += 1) {
            strSetChar(result, i * p.length + j, strChar(p, j));
        }
    }
    result.length = new_len;
    return result;
}

/// Join array of strings with separator
export fn string_join(array_desc: ?*const ArrayDescriptor, separator: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const ad = array_desc orelse return string_new_capacity(0);

    const sep = separator;
    const sep_len: i64 = if (sep) |s| s.length else 0;

    const count: i64 = if (ad.upperBound1 >= ad.lowerBound1)
        ad.upperBound1 - ad.lowerBound1 + 1
    else
        0;

    if (count <= 0 or ad.data == null) return string_new_capacity(0);

    const data_ptrs: [*]const ?*const StringDescriptor = @ptrCast(@alignCast(ad.data.?));

    // Compute total length
    var total_len: i64 = 0;
    var idx: i64 = 0;
    while (idx < count) : (idx += 1) {
        const uidx: usize = @intCast(idx);
        if (data_ptrs[uidx]) |s| {
            total_len += s.length;
        }
        if (idx + 1 < count) total_len += sep_len;
    }

    const result = string_new_capacity(total_len) orelse return null;
    const result_data: [*]u32 = @ptrCast(@alignCast(result.data orelse return null));

    var pos: usize = 0;
    idx = 0;
    while (idx < count) : (idx += 1) {
        const uidx: usize = @intCast(idx);
        if (data_ptrs[uidx]) |s| {
            if (s.length > 0 and s.data != null) {
                if (s.encoding == STRING_ENCODING_ASCII) {
                    const src: [*]const u8 = @ptrCast(@alignCast(s.data.?));
                    var k: usize = 0;
                    const slen: usize = @intCast(s.length);
                    while (k < slen) : (k += 1) {
                        result_data[pos] = @as(u32, src[k]);
                        pos += 1;
                    }
                } else {
                    const src: [*]const u32 = @ptrCast(@alignCast(s.data.?));
                    const slen: usize = @intCast(s.length);
                    @memcpy(result_data[pos .. pos + slen], src[0..slen]);
                    pos += slen;
                }
            }
        }

        if (idx + 1 < count and sep_len > 0) {
            if (sep) |sv| {
                if (sv.data != null) {
                    if (sv.encoding == STRING_ENCODING_ASCII) {
                        const src: [*]const u8 = @ptrCast(@alignCast(sv.data.?));
                        var k: usize = 0;
                        const usep_len: usize = @intCast(sep_len);
                        while (k < usep_len) : (k += 1) {
                            result_data[pos] = @as(u32, src[k]);
                            pos += 1;
                        }
                    } else {
                        const src: [*]const u32 = @ptrCast(@alignCast(sv.data.?));
                        const usep_len: usize = @intCast(sep_len);
                        @memcpy(result_data[pos .. pos + usep_len], src[0..usep_len]);
                        pos += usep_len;
                    }
                }
            }
        }
    }

    result.length = total_len;
    result.capacity = total_len;
    result.encoding = STRING_ENCODING_UTF32;
    result.dirty = 1;
    return result;
}

/// Helper to allocate array descriptor for split results
fn allocSplitDesc(upper_bound: i64, elem_size: usize) ?*ArrayDescriptor {
    const raw = c.malloc(@sizeOf(ArrayDescriptor)) orelse return null;
    const desc: *ArrayDescriptor = @ptrCast(@alignCast(raw));
    if (arrayDescriptorInit(desc, 0, upper_bound, @intCast(elem_size), 0, '$') != 0) {
        c.free(raw);
        return null;
    }
    return desc;
}

/// Split string into array of StringDescriptor*
export fn string_split(str: ?*const StringDescriptor, delimiter: ?*const StringDescriptor) callconv(.c) ?*ArrayDescriptor {
    const elem_size = @sizeOf(?*StringDescriptor);

    const s = str orelse {
        const desc = allocSplitDesc(0, elem_size) orelse return null;
        const empty = string_new_capacity(0);
        const data_arr: [*]?*StringDescriptor = @ptrCast(@alignCast(desc.data.?));
        data_arr[0] = string_retain(empty);
        string_release(empty);
        return desc;
    };

    const delim = delimiter orelse {
        const desc = allocSplitDesc(0, elem_size) orelse return null;
        const data_arr: [*]?*StringDescriptor = @ptrCast(@alignCast(desc.data.?));
        data_arr[0] = string_retain(@constCast(s));
        return desc;
    };

    if (delim.length == 0) {
        const desc = allocSplitDesc(0, elem_size) orelse return null;
        const data_arr: [*]?*StringDescriptor = @ptrCast(@alignCast(desc.data.?));
        data_arr[0] = string_retain(@constCast(s));
        return desc;
    }

    // First pass: count parts
    var pos: i64 = 0;
    var parts: i64 = 0;
    const hay_len = s.length;
    const delim_len = delim.length;

    while (true) {
        const found = string_instr(s, delim, pos);
        parts += 1;
        if (found < 0) break;
        pos = found + delim_len;
        if (pos > hay_len) break;
    }

    const desc = allocSplitDesc(parts - 1, elem_size) orelse return null;
    const data_arr: [*]?*StringDescriptor = @ptrCast(@alignCast(desc.data.?));

    // Second pass: extract parts
    pos = 0;
    var slot: i64 = 0;
    while (slot < parts) : (slot += 1) {
        const found = string_instr(s, delim, pos);
        var seg_len: i64 = if (found < 0) (hay_len - pos) else (found - pos);
        if (seg_len < 0) seg_len = 0;
        const segment = string_mid(s, pos, seg_len);
        const uslot: usize = @intCast(slot);
        data_arr[uslot] = string_retain(segment);
        string_release(segment);
        if (found < 0) break;
        pos = found + delim_len;
    }
    return desc;
}

/// Replace all occurrences
export fn string_replace(str: ?*const StringDescriptor, old_sub: ?*const StringDescriptor, new_sub: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return string_new_capacity(0);
    const old_s = old_sub orelse return string_clone(s);
    if (old_s.length == 0) return string_clone(s);

    // Use empty string if new_sub is null
    var new_s_owned: ?*StringDescriptor = null;
    const new_s: *const StringDescriptor = if (new_sub) |ns| ns else blk: {
        new_s_owned = string_new_capacity(0);
        break :blk new_s_owned orelse return string_clone(s);
    };
    defer if (new_s_owned) |owned| string_release(owned);

    // Count occurrences
    var occ_count: i64 = 0;
    var pos: i64 = 0;
    while (true) {
        pos = string_instr(s, old_s, pos);
        if (pos < 0) break;
        occ_count += 1;
        pos += old_s.length;
    }
    if (occ_count == 0) return string_clone(s);

    const new_len = s.length + occ_count * (new_s.length - old_s.length);
    const result = string_new_capacity(new_len) orelse return null;

    var src_pos: i64 = 0;
    var dst_pos: i64 = 0;

    while (src_pos < s.length) {
        const match_pos = string_instr(s, old_s, src_pos);
        if (match_pos < 0 or match_pos >= s.length) {
            // Copy remainder
            const remaining = s.length - src_pos;
            if (remaining > 0) {
                const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse break));
                const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse break));
                const urem: usize = @intCast(remaining);
                const usrc: usize = @intCast(src_pos);
                const udst: usize = @intCast(dst_pos);
                @memcpy(dst[udst * 4 .. (udst + urem) * 4], src[usrc * 4 .. (usrc + urem) * 4]);
                dst_pos += remaining;
            }
            break;
        }

        // Copy before match
        if (match_pos > src_pos) {
            const prefix_len = match_pos - src_pos;
            const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse break));
            const src: [*]const u8 = @ptrCast(@alignCast(s.data orelse break));
            const upfx: usize = @intCast(prefix_len);
            const usrc: usize = @intCast(src_pos);
            const udst: usize = @intCast(dst_pos);
            @memcpy(dst[udst * 4 .. (udst + upfx) * 4], src[usrc * 4 .. (usrc + upfx) * 4]);
            dst_pos += prefix_len;
        }

        // Copy replacement
        if (new_s.length > 0) {
            const dst: [*]u8 = @ptrCast(@alignCast(result.data orelse break));
            const src: [*]const u8 = @ptrCast(@alignCast(new_s.data orelse break));
            const unslen: usize = @intCast(new_s.length);
            const udst: usize = @intCast(dst_pos);
            @memcpy(dst[udst * 4 .. (udst + unslen) * 4], src[0 .. unslen * 4]);
            dst_pos += new_s.length;
        }

        src_pos = match_pos + old_s.length;
    }
    result.length = dst_pos;
    return result;
}

// =========================================================================
// Conversion Functions
// =========================================================================

/// Convert string to integer
export fn string_to_int(str: ?*const StringDescriptor) callconv(.c) i64 {
    const s = str orelse return 0;
    if (s.length == 0) return 0;
    const utf8 = string_to_utf8(@constCast(s));
    return @intCast(strtoll(utf8, null, 10));
}

/// Convert string to double
export fn string_to_double(str: ?*const StringDescriptor) callconv(.c) f64 {
    const s = str orelse return 0.0;
    if (s.length == 0) return 0.0;
    const utf8 = string_to_utf8(@constCast(s));
    return strtod(utf8, null);
}

/// Convert integer to string
export fn string_from_int(value: i64) callconv(.c) ?*StringDescriptor {
    var buffer: [32]u8 = undefined;
    const len = snprintf(&buffer, buffer.len, "%lld", value);
    if (len < 0) return string_new_capacity(0);
    buffer[@intCast(len)] = 0;
    return string_new_utf8(@ptrCast(&buffer));
}

/// Convert double to string
export fn string_from_double(value: f64) callconv(.c) ?*StringDescriptor {
    var buffer: [64]u8 = undefined;
    const len = snprintf(&buffer, buffer.len, "%.15g", value);
    if (len < 0) return string_new_capacity(0);
    buffer[@intCast(len)] = 0;
    return string_new_utf8(@ptrCast(&buffer));
}

/// Internal helper: format integer in arbitrary base
fn formatIntBase(value: i64, base: c_int, min_digits: i64, alphabet: [*:0]const u8) ?*StringDescriptor {
    if (base < 2 or base > 36) return string_new_capacity(0);
    const min_dig: i64 = if (min_digits < 0) 0 else min_digits;

    var buffer: [80]u8 = undefined;
    var idx: usize = 0;

    const negative = value < 0;
    var u: u64 = if (negative) @bitCast(-value) else @bitCast(value);

    if (u == 0) {
        buffer[idx] = '0';
        idx += 1;
    }
    const ubase: u64 = @intCast(base);
    while (u > 0 and idx < buffer.len - 1) {
        buffer[idx] = alphabet[@intCast(u % ubase)];
        idx += 1;
        u /= ubase;
    }

    const min_d: usize = @intCast(min_dig);
    while (idx < min_d and idx < buffer.len - 1) {
        buffer[idx] = '0';
        idx += 1;
    }

    if (negative and idx < buffer.len - 1) {
        buffer[idx] = '-';
        idx += 1;
    }

    // Reverse in-place
    {
        var i: usize = 0;
        var j: usize = idx - 1;
        while (i < j) {
            const tmp = buffer[i];
            buffer[i] = buffer[j];
            buffer[j] = tmp;
            i += 1;
            j -= 1;
        }
    }

    buffer[idx] = 0;
    return string_new_utf8(@ptrCast(&buffer));
}

/// HEX$ helper
export fn HEX_STRING(value: i64, digits: i64) callconv(.c) ?*StringDescriptor {
    return formatIntBase(value, 16, digits, "0123456789ABCDEF");
}

/// BIN$ helper
export fn BIN_STRING(value: i64, digits: i64) callconv(.c) ?*StringDescriptor {
    return formatIntBase(value, 2, digits, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ");
}

/// OCT$ helper
export fn OCT_STRING(value: i64, digits: i64) callconv(.c) ?*StringDescriptor {
    return formatIntBase(value, 8, digits, "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ");
}

// =========================================================================
// BASIC-Specific String Functions
// =========================================================================

/// STRING$(n, c)
export fn basic_string_repeat(count: i64, codepoint: u32) callconv(.c) ?*StringDescriptor {
    return string_new_repeat(codepoint, count);
}

/// CHR$(n)
export fn basic_chr(codepoint: u32) callconv(.c) ?*StringDescriptor {
    return string_new_repeat(codepoint, 1);
}

/// ASC(s$)
export fn basic_asc(str: ?*const StringDescriptor) callconv(.c) u32 {
    const s = str orelse return 0;
    if (s.length == 0) return 0;
    if (s.encoding == STRING_ENCODING_ASCII) {
        const data: [*]const u8 = @ptrCast(@alignCast(s.data orelse return 0));
        return data[0];
    } else {
        const data: [*]const u32 = @ptrCast(@alignCast(s.data orelse return 0));
        return data[0];
    }
}

/// VAL(s$)
export fn basic_val(str: ?*const StringDescriptor) callconv(.c) f64 {
    return string_to_double(str);
}

/// STR$(n) — integer
export fn basic_str_int(value: i64) callconv(.c) ?*StringDescriptor {
    return string_from_int(value);
}

/// STR$(n) — double
export fn basic_str_double(value: f64) callconv(.c) ?*StringDescriptor {
    return string_from_double(value);
}

/// SPACE$(n)
export fn basic_space(count: i64) callconv(.c) ?*StringDescriptor {
    return string_new_repeat(0x20, count);
}

// =========================================================================
// Character Access Functions
// =========================================================================

/// Get character at 0-based index
export fn string_get_char_at(str: ?*const StringDescriptor, index: i64) callconv(.c) u32 {
    const s = str orelse return 0;
    if (index < 0 or index >= s.length) return 0;
    return strChar(s, index);
}

/// Set character at 0-based index (with auto-promotion)
export fn string_set_char_at(str: ?*StringDescriptor, index: i64, codepoint: u32) callconv(.c) c_int {
    const s = str orelse return 0;
    if (index < 0 or index >= s.length) return 0;

    if (s.encoding == STRING_ENCODING_ASCII and codepoint >= 128) {
        _ = string_promote_to_utf32(s);
    }

    if (s.encoding == STRING_ENCODING_ASCII) {
        if (codepoint > 127) return 0;
        const data: [*]u8 = @ptrCast(@alignCast(s.data orelse return 0));
        data[@intCast(index)] = @truncate(codepoint);
    } else {
        const data: [*]u32 = @ptrCast(@alignCast(s.data orelse return 0));
        data[@intCast(index)] = codepoint;
    }

    s.dirty = 1;
    return 1;
}

// =========================================================================
// Memory Management Helpers
// =========================================================================

/// Ensure capacity (may reallocate) — UTF-32
export fn string_ensure_capacity(str: ?*StringDescriptor, required_capacity: i64) callconv(.c) bool {
    const s = str orelse return false;
    if (s.capacity >= required_capacity) return true;

    const ucap: usize = @intCast(required_capacity);
    const new_data = c.realloc(s.data, ucap * @sizeOf(u32));
    if (new_data == null) return false;

    s.data = new_data;
    s.capacity = required_capacity;
    return true;
}

/// Shrink capacity to match length
export fn string_shrink_to_fit(str: ?*StringDescriptor) callconv(.c) void {
    const s = str orelse return;
    if (s.capacity == s.length) return;

    if (s.length == 0) {
        if (s.data) |d| c.free(d);
        s.data = null;
        s.capacity = 0;
        return;
    }

    const ulen: usize = @intCast(s.length);
    const new_data = c.realloc(s.data, ulen * @sizeOf(u32));
    if (new_data != null) {
        s.data = new_data;
        s.capacity = s.length;
    }
}

// =========================================================================
// Debug and Statistics
// =========================================================================

/// Print string descriptor info
export fn string_debug_print(str: ?*const StringDescriptor) callconv(.c) void {
    const stdio = &__stdoutp;
    const s = str orelse {
        _ = fprintf(stdio.*, "StringDescriptor: NULL\n");
        return;
    };
    _ = fprintf(stdio.*, "StringDescriptor {\n");
    _ = fprintf(stdio.*, "  length: %lld\n", s.length);
    _ = fprintf(stdio.*, "  capacity: %lld\n", s.capacity);
    _ = fprintf(stdio.*, "  refcount: %d\n", s.refcount);
    _ = fprintf(stdio.*, "  dirty: %d\n", @as(c_int, s.dirty));
    _ = fprintf(stdio.*, "  content: \"%s\"\n", string_to_utf8(@constCast(s)));
    _ = fprintf(stdio.*, "}\n");
}

/// Get memory usage
export fn string_memory_usage(str: ?*const StringDescriptor) callconv(.c) usize {
    const s = str orelse return 0;
    var total: usize = @sizeOf(StringDescriptor);
    total += @as(usize, @intCast(s.capacity)) * @sizeOf(u32);
    if (s.utf8_cache) |cache| {
        total += strlen(@ptrCast(cache)) + 1;
    }
    return total;
}

// =========================================================================
// MID$ Assignment and Slice Assignment
// =========================================================================

/// MID$ assignment: MID$(str, pos, len) = replacement
export fn string_mid_assign(str: ?*StringDescriptor, pos_arg: i64, len_arg: i64, replacement: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    var s = str orelse return str;
    if (pos_arg < 1 or len_arg < 0) return s;

    // Use empty string if replacement is null
    var repl_owned: ?*StringDescriptor = null;
    const repl: *const StringDescriptor = if (replacement) |r| r else blk: {
        repl_owned = string_new_capacity(0);
        break :blk repl_owned orelse return s;
    };
    defer if (repl_owned) |owned| string_release(owned);

    // Copy-on-write
    if (s.refcount > 1) {
        const new_str = string_clone(s) orelse return s;
        s.refcount -= 1;
        s = new_str;
    }

    var pos = pos_arg - 1; // 0-based
    if (pos < 0) pos = 0;
    if (pos >= s.length) return s;
    var len = len_arg;
    if (len > s.length - pos) len = s.length - pos;

    if (len == repl.length) {
        // Same length — in-place replace
        var i: i64 = 0;
        while (i < len) : (i += 1) {
            strSetChar(s, pos + i, strChar(repl, i));
        }
        if (s.utf8_cache) |cache| {
            c.free(cache);
            s.utf8_cache = null;
            s.dirty = 1;
        }
        return s;
    }

    // Need resize
    const new_length = s.length - len + repl.length;
    const new_str = string_new_capacity(new_length) orelse return s;

    // Copy prefix
    {
        var i: i64 = 0;
        while (i < pos) : (i += 1) strSetChar(new_str, i, strChar(s, i));
    }
    // Copy replacement
    {
        var i: i64 = 0;
        while (i < repl.length) : (i += 1) strSetChar(new_str, pos + i, strChar(repl, i));
    }
    // Copy suffix
    {
        var i: i64 = pos + len;
        while (i < s.length) : (i += 1) {
            strSetChar(new_str, pos + repl.length + (i - pos - len), strChar(s, i));
        }
    }
    new_str.length = new_length;

    // Free old string
    samm_untrack(@ptrCast(s));
    if (s.data) |d| c.free(d);
    if (s.utf8_cache) |cache| c.free(cache);
    c.free(@ptrCast(s));

    return new_str;
}

/// String slice assignment
export fn string_slice_assign(str: ?*StringDescriptor, start_arg: i64, end_arg: i64, replacement: ?*const StringDescriptor) callconv(.c) ?*StringDescriptor {
    const s = str orelse return str;
    if (start_arg < 1) return s;

    var end = end_arg;
    if (end == -1) end = s.length;

    // Convert 1-based → 0-based
    const start0 = start_arg - 1;
    var end0 = end - 1;

    if (start0 < 0) return s;
    if (end0 >= s.length) end0 = s.length - 1;
    if (start0 > end0) return s;

    const len = end0 - start0 + 1;
    return string_mid_assign(s, start0 + 1, len, replacement);
}
