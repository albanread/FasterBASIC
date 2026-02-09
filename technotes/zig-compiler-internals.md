# Zig Compiler Internals

This document provides a deep dive into the internal architecture of the experimental Zig compiler for FasterBASIC. It is intended for compiler maintainers and contributors who need to understand the implementation details, memory model, and data structures.

## 1. Build and Development Environment

The compiler is built using the standard Zig build system.

**Commands:**
*   `zig build`: Compiles the compiler (`fbc`) to `zig-out/bin/`.
*   `zig build run -- [args]`: Runs the compiler directly.
*   `zig build test`: Runs specific unit tests (currently sparse, mostly integration tests via the test runner).

**Project Structure:**
The source is contained entirely within `zig_compiler/src/`. Key files:
*   `main.zig`: CLI driver and pipeline orchestration.
*   `token.zig`: Token definitions and source location logic.
*   `lexer.zig`: Tokenizer implementation.
*   `ast.zig`: Abstract Syntax Tree type definitions (tagged unions).
*   `parser.zig`: Recursive descent parser.
*   `semantic.zig`: Type checking and symbol table construction.
*   `cfg.zig`: Control Flow Graph implementation.
*   `codegen.zig`: QBE Intermediate Language emitter.
*   `qbe.zig`: Wrapper for invoking the QBE backend.

## 2. Memory Management Model

The FasterBASIC Zig compiler uses **Arena Allocation** heavily to simplify memory management and improve performance.

*   **AST & Parser**: The `parser.Parser` struct owns an `ast.Builder`. The builder wraps an `ArenaAllocator`. AST nodes (`Expression`, `Statement`) are allocated in this arena. They are never freed individually; the entire arena is dropped when the `Parser` (or the compiler phase) finishes.
*   **Symbol Table**: The `SemanticAnalyzer` also uses an arena for symbol data (strings, type descriptors). HashMaps store pointers to this arena-owned data.
*   **Temporary Allocations**: For string builders or temporary lists during parsing, the `allocator` passed to `init` is used.

**Maintainer Note:** When adding new nodes or persistent data structures, always prefer the arena allocator if the data lives for the duration of the compilation. Use the general-purpose allocator only for resizeable containers (ArrayLists, HashMaps) where the *container structure* needs to grow, but the *stored elements* should be arena-allocated if possible.

## 3. Data Structures

### 3.1 Abstract Syntax Tree (AST)

Unlike the C++ implementation which uses a class hierarchy with virtual methods, the Zig implementation uses **Tagged Unions**.

**Why?**
*   **Data Locality**: Nodes are POD (Plain Old Data) structs.
*   **No Vtable Overhead**: `switch` statements are faster than virtual calls.
*   **Explicitness**: The shape of the tree is defined entirely in `ast.zig`.

**Structure:**
*   `Statement`: A struct containing a `SourceLocation` and a `StmtData` union.
*   `Expression`: A struct containing a `SourceLocation` and an `ExprData` union.
*   `ExprPtr` / `StmtPtr`: Pointers to heap-allocated nodes.

**Example (Adding a Node):**
1.  Add the tag to the `StmtData` or `ExprData` enum in `ast.zig`.
2.  Define the payload struct (e.g., `pub const MyNewNode = struct { ... };`).
3.  Update the `switch` statements in `semantic.zig` (analysis) and `cfg.zig` (lowering).

### 3.2 Control Flow Graph (CFG)

The CFG is the intermediate representation between the AST and Code Generation. It resolves all control flow, meaning the backend doesn't need to know what a `FOR` loop or `IF` statement is—it only sees Blocks and Edges.

*   **BasicBlock**: Contains a list of standard statements (assignment, call, etc.) that execute linearly. It has no control flow *inside* it (except the terminator at the end).
*   **Edge**: Defines connections between blocks. Edges are typed: `branch_true`, `branch_false`, `jump`, `fallthrough`.

**Resolution Strategy (Unstructured Flow):**
Labels and `GOTO` targets are resolved in a two-pass approach within `cfg.zig`.
1.  **Pass 1**: Build blocks, record `LabelStmt` positions.
2.  **Pass 2**: Fix up `jump` edges to point to the correct block index based on the label map.

## 4. Compilation Phases Deep Dive

### Phase 1: Lexing (`lexer.zig`)
The lexer produces a slice of `Token`s upfront. This simplifies the parser, allowing arbitrary lookahead (though `peek(0)` and `peek(1)` are usually sufficient).
*   **Note**: The lexer is currently byte-based. Unicode support requires updating the character classification logic here.

### Phase 2: Parsing (`parser.zig`)
*   **Pratt Parsing**: Expressions are parsed using "Precedence Climbing". The `parseExpression(precedence)` function handles operator precedence automatically.
*   **Error Handling**: The parser returns `!Node`. However, it also accumulates "soft" errors in an `ArrayList` for recovery. If a hard error (like memory failure) occurs, it returns an error code.

### Phase 3: Semantic Analysis (`semantic.zig`)
*   **Symbol Table**: A `StringHashMap` mapping identifiers to `Symbol` variants (`var`, `func`, `const`, etc.).
*   **Type Resolution**: The `BaseType` enum (and associated data) tracks types. Implicit casting (e.g., `integer` to `double`) is handled here by injecting `CastExpr` nodes into the AST explicitly, or marking the conversion for the codegen.

### Phase 4: CFG Construction (`cfg.zig`)
This phase "lowers" high-level constructs.
*   *Example*: An `IF cond THEN true_block ELSE false_block` becomes:
    *   Block A: Evaluate `cond`. Terminator: `branch_true` to B, `branch_false` to C.
    *   Block B: `true_block` statements. Terminator: `jump` to D.
    *   Block C: `false_block` statements. Terminator: `jump` to D.
    *   Block D: Merge point.

### Phase 5: Code Generation (`codegen.zig`)
The generator iterates over the CFG blocks in **Reverse Post-Order (RPO)**. This ensures that (for acyclic graphs) definitions are visited before uses, though QBE handles SSA construction so strictly strict ordering isn't required for correctness, but RPO is good practice.

*   **QBE Interface**: The logic is string-based. It constructs QBE IL strings (e.g., `%v1 =w add %a, %b`) and emits them to the output buffer.
*   **Architecture Agnostic**: QBE handles the register allocation and instruction selection for x64/arm64. The Zig frontend only cares about QBE types (`w`, `l`, `d`, etc.).

## 5. Debugging the Compiler

Use the trace flags to inspect the internal state at each pipeline stage:

*   `--trace-ast`: Dumps a textual representation of the AST after parsing. Use this to verify the parser handles syntax correctly.
*   `--trace-symbols`: Dumps the symbol table after semantic analysis. Use this to check variable scoping and type resolution.
*   `--trace-cfg`: Dumps the Basic Blocks and Edges. Critical for debugging flow control issues (infinite loops, unreachable code).
*   `--show-il`: Prints the generated QBE IL. Use this to verify the output before it hits the backend.

## 6. Guide: Adding a New Feature

To add a new language feature (e.g., a `REPEAT...UNTIL` loop):

1.  **Token**: Add `REPEAT` and `UNTIL` to `token.zig`.
2.  **Lexer**: Ensure `lexer.zig` recognizes these keywords.
3.  **AST**: Add `RepeatLoop` to `StmtData` in `ast.zig`.
4.  **Parser**: Add a case in `parseStatement` in `parser.zig` to consume tokens and build the node.
5.  **Semantic**: Add logic in `semantic.zig` to validate the loop condition (must be boolean/numeric).
6.  **CFG**: In `cfg.zig`, implement the lowering logic:
    *   Create a "body" block and a "condition" block.
    *   Edge from body end -> condition.
    *   Edge from condition (false) -> body entry (since it's `UNTIL`).
    *   Edge from condition (true) -> exit.
7.  **Codegen**: Usually no changes needed if the CFG logic handles the connections correctly!

