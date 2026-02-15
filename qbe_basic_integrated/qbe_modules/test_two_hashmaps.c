/* Test two hashmaps with Alice and Bob in each
 * This reproduces the exact pattern from the BASIC hang
 */

#include <stdio.h>
#include <stdlib.h>
#include "hashmap.h"

int main() {
    printf("Creating first hashmap (contacts)...\n");
    void* contacts = hashmap_new(16);
    if (!contacts) {
        fprintf(stderr, "Failed to create contacts hashmap\n");
        return 1;
    }
    
    printf("Inserting Alice into contacts...\n");
    int result = hashmap_insert(contacts, "Alice", "alice@example.com");
    if (!result) {
        fprintf(stderr, "Failed to insert Alice into contacts\n");
        return 1;
    }
    
    printf("Inserting Bob into contacts...\n");
    result = hashmap_insert(contacts, "Bob", "bob@example.com");
    if (!result) {
        fprintf(stderr, "Failed to insert Bob into contacts\n");
        return 1;
    }
    
    printf("First hashmap complete!\n");
    
    printf("\nCreating second hashmap (scores)...\n");
    void* scores = hashmap_new(16);
    if (!scores) {
        fprintf(stderr, "Failed to create scores hashmap\n");
        return 1;
    }
    
    printf("Inserting Alice into scores...\n");
    result = hashmap_insert(scores, "Alice", "95");
    if (!result) {
        fprintf(stderr, "Failed to insert Alice into scores\n");
        return 1;
    }
    
    printf("Inserting Bob into scores...\n");
    fflush(stdout);  // Ensure output is visible before potential hang
    result = hashmap_insert(scores, "Bob", "87");
    if (!result) {
        fprintf(stderr, "Failed to insert Bob into scores\n");
        return 1;
    }
    
    printf("Second hashmap complete!\n");
    
    printf("\n✓ Both hashmaps created successfully!\n");
    
    // Verify lookups
    const char* alice_contact = hashmap_lookup(contacts, "Alice");
    const char* bob_contact = hashmap_lookup(contacts, "Bob");
    const char* alice_score = hashmap_lookup(scores, "Alice");
    const char* bob_score = hashmap_lookup(scores, "Bob");
    
    printf("\nVerification:\n");
    printf("  contacts[Alice] = %s\n", alice_contact ? alice_contact : "NULL");
    printf("  contacts[Bob] = %s\n", bob_contact ? bob_contact : "NULL");
    printf("  scores[Alice] = %s\n", alice_score ? alice_score : "NULL");
    printf("  scores[Bob] = %s\n", bob_score ? bob_score : "NULL");
    
    // Clean up
    hashmap_free(contacts);
    hashmap_free(scores);
    
    return 0;
}