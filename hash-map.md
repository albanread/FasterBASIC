compact_repo/hash-map.md
```

# Hash Map (Dictionary) Support in FasterBASIC

## Overview

This document describes the proposed syntax and implementation strategy for adding hash maps (dictionaries) as a first-class data structure in FasterBASIC. The goal is to provide an intuitive, powerful, and efficient way for BASIC programmers to use associative arrays with minimal learning curve.

---

## 1. Syntax Design

### Declaration

```basic
DIM dict AS HASHMAP
```
or with explicit key/value types (optional):

```basic
DIM dict AS HASHMAP(STRING, INTEGER)
DIM table AS HASHMAP(STRING, STRING)
DIM symtab AS HASHMAP(INTEGER, ANY)
```

### Assignment and Lookup

```basic
dict("foo") = 42
PRINT dict("foo")         ' Prints 42

table("hello") = "world"
PRINT table("hello")      ' Prints "world"
```

### Existence Check

```basic
IF dict.HASKEY("foo") THEN PRINT "Key exists!"
IF NOT dict.HASKEY("bar") THEN PRINT "No such key"
```

### Deletion

```basic
dict.REMOVE("foo")
```

### Iteration

```basic
FOR EACH k IN dict.KEYS()
    PRINT k, dict(k)
NEXT

' Or iterate over key-value pairs:
FOR EACH k, v IN dict.PAIRS()
    PRINT k, v
NEXT
```

### Size

```basic
PRINT dict.SIZE()
```

### Clear All

```basic
dict.CLEAR()
```

### Example: Symbol Table

```basic
DIM symtab AS HASHMAP(STRING, INTEGER)

symtab("x") = 1
symtab("y") = 2

IF symtab.HASKEY("x") THEN
    PRINT "x = "; symtab("x")
END IF

FOR EACH name, value IN symtab.PAIRS()
    PRINT name, value
NEXT
```

### Optional: Default Values

```basic
PRINT dict.GET("missing", 0)   ' Returns 0 if "missing" is not present
```

---

## 2. Feature Summary Table

| Operation         | Syntax Example                       |
|-------------------|--------------------------------------|
| Declare           | DIM d AS HASHMAP                     |
| Assign            | d("foo") = 123                       |
| Lookup            | PRINT d("foo")                       |
| Exists            | IF d.HASKEY("foo") THEN ...          |
| Remove            | d.REMOVE("foo")                      |
| Iterate keys      | FOR EACH k IN d.KEYS() ... NEXT      |
| Iterate pairs     | FOR EACH k, v IN d.PAIRS() ... NEXT  |
| Size              | PRINT d.SIZE()                       |
| Clear             | d.CLEAR()                            |
| Get with default  | d.GET("foo", default)                |

---

## 3. Implementation Notes

### 3.1. Internal Representation

- Each `HASHMAP` is implemented as a hash table with open addressing or separate chaining.
- Keys can be strings or integers (support for other types can be added as needed).
- Values can be any BASIC type, including user-defined types and arrays.
- Type annotations (e.g., `HASHMAP(STRING, INTEGER)`) are enforced at compile time if provided, but the default is fully dynamic.

### 3.2. Core Operations

- **Insert/Update:**  
  On `dict(key) = value`, hash the key and insert or update the value in the table.
- **Lookup:**  
  On `dict(key)`, hash the key and return the value if present, or raise a runtime error if not found (unless using `.GET(key, default)`).
- **Existence:**  
  `.HASKEY(key)` returns true if the key exists.
- **Remove:**  
  `.REMOVE(key)` deletes the key-value pair if present.
- **Iteration:**  
  `.KEYS()` returns an array of all keys.  
  `.PAIRS()` returns an iterable of (key, value) pairs.
- **Size:**  
  `.SIZE()` returns the number of entries.
- **Clear:**  
  `.CLEAR()` removes all entries.

### 3.3. Memory Management

- Hash maps are reference-counted objects. Assignment copies the reference, not the contents.
- When the last reference is released, the hash map and all its keys/values are freed.
- Iterators over hash maps are safe against modification during iteration (by snapshotting keys or using versioning).

### 3.4. Performance

- Hash maps are optimized for fast average-case insert, lookup, and delete (O(1) expected).
- Rehashing occurs automatically as the table grows.
- String keys use a fast, case-insensitive hash function by default (matching BASIC conventions).

### 3.5. Type Safety and Errors

- If a key or value of the wrong type is used (when types are declared), a compile-time or runtime error is raised.
- Accessing a missing key without `.GET()` raises a runtime error.
- All operations are safe and checked; no undefined behavior.

### 3.6. Code Generation

- The compiler recognizes `HASHMAP` declarations and emits calls to the runtime hash map API for all operations.
- Method calls (e.g., `.HASKEY`, `.REMOVE`) are lowered to runtime functions.
- `FOR EACH` over `.KEYS()` or `.PAIRS()` is translated to a loop over the runtime iterator.

### 3.7. Thread Safety

- Hash maps are not thread-safe by default. If used from multiple threads, access must be protected by a `CRITICAL SECTION` or explicit locking.

---

## 4. QBE Hand-Coded Core Plan

While much of the hash map feature can be implemented in FasterBASIC, for maximum performance and runtime independence, the core hash map routines can be hand-coded directly in QBE. This approach ensures that even the most fundamental operations (insert, lookup, remove, resize) are available without any C or C++ runtime dependency.

### Plan for Hand-Coding Hash Map Core in QBE

1. **Identify Core Operations to Implement in QBE:**
   - Hash function for strings and integers
   - Table initialization and allocation
   - Insert/update (with open addressing or chaining)
   - Lookup (with collision resolution)
   - Remove (with tombstone or rehashing support)
   - Resize and rehash
   - Iteration support (keys, pairs)

2. **Design QBE Function Interfaces:**
   - Use simple pointer-based APIs for table, key, and value access.
   - Return error codes or null pointers for missing keys.

3. **Write QBE Source Files:**
   - Implement each operation as a QBE function (e.g., `hashmap_insert`, `hashmap_lookup`, `hashmap_remove`, `hashmap_resize`).
   - Use QBE's memory allocation and pointer arithmetic for table management.
   - Provide wrappers for type-specific operations if needed.

4. **Integrate with Code Generator:**
   - The code generator emits calls to these QBE functions for all hash map operations.
   - As the language evolves, more of the hash map logic can be ported to FasterBASIC, but the QBE core remains as a high-performance, runtime-independent foundation.

5. **Testing and Validation:**
   - Write test programs in FasterBASIC that exercise all hash map operations, ensuring correctness and performance of the QBE core.

### Example QBE Function Signatures (Pseudo-code)

```
export function hashmap_new(size: w) -> l
export function hashmap_insert(table: l, key: l, value: l) -> w
export function hashmap_lookup(table: l, key: l) -> l
export function hashmap_remove(table: l, key: l) -> w
export function hashmap_size(table: l) -> w
export function hashmap_keys(table: l) -> l
```

### Rationale

- Hand-coding the core in QBE allows for a minimal, portable runtime that can be linked with any QBE-generated program.
- This approach is compatible with the long-term goal of eliminating C/C++ dependencies.
- As more features are implemented in FasterBASIC, the QBE core can remain as a fallback or performance-critical path.

---

## 5. Implementation Status

### QBE Core Module - COMPLETE ✓

The QBE hashmap core has been implemented in `qbe_basic_integrated/qbe_modules/hashmap.qbe`.

**Location:** `qbe_basic_integrated/qbe_modules/`

**Files:**
- `hashmap.qbe` - Hand-coded QBE IL implementation (740 lines)
- `hashmap.h` - C interface header
- `test_hashmap.c` - Comprehensive test suite
- `Makefile` - Build system for module and tests
- `README.md` - Complete documentation

**Features Implemented:**
- ✓ Hash table with open addressing and linear probing
- ✓ FNV-1a hash function for strings and integers
- ✓ Automatic resizing at 70% load factor
- ✓ Tombstone markers for efficient deletion
- ✓ All core operations: new, insert, lookup, remove, has_key, size, clear, keys
- ✓ Comprehensive error handling and NULL safety
- ✓ Memory-efficient layout (32-byte map struct, 24-byte entries)

**Testing:**
- ✓ 13 test cases covering all operations
- ✓ Edge cases (empty map, NULL safety, special characters)
- ✓ Collision handling and resize verification
- ✓ Performance characteristics validated

**Build Instructions:**
```bash
cd qbe_basic_integrated/qbe_modules
make test        # Build and run all tests
make hashmap.o   # Build object file for linking
```

**Next Steps:**
1. Update code generator to conditionally include `hashmap.o` when `HASHMAP` types are used
2. Implement BASIC syntax lowering to QBE function calls
3. Add reference counting integration for BASIC runtime values
4. Create BASIC test programs to validate end-to-end functionality

### Code Generator Integration - TODO

The code generator needs to be extended to:
- Recognize `DIM x AS HASHMAP` declarations
- Lower `dict("key") = value` to `hashmap_insert()` calls
- Lower `dict("key")` lookups to `hashmap_lookup()` calls
- Lower `.HASKEY()`, `.REMOVE()`, etc. to corresponding functions
- Emit reference counting code for value management
- Include `hashmap.o` in link command when needed

---

## 6. Future Extensions

- Support for other key types (e.g., user-defined types, tuples).
- Ordered hash maps (preserve insertion order).
- Immutable/frozen hash maps for functional programming.
- Built-in serialization to/from JSON or other formats.

---

## 7. Rationale

- The syntax is designed to be familiar to BASIC users, resembling array access but with additional methods for dictionary operations.
- Method-based API (e.g., `.HASKEY`, `.REMOVE`) is clear and discoverable.
- Optional type annotations provide safety without sacrificing flexibility.
- The feature is essential for implementing symbol tables, environments, and many other data structures needed for self-hosting and advanced programming.

---

## 8. Example Usage Recap

```basic
DIM dict AS HASHMAP(STRING, INTEGER)
dict("a") = 10
dict("b") = 20

IF dict.HASKEY("a") THEN PRINT dict("a")

FOR EACH k, v IN dict.PAIRS()
    PRINT k, v
NEXT

dict.REMOVE("a")
PRINT dict.SIZE()
dict.CLEAR()
```

---