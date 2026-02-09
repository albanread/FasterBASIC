# SAMM Phase 2: Zig Scope Tracking — Design Document

**Status:** Draft / Implementation Guide  
**Date:** 2026-02-09  
**Goal:** Replace C `realloc`-based scope arrays with Zig `ArenaAllocator`-backed structures.

---

## 1. Problem Statement

The current C implementation of `SAMMScope` uses `realloc` to manage dynamic arrays of pointers, types, and size classes.

```c
typedef struct {
    void**        ptrs;
    SAMMAllocType* types;
    uint8_t*      size_classes;
    size_t        count;
    size_t        capacity;
} SAMMScope;
```

**Issues:**
1. **Manual memory management:** `scope_ensure_capacity` handles resizing manually.
2. **Fragmentation:** Each scope frame creates 3 separate allocation headers.
3. **Synchronization:** Array resizing requires holding the strict `scope_mutex`.
4. **Cleanup complexity:** Handing off ownership to the background thread involves passing 3 raw pointers.

## 2. Proposed Zig Architecture

We will implement `runtime/samm_scope.zig`, which exports a clean C ABI for scope management.

### 2.1 The Zig Scope Structure

Instead of 3 parallel arrays, we can use a struct of arrays (SoA) layout managed by an `ArenaAllocator`. However, given the requirement to pass these arrays to the background worker (which is still in C for now, or will be in Zig later), keeping them compatible with C is key.

Actually, to pass data to the background worker, C currently copies the pointers:
```c
ptrs_to_clean  = s->ptrs;
types_to_clean = s->types;
/* ... */
enqueue_for_cleanup(ptrs_to_clean, ...);
```

For Phase 2, we want to replace the *storage* mechanism.

**Approach:** Use an `std.heap.ArenaAllocator` for each scope.

**Zig Scope State:**
```zig
const ScopeFrame = struct {
    arena: std.heap.ArenaAllocator,
    // We can use ArrayLists backed by the arena
    // But since we need to hand off to C, we might stick to raw slices 
    // or ArrayListUnmanaged.
    ptrs: std.ArrayListUnmanaged(*anyopaque),
    types: std.ArrayListUnmanaged(AllocType),
    size_classes: std.ArrayListUnmanaged(u8),
};
```

**Wait:** The C background worker expects `free()`-able pointers eventually. If we use an Arena, we can't `free()` individual arrays unless the Arena *is* the allocator for those arrays and we destroy the whole Arena.

In `samm_exit_scope`, the arrays are **detached** from the scope and given to the cleanup queue. The cleanup queue (consumer) eventually calls `free(ptrs); free(types); free(sc);`.

**Constraint:** The *arrays* themselves must be heap-allocated blocks compatible with how the cleanup queue destroys them. Currently `enqueue_for_cleanup` expects to own these pointers. The consumer (worker) finishes by doing:
```c
free(batch->ptrs);
free(batch->types);
free(batch->size_classes);
```

So we CANNOT use an `ArenaAllocator` for the arrays if we hand them off to C code that calls `free()`. We must use the general purpose allocator (C allocator or Zig GPA) for the arrays.

**Revised Decision:** We will use `std.ArrayListUnmanaged` with the `std.heap.c_allocator` to maintain exact C compatibility for the handover.

### 2.2 Zig Modules

#### `runtime/samm_scope.zig`

```zig
const std = @import("std");
const c_allocator = std.heap.c_allocator;

// Mirror C enums
pub const AllocType = enum(u8) {
    String = 0,
    Object = 1,
    // ...
};

const Scope = struct {
    ptrs: std.ArrayListUnmanaged(?*anyopaque) = .{},
    types: std.ArrayListUnmanaged(AllocType) = .{},
    size_classes: std.ArrayListUnmanaged(u8) = .{},

    fn deinit(self: *Scope) void {
        self.ptrs.deinit(c_allocator);
        self.types.deinit(c_allocator);
        self.size_classes.deinit(c_allocator);
    }
};

// Global state managed by Zig
var scopes: [SAMM_MAX_SCOPE_DEPTH]Scope = undefined;
// We still rely on samm_core.c to manage depth/indexing for now?
// Or we export the whole scope manager?
```

The C code still has `g_samm.scopes[]`. We need to replace *that*.

**Plan:** `samm_core.c` will no longer define `SAMMScope` or `scopes[]`. Instead, it will hold an opaque handle or calls Zig functions for *everything* related to scope storage.

**C Changes:**

```c
// samm_core.c

// REMOVE: SAMMScope struct definition
// REMOVE: g_samm.scopes array

// ADD:
void samm_scope_init_system(void); // Zig
void samm_scope_push(void);        // Zig
// Return the arrays for cleanup
void samm_scope_pop(void*** ptrs, SAMMAllocType** types, uint8_t** sc, size_t* count);
void samm_scope_track(void* ptr, SAMMAllocType type, uint8_t sc);
```

Wait, `samm_core.c` manages `scope_depth`. It needs to know the index.

**Integration Strategy:**
1.  **Storage in Zig:** `samm_scope.zig` allocates a fixed array of `Scope` structs (matches `SAMM_MAX_SCOPE_DEPTH`).
2.  **Tracking:** `samm_track_object` in C calls `samm_scope_add(depth, ptr, type, sc)` implemented in Zig.
3.  **Entering/Exiting:** `samm_enter_scope` calls `samm_scope_reset(depth)`. `samm_exit_scope` calls `samm_scope_detach(depth, &out_ptrs, ...)` to get the arrays for the cleanup queue.

### 2.3 API Definition

**Exports from `samm_scope.zig`:**

```zig
export fn samm_scope_ensure_init() void
export fn samm_scope_reset(depth: c_int) void
export fn samm_scope_add(depth: c_int, ptr: ?*anyopaque, type: u8, sc: u8) void
// Returns true if scope had items, populates out pointers.
// Arrays returned are malloc-compatible (allocated with c_allocator).
export fn samm_scope_detach(depth: c_int, 
                           out_ptrs: *[*]?*anyopaque, 
                           out_types: *[*]u8, 
                           out_sc: *[*]u8, 
                           out_count: *usize) bool
```

**Imports needed by Zig:**
None. It relies on `libc` for the allocator.

## 3. Implementation Steps

1.  **Define `samm_scope.zig`**:
    *   Use `std.ArrayListUnmanaged`.
    *   Use `std.heap.c_allocator` (critical for `free()` compatibility).
    *   Implement the exports.
    *   Add tests ensuring `scope_add` grows the lists.

2.  **Modify `samm_core.c`**:
    *   Delete local `SAMMScope` struct.
    *   Delete `scope_init`, `scope_ensure_capacity`, `scope_destroy`.
    *   Update `samm_track_object`: `samm_scope_add(g_samm.scope_depth, ...)`
    *   Update `samm_enter_scope`: `samm_scope_reset(new_depth)`
    *   Update `samm_exit_scope`: use `samm_scope_detach` to get arrays.

3.  **Synchronization**:
    *   Zig code does **not** handle locking in Phase 2. `samm_core.c` still holds `scope_mutex` when calling these functions. The Zig functions are "unsafe" primitives wrapped by C locking.

## 4. Risks & Mitigations

*   **Allocator mismatch:** Critical that Zig uses the same allocator that C `free()` expects. `std.heap.c_allocator` wraps `malloc`/`realloc`/`free` from libc, so this is safe.
*   **Performance:** `ArrayList.append` checks capacity. This is similar to the C version. Optimizations (unchecked append) can be added if needed, but the safety is preferred first.

## 5. Future (Phase 3)

In Phase 3, the entire background worker moves to Zig. Then we can switch to `ArenaAllocator` for scopes because Zig will handle the cleanup and won't need to call C `free()`.
