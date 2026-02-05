//
// string_pool.c
// FasterBASIC Runtime - String Descriptor Pool Implementation
//
// Implements efficient pooling of string descriptors using a slab allocator
// with free-list management for O(1) allocation/deallocation.
//

#include "string_pool.h"
#include <stdio.h>
#include <assert.h>

// Global string descriptor pool instance
StringDescriptorPool g_string_pool = {0};

//
// Private Helper Functions
//

// Allocate a new slab and add it to the pool
static bool pool_add_slab(StringDescriptorPool* pool) {
    // Check slab limit
    if (pool->total_slabs >= STRING_POOL_MAX_SLABS) {
        fprintf(stderr, "ERROR: String pool maximum slabs reached (%d)\n", STRING_POOL_MAX_SLABS);
        return false;
    }
    
    // Allocate new slab
    StringDescriptorSlab* slab = (StringDescriptorSlab*)malloc(sizeof(StringDescriptorSlab));
    if (!slab) {
        fprintf(stderr, "ERROR: Failed to allocate string descriptor slab\n");
        return false;
    }
    
    // Initialize slab
    memset(slab, 0, sizeof(StringDescriptorSlab));
    slab->next = pool->slabs;
    slab->allocated_count = 0;
    
    // Add all descriptors from this slab to the free list
    for (size_t i = 0; i < STRING_POOL_SLAB_SIZE; i++) {
        StringDescriptor* desc = &slab->descriptors[i];
        // Initialize to zero
        memset(desc, 0, sizeof(StringDescriptor));
        // Link into free list (reuse data pointer as next pointer)
        desc->data = (uint32_t*)pool->free_list;
        pool->free_list = desc;
    }
    
    // Update pool statistics
    pool->slabs = slab;
    pool->total_slabs++;
    pool->total_capacity += STRING_POOL_SLAB_SIZE;
    
    STRING_POOL_TRACE("Added slab #%zu (%zu descriptors, capacity=%zu)",
                      pool->total_slabs, STRING_POOL_SLAB_SIZE, pool->total_capacity);
    
    return true;
}

//
// Public API Implementation
//

void string_pool_init(StringDescriptorPool* pool) {
    if (!pool) return;
    
    memset(pool, 0, sizeof(StringDescriptorPool));
    pool->free_list = NULL;
    pool->slabs = NULL;
    pool->total_slabs = 0;
    pool->total_allocated = 0;
    pool->total_capacity = 0;
    pool->peak_usage = 0;
    pool->alloc_count = 0;
    pool->free_count = 0;
    
    // Pre-allocate initial slabs
    for (size_t i = 0; i < STRING_POOL_INITIAL_SLABS; i++) {
        if (!pool_add_slab(pool)) {
            fprintf(stderr, "WARNING: Failed to pre-allocate string pool slab %zu\n", i);
            break;
        }
    }
    
    STRING_POOL_TRACE("Initialized pool with %zu slabs (%zu descriptors)",
                      pool->total_slabs, pool->total_capacity);
}

void string_pool_cleanup(StringDescriptorPool* pool) {
    if (!pool) return;
    
    STRING_POOL_TRACE("Cleaning up pool: %zu slabs, %zu allocated, %zu peak",
                      pool->total_slabs, pool->total_allocated, pool->peak_usage);
    
    // Check for leaks
    if (pool->total_allocated > 0) {
        fprintf(stderr, "WARNING: String pool has %zu leaked descriptors\n", 
                pool->total_allocated);
    }
    
    // Free all slabs
    StringDescriptorSlab* slab = pool->slabs;
    while (slab) {
        StringDescriptorSlab* next = slab->next;
        
        // Free any remaining data in descriptors
        for (size_t i = 0; i < STRING_POOL_SLAB_SIZE; i++) {
            StringDescriptor* desc = &slab->descriptors[i];
            if (desc->data && desc->length > 0) {
                free(desc->data);
                desc->data = NULL;
            }
            if (desc->utf8_cache) {
                free(desc->utf8_cache);
                desc->utf8_cache = NULL;
            }
        }
        
        free(slab);
        slab = next;
    }
    
    // Reset pool
    memset(pool, 0, sizeof(StringDescriptorPool));
}

StringDescriptor* string_pool_alloc(StringDescriptorPool* pool) {
    if (!pool) return NULL;
    
    // If free list is empty, allocate a new slab
    if (!pool->free_list) {
        if (!pool_add_slab(pool)) {
            // Failed to grow pool, fall back to malloc
            fprintf(stderr, "WARNING: String pool exhausted, using malloc\n");
            StringDescriptor* desc = (StringDescriptor*)malloc(sizeof(StringDescriptor));
            if (desc) {
                memset(desc, 0, sizeof(StringDescriptor));
                string_desc_init_empty(desc);
            }
            return desc;
        }
    }
    
    // Pop descriptor from free list
    StringDescriptor* desc = pool->free_list;
    pool->free_list = (StringDescriptor*)desc->data; // Next pointer was stored in data
    
    // Initialize descriptor to empty state
    string_desc_init_empty(desc);
    
    // Update statistics
    pool->total_allocated++;
    pool->alloc_count++;
    
    if (pool->total_allocated > pool->peak_usage) {
        pool->peak_usage = pool->total_allocated;
    }
    
    STRING_POOL_TRACE("Allocated descriptor %p (allocated=%zu, capacity=%zu, free_list=%p)",
                      (void*)desc, pool->total_allocated, pool->total_capacity, 
                      (void*)pool->free_list);
    
    return desc;
}

void string_pool_free(StringDescriptorPool* pool, StringDescriptor* desc) {
    if (!pool || !desc) return;
    
    // Sanity check: refcount should be 0
    if (desc->refcount > 0) {
        fprintf(stderr, "WARNING: Freeing descriptor with refcount=%d\n", desc->refcount);
    }
    
    // Free descriptor's data and cache (should already be done, but be safe)
    string_desc_free_data(desc);
    
    // Push descriptor onto free list
    desc->data = (uint32_t*)pool->free_list;
    pool->free_list = desc;
    
    // Update statistics
    if (pool->total_allocated > 0) {
        pool->total_allocated--;
    }
    pool->free_count++;
    
    STRING_POOL_TRACE("Freed descriptor %p (allocated=%zu, capacity=%zu, free_list=%p)",
                      (void*)desc, pool->total_allocated, pool->total_capacity,
                      (void*)pool->free_list);
}

void string_pool_stats(const StringDescriptorPool* pool,
                       size_t* out_allocated,
                       size_t* out_capacity,
                       size_t* out_peak_usage,
                       size_t* out_slabs) {
    if (!pool) return;
    
    if (out_allocated) *out_allocated = pool->total_allocated;
    if (out_capacity) *out_capacity = pool->total_capacity;
    if (out_peak_usage) *out_peak_usage = pool->peak_usage;
    if (out_slabs) *out_slabs = pool->total_slabs;
}

void string_pool_reset_stats(StringDescriptorPool* pool) {
    if (!pool) return;
    
    pool->peak_usage = pool->total_allocated;
    pool->alloc_count = 0;
    pool->free_count = 0;
}

bool string_pool_validate(const StringDescriptorPool* pool) {
    if (!pool) return false;
    
    // Count descriptors in free list
    size_t free_count = 0;
    StringDescriptor* desc = pool->free_list;
    const size_t max_iterations = pool->total_capacity + 100; // Safety limit
    
    while (desc && free_count < max_iterations) {
        free_count++;
        desc = (StringDescriptor*)desc->data;
    }
    
    if (free_count >= max_iterations) {
        fprintf(stderr, "ERROR: Free list appears to be corrupted (cycle detected)\n");
        return false;
    }
    
    // Check: allocated + free should equal capacity
    size_t expected_free = pool->total_capacity - pool->total_allocated;
    if (free_count != expected_free) {
        fprintf(stderr, "ERROR: Free list count mismatch: found=%zu, expected=%zu\n",
                free_count, expected_free);
        fprintf(stderr, "       (allocated=%zu, capacity=%zu)\n",
                pool->total_allocated, pool->total_capacity);
        return false;
    }
    
    return true;
}

void string_pool_print_stats(const StringDescriptorPool* pool) {
    if (!pool) return;
    
    printf("=== String Descriptor Pool Statistics ===\n");
    printf("  Slabs:          %zu\n", pool->total_slabs);
    printf("  Capacity:       %zu descriptors\n", pool->total_capacity);
    printf("  Allocated:      %zu descriptors\n", pool->total_allocated);
    printf("  Free:           %zu descriptors\n", pool->total_capacity - pool->total_allocated);
    printf("  Peak Usage:     %zu descriptors\n", pool->peak_usage);
    printf("  Usage:          %.1f%%\n", string_pool_usage_percent(pool));
    printf("  Total Allocs:   %zu\n", pool->alloc_count);
    printf("  Total Frees:    %zu\n", pool->free_count);
    printf("  Net Allocations: %+zd\n", (ssize_t)pool->alloc_count - (ssize_t)pool->free_count);
    printf("==========================================\n");
}

void string_pool_check_leaks(const StringDescriptorPool* pool) {
    if (!pool) return;
    
    if (pool->total_allocated == 0) {
        printf("No string descriptor leaks detected.\n");
        return;
    }
    
    printf("WARNING: %zu string descriptors not freed\n", pool->total_allocated);
    
    // Try to find leaked descriptors
    size_t leaked = 0;
    StringDescriptorSlab* slab = pool->slabs;
    
    while (slab) {
        for (size_t i = 0; i < STRING_POOL_SLAB_SIZE; i++) {
            StringDescriptor* desc = &slab->descriptors[i];
            
            // Check if this descriptor is in the free list
            bool in_free_list = false;
            StringDescriptor* free_desc = pool->free_list;
            while (free_desc) {
                if (free_desc == desc) {
                    in_free_list = true;
                    break;
                }
                free_desc = (StringDescriptor*)free_desc->data;
            }
            
            // If not in free list and has data, it's likely leaked
            if (!in_free_list && (desc->data || desc->length > 0 || desc->refcount > 0)) {
                leaked++;
                printf("  Leaked descriptor #%zu: data=%p, length=%lld, capacity=%lld, refcount=%d\n",
                       leaked, (void*)desc->data, (long long)desc->length, 
                       (long long)desc->capacity, desc->refcount);
            }
        }
        slab = slab->next;
    }
}

void string_pool_preallocate(StringDescriptorPool* pool, size_t count) {
    if (!pool) return;
    
    // Calculate how many slabs we need
    size_t available = pool->total_capacity - pool->total_allocated;
    if (available >= count) {
        return; // Already have enough
    }
    
    size_t needed = count - available;
    size_t slabs_needed = (needed + STRING_POOL_SLAB_SIZE - 1) / STRING_POOL_SLAB_SIZE;
    
    STRING_POOL_TRACE("Pre-allocating %zu slabs for %zu descriptors", slabs_needed, count);
    
    for (size_t i = 0; i < slabs_needed; i++) {
        if (!pool_add_slab(pool)) {
            fprintf(stderr, "WARNING: Failed to pre-allocate slab %zu of %zu\n", 
                    i + 1, slabs_needed);
            break;
        }
    }
}

void string_pool_compact(StringDescriptorPool* pool) {
    if (!pool) return;
    
    // Only compact if usage is very low (< 25%)
    double usage = string_pool_usage_percent(pool);
    if (usage >= 25.0) {
        return; // Not worth compacting
    }
    
    // For now, we don't implement actual compaction (would require complex bookkeeping)
    // Just log that compaction would be beneficial
    STRING_POOL_TRACE("Pool usage is %.1f%% - compaction would be beneficial", usage);
}