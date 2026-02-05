/*
 * hashmap_debug.c
 * Comprehensive debugging and state inspection for QBE hashmap
 * 
 * This file provides functions to dump the complete internal state
 * of a hashmap, including all entries, capacity, size, tombstones,
 * and memory addresses. Useful for debugging from BASIC code.
 */

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include "hashmap.h"

// External QBE helper functions for low-level access
extern int64_t hashmap_load_capacity(void* map);
extern int64_t hashmap_load_size(void* map);
extern void* hashmap_load_entries(void* map);
extern int64_t hashmap_load_tombstones(void* map);
extern void* hashmap_get_entry_at_index(void* entries, uint32_t index);
extern uint32_t hashmap_load_entry_state(void* entry);
extern void* hashmap_load_entry_key(void* entry);
extern void* hashmap_load_entry_value(void* entry);
extern uint32_t hashmap_load_entry_hash(void* entry);

/*
 * Print a pointer value in hex format (helper for BASIC)
 */
void basic_print_pointer(void* ptr) {
    printf("0x%016lx", (unsigned long)ptr);
}

/*
 * Print a 64-bit integer in hex format (helper for BASIC)
 */
void basic_print_hex(int64_t value) {
    printf("0x%016lx", (unsigned long)value);
}

/*
 * Dump the complete state of a hashmap entry
 */
static void dump_entry(void* entry, int index) {
    uint32_t state = hashmap_load_entry_state(entry);
    
    printf("    [%3d] @ %p: ", index, entry);
    
    if (state == 0) {
        printf("EMPTY\n");
    } else if (state == 1) {
        void* key = hashmap_load_entry_key(entry);
        void* value = hashmap_load_entry_value(entry);
        uint32_t hash = hashmap_load_entry_hash(entry);
        
        printf("OCCUPIED\n");
        printf("          key:   %p", key);
        if (key != NULL) {
            // Try to print key string (careful with invalid pointers)
            printf(" \"%s\"", (char*)key);
        }
        printf("\n");
        printf("          value: %p", value);
        printf("\n");
        printf("          hash:  0x%08x (%u)\n", hash, hash);
    } else if (state == 2) {
        printf("TOMBSTONE\n");
    } else {
        printf("INVALID STATE (%u)\n", state);
    }
}

/*
 * Dump the complete state of a hashmap
 * 
 * This function prints:
 * - Hashmap pointer and structure addresses
 * - Capacity, size, tombstone count
 * - Entries array pointer
 * - Complete dump of all slots (occupied, empty, and tombstone)
 * - Summary statistics
 * 
 * map: pointer to HashMap structure
 */
void hashmap_dump_state(HashMap* map) {
    printf("\n");
    printf("================================================================================\n");
    printf("HASHMAP STATE DUMP\n");
    printf("================================================================================\n");
    
    if (map == NULL) {
        printf("ERROR: HashMap pointer is NULL\n");
        printf("================================================================================\n");
        return;
    }
    
    printf("HashMap structure address: %p\n", (void*)map);
    printf("\n");
    
    // Load hashmap fields
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    int64_t tombstones = hashmap_load_tombstones(map);
    void* entries = hashmap_load_entries(map);
    
    printf("Structure fields:\n");
    printf("  capacity (offset 0):   %ld (0x%lx)\n", capacity, capacity);
    printf("  size (offset 8):       %ld (0x%lx)\n", size, size);
    printf("  entries (offset 16):   %p\n", entries);
    printf("  tombstones (offset 24): %ld (0x%lx)\n", tombstones, tombstones);
    printf("\n");
    
    if (entries == NULL) {
        printf("ERROR: Entries array pointer is NULL\n");
        printf("================================================================================\n");
        return;
    }
    
    // Calculate statistics
    int empty_count = 0;
    int occupied_count = 0;
    int tombstone_count = 0;
    int invalid_count = 0;
    
    // First pass: count states
    for (int i = 0; i < capacity; i++) {
        void* entry = hashmap_get_entry_at_index(entries, i);
        uint32_t state = hashmap_load_entry_state(entry);
        
        switch (state) {
            case 0: empty_count++; break;
            case 1: occupied_count++; break;
            case 2: tombstone_count++; break;
            default: invalid_count++; break;
        }
    }
    
    printf("Statistics:\n");
    printf("  Total slots:    %ld\n", capacity);
    printf("  Occupied:       %d (%.1f%%)\n", occupied_count, 
           capacity > 0 ? (100.0 * occupied_count / capacity) : 0.0);
    printf("  Empty:          %d (%.1f%%)\n", empty_count,
           capacity > 0 ? (100.0 * empty_count / capacity) : 0.0);
    printf("  Tombstones:     %d (%.1f%%)\n", tombstone_count,
           capacity > 0 ? (100.0 * tombstone_count / capacity) : 0.0);
    printf("  Invalid:        %d\n", invalid_count);
    printf("\n");
    
    // Consistency checks
    printf("Consistency checks:\n");
    if (occupied_count == size) {
        printf("  ✓ occupied count matches size field\n");
    } else {
        printf("  ✗ MISMATCH: occupied=%d, size=%ld\n", occupied_count, size);
    }
    if (tombstone_count == tombstones) {
        printf("  ✓ tombstone count matches tombstones field\n");
    } else {
        printf("  ✗ MISMATCH: tombstone_count=%d, tombstones=%ld\n", 
               tombstone_count, tombstones);
    }
    printf("\n");
    
    printf("Entries array dump (capacity = %ld):\n", capacity);
    printf("--------------------------------------------------------------------------------\n");
    
    // Dump all entries
    for (int i = 0; i < capacity; i++) {
        void* entry = hashmap_get_entry_at_index(entries, i);
        dump_entry(entry, i);
    }
    
    printf("================================================================================\n");
    printf("END HASHMAP STATE DUMP\n");
    printf("================================================================================\n");
    printf("\n");
}

/*
 * Quick summary dump - just the key statistics
 */
void hashmap_dump_summary(HashMap* map) {
    if (map == NULL) {
        printf("HashMap: NULL\n");
        return;
    }
    
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    int64_t tombstones = hashmap_load_tombstones(map);
    void* entries = hashmap_load_entries(map);
    
    printf("HashMap @ %p: size=%ld, capacity=%ld, tombstones=%ld, entries=%p\n",
           (void*)map, size, capacity, tombstones, entries);
}

/*
 * Dump just the occupied entries (keys and values)
 */
void hashmap_dump_contents(HashMap* map) {
    if (map == NULL) {
        printf("HashMap: NULL\n");
        return;
    }
    
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    void* entries = hashmap_load_entries(map);
    
    printf("\nHashMap @ %p - Contents (%ld entries):\n", (void*)map, size);
    printf("----------------------------------------\n");
    
    if (size == 0) {
        printf("  (empty)\n");
    } else {
        for (int i = 0; i < capacity; i++) {
            void* entry = hashmap_get_entry_at_index(entries, i);
            uint32_t state = hashmap_load_entry_state(entry);
            
            if (state == 1) {  // OCCUPIED
                void* key = hashmap_load_entry_key(entry);
                void* value = hashmap_load_entry_value(entry);
                uint32_t hash = hashmap_load_entry_hash(entry);
                
                printf("  [%d] ", i);
                if (key != NULL) {
                    printf("\"%s\"", (char*)key);
                } else {
                    printf("(NULL key)");
                }
                printf(" => %p (hash=0x%08x)\n", value, hash);
            }
        }
    }
    printf("----------------------------------------\n\n");
}

/*
 * Compare two hashmaps and report differences
 */
void hashmap_compare(HashMap* map1, HashMap* map2) {
    printf("\n");
    printf("================================================================================\n");
    printf("HASHMAP COMPARISON\n");
    printf("================================================================================\n");
    
    printf("Map 1: %p\n", (void*)map1);
    printf("Map 2: %p\n", (void*)map2);
    printf("\n");
    
    if (map1 == NULL || map2 == NULL) {
        printf("ERROR: One or both maps are NULL\n");
        printf("================================================================================\n");
        return;
    }
    
    if (map1 == map2) {
        printf("WARNING: Both pointers refer to the same hashmap!\n");
        printf("================================================================================\n");
        return;
    }
    
    int64_t cap1 = hashmap_load_capacity(map1);
    int64_t cap2 = hashmap_load_capacity(map2);
    int64_t size1 = hashmap_load_size(map1);
    int64_t size2 = hashmap_load_size(map2);
    int64_t tomb1 = hashmap_load_tombstones(map1);
    int64_t tomb2 = hashmap_load_tombstones(map2);
    void* entries1 = hashmap_load_entries(map1);
    void* entries2 = hashmap_load_entries(map2);
    
    printf("Capacity:   %ld vs %ld %s\n", cap1, cap2, 
           cap1 == cap2 ? "✓" : "✗");
    printf("Size:       %ld vs %ld %s\n", size1, size2,
           size1 == size2 ? "✓" : "✗");
    printf("Tombstones: %ld vs %ld %s\n", tomb1, tomb2,
           tomb1 == tomb2 ? "✓" : "✗");
    printf("Entries:    %p vs %p %s\n", entries1, entries2,
           entries1 != entries2 ? "✓ (different arrays)" : "✗ (SAME ARRAY!)");
    
    if (entries1 == entries2) {
        printf("\nERROR: Both hashmaps share the same entries array!\n");
        printf("This is a critical bug - hashmaps must have independent storage.\n");
    }
    
    printf("================================================================================\n\n");
}

/*
 * Verify that a hashmap pointer looks valid
 * Returns 1 if it looks OK, 0 if suspicious
 */
int hashmap_validate(HashMap* map) {
    if (map == NULL) {
        printf("INVALID: HashMap pointer is NULL\n");
        return 0;
    }
    
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    int64_t tombstones = hashmap_load_tombstones(map);
    void* entries = hashmap_load_entries(map);
    
    int valid = 1;
    
    printf("Validating HashMap @ %p:\n", (void*)map);
    
    if (capacity < 16 || capacity > 1000000) {
        printf("  ✗ Suspicious capacity: %ld (expected 16-1000000)\n", capacity);
        valid = 0;
    } else {
        printf("  ✓ Capacity looks reasonable: %ld\n", capacity);
    }
    
    if (size < 0 || size > capacity) {
        printf("  ✗ Invalid size: %ld (capacity: %ld)\n", size, capacity);
        valid = 0;
    } else {
        printf("  ✓ Size is valid: %ld\n", size);
    }
    
    if (tombstones < 0 || tombstones > capacity) {
        printf("  ✗ Invalid tombstones: %ld (capacity: %ld)\n", tombstones, capacity);
        valid = 0;
    } else {
        printf("  ✓ Tombstones is valid: %ld\n", tombstones);
    }
    
    if (entries == NULL) {
        printf("  ✗ Entries pointer is NULL\n");
        valid = 0;
    } else {
        printf("  ✓ Entries pointer: %p\n", entries);
    }
    
    if (valid) {
        printf("  Overall: ✓ HashMap looks valid\n");
    } else {
        printf("  Overall: ✗ HashMap has problems\n");
    }
    
    return valid;
}

/*
 * Simple wrapper to call from BASIC - prints hashmap summary
 */
void debug_print_hashmap(void* map) {
    hashmap_dump_summary((HashMap*)map);
}

/*
 * Wrapper for full state dump callable from BASIC
 */
void debug_dump_hashmap_full(void* map) {
    hashmap_dump_state((HashMap*)map);
}

/*
 * Wrapper for contents dump callable from BASIC
 */
void debug_dump_hashmap_contents(void* map) {
    hashmap_dump_contents((HashMap*)map);
}

/*
 * Wrapper for validation callable from BASIC
 */
int debug_validate_hashmap(void* map) {
    return hashmap_validate((HashMap*)map);
}

/*
 * Wrapper for comparison callable from BASIC
 */
void debug_compare_hashmaps(void* map1, void* map2) {
    hashmap_compare((HashMap*)map1, (HashMap*)map2);
}

/*
 * Simple one-line status print for quick debugging from BASIC
 * Prints: "MAP@addr: sz=N cap=M tomb=T ent=addr"
 */
void debug_quick_status(void* map) {
    if (map == NULL) {
        printf("MAP: NULL\n");
        return;
    }
    
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    int64_t tombstones = hashmap_load_tombstones(map);
    void* entries = hashmap_load_entries(map);
    
    printf("MAP@%p: sz=%lld cap=%lld tomb=%lld ent=%p\n",
           map, size, capacity, tombstones, entries);
}

/*
 * Print just the entries array pointer for a map
 */
void debug_print_entries_ptr(void* map) {
    if (map == NULL) {
        printf("NULL\n");
        return;
    }
    void* entries = hashmap_load_entries(map);
    printf("%p\n", entries);
}

/*
 * Check if two maps share the same entries array (BUG!)
 */
int debug_check_shared_entries(void* map1, void* map2) {
    if (map1 == NULL || map2 == NULL) {
        printf("One or both maps are NULL\n");
        return 0;
    }
    
    void* entries1 = hashmap_load_entries(map1);
    void* entries2 = hashmap_load_entries(map2);
    
    printf("Map1 entries: %p\n", entries1);
    printf("Map2 entries: %p\n", entries2);
    
    if (entries1 == entries2) {
        printf("ERROR: Maps share the same entries array!\n");
        return 1;
    } else {
        printf("OK: Maps have different entries arrays\n");
        return 0;
    }
}