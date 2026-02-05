# FasterBASIC Plugin API Quick Reference
**API Version:** 2.0 (C-Native)

---

## Essential Headers

```c
#include "plugin_interface.h"  // Plugin registration API
#include "plugin_support.h"    // Runtime functions (optional)
```

---

## Plugin Skeleton

```c
#include "plugin_interface.h"

// Your plugin functions
void my_function_impl(FB_RuntimeContext* ctx) {
    int32_t param = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, param * 2);
}

// Plugin metadata
FB_PLUGIN_BEGIN("My Plugin", "1.0.0", "Description", "Author")

// Plugin initialization
FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "MYFUNC", "Description",
                    my_function_impl, FB_RETURN_INT, "category")
        .addParameter("n", FB_PARAM_INT, "Parameter description")
        .finish();
    return 0;
}

// Plugin shutdown
FB_PLUGIN_SHUTDOWN() {
    // Cleanup if needed
}
```

---

## Parameter Access

```c
// Get parameters (0-indexed)
int32_t    n = fb_get_int_param(ctx, 0);
int64_t    l = fb_get_long_param(ctx, 0);
float      f = fb_get_float_param(ctx, 0);
double     d = fb_get_double_param(ctx, 0);
const char* s = fb_get_string_param(ctx, 0);
int        b = fb_get_bool_param(ctx, 0);

// Get parameter count
int count = fb_param_count(ctx);
```

---

## Return Values

```c
fb_return_int(ctx, 42);
fb_return_long(ctx, 1234567890L);
fb_return_float(ctx, 3.14f);
fb_return_double(ctx, 2.718281828);
fb_return_string(ctx, "Hello");
fb_return_bool(ctx, 1);  // -1 for BASIC TRUE
```

---

## Error Handling

```c
// Set error
if (invalid_input) {
    fb_set_error(ctx, "Error message");
    return;
}

// Check for errors
if (fb_has_error(ctx)) {
    return;
}
```

---

## Memory Management

```c
// Allocate temporary memory (freed automatically)
char* buffer = (char*)fb_alloc(ctx, 1024);

// Create temporary string copy
const char* str = fb_create_string(ctx, "text");
```

---

## Parameter Types

| Type | Enum | BASIC Example |
|------|------|---------------|
| Integer | `FB_PARAM_INT` | `42` |
| Long | `FB_PARAM_LONG` | `1234567890&` |
| Float | `FB_PARAM_FLOAT` | `3.14!` |
| Double | `FB_PARAM_DOUBLE` | `2.718281828#` |
| String | `FB_PARAM_STRING` | `"Hello"` |
| Boolean | `FB_PARAM_BOOL` | `-1` (TRUE) or `0` (FALSE) |

---

## Return Types

| Type | Enum | BASIC Example |
|------|------|---------------|
| Void | `FB_RETURN_VOID` | (commands only) |
| Integer | `FB_RETURN_INT` | `x = FUNC()` |
| Long | `FB_RETURN_LONG` | `x& = FUNC&()` |
| Float | `FB_RETURN_FLOAT` | `x! = FUNC!()` |
| Double | `FB_RETURN_DOUBLE` | `x# = FUNC#()` |
| String | `FB_RETURN_STRING` | `x$ = FUNC$()` |
| Boolean | `FB_RETURN_BOOL` | `IF FUNC() THEN` |

---

## Registration Patterns

### Simple Command (No Return Value)

```c
void print_hello_impl(FB_RuntimeContext* ctx) {
    const char* name = fb_get_string_param(ctx, 0);
    printf("Hello, %s!\n", name);
}

FB_PLUGIN_INIT(callbacks) {
    FB_BeginCommand(callbacks, "SAYHELLO", "Print greeting",
                   print_hello_impl, "console")
        .addParameter("name", FB_PARAM_STRING, "Name to greet")
        .finish();
    return 0;
}
```

### Function with Return Value

```c
void add_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    fb_return_int(ctx, a + b);
}

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "ADD", "Add two numbers",
                    add_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    return 0;
}
```

### Optional Parameters

```c
void greet_impl(FB_RuntimeContext* ctx) {
    const char* name = fb_get_string_param(ctx, 0);
    const char* greeting = fb_get_string_param(ctx, 1);
    printf("%s, %s!\n", greeting, name);
}

FB_PLUGIN_INIT(callbacks) {
    FB_BeginCommand(callbacks, "GREET", "Print custom greeting",
                   greet_impl, "console")
        .addParameter("name", FB_PARAM_STRING, "Name")
        .addOptionalParameter("greeting", FB_PARAM_STRING, 
                            "Greeting", "Hello")
        .finish();
    return 0;
}
```

---

## Common Patterns

### Input Validation

```c
void factorial_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    if (n < 0) {
        fb_set_error(ctx, "Input must be non-negative");
        return;
    }
    
    if (n > 20) {
        fb_set_error(ctx, "Input too large (max 20)");
        return;
    }
    
    // Calculate factorial...
}
```

### String Processing

```c
void reverse_impl(FB_RuntimeContext* ctx) {
    const char* input = fb_get_string_param(ctx, 0);
    size_t len = strlen(input);
    
    // Allocate buffer
    char* output = (char*)fb_alloc(ctx, len + 1);
    
    // Reverse string
    for (size_t i = 0; i < len; i++) {
        output[i] = input[len - 1 - i];
    }
    output[len] = '\0';
    
    fb_return_string(ctx, output);
}
```

### Multiple Return Types

```c
// Integer version
void max_int_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    fb_return_int(ctx, (a > b) ? a : b);
}

// Double version
void max_double_impl(FB_RuntimeContext* ctx) {
    double a = fb_get_double_param(ctx, 0);
    double b = fb_get_double_param(ctx, 1);
    fb_return_double(ctx, (a > b) ? a : b);
}

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "MAXI", "Max of two integers",
                    max_int_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First")
        .addParameter("b", FB_PARAM_INT, "Second")
        .finish();
    
    FB_BeginFunction(callbacks, "MAXD", "Max of two doubles",
                    max_double_impl, FB_RETURN_DOUBLE, "math")
        .addParameter("a", FB_PARAM_DOUBLE, "First")
        .addParameter("b", FB_PARAM_DOUBLE, "Second")
        .finish();
    
    return 0;
}
```

---

## Build Commands

### macOS
```bash
clang -shared -fPIC -o myplugin.dylib myplugin.c \
      -I../fsh/FasterBASICT/src
```

### Linux
```bash
gcc -shared -fPIC -o myplugin.so myplugin.c \
    -I../fsh/FasterBASICT/src
```

### Windows (MinGW)
```bash
gcc -shared -o myplugin.dll myplugin.c \
    -I..\fsh\FasterBASICT\src
```

### Windows (MSVC)
```bash
cl /LD myplugin.c /I..\fsh\FasterBASICT\src
```

---

## Usage in BASIC

```basic
REM Load plugin
LOADPLUGIN "myplugin.dylib"

REM Call command (no return value)
SAYHELLO "World"

REM Call function (returns value)
result = ADD(10, 20)
PRINT result

REM Optional parameters
GREET "Alice"              ' Uses default greeting
GREET "Bob", "Hi"          ' Custom greeting

REM Error handling
ON ERROR GOTO handler
result = FACTORIAL(-5)
PRINT result
END

handler:
    PRINT "Error: "; ERR$
    RESUME NEXT
```

---

## Type Conversion Rules

### Automatic Conversions
- INT ↔ LONG ↔ FLOAT ↔ DOUBLE (may lose precision)
- BOOL → 1 (TRUE) or 0 (FALSE)
- STRING → 0 (for numeric types)

### No Conversion
- STRING cannot convert to numbers automatically
- Use `fb_str_to_int()` or similar if needed

---

## Memory Rules

### Safe (Automatic Cleanup)
✅ `fb_alloc()` - Freed when function returns
✅ `fb_create_string()` - Freed when function returns
✅ Parameter strings - Valid for entire function call
✅ Return strings - Copied to temp storage

### Unsafe (Manual Management)
❌ `malloc()` - Must call `free()` yourself
❌ Global variables - Must manage lifetime
❌ Static buffers - Must be thread-safe

---

## Performance Tips

1. **Minimize allocations** - Reuse buffers when possible
2. **Avoid string copying** - Use `fb_get_string_param()` directly
3. **Check parameter count** - `fb_param_count()` to validate
4. **Early returns** - Validate inputs first, compute later
5. **Use appropriate types** - INT for small numbers, LONG for large

---

## Error Codes (from plugin_support.h)

```c
#define FB_ERR_ILLEGAL_CALL     5
#define FB_ERR_OVERFLOW         6
#define FB_ERR_SUBSCRIPT        9
#define FB_ERR_DIV_ZERO        11
#define FB_ERR_TYPE_MISMATCH   13
#define FB_ERR_BAD_FILE        52
#define FB_ERR_FILE_NOT_FOUND  53
#define FB_ERR_DISK_FULL       61
#define FB_ERR_INPUT_PAST_END  62
```

---

## Categories (Recommended)

- `"math"` - Mathematical functions
- `"string"` - String manipulation
- `"file"` - File I/O operations
- `"graphics"` - Graphics/drawing
- `"audio"` - Sound/music
- `"network"` - Networking
- `"console"` - Console/terminal
- `"system"` - System operations
- `"custom"` - Custom/uncategorized

---

## Debugging Tips

### Print Debug Info
```c
printf("DEBUG: n=%d\n", n);
fflush(stdout);
```

### Check Parameter Count
```c
int count = fb_param_count(ctx);
printf("Received %d parameters\n", count);
```

### Verify String Parameters
```c
const char* s = fb_get_string_param(ctx, 0);
printf("String: '%s' (len=%zu)\n", s, strlen(s));
```

### Check for Errors
```c
if (fb_has_error(ctx)) {
    printf("Error occurred!\n");
    return;
}
```

---

## Common Mistakes

❌ **Don't forget to return a value**
```c
void myfunc_impl(FB_RuntimeContext* ctx) {
    int result = 42;
    // WRONG: Missing fb_return_int(ctx, result);
}
```

❌ **Don't modify parameter strings**
```c
void bad_impl(FB_RuntimeContext* ctx) {
    char* s = (char*)fb_get_string_param(ctx, 0);
    s[0] = 'X';  // WRONG: Parameter strings are const
}
```

❌ **Don't access invalid parameter indices**
```c
void bad_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);  // WRONG if only 1 param
}
```

✅ **Always validate parameter count**
```c
void good_impl(FB_RuntimeContext* ctx) {
    if (fb_param_count(ctx) < 2) {
        fb_set_error(ctx, "Expected 2 parameters");
        return;
    }
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);
}
```

---

## Further Reading

- `plugin_interface.h` - Complete API specification
- `plugin_support.h` - Runtime function reference
- `example_math_plugin.c` - Working example plugin
- `PLUGIN_SYSTEM_C_NATIVE.md` - Design document
- `PLUGIN_PHASE2_IMPLEMENTATION.md` - Implementation details

---

**Version:** 2.0  
**Last Updated:** 2024  
**Questions?** See docs/ folder for detailed documentation