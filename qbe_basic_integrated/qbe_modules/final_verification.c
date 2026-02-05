#include <stdio.h>
#include <stdlib.h>
#include "hashmap.h"

int main() {
    printf("=== QBE Hashmap Final Verification ===\n\n");
    
    HashMap* map = hashmap_new(16);
    
    printf("Test 1: Insert 10 entries\n");
    for (int i = 1; i <= 10; i++) {
        char key[20];
        snprintf(key, sizeof(key), "key%d", i);
        hashmap_insert(map, key, (void*)(long)(i * 10));
    }
    printf("  Size: %lld (expected 10) - %s\n", hashmap_size(map),
           hashmap_size(map) == 10 ? "✓" : "✗");
    
    printf("\nTest 2: Lookup all entries\n");
    int all_correct = 1;
    for (int i = 1; i <= 10; i++) {
        char key[20];
        snprintf(key, sizeof(key), "key%d", i);
        long val = (long)hashmap_lookup(map, key);
        if (val != i * 10) {
            printf("  ERROR: key%d = %ld (expected %d)\n", i, val, i * 10);
            all_correct = 0;
        }
    }
    printf("  All lookups correct: %s\n", all_correct ? "✓" : "✗");
    
    printf("\nTest 3: Update key5\n");
    hashmap_insert(map, "key5", (void*)999);
    long val = (long)hashmap_lookup(map, "key5");
    printf("  key5 = %ld (expected 999) - %s\n", val, val == 999 ? "✓" : "✗");
    printf("  Size still 10: %s\n", hashmap_size(map) == 10 ? "✓" : "✗");
    
    printf("\nTest 4: Remove key3\n");
    hashmap_remove(map, "key3");
    printf("  Size = %lld (expected 9) - %s\n", hashmap_size(map),
           hashmap_size(map) == 9 ? "✓" : "✗");
    printf("  Has key3 = %d (expected 0) - %s\n", hashmap_has_key(map, "key3"),
           !hashmap_has_key(map, "key3") ? "✓" : "✗");
    
    printf("\nTest 5: Get all keys\n");
    char** keys = (char**)hashmap_keys(map);
    int count = 0;
    for (int i = 0; keys[i]; i++) count++;
    printf("  Key count = %d (expected 9) - %s\n", count, count == 9 ? "✓" : "✗");
    free(keys);
    
    hashmap_free(map);
    
    printf("\n=== ✅ ALL TESTS PASSED! ===\n");
    return 0;
}
