# Plugin Loading and Linking - Complete System

**Date:** February 2026  
**Update:** Plugin directory structure + automatic runtime linking  
**Status:** ✅ COMPLETE

---

## 🎉 What Was Added

This update completes the plugin system with:

1. **Automatic plugin loading** from `plugins/enabled/` directory
2. **Plugin enable/disable** via folder structure
3. **Runtime linking** of plugin libraries into executables
4. **Plugin runtime files** support for helper code

---

## 📁 New Directory Structure

```
plugins/
├── README.md          # Complete user guide
├── enabled/           # Active plugins (auto-loaded)
│   ├── math.so       # ← Loaded automatically
│   └── csv.dylib     # ← Loaded automatically
└── disabled/          # Inactive plugins (not loaded)
    └── old_plugin.so  # ← Ignored
```

**Key Feature:** Just drop a plugin in `plugins/enabled/` and it's automatically available!

---

## 🚀 How It Works

### At Compile Time

1. **Compiler starts** → Scans `plugins/enabled/` directory
2. **Finds plugins** → Loads all `.so`, `.dylib`, `.dll` files
3. **Registers commands** → Each plugin registers its functions
4. **Your BASIC code** → Can now use plugin functions!

Example output:
```
Loading plugins [Math Plugin (5), CSV Handler (8)]
```

### At Link Time

When creating the executable, the linker includes:

1. **BASIC runtime** (always)
   - `basic_runtime.o`, `string_ops.o`, etc.
   - `plugin_context_runtime.o` ⭐

2. **Plugin runtime files** (if plugin specifies)
   - Helper `.c` files compiled to `.o`
   - Plugin-specific support code

3. **Plugin libraries** (the actual plugins)
   - `plugins/enabled/math.so`
   - `plugins/enabled/csv.dylib`

**Result:** Everything needed is in the final executable!

---

## 🔧 For Plugin Authors

### Minimal Plugin (No Runtime Files)

```c
#include "plugin_interface.h"

void double_impl(FB_RuntimeContext* ctx) {
    int value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 2);
}

FB_PLUGIN_BEGIN("Simple Plugin", "1.0", "Example", "Me")

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "DOUBLE", "Double value",
                     double_impl, FB_RETURN_INT)
        .addParameter("x", FB_PARAM_INT, "Input")
        .finish();
    return 0;
}

FB_PLUGIN_SHUTDOWN() {}
```

Build:
```bash
cc -shared -fPIC -o simple.so simple.c -I fsh/FasterBASICT/src
cp simple.so plugins/enabled/
```

### Advanced Plugin (With Runtime Files)

```c
#include "plugin_interface.h"
#include "my_helpers.h"  // From runtime file

void compute_impl(FB_RuntimeContext* ctx) {
    int a = fb_get_int_param(ctx, 0);
    int b = fb_get_int_param(ctx, 1);
    int result = my_helper_function(a, b);  // From runtime file
    fb_return_int(ctx, result);
}

FB_PLUGIN_BEGIN("Advanced Plugin", "1.0", "Example", "Me")

// ⭐ NEW: Specify runtime files
FB_PLUGIN_RUNTIME_FILES("my_helpers.c, data_parser.c")

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "COMPUTE", "Compute value",
                     compute_impl, FB_RETURN_INT)
        .addParameter("a", FB_PARAM_INT, "First")
        .addParameter("b", FB_PARAM_INT, "Second")
        .finish();
    return 0;
}

FB_PLUGIN_SHUTDOWN() {}
```

The runtime files (`my_helpers.c`, `data_parser.c`) will be:
1. Found alongside the plugin
2. Compiled to `.o` files
3. Linked into the executable

---

## 🎮 For BASIC Programmers

### Enable a Plugin

```bash
cp myplugin.so plugins/enabled/
```

### Use in BASIC

```basic
result% = DOUBLE(42)
PRINT result%  ' Prints: 84
END
```

**That's it!** No configuration needed.

### Disable a Plugin

```bash
mv plugins/enabled/myplugin.so plugins/disabled/
```

### List Active Plugins

```bash
ls plugins/enabled/
```

---

## 🔍 Technical Details

### Two Components of a Plugin

#### 1. Plugin Library (.so/.dylib)
- **Contains:** Command implementations
- **Loaded:** At compile time (dlopen) AND linked at link time
- **Purpose:** Registers commands + provides functions

#### 2. Runtime Files (.c files) - OPTIONAL
- **Contains:** Helper/support code
- **Loaded:** Compiled and linked at link time
- **Purpose:** Provides utilities for plugin functions

### Why Both?

**Plugin Library:**
- Must be a shared library (for dlopen at compile time)
- Contains plugin-specific code (uses plugin API)
- Linked into executable (for runtime calls)

**Runtime Files:**
- Pure C code (no plugin API)
- Simpler, easier to test
- Compiled fresh for each program
- Can be shared between plugins

---

## 📊 What Gets Linked Into Executable

```
Final Executable Contents:
├─ Your BASIC code (compiled to machine code)
├─ FasterBASIC runtime (~50KB)
│  ├─ basic_runtime.o
│  ├─ string_ops.o
│  ├─ array_ops.o
│  └─ plugin_context_runtime.o ⭐
├─ Plugin runtime files (~10KB per plugin)
│  ├─ my_helpers.o
│  └─ data_parser.o
└─ Plugin libraries (linked, not embedded)
   ├─ plugins/enabled/math.so
   └─ plugins/enabled/csv.dylib
```

Total overhead: ~50KB runtime + ~10KB per plugin

---

## 🎯 Key Updates Made

### 1. Wrapper Updated
**File:** `qbe_basic_integrated/fasterbasic_wrapper.cpp`

Added:
```cpp
// Load plugins from plugins/enabled directory
FasterBASIC::PluginSystem::initializeGlobalPluginLoader(registry);
```

**Effect:** Plugins automatically loaded when compiler starts

### 2. Linker Updated
**File:** `qbe_basic_integrated/qbe_source/main.c`

Added:
- Scan `plugins/enabled/` for plugin files
- Add plugin libraries to link command
- Compile plugin runtime files to `.o`

**Effect:** Plugins and their runtime files linked into executable

### 3. Plugin API Extended
**File:** `fsh/FasterBASICT/src/plugin_interface.h`

Added:
```c
typedef const char* (*FB_PluginRuntimeFilesFunc)();

#define FB_PLUGIN_RUNTIME_FILES(files) \
    FB_PLUGIN_EXPORT const char* FB_PLUGIN_RUNTIME_FILES() { return files; }
```

**Effect:** Plugins can specify helper C files

### 4. Directory Structure Created
**Directories:**
- `plugins/` - Main plugins folder
- `plugins/enabled/` - Active plugins
- `plugins/disabled/` - Inactive plugins

**Effect:** Easy plugin management (just move files)

### 5. Documentation Created
**Files:**
- `plugins/README.md` - User guide (425 lines)
- `docs/PLUGIN_RUNTIME_LINKING.md` - Technical deep-dive (475 lines)
- `docs/PLUGIN_LOADING_UPDATE.md` - This file

**Effect:** Complete understanding of plugin system

---

## ✅ Verification

### Test 1: Simple Plugin

```bash
# Build test plugin
cd test_plugin
./build.sh

# Copy to enabled
cp simple_math.so ../plugins/enabled/

# Compile BASIC program
cd ..
./qbe_basic_integrated/fbc_qbe test_plugin/test.bas

# Should see:
# Loading plugins [Simple Math Plugin (9)]
# Linking plugin: simple_math.so

# Run it
./test
# Should see all tests pass ✓
```

### Test 2: Enable/Disable

```bash
# Disable plugin
mv plugins/enabled/simple_math.so plugins/disabled/

# Compile again
./qbe_basic_integrated/fbc_qbe test.bas
# No plugin loaded, compilation fails if test.bas uses plugin

# Re-enable
mv plugins/disabled/simple_math.so plugins/enabled/

# Compile again
./qbe_basic_integrated/fbc_qbe test.bas
# Plugin loaded, compilation succeeds
```

---

## 🐛 Troubleshooting

### Plugin Not Loading

**Symptom:**
```
Error: Unknown function 'DOUBLE'
```

**Check:**
```bash
ls plugins/enabled/
# Make sure plugin file is there

./qbe_basic_integrated/fbc_qbe test.bas
# Look for "Loading plugins [...]" message
```

### Link Errors

**Symptom:**
```
Undefined symbols: _my_helper_function
```

**Fix:**
1. Check plugin specifies runtime files correctly
2. Verify runtime files exist in plugin directory
3. Check spelling in `FB_PLUGIN_RUNTIME_FILES()`

### Runtime Crashes

**Symptom:**
```
Segmentation fault
```

**Check:**
1. Plugin library linked: `ldd ./program` (Linux) or `otool -L ./program` (macOS)
2. Runtime files compiled: Check `.obj/` directory
3. Plugin directory still exists (needed for runtime files)

---

## 🚀 What This Enables

### Easy Plugin Management
```bash
# Enable plugin
cp plugin.so plugins/enabled/

# Disable plugin  
mv plugins/enabled/plugin.so plugins/disabled/

# Update plugin
cp new_version.so plugins/enabled/plugin.so
```

### No Configuration Files
- No plugin.conf
- No initialization code
- No manual loading

Just files in folders!

### Plugin Distribution
```bash
# Share plugin
tar czf myplugin.tar.gz myplugin.so my_helpers.c README.txt

# Install plugin
tar xzf myplugin.tar.gz -C plugins/enabled/
```

### Plugin Development Workflow
```bash
# Develop
vim myplugin.c
cc -shared -fPIC -o myplugin.so myplugin.c

# Test
cp myplugin.so plugins/enabled/
./qbe_basic_integrated/fbc_qbe test.bas
./test

# Iterate
vim myplugin.c
cc -shared -fPIC -o myplugin.so myplugin.c
cp myplugin.so plugins/enabled/
./qbe_basic_integrated/fbc_qbe test.bas
./test
```

---

## 📚 Related Documentation

- **User Guide:** `plugins/README.md`
- **Technical Details:** `docs/PLUGIN_RUNTIME_LINKING.md`
- **API Reference:** `docs/PLUGIN_API_QUICKREF.md`
- **Phase 3 Summary:** `docs/PHASE3_FINAL_SUMMARY.md`

---

## 🎊 Summary

The plugin system is now **complete and user-friendly**:

✅ **Drop plugins in folder** → Automatically loaded  
✅ **Move to disabled/** → Plugin disabled  
✅ **Move back to enabled/** → Plugin re-enabled  
✅ **Runtime files supported** → Complex plugins possible  
✅ **Everything linked properly** → Fast runtime execution  
✅ **No configuration needed** → Just works!

**The plugin system is production-ready and easy to use!**

---

**Last Updated:** February 2026  
**Status:** ✅ COMPLETE  
**Plugin API Version:** 2.0 (C-Native)