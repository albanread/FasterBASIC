# FasterBASIC Object System Design

**Date**: December 2024  
**Status**: Core Infrastructure Complete

---

## Overview

FasterBASIC now has a proper **object system** to support runtime-created objects with methods. This infrastructure allows the compiler to understand and validate operations on opaque object types (like HASHMAP, FILE, SPRITE) that are created and managed by C runtime functions.

---

## Key Concepts

### 1. Runtime Objects

**What are they?**
- Opaque handles (pointers) returned by C runtime functions
- Cannot be directly manipulated by BASIC code
- Have associated methods that operate on them
- May support subscript operators (e.g., `dict("key")`)

**Examples:**
- `HASHMAP` - Dictionary/hash table
- `FILE` - File handle (future)
- `SPRITE` - 2D graphics sprite (future)
- `TIMER` - Event timer (future)

### 2. Object Types vs Primitive Types

**Primitive Types** (INTEGER, DOUBLE, STRING):
- Values stored directly in variables
- Operations are built-in language operators (+, -, *, etc.)
- Type conversions are automatic

**Object Types** (HASHMAP, FILE, etc.):
- Variables hold opaque pointers
- Operations are method calls (`.SIZE()`, `.CLOSE()`, etc.)
- May support subscript operators (`dict("key")`)
- Cannot be type-converted

---

## Architecture

### Core Components

```
┌─────────────────────────────────────────────────────────────┐
│                 RuntimeObjectRegistry                        │
│  (Singleton - initialized at compiler startup)               │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  registerObjectType(ObjectTypeDescriptor)                   │
│  getObjectType(BaseType) -> ObjectTypeDescriptor*           │
│  isObjectType(BaseType) -> bool                             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                          │
                          │ contains
                          ▼
        ┌────────────────────────────────────┐
        │    ObjectTypeDescriptor            │
        │  (One per object type: HASHMAP)    │
        ├────────────────────────────────────┤
        │  typeName: "HASHMAP"               │
        │  baseType: BaseType::HASHMAP       │
        │  hasSubscriptOperator: true        │
        │  methods: [MethodSignature...]     │
        └────────────────────────────────────┘
                          │
                          │ contains
                          ▼
                ┌─────────────────────────┐
                │   MethodSignature       │
                │  (One per method)       │
                ├─────────────────────────┤
                │  name: "HASKEY"         │
                │  parameters: [...]      │
                │  returnType: INTEGER    │
                │  runtimeFunctionName:   │
                │    "hashmap_has_key"    │
                └─────────────────────────┘
```

### Data Structures

#### `MethodSignature`
Describes a method callable on an object:
- **name**: Method name (e.g., "HASKEY")
- **parameters**: List of parameters with types and optionality
- **returnType**: Return type (UNKNOWN for void methods)
- **runtimeFunctionName**: C function to call (e.g., "hashmap_has_key")

#### `ObjectTypeDescriptor`
Describes a runtime object type:
- **typeName**: Human-readable name (e.g., "HASHMAP")
- **baseType**: Corresponding `BaseType` enum value
- **methods**: List of `MethodSignature` objects
- **hasSubscriptOperator**: Whether `obj(key)` syntax is supported
- **subscriptKeyType**: Type of key for subscript operator
- **subscriptGetFunction**: C function for `value = obj(key)`
- **subscriptSetFunction**: C function for `obj(key) = value`

#### `RuntimeObjectRegistry`
Singleton registry of all known object types:
- Initialized once at compiler startup
- Queried by semantic analyzer to validate method calls
- Queried by code generator to emit correct runtime calls

---

## Usage in Compiler Pipeline

### 1. Initialization

```cpp
// In main() or compiler initialization:
FasterBASIC::initializeRuntimeObjectRegistry();
```

This registers all known object types (currently just HASHMAP).

### 2. Semantic Analysis

When validating method calls:

```cpp
// Check if variable is an object type
auto* varSym = lookupVariable(varName);
auto& registry = getRuntimeObjectRegistry();

if (registry.isObjectType(varSym->typeDesc.baseType)) {
    // Look up object descriptor
    auto* objDesc = registry.getObjectType(varSym->typeDesc.baseType);
    
    // Find method
    auto* method = objDesc->findMethod(methodName);
    if (!method) {
        error("Object has no method '" + methodName + "'");
    }
    
    // Validate argument types against method signature
    validateMethodArguments(callExpr->arguments, method->parameters);
}
```

When validating subscript operators:

```cpp
// dict("key") = value
if (registry.isObjectType(varType)) {
    auto* objDesc = registry.getObjectType(varType);
    if (objDesc->hasSubscriptOperator) {
        // Validate key type matches
        validateType(keyExpr, objDesc->subscriptKeyType);
    } else {
        error("Object does not support subscript operator");
    }
}
```

### 3. Code Generation

When emitting method calls:

```cpp
std::string ASTEmitter::emitMethodCall(const MethodCallExpression* expr) {
    auto& registry = getRuntimeObjectRegistry();
    auto* objDesc = registry.getObjectType(objectType);
    auto* method = objDesc->findMethod(expr->methodName);
    
    // Use runtime function name from registry
    builder_.emitCall(result, qbeType, method->runtimeFunctionName, args);
}
```

When emitting subscript operators:

```cpp
// dict("key") lookup
auto* objDesc = registry.getObjectType(BaseType::HASHMAP);
builder_.emitCall(result, "l", objDesc->subscriptGetFunction, args);

// dict("key") = value assignment
builder_.emitCall(result, "w", objDesc->subscriptSetFunction, args);
```

---

## Registering New Object Types

To add a new object type (e.g., FILE):

### Step 1: Add to BaseType enum

```cpp
// fasterbasic_semantic.h
enum class BaseType {
    // ... existing types ...
    HASHMAP,
    FILE,    // NEW
};
```

### Step 2: Register in RuntimeObjectRegistry

```cpp
// runtime_objects.cpp
void RuntimeObjectRegistry::registerFileType() {
    ObjectTypeDescriptor file;
    file.typeName = "FILE";
    file.baseType = BaseType::FILE;
    file.description = "File handle for I/O operations";
    
    // Add methods
    MethodSignature close("CLOSE", BaseType::UNKNOWN, "file_close");
    close.withDescription("Close the file");
    file.addMethod(close);
    
    MethodSignature eof("EOF", BaseType::INTEGER, "file_eof");
    eof.withDescription("Check if at end of file");
    file.addMethod(eof);
    
    MethodSignature read("READ", BaseType::STRING, "file_read");
    read.addParam("bytes", BaseType::INTEGER)
        .withDescription("Read bytes from file");
    file.addMethod(read);
    
    // Register
    registerObjectType(file);
}

void RuntimeObjectRegistry::initialize() {
    registerHashmapType();
    registerFileType();  // NEW
}
```

### Step 3: Create Runtime Implementation

```c
// runtime/file_runtime.c
void* file_open(const char* path, const char* mode) {
    FILE* f = fopen(path, mode);
    return (void*)f;
}

void file_close(void* handle) {
    if (handle) fclose((FILE*)handle);
}

int file_eof(void* handle) {
    return handle ? feof((FILE*)handle) : 1;
}
```

### Step 4: Use in BASIC

```basic
DIM f AS FILE
f = OPEN("data.txt", "r")

WHILE NOT f.EOF()
    line$ = f.READ(100)
    PRINT line$
WEND

f.CLOSE()
```

---

## Benefits

### 1. Type Safety
- Method calls are validated at compile time
- Wrong method names are caught immediately
- Argument types are checked against signatures

### 2. Extensibility
- Adding new object types requires no parser changes
- No hard-coded method names scattered through code
- Registration is centralized and declarative

### 3. Maintainability
- Object behavior defined in one place
- Consistent handling across compiler phases
- Self-documenting through descriptions

### 4. Clean Separation
- Semantic analyzer validates against signatures
- Code generator uses runtime function names from registry
- Runtime implements actual functionality

---

## Implementation Status

### ✅ Complete
- Core data structures (`MethodSignature`, `ObjectTypeDescriptor`, `RuntimeObjectRegistry`)
- Registry implementation with HASHMAP registered
- Full HASHMAP object descriptor with 5 methods
- Subscript operator support for HASHMAP

### 🚧 In Progress
- Semantic analyzer integration (updating to use registry)
- Code generator integration (updating to use registry)
- Method call validation logic
- Subscript operator validation logic

### 📋 TODO
- Initialize registry at compiler startup
- Update existing hashmap code to use registry
- Add FILE object type
- Add SPRITE object type
- Add comprehensive tests
- Update documentation

---

## Design Principles

### 1. Opaque Handles
Objects are always pointers (`void*` in C, `l` in QBE). BASIC code cannot inspect or manipulate the internal structure - only call methods.

### 2. Runtime Ownership
The C runtime owns object memory. BASIC code gets handles. The runtime provides `_new` and `_free` functions.

### 3. Method-Based Interface
All operations on objects happen through methods. There are no special operators except the optional subscript operator.

### 4. Compile-Time Validation
The compiler validates all method calls and subscript operations. Runtime errors are minimized.

### 5. No Inheritance or Polymorphism
Objects are simple - they have methods, that's it. No class hierarchies, no virtual dispatch, no interfaces.

---

## Comparison with Other Languages

### Python
```python
d = {}                    # Built-in dict type
d["key"] = "value"        # Subscript operator
d.keys()                  # Method call
```

### FasterBASIC
```basic
DIM d AS HASHMAP          ' Explicit type declaration
d("key") = "value"        ' Subscript operator (BASIC style)
keys = d.KEYS()           ' Method call (case-insensitive)
```

### Key Differences
- FasterBASIC requires explicit type declarations
- Methods use dot notation like OOP languages
- No dynamic typing - types checked at compile time
- Objects are opaque handles, not compound values

---

## Future Enhancements

### 1. Typed Collections
```basic
DIM scores AS HASHMAP OF INTEGER
scores("alice") = 95      ' Type-checked at compile time
```

### 2. Property Syntax
```basic
PRINT sprite.X            ' Read property
sprite.X = 100            ' Write property
```

### 3. Constructor Arguments
```basic
DIM dict AS HASHMAP(capacity: 1000)
```

### 4. Automatic Resource Management
```basic
SUB ProcessFile()
    DIM f AS FILE = OPEN("data.txt")
    ' ... use file ...
END SUB  ' f.CLOSE() called automatically
```

---

## Conclusion

The object system provides a clean, extensible foundation for runtime-created objects in FasterBASIC. It maintains BASIC's simplicity while enabling powerful runtime capabilities through a method-based interface.

**Next Step**: Integrate the registry into semantic analysis and code generation to replace hard-coded hashmap handling with registry-based lookups.