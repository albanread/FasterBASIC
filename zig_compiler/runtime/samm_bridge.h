/*
 * samm_bridge.h
 * FasterBASIC Runtime — SAMM (Scope Aware Memory Management) Bridge
 *
 * C-linkage API so QBE-emitted code can call SAMM functions.
 * All functions use the samm_ prefix.
 *
 * SAMM provides:
 *   - Scope-based automatic memory reclamation
 *   - Bloom-filter double-free detection
 *   - Background cleanup worker thread
 *   - Typed allocation tracking (objects, strings, lists)
 *   - RETAIN for explicit ownership transfer across scopes
 *
 * Design principles:
 *   - Zero overhead when SAMM is disabled (all calls become no-ops)
 *   - No per-assignment cost (unlike reference counting)
 *   - Deterministic cleanup at scope exit (unlike GC)
 *   - Matches BASIC's natural lexical scope structure
 *
 * Object Memory Layout (unchanged from class_runtime.h):
 *   [0]   vtable pointer  (8 bytes)
 *   [8]   class_id        (8 bytes, int64)
 *   [16]  fields...       (inherited first, then own)
 *
 * SAMM does NOT add any per-object header overhead.
 * Tracking is external (scope vectors + Bloom filter).
 */

#ifndef SAMM_BRIDGE_H
#define SAMM_BRIDGE_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Allocation Types                                                           */
/* ========================================================================= */

typedef enum {
    SAMM_ALLOC_UNKNOWN = 0,
    SAMM_ALLOC_OBJECT,     /* CLASS instance (vtable + fields)     */
    SAMM_ALLOC_STRING,     /* String descriptor (StringDescriptor) */
    SAMM_ALLOC_ARRAY,      /* Dynamic array                        */
    SAMM_ALLOC_LIST,       /* List header (future — Phase 4)       */
    SAMM_ALLOC_LIST_ATOM,  /* List node/atom (future — Phase 4)    */
    SAMM_ALLOC_GENERIC     /* Untyped heap allocation              */
} SAMMAllocType;

/* ========================================================================= */
/* Initialisation & Shutdown                                                  */
/* ========================================================================= */

/**
 * Initialise SAMM. Call once at program start, before any allocations.
 * Creates the singleton state, pushes the global scope, and starts
 * the background cleanup worker thread.
 *
 * Safe to call multiple times — subsequent calls are no-ops.
 */
void samm_init(void);

/**
 * Shutdown SAMM. Call once at program exit, after all scopes have exited.
 * Drains the cleanup queue, stops the background worker, cleans up
 * remaining scopes, and prints metrics if tracing is enabled.
 *
 * Safe to call multiple times — subsequent calls are no-ops.
 */
void samm_shutdown(void);

/* ========================================================================= */
/* Enable / Disable                                                           */
/* ========================================================================= */

/**
 * Enable or disable SAMM at runtime.
 * When disabled, all scope/track/retain calls become no-ops and
 * allocations go through raw calloc/free.
 *
 * @param enabled  Non-zero to enable, zero to disable
 */
void samm_set_enabled(int enabled);

/**
 * Query whether SAMM is currently enabled.
 * @return Non-zero if enabled, zero if disabled
 */
int samm_is_enabled(void);

/* ========================================================================= */
/* Scope Management                                                           */
/*                                                                            */
/* Emitted by codegen at SUB/FUNCTION/METHOD/FOR/WHILE boundaries.            */
/* Every samm_enter_scope() must have a matching samm_exit_scope() on         */
/* every control-flow path (including early RETURN).                          */
/* ========================================================================= */

/**
 * Enter a new lexical scope. Pushes a fresh tracking vector onto the
 * scope stack. All subsequent allocations (via samm_track) are
 * recorded in this scope.
 */
void samm_enter_scope(void);

/**
 * Exit the current lexical scope. Pops the scope's tracking vector
 * and queues all tracked pointers for background cleanup (destructor
 * calls + deallocation). The global scope (depth 0) cannot be exited.
 */
void samm_exit_scope(void);

/**
 * Query the current scope nesting depth.
 * Depth 0 is the global scope. Each samm_enter_scope increments by 1.
 * @return Current scope depth (0 = global)
 */
int samm_scope_depth(void);

/* ========================================================================= */
/* Object Allocation                                                          */
/*                                                                            */
/* These replace raw calloc/free in class_runtime.c.                          */
/* ========================================================================= */

/**
 * Allocate zeroed memory for a CLASS object.
 * Returns calloc'd memory of the given size, suitable for installing
 * a vtable pointer and class_id. Does NOT automatically track the
 * allocation in a scope — call samm_track() after installing the
 * vtable and class_id.
 *
 * @param size  Object size in bytes (must be >= 16)
 * @return Pointer to zeroed memory, or NULL on failure
 */
void* samm_alloc_object(size_t size);

/**
 * Free a previously allocated object. Updates the Bloom filter for
 * double-free detection. The memory is released immediately (not
 * queued for background cleanup — use this only for explicit DELETE).
 *
 * Safe to call with NULL — does nothing.
 *
 * @param ptr  Pointer to the object to free
 */
void samm_free_object(void* ptr);

/* ========================================================================= */
/* Scope Tracking                                                             */
/*                                                                            */
/* After allocating an object (via samm_alloc_object or calloc), call         */
/* samm_track() to register it in the current scope. On scope exit,           */
/* tracked pointers are automatically cleaned up.                             */
/* ========================================================================= */

/**
 * Track a pointer in the current scope. When the scope exits, this
 * pointer will be queued for background cleanup (destructor + free).
 *
 * @param ptr   Pointer to track (NULL is ignored)
 * @param type  Allocation type (determines cleanup strategy)
 */
void samm_track(void* ptr, SAMMAllocType type);

/**
 * Convenience: track a CLASS object in the current scope.
 * Equivalent to samm_track(ptr, SAMM_ALLOC_OBJECT).
 */
void samm_track_object(void* ptr);

/**
 * Untrack a pointer from the current scope (e.g., because the
 * programmer explicitly DELETEd it). Prevents double-free on
 * scope exit.
 *
 * @param ptr  Pointer to untrack (NULL is ignored)
 */
void samm_untrack(void* ptr);

/* ========================================================================= */
/* RETAIN — Ownership Transfer                                                */
/*                                                                            */
/* When an object must outlive its creating scope (e.g., returned from a      */
/* FUNCTION, or assigned to a module-level variable), RETAIN moves the        */
/* pointer from the current scope to an ancestor scope.                       */
/* ========================================================================= */

/**
 * Retain a pointer: move it from the current scope to an ancestor scope.
 *
 * @param ptr             Pointer to retain (NULL is ignored)
 * @param parent_offset   How many scopes up: 1 = parent, 2 = grandparent, etc.
 */
void samm_retain(void* ptr, int parent_offset);

/**
 * Convenience: retain a pointer to the immediate parent scope.
 * Equivalent to samm_retain(ptr, 1).
 * Typically emitted by codegen before a RETURN of a CLASS value.
 */
void samm_retain_parent(void* ptr);

/* ========================================================================= */
/* Double-Free Detection (Bloom Filter)                                       */
/* ========================================================================= */

/**
 * Query the Bloom filter to check if a pointer was recently freed.
 *
 * @param ptr  Pointer to check
 * @return Non-zero if the pointer is probably freed (may be false positive),
 *         zero if the pointer is definitely not in the freed set.
 */
int samm_is_probably_freed(void* ptr);

/* ========================================================================= */
/* List Support (Phase 4 — kept for future use)                               */
/*                                                                            */
/* Lists are the simplest heap collection type. The freelist/ListHeader        */
/* infrastructure from NBCPL is preserved so that when we add LIST types      */
/* to FasterBASIC, the memory management layer is already in place.           */
/* ========================================================================= */

/**
 * Allocate a list header tracked in the current scope.
 * The background worker will return it to the freelist (not raw-free).
 *
 * @return Pointer to a new list header, or NULL if lists are not yet
 *         implemented (Phase 4 stub)
 */
void* samm_alloc_list(void);

/**
 * Track a freelist-allocated list header in the current scope.
 * On scope exit, the background worker calls the list-specific
 * cleanup (return atoms to freelist, then return header to freelist)
 * rather than raw free().
 *
 * @param list_header_ptr  Pointer to the list header
 */
void samm_track_list(void* list_header_ptr);

/**
 * Allocate a list atom (node). Tracked separately from list headers
 * for efficient freelist reuse.
 *
 * @return Pointer to a new list atom, or NULL if not yet implemented
 */
void* samm_alloc_list_atom(void);

/* ========================================================================= */
/* String Tracking                                                            */
/*                                                                            */
/* String descriptors (StringDescriptor*) allocated by the runtime's          */
/* string_new_* / string_concat / string_from_* functions are automatically   */
/* tracked in the current SAMM scope. On scope exit, each tracked string      */
/* receives a string_release() call which decrements the refcount and frees   */
/* the descriptor + its data buffer when the refcount reaches zero.           */
/*                                                                            */
/* If a string must survive its creating scope (e.g., returned from a         */
/* FUNCTION or METHOD), use samm_retain_parent() to move it to the parent     */
/* scope before the current scope exits.                                      */
/* ========================================================================= */

/**
 * Track a string descriptor allocation in the current scope.
 * On scope exit, the cleanup worker calls string_release() which
 * decrements the refcount and frees when it reaches zero.
 *
 * @param string_desc_ptr  Pointer to the StringDescriptor
 */
void samm_track_string(void* string_desc_ptr);

/**
 * Allocate a zeroed StringDescriptor via calloc and automatically
 * track it in the current SAMM scope. The descriptor is initialised
 * with refcount=1 and dirty=1. The caller is responsible for setting
 * encoding, allocating the data buffer, etc.
 *
 * When SAMM is disabled this still allocates but does not track.
 *
 * @return Pointer to a zeroed StringDescriptor, or NULL on failure
 */
void* samm_alloc_string(void);

/* ========================================================================= */
/* Destructor Registration                                                    */
/*                                                                            */
/* SAMM needs to know how to call destructors for CLASS objects during         */
/* background cleanup. The default strategy reads vtable[3] (the destructor   */
/* slot). Custom cleanup functions can be registered for other alloc types.    */
/* ========================================================================= */

/**
 * Destructor/cleanup function signature.
 * @param ptr  Pointer to the object to clean up
 */
typedef void (*samm_cleanup_fn)(void* ptr);

/**
 * Register a custom cleanup function for a given allocation type.
 * This overrides the default cleanup strategy (which is type-specific:
 * objects use vtable[3], strings use string_release, etc.).
 *
 * @param type        Allocation type to register for
 * @param cleanup_fn  Function to call before freeing. NULL to use default.
 */
void samm_register_cleanup(SAMMAllocType type, samm_cleanup_fn cleanup_fn);

/* ========================================================================= */
/* Diagnostics & Metrics                                                      */
/* ========================================================================= */

/**
 * SAMM statistics snapshot.
 */
typedef struct {
    uint64_t scopes_entered;            /* Total samm_enter_scope calls      */
    uint64_t scopes_exited;             /* Total samm_exit_scope calls       */
    uint64_t objects_allocated;         /* Total samm_alloc_object calls     */
    uint64_t objects_freed;             /* Total samm_free_object calls      */
    uint64_t objects_cleaned;           /* Objects cleaned by background wkr */
    uint64_t cleanup_batches;           /* Background cleanup batches run    */
    uint64_t double_free_attempts;      /* Bloom filter double-free catches  */
    uint64_t bloom_false_positives;     /* Estimated Bloom filter FPs       */
    uint64_t retain_calls;              /* Total samm_retain* calls          */
    uint64_t total_bytes_allocated;     /* Cumulative bytes allocated        */
    uint64_t total_bytes_freed;         /* Cumulative bytes freed            */
    uint64_t strings_tracked;           /* Total samm_track_string calls     */
    uint64_t strings_cleaned;           /* Strings cleaned by scope exit     */
    int      current_scope_depth;       /* Current scope nesting depth       */
    int      peak_scope_depth;          /* Maximum scope depth observed      */
    size_t   bloom_memory_bytes;        /* Bloom filter memory usage         */
    double   total_cleanup_time_ms;     /* Total background cleanup time     */
    int      background_worker_active;  /* Non-zero if worker thread running */
} SAMMStats;

/**
 * Get a snapshot of SAMM statistics.
 * @param out_stats  Pointer to struct to fill in
 */
void samm_get_stats(SAMMStats* out_stats);

/**
 * Print SAMM statistics to stderr in a human-readable format.
 */
void samm_print_stats(void);

/**
 * Enable or disable allocation/free tracing to stderr.
 * When enabled, every scope enter/exit, allocation, free, and retain
 * is logged. Useful for debugging but very verbose.
 *
 * @param enabled  Non-zero to enable, zero to disable
 */
void samm_set_trace(int enabled);

/**
 * Block until all queued background cleanup work is complete.
 * Useful before program exit to ensure all destructors have run
 * and diagnostic output is complete.
 */
void samm_wait(void);

/**
 * Record that bytes have been freed (or recycled back to a pool).
 * Called from type-specific release functions (e.g. string_release)
 * that live outside samm_core.c but need to update the byte counters.
 *
 * @param bytes  Number of bytes freed/recycled
 */
void samm_record_bytes_freed(uint64_t bytes);

/* ========================================================================= */
/* Constants                                                                  */
/* ========================================================================= */

/** Maximum scope nesting depth. Exceeding this aborts. */
#define SAMM_MAX_SCOPE_DEPTH        256

/** Initial capacity for per-scope pointer tracking arrays. */
#define SAMM_SCOPE_INITIAL_CAPACITY 32

/** Maximum cleanup queue depth before blocking. */
#define SAMM_MAX_QUEUE_DEPTH        1024

/**
 * Bloom filter configuration — LAZY allocation (Phase 4).
 *
 * The Bloom filter is only needed for overflow-class objects (> 1024 B)
 * that are allocated via malloc rather than from size-class pools.
 * Pool-managed objects (strings, lists, objects ≤ 1024 B) don't need
 * the filter because their pools own the address space and detect
 * double-free via the in_use counter.
 *
 * The filter is NOT allocated at init time.  It is allocated on first
 * use (first overflow-class DELETE or scope cleanup of an overflow
 * object).  Programs that never create >1024 B objects pay zero cost.
 *
 * 512K bits = 64 KB, 7 hash functions.
 * Supports ~55K freed overflow addresses at <1% false-positive rate.
 * (Optimal k for m/n ≈ 9.4 is k ≈ 7; using 7 hash functions.)
 */
#define SAMM_BLOOM_BITS             524288
#define SAMM_BLOOM_BYTES            ((SAMM_BLOOM_BITS + 7) / 8)
#define SAMM_BLOOM_HASH_COUNT       7

/* FNV-1a hash constants (64-bit) */
#define SAMM_FNV_PRIME              0x00000100000001b3ULL
#define SAMM_FNV_OFFSET_BASIS       0xcbf29ce484222325ULL

#ifdef __cplusplus
}
#endif

#endif /* SAMM_BRIDGE_H */