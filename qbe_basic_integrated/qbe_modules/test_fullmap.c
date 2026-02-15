#include <stdio.h>
#include "hashmap.h"

int main() {
    HashMap* map = hashmap_new(16);
    
    printf("Inserting apple=1, banana=2, cherry=3\n");
    hashmap_insert(map, "apple", (void*)1);
    hashmap_insert(map, "banana", (void*)2);
    hashmap_insert(map, "cherry", (void*)3);
    
    printf("Map size: %lld\n", hashmap_size(map));
    
    printf("\nLookups:\n");
    printf("  apple  -> %ld\n", (long)hashmap_lookup(map, "apple"));
    printf("  banana -> %ld\n", (long)hashmap_lookup(map, "banana"));
    printf("  cherry -> %ld\n", (long)hashmap_lookup(map, "cherry"));
    
    hashmap_free(map);
    printf("\nSUCCESS!\n");
    return 0;
}
