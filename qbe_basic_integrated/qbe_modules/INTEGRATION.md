# Integrating QBE Hashmap Module with FasterBASIC

This document describes how to integrate the QBE hashmap module into the FasterBASIC compiler and runtime.

## Overview

The hashmap module provides a complete hash table implementation in QBE IL that can be linked into FasterBASIC programs. Integration requires:

1. Building the hashmap module
2. Updating the code generator to emit hashmap calls
3. Modifying the build system to link the hashmap object file
4. Adding runtime support for reference counting integration

---

## Step 1: Build the Hashmap Module

### Automatic Build Integration

Add hashmap module compilation to the main build script:

```bash
# In build_qbe_basic.sh, after Step 4 (runtime files):

echo "Building QBE modules..."
cd "$PROJECT_ROOT/qbe_modules"
make hashmap.o
if [ $? -ne 0 ]; then
    echo "  ✗ QBE modules compilation failed"
    exit 1
fi
echo "  ✓ QBE modules built"
cd "$PROJECT_ROOT"
```

### Manual Build

```bash
cd qbe_basic_integrated/qbe_modules
make hashmap.o
```

This produces `hashmap.o` ready for linking.

---

## Step 2: Code Generator Changes

### 2.1 Detect HASHMAP Usage

In `qbe_codegen_v2.cpp` or semantic analyzer, track when `HASHMAP` types are declared:

```cpp
class CodeGenContext {
    bool uses_hashmap = false;
    // ... other fields
};

void visitDimStatement(DimNode* node) {
    if (node->type == TypeKind::HASHMAP) {
        context.uses_hashmap = true;
    }
    // ... rest of implementation
}
```

### 2.2 Emit Function Declarations

Add hashmap function declarations to QBE output when `uses_hashmap` is true:

```cpp
void emitHashmapDeclarations(QBEBuilder& qbe) {
    qbe.emitLine("# Hashmap runtime functions");
    qbe.emitLine("export function l $hashmap_new(w)");
    qbe.emitLine("export function $hashmap_free(l)");
    qbe.emitLine("export function w $hashmap_insert(l, l, l)");
    qbe.emitLine("export function l $hashmap_lookup(l, l)");
    qbe.emitLine("export function w $hashmap_has_key(l, l)");
    qbe.emitLine("export function w $hashmap_remove(l, l)");
    qbe.emitLine("export function l $hashmap_size(l)");
    qbe.emitLine("export function $hashmap_clear(l)");
    qbe.emitLine("export function l $hashmap_keys(l)");
    qbe.emitLine("");
}
```

### 2.3 Lower BASIC Syntax to QBE Calls

#### DIM dict AS HASHMAP

```cpp
void emitHashmapDeclaration(const std::string& varname) {
    // %dict =l call $hashmap_new(w 16)
    std::string temp = allocateTemp();
    emit(temp + " =l call $hashmap_new(w 16)");
    storeVariable(varname, temp);
}
```

#### dict("key") = value (Assignment)

```cpp
void emitHashmapInsert(const std::string& mapVar, 
                       const std::string& keyExpr, 
                       const std::string& valueExpr) {
    // Load map pointer
    std::string map = loadVariable(mapVar);
    
    // Load or create key string
    std::string key = emitExpression(keyExpr);
    
    // Load or create value
    std::string value = emitExpression(valueExpr);
    
    // Increment value refcount if needed
    if (isRefcountedType(valueExpr)) {
        emit("call $str_retain(l " + value + ")");
    }
    
    // Call hashmap_insert
    std::string result = allocateTemp();
    emit(result + " =w call $hashmap_insert(l " + map + 
         ", l " + key + ", l " + value + ")");
    
    // Check result (optional: error handling)
}
```

#### x = dict("key") (Lookup)

```cpp
void emitHashmapLookup(const std::string& mapVar, 
                       const std::string& keyExpr) {
    std::string map = loadVariable(mapVar);
    std::string key = emitExpression(keyExpr);
    
    std::string result = allocateTemp();
    emit(result + " =l call $hashmap_lookup(l " + map + 
         ", l " + key + ")");
    
    // TODO: Check for NULL, throw error if key not found
    // (unless using .GET with default)
    
    return result;
}
```

#### IF dict.HASKEY("key")

```cpp
void emitHashmapHasKey(const std::string& mapVar, 
                       const std::string& keyExpr) {
    std::string map = loadVariable(mapVar);
    std::string key = emitExpression(keyExpr);
    
    std::string result = allocateTemp();
    emit(result + " =w call $hashmap_has_key(l " + map + 
         ", l " + key + ")");
    
    return result;
}
```

#### dict.REMOVE("key")

```cpp
void emitHashmapRemove(const std::string& mapVar, 
                       const std::string& keyExpr) {
    std::string map = loadVariable(mapVar);
    std::string key = emitExpression(keyExpr);
    
    // Get value before removing (for refcount)
    std::string value = allocateTemp();
    emit(value + " =l call $hashmap_lookup(l " + map + 
         ", l " + key + ")");
    
    // Remove from map
    std::string removed = allocateTemp();
    emit(removed + " =w call $hashmap_remove(l " + map + 
         ", l " + key + ")");
    
    // Decrement refcount if value was found
    if (isRefcountedType(mapVar)) {
        std::string not_null = allocateTemp();
        std::string label_release = allocateLabel("release");
        std::string label_done = allocateLabel("done");
        
        emit(not_null + " =w cnel " + value + ", 0");
        emit("jnz " + not_null + ", " + label_release + ", " + label_done);
        emitLabel(label_release);
        emit("call $str_release(l " + value + ")");
        emitLabel(label_done);
    }
}
```

#### FOR EACH key IN dict.KEYS()

```cpp
void emitHashmapKeysIteration(const std::string& keyVar,
                               const std::string& mapVar,
                               const std::string& loopBody) {
    std::string map = loadVariable(mapVar);
    
    // Get keys array
    std::string keys = allocateTemp();
    emit(keys + " =l call $hashmap_keys(l " + map + ")");
    
    // Iterate over array
    std::string index = allocateTemp();
    emit(index + " =l copy 0");
    
    std::string loop_check = allocateLabel("keys_loop_check");
    std::string loop_body = allocateLabel("keys_loop_body");
    std::string loop_end = allocateLabel("keys_loop_end");
    
    emitLabel(loop_check);
    
    // Load key pointer at keys[index]
    std::string offset = allocateTemp();
    emit(offset + " =l mul " + index + ", 8");
    std::string key_ptr_addr = allocateTemp();
    emit(key_ptr_addr + " =l add " + keys + ", " + offset);
    std::string key_ptr = allocateTemp();
    emit(key_ptr + " =l loadl " + key_ptr_addr);
    
    // Check if NULL (end of array)
    std::string is_null = allocateTemp();
    emit(is_null + " =w ceql " + key_ptr + ", 0");
    emit("jnz " + is_null + ", " + loop_end + ", " + loop_body);
    
    emitLabel(loop_body);
    storeVariable(keyVar, key_ptr);
    
    // Emit loop body statements
    emitStatements(loopBody);
    
    // Increment index
    std::string next_index = allocateTemp();
    emit(next_index + " =l add " + index + ", 1");
    emit(index + " =l copy " + next_index);
    emit("jmp " + loop_check);
    
    emitLabel(loop_end);
    
    // Free keys array
    emit("call $free(l " + keys + ")");
}
```

---

## Step 3: Build System Integration

### 3.1 Update Compiler Linking

Modify the compiler to track hashmap usage and add to link line:

```cpp
// In main compilation function
bool uses_hashmap = detectHashmapUsage(ast);

// When linking
std::string link_cmd = "cc -o " + output_file + " " + 
                       obj_file + " " + runtime_objects;

if (uses_hashmap) {
    link_cmd += " " + project_root + "/qbe_modules/hashmap.o";
}
```

### 3.2 Update fbc_qbe Wrapper

In `basic_frontend.cpp`, track if hashmap is used and include it:

```cpp
// After compiling .bas to QBE and QBE to .s
if (program_uses_hashmap) {
    std::string hashmap_obj = project_root + "/qbe_modules/hashmap.o";
    // Include in link command
}
```

---

## Step 4: Runtime Integration

### 4.1 String Key Management

Hashmap calls `strdup()` for keys. Ensure it's available:

```c
// In basic_runtime.c or memory_mgmt.c
char* strdup(const char* s) {
    size_t len = strlen(s) + 1;
    char* dup = malloc(len);
    if (dup) memcpy(dup, s, len);
    return dup;
}
```

### 4.2 Value Reference Counting

When storing BasicString or other refcounted types:

```c
// Before insert
void hashmap_insert_string(HashMap* map, const char* key, BasicString* value) {
    str_retain(value);  // Increment refcount
    hashmap_insert(map, key, (void*)value);
}

// After remove
void hashmap_remove_string(HashMap* map, const char* key) {
    BasicString* value = (BasicString*)hashmap_lookup(map, key);
    if (value) {
        hashmap_remove(map, key);
        str_release(value);  // Decrement refcount
    }
}

// When freeing map
void hashmap_free_strings(HashMap* map) {
    char** keys = (char**)hashmap_keys(map);
    if (keys) {
        for (int i = 0; keys[i]; i++) {
            BasicString* value = (BasicString*)hashmap_lookup(map, keys[i]);
            if (value) str_release(value);
        }
        free(keys);
    }
    hashmap_free(map);
}
```

---

## Step 5: Testing Integration

### 5.1 Create Test Programs

Test basic hashmap operations:

```basic
REM test_hashmap_basic.bas
DIM dict AS HASHMAP
dict("test") = 42
PRINT dict("test")
```

Compile and run:

```bash
./fbc_qbe test_hashmap_basic.bas -o test_hashmap_basic
./test_hashmap_basic
```

### 5.2 Verify Linking

Check that `hashmap.o` is included:

```bash
./fbc_qbe test_hashmap_basic.bas -c -o test.s  # QBE -> assembly
cc -v test.s runtime/*.o qbe_modules/hashmap.o -o test  # Link with verbose
```

Should see `hashmap.o` in link command.

---

## Step 6: Conditional Compilation

### 6.1 Compiler Flag

Add a feature flag for testing:

```bash
./fbc_qbe --enable-hashmap input.bas
```

Or detect automatically from AST.

### 6.2 Graceful Degradation

If hashmap module not available, emit error:

```cpp
if (uses_hashmap && !hashmap_module_available()) {
    error("HASHMAP type requires hashmap.o module. "
          "Run 'make hashmap.o' in qbe_modules/");
}
```

---

## Example: Complete Workflow

### 1. Build hashmap module
```bash
cd qbe_basic_integrated/qbe_modules
make hashmap.o
cd ../..
```

### 2. Write BASIC program
```basic
DIM ages AS HASHMAP
ages("Alice") = 30
PRINT ages("Alice")
```

### 3. Compile
```bash
./fbc_qbe example.bas -o example
```

Compiler should:
- Detect `HASHMAP` usage
- Emit QBE calls to `$hashmap_*`
- Link with `hashmap.o`

### 4. Run
```bash
./example
# Output: 30
```

---

## Debugging Tips

### Check QBE Output

```bash
./fbc_qbe example.bas -i -o example.qbe
```

Look for:
- `export function` declarations for hashmap
- `call $hashmap_new(w 16)`
- `call $hashmap_insert(l %map, l %key, l %value)`

### Verify Object File

```bash
nm qbe_modules/hashmap.o | grep hashmap
```

Should show all exported symbols:
```
T _hashmap_new
T _hashmap_insert
T _hashmap_lookup
...
```

### Link Errors

If you see undefined references:
- Ensure `hashmap.o` is in link command
- Check symbol names match (underscore prefix on macOS)
- Verify QBE compiled with correct target

---

## Performance Considerations

### 1. Hash Function Overhead

For integer keys, consider direct hash (no string conversion):

```qbe
export function w $hashmap_insert_int(l %map, l %key_int, l %value) {
    %hash =w call $hashmap_hash_int(l %key_int)
    # ... rest of implementation
}
```

### 2. Resize Strategy

Default: resize at 70% load. For known sizes, pre-allocate:

```basic
DIM large_dict AS HASHMAP(100)  ' Pre-allocate capacity
```

### 3. Memory Management

- Keys are copied (overhead for large keys)
- Values are pointers only (no copy)
- Consider string interning for repeated keys

---

## Future Enhancements

1. **Integer Keys** - Avoid string conversion overhead
2. **Type-Specific Maps** - Optimized for common value types
3. **Weak References** - Don't increment refcount
4. **Concurrent Access** - Add locking for thread safety
5. **Serialization** - Save/load hashmap to disk

---

## Troubleshooting

### "Undefined reference to hashmap_new"

**Solution:** Add `qbe_modules/hashmap.o` to link command

### "Symbol not found: _hashmap_new"

**macOS:** QBE adds underscore prefix. Ensure consistency.

**Solution:** Check QBE target in `config.h`

### Segmentation fault on hashmap operation

**Debug:**
1. Verify map pointer is not NULL
2. Check key string is null-terminated
3. Enable address sanitizer: `cc -fsanitize=address`

### Memory leaks

**Check:**
1. All values have matching retain/release
2. `hashmap_free()` called before program exit
3. `hashmap_keys()` result is freed

---

## Summary

Integration checklist:

- [ ] Build `hashmap.o` module
- [ ] Update code generator to detect HASHMAP usage
- [ ] Emit QBE function declarations
- [ ] Lower BASIC syntax to QBE calls
- [ ] Add hashmap.o to link command
- [ ] Implement reference counting wrappers
- [ ] Test with sample programs
- [ ] Update documentation

Once complete, FasterBASIC programs can use hash maps as a first-class data structure!