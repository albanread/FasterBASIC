// class_runtime.zig
// FasterBASIC Runtime — CLASS & Object System (Zig port)
//
// Runtime support for heap-allocated CLASS instances:
//   - class_object_new()        Allocate + install vtable + class_id
//   - class_object_delete()     Destructor call + free + nullify
//   - class_is_instance()       IS type-check (walks inheritance chain)
//   - class_null_method_error() Runtime error: method call on NOTHING
//   - class_null_field_error()  Runtime error: field access on NOTHING
//   - class_object_debug()      Debug: print object info
//
// Object Memory Layout (every instance):
//   Offset  Size  Content
//   ------  ----  ---------------------------
//   0       8     vtable pointer
//   8       8     class_id (int64)
//   16      ...   fields (inherited first, then own)
//
// VTable Layout (one per class, statically allocated in data section):
//   Offset  Size  Content
//   ------  ----  ---------------------------
//   0       8     class_id (int64)
//   8       8     parent_vtable pointer (NULL for root)
//   16      8     class_name pointer (C string)
//   24      8     destructor pointer (NULL if none)
//   32+     8*N   method pointers (declaration order, parent slots first)
//
// Replaces class_runtime.c — all exported symbols maintain C ABI compatibility.

const std = @import("std");

// =========================================================================
// Constants
// =========================================================================
const CLASS_HEADER_SIZE: usize = 16; // vtable ptr (8) + class_id (8)

// =========================================================================
// C library imports
// =========================================================================
const c = struct {
    extern fn calloc(count: usize, size: usize) ?*anyopaque;
    extern fn free(ptr: ?*anyopaque) void;
    extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;
    extern fn exit(status: c_int) noreturn;

    // macOS stderr
    extern const __stderrp: *anyopaque;
    fn getStderr() *anyopaque {
        return __stderrp;
    }
};

// =========================================================================
// SAMM extern declarations
// =========================================================================
extern fn samm_is_enabled() i32;
extern fn samm_alloc_object(size: usize) ?*anyopaque;
extern fn samm_track_object(obj: *anyopaque) void;
extern fn samm_free_object(obj: *anyopaque) void;

// =========================================================================
// Object Allocation
// =========================================================================

export fn class_object_new(object_size: i64, vtable: ?*anyopaque, class_id: i64) ?*anyopaque {
    const size: usize = @intCast(object_size);

    if (size < CLASS_HEADER_SIZE) {
        _ = c.fprintf(c.getStderr(), "INTERNAL ERROR: class_object_new called with object_size=%lld (minimum is %d)\n", @as(c_longlong, object_size), @as(c_int, @intCast(CLASS_HEADER_SIZE)));
        c.exit(1);
    }

    // Allocate through SAMM if available, otherwise raw calloc.
    // samm_alloc_object returns zeroed memory (calloc semantics).
    const obj: *anyopaque = blk: {
        if (samm_is_enabled() != 0) {
            break :blk samm_alloc_object(size) orelse {
                _ = c.fprintf(c.getStderr(), "ERROR: Out of memory allocating object (%lld bytes)\n", @as(c_longlong, object_size));
                c.exit(1);
            };
        } else {
            break :blk c.calloc(1, size) orelse {
                _ = c.fprintf(c.getStderr(), "ERROR: Out of memory allocating object (%lld bytes)\n", @as(c_longlong, object_size));
                c.exit(1);
            };
        }
    };

    // Install vtable pointer at obj[0]
    const slots: [*]?*anyopaque = @ptrCast(@alignCast(obj));
    slots[0] = vtable;

    // Install class_id at obj[1] (offset 8)
    const id_slots: [*]i64 = @ptrCast(@alignCast(obj));
    id_slots[1] = class_id;

    // Track in current SAMM scope so it gets auto-cleaned on scope exit.
    // Must be done AFTER installing vtable+class_id so the background
    // cleanup worker can call the destructor via vtable[3].
    if (samm_is_enabled() != 0) {
        samm_track_object(obj);
    }

    return obj;
}

// =========================================================================
// Object Deallocation
// =========================================================================

export fn class_object_delete(obj_ref: ?*?*anyopaque) void {
    const ref = obj_ref orelse return;
    const obj = ref.* orelse return; // DELETE on NOTHING is a no-op

    // Load vtable pointer from obj[0]
    const slots: [*]?*anyopaque = @ptrCast(@alignCast(obj));
    const vtable_ptr = slots[0];

    if (vtable_ptr) |vt| {
        // Load destructor pointer from vtable[3] (offset 24)
        const vt_slots: [*]?*anyopaque = @ptrCast(@alignCast(vt));
        const dtor_ptr = vt_slots[3];

        if (dtor_ptr) |dtor| {
            // Call destructor: void dtor(void* me)
            const dtor_fn: *const fn (*anyopaque) callconv(.c) void = @ptrCast(@alignCast(dtor));
            dtor_fn(obj);
        }
    }

    // Free the object memory through SAMM or raw free.
    if (samm_is_enabled() != 0) {
        samm_free_object(obj);
    } else {
        c.free(obj);
    }

    // Set the caller's variable to NOTHING (null)
    ref.* = null;
}

// =========================================================================
// IS Type Check
// =========================================================================

export fn class_is_instance(obj: ?*anyopaque, target_class_id: i64) i32 {
    const o = obj orelse return 0; // NOTHING IS Anything → false

    // Fast path: check the object's own class_id (stored at offset 8)
    const id_slots: [*]const i64 = @ptrCast(@alignCast(o));
    const obj_class_id = id_slots[1];
    if (obj_class_id == target_class_id) return 1;

    // Slow path: walk the parent chain via vtable parent pointers.
    // VTable layout:
    //   [0] class_id       (int64)
    //   [1] parent_vtable  (pointer, NULL for root)
    //   [2] class_name     (pointer)
    //   [3] destructor     (pointer)
    //   [4+] methods...
    const slots: [*]?*anyopaque = @ptrCast(@alignCast(o));
    var vtable: ?[*]?*anyopaque = blk: {
        const vt = slots[0] orelse break :blk null;
        // Move to parent — we already checked the object's own class above
        const vt_slots: [*]?*anyopaque = @ptrCast(@alignCast(vt));
        break :blk if (vt_slots[1]) |parent|
            @as([*]?*anyopaque, @ptrCast(@alignCast(parent)))
        else
            null;
    };

    while (vtable) |vt| {
        const vt_class_id: *const i64 = @ptrCast(@alignCast(&vt[0]));
        if (vt_class_id.* == target_class_id) return 1;
        // Walk to parent_vtable
        vtable = if (vt[1]) |parent|
            @as([*]?*anyopaque, @ptrCast(@alignCast(parent)))
        else
            null;
    }

    return 0;
}

// =========================================================================
// Null-Reference Error Handlers
// =========================================================================

export fn class_null_method_error(location: ?[*:0]const u8, method_name: ?[*:0]const u8) void {
    const loc = location orelse "unknown";
    const meth = method_name orelse "unknown";
    _ = c.fprintf(c.getStderr(), "ERROR: Method call on NOTHING reference at %s (method: %s)\n", @as([*:0]const u8, loc), @as([*:0]const u8, meth));
    c.exit(1);
}

export fn class_null_field_error(location: ?[*:0]const u8, field_name: ?[*:0]const u8) void {
    const loc = location orelse "unknown";
    const fld = field_name orelse "unknown";
    _ = c.fprintf(c.getStderr(), "ERROR: Field access on NOTHING reference at %s (field: %s)\n", @as([*:0]const u8, loc), @as([*:0]const u8, fld));
    c.exit(1);
}

// =========================================================================
// Debug Utilities
// =========================================================================

export fn class_object_debug(obj: ?*anyopaque) void {
    const o = obj orelse {
        _ = c.fprintf(c.getStderr(), "[NOTHING]\n");
        return;
    };

    // Load vtable and class_id
    const slots: [*]?*anyopaque = @ptrCast(@alignCast(o));
    const id_slots: [*]const i64 = @ptrCast(@alignCast(o));
    const class_id = id_slots[1];

    var class_name: [*:0]const u8 = "(unknown)";
    if (slots[0]) |vt| {
        const vt_slots: [*]?*anyopaque = @ptrCast(@alignCast(vt));
        if (vt_slots[2]) |name_ptr| {
            class_name = @ptrCast(name_ptr);
        }
    }

    _ = c.fprintf(c.getStderr(), "[%s@%p id=%lld]\n", class_name, o, @as(c_longlong, class_id));
}

// =========================================================================
// Unit tests
// =========================================================================

test "class_is_instance returns 0 for null" {
    try std.testing.expectEqual(@as(i32, 0), class_is_instance(null, 1));
}
