# QBE Hashmap Module - Quick Start Guide

Get up and running with the QBE hashmap implementation in 5 minutes.

## Prerequisites

- QBE compiler built in `../qbe_source/`
- C compiler (cc, clang, or gcc)
- Make

## 1. Build the Module (30 seconds)

```bash
cd qbe_basic_integrated/qbe_modules
make hashmap.o
```

Expected output:
```
Compiling QBE hashmap module...
Assembling hashmap object...
```

## 2. Run Tests (30 seconds)

```bash
make test
```

Expected output:
```
Running hashmap tests...
Running test: create_and_free ... PASSED
Running test: insert_and_lookup ... PASSED
...
✓ All tests passed!
```

## 3. Use in C Code (2 minutes)

Create `my_test.c`:

```c
#include <stdio.h>
#include "qbe_modules/hashmap.h"

int main() {
    // Create hashmap
    HashMap* map = hashmap_new(16);
    
    // Insert values
    hashmap_insert(map, "name", "Alice");
    hashmap_insert(map, "age", (void*)30);
    
    // Lookup
    char* name = hashmap_lookup(map, "name");
    int age = (int)(long)hashmap_lookup(map, "age");
    
    printf("Name: %s\n", name);
    printf("Age: %d\n", age);
    printf("Size: %ld\n", hashmap_size(map));
    
    // Cleanup
    hashmap_free(map);
    return 0;
}
```

Compile and run:

```bash
cc -I. my_test.c qbe_modules/hashmap.o -o my_test
./my_test
```

## 4. Use in FasterBASIC (Coming Soon)

Once the code generator is updated:

```basic
DIM dict AS HASHMAP
dict("hello") = "world"
PRINT dict("hello")
```

## Common Operations

### Create Map
```c
HashMap* map = hashmap_new(16);
```

### Insert/Update
```c
hashmap_insert(map, "key", value_ptr);
```

### Lookup
```c
void* value = hashmap_lookup(map, "key");
if (value == NULL) {
    // Key not found
}
```

### Check Existence
```c
if (hashmap_has_key(map, "key")) {
    // Key exists
}
```

### Remove
```c
if (hashmap_remove(map, "key")) {
    // Successfully removed
}
```

### Get Size
```c
int64_t count = hashmap_size(map);
```

### Iterate Keys
```c
char** keys = hashmap_keys(map);
for (int i = 0; keys[i]; i++) {
    void* value = hashmap_lookup(map, keys[i]);
    // Process key/value
}
free(keys);
```

### Clear All
```c
hashmap_clear(map);
```

### Free Map
```c
hashmap_free(map);
```

## Important Notes

### Memory Management

1. **Keys are copied** - You can free your key string after insert
2. **Values are NOT copied** - Keep values alive while in map
3. **Free the keys array** - `hashmap_keys()` returns allocated memory
4. **Not thread-safe** - Use external locking if needed

### Example with Proper Cleanup

```c
HashMap* map = hashmap_new(16);

// Insert (key is copied, value is stored as-is)
char* my_value = strdup("important data");
hashmap_insert(map, "key1", my_value);

// Lookup
char* found = hashmap_lookup(map, "key1");
printf("%s\n", found);  // "important data"

// Remove and free
hashmap_remove(map, "key1");
free(my_value);  // YOU must free the value

// Free map
hashmap_free(map);
```

## Troubleshooting

### Build Fails

**Problem:** `qbe: command not found`

**Solution:** Build QBE first:
```bash
cd ../qbe_source
make
cd ../qbe_modules
```

### Link Errors

**Problem:** `undefined reference to hashmap_new`

**Solution:** Add `hashmap.o` to your link command:
```bash
cc my_program.c qbe_modules/hashmap.o -o my_program
```

### Segfault

**Problem:** Crash when accessing hashmap

**Solution:** Check these common issues:
- Map pointer is not NULL
- Key strings are null-terminated
- Values are valid pointers
- Don't use values after removing from map

## Performance Tips

1. **Pre-allocate** if you know the size:
   ```c
   HashMap* map = hashmap_new(1000);  // For ~1000 items
   ```

2. **Avoid repeated lookups**:
   ```c
   void* value = hashmap_lookup(map, "key");
   // Use value multiple times
   ```

3. **Clear instead of free/new**:
   ```c
   hashmap_clear(map);  // Reuses capacity
   ```

## Next Steps

- Read `README.md` for detailed documentation
- See `INTEGRATION.md` for FasterBASIC integration
- Check `test_hashmap.c` for more examples
- Review `hashmap.h` for complete API

## Need Help?

- Check the test suite: `test_hashmap.c`
- Review QBE source: `hashmap.qbe`
- Read integration guide: `INTEGRATION.md`

Happy hashing! 🎉