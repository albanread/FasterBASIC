# FasterBASIC C-Native Plugin System Design

## Overview

FasterBASIC's plugin system allows extending the language with custom commands and functions through dynamically loaded C/C++ libraries. This document describes the native C ABI plugin interface that replaced the previous Lua-based system.

**Status**: Design & Implementation Phase  
**Date**: February 2025  
**Version**: 2.0 (C-Native)

---

## Architecture

### Key Components

1. **Plugin Interface** (`plugin_interface.h`)
   - C ABI function signatures for plugins
   - Metadata export functions
   - Registration callbacks

2. **Plugin Loader** (`plugin_loader.cpp/h`)
   - Dynamic library loading (dlopen/LoadLibrary)
   - Plugin validation and lifecycle management
   - Directory scanning (enabled/disabled)

3. **Command Registry** (`modular_commands.h/cpp`)
   - Stores plugin commands/functions
   - Maps BASIC names to native C function pointers
   - Type information for parameters and returns

4. **Code Generator Integration** (`codegen_v2/`)
   - Emits QBE IL calls to plugin functions
   - Marshals arguments from BASIC types to C types
   - Handles return value conversion

---

## Plugin Structure

### Minimal Plugin Example

```c
// example_plugin.c
#include "plugin_interface.h"
#include <stdio.h>

// ============================================================================
// Plugin Metadata
// ============================================================================

const char* FB_PLUGIN_NAME() {
    return "ExamplePlugin";
}

const char* FB_PLUGIN_VERSION() {
    return "1.0.0";
}

const char* FB_PLUGIN_DESCRIPTION() {
    return "Example plugin demonstrating C-native interface";
}

const char* FB_PLUGIN_AUTHOR() {
    return "Your Name";
}

int FB_PLUGIN_API_VERSION() {
    return FB_PLUGIN_API_VERSION_CURRENT;
}

// ============================================================================
// Plugin Functions (called from BASIC code)
// ============================================================================

// Example: GREET(name$) - Prints a greeting
void greet_impl(FB_RuntimeContext* ctx) {
    // Get string parameter
    const char* name = fb_get_string_param(ctx, 0);
    
    printf("Hello, %s!\n", name);
    
    // Return (void function, no return value)
}

// Example: ADD(a, b) AS INTEGER - Returns sum
void add_impl(FB_RuntimeContext* ctx) {
    // Get integer parameters
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    
    // Return result
    fb_return_int(ctx, a + b);
}

// ============================================================================
// Plugin Initialization
// ============================================================================

int FB_PLUGIN_INIT(FB_PluginCallbacks* callbacks) {
    void* userData = callbacks->userData;
    
    // Register GREET command (no return value)
    int cmd1 = callbacks->beginCommand(
        userData,
        "GREET",                          // BASIC name
        "Print a greeting message",       // Description
        (FB_FunctionPtr)greet_impl,       // C function pointer
        "examples"                        // Category
    );
    callbacks->addParameter(userData, cmd1, "name", FB_PARAM_STRING, 
                           "Name to greet", 0, NULL);
    callbacks->endCommand(userData, cmd1);
    
    // Register ADD function (returns INTEGER)
    int cmd2 = callbacks->beginFunction(
        userData,
        "ADD",                            // BASIC name
        "Add two numbers",                // Description
        (FB_FunctionPtr)add_impl,         // C function pointer
        "math",                           // Category
        FB_RETURN_INT                     // Return type
    );
    callbacks->addParameter(userData, cmd2, "a", FB_PARAM_INT, 
                           "First number", 0, "0");
    callbacks->addParameter(userData, cmd2, "b", FB_PARAM_INT, 
                           "Second number", 0, "0");
    callbacks->endCommand(userData, cmd2);
    
    return 0; // Success
}

void FB_PLUGIN_SHUTDOWN() {
    // Cleanup if needed
}
```

### Using the Plugin in BASIC

```basic
' Load plugin at runtime
LOADPLUGIN "example_plugin.dylib"

' Use plugin commands
GREET("World")

' Use plugin functions
result = ADD(10, 20)
PRINT "10 + 20 = "; result
```

---

## Plugin Interface Reference

### Runtime Context

All plugin functions receive a `FB_RuntimeContext*` pointer containing:
- Parameter values (accessed by index)
- Return value storage
- Error handling
- Memory allocation helpers

### Parameter Access Functions

```c
// Get parameters by index (0-based)
int32_t    fb_get_int_param(FB_RuntimeContext* ctx, int index);
int64_t    fb_get_long_param(FB_RuntimeContext* ctx, int index);
float      fb_get_float_param(FB_RuntimeContext* ctx, int index);
double     fb_get_double_param(FB_RuntimeContext* ctx, int index);
const char* fb_get_string_param(FB_RuntimeContext* ctx, int index);
int        fb_get_bool_param(FB_RuntimeContext* ctx, int index);

// Check parameter count
int fb_param_count(FB_RuntimeContext* ctx);
```

### Return Value Functions

```c
void fb_return_int(FB_RuntimeContext* ctx, int32_t value);
void fb_return_long(FB_RuntimeContext* ctx, int64_t value);
void fb_return_float(FB_RuntimeContext* ctx, float value);
void fb_return_double(FB_RuntimeContext* ctx, double value);
void fb_return_string(FB_RuntimeContext* ctx, const char* value);
void fb_return_bool(FB_RuntimeContext* ctx, int value);
```

### Error Handling

```c
void fb_set_error(FB_RuntimeContext* ctx, const char* message);
int  fb_has_error(FB_RuntimeContext* ctx);
```

### Memory Management

```c
// Allocate memory (freed automatically when function returns)
void* fb_alloc(FB_RuntimeContext* ctx, size_t size);

// Create string (managed by runtime, reference counted)
const char* fb_create_string(FB_RuntimeContext* ctx, const char* str);
```

---

## Parameter Types

| FB Type | C Type | Description |
|---------|--------|-------------|
| `FB_PARAM_INT` | `int32_t` | 32-bit integer |
| `FB_PARAM_LONG` | `int64_t` | 64-bit integer |
| `FB_PARAM_FLOAT` | `float` | 32-bit float |
| `FB_PARAM_DOUBLE` | `double` | 64-bit float |
| `FB_PARAM_STRING` | `const char*` | UTF-8 string |
| `FB_PARAM_BOOL` | `int` | Boolean (0=false, non-zero=true) |

## Return Types

| FB Type | C Type | Description |
|---------|--------|-------------|
| `FB_RETURN_VOID` | - | No return value (command) |
| `FB_RETURN_INT` | `int32_t` | 32-bit integer |
| `FB_RETURN_LONG` | `int64_t` | 64-bit integer |
| `FB_RETURN_FLOAT` | `float` | 32-bit float |
| `FB_RETURN_DOUBLE` | `double` | 64-bit float |
| `FB_RETURN_STRING` | `const char*` | UTF-8 string |
| `FB_RETURN_BOOL` | `int` | Boolean |

---

## Plugin Lifecycle

### 1. Discovery
- Plugin loader scans `plugins/enabled/` directory
- Finds `.dylib` (macOS), `.so` (Linux), `.dll` (Windows) files

### 2. Loading
- `dlopen()` / `LoadLibrary()` loads the shared library
- Validates required exports exist
- Checks API version compatibility

### 3. Initialization
- Calls `FB_PLUGIN_INIT(callbacks)`
- Plugin registers commands/functions via callbacks
- Commands added to global registry

### 4. Compilation
- BASIC source references plugin commands
- Code generator emits QBE IL calls to plugin functions
- Type checking ensures parameter/return type safety

### 5. Runtime
- Compiled program calls plugin functions directly
- Runtime marshals arguments and return values
- Context provides error handling and memory management

### 6. Shutdown
- Calls `FB_PLUGIN_SHUTDOWN()` when unloading
- Plugin cleans up resources
- `dlclose()` / `FreeLibrary()` unloads library

---

## Advanced Features

### Optional Parameters

```c
callbacks->addParameter(userData, cmdId, "count", FB_PARAM_INT, 
                       "Number of times", 1, "1");  // Optional, default=1
```

### Variadic Functions

Use `fb_param_count()` to handle variable argument lists:

```c
void sum_all_impl(FB_RuntimeContext* ctx) {
    int count = fb_param_count(ctx);
    int32_t sum = 0;
    
    for (int i = 0; i < count; i++) {
        sum += fb_get_int_param(ctx, i);
    }
    
    fb_return_int(ctx, sum);
}
```

### Working with Arrays

```c
// Arrays passed as opaque handles
FB_ArrayHandle arr = fb_get_array_param(ctx, 0);

// Access array elements
int32_t value = fb_array_get_int(arr, index);
fb_array_set_int(arr, index, new_value);

// Query array properties
int size = fb_array_size(arr);
int dims = fb_array_dimensions(arr);
```

### Working with UDTs

```c
// UDTs passed as opaque handles
FB_UDTHandle udt = fb_get_udt_param(ctx, 0);

// Access UDT fields by name
int32_t age = fb_udt_get_int(udt, "Age");
const char* name = fb_udt_get_string(udt, "Name");

// Modify UDT fields
fb_udt_set_int(udt, "Age", 25);
fb_udt_set_string(udt, "Name", "Alice");
```

---

## Building Plugins

### macOS

```bash
clang -shared -fPIC -o myplugin.dylib myplugin.c \
      -I/path/to/fasterbasic/include
```

### Linux

```bash
gcc -shared -fPIC -o myplugin.so myplugin.c \
    -I/path/to/fasterbasic/include
```

### Windows

```bash
cl /LD myplugin.c /I C:\path\to\fasterbasic\include
```

---

## Example Plugin Ideas

### Math Extensions
- `FACTORIAL(n)`, `ISPRIME(n)`, `GCD(a,b)`, `LCM(a,b)`
- `CLAMP(val,min,max)`, `LERP(a,b,t)`

### File Operations
- `FILEEXISTS(path$)`, `FILESIZE(path$)`, `FILECOPY(src$, dst$)`
- `DIRLIST(path$)` - returns array of files

### Date/Time
- `NOW()`, `TODAY()`, `TIMEPARSE(fmt$, str$)`
- `DATEADD(date, days)`, `DATEDIFF(date1, date2)`

### Networking
- `HTTPGET(url$)`, `HTTPPOST(url$, data$)`
- `SOCKETOPEN(host$, port)`, `SOCKETREAD(handle)`

### Graphics (SDL2, OpenGL bindings)
- `DRAWPIXEL(x, y, color)`, `DRAWLINE(x1, y1, x2, y2)`
- `LOADIMAGE(path$)`, `BLIT(image, x, y)`

### Database
- `DBOPEN(path$)`, `DBQUERY(sql$)`, `DBEXEC(sql$)`
- `DBFETCH()`, `DBCLOSE()`

---

## Migration from Lua Plugins

### Changes

| Old (Lua) | New (C-Native) |
|-----------|----------------|
| Lua function name string | C function pointer |
| `lua_State*` parameter | `FB_RuntimeContext*` |
| `lua_to*()` functions | `fb_get_*_param()` |
| `lua_push*()` functions | `fb_return_*()` |
| Lua runtime required | No runtime dependency |

### Benefits

- ✅ **Faster**: No Lua interpreter overhead
- ✅ **Simpler**: No Lua runtime to embed/initialize
- ✅ **Smaller**: No LuaJIT dependency (~500KB saved)
- ✅ **Type-safe**: Compile-time type checking
- ✅ **Debuggable**: Use native debuggers (gdb, lldb)
- ✅ **Portable**: Standard C ABI, any language can create plugins

---

## Implementation Status

### ✅ Completed
- Plugin interface design
- Lua removal plan

### 🚧 In Progress
- Update `plugin_interface.h` with C function pointers
- Implement runtime context and parameter access
- Update plugin loader to skip Lua initialization

### 📋 TODO
- Update code generator to emit direct C calls
- Create example plugins (math, file, datetime)
- Write plugin developer guide
- Add plugin template/skeleton generator
- Test suite for plugin system
- Documentation for plugin API versioning

---

## Security Considerations

1. **Plugin Validation**: Check API version before loading
2. **Sandboxing**: Plugins run in same process (trusted code only)
3. **Resource Limits**: Future: Add memory/CPU limits per plugin
4. **Code Signing**: Future: Verify plugin signatures before loading

---

## Performance Notes

- Plugin function calls have minimal overhead (~10ns on modern CPU)
- No marshaling overhead for POD types (int, float, etc.)
- String parameters use zero-copy when possible
- Array/UDT access goes through handles (slight indirection cost)

---

## Future Enhancements

1. **Hot Reload**: Reload plugins without restarting compiler
2. **Plugin Dependencies**: Plugins can depend on other plugins
3. **Async Functions**: Support for async/callback-based plugins
4. **FFI Generator**: Auto-generate plugin wrappers from C headers
5. **Package Manager**: Download plugins from central repository

---

**Last Updated**: February 5, 2025  
**Author**: FasterBASIC Development Team