# Object System Implementation Progress

## Summary

This document tracks the progress of implementing a first-class object system for runtime types (HASHMAP, FILE, etc.) in the FasterBASIC compiler.

## Architecture Changes

### 1. Unified Object Type System

**Problem Identified**: The compiler had TWO parallel type systems:
- **Old system**: `VariableType` enum (INT, FLOAT, DOUBLE, STRING, etc.)
- **New system**: `BaseType` enum with `TypeDescriptor` struct (BYTE, INTEGER, LONG, OBJECT, USER_DEFINED, etc.)

This dual system caused bugs and confusion, with conversion functions like `descriptorToLegacyType()` bridging the gap.

**Solution**: Continuing migration to the NEW system (`TypeDescriptor` with `BaseType`), as this is where OBJECT types live.

### 2. BaseType::OBJECT Instead of Per-Type Enums

**Previous Approach**: Adding `BaseType::HASHMAP`, `BaseType::FILE`, etc. (doesn't scale)

**New Approach**: 
- Single `BaseType::OBJECT` enum value
- `TypeDescriptor::objectTypeName` field identifies specific object type (e.g., "HASHMAP")
- `RuntimeObjectRegistry` maps object type names to descriptors
- Like `BaseType::USER_DEFINED` uses `udtName`, `BaseType::OBJECT` uses `objectTypeName`

### 3. Runtime Object Registry

A singleton registry (`RuntimeObjectRegistry`) stores metadata for all runtime object types:
- Object type name (e.g., "HASHMAP")
- Subscript operator support (e.g., `dict("key")`)
- Method signatures with parameter/return types
- Runtime function names for code generation

**Initialization**:
- `initializeRuntimeObjectRegistry()` called in `main()`
- Also called in `SemanticAnalyzer` constructor as safety measure (ensures registry is initialized even if main forgets)

## Key Fixes Implemented

### 1. Variable Declaration (Semantic Analysis)

**File**: `fasterbasic_semantic.cpp::processDimStatement()`

**Problem**: For `DIM d AS HASHMAP`, the code was checking `arrayDim.asTypeName` (which is empty for keyword types) instead of `arrayDim.asTypeKeyword`.

**Fix**: Check `asTypeKeyword` FIRST (for built-in types like HASHMAP, INTEGER, etc.), then fall back to `asTypeName` (for user-defined types):

```cpp
// Check asTypeKeyword first (for built-in types like HASHMAP, INTEGER, etc.)
if (arrayDim.hasAsType && arrayDim.asTypeKeyword != TokenType::UNKNOWN) {
    // Use keywordToDescriptor to get correct type from keyword token
    typeDesc = keywordToDescriptor(arrayDim.asTypeKeyword);
} else if (arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
    // AS TypeName (for user-defined types)
    // ...
}
```

This matches how array declarations work.

### 2. Variable Name Normalization

**File**: `fasterbasic_semantic.cpp::normalizeVariableName()`

**Problem**: Object types were falling through to default case and getting incorrect suffixes.

**Fix**: Object types (like USER_DEFINED types) don't use suffixes - return base name:

```cpp
case BaseType::OBJECT:
    // Object types don't get a suffix (like USER_DEFINED types)
    return baseName;
```

### 3. Array Access Validation

**File**: `fasterbasic_semantic.cpp::inferArrayAccessType()`

**Problem**: Object subscript access (`dict("key")`) was being validated as array access AFTER other checks.

**Fix**: Check for objects FIRST, before treating as arrays:

```cpp
// Check if this is an object with subscript operator (like hashmap) FIRST
// This must come before function/array checks to avoid treating objects as arrays
auto* varSym = lookupVariable(expr.name);
auto& registry = getRuntimeObjectRegistry();

if (varSym && registry.isObjectType(varSym->typeDesc)) {
    auto* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
    if (objDesc && objDesc->hasSubscriptOperator) {
        // Handle as object subscript, return early
        // ...
    }
}
```

### 4. Array Usage Tracking

**File**: `fasterbasic_semantic.cpp::useArray()`

**Problem**: When validating `d("test")`, the function generated "Array used without DIM" error because it didn't recognize objects.

**Fix**: Added object check before array validation:

```cpp
// Check if this is an object with subscript operator (like hashmap)
auto* varSym = lookupVariable(name);
if (varSym && varSym->typeDesc.isObject()) {
    auto& registry = getRuntimeObjectRegistry();
    if (registry.isObjectType(varSym->typeDesc)) {
        auto* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
        if (objDesc && objDesc->hasSubscriptOperator) {
            // This is an object subscript operation, not an array - skip array validation
            return;
        }
    }
}
```

### 5. LET Statement Validation

**File**: `fasterbasic_semantic.cpp::validateLetStatement()`

**Problem**: Used `m_symbolTable.lookupVariableLegacy()` directly, which didn't work correctly.

**Fix**: Use `lookupVariable()` which goes through the proper lookup chain:

```cpp
// Check if this is an object with subscript operator (like hashmap)
auto* varSym = lookupVariable(stmt.variable);  // Changed from lookupVariableLegacy
auto& registry = getRuntimeObjectRegistry();
bool isObject = (varSym && registry.isObjectType(varSym->typeDesc));
```

## Current Status

### ✅ Working: Semantic Analysis

- `DIM d AS HASHMAP` declarations are recognized
- Variables are properly stored with `BaseType::OBJECT` and `objectTypeName="HASHMAP"`
- Object subscript access `d("key")` doesn't generate "array without DIM" errors
- Assignment `d("key") = "value"` is validated correctly
- Reading `PRINT d("key")` is validated correctly

### ⚠️ Partial: Code Generation

- `hashmap_new()` is called for initialization ✅
- Object pointer is stored in variable ✅
- Subscript operations (`d("key")`) still show `# ERROR: array not found: d` ❌

**Next Steps for Codegen**:
1. Update `ast_emitter.cpp::loadArrayElement()` to check for objects first
2. Update `ast_emitter.cpp::emitLetStatement()` subscript assignment path
3. Use `RuntimeObjectRegistry` to get subscript get/set function names
4. Generate proper calls to `hashmap_insert()` and `hashmap_lookup()`

### ❌ Not Yet Implemented

- Method calls (`.SIZE()`, `.HASKEY()`, `.REMOVE()`, etc.)
- Reference counting for hashmap values
- Boxing/unboxing for numeric values
- `.KEYS()` array conversion
- Automatic linking of runtime library

## Test Case

```basic
DIM d AS HASHMAP
PRINT "Step 1 OK"
d("test") = "value"  
PRINT "Step 2 OK"
END
```

**Current Result**: 
- ✅ Semantic analysis passes (no errors)
- ✅ `hashmap_new()` called
- ❌ Codegen shows `# ERROR: array not found: d` for subscript operations

## Files Modified

### Core Type System
- `fsh/FasterBASICT/src/fasterbasic_semantic.h` - Added `BaseType::OBJECT`, `TypeDescriptor::objectTypeName`, `TypeDescriptor::makeObject()`
- `fsh/FasterBASICT/src/fasterbasic_semantic.cpp` - Fixed variable declaration and lookup for objects

### Runtime Object Registry
- `fsh/FasterBASICT/src/runtime_objects.h` - Object registry interface
- `fsh/FasterBASICT/src/runtime_objects.cpp` - Object registry implementation with HASHMAP registration

### Initialization
- `fsh/FasterBASICT/src/fbc_qbe.cpp` - Call `initializeRuntimeObjectRegistry()` in main
- `fsh/FasterBASICT/src/fasterbasic_semantic.cpp` - Call `getRuntimeObjectRegistry().initialize()` in constructor

### Build System
- `qbe_basic_integrated/build_qbe_basic.sh` - Added `runtime_objects.cpp` to build

## Design Decisions

### Why Not Use BaseType Per Object?

**Bad**: `BaseType::HASHMAP`, `BaseType::FILE`, `BaseType::SPRITE`, etc.

**Good**: `BaseType::OBJECT` with `objectTypeName` field

**Reasons**:
1. Scalability - can add new object types without modifying enum
2. Consistency - mirrors how `BaseType::USER_DEFINED` uses `udtName`
3. Flexibility - object types can be registered at runtime
4. Separation of concerns - type system doesn't need to know about every object

### Registry as Singleton

The `RuntimeObjectRegistry` uses the singleton pattern to ensure:
1. Only one registry exists
2. All compiler phases use the same registry
3. Registry survives across compilation units
4. Easy access via `getRuntimeObjectRegistry()`

### Object Types Don't Use Suffixes

Like `USER_DEFINED` types, `OBJECT` types don't append suffixes to variable names:
- `DIM x AS INTEGER` → stored as `x_INT`
- `DIM p AS Point` → stored as `p` (no suffix)
- `DIM d AS HASHMAP` → stored as `d` (no suffix)

This keeps object variable names clean and matches user-defined type behavior.

## Lessons Learned

1. **Always use clean builds** - incremental builds can hide issues with header changes
2. **Dual type systems are dangerous** - need to complete migration to new system
3. **Check keyword types first** - parser sets `asTypeKeyword` for built-in types, not `asTypeName`
4. **Objects must be checked BEFORE arrays** - subscript syntax `x(key)` is ambiguous
5. **Registry must be initialized early** - add to both main() and relevant constructors as safety
6. **Use consistent lookup methods** - `lookupVariable()` vs `lookupVariableLegacy()` can give different results

## Next Session Goals

1. **Fix codegen for subscript operations** - make `d("key")` actually call `hashmap_lookup/insert`
2. **Implement method call codegen** - emit calls to registry-specified functions
3. **Add reference counting** - wrap/unwrap values with retain/release
4. **Test end-to-end** - compile and run a hashmap test program
5. **Clean up dual type system** - migrate more code to TypeDescriptor

## Reference

- Thread: "FasterBASIC QBE Hashmap Methods"
- Design doc: `OBJECT_SYSTEM_DESIGN.md`
- Status doc: `HASHMAP_STATUS.md`
