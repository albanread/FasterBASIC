# FasterBASIC Plugins Directory

This directory contains plugins for the FasterBASIC compiler. Plugins extend the BASIC language with custom commands and functions written in C.

---

## 📁 Directory Structure

```
plugins/
├── README.md          # This file
├── enabled/           # Active plugins (auto-loaded)
├── disabled/          # Inactive plugins (not loaded)
└── examples/          # Example plugins (optional)
```

---

## 🚀 Quick Start

### Enable a Plugin

1. **Copy plugin to enabled folder:**
   ```bash
   cp my_plugin.so plugins/enabled/
   # or on macOS:
   cp my_plugin.dylib plugins/enabled/
   ```

2. **Compile your BASIC program:**
   ```bash
   ./qbe_basic_integrated/fbc_qbe myprogram.bas
   ```
   
   Plugins are automatically loaded at compile time!

### Disable a Plugin

Simply move it to the disabled folder:

```bash
mv plugins/enabled/my_plugin.so plugins/disabled/
```

To re-enable, move it back:

```bash
mv plugins/disabled/my_plugin.so plugins/enabled/
```

---

## 🎯 How It Works

### Automatic Loading

When you compile a BASIC program, the compiler:

1. **Scans** `plugins/enabled/` directory
2. **Loads** all `.so`, `.dylib`, or `.dll` files found
3. **Registers** commands and functions from each plugin
4. **Makes available** to your BASIC code

### Example

**Plugin in enabled folder:**
```
plugins/enabled/math_extra.so
```

**BASIC code can now use:**
```basic
result% = FACTORIAL(5)    ' From math_extra plugin
PRINT result%             ' Prints: 120
```

---

## 📝 Plugin Format

Plugins must be:
- **Dynamic libraries** (`.so` on Linux, `.dylib` on macOS, `.dll` on Windows)
- **C-compatible** exports (use `extern "C"`)
- **Implement required functions:**
  - `FB_PLUGIN_NAME()` - Plugin name
  - `FB_PLUGIN_VERSION()` - Plugin version
  - `FB_PLUGIN_DESCRIPTION()` - Plugin description
  - `FB_PLUGIN_AUTHOR()` - Plugin author
  - `FB_PLUGIN_API_VERSION()` - API version (must return 2)
  - `FB_PLUGIN_INIT()` - Initialize and register commands
  - `FB_PLUGIN_SHUTDOWN()` - Cleanup (optional)

---

## 🔧 Creating a Plugin

### Minimal Example

```c
#include "plugin_interface.h"

void my_func_impl(FB_RuntimeContext* ctx) {
    int value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 2);
}

FB_PLUGIN_BEGIN("My Plugin", "1.0", "Description", "Author")

FB_PLUGIN_INIT(callbacks) {
    FB_BeginFunction(callbacks, "MYFUNC", "Doubles value", 
                     my_func_impl, FB_RETURN_INT)
        .addParameter("x", FB_PARAM_INT, "Input value")
        .finish();
    return 0;
}

FB_PLUGIN_SHUTDOWN() {}
```

### Build Commands

**Linux:**
```bash
cc -shared -fPIC -o my_plugin.so my_plugin.c \
   -I fsh/FasterBASICT/src
```

**macOS:**
```bash
cc -dynamiclib -o my_plugin.dylib my_plugin.c \
   -I fsh/FasterBASICT/src
```

**Windows:**
```bash
cl /LD my_plugin.c /I fsh\FasterBASICT\src
```

### Install Plugin

```bash
cp my_plugin.so plugins/enabled/
```

### Use in BASIC

```basic
result% = MYFUNC(42)
PRINT result%  ' Prints: 84
```

---

## 📚 Documentation

- **Complete API:** `../fsh/FasterBASICT/src/plugin_interface.h`
- **Quick Reference:** `../docs/PLUGIN_API_QUICKREF.md`
- **Tutorial:** `../docs/PHASE3_README.md`
- **Examples:** `../test_plugin/simple_math.c`

---

## 🎮 Managing Plugins

### List Enabled Plugins

```bash
ls -1 plugins/enabled/
```

### List Disabled Plugins

```bash
ls -1 plugins/disabled/
```

### Enable Multiple Plugins

```bash
cp plugins/disabled/*.so plugins/enabled/
```

### Disable All Plugins

```bash
mv plugins/enabled/* plugins/disabled/
```

### Check Plugin is Loaded

When compiling, you'll see:
```
Loading plugins [PluginName (5), AnotherPlugin (3)]
```

The number in parentheses is the count of commands/functions registered.

---

## ⚙️ Plugin Search Paths

The compiler looks for plugins in this order:

1. **`plugins/enabled/`** (relative to compiler)
2. **`FB_PLUGIN_PATH`** environment variable (if set)
3. **Current directory** (as fallback)

### Custom Plugin Directory

Set the `FB_PLUGIN_PATH` environment variable:

```bash
export FB_PLUGIN_PATH=/path/to/my/plugins
./qbe_basic_integrated/fbc_qbe myprogram.bas
```

---

## 🐛 Troubleshooting

### Plugin Not Loading

**Problem:**
```
Failed to load 1 plugin(s):
  - my_plugin.so: Cannot open shared object file
```

**Solutions:**
- Check file exists: `ls -l plugins/enabled/my_plugin.so`
- Check permissions: `chmod +x plugins/enabled/my_plugin.so`
- Check dependencies: `ldd plugins/enabled/my_plugin.so` (Linux)
- Check architecture: 64-bit plugin for 64-bit compiler

### Plugin Loaded But Function Not Found

**Problem:**
```
Error: Unknown function 'MYFUNC'
```

**Solutions:**
- Check plugin was loaded (see "Loading plugins" message)
- Verify function name matches registration (case-sensitive)
- Check `FB_PLUGIN_API_VERSION()` returns 2
- Rebuild plugin with correct includes

### Multiple Plugins Conflict

**Problem:**
```
Warning: Function 'MYFUNC' already registered
```

**Solutions:**
- Disable conflicting plugin: `mv plugins/enabled/conflict.so plugins/disabled/`
- Rename function in one plugin
- Use plugin priority/ordering (future feature)

---

## 🔒 Security Considerations

### Trusted Plugins Only

Plugins run with **full compiler privileges** and have access to:
- File system
- Network
- System calls
- Memory

**Only load plugins from trusted sources!**

### Disable Untrusted Plugins

If you receive a plugin you don't trust:

```bash
# Don't enable it!
cp untrusted.so plugins/disabled/

# Inspect source code first
# Only enable after code review
```

---

## 📦 Plugin Distribution

### Sharing Your Plugin

To share a plugin:

1. **Provide source code** (`.c` file)
2. **Include build instructions**
3. **Document functions** (parameters, return values)
4. **List dependencies** (if any)
5. **Specify license**

### Installing Shared Plugins

When installing someone else's plugin:

1. **Review source code** for safety
2. **Build from source** (don't trust binaries)
3. **Test in isolated environment** first
4. **Copy to enabled folder** when satisfied

---

## 🎯 Example Plugins

### Test Plugin (Included)

```bash
cd test_plugin
./build.sh
cp simple_math.so ../plugins/enabled/
```

Provides: `DOUBLE()`, `ADD()`, `MULTIPLY()`, `SQUARE()`, `FACTORIAL()`, etc.

### Custom Plugins (Community)

Check the FasterBASIC community for:
- CSV file handling
- JSON parsing
- Database access
- Network requests
- Image processing
- Audio processing
- GUI widgets
- And more!

---

## 💡 Tips

1. **Keep plugins small** - One plugin per feature area
2. **Use descriptive names** - `csv_handler.so`, not `plugin1.so`
3. **Document your functions** - Good descriptions help users
4. **Handle errors gracefully** - Always validate inputs
5. **Test thoroughly** - Test edge cases and error conditions
6. **Version your plugins** - Update version string when changing
7. **Clean up resources** - Implement `FB_PLUGIN_SHUTDOWN()` properly

---

## 🚀 Advanced Features

### Plugin Dependencies

Plugins can depend on other plugins (future feature):
```c
FB_PLUGIN_DEPENDS("base_plugin", "1.0")
```

### Plugin Priority

Control loading order (future feature):
```c
FB_PLUGIN_PRIORITY(100)  // Higher = load first
```

### Hot Reload

Reload plugins without restarting compiler (future feature):
```bash
fbc --reload-plugins
```

---

## 📞 Support

### Getting Help

- Read API documentation: `plugin_interface.h`
- Check examples: `test_plugin/simple_math.c`
- Review troubleshooting section above
- Ask in FasterBASIC community

### Reporting Issues

If a plugin causes problems:

1. Disable the plugin
2. Report issue with:
   - Plugin name and version
   - Error message
   - Steps to reproduce
   - System information

---

## ✅ Best Practices

- ✅ Always use `FB_PLUGIN_BEGIN()` macro
- ✅ Return 0 from `FB_PLUGIN_INIT()` on success
- ✅ Validate all input parameters
- ✅ Use `fb_set_error()` for error messages
- ✅ Use `fb_alloc()` for automatic memory management
- ✅ Test with various input types and edge cases
- ✅ Document all functions clearly
- ✅ Handle errors gracefully
- ✅ Free resources in `FB_PLUGIN_SHUTDOWN()`

---

## 🎉 Conclusion

The FasterBASIC plugin system makes it easy to:

- ✅ **Add custom commands** without modifying the compiler
- ✅ **Extend the language** with domain-specific features
- ✅ **Share functionality** with the community
- ✅ **Enable/disable features** by moving files

**Just drop a plugin in `plugins/enabled/` and start using it!**

---

**Last Updated:** February 2026  
**Plugin API Version:** 2.0 (C-Native)  
**Status:** ✅ Production Ready