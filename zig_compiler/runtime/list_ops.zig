//
// list_ops.zig
// FasterBASIC Runtime — Linked List Operations (Zig port)
//
// Implements singly-linked heterogeneous and typed lists.
// All positions are 1-based (BASIC convention).
// SAMM integration: headers tracked as SAMM_ALLOC_LIST,
// atoms tracked as SAMM_ALLOC_LIST_ATOM.
//
// All exported functions use callconv(.c) for C ABI compatibility.
//

const std = @import("std");
const c = std.c;

// =========================================================================
// Atom Type Tags
// =========================================================================
pub const ATOM_SENTINEL: i32 = 0;
pub const ATOM_INT: i32 = 1;
pub const ATOM_FLOAT: i32 = 2;
pub const ATOM_STRING: i32 = 3;
pub const ATOM_LIST: i32 = 4;
pub const ATOM_OBJECT: i32 = 5;

// =========================================================================
// ListHeader Flags
// =========================================================================
pub const LIST_FLAG_ELEM_ANY: i32 = 0x0000;
pub const LIST_FLAG_ELEM_MASK: i32 = 0x0F00;

// =========================================================================
// Struct Layouts (must match list_ops.h)
// =========================================================================

/// Value union — 8 bytes, same layout as C union { int64_t; double; void* }
pub const AtomValue = extern union {
    int_value: i64,
    float_value: f64,
    ptr_value: ?*anyopaque,
};

/// ListAtom — 24 bytes per element
pub const ListAtom = extern struct {
    type: i32,
    pad: i32,
    value: AtomValue,
    next: ?*ListAtom,
};

/// ListHeader — 32 bytes, the handle that BASIC variables point to
pub const ListHeader = extern struct {
    type: i32,
    flags: i32,
    length: i64,
    head: ?*ListAtom,
    tail: ?*ListAtom,
};

// =========================================================================
// Extern declarations
// =========================================================================

// SAMM functions
extern fn samm_is_enabled() c_int;
extern fn samm_alloc_list_atom() ?*anyopaque;
extern fn samm_alloc_list() ?*anyopaque;
extern fn samm_track(ptr: ?*anyopaque, alloc_type: c_int) void;
extern fn samm_track_list(ptr: ?*anyopaque) void;
extern fn samm_untrack(ptr: ?*anyopaque) void;
extern fn samm_record_bytes_freed(bytes: u64) void;
extern fn samm_slab_pool_alloc(pool: ?*anyopaque) ?*anyopaque;
extern fn samm_slab_pool_free(pool: ?*anyopaque, ptr: ?*anyopaque) void;
extern var g_list_atom_pool: ?*anyopaque;
extern var g_list_header_pool: ?*anyopaque;

// String functions (from string_utf32.zig / string_ops.zig)
extern fn string_retain(str: ?*anyopaque) ?*anyopaque;
extern fn string_release(str: ?*anyopaque) void;
extern fn string_compare(a: ?*const anyopaque, b: ?*const anyopaque) c_int;
extern fn string_to_utf8(str: ?*anyopaque) [*:0]const u8;
extern fn string_new_ascii(str: ?[*:0]const u8) ?*anyopaque;
extern fn string_new_utf8(str: ?[*:0]const u8) ?*anyopaque;

// C stdlib
extern fn snprintf(buf: [*]u8, size: usize, fmt: [*:0]const u8, ...) c_int;
extern fn strdup(s: [*:0]const u8) ?[*:0]u8;
extern const __stderrp: *anyopaque;
extern fn fprintf(stream: *anyopaque, fmt: [*:0]const u8, ...) c_int;

// SAMM alloc type for tracking
const SAMM_ALLOC_LIST_ATOM: c_int = 5;

// =========================================================================
// Internal: Atom allocation & cleanup
// =========================================================================

fn atomAlloc() *ListAtom {
    var raw: ?*anyopaque = null;

    if (samm_is_enabled() != 0) {
        raw = samm_alloc_list_atom();
    } else {
        raw = samm_slab_pool_alloc(g_list_atom_pool);
    }

    if (raw == null) {
        _ = fprintf(__stderrp, "list_ops: out of memory allocating ListAtom\n");
        std.process.abort();
    }

    const atom: *ListAtom = @ptrCast(@alignCast(raw.?));
    atom.type = ATOM_SENTINEL;

    if (samm_is_enabled() != 0) {
        samm_track(@ptrCast(atom), SAMM_ALLOC_LIST_ATOM);
    }

    return atom;
}

fn atomReleasePayload(atom: ?*ListAtom) void {
    const a = atom orelse return;

    switch (a.type) {
        ATOM_STRING => {
            if (a.value.ptr_value) |ptr| {
                string_release(ptr);
                a.value.ptr_value = null;
            }
        },
        ATOM_LIST => {
            if (a.value.ptr_value) |ptr| {
                list_free(@ptrCast(@alignCast(ptr)));
                a.value.ptr_value = null;
            }
        },
        ATOM_OBJECT => {
            a.value.ptr_value = null;
        },
        else => {},
    }
}

fn atomFree(atom: ?*ListAtom) void {
    const a = atom orelse return;
    atomReleasePayload(a);
    if (samm_is_enabled() != 0) {
        samm_untrack(@ptrCast(a));
    }
    samm_record_bytes_freed(@sizeOf(ListAtom));
    samm_slab_pool_free(g_list_atom_pool, @ptrCast(a));
}

fn atomWalkTo(head: ?*ListAtom, pos: i64, out_prev: ?*?*ListAtom) ?*ListAtom {
    if (out_prev) |pp| pp.* = null;
    if (pos < 1) return null;
    var curr = head orelse return null;

    var prev: ?*ListAtom = null;
    var i: i64 = 1;

    while (i < pos) : (i += 1) {
        prev = curr;
        curr = curr.next orelse return null;
    }

    if (out_prev) |pp| pp.* = prev;
    return curr;
}

// =========================================================================
// Internal: Atom linking helpers
// =========================================================================

fn listAppendAtom(list: ?*ListHeader, atom: ?*ListAtom) void {
    const l = list orelse return;
    const a = atom orelse return;
    a.next = null;

    if (l.tail) |tail| {
        tail.next = a;
        l.tail = a;
    } else {
        l.head = a;
        l.tail = a;
    }
    l.length += 1;
}

fn listPrependAtom(list: ?*ListHeader, atom: ?*ListAtom) void {
    const l = list orelse return;
    const a = atom orelse return;
    a.next = l.head;
    l.head = a;

    if (l.tail == null) {
        l.tail = a;
    }
    l.length += 1;
}

fn listInsertAtom(list: ?*ListHeader, pos: i64, atom: ?*ListAtom) void {
    const l = list orelse return;
    const a = atom orelse return;

    if (pos <= 1) {
        listPrependAtom(l, a);
        return;
    }
    if (pos > l.length) {
        listAppendAtom(l, a);
        return;
    }

    var prev: ?*ListAtom = null;
    _ = atomWalkTo(l.head, pos, &prev);

    const p = prev orelse {
        listPrependAtom(l, a);
        return;
    };

    a.next = p.next;
    p.next = a;

    if (a.next == null) {
        l.tail = a;
    }
    l.length += 1;
}

// =========================================================================
// Internal: shift/pop helpers
// =========================================================================

fn listShiftAtom(list: ?*ListHeader) ?*ListAtom {
    const l = list orelse return null;
    const atom = l.head orelse return null;
    l.head = atom.next;
    atom.next = null;

    if (l.head == null) {
        l.tail = null;
    }
    l.length -= 1;
    return atom;
}

fn listPopAtom(list: ?*ListHeader) ?*ListAtom {
    const l = list orelse return null;
    const head = l.head orelse return null;

    // Single element?
    if (l.head == l.tail) {
        l.head = null;
        l.tail = null;
        l.length = 0;
        head.next = null;
        return head;
    }

    // Walk to second-to-last
    var prev = head;
    while (true) {
        const next = prev.next orelse break;
        if (next == l.tail) break;
        prev = next;
    }

    const atom = l.tail orelse return null;
    prev.next = null;
    l.tail = prev;
    l.length -= 1;
    atom.next = null;
    return atom;
}

/// Free an atom shell without releasing payload (for shift/pop value extraction)
fn atomFreeShell(atom: *ListAtom) void {
    if (samm_is_enabled() != 0) samm_untrack(@ptrCast(atom));
    samm_record_bytes_freed(@sizeOf(ListAtom));
    samm_slab_pool_free(g_list_atom_pool, @ptrCast(atom));
}

// =========================================================================
// Creation & Destruction
// =========================================================================

export fn list_create() callconv(.c) ?*ListHeader {
    var raw: ?*anyopaque = null;

    if (samm_is_enabled() != 0) {
        raw = samm_alloc_list();
    } else {
        raw = samm_slab_pool_alloc(g_list_header_pool);
    }

    if (raw == null) {
        _ = fprintf(__stderrp, "list_ops: out of memory allocating ListHeader\n");
        std.process.abort();
    }

    const h: *ListHeader = @ptrCast(@alignCast(raw.?));
    h.type = ATOM_SENTINEL;
    h.flags = LIST_FLAG_ELEM_ANY;
    h.length = 0;
    h.head = null;
    h.tail = null;

    if (samm_is_enabled() != 0) {
        samm_track_list(@ptrCast(h));
    }

    return h;
}

export fn list_create_typed(elem_type_flag: i32) callconv(.c) ?*ListHeader {
    const h = list_create() orelse return null;
    h.flags = (h.flags & ~LIST_FLAG_ELEM_MASK) | (elem_type_flag & LIST_FLAG_ELEM_MASK);
    return h;
}

export fn list_free(list: ?*ListHeader) callconv(.c) void {
    const l = list orelse return;

    if (samm_is_enabled() != 0) {
        samm_untrack(@ptrCast(l));
    }

    var curr = l.head;
    while (curr) |atom| {
        const next = atom.next;
        atomFree(atom);
        curr = next;
    }

    l.head = null;
    l.tail = null;
    l.length = 0;

    samm_record_bytes_freed(@sizeOf(ListHeader));
    samm_slab_pool_free(g_list_header_pool, @ptrCast(l));
}

// =========================================================================
// Adding Elements — Append
// =========================================================================

export fn list_append_int(list: ?*ListHeader, value: i64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_INT;
    atom.value.int_value = value;
    listAppendAtom(list, atom);
}

export fn list_append_float(list: ?*ListHeader, value: f64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_FLOAT;
    atom.value.float_value = value;
    listAppendAtom(list, atom);
}

export fn list_append_string(list: ?*ListHeader, value: ?*anyopaque) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_STRING;
    if (value != null) {
        _ = string_retain(value);
    }
    atom.value.ptr_value = value;
    listAppendAtom(list, atom);
}

export fn list_append_list(list: ?*ListHeader, nested: ?*ListHeader) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_LIST;
    atom.value.ptr_value = @ptrCast(nested);
    listAppendAtom(list, atom);
}

export fn list_append_object(list: ?*ListHeader, object_ptr: ?*anyopaque) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_OBJECT;
    atom.value.ptr_value = object_ptr;
    listAppendAtom(list, atom);
}

// =========================================================================
// Adding Elements — Prepend
// =========================================================================

export fn list_prepend_int(list: ?*ListHeader, value: i64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_INT;
    atom.value.int_value = value;
    listPrependAtom(list, atom);
}

export fn list_prepend_float(list: ?*ListHeader, value: f64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_FLOAT;
    atom.value.float_value = value;
    listPrependAtom(list, atom);
}

export fn list_prepend_string(list: ?*ListHeader, value: ?*anyopaque) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_STRING;
    if (value != null) {
        _ = string_retain(value);
    }
    atom.value.ptr_value = value;
    listPrependAtom(list, atom);
}

export fn list_prepend_list(list: ?*ListHeader, nested: ?*ListHeader) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_LIST;
    atom.value.ptr_value = @ptrCast(nested);
    listPrependAtom(list, atom);
}

// =========================================================================
// Adding Elements — Insert (1-based position)
// =========================================================================

export fn list_insert_int(list: ?*ListHeader, pos: i64, value: i64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_INT;
    atom.value.int_value = value;
    listInsertAtom(list, pos, atom);
}

export fn list_insert_float(list: ?*ListHeader, pos: i64, value: f64) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_FLOAT;
    atom.value.float_value = value;
    listInsertAtom(list, pos, atom);
}

export fn list_insert_string(list: ?*ListHeader, pos: i64, value: ?*anyopaque) callconv(.c) void {
    if (list == null) return;
    const atom = atomAlloc();
    atom.type = ATOM_STRING;
    if (value != null) {
        _ = string_retain(value);
    }
    atom.value.ptr_value = value;
    listInsertAtom(list, pos, atom);
}

// =========================================================================
// Extending
// =========================================================================

export fn list_extend(dest: ?*ListHeader, src: ?*ListHeader) callconv(.c) void {
    const d = dest orelse return;
    const s = src orelse return;

    var curr = s.head;
    while (curr) |atom| {
        switch (atom.type) {
            ATOM_INT => list_append_int(d, atom.value.int_value),
            ATOM_FLOAT => list_append_float(d, atom.value.float_value),
            ATOM_STRING => list_append_string(d, atom.value.ptr_value),
            ATOM_LIST => list_append_list(d, list_copy(@ptrCast(@alignCast(atom.value.ptr_value)))),
            ATOM_OBJECT => list_append_object(d, atom.value.ptr_value),
            else => {},
        }
        curr = atom.next;
    }
}

// =========================================================================
// Removing Elements — Shift (remove first)
// =========================================================================

export fn list_shift_int(list: ?*ListHeader) callconv(.c) i64 {
    const atom = listShiftAtom(list) orelse return 0;
    const val = atom.value.int_value;
    atomFreeShell(atom);
    return val;
}

export fn list_shift_float(list: ?*ListHeader) callconv(.c) f64 {
    const atom = listShiftAtom(list) orelse return 0.0;
    const val = atom.value.float_value;
    atomFreeShell(atom);
    return val;
}

export fn list_shift_ptr(list: ?*ListHeader) callconv(.c) ?*anyopaque {
    const atom = listShiftAtom(list) orelse return null;
    const val = atom.value.ptr_value;
    atomFreeShell(atom);
    return val;
}

export fn list_shift_type(list: ?*ListHeader) callconv(.c) i32 {
    const l = list orelse return ATOM_SENTINEL;
    const head = l.head orelse return ATOM_SENTINEL;
    return head.type;
}

export fn list_shift(list: ?*ListHeader) callconv(.c) void {
    const atom = listShiftAtom(list) orelse return;
    atomFree(atom);
}

// =========================================================================
// Removing Elements — Pop (remove last, O(n))
// =========================================================================

export fn list_pop_int(list: ?*ListHeader) callconv(.c) i64 {
    const atom = listPopAtom(list) orelse return 0;
    const val = atom.value.int_value;
    atomFreeShell(atom);
    return val;
}

export fn list_pop_float(list: ?*ListHeader) callconv(.c) f64 {
    const atom = listPopAtom(list) orelse return 0.0;
    const val = atom.value.float_value;
    atomFreeShell(atom);
    return val;
}

export fn list_pop_ptr(list: ?*ListHeader) callconv(.c) ?*anyopaque {
    const atom = listPopAtom(list) orelse return null;
    const val = atom.value.ptr_value;
    atomFreeShell(atom);
    return val;
}

export fn list_pop(list: ?*ListHeader) callconv(.c) void {
    const atom = listPopAtom(list) orelse return;
    atomFree(atom);
}

// =========================================================================
// Removing Elements — Positional
// =========================================================================

export fn list_remove(list: ?*ListHeader, pos: i64) callconv(.c) void {
    const l = list orelse return;
    if (l.head == null or pos < 1 or pos > l.length) return;

    if (pos == 1) {
        list_shift(l);
        return;
    }
    if (pos == l.length) {
        list_pop(l);
        return;
    }

    var prev: ?*ListAtom = null;
    const target = atomWalkTo(l.head, pos, &prev) orelse return;
    const p = prev orelse return;

    p.next = target.next;
    target.next = null;
    l.length -= 1;
    atomFree(target);
}

export fn list_clear(list: ?*ListHeader) callconv(.c) void {
    const l = list orelse return;

    var curr = l.head;
    while (curr) |atom| {
        const next = atom.next;
        atomFree(atom);
        curr = next;
    }

    l.head = null;
    l.tail = null;
    l.length = 0;
}

// =========================================================================
// Access — Positional (1-based)
// =========================================================================

export fn list_get_int(list: ?*ListHeader, pos: i64) callconv(.c) i64 {
    if (list == null) return 0;
    const atom = atomWalkTo(list.?.head, pos, null) orelse return 0;
    return atom.value.int_value;
}

export fn list_get_float(list: ?*ListHeader, pos: i64) callconv(.c) f64 {
    if (list == null) return 0.0;
    const atom = atomWalkTo(list.?.head, pos, null) orelse return 0.0;
    return atom.value.float_value;
}

export fn list_get_ptr(list: ?*ListHeader, pos: i64) callconv(.c) ?*anyopaque {
    if (list == null) return null;
    const atom = atomWalkTo(list.?.head, pos, null) orelse return null;
    return atom.value.ptr_value;
}

export fn list_get_type(list: ?*ListHeader, pos: i64) callconv(.c) i32 {
    if (list == null) return ATOM_SENTINEL;
    const atom = atomWalkTo(list.?.head, pos, null) orelse return ATOM_SENTINEL;
    return atom.type;
}

// =========================================================================
// Access — Head
// =========================================================================

export fn list_head_int(list: ?*ListHeader) callconv(.c) i64 {
    const l = list orelse return 0;
    const head = l.head orelse return 0;
    return head.value.int_value;
}

export fn list_head_float(list: ?*ListHeader) callconv(.c) f64 {
    const l = list orelse return 0.0;
    const head = l.head orelse return 0.0;
    return head.value.float_value;
}

export fn list_head_ptr(list: ?*ListHeader) callconv(.c) ?*anyopaque {
    const l = list orelse return null;
    const head = l.head orelse return null;
    return head.value.ptr_value;
}

export fn list_head_type(list: ?*ListHeader) callconv(.c) i32 {
    const l = list orelse return ATOM_SENTINEL;
    const head = l.head orelse return ATOM_SENTINEL;
    return head.type;
}

// =========================================================================
// Access — Metadata
// =========================================================================

export fn list_length(list: ?*ListHeader) callconv(.c) i64 {
    const l = list orelse return 0;
    return l.length;
}

export fn list_empty(list: ?*ListHeader) callconv(.c) i32 {
    const l = list orelse return 1;
    return if (l.length == 0) 1 else 0;
}

// =========================================================================
// Iteration Support
// =========================================================================

export fn list_iter_begin(list: ?*ListHeader) callconv(.c) ?*ListAtom {
    const l = list orelse return null;
    return l.head;
}

export fn list_iter_next(current: ?*ListAtom) callconv(.c) ?*ListAtom {
    const a = current orelse return null;
    return a.next;
}

export fn list_iter_type(current: ?*ListAtom) callconv(.c) i32 {
    const a = current orelse return ATOM_SENTINEL;
    return a.type;
}

export fn list_iter_value_int(current: ?*ListAtom) callconv(.c) i64 {
    const a = current orelse return 0;
    return a.value.int_value;
}

export fn list_iter_value_float(current: ?*ListAtom) callconv(.c) f64 {
    const a = current orelse return 0.0;
    return a.value.float_value;
}

export fn list_iter_value_ptr(current: ?*ListAtom) callconv(.c) ?*anyopaque {
    const a = current orelse return null;
    return a.value.ptr_value;
}

// =========================================================================
// Operations — Copy / Rest / Reverse
// =========================================================================

export fn list_copy(list: ?*ListHeader) callconv(.c) ?*ListHeader {
    const l = list orelse return list_create();

    const copy = list_create_typed(l.flags & LIST_FLAG_ELEM_MASK) orelse return null;

    var curr = l.head;
    while (curr) |atom| {
        switch (atom.type) {
            ATOM_INT => list_append_int(copy, atom.value.int_value),
            ATOM_FLOAT => list_append_float(copy, atom.value.float_value),
            ATOM_STRING => list_append_string(copy, atom.value.ptr_value),
            ATOM_LIST => list_append_list(copy, list_copy(@ptrCast(@alignCast(atom.value.ptr_value)))),
            ATOM_OBJECT => list_append_object(copy, atom.value.ptr_value),
            else => {},
        }
        curr = atom.next;
    }
    return copy;
}

export fn list_rest(list: ?*ListHeader) callconv(.c) ?*ListHeader {
    const l = list orelse return list_create();
    const head = l.head orelse return list_create();

    const rest = list_create_typed(l.flags & LIST_FLAG_ELEM_MASK) orelse return null;

    var curr = head.next;
    while (curr) |atom| {
        switch (atom.type) {
            ATOM_INT => list_append_int(rest, atom.value.int_value),
            ATOM_FLOAT => list_append_float(rest, atom.value.float_value),
            ATOM_STRING => list_append_string(rest, atom.value.ptr_value),
            ATOM_LIST => list_append_list(rest, list_copy(@ptrCast(@alignCast(atom.value.ptr_value)))),
            ATOM_OBJECT => list_append_object(rest, atom.value.ptr_value),
            else => {},
        }
        curr = atom.next;
    }
    return rest;
}

export fn list_reverse(list: ?*ListHeader) callconv(.c) ?*ListHeader {
    const l = list orelse return list_create();

    const rev = list_create_typed(l.flags & LIST_FLAG_ELEM_MASK) orelse return null;

    var curr = l.head;
    while (curr) |atom| {
        switch (atom.type) {
            ATOM_INT => list_prepend_int(rev, atom.value.int_value),
            ATOM_FLOAT => list_prepend_float(rev, atom.value.float_value),
            ATOM_STRING => list_prepend_string(rev, atom.value.ptr_value),
            ATOM_LIST => list_prepend_list(rev, list_copy(@ptrCast(@alignCast(atom.value.ptr_value)))),
            ATOM_OBJECT => {
                const a = atomAlloc();
                a.type = ATOM_OBJECT;
                a.value.ptr_value = atom.value.ptr_value;
                listPrependAtom(rev, a);
            },
            else => {},
        }
        curr = atom.next;
    }
    return rev;
}

// =========================================================================
// Operations — Search
// =========================================================================

export fn list_contains_int(list: ?*ListHeader, value: i64) callconv(.c) i32 {
    const l = list orelse return 0;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_INT and atom.value.int_value == value) return 1;
        curr = atom.next;
    }
    return 0;
}

export fn list_contains_float(list: ?*ListHeader, value: f64) callconv(.c) i32 {
    const l = list orelse return 0;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_FLOAT and atom.value.float_value == value) return 1;
        curr = atom.next;
    }
    return 0;
}

export fn list_contains_string(list: ?*ListHeader, value: ?*anyopaque) callconv(.c) i32 {
    const l = list orelse return 0;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_STRING) {
            const elem = atom.value.ptr_value;
            if (elem == value) return 1;
            if (elem != null and value != null and string_compare(elem, value) == 0) return 1;
        }
        curr = atom.next;
    }
    return 0;
}

export fn list_indexof_int(list: ?*ListHeader, value: i64) callconv(.c) i64 {
    const l = list orelse return 0;
    var index: i64 = 1;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_INT and atom.value.int_value == value) return index;
        curr = atom.next;
        index += 1;
    }
    return 0;
}

export fn list_indexof_float(list: ?*ListHeader, value: f64) callconv(.c) i64 {
    const l = list orelse return 0;
    var index: i64 = 1;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_FLOAT and atom.value.float_value == value) return index;
        curr = atom.next;
        index += 1;
    }
    return 0;
}

export fn list_indexof_string(list: ?*ListHeader, value: ?*anyopaque) callconv(.c) i64 {
    const l = list orelse return 0;
    var index: i64 = 1;
    var curr = l.head;
    while (curr) |atom| {
        if (atom.type == ATOM_STRING) {
            const elem = atom.value.ptr_value;
            if (elem == value) return index;
            if (elem != null and value != null and string_compare(elem, value) == 0) return index;
        }
        curr = atom.next;
        index += 1;
    }
    return 0;
}

// =========================================================================
// Operations — Join
// =========================================================================

fn atomValueToCstr(atom: ?*ListAtom) ?[*:0]u8 {
    const a = atom orelse return strdup("");

    switch (a.type) {
        ATOM_INT => {
            var buf: [64]u8 = undefined;
            _ = snprintf(&buf, buf.len, "%lld", a.value.int_value);
            return strdup(@ptrCast(&buf));
        },
        ATOM_FLOAT => {
            var buf: [64]u8 = undefined;
            _ = snprintf(&buf, buf.len, "%g", a.value.float_value);
            return strdup(@ptrCast(&buf));
        },
        ATOM_STRING => {
            if (a.value.ptr_value) |ptr| {
                const utf8 = string_to_utf8(ptr);
                return strdup(utf8);
            }
            return strdup("");
        },
        ATOM_LIST => return strdup("[List]"),
        ATOM_OBJECT => return strdup("[Object]"),
        else => return strdup(""),
    }
}

export fn list_join(list: ?*ListHeader, separator: ?*anyopaque) callconv(.c) ?*anyopaque {
    const l = list orelse return string_new_ascii("");
    if (l.length == 0) return string_new_ascii("");

    var sep_cstr: [*:0]const u8 = "";
    if (separator) |sep| {
        sep_cstr = string_to_utf8(sep);
    }
    var sep_len: usize = 0;
    {
        var p = sep_cstr;
        while (p[0] != 0) : (p += 1) sep_len += 1;
    }

    // First pass: calculate total length
    var total_len: usize = 0;
    {
        var curr = l.head;
        while (curr) |atom| {
            const val_str = atomValueToCstr(atom);
            if (val_str) |vs| {
                var vlen: usize = 0;
                var p = vs;
                while (p[0] != 0) : (p += 1) vlen += 1;
                total_len += vlen;
                c.free(vs);
            }
            if (atom.next != null) total_len += sep_len;
            curr = atom.next;
        }
    }

    // Allocate output buffer
    const result_buf = c.malloc(total_len + 1) orelse return string_new_ascii("");
    const result: [*]u8 = @ptrCast(result_buf);

    // Second pass: build joined string
    var out_pos: usize = 0;
    {
        var curr = l.head;
        while (curr) |atom| {
            const val_str = atomValueToCstr(atom);
            if (val_str) |vs| {
                var vlen: usize = 0;
                var p: [*]const u8 = vs;
                while (p[0] != 0) : (p += 1) vlen += 1;
                const src: [*]const u8 = vs;
                @memcpy(result[out_pos .. out_pos + vlen], src[0..vlen]);
                out_pos += vlen;
                c.free(vs);
            }
            if (atom.next != null and sep_len > 0) {
                const src: [*]const u8 = sep_cstr;
                @memcpy(result[out_pos .. out_pos + sep_len], src[0..sep_len]);
                out_pos += sep_len;
            }
            curr = atom.next;
        }
    }
    result[out_pos] = 0;

    const sd = string_new_utf8(@ptrCast(result));
    c.free(result_buf);
    return sd;
}

// =========================================================================
// SAMM Cleanup Path
// =========================================================================

export fn list_free_from_samm(header_ptr: ?*anyopaque) callconv(.c) void {
    const raw = header_ptr orelse return;
    const l: *ListHeader = @ptrCast(@alignCast(raw));

    l.head = null;
    l.tail = null;
    l.length = 0;
    samm_slab_pool_free(g_list_header_pool, raw);
}

export fn list_atom_free_from_samm(atom_ptr: ?*anyopaque) callconv(.c) void {
    const raw = atom_ptr orelse return;
    const atom: *ListAtom = @ptrCast(@alignCast(raw));

    atomReleasePayload(atom);
    samm_slab_pool_free(g_list_atom_pool, raw);
}

// =========================================================================
// Debug
// =========================================================================

export fn list_debug_print(list: ?*ListHeader) callconv(.c) void {
    const l = list orelse {
        _ = fprintf(__stderrp, "LIST: (null)\n");
        return;
    };

    _ = fprintf(__stderrp, "LIST: length=%lld flags=0x%04x {\n", l.length, l.flags);

    var index: i64 = 1;
    var curr = l.head;
    while (curr) |atom| {
        _ = fprintf(__stderrp, "  [%lld] ", index);
        switch (atom.type) {
            ATOM_INT => {
                _ = fprintf(__stderrp, "INT: %lld\n", atom.value.int_value);
            },
            ATOM_FLOAT => {
                _ = fprintf(__stderrp, "FLOAT: %g\n", atom.value.float_value);
            },
            ATOM_STRING => {
                if (atom.value.ptr_value) |ptr| {
                    const utf8 = string_to_utf8(ptr);
                    _ = fprintf(__stderrp, "STRING: \"%s\"\n", utf8);
                } else {
                    _ = fprintf(__stderrp, "STRING: (null descriptor)\n");
                }
            },
            ATOM_LIST => {
                if (atom.value.ptr_value) |ptr| {
                    const nested: *ListHeader = @ptrCast(@alignCast(ptr));
                    _ = fprintf(__stderrp, "LIST: [nested, length=%lld]\n", nested.length);
                } else {
                    _ = fprintf(__stderrp, "LIST: (null)\n");
                }
            },
            ATOM_OBJECT => {
                _ = fprintf(__stderrp, "OBJECT: %p\n", atom.value.ptr_value);
            },
            else => {
                _ = fprintf(__stderrp, "UNKNOWN(type=%d)\n", atom.type);
            },
        }
        curr = atom.next;
        index += 1;
    }
    _ = fprintf(__stderrp, "}\n");
}
