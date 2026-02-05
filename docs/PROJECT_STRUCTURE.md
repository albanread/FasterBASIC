# FasterBASIC Project Structure

This document describes the organization of the FasterBASIC compiler project.

## Root Directory

The root contains only essential project-level files:

- `README.md` - Main project readme with overview and getting started
- `LICENSE` - Project license
- `BUILD.md` - Build instructions
- `.gitignore` - Git ignore rules

## Directory Structure

### `/qbe_basic_integrated/`
The main compiler implementation using QBE (C compiler backend).

- `compiler/` - Core compiler components
  - `lexer/` - Tokenization
  - `parser/` - AST generation
  - `codegen_v2/` - QBE IL code generation
  - `type_system/` - Type checking and UDT support
- `runtime/` - C runtime library
  - String management (reference counting)
  - Array support
  - HashMap implementation
  - Built-in functions (PRINT, INPUT, etc.)
- `include/` - Runtime header files

### `/fsh/`
The original FasterBASIC shell-based compiler (legacy).

Contains the initial implementation that translates BASIC to shell scripts.

### `/tests/`
Test suite for the compiler.

- `arithmetic/` - Math and operator tests
- `arrays/` - Array functionality tests
- `comparisons/` - Comparison operator tests
- `conditionals/` - IF/THEN/ELSE, SELECT CASE tests
- `functions/` - Function and SUB tests
- `loops/` - FOR, WHILE, DO tests
- `strings/` - String operation tests
- `hashmap/` - HashMap/dictionary tests
- `io/` - Input/output tests
- `rosetta/` - Rosetta Code examples
- `test_*.bas` - Individual test files

### `/examples/`
Demo programs showcasing language features.

- `demo_*.bas` - Demo source files
- Compiled demo executables

### `/test_output/`
Build artifacts from test compilation.

- Compiled test executables
- Intermediate files (`.qbe`, `.s`, `.c`)
- Generated assembly and object files

This directory is excluded from version control and can be safely deleted.

### `/docs/`
Project documentation and development notes.

#### Language Documentation
- `FasterBASIC_BNF.md` - Formal grammar specification
- `FasterBASIC_Language_Summary.md` - Language features overview
- `FasterBASIC_QuickRef.md` - Quick reference guide
- `FasterBASIC_overview.md` - High-level language overview
- `LANGUAGE_DOCS_INDEX.md` - Index of all language docs

#### Feature Documentation
- `UDT_*.md` - User-Defined Type (struct) implementation docs
- `HASHMAP_*.md` - HashMap implementation and integration docs
- `OBJECT_*.md` - Object/method system design and implementation
- `Timer_support_design.md` - Timer feature design
- `hash-map.md` - HashMap design document

#### Development Notes
- `ADDING_OBJECT_TYPES.md` - Object-oriented features design
- `LOGICAL_OPERATORS_FIX.md` - Boolean logic fixes
- `STRING_POOL_FIX_SUMMARY.md` - String literal optimization
- `TESTABLE_IL_METHODOLOGY.md` - Testing approach for IL generation
- `QBE_COMPILATION_FEATURE.md` - QBE backend integration
- `PERFORMANCE_OPTIMIZATION_NEEDED.md` - Performance TODO items

#### Status and Progress
- `FINAL_STATUS.md` - Current project status
- `FINAL_ACHIEVEMENT_SUMMARY.md` - Major milestones achieved
- `GIT_STATUS.md` - Git repository status
- `VERIFICATION_REPORT.md` - Test verification results
- `SESSION_SUMMARY_*.md` - Development session summaries

#### Build Documentation
- `selfhosting-prereqs.md` - Requirements for self-hosting compiler

### `/scripts/`
Build and utility scripts.

- Build automation
- Test runners
- Code generation utilities

## Build Artifacts

Generated files during compilation:

- `.qbe` - QBE intermediate language files
- `.s` - Assembly source files
- `.o` - Object files
- Executables (no extension) - Compiled programs

These are typically stored in `/test_output/` or `/examples/` and are not version controlled.

## Key Components

### Compiler Pipeline

1. **Lexer** - Tokenizes BASIC source → tokens
2. **Parser** - Parses tokens → AST (Abstract Syntax Tree)
3. **Type Checker** - Validates types, resolves symbols
4. **Code Generator** - Emits QBE IL
5. **QBE** - Compiles IL → assembly
6. **System Assembler** - Assembles → object code
7. **System Linker** - Links with runtime → executable

### Runtime Library

Written in C, provides:
- String handling (refcounted descriptors)
- Dynamic arrays (with bounds checking)
- HashMap implementation (open addressing)
- Built-in functions (PRINT, INPUT, CHR$, STR$, etc.)
- Memory management

### Type System

- Scalar types: INTEGER (i32), LONG (i64), SINGLE (f32), DOUBLE (f64)
- STRING type (reference-counted)
- Arrays of any type
- User-Defined Types (UDTs/structs) with nesting
- Type inference for numeric literals

## Development Workflow

1. Write test case in `/tests/`
2. Run compiler: `./qbe_basic_integrated/fbc test.bas`
3. Generates QBE IL and compiles to executable
4. Run and verify output
5. Compiled artifacts go to `/test_output/`

## Git Organization

- Main development on `main` branch
- Feature branches for major additions
- Tags for milestones (e.g., `v1.0-udt-assignment`)

---

*Last updated: 2024-02-05*