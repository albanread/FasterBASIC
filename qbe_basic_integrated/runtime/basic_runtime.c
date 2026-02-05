//
// basic_runtime.c
// FasterBASIC QBE Runtime Library - Core Implementation
//
// NOTE: This is part of the C runtime library (runtime_c/) that gets linked with
//       COMPILED BASIC programs, not the C++ compiler runtime (runtime/).
//
// This file contains runtime initialization, cleanup, and core utilities.
//

#include "basic_runtime.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

// =============================================================================
// Global State
// =============================================================================

// Current line number (for error reporting)
static int32_t g_current_line = 0;

// Random number generator state
static bool g_rnd_initialized = false;

// Arena allocator for temporary values
#define ARENA_SIZE (1024 * 1024)  // 1 MB
static char* g_arena = NULL;
static size_t g_arena_offset = 0;

// DATA statement support
static const char** g_data_values = NULL;
static int32_t g_data_count = 0;
static int32_t g_data_index = 0;

// File table (for file operations)
#define MAX_FILES 256
static BasicFile* g_files[MAX_FILES] = {NULL};

// Program start time (for TIMER function)
static int64_t g_program_start_ms = 0;

// Exception handling state
static ExceptionContext* volatile g_exception_stack = NULL;
static int32_t g_last_error = 0;
static int32_t g_last_error_line = 0;

// =============================================================================
// Runtime Initialization and Cleanup
// =============================================================================

void basic_runtime_init(void) {
    // Allocate arena for temporary values
    g_arena = (char*)malloc(ARENA_SIZE);
    if (!g_arena) {
        fprintf(stderr, "FATAL: Failed to allocate arena memory\n");
        exit(1);
    }
    g_arena_offset = 0;
    
    // Initialize random number generator
    if (!g_rnd_initialized) {
        srand((unsigned int)time(NULL));
        g_rnd_initialized = true;
    }
    
    // Initialize program start time
    g_program_start_ms = basic_timer_ms();
    
    // Initialize file table
    for (int i = 0; i < MAX_FILES; i++) {
        g_files[i] = NULL;
    }
    
    // Reset line number
    g_current_line = 0;
}

void basic_runtime_cleanup(void) {
    // Close all open files
    file_close_all();
    
    // Free arena
    if (g_arena) {
        free(g_arena);
        g_arena = NULL;
    }
    g_arena_offset = 0;
}

// =============================================================================
// Memory Management - Arena Allocator
// =============================================================================

void* basic_alloc_temp(size_t size) {
    // Align to 8 bytes
    size = (size + 7) & ~7;
    
    if (g_arena_offset + size > ARENA_SIZE) {
        fprintf(stderr, "FATAL: Arena memory exhausted\n");
        exit(1);
    }
    
    void* ptr = g_arena + g_arena_offset;
    g_arena_offset += size;
    return ptr;
}

void basic_clear_temps(void) {
    g_arena_offset = 0;
}

// =============================================================================
// Error Handling
// =============================================================================

void basic_error(int32_t line_number, const char* message) {
    fprintf(stderr, "Runtime error at line %d: %s\n", line_number, message);
    exit(1);
}

void basic_error_msg(const char* message) {
    if (g_current_line > 0) {
        fprintf(stderr, "Runtime error at line %d: %s\n", g_current_line, message);
    } else {
        fprintf(stderr, "Runtime error: %s\n", message);
    }
    exit(1);
}

void basic_set_line(int32_t line_number) {
    g_current_line = line_number;
}

int32_t basic_get_line(void) {
    return g_current_line;
}

void basic_array_bounds_error(int64_t index, int64_t lower, int64_t upper) {
    basic_throw(ERR_SUBSCRIPT);
}

// =============================================================================
// DATA/READ/RESTORE Support
// =============================================================================

void basic_data_init(const char** data_values, int32_t count) {
    g_data_values = data_values;
    g_data_count = count;
    g_data_index = 0;
}

BasicString* basic_read_data_string(void) {
    if (g_data_index >= g_data_count) {
        basic_error_msg("OUT OF DATA");
        return NULL;
    }
    
    BasicString* result = str_new(g_data_values[g_data_index]);
    g_data_index++;
    return result;
}

int32_t basic_read_data_int(void) {
    if (g_data_index >= g_data_count) {
        basic_error_msg("OUT OF DATA");
        return 0;
    }
    
    int32_t result = atoi(g_data_values[g_data_index]);
    g_data_index++;
    return result;
}

double basic_read_data_double(void) {
    if (g_data_index >= g_data_count) {
        basic_error_msg("OUT OF DATA");
        return 0.0;
    }
    
    double result = atof(g_data_values[g_data_index]);
    g_data_index++;
    return result;
}

void basic_restore_data(void) {
    g_data_index = 0;
}

// =============================================================================
// Timer Support
// =============================================================================

#include <sys/time.h>

int64_t basic_timer_ms(void) {
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (int64_t)tv.tv_sec * 1000 + (int64_t)tv.tv_usec / 1000;
}

// Get seconds since program start (BASIC TIMER function)
double basic_timer(void) {
    int64_t current_ms = basic_timer_ms();
    return (double)(current_ms - g_program_start_ms) / 1000.0;
}

void basic_sleep_ms(int32_t milliseconds) {
    if (milliseconds <= 0) return;
    
    struct timespec ts;
    ts.tv_sec = milliseconds / 1000;
    ts.tv_nsec = (milliseconds % 1000) * 1000000;
    nanosleep(&ts, NULL);
}

// =============================================================================
// File Management Utilities
// =============================================================================

void file_close_all(void) {
    for (int i = 0; i < MAX_FILES; i++) {
        if (g_files[i]) {
            file_close(g_files[i]);
        }
    }
}

// Internal: Register file in global table
void _basic_register_file(BasicFile* file) {
    if (!file) return;
    
    for (int i = 0; i < MAX_FILES; i++) {
        if (!g_files[i]) {
            g_files[i] = file;
            return;
        }
    }
    
    basic_error_msg("Too many open files");
}

// Internal: Unregister file from global table
void _basic_unregister_file(BasicFile* file) {
    if (!file) return;
    
    for (int i = 0; i < MAX_FILES; i++) {
        if (g_files[i] == file) {
            g_files[i] = NULL;
            return;
        }
    }
}
void basic_array_bounds_error_2d(int64_t index1, int64_t lower1, int64_t upper1,
                                  int64_t index2, int64_t lower2, int64_t upper2) {
    char msg[256];
    snprintf(msg, sizeof(msg),
             "Array subscript out of bounds: indices [%lld, %lld] not in [%lld:%lld, %lld:%lld]",
             (long long)index1, (long long)index2,
             (long long)lower1, (long long)upper1,
             (long long)lower2, (long long)upper2);
    basic_error_msg(msg);
}

void basic_error_multidim_arrays() {
    basic_error_msg("Multi-dimensional arrays (>2D) not yet supported");
}

void fb_error_out_of_data() {
    basic_error_msg("Out of DATA");
}

// RESTORE statement support
// These functions are called from generated code which handles the actual pointer updates
// The generated code loads $__data_start, calls this to validate, then stores to $__data_pointer
// So these are currently no-ops - the actual work is done inline in the generated QBE code
void fb_restore() {
    // No-op: generated code handles pointer reset inline
}

void fb_restore_to_label(char* label_pos) {
    // No-op: generated code handles pointer update inline
}

void fb_restore_to_line(char* line_pos) {
    // No-op: generated code handles pointer update inline
}

// =============================================================================
// Exception Handling Implementation
// =============================================================================

// Push new exception context onto stack
ExceptionContext* basic_exception_push(int32_t has_finally) {
    ExceptionContext* ctx = (ExceptionContext*)malloc(sizeof(ExceptionContext));
    if (!ctx) {
        fprintf(stderr, "FATAL: Failed to allocate exception context\n");
        exit(1);
    }
    
    ctx->prev = (ExceptionContext*)g_exception_stack;
    ctx->has_finally = has_finally;
    ctx->error_code = 0;
    ctx->error_line = 0;
    
    g_exception_stack = ctx;
    return ctx;
}

// Pop exception context from stack
void basic_exception_pop(void) {
    if (g_exception_stack) {
        ExceptionContext* ctx = g_exception_stack;
        g_exception_stack = ctx->prev;
        free(ctx);
    }
}

// Throw exception with error code
void basic_throw(int32_t error_code) {
    ExceptionContext* ctx = (ExceptionContext*)g_exception_stack;
    if (ctx) {
        // We have a handler - save error info and longjmp
        ctx->error_code = error_code;
        ctx->error_line = g_current_line;
        g_last_error = error_code;
        g_last_error_line = g_current_line;
        
        longjmp(ctx->jump_buffer, 1);
        // Never returns
    } else {
        // No handler - fatal error with descriptive message
        const char* error_msg = "Unknown error";
        switch (error_code) {
            case ERR_ILLEGAL_CALL:    error_msg = "Illegal function call"; break;
            case ERR_OVERFLOW:        error_msg = "Overflow"; break;
            case ERR_SUBSCRIPT:       error_msg = "Subscript out of range"; break;
            case ERR_DIV_ZERO:        error_msg = "Division by zero"; break;
            case ERR_TYPE_MISMATCH:   error_msg = "Type mismatch"; break;
            case ERR_BAD_FILE:        error_msg = "Bad file number"; break;
            case ERR_FILE_NOT_FOUND:  error_msg = "File not found"; break;
            case ERR_DISK_FULL:       error_msg = "Disk full"; break;
            case ERR_INPUT_PAST_END:  error_msg = "Input past end"; break;
            case ERR_DISK_NOT_READY:  error_msg = "Disk not ready"; break;
        }
        
        fprintf(stderr, "Unhandled exception at line %d: %s (error code %d)\n",
                g_current_line, error_msg, error_code);
        exit(1);
    }
}

// Get current error code (ERR function)
int32_t basic_err(void) {
    return g_last_error;
}

// Get error line number (ERL function)
int32_t basic_erl(void) {
    return g_last_error_line;
}

// Re-throw current exception (for unmatched CATCH clauses)
void basic_rethrow(void) {
    // Pop current exception context and re-throw to outer handler
    ExceptionContext* ctx = (ExceptionContext*)g_exception_stack;
    if (ctx) {
        int32_t error_code = ctx->error_code;
        basic_exception_pop();
        basic_throw(error_code);
        // Never returns
    } else {
        // No exception context - this shouldn't happen
        fprintf(stderr, "FATAL: basic_rethrow called with no active exception\n");
        exit(1);
    }
}

// Wrapper for setjmp - called from generated code
int32_t basic_setjmp(void) {
    ExceptionContext* ctx = (ExceptionContext*)g_exception_stack;
    if (!ctx) {
        fprintf(stderr, "FATAL: basic_setjmp called without exception context\n");
        exit(1);
    }
    
    return setjmp(ctx->jump_buffer);
}

// =============================================================================
// GLOBAL Variables Support
// =============================================================================

// Global variable vector
static int64_t* g_global_vector = NULL;
static size_t g_global_vector_size = 0;

// Initialize global variable vector with specified number of slots
void basic_global_init(int64_t count) {
    if (count <= 0) {
        g_global_vector = NULL;
        g_global_vector_size = 0;
        return;
    }
    
    // Allocate vector and zero-initialize all slots
    g_global_vector_size = (size_t)count;
    g_global_vector = (int64_t*)calloc(g_global_vector_size, sizeof(int64_t));
    
    if (!g_global_vector) {
        fprintf(stderr, "FATAL: Failed to allocate global variable vector (%lld slots)\n", 
                (long long)count);
        exit(1);
    }
}

// Get base pointer to global variable vector
int64_t* basic_global_base(void) {
    return g_global_vector;
}

// Clean up global variable vector
void basic_global_cleanup(void) {
    if (g_global_vector) {
        free(g_global_vector);
        g_global_vector = NULL;
    }
    g_global_vector_size = 0;
}
