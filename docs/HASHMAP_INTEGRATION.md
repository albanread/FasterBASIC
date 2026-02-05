# FasterBASIC Hashmap Integration

## Overview

This document describes the integration of hashmap (dictionary) support into FasterBASIC, using the hand-coded QBE hashmap module as the runtime implementation.

## Status

**Current State**: Lexer and parser integration complete. Codegen partially implemented.

**Completed**:
- ✅ Lexer: Added `HASHMAP` keyword and method keywords (`HASKEY`, `KEYS`, `SIZE`, `CLEAR`, `REMOVE`)
- ✅ Parser: Added `AS HASHMAP` type recognition in `DIM` statements
- ✅ Semantic Analyzer: Added `BaseType::HASHMAP` type support
- ✅ Code Generator: Basic hashmap initialization, insert, and lookup operations

**TODO**:
- ⚠️ Implement hashmap method calls (`.HASKEY()`, `.REMOVE()`, `.SIZE()`, `.CLEAR()`, `.KEYS()`)
- ⚠️ Implement proper value boxing/unboxing (currently assumes pointer types)
- ⚠️ Add reference counting integration for stored values
- ⚠️ Link `hashmap.o` automatically when hashmaps are used
- ⚠️ Add semantic validation (e.g., only string keys allowed)
- ⚠️ Write comprehensive tests

## Syntax

### Declaration

```basic
DIM dict AS HASHMAP
```

Creates a new hashmap with default capacity (16 entries). The hashmap is initialized by calling the QBE runtime function `hashmap_new(16)`.

### Assignment (Insert/Update)

```basic
dict("name") = "Alice"
dict("age") = 25
dict("score") = 95.5
```

Inserts or updates a key-value pair. Keys must be strings. Values can be any type (currently stored as generic pointers).

**Generated Code**: Calls `hashmap_insert(map, key, value)` from the QBE runtime.

### Lookup

```basic
name$ = dict("name")
age = dict("age")
score# = dict("score")
```

Retrieves a value by key. Returns the stored value (or null/0 if not found).

**Generated Code**: Calls `hashmap_lookup(map, key)` from the QBE runtime.

### Methods

#### Check if Key Exists

```basic
IF dict.HASKEY("name") THEN
    PRINT "Name is set"
ENDIF
```

**Runtime Function**: `hashmap_has_key(map, key)` → returns 1 if found, 0 otherwise

#### Remove Key

```basic
dict.REMOVE("age")
```

**Runtime Function**: `hashmap_remove(map, key)` → returns 1 if removed, 0 if not found

#### Get Size

```basic
count = dict.SIZE()
PRINT "Dictionary has "; count; " entries"
```

**Runtime Function**: `hashmap_size(map)` → returns int64_t size

#### Clear All Entries

```basic
dict.CLEAR()
```

**Runtime Function**: `hashmap_clear(map)` → resets size to 0

#### Get All Keys

```basic
keys$ = dict.KEYS()
FOR i = 0 TO UBOUND(keys$)
    PRINT keys$(i)
NEXT i
```

**Runtime Function**: `hashmap_keys(map)` → returns array of keys (as null-terminated char** array)

**Note**: The `.KEYS()` method implementation needs to convert the C array to a FasterBASIC string array.

## Implementation Details

### Files Modified

1. **`fasterbasic_token.h`**
   - Added `TokenType::KEYWORD_HASHMAP`
   - Added method tokens: `HASKEY`, `KEYS`, `SIZE`, `CLEAR`, `REMOVE`
   - Updated `tokenTypeToString()` to include new tokens

2. **`fasterbasic_lexer.cpp`**
   - Added keyword mappings for `HASHMAP` and method keywords

3. **`fasterbasic_parser.cpp`**
   - Updated `isTypeKeyword()` to include `KEYWORD_HASHMAP`
   - Updated `asTypeToSuffix()` to return `UNKNOWN` for hashmap (no type suffix)

4. **`fasterbasic_semantic.h`**
   - Added `BaseType::HASHMAP` to the `BaseType` enum
   - Updated `TypeDescriptor::toString()` to handle `HASHMAP` type
   - Updated `keywordToDescriptor()` to map `KEYWORD_HASHMAP` → `BaseType::HASHMAP`

5. **`fasterbasic_semantic.cpp`**
   - Updated `processDimStatement()` to handle `AS HASHMAP` declarations

6. **`ast_emitter.cpp`** (Code Generator)
   - Updated `emitDimStatement()` to call `hashmap_new(16)` for hashmap variables
   - Updated `emitLetStatement()` to detect hashmap assignments and call `hashmap_insert()`
   - Updated `loadArrayElement()` to detect hashmap lookups and call `hashmap_lookup()`

### QBE Runtime Functions

The following functions from `qbe_modules/hashmap.qbe` are available:

| Function | Signature | Description |
|----------|-----------|-------------|
| `hashmap_new` | `l hashmap_new(w capacity)` | Create new hashmap |
| `hashmap_free` | `void hashmap_free(l map)` | Free hashmap |
| `hashmap_insert` | `w hashmap_insert(l map, l key, l value)` | Insert/update key-value pair |
| `hashmap_lookup` | `l hashmap_lookup(l map, l key)` | Lookup value by key (returns pointer or null) |
| `hashmap_has_key` | `w hashmap_has_key(l map, l key)` | Check if key exists |
| `hashmap_remove` | `w hashmap_remove(l map, l key)` | Remove key |
| `hashmap_size` | `l hashmap_size(l map)` | Get number of entries |
| `hashmap_clear` | `void hashmap_clear(l map)` | Clear all entries |
| `hashmap_keys` | `l hashmap_keys(l map)` | Get array of keys (char**) |

### Type System Integration

Hashmaps are represented as:
- **BaseType**: `HASHMAP`
- **QBE Type**: `l` (64-bit pointer)
- **Storage**: Global or local variable containing a pointer to the HashMap structure

The HashMap structure itself (32 bytes) is defined in the QBE module:
```c
struct HashMap {
    int64_t capacity;    // offset 0
    int64_t size;        // offset 8
    void*   entries;     // offset 16
    int64_t tombstones;  // offset 24
};
```

## Codegen Strategy

### Variable Declaration

```basic
DIM dict AS HASHMAP
```

**Generated QBE IL**:
```qbe
# DIM dict AS HASHMAP - call hashmap_new()
%.t1 =w copy 16
%.t2 =l call $hashmap_new(w %.t1)
storel %.t2, $dict
```

### Hashmap Insert

```basic
dict("name") = "Alice"
```

**Generated QBE IL**:
```qbe
# HASHMAP insert: dict(...) = value
%.hashmapPtr =l loadl $dict
%.keyValue =l <string literal or expression>
%.value =l <value expression>
%.result =w call $hashmap_insert(l %.hashmapPtr, l %.keyValue, l %.value)
```

### Hashmap Lookup

```basic
x$ = dict("name")
```

**Generated QBE IL**:
```qbe
# HASHMAP lookup: dict(...)
%.hashmapPtr =l loadl $dict
%.keyValue =l <string literal or expression>
%.resultPtr =l call $hashmap_lookup(l %.hashmapPtr, l %.keyValue)
```

## Value Boxing/Unboxing

**Current Implementation**: Values are stored as raw pointers (`void*`). This works for:
- Strings (already stored as `BasicString*` pointers)
- Arrays (stored as `BasicArray*` pointers)
- User-defined types (stored as structure pointers)

**TODO**: For scalar numeric types (integers, floats), we need to implement boxing:

### Option 1: Box All Values
Create a generic `BasicValue` wrapper:
```c
struct BasicValue {
    enum ValueType { INT, FLOAT, DOUBLE, STRING, ARRAY, UDT } type;
    union {
        int64_t int_val;
        float float_val;
        double double_val;
        void* ptr_val;
    } data;
};
```

### Option 2: Type-Specific Hashmaps
Provide specialized hashmap variants:
- `HASHMAP OF STRING`
- `HASHMAP OF INTEGER`
- `HASHMAP OF DOUBLE`

This avoids boxing overhead but requires more complex parsing and codegen.

### Option 3: Always Use Heap-Allocated Values
Force all hashmap values to be heap-allocated:
```basic
dict("age") = NEW(INTEGER, 25)
age% = *dict("age")  ' Dereference pointer
```

This is more explicit but less user-friendly.

**Recommendation**: Implement Option 1 (generic boxing) for maximum flexibility and transparency to the user.

## Reference Counting

Hashmaps need to integrate with FasterBASIC's reference-counted runtime:

### On Insert
```qbe
# Before inserting, increment reference count
%.value =l <expression>
call $basic_retain(l %.value)
call $hashmap_insert(l %.map, l %.key, l %.value)
```

### On Remove
```qbe
# Before removing, get old value and release it
%.oldValue =l call $hashmap_lookup(l %.map, l %.key)
%.removed =w call $hashmap_remove(l %.map, l %.key)
jnz %.removed, @release_old, @skip_release
@release_old
call $basic_release(l %.oldValue)
@skip_release
```

### On Update
```qbe
# When updating, release old value and retain new value
%.oldValue =l call $hashmap_lookup(l %.map, l %.key)
%.newValue =l <expression>
call $basic_retain(l %.newValue)
call $hashmap_insert(l %.map, l %.key, l %.newValue)
call $basic_release(l %.oldValue)
```

### On Clear/Free
```qbe
# Iterate all values and release them
%.keys =l call $hashmap_keys(l %.map)
# (iterate keys, lookup each value, release)
call $hashmap_clear(l %.map)
call $hashmap_free(l %.map)
```

## Linking

To use hashmaps, the compiled program must link with `hashmap.o`:

```bash
fbc_qbe myprogram.bas -o myprogram
# Currently needs manual linking:
cc myprogram.o qbe_modules/hashmap.o -o myprogram
```

**TODO**: Automatically detect hashmap usage and include `hashmap.o` in the link step.

### Automatic Linking Strategy

1. During semantic analysis, set a flag if `BaseType::HASHMAP` is used
2. Pass this flag to the linker phase
3. Add `qbe_modules/hashmap.o` to the link command if the flag is set

```cpp
// In qbe_codegen_v2.cpp or main.c
if (usesHashmaps) {
    linkCommand += " qbe_modules/hashmap.o";
}
```

## Method Call Parsing

Method calls on hashmaps use dot notation:

```basic
IF dict.HASKEY("name") THEN ...
dict.REMOVE("age")
count = dict.SIZE()
```

**Parsing Approach**:

1. In `parsePrimary()`, when we see `IDENTIFIER DOT IDENTIFIER`, check if:
   - The first identifier is a variable with `BaseType::HASHMAP`
   - The second identifier is a method name (`HASKEY`, `REMOVE`, `SIZE`, `CLEAR`, `KEYS`)

2. If so, create a new AST node type: `HashmapMethodCallExpression`
   ```cpp
   struct HashmapMethodCallExpression : Expression {
       std::string hashmapName;
       std::string methodName;
       std::vector<ExpressionPtr> arguments;
   };
   ```

3. In codegen, emit calls to the corresponding QBE runtime functions.

**Alternative**: Treat method calls as special function calls with a hidden first parameter (the hashmap).

## Testing

### Test Cases Needed

1. **Basic Operations**
   ```basic
   DIM dict AS HASHMAP
   dict("key1") = "value1"
   dict("key2") = 42
   PRINT dict("key1")
   PRINT dict("key2")
   ```

2. **Method Calls**
   ```basic
   DIM dict AS HASHMAP
   dict("a") = 1
   IF dict.HASKEY("a") THEN PRINT "Found"
   PRINT dict.SIZE()
   dict.REMOVE("a")
   PRINT dict.SIZE()
   dict.CLEAR()
   ```

3. **Keys Iteration**
   ```basic
   DIM dict AS HASHMAP
   dict("one") = 1
   dict("two") = 2
   dict("three") = 3
   keys$ = dict.KEYS()
   FOR i = 0 TO UBOUND(keys$)
       PRINT keys$(i); " = "; dict(keys$(i))
   NEXT i
   ```

4. **Stress Test**
   ```basic
   DIM dict AS HASHMAP
   FOR i = 1 TO 1000
       dict("key" + STR$(i)) = i
   NEXT i
   PRINT "Size: "; dict.SIZE()
   ```

5. **Reference Counting**
   ```basic
   DIM dict AS HASHMAP
   DIM s$ = "test string"
   dict("key") = s$
   s$ = ""  ' Should not free the string yet (dict holds a reference)
   PRINT dict("key")  ' Should still work
   ```

## Future Enhancements

1. **Typed Hashmaps**
   ```basic
   DIM scores AS HASHMAP OF DOUBLE
   DIM names AS HASHMAP OF STRING
   ```

2. **Integer Keys**
   ```basic
   DIM idMap AS HASHMAP
   idMap(12345) = "Alice"  ' Integer key
   ```

3. **Iteration Support**
   ```basic
   FOR EACH key$ IN dict.KEYS()
       PRINT key$; " => "; dict(key$)
   NEXT
   ```

4. **Hashmap Literals**
   ```basic
   DIM dict AS HASHMAP = {"name": "Alice", "age": 25}
   ```

5. **Nested Hashmaps**
   ```basic
   DIM outer AS HASHMAP
   DIM inner AS HASHMAP
   inner("x") = 10
   outer("sub") = inner
   PRINT outer("sub")("x")  ' Nested access
   ```

## Performance Considerations

- **Initial Capacity**: Default of 16 is reasonable for small maps. Allow user to specify:
  ```basic
  DIM dict AS HASHMAP(128)  ' Pre-allocate for 128 entries
  ```

- **Load Factor**: The QBE module uses 70% load factor. This is a good balance.

- **Resize Strategy**: Doubles capacity on resize (good for amortized O(1) insert).

- **String Hashing**: FNV-1a is fast and has good distribution. Consider xxHash or MurmurHash3 for even better performance.

- **Collision Resolution**: Linear probing is cache-friendly. Consider Robin Hood hashing for better worst-case performance.

## Debugging

### Trace Hashmap Operations

Add a compiler flag to emit debug comments:
```bash
fbc_qbe -trace-hashmap myprogram.bas
```

This would generate:
```qbe
# HASHMAP: insert dict("name") = "Alice"
# HASHMAP: size before = 0
call $hashmap_insert(...)
# HASHMAP: size after = 1
```

### Runtime Debugging

Add a `hashmap_dump()` function to print the internal state:
```c
void hashmap_dump(HashMap* map) {
    printf("HashMap at %p:\n", map);
    printf("  capacity: %ld\n", map->capacity);
    printf("  size: %ld\n", map->size);
    printf("  tombstones: %ld\n", map->tombstones);
    printf("  load: %.2f%%\n", 100.0 * (map->size + map->tombstones) / map->capacity);
    // ... print entries ...
}
```

## Conclusion

The hashmap integration builds on the solid foundation of the QBE hashmap module. The lexer, parser, and semantic analyzer changes are straightforward and follow established patterns. The code generator changes are more complex due to the need for proper value boxing/unboxing and reference counting integration.

Once the remaining TODO items are completed, FasterBASIC will have a fast, native hashmap implementation with clean, intuitive syntax that fits naturally with the rest of the language.

## Next Steps

1. **Implement Method Call Parsing**
   - Extend parser to recognize `.HASKEY()`, `.REMOVE()`, etc.
   - Create AST nodes for method calls

2. **Implement Method Call Codegen**
   - Emit calls to `hashmap_has_key()`, `hashmap_remove()`, etc.
   - Handle `.KEYS()` return value conversion to string array

3. **Implement Value Boxing**
   - Design and implement `BasicValue` wrapper structure
   - Update insert/lookup to box/unbox values transparently

4. **Add Reference Counting**
   - Emit `basic_retain()` calls on insert
   - Emit `basic_release()` calls on remove/update/free

5. **Automatic Linking**
   - Detect hashmap usage during compilation
   - Automatically include `hashmap.o` in link command

6. **Write Tests**
   - Create comprehensive test suite covering all operations
   - Test edge cases (empty map, resize, collisions, etc.)

7. **Documentation**
   - Update language documentation with hashmap syntax
   - Add examples to the QuickRef
   - Write tutorial showing common use cases