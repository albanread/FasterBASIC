//! SAMM Slab Pool Allocator — Zig Implementation
//!
//! Replaces samm_pool.c with type-safe comptime-specialized pools.
//! Exports C ABI functions for compatibility with samm_core.c.
//!
//! Key features:
//! - Comptime-parameterized SlabPool(slot_size, slots_per_slab)
//! - Intrusive free-list (O(1) alloc/free)
//! - Per-pool mutex for thread safety
//! - Rich diagnostics (leak detection, stats, validation)
//! - Zero runtime overhead from comptime specialization

const std = @import("std");
const builtin = @import("builtin");

// Extern C functions and variables
extern "c" fn fprintf(stream: *anyopaque, format: [*:0]const u8, ...) c_int;
extern "c" var __stderrp: *anyopaque;

// ============================================================================
// Comptime Slab Pool Generic
// ============================================================================

/// Comptime-parameterized slab pool allocator.
/// Each instantiation generates specialized code for one fixed slot size.
pub fn SlabPool(comptime slot_size: u32, comptime slots_per_slab: u32) type {
    return struct {
        const Self = @This();

        // Compile-time constants (zero runtime cost)
        pub const SLOT_SIZE = slot_size;
        pub const SLOTS_PER_SLAB = slots_per_slab;
        pub const MAX_SLABS: usize = 1024;

        // Free-list node overlay (first @sizeOf(usize) bytes of each free slot)
        const FreeNode = struct {
            next: ?*FreeNode,
        };

        // Slab: header + contiguous array of slots
        const Slab = struct {
            next: ?*Slab,
            used_count: u32,
            data: [slots_per_slab][slot_size]u8 align(@alignOf(usize)),
        };

        // Pool state
        free_list: ?*FreeNode = null,
        slabs: ?*Slab = null,
        total_slabs: usize = 0,
        total_capacity: usize = 0,
        in_use: usize = 0,
        peak_use: usize = 0,
        peak_footprint_bytes: usize = 0,
        total_allocs: usize = 0,
        total_frees: usize = 0,
        name: [*:0]const u8,
        mutex: std.Thread.Mutex = .{},

        /// Initialize a new pool with the given name.
        pub fn init(name: [*:0]const u8) Self {
            comptime {
                // Verify slot is large enough for free-list overlay
                if (slot_size < @sizeOf(usize)) {
                    @compileError("slot_size must be >= " ++ @typeName(usize) ++ " bytes for free-list overlay");
                }
            }

            return Self{
                .name = name,
            };
        }

        /// Allocate a new slab and thread all its slots onto the free list.
        fn addSlab(self: *Self) !void {
            if (self.total_slabs >= MAX_SLABS) {
                std.log.err("SAMM Pool '{s}': maximum slabs ({d}) reached", .{ self.name, MAX_SLABS });
                return error.PoolExhausted;
            }

            // Allocate slab (header + data)
            const allocator = std.heap.c_allocator;
            const slab = try allocator.create(Slab);
            errdefer allocator.destroy(slab);

            // Initialize header
            slab.* = .{
                .next = self.slabs,
                .used_count = 0,
                .data = undefined,
            };

            // Zero all slot data
            @memset(std.mem.asBytes(&slab.data), 0);

            // Thread slots onto free list in reverse order
            // (so slot 0 ends up at head → better cache locality)
            var i: usize = slots_per_slab;
            while (i > 0) {
                i -= 1;
                const slot: *FreeNode = @ptrCast(&slab.data[i]);
                slot.next = self.free_list;
                self.free_list = slot;
            }

            // Link slab into chain
            self.slabs = slab;
            self.total_slabs += 1;
            self.total_capacity += slots_per_slab;

            // Update peak footprint
            const current_footprint = self.total_slabs * @sizeOf(Slab);
            if (current_footprint > self.peak_footprint_bytes) {
                self.peak_footprint_bytes = current_footprint;
            }
        }

        /// Allocate one slot from the pool.
        /// Returns a zeroed block of SLOT_SIZE bytes.
        pub fn alloc(self: *Self) ?*anyopaque {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Grow pool if free list is empty
            if (self.free_list == null) {
                self.addSlab() catch {
                    // Fallback to malloc if pool exhausted
                    std.log.warn("SAMM Pool '{s}': pool exhausted, falling back to malloc", .{self.name});
                    const ptr = std.heap.c_allocator.alloc(u8, slot_size) catch return null;
                    @memset(ptr, 0);
                    return ptr.ptr;
                };
            }

            // Pop from free list
            const node = self.free_list.?;
            self.free_list = node.next;

            // Update statistics
            self.in_use += 1;
            self.total_allocs += 1;
            self.peak_use = @max(self.peak_use, self.in_use);

            // Zero the slot (overwrites free-list link)
            const ptr: *[slot_size]u8 = @ptrCast(node);
            @memset(ptr, 0);

            return ptr;
        }

        /// Return one slot to the pool's free list.
        pub fn free(self: *Self, ptr: *anyopaque) void {
            self.mutex.lock();
            defer self.mutex.unlock();

            // Push onto free list head
            const node: *FreeNode = @ptrCast(@alignCast(ptr));
            node.next = self.free_list;
            self.free_list = node;

            // Update statistics
            if (self.in_use > 0) {
                self.in_use -= 1;
            } else {
                std.log.warn("SAMM Pool '{s}': free() when in_use is already 0 (double free?)", .{self.name});
            }
            self.total_frees += 1;
        }

        /// Destroy the pool and free all slabs.
        pub fn deinit(self: *Self) void {
            // Report leaks (before locking, to avoid deadlock with log)
            if (self.in_use > 0) {
                _ = fprintf(__stderrp, "SAMM Pool '%s': %zu leaked slots at shutdown\n", self.name, self.in_use);
            }

            // Free all slabs
            const allocator = std.heap.c_allocator;
            var slab = self.slabs;
            while (slab) |s| {
                const next = s.next;
                allocator.destroy(s);
                slab = next;
            }

            // Zero out pool state (preserve name for diagnostics)
            const saved_name = self.name;
            self.* = Self.init(saved_name);
        }

        /// Print pool statistics to stderr.
        pub fn printStats(self: *const Self) void {
            _ = fprintf(__stderrp, "SAMM Pool '%s':\n", self.name);
            _ = fprintf(__stderrp, "  Slot size:       %u bytes\n", slot_size);
            _ = fprintf(__stderrp, "  Slots per slab:  %u\n", slots_per_slab);
            _ = fprintf(__stderrp, "  Total slabs:     %zu\n", self.total_slabs);
            _ = fprintf(__stderrp, "  Total capacity:  %zu slots\n", self.total_capacity);
            _ = fprintf(__stderrp, "  In use:          %zu slots\n", self.in_use);
            _ = fprintf(__stderrp, "  Peak use:        %zu slots\n", self.peak_use);
            _ = fprintf(__stderrp, "  Total allocs:    %zu\n", self.total_allocs);
            _ = fprintf(__stderrp, "  Total frees:     %zu\n", self.total_frees);
            _ = fprintf(__stderrp, "  Peak footprint:  %zu bytes\n", self.peak_footprint_bytes);

            const usage_pct: f64 = if (self.total_capacity > 0)
                @as(f64, @floatFromInt(self.in_use)) / @as(f64, @floatFromInt(self.total_capacity)) * 100.0
            else
                0.0;
            _ = fprintf(__stderrp, "  Usage:           %.1f%%\n", usage_pct);
        }

        /// Validate pool integrity.
        /// Returns true if pool is consistent, false if corruption detected.
        pub fn validate(self: *const Self) bool {
            // Count free list length
            var free_count: usize = 0;
            var node = self.free_list;
            while (node) |n| : (node = n.next) {
                free_count += 1;
                if (free_count > self.total_capacity) {
                    std.log.err("SAMM Pool '{s}': free list longer than capacity (corrupted)", .{self.name});
                    return false;
                }
            }

            // Verify: free_count + in_use == total_capacity
            const expected = free_count + self.in_use;
            if (expected != self.total_capacity) {
                std.log.err("SAMM Pool '{s}': free={d} + in_use={d} = {d}, expected capacity={d}", .{
                    self.name,
                    free_count,
                    self.in_use,
                    expected,
                    self.total_capacity,
                });
                return false;
            }

            return true;
        }
    };
}

// ============================================================================
// Global Pool Instances
// ============================================================================

// String descriptor pool (Phase 4 migration from StringDescriptorPool)
var g_string_desc_pool_instance = SlabPool(40, 256).init("StringDesc");

// List pools (Phase 2)
var g_list_header_pool_instance = SlabPool(32, 256).init("ListHeader");
var g_list_atom_pool_instance = SlabPool(24, 512).init("ListAtom");

// Object size-class pools (Phase 3)
// Note: Each pool type is different due to comptime slot_size, but we wrap them in a union
// to store in a homogeneous array. C code sees them all as opaque *anyopaque anyway.
const ObjectPool = union(enum) {
    p32: SlabPool(32, 128),
    p64: SlabPool(64, 128),
    p128: SlabPool(128, 128),
    p256: SlabPool(256, 128),
    p512: SlabPool(512, 64),
    p1024: SlabPool(1024, 32),
};

var g_object_pools_instance = [_]ObjectPool{
    .{ .p32 = SlabPool(32, 128).init("Object_32") },
    .{ .p64 = SlabPool(64, 128).init("Object_64") },
    .{ .p128 = SlabPool(128, 128).init("Object_128") },
    .{ .p256 = SlabPool(256, 128).init("Object_256") },
    .{ .p512 = SlabPool(512, 64).init("Object_512") },
    .{ .p1024 = SlabPool(1024, 32).init("Object_1024") },
};

// Export as C symbols (must match samm_pool.h declarations)
// We export pointers because Zig cannot export structs with runtime-initialized fields (mutexes).
export var g_string_desc_pool: *anyopaque = @ptrCast(&g_string_desc_pool_instance);
export var g_list_header_pool: *anyopaque = @ptrCast(&g_list_header_pool_instance);
export var g_list_atom_pool: *anyopaque = @ptrCast(&g_list_atom_pool_instance);
export var g_object_pools: [6]*anyopaque = .{
    @ptrCast(&g_object_pools_instance[0]),
    @ptrCast(&g_object_pools_instance[1]),
    @ptrCast(&g_object_pools_instance[2]),
    @ptrCast(&g_object_pools_instance[3]),
    @ptrCast(&g_object_pools_instance[4]),
    @ptrCast(&g_object_pools_instance[5]),
};

// ============================================================================
// C ABI Exports
// ============================================================================

/// Initialize a pool by pre-allocating SAMM_SLAB_POOL_INITIAL_SLABS (1) slab.
/// C now declares pool globals as pointers (SammSlabPool*), so handle is the
/// direct pool instance pointer — no ptr-to-ptr dereference needed.
export fn samm_slab_pool_init(
    handle: ?*anyopaque,
    slot_size: u32,
    slots_per_slab: u32,
    name: [*:0]const u8,
) callconv(.c) void {
    _ = slot_size;
    _ = slots_per_slab;
    _ = name;

    const h = handle orelse return;

    // Dispatch by comparing the handle address to the known pool instance addresses.
    // This is the same pattern used by samm_slab_pool_alloc/free/destroy/etc.

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        g_string_desc_pool_instance.addSlab() catch |err| {
            std.log.err("Failed to add initial slab to StringDesc pool: {any}", .{err});
        };
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        g_list_header_pool_instance.addSlab() catch |err| {
            std.log.err("Failed to add initial slab to ListHeader pool: {any}", .{err});
        };
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        g_list_atom_pool_instance.addSlab() catch |err| {
            std.log.err("Failed to add initial slab to ListAtom pool: {any}", .{err});
        };
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.addSlab() catch |err| {
                    std.log.err("Failed to add initial slab to object pool {d}: {any}", .{ i, err });
                },
            }
            return;
        }
    }

    // Unknown pool handle
    std.log.err("samm_slab_pool_init: unknown pool handle", .{});
}

/// Destroy a pool and free all slabs.
export fn samm_slab_pool_destroy(handle: ?*anyopaque) callconv(.c) void {
    const h = handle orelse return;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        g_string_desc_pool_instance.deinit();
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        g_list_header_pool_instance.deinit();
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        g_list_atom_pool_instance.deinit();
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.deinit(),
            }
            return;
        }
    }
}

/// Allocate one slot from the pool.
export fn samm_slab_pool_alloc(handle: ?*anyopaque) callconv(.c) ?*anyopaque {
    const h = handle orelse return null;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        return g_string_desc_pool_instance.alloc();
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        return g_list_header_pool_instance.alloc();
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        return g_list_atom_pool_instance.alloc();
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            return switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.alloc(),
            };
        }
    }

    return null;
}

/// Return one slot to the pool's free list.
export fn samm_slab_pool_free(handle: ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
    const h = handle orelse return;
    const p = ptr orelse return;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        g_string_desc_pool_instance.free(p);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        g_list_header_pool_instance.free(p);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        g_list_atom_pool_instance.free(p);
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.free(p),
            }
            return;
        }
    }
}

/// Print pool statistics to stderr.
export fn samm_slab_pool_print_stats(handle: ?*anyopaque) callconv(.c) void {
    const h = handle orelse return;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        g_string_desc_pool_instance.printStats();
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        g_list_header_pool_instance.printStats();
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        g_list_atom_pool_instance.printStats();
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.printStats(),
            }
            return;
        }
    }
}

/// Get statistics for a pool (snapshot, not locked).
export fn samm_slab_pool_stats(
    handle: ?*anyopaque,
    out_in_use: ?*usize,
    out_capacity: ?*usize,
    out_peak_use: ?*usize,
    out_slabs: ?*usize,
    out_allocs: ?*usize,
    out_frees: ?*usize,
) callconv(.c) void {
    const h = handle orelse return;

    // Helper to extract stats from a pool
    const extractStats = struct {
        fn extract(
            comptime T: type,
            pool: *const T,
            opt_in_use: ?*usize,
            opt_capacity: ?*usize,
            opt_peak_use: ?*usize,
            opt_slabs: ?*usize,
            opt_allocs: ?*usize,
            opt_frees: ?*usize,
        ) void {
            if (opt_in_use) |p| p.* = pool.in_use;
            if (opt_capacity) |p| p.* = pool.total_capacity;
            if (opt_peak_use) |p| p.* = pool.peak_use;
            if (opt_slabs) |p| p.* = pool.total_slabs;
            if (opt_allocs) |p| p.* = pool.total_allocs;
            if (opt_frees) |p| p.* = pool.total_frees;
        }
    }.extract;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        extractStats(@TypeOf(g_string_desc_pool_instance), &g_string_desc_pool_instance, out_in_use, out_capacity, out_peak_use, out_slabs, out_allocs, out_frees);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        extractStats(@TypeOf(g_list_header_pool_instance), &g_list_header_pool_instance, out_in_use, out_capacity, out_peak_use, out_slabs, out_allocs, out_frees);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        extractStats(@TypeOf(g_list_atom_pool_instance), &g_list_atom_pool_instance, out_in_use, out_capacity, out_peak_use, out_slabs, out_allocs, out_frees);
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| extractStats(@TypeOf(pool.*), pool, out_in_use, out_capacity, out_peak_use, out_slabs, out_allocs, out_frees),
            }
            return;
        }
    }
}

/// Validate pool integrity.
export fn samm_slab_pool_validate(handle: ?*anyopaque) callconv(.c) c_int {
    const h = handle orelse return 0;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        return if (g_string_desc_pool_instance.validate()) 1 else 0;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        return if (g_list_header_pool_instance.validate()) 1 else 0;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        return if (g_list_atom_pool_instance.validate()) 1 else 0;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            return switch (g_object_pools_instance[i]) {
                inline else => |*pool| if (pool.validate()) 1 else 0,
            };
        }
    }

    return 0;
}

/// Check for leaked slots and report to stderr.
export fn samm_slab_pool_check_leaks(handle: ?*anyopaque) callconv(.c) void {
    const h = handle orelse return;

    // All pools report leaks in their deinit() method, so we just
    // check in_use here and print if non-zero
    const checkLeaks = struct {
        fn check(comptime T: type, pool: *const T) void {
            if (pool.in_use > 0) {
                _ = fprintf(__stderrp, "SAMM Pool '%s': %zu leaked slots\n", pool.name, pool.in_use);
            }
        }
    }.check;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        checkLeaks(@TypeOf(g_string_desc_pool_instance), &g_string_desc_pool_instance);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        checkLeaks(@TypeOf(g_list_header_pool_instance), &g_list_header_pool_instance);
        return;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        checkLeaks(@TypeOf(g_list_atom_pool_instance), &g_list_atom_pool_instance);
        return;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            switch (g_object_pools_instance[i]) {
                inline else => |*pool| checkLeaks(@TypeOf(pool.*), pool),
            }
            return;
        }
    }
}

/// NEW: Accessor for total_allocs (replaces direct field access in samm_core.c).
export fn samm_slab_pool_total_allocs(handle: ?*anyopaque) callconv(.c) usize {
    const h = handle orelse return 0;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        return g_string_desc_pool_instance.total_allocs;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        return g_list_header_pool_instance.total_allocs;
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        return g_list_atom_pool_instance.total_allocs;
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            return switch (g_object_pools_instance[i]) {
                inline else => |*pool| pool.total_allocs,
            };
        }
    }

    return 0;
}

/// Usage percentage accessor (replaces static inline in samm_pool.h that
/// cannot read Zig struct fields directly).
export fn samm_slab_pool_usage_percent(handle: ?*anyopaque) callconv(.c) f64 {
    const h = handle orelse return 0.0;

    const computeUsage = struct {
        fn compute(comptime T: type, pool: *const T) f64 {
            if (pool.total_capacity == 0) return 0.0;
            return @as(f64, @floatFromInt(pool.in_use)) / @as(f64, @floatFromInt(pool.total_capacity)) * 100.0;
        }
    }.compute;

    if (h == @as(*anyopaque, @ptrCast(&g_string_desc_pool_instance))) {
        return computeUsage(@TypeOf(g_string_desc_pool_instance), &g_string_desc_pool_instance);
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_header_pool_instance))) {
        return computeUsage(@TypeOf(g_list_header_pool_instance), &g_list_header_pool_instance);
    }
    if (h == @as(*anyopaque, @ptrCast(&g_list_atom_pool_instance))) {
        return computeUsage(@TypeOf(g_list_atom_pool_instance), &g_list_atom_pool_instance);
    }

    // Check object pools
    inline for (0..6) |i| {
        if (h == @as(*anyopaque, @ptrCast(&g_object_pools_instance[i]))) {
            return switch (g_object_pools_instance[i]) {
                inline else => |*pool| computeUsage(@TypeOf(pool.*), pool),
            };
        }
    }

    return 0.0;
}

// ============================================================================
// Unit Tests
// ============================================================================

test "alloc returns zeroed slot" {
    var pool = SlabPool(64, 16).init("test");
    defer pool.deinit();

    const ptr = pool.alloc() orelse return error.AllocFailed;
    const bytes: [*]u8 = @ptrCast(ptr);

    for (0..64) |i| {
        try std.testing.expectEqual(@as(u8, 0), bytes[i]);
    }
}

test "alloc/free cycle preserves in_use count" {
    var pool = SlabPool(32, 8).init("test");
    defer pool.deinit();

    var ptrs: [8]?*anyopaque = undefined;
    for (&ptrs) |*p| {
        p.* = pool.alloc();
    }

    try std.testing.expectEqual(@as(usize, 8), pool.in_use);

    for (ptrs) |p| {
        if (p) |ptr| pool.free(ptr);
    }

    try std.testing.expectEqual(@as(usize, 0), pool.in_use);
}

test "slab growth on exhaustion" {
    var pool = SlabPool(32, 4).init("test");
    defer pool.deinit();

    // Exhaust first slab
    for (0..4) |_| _ = pool.alloc();
    try std.testing.expectEqual(@as(usize, 1), pool.total_slabs);

    // Triggers second slab
    _ = pool.alloc();
    try std.testing.expectEqual(@as(usize, 2), pool.total_slabs);
}

test "peak_use tracking" {
    var pool = SlabPool(64, 16).init("test");
    defer pool.deinit();

    var ptrs: [10]?*anyopaque = undefined;
    for (&ptrs) |*p| {
        p.* = pool.alloc();
    }

    try std.testing.expectEqual(@as(usize, 10), pool.peak_use);

    // Free half
    for (0..5) |i| {
        if (ptrs[i]) |ptr| pool.free(ptr);
    }

    try std.testing.expectEqual(@as(usize, 5), pool.in_use);
    try std.testing.expectEqual(@as(usize, 10), pool.peak_use); // Peak unchanged
}

test "validate returns true for consistent pool" {
    var pool = SlabPool(48, 8).init("test");
    defer pool.deinit();

    try std.testing.expect(pool.validate());

    var ptrs: [4]?*anyopaque = undefined;
    for (&ptrs) |*p| {
        p.* = pool.alloc();
    }

    try std.testing.expect(pool.validate());

    for (ptrs) |p| {
        if (p) |ptr| pool.free(ptr);
    }

    try std.testing.expect(pool.validate());
}
