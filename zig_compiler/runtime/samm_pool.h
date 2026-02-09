/*
 * samm_pool.h
 * FasterBASIC Runtime — Generic Slab Pool Allocator
 *
 * Type-agnostic fixed-size slab pool with intrusive free-list.
 * Parameterized by slot_size and slots_per_slab at init time.
 *
 * Used by SAMM to pool fixed-size runtime descriptors:
 *   - ListHeader  (32 B, 256 slots/slab)
 *   - ListAtom    (24 B, 512 slots/slab)
 *   - Future: object size-class pools (Phase 3)
 *
 * Design:
 *   Each slab is a contiguous allocation of (header + N * slot_size) bytes.
 *   Free slots are linked via an intrusive pointer overlay at the start of
 *   each slot (all slot sizes >= 8 bytes, so this is always safe).
 *   Allocation is O(1) — pop from free list head.
 *   Deallocation is O(1) — push onto free list head.
 *
 * Thread safety:
 *   A per-pool pthread_mutex protects alloc/free. Contention is expected
 *   to be low (main thread allocs, background worker frees, minimal overlap).
 *
 * See SAMM_POOL_DESIGN.md §4.1 / §9 Phase 5 for design rationale.
 */

#ifndef SAMM_POOL_H
#define SAMM_POOL_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#include <pthread.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Slab Structure                                                             */
/* ========================================================================= */

/*
 * Opaque handle to the Zig implementation of the slab pool.
 *
 * The actual struct is defined in runtime/samm_pool.zig as a union wrapping
 * the generic SlabPool(S, N) type.
 */
typedef struct SammSlabPool SammSlabPool;


/* ========================================================================= */
/* Pool API                                                                   */
/* ========================================================================= */

/**
 * Initialise a slab pool for a given slot size.
 *
 * @param pool           Pool to initialise (caller owns storage)
 * @param slot_size      Bytes per slot (must be >= 8)
 * @param slots_per_slab Number of slots per slab allocation
 * @param name           Human-readable name for diagnostics (e.g. "ListHeader")
 *
 * Pre-allocates SAMM_SLAB_POOL_INITIAL_SLABS slabs so the first alloc
 * does not hit the system allocator.
 */
void samm_slab_pool_init(SammSlabPool* pool,
                         uint32_t slot_size,
                         uint32_t slots_per_slab,
                         const char* name);

/**
 * Destroy a slab pool and free all slabs back to the OS.
 *
 * Reports leaked slots (in_use > 0) to stderr as a diagnostic.
 * After this call, the pool must not be used without re-initialisation.
 *
 * @param pool  Pool to destroy
 */
void samm_slab_pool_destroy(SammSlabPool* pool);

/**
 * Allocate one slot from the pool.
 *
 * Returns a zeroed block of pool->slot_size bytes.
 * If the free list is empty, a new slab is allocated from the system.
 * If slab allocation fails (MAX_SLABS reached), falls back to malloc
 * and prints a warning.
 *
 * Thread-safe (acquires pool lock).
 *
 * @param pool  Pool to allocate from
 * @return      Pointer to zeroed slot, or NULL on total failure
 */
void* samm_slab_pool_alloc(SammSlabPool* pool);

/**
 * Return one slot to the pool's free list.
 *
 * The slot's contents are NOT zeroed at free time — zeroing happens
 * at the next allocation.  The first sizeof(void*) bytes are overwritten
 * with the free-list link.
 *
 * Thread-safe (acquires pool lock).
 *
 * @param pool  Pool that owns the slot
 * @param ptr   Pointer previously returned by samm_slab_pool_alloc()
 */
void samm_slab_pool_free(SammSlabPool* pool, void* ptr);

/* ========================================================================= */
/* Pool Statistics & Diagnostics                                              */
/* ========================================================================= */

/**
 * Get pool statistics (snapshot, not locked — advisory only).
 *
 * Any output pointer may be NULL to skip that stat.
 */
void samm_slab_pool_stats(const SammSlabPool* pool,
                          size_t* out_in_use,
                          size_t* out_capacity,
                          size_t* out_peak_use,
                          size_t* out_slabs,
                          size_t* out_allocs,
                          size_t* out_frees);

/**
 * Print pool statistics to stderr.
 */
void samm_slab_pool_print_stats(const SammSlabPool* pool);

/**
 * Validate pool integrity: verify free list count + in_use == capacity.
 *
 * @param pool  Pool to validate
 * @return      true if valid, false if corruption detected
 */
bool samm_slab_pool_validate(const SammSlabPool* pool);

/**
 * Report leaked slots (allocated but not freed) to stderr.
 * Useful at shutdown for diagnostics.
 */
void samm_slab_pool_check_leaks(const SammSlabPool* pool);

/**
 * Get the total_allocs counter for a pool.
 * This accessor replaces direct field access (pool->total_allocs).
 */
size_t samm_slab_pool_total_allocs(const SammSlabPool* pool);

/**
 * Get usage percentage (in_use / capacity * 100).
 */
/**
 * Get usage percentage (in_use / capacity * 100).
 * Implemented in samm_pool.zig — cannot inline because the Zig pool
 * struct layout differs from the C SammSlabPool typedef.
 */
double samm_slab_pool_usage_percent(const SammSlabPool* pool);

/* ========================================================================= */
/* Global Pool Instances for String Descriptors (Phase 4 migration)           */
/*                                                                            */
/* Replaces the legacy StringDescriptorPool (string_pool.c) with the generic  */
/* SammSlabPool.  StringDescriptor is 40 bytes; 256 descriptors per slab.     */
/*                                                                            */
/* Defined in samm_pool.c, initialised by samm_init() via                     */
/* samm_slab_pool_init(), destroyed by samm_shutdown() via                    */
/* samm_slab_pool_destroy().                                                  */
/* ========================================================================= */

extern SammSlabPool* g_string_desc_pool;  /* 40-byte slots, 256/slab (ptr to Zig pool instance) */

#define STRING_DESC_POOL_SLOT_SIZE      40
#define STRING_DESC_POOL_SLOTS_PER_SLAB 256

/* ========================================================================= */
/* Global Pool Instances for List Types (Phase 2)                             */
/*                                                                            */
/* Defined in samm_pool.c, initialised by samm_init() via                     */
/* samm_slab_pool_init(), destroyed by samm_shutdown() via                    */
/* samm_slab_pool_destroy().                                                  */
/* ========================================================================= */

extern SammSlabPool* g_list_header_pool;  /* 32-byte slots, 256/slab (ptr to Zig pool instance) */
extern SammSlabPool* g_list_atom_pool;    /* 24-byte slots, 512/slab (ptr to Zig pool instance) */

/* Convenience sizing constants */
#define LIST_HEADER_POOL_SLOT_SIZE      32
#define LIST_HEADER_POOL_SLOTS_PER_SLAB 256

#define LIST_ATOM_POOL_SLOT_SIZE        24
#define LIST_ATOM_POOL_SLOTS_PER_SLAB   512

/* ========================================================================= */
/* Object Size-Class Pools (Phase 3)                                          */
/*                                                                            */
/* Class objects have variable sizes (header 16 B + N fields × 8 B), but      */
/* each class has a fixed size known at compile time.  We round up to the     */
/* nearest power-of-two size class and allocate from the corresponding pool.  */
/*                                                                            */
/* Objects > 1024 B fall back to malloc (overflow, tracked with size_class    */
/* SAMM_SIZE_CLASS_NONE = 0xFF).                                              */
/* ========================================================================= */

/* Number of object size classes */
#define SAMM_OBJECT_SIZE_CLASSES    6

/* Size class index constants */
#define SAMM_SC_32      0       /* 17–32 B   (header-only, no fields)    */
#define SAMM_SC_64      1       /* 33–64 B   (1–6 fields)               */
#define SAMM_SC_128     2       /* 65–128 B  (7–14 fields)              */
#define SAMM_SC_256     3       /* 129–256 B (15–30 fields)             */
#define SAMM_SC_512     4       /* 257–512 B (large objects)            */
#define SAMM_SC_1024    5       /* 513–1024 B (very large objects)      */

/* Sentinel: object allocated via malloc (> 1024 B or unknown) */
#define SAMM_SIZE_CLASS_NONE    0xFF

/* Slot sizes for each size class */
static const uint32_t samm_object_slot_sizes[SAMM_OBJECT_SIZE_CLASSES] = {
    32, 64, 128, 256, 512, 1024
};

/* Slots per slab for each size class (128 each — ~4 KB to 128 KB per slab) */
static const uint32_t samm_object_slots_per_slab[SAMM_OBJECT_SIZE_CLASSES] = {
    128, 128, 128, 128, 64, 32
};

/* Pool name strings for diagnostics */
static const char* const samm_object_pool_names[SAMM_OBJECT_SIZE_CLASSES] = {
    "Object_32", "Object_64", "Object_128",
    "Object_256", "Object_512", "Object_1024"
};

/**
 * Map an object size (in bytes) to a size-class index (0–5).
 * Returns -1 for overflow objects (> 1024 B), which use malloc.
 *
 * Minimum object size is CLASS_HEADER_SIZE (16 B), which maps to class 0 (32 B).
 */
static inline int samm_size_to_class(size_t size) {
    if (size <= 32)   return SAMM_SC_32;
    if (size <= 64)   return SAMM_SC_64;
    if (size <= 128)  return SAMM_SC_128;
    if (size <= 256)  return SAMM_SC_256;
    if (size <= 512)  return SAMM_SC_512;
    if (size <= 1024) return SAMM_SC_1024;
    return -1;  /* overflow → malloc */
}

/**
 * Convert a size class index to the uint8_t stored in SAMMScope.
 * Returns SAMM_SIZE_CLASS_NONE for invalid / overflow classes.
 */
static inline uint8_t samm_class_to_u8(int sc) {
    if (sc >= 0 && sc < SAMM_OBJECT_SIZE_CLASSES) return (uint8_t)sc;
    return SAMM_SIZE_CLASS_NONE;
}

/* Global array of object size-class pools.
 * Defined in samm_pool.c, initialised by samm_init(). */
extern SammSlabPool* g_object_pools[SAMM_OBJECT_SIZE_CLASSES];

/* ========================================================================= */
/* Debug Tracing                                                              */
/* ========================================================================= */

#ifdef SAMM_POOL_DEBUG
    #define SAMM_POOL_TRACE(fmt, ...) \
        fprintf(stderr, "[SAMM_POOL] " fmt "\n", ##__VA_ARGS__)
#else
    #define SAMM_POOL_TRACE(fmt, ...)
#endif

#ifdef __cplusplus
}
#endif

#endif /* SAMM_POOL_H */