/*
 * fbc_bridge.c
 * FasterBASIC Compiler - Runtime Bridge
 *
 * Provides non-inline wrapper functions for ArrayDescriptor operations
 * that the QBE-generated code calls.  The underlying implementations
 * live as static-inline helpers in array_descriptor.h; QBE IL cannot
 * call inline functions directly, so we expose thin wrappers here.
 *
 * Also provides any other small bridging symbols that the codegen
 * emits but that don't have a dedicated non-inline implementation
 * in the rest of the runtime.
 */

#include <stdint.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>

#include "array_descriptor.h"

/* ========================================================================= */
/* fbc_array_create                                                           */
/*                                                                            */
/* Called by codegen as:                                                       */
/*   call $fbc_array_create(w ndims, l desc_ptr, w upper_bound, w elem_size)  */
/*                                                                            */
/* Initialises a 1-D ArrayDescriptor that has already been allocated           */
/* (typically as a global or stack variable).  Lower bound defaults to 0.      */
/* ========================================================================= */
void fbc_array_create(int32_t ndims,
                      ArrayDescriptor *desc,
                      int32_t upper_bound,
                      int32_t elem_size)
{
    if (!desc) {
        fprintf(stderr, "ERROR: fbc_array_create called with NULL descriptor\n");
        exit(1);
    }

    /* Zero the descriptor first so any leftover state is cleared. */
    memset(desc, 0, sizeof(ArrayDescriptor));

    int rc;
    if (ndims <= 1) {
        rc = array_descriptor_init(desc,
                                   0,                     /* lowerBound  */
                                   (int64_t)upper_bound,  /* upperBound  */
                                   (int64_t)elem_size,    /* elementSize */
                                   0,                     /* base (OPTION BASE 0) */
                                   0);                    /* typeSuffix (unknown)  */
    } else {
        /* 2-D not yet emitted by codegen — fall back to 1-D for safety. */
        rc = array_descriptor_init(desc,
                                   0,
                                   (int64_t)upper_bound,
                                   (int64_t)elem_size,
                                   0,
                                   0);
    }

    if (rc != 0) {
        fprintf(stderr, "ERROR: fbc_array_create failed (upper=%d, elem_size=%d)\n",
                upper_bound, elem_size);
        exit(1);
    }
}

/* ========================================================================= */
/* fbc_array_bounds_check                                                     */
/*                                                                            */
/* Called by codegen as:                                                       */
/*   call $fbc_array_bounds_check(l desc_ptr, w index)                        */
/*                                                                            */
/* Aborts with an error message if the index is out of range.                 */
/* ========================================================================= */
void fbc_array_bounds_check(ArrayDescriptor *desc, int32_t index)
{
    if (!desc) {
        fprintf(stderr, "ERROR: array bounds check on NULL descriptor\n");
        exit(1);
    }

    if (!desc->data) {
        fprintf(stderr, "ERROR: array not initialised (DIM not executed?)\n");
        exit(1);
    }

    int ok = array_descriptor_check_bounds(desc, (int64_t)index);
    if (!ok) {
        fprintf(stderr, "ERROR: array index %d out of bounds [%lld..%lld]\n",
                index,
                (long long)desc->lowerBound1,
                (long long)desc->upperBound1);
        exit(1);
    }
}

/* ========================================================================= */
/* fbc_array_element_addr                                                     */
/*                                                                            */
/* Called by codegen as:                                                       */
/*   %addr =l call $fbc_array_element_addr(l desc_ptr, w index)               */
/*                                                                            */
/* Returns a pointer to the element at the given index.  The caller is        */
/* expected to have already performed a bounds check.                          */
/* ========================================================================= */
void *fbc_array_element_addr(ArrayDescriptor *desc, int32_t index)
{
    return array_descriptor_get_element_ptr(desc, (int64_t)index);
}

/* ========================================================================= */
/* fbc_array_redim                                                            */
/*                                                                            */
/* REDIM support — reallocate array to new upper bound (loses old data).      */
/* ========================================================================= */
void fbc_array_redim(ArrayDescriptor *desc, int32_t new_upper)
{
    if (!desc) {
        fprintf(stderr, "ERROR: fbc_array_redim called with NULL descriptor\n");
        exit(1);
    }

    int rc = array_descriptor_redim(desc, 0, (int64_t)new_upper);
    if (rc != 0) {
        fprintf(stderr, "ERROR: fbc_array_redim failed (new_upper=%d)\n", new_upper);
        exit(1);
    }
}

/* ========================================================================= */
/* fbc_array_redim_preserve                                                   */
/*                                                                            */
/* REDIM PRESERVE — resize array keeping existing data.                       */
/* ========================================================================= */
void fbc_array_redim_preserve(ArrayDescriptor *desc, int32_t new_upper)
{
    if (!desc) {
        fprintf(stderr, "ERROR: fbc_array_redim_preserve called with NULL descriptor\n");
        exit(1);
    }

    int rc = array_descriptor_redim_preserve(desc, 0, (int64_t)new_upper);
    if (rc != 0) {
        fprintf(stderr, "ERROR: fbc_array_redim_preserve failed (new_upper=%d)\n", new_upper);
        exit(1);
    }
}

/* ========================================================================= */
/* fbc_array_erase                                                            */
/*                                                                            */
/* ERASE — free array data and reset descriptor.                              */
/* ========================================================================= */
void fbc_array_erase(ArrayDescriptor *desc)
{
    if (desc) {
        array_descriptor_erase(desc);
    }
}

/* ========================================================================= */
/* fbc_array_lbound / fbc_array_ubound                                        */
/*                                                                            */
/* Return the lower / upper bound of dimension 1.                             */
/* ========================================================================= */
int32_t fbc_array_lbound(ArrayDescriptor *desc)
{
    if (!desc) return 0;
    return (int32_t)desc->lowerBound1;
}

int32_t fbc_array_ubound(ArrayDescriptor *desc)
{
    if (!desc) return -1;
    return (int32_t)desc->upperBound1;
}