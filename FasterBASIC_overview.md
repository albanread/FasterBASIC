# FasterBASIC: Compiler Architecture & Language Review

## Executive Summary

FasterBASIC is a modern, high-performance implementation of the BASIC programming language. Unlike traditional BASIC interpreters, FasterBASIC is a full AOT (Ahead-of-Time) compiler that leverages a sophisticated C++ frontend and the QBE (Quick Backend) compiler infrastructure to generate highly optimized native machine code.

The project demonstrates a significant architectural shift with its "CodeGen V2" engine, moving towards a robust Control Flow Graph (CFG) based representation that enables advanced analysis and optimization before code generation.

## Compiler Architecture

The compiler follows a classic three-stage design, implemented primarily in C++17.

### 1. The Frontend
Located in `fsh/FasterBASICT/src`, the frontend is responsible for parsing the BASIC source code.
*   **Lexer & Parser**: A custom recursive descent parser converts BASIC source code into an Abstract Syntax Tree (AST).
*   **Semantic Analysis**: Type checking and scope resolution occur here. The type system supports standard primitives (`INTEGER`, `FLOAT`, `DOUBLE`, `STRING`) as well as `USER_DEFINED` types and `UNICODE` support.
*   **Command Registry**: The language uses a modular command registry (`command_registry_core.cpp`), allowing for easy addition of new keywords and statements without destabilizing the core parser.

### 2. The Middle-End (CodeGen V2)
This is the heart of the recent improvements. The compiler transforms the AST into a Control Flow Graph (CFG).
*   **CFG Construction**: A dedicated suite of builders (`cfg/cfg_builder_*.cpp`) handles specific constructs:
    *   `cfg_builder_loops.cpp`: Handles `FOR`/`NEXT`, `DO`/`LOOP`.
    *   `cfg_builder_conditional.cpp`: Handles `IF`/`THEN`/`ELSE`, `SELECT CASE`.
    *   `cfg_builder_exception.cpp`: Suggests support for structured error handling.
*   **Analysis**: The CFG representation allows the compiler to understand the flow of execution, optimizing jump targets and block structure before generating IR.

### 3. The Backend (QBE Integration)
Instead of generating assembly directly or using LLVM (which can be heavy), FasterBASIC integrates **QBE**.
*   **Translation**: The `codegen_v2` module translates the internal CFG into QBE's Intermediate Language (IL).
*   **QBE Core**: The integrated QBE source (`qbe_source/`) compiles this IL into assembly for the target architecture.
*   **Native Output**: The system supports multiple architectures including **AMD64**, **ARM64**, and **RISC-V (RV64)**, making it highly portable across modern hardware (Intel/AMD, Apple Silicon, Raspberry Pi, etc.).

## Runtime Environment

FasterBASIC relies on a hybrid runtime system:
1.  **C Runtime (`runtime_c/`)**: Handles low-level operations for speed.
    *   String pooling and UTF-32 manipulation.
    *   Array descriptor management.
    *   Memory management.
2.  **C++ Runtime (`runtime/`)**: Handles higher-level abstractions.
    *   Event queues.
    *   File/Terminal I/O managers.
3.  **Lua Integration**: The presence of `*_lua_bindings.cpp` indicates a powerful feature: the ability to embed Lua or interface with Lua scripts, potentially for plugin systems or dynamic evaluation.

## Build System

The build process is streamlined via `build_qbe_basic.sh`.
*   It performs a parallel build of the FasterBASIC compiler sources.
*   It automatically configures and builds the QBE backend based on the host architecture (`uname -m`).
*   It links the compiler frontend, the optimization passes, and the QBE backend into a single standalone executable `fbc_qbe`.

## Assessment

FasterBASIC represents a "modernization" of the BASIC language. It retains the ease of use associated with BASIC but adopts the tooling and architectural rigor of modern systems programming languages. The move to a CFG-based middle-end is a critical step that separates it from simple transpilers, allowing for true compiler optimizations and reliable native code generation.