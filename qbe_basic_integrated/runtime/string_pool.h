//
// string_pool.h
// FasterBASIC Runtime - String Descriptor Pool
//
// Implements efficient pooling of string descriptors to minimize malloc/free overhead.
// Uses a free-list approach for O(1) allocation/deallocation.
//
// Benefits:
// - Reduced allocation overhead (pool operations vs heap operations)
// - Better cache locality (descriptors in contiguous memory)
// - Reduced heap fragmentation
// - Faster allocation/deallocation
// - Automatic memory reuse
//

#ifndef STRING_POOL_H
#define STRING_POOL_H

#include <stdint.h>
#include <stdlib.h>
#include <stdbool.h>
#include <string.h>
#include "string_descriptor.h"  // Use canonical StringDescriptor definition

#ifdef __cplusplus
extern "C" {
#endif

//
// NOTE: StringDescriptor is defined in string_descriptor.h
// This file provides pooling infrastructure for StringDescriptor instances.
//

//
// StringDescriptorPool: Manages a pool of reusable descriptors
//
typedef struct StringDescriptorSlab StringDescriptorSlab;

struct StringDescriptorSlab {
    StringDescriptor  descriptors[256];  // 256 descriptors per slab (10KB)
    StringDescriptorSlab* next;          // Next slab in chain
    uint32_t          allocated_count;   // Number of descriptors in use
};

typedef struct {
    StringDescriptor*     free_list;     // Free list head (linked via data pointer)
    StringDescriptorSlab* slabs;         // Chain of slabs
    size_t                total_slabs;   // Number of slabs allocated
    size_t                total_allocated; // Total descriptors in use
    size_t                total_capacity;  // Total descriptors available
    size_t                peak_usage;    // Peak number of descriptors in use
    size_t                alloc_count;   // Total allocations (for statistics)
    size_t                free_count;    // Total frees (for statistics)
} StringDescriptorPool;

//
// Global pool instance (initialized at runtime startup)
//
extern StringDescriptorPool g_string_pool;

//
// Pool Management Functions
//

// Initialize the string descriptor pool
// Call once at program startup
void string_pool_init(StringDescriptorPool* pool);

// Cleanup the string descriptor pool
// Call once at program shutdown (frees all slabs)
void string_pool_cleanup(StringDescriptorPool* pool);

// Allocate a descriptor from the pool
// Returns a zeroed descriptor ready for use
StringDescriptor* string_pool_alloc(StringDescriptorPool* pool);

// Free a descriptor back to the pool
// The descriptor's data and utf8_cache should already be freed
void string_pool_free(StringDescriptorPool* pool, StringDescriptor* desc);

// Get pool statistics (for debugging/profiling)
void string_pool_stats(const StringDescriptorPool* pool, 
                       size_t* out_allocated,
                       size_t* out_capacity,
                       size_t* out_peak_usage,
                       size_t* out_slabs);

// Reset pool statistics
void string_pool_reset_stats(StringDescriptorPool* pool);

//
// Convenience wrappers using global pool
//

static inline StringDescriptor* string_desc_alloc(void) {
    return string_pool_alloc(&g_string_pool);
}

static inline void string_desc_free(StringDescriptor* desc) {
    string_pool_free(&g_string_pool, desc);
}

//
// String Descriptor Helper Functions
//

// Initialize a descriptor to empty state
static inline void string_desc_init_empty(StringDescriptor* desc) {
    desc->data = NULL;
    desc->length = 0;
    desc->capacity = 0;
    desc->refcount = 1;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
}

// Free a descriptor's data (but not the descriptor itself)
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
    
    // Allocate new data buffer - size depends on encoding
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
    
    dest->length = src->length;
    dest->capacity = src->length; // Set capacity to actual length
    dest->refcount = 1;
    dest->encoding = src->encoding; // Preserve encoding
    dest->dirty = 1;
    dest->utf8_cache = NULL; // Don't copy cache, will regenerate if needed
    
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

//
// Memory Pool Configuration
//

// Descriptors per slab (256 = 10KB per slab)
#define STRING_POOL_SLAB_SIZE 256

// Initial number of slabs to pre-allocate
#define STRING_POOL_INITIAL_SLABS 1

// Maximum number of slabs (safety limit)
#define STRING_POOL_MAX_SLABS 1024

//
// Debug and Profiling
//

#ifdef STRING_POOL_DEBUG
    #define STRING_POOL_TRACE(fmt, ...) \
        fprintf(stderr, "[STRING_POOL] " fmt "\n", ##__VA_ARGS__)
#else
    #define STRING_POOL_TRACE(fmt, ...)
#endif

// Validate pool integrity (for debugging)
bool string_pool_validate(const StringDescriptorPool* pool);

// Print pool statistics
void string_pool_print_stats(const StringDescriptorPool* pool);

// Check for memory leaks (descriptors not returned to pool)
void string_pool_check_leaks(const StringDescriptorPool* pool);

//
// Advanced Features
//

// Pre-allocate descriptors to avoid allocation during critical sections
void string_pool_preallocate(StringDescriptorPool* pool, size_t count);

// Compact pool (free unused slabs if usage is low)
void string_pool_compact(StringDescriptorPool* pool);

// Get descriptor usage percentage
static inline double string_pool_usage_percent(const StringDescriptorPool* pool) {
    if (pool->total_capacity == 0) return 0.0;
    return (double)pool->total_allocated / (double)pool->total_capacity * 100.0;
}

#ifdef __cplusplus
}
#endif

#endif // STRING_POOL_H