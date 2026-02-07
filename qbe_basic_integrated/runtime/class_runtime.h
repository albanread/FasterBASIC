/*
 * class_runtime.h
 * FasterBASIC CLASS & Object System Runtime
 *
 * Runtime support functions for the CLASS/OBJECT system:
 *   - Object allocation and deallocation
 *   - IS type-check operator (inheritance chain walking)
 *   - Null-reference error handlers
 *   - Debug utilities
 *
 * Object Memory Layout:
 *   [0]   vtable pointer  (8 bytes, ptr to class vtable data)
 *   [8]   class_id        (8 bytes, int64, unique per class)
 *   [16]  fields...       (inherited fields first, then own fields)
 *
 * VTable Layout:
 *   [0]   class_id            (8 bytes, int64)
 *   [8]   parent_vtable ptr   (8 bytes, 0 if root class)
 *   [16]  class_name ptr      (8 bytes, ptr to C string)
 *   [24]  destructor ptr      (8 bytes, 0 if none)
 *   [32]  method pointers...  (8 bytes each, in declaration order)
 */

#ifndef CLASS_RUNTIME_H
#define CLASS_RUNTIME_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ========================================================================= */
/* Constants                                                                  */
/* ========================================================================= */

/* Object header offsets */
#define CLASS_VTABLE_PTR_OFFSET     0
#define CLASS_ID_OFFSET             8
#define CLASS_HEADER_SIZE           16

/* VTable header offsets */
#define VTABLE_CLASS_ID_OFFSET      0
#define VTABLE_PARENT_PTR_OFFSET    8
#define VTABLE_NAME_PTR_OFFSET      16
#define VTABLE_DESTRUCTOR_OFFSET    24
#define VTABLE_METHODS_OFFSET       32

/* Reserved class IDs */
#define CLASS_ID_NOTHING            0
#define CLASS_ID_FIRST              1

/* ========================================================================= */
/* Object Allocation & Deallocation                                           */
/* ========================================================================= */

/**
 * Allocate a new object of the given size, install vtable and class_id.
 *
 * The object is zero-initialised (via calloc), so all fields start at
 * their default values: integers = 0, strings = NULL descriptor,
 * object references = NOTHING.
 *
 * @param object_size  Total object size in bytes (header + all fields)
 * @param vtable       Pointer to the class's statically-allocated vtable
 * @param class_id     Unique class identifier (>= CLASS_ID_FIRST)
 * @return Pointer to the newly allocated object (never NULL — aborts on OOM)
 */
void* class_object_new(int64_t object_size, void* vtable, int64_t class_id);

/**
 * Delete an object: call destructor (if present in vtable), free memory,
 * and set the caller's pointer to NULL (NOTHING).
 *
 * Safe to call on NULL — does nothing in that case.
 *
 * @param obj_ref  Pointer to the object-pointer variable (so we can set it to NULL)
 */
void class_object_delete(void** obj_ref);

/* ========================================================================= */
/* Type Checking (IS operator)                                                */
/* ========================================================================= */

/**
 * Runtime IS type check: walk the inheritance chain via parent_vtable pointers.
 *
 * Returns 1 if obj's class is target_class_id or a subclass of it.
 * Returns 0 if obj is NULL (NOTHING IS Anything → false).
 *
 * @param obj              Pointer to the object to check
 * @param target_class_id  The class_id to check against
 * @return 1 if the object is an instance of the target class (or subclass), 0 otherwise
 */
int32_t class_is_instance(void* obj, int64_t target_class_id);

/* ========================================================================= */
/* Null-Reference Error Handlers                                              */
/* ========================================================================= */

/**
 * Runtime error: method call on NOTHING reference.
 * Prints an error message including the source location and method name,
 * then calls exit(1).
 *
 * @param location     String describing the source location (e.g. "line 42")
 * @param method_name  Name of the method that was called
 */
void class_null_method_error(const char* location, const char* method_name);

/**
 * Runtime error: field access on NOTHING reference.
 * Prints an error message including the source location and field name,
 * then calls exit(1).
 *
 * @param location    String describing the source location (e.g. "line 42")
 * @param field_name  Name of the field that was accessed
 */
void class_null_field_error(const char* location, const char* field_name);

/* ========================================================================= */
/* Debug Utilities                                                            */
/* ========================================================================= */

/**
 * Print debug information about an object: class name, address, class_id.
 * Useful for debugging object-related issues.
 *
 * Safe to call on NULL — prints "[NOTHING]" in that case.
 *
 * @param obj  Pointer to the object (or NULL)
 */
void class_object_debug(void* obj);

#ifdef __cplusplus
}
#endif

#endif /* CLASS_RUNTIME_H */