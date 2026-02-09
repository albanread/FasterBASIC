// memory_mgmt.zig
// FasterBASIC Runtime — Memory Management (Zig port)
//
// Provides safe memory allocation wrappers with error checking,
// memory utilities, and optional debug counters.
//
// Replaces memory_mgmt.c — all exported symbols maintain C ABI compatibility.

const std = @import("std");
const builtin = @import("builtin");

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn malloc(size: usize) ?*anyopaque;
    extern fn calloc(count: usize, size: usize) ?*anyopaque;
    extern fn realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque;
    extern fn memset(ptr: ?*anyopaque, value: c_int, n: usize) ?*anyopaque;
    extern fn memcmp(ptr1: ?*const anyopaque, ptr2: ?*const anyopaque, n: usize) c_int;
    extern fn strlen(s: [*:0]const u8) usize;
};

// =========================================================================
// External runtime functions
// =========================================================================
extern fn basic_error_msg(msg: [*:0]const u8) void;

// =========================================================================
// Debug memory tracking (compile-time optional)
// =========================================================================
const DEBUG_MEMORY = false; // Set true for debug builds

var g_allocations: usize = 0;
var g_deallocations: usize = 0;
var g_bytes_allocated: usize = 0;

// =========================================================================
// Exported API — Safe Memory Allocation
// =========================================================================

export fn basic_malloc(size: usize) ?*anyopaque {
    const ptr = c.malloc(size);
    if (ptr == null) {
        basic_error_msg("Out of memory");
        return null;
    }
    if (DEBUG_MEMORY) {
        g_allocations += 1;
        g_bytes_allocated += size;
    }
    return ptr;
}

export fn basic_calloc(count: usize, size: usize) ?*anyopaque {
    const ptr = c.calloc(count, size);
    if (ptr == null) {
        basic_error_msg("Out of memory");
        return null;
    }
    if (DEBUG_MEMORY) {
        g_allocations += 1;
        g_bytes_allocated += count * size;
    }
    return ptr;
}

export fn basic_realloc(ptr: ?*anyopaque, size: usize) ?*anyopaque {
    const new_ptr = c.realloc(ptr, size);
    if (new_ptr == null) {
        basic_error_msg("Out of memory");
        return null;
    }
    return new_ptr;
}

export fn basic_free(ptr: ?*anyopaque) void {
    if (ptr == null) return;
    if (DEBUG_MEMORY) {
        g_deallocations += 1;
    }
    c.free(ptr);
}

// =========================================================================
// Exported API — Memory Utilities
// =========================================================================

export fn basic_memcpy(dest: ?*anyopaque, src: ?*const anyopaque, n: usize) ?*anyopaque {
    return c.memcpy(dest, src, n);
}

export fn basic_memset(ptr: ?*anyopaque, value: c_int, n: usize) ?*anyopaque {
    return c.memset(ptr, value, n);
}

export fn basic_memcmp(ptr1: ?*const anyopaque, ptr2: ?*const anyopaque, n: usize) c_int {
    return c.memcmp(ptr1, ptr2, n);
}

// =========================================================================
// Exported API — String Duplication
// =========================================================================

export fn basic_strdup(str: ?[*:0]const u8) ?[*]u8 {
    const s = str orelse return null;
    const len = c.strlen(s);
    const dup_ptr = basic_malloc(len + 1) orelse return null;
    _ = c.memcpy(dup_ptr, @as(?*const anyopaque, @ptrCast(s)), len + 1);
    return @ptrCast(dup_ptr);
}

// =========================================================================
// Exported API — Debug Stats
// =========================================================================

export fn basic_mem_stats() void {
    if (DEBUG_MEMORY) {
        const stdio = @cImport(@cInclude("stdio.h"));
        _ = stdio.printf("Memory Statistics:\n");
        _ = stdio.printf("  Allocations:   %zu\n", g_allocations);
        _ = stdio.printf("  Deallocations: %zu\n", g_deallocations);
        _ = stdio.printf("  Bytes:         %zu\n", g_bytes_allocated);
        _ = stdio.printf("  Leaked:        %zu\n", g_allocations - g_deallocations);
    }
}

// =========================================================================
// Unit tests
// =========================================================================

test "basic_malloc returns non-null for valid size" {
    const ptr = basic_malloc(64);
    try std.testing.expect(ptr != null);
    basic_free(ptr);
}

test "basic_calloc returns zeroed memory" {
    const ptr = basic_calloc(1, 64) orelse unreachable;
    const bytes: [*]const u8 = @ptrCast(ptr);
    for (0..64) |i| {
        try std.testing.expectEqual(@as(u8, 0), bytes[i]);
    }
    basic_free(ptr);
}

test "basic_free handles null" {
    basic_free(null); // should not crash
}
