/*
 * list_ops.h
 * FasterBASIC Runtime — Linked List Operations
 *
 * Implements singly-linked heterogeneous and typed lists for FasterBASIC.
 * Follows the same design as NBCPL lists: a ListHeader "handle" that the
 * BASIC variable points to, plus a chain of type-tagged ListAtom nodes.
 *
 * Memory layout:
 *   ListHeader (32 bytes) — container metadata, head/tail pointers
 *   ListAtom   (24 bytes) — type tag, value union, next pointer
 *
 * The type tag on each atom allows heterogeneous LIST OF ANY collections
 * while typed lists (LIST OF INTEGER, etc.) always set the same tag.
 *
 * SAMM integration:
 *   - list_create() tracks the header as SAMM_ALLOC_LIST
 *   - Each atom is tracked as SAMM_ALLOC_LIST_ATOM
 *   - String atoms call string_retain() on append, string_release() on free
 *   - Nested list atoms are recursively freed via list_free()
 *
 * Build:
 *   cc -std=c99 -O2 -c list_ops.c -o list_ops.o
 */

#ifndef LIST_OPS_H
#define LIST_OPS_H

#include <stdint.h>
#include <stddef.h>
#include "string_descriptor.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Atom Type Tags                                                             */
/* ========================================================================= */

#define ATOM_SENTINEL     0    /* ListHeader marker — never used on atoms    */
#define ATOM_INT          1    /* int64_t                                    */
#define ATOM_FLOAT        2    /* double (IEEE 754)                          */
#define ATOM_STRING       3    /* StringDescriptor*                          */
#define ATOM_LIST         4    /* Nested ListHeader*                         */
#define ATOM_OBJECT       5    /* Generic object pointer                     */

/* ========================================================================= */
/* ListHeader Flags                                                           */
/* ========================================================================= */

#define LIST_FLAG_ELEM_ANY     0x0000
#define LIST_FLAG_ELEM_INT     0x0100
#define LIST_FLAG_ELEM_FLOAT   0x0200
#define LIST_FLAG_ELEM_STRING  0x0300
#define LIST_FLAG_ELEM_LIST    0x0400
#define LIST_FLAG_ELEM_OBJECT  0x0500
#define LIST_FLAG_ELEM_MASK    0x0F00
#define LIST_FLAG_IMMUTABLE    0x0001

/* ========================================================================= */
/* ListAtom — 24 bytes per element                                            */
/* ========================================================================= */
/*
 * Memory layout:
 *   Offset  0: type       (i32) — ATOM_INT, ATOM_FLOAT, ATOM_STRING, etc.
 *   Offset  4: pad        (i32) — alignment padding
 *   Offset  8: value      (i64) — union: int64_t / double / void*
 *   Offset 16: next       (ptr) — next atom in chain (NULL = last)
 */

typedef struct ListAtom {
    int32_t  type;          /* ATOM_INT, ATOM_FLOAT, ATOM_STRING, etc.      */
    int32_t  pad;           /* Alignment padding                            */
    union {
        int64_t  int_value;     /* Integer value                            */
        double   float_value;   /* Double value (IEEE 754)                  */
        void*    ptr_value;     /* String descriptor, nested list, object   */
    } value;
    struct ListAtom* next;  /* Next atom in chain (NULL = last element)     */
} ListAtom;

/* ========================================================================= */
/* ListHeader — 32 bytes, the "handle" that BASIC variables point to          */
/* ========================================================================= */
/*
 * Memory layout:
 *   Offset  0: type       (i32) — Always ATOM_SENTINEL (0)
 *   Offset  4: flags      (i32) — Element type hint, immutability, etc.
 *   Offset  8: length     (i64) — Number of elements (maintained on add/remove)
 *   Offset 16: head       (ptr) — First element (NULL if empty)
 *   Offset 24: tail       (ptr) — Last element  (NULL if empty)
 *
 * Key invariant: type == ATOM_SENTINEL (0) distinguishes a header from an
 * atom in memory. Any runtime function receiving a void* can check this.
 */

typedef struct ListHeader {
    int32_t  type;          /* Always ATOM_SENTINEL (0)                     */
    int32_t  flags;         /* LIST_FLAG_* — element type hint, etc.        */
    int64_t  length;        /* Number of elements — O(1) access             */
    ListAtom* head;         /* First element (NULL if empty)                */
    ListAtom* tail;         /* Last element  (NULL if empty)                */
} ListHeader;

/* ========================================================================= */
/* Creation & Destruction                                                     */
/* ========================================================================= */

/**
 * Create a new empty list (LIST OF ANY).
 * The header is SAMM-tracked as SAMM_ALLOC_LIST.
 */
ListHeader* list_create(void);

/**
 * Create a new empty list with an element type hint in flags.
 * elem_type_flag should be one of LIST_FLAG_ELEM_*.
 */
ListHeader* list_create_typed(int32_t elem_type_flag);

/**
 * Free a list: release all atoms (and their string/list payloads),
 * then free the header itself.
 */
void list_free(ListHeader* list);

/* ========================================================================= */
/* Adding Elements — Append (to end, O(1))                                    */
/* ========================================================================= */

void list_append_int(ListHeader* list, int64_t value);
void list_append_float(ListHeader* list, double value);
void list_append_string(ListHeader* list, StringDescriptor* value);
void list_append_list(ListHeader* list, ListHeader* nested);
void list_append_object(ListHeader* list, void* object_ptr);

/* ========================================================================= */
/* Adding Elements — Prepend (to beginning, O(1))                             */
/* ========================================================================= */

void list_prepend_int(ListHeader* list, int64_t value);
void list_prepend_float(ListHeader* list, double value);
void list_prepend_string(ListHeader* list, StringDescriptor* value);
void list_prepend_list(ListHeader* list, ListHeader* nested);

/* ========================================================================= */
/* Adding Elements — Insert (at 1-based position, O(n))                       */
/* ========================================================================= */

void list_insert_int(ListHeader* list, int64_t pos, int64_t value);
void list_insert_float(ListHeader* list, int64_t pos, double value);
void list_insert_string(ListHeader* list, int64_t pos, StringDescriptor* value);

/* ========================================================================= */
/* Extending — Append all elements from another list                          */
/* ========================================================================= */

void list_extend(ListHeader* dest, ListHeader* src);

/* ========================================================================= */
/* Removing Elements — Shift (remove first, O(1))                             */
/* ========================================================================= */

/** Remove first element, return its integer value. Returns 0 if empty. */
int64_t  list_shift_int(ListHeader* list);

/** Remove first element, return its float value. Returns 0.0 if empty. */
double   list_shift_float(ListHeader* list);

/** Remove first element, return its pointer value. Returns NULL if empty. */
void*    list_shift_ptr(ListHeader* list);

/** Return the type tag of the first element (without removing). Returns 0 if empty. */
int32_t  list_shift_type(ListHeader* list);

/** Remove first element, discard the value. */
void     list_shift(ListHeader* list);

/* ========================================================================= */
/* Removing Elements — Pop (remove last, O(n) for singly-linked)              */
/* ========================================================================= */

/** Remove last element, return its integer value. Returns 0 if empty. */
int64_t  list_pop_int(ListHeader* list);

/** Remove last element, return its float value. Returns 0.0 if empty. */
double   list_pop_float(ListHeader* list);

/** Remove last element, return its pointer value. Returns NULL if empty. */
void*    list_pop_ptr(ListHeader* list);

/** Remove last element, discard the value. */
void     list_pop(ListHeader* list);

/* ========================================================================= */
/* Removing Elements — Positional                                             */
/* ========================================================================= */

/** Remove element at 1-based position. No-op if out of range. */
void list_remove(ListHeader* list, int64_t pos);

/** Remove all elements (list becomes empty, header retained). */
void list_clear(ListHeader* list);

/* ========================================================================= */
/* Access — Positional (1-based, O(n))                                        */
/* ========================================================================= */

/** Get integer value at 1-based position. Returns 0 if out of range. */
int64_t  list_get_int(ListHeader* list, int64_t pos);

/** Get float value at 1-based position. Returns 0.0 if out of range. */
double   list_get_float(ListHeader* list, int64_t pos);

/** Get pointer value at 1-based position. Returns NULL if out of range. */
void*    list_get_ptr(ListHeader* list, int64_t pos);

/** Get type tag at 1-based position. Returns ATOM_SENTINEL (0) if out of range. */
int32_t  list_get_type(ListHeader* list, int64_t pos);

/* ========================================================================= */
/* Access — Head (first element, O(1))                                        */
/* ========================================================================= */

/** First element as int. Returns 0 if empty. */
int64_t  list_head_int(ListHeader* list);

/** First element as float. Returns 0.0 if empty. */
double   list_head_float(ListHeader* list);

/** First element as pointer. Returns NULL if empty. */
void*    list_head_ptr(ListHeader* list);

/** Type tag of first element. Returns ATOM_SENTINEL (0) if empty. */
int32_t  list_head_type(ListHeader* list);

/* ========================================================================= */
/* Access — Metadata (O(1))                                                   */
/* ========================================================================= */

/** Number of elements in the list. */
int64_t  list_length(ListHeader* list);

/** 1 if empty, 0 otherwise. */
int32_t  list_empty(ListHeader* list);

/* ========================================================================= */
/* Iteration Support                                                          */
/* ========================================================================= */
/*
 * Cursor-based iteration for FOR EACH codegen:
 *
 *   ListAtom* cursor = list_iter_begin(header);
 *   while (cursor) {
 *       int32_t type  = list_iter_type(cursor);
 *       int64_t ival  = list_iter_value_int(cursor);
 *       double  fval  = list_iter_value_float(cursor);
 *       void*   pval  = list_iter_value_ptr(cursor);
 *       cursor = list_iter_next(cursor);
 *   }
 *
 * The codegen typically inlines these (they're trivial field accesses)
 * but the functions exist for use from standalone C tests and from
 * the SAMM cleanup path.
 */

/** Return the first atom (header->head), or NULL if empty. */
ListAtom* list_iter_begin(ListHeader* list);

/** Return the next atom (current->next), or NULL if at end. */
ListAtom* list_iter_next(ListAtom* current);

/** Return the type tag of the current atom. */
int32_t   list_iter_type(ListAtom* current);

/** Return the integer value of the current atom. */
int64_t   list_iter_value_int(ListAtom* current);

/** Return the float value of the current atom. */
double    list_iter_value_float(ListAtom* current);

/** Return the pointer value of the current atom. */
void*     list_iter_value_ptr(ListAtom* current);

/* ========================================================================= */
/* Operations — Return New Lists                                              */
/* ========================================================================= */

/**
 * Deep copy: new header, new atoms. String atoms are string_retain()'d
 * (shared ownership). Nested list atoms are recursively copied.
 */
ListHeader* list_copy(ListHeader* list);

/**
 * Return a copy of all elements except the first (functional "tail").
 * Returns an empty list if the input has 0 or 1 elements.
 */
ListHeader* list_rest(ListHeader* list);

/**
 * Return a new list with elements in reversed order.
 * The original list is not modified.
 */
ListHeader* list_reverse(ListHeader* list);

/* ========================================================================= */
/* Operations — Search                                                        */
/* ========================================================================= */

/** 1 if the list contains the given integer value, 0 otherwise. */
int32_t  list_contains_int(ListHeader* list, int64_t value);

/** 1 if the list contains the given float value, 0 otherwise. */
int32_t  list_contains_float(ListHeader* list, double value);

/** 1 if the list contains a string equal to value, 0 otherwise. */
int32_t  list_contains_string(ListHeader* list, StringDescriptor* value);

/**
 * Return the 1-based index of the first occurrence of value,
 * or 0 if not found.
 */
int64_t  list_indexof_int(ListHeader* list, int64_t value);

/**
 * Return the 1-based index of the first occurrence of value,
 * or 0 if not found.
 */
int64_t  list_indexof_float(ListHeader* list, double value);

/**
 * Return the 1-based index of the first string equal to value,
 * or 0 if not found.
 */
int64_t  list_indexof_string(ListHeader* list, StringDescriptor* value);

/* ========================================================================= */
/* Operations — Join                                                          */
/* ========================================================================= */

/**
 * Join all elements as strings with a separator between them.
 * Non-string elements are converted to their string representation.
 * Returns a new StringDescriptor* (caller must string_release when done).
 */
StringDescriptor* list_join(ListHeader* list, StringDescriptor* separator);

/* ========================================================================= */
/* Utility                                                                    */
/* ========================================================================= */

/**
 * Check if a void* points to a ListHeader (type == ATOM_SENTINEL)
 * vs. a ListAtom (type >= 1). Useful for defensive runtime code.
 */
static inline int list_is_header(const void* ptr) {
    if (!ptr) return 0;
    return ((const ListHeader*)ptr)->type == ATOM_SENTINEL;
}

/**
 * Get the element type flag from a list's flags field.
 */
static inline int32_t list_elem_type_flag(const ListHeader* list) {
    if (!list) return LIST_FLAG_ELEM_ANY;
    return list->flags & LIST_FLAG_ELEM_MASK;
}

/**
 * Debug: print list contents to stderr.
 */
void list_debug_print(ListHeader* list);

/* ========================================================================= */
/* SAMM Cleanup Path                                                          */
/* ========================================================================= */
/*
 * These functions are called by SAMM's cleanup_batch when it encounters
 * pointers tracked as SAMM_ALLOC_LIST or SAMM_ALLOC_LIST_ATOM.
 *
 * They differ from list_free/atom_free in that they do NOT call
 * samm_untrack (the pointer is already being cleaned by SAMM) and they
 * handle the case where atoms may have already been individually freed
 * by SAMM before the header is freed.
 *
 * The key issue: SAMM tracks both headers and atoms independently.
 * When a scope exits, SAMM may free atoms before or after their parent
 * header. These functions handle that safely:
 *
 *   list_free_from_samm()      — frees header only (atoms handled by SAMM)
 *   list_atom_free_from_samm() — releases atom payload then frees the atom
 */

/**
 * Called by SAMM cleanup for SAMM_ALLOC_LIST pointers.
 * Frees the header struct only — does NOT walk the atom chain,
 * because SAMM tracks and frees atoms independently.
 */
void list_free_from_samm(void* header_ptr);

/**
 * Called by SAMM cleanup for SAMM_ALLOC_LIST_ATOM pointers.
 * Releases the atom's payload (string_release for strings,
 * recursive list_free for nested lists owned by this atom)
 * then frees the atom struct.
 */
void list_atom_free_from_samm(void* atom_ptr);

#ifdef __cplusplus
}
#endif

#endif /* LIST_OPS_H */