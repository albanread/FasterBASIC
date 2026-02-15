/*
 * test_debug.c
 * Test program for hashmap debug and state inspection functions
 * 
 * This program creates multiple hashmaps, populates them, and uses
 * the debug functions to inspect their internal state.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "hashmap.h"

// Debug function declarations
extern void hashmap_dump_state(void* map);
extern void hashmap_dump_summary(void* map);
extern void hashmap_dump_contents(void* map);
extern void hashmap_compare(void* map1, void* map2);
extern int hashmap_validate(void* map);
extern void basic_print_pointer(void* ptr);
extern void basic_print_hex(int64_t value);

int main() {
    printf("========================================\n");
    printf("Hashmap Debug Functions Test\n");
    printf("========================================\n\n");

    // Test 1: Create and dump an empty hashmap
    printf("TEST 1: Empty hashmap\n");
    printf("----------------------------------------\n");
    HashMap* map1 = hashmap_new(16);
    printf("Created map1: ");
    basic_print_pointer(map1);
    printf("\n");
    
    hashmap_validate(map1);
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    
    printf("\n");

    // Test 2: Add some entries and dump
    printf("TEST 2: Hashmap with entries\n");
    printf("----------------------------------------\n");
    hashmap_insert(map1, "Alice", "Engineer");
    hashmap_insert(map1, "Bob", "Designer");
    hashmap_insert(map1, "Charlie", "Manager");
    
    printf("After inserting 3 entries:\n");
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    
    printf("\n");

    // Test 3: Full state dump
    printf("TEST 3: Full state dump of map1\n");
    printf("----------------------------------------\n");
    hashmap_dump_state(map1);
    
    printf("\n");

    // Test 4: Create a second hashmap
    printf("TEST 4: Second hashmap\n");
    printf("----------------------------------------\n");
    HashMap* map2 = hashmap_new(16);
    printf("Created map2: ");
    basic_print_pointer(map2);
    printf("\n");
    
    hashmap_insert(map2, "David", "Developer");
    hashmap_insert(map2, "Eve", "Tester");
    
    printf("After inserting 2 entries:\n");
    hashmap_dump_summary(map2);
    hashmap_dump_contents(map2);
    
    printf("\n");

    // Test 5: Compare the two hashmaps
    printf("TEST 5: Compare two hashmaps\n");
    printf("----------------------------------------\n");
    hashmap_compare(map1, map2);
    
    printf("\n");

    // Test 6: Remove an entry and check tombstones
    printf("TEST 6: Remove entry and check tombstones\n");
    printf("----------------------------------------\n");
    printf("Before removal:\n");
    hashmap_dump_summary(map1);
    
    hashmap_remove(map1, "Bob");
    
    printf("\nAfter removing 'Bob':\n");
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    
    printf("\n");

    // Test 7: Trigger resize by adding many entries
    printf("TEST 7: Trigger resize\n");
    printf("----------------------------------------\n");
    printf("Before resize:\n");
    hashmap_dump_summary(map1);
    
    // Add many entries to trigger resize
    const char* names[] = {
        "Frank", "Grace", "Henry", "Iris", "Jack",
        "Kate", "Leo", "Mary", "Nick", "Olivia",
        "Paul", "Quinn", "Rose", "Sam", "Tina"
    };
    
    for (int i = 0; i < 15; i++) {
        hashmap_insert(map1, names[i], "Role");
    }
    
    printf("\nAfter adding 15 more entries (should trigger resize):\n");
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    
    printf("\n");

    // Test 8: Full dump of resized map
    printf("TEST 8: Full state dump after resize\n");
    printf("----------------------------------------\n");
    hashmap_dump_state(map1);
    
    printf("\n");

    // Test 9: Test with NULL pointer
    printf("TEST 9: NULL pointer handling\n");
    printf("----------------------------------------\n");
    hashmap_validate(NULL);
    hashmap_dump_summary(NULL);
    hashmap_dump_state(NULL);
    
    printf("\n");

    // Test 10: Validate both maps
    printf("TEST 10: Final validation\n");
    printf("----------------------------------------\n");
    printf("Validating map1:\n");
    int valid1 = hashmap_validate(map1);
    printf("\nValidating map2:\n");
    int valid2 = hashmap_validate(map2);
    
    printf("\n");
    if (valid1 && valid2) {
        printf("✓ Both hashmaps are valid\n");
    } else {
        printf("✗ One or more hashmaps have issues\n");
    }
    
    printf("\n");

    // Test 11: Print raw pointers
    printf("TEST 11: Raw pointer printing\n");
    printf("----------------------------------------\n");
    printf("map1 pointer: ");
    basic_print_pointer(map1);
    printf("\n");
    
    printf("map2 pointer: ");
    basic_print_pointer(map2);
    printf("\n");
    
    printf("Integer as hex: ");
    basic_print_hex(0x123456789ABCDEF0);
    printf("\n");
    
    printf("\n");

    // Cleanup
    printf("TEST 12: Cleanup\n");
    printf("----------------------------------------\n");
    printf("Freeing map1...\n");
    hashmap_free(map1);
    printf("Freeing map2...\n");
    hashmap_free(map2);
    printf("Cleanup complete.\n\n");

    // Final summary
    printf("========================================\n");
    printf("All debug function tests completed!\n");
    printf("========================================\n");

    return 0;
}