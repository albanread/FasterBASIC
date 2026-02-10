/**
 * worker_runtime.c — FasterBASIC WORKER concurrency runtime
 *
 * Implements the Web Workers–inspired threading model:
 * - Workers are isolated functions that run on background threads
 * - Arguments are copied in (no shared state)
 * - Results are returned via a FUTURE handle
 * - Uses pthreads for cross-platform threading
 *
 * Thread safety is achieved through isolation, not locks.
 * The only synchronization is a single mutex+condvar per FUTURE,
 * used to signal completion.
 */

#include <pthread.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "array_descriptor.h"

/* ── Argument block ────────────────────────────────────────────────── */

/**
 * An argument block holds packed arguments for a worker.
 * Each argument is stored as a 64-bit value (double, int extended,
 * or pointer).
 */
typedef struct {
    int32_t num_args;
    double  values[16];   /* max 16 arguments — more than enough */
} WorkerArgs;

WorkerArgs *worker_args_alloc(int32_t num_args) {
    WorkerArgs *args = (WorkerArgs *)calloc(1, sizeof(WorkerArgs));
    if (args) args->num_args = num_args;
    return args;
}

void worker_args_set_double(WorkerArgs *args, int32_t index, double value) {
    if (args && index >= 0 && index < 16) {
        args->values[index] = value;
    }
}

void worker_args_set_int(WorkerArgs *args, int32_t index, int32_t value) {
    if (args && index >= 0 && index < 16) {
        /* Store int as double for uniform 64-bit storage */
        args->values[index] = (double)value;
    }
}

void worker_args_set_ptr(WorkerArgs *args, int32_t index, void *value) {
    if (args && index >= 0 && index < 16) {
        /* Store pointer bits as double — recovered via memcpy */
        double d;
        memcpy(&d, &value, sizeof(d));
        args->values[index] = d;
    }
}

/* ── Future handle ─────────────────────────────────────────────────── */

/**
 * A FutureHandle represents a running or completed worker.
 * It owns the thread, the argument block, and the result.
 */
typedef struct {
    pthread_t       thread;
    pthread_mutex_t mutex;
    pthread_cond_t  cond;
    int             done;       /* 0 = running, 1 = completed */
    double          result;     /* result stored as double (64 bits) */
    int32_t         ret_type;   /* 0=double, 1=int, 2=ptr */

    /* Worker function and arguments */
    void           *func_ptr;
    WorkerArgs     *args;
    int32_t         num_args;
} FutureHandle;

/* ── Thread entry point ────────────────────────────────────────────── */

/**
 * Generic worker thread function.
 *
 * The compiled worker function is a normal QBE function with typed
 * parameters.  We call it via a function pointer, passing arguments
 * from the packed args block.
 *
 * Since QBE compiles functions with standard C calling conventions,
 * we can call them with up to 8 double arguments directly.  For
 * simplicity and safety, we support up to 8 double args.
 */
static void *worker_thread_entry(void *ctx) {
    FutureHandle *fh = (FutureHandle *)ctx;

    /* Cast the function pointer based on argument count.
     * QBE functions use the platform ABI, so we can call them
     * with the right number of double arguments.
     * Workers always return double (the codegen converts to/from). */
    double result = 0.0;
    double *v = fh->args->values;

    switch (fh->num_args) {
        case 0: {
            typedef double (*fn0_t)(void);
            result = ((fn0_t)fh->func_ptr)();
            break;
        }
        case 1: {
            typedef double (*fn1_t)(double);
            result = ((fn1_t)fh->func_ptr)(v[0]);
            break;
        }
        case 2: {
            typedef double (*fn2_t)(double, double);
            result = ((fn2_t)fh->func_ptr)(v[0], v[1]);
            break;
        }
        case 3: {
            typedef double (*fn3_t)(double, double, double);
            result = ((fn3_t)fh->func_ptr)(v[0], v[1], v[2]);
            break;
        }
        case 4: {
            typedef double (*fn4_t)(double, double, double, double);
            result = ((fn4_t)fh->func_ptr)(v[0], v[1], v[2], v[3]);
            break;
        }
        case 5: {
            typedef double (*fn5_t)(double, double, double, double, double);
            result = ((fn5_t)fh->func_ptr)(v[0], v[1], v[2], v[3], v[4]);
            break;
        }
        case 6: {
            typedef double (*fn6_t)(double, double, double, double, double, double);
            result = ((fn6_t)fh->func_ptr)(v[0], v[1], v[2], v[3], v[4], v[5]);
            break;
        }
        case 7: {
            typedef double (*fn7_t)(double, double, double, double, double, double, double);
            result = ((fn7_t)fh->func_ptr)(v[0], v[1], v[2], v[3], v[4], v[5], v[6]);
            break;
        }
        case 8: {
            typedef double (*fn8_t)(double, double, double, double, double, double, double, double);
            result = ((fn8_t)fh->func_ptr)(v[0], v[1], v[2], v[3], v[4], v[5], v[6], v[7]);
            break;
        }
        default:
            /* Unsupported argument count — return 0 */
            break;
    }

    /* Signal completion */
    pthread_mutex_lock(&fh->mutex);
    fh->result = result;
    fh->done = 1;
    pthread_cond_signal(&fh->cond);
    pthread_mutex_unlock(&fh->mutex);

    return NULL;
}

/* ── Public API ────────────────────────────────────────────────────── */

/**
 * Spawn a worker on a new thread.
 *
 * @param func_ptr  Pointer to the compiled worker function
 * @param args      Packed argument block (ownership transferred)
 * @param num_args  Number of arguments
 * @param ret_type  Return type code (0=double, 1=int, 2=ptr)
 * @return          Opaque future handle (pointer)
 */
FutureHandle *worker_spawn(void *func_ptr, WorkerArgs *args,
                           int32_t num_args, int32_t ret_type) {
    FutureHandle *fh = (FutureHandle *)calloc(1, sizeof(FutureHandle));
    if (!fh) return NULL;

    fh->func_ptr = func_ptr;
    fh->args     = args;
    fh->num_args = num_args;
    fh->ret_type = ret_type;
    fh->done     = 0;
    fh->result   = 0.0;

    pthread_mutex_init(&fh->mutex, NULL);
    pthread_cond_init(&fh->cond, NULL);

    pthread_create(&fh->thread, NULL, worker_thread_entry, fh);

    return fh;
}

/**
 * Wait for a worker to complete and return its result.
 * After this call, the future handle is destroyed and must not be reused.
 *
 * @param handle  Future handle from worker_spawn
 * @return        The worker's return value (as double)
 */
double worker_await(FutureHandle *handle) {
    if (!handle) return 0.0;

    pthread_mutex_lock(&handle->mutex);
    while (!handle->done) {
        pthread_cond_wait(&handle->cond, &handle->mutex);
    }
    pthread_mutex_unlock(&handle->mutex);

    double result = handle->result;

    /* Clean up */
    pthread_join(handle->thread, NULL);
    pthread_mutex_destroy(&handle->mutex);
    pthread_cond_destroy(&handle->cond);
    if (handle->args) free(handle->args);
    free(handle);

    return result;
}

/**
 * Check if a worker has completed (non-blocking).
 *
 * @param handle  Future handle from worker_spawn
 * @return        1 if done, 0 if still running
 */
int32_t worker_ready(FutureHandle *handle) {
    if (!handle) return 1;

    pthread_mutex_lock(&handle->mutex);
    int done = handle->done;
    pthread_mutex_unlock(&handle->mutex);

    return done ? 1 : 0;
}

/* ── MARSHALL / UNMARSHALL ─────────────────────────────────────────── */
/* Marshalling is now implemented in marshalling.zig.                   */
/* The Zig runtime exports: marshall_udt, unmarshall_udt,              */
/*   marshall_udt_deep, unmarshall_udt_deep,                           */
/*   marshall_array, unmarshall_array                                   */
