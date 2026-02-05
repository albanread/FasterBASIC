# FasterBASIC Plugin API Quick Reference Card

**Version:** 2.0 (C-Native)  
**Date:** February 2026  
**Phase:** 3 Complete

---

## 📋 Minimal Plugin Template

```c
#include "plugin_interface.h"

void my_func_impl(FB_RuntimeContext* ctx) {
    int value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 2);
}

FB_PLUGIN_BEGIN("Plugin Name", "1.0", "Description", "Author")

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "MYFUNC", "Description", 
                     my_func_impl, FB_RETURN_INT)
        .addParameter("x", FB_PARAM_INT, "Description")
        .finish();
    return 0;
}

FB_PLUGIN_SHUTDOWN() {}
```

---

## 🔧 Build Commands

### Linux
```bash
cc -shared -fPIC -o plugin.so plugin.c -I path/to/plugin_interface.h
```

### macOS
```bash
cc -dynamiclib -o plugin.dylib plugin.c -I path/to/plugin_interface.h
```

### Windows
```bash
cl /LD plugin.c /I path\to\plugin_interface.h
```

---

## 📥 Parameter Access

### Get Parameters
```c
int32_t  fb_get_int_param(ctx, index);
int64_t  fb_get_long_param(ctx, index);
float    fb_get_float_param(ctx, index);
double   fb_get_double_param(ctx, index);
const char* fb_get_string_param(ctx, index);  // NULL-terminated C string
int      fb_get_bool_param(ctx, index);        // 0 or 1
int      fb_param_count(ctx);                  // Number of parameters
```

### Example
```c
void example_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);      // First parameter
    float b = fb_get_float_param(ctx, 1);  // Second parameter
    const char* s = fb_get_string_param(ctx, 2);  // Third parameter
    
    // Use parameters...
}
```

---

## 📤 Return Values

### Set Return Value
```c
void fb_return_int(ctx, int32_t value);
void fb_return_long(ctx, int64_t value);
void fb_return_float(ctx, float value);
void fb_return_double(ctx, double value);
void fb_return_string(ctx, const char* value);
void fb_return_bool(ctx, int value);
```

### Example
```c
void add_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);
    fb_return_int(ctx, a + b);
}

void greet_impl(FB_RuntimeContext* ctx) {
    const char* name = fb_get_string_param(ctx, 0);
    char* greeting = fb_alloc(ctx, 256);
    sprintf(greeting, "Hello, %s!", name);
    fb_return_string(ctx, greeting);
}
```

---

## 🚨 Error Handling

### Set Error
```c
void fb_set_error(ctx, const char* message);
int  fb_has_error(ctx);
```

### Example
```c
void divide_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);
    
    if (b == 0) {
        fb_set_error(ctx, "Division by zero");
        return;
    }
    
    fb_return_int(ctx, a / b);
}
```

---

## 🧠 Memory Management

### Allocate Memory (Auto-freed)
```c
void* fb_alloc(ctx, size_t size);
const char* fb_create_string(ctx, const char* str);
```

### Example
```c
void concat_impl(FB_RuntimeContext* ctx) {
    const char* a = fb_get_string_param(ctx, 0);
    const char* b = fb_get_string_param(ctx, 1);
    
    size_t len = strlen(a) + strlen(b) + 1;
    char* result = fb_alloc(ctx, len);
    
    strcpy(result, a);
    strcat(result, b);
    
    fb_return_string(ctx, result);
    // Memory automatically freed when function returns
}
```

---

## 📝 Plugin Registration

### Register Function (Returns Value)
```c
FB_BeginFunction(callbacks, "NAME", "Description", func_ptr, return_type, "category")
    .addParameter("param1", type, "Description")
    .addParameter("param2", type, "Description")
    .finish();
```

### Register Command (Void Return)
```c
FB_BeginCommand(callbacks, "NAME", "Description", func_ptr, "category")
    .addParameter("param1", type, "Description")
    .finish();
```

### Example
```c
FB_PLUGIN_INIT(callbacks) {
    // Function with return value
    FB_BeginFunction(callbacks, "ADD", "Add two numbers", 
                     add_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    
    // Command (no return value)
    FB_BeginCommand(callbacks, "PRINT_DEBUG", "Print debug message",
                    print_debug_impl, "debug")
        .addParameter("msg", FB_PARAM_STRING, "Message")
        .finish();
    
    return 0;  // Success
}
```

---

## 🔢 Parameter Types

| Type | Enum | C Type | BASIC Example |
|------|------|--------|---------------|
| Integer | `FB_PARAM_INT` | `int32_t` | `x%` |
| Long | `FB_PARAM_LONG` | `int64_t` | `x&` |
| Float | `FB_PARAM_FLOAT` | `float` | `x!` |
| Double | `FB_PARAM_DOUBLE` | `double` | `x#` |
| String | `FB_PARAM_STRING` | `const char*` | `x$` |
| Boolean | `FB_PARAM_BOOL` | `int` | `x%` (0 or 1) |

---

## 🎯 Return Types

| Type | Enum | C Type |
|------|------|--------|
| Integer | `FB_RETURN_INT` | `int32_t` |
| Long | `FB_RETURN_LONG` | `int64_t` |
| Float | `FB_RETURN_FLOAT` | `float` |
| Double | `FB_RETURN_DOUBLE` | `double` |
| String | `FB_RETURN_STRING` | `const char*` |
| Boolean | `FB_RETURN_BOOL` | `int` |
| Void | `FB_RETURN_VOID` | (none) |

---

## 🔄 Type Conversions

The runtime automatically converts between types:

```c
// Automatic conversions happen transparently
void flexible_impl(FB_RuntimeContext* ctx) {
    // Can get as int even if BASIC passes float
    int value = fb_get_int_param(ctx, 0);  // 3.14 → 3
    
    // Can get as float even if BASIC passes int
    float fval = fb_get_float_param(ctx, 0);  // 42 → 42.0
    
    // Strings return "" if parameter is not a string
    const char* s = fb_get_string_param(ctx, 0);
}
```

---

## 📚 Common Patterns

### Simple Math Function
```c
void square_impl(FB_RuntimeContext* ctx) {
    int x = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, x * x);
}
```

### String Function
```c
void repeat_impl(FB_RuntimeContext* ctx) {
    const char* str = fb_get_string_param(ctx, 0);
    int count = fb_get_int_param(ctx, 1);
    
    size_t len = strlen(str) * count + 1;
    char* result = fb_alloc(ctx, len);
    
    result[0] = '\0';
    for (int i = 0; i < count; i++) {
        strcat(result, str);
    }
    
    fb_return_string(ctx, result);
}
```

### Validation with Error
```c
void validate_impl(FB_RuntimeContext* ctx) {
    int value = fb_get_int_param(ctx, 0);
    
    if (value < 0) {
        fb_set_error(ctx, "Value must be non-negative");
        return;
    }
    
    if (value > 100) {
        fb_set_error(ctx, "Value must be <= 100");
        return;
    }
    
    fb_return_int(ctx, value);  // Valid
}
```

### Multi-Parameter Function
```c
void clamp_impl(FB_RuntimeContext* ctx) {
    double value = fb_get_double_param(ctx, 0);
    double min = fb_get_double_param(ctx, 1);
    double max = fb_get_double_param(ctx, 2);
    
    if (value < min) value = min;
    if (value > max) value = max;
    
    fb_return_double(ctx, value);
}
```

### Command (Void Return)
```c
void log_impl(FB_RuntimeContext* ctx) {
    const char* level = fb_get_string_param(ctx, 0);
    const char* message = fb_get_string_param(ctx, 1);
    
    printf("[%s] %s\n", level, message);
    // No return value
}
```

---

## 🎮 BASIC Usage

### Call Function
```basic
result% = MYFUNC(42)
```

### Call Command
```basic
MYCOMMAND "argument"
```

### With Multiple Parameters
```basic
sum% = ADD(10, 20)
msg$ = REPEAT$("Hi", 3)
clamped# = CLAMP(5.5, 0.0, 10.0)
```

---

## ⚡ Performance Tips

1. **Minimize allocations** - Reuse buffers when possible
2. **Use appropriate types** - INT for integers, not DOUBLE
3. **Avoid string copies** - Return references when safe
4. **Check error conditions early** - Fail fast
5. **Keep functions simple** - One function, one job

---

## 🐛 Debugging

### Print Debug Info
```c
void debug_impl(FB_RuntimeContext* ctx) {
    int count = fb_param_count(ctx);
    printf("Received %d parameters\n", count);
    
    for (int i = 0; i < count; i++) {
        int value = fb_get_int_param(ctx, i);
        printf("  Param %d: %d\n", i, value);
    }
}
```

### Check for Errors
```c
if (fb_has_error(ctx)) {
    // Error already set, return early
    return;
}
```

---

## ✅ Checklist

- [ ] Include `plugin_interface.h`
- [ ] Implement function with `FB_RuntimeContext* ctx` parameter
- [ ] Use `FB_PLUGIN_BEGIN` macro for metadata
- [ ] Register functions in `FB_PLUGIN_INIT`
- [ ] Return 0 from init (success)
- [ ] Compile with `-shared -fPIC` (or platform equivalent)
- [ ] Test in BASIC program
- [ ] Handle errors gracefully
- [ ] Free memory properly (use fb_alloc)
- [ ] Document your plugin

---

## 📖 Full Documentation

- **Complete API:** `plugin_interface.h`
- **Examples:** `docs/test_math_plugin.c`
- **Tutorial:** `docs/PHASE3_README.md`
- **Details:** `docs/phase3_completion.md`

---

**Quick Start:** Copy the minimal template, modify the function, compile, and use!

**Happy Plugin Development!** 🚀