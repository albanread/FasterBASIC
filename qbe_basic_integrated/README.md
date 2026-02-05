# QBE + FasterBASIC Integrated Compiler

Single-binary compiler that accepts QBE IL, FasterBASIC source files, and compiles them to executables or object files.

## Architecture

```
BASIC source (.bas)
    ↓
FasterBASIC Frontend → QBE IL (in memory)
    ↓
QBE Backend → Assembly (.s)
    ↓
Clang/GCC → Executable

QBE IL source (.qbe)
    ↓
QBE Backend → Assembly (.s)
    ↓
Assembler → Object file (.o)
```

## Features

- **Single pass compilation**: BASIC → assembly in memory (no temp files)
- **Unified binary**: One tool for QBE IL, BASIC, and object file generation
- **QBE module support**: Compile `.qbe` files directly to `.o` object files
- **Fast**: No process spawning overhead between stages
- **Drop-in compatible**: Works with existing QBE workflows
- **Automatic linking**: BASIC programs automatically link with runtime

## Building

```bash
./build_qbe_basic.sh
```

This creates:
- `fbc_qbe` - Main compiler executable
- `qbe_basic` - Symlink for backward compatibility

## Usage

### Compile FasterBASIC Programs

```bash
# Compile BASIC to executable (default)
./fbc_qbe program.bas                    # Creates 'program' executable
./fbc_qbe program.bas -o myapp           # Creates 'myapp' executable

# Output QBE IL only
./fbc_qbe program.bas -i                 # IL to stdout
./fbc_qbe program.bas -i -o program.qbe  # IL to file

# Generate assembly only
./fbc_qbe program.bas -c -o program.s
```

### Compile QBE IL Files to Object Files

```bash
# Compile QBE IL to object file (default for .qbe files)
./fbc_qbe hashmap.qbe                    # Creates 'hashmap.o'
./fbc_qbe hashmap.qbe -o mymodule.o      # Creates 'mymodule.o'

# Generate assembly only from QBE IL
./fbc_qbe hashmap.qbe -c                 # Assembly to stdout
./fbc_qbe hashmap.qbe -c -o hashmap.s    # Assembly to file

# Output QBE IL (pass-through)
./fbc_qbe input.qbe -i                   # Copy IL to stdout
```

### Traditional QBE IL Compilation

```bash
# Standard QBE usage still works
./fbc_qbe program.ssa -o program.s
./fbc_qbe - < input.qbe > output.s
```

## QBE Modules

The compiler can now compile hand-written QBE IL files into object files for linking with BASIC programs. This enables:

- Runtime-independent core libraries
- Performance-critical routines in QBE IL
- Custom data structures (e.g., `qbe_modules/hashmap.qbe`)

Example workflow:

```bash
# Build a QBE module
cd qbe_modules
../fbc_qbe hashmap.qbe                   # Creates hashmap.o

# Link with BASIC program
cd ..
./fbc_qbe myprogram.bas                  # Automatically includes runtime
cc myprogram.o qbe_modules/hashmap.o -o myprogram
```

## Command-Line Options

```
Usage: fbc_qbe [OPTIONS] {file.bas, file.qbe, file.ssa, -}

Input files:
  file.bas             FasterBASIC source (compiles to executable)
  file.qbe             QBE IL source (compiles to .o object file)
  file.ssa             QBE IL or SSA (compiles to assembly)
  -                    standard input

Options:
  -h, --help           prints this help
  -o <file>            output to file
  -i                   output IL only (stop before assembly)
  -c                   compile only (stop at assembly)
  -G                   trace CFG and exit (BASIC files only)
  -A                   trace AST and exit (BASIC files only)
  -S                   trace symbols and exit (BASIC files only)
  -D, --debug          enable debug output
  --enable-madd-fusion enable MADD/MSUB fusion (default)
  --disable-madd-fusion disable MADD/MSUB fusion
  -t <target>          generate for target
  -d <flags>           dump debug information
```

## Implementation

- Modified `qbe/main.c` to detect `.bas` and `.qbe` files
- Added `basic_frontend.cpp` that runs FasterBASIC compiler
- Uses `fmemopen()` to pass IL in memory to QBE parser
- `.qbe` files are compiled directly to object files by default
- Zero changes to QBE's optimization pipeline
- Automatic runtime linking for `.bas` files

## Examples

See `qbe_modules/` for hand-coded QBE modules and examples.
