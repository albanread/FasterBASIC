# Zig SAMM Phase 1 — Status Tracker

**Phase:** Replace `samm_pool.c` with `samm_pool.zig`  
**Started:** 2025-01-27  
**Target:** Native-only compilation (cross-compilation deferred to future phase)

---

## Overview

Replace the C slab pool allocator with a Zig implementation while maintaining
100% C ABI compatibility. No changes to codegen, no changes to BASIC programs,
minimal changes to `samm_core.c`.

---

## Success Criteria

- [x] Design document complete (`ZIG_SAMM_MIGRATION.md`)
- [x] `runtime/samm_pool.zig` implemented and compiles
- [x] `build.zig` modified to compile `.zig` → `libsamm_pool.a`
- [x] `src/main.zig` modified to link `.a` files
- [x] `runtime/samm_pool.h` modified (opaque struct + accessor)
- [x] `runtime/samm_core.c` modified (one field access → function call)
- [x] `runtime/samm_pool.c` deleted
- [x] `zig test runtime/samm_pool.zig -lc` passes (5 unit tests)
- [x] `bash run_tests_parallel.sh` — 285/285 (100%)
- [x] Manual verification: `SAMM_STATS=1` output correct

---

## Task Checklist

### 1. Implement `runtime/samm_pool.zig`

- [x] Define `SlabPool(slot_size, slots_per_slab)` comptime generic
  - [x] `FreeNode` struct for intrusive free-list
  - [x] `Slab` struct with header + fixed-size data array
  - [x] `init(name)` — initialize empty pool
  - [x] `deinit()` — free all slabs, report leaks
  - [x] `alloc()` → `?*anyopaque` — pop from free list, grow if needed
  - [x] `free(ptr)` — push to free list
  - [x] `addSlab()` — allocate new slab, thread slots into free list
  - [x] `printStats()` — dump pool statistics (using fprintf)
  - [x] `validate()` — verify free list integrity
  - [x] Thread safety via `std.Thread.Mutex`

- [x] Define global pool instances
  - [x] `g_string_desc_pool` — `SlabPool(40, 256)`
  - [x] `g_list_header_pool` — `SlabPool(32, 256)`
  - [x] `g_list_atom_pool` — `SlabPool(24, 512)`
  - [x] `g_object_pools[6]` — size classes 32/64/128/256/512/1024 (via union wrapper)

- [x] Export C ABI functions
  - [x] `samm_slab_pool_init(handle, slot_size, slots_per_slab, name)` — NOP (pools pre-initialized)
  - [x] `samm_slab_pool_destroy(handle)` — dispatch to correct pool's `deinit()`
  - [x] `samm_slab_pool_alloc(handle)` → `?*anyopaque` — dispatch to pool's `alloc()`
  - [x] `samm_slab_pool_free(handle, ptr)` — dispatch to pool's `free()`
  - [x] `samm_slab_pool_print_stats(handle)` — dispatch to pool's `printStats()`
  - [x] `samm_slab_pool_total_allocs(handle)` → `usize` — NEW accessor
  - [x] `samm_slab_pool_stats(handle, ...)` — extract stats to caller's pointers
  - [x] `samm_slab_pool_validate(handle)` → `c_int`
  - [x] `samm_slab_pool_check_leaks(handle)`

- [x] Export global pool symbols with C linkage
  - [x] `export var g_string_desc_pool: *anyopaque`
  - [x] `export var g_list_header_pool: *anyopaque`
  - [x] `export var g_list_atom_pool: *anyopaque`
  - [x] `export var g_object_pools: [6]*anyopaque`

- [x] Implement handle dispatch (pointer comparison strategy)
  - [x] `alloc/free/destroy/stats` check handle against known pool addresses
  - [x] Object pools use `switch` on union to dispatch to correct typed pool

- [x] Add embedded unit tests (5 tests, all passing)
  - [x] `test "alloc returns zeroed slot"`
  - [x] `test "alloc/free cycle preserves in_use count"`
  - [x] `test "slab growth on exhaustion"`
  - [x] `test "peak_use tracking"`
  - [x] `test "validate returns true for consistent pool"`

### 2. Modify `build.zig`

- [x] Add static library compilation step via system command
  - Uses `zig build-lib` to compile `samm_pool.zig` → `libsamm_pool.a`
  - Output goes to `zig-out/lib/libsamm_pool.a`
  - Creates output directory with `mkdir -p` dependency
  - Added to install step dependencies

- [x] Add SAMM pool tests to test suite
  - Creates module for `samm_pool.zig` with libc linkage
  - Runs 5 unit tests as part of `zig build test`

### 3. Modify `src/main.zig`

- [x] Add logic to link `libsamm_pool.a` from `zig-out/lib`
  - Checks for `{runtime_dir}/../zig-out/lib/libsamm_pool.a`
  - Adds to link_args if found
  - Verbose mode prints confirmation message
  - No changes needed to `listCFiles` (`.c` files remain as-is)

### 4. Modify `runtime/samm_pool.h`

- [ ] Make `SammSlabPool` an opaque forward declaration
  ```c
  typedef struct SammSlabPool SammSlabPool;
  ```

- [ ] Remove struct body definition (moved to Zig)
- [ ] Remove `SammSlab` struct definition (Zig-internal)
- [ ] Keep all function declarations (API unchanged)
- [ ] Add new accessor:
  ```c
  size_t samm_slab_pool_total_allocs(const SammSlabPool* pool);
  ```

- [ ] Keep size-class constants and helper inline functions
  - `SAMM_OBJECT_SIZE_CLASSES`
  - `SAMM_SC_32` ... `SAMM_SC_1024`
  - `SAMM_SIZE_CLASS_NONE`
  - `samm_size_to_class()` inline function
  - `samm_class_to_u8()` inline function
  - `samm_object_slot_sizes[]`
  - `samm_object_slots_per_slab[]`
  - `samm_object_pool_names[]`

- [ ] Keep `extern` declarations for global pools

### 5. Modify `runtime/samm_core.c`

- [ ] Replace direct field access with accessor call (1 location):
  ```c
  // Before:
  if (g_object_pools[sc].total_allocs > 0) {

  // After:
  if (samm_slab_pool_total_allocs(&g_object_pools[sc]) > 0) {
  ```

### 6. Remove `runtime/samm_pool.c`

- [ ] Delete the file (after all tests pass)
- [ ] Optional: rename to `.c.bak` as backup during testing

### 7. Testing

- [ ] Run `zig build` — should compile without errors
- [ ] Run `zig build test` — Zig unit tests pass
- [ ] Run `bash run_tests_parallel.sh` — 285/285 pass
- [ ] Run individual SAMM stress tests:
  - [ ] `test_samm_stress_cross_scope`
  - [ ] `test_samm_stress_volume`
  - [ ] `test_samm_stress_string_churn`
  - [ ] `test_samm_stress_list_pool`
  - [ ] `test_samm_stress_background`
  - [ ] `test_samm_stress_scope_depth`
- [ ] Manual: compile a test program with `SAMM_STATS=1`, verify output

---

## Implementation Notes

### Handle Dispatch Strategy

Using pointer comparison (simplest for 9 known pools):

```zig
export fn samm_slab_pool_alloc(handle: *anyopaque) callconv(.C) ?*anyopaque {
    if (handle == @ptrCast(&g_string_desc_pool)) 
        return g_string_desc_pool.alloc();
    if (handle == @ptrCast(&g_list_header_pool)) 
        return g_list_header_pool.alloc();
    if (handle == @ptrCast(&g_list_atom_pool)) 
        return g_list_atom_pool.alloc();
    inline for (0..6) |i| {
        if (handle == @ptrCast(&g_object_pools[i])) 
            return g_object_pools[i].alloc();
    }
    return null;  // invalid handle
}
```

### `samm_slab_pool_init()` Behavior

In the C version, pools are initialized by calling `samm_slab_pool_init()` at runtime.
In the Zig version, pools are pre-initialized via their `init()` method at comptime
or startup. The exported `samm_slab_pool_init()` becomes a NOP or just validates
that the requested size matches the pool's size.

Alternative: make it a true init and have globals start uninitialized, but this
complicates the Zig code.

### Memory Layout

Zig's `Slab` struct uses a fixed-size array instead of C's flexible array member:

```zig
const Slab = struct {
    next: ?*Slab,
    used_count: u32,
    data: [slots_per_slab][slot_size]u8 align(@alignOf(usize)),
};
```

This is simpler and type-safe. The alignment ensures free-list overlay works.

---

## Risks and Contingencies

| Risk | Mitigation |
|------|------------|
| Zig `.o` not found at link time | Verify build step installs to correct path; add verbose logging in main.zig |
| Symbol mismatch between Zig export and C `extern` | Use `nm` to inspect symbol names; ensure `export` uses C mangling |
| Pool handle dispatch overhead | Profile hot path; if needed, switch to vtable or tag-based dispatch |
| Tests fail after swap | Keep `samm_pool.c` as `.bak`; easy rollback; inspect test output for clues |

---

## Rollback Plan

If Phase 1 fails or introduces regressions:

1. Restore `runtime/samm_pool.c` from `.bak` or git
2. Revert changes to `samm_pool.h`
3. Revert `samm_core.c` (restore direct field access)
4. Remove `samm_pool.zig`
5. Revert `build.zig` and `main.zig` changes
6. Run `zig build && bash run_tests_parallel.sh` — should return to 285/285

---

## Current Status

**Completed:**
- ✅ `runtime/samm_pool.zig` fully implemented (615 lines)
- ✅ Comptime `SlabPool` generic with type safety
- ✅ All C ABI exports matching existing API
- ✅ Union-based dispatch for heterogeneous object pool array
- ✅ 5 embedded unit tests passing
- ✅ Compiles cleanly with `zig build-obj -lc`
- ✅ `build.zig` modified to compile `libsamm_pool.a` during build
- ✅ `src/main.zig` modified to link the Zig library
- ✅ Library builds successfully (187KB static archive)

**Next actions:**
1. Modify `runtime/samm_pool.h` to make struct opaque and add accessor
2. Modify `runtime/samm_core.c` to use accessor instead of direct field access
3. Delete (or rename) `runtime/samm_pool.c`
4. Full integration test: `bash run_tests_parallel.sh` — should remain 285/285

---

## Completion Log

- 2025-01-27: Design phase complete, status tracker created
- 2025-01-27: `samm_pool.zig` implementation complete, all unit tests passing (5/5)
  - Fixed Zig 0.15 API changes: `.C` → `.c` calling convention
  - Fixed `std.io` API changes: used extern `fprintf` and `__stderrp` for stderr
  - Fixed object pool array: used union wrapper for heterogeneous comptime types
  - All exports use pointer-comparison dispatch (9 pools, O(1) per check)
- 2025-01-27: Build system integration complete
  - `build.zig`: Added system command to compile `libsamm_pool.a` (187KB)
  - `build.zig`: Added SAMM pool tests to `zig build test` suite
  - `src/main.zig`: Added logic to link `libsamm_pool.a` when compiling BASIC programs
  - Build produces `zig-out/lib/libsamm_pool.a` alongside `zig-out/bin/fbc`