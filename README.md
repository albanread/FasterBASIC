# FasterBASIC

[![Build Status](https://github.com/albanread/FasterBASIC/actions/workflows/build.yml/badge.svg)](https://github.com/albanread/FasterBASIC/actions)

A modern, compiled BASIC dialect that generates native machine code for AMD64, ARM64, and RISC-V architectures.

## 🎉 Latest Features (February 2025)

### Object-Oriented Programming
**NEW:** Full CLASS system with inheritance, polymorphism, and virtual dispatch!

```basic
CLASS Animal
  Name AS STRING
  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
  METHOD Speak() AS STRING
    RETURN "..."
  END METHOD
END CLASS

CLASS Dog EXTENDS Animal
  METHOD Speak() AS STRING
    RETURN "Woof!"
  END METHOD
END CLASS

DIM pet AS Dog = NEW Dog("Rex")
PRINT pet.Speak()  ' Output: Woof!
```

### HashMaps
**NEW:** Native hashmap support for key-value storage!

```basic
DIM users AS HASHMAP
users("alice") = "Alice Smith"
users("bob") = "Bob Jones"
PRINT users("alice")  ' Output: Alice Smith
```

### Lists with Pattern Matching
**NEW:** Dynamic lists with type-safe pattern matching!

```basic
DIM items AS LIST OF ANY
items.APPEND(42)
items.APPEND("Hello")

FOR EACH item IN items
  MATCH TYPE item
    CASE INTEGER n
      PRINT "Integer: "; n
    CASE STRING s
      PRINT "String: "; s
  END MATCH
NEXT
```

### NEON SIMD Acceleration
**NEW:** Automatic vectorization for ARM64 platforms!

```basic
TYPE Vec4
  X AS SINGLE
  Y AS SINGLE
  Z AS SINGLE
  W AS SINGLE
END TYPE

DIM v1 AS Vec4, v2 AS Vec4, result AS Vec4
result = v1 + v2  ' ← Compiles to NEON SIMD instructions!
```

---

> **⚠️ Important Build Note:** This project has a single build location. Always build using:
> ```bash
> cd qbe_basic_integrated && ./build_qbe_basic.sh
> ```
> The `qbe_basic` executable at the project root is a **symlink** to `qbe_basic_integrated/qbe_basic`.
> See [BUILD.md](BUILD.md) for detailed build instructions.
>
> **📁 Project Structure:** See [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for an overview of the repository organization.

## Overview

FasterBASIC is a modern BASIC compiler that combines the ease of traditional BASIC with advanced features like object-oriented programming, exception handling, and SIMD acceleration. It compiles to native machine code through the QBE (Quick Backend) intermediate representation.

### Key Features

- **Native Compilation** - Compiles to machine code, not interpreted
- **Object-Oriented** - Classes, inheritance, polymorphism, virtual dispatch
- **Modern Collections** - Lists, HashMaps, pattern matching
- **Exception Handling** - TRY/CATCH/FINALLY blocks
- **SIMD Acceleration** - Automatic NEON vectorization on ARM64
- **Plugin System** - Extensible with C/C++ plugins
- **Cross-Platform** - AMD64, ARM64, RISC-V support

> **Note on Graphics & Multimedia:** FasterBASIC will integrate with the [Superterminal](https://github.com/albanread/Superterminal) project to provide advanced graphics, sprites, and audio capabilities in the future.

### Documentation

📚 **[Visit the Wiki](https://github.com/albanread/FasterBASIC/wiki)** for comprehensive documentation:

- **[Quick Reference](https://github.com/albanread/FasterBASIC/wiki/Quick-Reference)** - Syntax cheat sheet
- **[Language Summary](https://github.com/albanread/FasterBASIC/wiki/Language-Summary)** - Complete language reference
- **[Classes and Objects](https://github.com/albanread/FasterBASIC/wiki/Classes-and-Objects)** - OOP guide
- **[Lists and Pattern Matching](https://github.com/albanread/FasterBASIC/wiki/Lists-and-Pattern-Matching)** - Collections guide
- **[NEON SIMD Support](https://github.com/albanread/FasterBASIC/wiki/NEON-SIMD-Support)** - Performance optimization
- **[BNF Grammar](https://github.com/albanread/FasterBASIC/wiki/BNF-Grammar)** - Formal specification

## Project Status

**Latest Update (February 2025)**: Full object-oriented programming with classes, inheritance, and polymorphism. HashMaps, Lists with pattern matching, NEON SIMD acceleration, and a comprehensive plugin system.

### ✅ Core Language Features

**Object-Oriented Programming:**
- ✅ CLASS/END CLASS declarations
- ✅ Fields (all primitive types + class references)
- ✅ CONSTRUCTOR with parameters
- ✅ DESTRUCTOR with automatic cleanup
- ✅ METHOD with return values
- ✅ ME keyword for self-reference
- ✅ Inheritance with EXTENDS
- ✅ SUPER() for parent constructor calls
- ✅ Virtual dispatch (polymorphism)
- ✅ IS operator for type checking
- ✅ DELETE for explicit object destruction
- ✅ SAMM (Scope-Aware Memory Manager) for automatic cleanup

**Collections:**
- ✅ LIST OF type (typed lists)
- ✅ LIST OF ANY (heterogeneous lists)
- ✅ List methods: APPEND, PREPEND, POP, SHIFT, GET, LENGTH, etc.
- ✅ HASHMAP type for key-value storage
- ✅ HashMap operations: assignment, lookup, iteration
- ✅ FOR EACH loops for lists and hashmaps
- ✅ MATCH TYPE for type dispatch on LIST OF ANY

**User-Defined Types (UDTs):**
- ✅ TYPE/END TYPE declarations
- ✅ UDT member access (read/write)
- ✅ UDT-to-UDT assignment with proper string refcounting
- ✅ String fields with proper refcounting
- ✅ Nested UDTs (recursive field access)
- ✅ Arrays of UDTs
- ✅ SIMD optimization for homogeneous numeric UDTs

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

**Plugin System:**
- ✅ C/C++ plugin architecture
- ✅ Automatic loading from plugins/enabled/
- ✅ Plugin commands integrated into language
- ✅ Command registry system

**Performance:**
- ✅ NEON SIMD acceleration for ARM64
- ✅ Automatic vectorization for UDT operations
- ✅ SIMD test suite and verification
- ✅ Optional SIMD disable (OPTION NO_NEON)

### 🚧 In Progress

- **Superterminal Integration**: Graphics, sprites, and audio via Superterminal project
- **Advanced string functions**: Additional string manipulation functions
- **File I/O**: Expanded file handling capabilities
- **Optimization passes**: Additional peephole optimizations

### 📋 Planned

- **Graphics & Multimedia**: Integration with Superterminal for advanced graphics, sprites, and audio
- **Debug info**: Enhanced debugging support with source maps
- **Additional platforms**: Windows support
- **Standard library**: Expanded built-in functions

## Quick Start

### Installation

```bash
git clone https://github.com/albanread/FasterBASIC.git
cd FasterBASIC
cd qbe_basic_integrated
./build_qbe_basic.sh
```

### Your First Program

Create `hello.bas`:

```basic
PRINT "Hello, FasterBASIC!"
END
```

Compile and run:

```bash
./qbe_basic -o hello hello.bas
./hello
```

### Using the Compiler

The integrated `qbe_basic` compiler provides single-command compilation:

```bash
# Compile to executable
./qbe_basic -o program input.bas

# Generate QBE IL only (for debugging)
./qbe_basic -i -o output.qbe input.bas

# Generate assembly only
./qbe_basic -c -o output.s input.bas

# Target specific architecture
./qbe_basic -t arm64_apple -o program input.bas
```

**Features:**
- Single command compilation from BASIC → executable
- Automatic platform detection (macOS ARM64/x86_64, Linux)
- Smart runtime caching (10x faster on subsequent builds)
- Self-contained with bundled runtime library

### Examples

```basic
' Object-Oriented Programming
CLASS Rectangle
  Width AS DOUBLE
  Height AS DOUBLE
  
  CONSTRUCTOR(w AS DOUBLE, h AS DOUBLE)
    ME.Width = w
    ME.Height = h
  END CONSTRUCTOR
  
  METHOD Area() AS DOUBLE
    RETURN ME.Width * ME.Height
  END METHOD
END CLASS

DIM r AS Rectangle = NEW Rectangle(10.0, 5.0)
PRINT "Area: "; r.Area()

' Lists and Pattern Matching
DIM items AS LIST OF ANY
items.APPEND(42)
items.APPEND("Hello")
items.APPEND(3.14)

FOR EACH item IN items
  MATCH TYPE item
    CASE INTEGER n
      PRINT "Integer: "; n * 2
    CASE STRING s
      PRINT "String: "; s
    CASE DOUBLE d
      PRINT "Double: "; d
  END MATCH
NEXT

' HashMaps
DIM scores AS HASHMAP
scores("Alice") = "95"
scores("Bob") = "87"
scores("Charlie") = "92"

FOR EACH name IN scores
  PRINT name; ": "; scores(name)
NEXT

' Exception Handling
TRY
  THROW 100
CATCH 100
  PRINT "Caught error: "; ERR()
FINALLY
  PRINT "Cleanup"
END TRY
```

### Testing

```bash
# Run the full test suite
./scripts/run_tests_simple.sh

# Run specific test categories
./scripts/run_tests_simple.sh classes
./scripts/run_tests_simple.sh lists
```

### Developer Resources

- **[START_HERE.md](START_HERE.md)** - Comprehensive developer guide
- **[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** - Repository organization
- **[docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md)** - Technical details
- **[BUILD.md](BUILD.md)** - Detailed build instructions

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

### Linked Lists (LIST)

```basic
OPTION SAMM ON

' Typed lists — element type is known at compile time
DIM nums AS LIST OF INTEGER = LIST(10, 20, 30)
DIM words AS LIST OF STRING = LIST("hello", "world")

' Basic operations
nums.APPEND(40)
nums.PREPEND(5)
PRINT "Length: "; nums.LENGTH()
PRINT "Head: "; nums.HEAD()
PRINT "Get(2): "; nums.GET(2)

' Subscript sugar — myList(n) is shorthand for myList.GET(n)
PRINT "nums(3): "; nums(3)

' Removal
DIM first% = nums.SHIFT()    ' Remove and return first element
DIM last%  = nums.POP()      ' Remove and return last element
nums.REMOVE(2)                ' Remove element at position 2

' Search
PRINT "Contains 20: "; nums.CONTAINS(20)
PRINT "IndexOf 20: "; nums.INDEXOF(20)

' String list operations
DIM joined$ = words.JOIN(", ")
PRINT "Joined: "; joined$

' Iteration with FOR EACH
FOR EACH elem IN nums
    PRINT elem; " ";
NEXT elem

' Iteration with index
FOR EACH val, idx IN nums
    PRINT "Index "; idx; ": "; val
NEXT val

' Copy and reverse (return new lists)
DIM rev AS LIST OF INTEGER = nums.REVERSE()
DIM dup AS LIST OF INTEGER = nums.COPY()

' ERASE frees a list and sets the variable to null
ERASE nums
END
```

### MATCH TYPE (Safe Type Dispatch)

```basic
OPTION SAMM ON

' LIST OF ANY holds elements of mixed types
DIM mixed AS LIST OF ANY = LIST(42, "hello", 3.14)

' MATCH TYPE safely dispatches on element type
' The compiler fuses the type check and typed load — no way to mismatch
FOR EACH T, E IN mixed
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Flt: "; f#
        CASE ELSE
            PRINT "Other type"
    END MATCH
NEXT T
END
```

**MATCH TYPE guarantees:**
- Binding variable type always matches the CASE arm (compiler-enforced)
- No `AS` casts needed — the typed load is fused into each arm
- Duplicate type arms are a compile-time error
- Binding variables are scoped to their arm (no leaking)
- Zero runtime overhead vs. manual `SELECT CASE` + `AS`

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

FasterBASIC explores modern compiler techniques applied to a classic language:
- Object-oriented programming in BASIC with virtual dispatch
- SSA-based compilation via QBE backend
- SIMD optimization for ARM64 NEON
- Pattern matching and type dispatch for heterogeneous collections
- Scope-aware memory management (SAMM)
- Plugin architecture for extensibility

**Before contributing:**
1. Read [START_HERE.md](START_HERE.md) for project overview
2. Check [docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md) for technical details
3. Review the [Wiki](https://github.com/albanread/FasterBASIC/wiki) for language documentation
4. Run `./scripts/run_tests_simple.sh` to ensure all tests pass
5. Add tests for new features

**Areas for contribution:**
- Additional language features and standard library functions
- Plugin development (see `plugins/` directory)
- Platform support (Windows, additional architectures)
- Optimization passes and performance improvements
- Documentation and examples

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
- Classic BASIC implementations (GW-BASIC, QuickBASIC, BBC BASIC) for inspiration
- The BASIC programming community for continued enthusiasm

## References

- **[Project Wiki](https://github.com/albanread/FasterBASIC/wiki)** - Complete documentation
- **[QBE IL Documentation](https://c9x.me/compile/doc/il.html)** - Backend reference
- **[GitHub Repository](https://github.com/albanread/FasterBASIC)** - Source code
