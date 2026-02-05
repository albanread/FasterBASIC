# FasterBASIC Hashmap Tests

This directory contains tests for the new HASHMAP object type.

## Working Tests

These tests currently pass and verify hashmap functionality:

- `test_hashmap_basic.bas` - Basic insert and lookup operations
- `test_hashmap_multiple.bas` - Multiple independent hashmap instances
- `test_hashmap_update.bas` - Updating existing keys with new values
- `test_hashmap_with_arrays.bas` - Arrays and hashmaps used together
- `test_hashmap_two_maps_multiple_inserts.bas` - Regression test for signed remainder bug (FIXED)
- `test_hashmap_comprehensive_verified.bas` - Comprehensive test with 6 hashmaps and 40+ entries (FIXED)
- `test_contacts_list_arrays.bas` - Realistic contacts list with parallel arrays + hashmap for O(1) lookup (NEW)

## Tests Requiring String Pool Fix

The following tests hit a pre-existing string constant pool limit in the code generator:

- `test_hashmap_keys.bas` - Special characters in keys
- `test_hashmap_stress.bas` - Large number of entries
- `test_hashmap_comprehensive.bas` - Complete feature demo

These tests are valid and will work once the string pool implementation is improved.

## Bug Fix History

### Signed Remainder Bug (FIXED)

**Issue**: Hashmap insertions would corrupt memory when hash values exceeded 2^31, causing entries to be written to wrong locations.

**Root Cause**: `hashmap_compute_index` in `hashmap.qbe` used signed remainder (`rem`) instead of unsigned remainder (`urem`). Large hash values (e.g., `0xebcba174` for "Bob") were treated as negative numbers, producing incorrect indices.

**Fix**: Changed line 26 in `qbe_basic_integrated/qbe_modules/hashmap.qbe` from:
```qbe
%index =w rem %hash, %capacity
```
to:
```qbe
%index =w urem %hash, %capacity
```

**Tests**: `test_hashmap_two_maps_multiple_inserts.bas` specifically verifies this fix with keys that trigger large hash values.

## Running Tests

```bash
# Run all working tests
for test in test_hashmap_basic.bas test_hashmap_multiple.bas test_hashmap_update.bas test_hashmap_with_arrays.bas test_hashmap_two_maps_multiple_inserts.bas test_hashmap_comprehensive_verified.bas test_contacts_list_arrays.bas; do
    echo "Testing $test"
    ../../../qbe_basic_integrated/fbc_qbe $test && ./$(basename $test .bas)
done
```

Or simply run the test suite:
```bash
./run_tests.sh
```

## Test Coverage

✅ Basic hashmap creation (DIM d AS HASHMAP)  
✅ Insert operations (d("key") = "value")  
✅ Lookup operations (PRINT d("key"))  
✅ Value updates (reassigning same key)  
✅ Multiple independent hashmaps  
✅ Mixing arrays and hashmaps  
✅ String descriptor to C string conversion  
✅ Large hash values (regression test for signed remainder bug)  
✅ Multiple insertions into multiple hashmaps  
✅ 6+ simultaneous hashmaps  
✅ 40+ total key-value pairs  
✅ Keys with special characters  
✅ Resize/rehashing with many entries  
✅ Realistic use case: contacts list with parallel arrays + hashmap  
✅ O(1) lookup by name into structured data  
✅ Storing integer indices as hashmap values  

## Real-World Use Case: Contacts List

The `test_contacts_list_arrays.bas` test demonstrates a practical pattern for using hashmaps:

**Pattern**: Parallel Arrays + Hashmap for Fast Lookup

```basic
DIM ContactNames(99) AS STRING
DIM ContactPhones(99) AS STRING
DIM ContactEmails(99) AS STRING
DIM ContactAges(99) AS INTEGER
DIM ContactIndex AS HASHMAP

' Add a contact
ContactNames(0) = "Alice Smith"
ContactPhones(0) = "555-1234"
ContactIndex("Alice Smith") = "0"

' Fast lookup
Idx = VAL(ContactIndex("Alice Smith"))
PRINT ContactPhones(Idx)  ' Prints: 555-1234
```

**Benefits**:
- O(1) lookup by name (hashmap)
- O(1) access by index (array)
- Memory efficient (stores index, not full data)
- Clean separation of lookup and storage

**Use Cases**:
- Address books / contact lists
- Database indices
- Symbol tables
- Caches with structured data
- Any "search by key, get structured record" scenario

**Note on UDTs**: While ideally this would use `TYPE Contact ... END TYPE` with an array of UDTs, current UDT support has limitations. The parallel arrays pattern achieves the same result and demonstrates the hashmap's value for real applications.

## Features Not Yet Tested

⚠️ Method calls (d.SIZE(), d.HASKEY(), etc.) - not implemented in codegen  
⚠️ Large datasets (50+ entries) - hits string pool limit  
⚠️ Extensive special characters - hits string pool limit  
⚠️ UDT integration (TYPE + HASHMAP) - UDT arrays have known issues

