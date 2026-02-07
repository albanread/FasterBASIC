/*
 * samm_pool.c
 * FasterBASIC Runtime — Generic Slab Pool Allocator Implementation
 *
 * Type-agnostic fixed-size slab pool with intrusive free-list.
 * See samm_pool.h for API documentation and design rationale.
 *
 * Build:
 *   cc -std=c99 -O2 -c samm_pool.c -o samm_pool.o -lpthread
 */

#include "samm_pool.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <assert.h>

/* ========================================================================= */
/* Global Pool Instance (Phase 4: String descriptors)                         */
/* ========================================================================= */

SammSlabPool g_string_desc_pool = {0};

/* ========================================================================= */
/* Global Pool Instances (Phase 2: List types)                                */
/* ========================================================================= */

SammSlabPool g_list_header_pool = {0};
SammSlabPool g_list_atom_pool   = {0};

/* ========================================================================= */
/* Global Pool Instances (Phase 3: Object size-class pools)                   */
/*                                                                            */
/* Six pools covering objects from 32 B to 1024 B.  Objects larger than       */
/* 1024 B fall back to malloc (tracked with size_class = 0xFF).               */
/*                                                                            */
/* Index  Slot Size  Covers            Slots/Slab                             */
/*   0      32 B     17–32 B           128                                    */
/*   1      64 B     33–64 B           128                                    */
/*   2     128 B     65–128 B          128                                    */
/*   3     256 B     129–256 B         128                                    */
/*   4     512 B     257–512 B          64                                    */
/*   5    1024 B     513–1024 B         32                                    */
/* ========================================================================= */

SammSlabPool g_object_pools[SAMM_OBJECT_SIZE_CLASSES] = {{0}};

/* ========================================================================= */
/* Internal: Free-list link overlay                                           */
/*                                                                            */
/* When a slot is on the free list, its first sizeof(void*) bytes store a     */
/* pointer to the next free slot.  This is safe because:                      */
/*   - All slot sizes are >= 8 bytes (asserted at init)                       */
/*   - The slot is not in use, so its contents are don't-care                 */
/*   - We zero the slot on allocation before returning to the caller          */
/* ========================================================================= */

/* Read the next-pointer from a free slot */
static inline void* freelist_next(void* slot) {
    void* next;
    memcpy(&next, slot, sizeof(void*));
    return next;
}

/* Write the next-pointer into a free slot */
static inline void freelist_set_next(void* slot, void* next) {
    memcpy(slot, &next, sizeof(void*));
}

/* ========================================================================= */
/* Internal: Slab allocation                                                  */
/* ========================================================================= */

/*
 * Allocate a new slab and thread all its slots onto the pool's free list.
 *
 * Slab memory layout:
 *   [ SammSlab header ][ slot 0 ][ slot 1 ]...[ slot N-1 ]
 *
 * The header and slots are allocated as a single contiguous block via
 * malloc(sizeof(SammSlab) + slots_per_slab * slot_size).  SammSlab uses
 * a flexible array member (data[]) so the slots start immediately after
 * the header with correct alignment.
 *
 * Returns true on success, false on failure.
 * Caller must hold pool->lock.
 */
static bool pool_add_slab(SammSlabPool* pool) {
    if (!pool) return false;

    /* Safety limit */
    if (pool->total_slabs >= SAMM_SLAB_POOL_MAX_SLABS) {
        fprintf(stderr, "ERROR: %s pool maximum slabs reached (%d)\n",
                pool->name ? pool->name : "SammSlabPool",
                SAMM_SLAB_POOL_MAX_SLABS);
        return false;
    }

    size_t data_bytes = (size_t)pool->slots_per_slab * (size_t)pool->slot_size;
    size_t slab_bytes = sizeof(SammSlab) + data_bytes;

    SammSlab* slab = (SammSlab*)malloc(slab_bytes);
    if (!slab) {
        fprintf(stderr, "ERROR: %s pool failed to allocate slab (%zu bytes)\n",
                pool->name ? pool->name : "SammSlabPool", slab_bytes);
        return false;
    }

    /* Initialise slab header */
    memset(slab, 0, sizeof(SammSlab));
    slab->slot_size  = pool->slot_size;
    slab->slot_count = pool->slots_per_slab;
    slab->used_count = 0;

    /* Zero all slot data */
    memset(slab->data, 0, data_bytes);

    /* Thread all slots in this slab onto the free list.
     * We iterate in reverse so that slot 0 ends up at the head of the
     * free list, giving sequential allocation order within a slab
     * (better cache behaviour). */
    for (int i = (int)pool->slots_per_slab - 1; i >= 0; i--) {
        void* slot = slab->data + ((size_t)i * (size_t)pool->slot_size);
        freelist_set_next(slot, pool->free_list);
        pool->free_list = slot;
    }

    /* Link slab into chain (newest first) */
    slab->next   = pool->slabs;
    pool->slabs  = slab;
    pool->total_slabs++;
    pool->total_capacity += pool->slots_per_slab;

    /* Update peak footprint (slabs are never returned, so this always grows) */
    size_t current_footprint = pool->total_slabs *
        (sizeof(SammSlab) + (size_t)pool->slots_per_slab * (size_t)pool->slot_size);
    if (current_footprint > pool->peak_footprint_bytes) {
        pool->peak_footprint_bytes = current_footprint;
    }

    SAMM_POOL_TRACE("%s: added slab #%zu (%u slots, capacity=%zu)",
                    pool->name ? pool->name : "pool",
                    pool->total_slabs, pool->slots_per_slab,
                    pool->total_capacity);

    return true;
}

/* ========================================================================= */
/* Public API: Initialisation & Destruction                                   */
/* ========================================================================= */

void samm_slab_pool_init(SammSlabPool* pool,
                         uint32_t slot_size,
                         uint32_t slots_per_slab,
                         const char* name) {
    if (!pool) return;

    /* Slot must be large enough to hold a free-list pointer */
    assert(slot_size >= sizeof(void*));

    memset(pool, 0, sizeof(SammSlabPool));
    pthread_mutex_init(&pool->lock, NULL);

    pool->slot_size      = slot_size;
    pool->slots_per_slab = slots_per_slab;
    pool->name           = name;
    pool->free_list      = NULL;
    pool->slabs          = NULL;
    pool->total_slabs    = 0;
    pool->total_capacity = 0;
    pool->in_use         = 0;
    pool->peak_use       = 0;
    pool->peak_footprint_bytes = 0;
    pool->total_allocs   = 0;
    pool->total_frees    = 0;

    /* Pre-allocate initial slabs so the first alloc doesn't hit malloc */
    for (size_t i = 0; i < SAMM_SLAB_POOL_INITIAL_SLABS; i++) {
        if (!pool_add_slab(pool)) {
            fprintf(stderr, "WARNING: %s pool failed to pre-allocate slab %zu\n",
                    name ? name : "SammSlabPool", i);
            break;
        }
    }

    SAMM_POOL_TRACE("%s: initialised (slot_size=%u, slots_per_slab=%u, "
                    "initial_capacity=%zu)",
                    name ? name : "pool",
                    slot_size, slots_per_slab, pool->total_capacity);
}

void samm_slab_pool_destroy(SammSlabPool* pool) {
    if (!pool) return;

    SAMM_POOL_TRACE("%s: destroying (slabs=%zu, in_use=%zu, peak=%zu, "
                    "allocs=%zu, frees=%zu)",
                    pool->name ? pool->name : "pool",
                    pool->total_slabs, pool->in_use, pool->peak_use,
                    pool->total_allocs, pool->total_frees);

    /* Report leaks */
    if (pool->in_use > 0) {
        fprintf(stderr, "WARNING: %s pool has %zu leaked slots at shutdown\n",
                pool->name ? pool->name : "SammSlabPool", pool->in_use);
    }

    /* Free all slabs */
    SammSlab* slab = pool->slabs;
    while (slab) {
        SammSlab* next = slab->next;
        free(slab);
        slab = next;
    }

    /* Destroy mutex before zeroing */
    pthread_mutex_destroy(&pool->lock);

    /* Zero out the pool struct */
    const char* saved_name = pool->name;
    memset(pool, 0, sizeof(SammSlabPool));
    pool->name = saved_name; /* preserve name for post-mortem diagnostics */
}

/* ========================================================================= */
/* Public API: Allocation & Deallocation                                      */
/* ========================================================================= */

void* samm_slab_pool_alloc(SammSlabPool* pool) {
    if (!pool) return NULL;

    pthread_mutex_lock(&pool->lock);

    /* If free list is empty, grow the pool */
    if (!pool->free_list) {
        if (!pool_add_slab(pool)) {
            pthread_mutex_unlock(&pool->lock);

            /* Fallback to malloc — print warning once */
            fprintf(stderr, "WARNING: %s pool exhausted, falling back to malloc\n",
                    pool->name ? pool->name : "SammSlabPool");
            void* ptr = malloc(pool->slot_size);
            if (ptr) {
                memset(ptr, 0, pool->slot_size);
            }
            return ptr;
        }
    }

    /* Pop from free list head */
    void* slot = pool->free_list;
    pool->free_list = freelist_next(slot);

    /* Update statistics */
    pool->in_use++;
    pool->total_allocs++;
    if (pool->in_use > pool->peak_use) {
        pool->peak_use = pool->in_use;
    }

    SAMM_POOL_TRACE("%s: alloc %p (in_use=%zu, capacity=%zu)",
                    pool->name ? pool->name : "pool",
                    slot, pool->in_use, pool->total_capacity);

    pthread_mutex_unlock(&pool->lock);

    /* Zero the slot before returning.
     * This clears the free-list link and ensures the caller gets a
     * clean block, matching calloc() / memset() semantics. */
    memset(slot, 0, pool->slot_size);

    return slot;
}

void samm_slab_pool_free(SammSlabPool* pool, void* ptr) {
    if (!pool || !ptr) return;

    pthread_mutex_lock(&pool->lock);

    /* Push onto free list head */
    freelist_set_next(ptr, pool->free_list);
    pool->free_list = ptr;

    /* Update statistics */
    if (pool->in_use > 0) {
        pool->in_use--;
    } else {
        fprintf(stderr, "WARNING: %s pool free when in_use is already 0 "
                "(double free?)\n",
                pool->name ? pool->name : "SammSlabPool");
    }
    pool->total_frees++;

    SAMM_POOL_TRACE("%s: free %p (in_use=%zu, capacity=%zu)",
                    pool->name ? pool->name : "pool",
                    ptr, pool->in_use, pool->total_capacity);

    pthread_mutex_unlock(&pool->lock);
}

/* ========================================================================= */
/* Public API: Statistics & Diagnostics                                       */
/* ========================================================================= */

void samm_slab_pool_stats(const SammSlabPool* pool,
                          size_t* out_in_use,
                          size_t* out_capacity,
                          size_t* out_peak_use,
                          size_t* out_slabs,
                          size_t* out_allocs,
                          size_t* out_frees) {
    if (!pool) return;

    if (out_in_use)   *out_in_use   = pool->in_use;
    if (out_capacity) *out_capacity = pool->total_capacity;
    if (out_peak_use) *out_peak_use = pool->peak_use;
    if (out_slabs)    *out_slabs    = pool->total_slabs;
    if (out_allocs)   *out_allocs   = pool->total_allocs;
    if (out_frees)    *out_frees    = pool->total_frees;
}

void samm_slab_pool_print_stats(const SammSlabPool* pool) {
    if (!pool) return;

    const char* name = pool->name ? pool->name : "SammSlabPool";

    fprintf(stderr, "=== %s Pool Statistics ===\n", name);
    fprintf(stderr, "  Slot size:       %u bytes\n",  pool->slot_size);
    fprintf(stderr, "  Slots/slab:      %u\n",        pool->slots_per_slab);
    fprintf(stderr, "  Slabs:           %zu\n",       pool->total_slabs);
    fprintf(stderr, "  Capacity:        %zu slots\n", pool->total_capacity);
    fprintf(stderr, "  In use:          %zu slots\n", pool->in_use);
    fprintf(stderr, "  Free:            %zu slots\n",
            pool->total_capacity > pool->in_use
                ? pool->total_capacity - pool->in_use : 0);
    fprintf(stderr, "  Peak usage:      %zu slots\n", pool->peak_use);
    fprintf(stderr, "  Usage:           %.1f%%\n",
            samm_slab_pool_usage_percent(pool));
    fprintf(stderr, "  Total allocs:    %zu\n",       pool->total_allocs);
    fprintf(stderr, "  Total frees:     %zu\n",       pool->total_frees);
    fprintf(stderr, "  Net allocations: %+zd\n",
            (ssize_t)pool->total_allocs - (ssize_t)pool->total_frees);
    size_t current_footprint = pool->total_slabs * (sizeof(SammSlab) +
        (size_t)pool->slots_per_slab * (size_t)pool->slot_size);
    size_t peak_obj_bytes = pool->peak_use * (size_t)pool->slot_size;
    fprintf(stderr, "  Memory footprint: %zu bytes (%.1f KB)\n",
            current_footprint, (double)current_footprint / 1024.0);
    fprintf(stderr, "  Peak footprint:   %zu bytes (%.1f KB)\n",
            pool->peak_footprint_bytes,
            (double)pool->peak_footprint_bytes / 1024.0);
    fprintf(stderr, "  Peak object mem:  %zu bytes (%.1f KB)  [%zu slots x %u B]\n",
            peak_obj_bytes, (double)peak_obj_bytes / 1024.0,
            pool->peak_use, pool->slot_size);
    fprintf(stderr, "=======================================\n");
}

bool samm_slab_pool_validate(const SammSlabPool* pool) {
    if (!pool) return false;

    /* Count slots on the free list */
    size_t free_count = 0;
    void* slot = pool->free_list;
    const size_t max_iter = pool->total_capacity + 100; /* cycle guard */

    while (slot && free_count < max_iter) {
        free_count++;
        slot = freelist_next(slot);
    }

    if (free_count >= max_iter) {
        fprintf(stderr, "ERROR: %s pool free list corrupted (cycle detected)\n",
                pool->name ? pool->name : "SammSlabPool");
        return false;
    }

    /* free + in_use should equal total capacity */
    size_t expected_free = pool->total_capacity - pool->in_use;
    if (free_count != expected_free) {
        fprintf(stderr, "ERROR: %s pool free list count mismatch: "
                "found=%zu, expected=%zu (in_use=%zu, capacity=%zu)\n",
                pool->name ? pool->name : "SammSlabPool",
                free_count, expected_free,
                pool->in_use, pool->total_capacity);
        return false;
    }

    return true;
}

void samm_slab_pool_check_leaks(const SammSlabPool* pool) {
    if (!pool) return;

    const char* name = pool->name ? pool->name : "SammSlabPool";

    if (pool->in_use == 0) {
        fprintf(stderr, "%s: no leaked slots detected.\n", name);
        return;
    }

    fprintf(stderr, "WARNING: %s has %zu leaked slots (%zu allocs, %zu frees)\n",
            name, pool->in_use, pool->total_allocs, pool->total_frees);

    /*
     * Enumerate leaked slots by scanning all slabs and checking which
     * slots are NOT on the free list.
     *
     * This is O(slabs * slots_per_slab * free_list_length) in the worst
     * case, so it's only suitable for diagnostics at shutdown, not for
     * hot-path use.
     */
    size_t leaked = 0;
    SammSlab* slab = pool->slabs;

    while (slab) {
        for (uint32_t i = 0; i < slab->slot_count; i++) {
            void* slot = slab->data + ((size_t)i * (size_t)slab->slot_size);

            /* Check if this slot is on the free list */
            bool in_free_list = false;
            void* free_slot = pool->free_list;
            while (free_slot) {
                if (free_slot == slot) {
                    in_free_list = true;
                    break;
                }
                free_slot = freelist_next(free_slot);
            }

            if (!in_free_list) {
                leaked++;
                /* Print first 8 bytes as hex for diagnosis */
                uint8_t* bytes = (uint8_t*)slot;
                fprintf(stderr, "  Leaked slot #%zu at %p: "
                        "%02x %02x %02x %02x %02x %02x %02x %02x\n",
                        leaked, slot,
                        bytes[0], bytes[1], bytes[2], bytes[3],
                        bytes[4], bytes[5], bytes[6], bytes[7]);

                /* Limit output for large leaks */
                if (leaked >= 20) {
                    fprintf(stderr, "  ... (%zu more leaked slots not shown)\n",
                            pool->in_use - leaked);
                    return;
                }
            }
        }
        slab = slab->next;
    }
}