# Zig SAMM Migration — Design Document

> Migrating the SAMM slab pool allocator and core runtime from C to Zig
> for type safety, comptime specialization, and memory safety.

**Status:** Proposed
**Date:** 2025-01-27
**Depends on:** SAMM_POOL_DESIGN.md (all phases complete in C)

---

## 1. Current State Summary

### 1.1 Test Suite — Milestone Achieved

All 285 end-to-end tests pass (100%) on the Zig compiler. The fixes applied across
the previous sessions were:

| Fix | Root Cause | Effect |
|-----|-----------|--------|
| List subscript type inference | `inferExprType(.array_access)` didn't check LIST variables | Correct print/emit path for list element types |
| Array reduction return types | `SUM`/`MAX`/`MIN`/`AVG`/`DOT` defaulted to double | No more `dtosi` on integer temps |
| Scalar `MAX`/`MIN` inlining | 2-arg overloads generated unresolved externals | Inline compare+select, no linker errors |
| Class-instance parameter resolution | `inferClassName` prioritized globals over locals | Correct vtable dispatch for method calls on parameters |
| Method return SAMM retain | Returned objects freed by `samm_exit_scope` before caller received them | `samm_retain(ret, 1)` before scope exit preserves returned objects |

### 1.2 Current Runtime Architecture

The runtime is written in C and lives in `zig_compiler/runtime/`. It is compiled
at link time — `fbc` invokes `cc` and passes all `.c` files from the runtime
directory alongside the QBE-generated assembly.

```
fbc input.bas -o program
  │
  ├─ Lex → Parse → Semantic → Codegen → QBE IL
  ├─ QBE (embedded) → assembly (.s)
  └─ cc -O1 -o program output.s runtime/*.c -lm
```

Alternative: if `runtime/libfbruntime.a` exists, it is linked instead of
compiling `.c` files individually.

### 1.3 SAMM Runtime Files

| File | Lines | Role |
|------|-------|------|
| `samm_pool.h` | ~270 | Struct definitions, API declarations, size-class constants |
| `samm_pool.c` | ~450 | Slab allocator implementation (alloc/free/stats/validate) |
| `samm_core.c` | ~1350 | Scope manager, retain, bloom filter, background worker |
| `samm_bridge.h` | ~420 | Public C API declarations, constants, SAMMStats struct |

### 1.4 How samm_core.c Uses the Pool

`samm_core.c` interacts with the pool through:

**Function calls only (clean interface):**
- `samm_slab_pool_init(&pool, slot_size, slots_per_slab, name)`
- `samm_slab_pool_destroy(&pool)`
- `samm_slab_pool_alloc(&pool)` → `void*`
- `samm_slab_pool_free(&pool, ptr)`
- `samm_slab_pool_print_stats(&pool)`

**Direct struct field access (1 location):**
- `g_object_pools[sc].total_allocs > 0` — stats check in shutdown

**Global pool instances (defined in samm_pool.c, extern in samm_pool.h):**
- `g_string_desc_pool` — 40-byte slots, 256/slab
- `g_list_header_pool` — 32-byte slots, 256/slab
- `g_list_atom_pool` — 24-byte slots, 512/slab
- `g_object_pools[6]` — size classes 32–1024 bytes

---

## 2. Motivation for Zig Migration

### 2.1 What the C Pool Does Well

The C slab pool is well-designed: O(1) alloc/free via intrusive free-list,
slab-based growth, per-pool mutex, rich diagnostics. It works correctly and
has been battle-tested across all 285 tests.

### 2.2 What Zig Improves

| Concern | C (current) | Zig (proposed) |
|---------|-------------|----------------|
| **Type safety** | `void*` everywhere; wrong-pool-free is a runtime bug | Comptime-typed pools; type system prevents cross-pool errors |
| **Alignment** | Manual; `slot_size >= sizeof(void*)` asserted at runtime | `@alignOf(T)` computed at comptime; guaranteed correct |
| **Free-list link** | `memcpy` overlay on first 8 bytes | `@ptrCast` with alignment; no memcpy needed |
| **Zeroing** | `memset(slot, 0, slot_size)` | `@memset(slot, 0)` with known size at comptime |
| **Buffer overrun** | Silent corruption | Safety-checked pointer arithmetic |
| **Thread safety** | Manual `pthread_mutex` | `std.Thread.Mutex` (same perf, less boilerplate) |
| **Diagnostics** | `fprintf(stderr, ...)` | `std.log` with scoped levels; comptime format checking |
| **Testing** | No unit tests for the pool | Zig's built-in `test` blocks adjacent to implementation |
| **Generics** | Runtime-parameterized (`slot_size` arg) | Comptime-parameterized (`SlabPool(40, 256)`) — zero-cost |
| **Double-free** | Bloom filter (probabilistic) for overflow | Same, plus deterministic pool-level detection in debug builds |

### 2.3 Build Integration Advantage

The Zig compiler (`fbc`) is already built with `zig build`. Zig can compile
Zig source to `.o` files with C ABI exports. These `.o` files integrate into
the existing link step with zero changes to the compiled BASIC program's
perspective.

---

## 3. Architecture

### 3.1 Design Principles

1. **C ABI surface unchanged.** Compiled BASIC programs and `samm_core.c` see
   the same function names and calling conventions. No changes to codegen.zig.

2. **Opaque pool handles.** `samm_core.c` no longer sees pool struct internals.
   The single direct field access (`total_allocs`) gets a new accessor function.

3. **Comptime specialization.** Each pool type is generated at compile time with
   exact slot size and alignment. No runtime branching on slot_size.

4. **Incremental migration.** Pool first, core later. Each phase is independently
   testable and reversible.

5. **Global instances stay global.** The pool instances remain global symbols
   with C linkage, just defined in Zig instead of C.

### 3.2 Module Structure

```
zig_compiler/
├── runtime/
│   ├── samm_pool.zig          # NEW: Zig slab pool implementation
│   ├── samm_pool.h            # MODIFIED: opaque struct, accessor added
│   ├── samm_pool.c            # REMOVED (replaced by .zig)
│   ├── samm_core.c            # MODIFIED: one field access → function call
│   ├── samm_bridge.h          # UNCHANGED
│   └── ...other runtime .c...
├── build.zig                  # MODIFIED: compile samm_pool.zig → .o
└── src/
    └── main.zig               # MODIFIED: link .o files from runtime dir
```

### 3.3 Build Flow

```
zig build
  │
  ├─ Compile src/*.zig → fbc executable (as today)
  └─ Compile runtime/samm_pool.zig → runtime/samm_pool.o (NEW)
       ├─ target: native (or cross-compile target)
       ├─ exports: extern "C" functions
       └─ installed alongside fbc

fbc input.bas -o program
  │
  └─ cc -O1 -o program output.s runtime/*.c runtime/samm_pool.o -lm
                                              ^^^^^^^^^^^^^^^^^^^
                                              Zig-compiled object
```

`main.zig`'s `listCFiles` becomes `listRuntimeFiles` and picks up both
`.c` and `.o` files from the runtime directory.

---

## 4. Zig Slab Pool Design

### 4.1 Core Type: `SlabPool`

```zig
/// Comptime-parameterized slab pool allocator.
/// Each instantiation generates specialized code for one slot size.
pub fn SlabPool(comptime slot_size: u32, comptime slots_per_slab: u32) type {
    return struct {
        const Self = @This();

        // Compile-time constants (no runtime branching)
        pub const SLOT_SIZE = slot_size;
        pub const SLOTS_PER_SLAB = slots_per_slab;

        const Slot = [slot_size]u8;
        const SlotPtr = *align(@alignOf(usize)) Slot;

        // Free-list node overlay (first 8 bytes of each free slot)
        const FreeNode = struct {
            next: ?*FreeNode,
        };

        // Slab: header + contiguous array of slots
        const Slab = struct {
            next: ?*Slab,
            used_count: u32,
            data: [slots_per_slab]Slot align(@alignOf(usize)),
        };

        // Pool state
        free_list: ?*FreeNode = null,
        slabs: ?*Slab = null,
        total_slabs: usize = 0,
        total_capacity: usize = 0,
        in_use: usize = 0,
        peak_use: usize = 0,
        total_allocs: usize = 0,
        total_frees: usize = 0,
        name: [*:0]const u8 = "pool",
        mutex: std.Thread.Mutex = .{},

        pub fn init(name: [*:0]const u8) Self { ... }
        pub fn deinit(self: *Self) void { ... }
        pub fn alloc(self: *Self) ?*anyopaque { ... }
        pub fn free(self: *Self, ptr: *anyopaque) void { ... }
        pub fn printStats(self: *const Self) void { ... }
        pub fn validate(self: *const Self) bool { ... }
    };
}
```

**Key differences from C version:**
- `slot_size` and `slots_per_slab` are comptime — no runtime fields needed
- `Slab.data` uses a fixed-size array (not flexible array member hack)
- `FreeNode` overlay is a typed struct, not `memcpy`-based
- `mutex` is `std.Thread.Mutex` (platform-appropriate, no pthread import)
- Alignment is automatic via `@alignOf(usize)`

### 4.2 C ABI Exports

The Zig file exports thin wrappers that match the existing C function signatures:

```zig
// --- Opaque handle type for C ---
const PoolHandle = *anyopaque;

// --- Global pool instances ---
var string_desc_pool = SlabPool(40, 256).init("StringDesc");
var list_header_pool = SlabPool(32, 256).init("ListHeader");
var list_atom_pool   = SlabPool(24, 512).init("ListAtom");
var object_pools = .{
    SlabPool(32, 128).init("Object_32"),
    SlabPool(64, 128).init("Object_64"),
    SlabPool(128, 128).init("Object_128"),
    SlabPool(256, 128).init("Object_256"),
    SlabPool(512, 64).init("Object_512"),
    SlabPool(1024, 32).init("Object_1024"),
};

// --- Exported C functions ---
export fn samm_slab_pool_alloc(handle: PoolHandle) callconv(.C) ?*anyopaque { ... }
export fn samm_slab_pool_free(handle: PoolHandle, ptr: ?*anyopaque) callconv(.C) void { ... }
export fn samm_slab_pool_init(...) callconv(.C) void { ... }
export fn samm_slab_pool_destroy(handle: PoolHandle) callconv(.C) void { ... }
export fn samm_slab_pool_print_stats(handle: PoolHandle) callconv(.C) void { ... }
export fn samm_slab_pool_total_allocs(handle: PoolHandle) callconv(.C) usize { ... }  // NEW accessor
```

### 4.3 Handle Dispatch

Since C code passes `SammSlabPool*` pointers, the Zig exports need to dispatch
to the correct typed pool. Two approaches:

**Option A: Tag-based dispatch (recommended for Phase 1)**

Each pool instance stores a `pool_id` tag. The export functions switch on it:

```zig
const PoolId = enum(u8) {
    string_desc, list_header, list_atom,
    obj_32, obj_64, obj_128, obj_256, obj_512, obj_1024,
};
```

**Option B: Vtable-based dispatch**

Each pool instance stores a pointer to a vtable of `fn alloc`, `fn free`, etc.
The comptime-generated pool type populates the vtable at init. Export functions
call through the vtable. More flexible, slightly more indirection.

**Option C: Direct pointer comparison (simplest)**

There are only 9 pool instances. The export functions compare the handle pointer
against the known global addresses:

```zig
export fn samm_slab_pool_alloc(handle: *anyopaque) callconv(.C) ?*anyopaque {
    if (handle == @ptrCast(&string_desc_pool)) return string_desc_pool.alloc();
    if (handle == @ptrCast(&list_header_pool)) return list_header_pool.alloc();
    // ...
}
```

This is simple but O(N) in pool count. With 9 pools it's negligible.

### 4.4 Modified samm_pool.h

```c
/* Opaque pool handle — internal layout managed by Zig */
typedef struct SammSlabPool SammSlabPool;

/* API unchanged */
void  samm_slab_pool_init(SammSlabPool* pool, uint32_t slot_size,
                          uint32_t slots_per_slab, const char* name);
void  samm_slab_pool_destroy(SammSlabPool* pool);
void* samm_slab_pool_alloc(SammSlabPool* pool);
void  samm_slab_pool_free(SammSlabPool* pool, void* ptr);
void  samm_slab_pool_print_stats(const SammSlabPool* pool);

/* NEW: accessor for total_allocs (replaces direct field access) */
size_t samm_slab_pool_total_allocs(const SammSlabPool* pool);

/* Global instances — defined in Zig, declared here */
extern SammSlabPool g_string_desc_pool;
extern SammSlabPool g_list_header_pool;
extern SammSlabPool g_list_atom_pool;
extern SammSlabPool g_object_pools[6];
```

### 4.5 samm_core.c Change (Minimal)

Only one line changes — the direct struct field access in `samm_shutdown()`:

```c
// Before:
if (g_object_pools[sc].total_allocs > 0) {

// After:
if (samm_slab_pool_total_allocs(&g_object_pools[sc]) > 0) {
```

---

## 5. Embedded Unit Tests

One of the strongest arguments for Zig: tests live next to the code.

```zig
test "alloc returns zeroed slot" {
    var pool = SlabPool(64, 16).init("test");
    defer pool.deinit();

    const ptr: [*]u8 = @ptrCast(pool.alloc() orelse unreachable);
    for (0..64) |i| {
        try std.testing.expectEqual(@as(u8, 0), ptr[i]);
    }
}

test "alloc/free cycle preserves count" {
    var pool = SlabPool(32, 8).init("test");
    defer pool.deinit();

    var ptrs: [8]?*anyopaque = undefined;
    for (&ptrs) |*p| p.* = pool.alloc();

    try std.testing.expectEqual(@as(usize, 8), pool.in_use);

    for (&ptrs) |p| pool.free(p.?);

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

test "thread safety under contention" {
    var pool = SlabPool(64, 256).init("test");
    defer pool.deinit();

    const threads = try std.Thread.spawn(.{}, allocFreeWorker, .{&pool});
    // ... spawn multiple threads, join, verify counts
}
```

These run via `zig build test` alongside the existing compiler unit tests.

---

## 6. Migration Plan

### Phase 1: Zig Slab Pool (this phase)

**Scope:** Replace `samm_pool.c` with `samm_pool.zig`. All C consumers unchanged
except one accessor call.

**Steps:**

1. **Write `runtime/samm_pool.zig`**
   - Implement `SlabPool` comptime generic
   - Define global pool instances with `export` linkage
   - Export all `samm_slab_pool_*` functions with `callconv(.C)`
   - Add `samm_slab_pool_total_allocs` accessor
   - Add embedded unit tests

2. **Modify `build.zig`**
   - Add a build step to compile `runtime/samm_pool.zig` → `runtime/samm_pool.o`
   - Use `b.addObject()` with `.root_source_file` pointing to the Zig source
   - Set target and optimize to match the main build
   - Install the `.o` file to the runtime output directory

3. **Modify `src/main.zig`**
   - Rename `listCFiles` → `listRuntimeFiles`
   - Also collect `.o` files from the runtime directory
   - Pass them to the `cc` link command

4. **Modify `runtime/samm_pool.h`**
   - Make `SammSlabPool` an opaque forward declaration
   - Add `samm_slab_pool_total_allocs()` declaration
   - Keep all existing function declarations
   - Remove struct body, `SammSlab` definition, inline functions
   - Move size-class constants to a new `samm_constants.h` (shared by both
     Zig and C) or keep them in `samm_pool.h` as `#define` constants that
     don't depend on the struct layout

5. **Modify `runtime/samm_core.c`**
   - Replace `g_object_pools[sc].total_allocs > 0` with
     `samm_slab_pool_total_allocs(&g_object_pools[sc]) > 0`
   - No other changes needed

6. **Remove `runtime/samm_pool.c`**

7. **Test**
   - `zig build test` — runs Zig unit tests for the pool
   - `bash run_tests_parallel.sh` — full 285-test e2e suite must stay 100%
   - Manual: `SAMM_STATS=1 ./program` — verify pool stats still print correctly

**Risk:** Low. The C ABI surface is identical. The pool is a pure allocator with
no complex interactions beyond alloc/free.

**Rollback:** Restore `samm_pool.c`, revert `.h` changes, remove `.zig` file.

### Phase 2: Zig Scope Tracking (future)

Replace the scope tracking arrays (`ptrs[]`, `types[]`, `size_classes[]`) in
`samm_core.c` with Zig `ArrayList` or arena-backed arrays.

- Eliminates manual `realloc` / `capacity` management in `scope_ensure_capacity`
- Scope arrays are bulk-allocated, never individually freed, discarded on exit
  — ideal for `ArenaAllocator`
- Each scope gets a Zig arena; `samm_exit_scope` just destroys the arena

**Prerequisite:** Phase 1 complete and stable.

### Phase 3: Zig Core (future)

Rewrite `samm_core.c` entirely in Zig:

- Scope stack management
- Retain/untrack with proper error handling
- Bloom filter → `std.StaticBitSet` or custom
- Background worker → `std.Thread` with proper Zig concurrency
- Full SAMMState in Zig with atomic stats via `std.atomic.Value`

**Prerequisite:** Phase 2 complete. This is the largest change and should be
done when the team is confident in the Zig runtime integration pattern.

### Phase 4: Arena Per Scope (future, optional)

Investigate `std.heap.ArenaAllocator` for scope-local temporaries:

- Scope tracking metadata (not the user objects themselves)
- String temporaries within expression evaluation
- Only beneficial if profiling shows `realloc` churn in scope arrays

---

## 7. Risks and Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Struct layout mismatch between Zig globals and C `extern` declarations | Medium | Link error or corruption | Make struct opaque from C; only access through functions |
| Zig `.o` not found at link time | Low | Unresolved symbols | Build step installs `.o` to same dir as runtime `.c` files |
| Cross-compilation target mismatch | Low | Wrong ABI | Use same `target` option for pool `.o` as for the main build |
| Thread safety regression | Low | Race condition | Zig `std.Thread.Mutex` is equivalent to `pthread_mutex`; unit test under contention |
| Performance regression | Very Low | Slower alloc/free | Zig comptime specialization should be equal or faster; benchmark if concerned |

---

## 8. Success Criteria

- [ ] `zig build` compiles `samm_pool.zig` → `samm_pool.o` without errors
- [ ] `zig build test` passes all pool unit tests (including thread safety)
- [ ] `bash run_tests_parallel.sh` — 285/285 (100%) pass rate maintained
- [ ] `SAMM_STATS=1` output matches current format and values
- [ ] `samm_pool.c` removed from the runtime directory
- [ ] No `void*` casts in the pool implementation (internal Zig code)
- [ ] Comptime slot sizes — no runtime branching on slot_size in hot paths
- [ ] Pool validation (`samm_slab_pool_validate`) passes in debug builds

---

## 9. Appendix: Zig vs C Side-by-Side

### Alloc hot path

**C (current):**
```c
void* samm_slab_pool_alloc(SammSlabPool* pool) {
    pthread_mutex_lock(&pool->lock);
    if (!pool->free_list) {
        if (!pool_add_slab(pool)) { /* fallback */ }
    }
    void* slot = pool->free_list;
    pool->free_list = freelist_next(slot);  // memcpy-based
    pool->in_use++;
    pool->total_allocs++;
    if (pool->in_use > pool->peak_use) pool->peak_use = pool->in_use;
    pthread_mutex_unlock(&pool->lock);
    memset(slot, 0, pool->slot_size);       // runtime slot_size
    return slot;
}
```

**Zig (proposed):**
```zig
pub fn alloc(self: *Self) ?*anyopaque {
    self.mutex.lock();
    defer self.mutex.unlock();

    if (self.free_list == null) {
        self.addSlab() catch return null;
    }

    const node = self.free_list.?;
    self.free_list = node.next;
    self.in_use += 1;
    self.total_allocs += 1;
    self.peak_use = @max(self.peak_use, self.in_use);

    const ptr: *Slot = @ptrCast(node);      // typed, aligned
    @memset(ptr, 0);                         // comptime-known size
    return ptr;
}
```

Differences: no manual lock/unlock (defer), typed pointer cast instead of
memcpy for free-list traversal, comptime-known `@memset` size, `@max` builtin
instead of branch.

---

## 10. Open Questions

1. **Should we precompile `samm_pool.o` for multiple targets?**
   Currently fbc only targets the host. If cross-compilation becomes a goal,
   the build step needs to produce `.o` files for each target triple.

2. **Should the Zig pool support a `GeneralPurposeAllocator` debug mode?**
   In debug builds, we could back the pool with Zig's GPA to get full
   use-after-free and leak detection with stack traces — much richer than
   the current Bloom filter.

3. **Should `samm_core.c` migrate in the same phase or separately?**
   Keeping it in C for Phase 1 minimizes risk. But migrating it together
   would eliminate the opaque-handle dispatch overhead entirely — the Zig
   core would call Zig pool methods directly with full type information.

4. **Pre-built `libfbruntime.a` workflow:**
   Currently the user can pre-build a static archive. With mixed C+Zig
   sources, the build script for the archive needs to also compile
   `samm_pool.zig`. Should we provide a `build_runtime.sh` or fold it
   into `zig build`?
```

Now let me verify the file was created properly: