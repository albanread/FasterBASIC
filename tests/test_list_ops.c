/*
 * test_list_ops.c
 * Standalone C test for FasterBASIC list runtime (list_ops.c)
 *
 * Tests all Phase 1 runtime operations:
 *   - Creation (list_create, list_create_typed)
 *   - Append (int, float, string, list, object)
 *   - Prepend (int, float, string, list)
 *   - Insert (int, float, string)
 *   - Shift (int, float, ptr, type, discard)
 *   - Pop (int, float, ptr, discard)
 *   - Remove (positional)
 *   - Clear
 *   - Get (int, float, ptr, type)
 *   - Head (int, float, ptr, type)
 *   - Length, Empty
 *   - Iteration (begin, next, type, value_int, value_float, value_ptr)
 *   - Copy, Rest, Reverse
 *   - Contains (int, float, string)
 *   - IndexOf (int, float, string)
 *   - Join
 *   - Free
 *   - SAMM cleanup path (list_free_from_samm, list_atom_free_from_samm)
 *   - Debug print
 *
 * Build:
 *   cd compact_repo
 *   cc -std=c99 -g -O0 \
 *      -I fsh/FasterBASICT/runtime_c \
 *      tests/test_list_ops.c \
 *      fsh/FasterBASICT/runtime_c/list_ops.c \
 *      fsh/FasterBASICT/runtime_c/string_utf32.c \
 *      fsh/FasterBASICT/runtime_c/string_ops.c \
 *      fsh/FasterBASICT/runtime_c/string_pool.c \
 *      fsh/FasterBASICT/runtime_c/samm_core.c \
 *      fsh/FasterBASICT/runtime_c/array_descriptor_runtime.c \
 *      -lpthread -lm \
 *      -o tests/test_list_ops
 *   ./tests/test_list_ops
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>

#include "list_ops.h"
#include "string_descriptor.h"
#include "samm_bridge.h"

/* ========================================================================= */
/* Test framework                                                             */
/* ========================================================================= */

static int tests_run    = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) \
    do { \
        tests_run++; \
        fprintf(stderr, "  TEST: %-50s ", name); \
    } while (0)

#define PASS() \
    do { \
        tests_passed++; \
        fprintf(stderr, "PASS\n"); \
    } while (0)

#define FAIL(msg) \
    do { \
        tests_failed++; \
        fprintf(stderr, "FAIL  (%s)\n", msg); \
    } while (0)

#define ASSERT_EQ_INT(expected, actual, msg) \
    do { \
        long long _e = (long long)(expected); \
        long long _a = (long long)(actual); \
        if (_e != _a) { \
            char _buf[256]; \
            snprintf(_buf, sizeof(_buf), "%s: expected %lld, got %lld", msg, _e, _a); \
            FAIL(_buf); \
            return; \
        } \
    } while (0)

#define ASSERT_EQ_DOUBLE(expected, actual, msg) \
    do { \
        double _e = (double)(expected); \
        double _a = (double)(actual); \
        if (fabs(_e - _a) > 1e-9) { \
            char _buf[256]; \
            snprintf(_buf, sizeof(_buf), "%s: expected %g, got %g", msg, _e, _a); \
            FAIL(_buf); \
            return; \
        } \
    } while (0)

#define ASSERT_NOT_NULL(ptr, msg) \
    do { \
        if ((ptr) == NULL) { \
            FAIL(msg ": expected non-NULL"); \
            return; \
        } \
    } while (0)

#define ASSERT_NULL(ptr, msg) \
    do { \
        if ((ptr) != NULL) { \
            FAIL(msg ": expected NULL"); \
            return; \
        } \
    } while (0)

#define ASSERT_STR_EQ(expected, actual, msg) \
    do { \
        const char* _e = (expected); \
        const char* _a = (actual); \
        if (!_e && !_a) break; \
        if (!_e || !_a || strcmp(_e, _a) != 0) { \
            char _buf[256]; \
            snprintf(_buf, sizeof(_buf), "%s: expected \"%s\", got \"%s\"", \
                     msg, _e ? _e : "(null)", _a ? _a : "(null)"); \
            FAIL(_buf); \
            return; \
        } \
    } while (0)

/* ========================================================================= */
/* Tests: Creation                                                            */
/* ========================================================================= */

static void test_create_empty(void) {
    TEST("list_create — empty list");

    ListHeader* list = list_create();
    ASSERT_NOT_NULL(list, "list_create returned NULL");
    ASSERT_EQ_INT(0, list->type, "header type should be ATOM_SENTINEL");
    ASSERT_EQ_INT(0, list->length, "empty list length");
    ASSERT_EQ_INT(1, list_empty(list), "empty list should report empty");
    ASSERT_NULL(list->head, "empty list head");
    ASSERT_NULL(list->tail, "empty list tail");
    ASSERT_EQ_INT(LIST_FLAG_ELEM_ANY, list_elem_type_flag(list), "default flags = ANY");

    list_free(list);
    PASS();
}

static void test_create_typed(void) {
    TEST("list_create_typed — typed list flags");

    ListHeader* intList = list_create_typed(LIST_FLAG_ELEM_INT);
    ASSERT_NOT_NULL(intList, "int list");
    ASSERT_EQ_INT(LIST_FLAG_ELEM_INT, list_elem_type_flag(intList), "int flag");
    list_free(intList);

    ListHeader* strList = list_create_typed(LIST_FLAG_ELEM_STRING);
    ASSERT_NOT_NULL(strList, "str list");
    ASSERT_EQ_INT(LIST_FLAG_ELEM_STRING, list_elem_type_flag(strList), "str flag");
    list_free(strList);

    ListHeader* fltList = list_create_typed(LIST_FLAG_ELEM_FLOAT);
    ASSERT_NOT_NULL(fltList, "flt list");
    ASSERT_EQ_INT(LIST_FLAG_ELEM_FLOAT, list_elem_type_flag(fltList), "flt flag");
    list_free(fltList);

    PASS();
}

/* ========================================================================= */
/* Tests: Append                                                              */
/* ========================================================================= */

static void test_append_int(void) {
    TEST("list_append_int — basic integer append");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);

    ASSERT_EQ_INT(3, list_length(list), "length after 3 appends");
    ASSERT_EQ_INT(0, list_empty(list), "not empty");
    ASSERT_EQ_INT(10, list_get_int(list, 1), "element 1");
    ASSERT_EQ_INT(20, list_get_int(list, 2), "element 2");
    ASSERT_EQ_INT(30, list_get_int(list, 3), "element 3");

    /* Type tags */
    ASSERT_EQ_INT(ATOM_INT, list_get_type(list, 1), "type at 1");
    ASSERT_EQ_INT(ATOM_INT, list_get_type(list, 2), "type at 2");
    ASSERT_EQ_INT(ATOM_INT, list_get_type(list, 3), "type at 3");

    list_free(list);
    PASS();
}

static void test_append_float(void) {
    TEST("list_append_float — basic double append");

    ListHeader* list = list_create();
    list_append_float(list, 1.5);
    list_append_float(list, 2.7);

    ASSERT_EQ_INT(2, list_length(list), "length");
    ASSERT_EQ_DOUBLE(1.5, list_get_float(list, 1), "element 1");
    ASSERT_EQ_DOUBLE(2.7, list_get_float(list, 2), "element 2");
    ASSERT_EQ_INT(ATOM_FLOAT, list_get_type(list, 1), "type");

    list_free(list);
    PASS();
}

static void test_append_string(void) {
    TEST("list_append_string — string append with retain");

    ListHeader* list = list_create();

    StringDescriptor* s1 = string_new_ascii("hello");
    StringDescriptor* s2 = string_new_ascii("world");

    list_append_string(list, s1);
    list_append_string(list, s2);

    ASSERT_EQ_INT(2, list_length(list), "length");
    ASSERT_EQ_INT(ATOM_STRING, list_get_type(list, 1), "type 1");
    ASSERT_EQ_INT(ATOM_STRING, list_get_type(list, 2), "type 2");

    /* Verify string values via list_get_ptr */
    StringDescriptor* got1 = (StringDescriptor*)list_get_ptr(list, 1);
    StringDescriptor* got2 = (StringDescriptor*)list_get_ptr(list, 2);
    ASSERT_NOT_NULL(got1, "got1");
    ASSERT_NOT_NULL(got2, "got2");
    ASSERT_STR_EQ("hello", string_to_utf8(got1), "value 1");
    ASSERT_STR_EQ("world", string_to_utf8(got2), "value 2");

    /* Refcount should be > 1 since both original and list own it */
    ASSERT_EQ_INT(1, (got1->refcount > 1), "s1 retained");
    ASSERT_EQ_INT(1, (got2->refcount > 1), "s2 retained");

    /* Release our original references */
    string_release(s1);
    string_release(s2);

    /* List still has valid refs */
    got1 = (StringDescriptor*)list_get_ptr(list, 1);
    ASSERT_STR_EQ("hello", string_to_utf8(got1), "value 1 after release");

    list_free(list);
    PASS();
}

static void test_append_nested_list(void) {
    TEST("list_append_list — nested list");

    ListHeader* outer = list_create();
    ListHeader* inner = list_create();
    list_append_int(inner, 100);
    list_append_int(inner, 200);

    list_append_list(outer, inner);

    ASSERT_EQ_INT(1, list_length(outer), "outer length");
    ASSERT_EQ_INT(ATOM_LIST, list_get_type(outer, 1), "type = LIST");

    ListHeader* retrieved = (ListHeader*)list_get_ptr(outer, 1);
    ASSERT_NOT_NULL(retrieved, "retrieved nested list");
    ASSERT_EQ_INT(2, list_length(retrieved), "inner length");
    ASSERT_EQ_INT(100, list_get_int(retrieved, 1), "inner[1]");
    ASSERT_EQ_INT(200, list_get_int(retrieved, 2), "inner[2]");

    /* Freeing outer should also free inner (atom owns it) */
    list_free(outer);
    PASS();
}

static void test_append_mixed(void) {
    TEST("list_append — heterogeneous LIST OF ANY");

    ListHeader* list = list_create();
    list_append_int(list, 42);
    StringDescriptor* s = string_new_ascii("hello");
    list_append_string(list, s);
    string_release(s);
    list_append_float(list, 3.14);

    ASSERT_EQ_INT(3, list_length(list), "length");
    ASSERT_EQ_INT(ATOM_INT,    list_get_type(list, 1), "type 1 = INT");
    ASSERT_EQ_INT(ATOM_STRING, list_get_type(list, 2), "type 2 = STRING");
    ASSERT_EQ_INT(ATOM_FLOAT,  list_get_type(list, 3), "type 3 = FLOAT");

    ASSERT_EQ_INT(42, list_get_int(list, 1), "int value");
    ASSERT_EQ_DOUBLE(3.14, list_get_float(list, 3), "float value");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Prepend                                                             */
/* ========================================================================= */

static void test_prepend_int(void) {
    TEST("list_prepend_int — prepend to beginning");

    ListHeader* list = list_create();
    list_prepend_int(list, 30);
    list_prepend_int(list, 20);
    list_prepend_int(list, 10);

    ASSERT_EQ_INT(3, list_length(list), "length");
    ASSERT_EQ_INT(10, list_get_int(list, 1), "first");
    ASSERT_EQ_INT(20, list_get_int(list, 2), "second");
    ASSERT_EQ_INT(30, list_get_int(list, 3), "third");

    list_free(list);
    PASS();
}

static void test_prepend_string(void) {
    TEST("list_prepend_string — string prepend with retain");

    ListHeader* list = list_create();
    StringDescriptor* s1 = string_new_ascii("world");
    StringDescriptor* s2 = string_new_ascii("hello");

    list_prepend_string(list, s1);
    list_prepend_string(list, s2);

    string_release(s1);
    string_release(s2);

    ASSERT_EQ_INT(2, list_length(list), "length");
    StringDescriptor* got1 = (StringDescriptor*)list_get_ptr(list, 1);
    StringDescriptor* got2 = (StringDescriptor*)list_get_ptr(list, 2);
    ASSERT_STR_EQ("hello", string_to_utf8(got1), "first = hello");
    ASSERT_STR_EQ("world", string_to_utf8(got2), "second = world");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Insert                                                              */
/* ========================================================================= */

static void test_insert_int(void) {
    TEST("list_insert_int — insert at various positions");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 30);

    /* Insert at position 2 (between 10 and 30) */
    list_insert_int(list, 2, 20);

    ASSERT_EQ_INT(3, list_length(list), "length");
    ASSERT_EQ_INT(10, list_get_int(list, 1), "[1]");
    ASSERT_EQ_INT(20, list_get_int(list, 2), "[2]");
    ASSERT_EQ_INT(30, list_get_int(list, 3), "[3]");

    /* Insert at position 1 (prepend) */
    list_insert_int(list, 1, 5);
    ASSERT_EQ_INT(4, list_length(list), "length after prepend");
    ASSERT_EQ_INT(5, list_get_int(list, 1), "[1] after prepend");

    /* Insert beyond end (append) */
    list_insert_int(list, 100, 99);
    ASSERT_EQ_INT(5, list_length(list), "length after append");
    ASSERT_EQ_INT(99, list_get_int(list, 5), "[5] after append");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Shift (remove first)                                                */
/* ========================================================================= */

static void test_shift_int(void) {
    TEST("list_shift_int — remove first element");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);

    int64_t v1 = list_shift_int(list);
    ASSERT_EQ_INT(10, v1, "shifted value 1");
    ASSERT_EQ_INT(2, list_length(list), "length after shift");
    ASSERT_EQ_INT(20, list_head_int(list), "new head");

    int64_t v2 = list_shift_int(list);
    ASSERT_EQ_INT(20, v2, "shifted value 2");

    int64_t v3 = list_shift_int(list);
    ASSERT_EQ_INT(30, v3, "shifted value 3");
    ASSERT_EQ_INT(0, list_length(list), "empty after all shifts");
    ASSERT_EQ_INT(1, list_empty(list), "is empty");

    /* Shift from empty list */
    int64_t v4 = list_shift_int(list);
    ASSERT_EQ_INT(0, v4, "shift from empty = 0");

    list_free(list);
    PASS();
}

static void test_shift_type(void) {
    TEST("list_shift_type — peek at first element type");

    ListHeader* list = list_create();
    list_append_int(list, 42);
    list_append_float(list, 3.14);

    ASSERT_EQ_INT(ATOM_INT, list_shift_type(list), "first type = INT");
    list_shift(list); /* discard first */
    ASSERT_EQ_INT(ATOM_FLOAT, list_shift_type(list), "second type = FLOAT");
    list_shift(list);
    ASSERT_EQ_INT(ATOM_SENTINEL, list_shift_type(list), "empty type = SENTINEL");

    list_free(list);
    PASS();
}

static void test_shift_ptr(void) {
    TEST("list_shift_ptr — shift string transfers ownership");

    ListHeader* list = list_create();
    StringDescriptor* s = string_new_ascii("transferred");
    list_append_string(list, s);
    /* s refcount is now 2 (original + list) */
    string_release(s); /* drop our ref — list owns it */

    /* Shift returns the pointer, transfers ownership to caller */
    void* ptr = list_shift_ptr(list);
    ASSERT_NOT_NULL(ptr, "shifted ptr");
    StringDescriptor* got = (StringDescriptor*)ptr;
    ASSERT_STR_EQ("transferred", string_to_utf8(got), "value");
    ASSERT_EQ_INT(0, list_length(list), "empty after shift");

    /* We now own the string — release it */
    string_release(got);

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Pop (remove last)                                                   */
/* ========================================================================= */

static void test_pop_int(void) {
    TEST("list_pop_int — remove last element");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);

    int64_t v = list_pop_int(list);
    ASSERT_EQ_INT(30, v, "popped value");
    ASSERT_EQ_INT(2, list_length(list), "length after pop");

    v = list_pop_int(list);
    ASSERT_EQ_INT(20, v, "popped 2");

    v = list_pop_int(list);
    ASSERT_EQ_INT(10, v, "popped 3");

    ASSERT_EQ_INT(1, list_empty(list), "empty after all pops");

    /* Pop from empty */
    v = list_pop_int(list);
    ASSERT_EQ_INT(0, v, "pop from empty = 0");

    list_free(list);
    PASS();
}

static void test_pop_single_element(void) {
    TEST("list_pop — single element list");

    ListHeader* list = list_create();
    list_append_int(list, 42);

    int64_t v = list_pop_int(list);
    ASSERT_EQ_INT(42, v, "popped single");
    ASSERT_EQ_INT(1, list_empty(list), "empty");
    ASSERT_NULL(list->head, "head is NULL");
    ASSERT_NULL(list->tail, "tail is NULL");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Remove (positional)                                                 */
/* ========================================================================= */

static void test_remove_middle(void) {
    TEST("list_remove — remove from middle");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);
    list_append_int(list, 40);

    /* Remove position 2 (value 20) */
    list_remove(list, 2);
    ASSERT_EQ_INT(3, list_length(list), "length");
    ASSERT_EQ_INT(10, list_get_int(list, 1), "[1]");
    ASSERT_EQ_INT(30, list_get_int(list, 2), "[2]");
    ASSERT_EQ_INT(40, list_get_int(list, 3), "[3]");

    /* Remove first */
    list_remove(list, 1);
    ASSERT_EQ_INT(2, list_length(list), "length after remove first");
    ASSERT_EQ_INT(30, list_get_int(list, 1), "new first");

    /* Remove last */
    list_remove(list, 2);
    ASSERT_EQ_INT(1, list_length(list), "length after remove last");
    ASSERT_EQ_INT(30, list_get_int(list, 1), "remaining");

    /* Out of range — should be no-op */
    list_remove(list, 0);
    list_remove(list, 5);
    ASSERT_EQ_INT(1, list_length(list), "no-op for out of range");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Clear                                                               */
/* ========================================================================= */

static void test_clear(void) {
    TEST("list_clear — remove all elements");

    ListHeader* list = list_create();
    list_append_int(list, 1);
    list_append_int(list, 2);
    list_append_int(list, 3);

    list_clear(list);
    ASSERT_EQ_INT(0, list_length(list), "length after clear");
    ASSERT_EQ_INT(1, list_empty(list), "empty after clear");
    ASSERT_NULL(list->head, "head NULL");
    ASSERT_NULL(list->tail, "tail NULL");

    /* Can still append after clear */
    list_append_int(list, 99);
    ASSERT_EQ_INT(1, list_length(list), "length after re-append");
    ASSERT_EQ_INT(99, list_get_int(list, 1), "value after re-append");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Head access                                                         */
/* ========================================================================= */

static void test_head(void) {
    TEST("list_head_* — first element access");

    ListHeader* list = list_create();

    /* Empty list */
    ASSERT_EQ_INT(0, list_head_int(list), "head int empty");
    ASSERT_EQ_DOUBLE(0.0, list_head_float(list), "head float empty");
    ASSERT_NULL(list_head_ptr(list), "head ptr empty");
    ASSERT_EQ_INT(ATOM_SENTINEL, list_head_type(list), "head type empty");

    list_append_int(list, 42);
    ASSERT_EQ_INT(42, list_head_int(list), "head int");
    ASSERT_EQ_INT(ATOM_INT, list_head_type(list), "head type = INT");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Get (out of bounds)                                                 */
/* ========================================================================= */

static void test_get_out_of_bounds(void) {
    TEST("list_get_* — out of bounds returns zero/NULL");

    ListHeader* list = list_create();
    list_append_int(list, 42);

    ASSERT_EQ_INT(0, list_get_int(list, 0), "pos 0");
    ASSERT_EQ_INT(0, list_get_int(list, 2), "pos 2 (past end)");
    ASSERT_EQ_INT(0, list_get_int(list, -1), "pos -1");
    ASSERT_EQ_INT(ATOM_SENTINEL, list_get_type(list, 0), "type at 0");
    ASSERT_NULL(list_get_ptr(list, 5), "ptr at 5");

    /* NULL list */
    ASSERT_EQ_INT(0, list_get_int(NULL, 1), "NULL list");
    ASSERT_EQ_INT(0, list_length(NULL), "NULL length");
    ASSERT_EQ_INT(1, list_empty(NULL), "NULL empty");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Iteration                                                           */
/* ========================================================================= */

static void test_iteration(void) {
    TEST("list_iter_* — cursor-based iteration");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_float(list, 2.5);
    StringDescriptor* s = string_new_ascii("three");
    list_append_string(list, s);
    string_release(s);

    ListAtom* cursor = list_iter_begin(list);
    ASSERT_NOT_NULL(cursor, "begin not NULL");

    /* Element 1: INT 10 */
    ASSERT_EQ_INT(ATOM_INT, list_iter_type(cursor), "iter type 1");
    ASSERT_EQ_INT(10, list_iter_value_int(cursor), "iter value 1");

    /* Element 2: FLOAT 2.5 */
    cursor = list_iter_next(cursor);
    ASSERT_NOT_NULL(cursor, "cursor 2");
    ASSERT_EQ_INT(ATOM_FLOAT, list_iter_type(cursor), "iter type 2");
    ASSERT_EQ_DOUBLE(2.5, list_iter_value_float(cursor), "iter value 2");

    /* Element 3: STRING "three" */
    cursor = list_iter_next(cursor);
    ASSERT_NOT_NULL(cursor, "cursor 3");
    ASSERT_EQ_INT(ATOM_STRING, list_iter_type(cursor), "iter type 3");
    StringDescriptor* iterStr = (StringDescriptor*)list_iter_value_ptr(cursor);
    ASSERT_NOT_NULL(iterStr, "iter ptr 3");
    ASSERT_STR_EQ("three", string_to_utf8(iterStr), "iter value 3");

    /* End of list */
    cursor = list_iter_next(cursor);
    ASSERT_NULL(cursor, "end of iteration");

    /* Empty list */
    ListHeader* empty = list_create();
    ASSERT_NULL(list_iter_begin(empty), "begin on empty");
    list_free(empty);

    list_free(list);
    PASS();
}

static void test_iteration_count(void) {
    TEST("list_iter — count matches length");

    ListHeader* list = list_create();
    for (int i = 0; i < 100; i++) {
        list_append_int(list, i);
    }

    int count = 0;
    ListAtom* cursor = list_iter_begin(list);
    while (cursor) {
        count++;
        cursor = list_iter_next(cursor);
    }

    ASSERT_EQ_INT(100, count, "iteration count");
    ASSERT_EQ_INT(100, list_length(list), "length matches");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Copy                                                                */
/* ========================================================================= */

static void test_copy(void) {
    TEST("list_copy — deep copy");

    ListHeader* original = list_create();
    list_append_int(original, 10);
    list_append_float(original, 2.5);
    StringDescriptor* s = string_new_ascii("copied");
    list_append_string(original, s);
    string_release(s);

    ListHeader* copy = list_copy(original);
    ASSERT_NOT_NULL(copy, "copy not NULL");
    ASSERT_EQ_INT(3, list_length(copy), "copy length");

    /* Values match */
    ASSERT_EQ_INT(10, list_get_int(copy, 1), "copy[1]");
    ASSERT_EQ_DOUBLE(2.5, list_get_float(copy, 2), "copy[2]");
    StringDescriptor* copyStr = (StringDescriptor*)list_get_ptr(copy, 3);
    ASSERT_STR_EQ("copied", string_to_utf8(copyStr), "copy[3]");

    /* Modify original — copy should not change */
    list_append_int(original, 99);
    ASSERT_EQ_INT(4, list_length(original), "original modified");
    ASSERT_EQ_INT(3, list_length(copy), "copy unchanged");

    /* Copy of NULL */
    ListHeader* nullCopy = list_copy(NULL);
    ASSERT_NOT_NULL(nullCopy, "copy(NULL) returns empty list");
    ASSERT_EQ_INT(0, list_length(nullCopy), "copy(NULL) length = 0");
    list_free(nullCopy);

    list_free(original);
    list_free(copy);
    PASS();
}

static void test_copy_nested(void) {
    TEST("list_copy — deep copy of nested lists");

    ListHeader* outer = list_create();
    ListHeader* inner = list_create();
    list_append_int(inner, 100);
    list_append_int(inner, 200);
    list_append_list(outer, inner);
    list_append_int(outer, 42);

    ListHeader* copy = list_copy(outer);
    ASSERT_EQ_INT(2, list_length(copy), "copy length");

    /* The nested list in the copy should be a separate copy */
    ListHeader* copiedInner = (ListHeader*)list_get_ptr(copy, 1);
    ASSERT_NOT_NULL(copiedInner, "copied inner");
    ASSERT_EQ_INT(2, list_length(copiedInner), "copied inner length");
    ASSERT_EQ_INT(100, list_get_int(copiedInner, 1), "copied inner[1]");

    /* Modify original inner — copy should be independent */
    list_append_int(inner, 300);
    ASSERT_EQ_INT(3, list_length(inner), "original inner modified");
    ASSERT_EQ_INT(2, list_length(copiedInner), "copied inner unchanged");

    list_free(outer);
    list_free(copy);
    PASS();
}

/* ========================================================================= */
/* Tests: Rest                                                                */
/* ========================================================================= */

static void test_rest(void) {
    TEST("list_rest — all but first");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);

    ListHeader* rest = list_rest(list);
    ASSERT_EQ_INT(2, list_length(rest), "rest length");
    ASSERT_EQ_INT(20, list_get_int(rest, 1), "rest[1]");
    ASSERT_EQ_INT(30, list_get_int(rest, 2), "rest[2]");

    /* Original unchanged */
    ASSERT_EQ_INT(3, list_length(list), "original length unchanged");

    /* Rest of empty list */
    ListHeader* empty = list_create();
    ListHeader* emptyRest = list_rest(empty);
    ASSERT_EQ_INT(0, list_length(emptyRest), "rest of empty = empty");
    list_free(empty);
    list_free(emptyRest);

    /* Rest of single element list */
    ListHeader* single = list_create();
    list_append_int(single, 42);
    ListHeader* singleRest = list_rest(single);
    ASSERT_EQ_INT(0, list_length(singleRest), "rest of single = empty");
    list_free(single);
    list_free(singleRest);

    list_free(list);
    list_free(rest);
    PASS();
}

/* ========================================================================= */
/* Tests: Reverse                                                             */
/* ========================================================================= */

static void test_reverse(void) {
    TEST("list_reverse — reversed copy");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);

    ListHeader* rev = list_reverse(list);
    ASSERT_EQ_INT(3, list_length(rev), "rev length");
    ASSERT_EQ_INT(30, list_get_int(rev, 1), "rev[1]");
    ASSERT_EQ_INT(20, list_get_int(rev, 2), "rev[2]");
    ASSERT_EQ_INT(10, list_get_int(rev, 3), "rev[3]");

    /* Original unchanged */
    ASSERT_EQ_INT(10, list_get_int(list, 1), "original[1]");

    /* Reverse of empty */
    ListHeader* empty = list_create();
    ListHeader* emptyRev = list_reverse(empty);
    ASSERT_EQ_INT(0, list_length(emptyRev), "reverse of empty");
    list_free(empty);
    list_free(emptyRev);

    list_free(list);
    list_free(rev);
    PASS();
}

/* ========================================================================= */
/* Tests: Contains                                                            */
/* ========================================================================= */

static void test_contains(void) {
    TEST("list_contains_* — search for values");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_float(list, 3.14);
    StringDescriptor* s = string_new_ascii("hello");
    list_append_string(list, s);

    /* Contains int */
    ASSERT_EQ_INT(1, list_contains_int(list, 10), "contains 10");
    ASSERT_EQ_INT(1, list_contains_int(list, 20), "contains 20");
    ASSERT_EQ_INT(0, list_contains_int(list, 99), "not contains 99");

    /* Contains float */
    ASSERT_EQ_INT(1, list_contains_float(list, 3.14), "contains 3.14");
    ASSERT_EQ_INT(0, list_contains_float(list, 2.71), "not contains 2.71");

    /* Contains string */
    ASSERT_EQ_INT(1, list_contains_string(list, s), "contains 'hello'");
    StringDescriptor* other = string_new_ascii("goodbye");
    ASSERT_EQ_INT(0, list_contains_string(list, other), "not contains 'goodbye'");

    /* Contains string by value (not pointer) */
    StringDescriptor* hello2 = string_new_ascii("hello");
    ASSERT_EQ_INT(1, list_contains_string(list, hello2), "contains 'hello' by value");
    string_release(hello2);
    string_release(other);

    /* NULL list */
    ASSERT_EQ_INT(0, list_contains_int(NULL, 10), "NULL list");

    string_release(s);
    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: IndexOf                                                             */
/* ========================================================================= */

static void test_indexof(void) {
    TEST("list_indexof_* — find position (1-based)");

    ListHeader* list = list_create();
    list_append_int(list, 10);
    list_append_int(list, 20);
    list_append_int(list, 30);
    list_append_float(list, 2.5);

    ASSERT_EQ_INT(1, list_indexof_int(list, 10), "indexof 10");
    ASSERT_EQ_INT(2, list_indexof_int(list, 20), "indexof 20");
    ASSERT_EQ_INT(3, list_indexof_int(list, 30), "indexof 30");
    ASSERT_EQ_INT(0, list_indexof_int(list, 99), "indexof 99 (not found)");

    ASSERT_EQ_INT(4, list_indexof_float(list, 2.5), "indexof 2.5");
    ASSERT_EQ_INT(0, list_indexof_float(list, 9.9), "indexof 9.9 (not found)");

    /* String indexof */
    ListHeader* strList = list_create();
    StringDescriptor* s1 = string_new_ascii("alpha");
    StringDescriptor* s2 = string_new_ascii("beta");
    StringDescriptor* s3 = string_new_ascii("gamma");
    list_append_string(strList, s1);
    list_append_string(strList, s2);
    list_append_string(strList, s3);

    ASSERT_EQ_INT(1, list_indexof_string(strList, s1), "indexof alpha");
    ASSERT_EQ_INT(2, list_indexof_string(strList, s2), "indexof beta");
    ASSERT_EQ_INT(3, list_indexof_string(strList, s3), "indexof gamma");

    /* Search by value, not pointer identity */
    StringDescriptor* betaCopy = string_new_ascii("beta");
    ASSERT_EQ_INT(2, list_indexof_string(strList, betaCopy), "indexof beta by value");
    string_release(betaCopy);

    StringDescriptor* notFound = string_new_ascii("delta");
    ASSERT_EQ_INT(0, list_indexof_string(strList, notFound), "indexof delta (not found)");
    string_release(notFound);

    string_release(s1);
    string_release(s2);
    string_release(s3);
    list_free(strList);
    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Extend                                                              */
/* ========================================================================= */

static void test_extend(void) {
    TEST("list_extend — append all from another list");

    ListHeader* dest = list_create();
    list_append_int(dest, 1);
    list_append_int(dest, 2);

    ListHeader* src = list_create();
    list_append_int(src, 3);
    list_append_int(src, 4);
    list_append_int(src, 5);

    list_extend(dest, src);

    ASSERT_EQ_INT(5, list_length(dest), "dest length");
    ASSERT_EQ_INT(1, list_get_int(dest, 1), "dest[1]");
    ASSERT_EQ_INT(2, list_get_int(dest, 2), "dest[2]");
    ASSERT_EQ_INT(3, list_get_int(dest, 3), "dest[3]");
    ASSERT_EQ_INT(4, list_get_int(dest, 4), "dest[4]");
    ASSERT_EQ_INT(5, list_get_int(dest, 5), "dest[5]");

    /* Source unchanged */
    ASSERT_EQ_INT(3, list_length(src), "src unchanged");

    list_free(dest);
    list_free(src);
    PASS();
}

/* ========================================================================= */
/* Tests: Join                                                                */
/* ========================================================================= */

static void test_join(void) {
    TEST("list_join — join elements with separator");

    ListHeader* list = list_create();
    StringDescriptor* s1 = string_new_ascii("hello");
    StringDescriptor* s2 = string_new_ascii("world");
    list_append_string(list, s1);
    list_append_string(list, s2);
    string_release(s1);
    string_release(s2);

    StringDescriptor* sep = string_new_ascii(", ");
    StringDescriptor* result = list_join(list, sep);
    ASSERT_NOT_NULL(result, "join result");
    ASSERT_STR_EQ("hello, world", string_to_utf8(result), "join value");
    string_release(result);
    string_release(sep);

    list_free(list);
    PASS();
}

static void test_join_mixed(void) {
    TEST("list_join — mixed types");

    ListHeader* list = list_create();
    list_append_int(list, 42);
    StringDescriptor* s = string_new_ascii("hello");
    list_append_string(list, s);
    string_release(s);
    list_append_float(list, 3.14);

    StringDescriptor* sep = string_new_ascii(" | ");
    StringDescriptor* result = list_join(list, sep);
    ASSERT_NOT_NULL(result, "join result");

    /* The exact format depends on atom_value_to_cstr, but should contain all values */
    const char* str = string_to_utf8(result);
    ASSERT_NOT_NULL(str, "join string");
    /* Check that all parts are present */
    ASSERT_EQ_INT(1, (strstr(str, "42") != NULL), "contains 42");
    ASSERT_EQ_INT(1, (strstr(str, "hello") != NULL), "contains hello");
    ASSERT_EQ_INT(1, (strstr(str, "3.14") != NULL), "contains 3.14");
    ASSERT_EQ_INT(1, (strstr(str, " | ") != NULL), "contains separator");

    string_release(result);
    string_release(sep);
    list_free(list);
    PASS();
}

static void test_join_empty(void) {
    TEST("list_join — empty list");

    ListHeader* list = list_create();
    StringDescriptor* sep = string_new_ascii(", ");
    StringDescriptor* result = list_join(list, sep);
    ASSERT_NOT_NULL(result, "join result");
    ASSERT_EQ_INT(0, string_length(result), "empty join = empty string");

    string_release(result);
    string_release(sep);
    list_free(list);
    PASS();
}

static void test_join_single(void) {
    TEST("list_join — single element (no separator)");

    ListHeader* list = list_create();
    list_append_int(list, 42);
    StringDescriptor* sep = string_new_ascii(", ");
    StringDescriptor* result = list_join(list, sep);
    ASSERT_NOT_NULL(result, "join result");
    ASSERT_STR_EQ("42", string_to_utf8(result), "single element join");

    string_release(result);
    string_release(sep);
    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: list_is_header utility                                              */
/* ========================================================================= */

static void test_is_header(void) {
    TEST("list_is_header — distinguish header from atom");

    ListHeader* list = list_create();
    list_append_int(list, 42);

    ASSERT_EQ_INT(1, list_is_header(list), "header is header");
    ASSERT_EQ_INT(0, list_is_header(list->head), "atom is not header");
    ASSERT_EQ_INT(0, list_is_header(NULL), "NULL is not header");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Edge cases                                                          */
/* ========================================================================= */

static void test_null_safety(void) {
    TEST("NULL safety — all functions handle NULL gracefully");

    /* These should all be no-ops or return defaults */
    list_append_int(NULL, 42);
    list_prepend_int(NULL, 42);
    list_insert_int(NULL, 1, 42);
    list_extend(NULL, NULL);
    list_shift(NULL);
    list_pop(NULL);
    list_remove(NULL, 1);
    list_clear(NULL);
    list_free(NULL);

    ASSERT_EQ_INT(0, list_shift_int(NULL), "shift_int NULL");
    ASSERT_EQ_DOUBLE(0.0, list_shift_float(NULL), "shift_float NULL");
    ASSERT_NULL(list_shift_ptr(NULL), "shift_ptr NULL");
    ASSERT_EQ_INT(ATOM_SENTINEL, list_shift_type(NULL), "shift_type NULL");

    ASSERT_EQ_INT(0, list_pop_int(NULL), "pop_int NULL");
    ASSERT_EQ_DOUBLE(0.0, list_pop_float(NULL), "pop_float NULL");
    ASSERT_NULL(list_pop_ptr(NULL), "pop_ptr NULL");

    ASSERT_NULL(list_iter_begin(NULL), "iter_begin NULL");
    ASSERT_NULL(list_iter_next(NULL), "iter_next NULL");
    ASSERT_EQ_INT(ATOM_SENTINEL, list_iter_type(NULL), "iter_type NULL");
    ASSERT_EQ_INT(0, list_iter_value_int(NULL), "iter_value_int NULL");

    PASS();
}

static void test_large_list(void) {
    TEST("large list — 10000 elements");

    ListHeader* list = list_create();
    for (int i = 0; i < 10000; i++) {
        list_append_int(list, i);
    }

    ASSERT_EQ_INT(10000, list_length(list), "length");
    ASSERT_EQ_INT(0, list_get_int(list, 1), "first");
    ASSERT_EQ_INT(9999, list_get_int(list, 10000), "last");
    ASSERT_EQ_INT(5000, list_get_int(list, 5001), "middle");

    /* Contains and indexof on large list */
    ASSERT_EQ_INT(1, list_contains_int(list, 7777), "contains 7777");
    ASSERT_EQ_INT(0, list_contains_int(list, 10001), "not contains 10001");
    ASSERT_EQ_INT(7778, list_indexof_int(list, 7777), "indexof 7777");

    list_free(list);
    PASS();
}

static void test_append_null_string(void) {
    TEST("list_append_string — NULL string descriptor");

    ListHeader* list = list_create();
    list_append_string(list, NULL);

    ASSERT_EQ_INT(1, list_length(list), "length");
    ASSERT_EQ_INT(ATOM_STRING, list_get_type(list, 1), "type = STRING");
    ASSERT_NULL(list_get_ptr(list, 1), "value = NULL");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: SAMM cleanup path                                                   */
/* ========================================================================= */

static void test_samm_cleanup_functions(void) {
    TEST("list_free_from_samm / list_atom_free_from_samm");

    /* Test list_free_from_samm — should free header only */
    ListHeader* h = (ListHeader*)malloc(sizeof(ListHeader));
    h->type = ATOM_SENTINEL;
    h->flags = 0;
    h->length = 0;
    h->head = NULL;
    h->tail = NULL;
    list_free_from_samm(h);
    /* If we get here without crash, it worked */

    /* Test list_atom_free_from_samm with INT atom */
    ListAtom* atom = (ListAtom*)malloc(sizeof(ListAtom));
    atom->type = ATOM_INT;
    atom->pad = 0;
    atom->value.int_value = 42;
    atom->next = NULL;
    list_atom_free_from_samm(atom);

    /* Test list_atom_free_from_samm with STRING atom */
    ListAtom* strAtom = (ListAtom*)malloc(sizeof(ListAtom));
    strAtom->type = ATOM_STRING;
    strAtom->pad = 0;
    StringDescriptor* sd = string_new_ascii("samm_test");
    string_retain(sd); /* Simulate what list_append_string does */
    strAtom->value.ptr_value = sd;
    strAtom->next = NULL;
    string_release(sd); /* Drop our original ref */
    list_atom_free_from_samm(strAtom); /* Should release the string */

    /* NULL safety */
    list_free_from_samm(NULL);
    list_atom_free_from_samm(NULL);

    PASS();
}

/* ========================================================================= */
/* Tests: Debug print (visual verification)                                   */
/* ========================================================================= */

static void test_debug_print(void) {
    TEST("list_debug_print — visual verification");

    ListHeader* list = list_create();
    list_append_int(list, 42);
    list_append_float(list, 3.14);
    StringDescriptor* s = string_new_ascii("hello");
    list_append_string(list, s);
    string_release(s);

    ListHeader* inner = list_create();
    list_append_int(inner, 100);
    list_append_list(list, inner);

    fprintf(stderr, "\n--- Debug print output (visual check) ---\n");
    list_debug_print(list);
    list_debug_print(NULL);
    ListHeader* empty = list_create();
    list_debug_print(empty);
    list_free(empty);
    fprintf(stderr, "--- End debug print ---\n");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Stack and Queue patterns                                            */
/* ========================================================================= */

static void test_stack_pattern(void) {
    TEST("stack pattern — LIFO with append/pop");

    ListHeader* stack = list_create();
    list_append_int(stack, 1);
    list_append_int(stack, 2);
    list_append_int(stack, 3);

    ASSERT_EQ_INT(3, list_pop_int(stack), "pop 1 (LIFO)");
    ASSERT_EQ_INT(2, list_pop_int(stack), "pop 2");
    ASSERT_EQ_INT(1, list_pop_int(stack), "pop 3");
    ASSERT_EQ_INT(1, list_empty(stack), "empty after all pops");

    list_free(stack);
    PASS();
}

static void test_queue_pattern(void) {
    TEST("queue pattern — FIFO with append/shift");

    ListHeader* queue = list_create();
    list_append_int(queue, 1);
    list_append_int(queue, 2);
    list_append_int(queue, 3);

    ASSERT_EQ_INT(1, list_shift_int(queue), "shift 1 (FIFO)");
    ASSERT_EQ_INT(2, list_shift_int(queue), "shift 2");
    ASSERT_EQ_INT(3, list_shift_int(queue), "shift 3");
    ASSERT_EQ_INT(1, list_empty(queue), "empty");

    list_free(queue);
    PASS();
}

/* ========================================================================= */
/* Tests: Head/tail consistency                                               */
/* ========================================================================= */

static void test_head_tail_consistency(void) {
    TEST("head/tail consistency through operations");

    ListHeader* list = list_create();

    /* Empty: both NULL */
    ASSERT_NULL(list->head, "empty head");
    ASSERT_NULL(list->tail, "empty tail");

    /* One element: head == tail */
    list_append_int(list, 10);
    ASSERT_NOT_NULL(list->head, "head after 1 append");
    ASSERT_EQ_INT(1, (list->head == list->tail), "head == tail for 1 elem");

    /* Two elements: head != tail, head->next == tail */
    list_append_int(list, 20);
    ASSERT_EQ_INT(0, (list->head == list->tail), "head != tail for 2 elem");
    ASSERT_EQ_INT(1, (list->head->next == list->tail), "head->next == tail");
    ASSERT_NULL(list->tail->next, "tail->next == NULL");

    /* Pop back to one element */
    list_pop(list);
    ASSERT_EQ_INT(1, (list->head == list->tail), "head == tail after pop to 1");
    ASSERT_NULL(list->head->next, "single elem next == NULL");

    /* Pop to empty */
    list_pop(list);
    ASSERT_NULL(list->head, "head NULL after pop to empty");
    ASSERT_NULL(list->tail, "tail NULL after pop to empty");
    ASSERT_EQ_INT(0, list->length, "length 0");

    /* Shift pattern */
    list_append_int(list, 1);
    list_append_int(list, 2);
    list_shift(list);
    ASSERT_EQ_INT(1, (list->head == list->tail), "head == tail after shift to 1");
    list_shift(list);
    ASSERT_NULL(list->head, "head NULL after shift to empty");
    ASSERT_NULL(list->tail, "tail NULL after shift to empty");

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: Mixed prepend and append                                            */
/* ========================================================================= */

static void test_mixed_prepend_append(void) {
    TEST("mixed prepend/append ordering");

    ListHeader* list = list_create();
    list_append_int(list, 3);    /* [3] */
    list_prepend_int(list, 1);   /* [1, 3] */
    list_insert_int(list, 2, 2); /* [1, 2, 3] */
    list_append_int(list, 4);    /* [1, 2, 3, 4] */
    list_prepend_int(list, 0);   /* [0, 1, 2, 3, 4] */

    ASSERT_EQ_INT(5, list_length(list), "length");
    for (int i = 0; i < 5; i++) {
        ASSERT_EQ_INT(i, list_get_int(list, i + 1), "element");
    }

    list_free(list);
    PASS();
}

/* ========================================================================= */
/* Tests: String cleanup on list_free                                         */
/* ========================================================================= */

static void test_string_cleanup_on_free(void) {
    TEST("string refcount drops to 0 on list_free");

    StringDescriptor* s = string_new_ascii("watch_me");
    int initial_refcount = s->refcount;
    ASSERT_EQ_INT(1, initial_refcount, "initial refcount = 1");

    ListHeader* list = list_create();
    list_append_string(list, s);
    ASSERT_EQ_INT(2, s->refcount, "refcount after append = 2");

    string_release(s); /* Drop our reference — list owns it now */
    /* s still valid because list holds a reference (refcount = 1) */

    /* Freeing the list should release the last reference */
    list_free(list);

    /* We can't safely check s->refcount here because it's been freed.
     * If we get here without a crash or ASAN error, the cleanup worked. */
    PASS();
}

/* ========================================================================= */
/* Main                                                                       */
/* ========================================================================= */

int main(int argc, char** argv) {
    (void)argc;
    (void)argv;

    /* Initialize SAMM (but don't enable it for these tests — we want
     * to test list_ops in isolation with manual memory management) */
    samm_init();

    fprintf(stderr, "\n");
    fprintf(stderr, "╔══════════════════════════════════════════════════════════╗\n");
    fprintf(stderr, "║      FasterBASIC LIST Runtime Test Suite (Phase 1)      ║\n");
    fprintf(stderr, "╚══════════════════════════════════════════════════════════╝\n\n");

    /* Creation */
    fprintf(stderr, "--- Creation ---\n");
    test_create_empty();
    test_create_typed();

    /* Append */
    fprintf(stderr, "\n--- Append ---\n");
    test_append_int();
    test_append_float();
    test_append_string();
    test_append_nested_list();
    test_append_mixed();
    test_append_null_string();

    /* Prepend */
    fprintf(stderr, "\n--- Prepend ---\n");
    test_prepend_int();
    test_prepend_string();

    /* Insert */
    fprintf(stderr, "\n--- Insert ---\n");
    test_insert_int();

    /* Shift */
    fprintf(stderr, "\n--- Shift ---\n");
    test_shift_int();
    test_shift_type();
    test_shift_ptr();

    /* Pop */
    fprintf(stderr, "\n--- Pop ---\n");
    test_pop_int();
    test_pop_single_element();

    /* Remove */
    fprintf(stderr, "\n--- Remove ---\n");
    test_remove_middle();

    /* Clear */
    fprintf(stderr, "\n--- Clear ---\n");
    test_clear();

    /* Access */
    fprintf(stderr, "\n--- Access ---\n");
    test_head();
    test_get_out_of_bounds();

    /* Iteration */
    fprintf(stderr, "\n--- Iteration ---\n");
    test_iteration();
    test_iteration_count();

    /* Copy */
    fprintf(stderr, "\n--- Copy ---\n");
    test_copy();
    test_copy_nested();

    /* Rest */
    fprintf(stderr, "\n--- Rest ---\n");
    test_rest();

    /* Reverse */
    fprintf(stderr, "\n--- Reverse ---\n");
    test_reverse();

    /* Contains */
    fprintf(stderr, "\n--- Contains ---\n");
    test_contains();

    /* IndexOf */
    fprintf(stderr, "\n--- IndexOf ---\n");
    test_indexof();

    /* Extend */
    fprintf(stderr, "\n--- Extend ---\n");
    test_extend();

    /* Join */
    fprintf(stderr, "\n--- Join ---\n");
    test_join();
    test_join_mixed();
    test_join_empty();
    test_join_single();

    /* Utility */
    fprintf(stderr, "\n--- Utility ---\n");
    test_is_header();

    /* Patterns */
    fprintf(stderr, "\n--- Usage Patterns ---\n");
    test_stack_pattern();
    test_queue_pattern();

    /* Consistency */
    fprintf(stderr, "\n--- Consistency ---\n");
    test_head_tail_consistency();
    test_mixed_prepend_append();
    test_string_cleanup_on_free();

    /* Edge cases */
    fprintf(stderr, "\n--- Edge Cases ---\n");
    test_null_safety();
    test_large_list();

    /* SAMM cleanup */
    fprintf(stderr, "\n--- SAMM Cleanup Path ---\n");
    test_samm_cleanup_functions();

    /* Debug print (visual) */
    fprintf(stderr, "\n--- Debug ---\n");
    test_debug_print();

    /* Summary */
    fprintf(stderr, "\n");
    fprintf(stderr, "══════════════════════════════════════════════════════════\n");
    fprintf(stderr, "  Results: %d tests run, %d passed, %d failed\n",
            tests_run, tests_passed, tests_failed);
    fprintf(stderr, "══════════════════════════════════════════════════════════\n\n");

    samm_shutdown();

    if (tests_failed > 0) {
        fprintf(stderr, "  *** FAILURES DETECTED ***\n\n");
        return 1;
    }

    fprintf(stderr, "  All tests passed! ✓\n\n");
    return 0;
}