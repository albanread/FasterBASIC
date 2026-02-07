# SAMM Phase 1 Implementation Status

## Scope-Aware Memory Management for FasterBASIC — Phase 1 Completion Report

**Date:** June 2025
**Status:** Phase 1 Core Integration Complete ✅
**Test Results:** 8/8 CLASS tests passing, 8/8 SAMM integration tests passing

---

## Overview

SAMM (Scope-Aware Memory Management) has been integrated into the FasterBASIC CLASS
runtime and QBE code generation pipeline. Phase 1 provides automatic scope-based
lifetime management for CLASS instances, Bloom-filter double-free detection, and a
background cleanup worker thread.

---

## What Was Implemented

### 1. Pure-C SAMM Runtime Core

| File | Location | Description |
|------|----------|-------------|
| `samm_bridge.h` | `fsh/FasterBASICT/runtime_c/` | C-linkage API header (also copied to `qbe_basic_integrated/runtime/`) |
| `samm_core.c` | `fsh/FasterBASICT/runtime_c/` | Full SAMM implementation in pure C (also copied to `qbe_basic_integrated/runtime/`) |

**Capabilities:**
- Scope stack (up to 256 nesting levels) with per-scope tracking vectors
- Bloom filter double-free detection (96M bits = 12 MB, 10 FNV-1a hashes)
- Background cleanup worker thread (pthread-based) with batched processing
- Typed allocation tracking (OBJECT, STRING, ARRAY, LIST, GENERIC)
- RETAIN for explicit ownership transfer across scopes
- Runtime statistics and optional trace logging
- Zero overhead when disabled (all calls become no-ops)
- List support stubs preserved for Phase 4

### 2. CLASS Runtime Integration (`class_runtime.c`)

- `class_object_new()` routes through `samm_alloc_object()` + `samm_track_object()` when SAMM is enabled
- `class_object_delete()` checks Bloom filter for double-free before freeing via `samm_free_object()`
- Falls back to raw `calloc`/`free` when SAMM is disabled (backward compatible)

### 3. Code Generator Changes (`qbe_codegen_v2.cpp`, `cfg_emitter.cpp`, `ast_emitter.cpp`)

#### SAMM Preamble (scope entry)

SAMM calls must be emitted **inside** QBE labeled blocks (QBE requires all instructions
to be inside a labeled block). A `SAMMPreamble` mechanism was added to `CFGEmitter`:

| Context | Preamble | Emitted inside |
|---------|----------|----------------|
| `main` | `samm_init()` | Block 0 of main CFG |
| `FUNCTION` | `samm_enter_scope()` | Block 0 of function CFG |
| `SUB` | `samm_enter_scope()` | Block 0 of sub CFG |
| `METHOD` | `samm_enter_scope()` | After `@start` label |
| `CONSTRUCTOR` | `samm_enter_scope()` | After `@start` label |
| `DESTRUCTOR` | `samm_enter_scope()` | After `@start` label |

#### SAMM Epilogue (scope exit)

`samm_exit_scope()` / `samm_shutdown()` are emitted **before every `ret` instruction**
on all exit paths:

| Exit Path | What's emitted | Location |
|-----------|---------------|----------|
| Function exit block | `samm_exit_scope()` → `ret` | `CFGEmitter::emitExitBlockTerminator()` |
| SUB exit block | `samm_exit_scope()` → `ret` | `CFGEmitter::emitExitBlockTerminator()` |
| Main exit block | `samm_shutdown()` → `ret 0` | `CFGEmitter::emitExitBlockTerminator()` |
| METHOD explicit RETURN | `samm_exit_scope()` → `ret val` | `ASTEmitter::emitReturnStatement()` |
| METHOD void RETURN | `samm_exit_scope()` → `ret` | `ASTEmitter::emitReturnStatement()` |
| METHOD fallback (no RETURN) | `samm_exit_scope()` → `ret default` | `QBECodeGeneratorV2::emitClassMethod()` |
| CONSTRUCTOR end | `samm_exit_scope()` → `ret` | `QBECodeGeneratorV2::emitClassConstructor()` |
| DESTRUCTOR end | `samm_exit_scope()` → `ret` | `QBECodeGeneratorV2::emitClassDestructor()` |
| END statement | `samm_shutdown()` → `ret 0` | `ASTEmitter::emitEndStatement()` |

#### RETAIN on RETURN (automatic ownership transfer)

When a FUNCTION or METHOD returns a `CLASS_INSTANCE` value, `samm_retain_parent()`
is emitted on the return value **before** `samm_exit_scope()`. This moves the object
from the current (about-to-be-destroyed) scope to the caller's scope, preventing
premature cleanup.

| Context | Detection | Emission point |
|---------|-----------|----------------|
| FUNCTION returning CLASS | `returnType == BaseType::CLASS_INSTANCE` | `CFGEmitter::emitExitBlockTerminator()` |
| METHOD returning CLASS | `methodReturnType_ == BaseType::CLASS_INSTANCE` | `ASTEmitter::emitReturnStatement()` |

### 4. Build Integration

| Build Path | File | Changes |
|------------|------|---------|
| Integrated QBE (`qbe_basic_integrated/`) | `qbe_source/main.c` | Added `samm_core.c` to runtime file list, `-lpthread` to all link commands |
| fsh standalone (`fsh/FasterBASICT/`) | `src/fbc_qbe.cpp` | Added `samm_core.c`, `array_descriptor_runtime.c`, `plugin_context_runtime.c`, `string_pool.c` to runtime files list, `-lpthread` to link commands |
| Build script | `build_qbe_basic.sh` | Copies runtime files including SAMM sources (Step 4) |

### 5. Tests

| Test File | Status | What It Tests |
|-----------|--------|---------------|
| `test_class_concat.bas` | ✅ PASS | String concatenation in CLASS context |
| `test_class_p1_constructor.bas` | ✅ PASS | Constructors with various parameter types |
| `test_class_p1_minimal.bas` | ✅ PASS | Minimal CLASS allocation and field access |
| `test_class_p2_basic.bas` | ✅ PASS | Inheritance, SUPER, method override |
| `test_class_p2_inheritance.bas` | ⏭ SKIP | Pre-existing parser issue (unrelated to SAMM) |
| `test_class_p3_is_nothing.bas` | ✅ PASS | IS type check, IS NOTHING, DELETE |
| `test_class_p4_integration.bas` | ✅ PASS | Multiple classes, mixed features, loops |
| `test_class_return_str.bas` | ✅ PASS | METHOD returning STRING |
| `test_class_simple_ctor.bas` | ✅ PASS | Simple constructor |
| `test_samm_integration.bas` | ✅ PASS | **New** — 8 SAMM-specific scenarios |

#### SAMM Integration Test Scenarios (`test_samm_integration.bas`)

1. **Basic allocation** — Object creation and field access
2. **DELETE + IS NOTHING** — Explicit deallocation, null check
3. **Multiple objects** — Independent objects coexisting in same scope
4. **Method returns object (RETAIN)** — Factory method with `samm_retain_parent()`
5. **Object reassignment** — Old reference becomes unreachable
6. **IS type checks** — Inheritance-based IS with SAMM-managed objects
7. **DELETE on NOTHING** — No-op safety
8. **Stress test** — Multiple counters exercised in a loop

---

## Critical Bugs Fixed During Integration

### 1. Dead Code: SAMM calls after CFG emission

**Problem:** `samm_exit_scope()` and `samm_shutdown()` were emitted after
`cfgEmitter_->emitCFG()` in `generateFunction()`, `generateSub()`, and
`generateMainFunction()`. But the exit block within the CFG already emits a `ret`
instruction, making any code after `emitCFG()` unreachable.

**Fix:** Moved scope exit/shutdown calls into `CFGEmitter::emitExitBlockTerminator()`
so they're emitted **before** each `ret` instruction.

### 2. Instructions before first block label

**Problem:** `samm_init()` and `samm_enter_scope()` were emitted before the first
`@block_0` label. QBE requires all instructions to be inside labeled blocks — this
caused `label or } expected` errors.

**Fix:** Added `SAMMPreamble` mechanism to `CFGEmitter`. The preamble is set before
`emitCFG()` and emitted inside block 0 after the `@block_0` label.

### 3. Missing scope exit on METHOD fallback path

**Problem:** In `emitClassMethod()`, the `samm_exit_scope()` was placed between the
method body and the fallback label — dead code because the body's last RETURN already
emitted `ret`. The fallback label's `ret` had no preceding scope exit.

**Fix:** Moved `samm_exit_scope()` to after the fallback label, before the fallback `ret`.

### 4. END statement bypassed shutdown

**Problem:** The BASIC `END` statement emits a direct `ret 0` without calling
`samm_shutdown()`, causing the background cleanup worker to be abandoned.

**Fix:** Added `samm_shutdown()` call before `ret 0` in `emitEndStatement()`.

### 5. Destructor scope safety

**Problem:** Destructors could be called by the SAMM background worker thread, which
has no ambient scope. Any temporary allocations during destructor execution would have
no tracking scope.

**Fix:** Added `samm_enter_scope()` / `samm_exit_scope()` to `emitClassDestructor()`.

### 6. Void METHOD RETURN jumped to non-existent block

**Problem:** A void METHOD with an explicit `RETURN` statement emitted `jmp @block_1`,
but methods are not CFG-based — there is no `block_1`. This is a pre-existing bug
that became apparent during SAMM audit.

**Fix:** Void METHOD RETURN now emits `samm_exit_scope()` followed by direct `ret`
when inside a class context (`currentClassContext_ != nullptr`).

---

## Known Limitations

### Pre-existing (not SAMM-related)

1. **FUNCTION returning CLASS_INSTANCE** — The semantic analyzer reports
   "Unknown return type" for CLASS names as FUNCTION return types. Only METHOD
   return of CLASS instances works. FUNCTION-level CLASS returns require
   frontend changes (parser + semantic analyzer).

2. **DIM inside METHOD bodies** — Local variable declarations (`DIM`) inside
   METHOD bodies can't resolve the variable in the symbol table, causing
   "Variable not found" errors and undefined SSA temporaries. Workaround:
   use direct expressions (e.g., `RETURN NEW Widget(...)`) instead of
   storing to a local first.

3. **SUB-local CLASS variables** — Variables declared with `DIM` inside a SUB
   are allocated in the main function's block_0 instead of the SUB's own scope.
   The SUB references a global variable address that doesn't exist in its
   function. This is a pre-existing scoping issue.

4. **`test_class_p2_inheritance.bas`** — Parser fails on line 118 with
   "Unexpected token: UNKNOWN(.)". Unrelated to SAMM.

### SAMM-specific

1. **No FOR/WHILE loop scopes yet** — SAMM scope enter/exit is only emitted for
   FUNCTION, SUB, METHOD, CONSTRUCTOR, and DESTRUCTOR boundaries. Loop-body
   scopes are planned for Phase 2.

2. **String tracking is a stub** — `samm_track_string()` is a no-op. String
   descriptor integration with SAMM is planned for Phase 2.

3. **List support is dormant** — `samm_alloc_list()`, `samm_track_list()`, and
   `samm_alloc_list_atom()` return NULL / are no-ops. Active in Phase 4.

4. **Bloom filter memory** — The Bloom filter allocates 12 MB at `samm_init()`.
   This is negligible on desktop systems but may need tuning for constrained
   targets.

---

## Files Modified

| File | Type | Summary |
|------|------|---------|
| `fsh/FasterBASICT/runtime_c/samm_bridge.h` | **New** | SAMM C-linkage API header |
| `fsh/FasterBASICT/runtime_c/samm_core.c` | **New** | Pure-C SAMM implementation |
| `fsh/FasterBASICT/runtime_c/class_runtime.c` | Modified | Routed allocation/free through SAMM |
| `fsh/FasterBASICT/src/codegen_v2/qbe_codegen_v2.cpp` | Modified | SAMM preamble, scope management for all function types |
| `fsh/FasterBASICT/src/codegen_v2/cfg_emitter.h` | Modified | Added `SAMMPreamble` enum and setter |
| `fsh/FasterBASICT/src/codegen_v2/cfg_emitter.cpp` | Modified | SAMM preamble emission in block 0, scope exit in exit block |
| `fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp` | Modified | SAMM scope exit + RETAIN in METHOD/END returns |
| `fsh/FasterBASICT/src/fbc_qbe.cpp` | Modified | Added SAMM + missing runtime files to link command |
| `qbe_basic_integrated/qbe_source/main.c` | Modified | Added `samm_core.c` and `-lpthread` |
| `qbe_basic_integrated/runtime/samm_bridge.h` | **New** | Copy of SAMM header |
| `qbe_basic_integrated/runtime/samm_core.c` | **New** | Copy of SAMM implementation |
| `qbe_basic_integrated/runtime/class_runtime.c` | Modified | Copy of SAMM-integrated class runtime |
| `tests/test_samm_integration.bas` | **New** | 8-scenario SAMM integration test |

---

## Next Steps (Remaining Phase 1 + Phase 2)

### High Priority

1. **Fix FUNCTION returning CLASS_INSTANCE** — Requires semantic analyzer changes
   to recognize CLASS names as valid return types for standalone FUNCTIONs. This
   would enable factory functions like `FUNCTION MakeWidget() AS Widget`.

2. **Fix DIM inside METHOD bodies** — Local variable allocation in method bodies
   needs to register variables in the method's local scope rather than failing
   symbol table lookup.

3. **Fix SUB-local CLASS scoping** — Variables declared in SUBs should be
   allocated within the SUB's own QBE function, not in main's block_0.

### Phase 2 Planning

4. **String tracking** — Integrate `string_pool.c` with SAMM scope tracking.
   Track string descriptors via `samm_track_string()`, add RETAIN for strings
   returned from functions.

5. **FOR/WHILE loop scopes** — Emit `samm_enter_scope()` / `samm_exit_scope()`
   at loop boundaries so temporaries created inside loops are cleaned up each
   iteration.

6. **Array scope tracking** — Track dynamic array allocations in SAMM scopes.

### Phase 3–4

7. **Default-on + opt-out** — Make SAMM enabled by default, add `OPTION SAMM OFF`.
8. **Performance benchmarking** — Measure overhead, tune Bloom filter parameters.
9. **LIST types** — Activate dormant list support, add `LIST OF T` syntax.

---

## Architecture Summary

```
┌─────────────────────────────────────────────────────────┐
│                    BASIC Source Code                      │
│  CLASS Widget ... END CLASS                               │
│  DIM w AS Widget = NEW Widget(...)                        │
│  RETURN w   ← triggers RETAIN                            │
│  DELETE w   ← explicit free with Bloom check             │
│  END        ← triggers samm_shutdown()                   │
└──────────────────┬──────────────────────────────────────┘
                   │ CodeGen (qbe_codegen_v2 + cfg_emitter + ast_emitter)
                   ▼
┌─────────────────────────────────────────────────────────┐
│                    QBE IL Output                          │
│  @block_0                                                 │
│      call $samm_init()          ← main preamble          │
│      call $samm_enter_scope()   ← function preamble      │
│      ...                                                  │
│      call $samm_retain_parent(l %retval)  ← before exit  │
│      call $samm_exit_scope()    ← before every ret       │
│      ret %retval                                          │
└──────────────────┬──────────────────────────────────────┘
                   │ QBE Backend → Assembly → Linking
                   ▼
┌─────────────────────────────────────────────────────────┐
│              Linked Executable (with runtime)             │
│                                                           │
│  ┌─────────────────┐     ┌──────────────────────┐        │
│  │  class_runtime.c │────▶│    samm_core.c        │        │
│  │  class_object_new│     │  Scope Stack          │        │
│  │  class_object_del│     │  Bloom Filter (12MB)  │        │
│  └─────────────────┘     │  Background Worker    │        │
│                           │  Cleanup Queue        │        │
│                           │  RETAIN / Track       │        │
│                           └──────────────────────┘        │
└─────────────────────────────────────────────────────────┘
```
