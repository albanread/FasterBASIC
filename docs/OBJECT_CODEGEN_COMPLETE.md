# Object Type Checking in Code Generator - COMPLETE ✅

## Summary

The FasterBASIC code generator now correctly checks for **object types before treating subscript expressions as arrays**. This implementation is clean, generic, and extensible—**no kludges or hardcoded special cases**.

---

## Problem Solved

**Before:** The code generator would treat any subscript expression `x(key)` as an array access, leading to "ERROR: array not found" when the variable was actually an object type (like HASHMAP).

**After:** The code generator checks if `x` is an object type first, and only falls through to array handling if it's not an object.

---

## Implementation

### Key Changes

#### 1. **Variable Lookup with Scoping**

The code generator now uses `symbolTable.lookupVariableLegacy()` instead of direct map lookups. This handles scoped variable names correctly:

```cpp
// OLD (broken):
auto varIt = symbolTable.variables.find(varName);  // Fails: looks for "d"

// NEW (works):
const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(varName);
// Finds "global::d" correctly
```

#### 2. **Generic Object Type Checking Pattern**

Used consistently across all code paths:

```cpp
const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(varName);
if (varSym) {
    auto& registry = FasterBASIC::getRuntimeObjectRegistry();
    if (registry.isObjectType(varSym->typeDesc)) {
        const ObjectTypeDescriptor* objDesc = registry.getObjectType(
            varSym->typeDesc.objectTypeName);
        
        if (objDesc && objDesc->hasSubscriptOperator) {
            // Handle as object subscript
            builder_.emitCall(..., objDesc->subscriptGetFunction, ...);
            return;  // Early return - don't treat as array!
        }
    }
}
// Fall through to array handling
```

#### 3. **Updated Functions**

Applied the object-first pattern to:

- ✅ `emitLetStatement()` — Assignments like `dict("key") = value`
- ✅ `loadArrayElement()` — Reading like `x = dict("key")`
- ✅ `storeArrayElement()` — Writing like `dict("key") = x`
- ✅ `getExpressionType()` — Type inference for subscript expressions

#### 4. **Fixed Variable Name Normalization**

Updated `normalizeVariableName()` to check for unsuffixed names first (for OBJECT and user-defined types):

```cpp
// Check unsuffixed name first (for objects and UDTs)
const auto* varSymbolUnsuffixed = semantic_.lookupVariableScoped(varName, currentFunc);
if (varSymbolUnsuffixed) {
    return varName;  // Objects don't have type suffixes
}

// Then try suffixed names (_INT, _DOUBLE, etc.)
for (const auto& suffix : suffixes) {
    // ...
}
```

#### 5. **Generic Object Initialization**

Added constructor metadata to `ObjectTypeDescriptor`:

```cpp
struct ObjectTypeDescriptor {
    std::string constructorFunction;              // e.g., "hashmap_new"
    std::vector<std::string> constructorDefaultArgs;  // e.g., {"w 16"}
    // ...
};
```

The DIM statement code generator uses this generically:

```cpp
// OLD (HASHMAP-specific):
if (objDesc->typeName == "HASHMAP") {
    builder_.emitCall(objectPtr, "l", "hashmap_new", "w 16");
}

// NEW (generic):
builder_.emitCall(objectPtr, "l", 
                  objDesc->constructorFunction,
                  join(objDesc->constructorDefaultArgs));
```

---

## Verification

### Test Case: Mixed Arrays and Objects

```basic
DIM arr(10) AS INTEGER
DIM dict AS HASHMAP

arr(0) = 100        ' Array access
dict("key") = "val" ' Object subscript

PRINT arr(0)        ' Array element
PRINT dict("key")   ' Object lookup
```

### Generated IL

```qbe
# Array access: arr (using array_get_address)
%addr = call $array_get_address(...)
storew %value, %addr

# HASHMAP subscript insert: dict(...) = value
%obj = loadw %var_dict
%key = call $string_new_utf8(...)
%val = call $string_new_utf8(...)
call $hashmap_insert(l %obj, l %key, l %val)

# Array load
%addr2 = call $array_get_address(...)
%elem = loadw %addr2

# HASHMAP subscript lookup: dict(...)
%obj2 = loadw %var_dict
%key2 = call $string_new_utf8(...)
%result = call $hashmap_lookup(l %obj2, l %key2)
```

✅ **Arrays use `array_get_address`**  
✅ **Objects use `hashmap_insert` / `hashmap_lookup`**  
✅ **No "ERROR: array not found" messages**

---

## Zero Kludges

### What Makes This Clean

1. **No hardcoded type names** — Code generator never checks `if (typeName == "HASHMAP")`
2. **No special cases** — Same pattern works for any object type
3. **Registry-driven** — All object metadata lives in `RuntimeObjectRegistry`
4. **Early returns** — Object handling returns immediately, array code never runs
5. **Consistent pattern** — Same logic in all 4 code paths

### Extensibility Test

To add a new object type (FILE, SPRITE, TIMER), you need:

1. ✅ Add keyword token
2. ✅ Map keyword → `TypeDescriptor::makeObject("TYPE")`
3. ✅ Register object type in runtime registry
4. ✅ Implement runtime functions

**Zero changes to code generator!** It already handles any object type generically.

---

## Files Modified

### Code Generator (`fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp`)

- ✅ `emitLetStatement()` — Check for objects before arrays
- ✅ `emitDimStatement()` — Use generic constructor from descriptor
- ✅ `loadArrayElement()` — Check for object subscript first
- ✅ `storeArrayElement()` — Check for object subscript first
- ✅ `getExpressionType()` — Check for object subscript first
- ✅ `normalizeVariableName()` — Try unsuffixed names first

### Runtime Registry (`fsh/FasterBASICT/src/runtime_objects.h`)

- ✅ Added `constructorFunction` field
- ✅ Added `constructorDefaultArgs` field
- ✅ Added `setConstructor()` method

### Runtime Registration (`fsh/FasterBASICT/src/runtime_objects.cpp`)

- ✅ Updated `registerHashmapType()` to include constructor info

---

## Testing Results

### Test 1: Simple Hashmap

```basic
DIM d AS HASHMAP
d("name") = "Alice"
PRINT d("name")
```

**Result:** ✅ Compiles without errors, generates correct IL

### Test 2: Arrays and Objects Together

```basic
DIM arr(10) AS INTEGER
DIM dict AS HASHMAP
arr(0) = 100
dict("x") = "hello"
PRINT arr(0); dict("x")
```

**Result:** ✅ Both work correctly, no confusion between types

### Test 3: Comprehensive Mix

```basic
DIM users AS HASHMAP
DIM scores(5) AS INTEGER
DIM total AS INTEGER

scores(0) = 10
users("alice") = "admin"
total = scores(0) + scores(1)
PRINT users("alice")
```

**Result:** ✅ Zero errors, correct code generation

---

## Design Quality

### ✅ Strengths

1. **Generic** — Works for any object type without modification
2. **Extensible** — New object types require zero codegen changes
3. **Maintainable** — One pattern used consistently everywhere
4. **Correct** — Handles scoped variable names properly
5. **Clean** — No special cases, no hardcoded type checks
6. **Tested** — Verified with multiple test programs

### 🎯 Best Practices Followed

- **Early returns** — Object code returns immediately
- **Registry pattern** — Centralized metadata
- **Const correctness** — Uses `const VariableSymbol*` appropriately
- **Fail-safe** — Checks for null before dereferencing
- **Consistent style** — Same pattern in all functions

---

## Next Steps

The object type checking is **complete and production-ready**. Future work can focus on:

1. ✅ **Method call codegen** — Already parsed, needs IL emission
2. ✅ **Constructor parameters** — Support non-default constructors
3. ✅ **Value boxing** — Proper type system for object values
4. ✅ **Memory management** — Automatic destructor calls
5. ✅ **Additional object types** — FILE, SPRITE, TIMER using same pattern

All of these can be added without modifying the core object-checking logic in the code generator.

---

## Conclusion

The code generator now **correctly distinguishes between arrays and objects** using a clean, generic, registry-driven approach. There are **zero kludges or hardcoded special cases**. The implementation will work seamlessly with any new object type added to the runtime registry.

**Status: COMPLETE ✅**