//
// array_ops.c
// FasterBASIC QBE Runtime Library - Array Operations
//
// This file implements dynamic array management with bounds checking.
// Arrays can be multi-dimensional and support OPTION BASE 0 or 1.
//

#include "basic_runtime.h"
#include "samm_bridge.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>

// =============================================================================
// Array Creation
// =============================================================================

BasicArray* array_new(char type_suffix, int32_t dimensions, int32_t* bounds, int32_t base) {
    if (dimensions <= 0 || dimensions > 8) {
        basic_error_msg("Invalid array dimensions");
        return NULL;
    }
    
    if (!bounds) {
        basic_error_msg("Array bounds not specified");
        return NULL;
    }
    
    BasicArray* array = (BasicArray*)malloc(sizeof(BasicArray));
    if (!array) {
        basic_error_msg("Out of memory (array allocation)");
        return NULL;
    }
    
    array->dimensions = dimensions;
    array->base = base;
    array->type_suffix = type_suffix;
    
    // Allocate bounds array: [lower1, upper1, lower2, upper2, ...]
    array->bounds = (int32_t*)malloc(dimensions * 2 * sizeof(int32_t));
    if (!array->bounds) {
        free(array);
        basic_error_msg("Out of memory (array bounds)");
        return NULL;
    }
    memcpy(array->bounds, bounds, dimensions * 2 * sizeof(int32_t));
    
    // Calculate strides for each dimension
    array->strides = (int32_t*)malloc(dimensions * sizeof(int32_t));
    if (!array->strides) {
        free(array->bounds);
        free(array);
        basic_error_msg("Out of memory (array strides)");
        return NULL;
    }
    
    // Determine element size based on type suffix
    switch (type_suffix) {
        case '%': // INTEGER
            array->element_size = sizeof(int32_t);
            break;
        case '&': // LONG
            array->element_size = sizeof(int64_t);
            break;
        case '!': // SINGLE
            array->element_size = sizeof(float);
            break;
        case '#': // DOUBLE
            array->element_size = sizeof(double);
            break;
        case '$': // STRING (StringDescriptor*)
            array->element_size = sizeof(StringDescriptor*);
            break;
        default:
            // Default to DOUBLE for untyped arrays
            array->element_size = sizeof(double);
            type_suffix = '#';
            break;
    }
    
    // Calculate total size and strides
    size_t total_elements = 1;
    for (int32_t i = dimensions - 1; i >= 0; i--) {
        int32_t lower = bounds[i * 2];
        int32_t upper = bounds[i * 2 + 1];
        int32_t size = upper - lower + 1;
        
        if (size <= 0) {
            free(array->strides);
            free(array->bounds);
            free(array);
            basic_error_msg("Invalid array bounds");
            return NULL;
        }
        
        array->strides[i] = (int32_t)total_elements;
        total_elements *= size;
    }
    
    // Allocate data
    size_t data_size = total_elements * array->element_size;
    array->data = malloc(data_size);
    if (!array->data) {
        free(array->strides);
        free(array->bounds);
        free(array);
        basic_error_msg("Out of memory (array data)");
        return NULL;
    }
    
    // Initialize to zero
    memset(array->data, 0, data_size);
    
    return array;
}

// Create array with custom element size (for UDTs)
BasicArray* array_new_custom(size_t element_size, int32_t dimensions, int32_t* bounds, int32_t base) {
    if (dimensions <= 0 || dimensions > 8) {
        basic_error_msg("Invalid array dimensions");
        return NULL;
    }
    
    if (!bounds) {
        basic_error_msg("Array bounds not specified");
        return NULL;
    }
    
    if (element_size == 0) {
        basic_error_msg("Invalid element size");
        return NULL;
    }
    
    BasicArray* array = (BasicArray*)malloc(sizeof(BasicArray));
    if (!array) {
        basic_error_msg("Out of memory (array allocation)");
        return NULL;
    }
    
    array->dimensions = dimensions;
    array->base = base;
    array->type_suffix = 'U';  // Special marker for UDT/custom arrays
    array->element_size = element_size;
    
    // Allocate bounds array: [lower1, upper1, lower2, upper2, ...]
    array->bounds = (int32_t*)malloc(dimensions * 2 * sizeof(int32_t));
    if (!array->bounds) {
        free(array);
        basic_error_msg("Out of memory (array bounds)");
        return NULL;
    }
    memcpy(array->bounds, bounds, dimensions * 2 * sizeof(int32_t));
    
    // Calculate strides for each dimension
    array->strides = (int32_t*)malloc(dimensions * sizeof(int32_t));
    if (!array->strides) {
        free(array->bounds);
        free(array);
        basic_error_msg("Out of memory (array strides)");
        return NULL;
    }
    
    // Calculate total size and strides
    size_t total_elements = 1;
    for (int32_t i = dimensions - 1; i >= 0; i--) {
        int32_t lower = bounds[i * 2];
        int32_t upper = bounds[i * 2 + 1];
        int32_t size = upper - lower + 1;
        
        if (size <= 0) {
            free(array->strides);
            free(array->bounds);
            free(array);
            basic_error_msg("Invalid array bounds");
            return NULL;
        }
        
        array->strides[i] = (int32_t)total_elements;
        total_elements *= size;
    }
    
    // Allocate data
    size_t data_size = total_elements * array->element_size;
    array->data = malloc(data_size);
    if (!array->data) {
        free(array->strides);
        free(array->bounds);
        free(array);
        basic_error_msg("Out of memory (array data)");
        return NULL;
    }
    
    // Initialize to zero
    memset(array->data, 0, data_size);
    
    return array;
}

// =============================================================================
// Array Destruction
// =============================================================================

void array_free(BasicArray* array) {
    if (!array) return;
    
    // If string array, release all strings
    if (array->type_suffix == '$' && array->data) {
        // Calculate total elements
        size_t total_elements = 1;
        for (int32_t i = 0; i < array->dimensions; i++) {
            int32_t lower = array->bounds[i * 2];
            int32_t upper = array->bounds[i * 2 + 1];
            total_elements *= (upper - lower + 1);
        }
        
        StringDescriptor** strings = (StringDescriptor**)array->data;
        for (size_t i = 0; i < total_elements; i++) {
            if (strings[i]) {
                string_release(strings[i]);
            }
        }
    }
    
    if (array->data) free(array->data);
    if (array->bounds) free(array->bounds);
    if (array->strides) free(array->strides);
    free(array);
}

// =============================================================================
// Index Calculation
// =============================================================================

static size_t calculate_offset(BasicArray* array, int32_t* indices) {
    size_t offset = 0;
    
    for (int32_t i = 0; i < array->dimensions; i++) {
        int32_t lower = array->bounds[i * 2];
        int32_t upper = array->bounds[i * 2 + 1];
        int32_t index = indices[i];
        
        // Bounds check
        if (index < lower || index > upper) {
            char msg[256];
            snprintf(msg, sizeof(msg), 
                "Array subscript out of range (dimension %d: %d not in [%d, %d])",
                i + 1, index, lower, upper);
            basic_error_msg(msg);
            return 0;
        }
        
        offset += (index - lower) * array->strides[i];
    }
    
    return offset;
}

// =============================================================================
// Get Element Address
// =============================================================================

void* array_get_address(BasicArray* array, int32_t* indices) {
    if (!array || !indices) return NULL;
    
    size_t offset = calculate_offset(array, indices);
    return (char*)array->data + (offset * array->element_size);
}

// =============================================================================
// Integer Array Operations
// =============================================================================

int32_t array_get_int(BasicArray* array, int32_t* indices) {
    if (!array || array->type_suffix != '%') {
        basic_error_msg("Type mismatch in array access");
        return 0;
    }
    
    size_t offset = calculate_offset(array, indices);
    int32_t* data = (int32_t*)array->data;
    return data[offset];
}

void array_set_int(BasicArray* array, int32_t* indices, int32_t value) {
    if (!array || array->type_suffix != '%') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    
    size_t offset = calculate_offset(array, indices);
    int32_t* data = (int32_t*)array->data;
    data[offset] = value;
}

// =============================================================================
// Long Array Operations
// =============================================================================

int64_t array_get_long(BasicArray* array, int32_t* indices) {
    if (!array || array->type_suffix != '&') {
        basic_error_msg("Type mismatch in array access");
        return 0;
    }
    
    size_t offset = calculate_offset(array, indices);
    int64_t* data = (int64_t*)array->data;
    return data[offset];
}

void array_set_long(BasicArray* array, int32_t* indices, int64_t value) {
    if (!array || array->type_suffix != '&') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    
    size_t offset = calculate_offset(array, indices);
    int64_t* data = (int64_t*)array->data;
    data[offset] = value;
}

// =============================================================================
// Float Array Operations
// =============================================================================

float array_get_float(BasicArray* array, int32_t* indices) {
    if (!array || array->type_suffix != '!') {
        basic_error_msg("Type mismatch in array access");
        return 0.0f;
    }
    
    size_t offset = calculate_offset(array, indices);
    float* data = (float*)array->data;
    return data[offset];
}

void array_set_float(BasicArray* array, int32_t* indices, float value) {
    if (!array || array->type_suffix != '!') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    
    size_t offset = calculate_offset(array, indices);
    float* data = (float*)array->data;
    data[offset] = value;
}

// =============================================================================
// Double Array Operations
// =============================================================================

double array_get_double(BasicArray* array, int32_t* indices) {
    if (!array || array->type_suffix != '#') {
        basic_error_msg("Type mismatch in array access");
        return 0.0;
    }
    
    size_t offset = calculate_offset(array, indices);
    double* data = (double*)array->data;
    return data[offset];
}

void array_set_double(BasicArray* array, int32_t* indices, double value) {
    if (!array || array->type_suffix != '#') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    
    size_t offset = calculate_offset(array, indices);
    double* data = (double*)array->data;
    data[offset] = value;
}

// =============================================================================
// String Array Operations
// =============================================================================

StringDescriptor* array_get_string(BasicArray* array, int32_t* indices) {
    if (!array || array->type_suffix != '$') {
        basic_error_msg("Type mismatch in array access");
        return string_new_capacity(0);
    }
    
    size_t offset = calculate_offset(array, indices);
    StringDescriptor** data = (StringDescriptor**)array->data;
    
    return string_retain(data[offset]);
}

void array_set_string(BasicArray* array, int32_t* indices, StringDescriptor* value) {
    if (!array || array->type_suffix != '$') {
        basic_error_msg("Type mismatch in array assignment");
        return;
    }
    
    size_t offset = calculate_offset(array, indices);
    StringDescriptor** data = (StringDescriptor**)array->data;
    
    if (data[offset]) {
        string_release(data[offset]);
    }
    
    data[offset] = string_retain(value);
}

// =============================================================================
// Array Bounds Inquiry
// =============================================================================

int32_t array_lbound(BasicArray* array, int32_t dimension) {
    if (!array || dimension < 1 || dimension > array->dimensions) {
        basic_error_msg("Invalid dimension in LBOUND");
        return 0;
    }
    
    return array->bounds[(dimension - 1) * 2];
}

int32_t array_ubound(BasicArray* array, int32_t dimension) {
    if (!array || dimension < 1 || dimension > array->dimensions) {
        basic_error_msg("Invalid dimension in UBOUND");
        return 0;
    }
    
    return array->bounds[(dimension - 1) * 2 + 1];
}

// =============================================================================
// Array Redimension
// =============================================================================

void array_redim(BasicArray* array, int32_t* new_bounds, bool preserve) {
    if (!array || !new_bounds) {
        basic_error_msg("Invalid REDIM parameters");
        return;
    }
    
    // Save old bounds and data if preserving
    void* old_data = NULL;
    int32_t* old_bounds = NULL;
    int32_t* old_strides = NULL;
    
    if (preserve && array->data) {
        // Save old state
        old_data = array->data;
        old_bounds = (int32_t*)malloc(array->dimensions * 2 * sizeof(int32_t));
        old_strides = (int32_t*)malloc(array->dimensions * sizeof(int32_t));
        if (!old_bounds || !old_strides) {
            if (old_bounds) free(old_bounds);
            if (old_strides) free(old_strides);
            basic_error_msg("Out of memory (REDIM PRESERVE)");
            return;
        }
        memcpy(old_bounds, array->bounds, array->dimensions * 2 * sizeof(int32_t));
        memcpy(old_strides, array->strides, array->dimensions * sizeof(int32_t));
    } else {
        // Not preserving - free old data
        if (array->data) {
            if (array->type_suffix == '$') {
                // Release all strings — untrack from SAMM first to avoid double-free
                size_t total_elements = 1;
                for (int32_t i = 0; i < array->dimensions; i++) {
                    int32_t lower = array->bounds[i * 2];
                    int32_t upper = array->bounds[i * 2 + 1];
                    total_elements *= (upper - lower + 1);
                }
                
                StringDescriptor** strings = (StringDescriptor**)array->data;
                for (size_t i = 0; i < total_elements; i++) {
                    if (strings[i]) {
                        samm_untrack(strings[i]);
                        string_release(strings[i]);
                    }
                }
            }
            free(array->data);
            array->data = NULL;
        }
    }
    
    // Update bounds
    memcpy(array->bounds, new_bounds, array->dimensions * 2 * sizeof(int32_t));
    
    // Recalculate strides and total size
    size_t new_total_elements = 1;
    for (int32_t i = array->dimensions - 1; i >= 0; i--) {
        int32_t lower = new_bounds[i * 2];
        int32_t upper = new_bounds[i * 2 + 1];
        int32_t size = upper - lower + 1;
        
        if (size <= 0) {
            if (old_bounds) free(old_bounds);
            if (old_strides) free(old_strides);
            if (old_data) free(old_data);
            basic_error_msg("Invalid array bounds in REDIM");
            return;
        }
        
        array->strides[i] = (int32_t)new_total_elements;
        new_total_elements *= size;
    }
    
    // Allocate new data
    size_t new_data_size = new_total_elements * array->element_size;
    void* new_data = malloc(new_data_size);
    if (!new_data) {
        if (old_bounds) free(old_bounds);
        if (old_strides) free(old_strides);
        if (old_data) {
            array->data = old_data;  // Restore old data
        }
        basic_error_msg("Out of memory (REDIM)");
        return;
    }
    
    // Initialize new data to zero
    memset(new_data, 0, new_data_size);
    
    // If preserving, copy overlapping elements
    if (preserve && old_data) {
        // For 1D arrays, use simple linear copy
        if (array->dimensions == 1) {
            int32_t old_lower = old_bounds[0];
            int32_t old_upper = old_bounds[1];
            int32_t new_lower = new_bounds[0];
            int32_t new_upper = new_bounds[1];
            
            int32_t start = (old_lower > new_lower) ? old_lower : new_lower;
            int32_t end = (old_upper < new_upper) ? old_upper : new_upper;
            
            for (int32_t i = start; i <= end; i++) {
                size_t old_offset = (i - old_lower) * old_strides[0];
                size_t new_offset = (i - new_lower) * array->strides[0];
                
                void* old_ptr = (char*)old_data + (old_offset * array->element_size);
                void* new_ptr = (char*)new_data + (new_offset * array->element_size);
                
                if (array->type_suffix == '$') {
                    StringDescriptor** old_str = (StringDescriptor**)old_ptr;
                    StringDescriptor** new_str = (StringDescriptor**)new_ptr;
                    if (*old_str) {
                        *new_str = string_retain(*old_str);
                    }
                } else {
                    memcpy(new_ptr, old_ptr, array->element_size);
                }
            }
        } else {
            // For multi-dimensional arrays, iterate through all overlapping indices
            // Calculate overlapping ranges for each dimension
            int32_t* overlap_start = (int32_t*)malloc(array->dimensions * sizeof(int32_t));
            int32_t* overlap_end = (int32_t*)malloc(array->dimensions * sizeof(int32_t));
            int32_t* current_idx = (int32_t*)malloc(array->dimensions * sizeof(int32_t));
            
            if (!overlap_start || !overlap_end || !current_idx) {
                if (overlap_start) free(overlap_start);
                if (overlap_end) free(overlap_end);
                if (current_idx) free(current_idx);
                free(new_data);
                free(old_data);
                free(old_bounds);
                free(old_strides);
                basic_error_msg("Out of memory (REDIM PRESERVE copy)");
                return;
            }
            
            for (int32_t d = 0; d < array->dimensions; d++) {
                int32_t old_lower = old_bounds[d * 2];
                int32_t old_upper = old_bounds[d * 2 + 1];
                int32_t new_lower = new_bounds[d * 2];
                int32_t new_upper = new_bounds[d * 2 + 1];
                
                overlap_start[d] = (old_lower > new_lower) ? old_lower : new_lower;
                overlap_end[d] = (old_upper < new_upper) ? old_upper : new_upper;
                current_idx[d] = overlap_start[d];
            }
            
            // Iterate through all overlapping elements
            int done = 0;
            while (!done) {
                // Calculate offsets
                size_t old_offset = 0;
                size_t new_offset = 0;
                for (int32_t d = 0; d < array->dimensions; d++) {
                    old_offset += (current_idx[d] - old_bounds[d * 2]) * old_strides[d];
                    new_offset += (current_idx[d] - new_bounds[d * 2]) * array->strides[d];
                }
                
                // Copy element
                void* old_ptr = (char*)old_data + (old_offset * array->element_size);
                void* new_ptr = (char*)new_data + (new_offset * array->element_size);
                
                if (array->type_suffix == '$') {
                    StringDescriptor** old_str = (StringDescriptor**)old_ptr;
                    StringDescriptor** new_str = (StringDescriptor**)new_ptr;
                    if (*old_str) {
                        *new_str = string_retain(*old_str);
                    }
                } else {
                    memcpy(new_ptr, old_ptr, array->element_size);
                }
                
                // Increment indices (rightmost dimension first)
                int32_t d = array->dimensions - 1;
                while (d >= 0) {
                    current_idx[d]++;
                    if (current_idx[d] <= overlap_end[d]) {
                        break;
                    }
                    current_idx[d] = overlap_start[d];
                    d--;
                }
                if (d < 0) {
                    done = 1;
                }
            }
            
            free(overlap_start);
            free(overlap_end);
            free(current_idx);
        }
        
        // Free old data (strings already handled by copy or will be released)
        if (array->type_suffix == '$') {
            // Release all strings from old array (copied ones have increased refcount)
            // Untrack from SAMM first to avoid double-free at scope exit
            size_t old_total_elements = 1;
            for (int32_t i = 0; i < array->dimensions; i++) {
                int32_t lower = old_bounds[i * 2];
                int32_t upper = old_bounds[i * 2 + 1];
                old_total_elements *= (upper - lower + 1);
            }
            
            StringDescriptor** strings = (StringDescriptor**)old_data;
            for (size_t i = 0; i < old_total_elements; i++) {
                if (strings[i]) {
                    samm_untrack(strings[i]);
                    string_release(strings[i]);
                }
            }
        }
        free(old_data);
        free(old_bounds);
        free(old_strides);
    }
    
    // Update array data pointer
    array->data = new_data;
}

// =============================================================================
// Bounds Checking
// =============================================================================

void basic_check_bounds(BasicArray* array, int32_t* indices) {
    if (!array || !indices) return;
    
    for (int32_t i = 0; i < array->dimensions; i++) {
        int32_t lower = array->bounds[i * 2];
        int32_t upper = array->bounds[i * 2 + 1];
        int32_t index = indices[i];
        
        if (index < lower || index > upper) {
            char msg[256];
            snprintf(msg, sizeof(msg), 
                "Array subscript out of range (dimension %d: %d not in [%d, %d])",
                i + 1, index, lower, upper);
            basic_error_msg(msg);
            return;
        }
    }
}

// =============================================================================
// Convenience Wrappers for Codegen
// =============================================================================

// Simple array creation wrapper for codegen
// Creates a 1D array with default type (double '#')
BasicArray* array_create(int32_t dimensions, ...) {
if (dimensions <= 0 || dimensions > 8) {
    basic_error_msg("Invalid array dimensions in array_create");
    return NULL;
}
    
// Allocate bounds array
int32_t* bounds = (int32_t*)malloc(dimensions * 2 * sizeof(int32_t));
if (!bounds) {
    basic_error_msg("Out of memory (array_create bounds)");
    return NULL;
}
    
// Extract dimension sizes from varargs
va_list args;
va_start(args, dimensions);
    
for (int32_t i = 0; i < dimensions; i++) {
    int32_t size = va_arg(args, int32_t);
    bounds[i * 2] = 0;      // Lower bound (OPTION BASE 0 by default)
    bounds[i * 2 + 1] = size;  // Upper bound
}
    
va_end(args);
    
// Create array with default type (double '#')
BasicArray* array = array_new('#', dimensions, bounds, 0);
    
free(bounds);
return array;
}

// =============================================================================
// NEON Loop Vectorization Support
// =============================================================================

// Get raw data pointer for direct NEON access (bypasses per-element bounds checking)
void* array_get_data_ptr(BasicArray* array) {
    if (!array || !array->data) return NULL;
    return array->data;
}

// Get element size in bytes
size_t array_get_element_size(BasicArray* array) {
    if (!array) return 0;
    return array->element_size;
}

// Validate that a contiguous range [start_idx, end_idx] is within bounds
// for dimension 0.  Called once before a NEON-vectorized loop to replace
// per-element bounds checking.
void array_check_range(BasicArray* array, int32_t start_idx, int32_t end_idx) {
    if (!array) {
        basic_error_msg("NEON loop: null array pointer");
        return;
    }
    if (!array->data) {
        basic_error_msg("NEON loop: array has no data (not allocated?)");
        return;
    }
    if (array->dimensions < 1) {
        basic_error_msg("NEON loop: array has no dimensions");
        return;
    }
    int32_t lower = array->bounds[0];
    int32_t upper = array->bounds[1];
    if (start_idx < lower || end_idx > upper) {
        char msg[256];
        snprintf(msg, sizeof(msg),
            "NEON loop: array range [%d, %d] out of bounds [%d, %d]",
            start_idx, end_idx, lower, upper);
        basic_error_msg(msg);
    }
}

// Erase an array (deallocate memory but keep descriptor)
void array_erase(BasicArray* array) {
    if (!array) return;
    
    // Free the data
    if (array->data) {
        // If string array, release all strings first
        // Untrack from SAMM before releasing to prevent double-free at scope exit
        if (array->type_suffix == '$') {
            size_t total_elements = 1;
            for (int32_t i = 0; i < array->dimensions; i++) {
                int32_t lower = array->bounds[i * 2];
                int32_t upper = array->bounds[i * 2 + 1];
                total_elements *= (upper - lower + 1);
            }
            
            StringDescriptor** strings = (StringDescriptor**)array->data;
            for (size_t i = 0; i < total_elements; i++) {
                if (strings[i]) {
                    samm_untrack(strings[i]);
                    string_release(strings[i]);
                }
            }
        }
        
        free(array->data);
        array->data = NULL;
    }
    
    // Set bounds to indicate empty array (0, -1 means size 0)
    for (int32_t i = 0; i < array->dimensions; i++) {
        array->bounds[i * 2] = 0;
        array->bounds[i * 2 + 1] = -1;
    }
}
