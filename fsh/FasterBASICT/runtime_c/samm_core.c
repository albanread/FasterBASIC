/*
 * samm_core.c
 * FasterBASIC Runtime — SAMM (Scope Aware Memory Management) Core
 *
 * Environment variables:
 *   SAMM_TRACE=1   Enable verbose per-call trace logging to stderr
 *   SAMM_STATS=1   Print summary statistics at shutdown (no per-call noise)
 *
 * Pure C implementation of scope-aware memory management.
 * Algorithms and data structures are faithful to the NBCPL HeapManager
 * design but implemented without C++ dependencies so the runtime can
 * be compiled with a plain C compiler.
 *
 * Components:
 *   1. Scope Stack    — fixed-depth array of dynamic pointer vectors
 *   2. Bloom Filter   — 96M-bit (12 MB) double-free detector
 *   3. Cleanup Queue  — bounded ring buffer of pointer batches
 *   4. Background Worker — pthread that drains the cleanup queue
 *   5. Metrics        — atomic counters for diagnostics
 *
 * Thread safety:
 *   - scope_mutex_   protects the scope stack (hot path, minimal hold time)
 *   - queue_mutex_   protects the cleanup queue (producer/consumer)
 *   - Bloom filter writes are protected by scope_mutex_ (freed pointers
 *     are only added during samm_free_object or background cleanup)
 *
 * Build:
 *   cc -O2 -c samm_core.c -o samm_core.o -lpthread
 *   (linked automatically via the runtime_files[] list in main.c)
 */

#include "samm_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>
#include <inttypes.h>

/* ========================================================================= */
/* Platform: stdatomic vs __sync builtins                                     */
/* ========================================================================= */

#if defined(__STDC_VERSION__) && __STDC_VERSION__ >= 201112L && !defined(__STDC_NO_ATOMICS__)
#include <stdatomic.h>
typedef _Atomic uint64_t samm_atomic_u64;
typedef _Atomic int      samm_atomic_int;
#define SAMM_ATOMIC_LOAD(x)        atomic_load(&(x))
#define SAMM_ATOMIC_STORE(x, v)    atomic_store(&(x), (v))
#define SAMM_ATOMIC_INC(x)         atomic_fetch_add(&(x), 1)
#define SAMM_ATOMIC_ADD(x, v)      atomic_fetch_add(&(x), (v))
#else
/* Fallback: GCC/Clang __sync builtins */
typedef volatile uint64_t samm_atomic_u64;
typedef volatile int      samm_atomic_int;
#define SAMM_ATOMIC_LOAD(x)        __sync_add_and_fetch(&(x), 0)
#define SAMM_ATOMIC_STORE(x, v)    do { __sync_lock_test_and_set(&(x), (v)); } while(0)
#define SAMM_ATOMIC_INC(x)         __sync_fetch_and_add(&(x), 1)
#define SAMM_ATOMIC_ADD(x, v)      __sync_fetch_and_add(&(x), (v))
#endif

/* ========================================================================= */
/* Scope Entry: dynamic array of tracked pointers                             */
/* ========================================================================= */

typedef struct {
    void**        ptrs;       /* Heap-allocated array of tracked pointers    */
    SAMMAllocType* types;     /* Parallel array: alloc type per pointer      */
    size_t        count;      /* Number of pointers currently tracked        */
    size_t        capacity;   /* Allocated capacity                          */
} SAMMScope;

static void scope_init(SAMMScope* s) {
    s->ptrs     = NULL;
    s->types    = NULL;
    s->count    = 0;
    s->capacity = 0;
}

static void scope_ensure_capacity(SAMMScope* s) {
    if (s->count < s->capacity) return;
    size_t new_cap = (s->capacity == 0) ? SAMM_SCOPE_INITIAL_CAPACITY : s->capacity * 2;
    void** new_ptrs  = (void**)realloc(s->ptrs, new_cap * sizeof(void*));
    SAMMAllocType* new_types = (SAMMAllocType*)realloc(s->types, new_cap * sizeof(SAMMAllocType));
    if (!new_ptrs || !new_types) {
        fprintf(stderr, "SAMM FATAL: scope realloc failed (cap=%zu)\n", new_cap);
        abort();
    }
    s->ptrs     = new_ptrs;
    s->types    = new_types;
    s->capacity = new_cap;
}

static void scope_push(SAMMScope* s, void* ptr, SAMMAllocType type) {
    scope_ensure_capacity(s);
    s->ptrs[s->count]  = ptr;
    s->types[s->count] = type;
    s->count++;
}

/* Remove first occurrence of ptr from scope. Returns 1 if found, 0 if not. */
static int scope_remove(SAMMScope* s, void* ptr) {
    for (size_t i = 0; i < s->count; i++) {
        if (s->ptrs[i] == ptr) {
            /* Swap with last element for O(1) removal */
            s->count--;
            s->ptrs[i]  = s->ptrs[s->count];
            s->types[i] = s->types[s->count];
            return 1;
        }
    }
    return 0;
}

/* Find the type for a given pointer. Returns SAMM_ALLOC_UNKNOWN if not found. */
static SAMMAllocType scope_find_type(SAMMScope* s, void* ptr) {
    for (size_t i = 0; i < s->count; i++) {
        if (s->ptrs[i] == ptr) {
            return s->types[i];
        }
    }
    return SAMM_ALLOC_UNKNOWN;
}

static void scope_destroy(SAMMScope* s) {
    free(s->ptrs);
    free(s->types);
    s->ptrs     = NULL;
    s->types    = NULL;
    s->count    = 0;
    s->capacity = 0;
}

/* ========================================================================= */
/* Cleanup Batch: a snapshot of pointers to clean up                          */
/* ========================================================================= */

typedef struct {
    void**        ptrs;
    SAMMAllocType* types;
    size_t        count;
} SAMMCleanupBatch;

/* ========================================================================= */
/* Bloom Filter (fixed 96M bits, 10 hash functions)                           */
/* ========================================================================= */

typedef struct {
    uint8_t* bits;          /* Heap-allocated bit array (SAMM_BLOOM_BYTES)   */
    size_t   items_added;   /* Approximate number of items inserted          */
} SAMMBloomFilter;

static uint64_t bloom_fnv1a(const void* data, size_t len) {
    uint64_t hash = SAMM_FNV_OFFSET_BASIS;
    const uint8_t* bytes = (const uint8_t*)data;
    for (size_t i = 0; i < len; i++) {
        hash ^= bytes[i];
        hash *= SAMM_FNV_PRIME;
    }
    return hash;
}

static void bloom_generate_hashes(const void* ptr, uint64_t* hashes) {
    uint64_t h1 = bloom_fnv1a(&ptr, sizeof(void*));
    uint64_t h2 = bloom_fnv1a(&h1, sizeof(uint64_t));
    for (int i = 0; i < SAMM_BLOOM_HASH_COUNT; i++) {
        hashes[i] = (h1 + (uint64_t)i * h2) % SAMM_BLOOM_BITS;
    }
}

static void bloom_init(SAMMBloomFilter* bf) {
    bf->bits = (uint8_t*)calloc(1, SAMM_BLOOM_BYTES);
    if (!bf->bits) {
        fprintf(stderr, "SAMM FATAL: Bloom filter alloc failed (%d bytes)\n", SAMM_BLOOM_BYTES);
        abort();
    }
    bf->items_added = 0;
}

static void bloom_destroy(SAMMBloomFilter* bf) {
    free(bf->bits);
    bf->bits = NULL;
    bf->items_added = 0;
}

static void bloom_add(SAMMBloomFilter* bf, const void* ptr) {
    uint64_t hashes[SAMM_BLOOM_HASH_COUNT];
    bloom_generate_hashes(ptr, hashes);
    for (int i = 0; i < SAMM_BLOOM_HASH_COUNT; i++) {
        size_t byte_idx = (size_t)(hashes[i] / 8);
        size_t bit_off  = (size_t)(hashes[i] % 8);
        bf->bits[byte_idx] |= (uint8_t)(1 << bit_off);
    }
    bf->items_added++;
}

static int bloom_check(const SAMMBloomFilter* bf, const void* ptr) {
    if (!bf->bits) return 0;
    uint64_t hashes[SAMM_BLOOM_HASH_COUNT];
    bloom_generate_hashes(ptr, hashes);
    for (int i = 0; i < SAMM_BLOOM_HASH_COUNT; i++) {
        size_t byte_idx = (size_t)(hashes[i] / 8);
        size_t bit_off  = (size_t)(hashes[i] % 8);
        if (!(bf->bits[byte_idx] & (1 << bit_off))) {
            return 0;  /* Definitely not in the set */
        }
    }
    return 1;  /* Probably in the set */
}

/* ========================================================================= */
/* Singleton State                                                            */
/* ========================================================================= */

typedef struct {
    /* --- Scope stack --- */
    SAMMScope       scopes[SAMM_MAX_SCOPE_DEPTH];
    int             scope_depth;      /* Current depth (0 = global) */
    int             peak_scope_depth;
    pthread_mutex_t scope_mutex;

    /* --- Bloom filter --- */
    SAMMBloomFilter bloom;

    /* --- Cleanup queue (bounded ring buffer) --- */
    SAMMCleanupBatch queue[SAMM_MAX_QUEUE_DEPTH];
    int              queue_head;
    int              queue_tail;
    int              queue_count;
    pthread_mutex_t  queue_mutex;
    pthread_cond_t   queue_cv;

    /* --- Background worker --- */
    pthread_t        worker_thread;
    int              worker_running;   /* boolean */
    int              shutdown_flag;    /* boolean */

    /* --- Custom cleanup functions (one per alloc type) --- */
    samm_cleanup_fn  cleanup_fns[8];   /* indexed by SAMMAllocType */

    /* --- Configuration --- */
    int              enabled;
    int              trace;
    int              initialised;

    /* --- Metrics (atomics) --- */
    samm_atomic_u64 stat_scopes_entered;
    samm_atomic_u64 stat_scopes_exited;
    samm_atomic_u64 stat_objects_allocated;
    samm_atomic_u64 stat_objects_freed;
    samm_atomic_u64 stat_objects_cleaned;
    samm_atomic_u64 stat_cleanup_batches;
    samm_atomic_u64 stat_double_free_attempts;
    samm_atomic_u64 stat_retain_calls;
    samm_atomic_u64 stat_total_bytes_allocated;
    samm_atomic_u64 stat_total_bytes_freed;
    double          stat_total_cleanup_time_ms;  /* protected by queue_mutex */
} SAMMState;

static SAMMState g_samm = {0};

/* ========================================================================= */
/* Default Cleanup: CLASS object destructor via vtable                         */
/* ========================================================================= */

/*
 * Default cleanup for CLASS objects: read vtable[3] (destructor pointer)
 * and call it if non-NULL, then free the memory.
 *
 * VTable Layout:
 *   [0] class_id          (int64)
 *   [1] parent_vtable     (pointer)
 *   [2] class_name        (pointer)
 *   [3] destructor        (pointer)
 *   [4+] method pointers
 */
static void default_object_cleanup(void* ptr) {
    if (!ptr) return;

    /* Load vtable pointer from obj[0] */
    void** vtable = (void**)((void**)ptr)[0];
    if (vtable) {
        void* dtor_ptr = ((void**)vtable)[3];
        if (dtor_ptr) {
            typedef void (*dtor_fn)(void*);
            ((dtor_fn)dtor_ptr)(ptr);
        }
    }

    /* Free the object memory */
    free(ptr);
}

static void default_generic_cleanup(void* ptr) {
    free(ptr);
}

/* ========================================================================= */
/* Internal: clean up a batch of pointers immediately (on worker thread)      */
/* ========================================================================= */

static void cleanup_batch(SAMMCleanupBatch* batch) {
    for (size_t i = 0; i < batch->count; i++) {
        void* ptr = batch->ptrs[i];
        if (!ptr) continue;

        SAMMAllocType type = batch->types[i];

        /* Use registered cleanup function if available */
        samm_cleanup_fn fn = NULL;
        if ((int)type >= 0 && (int)type < 8) {
            fn = g_samm.cleanup_fns[(int)type];
        }

        if (fn) {
            fn(ptr);
        } else {
            /* Fallback: type-specific default cleanup */
            switch (type) {
                case SAMM_ALLOC_OBJECT:
                    default_object_cleanup(ptr);
                    break;
                case SAMM_ALLOC_LIST:
                    /* Phase 4: return to freelist. For now, just free. */
                    free(ptr);
                    break;
                case SAMM_ALLOC_LIST_ATOM:
                    /* Phase 4: return to atom freelist. For now, just free. */
                    free(ptr);
                    break;
                case SAMM_ALLOC_STRING:
                    /* Phase 2: call string_pool_free. For now, just free. */
                    free(ptr);
                    break;
                default:
                    default_generic_cleanup(ptr);
                    break;
            }
        }

        /* Mark as freed in Bloom filter */
        pthread_mutex_lock(&g_samm.scope_mutex);
        bloom_add(&g_samm.bloom, ptr);
        pthread_mutex_unlock(&g_samm.scope_mutex);

        SAMM_ATOMIC_INC(g_samm.stat_objects_cleaned);
    }

    /* Free the batch arrays */
    free(batch->ptrs);
    free(batch->types);
    batch->ptrs  = NULL;
    batch->types = NULL;
    batch->count = 0;
}

/* ========================================================================= */
/* Background cleanup worker thread                                           */
/* ========================================================================= */

static void* samm_worker_fn(void* arg) {
    (void)arg;

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Background cleanup worker started\n");
    }

    while (1) {
        SAMMCleanupBatch batch;
        batch.ptrs  = NULL;
        batch.types = NULL;
        batch.count = 0;

        /* Wait for work */
        pthread_mutex_lock(&g_samm.queue_mutex);
        while (g_samm.queue_count == 0 && !g_samm.shutdown_flag) {
            pthread_cond_wait(&g_samm.queue_cv, &g_samm.queue_mutex);
        }

        if (g_samm.queue_count == 0 && g_samm.shutdown_flag) {
            pthread_mutex_unlock(&g_samm.queue_mutex);
            break;
        }

        /* Dequeue one batch */
        batch = g_samm.queue[g_samm.queue_head];
        /* Clear the slot */
        g_samm.queue[g_samm.queue_head].ptrs  = NULL;
        g_samm.queue[g_samm.queue_head].types = NULL;
        g_samm.queue[g_samm.queue_head].count = 0;
        g_samm.queue_head = (g_samm.queue_head + 1) % SAMM_MAX_QUEUE_DEPTH;
        g_samm.queue_count--;
        pthread_mutex_unlock(&g_samm.queue_mutex);

        /* Process the batch */
        if (batch.count > 0) {
            /* Time the cleanup */
            struct timespec t_start, t_end;
#if defined(CLOCK_MONOTONIC)
            clock_gettime(CLOCK_MONOTONIC, &t_start);
#else
            memset(&t_start, 0, sizeof(t_start));
#endif

            if (g_samm.trace) {
                fprintf(stderr, "SAMM: Worker processing batch of %zu objects\n", batch.count);
            }

            cleanup_batch(&batch);
            SAMM_ATOMIC_INC(g_samm.stat_cleanup_batches);

#if defined(CLOCK_MONOTONIC)
            clock_gettime(CLOCK_MONOTONIC, &t_end);
            double ms = (double)(t_end.tv_sec - t_start.tv_sec) * 1000.0
                      + (double)(t_end.tv_nsec - t_start.tv_nsec) / 1e6;
            pthread_mutex_lock(&g_samm.queue_mutex);
            g_samm.stat_total_cleanup_time_ms += ms;
            pthread_mutex_unlock(&g_samm.queue_mutex);
#endif
        }
    }

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Background cleanup worker stopped\n");
    }
    return NULL;
}

/* ========================================================================= */
/* Internal: enqueue a scope's pointers for background cleanup                */
/* ========================================================================= */

static void enqueue_for_cleanup(void** ptrs, SAMMAllocType* types, size_t count) {
    if (count == 0) {
        free(ptrs);
        free(types);
        return;
    }

    pthread_mutex_lock(&g_samm.queue_mutex);

    if (g_samm.queue_count >= SAMM_MAX_QUEUE_DEPTH) {
        /* Queue full — clean up synchronously as fallback */
        pthread_mutex_unlock(&g_samm.queue_mutex);

        if (g_samm.trace) {
            fprintf(stderr, "SAMM: Queue full, cleaning %zu objects synchronously\n", count);
        }

        SAMMCleanupBatch batch;
        batch.ptrs  = ptrs;
        batch.types = types;
        batch.count = count;
        cleanup_batch(&batch);
        SAMM_ATOMIC_INC(g_samm.stat_cleanup_batches);
        return;
    }

    int slot = g_samm.queue_tail;
    g_samm.queue[slot].ptrs  = ptrs;
    g_samm.queue[slot].types = types;
    g_samm.queue[slot].count = count;
    g_samm.queue_tail = (g_samm.queue_tail + 1) % SAMM_MAX_QUEUE_DEPTH;
    g_samm.queue_count++;

    pthread_cond_signal(&g_samm.queue_cv);
    pthread_mutex_unlock(&g_samm.queue_mutex);
}

/* ========================================================================= */
/* Internal: drain the queue synchronously (for shutdown / samm_wait)          */
/* ========================================================================= */

static void drain_queue_sync(void) {
    while (1) {
        SAMMCleanupBatch batch;
        batch.ptrs  = NULL;
        batch.types = NULL;
        batch.count = 0;

        pthread_mutex_lock(&g_samm.queue_mutex);
        if (g_samm.queue_count == 0) {
            pthread_mutex_unlock(&g_samm.queue_mutex);
            break;
        }
        batch = g_samm.queue[g_samm.queue_head];
        g_samm.queue[g_samm.queue_head].ptrs  = NULL;
        g_samm.queue[g_samm.queue_head].types = NULL;
        g_samm.queue[g_samm.queue_head].count = 0;
        g_samm.queue_head = (g_samm.queue_head + 1) % SAMM_MAX_QUEUE_DEPTH;
        g_samm.queue_count--;
        pthread_mutex_unlock(&g_samm.queue_mutex);

        if (batch.count > 0) {
            cleanup_batch(&batch);
            SAMM_ATOMIC_INC(g_samm.stat_cleanup_batches);
        }
    }
}

/* ========================================================================= */
/* Public API: Initialisation & Shutdown                                       */
/* ========================================================================= */

void samm_init(void) {
    if (g_samm.initialised) return;

    memset(&g_samm, 0, sizeof(g_samm));

    /* Initialise mutexes and condition variable */
    pthread_mutex_init(&g_samm.scope_mutex, NULL);
    pthread_mutex_init(&g_samm.queue_mutex, NULL);
    pthread_cond_init(&g_samm.queue_cv, NULL);

    /* Initialise Bloom filter */
    bloom_init(&g_samm.bloom);

    /* Initialise global scope (depth 0) */
    scope_init(&g_samm.scopes[0]);
    g_samm.scope_depth      = 0;
    g_samm.peak_scope_depth = 0;

    /* Initialise cleanup queue */
    g_samm.queue_head  = 0;
    g_samm.queue_tail  = 0;
    g_samm.queue_count = 0;

    /* Start background worker */
    g_samm.shutdown_flag  = 0;
    g_samm.worker_running = 0;

    int rc = pthread_create(&g_samm.worker_thread, NULL, samm_worker_fn, NULL);
    if (rc == 0) {
        g_samm.worker_running = 1;
    } else {
        fprintf(stderr, "SAMM WARNING: Failed to create background worker (rc=%d). "
                "Cleanup will be synchronous.\n", rc);
    }

    g_samm.enabled     = 1;
    g_samm.initialised = 1;

    /* Auto-enable trace from environment variable:
     *   SAMM_TRACE=1 ./my_program
     * This enables verbose per-call logging (scope enter/exit, alloc,
     * free, retain) to stderr.  For stats-only output without the
     * per-call noise, use SAMM_STATS=1 instead. */
    g_samm.trace = (getenv("SAMM_TRACE") != NULL) ? 1 : 0;

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Initialised (Bloom filter: %d bytes, max scopes: %d)\n",
                SAMM_BLOOM_BYTES, SAMM_MAX_SCOPE_DEPTH);
    }
}

void samm_shutdown(void) {
    if (!g_samm.initialised) return;

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Shutting down...\n");
    }

    /* Signal worker to stop */
    pthread_mutex_lock(&g_samm.queue_mutex);
    g_samm.shutdown_flag = 1;
    pthread_cond_signal(&g_samm.queue_cv);
    pthread_mutex_unlock(&g_samm.queue_mutex);

    /* Join worker thread */
    if (g_samm.worker_running) {
        pthread_join(g_samm.worker_thread, NULL);
        g_samm.worker_running = 0;
    }

    /* Drain any remaining items in the queue synchronously */
    drain_queue_sync();

    /* Clean up all remaining scopes (including global) */
    for (int d = g_samm.scope_depth; d >= 0; d--) {
        SAMMScope* s = &g_samm.scopes[d];
        if (s->count > 0) {
            if (g_samm.trace) {
                fprintf(stderr, "SAMM: Cleaning up %zu objects from scope depth %d\n",
                        s->count, d);
            }
            /* Clean up directly (worker is stopped) */
            SAMMCleanupBatch batch;
            batch.ptrs  = s->ptrs;
            batch.types = s->types;
            batch.count = s->count;
            cleanup_batch(&batch);
            /* cleanup_batch freed ptrs and types, clear the scope */
            s->ptrs     = NULL;
            s->types    = NULL;
            s->count    = 0;
            s->capacity = 0;
        } else {
            scope_destroy(s);
        }
    }

    /* Print stats if tracing enabled or SAMM_STATS env var is set.
     * This lets users see SAMM diagnostics without enabling the
     * very verbose per-call trace output:
     *   SAMM_STATS=1 ./my_program        */
    if (g_samm.trace || getenv("SAMM_STATS")) {
        samm_print_stats();
    }

    /* Destroy Bloom filter */
    bloom_destroy(&g_samm.bloom);

    /* Destroy mutexes */
    pthread_mutex_destroy(&g_samm.scope_mutex);
    pthread_mutex_destroy(&g_samm.queue_mutex);
    pthread_cond_destroy(&g_samm.queue_cv);

    g_samm.initialised = 0;
    g_samm.enabled     = 0;
}

/* ========================================================================= */
/* Public API: Enable / Disable                                                */
/* ========================================================================= */

void samm_set_enabled(int enabled) {
    if (enabled && !g_samm.initialised) {
        samm_init();
    }
    g_samm.enabled = (enabled != 0);
}

int samm_is_enabled(void) {
    return g_samm.enabled;
}

/* ========================================================================= */
/* Public API: Scope Management                                                */
/* ========================================================================= */

void samm_enter_scope(void) {
    if (!g_samm.enabled) return;

    pthread_mutex_lock(&g_samm.scope_mutex);

    int new_depth = g_samm.scope_depth + 1;
    if (new_depth >= SAMM_MAX_SCOPE_DEPTH) {
        pthread_mutex_unlock(&g_samm.scope_mutex);
        fprintf(stderr, "SAMM FATAL: Maximum scope depth (%d) exceeded\n",
                SAMM_MAX_SCOPE_DEPTH);
        abort();
    }

    scope_init(&g_samm.scopes[new_depth]);
    g_samm.scope_depth = new_depth;
    if (new_depth > g_samm.peak_scope_depth) {
        g_samm.peak_scope_depth = new_depth;
    }

    pthread_mutex_unlock(&g_samm.scope_mutex);

    SAMM_ATOMIC_INC(g_samm.stat_scopes_entered);

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Enter scope (depth: %d)\n", new_depth);
    }
}

void samm_exit_scope(void) {
    if (!g_samm.enabled) return;

    void**        ptrs_to_clean  = NULL;
    SAMMAllocType* types_to_clean = NULL;
    size_t        count_to_clean = 0;

    pthread_mutex_lock(&g_samm.scope_mutex);

    if (g_samm.scope_depth <= 0) {
        /* Cannot exit global scope */
        pthread_mutex_unlock(&g_samm.scope_mutex);
        if (g_samm.trace) {
            fprintf(stderr, "SAMM: Cannot exit global scope (depth 0)\n");
        }
        return;
    }

    SAMMScope* s = &g_samm.scopes[g_samm.scope_depth];

    if (s->count > 0) {
        /* Take ownership of the arrays — the queue/worker will free them */
        ptrs_to_clean  = s->ptrs;
        types_to_clean = s->types;
        count_to_clean = s->count;

        /* Detach from scope (don't free here, queue takes ownership) */
        s->ptrs     = NULL;
        s->types    = NULL;
        s->count    = 0;
        s->capacity = 0;
    } else {
        scope_destroy(s);
    }

    g_samm.scope_depth--;

    pthread_mutex_unlock(&g_samm.scope_mutex);

    SAMM_ATOMIC_INC(g_samm.stat_scopes_exited);

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: Exit scope (depth now: %d, cleaning: %zu objects)\n",
                g_samm.scope_depth, count_to_clean);
    }

    /* Enqueue for background cleanup (or sync if no worker) */
    if (count_to_clean > 0) {
        if (g_samm.worker_running) {
            enqueue_for_cleanup(ptrs_to_clean, types_to_clean, count_to_clean);
        } else {
            /* No worker — clean synchronously */
            SAMMCleanupBatch batch;
            batch.ptrs  = ptrs_to_clean;
            batch.types = types_to_clean;
            batch.count = count_to_clean;
            cleanup_batch(&batch);
            SAMM_ATOMIC_INC(g_samm.stat_cleanup_batches);
        }
    }
}

int samm_scope_depth(void) {
    if (!g_samm.enabled) return 0;
    int depth;
    pthread_mutex_lock(&g_samm.scope_mutex);
    depth = g_samm.scope_depth;
    pthread_mutex_unlock(&g_samm.scope_mutex);
    return depth;
}

/* ========================================================================= */
/* Public API: Object Allocation                                               */
/* ========================================================================= */

void* samm_alloc_object(size_t size) {
    void* ptr = calloc(1, size);
    if (ptr) {
        SAMM_ATOMIC_INC(g_samm.stat_objects_allocated);
        SAMM_ATOMIC_ADD(g_samm.stat_total_bytes_allocated, (uint64_t)size);
    }
    return ptr;
}

void samm_free_object(void* ptr) {
    if (!ptr) return;

    /* Check Bloom filter for double-free */
    if (g_samm.enabled) {
        pthread_mutex_lock(&g_samm.scope_mutex);
        int probably_freed = bloom_check(&g_samm.bloom, ptr);
        pthread_mutex_unlock(&g_samm.scope_mutex);

        if (probably_freed) {
            SAMM_ATOMIC_INC(g_samm.stat_double_free_attempts);
            if (g_samm.trace) {
                fprintf(stderr, "SAMM WARNING: Possible double-free on %p (Bloom filter hit)\n", ptr);
            }
            /* Don't free — it's probably already freed.
             * For safety, we log and skip. */
            return;
        }

        /* Untrack from current scope (if it's being explicitly DELETEd) */
        pthread_mutex_lock(&g_samm.scope_mutex);
        if (g_samm.scope_depth >= 0) {
            scope_remove(&g_samm.scopes[g_samm.scope_depth], ptr);
        }
        /* Add to Bloom filter */
        bloom_add(&g_samm.bloom, ptr);
        pthread_mutex_unlock(&g_samm.scope_mutex);
    }

    free(ptr);
    SAMM_ATOMIC_INC(g_samm.stat_objects_freed);
}

/* ========================================================================= */
/* Public API: Scope Tracking                                                  */
/* ========================================================================= */

void samm_track(void* ptr, SAMMAllocType type) {
    if (!g_samm.enabled || !ptr) return;

    pthread_mutex_lock(&g_samm.scope_mutex);
    if (g_samm.scope_depth >= 0 && g_samm.scope_depth < SAMM_MAX_SCOPE_DEPTH) {
        scope_push(&g_samm.scopes[g_samm.scope_depth], ptr, type);
        if (g_samm.trace) {
            fprintf(stderr, "SAMM: Tracked %p (type=%d) in scope %d (scope size: %zu)\n",
                    ptr, (int)type, g_samm.scope_depth,
                    g_samm.scopes[g_samm.scope_depth].count);
        }
    }
    pthread_mutex_unlock(&g_samm.scope_mutex);
}

void samm_track_object(void* ptr) {
    samm_track(ptr, SAMM_ALLOC_OBJECT);
}

void samm_untrack(void* ptr) {
    if (!g_samm.enabled || !ptr) return;

    pthread_mutex_lock(&g_samm.scope_mutex);
    /* Search from innermost scope outward */
    for (int d = g_samm.scope_depth; d >= 0; d--) {
        if (scope_remove(&g_samm.scopes[d], ptr)) {
            if (g_samm.trace) {
                fprintf(stderr, "SAMM: Untracked %p from scope %d\n", ptr, d);
            }
            break;
        }
    }
    pthread_mutex_unlock(&g_samm.scope_mutex);
}

/* ========================================================================= */
/* Public API: RETAIN                                                          */
/* ========================================================================= */

void samm_retain(void* ptr, int parent_offset) {
    if (!g_samm.enabled || !ptr || parent_offset <= 0) return;

    SAMM_ATOMIC_INC(g_samm.stat_retain_calls);

    pthread_mutex_lock(&g_samm.scope_mutex);

    /* Find and remove from current scope */
    int current = g_samm.scope_depth;
    SAMMAllocType type = SAMM_ALLOC_UNKNOWN;
    int found = 0;

    if (current >= 0) {
        type = scope_find_type(&g_samm.scopes[current], ptr);
        found = scope_remove(&g_samm.scopes[current], ptr);
    }

    if (found) {
        /* Compute target scope depth */
        int target = current - parent_offset;
        if (target < 0) target = 0;  /* Clamp to global scope */

        scope_push(&g_samm.scopes[target], ptr, type);

        if (g_samm.trace) {
            fprintf(stderr, "SAMM: Retained %p from scope %d to scope %d\n",
                    ptr, current, target);
        }
    } else {
        /* Pointer wasn't in current scope — might be in an outer scope already.
         * Search outward and move it if found. */
        for (int d = current - 1; d >= 0; d--) {
            type = scope_find_type(&g_samm.scopes[d], ptr);
            if (scope_remove(&g_samm.scopes[d], ptr)) {
                int target = d - parent_offset;
                if (target < 0) target = 0;
                scope_push(&g_samm.scopes[target], ptr, type);
                if (g_samm.trace) {
                    fprintf(stderr, "SAMM: Retained %p from scope %d to scope %d (found in outer scope)\n",
                            ptr, d, target);
                }
                found = 1;
                break;
            }
        }

        if (!found && g_samm.trace) {
            fprintf(stderr, "SAMM: Retain failed — %p not found in any scope\n", ptr);
        }
    }

    pthread_mutex_unlock(&g_samm.scope_mutex);
}

void samm_retain_parent(void* ptr) {
    samm_retain(ptr, 1);
}

/* ========================================================================= */
/* Public API: Double-Free Detection                                           */
/* ========================================================================= */

int samm_is_probably_freed(void* ptr) {
    if (!g_samm.enabled || !ptr) return 0;

    int result;
    pthread_mutex_lock(&g_samm.scope_mutex);
    result = bloom_check(&g_samm.bloom, ptr);
    pthread_mutex_unlock(&g_samm.scope_mutex);
    return result;
}

/* ========================================================================= */
/* Public API: List Support (Phase 4 stubs)                                    */
/* ========================================================================= */

void* samm_alloc_list(void) {
    /* Phase 4: allocate a ListHeader from the freelist.
     * For now, return NULL — lists are not yet implemented. */
    return NULL;
}

void samm_track_list(void* list_header_ptr) {
    /* Phase 4: track as SAMM_ALLOC_LIST so the worker returns to freelist. */
    samm_track(list_header_ptr, SAMM_ALLOC_LIST);
}

void* samm_alloc_list_atom(void) {
    /* Phase 4: allocate a ListAtom from the atom freelist.
     * For now, return NULL. */
    return NULL;
}

/* ========================================================================= */
/* Public API: String Tracking (Phase 2 stub)                                  */
/* ========================================================================= */

void samm_track_string(void* string_desc_ptr) {
    /* Phase 2: track as SAMM_ALLOC_STRING so the worker calls
     * string_pool_free instead of raw free.
     * For now, track as generic so it at least gets freed. */
    samm_track(string_desc_ptr, SAMM_ALLOC_STRING);
}

/* ========================================================================= */
/* Public API: Destructor Registration                                         */
/* ========================================================================= */

void samm_register_cleanup(SAMMAllocType type, samm_cleanup_fn fn) {
    if ((int)type >= 0 && (int)type < 8) {
        g_samm.cleanup_fns[(int)type] = fn;
    }
}

/* ========================================================================= */
/* Public API: Diagnostics                                                     */
/* ========================================================================= */

void samm_get_stats(SAMMStats* out) {
    if (!out) return;

    out->scopes_entered        = SAMM_ATOMIC_LOAD(g_samm.stat_scopes_entered);
    out->scopes_exited         = SAMM_ATOMIC_LOAD(g_samm.stat_scopes_exited);
    out->objects_allocated     = SAMM_ATOMIC_LOAD(g_samm.stat_objects_allocated);
    out->objects_freed         = SAMM_ATOMIC_LOAD(g_samm.stat_objects_freed);
    out->objects_cleaned       = SAMM_ATOMIC_LOAD(g_samm.stat_objects_cleaned);
    out->cleanup_batches       = SAMM_ATOMIC_LOAD(g_samm.stat_cleanup_batches);
    out->double_free_attempts  = SAMM_ATOMIC_LOAD(g_samm.stat_double_free_attempts);
    out->bloom_false_positives = 0; /* TODO: estimate from Bloom filter fill ratio */
    out->retain_calls          = SAMM_ATOMIC_LOAD(g_samm.stat_retain_calls);
    out->total_bytes_allocated = SAMM_ATOMIC_LOAD(g_samm.stat_total_bytes_allocated);
    out->total_bytes_freed     = SAMM_ATOMIC_LOAD(g_samm.stat_total_bytes_freed);

    pthread_mutex_lock(&g_samm.scope_mutex);
    out->current_scope_depth = g_samm.scope_depth;
    out->peak_scope_depth    = g_samm.peak_scope_depth;
    pthread_mutex_unlock(&g_samm.scope_mutex);

    out->bloom_memory_bytes        = g_samm.bloom.bits ? SAMM_BLOOM_BYTES : 0;

    pthread_mutex_lock(&g_samm.queue_mutex);
    out->total_cleanup_time_ms     = g_samm.stat_total_cleanup_time_ms;
    pthread_mutex_unlock(&g_samm.queue_mutex);

    out->background_worker_active  = g_samm.worker_running;
}

void samm_print_stats(void) {
    SAMMStats s;
    samm_get_stats(&s);

    fprintf(stderr, "\n");
    fprintf(stderr, "=== SAMM Statistics ===\n");
    fprintf(stderr, "  Scopes entered:       %" PRIu64 "\n", s.scopes_entered);
    fprintf(stderr, "  Scopes exited:        %" PRIu64 "\n", s.scopes_exited);
    fprintf(stderr, "  Objects allocated:    %" PRIu64 "\n", s.objects_allocated);
    fprintf(stderr, "  Objects freed (DEL):  %" PRIu64 "\n", s.objects_freed);
    fprintf(stderr, "  Objects cleaned (bg): %" PRIu64 "\n", s.objects_cleaned);
    fprintf(stderr, "  Cleanup batches:      %" PRIu64 "\n", s.cleanup_batches);
    fprintf(stderr, "  Double-free catches:  %" PRIu64 "\n", s.double_free_attempts);
    fprintf(stderr, "  RETAIN calls:         %" PRIu64 "\n", s.retain_calls);
    fprintf(stderr, "  Bytes allocated:      %" PRIu64 "\n", s.total_bytes_allocated);
    fprintf(stderr, "  Bytes freed:          %" PRIu64 "\n", s.total_bytes_freed);
    fprintf(stderr, "  Current scope depth:  %d\n", s.current_scope_depth);
    fprintf(stderr, "  Peak scope depth:     %d\n", s.peak_scope_depth);
    fprintf(stderr, "  Bloom filter memory:  %zu bytes (%.1f MB)\n",
            s.bloom_memory_bytes, (double)s.bloom_memory_bytes / (1024.0 * 1024.0));
    fprintf(stderr, "  Cleanup time:         %.3f ms\n", s.total_cleanup_time_ms);
    fprintf(stderr, "  Background worker:    %s\n",
            s.background_worker_active ? "active" : "stopped");
    fprintf(stderr, "===========================\n");
    fprintf(stderr, "\n");
}

void samm_set_trace(int enabled) {
    g_samm.trace = (enabled != 0);
}

void samm_wait(void) {
    if (!g_samm.enabled) return;

    if (g_samm.worker_running) {
        /* Spin until the queue is empty */
        int remaining;
        do {
            /* Give the worker time to process */
            struct timespec ts = {0, 1000000}; /* 1ms */
            nanosleep(&ts, NULL);

            pthread_mutex_lock(&g_samm.queue_mutex);
            remaining = g_samm.queue_count;
            pthread_mutex_unlock(&g_samm.queue_mutex);
        } while (remaining > 0);
    } else {
        /* No worker — drain synchronously */
        drain_queue_sync();
    }

    if (g_samm.trace) {
        fprintf(stderr, "SAMM: All pending cleanup complete\n");
    }
}