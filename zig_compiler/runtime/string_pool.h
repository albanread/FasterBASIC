//
// string_pool.h
// FasterBASIC Runtime - String Descriptor Pool
//
// Phase 4 migration: delegates to the generic SammSlabPool infrastructure.
// StringDescriptor (40 bytes) is allocated from g_string_desc_pool
// defined in samm_pool.c, initialised by samm_init(), destroyed by
// samm_shutdown().
//
// This header preserves the public convenience API:
//   string_desc_alloc()    — allocate a zeroed descriptor from the pool
//   string_desc_free()     — return a descriptor to the pool
//   string_desc_init_empty() — initialise descriptor fields
//   string_desc_free_data()  — free a descriptor's data buffers
//   string_desc_clone()    — deep-copy a descriptor (pool-allocated)
//   string_desc_retain()   — increment refcount
//   string_desc_release()  — decrement refcount, free if 0
//
// Legacy types (StringDescriptorPool, StringDescriptorSlab) and their
// management functions have been removed.  All pool operations now go
// through SammSlabPool, giving strings the same stats, validation,
// and leak-check infrastructure as lists and objects.
//

#ifndef STRING_POOL_H
#define STRING_POOL_H

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "string_descriptor.h"
#include "samm_pool.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Pool-based Descriptor Allocation                                           */
/*                                                                            */
/* g_string_desc_pool is a SammSlabPool with 40-byte slots (matching          */
/* sizeof(StringDescriptor)) and 256 slots per slab.  It is declared in       */
/* samm_pool.h and defined in samm_pool.c.                                    */
/* ========================================================================= */

//
// Allocate a descriptor from the pool.
// Returns a descriptor initialised to empty state (refcount=1, encoding=ASCII,
// all pointers NULL, dirty=1).
//
static inline StringDescriptor* string_desc_alloc(void) {
    StringDescriptor* desc = (StringDescriptor*)samm_slab_pool_alloc(&g_string_desc_pool);
    if (desc) {
        // samm_slab_pool_alloc returns zeroed memory — set non-zero defaults
        desc->refcount = 1;
        desc->encoding = STRING_ENCODING_ASCII;
        desc->dirty    = 1;
    }
    return desc;
}

//
// Return a descriptor to the pool.
// The descriptor's data and utf8_cache should already be freed
// (string_desc_free_data handles that).  As a safety net, this
// function calls string_desc_free_data before returning the
// descriptor shell to the pool.
//
static inline void string_desc_free(StringDescriptor* desc) {
    if (!desc) return;
    // Safety: free any remaining buffers
    if (desc->data) {
        free(desc->data);
        desc->data = NULL;
    }
    if (desc->utf8_cache) {
        free(desc->utf8_cache);
        desc->utf8_cache = NULL;
    }
    samm_slab_pool_free(&g_string_desc_pool, desc);
}

/* ========================================================================= */
/* String Descriptor Helper Functions                                         */
/* ========================================================================= */

// Initialize a descriptor to empty state
static inline void string_desc_init_empty(StringDescriptor* desc) {
    desc->data = NULL;
    desc->length = 0;
    desc->capacity = 0;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_ASCII;
    desc->dirty = 1;
    desc->_padding[0] = 0;
    desc->_padding[1] = 0;
    desc->utf8_cache = NULL;
}

// Free a descriptor's data buffers (but not the descriptor itself)
static inline void string_desc_free_data(StringDescriptor* desc) {
    if (desc) {
        if (desc->data) {
            free(desc->data);
            desc->data = NULL;
        }
        if (desc->utf8_cache) {
            free(desc->utf8_cache);
            desc->utf8_cache = NULL;
        }
        desc->length = 0;
        desc->capacity = 0;
        desc->dirty = 1;
    }
}

// Clone a descriptor (allocates new descriptor from pool)
// NOTE: This is a pool-based clone. Use string_clone() from string_descriptor.h
// for encoding-aware cloning that preserves ASCII vs UTF-32.
static inline StringDescriptor* string_desc_clone(const StringDescriptor* src) {
    if (!src) return NULL;

    StringDescriptor* dest = string_desc_alloc();
    if (!dest) return NULL;

    // Allocate new data buffer — size depends on encoding
    if (src->length > 0 && src->data) {
        size_t elem_size = (src->encoding == STRING_ENCODING_ASCII) ? sizeof(uint8_t) : sizeof(uint32_t);
        size_t bytes = src->length * elem_size;
        dest->data = malloc(bytes);
        if (!dest->data) {
            string_desc_free(dest);
            return NULL;
        }
        memcpy(dest->data, src->data, bytes);
    } else {
        dest->data = NULL;
    }

    dest->length   = src->length;
    dest->capacity = src->length;
    dest->refcount = 1;
    dest->encoding = src->encoding;
    dest->dirty    = 1;
    dest->utf8_cache = NULL;

    return dest;
}

// Retain a descriptor (increment refcount)
static inline StringDescriptor* string_desc_retain(StringDescriptor* desc) {
    if (desc) {
        desc->refcount++;
    }
    return desc;
}

// Release a descriptor (decrement refcount, free if 0)
static inline void string_desc_release(StringDescriptor* desc) {
    if (!desc) return;

    desc->refcount--;
    if (desc->refcount <= 0) {
        // Free data and cache
        string_desc_free_data(desc);
        // Return descriptor to pool
        string_desc_free(desc);
    }
}

/* ========================================================================= */
/* Legacy Compatibility                                                       */
/*                                                                            */
/* These thin wrappers preserve call sites that still reference the old       */
/* string_pool_alloc / string_pool_free API through g_string_pool.           */
/* They delegate directly to the SammSlabPool-based functions above.          */
/* New code should use string_desc_alloc() / string_desc_free() directly.    */
/* ========================================================================= */

// Legacy: the old pool type is no longer used, but some call sites reference
// "g_string_pool" or pass a pool pointer.  Provide a minimal typedef so
// those sites compile, then the functions ignore the pool pointer and use
// g_string_desc_pool directly.

typedef struct {
    int _unused;  // Placeholder — no longer functional
} StringDescriptorPool;

extern StringDescriptorPool g_string_pool;

static inline void string_pool_init(StringDescriptorPool* pool) {
    (void)pool;
    // Actual init is done by samm_init() → samm_slab_pool_init(&g_string_desc_pool, ...)
}

static inline void string_pool_cleanup(StringDescriptorPool* pool) {
    (void)pool;
    // Actual cleanup is done by samm_shutdown() → samm_slab_pool_destroy(&g_string_desc_pool)
    // Leak warnings are handled by samm_slab_pool_destroy.
}

static inline StringDescriptor* string_pool_alloc(StringDescriptorPool* pool) {
    (void)pool;
    return string_desc_alloc();
}

static inline void string_pool_free(StringDescriptorPool* pool, StringDescriptor* desc) {
    (void)pool;
    string_desc_free(desc);
}

static inline void string_pool_stats(const StringDescriptorPool* pool,
                                     size_t* out_allocated,
                                     size_t* out_capacity,
                                     size_t* out_peak_usage,
                                     size_t* out_slabs) {
    (void)pool;
    samm_slab_pool_stats(&g_string_desc_pool,
                         out_allocated, out_capacity, out_peak_usage,
                         out_slabs, NULL, NULL);
}

static inline bool string_pool_validate(const StringDescriptorPool* pool) {
    (void)pool;
    return samm_slab_pool_validate(&g_string_desc_pool);
}

static inline void string_pool_print_stats(const StringDescriptorPool* pool) {
    (void)pool;
    samm_slab_pool_print_stats(&g_string_desc_pool);
}

static inline void string_pool_check_leaks(const StringDescriptorPool* pool) {
    (void)pool;
    samm_slab_pool_check_leaks(&g_string_desc_pool);
}

static inline double string_pool_usage_percent(const StringDescriptorPool* pool) {
    (void)pool;
    return samm_slab_pool_usage_percent(&g_string_desc_pool);
}

// No-ops for features not applicable to generic pool
static inline void string_pool_reset_stats(StringDescriptorPool* pool) { (void)pool; }
static inline void string_pool_preallocate(StringDescriptorPool* pool, size_t count) { (void)pool; (void)count; }
static inline void string_pool_compact(StringDescriptorPool* pool) { (void)pool; }

#ifdef __cplusplus
}
#endif

#endif // STRING_POOL_H