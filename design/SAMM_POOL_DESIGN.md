# SAMM Pool-Based Memory Management — Design Document

**Date:** February 2025
**Status:** Proposed
**Author:** Design session notes

---

## 1. Problem Statement

SAMM (Scope-Aware Memory Management) currently wraps `malloc`/`calloc`/`free` with
scope tracking, a background cleanup worker, and a Bloom filter for double-free
detection. Despite all this machinery, **SAMM does not actually manage memory**.
Every allocation goes straight to the system allocator, and every deallocation
returns memory to the system allocator.

This creates three concrete problems:

### 1.1 Bloom Filter False Positives (Address Reuse)

When SAMM calls `free(ptr)`, the system allocator is free to return that same
address from the next `malloc`. SAMM's Bloom filter still has the old address
recorded as "freed," so when the program `DELETE`s the new object at the same
address, the Bloom filter incorrectly flags it as a double-free.

This was caught by the stress tests: a tight `NEW`/`DELETE` loop in a FOR loop
produced hundreds of false "double-free" warnings because `malloc` reused the
same 32-byte block on every iteration.

The workaround (check scope tracking before consulting the Bloom filter) is
fragile and adds complexity. The root cause is that SAMM doesn't own the
address space.

### 1.2 Performance Left on the Table

Every object allocation hits the system allocator's locks, free-list searches,
and bookkeeping. For a BASIC program that creates and destroys thousands of
small objects per second (loop-scoped temporaries, string descriptors, list
atoms), this is unnecessary overhead. A slab pool with a per-type free list
gives O(1) alloc and O(1) free with no locks needed for single-threaded
allocation (only the background cleanup worker needs synchronization).

### 1.3 Heap Fragmentation

Thousands of small, short-lived allocations scattered across the heap cause
fragmentation. Pool-allocated objects live in contiguous slabs, improving
cache locality and reducing fragmentation.

---

## 2. Current Architecture

```
                    BASIC Program
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
     class_object_new()      string_new_*()
              │                     │
              ▼                     ▼
     samm_alloc_object()     samm_alloc_string()
              │                     │
              ▼                     ▼
          calloc()              calloc()          ← system allocator
              │                     │
              ▼                     ▼
     samm_track_object()     samm_track_string()
              │                     │
              ▼                     ▼
         SAMMScope tracking arrays
              │
              ▼  (on scope exit)
     cleanup_batch() → free()                     ← system allocator
```

**Allocation types tracked by SAMM today:**

| Type                | Size        | Frequency    | Current Allocator |
|---------------------|-------------|--------------|-------------------|
| `SAMM_ALLOC_OBJECT` | 16–512 B    | High         | `calloc`          |
| `SAMM_ALLOC_STRING` | 40 B (fixed)| Very High    | `calloc`          |
| `SAMM_ALLOC_LIST`   | 40 B (fixed)| Medium       | `malloc`          |
| `SAMM_ALLOC_LIST_ATOM` | 24 B (fixed) | High    | `malloc`          |

Note: string **data** buffers (the actual characters) and UTF-8 caches are
variable-size and allocated separately. These remain on the system allocator
and are **not** tracked by SAMM — they are owned by the descriptor and freed
when the descriptor is released.

---

## 3. Proposed Architecture

```
                    BASIC Program
                         │
              ┌──────────┴──────────┐
              ▼                     ▼
     class_object_new()      string_new_*()
              │                     │
              ▼                     ▼
     samm_alloc_object(sz)   samm_alloc_string()
              │                     │
              ▼                     ▼
     ObjectPool (size-class)  StringPool (fixed-size slab)
              │                     │
              ▼                     ▼
     samm_track_object()     samm_track_string()
              │                     │
              ▼                     ▼
         SAMMScope tracking arrays
              │
              ▼  (on scope exit)
     cleanup_batch() → return to pool free list
```

### 3.1 Design Principles

1. **SAMM owns the address space.** Pool-allocated addresses are never returned
   to the system allocator during normal operation. They go back to the pool's
   free list. This eliminates the Bloom filter false-positive problem entirely.

2. **Fixed-size types get dedicated slab pools.** StringDescriptor (40 B),
   ListHeader (40 B), and ListAtom (24 B) are fixed-size structures. Each gets
   its own slab allocator with a free list — O(1) alloc, O(1) free.

3. **Class objects get a size-class pool.** Object sizes vary by class but are
   fixed at compile time. A small set of size classes (32, 64, 128, 256, 512,
   1024 bytes) covers the range. Each size class is its own slab pool.

4. **Variable-size data stays on malloc.** String data buffers, UTF-8 caches,
   and any other variable-size allocations remain on the system allocator.
   SAMM doesn't track these — they are owned by their parent descriptor and
   freed when the descriptor is released.

5. **Slabs grow on demand, never shrink during execution.** New slabs are
   allocated from the system when a pool runs out. Slabs are only freed at
   `samm_shutdown()`. This is the right trade-off for a program that runs to
   completion — we trade peak memory for allocation speed and simplicity.

6. **Thread safety via the existing model.** Allocation happens on the main
   thread (single-threaded BASIC). Deallocation (cleanup) happens on the
   background worker thread. The pool free list needs a lock (or lock-free
   push) only when the worker returns objects. The main thread's allocation
   path can be lock-free if we use a dual-list (main thread pops from one
   list, worker pushes to another, periodic merge).

---

## 4. Pool Design Details

### 4.1 Slab Allocator (for fixed-size types)

A slab is a contiguous block of memory divided into N equally-sized slots.

```
┌─────────────────────────────────────────────────┐
│  Slab Header  │ Slot 0 │ Slot 1 │ ... │ Slot N │
│  (next ptr,   │ 40 B   │ 40 B   │     │ 40 B   │
│   count)      │        │        │     │        │
└─────────────────────────────────────────────────┘
```

**Slab parameters:**

| Pool              | Slot Size | Slots/Slab | Slab Size  | Notes                    |
|-------------------|-----------|------------|------------|--------------------------|
| StringDescriptor  | 40 B      | 256        | ~10 KB     | Already designed          |
| ListHeader        | 40 B      | 256        | ~10 KB     |                          |
| ListAtom          | 24 B      | 512        | ~12 KB     | Higher count (more atoms) |

**Free list:** Each free slot's first 8 bytes store a pointer to the next free
slot (intrusive linked list). Since the slot is not in use, repurposing its
memory for the link is safe. The existing `string_pool.c` already does this
(it stores the next pointer in the `data` field of the descriptor).

**Allocation:** Pop from free list head. If empty, allocate a new slab from
the system, thread all its slots onto the free list, then pop.

**Deallocation:** Push onto free list head. The descriptor's data buffers
(string contents, utf8 cache) are freed via `free()` first — only the
fixed-size descriptor shell goes back to the pool.

### 4.2 Size-Class Pool (for class objects)

Class objects vary in size depending on the number of fields, but each class
has a fixed size known at compile time. We round up to the nearest size class.

**Size classes:**

| Class | Slot Size | Covers object sizes | Typical use                    |
|-------|-----------|---------------------|--------------------------------|
| 0     | 32 B      | 17–32 B             | Header-only (no fields)        |
| 1     | 64 B      | 33–64 B             | 1–6 fields                     |
| 2     | 128 B     | 65–128 B            | 7–14 fields                    |
| 3     | 256 B     | 129–256 B           | 15–30 fields                   |
| 4     | 512 B     | 257–512 B           | Large objects                  |
| 5     | 1024 B    | 513–1024 B          | Very large objects             |
| 6     | overflow  | > 1024 B            | Falls back to malloc           |

Each size class is a slab pool with 128 slots per slab.

**Size class lookup:** Given an allocation request of `size` bytes:

```c
static inline int size_to_class(size_t size) {
    if (size <= 32)   return 0;
    if (size <= 64)   return 1;
    if (size <= 128)  return 2;
    if (size <= 256)  return 3;
    if (size <= 512)  return 4;
    if (size <= 1024) return 5;
    return -1;  // overflow → malloc
}
```

**Cleanup:** The background worker calls the destructor (via vtable[3]) then
returns the slot to the correct size class's free list. The worker must know
which size class a pointer belongs to. Two options:

- **Option A (recommended):** Store the size class index in the SAMMScope
  tracking array alongside the pointer and type. This adds 1 byte per tracked
  pointer — negligible. The `SAMMScope` struct becomes:

  ```c
  typedef struct {
      void**        ptrs;
      SAMMAllocType* types;
      uint8_t*      size_classes;   // NEW: pool size class (0–5, or 0xFF for malloc)
      size_t        count;
      size_t        capacity;
  } SAMMScope;
  ```

- **Option B:** Determine the size class from the pointer address by checking
  which slab it falls within. This is how production allocators work (e.g.,
  jemalloc uses page alignment). More complex to implement but zero per-pointer
  overhead.

Option A is simpler, correct, and the overhead (1 byte per tracked pointer)
is negligible. Recommend starting with Option A.

### 4.3 What Stays on malloc

These allocations are **not** pooled:

- **String data buffers** (`str->data`): Variable size, frequently reallocated
  (e.g., concat grows the buffer). Owned by the descriptor, freed when the
  descriptor is released.

- **UTF-8 caches** (`str->utf8_cache`): Variable size, lazily allocated,
  invalidated on mutation. Owned by the descriptor.

- **SAMMScope tracking arrays** (`ptrs`, `types`, `size_classes`): These are
  SAMM's own internal bookkeeping, not user objects. They grow geometrically
  and are freed when the scope exits.

- **Cleanup batch arrays**: Internal to the cleanup queue.

- **Overflow objects** (> 1024 bytes): Rare. Fall back to system allocator.
  Tracked with `size_class = 0xFF` to indicate "not pooled."

---

## 5. Bloom Filter Impact

With pool-based allocation, the Bloom filter's false-positive problem is
**eliminated** for pooled types:

- A pool address that has been returned to the free list will never be
  returned by `malloc` for a different purpose. If SAMM sees it again, it's
  either a legitimate reuse from the pool (in which case it's tracked in a
  scope and the Bloom filter is not consulted) or a genuine double-free.

- The Bloom filter remains useful for overflow objects (> 1024 B) that still
  use `malloc`, and as a secondary safety net.

- Long term, the Bloom filter could be removed entirely once all allocation
  types are pooled. The pool's own free-list membership is a perfect
  "is this freed?" check.

---

## 6. Integration Points

### 6.1 `samm_init()` / `samm_shutdown()`

```c
void samm_init(void) {
    // ... existing init ...
    string_pool_init(&g_samm.string_pool);
    list_header_pool_init(&g_samm.list_header_pool);
    list_atom_pool_init(&g_samm.list_atom_pool);
    object_pool_init(&g_samm.object_pool);  // inits all 6 size classes
}

void samm_shutdown(void) {
    // ... existing shutdown (drain queue, join worker) ...
    string_pool_cleanup(&g_samm.string_pool);
    list_header_pool_cleanup(&g_samm.list_header_pool);
    list_atom_pool_cleanup(&g_samm.list_atom_pool);
    object_pool_cleanup(&g_samm.object_pool);
}
```

### 6.2 `samm_alloc_string()`

```c
void* samm_alloc_string(void) {
    // BEFORE: calloc(1, sizeof(StringDescriptor))
    // AFTER:
    StringDescriptor* desc = string_pool_alloc(&g_samm.string_pool);
    if (!desc) return NULL;
    desc->refcount = 1;
    desc->dirty    = 1;
    if (g_samm.enabled) {
        samm_track_string(desc);
    }
    return desc;
}
```

### 6.3 `samm_alloc_object(size)`

```c
void* samm_alloc_object(size_t size) {
    int sc = size_to_class(size);
    void* ptr;
    if (sc >= 0) {
        ptr = object_pool_alloc(&g_samm.object_pool, sc);
    } else {
        ptr = calloc(1, size);  // overflow
    }
    if (ptr) {
        SAMM_ATOMIC_INC(g_samm.stat_objects_allocated);
    }
    return ptr;
}
```

### 6.4 `samm_track()` — extended with size class

```c
void samm_track(void* ptr, SAMMAllocType type, uint8_t size_class) {
    // ... existing lock + scope_push ...
    // scope_push now also stores size_class
}
```

The `class_object_new` call site passes the size class:

```c
uint8_t sc = (uint8_t)size_to_class((size_t)object_size);
if (sc < 0) sc = 0xFF;
samm_track(obj, SAMM_ALLOC_OBJECT, sc);
```

String and list callers pass `0` (irrelevant for fixed-size pools).

### 6.5 `string_release()` — return to pool instead of `free(desc)`

```c
void string_release(StringDescriptor* str) {
    if (!str) return;
    str->refcount--;
    if (str->refcount <= 0) {
        samm_untrack(str);
        if (str->data)       free(str->data);        // data buffer → system
        if (str->utf8_cache) free(str->utf8_cache);   // utf8 cache → system
        string_pool_free(&g_samm.string_pool, str);   // descriptor → pool
    }
}
```

### 6.6 `cleanup_batch()` — return to pools instead of `free(ptr)`

```c
case SAMM_ALLOC_OBJECT:
    default_object_cleanup(ptr);    // calls destructor
    // BEFORE: free(ptr) was inside default_object_cleanup
    // AFTER:  return to pool
    if (size_class != 0xFF) {
        object_pool_free(&g_samm.object_pool, size_class, ptr);
    } else {
        free(ptr);
    }
    break;

case SAMM_ALLOC_STRING:
    string_release((StringDescriptor*)ptr);
    // string_release already returns descriptor to pool
    break;

case SAMM_ALLOC_LIST:
    list_free_internal(ptr);        // frees atoms + their payloads
    list_header_pool_free(&g_samm.list_header_pool, ptr);
    break;

case SAMM_ALLOC_LIST_ATOM:
    list_atom_release_payload(ptr); // release string/nested list payload
    list_atom_pool_free(&g_samm.list_atom_pool, ptr);
    break;
```

### 6.7 `default_object_cleanup()` — no longer calls `free()`

```c
static void default_object_cleanup(void* ptr) {
    if (!ptr) return;
    void** vtable = (void**)((void**)ptr)[0];
    if (vtable) {
        void* dtor_ptr = ((void**)vtable)[3];
        if (dtor_ptr) {
            typedef void (*dtor_fn)(void*);
            ((dtor_fn)dtor_ptr)(ptr);
        }
    }
    // NOTE: do NOT free(ptr) here — caller returns it to the pool
}
```

---

## 7. Memory Layout Summary

After the change, memory ownership looks like this:

```
┌─────────────────────────────────────────────────────────────┐
│                    System Allocator (malloc)                 │
│                                                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐      │
│  │ String Data   │  │ UTF-8 Caches │  │ Overflow Obj │      │
│  │ Buffers       │  │              │  │ (> 1024 B)   │      │
│  │ (var size)    │  │ (var size)   │  │              │      │
│  └──────────────┘  └──────────────┘  └──────────────┘      │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              SAMM Pool Slabs (bulk malloc)            │   │
│  │                                                      │   │
│  │  ┌────────────┐ ┌────────────┐ ┌────────────┐       │   │
│  │  │StringPool  │ │ListHdrPool │ │ListAtomPool│       │   │
│  │  │Slab → Slab │ │Slab → Slab │ │Slab → Slab │       │   │
│  │  │40B × 256   │ │40B × 256   │ │24B × 512   │       │   │
│  │  └────────────┘ └────────────┘ └────────────┘       │   │
│  │                                                      │   │
│  │  ┌──────────────────────────────────────────┐        │   │
│  │  │         Object Size-Class Pools          │        │   │
│  │  │  SC0: 32B × 128  │  SC1: 64B × 128      │        │   │
│  │  │  SC2: 128B × 128 │  SC3: 256B × 128     │        │   │
│  │  │  SC4: 512B × 64  │  SC5: 1024B × 32     │        │   │
│  │  └──────────────────────────────────────────┘        │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │         SAMM Internal Bookkeeping                     │   │
│  │  Scope tracking arrays, cleanup queue, Bloom filter   │   │
│  └──────────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────┘
```

---

## 8. Thread Safety

**Main thread (allocation):**

- `samm_alloc_string()` → pops from string pool free list
- `samm_alloc_object()` → pops from size-class free list
- These only run on the main thread (BASIC is single-threaded)

**Worker thread (deallocation):**

- `cleanup_batch()` → pushes freed slots back to pool free lists
- Runs on the background worker thread

**Contention point:** The pool free list is accessed by both threads. Options:

1. **Simple mutex per pool** — low contention since the worker processes
   batches (amortized lock cost). This is the simplest correct approach.

2. **Lock-free MPSC queue** — the worker pushes (single producer of freed
   objects per batch), the main thread pops (single consumer). More complex
   but avoids locks entirely on the allocation hot path.

3. **Dual free lists** — the main thread pops from a "hot" list, the worker
   pushes to a "cold" list. Periodically (or when the hot list is empty),
   swap the lists under a lock. This gives lock-free allocation in the common
   case.

**Recommendation:** Start with option 1 (mutex per pool). Profile. If lock
contention shows up, move to option 3. Option 2 is overkill for a BASIC
runtime.

---

## 9. Migration Plan

The migration should be incremental. Each step is independently testable and
committable.

### Phase 1: String Descriptor Pool (Low Risk)

Wire the existing `string_pool.c` into SAMM. This is the lowest-risk change
because the pool code already exists and is tested.

1. Add `StringDescriptorPool` to `SAMMState`
2. Init/cleanup in `samm_init()` / `samm_shutdown()`
3. `samm_alloc_string()` → `string_pool_alloc()` instead of `calloc`
4. `string_release()` → `string_pool_free()` instead of `free(desc)`
5. `cleanup_batch()` string case → `string_pool_free()` after releasing data
6. Run stress tests, verify no warnings, no leaks

### Phase 2: List Pools (Low Risk) — ✅ COMPLETE

Implemented a generic `SammSlabPool` (type-agnostic, parameterized by
`slot_size` and `slots_per_slab`) and instantiated it for both list types.
This also provides the reusable pool infrastructure for Phase 3 (object
size-class pools) — Phase 5's "generic slab pool" was pulled forward.

**Files created:**
- `samm_pool.h` — `SammSlabPool` type, API, global pool instances
- `samm_pool.c` — slab allocator, intrusive free-list, mutex, stats,
  validation, leak detection

**Files modified:**
- `samm_core.c` — pool init/destroy in `samm_init()`/`samm_shutdown()`,
  `samm_alloc_list()` and `samm_alloc_list_atom()` now use pool,
  `cleanup_batch()` comments updated, pool stats printed at shutdown
- `list_ops.c` — `atom_alloc()` uses `samm_alloc_list_atom()` (pool),
  `atom_free()` returns to pool, `list_create()` uses `samm_alloc_list()`
  (pool), `list_free()` returns header to pool + added `samm_untrack()`
  to prevent double-free on scope exit, all `list_shift_*`/`list_pop_*`
  functions return atoms to pool, `list_free_from_samm()` and
  `list_atom_free_from_samm()` return to pool, `list_clear()` returns
  atoms to pool (via `atom_free`)
- `main.c` — added `samm_pool.c` to `runtime_files[]`

**Pool configuration:**
- ListHeader: 32-byte slots, 256 slots/slab (~8 KB)
- ListAtom:   24-byte slots, 512 slots/slab (~12 KB)
- Intrusive free-list via `void*` overlay at slot start (generic, not
  type-specific like string pool's `data` pointer trick)

**Safety fix discovered during implementation:**
- `list_free()` was missing `samm_untrack()` — the header remained in
  SAMM's scope array after explicit free, risking double-free when the
  scope exited. With pools this is critical because the recycled slot
  could already be reused for a new list. Added untrack before pool return.

**Test results:**
- 264/269 tests pass (5 failures are pre-existing, unrelated)
- All list tests pass: `test_list_basic`, `test_list_advanced`,
  `test_list_int_minimal`, `test_list_string_minimal`
- Volume stress test: 14/14 pass, zero double-free catches
- New list pool stress test (`test_samm_stress_list_pool.bas`): 10/10 pass
  - 35,720 objects cleaned, 928,656 bytes freed, zero double-free catches
  - Tests cover: create/destroy churn (2000 lists), append/shift-all (500),
    append/pop cycling (50×100), string list churn (1000), nested lists (200),
    copy/reverse churn (100×100), extend churn (100×50), prepend/shift storm
    (1000), 10 simultaneous lists (100 each), insert/remove mid-list (500)

**Steps completed:**
1. ✅ Created generic `SammSlabPool` parameterized by slot size
2. ✅ Wired into `samm_alloc_list()`, `samm_alloc_list_atom()`
3. ✅ Updated `list_free_from_samm()` and `list_atom_free_from_samm()`
4. ✅ Updated all explicit free paths (`atom_free`, `list_free`,
   `list_shift_*`, `list_pop_*`, `list_clear`, `list_remove`)
5. ✅ Added byte accounting (`samm_record_bytes_freed`) at all free sites
6. ✅ Ran list tests + stress tests — all pass
7. ✅ Synced to `qbe_basic_integrated/runtime/`

### Phase 3: Object Size-Class Pool (Medium Risk)

This is the most complex change because object sizes vary.

1. Implement size-class pool with 6 classes
2. Extend `SAMMScope` with `size_classes` array
3. Extend `samm_track()` signature to accept size class
4. Update `samm_alloc_object()` to use pool
5. Update `default_object_cleanup()` to not call `free()`
6. Update `cleanup_batch()` to return to pool
7. Update `class_object_new()` to pass size class to tracking
8. Run full test suite + stress tests

### Phase 4: Bloom Filter Cleanup (Low Risk)

Once all types are pooled:

1. The Bloom filter is now only needed for overflow objects (> 1024 B)
2. Consider removing it entirely — pool membership is a perfect freed check
3. Or keep it as a lightweight safety net with reduced size (much smaller
   bit array since it only needs to handle overflow objects)

### Phase 5: Generalize to Generic Slab Pool (Optional) — ✅ PULLED FORWARD

**Implemented during Phase 2.** The generic `SammSlabPool` type was created
as part of Phase 2 (list pools) rather than deferred to Phase 5, because
the implementation cost was the same and it provides the reusable foundation
for Phase 3 (object size-class pools).

The string pool (`string_pool.c`) remains its own separate implementation
for now (it predates the generic pool and uses type-specific tricks like
the `data` pointer as free-list link). It could be migrated to
`SammSlabPool` in a future cleanup pass, but this is cosmetic — both
implementations are functionally equivalent.

Original design (preserved for reference):
Factor out the common slab pool logic into a reusable `SammSlabPool` type
parameterized by slot size and slots-per-slab. The string, list header, list
atom, and each object size-class pool all become instances of the same
generic pool. This reduces code duplication significantly.

```c
typedef struct SammSlab SammSlab;
struct SammSlab {
    SammSlab* next;
    uint32_t  slot_size;
    uint32_t  slot_count;
    uint32_t  used_count;
    uint8_t   data[];       // flexible array of slot_count × slot_size bytes
};

typedef struct {
    void*       free_list;      // intrusive linked list of free slots
    SammSlab*   slabs;          // chain of slabs
    uint32_t    slot_size;      // bytes per slot
    uint32_t    slots_per_slab; // slots per slab allocation
    size_t      total_allocs;
    size_t      total_frees;
    size_t      total_capacity;
    size_t      in_use;
    size_t      peak_use;
    pthread_mutex_t lock;       // for worker thread safety
} SammSlabPool;

void  samm_slab_pool_init(SammSlabPool* pool, uint32_t slot_size, uint32_t slots_per_slab);
void  samm_slab_pool_destroy(SammSlabPool* pool);
void* samm_slab_pool_alloc(SammSlabPool* pool);
void  samm_slab_pool_free(SammSlabPool* pool, void* ptr);
void  samm_slab_pool_stats(const SammSlabPool* pool, ...);
```

Then:

```c
typedef struct {
    // ... existing SAMMState fields ...

    SammSlabPool  string_pool;       // 40-byte slots
    SammSlabPool  list_header_pool;  // 40-byte slots
    SammSlabPool  list_atom_pool;    // 24-byte slots
    SammSlabPool  object_pools[6];   // 32, 64, 128, 256, 512, 1024-byte slots
} SAMMState;
```

---

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|------|--------|------------|
| Pool slot too small for an object | Heap corruption | `size_to_class()` rounds up; overflow (>1024) falls back to malloc |
| Memory not zeroed | Stale field values | `samm_slab_pool_alloc()` calls `memset(slot, 0, slot_size)` before returning |
| Worker returns to wrong pool | Corruption | Size class stored in scope tracking array, validated at cleanup |
| Slabs never freed → high water mark | Memory waste | Acceptable for batch programs; add `pool_compact()` for long-running use |
| Thread race on free list | Corruption | Mutex per pool (simple, low contention) |
| String pool `free_list` uses `data` pointer | Aliasing concern | Only when descriptor is not in use; `data` is reset on alloc. Existing code already does this. |

---

## 11. Performance Expectations

### Allocation

| Operation | Before (malloc) | After (pool) | Speedup |
|-----------|-----------------|--------------|---------|
| String descriptor alloc | ~50–200 ns | ~5–10 ns | 10–20× |
| Object alloc (small) | ~50–200 ns | ~5–10 ns | 10–20× |
| List atom alloc | ~50–200 ns | ~5–10 ns | 10–20× |

(Pool alloc = pop from free list + memset. No lock needed on main thread
with dual-list approach.)

### Deallocation

| Operation | Before (free) | After (pool) | Speedup |
|-----------|---------------|--------------|---------|
| Descriptor return to pool | ~30–100 ns | ~3–5 ns | 10–20× |

(Pool free = push to free list. Lock needed only on worker thread.)

### Cache Locality

Slab-allocated objects are contiguous in memory. Iterating over a list of
string descriptors hits the same cache lines instead of bouncing across
the heap. This is hard to quantify but typically yields 2–5× improvement
on tight loops that touch many small objects.

### Memory Overhead

Each slab pool pre-allocates one slab:

- String pool: 256 × 40 B = 10 KB
- List header pool: 256 × 40 B = 10 KB
- List atom pool: 512 × 24 B = 12 KB
- Object pools (6): ~100 KB total for initial slabs

**Total initial overhead: ~132 KB.** Negligible.

---

## 12. Existing Code to Reuse

- **`string_pool.c` / `string_pool.h`**: Fully implemented slab pool for
  StringDescriptor. Currently unused. Wire it in for Phase 1.

- **`SAMMAllocType` enum**: Already distinguishes objects, strings, lists,
  list atoms. Extend with size-class info.

- **`cleanup_batch()` switch statement**: Already dispatches by type. Just
  change the free path from `free()` to pool return.

- **`samm_alloc_string()`**: Already exists as the single allocation point
  for string descriptors (consolidated in the recent refactor). Just swap
  the calloc for a pool alloc.

---

## 13. Open Questions

1. **Should we pool string data buffers too?** String contents vary widely
   in size (1 byte to megabytes). A size-class pool for data buffers would
   reduce malloc pressure further but adds complexity. Recommend deferring
   to a future phase and profiling first.

2. **Should the Bloom filter be removed entirely?** Once all types are
   pooled, the Bloom filter is redundant for pooled types. It's 12 MB of
   memory. Removing it saves memory and simplifies the code. But it's a
   useful safety net during development. Recommend keeping it through the
   migration, then removing in Phase 4.

3. **Should pools be global or per-scope?** Global pools (proposed) are
   simpler and amortize slab allocation. Per-scope pools would allow
   bulk-freeing an entire scope's allocations by resetting the pool, but
   would waste memory (each scope pre-allocates slabs). Recommend global.

4. **What about BASIC arrays?** Array descriptors and array data are
   currently allocated with malloc and not tracked by SAMM at all. This
   is a separate concern and out of scope for this design.

5. **Concurrency model for long-running BASIC programs?** The current
   "slabs never shrink" policy is fine for batch programs but could be
   a problem for a long-running interactive program that has a spike of
   allocations and then settles down. The `pool_compact()` function
   (described in Phase 5) addresses this.

---

## 14. Fixed-Size Structure Audit

**Date:** February 2025
**Platform:** macOS ARM64 (Apple Silicon)

All sizes verified at compile time with `sizeof` / `_Alignof`.

### 14.1 Structure Inventory

| Structure | Size | Align | SAMM Tracked | Alloc Type | Current Allocator | Alloc Frequency | Freelist Candidate |
|-----------|------|-------|-------------|------------|-------------------|-----------------|-------------------|
| **StringDescriptor** | 40 B | 8 | ✅ `SAMM_ALLOC_STRING` | `calloc` via `samm_alloc_string()` | system | Very High | ✅ **Pool code exists, not wired in** |
| **ListAtom** | 24 B | 8 | ✅ `SAMM_ALLOC_LIST_ATOM` | `malloc` in `atom_alloc()` | system | High | ✅ |
| **ListHeader** | 32 B | 8 | ✅ `SAMM_ALLOC_LIST` | `malloc` in `list_create()` | system | Medium | ✅ |
| **Class objects** | 16–1024+ B | 8 | ✅ `SAMM_ALLOC_OBJECT` | `calloc` via `samm_alloc_object()` | system | High | ✅ Size-class pools |
| ArrayDescriptor | 64 B | 8 | ❌ | Various (inline/stack) | system | Medium | Deferred |
| ExceptionContext | 216 B | 8 | ❌ | `malloc` in `basic_exception_push()` | system | Low | No — not worth it |
| BasicString (legacy) | 32 B | 8 | ❌ | `malloc` in `str_new()` | system | Low | No — legacy path |
| BasicArray (legacy) | 48 B | 8 | ❌ | `malloc` in `array_new()` | system | Low | No — legacy path |
| BasicFile | 40 B | 8 | ❌ | `malloc` | system | Very Low | No — few files open |

### 14.2 Intrusive Free-List Viability

Each free-list slot must be at least 8 bytes (one pointer) to store the
intrusive next-link when the slot is not in use. All candidates exceed this:

| Structure | Size | ≥ 8 B? | Free-list link strategy |
|-----------|------|--------|------------------------|
| StringDescriptor | 40 B | ✅ | Reuse `data` pointer (existing `string_pool.c` already does this) |
| ListAtom | 24 B | ✅ | Reuse `next` pointer (natural — already a linked-list node) |
| ListHeader | 32 B | ✅ | Reuse `head` pointer |
| Class objects | 16+ B | ✅ | Reuse first 8 bytes (vtable pointer slot) |

### 14.3 Current Allocation / Free Paths

All four SAMM-tracked types currently round-trip through the **system
allocator** on both sides:

```
Allocation path:
  calloc/malloc → samm_track() → SAMMScope

Explicit free (DELETE):
  samm_free_object() → untrack from scope → bloom_add() → free()

Scope-exit free (automatic):
  samm_exit_scope() → enqueue batch → cleanup_batch()
    → type-specific cleanup (destructor / string_release / list_free) → free()
```

All four types share the same Bloom-filter false-positive vulnerability:
`free()` returns an address to the system, `malloc` immediately reuses it
for a new tracked allocation, and the Bloom filter incorrectly flags the
new allocation as a double-free. The current workaround (untrack first,
check Bloom only if not tracked) is fragile. Pool ownership eliminates
the problem entirely.

### 14.4 Per-Type Analysis

#### StringDescriptor (40 B) — Phase 1 (pool code exists)

**Allocation point:** `samm_alloc_string()` in `samm_core.c:991–1003`

```c
void* samm_alloc_string(void) {
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    desc->refcount = 1;
    desc->dirty    = 1;
    if (g_samm.enabled) {
        samm_track_string(desc);
    }
    return desc;
}
```

All leaf string creators (`string_new_ascii`, `string_new_utf8`,
`string_new_utf32`, `string_new_capacity`, `string_new_repeat`, etc.)
route through `alloc_descriptor()` → `samm_alloc_string()`.

**Free points:**

1. `string_release()` in `string_utf32.c:454–474` — explicit release when
   refcount hits 0. Calls `samm_untrack(str)`, frees `data` + `utf8_cache`
   buffers, then `free(str)`. The final `free(str)` is the descriptor shell
   free — swap for `string_pool_free()`.

2. `cleanup_batch()` in `samm_core.c:345–349` — scope-exit path. Calls
   `string_release()` which handles the descriptor free.

**Pool code:** `string_pool.c` / `string_pool.h` — slab allocator with
256 descriptors per slab (~10 KB), intrusive free list via `data` pointer.
Global pool instance `g_string_pool`. Complete but **not called anywhere**.

**Wiring required:**
- `samm_init()`: call `string_pool_init(&g_string_pool)`
- `samm_shutdown()`: call `string_pool_cleanup(&g_string_pool)`
- `samm_alloc_string()`: replace `calloc` with `string_pool_alloc(&g_string_pool)`
- `string_release()`: replace `free(str)` with `string_pool_free(&g_string_pool, str)`

#### ListAtom (24 B) — Phase 2

**Allocation point:** `atom_alloc()` in `list_ops.c:37–55` — static helper
called from every `list_append_*`, `list_prepend_*`, `list_insert_*`.
Uses raw `malloc(sizeof(ListAtom))`, then tracks via
`samm_track(atom, SAMM_ALLOC_LIST_ATOM)`.

**Free points:**

1. `atom_free()` in `list_ops.c` — explicit removal (`list_shift`,
   `list_pop`, `list_remove`). Calls `samm_untrack()`, releases payload,
   then `free(atom)`.

2. `list_atom_free_from_samm()` in `list_ops.c:1038–1048` — scope-exit
   path via `cleanup_batch()`. Releases payload, then `free(atom)`.

**Pool needed:** New slab pool, 24-byte slots, 512 slots/slab (~12 KB).
Can use the generic `SammSlabPool` from Phase 5 design, or clone the
`string_pool` pattern parameterized by slot size.

**Free-list link:** Reuse the `next` pointer — it's naturally a linked-list
link and is meaningless when the atom is on the free list.

#### ListHeader (32 B) — Phase 2

**Allocation point:** `list_create()` in `list_ops.c:206–226`. Uses raw
`malloc(sizeof(ListHeader))`, then tracks via `samm_track_list()`.

**Free points:**

1. `list_free()` in `list_ops.c` — explicit `LIST.FREE`. Walks the atom
   chain, frees atoms, then `free(header)`.

2. `list_free_from_samm()` in `list_ops.c:1017–1036` — scope-exit path.
   Zeros the header (does NOT walk atoms — they have their own SAMM
   tracking), then `free(list)`.

**Pool needed:** New slab pool, 32-byte slots, 256 slots/slab (~8 KB).

**Free-list link:** Reuse the `head` pointer.

#### Class Objects (variable size) — Phase 3

**Allocation point:** `class_object_new()` in `class_runtime.c:53–94`.
Calls `samm_alloc_object(object_size)` → `calloc(1, size)`. Then installs
vtable + class_id and tracks via `samm_track_object()`.

**Free points:**

1. `class_object_delete()` in `class_runtime.c` — explicit `DELETE obj`.
   Calls destructor via vtable[3], then `samm_free_object(obj)` → `free()`.

2. `cleanup_batch()` in `samm_core.c:328–330` — scope-exit path. Calls
   `default_object_cleanup()` which runs destructor + `free()`.

**Pool needed:** 6 size-class slab pools (32, 64, 128, 256, 512, 1024 B)
plus overflow to `malloc` for objects > 1024 B.

**Additional bookkeeping:** `SAMMScope` needs a `uint8_t* size_classes`
parallel array so `cleanup_batch()` knows which pool to return the object
to. `default_object_cleanup()` must stop calling `free()` — the caller
handles pool return.

**Free-list link:** Reuse the first 8 bytes (vtable pointer slot).

### 14.5 Structures NOT Pooled (and why)

- **ArrayDescriptor (64 B):** Not currently tracked by SAMM. Arrays are
  typically allocated on the stack or as part of global storage. Adding
  SAMM tracking for arrays is a prerequisite. Defer to a future phase.

- **ExceptionContext (216 B):** Low allocation frequency (one per
  TRY block, typically few active). The 216 B size also makes slab
  overhead less attractive. Not worth pooling.

- **BasicString (32 B):** Legacy string type. All new code uses
  `StringDescriptor`. Will be removed, not pooled.

- **BasicArray (48 B):** Legacy array type. Same situation as BasicString.

- **BasicFile (40 B):** Extremely low frequency (programs open a handful
  of files). Not worth pooling.

### 14.6 Implementation Patterns

Three distinct implementation patterns cover all four pooled types:

1. **Wire existing pool** — StringDescriptor (Phase 1). Pool code in
   `string_pool.c` is complete. Swap 3–4 call sites. Estimated effort:
   small (hours).

2. **Generic fixed-size slab pool** — ListAtom + ListHeader (Phase 2).
   Implement `SammSlabPool` parameterized by `slot_size` and
   `slots_per_slab`. Two instances. Estimated effort: small–medium (1 day).

3. **Size-class slab pool** — Class objects (Phase 3). Six `SammSlabPool`
   instances indexed by size class. Extend `SAMMScope` with
   `size_classes` array. Modify `cleanup_batch()` to dispatch by size
   class. Estimated effort: medium (2–3 days).

### 14.7 Expected Impact

After all four types are pooled:

- **Bloom filter false positives:** Eliminated for all pooled types.
  Pool-owned addresses are never returned to the system allocator during
  normal operation, so `malloc` cannot reuse them.

- **Allocation speed:** 10–20× faster for pooled types (free-list pop +
  memset vs. system allocator lock + free-list search + bookkeeping).

- **Cache locality:** Descriptors and atoms in contiguous slab memory
  instead of scattered across the heap.

- **Memory overhead:** ~132 KB initial (one slab per pool). Negligible.