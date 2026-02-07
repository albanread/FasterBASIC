# SAMM Integration Proposal: Scope-Aware Memory Management for FasterBASIC

## Executive Summary

This document proposes integrating the **SAMM (Scope Aware Memory Management)** system
from NewBCPL into FasterBASIC's CLASS/object runtime. SAMM replaces the current raw
`calloc()`/`free()` approach in `class_runtime.c` with a scope-tracked, background-cleaned,
double-free-safe memory manager that maps naturally onto BASIC's lexical structure.

The result: CLASS instances are allocated through a managed heap with automatic scope-exit
cleanup, explicit RETAIN for ownership transfer, Bloom-filter double-free detection, and
background reclamation — all without garbage collection pauses or reference counting overhead.

---

## Table of Contents

1. [Motivation](#1-motivation)
2. [Current State](#2-current-state)
3. [SAMM Architecture Overview](#3-samm-architecture-overview)
4. [Integration Design](#4-integration-design)
5. [Runtime Changes](#5-runtime-changes)
6. [CodeGen Changes](#6-codegen-changes)
7. [BASIC Language Surface](#7-basic-language-surface)
8. [Object Lifecycle Examples](#8-object-lifecycle-examples)
9. [String, Array & List Unification](#9-string-array--list-unification)
10. [Safety Guarantees](#10-safety-guarantees)
11. [Performance Considerations](#11-performance-considerations)
12. [Migration Path](#12-migration-path)
13. [Phase Plan](#13-phase-plan)
14. [Risks & Mitigations](#14-risks--mitigations)
15. [Appendix: API Reference](#15-appendix-api-reference)

---

## 1. Motivation

### 1.1 The Problem

FasterBASIC CLASS instances are heap-allocated via raw `calloc()` and freed via raw
`free()`. This works for trivial programs but has serious limitations:

| Problem | Impact |
|---------|--------|
| **No scope-based cleanup** | Objects allocated inside a SUB/FUNCTION/METHOD that are not explicitly DELETEd leak silently |
| **No double-free detection** | `DELETE obj` twice causes undefined behaviour (heap corruption, crash) |
| **Synchronous destruction** | Destructor chains run inline — deep hierarchies stall the main thread |
| **No allocation tracking** | No way to report leaks, no metrics, no crash diagnostics for heap state |
| **No ownership model** | Returning an object from a function is unsafe — caller must manually track lifetime |

### 1.2 Why SAMM

SAMM (from NewBCPL's HeapManager) solves all of the above without introducing GC pauses
or reference-counting overhead:

- **Scope-based recycling**: allocations are tied to the creating lexical scope and
  automatically reclaimed on scope exit — just like local variables.
- **RETAIN for ownership transfer**: objects that must outlive their scope are explicitly
  promoted to a parent scope via `RETAIN`.
- **Bloom-filter double-free detection**: a fixed 12 MB Bloom filter (96M bits, 10 hash
  functions) catches double-free attempts with <0.1% false-positive rate at zero per-free
  scanning cost.
- **Background cleanup worker**: a dedicated thread drains the cleanup queue so
  destructor chains and deallocation never stall the main thread.
- **Typed allocation tracking**: separate counters and code paths for objects, vectors,
  strings, and lists enable targeted diagnostics and tuned allocation strategies.
- **Thread-safe**: dual-mutex architecture (fast scope mutex + cleanup queue mutex)
  keeps contention minimal on the hot allocation path.
- **Signal-safe crash diagnostics**: shadow heap state can be dumped from signal handlers
  for post-mortem debugging.

### 1.3 Design Philosophy

SAMM is **not** a garbage collector. It is simpler, faster, and more predictable:

| Property | GC / Ref-Counting | SAMM |
|----------|-------------------|------|
| Pause model | Stop-the-world or incremental pauses | None (background thread) |
| Per-assignment cost | Ref inc/dec on every pointer copy | Zero (no ref counts) |
| Cleanup timing | Nondeterministic | Deterministic at scope exit |
| Cycle handling | Needs special support | Not needed (scope-based) |
| Memory overhead | Object headers, ref fields, mark bits | Bloom filter (fixed 12 MB) + scope vectors |
| Complexity | High | Low |

The trade-off: programmers must use `RETAIN` (or `RETURN`) when an object needs to
survive past its creating scope. This is a minimal cognitive cost for a BASIC-level
language where most objects are local temporaries.

---

## 2. Current State

### 2.1 class_runtime.c — Object Allocation

```c
/* class_runtime.c — current implementation */
void* class_object_new(int64_t object_size, void* vtable, int64_t class_id) {
    void* obj = calloc(1, (size_t)object_size);   // raw calloc
    if (!obj) { /* abort */ }
    ((void**)obj)[0] = vtable;                     // install vtable
    ((int64_t*)obj)[1] = class_id;                 // install class_id
    return obj;
}

void class_object_delete(void** obj_ref) {
    void* obj = *obj_ref;
    if (!obj) return;
    /* call destructor via vtable[3] if present */
    free(obj);                                     // raw free
    *obj_ref = NULL;
}
```

### 2.2 memory_mgmt.c — Basic Wrappers

Thin wrappers around `malloc`/`calloc`/`free` with optional `DEBUG_MEMORY` counters.
No scope tracking. No double-free protection.

### 2.3 string_pool.c — String Descriptors

Slab-allocated string descriptor pool with free-list recycling. Already has its own
lifecycle management. SAMM can wrap this rather than replace it.

### 2.4 Emitted Code (QBE IL)

The codegen emits direct calls to `class_object_new` and `class_object_delete`. No
scope enter/exit calls are emitted. Method bodies, SUBs, and FUNCTIONs have no
prologue/epilogue hooks for memory management.

---

## 3. SAMM Architecture Overview

### 3.1 Core Components (from NewBCPL HeapManager)

```
┌─────────────────────────────────────────────────────────────────┐
│                        HeapManager                              │
│                       (Singleton)                               │
│                                                                 │
│  ┌──────────────────┐  ┌──────────────┐  ┌──────────────────┐  │
│  │  Scope Stack     │  │ Bloom Filter │  │ Background       │  │
│  │  ┌─ global ────┐ │  │ 96M bits     │  │ Cleanup Worker   │  │
│  │  │ ┌─ sub ───┐ │ │  │ 10 hash fns  │  │ (std::thread)    │  │
│  │  │ │ ┌─for─┐ │ │ │  │ <0.1% FP     │  │                  │  │
│  │  │ │ │ptrs │ │ │ │  │              │  │ cleanup_queue_   │  │
│  │  │ │ └─────┘ │ │ │  │ Double-free  │  │ cleanup_cv_      │  │
│  │  │ └─────────┘ │ │  │ detection    │  │ Batched dealloc  │  │
│  │  └─────────────┘ │  └──────────────┘  └──────────────────┘  │
│  └──────────────────┘                                           │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Typed Allocators                                        │   │
│  │  allocObject()  allocVec()  allocString()  allocList()   │   │
│  │  + Retained variants for ownership transfer              │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │  Metrics & Diagnostics                                   │   │
│  │  Allocation counts, bytes, peak usage, cleanup timing    │   │
│  │  Signal-safe shadow heap for crash dumps                 │   │
│  └──────────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
```

### 3.2 Lifecycle Flow

```
Program start
  │
  ├─ HeapManager singleton created
  ├─ Global scope pushed onto scope_allocations_
  ├─ SAMM enabled, background worker started
  │
  ├─ enterScope()          ← SUB / FUNCTION / METHOD / FOR / WHILE
  │   ├─ Push new vector onto scope_allocations_
  │   ├─ allocObject()     ← NEW ClassName()
  │   │   └─ Pointer tracked in current scope vector
  │   ├─ retainPointer()   ← RETAIN / RETURN object
  │   │   └─ Move pointer from current scope to parent scope
  │   └─ ...
  │
  ├─ exitScope()           ← END SUB / END FUNCTION / NEXT / WEND
  │   ├─ Pop scope vector
  │   ├─ Queue pointers for background cleanup
  │   └─ Notify cleanup worker
  │
  ├─ cleanupWorker (background thread)
  │   ├─ Dequeue batch of pointers
  │   ├─ Call destructors via vtable
  │   ├─ Free memory
  │   └─ Update Bloom filter and metrics
  │
  └─ shutdown()
      ├─ Drain remaining cleanup queue
      ├─ Clean up all remaining scopes
      ├─ Stop background worker
      └─ Print metrics
```

### 3.3 RETAIN Semantics

When an object must outlive its creating scope (e.g., returned from a function or
assigned to a module-level variable), the codegen emits a `RETAIN` call:

```
retainPointer(ptr, parent_scope_offset)
```

This moves the pointer from the current scope's tracking vector to a parent scope's
vector. The object will be cleaned up when that parent scope exits instead.

---

## 4. Integration Design

### 4.1 Principles

1. **C-linkage API**: SAMM is exposed to QBE-emitted code through `extern "C"` wrapper
   functions, exactly as the current `class_object_new`/`class_object_delete` are.
2. **Drop-in replacement**: `class_object_new` calls `HeapManager::allocObject` instead of
   `calloc`. `class_object_delete` calls `HeapManager::free` instead of `free`.
3. **Scope hooks in codegen**: The QBE emitter inserts `samm_enter_scope()` /
   `samm_exit_scope()` calls at SUB/FUNCTION/METHOD boundaries.
4. **Opt-in initially**: SAMM is enabled by a compiler flag (`--samm` or `OPTION SAMM ON`
   in source). Without the flag, behaviour is identical to today (raw malloc/free).
5. **Incremental adoption**: Strings, arrays, lists, and UDTs can be brought under SAMM
   tracking in later phases — the initial integration targets CLASS instances only. List
   support is kept intact in the imported HeapManager so it is ready when we add list
   types to FasterBASIC.

### 4.2 Component Mapping

| SAMM Component | FasterBASIC Integration Point |
|----------------|-------------------------------|
| `HeapManager::allocObject()` | Called from `class_object_new()` |
| `HeapManager::free()` | Called from `class_object_delete()` |
| `HeapManager::enterScope()` | Emitted at SUB/FUNCTION/METHOD prologue |
| `HeapManager::exitScope()` | Emitted at END SUB/END FUNCTION/END METHOD epilogue |
| `HeapManager::retainPointer()` | Emitted for RETURN of object values, RETAIN statement |
| `HeapManager::trackInCurrentScope()` | Emitted after `class_object_new` for explicit tracking |
| Bloom filter | Checked in `class_object_delete` before freeing |
| Background worker | Runs destructor chains + deallocation off main thread |
| `HeapManager::shutdown()` | Called from `basic_cleanup()` at program exit |

### 4.3 File Organisation

```
runtime_c/
  class_runtime.c          ← Modified: route through SAMM
  class_runtime.h          ← Modified: add SAMM declarations
  samm_bridge.c            ← NEW: C-linkage bridge to HeapManager
  samm_bridge.h            ← NEW: C-linkage bridge header
  memory_mgmt.c            ← Unchanged (basic wrappers still available)
  string_pool.c            ← Phase 2: track descriptors in SAMM scopes

runtime/ (or lib/)
  HeapManager.h             ← Imported from NBCPL (adapted, list support kept)
  HeapManager.cpp           ← Imported from NBCPL (adapted, list support kept)
  BloomFilter.h             ← Imported from NBCPL (unchanged)
  heap_manager_defs.h       ← Imported from NBCPL (adapted)
  heap_c_wrappers.cpp       ← Imported from NBCPL (adapted)
  ListDataTypes.h           ← Imported from NBCPL (kept for future list support)
```

---

## 5. Runtime Changes

### 5.1 samm_bridge.h — C-Linkage API for QBE-Emitted Code

```c
/* samm_bridge.h
 * C-linkage wrappers so QBE-emitted code can call SAMM functions.
 * All functions use the FasterBASIC naming convention (samm_ prefix).
 */

#ifndef SAMM_BRIDGE_H
#define SAMM_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Initialise SAMM (call once at program start, before any allocations) */
void samm_init(void);

/* Shutdown SAMM (call once at program exit, after all scopes exited) */
void samm_shutdown(void);

/* Scope management — emitted by codegen at function/method boundaries */
void samm_enter_scope(void);
void samm_exit_scope(void);

/* Object allocation — replaces raw calloc in class_object_new */
void* samm_alloc_object(size_t size);

/* Object deallocation — replaces raw free in class_object_delete */
void samm_free_object(void* ptr);

/* Track an allocation in the current scope (for objects allocated
   through class_object_new which already calls samm_alloc_object) */
void samm_track(void* ptr);

/* RETAIN: move pointer from current scope to parent scope.
 * parent_offset=1 means immediate parent, 2 means grandparent, etc.
 * Used when returning objects or assigning to outer-scope variables. */
void samm_retain(void* ptr, int parent_offset);

/* Convenience: retain to immediate parent scope */
void samm_retain_parent(void* ptr);

/* List allocation — kept for future FasterBASIC list support (Phase 4).
 * Allocates a ListHeader tracked in current scope. */
void* samm_alloc_list(void);

/* Track a freelist-allocated ListHeader in current scope.
 * Background worker will return it to the freelist instead of raw-freeing. */
void samm_track_list(void* list_header_ptr);

/* Check if a pointer was already freed (Bloom filter query).
 * Returns non-zero if the pointer is probably freed. */
int samm_is_probably_freed(void* ptr);

/* Query current scope depth (for diagnostics) */
int samm_scope_depth(void);

/* Print SAMM metrics to stderr */
void samm_print_stats(void);

/* Wait for all background cleanup to complete */
void samm_wait(void);

#ifdef __cplusplus
}
#endif

#endif /* SAMM_BRIDGE_H */
```

### 5.2 samm_bridge.c — Implementation

```c
/* samm_bridge.c
 * C-linkage bridge between QBE-emitted code and HeapManager (C++ singleton).
 *
 * When SAMM is disabled (compile-time or runtime), these functions
 * fall through to raw malloc/free so there is zero overhead.
 */

#include "samm_bridge.h"

/* When building with SAMM support, the real implementations are provided
   by heap_c_wrappers.cpp which delegates to HeapManager::getInstance().
   When building without SAMM, we provide trivial fallbacks here. */

#ifndef SAMM_ENABLED

#include <stdlib.h>
#include <string.h>

void  samm_init(void)                       { /* no-op */ }
void  samm_shutdown(void)                   { /* no-op */ }
void  samm_enter_scope(void)                { /* no-op */ }
void  samm_exit_scope(void)                 { /* no-op */ }
void* samm_alloc_object(size_t size)        { return calloc(1, size); }
void  samm_free_object(void* ptr)           { free(ptr); }
void  samm_track(void* ptr)                 { (void)ptr; }
void  samm_retain(void* ptr, int offset)    { (void)ptr; (void)offset; }
void  samm_retain_parent(void* ptr)         { (void)ptr; }
void* samm_alloc_list(void)                 { return NULL; /* lists not yet supported */ }
void  samm_track_list(void* ptr)            { (void)ptr; }
int   samm_is_probably_freed(void* ptr)     { (void)ptr; return 0; }
int   samm_scope_depth(void)                { return 0; }
void  samm_print_stats(void)                { /* no-op */ }
void  samm_wait(void)                       { /* no-op */ }

#endif /* !SAMM_ENABLED */
```

### 5.3 Modified class_runtime.c

The key changes are replacing `calloc`/`free` with `samm_alloc_object`/`samm_free_object`
and adding double-free detection:

```c
#include "class_runtime.h"
#include "samm_bridge.h"

void* class_object_new(int64_t object_size, void* vtable, int64_t class_id) {
    if (object_size < CLASS_HEADER_SIZE) {
        fprintf(stderr, "INTERNAL ERROR: class_object_new: size %" PRId64
                " < minimum %d\n", object_size, CLASS_HEADER_SIZE);
        exit(1);
    }

    /* Allocate through SAMM — returns zeroed memory, tracked in current scope */
    void* obj = samm_alloc_object((size_t)object_size);
    if (!obj) {
        fprintf(stderr, "ERROR: Out of memory (%" PRId64 " bytes)\n", object_size);
        exit(1);
    }

    /* Track in current SAMM scope so it gets cleaned up on scope exit */
    samm_track(obj);

    /* Install object header */
    ((void**)obj)[0]   = vtable;
    ((int64_t*)obj)[1] = class_id;

    return obj;
}

void class_object_delete(void** obj_ref) {
    if (!obj_ref) return;
    void* obj = *obj_ref;
    if (!obj) return;

    /* Double-free detection via Bloom filter */
    if (samm_is_probably_freed(obj)) {
        fprintf(stderr, "WARNING: Possible double-free on object at %p\n", obj);
        *obj_ref = NULL;
        return;
    }

    /* Call destructor via vtable[3] if present */
    void** vtable = (void**)((void**)obj)[0];
    if (vtable) {
        void* dtor_ptr = ((void**)vtable)[3];
        if (dtor_ptr) {
            typedef void (*dtor_fn)(void*);
            ((dtor_fn)dtor_ptr)(obj);
        }
    }

    /* Free through SAMM */
    samm_free_object(obj);

    /* Nullify caller's pointer */
    *obj_ref = NULL;
}
```

### 5.4 HeapManager Adaptation for FasterBASIC

The HeapManager from NBCPL needs minor adaptation:

| Area | Change |
|------|--------|
| **Singleton init** | Remove NBCPL-specific `stats_init()`, replace with FasterBASIC metrics init |
| **ListHeader/ListAtom** | **Keep** — list support will be used when we add lists to FasterBASIC (lists of objects, etc.). Wire `returnNodeToFreelist`/`returnHeaderToFreelist` to FasterBASIC-side freelist once list types are introduced (Phase 4). Until then the code paths remain dormant but intact. |
| **Graphics resources** | Remove — not needed for FasterBASIC (can be re-added if graphics CLASSes are introduced) |
| **String pool integration** | Replace NBCPL `embedded_fast_bcpl_free_chars` with FasterBASIC `string_pool_free` |
| **Debug printf** | Gate behind `SAMM_TRACE` compile flag (remove unconditional `printf("DEBUG: ...")`) |
| **allocObject** | Ensure it zero-fills (calloc semantics) — CLASS fields depend on zero-init |
| **cleanupPointersImmediate** | Add vtable-aware destructor dispatch — walk vtable[3] before freeing object memory. Keep existing list-cleanup path (`returnNodeToFreelist` / `returnHeaderToFreelist`) for future use. |
| **freelist_pointers_ / trackFreelistAllocation** | **Keep** — these track ListHeader pointers so the background worker can return list memory to the freelist rather than raw-freeing it. Needed for Phase 4. |
| **Bloom filter** | Keep the fixed 96M-bit filter (12 MB) — no scaling needed for BASIC programs |

### 5.5 SAMM-Aware Destructor Dispatch in Background Worker

When the background cleanup worker processes a batch of object pointers, it must call
destructors **before** freeing memory. This is critical for CLASS objects that hold
resources (file handles, strings, child objects):

```c
/* In cleanupPointersImmediate — adapted for FasterBASIC CLASS objects */
for (void* ptr : ptrs) {
    if (ptr == nullptr) continue;

    /* Check if this is a CLASS object (has vtable at offset 0) */
    void** vtable = (void**)((void**)ptr)[0];
    if (vtable) {
        /* Call destructor via vtable[3] if present */
        void* dtor_ptr = ((void**)vtable)[3];
        if (dtor_ptr) {
            typedef void (*dtor_fn)(void*);
            ((dtor_fn)dtor_ptr)(ptr);
        }
    }

    /* Now safe to free the memory */
    /* ... existing HeapManager free logic ... */
}
```

**Safety note**: destructors run on the background thread, so they must not touch
thread-local state or perform I/O that assumes the main thread's context. For Phase 1,
we document this limitation. In Phase 2, we can add a `DESTRUCTOR THREADSAFE` annotation
or queue destructors back to the main thread if needed.

---

## 6. CodeGen Changes

### 6.1 Scope Prologue/Epilogue Emission

The QBE code generator (`QBECodeGeneratorV2` / `ASTEmitter`) emits scope enter/exit
calls at every SUB, FUNCTION, and METHOD boundary.

#### Before (current):

```qbe
export function $MyFunction() {
@start
    ; ... function body ...
    ret
}
```

#### After (with SAMM):

```qbe
export function $MyFunction() {
@start
    call $samm_enter_scope()
    ; ... function body ...
    call $samm_exit_scope()
    ret
}
```

For methods:

```qbe
function $Animal_Speak(l %me) {
@start
    call $samm_enter_scope()
    ; ... method body ...
    call $samm_exit_scope()
    ret
}
```

#### Early return paths:

Every `RETURN` statement must call `samm_exit_scope()` before the QBE `ret`:

```qbe
@return_path
    call $samm_exit_scope()
    ret %retval
```

The emitter already generates method-return paths — these just need the exit-scope
call prepended.

### 6.2 NEW Expression — Track Allocation

After `class_object_new` returns, the pointer is already tracked (because
`class_object_new` calls `samm_track`). No additional codegen change is needed for
the common case.

### 6.3 RETURN Object — RETAIN Before Exit

When a METHOD or FUNCTION returns a CLASS instance, the object must be retained to the
caller's scope **before** the current scope is exited:

```qbe
@method_return
    ; %retval holds the object pointer being returned
    call $samm_retain_parent(l %retval)
    call $samm_exit_scope()
    ret %retval
```

The emitter must detect when the return type is a CLASS type and insert the
`samm_retain_parent` call.

### 6.4 Assignment to Outer-Scope Variable

When an object created in an inner scope is assigned to a variable in an outer scope
(e.g., a module-level DIM), the codegen must emit RETAIN:

```basic
DIM globalObj AS Widget

SUB CreateWidget()
    DIM w AS Widget = NEW Widget()
    globalObj = w          ' ← w must be RETAINED to global scope
END SUB
```

Emitted as:

```qbe
    ; After storing %w into $globalObj
    %depth = call $samm_scope_depth()
    call $samm_retain(l %w, w %depth)   ; retain to global scope
```

**Implementation note**: Detecting cross-scope assignment statically requires the
semantic analyzer to compare the declaring scope of the target variable with the
current scope. For Phase 1, we can use a conservative approach: RETAIN every object
assigned to a variable declared in a different (outer) scope.

### 6.5 DELETE Statement — Explicit Free

`DELETE obj` continues to call `class_object_delete` which now routes through SAMM.
The Bloom filter check prevents double-free. No codegen change needed beyond what
already exists.

### 6.6 FOR/WHILE/Block Scopes (Phase 2)

In Phase 2, we can optionally emit `samm_enter_scope()`/`samm_exit_scope()` for
FOR/WHILE loop bodies, so temporary objects created inside loops are reclaimed per
iteration rather than accumulating until the enclosing function exits:

```basic
FOR i = 1 TO 1000000
    DIM temp AS Widget = NEW Widget()  ' cleaned up each iteration
    temp.Process()
NEXT i
```

This is a significant anti-leak feature for long-running loops. Without per-loop
scoping, all 1,000,000 Widget objects would live until the function returns.

---

## 7. BASIC Language Surface

### 7.1 Opt-In Syntax

SAMM is enabled per-program via an option statement:

```basic
OPTION SAMM ON           ' Enable scope-aware memory management
```

Or via compiler flag:

```
fbc --samm program.bas
```

When SAMM is OFF (default for backward compatibility), behaviour is identical to the
current raw calloc/free approach.

### 7.2 RETAIN Statement (Explicit Ownership Transfer)

```basic
FUNCTION MakeWidget() AS Widget
    DIM w AS Widget = NEW Widget()
    w.Configure()
    RETAIN w                    ' Promote to caller's scope
    RETURN w
END FUNCTION
```

**Syntax**: `RETAIN variable`

**Semantics**: Moves the object from the current scope's tracking to the immediate
parent scope. The object will be cleaned up when the parent scope exits (unless
retained again or explicitly DELETEd).

**Note**: For the common case of `RETURN objectVar`, the compiler can automatically
insert RETAIN — no explicit statement needed. The explicit `RETAIN` is for cases
where the programmer assigns to an outer variable without returning.

### 7.3 Implicit RETAIN on RETURN (Sugar)

When a FUNCTION/METHOD returns a CLASS-typed value, the compiler automatically retains
the object. The programmer never needs to write `RETAIN` for simple factory patterns:

```basic
FUNCTION CreatePerson(name AS STRING, age AS INTEGER) AS Person
    DIM p AS Person = NEW Person(name, age)
    RETURN p                    ' Compiler auto-inserts RETAIN before scope exit
END FUNCTION
```

### 7.4 DELETE (Unchanged)

```basic
DELETE obj                      ' Explicit deallocation (with double-free safety)
```

DELETE behaviour is unchanged from the programmer's perspective. Under the hood, SAMM
adds Bloom-filter double-free detection and removes the pointer from scope tracking so
it won't be freed again on scope exit.

### 7.5 SAMM Diagnostics (Debug Mode)

```basic
OPTION SAMM ON
OPTION SAMM TRACE ON            ' Enable allocation/free tracing to stderr
```

At program exit, if SAMM TRACE is ON, the runtime prints:

```
=== SAMM Statistics ===
  Scopes entered:     142
  Scopes exited:      142
  Objects allocated:  387
  Objects cleaned:    387
  Cleanup batches:    28
  Cleanup time:       1.23 ms
  Double-free blocks: 0
  Bloom filter FP:    0.00%
  Peak scope depth:   7
===========================
```

---

## 8. Object Lifecycle Examples

### 8.1 Simple Local Object (Auto-Cleaned)

```basic
OPTION SAMM ON

CLASS Counter
    Value AS INTEGER
    CONSTRUCTOR()
        ME.Value = 0
    END CONSTRUCTOR
    METHOD Increment()
        ME.Value = ME.Value + 1
    END METHOD
END CLASS

SUB DoWork()                            ' ← samm_enter_scope()
    DIM c AS Counter = NEW Counter()    ' ← samm_alloc_object + samm_track
    c.Increment()
    c.Increment()
    PRINT c.Value                       ' prints 2
END SUB                                 ' ← samm_exit_scope() → c auto-freed

DoWork()
' c is already freed — no leak
```

### 8.2 Factory Function (RETAIN via RETURN)

```basic
OPTION SAMM ON

CLASS Widget
    Name AS STRING
    CONSTRUCTOR(n AS STRING)
        ME.Name = n
    END CONSTRUCTOR
    METHOD Describe()
        PRINT "Widget: "; ME.Name
    END METHOD
END CLASS

FUNCTION MakeWidget(name AS STRING) AS Widget    ' ← samm_enter_scope()
    DIM w AS Widget = NEW Widget(name)           ' tracked in MakeWidget scope
    RETURN w                                     ' ← samm_retain_parent(w)
END FUNCTION                                     ' ← samm_exit_scope()
                                                 '    w survives (retained to caller)

SUB Main()                                       ' ← samm_enter_scope()
    DIM myWidget AS Widget = MakeWidget("Gizmo") ' myWidget in Main's scope
    myWidget.Describe()
END SUB                                          ' ← samm_exit_scope()
                                                 '    myWidget freed here

Main()
```

### 8.3 Inheritance with Destructor Chain

```basic
OPTION SAMM ON

CLASS Base
    DESTRUCTOR()
        PRINT "~Base"
    END DESTRUCTOR
END CLASS

CLASS Derived EXTENDS Base
    DESTRUCTOR()
        PRINT "~Derived"
    END DESTRUCTOR
END CLASS

SUB Test()                                       ' ← samm_enter_scope()
    DIM d AS Derived = NEW Derived()
END SUB                                          ' ← samm_exit_scope()
                                                 '    Background worker calls:
                                                 '      ~Derived (via vtable[3])
                                                 '      then frees memory

Test()
samm_wait()                                      ' ensure output appears
' Output:
'   ~Derived
```

### 8.4 Double-Free Protection

```basic
OPTION SAMM ON

CLASS Foo
END CLASS

DIM x AS Foo = NEW Foo()
DELETE x                    ' First delete: OK, x set to NOTHING
DELETE x                    ' Second delete: NOTHING check → no-op (safe)

' Edge case: manual pointer aliasing (if supported in future)
' DIM y AS Foo = x           ' y aliases x
' DELETE x                   ' frees the object, x = NOTHING
' DELETE y                   ' Bloom filter catches: "WARNING: Possible double-free"
```

---

## 9. String, Array & List Unification

### 9.1 Phase 2 Goal: Strings

Once SAMM is working for CLASS instances, the next priority is string scope tracking:

- **String descriptors**: Track string allocations in SAMM scopes so temporary strings
  created inside loops are reclaimed per iteration.
- **Dynamic arrays**: Track REDIM'd arrays in SAMM scopes for automatic cleanup.

### 9.2 String Pool Integration

The existing `string_pool.c` slab allocator continues to manage string descriptor
memory. SAMM wraps it by calling `samm_track_string_pool_allocation(ptr)` when a
descriptor is allocated, and the cleanup worker calls `string_pool_free()` instead of
raw `free()` for string-pool-tagged pointers.

This is exactly how NBCPL's HeapManager already handles string pool allocations — the
`string_pool_pointers_` set distinguishes them from regular heap allocations.

### 9.3 Array Scope Tracking

Dynamic arrays allocated via REDIM can be tracked similarly:

```basic
SUB ProcessData()                   ' ← samm_enter_scope()
    DIM buffer%(1000)               ' tracked in scope
    ' ... work with buffer ...
END SUB                             ' ← samm_exit_scope() → buffer freed
```

This eliminates a common source of leaks in BASIC programs where dynamically allocated
arrays inside SUBs are never explicitly freed.

### 9.4 Phase 4 Goal: Lists

After objects, strings, and arrays are managed under SAMM, we introduce **lists** as a
first-class heap data structure in FasterBASIC. Lists are the simplest way to use the
heap for collections, and "lists of objects" is an extremely common pattern.

SAMM already has full list infrastructure from NBCPL:

- **`allocList()`** — allocates a `ListHeader` tracked in the current scope
- **`trackFreelistAllocation()`** — marks a pointer as a freelist-managed ListHeader
- **`freelist_pointers_` set** — tells the background worker to return list memory to
  the freelist (via `returnHeaderToFreelist` / `returnNodeToFreelist`) rather than
  raw-freeing it
- **Scope-aware cleanup** — list headers and their atoms are returned to freelists on
  scope exit, ready for immediate reuse

This infrastructure is kept intact during Phases 1–3 so that when we add list types to
FasterBASIC, the memory management layer is already in place.

#### Envisioned BASIC Syntax (Phase 4)

```basic
' Create a list of objects
DIM animals AS LIST OF Animal

' Append objects — tracked in current SAMM scope
animals.ADD(NEW Dog("Rex"))
animals.ADD(NEW Cat("Whiskers"))

' Iterate
FOR EACH a IN animals
    a.Speak()
NEXT a

' List and contents auto-cleaned on scope exit
```

#### Why Keep List Support Now

1. **Zero cost** — dormant code paths add no runtime overhead when lists aren't used
2. **Avoids rework** — stripping list support and re-adding it later means touching
   HeapManager twice, with risk of regression
3. **Proven code** — the NBCPL freelist/ListHeader machinery is already tested and
   integrated with SAMM's background worker
4. **Natural extension** — once CLASS objects work under SAMM, "list of objects" is
   the obvious next collection type to add

---

## 10. Safety Guarantees

### 10.1 What SAMM Guarantees

| Guarantee | Mechanism |
|-----------|-----------|
| **No leaked objects** (within SAMM scopes) | Scope-exit cleanup frees all tracked allocations |
| **No double-free crashes** | Bloom filter detects and blocks double-free attempts |
| **No use-after-free** (for scope-local objects) | Object is freed only after scope exits — all references within the scope are dead |
| **Deterministic cleanup timing** | Cleanup happens at scope exit (queued to background worker) |
| **Thread-safe allocation** | Mutex-protected singleton, dual-mutex for low contention |

### 10.2 What SAMM Does NOT Guarantee

| Non-guarantee | Explanation |
|---------------|-------------|
| **Cyclic reference cleanup** | If A references B and B references A, and both are RETAIN'd to the same scope, they will be freed (but destructor ordering is not defined). Cycles across scope boundaries are the programmer's responsibility. |
| **Use-after-free for retained objects** | If you RETAIN an object and then use it after the retaining scope exits, it's undefined. |
| **Destructor ordering** | Objects in the same scope are cleaned up in batch — ordering within a batch is not guaranteed. |
| **Destructor thread affinity** | Destructors run on the background cleanup thread (Phase 1). Thread-sensitive destructors need care. |

### 10.3 Bloom Filter False Positives

The fixed 96M-bit Bloom filter with 10 hash functions has a false-positive rate of
<0.1% at 10M tracked addresses. A false positive means SAMM incorrectly warns about
a double-free that isn't one. This is harmless — the warning is printed but the free
proceeds (the check is advisory, not blocking in Phase 1).

For FasterBASIC programs, which rarely allocate more than a few thousand objects, the
effective false-positive rate is negligibly close to zero.

---

## 11. Performance Considerations

### 11.1 Overhead per Allocation

| Operation | Without SAMM | With SAMM | Delta |
|-----------|-------------|-----------|-------|
| `class_object_new` | `calloc` (~50ns) | `calloc` + scope-track (~80ns) | +30ns |
| `class_object_delete` | `free` (~40ns) | Bloom check + queue (~60ns) | +20ns |
| Scope enter | N/A | Push vector (~10ns) | +10ns |
| Scope exit | N/A | Pop + queue batch (~50ns) | +50ns |

Total overhead per object lifecycle: ~100ns. For a program that creates 10,000 objects,
that's 1ms total — well within acceptable bounds.

### 11.2 Memory Overhead

| Component | Size |
|-----------|------|
| Bloom filter | 12 MB (fixed, one-time) |
| Scope stack | ~1 KB per scope depth level (vector of pointers) |
| HeapBlock tracking map | ~100 bytes per live allocation |
| Background thread | ~8 KB stack |

Total for a typical program: ~13 MB. This is the same fixed cost regardless of program
size — suitable for modern systems.

### 11.3 Background Cleanup Benefit

The background cleanup worker means destructor chains and deallocation happen off the
main thread. For programs with complex destructor logic (e.g., closing files, releasing
resources), this is a net performance win — the main thread never blocks on cleanup.

---

## 12. Migration Path

### 12.1 Backward Compatibility

- Without `OPTION SAMM ON` or `--samm`, the compiler emits no scope calls and
  `class_runtime.c` uses the existing calloc/free path via the no-op fallbacks in
  `samm_bridge.c`.
- All existing tests pass unchanged.
- SAMM is additive — it cannot break programs that don't opt in.

### 12.2 Gradual Rollout

1. **Phase 1**: SAMM for CLASS instances only, opt-in via flag.
2. **Phase 2**: SAMM for strings and arrays.
3. **Phase 3**: Polish, default-on, remove raw calloc/free fallbacks.
4. **Phase 4**: Add list types to FasterBASIC, backed by SAMM's existing freelist infrastructure.

### 12.3 Testing Strategy

| Test Category | Count | Description |
|---------------|-------|-------------|
| Existing CLASS tests | 9 | Re-run with SAMM enabled, verify identical output |
| SAMM scope tests | 5 | Verify objects freed on scope exit |
| SAMM RETAIN tests | 5 | Verify factory pattern, cross-scope assignment |
| SAMM double-free tests | 3 | Verify Bloom filter catches double DELETE |
| SAMM destructor tests | 3 | Verify destructors run on scope exit |
| SAMM loop cleanup tests | 3 | Verify per-iteration cleanup (Phase 2) |
| SAMM metrics tests | 2 | Verify diagnostic output |
| Stress tests | 3 | 100K+ objects, deep scope nesting, rapid alloc/free |

---

## 13. Phase Plan

### Phase 1: Core SAMM Integration — Objects & Classes (MVP)

| Task | Component | Estimate |
|------|-----------|----------|
| Import HeapManager.h/cpp, BloomFilter.h, heap_manager_defs.h, ListDataTypes.h | Runtime | 2 hr |
| Adapt HeapManager: remove NBCPL-specific code (graphics, BCPL-specific stats); **keep list support intact** | Runtime | 3 hr |
| Create samm_bridge.h / samm_bridge.c (with dormant list API stubs) | Runtime | 2 hr |
| Create heap_c_wrappers.cpp for FasterBASIC | Runtime | 2 hr |
| Modify class_runtime.c to use samm_alloc_object / samm_free_object | Runtime | 1 hr |
| Add `samm_enter_scope`/`samm_exit_scope` emission in QBECodeGeneratorV2 for SUB/FUNCTION | CodeGen | 3 hr |
| Add `samm_enter_scope`/`samm_exit_scope` emission for METHOD bodies | CodeGen | 2 hr |
| Add `samm_retain_parent` emission for RETURN of CLASS values | CodeGen | 2 hr |
| Add samm_init() to program prologue, samm_shutdown() to epilogue | CodeGen | 1 hr |
| Update build system (Makefile/CMake) to compile C++ runtime with SAMM | Build | 2 hr |
| Port existing 9 CLASS tests to run with SAMM | Tests | 2 hr |
| Write 5 new SAMM-specific tests (scope cleanup, RETAIN, double-free) | Tests | 3 hr |
| **Phase 1 Total** | | **~25 hr** |

### Phase 2: String & Array Tracking

| Task | Component | Estimate |
|------|-----------|----------|
| Integrate string_pool.c with SAMM scope tracking | Runtime | 4 hr |
| Add SAMM tracking for dynamic array allocation | Runtime | 3 hr |
| Emit scope enter/exit for FOR/WHILE loop bodies | CodeGen | 3 hr |
| RETAIN semantics for strings returned from functions | CodeGen | 2 hr |
| Write loop-cleanup and string-scope tests | Tests | 3 hr |
| **Phase 2 Total** | | **~15 hr** |

### Phase 3: Polish & Default-On

| Task | Component | Estimate |
|------|-----------|----------|
| Make SAMM default-on, add `OPTION SAMM OFF` for opt-out | CodeGen/Parser | 2 hr |
| Destructor thread-safety annotations | Semantic | 3 hr |
| SAMM TRACE integration with existing debug infrastructure | Runtime | 2 hr |
| Performance benchmarking and tuning | All | 4 hr |
| Documentation and examples | Docs | 3 hr |
| **Phase 3 Total** | | **~14 hr** |

### Phase 4: Lists

Lists are a natural next step — "list of objects" is the simplest and most useful
collection pattern for a BASIC language. SAMM's freelist/ListHeader infrastructure
(kept intact from NBCPL during Phases 1–3) provides the memory management backbone.

| Task | Component | Estimate |
|------|-----------|----------|
| Design LIST type syntax and semantics for FasterBASIC (`LIST OF ClassName`) | Design | 3 hr |
| Add LIST type to parser, semantic analyzer, type system | Frontend | 6 hr |
| Implement ListHeader/ListAtom freelist for FasterBASIC (wire to SAMM `allocList`, `trackFreelistAllocation`) | Runtime | 4 hr |
| Emit LIST operations in QBE codegen (ADD, REMOVE, FOR EACH, SIZE, etc.) | CodeGen | 8 hr |
| SAMM integration: list headers tracked in scope, atoms returned to freelist on cleanup | Runtime | 3 hr |
| RETAIN semantics for lists returned from functions / assigned to outer scope | CodeGen | 2 hr |
| Write LIST tests: create, iterate, scope cleanup, lists of objects, nested lists | Tests | 5 hr |
| **Phase 4 Total** | | **~31 hr** |

### Total Estimated Effort: ~85 hours

---

## 14. Risks & Mitigations

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| **Background destructor thread safety** | Medium | High | Phase 1: document limitation; Phase 2: add `DESTRUCTOR MAIN` annotation to queue destructors back to main thread |
| **C++ dependency** | Low | Medium | HeapManager is C++ but exposed via `extern "C"` wrappers — QBE-emitted code sees only C functions. The C++ runtime is already compiled and linked as a library. |
| **Bloom filter memory (12 MB)** | Low | Low | 12 MB is negligible on modern systems. Can be reduced to 1.2 MB (10x smaller filter) for constrained targets with higher FP rate (~1%). |
| **Scope mismatch bugs** | Medium | High | Every `samm_enter_scope` must have a matching `samm_exit_scope` on every control-flow path including early returns and exceptions. The emitter must audit all exit paths. |
| **RETAIN forgetting** | Medium | Medium | Objects not RETAIN'd are freed on scope exit. If the programmer forgets RETAIN and uses the pointer after scope exit, it's use-after-free. Mitigated by auto-RETAIN on RETURN and clear documentation. |
| **Integration with existing string refcounting** | Medium | Medium | Strings already use refcounting via string descriptors. SAMM scope tracking is additive — it catches descriptors that leak past their refcount (e.g., lost references). The two systems complement each other. |

---

## 15. Appendix: API Reference

### 15.1 C-Linkage Functions (for QBE-Emitted Code)

| Function | Signature | Description |
|----------|-----------|-------------|
| `samm_init` | `void samm_init(void)` | Initialise SAMM singleton, start background worker |
| `samm_shutdown` | `void samm_shutdown(void)` | Drain queues, stop worker, print metrics |
| `samm_enter_scope` | `void samm_enter_scope(void)` | Push new scope onto scope stack |
| `samm_exit_scope` | `void samm_exit_scope(void)` | Pop scope, queue allocations for cleanup |
| `samm_alloc_object` | `void* samm_alloc_object(size_t size)` | Allocate and zero-fill object memory |
| `samm_free_object` | `void samm_free_object(void* ptr)` | Free object (with Bloom filter tracking) |
| `samm_track` | `void samm_track(void* ptr)` | Track pointer in current scope |
| `samm_retain` | `void samm_retain(void* ptr, int offset)` | Move pointer to ancestor scope |
| `samm_retain_parent` | `void samm_retain_parent(void* ptr)` | Shorthand: retain to parent scope |
| `samm_is_probably_freed` | `int samm_is_probably_freed(void* ptr)` | Bloom filter query |
| `samm_scope_depth` | `int samm_scope_depth(void)` | Current scope nesting depth |
| `samm_print_stats` | `void samm_print_stats(void)` | Dump metrics to stderr |
| `samm_wait` | `void samm_wait(void)` | Block until all cleanup completes |

### 15.2 HeapManager Internal Methods (C++ Only)

| Method | Description |
|--------|-------------|
| `getInstance()` | Singleton access |
| `allocObject(size)` | Allocate object memory (calloc semantics) |
| `free(ptr)` | Free and track in Bloom filter |
| `enterScope()` | Push scope vector |
| `exitScope()` | Pop scope, queue for background cleanup |
| `retainPointer(ptr, offset)` | Move pointer between scope vectors |
| `trackInCurrentScope(ptr)` | Add pointer to current scope's tracking vector |
| `shutdown()` | Drain all queues, join worker thread |
| `getSAMMStats()` | Return diagnostic counters |

### 15.3 Object Memory Layout (Unchanged)

```
Offset  Size  Content
------  ----  ---------------------------
0       8     vtable pointer
8       8     class_id (int64)
16      ...   fields (inherited first, then own)
```

SAMM does not add any per-object header overhead. The tracking is external (scope
vectors and Bloom filter), preserving the existing compact object layout.

### 15.4 QBE Runtime Function Declarations

```qbe
# SAMM runtime functions (declared in QBE IL preamble)
function $samm_init()
function $samm_shutdown()
function $samm_enter_scope()
function $samm_exit_scope()
function l $samm_alloc_object(l)
function $samm_free_object(l)
function $samm_track(l)
function $samm_retain_parent(l)
function $samm_retain(l, w)
```

---

## Summary

Integrating SAMM into FasterBASIC gives the CLASS system a production-quality memory
manager with scope-based automatic cleanup, double-free protection, background
reclamation, and detailed diagnostics — all without garbage collection overhead. The
integration is incremental (opt-in Phase 1), backward-compatible, and maps cleanly
onto BASIC's natural lexical scope structure.

The SAMM system from NBCPL is already proven, well-tested, and designed for exactly
this use case. Adapting it for FasterBASIC requires removing only NBCPL-specific
features (graphics resources, BCPL-specific stats) while **keeping list support intact**
for future use. The integration adds a thin C-linkage bridge layer — roughly 25 hours
of work for the MVP.

**Recommendation**: Proceed with Phase 1 implementation. The immediate wins are:
1. No more silent leaks from CLASS objects in SUBs/FUNCTIONs
2. Safe DELETE with double-free detection
3. Background cleanup for better responsiveness
4. Diagnostic metrics for debugging memory issues

These benefits directly address the most pressing pain points in the CLASS implementation.
The roadmap then extends naturally: **objects → strings → lists**, with each phase
building on the SAMM infrastructure from the previous one. Keeping list support in
SAMM from day one means Phase 4 (lists) inherits a battle-tested freelist and
scope-cleanup mechanism with zero rework.