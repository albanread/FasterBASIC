//
// io_ops.c
// FasterBASIC QBE Runtime Library - I/O Operations
//
// This file implements console and file I/O operations.
//

#include "basic_runtime.h"
#include "string_descriptor.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// =============================================================================
// Console Output
// =============================================================================

void basic_print_int(int64_t value) {
    printf("%lld", (long long)value);
    fflush(stdout);
}

void basic_print_long(int64_t value) {
    printf("%lld", (long long)value);
    fflush(stdout);
}

void basic_print_float(float value) {
    printf("%g", value);
    fflush(stdout);
}

void basic_print_double(double value) {
    printf("%g", value);
    fflush(stdout);
}

void basic_print_string(BasicString* str) {
    if (!str) return;
    printf("%s", str->data);
    fflush(stdout);
}

// Print a C string literal (for compile-time string constants)
void basic_print_cstr(const char* str) {
    if (!str) return;
    printf("%s", str);
    fflush(stdout);
}

// Print UTF-32 StringDescriptor (converts to UTF-8 for output)
void basic_print_string_desc(StringDescriptor* desc) {
    if (!desc) return;
    const char* utf8 = string_to_utf8(desc);
    printf("%s", utf8);
    fflush(stdout);
}

void basic_print_hex(int64_t value) {
    printf("0x%llx", (unsigned long long)value);
    fflush(stdout);
}

void basic_print_pointer(void* ptr) {
    printf("0x%llx", (unsigned long long)(uintptr_t)ptr);
    fflush(stdout);
}

void debug_print_hashmap(void* map) {
    printf("[HASHMAP@");
    basic_print_pointer(map);
    printf("]");
    fflush(stdout);
}

void basic_print_newline(void) {
    printf("\n");
    fflush(stdout);
}

void basic_print_tab(void) {
    printf("\t");
    fflush(stdout);
}

void basic_print_at(int32_t row, int32_t col, BasicString* str) {
    // ANSI escape codes for cursor positioning (1-based)
    printf("\033[%d;%dH", row, col);
    if (str) {
        printf("%s", str->data);
    }
    fflush(stdout);
}

void basic_cls(void) {
    // ANSI escape code to clear screen and move cursor to home
    printf("\033[2J\033[H");
    fflush(stdout);
}

// =============================================================================
// Terminal Control Commands
// =============================================================================

// LOCATE: Move cursor to specific row, column (1-based)
void basic_locate(int32_t row, int32_t col) {
    printf("\033[%d;%dH", row, col);
    fflush(stdout);
}

// COLOR: Set foreground and background colors using ANSI codes
// Colors: 0=black, 1=blue, 2=green, 3=cyan, 4=red, 5=magenta, 6=yellow, 7=white
// 8-15 are bright versions
void basic_color(int32_t foreground, int32_t background) {
    // ANSI color codes: 30-37 for foreground, 40-47 for background
    // Bright colors: 90-97 for foreground, 100-107 for background
    
    int fg = 30, bg = 40;
    
    // Map BASIC colors to ANSI
    if (foreground >= 8) {
        fg = 90 + (foreground - 8);  // Bright colors
    } else if (foreground >= 0) {
        fg = 30 + foreground;
    }
    
    if (background >= 8) {
        bg = 100 + (background - 8);  // Bright backgrounds
    } else if (background >= 0) {
        bg = 40 + background;
    }
    
    printf("\033[%d;%dm", fg, bg);
    fflush(stdout);
}

// WIDTH: Set terminal width (informational - actual effect depends on terminal)
static int32_t g_terminal_width = 80;

void basic_width(int32_t columns) {
    if (columns > 0) {
        g_terminal_width = columns;
    }
}

int32_t basic_get_width(void) {
    return g_terminal_width;
}

// CSRLIN: Get current cursor row (1-based)
// Note: This requires terminal query support - for now return estimated position
static int32_t g_cursor_row = 1;

int32_t basic_csrlin(void) {
    // In a full implementation, we'd query the terminal with \033[6n
    // and parse the response. For now, track internally.
    return g_cursor_row;
}

// POS: Get current cursor column (1-based)
static int32_t g_cursor_col = 1;

int32_t basic_pos(int32_t dummy) {
    // dummy parameter for BASIC compatibility (always pass 0)
    (void)dummy;
    return g_cursor_col;
}

// Update cursor position tracking (called internally)
void _basic_update_cursor_pos(int32_t row, int32_t col) {
    g_cursor_row = row;
    g_cursor_col = col;
}

// INKEY$: Non-blocking keyboard input
// Returns empty string if no key pressed, otherwise returns single character
#include <fcntl.h>
#include <unistd.h>
#include <termios.h>

StringDescriptor* basic_inkey(void) {
    // Set stdin to non-blocking mode
    int flags = fcntl(STDIN_FILENO, F_GETFL, 0);
    fcntl(STDIN_FILENO, F_SETFL, flags | O_NONBLOCK);
    
    // Try to read one character
    char ch;
    ssize_t n = read(STDIN_FILENO, &ch, 1);
    
    // Restore blocking mode
    fcntl(STDIN_FILENO, F_SETFL, flags);
    
    if (n == 1) {
        // Got a character
        char str[2] = {ch, '\0'};
        return string_new_utf8(str);
    }
    
    // No character available
    return string_new_utf8("");
}

// LINE INPUT: Read entire line including commas and spaces
StringDescriptor* basic_line_input(const char* prompt) {
    if (prompt && prompt[0]) {
        printf("%s", prompt);
        fflush(stdout);
    }
    
    char buffer[4096];
    
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return string_new_utf8("");
    }
    
    // Remove trailing newline
    size_t len = strlen(buffer);
    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }
    
    return string_new_utf8(buffer);
}

// =============================================================================
// Console Input
// =============================================================================

BasicString* basic_input_string(void) {
    char buffer[4096];
    
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return str_new("");
    }
    
    // Remove trailing newline
    size_t len = strlen(buffer);
    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }
    
    return str_new(buffer);
}

BasicString* basic_input_prompt(BasicString* prompt) {
    if (prompt && prompt->length > 0) {
        printf("%s", prompt->data);
        fflush(stdout);
    }
    
    return basic_input_string();
}

int32_t basic_input_int(void) {
    BasicString* str = basic_input_string();
    int32_t result = str_to_int(str);
    str_release(str);
    return result;
}

double basic_input_double(void) {
    BasicString* str = basic_input_string();
    double result = str_to_double(str);
    str_release(str);
    return result;
}

// UTF-32 StringDescriptor input (reads UTF-8 from console, converts to UTF-32)
StringDescriptor* basic_input_line(void) {
    char buffer[4096];
    
    if (fgets(buffer, sizeof(buffer), stdin) == NULL) {
        return string_new_utf8("");
    }
    
    // Remove trailing newline
    size_t len = strlen(buffer);
    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }
    
    return string_new_utf8(buffer);
}

// =============================================================================
// File Operations
// =============================================================================

// Forward declarations for internal functions
extern void _basic_register_file(BasicFile* file);
extern void _basic_unregister_file(BasicFile* file);

BasicFile* file_open(BasicString* filename, BasicString* mode) {
    if (!filename || !mode) {
        basic_error_msg("Invalid file open parameters");
        return NULL;
    }
    
    BasicFile* file = (BasicFile*)malloc(sizeof(BasicFile));
    if (!file) {
        basic_error_msg("Out of memory (file allocation)");
        return NULL;
    }
    
    file->filename = strdup(filename->data);
    file->mode = strdup(mode->data);
    file->file_number = 0;  // Will be set by caller if needed
    file->is_open = false;
    
    // Open the file
    file->fp = fopen(filename->data, mode->data);
    if (!file->fp) {
        free(file->filename);
        free(file->mode);
        free(file);
        
        char err_msg[256];
        snprintf(err_msg, sizeof(err_msg), "Cannot open file: %s", filename->data);
        basic_error_msg(err_msg);
        return NULL;
    }
    
    file->is_open = true;
    _basic_register_file(file);
    
    return file;
}

void file_close(BasicFile* file) {
    if (!file) return;
    
    if (file->is_open && file->fp) {
        fclose(file->fp);
        file->fp = NULL;
        file->is_open = false;
    }
    
    _basic_unregister_file(file);
    
    if (file->filename) {
        free(file->filename);
        file->filename = NULL;
    }
    
    if (file->mode) {
        free(file->mode);
        file->mode = NULL;
    }
    
    free(file);
}

void file_print_string(BasicFile* file, BasicString* str) {
    if (!file || !file->is_open || !file->fp) {
        basic_error_msg("File not open for writing");
        return;
    }
    
    if (!str) return;
    
    fprintf(file->fp, "%s", str->data);
    fflush(file->fp);
}

void file_print_int(BasicFile* file, int32_t value) {
    if (!file || !file->is_open || !file->fp) {
        basic_error_msg("File not open for writing");
        return;
    }
    
    fprintf(file->fp, "%d", value);
    fflush(file->fp);
}

void file_print_newline(BasicFile* file) {
    if (!file || !file->is_open || !file->fp) {
        basic_error_msg("File not open for writing");
        return;
    }
    
    fprintf(file->fp, "\n");
    fflush(file->fp);
}

BasicString* file_read_line(BasicFile* file) {
    if (!file || !file->is_open || !file->fp) {
        basic_error_msg("File not open for reading");
        return str_new("");
    }
    
    char buffer[4096];
    
    if (fgets(buffer, sizeof(buffer), file->fp) == NULL) {
        return str_new("");
    }
    
    // Remove trailing newline
    size_t len = strlen(buffer);
    if (len > 0 && buffer[len - 1] == '\n') {
        buffer[len - 1] = '\0';
    }
    
    return str_new(buffer);
}

bool file_eof(BasicFile* file) {
    if (!file || !file->is_open || !file->fp) {
        return true;
    }
    
    return feof(file->fp) != 0;
}