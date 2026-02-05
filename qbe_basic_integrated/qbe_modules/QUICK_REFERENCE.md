# Hash Map Module - Quick Reference Card

## Building

```bash
# Build hashmap module
cd qbe_basic_integrated/qbe_modules
../fbc_qbe hashmap.qbe              # Creates hashmap.o

# Run tests
make test
```

## C API

```c
#include "qbe_modules/hashmap.h"

// Create
HashMap* map = hashmap_new(16);

// Insert/Update
hashmap_insert(map, "key", value_ptr);

// Lookup
void* value = hashmap_lookup(map, "key");

// Check existence
if (hashmap_has_key(map, "key")) { ... }

// Remove
hashmap_remove(map, "key");

// Size
int64_t count = hashmap_size(map);

// Iterate
char** keys = hashmap_keys(map);
for (int i = 0; keys[i]; i++) {
    void* val = hashmap_lookup(map, keys[i]);
    // ...
}
free(keys);

// Clear
hashmap_clear(map);

// Free
hashmap_free(map);
```

## FasterBASIC (Future)

```basic
DIM dict AS HASHMAP

dict("key") = value
x = dict("key")

IF dict.HASKEY("key") THEN ...
dict.REMOVE("key")

FOR EACH k IN dict.KEYS()
    PRINT k, dict(k)
NEXT

PRINT dict.SIZE()
dict.CLEAR()
```

## Memory Rules

- **Keys:** Copied (via strdup), caller can free after insert
- **Values:** Stored as pointers, caller manages lifetime
- **Keys array:** Must free result from `hashmap_keys()`
- **Not thread-safe:** Use external locking if needed

## Compilation

```bash
# QBE IL → Object file
./fbc_qbe hashmap.qbe                # Creates hashmap.o

# QBE IL → Assembly
./fbc_qbe hashmap.qbe -c             # Creates hashmap.s

# Custom output
./fbc_qbe hashmap.qbe -o mymod.o

# Link with C
cc program.c hashmap.o -o program
```

## Performance

- **Insert/Lookup/Remove:** O(1) average, O(n) worst
- **Space:** 24 bytes per entry + 32 byte header
- **Load Factor:** 70% (auto-resize)
- **Min Capacity:** 16 slots
- **Growth:** 2x on resize

## Common Patterns

### String-String Map
```c
HashMap* map = hashmap_new(100);
hashmap_insert(map, "name", strdup("Alice"));
hashmap_insert(map, "city", strdup("NYC"));
char* name = (char*)hashmap_lookup(map, "name");
```

### String-Integer Map
```c
hashmap_insert(map, "age", (void*)30);
int age = (int)(long)hashmap_lookup(map, "age");
```

### Iteration
```c
char** keys = hashmap_keys(map);
for (int i = 0; keys[i]; i++) {
    printf("%s = %s\n", keys[i], 
           (char*)hashmap_lookup(map, keys[i]));
}
free(keys);
```

### Safe Lookup
```c
void* value = hashmap_lookup(map, "key");
if (value == NULL) {
    // Key not found
} else {
    // Use value
}
```

## Files

| File | Purpose |
|------|---------|
| `hashmap.qbe` | QBE IL implementation |
| `hashmap.h` | C interface |
| `hashmap.o` | Compiled object file |
| `test_hashmap.c` | Test suite |
| `README.md` | Full documentation |
| `INTEGRATION.md` | Code generator guide |
| `QUICKSTART.md` | 5-minute start |

## Help

```bash
# Test compilation
./test_qbe_compilation.sh

# Build and test
make test

# Clean
make clean
```

## Links

- Full docs: `README.md`
- Integration: `INTEGRATION.md`
- Status: `STATUS.md`
- Language design: `../../hash-map.md`
