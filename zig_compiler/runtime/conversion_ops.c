//
// conversion_ops.c
// FasterBASIC QBE Runtime Library - Type Conversion Operations
//
// This file implements conversions between different data types.
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

// =============================================================================
// Integer to String
// =============================================================================

BasicString* int_to_str(int32_t value) {
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%d", value);
    return str_new(buffer);
}

// =============================================================================
// Long to String
// =============================================================================

BasicString* long_to_str(int64_t value) {
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    return str_new(buffer);
}

// =============================================================================
// Float to String
// =============================================================================

BasicString* float_to_str(float value) {
    char buffer[64];
    
    // Check for special values
    if (isnan(value)) {
        return str_new("NaN");
    }
    if (isinf(value)) {
        return str_new(value > 0 ? "Infinity" : "-Infinity");
    }
    
    // Use %g for automatic formatting (removes trailing zeros)
    snprintf(buffer, sizeof(buffer), "%g", value);
    return str_new(buffer);
}

// =============================================================================
// Double to String
// =============================================================================

BasicString* double_to_str(double value) {
    char buffer[64];
    
    // Check for special values
    if (isnan(value)) {
        return str_new("NaN");
    }
    if (isinf(value)) {
        return str_new(value > 0 ? "Infinity" : "-Infinity");
    }
    
    // Use %g for automatic formatting (removes trailing zeros)
    snprintf(buffer, sizeof(buffer), "%g", value);
    return str_new(buffer);
}

// =============================================================================
// String to Integer
// =============================================================================

int32_t str_to_int(BasicString* str) {
    if (!str || str->length == 0) {
        return 0;
    }
    
    // Skip leading whitespace
    const char* p = str->data;
    while (*p && (*p == ' ' || *p == '\t')) {
        p++;
    }
    
    // Parse integer (stops at first non-digit)
    return (int32_t)atoi(p);
}

// =============================================================================
// String to Long
// =============================================================================

int64_t str_to_long(BasicString* str) {
    if (!str || str->length == 0) {
        return 0;
    }
    
    // Skip leading whitespace
    const char* p = str->data;
    while (*p && (*p == ' ' || *p == '\t')) {
        p++;
    }
    
    // Parse long integer (stops at first non-digit)
    return (int64_t)atoll(p);
}

// =============================================================================
// String to Float
// =============================================================================

float str_to_float(BasicString* str) {
    if (!str || str->length == 0) {
        return 0.0f;
    }
    
    // Skip leading whitespace
    const char* p = str->data;
    while (*p && (*p == ' ' || *p == '\t')) {
        p++;
    }
    
    // Parse float
    return (float)atof(p);
}

// =============================================================================
// String to Double
// =============================================================================

double str_to_double(BasicString* str) {
    if (!str || str->length == 0) {
        return 0.0;
    }
    
    // Skip leading whitespace
    const char* p = str->data;
    while (*p && (*p == ' ' || *p == '\t')) {
        p++;
    }
    
    // Parse double
    return atof(p);
}