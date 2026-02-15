#include <stdio.h>
#include "hashmap.h"

int main() {
    HashMap* map = hashmap_new(16);
    hashmap_insert(map, "apple", (void*)1);
    hashmap_insert(map, "banana", (void*)2);
    
    printf("apple: %ld\n", (long)hashmap_lookup(map, "apple"));
    printf("banana: %ld\n", (long)hashmap_lookup(map, "banana"));
    printf("size: %lld\n", hashmap_size(map));
    
    return 0;
}
