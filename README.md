# FasterBASIC

A modern, compiled BASIC dialect that generates native machine code for macOS ARM64 (Apple Silicon).

True to historical BASIC with some modern extensions.

Aims to be a modern BASIC compiler that combines the ease of traditional BASIC with advanced features like object-oriented programming, exception handling, SIMD acceleration and multiple CPUs.

> **The compiler is now written in Zig.** The Zig-based compiler (`zig_compiler/`) is the primary and actively maintained implementation, replacing the earlier C++ prototype. All new features — Workers, MARSHALL/UNMARSHALL, deep string marshalling — are Zig-only.

[![Build Status](https://github.com/albanread/FasterBASIC/actions/workflows/build.yml/badge.svg)](https://github.com/albanread/FasterBASIC/actions)

 The compiler is written in **Zig** with a hybrid **Zig + C** runtime, and targets the **QBE** SSA backend.

## 🎉 Latest Features (February 2026)

### Workers & Concurrency

Most computers have many CPUs now.

**NEW:**  safe worker threads with structured data passing!

```basic
TYPE Task
  Name AS STRING
  Value AS DOUBLE
END TYPE

DIM t AS Task
t.Name = "compute"
t.Value = 42.0

MARSHALL t INTO buf
WORKER result = MyWorker(buf)
' ...
UNMARSHALL result INTO t2 AS Task
PRINT t2.Name; " = "; t2.Value
```

Workers run in parallel via `pthreads`. Data is passed between threads using `MARSHALL`/`UNMARSHALL`, which deep-copies all string fields to ensure thread safety.

### MARSHALL / UNMARSHALL
**NEW:** Type-safe binary serialisation for UDTs and CLASS objects!

```basic
TYPE Person
  Name AS STRING
  Age AS DOUBLE
END TYPE

DIM p AS Person
p.Name = "Alice"
p.Age = 30

MARSHALL p INTO buf          ' deep-copy (strings are cloned)
UNMARSHALL buf INTO q AS Person
PRINT q.Name                 ' Output: Alice
```

- Works with UDTs and CLASS instances (including inherited fields)
- Automatic deep-copy of STRING fields via static offset tables
- Scalar-only types use a fast flat `memcpy` path
- Can be used anywhere — not restricted to workers

### Array Expressions & SIMD Math

Most computers have 'vector accelerators' now.

Complete array expression engine with NEON SIMD acceleration, reductions, and fused multiply-add.

```basic
DIM A(1000) AS SINGLE, B(1000) AS SINGLE, C(1000) AS SINGLE, D(1000) AS SINGLE

C() = A() + B()              ' element-wise add (NEON vectorized)
D() = A() + B() * C()        ' fused multiply-add (single FMLA instruction)

total! = SUM(A())             ' reduction to scalar
mx! = MAX(A())                ' maximum element
dp! = DOT(A(), B())           ' dot product
B() = ABS(A())                ' element-wise absolute value
```

Supports all numeric types including `BYTE` (16 elements/register) and `SHORT` (8 elements/register). See [Array Expressions](articles/array-expressions.md) for full documentation.

### Object-Oriented Programming

You can organize larger progams into simple classes.

Simple CLASS system with inheritance, polymorphism, and virtual dispatch.

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

Native hashmap support for key-value storage.

Handy addition to now many languages.

```basic
DIM users AS HASHMAP
users("alice") = "Alice Smith"
users("bob") = "Bob Jones"
PRINT users("alice")  ' Output: Alice Smith
```

### Lists with Pattern Matching

Most computers have a lot of memory now, lists can help organize it.

Dynamic lists with type-safe pattern matching.

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

Automatic vectorization for ARM64 platforms.

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

> **⚠️ Build Instructions (Zig Compiler):**
> ```bash
> cd zig_compiler && zig build
> ```
> The compiler executable is `zig_compiler/zig-out/bin/fbc`.
> See [BUILD.md](BUILD.md) for detailed build instructions.
>
> **📁 Project Structure:** See [docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md) for an overview of the repository organization.

## Overview

FasterBASIC is a modern BASIC compiler that combines the ease of traditional BASIC with advanced features like object-oriented programming, exception handling, and SIMD acceleration. The compiler is written in **Zig** and compiles to native machine code through the **QBE** (Quick Backend) intermediate representation.

### Key Features

- **Native Compilation** - Compiles to machine code, not interpreted
- **Zig Compiler** - Written in Zig for memory safety and performance
- **Object-Oriented** - Classes, inheritance, polymorphism, virtual dispatch
- **Workers** - Lightweight concurrent threads with structured data passing
- **MARSHALL/UNMARSHALL** - Type-safe binary serialisation with deep string copy
- **Modern Collections** - Lists, HashMaps, pattern matching
- **Exception Handling** - TRY/CATCH/FINALLY blocks
- **SIMD Acceleration** - Automatic NEON vectorization on ARM64
- **Plugin System** - Extensible with C/C++ plugins
- **Native ARM64** - Optimized for Apple Silicon

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

**Latest Update (February 2026)**: Compiler fully rewritten in Zig. Workers with `MARSHALL`/`UNMARSHALL` for thread-safe data passing. Deep string marshalling via static offset tables. 312 end-to-end tests passing (100%). Full OOP, HashMaps, Lists, NEON SIMD, and plugin system.

### ✅ Core Language Features

**Workers & Marshalling:**
- ✅ WORKER threads via pthreads
- ✅ MARSHALL / UNMARSHALL for UDTs and CLASS objects
- ✅ Deep-copy of STRING fields via static offset tables (marshalling.zig)
- ✅ Fast flat memcpy path for scalar-only types
- ✅ Array marshalling (descriptor + data blob)
- ✅ MARSHALL/UNMARSHALL usable anywhere (not restricted to workers)
- ✅ Nested UDTs and inherited CLASS fields fully supported
- ✅ Worker AWAIT / READY for synchronisation

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
- ✅ Array access in expressions: `PRINT names$(0)`, `x = numbers(i)`
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
- ✅ Optional SIMD disable (OPTION NEON OFF)

**Array Expressions:**
- ✅ Element-wise arithmetic: `C() = A() + B()`, `-`, `*`, `/`
- ✅ Array copy, fill, negate, scalar broadcast
- ✅ Fused multiply-add: `D() = A() + B() * C()` (ARM64 FMLA)
- ✅ Reduction functions: SUM(), MAX(), MIN(), AVG(), DOT()
- ✅ Unary array functions: ABS(), SQR()
- ✅ BYTE (16 lanes) and SHORT (8 lanes) NEON support
- ✅ Correct sub-word memory ops (storeb/loadsb, storeh/loadsh)
- ✅ Scalar MAX(a,b) / MIN(a,b) overloads

### 🚧 In Progress

- **Superterminal Integration**: Graphics, sprites, and audio via Superterminal project
- **Advanced string functions**: Additional string manipulation functions
- **File I/O**: Expanded file handling capabilities
- **Optimization passes**: Additional peephole optimizations

### 📋 Planned

- **Graphics & Multimedia**: Integration with Superterminal for advanced graphics, sprites, and audio
- **Debug info**: Enhanced debugging support with source maps
- **Additional platforms**: Intel Mac, Linux, Windows support
- **Standard library**: Expanded built-in functions

## Quick Start

### Installation

```bash
git clone https://github.com/albanread/FasterBASIC.git
cd FasterBASIC
cd zig_compiler
zig build
```

### Your First Program

Create `hello.bas`:

```basic
PRINT "Hello, FasterBASIC!"
END
```

Compile and run:

```bash
./zig_compiler/zig-out/bin/fbc hello.bas -o hello
./hello
```

### Using the Compiler

The Zig-based `fbc` compiler provides single-command compilation:

```bash
# Compile to executable
./zig_compiler/zig-out/bin/fbc input.bas -o program
./program

# Generate QBE IL only (for debugging)
./zig_compiler/zig-out/bin/fbc input.bas -i -o output.qbe

# Generate assembly only
./zig_compiler/zig-out/bin/fbc input.bas -c -o output.s
```

**Features:**
- Single command compilation from BASIC → executable
- Written in Zig with a hybrid Zig + C runtime
- Optimized for macOS ARM64 (Apple Silicon)
- Smart runtime caching (fast subsequent builds)
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
# Run the full parallel test suite (312 tests)
bash run_tests_parallel.sh

# Run specific test categories
bash run_e2e_tests.sh marshall
bash run_e2e_tests.sh workers
bash run_e2e_tests.sh classes
bash run_e2e_tests.sh lists
```

### Developer Resources

- **[START_HERE.md](START_HERE.md)** - Comprehensive developer guide
- **[docs/PROJECT_STRUCTURE.md](docs/PROJECT_STRUCTURE.md)** - Repository organization
- **[docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md)** - Technical details
- **[BUILD.md](BUILD.md)** - Detailed build instructions

## Platform Support

### Auto-Detection

FasterBASIC is currently built and tested on:

- **macOS ARM64** (Apple Silicon M1/M2/M3/M4)

The compiler uses the QBE backend which supports multiple architectures (AMD64, ARM64, RISC-V), making future platform support possible.

### Runtime Library

The runtime is built by Zig's build system alongside the compiler:
- Zig runtime modules are compiled as static object files
- C runtime modules are compiled via Zig's C compiler integration
- QBE backend is also compiled and linked in
- Self-contained in `zig_compiler/runtime/` directory

### Cross-Compilation

The QBE backend supports cross-compilation to other architectures, though primary development and testing is on macOS ARM64.

## Architecture

```
┌─────────────────┐
│  BASIC Source   │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Lexer (Zig)    │  Tokenization
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Parser (Zig)   │  AST Construction
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Semantic      │  Type checking, symbol resolution
│  Analyzer (Zig) │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  CFG Builder    │  Control Flow Graph construction
│     (Zig)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  QBE CodeGen    │  Generate QBE IL (SSA form)
│     (Zig)       │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  QBE Compiler   │  QBE → Assembly
│      (C)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Assembler     │  Assembly → Object code
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│     Linker      │  Link with Zig + C runtime → Executable
└─────────────────┘
```

### Runtime Libraries

The runtime is a hybrid of **Zig** and **C** modules linked together by the Zig build system:

| Module | Language | Purpose |
|--------|----------|---------|
| `string_utf32.zig` | Zig | UTF-32 string pool, `string_clone` |
| `marshalling.zig` | Zig | MARSHALL/UNMARSHALL deep-copy with offset tables |
| `class_runtime.zig` | Zig | Object allocation, vtable dispatch |
| `samm_runtime.zig` | Zig | Scope-Aware Memory Manager |
| `list_runtime.zig` | Zig | LIST OF type / LIST OF ANY |
| `hashmap_runtime.zig` | Zig | HASHMAP operations |
| `worker_runtime.c` | C | Worker threads (pthreads, futures) |
| `runtime_basic.c` | C | Core PRINT, INPUT, math, exceptions |
| `array_descriptor.c` | C | Array allocation, bounds checking |

## Building

### Prerequisites

- **Zig** (0.13+ recommended) — the compiler and runtime are built with Zig
- Standard build tools (`as`, `cc`) — for assembling and linking
- QBE is included in the repository (no separate installation needed)

### Build the Zig Compiler (Recommended)

```bash
cd zig_compiler
zig build
```

This builds `fbc`, a single executable that combines:
- FasterBASIC compiler (lexer, parser, semantic analyzer, CFG builder) — all Zig
- QBE code generator (Zig)
- QBE SSA optimizer and code emitter (bundled C)
- Hybrid Zig + C runtime libraries

The compiler executable is at `zig_compiler/zig-out/bin/fbc`.

### Using the Compiler

```bash
# Compile BASIC directly to executable (one command!)
./zig_compiler/zig-out/bin/fbc input.bas -o myprogram
./myprogram

# Generate QBE IL only (for inspection/debugging)
./zig_compiler/zig-out/bin/fbc input.bas -i -o output.qbe

# Generate assembly only (for manual linking)
./zig_compiler/zig-out/bin/fbc input.bas -c -o output.s
```

### Legacy C++ Compiler

The original C++ compiler remains in `qbe_basic_integrated/` for reference but is **no longer maintained**. All active development uses the Zig compiler.

## Example Programs

### Hello World
```basic
PRINT "Hello, World!"
END
```

### FOR Loop with Nested Loops
```basic
FOR i = 1 TO 3
    PRINT "Outer: i = "; i
    FOR j = 1 TO 2
        PRINT "  Inner: j = "; j
    NEXT j
NEXT i
END
```

### Recursive Function
```basic
FUNCTION Factorial(N)
    IF N <= 1 THEN
        Factorial = 1
    ELSE
        Factorial = N * Factorial(N - 1)
    END IF
END FUNCTION

PRINT "5! = "; Factorial(5)
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
FOR i = 1 TO 5
    PRINT i
NEXT i
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

**312 end-to-end tests — 100% pass rate.** Comprehensive test suite covering:

**Marshall/Unmarshall Tests** (`tests/marshall/`)
- UDT scalar, string, and mixed field marshalling
- CLASS scalar and string field marshalling
- All-strings and empty-string edge cases
- Multiple marshalls from the same object
- MARSHALL/UNMARSHALL inside SUB
- Nested UDTs (scalar and string at both levels)
- CLASS inheritance (3-level, with and without strings)

**Worker Tests** (`tests/workers/`)
- Worker spawn and await
- CLASS + STRING across worker boundary
- String round-trip via worker (create in worker, return marshalled)
- MARSHALL/UNMARSHALL without workers

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
- Classes, inheritance, polymorphism
- Lists and pattern matching
- HashMaps
- Recursive functions
- String operations
- Arithmetic and bitwise operations
- Type conversions
- NEON SIMD operations

Run the full test suite:
```bash
# Parallel execution (recommended)
bash run_tests_parallel.sh

# Filtered by category
bash run_e2e_tests.sh marshall
bash run_e2e_tests.sh workers
bash run_e2e_tests.sh classes
```

All tests pass on macOS ARM64.

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

Hybrid **Zig + C** runtime (`zig_compiler/runtime/`) provides:

**Core Functions (C):**
- `basic_init()` / `basic_cleanup()` - initialization/cleanup
- `basic_print_*()` - output functions for all types
- `basic_input_*()` - input functions

**Exception Handling (C):**
- `basic_exception_push()` / `basic_exception_pop()` - context management
- `basic_throw()` - throw exception with error code and line number
- `basic_err()` / `basic_erl()` - get current error info
- `basic_rethrow()` - propagate unhandled exceptions

**String Operations (Zig):**
- UTF-32 string pool management (`string_utf32.zig`)
- `string_clone` — deep-copy a string descriptor
- String concatenation, slicing, comparison

**Marshalling (Zig):**
- `marshall_udt` / `unmarshall_udt` — flat memcpy for scalar-only types
- `marshall_udt_deep` / `unmarshall_udt_deep` — deep-copy with string offset table
- `marshall_array` / `unmarshall_array` — descriptor + element data blob

**Object System (Zig):**
- `class_runtime.zig` — object allocation, vtable dispatch, inheritance
- `samm_runtime.zig` — Scope-Aware Memory Manager for automatic cleanup

**Collections (Zig):**
- `list_runtime.zig` — typed lists and LIST OF ANY
- `hashmap_runtime.zig` — hash map operations

**Workers (C):**
- `worker_runtime.c` — thread spawn/await/ready via pthreads

**Array Operations (C):**
- `array_descriptor_erase()` - free array memory (with string cleanup)
- Array allocation and bounds checking

## Contributing

FasterBASIC explores modern compiler techniques applied to a classic language:
- **Zig compiler** with hybrid Zig + C runtime
- Object-oriented programming in BASIC with virtual dispatch
- Workers and deep marshalling for concurrency
- SSA-based compilation via QBE backend
- SIMD optimization for ARM64 NEON
- Pattern matching and type dispatch for heterogeneous collections
- Scope-aware memory management (SAMM)
- Plugin architecture for extensibility

**Before contributing:**
1. Read [START_HERE.md](START_HERE.md) for project overview
2. Check [docs/CRITICAL_IMPLEMENTATION_NOTES.md](docs/CRITICAL_IMPLEMENTATION_NOTES.md) for technical details
3. Review the [Wiki](https://github.com/albanread/FasterBASIC/wiki) for language documentation
4. Run `bash run_tests_parallel.sh` to ensure all 312 tests pass
5. Add tests for new features

**Areas for contribution:**
- Additional language features and standard library functions
- Plugin development (see `plugins/` directory)
- Platform support (Intel Mac, Linux, Windows)
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
