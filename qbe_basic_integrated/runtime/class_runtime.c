/*
 * class_runtime.c
 * FasterBASIC CLASS & Object System Runtime
 *
 * Runtime support functions for heap-allocated CLASS instances:
 *   - class_object_new()          Allocate + install vtable + class_id
 *   - class_object_delete()       Destructor call + free + nullify
 *   - class_is_instance()         IS type-check (walks inheritance chain)
 *   - class_null_method_error()   Runtime error: method call on NOTHING
 *   - class_null_field_error()    Runtime error: field access on NOTHING
 *   - class_object_debug()        Debug: print object info
 *
 * Object Memory Layout (every instance):
 *   Offset  Size  Content
 *   ------  ----  ---------------------------
 *   0       8     vtable pointer
 *   8       8     class_id (int64)
 *   16      ...   fields (inherited first, then own)
 *
 * VTable Layout (one per class, statically allocated in data section):
 *   Offset  Size  Content
 *   ------  ----  ---------------------------
 *   0       8     class_id (int64)
 *   8       8     parent_vtable pointer (NULL for root)
 *   16      8     class_name pointer (C string)
 *   24      8     destructor pointer (NULL if none)
 *   32+     8*N   method pointers (declaration order, parent slots first)
 *
 * Memory Management:
 *   All object allocation and deallocation is routed through SAMM
 *   (Scope Aware Memory Management) when enabled. SAMM provides:
 *     - Scope-based automatic cleanup (objects freed on scope exit)
 *     - Bloom-filter double-free detection
 *     - Background cleanup worker thread
 *     - Allocation tracking and diagnostics
 *
 *   When SAMM is not enabled/initialised, allocation falls through to
 *   raw calloc/free (backward compatible).
 */

#include "class_runtime.h"
#include "samm_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <inttypes.h>

/* ========================================================================= */
/* Object Allocation                                                          */
/* ========================================================================= */

void* class_object_new(int64_t object_size, void* vtable, int64_t class_id) {
    if (object_size < CLASS_HEADER_SIZE) {
        fprintf(stderr,
                "INTERNAL ERROR: class_object_new called with object_size=%"
                PRId64 " (minimum is %d)\n",
                object_size, CLASS_HEADER_SIZE);
        exit(1);
    }

    /* Allocate through SAMM if available, otherwise raw calloc.
     * samm_alloc_object returns zeroed memory (calloc semantics) so all
     * fields start at their default values: integers = 0, string
     * descriptors = NULL, object references = NOTHING (0). */
    void* obj;
    if (samm_is_enabled()) {
        obj = samm_alloc_object((size_t)object_size);
    } else {
        obj = calloc(1, (size_t)object_size);
    }

    if (!obj) {
        fprintf(stderr,
                "ERROR: Out of memory allocating object (%" PRId64 " bytes)\n",
                object_size);
        exit(1);
    }

    /* Install vtable pointer at obj[0] */
    ((void**)obj)[0] = vtable;

    /* Install class_id at obj[1] (offset 8) */
    ((int64_t*)obj)[1] = class_id;

    /* Track in current SAMM scope so it gets auto-cleaned on scope exit.
     * Must be done AFTER installing vtable+class_id so that the background
     * cleanup worker can call the destructor via vtable[3]. */
    if (samm_is_enabled()) {
        samm_track_object(obj);
    }

    return obj;
}

/* ========================================================================= */
/* Object Deallocation                                                        */
/* ========================================================================= */

void class_object_delete(void** obj_ref) {
    if (!obj_ref) return;

    void* obj = *obj_ref;
    if (!obj) return;   /* DELETE on NOTHING is a no-op */

    /* Double-free detection via SAMM Bloom filter.
     * If the Bloom filter says this pointer was probably already freed,
     * we skip the free to prevent heap corruption. */
    if (samm_is_enabled() && samm_is_probably_freed(obj)) {
        fprintf(stderr,
                "WARNING: Possible double-free on object at %p "
                "(DELETE on already-freed object)\n", obj);
        *obj_ref = NULL;
        return;
    }

    /* Load vtable pointer from obj[0] */
    void** vtable = (void**)((void**)obj)[0];

    if (vtable) {
        /* Load destructor pointer from vtable[3] (offset 24) */
        void* dtor_ptr = ((void**)vtable)[3];

        if (dtor_ptr) {
            /* Call destructor: void dtor(void* me) */
            typedef void (*dtor_fn)(void*);
            ((dtor_fn)dtor_ptr)(obj);
        }
    }

    /* Free the object memory through SAMM or raw free.
     * samm_free_object also:
     *   - Untracks the pointer from the current scope (prevents
     *     double-free on scope exit)
     *   - Adds the pointer to the Bloom filter for future
     *     double-free detection */
    if (samm_is_enabled()) {
        samm_free_object(obj);
    } else {
        free(obj);
    }

    /* Set the caller's variable to NOTHING (null) */
    *obj_ref = NULL;
}

/* ========================================================================= */
/* IS Type Check                                                              */
/* ========================================================================= */

int32_t class_is_instance(void* obj, int64_t target_class_id) {
    if (!obj) return 0;  /* NOTHING IS Anything → false */

    /* Fast path: check the object's own class_id (stored at offset 8) */
    int64_t obj_class_id = ((int64_t*)obj)[1];
    if (obj_class_id == target_class_id) return 1;

    /* Slow path: walk the parent chain via vtable parent pointers.
     *
     * VTable layout reminder:
     *   [0] class_id       (int64)
     *   [1] parent_vtable  (pointer, NULL for root)
     *   [2] class_name     (pointer)
     *   [3] destructor     (pointer)
     *   [4+] methods...
     */
    void** vtable = (void**)((void**)obj)[0];

    /* Move to parent — we already checked the object's own class above,
       and vtable[0] has the same class_id as obj, so skip to parent. */
    if (vtable) {
        vtable = (void**)vtable[1];  /* parent_vtable */
    }

    while (vtable) {
        int64_t vt_class_id = ((int64_t*)vtable)[0];
        if (vt_class_id == target_class_id) return 1;
        vtable = (void**)vtable[1];  /* walk to parent_vtable */
    }

    return 0;
}

/* ========================================================================= */
/* Null-Reference Error Handlers                                              */
/* ========================================================================= */

void class_null_method_error(const char* location, const char* method_name) {
    if (!location) location = "unknown";
    if (!method_name) method_name = "unknown";

    fprintf(stderr,
            "ERROR: Method call on NOTHING reference at %s (method: %s)\n",
            location, method_name);
    exit(1);
}

void class_null_field_error(const char* location, const char* field_name) {
    if (!location) location = "unknown";
    if (!field_name) field_name = "unknown";

    fprintf(stderr,
            "ERROR: Field access on NOTHING reference at %s (field: %s)\n",
            location, field_name);
    exit(1);
}

/* ========================================================================= */
/* Debug Utilities                                                            */
/* ========================================================================= */

void class_object_debug(void* obj) {
    if (!obj) {
        fprintf(stderr, "[NOTHING]\n");
        return;
    }

    /* Load vtable */
    void** vtable = (void**)((void**)obj)[0];
    int64_t class_id = ((int64_t*)obj)[1];

    const char* class_name = "(unknown)";
    if (vtable) {
        const char* name_ptr = (const char*)vtable[2];  /* vtable[2] = class_name */
        if (name_ptr) {
            class_name = name_ptr;
        }
    }

    fprintf(stderr, "[%s@%p id=%" PRId64 "]\n", class_name, obj, class_id);
}