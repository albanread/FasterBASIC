#include "basic_runtime.h"
#include "string_descriptor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <stdbool.h>
#include <ctype.h>

// Internal helper: Reverses a string in place
static void reverse_str(char* s) {
    int i, j;
    for (i = 0, j = strlen(s) - 1; i < j; i++, j--) {
        char c = s[i]; s[i] = s[j]; s[j] = c;
    }
}

// Parse and format a numeric value according to a mask pattern
static void format_numeric(char* output, size_t output_size, const char* mask, const char* value_str) {
    // Try to parse value as a number
    char* endptr;
    double value = strtod(value_str, &endptr);
    bool is_numeric = (*endptr == '\0' || isspace(*endptr));
    
    if (!is_numeric) {
        // Not a number - just copy the value
        snprintf(output, output_size, "%s", value_str);
        return;
    }
    
    bool is_neg = (value < 0);
    double abs_val = fabs(value);

    // Analyze mask features
    bool has_comma = (strchr(mask, ',') != NULL);
    bool has_plus = (mask[0] == '+');
    bool has_minus_suffix = (mask[strlen(mask) - 1] == '-');
    bool has_exp = (strstr(mask, "^^^^") != NULL);
    bool has_dollar = (strstr(mask, "$$") != NULL);
    bool has_asterisk = (strstr(mask, "**") != NULL);

    // Determine precision
    int precision = 0;
    const char* dot = strchr(mask, '.');
    if (dot) {
        for (const char* p = dot + 1; *p == '#' || *p == '^'; p++) precision++;
    }

    // Core conversion
    char work[128];
    if (has_exp) {
        snprintf(work, sizeof(work), "%.*E", precision, value);
    } else {
        snprintf(work, sizeof(work), "%.*f", precision, abs_val);
    }

    // Manual comma insertion (integer part only)
    if (has_comma && !has_exp) {
        char *w_dot = strchr(work, '.');
        int int_len = w_dot ? (int)(w_dot - work) : (int)strlen(work);
        
        int src = int_len - 1;
        int dst = 0;
        int count = 0;
        char temp[128] = {0};

        while (src >= 0) {
            if (count > 0 && count % 3 == 0) temp[dst++] = ',';
            temp[dst++] = work[src--];
            count++;
        }
        reverse_str(temp);
        if (w_dot) strcat(temp, w_dot); // Append decimal part
        strcpy(work, temp);
    }

    // Decorations (Sign, $, *)
    char decorated[256] = {0};
    char prefix[10] = {0};
    
    if (has_plus) {
        strcat(prefix, is_neg ? "-" : "+");
    } else if (is_neg && !has_minus_suffix) {
        strcat(prefix, "-");
    }

    if (has_dollar) strcat(prefix, "$");
    
    snprintf(decorated, sizeof(decorated), "%s%s%s", prefix, work, (is_neg && has_minus_suffix) ? "-" : "");

    // Padding logic
    int mask_len = strlen(mask);
    int actual_len = strlen(decorated);
    int pad = mask_len - actual_len;

    if (pad < 0) {
        // Overflow - prefix with %
        snprintf(output, output_size, "%%%s", decorated);
    } else {
        // Pad with spaces or asterisks
        char padded[256] = {0};
        memset(padded, has_asterisk ? '*' : ' ', pad);
        strcat(padded, decorated);
        snprintf(output, output_size, "%s", padded);
    }
}

// Extract a format pattern starting at position p
// Returns the length of the pattern (0 if not a pattern)
static int extract_pattern(const char* p, char* pattern, size_t pattern_size) {
    const char* start = p;
    
    // Check for leading +, $, or *
    if (*p == '+' || (*p == '$' && *(p+1) == '$') || (*p == '*' && *(p+1) == '*')) {
        if (*p == '+') {
            pattern[0] = '+'; pattern[1] = '\0';
            p++;
        } else {
            pattern[0] = p[0]; pattern[1] = p[1]; pattern[2] = '\0';
            p += 2;
        }
    } else {
        pattern[0] = '\0';
    }
    
    // Collect #, comma, and decimal point
    size_t len = strlen(pattern);
    while (*p == '#' || *p == ',' || *p == '.') {
        if (len < pattern_size - 1) {
            pattern[len++] = *p;
            pattern[len] = '\0';
        }
        p++;
    }
    
    // Check for ^^^^
    if (strncmp(p, "^^^^", 4) == 0) {
        if (len + 4 < pattern_size) {
            strcat(pattern, "^^^^");
            len += 4;
        }
        p += 4;
    }
    
    // Check for trailing -
    if (*p == '-') {
        if (len < pattern_size - 1) {
            pattern[len++] = '-';
            pattern[len] = '\0';
        }
        p++;
    }
    
    // Return length only if we found at least one # or @
    if (strchr(pattern, '#') || strchr(start, '@')) {
        return (int)(p - start);
    }
    
    return 0;
}

// PRINT USING implementation with full numeric formatting support
void basic_print_using(StringDescriptor* format, int64_t count, StringDescriptor** args) {
    if (!format) return;

    // Extract format string UTF-8 immediately
    const char* fmt = string_to_utf8(format);
    if (!fmt) return;
    
    // Make a copy of format string since descriptors may be released
    char* fmt_copy = strdup(fmt);
    if (!fmt_copy) {
        basic_error_msg("Out of memory in basic_print_using");
        return;
    }

    // Collect argument UTF-8 strings immediately (before any descriptors are released)
    char** arg_strings = NULL;
    if (count > 0 && args) {
        arg_strings = (char**)calloc((size_t)count, sizeof(char*));
        if (!arg_strings) {
            free(fmt_copy);
            basic_error_msg("Out of memory in basic_print_using");
            return;
        }

        for (int64_t i = 0; i < count; i++) {
            if (args[i]) {
                const char* s = string_to_utf8(args[i]);
                if (s) {
                    arg_strings[i] = strdup(s);
                }
            }
        }
    }

    // Process the format string with collected arguments
    int64_t argIndex = 0;

    for (const char* p = fmt_copy; *p; ) {
        // Check for @ string placeholder
        if (*p == '@') {
            // String substitution - no special formatting
            if (argIndex < count && arg_strings && arg_strings[argIndex]) {
                printf("%s", arg_strings[argIndex]);
            }
            argIndex++;
            p++;
        }
        // Check for numeric format pattern
        else if (*p == '#' || *p == '+' || 
                 (*p == '$' && *(p+1) == '$') || 
                 (*p == '*' && *(p+1) == '*')) {
            char pattern[128];
            int pattern_len = extract_pattern(p, pattern, sizeof(pattern));
            
            if (pattern_len > 0) {
                // Apply numeric formatting
                if (argIndex < count && arg_strings && arg_strings[argIndex]) {
                    char formatted[256];
                    format_numeric(formatted, sizeof(formatted), pattern, arg_strings[argIndex]);
                    printf("%s", formatted);
                }
                argIndex++;
                p += pattern_len;
            } else {
                putchar(*p++);
            }
        } else {
            putchar(*p++);
        }
    }

    fflush(stdout);

    // Clean up
    if (arg_strings) {
        for (int64_t i = 0; i < count; i++) {
            if (arg_strings[i]) free(arg_strings[i]);
        }
        free(arg_strings);
    }
    free(fmt_copy);
}
