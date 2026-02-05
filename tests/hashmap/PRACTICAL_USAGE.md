# Practical Hashmap Usage Guide

## Introduction

This guide demonstrates real-world patterns for using hashmaps in FasterBASIC, with complete working examples from the test suite.

## Pattern 1: Simple Key-Value Store

**Use Case**: Configuration settings, feature flags, environment variables

**Example**:
```basic
DIM Config AS HASHMAP

Config("database_host") = "localhost"
Config("database_port") = "5432"
Config("max_connections") = "100"
Config("debug_mode") = "true"

' Fast lookup
IF Config("debug_mode") = "true" THEN
    PRINT "Debug mode enabled"
ENDIF
```

**Benefits**:
- O(1) lookup time
- String-based keys (human readable)
- Easy to add/update settings

## Pattern 2: Fast Lookup into Arrays

**Use Case**: Contacts list, database index, symbol table

**Example**: See `test_contacts_list_arrays.bas`

```basic
' Storage: Parallel arrays
DIM Names(99) AS STRING
DIM Phones(99) AS STRING
DIM Emails(99) AS STRING
DIM Count AS INTEGER

' Index: Hashmap for fast lookup
DIM Index AS HASHMAP

' Add contact
Names(Count) = "Alice Smith"
Phones(Count) = "555-1234"
Emails(Count) = "alice@example.com"
Index("Alice Smith") = STR$(Count)
Count = Count + 1

' Fast lookup by name
Idx = VAL(Index("Alice Smith"))
PRINT "Phone: "; Phones(Idx)
PRINT "Email: "; Emails(Idx)
```

**Benefits**:
- O(1) lookup by key (hashmap)
- O(1) access by index (array)
- Memory efficient (stores index, not duplicate data)
- Can iterate sequentially over arrays
- Can search by key via hashmap

**Why This Pattern Works**:
1. Arrays store the actual data sequentially
2. Hashmap stores name→index mappings
3. Fast lookup: name → index (hashmap) → data (array)
4. Memory efficient: hashmap stores small integers, not full records

## Pattern 3: Multiple Independent Hashmaps

**Use Case**: Multi-level indexing, separate namespaces

**Example**:
```basic
DIM UsersById AS HASHMAP
DIM UsersByEmail AS HASHMAP
DIM UsersByUsername AS HASHMAP

' Same user indexed three ways
UsersById("12345") = "Alice"
UsersByEmail("alice@example.com") = "Alice"
UsersByUsername("alice_smith") = "Alice"

' Flexible lookups
user1 = UsersById("12345")
user2 = UsersByEmail("alice@example.com")
user3 = UsersByUsername("alice_smith")
' All three return "Alice"
```

**Benefits**:
- Multiple ways to look up same data
- Each hashmap is independent
- No interference between maps (thanks to signed remainder bug fix!)

## Pattern 4: Counting and Statistics

**Use Case**: Word frequency, event counting, histogram

**Example**:
```basic
DIM WordCount AS HASHMAP

' Count words
words(0) = "hello"
words(1) = "world"
words(2) = "hello"
words(3) = "basic"
words(4) = "hello"

FOR i = 0 TO 4
    word = words(i)
    current = VAL(WordCount(word))
    current = current + 1
    WordCount(word) = STR$(current)
NEXT i

' Results:
' WordCount("hello") = "3"
' WordCount("world") = "1"
' WordCount("basic") = "1"
```

**Benefits**:
- Automatic tracking of unique items
- O(1) increment per item
- Works with any string key

## Pattern 5: Cache / Memoization

**Use Case**: Expensive computation results, API responses

**Example**:
```basic
DIM ComputeCache AS HASHMAP

SUB GetExpensiveValue(key AS STRING) AS STRING
    ' Check cache first
    cached = ComputeCache(key)
    IF cached <> "" THEN
        RETURN cached
    ENDIF
    
    ' Compute (expensive operation)
    result = PerformExpensiveComputation(key)
    
    ' Store in cache
    ComputeCache(key) = result
    
    RETURN result
END SUB
```

**Benefits**:
- Avoid redundant computation
- O(1) cache lookup
- Transparent to caller

## Performance Characteristics

### Time Complexity
- **Insert**: O(1) average
- **Lookup**: O(1) average
- **Remove**: O(1) average
- **Resize**: O(n) when triggered (automatic at 70% load)

### Space Complexity
- Initial capacity: 128 (configurable via `HASHMAP(capacity)`)
- Growth factor: 2x when load > 70%
- Memory per entry: ~24 bytes + key string + value pointer

### When Hashmaps Are Fast
- ✅ Frequent lookups by key
- ✅ Key-based existence checks
- ✅ Dynamic set of keys (add/remove)
- ✅ Unordered data

### When Arrays Are Better
- ❌ Sequential access (use arrays)
- ❌ Numeric indices 0..N (use arrays)
- ❌ Sorted iteration (use arrays + sort)
- ❌ Very small datasets (< 10 items, arrays may be faster)

## Best Practices

### 1. Store Indices, Not Full Data

**❌ Bad**: Store duplicate data in hashmap
```basic
DIM Names(100) AS STRING
DIM Emails(100) AS STRING
DIM NameToEmail AS HASHMAP

' Wasteful - email stored twice
Names(i) = "Alice"
Emails(i) = "alice@example.com"
NameToEmail("Alice") = "alice@example.com"  ' Duplicate!
```

**✅ Good**: Store index, lookup in array
```basic
DIM Names(100) AS STRING
DIM Emails(100) AS STRING
DIM NameToIndex AS HASHMAP

' Efficient - only index stored
Names(i) = "Alice"
Emails(i) = "alice@example.com"
NameToIndex("Alice") = STR$(i)  ' Just the index

' Lookup
idx = VAL(NameToIndex("Alice"))
email = Emails(idx)
```

### 2. Use STR$/VAL for Numeric Values

Hashmaps store strings as values. For numbers:

```basic
' Store
MyMap("count") = STR$(42)

' Retrieve
count = VAL(MyMap("count"))
```

### 3. Check for Empty Values

```basic
result = MyMap("unknown_key")
IF result = "" THEN
    PRINT "Key not found"
ELSE
    PRINT "Found: "; result
ENDIF
```

### 4. Initialize with Appropriate Capacity

```basic
' Small dataset (< 100 items)
DIM SmallMap AS HASHMAP  ' Default 128

' Large dataset (1000+ items)
' Note: Larger capacity not yet supported in codegen
' Will auto-resize as needed
```

## Common Patterns Summary

| Pattern | Use Case | Storage | Lookup |
|---------|----------|---------|--------|
| Key-Value Store | Config, flags | Direct | O(1) |
| Array Index | Contacts, records | Arrays + HashMap | O(1) |
| Multi-Index | Multiple lookups | Multiple HashMaps | O(1) each |
| Counting | Frequency, stats | HashMap values | O(1) |
| Cache | Memoization | HashMap | O(1) |

## Working Examples

All examples in this guide are based on passing tests:

- **Basic Operations**: `test_hashmap_basic.bas`
- **Multiple Maps**: `test_hashmap_multiple.bas`
- **Updates**: `test_hashmap_update.bas`
- **With Arrays**: `test_hashmap_with_arrays.bas`
- **Contacts List**: `test_contacts_list_arrays.bas`
- **Comprehensive**: `test_hashmap_comprehensive_verified.bas`

Run the test suite to see them in action:
```bash
cd tests/hashmap
./run_tests.sh
```

## Limitations and Workarounds

### Current Limitations
- UDT integration has issues (use parallel arrays instead)
- String pool limit for very large datasets
- Method calls (`.SIZE()`, `.HASKEY()`) not yet implemented

### Workarounds
- **UDT Issue**: Use parallel arrays (same performance, more verbose)
- **String Pool**: Split data across multiple arrays/maps
- **Methods**: Track size manually, check for empty string

## Future Enhancements

Planned features:
- `.SIZE()` method for count
- `.HASKEY()` method for existence check
- `.KEYS()` method for iteration
- `.CLEAR()` method
- `.REMOVE()` method
- Full UDT support

## Conclusion

Hashmaps provide O(1) lookups and are essential for:
- Fast key-based access
- Building indices into structured data
- Implementing caches and symbol tables
- Counting and frequency analysis

The parallel arrays + hashmap pattern is particularly powerful for real-world applications, enabling both fast lookup (by key) and sequential iteration (by array index).

For questions or issues, see `README.md` and the test suite in `tests/hashmap/`.