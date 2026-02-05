//
// string_utf32.c
// FasterBASIC QBE Runtime Library - UTF-32 String Implementation
//
// Implements the UTF-32 string operations declared in string_descriptor.h
// This provides O(1) character access and simple substring operations.
//

#include "string_descriptor.h"
#include "array_descriptor.h"
#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// Helper macros for encoding-aware data access
#define STR_CHAR(str, i) (str->encoding == STRING_ENCODING_ASCII ? \
    ((uint8_t*)str->data)[i] : ((uint32_t*)str->data)[i])
    
#define STR_SET_CHAR(str, i, c) do { \
    if (str->encoding == STRING_ENCODING_ASCII) \
        ((uint8_t*)str->data)[i] = (uint8_t)(c); \
    else \
        ((uint32_t*)str->data)[i] = (c); \
} while(0)

// =============================================================================
// UTF-8 ↔ UTF-32 Conversion
// =============================================================================

// Get length of UTF-8 string in code points
int64_t utf8_length_in_codepoints(const char* utf8_str) {
    if (!utf8_str) return 0;
    
    int64_t count = 0;
    const uint8_t* p = (const uint8_t*)utf8_str;
    
    while (*p) {
        if ((*p & 0x80) == 0) {
            // 1-byte character
            p += 1;
        } else if ((*p & 0xE0) == 0xC0) {
            // 2-byte character
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            // 3-byte character
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            // 4-byte character
            p += 4;
        } else {
            // Invalid UTF-8, skip byte
            p += 1;
            continue;
        }
        count++;
    }
    
    return count;
}

// Convert UTF-8 to UTF-32
int64_t utf8_to_utf32(const char* utf8_str, uint32_t* out_utf32, int64_t out_capacity) {
    if (!utf8_str || !out_utf32) return -1;
    
    int64_t count = 0;
    const uint8_t* p = (const uint8_t*)utf8_str;
    
    while (*p && count < out_capacity) {
        uint32_t codepoint;
        
        if ((*p & 0x80) == 0) {
            // 1-byte: 0xxxxxxx
            codepoint = *p;
            p += 1;
        } else if ((*p & 0xE0) == 0xC0) {
            // 2-byte: 110xxxxx 10xxxxxx
            codepoint = ((*p & 0x1F) << 6) | (p[1] & 0x3F);
            p += 2;
        } else if ((*p & 0xF0) == 0xE0) {
            // 3-byte: 1110xxxx 10xxxxxx 10xxxxxx
            codepoint = ((*p & 0x0F) << 12) | ((p[1] & 0x3F) << 6) | (p[2] & 0x3F);
            p += 3;
        } else if ((*p & 0xF8) == 0xF0) {
            // 4-byte: 11110xxx 10xxxxxx 10xxxxxx 10xxxxxx
            codepoint = ((*p & 0x07) << 18) | ((p[1] & 0x3F) << 12) | 
                       ((p[2] & 0x3F) << 6) | (p[3] & 0x3F);
            p += 4;
        } else {
            // Invalid UTF-8, skip byte
            p += 1;
            continue;
        }
        
        out_utf32[count++] = codepoint;
    }
    
    return count;
}

// Get required buffer size for UTF-32 → UTF-8 conversion
int64_t utf32_to_utf8_size(const uint32_t* utf32_data, int64_t length) {
    if (!utf32_data || length <= 0) return 1;  // Just null terminator
    
    int64_t size = 0;
    for (int64_t i = 0; i < length; i++) {
        uint32_t cp = utf32_data[i];
        if (cp < 0x80) size += 1;
        else if (cp < 0x800) size += 2;
        else if (cp < 0x10000) size += 3;
        else if (cp < 0x110000) size += 4;
    }
    return size + 1;  // Include null terminator
}

// Convert UTF-32 to UTF-8
int64_t utf32_to_utf8(const uint32_t* utf32_data, int64_t length, 
                      char* out_utf8, int64_t out_capacity) {
    if (!utf32_data || !out_utf8 || out_capacity == 0) return -1;
    
    int64_t written = 0;
    
    for (int64_t i = 0; i < length; i++) {
        uint32_t cp = utf32_data[i];
        
        if (cp < 0x80) {
            // 1 byte
            if (written + 1 >= out_capacity) break;
            out_utf8[written++] = (char)cp;
        } else if (cp < 0x800) {
            // 2 bytes
            if (written + 2 >= out_capacity) break;
            out_utf8[written++] = 0xC0 | (cp >> 6);
            out_utf8[written++] = 0x80 | (cp & 0x3F);
        } else if (cp < 0x10000) {
            // 3 bytes
            if (written + 3 >= out_capacity) break;
            out_utf8[written++] = 0xE0 | (cp >> 12);
            out_utf8[written++] = 0x80 | ((cp >> 6) & 0x3F);
            out_utf8[written++] = 0x80 | (cp & 0x3F);
        } else if (cp < 0x110000) {
            // 4 bytes
            if (written + 4 >= out_capacity) break;
            out_utf8[written++] = 0xF0 | (cp >> 18);
            out_utf8[written++] = 0x80 | ((cp >> 12) & 0x3F);
            out_utf8[written++] = 0x80 | ((cp >> 6) & 0x3F);
            out_utf8[written++] = 0x80 | (cp & 0x3F);
        }
    }
    
    out_utf8[written] = '\0';
    return written + 1;  // Include null terminator
}

// =============================================================================
// String Creation and Management
// =============================================================================

// Create new ASCII string from 7-bit ASCII C string
StringDescriptor* string_new_ascii(const char* ascii_str) {
    if (!ascii_str || *ascii_str == '\0') {
        StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
        if (desc) {
            desc->refcount = 1;
            desc->encoding = STRING_ENCODING_ASCII;
            desc->dirty = 1;
        }
        return desc;
    }
    
    size_t len = strlen(ascii_str);
    
    // Allocate descriptor
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    // Allocate ASCII buffer (1 byte per char)
    desc->data = (uint8_t*)malloc(len);
    if (!desc->data) {
        free(desc);
        return NULL;
    }
    
    // Copy ASCII data
    memcpy(desc->data, ascii_str, len);
    desc->length = len;
    desc->capacity = len;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_ASCII;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

// Create new ASCII string from buffer and length
StringDescriptor* string_new_ascii_len(const uint8_t* data, int64_t length) {
    if (!data || length <= 0) {
        StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
        if (desc) {
            desc->refcount = 1;
            desc->encoding = STRING_ENCODING_ASCII;
            desc->dirty = 1;
        }
        return desc;
    }
    
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    desc->data = (uint8_t*)malloc(length * sizeof(uint8_t));
    if (!desc->data) {
        free(desc);
        return NULL;
    }
    
    memcpy(desc->data, data, length * sizeof(uint8_t));
    desc->length = length;
    desc->capacity = length;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_ASCII;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

// Create new string from UTF-8 C string (auto-detects ASCII vs UTF-32)
StringDescriptor* string_new_utf8(const char* utf8_str) {
    if (!utf8_str || *utf8_str == '\0') {
        // Empty string - default to UTF-32
        StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
        if (desc) {
            desc->refcount = 1;
            desc->encoding = STRING_ENCODING_UTF32;
            desc->dirty = 1;
        }
        return desc;
    }
    
    // Check if string is pure ASCII (all bytes < 128)
    bool is_ascii = true;
    size_t len = 0;
    for (const char* p = utf8_str; *p; p++, len++) {
        if ((unsigned char)*p >= 128) {
            is_ascii = false;
        }
    }
    
    // If pure ASCII, use ASCII encoding for efficiency
    if (is_ascii) {
        return string_new_ascii(utf8_str);
    }
    
    // Contains non-ASCII - use UTF-32
    // Get length in code points
    int64_t cp_len = utf8_length_in_codepoints(utf8_str);
    if (cp_len == 0) {
        StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
        if (desc) {
            desc->refcount = 1;
            desc->encoding = STRING_ENCODING_UTF32;
            desc->dirty = 1;
        }
        return desc;
    }
    
    // Allocate descriptor
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    // Allocate UTF-32 buffer
    desc->data = (uint32_t*)malloc(cp_len * sizeof(uint32_t));
    if (!desc->data) {
        free(desc);
        return NULL;
    }
    
    // Convert UTF-8 to UTF-32
    int64_t converted = utf8_to_utf32(utf8_str, desc->data, cp_len);
    desc->length = converted;
    desc->capacity = cp_len;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_UTF32;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

// Create new string from UTF-32 data
StringDescriptor* string_new_utf32(const uint32_t* data, int64_t length) {
    if (!data || length <= 0) {
        StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
        if (desc) {
            desc->refcount = 1;
            desc->encoding = STRING_ENCODING_UTF32;
            desc->dirty = 1;
        }
        return desc;
    }
    
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    desc->data = (uint32_t*)malloc(length * sizeof(uint32_t));
    if (!desc->data) {
        free(desc);
        return NULL;
    }
    
    memcpy(desc->data, data, length * sizeof(uint32_t));
    desc->length = length;
    desc->capacity = length;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_UTF32;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

// Create empty string with reserved capacity
StringDescriptor* string_new_capacity(int64_t capacity) {
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    if (capacity > 0) {
        desc->data = (uint32_t*)malloc(capacity * sizeof(uint32_t));
        if (!desc->data) {
            free(desc);
            return NULL;
        }
        desc->capacity = capacity;
    }
    
    desc->length = 0;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_UTF32;  // Default to UTF-32 (caller can override)
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

StringDescriptor* string_new_ascii_capacity(int64_t capacity) {
    StringDescriptor* desc = (StringDescriptor*)calloc(1, sizeof(StringDescriptor));
    if (!desc) return NULL;
    
    if (capacity > 0) {
        desc->data = (uint8_t*)malloc(capacity * sizeof(uint8_t));
        if (!desc->data) {
            free(desc);
            return NULL;
        }
        desc->capacity = capacity;
    }
    
    desc->length = 0;
    desc->refcount = 1;
    desc->encoding = STRING_ENCODING_ASCII;
    desc->dirty = 1;
    desc->utf8_cache = NULL;
    
    return desc;
}

// Create string by repeating a character
StringDescriptor* string_new_repeat(uint32_t codepoint, int64_t count) {
    if (count <= 0) {
        return string_new_capacity(0);
    }
    
    StringDescriptor* desc = string_new_capacity(count);
    if (!desc) return NULL;
    
    // If codepoint is ASCII (<128), use ASCII encoding
    if (codepoint < 128) {
        desc->encoding = STRING_ENCODING_ASCII;
        // Realloc to 1 byte per char
        uint8_t* ascii_data = (uint8_t*)realloc(desc->data, count);
        if (ascii_data) {
            desc->data = ascii_data;
            desc->capacity = count;
            for (int64_t i = 0; i < count; i++) {
                ((uint8_t*)desc->data)[i] = (uint8_t)codepoint;
            }
        }
    } else {
        // UTF-32 for non-ASCII
        desc->encoding = STRING_ENCODING_UTF32;
        for (int64_t i = 0; i < count; i++) {
            ((uint32_t*)desc->data)[i] = codepoint;
        }
    }
    desc->length = count;
    
    return desc;
}

// Promote ASCII string to UTF-32 (in-place, returns same pointer)
StringDescriptor* string_promote_to_utf32(StringDescriptor* str) {
    if (!str) return NULL;
    if (str->encoding == STRING_ENCODING_UTF32) {
        return str;  // Already UTF-32
    }
    
    // Convert ASCII → UTF-32 in-place
    uint8_t* ascii_data = (uint8_t*)str->data;
    int64_t len = str->length;
    
    if (len == 0) {
        // Empty string, just change encoding
        str->encoding = STRING_ENCODING_UTF32;
        return str;
    }
    
    // Allocate new UTF-32 buffer
    uint32_t* utf32_data = (uint32_t*)malloc(len * sizeof(uint32_t));
    if (!utf32_data) {
        // Allocation failed, keep ASCII
        return str;
    }
    
    // Copy ASCII bytes to UTF-32 code points (expand 1:1)
    for (int64_t i = 0; i < len; i++) {
        utf32_data[i] = (uint32_t)ascii_data[i];
    }
    
    // Free old ASCII buffer and replace
    free(ascii_data);
    str->data = utf32_data;
    str->capacity = len;
    str->encoding = STRING_ENCODING_UTF32;
    str->dirty = 1;  // Invalidate UTF-8 cache
    
    return str;
}

// Clone string (deep copy)
StringDescriptor* string_clone(const StringDescriptor* str) {
    if (!str) return string_new_capacity(0);
    
    // Preserve encoding when cloning
    if (str->encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len((uint8_t*)str->data, str->length);
    } else {
        return string_new_utf32((uint32_t*)str->data, str->length);
    }
}

// Retain string (increment refcount)
StringDescriptor* string_retain(StringDescriptor* str) {
    if (!str) return NULL;
    str->refcount++;
    return str;
}

// Release string (decrement refcount, free if 0)
void string_release(StringDescriptor* str) {
    if (!str) return;
    
    str->refcount--;
    
    if (str->refcount <= 0) {
        if (str->data) {
            free(str->data);
        }
        if (str->utf8_cache) {
            free(str->utf8_cache);
        }
        free(str);
    }
}

// Get UTF-8 representation (cached)
const char* string_to_utf8(StringDescriptor* str) {
    if (!str) return "";
    
    if (str->length == 0) return "";
    
    // If cache is valid, use it
    if (!str->dirty && str->utf8_cache) {
        return str->utf8_cache;
    }
    
    // Free old cache if exists
    if (str->utf8_cache) {
        free(str->utf8_cache);
    }
    
    // Handle ASCII encoding (just copy bytes, they're already valid UTF-8)
    if (str->encoding == STRING_ENCODING_ASCII) {
        str->utf8_cache = (char*)malloc(str->length + 1);
        if (!str->utf8_cache) return "";
        memcpy(str->utf8_cache, str->data, str->length);
        str->utf8_cache[str->length] = '\0';
        str->dirty = 0;
        return str->utf8_cache;
    }
    
    // Handle UTF-32 encoding (convert to UTF-8)
    // Calculate required size
    int64_t utf8_size = utf32_to_utf8_size((uint32_t*)str->data, str->length);
    
    // Allocate UTF-8 buffer
    str->utf8_cache = (char*)malloc(utf8_size);
    if (!str->utf8_cache) return "";
    
    // Convert UTF-32 to UTF-8
    utf32_to_utf8((uint32_t*)str->data, str->length, str->utf8_cache, utf8_size);
    str->dirty = 0;
    
    return str->utf8_cache;
}

// =============================================================================
// String Manipulation Operations
// =============================================================================

// Concatenate two strings
StringDescriptor* string_concat(const StringDescriptor* a, const StringDescriptor* b) {
    if (!a || !b) return string_new_capacity(0);
    
    int64_t total_len = a->length + b->length;
    
    if (total_len == 0) return string_new_capacity(0);
    
    // Determine result encoding
    StringEncoding result_encoding = (a->encoding == STRING_ENCODING_ASCII && b->encoding == STRING_ENCODING_ASCII) 
                                   ? STRING_ENCODING_ASCII : STRING_ENCODING_UTF32;
    
    StringDescriptor* result;
    if (result_encoding == STRING_ENCODING_ASCII) {
        // Both ASCII: create ASCII result
        result = string_new_ascii_capacity(total_len);
        if (!result) return NULL;
        
        // Copy ASCII data
        uint8_t* dest = (uint8_t*)result->data;
        if (a->length > 0) {
            memcpy(dest, a->data, a->length * sizeof(uint8_t));
            dest += a->length;
        }
        if (b->length > 0) {
            memcpy(dest, b->data, b->length * sizeof(uint8_t));
        }
    } else {
        // Mixed encodings: create UTF-32 result
        result = string_new_capacity(total_len);
        if (!result) return NULL;
        
        uint32_t* dest = (uint32_t*)result->data;
        
        // Copy first string
        if (a->length > 0) {
            if (a->encoding == STRING_ENCODING_ASCII) {
                // Convert ASCII to UTF-32 on the fly
                uint8_t* src = (uint8_t*)a->data;
                for (int64_t i = 0; i < a->length; i++) {
                    dest[i] = (uint32_t)src[i];
                }
            } else {
                // Copy UTF-32 directly
                memcpy(dest, a->data, a->length * sizeof(uint32_t));
            }
            dest += a->length;
        }
        
        // Copy second string
        if (b->length > 0) {
            if (b->encoding == STRING_ENCODING_ASCII) {
                // Convert ASCII to UTF-32 on the fly
                uint8_t* src = (uint8_t*)b->data;
                for (int64_t i = 0; i < b->length; i++) {
                    dest[i] = (uint32_t)src[i];
                }
            } else {
                // Copy UTF-32 directly
                memcpy(dest, b->data, b->length * sizeof(uint32_t));
            }
        }
    }
    
    result->length = total_len;
    
    return result;
}

// Substring (MID$)
StringDescriptor* string_mid(const StringDescriptor* str, int64_t start, int64_t length) {
    if (!str || start < 0 || start >= str->length || length <= 0) {
        return string_new_capacity(0);
    }
    
    // Clamp length to available characters
    if (start + length > str->length) {
        length = str->length - start;
    }
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        // ASCII encoding - data is uint8_t*
        return string_new_ascii_len(str->data + start, length);
    } else {
        // UTF-32 encoding
        return string_new_utf32(str->data + start, length);
    }
}

// Left substring
StringDescriptor* string_left(const StringDescriptor* str, int64_t count) {
    if (!str || count <= 0) return string_new_capacity(0);
    if (count > str->length) count = str->length;
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len(str->data, count);
    } else {
        return string_new_utf32(str->data, count);
    }
}

// Right substring
StringDescriptor* string_right(const StringDescriptor* str, int64_t count) {
    if (!str || count <= 0) return string_new_capacity(0);
    if (count > str->length) count = str->length;
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len(str->data + (str->length - count), count);
    } else {
        return string_new_utf32(str->data + (str->length - count), count);
    }
}

// String slicing (start TO end, inclusive)
StringDescriptor* string_slice(const StringDescriptor* str, int64_t start, int64_t end) {
    if (!str || start < 1 || (end != -1 && end < start) || start > str->length) {
        return string_new_capacity(0);
    }
    
    // Handle implied end (-1 means to end of string)
    if (end == -1) {
        end = str->length;
    }
    
    // Adjust for 1-based indexing (BASIC style)
    start--;  // Convert to 0-based
    end--;    // Convert to 0-based
    
    // Clamp end to string length
    if (end >= str->length) {
        end = str->length - 1;
    }
    
    int64_t length = end - start + 1;
    if (length <= 0) return string_new_capacity(0);
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        return string_new_ascii_len(str->data + start, length);
    } else {
        return string_new_utf32(str->data + start, length);
    }
}

// Find substring starting from position (0-based, returns 0-based index or -1)
int64_t string_instr(const StringDescriptor* haystack, const StringDescriptor* needle, int64_t start_pos) {
    if (!haystack || !needle || needle->length == 0) return -1;
    if (start_pos < 0) start_pos = 0;
    if (start_pos >= haystack->length) return -1;
    if (needle->length > haystack->length - start_pos) return -1;
    
    int64_t max_pos = haystack->length - needle->length;
    
    for (int64_t pos = start_pos; pos <= max_pos; pos++) {
        bool match = true;
        for (int64_t i = 0; i < needle->length; i++) {
            if (STR_CHAR(haystack, pos + i) != STR_CHAR(needle, i)) {
                match = false;
                break;
            }
        }
        if (match) {
            return pos;  // Return 0-based index
        }
    }
    
    return -1;
}

// String comparison
int string_compare(const StringDescriptor* a, const StringDescriptor* b) {
    if (!a || !b) return 0;
    
    int64_t min_len = (a->length < b->length) ? a->length : b->length;
    
    for (int64_t i = 0; i < min_len; i++) {
        uint32_t ac = STR_CHAR(a, i);
        uint32_t bc = STR_CHAR(b, i);
        if (ac < bc) return -1;
        if (ac > bc) return 1;
    }
    
    if (a->length < b->length) return -1;
    if (a->length > b->length) return 1;
    return 0;
}

// String comparison (case-insensitive)
int string_compare_nocase(const StringDescriptor* a, const StringDescriptor* b) {
    if (!a || !b) return 0;
    
    int64_t min_len = (a->length < b->length) ? a->length : b->length;
    
    for (int64_t i = 0; i < min_len; i++) {
        uint32_t ca = char_to_lower(STR_CHAR(a, i));
        uint32_t cb = char_to_lower(STR_CHAR(b, i));
        if (ca < cb) return -1;
        if (ca > cb) return 1;
    }
    
    if (a->length < b->length) return -1;
    if (a->length > b->length) return 1;
    return 0;
}

// Convert to uppercase
StringDescriptor* string_upper(const StringDescriptor* str) {
    if (!str) return string_new_capacity(0);
    
    StringDescriptor* result = string_clone(str);
    if (!result) return NULL;
    
    for (int64_t i = 0; i < result->length; i++) {
        STR_SET_CHAR(result, i, char_to_upper(STR_CHAR(result, i)));
    }
    
    return result;
}

// Convert to lowercase
StringDescriptor* string_lower(const StringDescriptor* str) {
    if (!str) return string_new_capacity(0);
    
    StringDescriptor* result = string_clone(str);
    if (!result) return NULL;
    
    for (int64_t i = 0; i < result->length; i++) {
        STR_SET_CHAR(result, i, char_to_lower(STR_CHAR(result, i)));
    }
    
    return result;
}

// Trim whitespace
StringDescriptor* string_trim(const StringDescriptor* str) {
    if (!str || str->length == 0) return string_new_capacity(0);
    
    // Find first non-whitespace
    int64_t start = 0;
    while (start < str->length && char_is_whitespace(STR_CHAR(str, start))) {
        start++;
    }
    
    if (start >= str->length) return string_new_capacity(0);
    
    // Find last non-whitespace
    int64_t end = str->length;
    while (end > start && char_is_whitespace(STR_CHAR(str, end - 1))) {
        end--;
    }
    
    // Create substring
    int64_t new_len = end - start;
    StringDescriptor* result = string_new_capacity(new_len);
    if (!result) return NULL;
    
    result->encoding = str->encoding;
    result->length = new_len;
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        uint8_t* src = ((uint8_t*)str->data) + start;
        uint8_t* dst = (uint8_t*)realloc(result->data, new_len);
        if (dst) {
            result->data = dst;
            memcpy(result->data, src, new_len);
        }
    } else {
        uint32_t* src = ((uint32_t*)str->data) + start;
        memcpy(result->data, src, new_len * sizeof(uint32_t));
    }
    
    return result;
}

// Trim left whitespace
StringDescriptor* string_ltrim(const StringDescriptor* str) {
    if (!str || str->length == 0) return string_new_capacity(0);
    
    int64_t start = 0;
    while (start < str->length && char_is_whitespace(STR_CHAR(str, start))) {
        start++;
    }
    
    if (start >= str->length) return string_new_capacity(0);
    
    // Create substring from start to end
    StringDescriptor* result = string_new_capacity(str->length - start);
    if (!result) return NULL;
    
    result->encoding = str->encoding;
    result->length = str->length - start;
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        uint8_t* src = ((uint8_t*)str->data) + start;
        uint8_t* dst = (uint8_t*)realloc(result->data, result->length);
        if (dst) {
            result->data = dst;
            memcpy(result->data, src, result->length);
        }
    } else {
        uint32_t* src = ((uint32_t*)str->data) + start;
        memcpy(result->data, src, result->length * sizeof(uint32_t));
    }
    
    return result;
}

// Trim right whitespace
StringDescriptor* string_rtrim(const StringDescriptor* str) {
    if (!str || str->length == 0) return string_new_capacity(0);
    
    int64_t end = str->length;
    while (end >= 0 && char_is_whitespace(STR_CHAR(str, end))) {
        end--;
    }
    
    if (end < 0) return string_new_capacity(0);
    
    // Create substring from start to end+1
    StringDescriptor* result = string_new_capacity(end + 1);
    if (!result) return NULL;
    
    result->encoding = str->encoding;
    result->length = end + 1;
    
    if (str->encoding == STRING_ENCODING_ASCII) {
        uint8_t* dst = (uint8_t*)realloc(result->data, result->length);
        if (dst) {
            result->data = dst;
            memcpy(result->data, str->data, result->length);
        }
    } else {
        memcpy(result->data, str->data, result->length * sizeof(uint32_t));
    }
    
    return result;
}

// Reverse string
StringDescriptor* string_reverse(const StringDescriptor* str) {
    if (!str) return string_new_capacity(0);
    
    StringDescriptor* result = string_new_capacity(str->length);
    if (!result) return NULL;
    
    for (int64_t i = 0; i < str->length; i++) {
        STR_SET_CHAR(result, i, STR_CHAR(str, str->length - 1 - i));
    }
    result->length = str->length;
    
    return result;
}

    // Count occurrences of a substring (non-overlapping)
    int64_t string_tally(const StringDescriptor* str, const StringDescriptor* pattern) {
        if (!str || !pattern || pattern->length == 0 || str->length == 0) {
            return 0;
        }

        int64_t count = 0;
        int64_t pos = 0;
        while (pos <= str->length - pattern->length) {
            int64_t found = string_instr(str, pattern, pos);
            if (found < 0) break;
            count++;
            pos = found + pattern->length;
        }
        return count;
    }

    // Find substring from the right; returns 0-based index or -1 if not found
    int64_t string_instrrev(const StringDescriptor* haystack, const StringDescriptor* needle, int64_t start_pos) {
        if (!haystack || !needle || needle->length == 0) return -1;
        if (haystack->length == 0 || needle->length > haystack->length) return -1;

        // Default start position is end of haystack
        int64_t start = start_pos;
        if (start < 0 || start > haystack->length - needle->length) {
            start = haystack->length - needle->length;
        }

        for (int64_t pos = start; pos >= 0; pos--) {
            bool match = true;
            for (int64_t i = 0; i < needle->length; i++) {
                if (STR_CHAR(haystack, pos + i) != STR_CHAR(needle, i)) {
                    match = false;
                    break;
                }
            }
            if (match) {
                return pos;
            }
        }
        return -1;
    }

    // Insert substring at 1-based position
    StringDescriptor* string_insert(const StringDescriptor* str, int64_t pos, const StringDescriptor* insert_str) {
        if (!str) return string_clone(insert_str);
        if (!insert_str || insert_str->length == 0) return string_clone(str);

        // Clamp position to [1, len+1]
        if (pos < 1) pos = 1;
        if (pos > str->length + 1) pos = str->length + 1;

        int64_t prefix_len = pos - 1; // 0-based prefix length
        int64_t new_len = str->length + insert_str->length;

        StringDescriptor* result = string_new_capacity(new_len);
        if (!result) return NULL;

        // Copy prefix
        for (int64_t i = 0; i < prefix_len; i++) {
            STR_SET_CHAR(result, i, STR_CHAR(str, i));
        }

        // Copy inserted string
        for (int64_t i = 0; i < insert_str->length; i++) {
            STR_SET_CHAR(result, prefix_len + i, STR_CHAR(insert_str, i));
        }

        // Copy suffix
        for (int64_t i = prefix_len; i < str->length; i++) {
            STR_SET_CHAR(result, insert_str->length + i, STR_CHAR(str, i));
        }

        result->length = new_len;
        return result;
    }

    // Delete substring starting at 1-based position for given length
    StringDescriptor* string_delete(const StringDescriptor* str, int64_t pos, int64_t len) {
        if (!str || str->length == 0 || len <= 0) return string_clone(str);
        if (pos < 1) pos = 1;
        int64_t start = pos - 1; // 0-based
        if (start >= str->length) return string_clone(str);
        if (start + len > str->length) len = str->length - start;

        int64_t new_len = str->length - len;
        StringDescriptor* result = string_new_capacity(new_len);
        if (!result) return NULL;

        // Copy prefix
        for (int64_t i = 0; i < start; i++) {
            STR_SET_CHAR(result, i, STR_CHAR(str, i));
        }

        // Copy suffix
        for (int64_t i = start + len; i < str->length; i++) {
            STR_SET_CHAR(result, i - len, STR_CHAR(str, i));
        }

        result->length = new_len;
        return result;
    }

    // Remove all occurrences of pattern
    StringDescriptor* string_remove(const StringDescriptor* str, const StringDescriptor* pattern) {
        if (!str || str->length == 0) return string_new_capacity(0);
        if (!pattern || pattern->length == 0) return string_clone(str);

        StringDescriptor* empty = string_new_capacity(0);
        StringDescriptor* replaced = string_replace(str, pattern, empty);
        string_release(empty);
        return replaced;
    }

    // Extract substring by inclusive 1-based start/end
    StringDescriptor* string_extract(const StringDescriptor* str, int64_t start_pos, int64_t end_pos) {
        if (!str || str->length == 0) return string_new_capacity(0);
        if (start_pos < 1) start_pos = 1;
        if (end_pos < start_pos) return string_new_capacity(0);
        if (end_pos > str->length) end_pos = str->length;

        return string_slice(str, start_pos, end_pos);
    }

    // Left pad to width with padChar (first codepoint of pad string, default space)
    StringDescriptor* string_lpad(const StringDescriptor* str, int64_t width, const StringDescriptor* padStr) {
        if (!str) return string_new_capacity(0);
        if (width <= str->length) return string_clone(str);

        uint32_t pad = 0x20; // space
        if (padStr && padStr->length > 0) {
            pad = STR_CHAR(padStr, 0);
        }

        int64_t pad_len = width - str->length;
        StringDescriptor* pad_segment = string_new_repeat(pad, pad_len);
        if (!pad_segment) return NULL;

        StringDescriptor* result = string_concat(pad_segment, str);
        string_release(pad_segment);
        return result;
    }

    // Right pad to width with padChar
    StringDescriptor* string_rpad(const StringDescriptor* str, int64_t width, const StringDescriptor* padStr) {
        if (!str) return string_new_capacity(0);
        if (width <= str->length) return string_clone(str);

        uint32_t pad = 0x20;
        if (padStr && padStr->length > 0) {
            pad = STR_CHAR(padStr, 0);
        }

        int64_t pad_len = width - str->length;
        StringDescriptor* pad_segment = string_new_repeat(pad, pad_len);
        if (!pad_segment) return NULL;

        StringDescriptor* result = string_concat(str, pad_segment);
        string_release(pad_segment);
        return result;
    }

    // Center string within width using padChar
    StringDescriptor* string_center(const StringDescriptor* str, int64_t width, const StringDescriptor* padStr) {
        if (!str) return string_new_capacity(0);
        if (width <= str->length) return string_clone(str);

        uint32_t pad = 0x20;
        if (padStr && padStr->length > 0) {
            pad = STR_CHAR(padStr, 0);
        }

        int64_t total_pad = width - str->length;
        int64_t left_pad = total_pad / 2;
        int64_t right_pad = total_pad - left_pad;

        StringDescriptor* left = string_new_repeat(pad, left_pad);
        StringDescriptor* right = string_new_repeat(pad, right_pad);
        if (!left || !right) {
            if (left) string_release(left);
            if (right) string_release(right);
            return NULL;
        }

        StringDescriptor* tmp = string_concat(left, str);
        StringDescriptor* result = string_concat(tmp, right);

        string_release(left);
        string_release(right);
        string_release(tmp);
        return result;
    }

    // Create string of spaces (wrapper for clarity)
    StringDescriptor* string_space(int64_t count) {
        return string_new_repeat(0x20, count);
    }

    // Repeat a whole string pattern 'count' times
    StringDescriptor* string_repeat(const StringDescriptor* pattern, int64_t count) {
        if (count <= 0) return string_new_capacity(0);
        if (!pattern || pattern->length == 0) return string_new_capacity(0);

        int64_t new_len = pattern->length * count;
        StringDescriptor* result = string_new_capacity(new_len);
        if (!result) return NULL;

        for (int64_t i = 0; i < count; i++) {
            for (int64_t j = 0; j < pattern->length; j++) {
                STR_SET_CHAR(result, i * pattern->length + j, STR_CHAR(pattern, j));
            }
        }
        result->length = new_len;
        return result;
    }

    // Join array of strings with a separator
    StringDescriptor* string_join(const ArrayDescriptor* arrayDesc, const StringDescriptor* separator) {
        if (!arrayDesc) {
            return string_new_capacity(0);
        }

        const StringDescriptor* sep = separator ? separator : string_new_capacity(0);
        int64_t sep_len = sep ? sep->length : 0;

        // Compute element count
        int64_t count = (arrayDesc->upperBound1 >= arrayDesc->lowerBound1)
            ? (arrayDesc->upperBound1 - arrayDesc->lowerBound1 + 1)
            : 0;

        if (count <= 0 || !arrayDesc->data) {
            if (!separator && sep) string_release((StringDescriptor*)sep);
            return string_new_capacity(0);
        }

        StringDescriptor** data = (StringDescriptor**)arrayDesc->data;

        // Total length in codepoints
        int64_t total_len = 0;
        for (int64_t i = 0; i < count; i++) {
            const StringDescriptor* s = data[i];
            total_len += s ? s->length : 0;
            if (i + 1 < count) total_len += sep_len;
        }

        StringDescriptor* result = string_new_capacity(total_len);
        if (!result) {
            if (!separator && sep) string_release((StringDescriptor*)sep);
            return NULL;
        }

        int64_t pos = 0;
        for (int64_t i = 0; i < count; i++) {
            const StringDescriptor* s = data[i];
            if (s && s->length > 0 && s->data) {
                if (s->encoding == STRING_ENCODING_ASCII) {
                    const uint8_t* src = (const uint8_t*)s->data;
                    for (int64_t k = 0; k < s->length; k++) {
                        ((uint32_t*)result->data)[pos++] = (uint32_t)src[k];
                    }
                } else {
                    const uint32_t* src = (const uint32_t*)s->data;
                    memcpy(((uint32_t*)result->data) + pos, src, s->length * sizeof(uint32_t));
                    pos += s->length;
                }
            }

            if (i + 1 < count && sep_len > 0 && sep && sep->data) {
                if (sep->encoding == STRING_ENCODING_ASCII) {
                    const uint8_t* src = (const uint8_t*)sep->data;
                    for (int64_t k = 0; k < sep_len; k++) {
                        ((uint32_t*)result->data)[pos++] = (uint32_t)src[k];
                    }
                } else {
                    const uint32_t* src = (const uint32_t*)sep->data;
                    memcpy(((uint32_t*)result->data) + pos, src, sep_len * sizeof(uint32_t));
                    pos += sep_len;
                }
            }
        }

        result->length = total_len;
        result->capacity = total_len;
        result->encoding = STRING_ENCODING_UTF32; // Ensure UTF-32 backing
        result->dirty = 1;

        if (!separator && sep) string_release((StringDescriptor*)sep);
        return result;
    }

    // Helper to allocate descriptor + data for split results
    static ArrayDescriptor* alloc_split_desc(int64_t upperBound, size_t elemSize) {
        ArrayDescriptor* desc = (ArrayDescriptor*)malloc(sizeof(ArrayDescriptor));
        if (!desc) return NULL;
        if (array_descriptor_init(desc, 0, upperBound, (int64_t)elemSize, 0, '$') != 0) {
            free(desc);
            return NULL;
        }
        return desc;
    }

    // Split string into array of StringDescriptor* (1D array, lower bound 0)
    ArrayDescriptor* string_split(const StringDescriptor* str, const StringDescriptor* delimiter) {
        const size_t elemSize = sizeof(StringDescriptor*);

        if (!str) {
            ArrayDescriptor* desc = alloc_split_desc(0, elemSize);
            if (!desc) return NULL;
            StringDescriptor* empty = string_new_capacity(0);
            StringDescriptor** data = (StringDescriptor**)desc->data;
            data[0] = string_retain(empty);
            string_release(empty);
            return desc;
        }

        if (!delimiter || delimiter->length == 0) {
            ArrayDescriptor* desc = alloc_split_desc(0, elemSize);
            if (!desc) return NULL;
            StringDescriptor** data = (StringDescriptor**)desc->data;
            data[0] = string_retain((StringDescriptor*)str);
            return desc;
        }

        int64_t pos = 0;
        int64_t parts = 0;
        int64_t hay_len = str->length;
        int64_t delim_len = delimiter->length;

        // First pass: count parts (occurrences + 1)
        while (true) {
            int64_t found = string_instr(str, delimiter, pos);
            parts++;
            if (found < 0) break;
            pos = found + delim_len;
            if (pos > hay_len) break;
        }

        ArrayDescriptor* desc = alloc_split_desc(parts - 1, elemSize);
        if (!desc) return NULL;
        StringDescriptor** data = (StringDescriptor**)desc->data;

        // Second pass: extract parts
        pos = 0;
        int64_t slot = 0;
        while (slot < parts) {
            int64_t found = string_instr(str, delimiter, pos);
            int64_t seg_len = (found < 0) ? (hay_len - pos) : (found - pos);
            if (seg_len < 0) seg_len = 0;
            StringDescriptor* segment = string_mid(str, pos, seg_len);
            data[slot] = string_retain(segment);
            string_release(segment);
            slot++;
            if (found < 0) break;
            pos = found + delim_len;
        }

        return desc;
    }

// Replace all occurrences
StringDescriptor* string_replace(const StringDescriptor* str, 
                                  const StringDescriptor* old_substr,
                                  const StringDescriptor* new_substr) {
    if (!str || !old_substr || old_substr->length == 0) {
        return str ? string_clone(str) : string_new_capacity(0);
    }
    if (!new_substr) new_substr = string_new_capacity(0);
    
    // Count occurrences
    int64_t count = 0;
    int64_t pos = 0;
    while ((pos = string_instr(str, old_substr, pos)) >= 0) {
        count++;
        pos += old_substr->length;
    }
    
    if (count == 0) return string_clone(str);
    
    // Calculate new length
    int64_t new_len = str->length + count * (new_substr->length - old_substr->length);
    StringDescriptor* result = string_new_capacity(new_len);
    if (!result) return NULL;
    
    // Build result
    int64_t src_pos = 0;
    int64_t dst_pos = 0;
    
    while (src_pos < str->length) {
        int64_t match_pos = string_instr(str, old_substr, src_pos);
        
        if (match_pos < 0 || match_pos >= str->length) {
            // Copy remainder
            int64_t remaining = str->length - src_pos;
            if (remaining > 0) {
                memcpy(result->data + dst_pos, str->data + src_pos, 
                       remaining * sizeof(uint32_t));
                dst_pos += remaining;
            }
            break;
        }
        
        // Copy before match
        if (match_pos > src_pos) {
            int64_t prefix_len = match_pos - src_pos;
            memcpy(result->data + dst_pos, str->data + src_pos, 
                   prefix_len * sizeof(uint32_t));
            dst_pos += prefix_len;
        }
        
        // Copy replacement
        if (new_substr->length > 0) {
            memcpy(result->data + dst_pos, new_substr->data, 
                   new_substr->length * sizeof(uint32_t));
            dst_pos += new_substr->length;
        }
        
        src_pos = match_pos + old_substr->length;
    }
    
    result->length = dst_pos;
    return result;
}

// =============================================================================
// Conversion Functions
// =============================================================================

// Convert string to integer
int64_t string_to_int(const StringDescriptor* str) {
    if (!str || str->length == 0) return 0;
    const char* utf8 = string_to_utf8((StringDescriptor*)str);
    return strtoll(utf8, NULL, 10);
}

// Convert string to double
double string_to_double(const StringDescriptor* str) {
    if (!str || str->length == 0) return 0.0;
    const char* utf8 = string_to_utf8((StringDescriptor*)str);
    return strtod(utf8, NULL);
}

// Convert integer to string
StringDescriptor* string_from_int(int64_t value) {
    char buffer[32];
    snprintf(buffer, sizeof(buffer), "%lld", (long long)value);
    return string_new_utf8(buffer);
}

// Convert double to string
StringDescriptor* string_from_double(double value) {
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%.15g", value);
    return string_new_utf8(buffer);
}

// Internal helper to format integer in arbitrary base
static StringDescriptor* format_int_base(int64_t value, int base, int64_t min_digits, const char* alphabet) {
    if (base < 2 || base > 36) return string_new_capacity(0);
    if (min_digits < 0) min_digits = 0;

    char buffer[80];
    int idx = 0;

    bool negative = value < 0;
    uint64_t u = negative ? (uint64_t)(-value) : (uint64_t)value;

    if (u == 0) {
        buffer[idx++] = '0';
    }
    while (u > 0 && idx < (int)sizeof(buffer) - 1) {
        buffer[idx++] = alphabet[u % base];
        u /= base;
    }

    while (idx < min_digits && idx < (int)sizeof(buffer) - 1) {
        buffer[idx++] = '0';
    }

    if (negative && idx < (int)sizeof(buffer) - 1) {
        buffer[idx++] = '-';
    }

    buffer[idx] = '\0';

    // Reverse in-place
    for (int i = 0, j = idx - 1; i < j; i++, j--) {
        char tmp = buffer[i];
        buffer[i] = buffer[j];
        buffer[j] = tmp;
    }

    return string_new_utf8(buffer);
}

// HEX$ helper
StringDescriptor* HEX_STRING(int64_t value, int64_t digits) {
    static const char* alphabet = "0123456789ABCDEF";
    return format_int_base(value, 16, digits, alphabet);
}

// BIN$ helper
StringDescriptor* BIN_STRING(int64_t value, int64_t digits) {
    static const char* alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return format_int_base(value, 2, digits, alphabet);
}

// OCT$ helper
StringDescriptor* OCT_STRING(int64_t value, int64_t digits) {
    static const char* alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    return format_int_base(value, 8, digits, alphabet);
}

// =============================================================================
// BASIC-Specific String Functions
// =============================================================================

// STRING$(n, c) - Create string of n characters c
StringDescriptor* basic_string_repeat(int64_t count, uint32_t codepoint) {
    return string_new_repeat(codepoint, count);
}

// CHR$(n) - Create single-character string
StringDescriptor* basic_chr(uint32_t codepoint) {
    return string_new_repeat(codepoint, 1);
}

// ASC(s$) - Get code point of first character
// ASC(s$) - Get code point of first character
uint32_t basic_asc(const StringDescriptor* str) {
    if (!str || str->length == 0) return 0;
    if (str->encoding == STRING_ENCODING_ASCII) {
        return ((uint8_t*)str->data)[0];
    } else {
        return ((uint32_t*)str->data)[0];
    }
}

// VAL(s$) - Convert string to number
double basic_val(const StringDescriptor* str) {
    return string_to_double(str);
}

// STR$(n) - Convert number to string (integer)
StringDescriptor* basic_str_int(int64_t value) {
    return string_from_int(value);
}

// STR$(n) - Convert number to string (double)
StringDescriptor* basic_str_double(double value) {
    return string_from_double(value);
}

// SPACE$(n) - Create string of n spaces
StringDescriptor* basic_space(int64_t count) {
    return string_new_repeat(0x20, count);  // 0x20 = space character
}

// =============================================================================
// Character Access Functions (for indexed access: A$(i))
// =============================================================================

// Get character at index (0-based, returns 0 if out of bounds)
// This is for intrinsic use: code = A$(i)
uint32_t string_get_char_at(const StringDescriptor* str, int64_t index) {
    if (!str || index < 0 || index >= str->length) {
        return 0;  // Out of bounds
    }
    return STR_CHAR(str, index);
}

// Set character at index (0-based, with auto-promotion if needed)
// This is for intrinsic use: A$(i) = code
// Returns: 1 on success, 0 on failure
int string_set_char_at(StringDescriptor* str, int64_t index, uint32_t codepoint) {
    if (!str || index < 0 || index >= str->length) {
        return 0;  // Out of bounds
    }
    
    // Check if we need to promote ASCII → UTF-32
    if (str->encoding == STRING_ENCODING_ASCII && codepoint >= 128) {
        // Promote to UTF-32 before storing
        string_promote_to_utf32(str);
    }
    
    // Now store the character
    if (str->encoding == STRING_ENCODING_ASCII) {
        if (codepoint > 127) return 0;  // Safety check (shouldn't happen after promotion)
        ((uint8_t*)str->data)[index] = (uint8_t)codepoint;
    } else {
        ((uint32_t*)str->data)[index] = codepoint;
    }
    
    str->dirty = 1;  // Invalidate UTF-8 cache
    return 1;
}

// =============================================================================
// Memory Management Helpers
// =============================================================================

// Ensure capacity (may reallocate)
bool string_ensure_capacity(StringDescriptor* str, int64_t required_capacity) {
    if (!str) return false;
    if (str->capacity >= required_capacity) return true;
    
    uint32_t* new_data = (uint32_t*)realloc(str->data, required_capacity * sizeof(uint32_t));
    if (!new_data) return false;
    
    str->data = new_data;
    str->capacity = required_capacity;
    return true;
}

// Shrink capacity to match length
void string_shrink_to_fit(StringDescriptor* str) {
    if (!str || str->capacity == str->length) return;
    
    if (str->length == 0) {
        free(str->data);
        str->data = NULL;
        str->capacity = 0;
        return;
    }
    
    uint32_t* new_data = (uint32_t*)realloc(str->data, str->length * sizeof(uint32_t));
    if (new_data) {
        str->data = new_data;
        str->capacity = str->length;
    }
}

// =============================================================================
// Debug and Statistics
// =============================================================================

// Print string descriptor info (for debugging)
void string_debug_print(const StringDescriptor* str) {
    if (!str) {
        printf("StringDescriptor: NULL\n");
        return;
    }
    
    printf("StringDescriptor {\n");
    printf("  length: %lld\n", (long long)str->length);
    printf("  capacity: %lld\n", (long long)str->capacity);
    printf("  refcount: %d\n", str->refcount);
    printf("  dirty: %d\n", str->dirty);
    printf("  utf8_cache: %p\n", (void*)str->utf8_cache);
    printf("  content: \"%s\"\n", string_to_utf8((StringDescriptor*)str));
    printf("}\n");
}

// Get memory usage
size_t string_memory_usage(const StringDescriptor* str) {
    if (!str) return 0;
    
    size_t total = sizeof(StringDescriptor);
    total += str->capacity * sizeof(uint32_t);
    
    if (str->utf8_cache) {
        total += strlen(str->utf8_cache) + 1;
    }
    
    return total;
}

// MID$ assignment: MID$(str, pos, len) = replacement
StringDescriptor* string_mid_assign(StringDescriptor* str, int64_t pos, int64_t len, const StringDescriptor* replacement) {
    if (!str || pos < 1 || len < 0) return str;
    if (!replacement) replacement = string_new_capacity(0);
    
    // Copy-on-write: If string is shared (refcount > 1), create independent copy
    if (str->refcount > 1) {
        StringDescriptor* new_str = string_clone(str);
        if (!new_str) return str;  // Allocation failed, return original
        str->refcount--;  // Decrement refcount on original
        str = new_str;    // Work with the new copy
    }
    
    // Adjust for 1-based indexing
    pos--;  // Convert to 0-based
    
    // Clamp position and length
    if (pos < 0) pos = 0;
    if (pos >= str->length) return str;  // Nothing to replace
    if (len > str->length - pos) len = str->length - pos;
    
    // If replacement is same length, just copy
    if (len == replacement->length) {
        for (int64_t i = 0; i < len; i++) {
            STR_SET_CHAR(str, pos + i, STR_CHAR(replacement, i));
        }
        // Clear UTF-8 cache since string changed
        if (str->utf8_cache) {
            free(str->utf8_cache);
            str->utf8_cache = NULL;
            str->dirty = 1;
        }
        return str;
    }
    
    // Need to resize the string - create new string with correct size
    int64_t new_length = str->length - len + replacement->length;
    StringDescriptor* new_str = string_new_capacity(new_length);
    if (!new_str) return str;
    
    // Copy prefix (before replacement)
    for (int64_t i = 0; i < pos; i++) {
        STR_SET_CHAR(new_str, i, STR_CHAR(str, i));
    }
    
    // Copy replacement
    for (int64_t i = 0; i < replacement->length; i++) {
        STR_SET_CHAR(new_str, pos + i, STR_CHAR(replacement, i));
    }
    
    // Copy suffix (after replacement)
    for (int64_t i = pos + len; i < str->length; i++) {
        STR_SET_CHAR(new_str, pos + replacement->length + (i - pos - len), STR_CHAR(str, i));
    }
    
    new_str->length = new_length;
    
    // Free old string
    if (str->data) {
        free(str->data);
    }
    if (str->utf8_cache) {
        free(str->utf8_cache);
    }
    free(str);
    
    return new_str;
}

// String slice assignment: str$(start TO end) = replacement
StringDescriptor* string_slice_assign(StringDescriptor* str, int64_t start, int64_t end, const StringDescriptor* replacement) {
    if (!str || start < 1) return str;
    if (!replacement) replacement = string_new_capacity(0);
    
    // Handle implied end
    if (end == -1) {
        end = str->length;
    }
    
    // Adjust for 1-based indexing
    start--;  // Convert to 0-based
    end--;    // Convert to 0-based
    
    // Clamp positions
    if (start < 0) start = 0;
    if (end >= str->length) end = str->length - 1;
    if (start > end) return str;  // Invalid range
    
    int64_t len = end - start + 1;
    
    // Use MID assignment logic
    return string_mid_assign(str, start + 1, len, replacement);
}
