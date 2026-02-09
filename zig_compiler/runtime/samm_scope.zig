const std = @import("std");
const c_allocator = std.heap.c_allocator;

// Constants matching C runtime headers
const SAMM_MAX_SCOPE_DEPTH = 256;

const Scope = struct {
    ptrs: std.ArrayListUnmanaged(?*anyopaque) = .{},
    types: std.ArrayListUnmanaged(u8) = .{},
    size_classes: std.ArrayListUnmanaged(u8) = .{},

    fn deinit(self: *Scope) void {
        self.ptrs.deinit(c_allocator);
        self.types.deinit(c_allocator);
        self.size_classes.deinit(c_allocator);
    }

    fn reset(self: *Scope) void {
        // We do NOT deinit here because that frees the memory.
        // reset() is called when entering a new scope.
        // If the arrays were not detached (should not happen if exited correctly),
        // we should clear them.
        self.ptrs.clearRetainingCapacity();
        self.types.clearRetainingCapacity();
        self.size_classes.clearRetainingCapacity();
    }
};

// Global storage for scopes
// Note: We don't use a mutex here because the C caller holds scope_mutex
var scopes: [SAMM_MAX_SCOPE_DEPTH]Scope = undefined;
var initialized = false;

// Ensure initialization (called lazily or explicitly)
export fn samm_scope_ensure_init() callconv(.c) void {
    if (initialized) return;
    for (&scopes) |*s| {
        s.* = .{};
    }
    initialized = true;
}

// Reset a scope for use (called by samm_enter_scope)
export fn samm_scope_reset(depth: c_int) callconv(.c) void {
    if (!initialized) samm_scope_ensure_init();
    if (depth < 0 or depth >= SAMM_MAX_SCOPE_DEPTH) return;

    scopes[@intCast(depth)].reset();
}

// Add an object to the current scope (called by samm_track_object)
export fn samm_scope_add(depth: c_int, ptr: ?*anyopaque, type_id: u8, sc: u8) callconv(.c) void {
    if (!initialized) samm_scope_ensure_init();
    if (depth < 0 or depth >= SAMM_MAX_SCOPE_DEPTH) return;

    var scope = &scopes[@intCast(depth)];

    // Reserve capacity in all three arrays before appending so that if
    // allocation fails we haven't partially inserted into one array.
    // We use c_allocator because C code owns these arrays after detach.
    const new_cap = scope.ptrs.items.len + 1;
    scope.ptrs.ensureTotalCapacity(c_allocator, new_cap) catch {
        std.debug.print("SAMM FATAL: Scope expansion failed (OOM)\n", .{});
        std.process.exit(1);
    };
    scope.types.ensureTotalCapacity(c_allocator, new_cap) catch {
        std.debug.print("SAMM FATAL: Scope expansion failed (OOM)\n", .{});
        std.process.exit(1);
    };
    scope.size_classes.ensureTotalCapacity(c_allocator, new_cap) catch {
        std.debug.print("SAMM FATAL: Scope expansion failed (OOM)\n", .{});
        std.process.exit(1);
    };

    // Capacity is guaranteed — these cannot fail.
    scope.ptrs.appendAssumeCapacity(ptr);
    scope.types.appendAssumeCapacity(type_id);
    scope.size_classes.appendAssumeCapacity(sc);
}

// Remove an object from the scope (tombstone with null).
// Returns true if found and removed, populating out_type and out_sc.
// Called by samm_retain/samm_untrack.
//
// Design: We tombstone (set to null) rather than swap-remove because:
//   1. Swap-remove would break the parallel types/size_classes arrays.
//   2. cleanup_batch already skips null entries (samm_core.c:295).
//   3. Scopes are short-lived, so tombstone accumulation is bounded.
export fn samm_scope_remove(depth: c_int, ptr: ?*anyopaque, out_type: ?*u8, out_sc: ?*u8) callconv(.c) bool {
    if (!initialized) samm_scope_ensure_init();
    if (depth < 0 or depth >= SAMM_MAX_SCOPE_DEPTH) return false;
    if (ptr == null) return false;

    const scope = &scopes[@intCast(depth)];
    const items = scope.ptrs.items;

    // Search backwards (newest first)
    var i: usize = items.len;
    while (i > 0) {
        i -= 1;
        if (items[i] == ptr) {
            // Found it. Tombstone it.
            items[i] = null;
            if (out_type) |t_ptr| t_ptr.* = scope.types.items[i];
            if (out_sc) |sc_ptr| sc_ptr.* = scope.size_classes.items[i];
            return true;
        }
    }
    return false;
}

// Detach arrays from scope and return them to C (called by samm_exit_scope)
// Returns true if arrays were populated and detached, false if empty/invalid.
export fn samm_scope_detach(depth: c_int, out_ptrs: *[*]?*anyopaque, out_types: *[*]u8, out_sc: *[*]u8, out_count: *usize) callconv(.c) bool {
    if (!initialized) samm_scope_ensure_init();
    if (depth < 0 or depth >= SAMM_MAX_SCOPE_DEPTH) return false;

    var scope = &scopes[@intCast(depth)];
    const count = scope.ptrs.items.len;

    if (count == 0) {
        // If empty, just clear and return false, no arrays to hand off
        scope.reset();
        return false;
    }

    // Hand off ownership to C via toOwnedSlice.
    // This shrinks the allocation to exactly `count` elements so the C
    // consumer can safely free() the pointer without worrying about
    // excess capacity from the ArrayList's growth strategy.
    // toOwnedSlice also resets the list to empty, preventing double-free.
    //
    // OOM on shrink (realloc to smaller) is practically impossible with
    // libc, but if it happens we fall back to handing off the raw pointer
    // (C free() handles over-sized allocations correctly).
    const ptrs_slice = scope.ptrs.toOwnedSlice(c_allocator) catch blk: {
        const raw = scope.ptrs.items.ptr;
        scope.ptrs = .{};
        break :blk @as([]?*anyopaque, raw[0..count]);
    };
    const types_slice = scope.types.toOwnedSlice(c_allocator) catch blk: {
        const raw = scope.types.items.ptr;
        scope.types = .{};
        break :blk @as([]u8, raw[0..count]);
    };
    const sc_slice = scope.size_classes.toOwnedSlice(c_allocator) catch blk: {
        const raw = scope.size_classes.items.ptr;
        scope.size_classes = .{};
        break :blk @as([]u8, raw[0..count]);
    };

    out_ptrs.* = ptrs_slice.ptr;
    out_types.* = types_slice.ptr;
    out_sc.* = sc_slice.ptr;
    out_count.* = count;

    return true;
}

// --- Tests ---

test "scope life cycle" {
    samm_scope_ensure_init();
    const depth: c_int = 1;

    samm_scope_reset(depth);

    // Mock data
    const ptr1 = @as(?*anyopaque, @ptrFromInt(0xDEADBEEF));
    const ptr2 = @as(?*anyopaque, @ptrFromInt(0xCAFEBABE));

    samm_scope_add(depth, ptr1, 0, 1);
    samm_scope_add(depth, ptr2, 1, 2);

    // Check internal state
    const scope = &scopes[1];
    try std.testing.expectEqual(@as(usize, 2), scope.ptrs.items.len);
    try std.testing.expectEqual(ptr1, scope.ptrs.items[0]);
    try std.testing.expectEqual(ptr2, scope.ptrs.items[1]);

    // Detach
    var out_ptrs: [*]?*anyopaque = undefined;
    var out_types: [*]u8 = undefined;
    var out_sc: [*]u8 = undefined;
    var out_count: usize = 0;

    const res = samm_scope_detach(depth, &out_ptrs, &out_types, &out_sc, &out_count);

    try std.testing.expect(res);
    try std.testing.expectEqual(@as(usize, 2), out_count);
    try std.testing.expectEqual(ptr1, out_ptrs[0]);

    // Free the memory (simulation of C consumer)
    c_allocator.free(out_ptrs[0..out_count]);
    c_allocator.free(out_types[0..out_count]);
    c_allocator.free(out_sc[0..out_count]);

    // Verify scope is empty
    try std.testing.expectEqual(@as(usize, 0), scope.ptrs.items.len);
}

test "scope remove" {
    samm_scope_ensure_init();
    const depth: c_int = 2;
    samm_scope_reset(depth);

    const ptr = @as(?*anyopaque, @ptrFromInt(0xBEEF));
    samm_scope_add(depth, ptr, 5, 10);

    var type_id: u8 = 0;
    var sc: u8 = 0;

    // Test remove
    const found = samm_scope_remove(depth, ptr, &type_id, &sc);
    try std.testing.expect(found);
    try std.testing.expectEqual(@as(u8, 5), type_id);
    try std.testing.expectEqual(@as(u8, 10), sc);

    // Test double remove fails
    const found2 = samm_scope_remove(depth, ptr, &type_id, &sc);
    try std.testing.expect(!found2);

    // Cleanup to prevent leaks in test runner
    var out_ptrs: [*]?*anyopaque = undefined;
    var out_types: [*]u8 = undefined;
    var out_sc: [*]u8 = undefined;
    var out_count: usize = 0;
    if (samm_scope_detach(depth, &out_ptrs, &out_types, &out_sc, &out_count)) {
        c_allocator.free(out_ptrs[0..out_count]);
        c_allocator.free(out_types[0..out_count]);
        c_allocator.free(out_sc[0..out_count]);
    }
}
