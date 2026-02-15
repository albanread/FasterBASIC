/*
 * test_bug_hunt.c
 * Detailed step-by-step test to find exactly where the bug occurs
 * Inspects entries pointer at every step
 */

#include <stdio.h>
#include <stdlib.h>
#include "hashmap.h"

// External QBE helper functions
extern int64_t hashmap_load_capacity(void* map);
extern int64_t hashmap_load_size(void* map);
extern void* hashmap_load_entries(void* map);
extern void* hashmap_get_entry_at_index(void* entries, uint32_t index);
extern uint32_t hashmap_load_entry_state(void* entry);
extern void* hashmap_load_entry_key(void* entry);
extern void* hashmap_load_entry_value(void* entry);
extern uint32_t hashmap_load_entry_hash(void* entry);

void print_map_state(const char* label, void* map) {
    if (map == NULL) {
        printf("%s: NULL\n", label);
        return;
    }
    
    int64_t capacity = hashmap_load_capacity(map);
    int64_t size = hashmap_load_size(map);
    void* entries = hashmap_load_entries(map);
    
    printf("%s @ %p: size=%lld, cap=%lld, entries=%p\n", 
           label, map, size, capacity, entries);
}

void print_occupied_entries(void* map) {
    if (map == NULL) return;
    
    int64_t capacity = hashmap_load_capacity(map);
    void* entries = hashmap_load_entries(map);
    
    printf("  Occupied slots:\n");
    int count = 0;
    for (int i = 0; i < capacity; i++) {
        void* entry = hashmap_get_entry_at_index(entries, i);
        uint32_t state = hashmap_load_entry_state(entry);
        
        if (state == 1) {  // OCCUPIED
            void* key = hashmap_load_entry_key(entry);
            void* value = hashmap_load_entry_value(entry);
            printf("    [%d] key=%p (\"%s\"), value=%p\n", 
                   i, key, key ? (char*)key : "NULL", value);
            count++;
        }
    }
    if (count == 0) {
        printf("    (none)\n");
    }
}

int main() {
    printf("========================================\n");
    printf("Bug Hunt: Detailed Step-by-Step Test\n");
    printf("========================================\n\n");

    // Step 1: Create map1
    printf("STEP 1: Create map1\n");
    printf("----------------------------------------\n");
    void* map1 = hashmap_new(16);
    print_map_state("map1", map1);
    print_occupied_entries(map1);
    printf("\n");

    // Step 2: Insert Alice into map1
    printf("STEP 2: Insert Alice into map1\n");
    printf("----------------------------------------\n");
    printf("Before insert:\n");
    print_map_state("map1", map1);
    
    int result = hashmap_insert(map1, "Alice", "Engineer");
    printf("Insert result: %d\n", result);
    
    printf("After insert:\n");
    print_map_state("map1", map1);
    print_occupied_entries(map1);
    printf("\n");

    // Step 3: Insert Bob into map1
    printf("STEP 3: Insert Bob into map1\n");
    printf("----------------------------------------\n");
    printf("Before insert:\n");
    print_map_state("map1", map1);
    
    result = hashmap_insert(map1, "Bob", "Designer");
    printf("Insert result: %d\n", result);
    
    printf("After insert:\n");
    print_map_state("map1", map1);
    print_occupied_entries(map1);
    printf("\n");

    // Step 4: Create map2
    printf("STEP 4: Create map2\n");
    printf("----------------------------------------\n");
    void* map2 = hashmap_new(16);
    print_map_state("map2", map2);
    print_occupied_entries(map2);
    
    printf("\nBoth maps:\n");
    print_map_state("map1", map1);
    print_map_state("map2", map2);
    
    void* entries1 = hashmap_load_entries(map1);
    void* entries2 = hashmap_load_entries(map2);
    if (entries1 == entries2) {
        printf("ERROR: Both maps share same entries array!\n");
    } else {
        printf("OK: Maps have different entries arrays\n");
    }
    printf("\n");

    // Step 5: Insert Charlie into map2
    printf("STEP 5: Insert Charlie into map2\n");
    printf("----------------------------------------\n");
    printf("Before insert:\n");
    print_map_state("map2", map2);
    print_map_state("map1", map1);
    
    result = hashmap_insert(map2, "Charlie", "Manager");
    printf("Insert result: %d\n", result);
    
    printf("After insert:\n");
    print_map_state("map2", map2);
    print_occupied_entries(map2);
    
    printf("map1 after map2 insert:\n");
    print_map_state("map1", map1);
    print_occupied_entries(map1);
    printf("\n");

    // Step 6: Insert David into map2
    printf("STEP 6: Insert David into map2\n");
    printf("----------------------------------------\n");
    printf("Before insert:\n");
    print_map_state("map2", map2);
    print_map_state("map1", map1);
    
    result = hashmap_insert(map2, "David", "Developer");
    printf("Insert result: %d\n", result);
    
    printf("After insert:\n");
    print_map_state("map2", map2);
    print_occupied_entries(map2);
    
    printf("map1 after map2 insert:\n");
    print_map_state("map1", map1);
    print_occupied_entries(map1);
    printf("\n");

    // Step 7: Verify lookups
    printf("STEP 7: Verify lookups\n");
    printf("----------------------------------------\n");
    void* alice = hashmap_lookup(map1, "Alice");
    void* bob = hashmap_lookup(map1, "Bob");
    void* charlie = hashmap_lookup(map2, "Charlie");
    void* david = hashmap_lookup(map2, "David");
    
    printf("map1[Alice] = %p (%s)\n", alice, alice ? (char*)alice : "NULL");
    printf("map1[Bob] = %p (%s)\n", bob, bob ? (char*)bob : "NULL");
    printf("map2[Charlie] = %p (%s)\n", charlie, charlie ? (char*)charlie : "NULL");
    printf("map2[David] = %p (%s)\n", david, david ? (char*)david : "NULL");
    printf("\n");

    // Step 8: Check for corruption
    printf("STEP 8: Final corruption check\n");
    printf("----------------------------------------\n");
    
    int64_t size1 = hashmap_load_size(map1);
    int64_t size2 = hashmap_load_size(map2);
    
    entries1 = hashmap_load_entries(map1);
    entries2 = hashmap_load_entries(map2);
    
    printf("map1: size=%lld, entries=%p\n", size1, entries1);
    printf("map2: size=%lld, entries=%p\n", size2, entries2);
    
    // Count actual occupied slots
    int occupied1 = 0, occupied2 = 0;
    for (int i = 0; i < 16; i++) {
        void* entry1 = hashmap_get_entry_at_index(entries1, i);
        if (hashmap_load_entry_state(entry1) == 1) occupied1++;
        
        void* entry2 = hashmap_get_entry_at_index(entries2, i);
        if (hashmap_load_entry_state(entry2) == 1) occupied2++;
    }
    
    printf("map1: reported_size=%lld, actual_occupied=%d\n", size1, occupied1);
    printf("map2: reported_size=%lld, actual_occupied=%d\n", size2, occupied2);
    
    if (size1 != occupied1) {
        printf("BUG: map1 size mismatch!\n");
    }
    if (size2 != occupied2) {
        printf("BUG: map2 size mismatch!\n");
    }
    
    printf("\n");

    // Cleanup
    hashmap_free(map1);
    hashmap_free(map2);

    printf("========================================\n");
    printf("Test complete!\n");
    printf("========================================\n");

    return 0;
}