//
// string_ops.c
// FasterBASIC QBE Runtime Library - String Operations
//
// This file implements string management with reference counting.
// Strings are immutable (copy-on-write) for safety and performance.
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

// =============================================================================
// String Creation and Management
// =============================================================================

BasicString* str_new(const char* cstr) {
    if (!cstr) cstr = "";
    
    size_t len = strlen(cstr);
    
    BasicString* str = (BasicString*)malloc(sizeof(BasicString));
    if (!str) {
        basic_error_msg("Out of memory (string allocation)");
        return NULL;
    }
    
    str->length = len;
    str->capacity = len + 1;
    str->data = (char*)malloc(str->capacity);
    if (!str->data) {
        free(str);
        basic_error_msg("Out of memory (string data)");
        return NULL;
    }
    
    memcpy(str->data, cstr, len);
    str->data[len] = '\0';
    str->refcount = 1;
    
    return str;
}

BasicString* str_new_length(const char* data, size_t length) {
    if (!data) return str_new("");
    
    BasicString* str = (BasicString*)malloc(sizeof(BasicString));
    if (!str) {
        basic_error_msg("Out of memory (string allocation)");
        return NULL;
    }
    
    str->length = length;
    str->capacity = length + 1;
    str->data = (char*)malloc(str->capacity);
    if (!str->data) {
        free(str);
        basic_error_msg("Out of memory (string data)");
        return NULL;
    }
    
    memcpy(str->data, data, length);
    str->data[length] = '\0';
    str->refcount = 1;
    
    return str;
}

BasicString* str_new_capacity(size_t capacity) {
    BasicString* str = (BasicString*)malloc(sizeof(BasicString));
    if (!str) {
        basic_error_msg("Out of memory (string allocation)");
        return NULL;
    }
    
    str->length = 0;
    str->capacity = capacity + 1;
    str->data = (char*)malloc(str->capacity);
    if (!str->data) {
        free(str);
        basic_error_msg("Out of memory (string data)");
        return NULL;
    }
    
    str->data[0] = '\0';
    str->refcount = 1;
    
    return str;
}

// =============================================================================
// Reference Counting
// =============================================================================

BasicString* str_retain(BasicString* str) {
    if (!str) return NULL;
    str->refcount++;
    return str;
}

void str_release(BasicString* str) {
    if (!str) return;
    
    str->refcount--;
    if (str->refcount <= 0) {
        if (str->data) {
            free(str->data);
        }
        free(str);
    }
}

// =============================================================================
// String Access
// =============================================================================

const char* str_cstr(BasicString* str) {
    if (!str) return "";
    return str->data;
}

int32_t str_length(BasicString* str) {
    if (!str) return 0;
    return (int32_t)str->length;
}

// =============================================================================
// String Concatenation
// =============================================================================

BasicString* str_concat(BasicString* a, BasicString* b) {
    if (!a && !b) return str_new("");
    if (!a) return str_retain(b);
    if (!b) return str_retain(a);
    
    size_t new_len = a->length + b->length;
    BasicString* result = str_new_capacity(new_len);
    
    memcpy(result->data, a->data, a->length);
    memcpy(result->data + a->length, b->data, b->length);
    result->data[new_len] = '\0';
    result->length = new_len;
    
    return result;
}

// =============================================================================
// String Substring Operations
// =============================================================================

BasicString* str_substr(BasicString* str, int32_t start, int32_t length) {
    if (!str) return str_new("");
    
    // Convert to 0-based indexing
    start--;
    
    // Handle negative or out-of-bounds start
    if (start < 0) start = 0;
    if (start >= (int32_t)str->length) return str_new("");
    
    // Handle negative or excessive length
    if (length < 0) length = 0;
    if (start + length > (int32_t)str->length) {
        length = (int32_t)str->length - start;
    }
    
    return str_new_length(str->data + start, length);
}

BasicString* str_left(BasicString* str, int32_t n) {
    if (!str) return str_new("");
    if (n <= 0) return str_new("");
    if (n >= (int32_t)str->length) return str_retain(str);
    
    return str_new_length(str->data, n);
}

BasicString* str_right(BasicString* str, int32_t n) {
    if (!str) return str_new("");
    if (n <= 0) return str_new("");
    if (n >= (int32_t)str->length) return str_retain(str);
    
    size_t start = str->length - n;
    return str_new_length(str->data + start, n);
}

// =============================================================================
// String Comparison
// =============================================================================

int32_t str_compare(BasicString* a, BasicString* b) {
    if (!a && !b) return 0;
    if (!a) return -1;
    if (!b) return 1;
    
    int result = strcmp(a->data, b->data);
    if (result < 0) return -1;
    if (result > 0) return 1;
    return 0;
}

// =============================================================================
// String Case Conversion
// =============================================================================

BasicString* str_upper(BasicString* str) {
    if (!str) return str_new("");
    
    BasicString* result = str_new_capacity(str->length);
    result->length = str->length;
    
    for (size_t i = 0; i < str->length; i++) {
        result->data[i] = toupper((unsigned char)str->data[i]);
    }
    result->data[str->length] = '\0';
    
    return result;
}

BasicString* str_lower(BasicString* str) {
    if (!str) return str_new("");
    
    BasicString* result = str_new_capacity(str->length);
    result->length = str->length;
    
    for (size_t i = 0; i < str->length; i++) {
        result->data[i] = tolower((unsigned char)str->data[i]);
    }
    result->data[str->length] = '\0';
    
    return result;
}

// =============================================================================
// String Trimming
// =============================================================================

BasicString* str_trim(BasicString* str) {
    if (!str || str->length == 0) return str_new("");
    
    // Find first non-whitespace
    size_t start = 0;
    while (start < str->length && isspace((unsigned char)str->data[start])) {
        start++;
    }
    
    // All whitespace?
    if (start >= str->length) return str_new("");
    
    // Find last non-whitespace
    size_t end = str->length;
    while (end > start && isspace((unsigned char)str->data[end - 1])) {
        end--;
    }
    
    size_t new_len = end - start;
    return str_new_length(str->data + start, new_len);
}

// =============================================================================
// String Search
// =============================================================================

int32_t str_instr(BasicString* haystack, BasicString* needle) {
    if (!haystack || !needle) return 0;
    if (needle->length == 0) return 1;  // Empty needle found at position 1
    if (needle->length > haystack->length) return 0;
    
    const char* found = strstr(haystack->data, needle->data);
    if (!found) return 0;
    
    // Return 1-based position
    return (int32_t)(found - haystack->data) + 1;
}

// =============================================================================
// String Replacement
// =============================================================================

BasicString* str_replace(BasicString* str, BasicString* find, BasicString* replace) {
    if (!str) return str_new("");
    if (!find || find->length == 0) return str_retain(str);
    if (!replace) replace = str_new("");
    
    // Count occurrences
    int count = 0;
    const char* pos = str->data;
    while ((pos = strstr(pos, find->data)) != NULL) {
        count++;
        pos += find->length;
    }
    
    // No replacements needed
    if (count == 0) return str_retain(str);
    
    // Calculate new length
    size_t new_len = str->length + count * (replace->length - find->length);
    BasicString* result = str_new_capacity(new_len);
    
    // Build result string
    const char* src = str->data;
    char* dst = result->data;
    
    while (*src) {
        const char* match = strstr(src, find->data);
        if (!match) {
            // Copy remainder
            strcpy(dst, src);
            break;
        }
        
        // Copy up to match
        size_t prefix_len = match - src;
        if (prefix_len > 0) {
            memcpy(dst, src, prefix_len);
            dst += prefix_len;
        }
        
        // Copy replacement
        if (replace->length > 0) {
            memcpy(dst, replace->data, replace->length);
            dst += replace->length;
        }
        
        // Move past the match
        src = match + find->length;
    }
    
    *dst = '\0';
    result->length = dst - result->data;
    
    return result;
}

// =============================================================================
// BASIC Intrinsic Function Wrappers
// =============================================================================

// LEN(string$) - Return length of string
int32_t basic_string_len(BasicString* str) {
    return str_length(str);
}

// String concatenation wrapper for BASIC
BasicString* basic_string_concat(BasicString* a, BasicString* b) {
    return str_concat(a, b);
}

// String comparison wrapper for BASIC
// Returns: -1 if a < b, 0 if a == b, 1 if a > b
int32_t basic_string_compare(BasicString* a, BasicString* b) {
    return str_compare(a, b);
}

// MID$(string$, start, length) - Extract substring
// Note: BASIC uses 1-based indexing, but string_mid expects 0-based
// Call the UTF-32 aware version from string_utf32.c
StringDescriptor* basic_mid(StringDescriptor* str, int32_t start, int32_t length) {
    // Convert from 1-based BASIC indexing to 0-based C indexing
    return string_mid(str, start - 1, length);
}

// LEFT$(string$, count) - Extract leftmost characters
// Call the UTF-32 aware version from string_utf32.c
StringDescriptor* basic_left(StringDescriptor* str, int32_t count) {
    return string_left(str, count);
}

// RIGHT$(string$, count) - Extract rightmost characters
// Call the UTF-32 aware version from string_utf32.c
StringDescriptor* basic_right(StringDescriptor* str, int32_t count) {
    return string_right(str, count);
}