/*
 * test_simple_dump.c
 * Simple test that creates a hashmap and dumps it using debug functions
 * This mimics what the BASIC code would do
 */

#include <stdio.h>
#include <stdlib.h>
#include "hashmap.h"

// External debug functions
extern void hashmap_dump_state(void* map);
extern void hashmap_dump_summary(void* map);
extern void hashmap_dump_contents(void* map);
extern void hashmap_compare(void* map1, void* map2);
extern int hashmap_validate(void* map);
extern void basic_print_pointer(void* ptr);

int main() {
    printf("========================================\n");
    printf("Simple Hashmap Dump Test\n");
    printf("========================================\n\n");

    // Step 1: Create first hashmap
    printf("Step 1: Creating map1...\n");
    void* map1 = hashmap_new(16);
    printf("  map1 pointer: ");
    basic_print_pointer(map1);
    printf("\n");
    hashmap_dump_summary(map1);
    printf("\n");

    // Step 2: Insert Alice into map1
    printf("Step 2: Inserting Alice into map1...\n");
    hashmap_insert(map1, "Alice", "Engineer");
    printf("  After insert:\n");
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    printf("\n");

    // Step 3: Insert Bob into map1
    printf("Step 3: Inserting Bob into map1...\n");
    hashmap_insert(map1, "Bob", "Designer");
    printf("  After insert:\n");
    hashmap_dump_summary(map1);
    hashmap_dump_contents(map1);
    printf("\n");

    // Step 4: Full dump of map1
    printf("Step 4: Full state dump of map1\n");
    hashmap_dump_state(map1);
    printf("\n");

    // Step 5: Create second hashmap
    printf("Step 5: Creating map2...\n");
    void* map2 = hashmap_new(16);
    printf("  map2 pointer: ");
    basic_print_pointer(map2);
    printf("\n");
    hashmap_dump_summary(map2);
    printf("\n");

    // Step 6: Insert Charlie into map2
    printf("Step 6: Inserting Charlie into map2...\n");
    hashmap_insert(map2, "Charlie", "Manager");
    printf("  After insert:\n");
    hashmap_dump_summary(map2);
    hashmap_dump_contents(map2);
    printf("\n");

    // Step 7: Insert David into map2
    printf("Step 7: Inserting David into map2...\n");
    hashmap_insert(map2, "David", "Developer");
    printf("  After insert:\n");
    hashmap_dump_summary(map2);
    hashmap_dump_contents(map2);
    printf("\n");

    // Step 8: Compare the two hashmaps
    printf("Step 8: Comparing map1 and map2\n");
    hashmap_compare(map1, map2);
    printf("\n");

    // Step 9: Full dump of both
    printf("Step 9: Full dump of map1\n");
    hashmap_dump_state(map1);
    printf("\n");

    printf("Step 10: Full dump of map2\n");
    hashmap_dump_state(map2);
    printf("\n");

    // Step 11: Verify they have correct contents
    printf("Step 11: Verify lookups\n");
    printf("  map1[Alice] = %s\n", (char*)hashmap_lookup(map1, "Alice"));
    printf("  map1[Bob] = %s\n", (char*)hashmap_lookup(map1, "Bob"));
    printf("  map2[Charlie] = %s\n", (char*)hashmap_lookup(map2, "Charlie"));
    printf("  map2[David] = %s\n", (char*)hashmap_lookup(map2, "David"));
    printf("\n");

    // Step 12: Validate both
    printf("Step 12: Validate both hashmaps\n");
    int valid1 = hashmap_validate(map1);
    int valid2 = hashmap_validate(map2);
    printf("\n");

    if (valid1 && valid2) {
        printf("✓ Both hashmaps are valid\n");
    } else {
        printf("✗ One or both hashmaps have issues\n");
    }

    // Cleanup
    printf("\nCleaning up...\n");
    hashmap_free(map1);
    hashmap_free(map2);

    printf("\n========================================\n");
    printf("Test complete!\n");
    printf("========================================\n");

    return 0;
}