# FBCQBE - FasterBASIC QBE Backend

Working on V2 of the CFG and V2 of the codegen, so right now everything is very broken, but it should be more maintainable when it works.

[![Build Status](https://github.com/albanread/FBCQBE/actions/workflows/build.yml/badge.svg)](https://github.com/albanread/FBCQBE/actions)

A native-code ahead-of-time (AOT) compiler backend for FasterBASIC using the QBE intermediate language.

> **⚠️ Important Build Note:** This project has a single build location. Always build using:
> ```bash
> cd qbe_basic_integrated && ./build_qbe_basic.sh
> ```
> The `qbe_basic` executable at the project root is a **symlink** to `qbe_basic_integrated/qbe_basic`.
> See [BUILD.md](BUILD.md) for detailed build instructions.

## Overview

FBCQBE compiles FasterBASIC programs to native machine code through the QBE (Quick Backend) SSA-based intermediate representation. This provides:

- **Native performance**: Compiled to machine code, not interpreted
- **Strict correctness**: QBE's SSA form enforces proper control flow
- **Platform support**: Works on x86-64, ARM64, and RISC-V via QBE
- **Modern toolchain**: Integrates with standard C compilers and assemblers

## Project Status

**Latest Update (January 2025)**: Complete exception handling (TRY/CATCH/FINALLY/THROW) and dynamic array operations (ERASE/REDIM/REDIM PRESERVE) with comprehensive test coverage. String array support with read/write access and string slicing functionality. Parser correctly distinguishes between array access (`names$(0)`) and string slicing (`s$(1 TO 5)`) using lookahead detection of the TO keyword.

### ✅ Working Features

**Exception Handling:**
- ✅ TRY/CATCH/FINALLY/THROW structured exception handling
- ✅ Specific error code matching in CATCH blocks
- ✅ Catch-all handlers (CATCH without error code)
- ✅ FINALLY blocks (execute on both normal and exceptional paths)
- ✅ ERR() builtin - get current error code
- ✅ ERL() builtin - get current error line number
- ✅ Nested exception handling with proper propagation
- ✅ Direct setjmp/longjmp implementation (platform-safe)

**Control Flow:**
- ✅ IF/THEN/ELSE with proper block structure
- ✅ WHILE/WEND loops with condition checking
- ✅ REPEAT/UNTIL loops
- ✅ DO/LOOP (WHILE/UNTIL) variants
- ✅ FOR/NEXT/STEP loops with full CFG support
  - Nested FOR loops
  - EXIT FOR for early termination
  - Loop index modification (classic BASIC behavior)
  - Expression evaluation in TO clause
- ✅ SELECT CASE multi-way branching
- ✅ GOTO and GOSUB/RETURN

**Functions and Subroutines:**
- ✅ FUNCTION/END FUNCTION with return values
- ✅ SUB/END SUB procedures
- ✅ Recursive functions (Fibonacci, Factorial tested)
- ✅ LOCAL variables with proper scoping
- ✅ SHARED variables (access to globals)
- ✅ RETURN expression for early returns
- ✅ EXIT FUNCTION / EXIT SUB
- 🚧 DEF FN single-line functions (structure complete, type system needs work)

**Data Types:**
- ✅ INTEGER (w/%) - 32-bit signed
- ✅ FLOAT/DOUBLE (d/!) - 64-bit floating point
- ✅ STRING (l/$) - String pointers with UTF-32 descriptors
- ✅ Type suffix inference (%, #, !, $)

**Arrays:**
- ✅ STRING and numeric arrays with full read/write access
- ✅ Array declaration: `DIM names$(5)`, `DIM numbers%(10 TO 20)`
- ✅ Array assignment: `names$(0) = "Alice"`, `numbers%(15) = 42`
- ✅ Array access in expressions: `PRINT names$(0)`, `x% = numbers%(i%)`
- ✅ Bounds checking with runtime error handling
- ✅ Dynamic array operations:
  - ✅ ERASE - Free array memory (preserves declaration)
  - ✅ REDIM - Reallocate array with new bounds
  - ✅ REDIM PRESERVE - Reallocate while preserving existing elements
- ✅ Proper string cleanup on ERASE (no memory leaks)
- ✅ ArrayDescriptor metadata (bounds, dimensions, type info)

**String Operations:**
- ✅ String slicing: `s$(start TO end)` with all variants
  - `s$(1 TO 5)` - normal slice
  - `s$(TO 5)` - from start to position
  - `s$(7 TO)` - from position to end
  - `s$(7 TO 7)` - single character
- ✅ String concatenation with `+`
- ✅ String literals and variables

**Statements:**
- ✅ PRINT with formatting
- ✅ LET (assignment)
- ✅ DIM for arrays (structure, runtime integration pending)
- ✅ REM comments
- ✅ END program termination

**Code Generation:**
- ✅ Proper SSA form with explicit temporaries
- ✅ Control Flow Graph (CFG) construction
- ✅ Basic block emission
- ✅ Conditional and unconditional jumps
- ✅ Function calls (user-defined and runtime)
- ✅ Type-appropriate QBE instructions

### 🚧 In Progress

- **Type system**: Full type inference and conversion throughout expressions
- **DEF FN**: Complete implementation with proper typing
- **Arrays**: Full runtime integration for multi-dimensional arrays and numeric types
- **String operations**: Advanced string functions (LEN, MID, INSTR, etc.)

### 📋 Planned

- **Optimization passes**: Peephole optimization, constant folding
- **Debug info**: Source maps and line number tracking
- **Error handling**: Better error messages with source context
- **Standard library**: Expanded runtime functions (math, string, file I/O)

## Quick Start

### Using the Integrated Compiler (Recommended)

The integrated `qbe_basic` compiler combines FasterBASIC and QBE into a single executable with automatic runtime management:

```bash
# Build the integrated compiler
cd qbe_basic_integrated
./build_qbe_basic.sh

# Compile to executable (one command!)
./qbe_basic -o myprogram ../tests/exceptions/test_try_catch_basic.bas
./myprogram

# Or generate QBE IL only
./qbe_basic -i -o output.qbe input.bas

# Or generate assembly only
./qbe_basic -c -o output.s input.bas
```

**Features:**
- Single command compilation from BASIC → executable
- Automatic platform detection (macOS ARM64/x86_64, Linux)
- Smart runtime caching (10x faster on subsequent builds)
- Self-contained with bundled runtime library

### Alternative: Separate Tools

For development or debugging, you can use the separate tools:

```bash
# Build FasterBASIC compiler
cd fsh
./build_fbc_qbe.sh

# Compile and run with the wrapper
./basic --run ../tests/exceptions/test_try_catch_basic.bas
```

### Testing & Verification

```bash
# Run the full test suite
./test_basic_suite.sh

# Verify implementation integrity
./verify_implementation.sh
```

**New to the project?** See [START_HERE.md](START_HERE.md) for a comprehensive developer guide.

**⚠️ Working on exceptions or arrays?** See [docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md) for essential technical details.

## Platform Support

### Auto-Detection

The compiler automatically detects your platform and architecture during build:

- **macOS ARM64** (Apple Silicon M1/M2/M3) → `arm64_apple` target
- **macOS x86_64** (Intel) → `amd64_apple` target
- **Linux x86_64** → `amd64_sysv` target
- **Linux ARM64** → `arm64` target
- **Linux RISC-V 64** → `rv64` target

No manual configuration needed - just run `./build_qbe_basic.sh` and the correct target is selected automatically.

### Runtime Library

The runtime library is compiled on-demand with smart caching:
- First compilation: builds runtime to `.o` files (~500ms)
- Subsequent compilations: uses cached objects (~43ms, 10x faster)
- Automatic rebuild when source files are modified
- Self-contained in `qbe_basic_integrated/runtime/` directory

### Cross-Compilation

To target a different architecture, use the `-t` flag:

```bash
./qbe_basic -t amd64_apple -o program input.bas  # Target Intel Mac
./qbe_basic -t arm64_apple -o program input.bas   # Target Apple Silicon
./qbe_basic -t amd64_sysv -o program input.bas    # Target Linux x86_64
```

List available targets:
```bash
./qbe_basic -t ?
```

## Architecture

```
┌─────────────────┐
│  BASIC Source   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Lexer       │  Tokenization
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Parser      │  AST Construction
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│    Semantic     │  Type checking, symbol resolution
│    Analyzer     │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   CFG Builder   │  Control Flow Graph construction
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  QBE CodeGen    │  Generate QBE IL (SSA form)
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   QBE Compiler  │  QBE → Assembly
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Assembler     │  Assembly → Object code
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Linker      │  Link with runtime → Executable
└─────────────────┘
```

## Building

### Prerequisites

- C++17 compatible compiler (GCC 7+, Clang 5+, or MSVC 2017+)
- Standard build tools (make, as, gcc/clang)
- QBE is included in the repository (no separate installation needed)

### Build the Integrated Compiler (Recommended)

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

This builds `qbe_basic`, a single executable that combines:
- FasterBASIC compiler (lexer, parser, semantic analyzer, CFG builder)
- QBE code generator
- QBE SSA optimizer and code emitter
- Integrated runtime library with smart caching

**What gets built:**
- `qbe_basic` - The integrated compiler executable
- `runtime/` - Runtime library source files (auto-compiled on first use)

### Using the Integrated Compiler

```bash
# Compile BASIC directly to executable (one command!)
./qbe_basic -o myprogram input.bas
./myprogram

# Generate QBE IL only (for inspection/debugging)
./qbe_basic -i -o output.qbe input.bas

# Generate assembly only (for manual linking)
./qbe_basic -c -o output.s input.bas
```

### Alternative: Build Separate Tools

For compiler development or debugging the pipeline:

```bash
cd fsh
./build_fbc_qbe.sh
```

This produces separate tools:
- `fbc_qbe` - FasterBASIC to QBE IL compiler
- `basic` - Wrapper script for running programs

**Manual compilation pipeline:**
```bash
# Step 1: Compile BASIC to QBE IL
./fbc_qbe program.bas  # produces a.out (QBE IL)

# Step 2: Compile QBE IL to assembly
qbe a.out > program.s

# Step 3: Assemble and link
as program.s -o program.o
gcc program.o runtime_stubs.o -o program

# Step 4: Run
./program
```

**Note:** Most users should use the integrated `qbe_basic` compiler for simplicity and speed.

## Example Programs

### Hello World
```basic
PRINT "Hello, World!"
END
```

### FOR Loop with Nested Loops
```basic
FOR i% = 1 TO 3
    PRINT "Outer: i% = "; i%
    FOR j% = 1 TO 2
        PRINT "  Inner: j% = "; j%
    NEXT j%
NEXT i%
END
```

### Recursive Function
```basic
FUNCTION Factorial%(N%)
    IF N% <= 1 THEN
        Factorial% = 1
    ELSE
        Factorial% = N% * Factorial%(N% - 1)
    END IF
END FUNCTION

PRINT "5! = "; Factorial%(5)
END
```

### DEF FN (In Progress)
```basic
DEF FN Square(X) = X * X
DEF FN Hypotenuse(A, B) = SQR(A*A + B*B)

PRINT FN Square(5)
PRINT FN Hypotenuse(3, 4)
END
```

### String Arrays
```basic
DIM names$(5)

names$(0) = "Alice"
names$(1) = "Bob"
names$(2) = "Charlie"

PRINT "First name: "; names$(0)
PRINT "Second name: "; names$(1)
PRINT "Third name: "; names$(2)
END
```

### String Slicing
```basic
DIM s$, m$

s$ = "Hello World"
PRINT "Original: "; s$

m$ = s$(7 TO 11)
PRINT "s$(7 TO 11): "; m$

m$ = s$(TO 5)
PRINT "s$(TO 5): "; m$

m$ = s$(7 TO)
PRINT "s$(7 TO): "; m$
END
```

### Exception Handling
```basic
TRY
    PRINT "Attempting risky operation..."
    IF condition THEN THROW 10, 42  ' Error code 10, line 42
CATCH 5
    PRINT "Caught error 5"
CATCH 10
    PRINT "Caught error 10: ERR() = "; ERR(); " at line "; ERL()
CATCH
    PRINT "Caught unexpected error: "; ERR()
FINALLY
    PRINT "Cleanup always runs"
END TRY
END
```

### Dynamic Arrays
```basic
' Declare and use array
DIM numbers%(1 TO 10)
numbers%(5) = 42
PRINT numbers%(5)

' Free memory
ERASE numbers%

' Reallocate with different size
REDIM numbers%(1 TO 20)

' Reallocate while preserving existing data
numbers%(1) = 100
numbers%(2) = 200
REDIM PRESERVE numbers%(1 TO 30)
PRINT numbers%(1)  ' Still 100
PRINT numbers%(2)  ' Still 200
END
```

## Control Flow Graph (CFG)

The compiler builds an explicit CFG for all code, ensuring correctness:

### FOR Loop CFG Structure
```
┌──────────────┐
│  FOR Init    │  Initialize i, step, end
└──────┬───────┘
       │
       ▼
┌──────────────┐
│  FOR Check   │  if i <= end
└───┬──────┬───┘
    │ true │ false
    ▼      ▼
┌─────┐  ┌──────────┐
│Body │  │After FOR │
└──┬──┘  └──────────┘
   │
   ▼
┌─────────────┐
│    NEXT     │  i = i + step
└──────┬──────┘
       │
       └───────┐
               │
(jump back)    ▼
         ┌──────────────┐
         │  FOR Check   │
         └──────────────┘
```

### Nested FOR Loops
The CFG correctly handles nested loops by creating explicit edges from outer body to inner init:
```
Outer body block → Inner FOR init block → Inner check → Inner body → Inner exit (→ continues outer body)
```

## QBE IL Example

Input:
```basic
FOR i% = 1 TO 5
    PRINT i%
NEXT i%
END
```

Generated QBE:
```qbe
@block_1  # FOR Init
    %var_i_INT =w copy 1
    %step_i_INT =w copy 1
    %end_i_INT =w copy 5

@block_2  # FOR Check
    %t1 =w cslew %var_i_INT, %end_i_INT
    jnz %t1, @block_3, @block_4

@block_3  # FOR Body
    call $basic_print_int(w %var_i_INT)
    call $basic_print_newline()
    %t2 =w add %var_i_INT, %step_i_INT
    %var_i_INT =w copy %t2
    jmp @block_2

@block_4  # After FOR
    jmp @exit
```

## Testing

Comprehensive test suite covering:

**Exception Handling Tests** (`tests/exceptions/`)
- TRY/CATCH with specific error codes
- Catch-all handlers
- FINALLY block execution
- Nested exception handling
- ERR() and ERL() builtins
- Unhandled exception propagation

**Array Operation Tests** (`tests/arrays/`)
- ERASE (freeing array memory)
- REDIM (reallocation)
- REDIM PRESERVE (preserving elements)
- String array cleanup
- Memory stress tests

**Control Flow Tests**
- Simple and nested FOR loops
- EXIT FOR / EXIT WHILE
- STEP variants (positive, negative, expressions)
- Loop index modification
- SELECT CASE multi-way branching
- ON GOTO / ON GOSUB

**Additional Tests**
- Recursive functions
- Multi-function programs
- String operations
- Arithmetic and bitwise operations
- Type conversions

Run the full test suite:
```bash
./test_basic_suite.sh

# Or run specific test categories
./test_basic_suite.sh exceptions
./test_basic_suite.sh arrays

# Or run a single test
cd fsh
./basic --run ../tests/exceptions/test_try_catch_basic.bas
```

All tests pass on macOS ARM64 and x86_64. CI runs on every commit via GitHub Actions.

## Key Implementation Insights

### 1. Exception Handling: Direct setjmp Calls
**Critical**: Exception handling calls `setjmp` directly from generated QBE IL, not through a C wrapper. Calling through a wrapper saves the wrapper's stack frame, which `longjmp` then tries to restore after the wrapper has returned, causing crashes. Must also branch immediately after `setjmp` returns - no intermediate instructions, as `longjmp` can corrupt their register state.

### 2. ArrayDescriptor Field Offsets
**Critical**: `elementSize` is at offset 40 in the `ArrayDescriptor` structure, NOT offset 24 (which is `lowerBound2`). Loading from the wrong offset causes memory corruption and allocation errors. Always verify offsets against the runtime struct definition.

### 3. Array String Cleanup
Before reallocating string arrays with REDIM, must call `array_descriptor_erase()` to release individual string memory. Direct `free()` causes memory leaks. After erase, must restore descriptor fields (lowerBound, upperBound, dimensions) as erase sets them to empty state.

### 4. ERASE Semantics
`ERASE` frees array memory but does NOT remove the declaration from the symbol table. The descriptor remains in an empty state. Use `REDIM` to reallocate - attempting to `DIM` again is a semantic error ("array already declared").

### 5. FOR Loops and CFG
FOR loops need explicit edges in the CFG, not reliance on sequential block IDs. When processing a FOR statement, we create an edge from the current block to the FOR init block, ensuring nested loops work correctly.

### 6. String Array Type Inference
Array access expressions require proper type inference to distinguish between numeric and string arrays. The `inferExpressionType()` function handles `EXPR_ARRAY_ACCESS` nodes by looking up array types in the symbol table.

### 7. Slice vs Array Syntax Disambiguation
String slicing (`var$(start TO end)`) and array access (`var$(index)`) share similar syntax. The parser uses lookahead scanning within parentheses to detect the TO keyword, cleanly separating the two constructs without backtracking.

For detailed technical information, see [docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md).

## Runtime

Comprehensive C runtime (`fsh/FasterBASICT/runtime_c/`) provides:

**Core Functions:**
- `basic_init()` / `basic_cleanup()` - initialization/cleanup
- `basic_print_*()` - output functions for all types
- `basic_input_*()` - input functions

**Exception Handling:**
- `basic_exception_push()` / `basic_exception_pop()` - context management
- `basic_throw()` - throw exception with error code and line number
- `basic_err()` / `basic_erl()` - get current error info
- `basic_rethrow()` - propagate unhandled exceptions

**Array Operations:**
- `array_descriptor_erase()` - free array memory (with string cleanup)
- Array allocation and bounds checking
- String array element management

**String Operations:**
- UTF-32 string pool management
- String concatenation, slicing, comparison
- Memory management with reference counting

## Contributing

This is a research/educational project exploring:
- SSA-based compilation of BASIC
- Control flow graph construction for unstructured languages
- Integration of modern compilation techniques with retro languages
- Exception handling via setjmp/longjmp in compiler-generated code
- Dynamic memory management for arrays with proper cleanup

**Before contributing:**
1. Read [START_HERE.md](START_HERE.md)
2. If working on exceptions or arrays, read [docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md)
3. Run `./verify_implementation.sh` before committing
4. Run `./test_basic_suite.sh` to ensure all tests pass
5. Add tests for new features

## License

MIT License

Copyright (c) 2025 FasterBASIC QBE Project Contributors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Acknowledgments

- **QBE** by Quentin Carbonneaux for the excellent SSA backend
- **FasterBASIC** for the language specification and parser foundation
- Classic BASIC implementations (GW-BASIC, QuickBASIC, BBC BASIC) for inspiration

## References

- QBE IL Documentation: https://c9x.me/compile/doc/il.html
- FasterBASIC: [project link]
- Classic BASIC FOR loop semantics and edge cases
