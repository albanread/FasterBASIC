/*
 * test_helpers.c
 * Granular test suite for QBE hashmap helper functions
 * Tests each low-level function individually to isolate bugs
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>

// External declarations for QBE helper functions
extern uint32_t hashmap_compute_index(uint32_t hash, uint32_t capacity);
extern void* hashmap_get_entry_at_index(void* entries, uint32_t index);
extern uint32_t hashmap_load_entry_state(void* entry);
extern void* hashmap_load_entry_key(void* entry);
extern void* hashmap_load_entry_value(void* entry);
extern uint32_t hashmap_load_entry_hash(void* entry);
extern void hashmap_store_entry(void* entry, void* key, void* value, uint32_t hash, uint32_t state);
extern int hashmap_keys_equal(const char* key1, const char* key2);
extern uint32_t hashmap_hash_string(const char* str);
extern int64_t hashmap_load_capacity(void* map);
extern int64_t hashmap_load_size(void* map);
extern void* hashmap_load_entries(void* map);
extern void hashmap_store_size(void* map, int64_t size);
extern void hashmap_increment_size(void* map);

// Test counters
static int tests_run = 0;
static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) \
    static void test_##name(); \
    static void run_test_##name() { \
        printf("Test: %-40s ", #name); \
        fflush(stdout); \
        tests_run++; \
        test_##name(); \
        tests_passed++; \
        printf("PASS\n"); \
    } \
    static void test_##name()

#define ASSERT(condition, message) \
    do { \
        if (!(condition)) { \
            printf("FAIL\n"); \
            printf("  Assertion failed: %s\n", message); \
            printf("  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_EQ(actual, expected, message) \
    do { \
        if ((actual) != (expected)) { \
            printf("FAIL\n"); \
            printf("  %s\n", message); \
            printf("  Expected: %ld, Got: %ld\n", (long)(expected), (long)(actual)); \
            printf("  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

#define ASSERT_PTR_EQ(actual, expected, message) \
    do { \
        if ((actual) != (expected)) { \
            printf("FAIL\n"); \
            printf("  %s\n", message); \
            printf("  Expected: %p, Got: %p\n", (void*)(expected), (void*)(actual)); \
            printf("  at %s:%d\n", __FILE__, __LINE__); \
            tests_failed++; \
            return; \
        } \
    } while (0)

// =============================================================================
// Tests
// =============================================================================

TEST(compute_index_basic) {
    uint32_t index = hashmap_compute_index(280767167, 16);
    ASSERT_EQ(index, 15, "apple hash mod 16 should be 15");
    
    index = hashmap_compute_index(3649609552, 16);
    ASSERT_EQ(index, 0, "banana hash mod 16 should be 0");
    
    index = hashmap_compute_index(1232791672, 16);
    ASSERT_EQ(index, 8, "cherry hash mod 16 should be 8");
}

TEST(compute_index_different_capacities) {
    uint32_t index = hashmap_compute_index(100, 10);
    ASSERT_EQ(index, 0, "100 mod 10 should be 0");
    
    index = hashmap_compute_index(123, 10);
    ASSERT_EQ(index, 3, "123 mod 10 should be 3");
    
    index = hashmap_compute_index(1000, 16);
    ASSERT_EQ(index, 8, "1000 mod 16 should be 8");
}

TEST(get_entry_at_index) {
    // Create a fake entries array (4 entries of 24 bytes each)
    char entries[96];
    memset(entries, 0, sizeof(entries));
    
    void* entry0 = hashmap_get_entry_at_index(entries, 0);
    ASSERT_PTR_EQ(entry0, entries, "entry 0 should be at base");
    
    void* entry1 = hashmap_get_entry_at_index(entries, 1);
    ASSERT_PTR_EQ(entry1, entries + 24, "entry 1 should be at offset 24");
    
    void* entry2 = hashmap_get_entry_at_index(entries, 2);
    ASSERT_PTR_EQ(entry2, entries + 48, "entry 2 should be at offset 48");
    
    void* entry3 = hashmap_get_entry_at_index(entries, 3);
    ASSERT_PTR_EQ(entry3, entries + 72, "entry 3 should be at offset 72");
}

TEST(store_and_load_entry) {
    // Create an entry (24 bytes)
    char entry[24];
    memset(entry, 0, sizeof(entry));
    
    // Store data in entry
    char* test_key = "test_key";
    void* test_value = (void*)42;
    uint32_t test_hash = 12345;
    uint32_t test_state = 1; // OCCUPIED
    
    hashmap_store_entry(entry, test_key, test_value, test_hash, test_state);
    
    // Load data back
    void* loaded_key = hashmap_load_entry_key(entry);
    ASSERT_PTR_EQ(loaded_key, test_key, "loaded key should match");
    
    void* loaded_value = hashmap_load_entry_value(entry);
    ASSERT_PTR_EQ(loaded_value, test_value, "loaded value should match");
    
    uint32_t loaded_hash = hashmap_load_entry_hash(entry);
    ASSERT_EQ(loaded_hash, test_hash, "loaded hash should match");
    
    uint32_t loaded_state = hashmap_load_entry_state(entry);
    ASSERT_EQ(loaded_state, test_state, "loaded state should match");
}

TEST(store_multiple_entries) {
    // Create entries array (3 entries)
    char entries[72];
    memset(entries, 0, sizeof(entries));
    
    // Store different data in each entry
    hashmap_store_entry(entries + 0,  "key1", (void*)1, 100, 1);
    hashmap_store_entry(entries + 24, "key2", (void*)2, 200, 1);
    hashmap_store_entry(entries + 48, "key3", (void*)3, 300, 1);
    
    // Verify each entry independently
    void* entry0 = hashmap_get_entry_at_index(entries, 0);
    void* key0 = hashmap_load_entry_key(entry0);
    void* val0 = hashmap_load_entry_value(entry0);
    ASSERT_PTR_EQ(key0, "key1", "entry 0 key should be key1");
    ASSERT_EQ((long)val0, 1, "entry 0 value should be 1");
    
    void* entry1 = hashmap_get_entry_at_index(entries, 1);
    void* key1 = hashmap_load_entry_key(entry1);
    void* val1 = hashmap_load_entry_value(entry1);
    ASSERT_PTR_EQ(key1, "key2", "entry 1 key should be key2");
    ASSERT_EQ((long)val1, 2, "entry 1 value should be 2");
    
    void* entry2 = hashmap_get_entry_at_index(entries, 2);
    void* key2 = hashmap_load_entry_key(entry2);
    void* val2 = hashmap_load_entry_value(entry2);
    ASSERT_PTR_EQ(key2, "key3", "entry 2 key should be key3");
    ASSERT_EQ((long)val2, 3, "entry 2 value should be 3");
}

TEST(keys_equal) {
    int result = hashmap_keys_equal("hello", "hello");
    ASSERT_EQ(result, 1, "identical keys should be equal");
    
    result = hashmap_keys_equal("hello", "world");
    ASSERT_EQ(result, 0, "different keys should not be equal");
    
    result = hashmap_keys_equal("", "");
    ASSERT_EQ(result, 1, "empty strings should be equal");
    
    result = hashmap_keys_equal("test", "Test");
    ASSERT_EQ(result, 0, "case matters");
}

TEST(hash_string) {
    uint32_t h1 = hashmap_hash_string("apple");
    uint32_t h2 = hashmap_hash_string("banana");
    uint32_t h3 = hashmap_hash_string("cherry");
    
    // Verify they're different
    ASSERT(h1 != h2, "different strings should have different hashes");
    ASSERT(h2 != h3, "different strings should have different hashes");
    ASSERT(h1 != h3, "different strings should have different hashes");
    
    // Verify consistency
    uint32_t h1_again = hashmap_hash_string("apple");
    ASSERT_EQ(h1, h1_again, "same string should hash to same value");
}

TEST(map_structure_access) {
    // Create a fake map structure (32 bytes)
    char map[32];
    memset(map, 0, sizeof(map));
    
    // Set capacity at offset 0
    *(int64_t*)(&map[0]) = 16;
    int64_t cap = hashmap_load_capacity(map);
    ASSERT_EQ(cap, 16, "capacity should be 16");
    
    // Set size at offset 8
    *(int64_t*)(&map[8]) = 5;
    int64_t size = hashmap_load_size(map);
    ASSERT_EQ(size, 5, "size should be 5");
    
    // Set entries pointer at offset 16
    char entries[96];
    *(void**)(&map[16]) = entries;
    void* entries_ptr = hashmap_load_entries(map);
    ASSERT_PTR_EQ(entries_ptr, entries, "entries pointer should match");
}

TEST(store_and_increment_size) {
    char map[32];
    memset(map, 0, sizeof(map));
    
    // Initialize size to 0
    hashmap_store_size(map, 0);
    ASSERT_EQ(hashmap_load_size(map), 0, "initial size should be 0");
    
    // Increment size
    hashmap_increment_size(map);
    ASSERT_EQ(hashmap_load_size(map), 1, "size should be 1 after increment");
    
    hashmap_increment_size(map);
    ASSERT_EQ(hashmap_load_size(map), 2, "size should be 2 after second increment");
    
    // Store new size
    hashmap_store_size(map, 10);
    ASSERT_EQ(hashmap_load_size(map), 10, "size should be 10 after store");
}

TEST(entry_states) {
    char entry[24];
    
    // Test EMPTY state (0)
    memset(entry, 0, sizeof(entry));
    hashmap_store_entry(entry, "key", (void*)1, 100, 0);
    ASSERT_EQ(hashmap_load_entry_state(entry), 0, "state should be EMPTY (0)");
    
    // Test OCCUPIED state (1)
    hashmap_store_entry(entry, "key", (void*)1, 100, 1);
    ASSERT_EQ(hashmap_load_entry_state(entry), 1, "state should be OCCUPIED (1)");
    
    // Test TOMBSTONE state (2)
    hashmap_store_entry(entry, "key", (void*)1, 100, 2);
    ASSERT_EQ(hashmap_load_entry_state(entry), 2, "state should be TOMBSTONE (2)");
}

TEST(entry_value_types) {
    char entry[24];
    
    // Test with integer as pointer
    hashmap_store_entry(entry, "key", (void*)42, 100, 1);
    void* val = hashmap_load_entry_value(entry);
    ASSERT_EQ((long)val, 42, "integer value should work");
    
    // Test with actual pointer
    char* str = "hello";
    hashmap_store_entry(entry, "key", str, 100, 1);
    void* loaded = hashmap_load_entry_value(entry);
    ASSERT_PTR_EQ(loaded, str, "pointer value should work");
    
    // Test with NULL
    hashmap_store_entry(entry, "key", NULL, 100, 1);
    void* null_val = hashmap_load_entry_value(entry);
    ASSERT_PTR_EQ(null_val, NULL, "NULL value should work");
}

TEST(compute_index_edge_cases) {
    // Test with capacity 1
    uint32_t idx = hashmap_compute_index(0, 1);
    ASSERT_EQ(idx, 0, "any hash mod 1 should be 0");
    
    idx = hashmap_compute_index(100, 1);
    ASSERT_EQ(idx, 0, "any hash mod 1 should be 0");
    
    // Test with power of 2 capacities
    idx = hashmap_compute_index(17, 16);
    ASSERT_EQ(idx, 1, "17 mod 16 should be 1");
    
    idx = hashmap_compute_index(32, 16);
    ASSERT_EQ(idx, 0, "32 mod 16 should be 0");
}

TEST(hash_consistency) {
    // Same string should always hash to same value
    for (int i = 0; i < 10; i++) {
        uint32_t h1 = hashmap_hash_string("consistent");
        uint32_t h2 = hashmap_hash_string("consistent");
        ASSERT_EQ(h1, h2, "hash should be consistent");
    }
}

// =============================================================================
// Main
// =============================================================================

int main() {
    printf("========================================\n");
    printf("QBE Hashmap Helper Functions Test\n");
    printf("========================================\n\n");
    
    // Run all tests
    run_test_compute_index_basic();
    run_test_compute_index_different_capacities();
    run_test_get_entry_at_index();
    run_test_store_and_load_entry();
    run_test_store_multiple_entries();
    run_test_keys_equal();
    run_test_hash_string();
    run_test_map_structure_access();
    run_test_store_and_increment_size();
    run_test_entry_states();
    run_test_entry_value_types();
    run_test_compute_index_edge_cases();
    run_test_hash_consistency();
    
    // Print summary
    printf("\n========================================\n");
    printf("Test Summary\n");
    printf("========================================\n");
    printf("Tests run:    %d\n", tests_run);
    printf("Tests passed: %d\n", tests_passed);
    printf("Tests failed: %d\n", tests_failed);
    
    if (tests_failed == 0) {
        printf("\n✓ All helper tests passed!\n");
        return 0;
    } else {
        printf("\n✗ Some tests failed.\n");
        return 1;
    }
}