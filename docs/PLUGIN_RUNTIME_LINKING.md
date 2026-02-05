# Plugin Runtime Linking - How Plugins Work at Compile and Runtime

**Last Updated:** February 2026  
**Plugin API Version:** 2.0 (C-Native)

---

## 🎯 The Two Phases of Plugins

Understanding how plugins work requires understanding **two separate phases**:

### Phase 1: Compile Time (Compiler Process)
The FasterBASIC compiler itself loads plugins to know what commands are available.

### Phase 2: Runtime (Generated Executable)
The compiled BASIC program needs to call plugin functions.

---

## 📋 Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                      COMPILE TIME                            │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Compiler Process                                           │
│  ├─ Loads plugins/enabled/*.so (dlopen)                     │
│  ├─ Plugin registers commands: "I have DOUBLE()"            │
│  ├─ Compiler generates code that calls DOUBLE()             │
│  └─ Knows function pointer address (ASLR issue!)            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                       LINK TIME                              │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  QBE IL → Assembly → Object Files                           │
│  ├─ Compile: basic_runtime.c → basic_runtime.o              │
│  ├─ Compile: plugin_context_runtime.c → runtime.o           │
│  ├─ Compile: [plugin runtime files] → *.o                   │
│  └─ Link: temp.s + *.o + plugins/*.so → executable          │
│                                                              │
│  ⚠️  CRITICAL: Plugin .so/.dylib is LINKED into executable  │
│                                                              │
└─────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────┐
│                       RUNTIME                                │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  Generated Executable Runs                                  │
│  ├─ Plugin functions available (linked in!)                 │
│  ├─ Calls plugin functions directly                         │
│  └─ Uses plugin_context_runtime for marshalling             │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔧 What Gets Linked Into the Executable

### 1. FasterBASIC Runtime (Always)
These C files are compiled and linked into every BASIC program:

```
basic_runtime.c              - Core runtime (print, input, etc.)
io_ops.c                     - I/O operations
string_ops.c                 - String operations
array_ops.c                  - Array operations
plugin_context_runtime.c     - Plugin context API ⭐
... (more runtime files)
```

**Result:** `~50KB` of runtime code in every executable

### 2. Plugin Runtime Files (If Plugin Specifies)
Plugins can specify additional C files they need:

```c
// In plugin:
FB_PLUGIN_RUNTIME_FILES("my_helpers.c, data_parser.c")
```

These files are:
1. Found in plugin's directory
2. Compiled to `.o` files
3. Linked into the executable

**Result:** Additional `~10-20KB` per plugin (varies)

### 3. Plugin Library Itself (Always)
The plugin `.so`/`.dylib` is linked as a shared library:

```bash
cc -o program temp.s runtime.o ... plugins/enabled/myplugin.so
```

**Result:** Plugin code available at runtime

---

## 🎭 Two Types of Plugin Code

### Type 1: Command Implementation (Plugin .so)
This is the plugin's **logic** - what it actually does:

```c
// In myplugin.c (compiled to myplugin.so)
void double_impl(FB_RuntimeContext* ctx) {
    int value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 2);
}
```

This code is:
- ✅ In the plugin `.so`/`.dylib`
- ✅ Linked into the final executable
- ✅ Called at runtime by generated code

### Type 2: Helper Functions (Optional Runtime Files)
Additional support code the plugin needs:

```c
// In my_helpers.c (specified by FB_PLUGIN_RUNTIME_FILES)
int my_special_calculation(int x, int y) {
    return x * y + 42;
}
```

This code is:
- ✅ Compiled to `.o` file
- ✅ Linked into the final executable
- ✅ Called by plugin implementation

---

## 📝 Complete Example

### Plugin Source (myplugin.c)

```c
#include "plugin_interface.h"
#include "my_helpers.h"  // From runtime file

// Plugin implementation
void compute_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);
    
    // Call helper function (from my_helpers.c)
    int result = my_special_calculation(a, b);
    
    fb_return_int(ctx, result);
}

FB_PLUGIN_BEGIN("My Plugin", "1.0", "Example", "Me")

// Specify runtime files needed
FB_PLUGIN_RUNTIME_FILES("my_helpers.c")

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "COMPUTE", "Compute value",
                     compute_impl, FB_RETURN_INT)
        .addParameter("a", FB_PARAM_INT, "First value")
        .addParameter("b", FB_PARAM_INT, "Second value")
        .finish();
    return 0;
}

FB_PLUGIN_SHUTDOWN() {}
```

### Helper File (my_helpers.c)

```c
#include "my_helpers.h"

int my_special_calculation(int x, int y) {
    return x * y + 42;
}
```

### Helper Header (my_helpers.h)

```c
#ifndef MY_HELPERS_H
#define MY_HELPERS_H

int my_special_calculation(int x, int y);

#endif
```

### Build Plugin

```bash
# Compile plugin
cc -shared -fPIC -o myplugin.so myplugin.c \
   -I fsh/FasterBASICT/src

# Note: my_helpers.c is NOT compiled here!
# It will be compiled when a BASIC program uses this plugin
```

### BASIC Program

```basic
result% = COMPUTE(10, 5)
PRINT result%  ' Prints: 92 (10*5 + 42)
END
```

### Compilation Process

```bash
$ ./qbe_basic_integrated/fbc_qbe test.bas

Loading plugins [My Plugin (1)]
Compiling plugin runtime: my_helpers.c → my_helpers.o
Building runtime library...
Linking plugin: myplugin.so
Compiled test.bas -> test

$ ./test
92
```

### What Got Linked

```bash
$ nm test | grep compute
0000000100003f20 T _compute_impl           # From myplugin.so
0000000100003f40 T _my_special_calculation # From my_helpers.o

$ otool -L test  # macOS (or ldd on Linux)
test:
    plugins/enabled/myplugin.so
    /usr/lib/libSystem.B.dylib
```

---

## 🔍 Why Both Plugin .so AND Runtime Files?

### Plugin .so (Shared Library)
**Purpose:** Contains the command implementations

**Why needed:**
- Plugin must be loadable at compile time (for registration)
- Plugin must be linkable at link time (for runtime calls)
- One file, used in both phases

**When loaded:**
- Compile time: `dlopen()` by compiler
- Runtime: Linked into executable by linker

### Runtime Files (.c files)
**Purpose:** Contains helper/support code

**Why separate:**
- Pure C code with no plugin-specific API
- May be shared between multiple plugins
- Easier to maintain and test independently
- Can be optimized/inlined by compiler

**When compiled:**
- Only when BASIC program uses the plugin
- Compiled fresh for each program
- Linked statically into executable

---

## 🎮 Practical Implications

### For Plugin Authors

**Do:**
- ✅ Put command implementations in the plugin `.c` file
- ✅ Use `FB_PLUGIN_RUNTIME_FILES()` for helper code
- ✅ Keep runtime files simple (pure C, no plugin API)
- ✅ Test both compile-time and runtime behavior

**Don't:**
- ❌ Assume runtime files are always available
- ❌ Use plugin API in runtime files (they're separate!)
- ❌ Forget to distribute runtime files with plugin

### For BASIC Programmers

**You don't need to know any of this!**

Just write:
```basic
result% = PLUGIN_FUNCTION(args)
```

Everything is handled automatically.

### For Compiler Developers

**Critical points:**
1. Scan `plugins/enabled/` for `.so`/`.dylib` files
2. Extract runtime file list from each plugin
3. Compile runtime files to `.o`
4. Link everything: `temp.s + runtime.o + plugin_helpers.o + plugin.so`

---

## 🐛 Troubleshooting

### "Undefined symbol" at Link Time

**Problem:**
```
Undefined symbols: _my_helper_function
```

**Cause:** Plugin specified runtime file but it wasn't found

**Solution:**
1. Check runtime file exists in plugin directory
2. Check `FB_PLUGIN_RUNTIME_FILES()` spelling
3. Check file permissions

### "Plugin loaded but function crashes"

**Problem:**
```
Segmentation fault in plugin function
```

**Cause:** Runtime files weren't linked

**Solution:**
1. Check link command includes plugin runtime `.o` files
2. Verify `FB_PLUGIN_RUNTIME_FILES()` is correct
3. Rebuild with verbose output

### "Plugin works in compiler but not in program"

**Problem:**
```
Function works in compiler but crashes when program runs
```

**Cause:** Plugin `.so` not linked into executable

**Solution:**
1. Check link command includes `plugins/enabled/myplugin.so`
2. Verify plugin is in enabled folder at compile time
3. Check `ldd` or `otool -L` output on executable

---

## 📊 Performance Considerations

### Overhead Breakdown

| Component | Size | Loaded When | Cost |
|-----------|------|-------------|------|
| Plugin .so | ~50KB | Compile + Runtime | One-time dlopen |
| Runtime files | ~10KB | Link time | Static link |
| Context API | ~5KB | Always | Built-in runtime |
| Per-call | ~2KB | Each call | Stack allocation |

### Optimization Tips

1. **Keep runtime files small** - They're compiled for each program
2. **Inline simple helpers** - Use static inline in headers
3. **Minimize plugin .so size** - Strip debug symbols for release
4. **Cache compiled .o files** - Reuse between compilations

---

## 🔒 Security Implications

### At Compile Time
- Plugins loaded with compiler privileges
- Can modify compilation process
- **Only load trusted plugins**

### At Runtime
- Plugin code runs with program privileges
- No sandboxing (linked directly)
- **Same trust level as your BASIC code**

### Recommendations
1. Only enable plugins from trusted sources
2. Review plugin source code before enabling
3. Keep plugins in version control
4. Test plugins in isolation first

---

## 🚀 Advanced: Plugin Runtime Files

### Example: Database Plugin

**Plugin structure:**
```
db_plugin/
├── db_plugin.c          # Plugin implementation
├── db_sqlite.c          # SQLite wrapper (runtime file)
├── db_postgres.c        # PostgreSQL wrapper (runtime file)
└── db_common.h          # Shared header
```

**Plugin declaration:**
```c
FB_PLUGIN_RUNTIME_FILES("db_sqlite.c, db_postgres.c")
```

**Result:** User can connect to both SQLite and PostgreSQL databases!

### Example: Image Plugin

**Plugin structure:**
```
image_plugin/
├── image_plugin.c       # Plugin implementation
├── png_decoder.c        # PNG support (runtime file)
├── jpeg_decoder.c       # JPEG support (runtime file)
└── image_common.c       # Common utilities (runtime file)
```

**Plugin declaration:**
```c
FB_PLUGIN_RUNTIME_FILES("png_decoder.c, jpeg_decoder.c, image_common.c")
```

**Result:** Full image format support, compiled into user's program!

---

## 📚 Related Documentation

- **Plugin API:** `plugin_interface.h`
- **Quick Reference:** `PLUGIN_API_QUICKREF.md`
- **Phase 3 Details:** `phase3_completion.md`
- **Plugin Directory:** `plugins/README.md`

---

## ✅ Summary

### The Complete Picture

1. **Compile Time:** Compiler loads `plugin.so` to register commands
2. **Code Generation:** Compiler generates calls to plugin functions
3. **Link Time:** Linker includes:
   - BASIC runtime (always)
   - Plugin runtime files (if specified)
   - Plugin library itself (the .so/.dylib)
4. **Runtime:** Program calls plugin functions directly (they're linked in!)

### Key Takeaways

- ✅ Plugin `.so`/`.dylib` is **both** loaded and linked
- ✅ Runtime files are **only** compiled and linked (not loaded)
- ✅ Everything ends up in the final executable
- ✅ No runtime plugin loading needed in generated programs
- ✅ Fast direct function calls at runtime

---

**The plugin system is elegant:** Plugins are libraries that register themselves at compile time and execute at runtime!

---

**Last Updated:** February 2026  
**Status:** ✅ Production Ready  
**Plugin API:** 2.0 (C-Native)