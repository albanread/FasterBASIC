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
#include <setjmp.h>
#include <signal.h>
#include <unistd.h>
#include <fcntl.h>

// External SAMM function for printing statistics
extern void samm_print_stats_always(void);

// =============================================================================
// Global State
// =============================================================================

// Current line number (for error reporting)
static int32_t g_current_line = 0;

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
// JIT Exit Override
// =============================================================================
//
// In JIT mode the compiled program runs in-process.  If the runtime calls
// exit() (e.g. from basic_error) or QBE calls die_(), it would kill the
// entire fbc process.
//
// We maintain a small stack of jmp_bufs so that nested protected regions
// work correctly (e.g. basic_jit_call wrapping compilation, then
// basic_jit_exec wrapping execution inside the same callback).
//
// basic_exit() longjmps to the most recently armed jmp_buf instead of
// calling real exit().

#define JIT_JMP_STACK_MAX 4

static sigjmp_buf g_jit_jmp_stack[JIT_JMP_STACK_MAX];
static int      g_jit_jmp_depth = 0;
static int      g_jit_exit_code = 0;

void basic_exit(int code) {
    if (g_jit_jmp_depth > 0) {
        g_jit_exit_code = code;
        siglongjmp(g_jit_jmp_stack[g_jit_jmp_depth - 1], 1);
    }
    exit(code);
}

// ── Signal handlers for batch-mode protection ───────────────────────
//
// SIGABRT — QBE uses assert() liberally.  A failed assert calls abort()
//   which raises SIGABRT.  We longjmp back to the setjmp point.  This
//   is safe because the stack is intact (abort just raises a signal).
//
// SIGALRM — per-file execution timeout.  The batch harness calls
//   basic_jit_set_timeout(seconds) before executing each file.  When
//   the alarm fires we longjmp back with exit code 124 (matching the
//   GNU timeout convention).
//
// We do NOT catch SIGSEGV/SIGBUS — longjmp from those is undefined
// behaviour when the stack is corrupted.
//
// Signal installation is decoupled from basic_jit_call so the batch
// harness can keep signals armed across both compilation and execution
// phases.  Call basic_jit_arm_signals() once at the start of a batch
// run and basic_jit_disarm_signals() at the end.

static volatile sig_atomic_t g_signals_active = 0;
static struct sigaction       g_prev_sigabrt;
static struct sigaction       g_prev_sigalrm;

static void
jit_signal_handler(int sig)
{
    if (g_jit_jmp_depth > 0) {
        if (sig == SIGABRT)
            g_jit_exit_code = 134; /* 128 + SIGABRT(6) */
        else if (sig == SIGALRM)
            g_jit_exit_code = 124; /* GNU timeout convention */
        else
            g_jit_exit_code = 128 + sig;
        siglongjmp(g_jit_jmp_stack[g_jit_jmp_depth - 1], 1);
    }
    /* No protection armed — fall back to default behaviour. */
    signal(sig, SIG_DFL);
    raise(sig);
}

// ── Public API: arm/disarm signal handlers ──────────────────────────
//
// The batch harness calls these once around the entire batch loop so
// that SIGABRT and SIGALRM are caught during both QBE compilation
// (inside basic_jit_call) and JIT execution (inside basic_jit_exec).
// Calling them multiple times is safe — they refcount internally.

void basic_jit_arm_signals(void)
{
    if (g_signals_active)
        return;
    struct sigaction sa;
    memset(&sa, 0, sizeof sa);
    sa.sa_handler = jit_signal_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0; /* no SA_RESTART — we want the longjmp */
    sigaction(SIGABRT, &sa, &g_prev_sigabrt);
    sigaction(SIGALRM, &sa, &g_prev_sigalrm);
    g_signals_active = 1;
}

void basic_jit_disarm_signals(void)
{
    if (!g_signals_active)
        return;
    alarm(0); /* cancel any pending timeout */
    sigaction(SIGABRT, &g_prev_sigabrt, NULL);
    sigaction(SIGALRM, &g_prev_sigalrm, NULL);
    g_signals_active = 0;
}

// ── Per-file timeout ────────────────────────────────────────────────
//
// basic_jit_set_timeout(seconds) — arm a SIGALRM that will fire after
//   `seconds` wall-clock seconds.  Pass 0 to disarm.  The signal
//   handler longjmps back with exit code 124.
//
// The alarm is automatically cancelled when basic_jit_call returns
// (normal or longjmp path).

void basic_jit_set_timeout(unsigned int seconds) {
    alarm(seconds);
}

// ── Stdout redirection for batch mode ───────────────────────────────
//
// basic_jit_suppress_stdout()  — redirect fd 1 to /dev/null, return
//                                 the saved fd (or -1 on error).
// basic_jit_restore_stdout(fd) — restore fd 1 from the saved fd.
//
// This keeps JIT program output out of the batch harness report.
// The harness can choose to call these around execution when not in
// verbose mode.

int basic_jit_suppress_stdout(void) {
    fflush(stdout);
    int saved = dup(STDOUT_FILENO);
    if (saved < 0) return -1;
    int devnull = open("/dev/null", O_WRONLY);
    if (devnull < 0) { close(saved); return -1; }
    dup2(devnull, STDOUT_FILENO);
    close(devnull);
    return saved;
}

void basic_jit_restore_stdout(int saved_fd) {
    if (saved_fd < 0) return;
    fflush(stdout);
    dup2(saved_fd, STDOUT_FILENO);
    close(saved_fd);
}

// ── QBE cleanup after aborted compilation ───────────────────────────
// Defined in jit_collect.c (JIT builds) or runtime_shims.c (AOT builds).
// Releases QBE pool memory, closes the fmemopen FILE handle, and resets
// the bridge collector pointer.
extern void qbe_jit_cleanup(void);

// ── basic_jit_call ──────────────────────────────────────────────────
// Generic protected call.  Arms a setjmp, invokes the callback, and
// catches any basic_exit() that fires during the callback (including
// from QBE's die_(), err(), assert failures, runtime errors, etc.).
//
// Returns the callback's return value on success.
// On basic_exit() / abort, returns -(exit_code + 1)  (always negative).
int basic_jit_call(int (*callback)(void *ctx), void *ctx) {
    if (g_jit_jmp_depth >= JIT_JMP_STACK_MAX) {
        fprintf(stderr, "FATAL: JIT jmp_buf stack overflow\n");
        exit(1);
    }

    /* Ensure signal handlers are armed.  If the caller already called
     * basic_jit_arm_signals() this is a no-op. */
    basic_jit_arm_signals();

    int slot = g_jit_jmp_depth++;
    int result;
    if (sigsetjmp(g_jit_jmp_stack[slot], 1) == 0) {
        result = callback(ctx);
    } else {
        /* Arrived here via longjmp from basic_exit(), SIGABRT, or
         * SIGALRM.  Cancel any pending alarm and clean up QBE state. */
        alarm(0);
        qbe_jit_cleanup();
        result = -(g_jit_exit_code + 1);
    }
    g_jit_jmp_depth = slot;  // pop (also handles nested unwind)

    /* NOTE: we intentionally do NOT disarm signals here.  The batch
     * harness keeps them armed across the entire run via
     * basic_jit_arm_signals / basic_jit_disarm_signals.  For single-
     * file mode the signals stay armed harmlessly until process exit. */

    return result;
}

// ── basic_jit_exec ──────────────────────────────────────────────────
// Specialised wrapper for JIT program execution.  Arms a setjmp,
// calls the JIT main(argc, argv), and on basic_exit() cleans up
// runtime state (SAMM, files, timers) so the next program starts fresh.
int basic_jit_exec(void *fn_ptr, int argc, char **argv) {
    extern void samm_shutdown(void);
    extern void samm_force_abandon(void);
    extern void basic_print_force_unlock(void);

    if (g_jit_jmp_depth >= JIT_JMP_STACK_MAX) {
        fprintf(stderr, "FATAL: JIT jmp_buf stack overflow\n");
        exit(1);
    }
    int slot = g_jit_jmp_depth++;
    int result;
    if (sigsetjmp(g_jit_jmp_stack[slot], 1) == 0) {
        typedef int (*main_fn_t)(int, char **);
        result = ((main_fn_t)fn_ptr)(argc, argv);
    } else {
        // Arrived here via longjmp from basic_exit() or SIGALRM.
        result = g_jit_exit_code;
        // The program didn't exit normally — clean up runtime state
        // so the next batch run starts fresh.
        if (g_jit_exit_code == 124) {
            // SIGALRM timeout: any mutex may be held at interrupt time.
            // We cannot call samm_shutdown (it acquires queue_mutex and
            // joins the worker thread, both of which can deadlock).
            // Instead, abandon the entire SAMM state and let the next
            // samm_init() start fresh.  Accept the memory leak.
            basic_print_force_unlock();
            samm_force_abandon();
        } else {
            // Normal basic_exit (runtime error, END statement, etc.)
            // The program was between operations, so mutexes are not
            // held and a regular shutdown is safe.
            samm_shutdown();
        }
        basic_runtime_cleanup();
    }
    g_jit_jmp_depth = slot;  // pop
    return result;
}

// =============================================================================
// Runtime Initialization and Cleanup
// =============================================================================

void basic_runtime_init(void) {
    // Allocate arena for temporary values
    g_arena = (char*)malloc(ARENA_SIZE);
    if (!g_arena) {
        fprintf(stderr, "FATAL: Failed to allocate arena memory\n");
        basic_exit(1);
    }
    g_arena_offset = 0;
    
    // NOTE: RNG initialisation is handled lazily by math_ops.c (basic_rnd,
    // basic_rnd_int) on first use.  Calling srand() here would reset the
    // seed when a program calls RANDOMIZE before its first RND().
    
    // Initialize program start time
    g_program_start_ms = basic_timer_ms();
    
    // Initialize file table
    for (int i = 0; i < MAX_FILES; i++) {
        g_files[i] = NULL;
    }
    
    // Reset line number
    g_current_line = 0;
}

/* ── Forward declarations for message metrics (implemented in messaging.zig) ── */
extern void msg_metrics_report(void);
extern int32_t msg_metrics_check_leaks(void);

void basic_runtime_cleanup(void) {
    // Stop all active timers (AFTER/EVERY) before tearing down queues
    extern void timer_stop_all(void);
    timer_stop_all();

    // Close all open files
    file_close_all();
    
    // Free arena
    if (g_arena) {
        free(g_arena);
        g_arena = NULL;
    }
    g_arena_offset = 0;
    
    // Print memory statistics only if BASIC_MEMORY_STATS environment variable is set
    if (getenv("BASIC_MEMORY_STATS") != NULL) {
        basic_mem_stats();
        samm_print_stats_always();
        msg_metrics_report();
    }

    // Always check for message leaks (prints to stderr only if leaks found)
    msg_metrics_check_leaks();
}

// =============================================================================
// Memory Management - Arena Allocator
// =============================================================================

void* basic_alloc_temp(size_t size) {
    // Align to 8 bytes
    size = (size + 7) & ~7;
    
    if (g_arena_offset + size > ARENA_SIZE) {
        fprintf(stderr, "FATAL: Arena memory exhausted\n");
        basic_exit(1);
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
    basic_exit(1);
}

void basic_error_msg(const char* message) {
    if (g_current_line > 0) {
        fprintf(stderr, "Runtime error at line %d: %s\n", g_current_line, message);
    } else {
        fprintf(stderr, "Runtime error: %s\n", message);
    }
    basic_exit(1);
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
        basic_exit(1);
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
        basic_exit(1);
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
        basic_exit(1);
    }
}

// Wrapper for setjmp - called from generated code
int32_t basic_setjmp(void) {
    ExceptionContext* ctx = (ExceptionContext*)g_exception_stack;
    if (!ctx) {
        fprintf(stderr, "FATAL: basic_setjmp called without exception context\n");
        basic_exit(1);
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
        basic_exit(1);
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
