/*
 * hashmap.h
 * C interface for QBE hashmap core module
 *
 * This header provides declarations for the hand-coded QBE hashmap
 * implementation, allowing C code to interact with the hashmap runtime.
 */

#ifndef QBE_HASHMAP_H
#define QBE_HASHMAP_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Opaque HashMap Type
// =============================================================================

/*
 * HashMap structure (opaque to users)
 * Internal layout (32 bytes):
 *   offset 0:  int64_t capacity     - number of slots allocated
 *   offset 8:  int64_t size         - number of entries in use
 *   offset 16: void*   entries      - pointer to entry array
 *   offset 24: int64_t tombstones   - number of tombstone markers
 */
typedef struct HashMap HashMap;

// =============================================================================
// Hash Functions
// =============================================================================

/*
 * Hash a null-terminated C string using FNV-1a algorithm
 * Returns 32-bit hash value
 */
uint32_t hashmap_hash_string(const char* key_str);

/*
 * Hash a byte buffer using FNV-1a algorithm
 * Returns 32-bit hash value
 */
uint32_t hashmap_hash_bytes(const void* data, size_t len);

/*
 * Hash an integer (identity hash with mixing)
 * Returns 32-bit hash value
 */
uint32_t hashmap_hash_int(int64_t value);

// =============================================================================
// HashMap Core Functions
// =============================================================================

/*
 * Create a new hashmap with initial capacity
 * Returns pointer to HashMap, or NULL on allocation failure
 *
 * initial_capacity: Suggested initial capacity (will use minimum of 16)
 */
HashMap* hashmap_new(uint32_t initial_capacity);

/*
 * Free a hashmap and all its internal structures
 * Note: Does not free keys or values; caller must manage those
 */
void hashmap_free(HashMap* map);

/*
 * Insert or update a key-value pair in the hashmap
 * Returns 1 on success, 0 on failure
 *
 * map:   The hashmap
 * key:   Null-terminated string key (will be copied)
 * value: Pointer to value (stored as-is, not copied)
 *
 * If the key already exists, its value is updated.
 */
int32_t hashmap_insert(HashMap* map, const char* key, void* value);

/*
 * Lookup a value by key
 * Returns pointer to value, or NULL if not found
 *
 * map: The hashmap
 * key: Null-terminated string key
 */
void* hashmap_lookup(HashMap* map, const char* key);

/*
 * Check if a key exists in the hashmap
 * Returns 1 if key exists, 0 otherwise
 */
int32_t hashmap_has_key(HashMap* map, const char* key);

/*
 * Remove a key from the hashmap
 * Returns 1 if removed, 0 if not found
 *
 * Note: Does not free the key or value; caller must manage those
 */
int32_t hashmap_remove(HashMap* map, const char* key);

/*
 * Get the number of entries in the hashmap
 * Returns the size
 */
int64_t hashmap_size(HashMap* map);

/*
 * Clear all entries from the hashmap
 * Resets size to 0 but keeps capacity
 *
 * Note: Does not free keys or values; caller must manage those
 */
void hashmap_clear(HashMap* map);

/*
 * Get all keys from the hashmap as an array
 * Returns pointer to array of (char*) pointers, terminated by NULL
 * Caller must free the returned array (but not the individual keys)
 *
 * Example:
 *   char** keys = (char**)hashmap_keys(map);
 *   if (keys) {
 *       for (int i = 0; keys[i] != NULL; i++) {
 *           printf("Key: %s\n", keys[i]);
 *       }
 *       free(keys);
 *   }
 */
void** hashmap_keys(HashMap* map);

// =============================================================================
// Constants
// =============================================================================

#define HASHMAP_MIN_CAPACITY 16
#define HASHMAP_LOAD_FACTOR_NUM 7
#define HASHMAP_LOAD_FACTOR_DEN 10

// =============================================================================
// Memory Management Notes
// =============================================================================

/*
 * Memory Management Rules:
 * 
 * 1. Keys are COPIED (via strdup) when inserted, so the caller can free
 *    their key string after insertion.
 * 
 * 2. Values are stored as POINTERS ONLY. The hashmap does not copy or
 *    manage value memory. The caller is responsible for:
 *    - Allocating values before insertion
 *    - Keeping values alive while in the hashmap
 *    - Freeing values after removal or before hashmap_free()
 * 
 * 3. The hashmap_keys() function returns a dynamically allocated array
 *    that the caller must free. The keys themselves are owned by the
 *    hashmap and should not be freed by the caller.
 * 
 * 4. When calling hashmap_free(), the caller should first iterate and
 *    free all values if necessary.
 * 
 * Thread Safety:
 * 
 * This hashmap implementation is NOT thread-safe. If used from multiple
 * threads, access must be protected by external synchronization (mutexes,
 * CRITICAL SECTION in FasterBASIC, etc.).
 */

// =============================================================================
// Integration with FasterBASIC Runtime
// =============================================================================

/*
 * For integration with FasterBASIC's reference-counted runtime:
 * 
 * 1. Values stored in the hashmap should be BasicString*, BasicArray*,
 *    or other reference-counted types.
 * 
 * 2. When inserting a value, increment its reference count.
 * 
 * 3. When removing a value or freeing the hashmap, decrement reference
 *    counts appropriately.
 * 
 * 4. The code generator will emit calls to these functions and wrap them
 *    with appropriate reference counting logic.
 */

#ifdef __cplusplus
}
#endif

#endif /* QBE_HASHMAP_H */