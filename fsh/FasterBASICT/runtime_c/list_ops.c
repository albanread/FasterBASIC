/*
 * list_ops.c
 * FasterBASIC Runtime — Linked List Operations
 *
 * Implements singly-linked heterogeneous and typed lists.
 * See list_ops.h for data structure documentation and API reference.
 *
 * Design notes:
 *   - All positions are 1-based (BASIC convention)
 *   - NULL list pointers are handled gracefully (return zero/NULL/empty)
 *   - String atoms call string_retain() on add, string_release() on remove
 *   - Nested list atoms are recursively freed via list_free()
 *   - SAMM integration: headers tracked as SAMM_ALLOC_LIST,
 *     atoms tracked as SAMM_ALLOC_LIST_ATOM
 *
 * Build:
 *   cc -std=c99 -O2 -c list_ops.c -o list_ops.o
 */

#include "list_ops.h"
#include "string_descriptor.h"
#include "samm_bridge.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

/* ========================================================================= */
/* Internal: Atom allocation & cleanup                                        */
/* ========================================================================= */

/**
 * Allocate a new ListAtom. Uses malloc (Phase 5 will add freelist pooling).
 * The atom is SAMM-tracked as SAMM_ALLOC_LIST_ATOM.
 */
static ListAtom* atom_alloc(void) {
    ListAtom* atom = (ListAtom*)malloc(sizeof(ListAtom));
    if (!atom) {
        fprintf(stderr, "list_ops: out of memory allocating ListAtom\n");
        abort();
    }
    atom->type = ATOM_SENTINEL; /* Will be set by caller */
    atom->pad  = 0;
    atom->value.int_value = 0;
    atom->next = NULL;

    /* Track in SAMM so scope exit cleans up if needed */
    if (samm_is_enabled()) {
        samm_track((void*)atom, SAMM_ALLOC_LIST_ATOM);
    }

    return atom;
}

/**
 * Release the payload of a single atom (string_release, recursive list_free, etc.)
 * Does NOT free the atom struct itself — caller handles that.
 */
static void atom_release_payload(ListAtom* atom) {
    if (!atom) return;

    switch (atom->type) {
        case ATOM_STRING:
            if (atom->value.ptr_value) {
                string_release((StringDescriptor*)atom->value.ptr_value);
                atom->value.ptr_value = NULL;
            }
            break;
        case ATOM_LIST:
            if (atom->value.ptr_value) {
                list_free((ListHeader*)atom->value.ptr_value);
                atom->value.ptr_value = NULL;
            }
            break;
        case ATOM_OBJECT:
            /* Objects are managed by their own SAMM tracking.
             * We don't own them — just clear the pointer. */
            atom->value.ptr_value = NULL;
            break;
        default:
            /* INT, FLOAT — no cleanup needed */
            break;
    }
}

/**
 * Free a single atom: release payload, then free the struct.
 */
static void atom_free(ListAtom* atom) {
    if (!atom) return;
    atom_release_payload(atom);
    /* Untrack from SAMM before freeing so that SAMM's scope-exit
     * cleanup won't try to list_atom_free_from_samm on an
     * already-freed atom (double-free). */
    if (samm_is_enabled()) {
        samm_untrack(atom);
    }
    free(atom);
}

/**
 * Walk to the atom at 1-based position `pos` in the chain starting at `head`.
 * Returns NULL if pos is out of range [1..length].
 * Also returns the previous atom via `out_prev` (NULL if pos == 1).
 */
static ListAtom* atom_walk_to(ListAtom* head, int64_t pos, ListAtom** out_prev) {
    if (out_prev) *out_prev = NULL;
    if (!head || pos < 1) return NULL;

    ListAtom* prev = NULL;
    ListAtom* curr = head;
    int64_t i = 1;

    while (curr && i < pos) {
        prev = curr;
        curr = curr->next;
        i++;
    }

    if (i != pos || !curr) return NULL;

    if (out_prev) *out_prev = prev;
    return curr;
}

/* ========================================================================= */
/* Internal: Create atom with specific type/value and link into list           */
/* ========================================================================= */

/**
 * Create an atom, set its type and value, then append it to the list.
 */
static void list_append_atom(ListHeader* list, ListAtom* atom) {
    if (!list || !atom) return;

    atom->next = NULL;

    if (list->tail) {
        list->tail->next = atom;
        list->tail = atom;
    } else {
        /* Empty list */
        list->head = atom;
        list->tail = atom;
    }
    list->length++;
}

/**
 * Create an atom, set its type and value, then prepend it to the list.
 */
static void list_prepend_atom(ListHeader* list, ListAtom* atom) {
    if (!list || !atom) return;

    atom->next = list->head;
    list->head = atom;

    if (!list->tail) {
        list->tail = atom;
    }
    list->length++;
}

/**
 * Insert an atom at 1-based position. Position 1 = prepend, position > length = append.
 */
static void list_insert_atom(ListHeader* list, int64_t pos, ListAtom* atom) {
    if (!list || !atom) return;

    /* Clamp position */
    if (pos <= 1) {
        list_prepend_atom(list, atom);
        return;
    }
    if (pos > list->length) {
        list_append_atom(list, atom);
        return;
    }

    /* Walk to the atom just before the insertion point */
    ListAtom* prev = NULL;
    ListAtom* curr = atom_walk_to(list->head, pos, &prev);

    if (!prev) {
        /* pos == 1 (shouldn't reach here due to clamp, but safety) */
        list_prepend_atom(list, atom);
        return;
    }

    atom->next = prev->next;
    prev->next = atom;

    /* If inserting after the current tail, update tail */
    if (atom->next == NULL) {
        list->tail = atom;
    }

    list->length++;
}

/* ========================================================================= */
/* Creation & Destruction                                                     */
/* ========================================================================= */

ListHeader* list_create(void) {
    ListHeader* h = (ListHeader*)malloc(sizeof(ListHeader));
    if (!h) {
        fprintf(stderr, "list_ops: out of memory allocating ListHeader\n");
        abort();
    }
    h->type   = ATOM_SENTINEL;
    h->flags  = LIST_FLAG_ELEM_ANY;
    h->length = 0;
    h->head   = NULL;
    h->tail   = NULL;

    /* Track in SAMM */
    if (samm_is_enabled()) {
        samm_track_list((void*)h);
    }

    return h;
}

ListHeader* list_create_typed(int32_t elem_type_flag) {
    ListHeader* h = list_create();
    if (h) {
        h->flags = (h->flags & ~LIST_FLAG_ELEM_MASK) | (elem_type_flag & LIST_FLAG_ELEM_MASK);
    }
    return h;
}

void list_free(ListHeader* list) {
    if (!list) return;

    /* Free all atoms */
    ListAtom* curr = list->head;
    while (curr) {
        ListAtom* next = curr->next;
        atom_free(curr);
        curr = next;
    }

    list->head   = NULL;
    list->tail   = NULL;
    list->length = 0;

    /* Free the header itself */
    free(list);
}

/* ========================================================================= */
/* Adding Elements — Append                                                   */
/* ========================================================================= */

void list_append_int(ListHeader* list, int64_t value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_INT;
    atom->value.int_value = value;
    list_append_atom(list, atom);
}

void list_append_float(ListHeader* list, double value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_FLOAT;
    atom->value.float_value = value;
    list_append_atom(list, atom);
}

void list_append_string(ListHeader* list, StringDescriptor* value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_STRING;
    /* Retain the string — the list now co-owns it */
    if (value) {
        string_retain(value);
    }
    atom->value.ptr_value = (void*)value;
    list_append_atom(list, atom);
}

void list_append_list(ListHeader* list, ListHeader* nested) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_LIST;
    /* We store a reference to the nested list.
     * The caller is responsible for ensuring the nested list outlives
     * this reference, or that this list owns it (e.g., LIST(...) constructor). */
    atom->value.ptr_value = (void*)nested;
    list_append_atom(list, atom);
}

void list_append_object(ListHeader* list, void* object_ptr) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_OBJECT;
    atom->value.ptr_value = object_ptr;
    list_append_atom(list, atom);
}

/* ========================================================================= */
/* Adding Elements — Prepend                                                  */
/* ========================================================================= */

void list_prepend_int(ListHeader* list, int64_t value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_INT;
    atom->value.int_value = value;
    list_prepend_atom(list, atom);
}

void list_prepend_float(ListHeader* list, double value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_FLOAT;
    atom->value.float_value = value;
    list_prepend_atom(list, atom);
}

void list_prepend_string(ListHeader* list, StringDescriptor* value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_STRING;
    if (value) {
        string_retain(value);
    }
    atom->value.ptr_value = (void*)value;
    list_prepend_atom(list, atom);
}

void list_prepend_list(ListHeader* list, ListHeader* nested) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_LIST;
    atom->value.ptr_value = (void*)nested;
    list_prepend_atom(list, atom);
}

/* ========================================================================= */
/* Adding Elements — Insert (1-based position)                                */
/* ========================================================================= */

void list_insert_int(ListHeader* list, int64_t pos, int64_t value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_INT;
    atom->value.int_value = value;
    list_insert_atom(list, pos, atom);
}

void list_insert_float(ListHeader* list, int64_t pos, double value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_FLOAT;
    atom->value.float_value = value;
    list_insert_atom(list, pos, atom);
}

void list_insert_string(ListHeader* list, int64_t pos, StringDescriptor* value) {
    if (!list) return;
    ListAtom* atom = atom_alloc();
    atom->type = ATOM_STRING;
    if (value) {
        string_retain(value);
    }
    atom->value.ptr_value = (void*)value;
    list_insert_atom(list, pos, atom);
}

/* ========================================================================= */
/* Extending                                                                  */
/* ========================================================================= */

void list_extend(ListHeader* dest, ListHeader* src) {
    if (!dest || !src) return;

    ListAtom* curr = src->head;
    while (curr) {
        switch (curr->type) {
            case ATOM_INT:
                list_append_int(dest, curr->value.int_value);
                break;
            case ATOM_FLOAT:
                list_append_float(dest, curr->value.float_value);
                break;
            case ATOM_STRING:
                list_append_string(dest, (StringDescriptor*)curr->value.ptr_value);
                break;
            case ATOM_LIST:
                /* Deep copy the nested list to avoid shared ownership issues */
                list_append_list(dest, list_copy((ListHeader*)curr->value.ptr_value));
                break;
            case ATOM_OBJECT:
                list_append_object(dest, curr->value.ptr_value);
                break;
            default:
                break;
        }
        curr = curr->next;
    }
}

/* ========================================================================= */
/* Removing Elements — Shift (remove first)                                   */
/* ========================================================================= */

/**
 * Internal: remove the first atom and return it. Caller owns the atom.
 * Returns NULL if list is empty.
 */
static ListAtom* list_shift_atom(ListHeader* list) {
    if (!list || !list->head) return NULL;

    ListAtom* atom = list->head;
    list->head = atom->next;
    atom->next = NULL;

    if (!list->head) {
        list->tail = NULL;
    }
    list->length--;

    return atom;
}

int64_t list_shift_int(ListHeader* list) {
    ListAtom* atom = list_shift_atom(list);
    if (!atom) return 0;
    int64_t val = atom->value.int_value;
    /* Don't release payload for INT — just free struct */
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

double list_shift_float(ListHeader* list) {
    ListAtom* atom = list_shift_atom(list);
    if (!atom) return 0.0;
    double val = atom->value.float_value;
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

void* list_shift_ptr(ListHeader* list) {
    ListAtom* atom = list_shift_atom(list);
    if (!atom) return NULL;
    void* val = atom->value.ptr_value;
    /* Don't release the string/list — caller now owns the reference */
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

int32_t list_shift_type(ListHeader* list) {
    if (!list || !list->head) return ATOM_SENTINEL;
    return list->head->type;
}

void list_shift(ListHeader* list) {
    ListAtom* atom = list_shift_atom(list);
    if (atom) {
        atom_free(atom); /* Release payload and free */
    }
}

/* ========================================================================= */
/* Removing Elements — Pop (remove last, O(n))                                */
/* ========================================================================= */

/**
 * Internal: remove the last atom and return it. Caller owns the atom.
 * O(n) because we need to find the new tail in a singly-linked list.
 */
static ListAtom* list_pop_atom(ListHeader* list) {
    if (!list || !list->head) return NULL;

    /* Single element? */
    if (list->head == list->tail) {
        ListAtom* atom = list->head;
        list->head = NULL;
        list->tail = NULL;
        list->length = 0;
        atom->next = NULL;
        return atom;
    }

    /* Walk to the second-to-last element */
    ListAtom* prev = list->head;
    while (prev->next != list->tail) {
        prev = prev->next;
    }

    ListAtom* atom = list->tail;
    prev->next = NULL;
    list->tail = prev;
    list->length--;
    atom->next = NULL;

    return atom;
}

int64_t list_pop_int(ListHeader* list) {
    ListAtom* atom = list_pop_atom(list);
    if (!atom) return 0;
    int64_t val = atom->value.int_value;
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

double list_pop_float(ListHeader* list) {
    ListAtom* atom = list_pop_atom(list);
    if (!atom) return 0.0;
    double val = atom->value.float_value;
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

void* list_pop_ptr(ListHeader* list) {
    ListAtom* atom = list_pop_atom(list);
    if (!atom) return NULL;
    void* val = atom->value.ptr_value;
    /* Caller now owns the reference */
    if (samm_is_enabled()) samm_untrack(atom);
    free(atom);
    return val;
}

void list_pop(ListHeader* list) {
    ListAtom* atom = list_pop_atom(list);
    if (atom) {
        atom_free(atom);
    }
}

/* ========================================================================= */
/* Removing Elements — Positional                                             */
/* ========================================================================= */

void list_remove(ListHeader* list, int64_t pos) {
    if (!list || !list->head || pos < 1 || pos > list->length) return;

    if (pos == 1) {
        list_shift(list);
        return;
    }

    if (pos == list->length) {
        list_pop(list);
        return;
    }

    /* Walk to the atom at position pos and its predecessor */
    ListAtom* prev = NULL;
    ListAtom* target = atom_walk_to(list->head, pos, &prev);

    if (!target || !prev) return;

    prev->next = target->next;
    target->next = NULL;

    /* target can't be tail here (handled by pop case above) */
    list->length--;
    atom_free(target);
}

void list_clear(ListHeader* list) {
    if (!list) return;

    ListAtom* curr = list->head;
    while (curr) {
        ListAtom* next = curr->next;
        atom_free(curr);
        curr = next;
    }

    list->head   = NULL;
    list->tail   = NULL;
    list->length = 0;
}

/* ========================================================================= */
/* Access — Positional (1-based)                                              */
/* ========================================================================= */

int64_t list_get_int(ListHeader* list, int64_t pos) {
    if (!list) return 0;
    ListAtom* atom = atom_walk_to(list->head, pos, NULL);
    if (!atom) return 0;
    return atom->value.int_value;
}

double list_get_float(ListHeader* list, int64_t pos) {
    if (!list) return 0.0;
    ListAtom* atom = atom_walk_to(list->head, pos, NULL);
    if (!atom) return 0.0;
    return atom->value.float_value;
}

void* list_get_ptr(ListHeader* list, int64_t pos) {
    if (!list) return NULL;
    ListAtom* atom = atom_walk_to(list->head, pos, NULL);
    if (!atom) return NULL;
    return atom->value.ptr_value;
}

int32_t list_get_type(ListHeader* list, int64_t pos) {
    if (!list) return ATOM_SENTINEL;
    ListAtom* atom = atom_walk_to(list->head, pos, NULL);
    if (!atom) return ATOM_SENTINEL;
    return atom->type;
}

/* ========================================================================= */
/* Access — Head                                                              */
/* ========================================================================= */

int64_t list_head_int(ListHeader* list) {
    if (!list || !list->head) return 0;
    return list->head->value.int_value;
}

double list_head_float(ListHeader* list) {
    if (!list || !list->head) return 0.0;
    return list->head->value.float_value;
}

void* list_head_ptr(ListHeader* list) {
    if (!list || !list->head) return NULL;
    return list->head->value.ptr_value;
}

int32_t list_head_type(ListHeader* list) {
    if (!list || !list->head) return ATOM_SENTINEL;
    return list->head->type;
}

/* ========================================================================= */
/* Access — Metadata                                                          */
/* ========================================================================= */

int64_t list_length(ListHeader* list) {
    if (!list) return 0;
    return list->length;
}

int32_t list_empty(ListHeader* list) {
    if (!list) return 1;
    return (list->length == 0) ? 1 : 0;
}

/* ========================================================================= */
/* Iteration Support                                                          */
/* ========================================================================= */

ListAtom* list_iter_begin(ListHeader* list) {
    if (!list) return NULL;
    return list->head;
}

ListAtom* list_iter_next(ListAtom* current) {
    if (!current) return NULL;
    return current->next;
}

int32_t list_iter_type(ListAtom* current) {
    if (!current) return ATOM_SENTINEL;
    return current->type;
}

int64_t list_iter_value_int(ListAtom* current) {
    if (!current) return 0;
    return current->value.int_value;
}

double list_iter_value_float(ListAtom* current) {
    if (!current) return 0.0;
    return current->value.float_value;
}

void* list_iter_value_ptr(ListAtom* current) {
    if (!current) return NULL;
    return current->value.ptr_value;
}

/* ========================================================================= */
/* Operations — Copy / Rest / Reverse                                         */
/* ========================================================================= */

ListHeader* list_copy(ListHeader* list) {
    if (!list) return list_create();

    /* Create new list with same flags */
    ListHeader* copy = list_create_typed(list->flags & LIST_FLAG_ELEM_MASK);

    ListAtom* curr = list->head;
    while (curr) {
        switch (curr->type) {
            case ATOM_INT:
                list_append_int(copy, curr->value.int_value);
                break;
            case ATOM_FLOAT:
                list_append_float(copy, curr->value.float_value);
                break;
            case ATOM_STRING:
                /* string_retain is called inside list_append_string */
                list_append_string(copy, (StringDescriptor*)curr->value.ptr_value);
                break;
            case ATOM_LIST:
                /* Deep copy nested list */
                list_append_list(copy, list_copy((ListHeader*)curr->value.ptr_value));
                break;
            case ATOM_OBJECT:
                list_append_object(copy, curr->value.ptr_value);
                break;
            default:
                break;
        }
        curr = curr->next;
    }

    return copy;
}

ListHeader* list_rest(ListHeader* list) {
    if (!list || !list->head) return list_create();

    /* Create new list with same flags */
    ListHeader* rest = list_create_typed(list->flags & LIST_FLAG_ELEM_MASK);

    /* Skip the first element, copy the rest */
    ListAtom* curr = list->head->next;
    while (curr) {
        switch (curr->type) {
            case ATOM_INT:
                list_append_int(rest, curr->value.int_value);
                break;
            case ATOM_FLOAT:
                list_append_float(rest, curr->value.float_value);
                break;
            case ATOM_STRING:
                list_append_string(rest, (StringDescriptor*)curr->value.ptr_value);
                break;
            case ATOM_LIST:
                list_append_list(rest, list_copy((ListHeader*)curr->value.ptr_value));
                break;
            case ATOM_OBJECT:
                list_append_object(rest, curr->value.ptr_value);
                break;
            default:
                break;
        }
        curr = curr->next;
    }

    return rest;
}

ListHeader* list_reverse(ListHeader* list) {
    if (!list) return list_create();

    /* Create new list with same flags */
    ListHeader* rev = list_create_typed(list->flags & LIST_FLAG_ELEM_MASK);

    /* Walk the original and prepend each element to the new list */
    ListAtom* curr = list->head;
    while (curr) {
        switch (curr->type) {
            case ATOM_INT:
                list_prepend_int(rev, curr->value.int_value);
                break;
            case ATOM_FLOAT:
                list_prepend_float(rev, curr->value.float_value);
                break;
            case ATOM_STRING:
                list_prepend_string(rev, (StringDescriptor*)curr->value.ptr_value);
                break;
            case ATOM_LIST:
                list_prepend_list(rev, list_copy((ListHeader*)curr->value.ptr_value));
                break;
            case ATOM_OBJECT: {
                /* prepend_object doesn't exist, use manual atom creation */
                ListAtom* atom = atom_alloc();
                atom->type = ATOM_OBJECT;
                atom->value.ptr_value = curr->value.ptr_value;
                list_prepend_atom(rev, atom);
                break;
            }
            default:
                break;
        }
        curr = curr->next;
    }

    return rev;
}

/* ========================================================================= */
/* Operations — Search                                                        */
/* ========================================================================= */

int32_t list_contains_int(ListHeader* list, int64_t value) {
    if (!list) return 0;

    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_INT && curr->value.int_value == value) {
            return 1;
        }
        curr = curr->next;
    }
    return 0;
}

int32_t list_contains_float(ListHeader* list, double value) {
    if (!list) return 0;

    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_FLOAT && curr->value.float_value == value) {
            return 1;
        }
        curr = curr->next;
    }
    return 0;
}

int32_t list_contains_string(ListHeader* list, StringDescriptor* value) {
    if (!list) return 0;

    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_STRING) {
            StringDescriptor* elem = (StringDescriptor*)curr->value.ptr_value;
            /* Both NULL = match, both non-NULL = compare */
            if (elem == value) {
                return 1;
            }
            if (elem && value && string_compare(elem, value) == 0) {
                return 1;
            }
        }
        curr = curr->next;
    }
    return 0;
}

int64_t list_indexof_int(ListHeader* list, int64_t value) {
    if (!list) return 0;

    int64_t index = 1;
    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_INT && curr->value.int_value == value) {
            return index;
        }
        curr = curr->next;
        index++;
    }
    return 0; /* Not found */
}

int64_t list_indexof_float(ListHeader* list, double value) {
    if (!list) return 0;

    int64_t index = 1;
    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_FLOAT && curr->value.float_value == value) {
            return index;
        }
        curr = curr->next;
        index++;
    }
    return 0;
}

int64_t list_indexof_string(ListHeader* list, StringDescriptor* value) {
    if (!list) return 0;

    int64_t index = 1;
    ListAtom* curr = list->head;
    while (curr) {
        if (curr->type == ATOM_STRING) {
            StringDescriptor* elem = (StringDescriptor*)curr->value.ptr_value;
            if (elem == value) {
                return index;
            }
            if (elem && value && string_compare(elem, value) == 0) {
                return index;
            }
        }
        curr = curr->next;
        index++;
    }
    return 0;
}

/* ========================================================================= */
/* Operations — Join                                                          */
/* ========================================================================= */

/**
 * Internal helper: convert an atom's value to a temporary C string.
 * Returns a malloc'd string that the caller must free.
 */
static char* atom_value_to_cstr(ListAtom* atom) {
    if (!atom) return strdup("");

    char buf[64];

    switch (atom->type) {
        case ATOM_INT:
            snprintf(buf, sizeof(buf), "%lld", (long long)atom->value.int_value);
            return strdup(buf);

        case ATOM_FLOAT: {
            /* Format similarly to BASIC STR$() — remove trailing zeros */
            snprintf(buf, sizeof(buf), "%g", atom->value.float_value);
            return strdup(buf);
        }

        case ATOM_STRING: {
            StringDescriptor* sd = (StringDescriptor*)atom->value.ptr_value;
            if (!sd) return strdup("");
            const char* utf8 = string_to_utf8(sd);
            return utf8 ? strdup(utf8) : strdup("");
        }

        case ATOM_LIST:
            return strdup("[List]");

        case ATOM_OBJECT:
            return strdup("[Object]");

        default:
            return strdup("");
    }
}

StringDescriptor* list_join(ListHeader* list, StringDescriptor* separator) {
    if (!list || list->length == 0) {
        /* Return empty string */
        return string_new_ascii("");
    }

    /* Get separator as C string */
    const char* sep_cstr = "";
    if (separator) {
        sep_cstr = string_to_utf8(separator);
        if (!sep_cstr) sep_cstr = "";
    }
    size_t sep_len = strlen(sep_cstr);

    /* First pass: calculate total output length */
    size_t total_len = 0;
    int64_t count = 0;

    ListAtom* curr = list->head;
    while (curr) {
        char* val_str = atom_value_to_cstr(curr);
        total_len += strlen(val_str);
        free(val_str);

        count++;
        if (curr->next) {
            total_len += sep_len;
        }
        curr = curr->next;
    }

    /* Allocate output buffer */
    char* result = (char*)malloc(total_len + 1);
    if (!result) {
        return string_new_ascii("");
    }

    /* Second pass: build the joined string */
    char* pos = result;
    curr = list->head;
    while (curr) {
        char* val_str = atom_value_to_cstr(curr);
        size_t vlen = strlen(val_str);
        memcpy(pos, val_str, vlen);
        pos += vlen;
        free(val_str);

        if (curr->next) {
            memcpy(pos, sep_cstr, sep_len);
            pos += sep_len;
        }
        curr = curr->next;
    }
    *pos = '\0';

    /* Create a new StringDescriptor from the joined result */
    StringDescriptor* sd = string_new_utf8(result);
    free(result);

    return sd;
}

/* ========================================================================= */
/* Debug                                                                      */
/* ========================================================================= */

/* ========================================================================= */
/* SAMM Cleanup Path                                                          */
/* ========================================================================= */

void list_free_from_samm(void* header_ptr) {
    if (!header_ptr) return;

    ListHeader* list = (ListHeader*)header_ptr;

    /*
     * SAMM tracks headers and atoms independently. When SAMM cleans up
     * a scope, it will call list_atom_free_from_samm for each atom AND
     * list_free_from_samm for the header — in arbitrary order.
     *
     * Therefore we must NOT walk the atom chain here. The atoms are
     * (or will be) freed by their own SAMM_ALLOC_LIST_ATOM cleanup calls.
     *
     * We just zero out the header and free the struct.
     */
    list->head   = NULL;
    list->tail   = NULL;
    list->length = 0;
    free(list);
}

void list_atom_free_from_samm(void* atom_ptr) {
    if (!atom_ptr) return;

    ListAtom* atom = (ListAtom*)atom_ptr;

    /*
     * Release the atom's payload — strings need string_release(),
     * nested lists need list_free() (the nested list has its OWN
     * SAMM tracking, so this is safe — list_free is idempotent on
     * already-freed nested lists if SAMM cleaned them first, but
     * nested lists stored as atom values are typically NOT separately
     * SAMM-tracked, they're owned by the atom).
     */
    atom_release_payload(atom);

    /* Free the atom struct itself */
    free(atom);
}

/* ========================================================================= */
/* Debug                                                                      */
/* ========================================================================= */

void list_debug_print(ListHeader* list) {
    if (!list) {
        fprintf(stderr, "LIST: (null)\n");
        return;
    }

    fprintf(stderr, "LIST: length=%lld flags=0x%04x {\n",
            (long long)list->length, list->flags);

    int64_t index = 1;
    ListAtom* curr = list->head;
    while (curr) {
        fprintf(stderr, "  [%lld] ", (long long)index);
        switch (curr->type) {
            case ATOM_INT:
                fprintf(stderr, "INT: %lld\n", (long long)curr->value.int_value);
                break;
            case ATOM_FLOAT:
                fprintf(stderr, "FLOAT: %g\n", curr->value.float_value);
                break;
            case ATOM_STRING: {
                StringDescriptor* sd = (StringDescriptor*)curr->value.ptr_value;
                if (sd) {
                    const char* utf8 = string_to_utf8(sd);
                    fprintf(stderr, "STRING: \"%s\" (len=%lld)\n",
                            utf8 ? utf8 : "(null)", (long long)sd->length);
                } else {
                    fprintf(stderr, "STRING: (null descriptor)\n");
                }
                break;
            }
            case ATOM_LIST: {
                ListHeader* nested = (ListHeader*)curr->value.ptr_value;
                if (nested) {
                    fprintf(stderr, "LIST: [nested, length=%lld]\n",
                            (long long)nested->length);
                } else {
                    fprintf(stderr, "LIST: (null)\n");
                }
                break;
            }
            case ATOM_OBJECT:
                fprintf(stderr, "OBJECT: %p\n", curr->value.ptr_value);
                break;
            default:
                fprintf(stderr, "UNKNOWN(type=%d)\n", curr->type);
                break;
        }
        curr = curr->next;
        index++;
    }
    fprintf(stderr, "}\n");
}