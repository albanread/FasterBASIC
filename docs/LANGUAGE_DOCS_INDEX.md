# FasterBASIC Language Documentation Index

## Overview

This directory contains comprehensive documentation for the FasterBASIC language, a modern compiled BASIC dialect that generates native machine code for AMD64, ARM64, and RISC-V architectures.

## Documentation Files

### 1. **FasterBASIC_BNF.md** (26 KB)
Complete Backus-Naur Form (BNF) grammar specification of the FasterBASIC language.

**Contents:**
- Formal grammar definition
- Lexical elements and tokens
- Statement syntax rules
- Expression parsing rules
- Operator precedence
- Type system specification
- Built-in functions
- Language extensions
- Implementation notes

**Best for:** Language implementers, compiler developers, formal language specification

### 2. **FasterBASIC_Language_Summary.md** (12 KB)
Comprehensive language guide with examples and explanations.

**Contents:**
- Type system overview
- Variables and arrays
- Control flow structures
- Subroutines and functions
- Exception handling
- Input/Output operations
- String operations
- Graphics and multimedia
- Timer events
- Data statements
- Advanced features
- Compiler options
- Example programs
- Compilation process
- Architecture overview

**Best for:** Learning the language, reference documentation, tutorials

### 3. **FasterBASIC_QuickRef.md** (9 KB)
Quick reference card for fast lookup of syntax and features.

**Contents:**
- Basic syntax
- Data types
- Operators
- Control flow (condensed)
- Loops (condensed)
- Subroutines & functions (condensed)
- I/O statements
- String functions
- Math functions
- Graphics commands
- Timer events
- Common patterns
- Quick tips
- Compilation commands

**Best for:** Quick syntax lookup, experienced programmers, cheat sheet

### 4. **FasterBASIC_overview.md** (4 KB)
High-level architectural overview of the compiler and language.

**Contents:**
- Executive summary
- Compiler architecture
- Frontend (Lexer/Parser)
- Middle-end (CodeGen V2)
- Backend (QBE Integration)
- Runtime environment
- Build system
- Assessment

**Best for:** Understanding compiler internals, architecture overview

### 5. **ARRAY_EXPRESSIONS.md**
Comprehensive guide to whole-array operations, SIMD acceleration, and reduction functions.

**Contents:**
- Introduction to array expressions
- Supported arithmetic and logic operations
- Array broadcast, fill, and copy
- Reduction functions (SUM, MAX, MIN, DOT)
- SIMD optimization details
- Performance guide

**Best for:** Learning how to write high-performance array code

## How to Use This Documentation

### New to FasterBASIC?
Start with **FasterBASIC_Language_Summary.md** for a complete introduction with examples.

### Need Quick Syntax?
Use **FasterBASIC_QuickRef.md** for fast lookup of commands and syntax.

### Implementing a Parser/Compiler?
Reference **FasterBASIC_BNF.md** for the formal grammar specification.

### Understanding the Compiler?
Read **FasterBASIC_overview.md** for the compiler architecture.

## Language Features at a Glance

### Core Features
- ✅ Traditional BASIC syntax with optional line numbers
- ✅ Modern structured programming (IF/THEN/ELSE, SELECT CASE)
- ✅ Multiple loop types (FOR, WHILE, DO, REPEAT)
- ✅ Subroutines (SUB) and Functions (FUNCTION)
- ✅ Exception handling (TRY/CATCH/FINALLY)
- ✅ User-defined types (TYPE...END TYPE)
- ✅ Dynamic arrays with REDIM
- ✅ String slicing and manipulation

### Advanced Features
- ✅ Timer events (AFTER, EVERY)
- ✅ Event-driven programming with RUN loop
- ✅ Graphics primitives (LINE, RECT, CIRCLE)
- ✅ Sprite system with transformations
- ✅ Text layer with positioned I/O
- ✅ Audio playback
- ✅ File I/O
- ✅ Compiler directives (OPTION statements)

### Type System
- **INTEGER** (%) - 32-bit signed
- **LONG** (&) - 64-bit signed
- **SINGLE** (!) - 32-bit float
- **DOUBLE** (#) - 64-bit float
- **STRING** ($) - ASCII or UTF-32
- **BYTE** (@) - 8-bit unsigned
- **SHORT** (^) - 16-bit signed
- **User-Defined Types** - Composite structures

### Compilation
- AOT (Ahead-of-Time) compilation to native code
- QBE backend for code generation
- Targets: AMD64, ARM64, RISC-V (RV64)
- Fast compilation times
- Optimized machine code output

## Code Examples

### Hello World
```basic
PRINT "Hello, World!"
END
```

### For Loop
```basic
FOR i = 1 TO 10
  PRINT i
NEXT i
```

### Function
```basic
FUNCTION Add(a%, b%) AS INTEGER
  RETURN a% + b%
END FUNCTION

PRINT Add(5, 10)
```

### Exception Handling
```basic
TRY
  THROW 100
CATCH 100
  PRINT "Caught error"
END TRY
```

### Timer Event
```basic
EVERY 1000 MS DO
  PRINT "Tick"
DONE

RUN
```

## Additional Resources

### Source Code Directories
- **Lexer/Parser**: `fsh/FasterBASICT/src/`
- **Runtime**: `qbe_basic_integrated/runtime/`
- **QBE Backend**: `qbe_basic_integrated/qbe_source/`
- **Tests**: `tests/`

### Build and Test
- **Build Script**: `qbe_basic_integrated/build_qbe_basic.sh`
- **Test Runner**: `scripts/run_tests_simple.sh`
- **Build Instructions**: `BUILD.md`

### Test Suite
The `tests/` directory contains 123 test programs organized by category:
- `tests/arithmetic/` - Math operations
- `tests/loops/` - Loop constructs
- `tests/strings/` - String manipulation
- `tests/functions/` - Subroutines and functions
- `tests/arrays/` - Array operations
- `tests/types/` - Type system
- `tests/exceptions/` - Exception handling
- `tests/rosetta/` - Algorithm examples

## Getting Started

### Prerequisites
- C++17 compiler (g++ or clang)
- QBE compiler (included)
- Make or similar build tool

### Build the Compiler
```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

### Compile a Program
```bash
./qbe_basic_integrated/fbc_qbe myprogram.bas -o myprogram
```

### Run the Program
```bash
./myprogram
```

### Run Test Suite
```bash
./scripts/run_tests_simple.sh
```

## Version Information

This documentation describes the FasterBASIC language as implemented in the current repository version.

**Test Results**: 119/123 tests passing (96.7%)

## Contributing

When contributing to the language:
1. Review the BNF grammar for syntax consistency
2. Add tests to the appropriate test directory
3. Update documentation to reflect new features
4. Run the test suite to verify compatibility

## License

See LICENSE file in the project root.

## Documentation Maintenance

- **Last Updated**: February 2024
- **Compiler Version**: CodeGen V2
- **Grammar Version**: As implemented in `fasterbasic_parser.cpp`

For questions or issues, please refer to the source code and test suite for authoritative behavior.