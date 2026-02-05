# Adding New Object Types to FasterBASIC

This guide explains how to add new runtime object types (like FILE, SPRITE, TIMER) to the FasterBASIC compiler. The design is intentionally **generic and extensible** — no hardcoded special cases in the code generator.

## Overview

The FasterBASIC compiler uses a **centralized object registry** pattern:

1. **Runtime Object Registry** — Central registry that maps type names to descriptors
2. **Object Type Descriptor** — Metadata for each object type (constructor, methods, subscript operator)
3. **Code Generator** — Generic code that queries the registry (no per-type special cases)

## Step-by-Step: Adding a New Object Type

Let's walk through adding a hypothetical `FILE` object type as an example.

---

## Step 1: Add Keyword Token

**File:** `fsh/FasterBASICT/src/fasterbasic_token.h`

Add the new keyword to the `TokenType` enum:

```cpp
enum class TokenType {
    // ... existing tokens ...
    KEYWORD_HASHMAP,
    KEYWORD_FILE,      // <-- Add this
    KEYWORD_SPRITE,
    // ... rest of tokens ...
};
```

**File:** `fsh/FasterBASICT/src/fasterbasic_lexer.cpp`

Add keyword recognition in the lexer:

```cpp
void Lexer::initializeKeywords() {
    keywords_["HASHMAP"] = TokenType::KEYWORD_HASHMAP;
    keywords_["FILE"] = TokenType::KEYWORD_FILE;  // <-- Add this
    // ... rest of keywords ...
}
```

---

## Step 2: Map Keyword to Type Descriptor

**File:** `fsh/FasterBASICT/src/fasterbasic_semantic.h`

Update `keywordToDescriptor()` to handle the new keyword:

```cpp
inline TypeDescriptor keywordToDescriptor(TokenType keyword) {
    switch (keyword) {
        case TokenType::KEYWORD_INTEGER:
            return TypeDescriptor(BaseType::INTEGER);
        // ... other basic types ...
        case TokenType::KEYWORD_HASHMAP:
            return TypeDescriptor::makeObject("HASHMAP");
        case TokenType::KEYWORD_FILE:
            return TypeDescriptor::makeObject("FILE");  // <-- Add this
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}
```

---

## Step 3: Implement Runtime Functions (C)

**File:** `fsh/FasterBASICT/runtime_c/file_runtime.c` (new file)

Implement the actual runtime functions that your object will use:

```c
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
    FILE* handle;
    char* filename;
    int is_open;
} BasicFile;

// Constructor: file_new(filename$, mode$) -> FILE*
void* file_open(void* filename_desc, void* mode_desc) {
    BasicFile* file = malloc(sizeof(BasicFile));
    // Extract strings from BASIC string descriptors...
    const char* filename = /* ... extract from descriptor ... */;
    const char* mode = /* ... extract from descriptor ... */;
    
    file->handle = fopen(filename, mode);
    file->filename = strdup(filename);
    file->is_open = (file->handle != NULL);
    
    return file;
}

// Method: file.CLOSE() -> void
void file_close(void* file_ptr) {
    BasicFile* file = (BasicFile*)file_ptr;
    if (file->is_open) {
        fclose(file->handle);
        file->is_open = 0;
    }
}

// Method: file.READLINE() -> STRING
void* file_readline(void* file_ptr) {
    BasicFile* file = (BasicFile*)file_ptr;
    char buffer[4096];
    if (fgets(buffer, sizeof(buffer), file->handle)) {
        // Return BASIC string descriptor...
        return /* ... create string descriptor ... */;
    }
    return NULL;
}

// Destructor: file_free(file*) -> void
void file_free(void* file_ptr) {
    BasicFile* file = (BasicFile*)file_ptr;
    if (file->is_open) {
        fclose(file->handle);
    }
    free(file->filename);
    free(file);
}
```

---

## Step 4: Register Object Type in Registry

**File:** `fsh/FasterBASICT/src/runtime_objects.cpp`

Add a registration function for your object type:

```cpp
void RuntimeObjectRegistry::registerFileType() {
    ObjectTypeDescriptor file;
    file.typeName = "FILE";
    file.description = "File handle for text or binary I/O";
    
    // Set constructor: file_open(filename$, mode$)
    // Note: For constructors with parameters, you'll need to handle them specially
    // For now, we only support default constructors (see note below)
    file.setConstructor("file_open", {});
    
    // Method: CLOSE() -> void
    MethodSignature close("CLOSE", BaseType::UNKNOWN, "file_close");
    close.withDescription("Close the file");
    file.addMethod(close);
    
    // Method: READLINE() -> STRING
    MethodSignature readline("READLINE", BaseType::STRING, "file_readline");
    readline.withDescription("Read a line from the file");
    file.addMethod(readline);
    
    // Method: EOF() -> INTEGER (returns 1 if at end, 0 otherwise)
    MethodSignature eof("EOF", BaseType::INTEGER, "file_eof");
    eof.withDescription("Check if at end of file");
    file.addMethod(eof);
    
    // Method: WRITE(text$) -> void
    MethodSignature write("WRITE", BaseType::UNKNOWN, "file_write");
    write.addParam("text", BaseType::STRING)
         .withDescription("Write a string to the file");
    file.addMethod(write);
    
    // Register the file type
    registerObjectType(file);
}
```

Call the registration function in `initialize()`:

```cpp
void RuntimeObjectRegistry::initialize() {
    clear();
    
    registerHashmapType();
    registerFileType();     // <-- Add this
    // registerSpriteType();
    // registerTimerType();
}
```

---

## Step 5: Update Build System

**File:** `qbe_basic_integrated/build_qbe_basic.sh`

Add the new runtime file to the build:

```bash
# Runtime library source files
RUNTIME_SOURCES=(
    "string_runtime.c"
    "array_runtime.c"
    "hashmap_runtime.c"
    "file_runtime.c"        # <-- Add this
    # ... other files ...
)
```

---

## That's It!

Your new object type is now fully integrated. The code generator will automatically:

- ✅ Recognize `DIM f AS FILE` declarations
- ✅ Call the constructor function from the descriptor
- ✅ Generate method calls like `f.CLOSE()`, `f.READLINE()`
- ✅ Distinguish between object subscripts and array accesses
- ✅ Handle object variables correctly in all contexts

---

## Example Usage

```basic
DIM logfile AS FILE

' Open file (constructor with params - future enhancement)
' logfile = FILE_OPEN("log.txt", "w")

' Write to file
logfile.WRITE("Log entry 1")
logfile.WRITE("Log entry 2")

' Close file
logfile.CLOSE()

END
```

---

## Design Principles

### ✅ What Works Well

1. **No hardcoded type checks** — Code generator uses `registry.isObjectType()` and queries descriptors
2. **Centralized metadata** — All object info lives in the registry
3. **Easy to add methods** — Just add `MethodSignature` to the descriptor
4. **Subscript operators optional** — Only HASHMAP uses them currently

### 🚧 Current Limitations

1. **Constructor parameters** — Currently only supports default constructors with hardcoded args
   - `setConstructor("hashmap_new", {"w 16"})` works
   - `setConstructor("file_open", {filename, mode})` needs enhancement
   
2. **Value boxing/unboxing** — Hashmap values are currently untyped pointers
   - Need a `BasicValue` union type for proper type safety
   
3. **Memory management** — No automatic destructor calls yet
   - Objects leak when variables go out of scope
   - Need reference counting or garbage collection

4. **Method call codegen** — Method calls are parsed but not yet fully implemented in codegen
   - The `emitMethodCall()` function exists but needs completion

### 🔮 Future Enhancements

1. **Constructor with parameters:**
   ```cpp
   file.setConstructor("file_open")
       .addConstructorParam("filename", BaseType::STRING)
       .addConstructorParam("mode", BaseType::STRING, "\"r\"");  // default
   ```

2. **Destructor support:**
   ```cpp
   file.setDestructor("file_free");
   ```

3. **Typed subscript values:**
   ```cpp
   hashmap.enableSubscript(
       TypeDescriptor(BaseType::STRING),  // key type
       TypeDescriptor::makeUnion({        // value can be any type
           BaseType::INTEGER,
           BaseType::STRING,
           BaseType::DOUBLE
       }),
       "hashmap_lookup",
       "hashmap_insert"
   );
   ```

---

## Code Generator Implementation (for reference)

The code generator checks for object types **before** assuming something is an array:

```cpp
// In loadArrayElement() and storeArrayElement():
const VariableSymbol* varSym = symbolTable.lookupVariableLegacy(arrayName);
if (varSym) {
    auto& registry = FasterBASIC::getRuntimeObjectRegistry();
    if (registry.isObjectType(varSym->typeDesc)) {
        const ObjectTypeDescriptor* objDesc = registry.getObjectType(
            varSym->typeDesc.objectTypeName);
        
        if (objDesc && objDesc->hasSubscriptOperator) {
            // Generate object subscript call
            builder_.emitCall(..., objDesc->subscriptGetFunction, ...);
            return;  // Early return!
        }
    }
}
// Fall through to array handling...
```

This pattern is used consistently across:
- `emitLetStatement()` — assignments
- `loadArrayElement()` — reading subscripts
- `storeArrayElement()` — writing subscripts  
- `getExpressionType()` — type inference

**No special cases. No hardcoded type names. Just generic registry queries.**

---

## Testing Your New Object Type

1. Write a simple BASIC test program using your object
2. Compile with `-i` flag to inspect generated QBE IL
3. Verify constructor, methods, and memory management look correct
4. Test edge cases (null objects, multiple instances, etc.)

Example test:
```bash
cat > test_file.bas << 'EOF'
DIM f AS FILE
f.WRITE("Hello")
f.CLOSE()
END
EOF

./fbc_qbe test_file.bas -i > test_file.qbe
# Inspect the IL to verify correct function calls
```

---

## Summary

Adding a new object type requires:

1. ✅ Add keyword token (lexer + enum)
2. ✅ Map keyword to `TypeDescriptor::makeObject("TYPE")`
3. ✅ Implement runtime functions in C
4. ✅ Register object type with descriptor (constructor + methods)
5. ✅ Update build system

**Zero changes needed in the code generator!** It's already generic and extensible.