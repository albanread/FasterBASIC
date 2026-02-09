# Zig SAMM Phase 2 — Status Tracker

**Phase:** Replace scope tracking arrays in `samm_core.c` with Zig implementation
**Started:** 2026-02-09  
**Target:** Hybrid C/Zig implementation for scope management

---

## Overview

Migrate the internal scope tracking mechanism (dynamic arrays of pointers) from
C manual memory management (`realloc`) to Zig data structures (`ArrayList` or `ArenaAllocator`).
This prepares for the eventual full rewrite of `samm_core.c` in Phase 3.

---

## Success Criteria

- [x] `runtime/samm_scope.zig` implemented
- [x] `samm_core.c` modified to delegate scope array management to Zig
- [x] No regression in performance (scope entry/exit is hot path)
- [x] All tests pass (285/285)

---

## Task Checklist

### 1. Design & Prototype

- [x] Create detailed design document `design/SAMM_PHASE2_DESIGN.md`
- [x] Decide on `ArrayList` vs `ArenaAllocator` strategy for scope frames
- [x] Define C ABI for scope operations (`scope_init`, `scope_push`, `scope_pop`)

### 2. Implementation

- [x] Implement `runtime/samm_scope.zig`
- [x] Expose C ABI functions for scope management
- [x] Modify `build.zig` to compile/link the new module

### 3. Integration

- [x] Update `samm_core.c` to use the new Zig scope functions
- [x] Remove manual realloc logic from C code

### 4. Verification

- [x] `zig test runtime/samm_scope.zig`
- [x] Full regression test suite
