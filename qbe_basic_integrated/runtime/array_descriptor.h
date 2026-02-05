//
// array_descriptor.h
// FasterBASIC Runtime - Array Descriptor (Dope Vector)
//
// Defines the array descriptor structure used for efficient bounds checking
// and dynamic array operations (DIM, REDIM, REDIM PRESERVE, ERASE).
//

#ifndef ARRAY_DESCRIPTOR_H
#define ARRAY_DESCRIPTOR_H

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#ifdef __cplusplus
extern "C" {
#endif

//
// ArrayDescriptor: Tracks array metadata for bounds checking and reallocation
//
// Memory layout (kept in sync with QBE codegen):
//   Offset 0:  void*   data         - Pointer to array data
//   Offset 8:  int64_t lowerBound1  - Lower index bound for dimension 1 (typically 0 or 1)
//   Offset 16: int64_t upperBound1  - Upper index bound for dimension 1
//   Offset 24: int64_t lowerBound2  - Lower index bound for dimension 2 (0 if 1D array)
//   Offset 32: int64_t upperBound2  - Upper index bound for dimension 2 (0 if 1D array)
//   Offset 40: int64_t elementSize  - Size of each element in bytes
//   Offset 48: int32_t dimensions   - Number of dimensions (1 or 2)
//   Offset 52: int32_t base         - OPTION BASE (0 or 1)
//   Offset 56: char    typeSuffix   - BASIC suffix ('%', '!', '#', '$', '&' or 0 for UDT)
//   Offset 57: char[7] _padding     - Padding / future use
//
// Total size: 64 bytes (aligned)
//
typedef struct {
    void*    data;          // Pointer to the array data
    int64_t  lowerBound1;   // Lower index bound for dimension 1
    int64_t  upperBound1;   // Upper index bound for dimension 1
    int64_t  lowerBound2;   // Lower index bound for dimension 2 (0 if 1D)
    int64_t  upperBound2;   // Upper index bound for dimension 2 (0 if 1D)
    int64_t  elementSize;   // Size per element in bytes
    int32_t  dimensions;    // Number of dimensions (1 or 2)
    int32_t  base;          // OPTION BASE (0 or 1)
    char     typeSuffix;    // BASIC type suffix; 0 for UDT/opaque
    char     _padding[7];   // Padding for alignment / future use
} ArrayDescriptor;

//
// Runtime helper functions for array operations
//

// Initialize a new 1D array descriptor
// Returns 0 on success, -1 on failure
static inline int array_descriptor_init(
    ArrayDescriptor* desc,
    int64_t lowerBound,
    int64_t upperBound,
    int64_t elementSize,
    int32_t base,
    char typeSuffix)
{
    if (!desc || upperBound < lowerBound || elementSize <= 0) {
        return -1;
    }

    int64_t count = upperBound - lowerBound + 1;
    size_t totalSize = (size_t)(count * elementSize);

    desc->data = malloc(totalSize);
    if (!desc->data) {
        return -1;
    }

    // Zero-initialize the array data
    memset(desc->data, 0, totalSize);

    desc->lowerBound1 = lowerBound;
    desc->upperBound1 = upperBound;
    desc->lowerBound2 = 0;
    desc->upperBound2 = 0;
    desc->elementSize = elementSize;
    desc->dimensions = 1;
    desc->base = base;
    desc->typeSuffix = typeSuffix;
    memset(desc->_padding, 0, sizeof(desc->_padding));

    return 0;
}

// Initialize a new 2D array descriptor
// Returns 0 on success, -1 on failure
static inline int array_descriptor_init_2d(
    ArrayDescriptor* desc,
    int64_t lowerBound1,
    int64_t upperBound1,
    int64_t lowerBound2,
    int64_t upperBound2,
    int64_t elementSize,
    int32_t base,
    char typeSuffix)
{
    if (!desc || upperBound1 < lowerBound1 || upperBound2 < lowerBound2 || elementSize <= 0) {
        return -1;
    }

    int64_t count1 = upperBound1 - lowerBound1 + 1;
    int64_t count2 = upperBound2 - lowerBound2 + 1;
    int64_t totalCount = count1 * count2;
    size_t totalSize = (size_t)(totalCount * elementSize);

    desc->data = malloc(totalSize);
    if (!desc->data) {
        return -1;
    }

    // Zero-initialize the array data
    memset(desc->data, 0, totalSize);

    desc->lowerBound1 = lowerBound1;
    desc->upperBound1 = upperBound1;
    desc->lowerBound2 = lowerBound2;
    desc->upperBound2 = upperBound2;
    desc->elementSize = elementSize;
    desc->dimensions = 2;
    desc->base = base;
    desc->typeSuffix = typeSuffix;
    memset(desc->_padding, 0, sizeof(desc->_padding));

    return 0;
}

// Free array data (for ERASE or before REDIM)
static inline void array_descriptor_free(ArrayDescriptor* desc)
{
    if (desc && desc->data) {
        free(desc->data);
        desc->data = NULL;
        desc->lowerBound1 = 0;
        desc->upperBound1 = -1;
        desc->lowerBound2 = 0;
        desc->upperBound2 = -1;
    }
}

// REDIM: Free old data and allocate new
static inline int array_descriptor_redim(
    ArrayDescriptor* desc,
    int64_t newLowerBound,
    int64_t newUpperBound)
{
    if (!desc || newUpperBound < newLowerBound) {
        return -1;
    }

    // Free old data
    if (desc->data) {
        free(desc->data);
        desc->data = NULL;
    }

    // Allocate new data
    int64_t newCount = newUpperBound - newLowerBound + 1;
    size_t totalSize = (size_t)(newCount * desc->elementSize);

    desc->data = malloc(totalSize);
    if (!desc->data) {
        desc->lowerBound1 = 0;
        desc->upperBound1 = -1;
        return -1;
    }

    // Zero-initialize
    memset(desc->data, 0, totalSize);

    desc->lowerBound1 = newLowerBound;
    desc->upperBound1 = newUpperBound;
    desc->lowerBound2 = 0;
    desc->upperBound2 = 0;
    desc->dimensions = 1;

    return 0;
}

// REDIM PRESERVE: Resize array keeping existing data
static inline int array_descriptor_redim_preserve(
    ArrayDescriptor* desc,
    int64_t newLowerBound,
    int64_t newUpperBound)
{
    if (!desc || newUpperBound < newLowerBound) {
        return -1;
    }

    int64_t oldCount = desc->upperBound1 - desc->lowerBound1 + 1;
    int64_t newCount = newUpperBound - newLowerBound + 1;
    size_t oldSize = (size_t)(oldCount * desc->elementSize);
    size_t newSize = (size_t)(newCount * desc->elementSize);

    // Use realloc to resize
    void* newData = realloc(desc->data, newSize);
    if (!newData) {
        return -1;
    }

    desc->data = newData;

    // If growing, zero-fill the new elements
    if (newSize > oldSize) {
        char* fillStart = (char*)desc->data + oldSize;
        size_t fillSize = newSize - oldSize;
        memset(fillStart, 0, fillSize);
    }

    // Handle index shift if lower bound changed
    // Note: This is a simplified version. Full implementation would need
    // to copy data to account for index offset changes.
    if (newLowerBound != desc->lowerBound1 && newCount > 0 && oldCount > 0) {
        // For now, we assume bounds don't change much
        // A full implementation would memmove data based on index shift
    }

    desc->lowerBound1 = newLowerBound;
    desc->upperBound1 = newUpperBound;

    return 0;
}

// ERASE helper: implemented in array_descriptor_runtime.c
void array_descriptor_erase(ArrayDescriptor* desc);

// Destroy helper: erase contents and free descriptor
void array_descriptor_destroy(ArrayDescriptor* desc);

// Bounds check for 1D - returns 1 if index is valid, 0 if out of bounds
static inline int array_descriptor_check_bounds(
    const ArrayDescriptor* desc,
    int64_t index)
{
    return (desc && desc->dimensions == 1 && 
            index >= desc->lowerBound1 && index <= desc->upperBound1);
}

// Bounds check for 2D - returns 1 if indices are valid, 0 if out of bounds
static inline int array_descriptor_check_bounds_2d(
    const ArrayDescriptor* desc,
    int64_t index1,
    int64_t index2)
{
    return (desc && desc->dimensions == 2 && 
            index1 >= desc->lowerBound1 && index1 <= desc->upperBound1 &&
            index2 >= desc->lowerBound2 && index2 <= desc->upperBound2);
}

// Calculate element pointer for 1D array (no bounds check)
static inline void* array_descriptor_get_element_ptr(
    const ArrayDescriptor* desc,
    int64_t index)
{
    int64_t offset = (index - desc->lowerBound1) * desc->elementSize;
    return (char*)desc->data + offset;
}

// Calculate element pointer for 2D array (no bounds check)
// Row-major order: element[i,j] = data[(i - lowerBound1) * dim2_size + (j - lowerBound2)]
static inline void* array_descriptor_get_element_ptr_2d(
    const ArrayDescriptor* desc,
    int64_t index1,
    int64_t index2)
{
    int64_t dim2_size = desc->upperBound2 - desc->lowerBound2 + 1;
    int64_t offset = ((index1 - desc->lowerBound1) * dim2_size + 
                      (index2 - desc->lowerBound2)) * desc->elementSize;
    return (char*)desc->data + offset;
}

// Runtime error handler for bounds violations
// This should be called when bounds check fails
extern void basic_array_bounds_error(int64_t index, int64_t lower, int64_t upper);

#ifdef __cplusplus
}
#endif

#endif // ARRAY_DESCRIPTOR_H