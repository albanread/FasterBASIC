/*
 * test_trace_insert.c
 * Call QBE internal functions directly to trace the bug
 * This will show us exactly which entries pointer is being used
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
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
extern void hashmap_store_entry(void* entry, void* key, void* value, uint32_t hash, uint32_t state);
extern uint32_t hashmap_hash_string(const char* str);
extern uint32_t hashmap_compute_index(uint32_t hash, uint32_t capacity);
extern void* hashmap_find_slot_simple(void* map, const char* key, uint32_t hash, uint32_t for_insert);
extern void hashmap_increment_size(void* map);

void trace_map_state(const char* label, void* map) {
    printf("  %s:\n", label);
    printf("    map ptr:     %p\n", map);
    printf("    capacity:    %lld\n", hashmap_load_capacity(map));
    printf("    size:        %lld\n", hashmap_load_size(map));
    printf("    entries ptr: %p\n", hashmap_load_entries(map));
}

int main() {
    printf("========================================\n");
    printf("Trace Insert: Manual Step-by-Step\n");
    printf("========================================\n\n");

    // Create map1
    printf("Creating map1...\n");
    void* map1 = hashmap_new(16);
    trace_map_state("map1", map1);
    printf("\n");

    // Manually insert Alice into map1
    printf("Manually inserting Alice into map1...\n");
    const char* key1 = "Alice";
    const char* val1 = "Engineer";
    
    uint32_t hash1 = hashmap_hash_string(key1);
    printf("  hash(Alice) = 0x%08x\n", hash1);
    
    uint32_t index1 = hashmap_compute_index(hash1, 16);
    printf("  index = %u\n", index1);
    
    void* entries1 = hashmap_load_entries(map1);
    printf("  entries ptr from map1: %p\n", entries1);
    
    void* slot1 = hashmap_find_slot_simple(map1, key1, hash1, 1);
    printf("  slot returned: %p\n", slot1);
    
    // Calculate expected slot address
    void* expected1 = hashmap_get_entry_at_index(entries1, index1);
    printf("  expected slot at index %u: %p\n", index1, expected1);
    
    if (slot1 == expected1) {
        printf("  ✓ Slot matches expected\n");
    } else {
        printf("  ✗ Slot MISMATCH!\n");
    }
    
    // Store the entry
    char* key1_copy = strdup(key1);
    hashmap_store_entry(slot1, key1_copy, (void*)val1, hash1, 1);
    hashmap_increment_size(map1);
    
    trace_map_state("map1 after Alice", map1);
    printf("\n");

    // Manually insert Bob into map1
    printf("Manually inserting Bob into map1...\n");
    const char* key2 = "Bob";
    const char* val2 = "Designer";
    
    uint32_t hash2 = hashmap_hash_string(key2);
    printf("  hash(Bob) = 0x%08x\n", hash2);
    
    uint32_t index2 = hashmap_compute_index(hash2, 16);
    printf("  index = %u\n", index2);
    
    printf("  BEFORE calling hashmap_load_entries:\n");
    printf("    map1 ptr = %p\n", map1);
    
    void* entries2 = hashmap_load_entries(map1);
    printf("  entries ptr from map1: %p\n", entries2);
    
    if (entries1 != entries2) {
        printf("  ✗ ERROR: entries pointer changed! Was %p, now %p\n", entries1, entries2);
    } else {
        printf("  ✓ entries pointer unchanged: %p\n", entries2);
    }
    
    printf("  BEFORE calling hashmap_find_slot_simple:\n");
    printf("    map1 ptr = %p\n", map1);
    printf("    key = %s\n", key2);
    printf("    hash = 0x%08x\n", hash2);
    
    void* slot2 = hashmap_find_slot_simple(map1, key2, hash2, 1);
    printf("  slot returned: %p\n", slot2);
    
    // Calculate expected slot address
    void* expected2 = hashmap_get_entry_at_index(entries2, index2);
    printf("  expected slot at index %u: %p\n", index2, expected2);
    
    if (slot2 == expected2) {
        printf("  ✓ Slot matches expected\n");
    } else {
        printf("  ✗ Slot MISMATCH!\n");
        printf("    Difference: %ld bytes\n", (char*)slot2 - (char*)expected2);
        
        // Check if it's pointing to map1's entries or somewhere else
        void* entries_start = entries2;
        void* entries_end = (char*)entries2 + (16 * 24);
        if (slot2 >= entries_start && slot2 < entries_end) {
            printf("    Slot IS within map1's entries array\n");
            // Calculate which index it's actually at
            int64_t offset = (char*)slot2 - (char*)entries2;
            int actual_index = offset / 24;
            printf("    Actual index: %ld (expected: %u)\n", actual_index, index2);
        } else {
            printf("    Slot is NOT within map1's entries array!\n");
        }
    }
    
    // Store the entry
    char* key2_copy = strdup(key2);
    hashmap_store_entry(slot2, key2_copy, (void*)val2, hash2, 1);
    hashmap_increment_size(map1);
    
    trace_map_state("map1 after Bob", map1);
    
    // Check what's actually in the entries array
    printf("\n  Scanning map1 entries array:\n");
    for (int i = 0; i < 16; i++) {
        void* entry = hashmap_get_entry_at_index(entries2, i);
        uint32_t state = hashmap_load_entry_state(entry);
        if (state == 1) {
            void* key = hashmap_load_entry_key(entry);
            printf("    [%d] @ %p: \"%s\"\n", i, entry, key ? (char*)key : "NULL");
        }
    }
    printf("\n");

    // Create map2
    printf("Creating map2...\n");
    void* map2 = hashmap_new(16);
    trace_map_state("map2", map2);
    
    printf("\n  Both maps:\n");
    trace_map_state("map1", map1);
    trace_map_state("map2", map2);
    printf("\n");

    // Manually insert Charlie into map2
    printf("Manually inserting Charlie into map2...\n");
    const char* key3 = "Charlie";
    const char* val3 = "Manager";
    
    uint32_t hash3 = hashmap_hash_string(key3);
    printf("  hash(Charlie) = 0x%08x\n", hash3);
    
    uint32_t index3 = hashmap_compute_index(hash3, 16);
    printf("  index = %u\n", index3);
    
    void* entries3 = hashmap_load_entries(map2);
    printf("  entries ptr from map2: %p\n", entries3);
    
    void* slot3 = hashmap_find_slot_simple(map2, key3, hash3, 1);
    printf("  slot returned: %p\n", slot3);
    
    void* expected3 = hashmap_get_entry_at_index(entries3, index3);
    printf("  expected slot at index %u: %p\n", index3, expected3);
    
    if (slot3 == expected3) {
        printf("  ✓ Slot matches expected\n");
    } else {
        printf("  ✗ Slot MISMATCH!\n");
    }
    
    char* key3_copy = strdup(key3);
    hashmap_store_entry(slot3, key3_copy, (void*)val3, hash3, 1);
    hashmap_increment_size(map2);
    
    trace_map_state("map2 after Charlie", map2);
    printf("\n");

    // Manually insert David into map2
    printf("Manually inserting David into map2...\n");
    const char* key4 = "David";
    const char* val4 = "Developer";
    
    uint32_t hash4 = hashmap_hash_string(key4);
    printf("  hash(David) = 0x%08x\n", hash4);
    
    uint32_t index4 = hashmap_compute_index(hash4, 16);
    printf("  index = %u\n", index4);
    
    printf("  BEFORE calling hashmap_load_entries:\n");
    printf("    map2 ptr = %p\n", map2);
    
    void* entries4 = hashmap_load_entries(map2);
    printf("  entries ptr from map2: %p\n", entries4);
    
    if (entries3 != entries4) {
        printf("  ✗ ERROR: entries pointer changed! Was %p, now %p\n", entries3, entries4);
    } else {
        printf("  ✓ entries pointer unchanged: %p\n", entries4);
    }
    
    printf("  BEFORE calling hashmap_find_slot_simple:\n");
    printf("    map2 ptr = %p\n", map2);
    
    void* slot4 = hashmap_find_slot_simple(map2, key4, hash4, 1);
    printf("  slot returned: %p\n", slot4);
    
    void* expected4 = hashmap_get_entry_at_index(entries4, index4);
    printf("  expected slot at index %u: %p\n", index4, expected4);
    
    if (slot4 == expected4) {
        printf("  ✓ Slot matches expected\n");
    } else {
        printf("  ✗ Slot MISMATCH!\n");
        
        // Check if it's in map2's array or map1's array
        void* map2_start = entries4;
        void* map2_end = (char*)entries4 + (16 * 24);
        void* map1_entries = hashmap_load_entries(map1);
        void* map1_start = map1_entries;
        void* map1_end = (char*)map1_entries + (16 * 24);
        
        if (slot4 >= map2_start && slot4 < map2_end) {
            printf("    Slot IS within map2's entries array\n");
            int64_t offset = (char*)slot4 - (char*)entries4;
            int actual_index = offset / 24;
            printf("    Actual index: %ld (expected: %u)\n", actual_index, index4);
        } else if (slot4 >= map1_start && slot4 < map1_end) {
            printf("    ✗✗✗ BUG: Slot is in MAP1's entries array!\n");
            int64_t offset = (char*)slot4 - (char*)map1_entries;
            int actual_index = offset / 24;
            printf("    Index in map1: %ld\n", actual_index);
        } else {
            printf("    Slot is in UNKNOWN memory!\n");
        }
    }
    
    char* key4_copy = strdup(key4);
    hashmap_store_entry(slot4, key4_copy, (void*)val4, hash4, 1);
    hashmap_increment_size(map2);
    
    trace_map_state("map2 after David", map2);
    
    printf("\n  Scanning map1 entries array after map2 insert:\n");
    void* map1_entries_final = hashmap_load_entries(map1);
    for (int i = 0; i < 16; i++) {
        void* entry = hashmap_get_entry_at_index(map1_entries_final, i);
        uint32_t state = hashmap_load_entry_state(entry);
        if (state == 1) {
            void* key = hashmap_load_entry_key(entry);
            printf("    [%d] @ %p: \"%s\"\n", i, entry, key ? (char*)key : "NULL");
        }
    }
    
    printf("\n  Scanning map2 entries array:\n");
    for (int i = 0; i < 16; i++) {
        void* entry = hashmap_get_entry_at_index(entries4, i);
        uint32_t state = hashmap_load_entry_state(entry);
        if (state == 1) {
            void* key = hashmap_load_entry_key(entry);
            printf("    [%d] @ %p: \"%s\"\n", i, entry, key ? (char*)key : "NULL");
        }
    }
    printf("\n");

    // Test lookups
    printf("Testing lookups...\n");
    void* alice_val = hashmap_lookup(map1, "Alice");
    void* bob_val = hashmap_lookup(map1, "Bob");
    void* charlie_val = hashmap_lookup(map2, "Charlie");
    void* david_val = hashmap_lookup(map2, "David");
    
    printf("  map1[Alice] = %s\n", alice_val ? (char*)alice_val : "NULL");
    printf("  map1[Bob] = %s\n", bob_val ? (char*)bob_val : "NULL");
    printf("  map2[Charlie] = %s\n", charlie_val ? (char*)charlie_val : "NULL");
    printf("  map2[David] = %s\n", david_val ? (char*)david_val : "NULL");

    // Cleanup
    hashmap_free(map1);
    hashmap_free(map2);

    printf("\n========================================\n");
    printf("Trace complete!\n");
    printf("========================================\n");

    return 0;
}