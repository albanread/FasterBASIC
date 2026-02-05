//
// memory_mgmt.c
// FasterBASIC QBE Runtime Library - Memory Management
//
// This file provides additional memory management utilities.
// Most memory management is handled in other modules:
// - String reference counting in string_ops.c
// - Array allocation in array_ops.c
// - Arena allocation in basic_runtime.c
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// =============================================================================
// Memory Debugging (optional, for development)
// =============================================================================

#ifdef DEBUG_MEMORY
static size_t g_allocations = 0;
static size_t g_deallocations = 0;
static size_t g_bytes_allocated = 0;

void basic_mem_stats(void) {
    printf("Memory Statistics:\n");
    printf("  Allocations:   %zu\n", g_allocations);
    printf("  Deallocations: %zu\n", g_deallocations);
    printf("  Bytes:         %zu\n", g_bytes_allocated);
    printf("  Leaked:        %zu\n", g_allocations - g_deallocations);
}
#endif

// =============================================================================
// Safe Memory Allocation (with error checking)
// =============================================================================

void* basic_malloc(size_t size) {
    void* ptr = malloc(size);
    if (!ptr) {
        basic_error_msg("Out of memory");
        return NULL;
    }
    
#ifdef DEBUG_MEMORY
    g_allocations++;
    g_bytes_allocated += size;
#endif
    
    return ptr;
}

void* basic_calloc(size_t count, size_t size) {
    void* ptr = calloc(count, size);
    if (!ptr) {
        basic_error_msg("Out of memory");
        return NULL;
    }
    
#ifdef DEBUG_MEMORY
    g_allocations++;
    g_bytes_allocated += (count * size);
#endif
    
    return ptr;
}

void* basic_realloc(void* ptr, size_t size) {
    void* new_ptr = realloc(ptr, size);
    if (!new_ptr) {
        basic_error_msg("Out of memory");
        return NULL;
    }
    
    return new_ptr;
}

void basic_free(void* ptr) {
    if (!ptr) return;
    
#ifdef DEBUG_MEMORY
    g_deallocations++;
#endif
    
    free(ptr);
}

// =============================================================================
// Memory Utilities
// =============================================================================

void* basic_memcpy(void* dest, const void* src, size_t n) {
    return memcpy(dest, src, n);
}

void* basic_memset(void* ptr, int value, size_t n) {
    return memset(ptr, value, n);
}

int basic_memcmp(const void* ptr1, const void* ptr2, size_t n) {
    return memcmp(ptr1, ptr2, n);
}

// =============================================================================
// String Duplication (utility)
// =============================================================================

char* basic_strdup(const char* str) {
    if (!str) return NULL;
    
    size_t len = strlen(str);
    char* dup = (char*)basic_malloc(len + 1);
    if (!dup) return NULL;
    
    memcpy(dup, str, len + 1);
    return dup;
}

// =============================================================================
// Stack Safety (for deep recursion detection)
// =============================================================================

#ifdef STACK_CHECK
static size_t g_call_depth = 0;
#define MAX_CALL_DEPTH 10000

void basic_push_call(void) {
    g_call_depth++;
    if (g_call_depth > MAX_CALL_DEPTH) {
        basic_error_msg("Stack overflow (too much recursion)");
    }
}

void basic_pop_call(void) {
    if (g_call_depth > 0) {
        g_call_depth--;
    }
}

size_t basic_call_depth(void) {
    return g_call_depth;
}
#endif