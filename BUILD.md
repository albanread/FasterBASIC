# Building the FasterBASIC QBE Compiler

## Quick Start

To build the compiler, run:

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

This will create the `qbe_basic` executable in the `qbe_basic_integrated/` directory.

A symlink exists at the project root (`./qbe_basic`) that points to the integrated build, so you can run the compiler from anywhere in the project:

```bash
# From project root
./qbe_basic program.bas

# From the integrated directory
cd qbe_basic_integrated
./qbe_basic program.bas
```

## Build Requirements

- **C++17 compiler** (clang++ or g++)
- **C99 compiler** (gcc or clang)
- **Standard build tools** (make, as)

## What Gets Built

The build process:

1. **Compiles FasterBASIC frontend** - Lexer, parser, semantic analyzer, CFG builder, QBE code generator
2. **Compiles QBE backend** - The QBE IL compiler that generates assembly
3. **Links them together** - Creates a single `qbe_basic` executable that compiles BASIC directly to native code
4. **Copies runtime library** - BASIC runtime functions (strings, arrays, I/O, etc.) to `runtime/`

## Build Locations

**DO NOT use any other build scripts!** There is only ONE build location:

- ✅ **Correct**: `qbe_basic_integrated/build_qbe_basic.sh`
- ❌ **Old/Deprecated**: Any other `build*.sh` files

The project root contains a symlink (`qbe_basic -> qbe_basic_integrated/qbe_basic`) for convenience.

## Rebuilding After Changes

If you modify any source files, rebuild with:

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

The build is incremental - QBE objects are cached and only recompiled if missing.

## Build Output

After a successful build:

```
=== Build Complete ===
Executable: /path/to/qbe_basic_integrated/qbe_basic

Usage:
  ./qbe_basic input.bas -o program      # Compile to executable
  ./qbe_basic -i -o output.qbe input.bas # Generate QBE IL only
  ./qbe_basic -c -o output.s input.bas   # Generate assembly only
```

## Using the Compiler

See [START_HERE.md](START_HERE.md) for detailed usage instructions.

Quick example:

```bash
# Create a BASIC program
cat > hello.bas << 'EOF'
PRINT "Hello, World!"
END
EOF

# Compile and run
./qbe_basic hello.bas -o hello
./hello
```

## Troubleshooting

### Build fails with "FasterBASIC sources not found"

Make sure you're in the correct directory:

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

### Compiler produces wrong results

Make sure you're using the latest build:

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

Then use `./qbe_basic` (either the symlink from root or the actual executable in `qbe_basic_integrated/`).

### Multiple build locations confusion

This project previously had multiple build scripts. They have been consolidated:

- The root-level `qbe_basic` is now a **symlink** to `qbe_basic_integrated/qbe_basic`
- Only use `qbe_basic_integrated/build_qbe_basic.sh` to build
- All other build scripts have been removed or are deprecated

## Clean Build

To force a complete rebuild:

```bash
cd qbe_basic_integrated
rm -rf obj/*.o qbe_source/*.o qbe_source/*/*.o qbe_basic
./build_qbe_basic.sh
```
