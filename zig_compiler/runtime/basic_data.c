//
// basic_data.c
// FasterBASIC QBE Runtime Library - DATA/READ/RESTORE Support
//
// NOTE: This is part of the C runtime library (runtime_c/) that gets linked with
//       COMPILED BASIC programs, not the C++ compiler runtime (runtime/).
//
// This file contains runtime support for BASIC DATA, READ, and RESTORE statements.
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// =============================================================================
// External DATA Section References
// =============================================================================

// These symbols are defined in the generated QBE IL code
// If the program doesn't use DATA statements, provide weak default symbols
extern int64_t __basic_data[];        // Array of data values
extern uint8_t __basic_data_types[];  // Array of type tags (0=INT, 1=DOUBLE, 2=STRING)
extern int64_t __basic_data_ptr;      // Current read position

// Weak default symbols for programs without DATA statements
__attribute__((weak)) int64_t __basic_data[1] = {0};
__attribute__((weak)) uint8_t __basic_data_types[1] = {0};
__attribute__((weak)) int64_t __basic_data_ptr = 0;

// =============================================================================
// Type Enumeration
// =============================================================================

#define DATA_TYPE_INT    0
#define DATA_TYPE_DOUBLE 1
#define DATA_TYPE_STRING 2

// =============================================================================
// READ Functions
// =============================================================================

// Read an integer value from DATA
int32_t basic_read_int(void) {
    // Check bounds
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }
    
    int64_t idx = __basic_data_ptr;
    uint8_t type = __basic_data_types[idx];
    
    // Type check
    if (type != DATA_TYPE_INT) {
        basic_throw(ERR_TYPE_MISMATCH);
    }
    
    // Read value and advance pointer
    int32_t value = (int32_t)__basic_data[idx];
    __basic_data_ptr++;
    
    return value;
}

// Read a double value from DATA
double basic_read_double(void) {
    // Check bounds
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }
    
    int64_t idx = __basic_data_ptr;
    uint8_t type = __basic_data_types[idx];
    
    // Type check - allow INT to be read as DOUBLE
    if (type == DATA_TYPE_INT) {
        int32_t value = (int32_t)__basic_data[idx];
        __basic_data_ptr++;
        return (double)value;
    } else if (type == DATA_TYPE_DOUBLE) {
        // Reinterpret the bits as double
        union {
            int64_t i;
            double d;
        } converter;
        converter.i = __basic_data[idx];
        __basic_data_ptr++;
        return converter.d;
    } else {
        basic_throw(ERR_TYPE_MISMATCH);
    }
}

// Read a string value from DATA
const char* basic_read_string(void) {
    // Check bounds
    if (__basic_data_ptr < 0) {
        basic_throw(ERR_ILLEGAL_CALL);
    }
    
    int64_t idx = __basic_data_ptr;
    uint8_t type = __basic_data_types[idx];
    
    // Type check
    if (type != DATA_TYPE_STRING) {
        basic_throw(ERR_TYPE_MISMATCH);
    }
    
    // Read pointer value and advance pointer
    const char* str = (const char*)__basic_data[idx];
    __basic_data_ptr++;
    
    return str;
}

// =============================================================================
// RESTORE Function
// =============================================================================

// Restore DATA pointer to a specific position
void basic_restore(int64_t index) {
    __basic_data_ptr = index;
}

// Restore DATA pointer to the beginning
void basic_restore_start(void) {
    __basic_data_ptr = 0;
}
