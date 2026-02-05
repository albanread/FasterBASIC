compact_repo/selfhosting-prereqs.md
```

# Prerequisites for Self-Hosting FasterBASIC

## Purpose

This document outlines the essential language features and runtime capabilities required to write the FasterBASIC compiler in FasterBASIC itself (self-hosting). Each feature is prioritized and explained in the context of compiler construction and bootstrapping.

---

## 1. Strings and String Manipulation

**Why:**  
Lexers, parsers, and code generators all require robust string handling. Efficient, flexible strings (with slicing, concatenation, search, replace, and Unicode support) are foundational.

**Recommended additions:**
- String slicing and substring functions
- String concatenation and interpolation
- Pattern matching and regular expressions

---

## 2. Dynamic Arrays and Collections

**Why:**  
Compilers need to build and traverse lists of tokens, AST nodes, and intermediate representations. Dynamic arrays (resizable, multi-dimensional) are essential.

**Recommended additions:**
- Dynamic arrays (with push/pop/resize)
- Multi-dimensional arrays
- Array slicing and iteration

---

## 3. Hash Maps / Dictionaries

**Why:**  
Symbol tables, token maps, and environment tables are best represented as hash maps. This is the single most important data structure for a compiler.

**Recommended additions:**
- Built-in hash map/dictionary type
- String and integer keys
- Iteration over keys/values

---

## 4. User-Defined Types / Structs / Records

**Why:**  
AST nodes, tokens, and symbol table entries are naturally modeled as records with named fields.

**Recommended additions:**
- Struct/record syntax with named fields
- Support for nested and recursive types

---

## 5. Modularization and Namespaces

**Why:**  
A large compiler must be split into manageable modules (lexer, parser, codegen, etc.). Namespaces prevent symbol collisions and improve maintainability.

**Recommended additions:**
- Module or namespace system
- Import/include mechanism

---

## 6. First-Class Functions and Lambdas

**Why:**  
Visitors, callbacks, and flexible traversals are much easier with first-class functions. Lambdas enable concise, inline function definitions.

**Recommended additions:**
- Passing functions as arguments
- Assigning functions to variables
- Anonymous functions/lambdas

---

## 7. Structured Error Handling

**Why:**  
Compilers must report errors gracefully and recover where possible. Structured error handling (try/catch, exceptions, or error codes) is critical for robustness.

**Recommended additions:**
- TRY/CATCH or equivalent
- Custom error types
- Stack traces or error context

---

## 8. File and I/O Support

**Why:**  
Reading source files, writing output (QBE), and handling directories are core compiler tasks.

**Recommended additions:**
- File read/write (text and binary)
- Directory listing
- Command-line argument parsing

---

## 9. Memory Management

**Why:**  
Efficient handling of ASTs, symbol tables, and other dynamic structures requires safe memory management.

**Recommended additions:**
- Garbage collection or safe manual allocation/free
- Dynamic object/array allocation

---

## 10. QBE Code Generation Support

**Why:**  
The compiler must emit QBE IL. Helpers or DSLs for QBE output reduce errors and improve maintainability.

**Recommended additions:**
- String-based QBE emission
- Optionally, QBE codegen helpers or DSL

---

## 11. Testing and Debugging Support

**Why:**  
A self-hosted compiler must be reliable. Unit testing and debugging facilities are essential for development and maintenance.

**Recommended additions:**
- Unit testing framework
- Assertions
- Debug print/logging

---

## 12. Optional Advanced Features

- **Reflection/meta-programming:** For advanced code generation or bootstrapping.
- **Pattern matching:** For AST transformations.
- **Coroutines/generators:** For lexers or traversals.
- **FFI (Foreign Function Interface):** To call C/QBE helpers if needed.

---

## Prioritization Roadmap

1. **Hash maps/dictionaries**
2. **Dynamic arrays and user-defined types**
3. **String manipulation and regular expressions**
4. **Modules/namespaces**
5. **First-class functions/lambdas**
6. **Structured error handling**
7. **File I/O and command-line support**
8. **Testing and debugging**
9. **Memory management improvements**
10. **QBE codegen helpers**
11. **Optional advanced features**

---

## Summary Table

| Feature                        | Why Needed for Compiler?                |
|---------------------------------|----------------------------------------|
| Strings & regex                 | Lexing, parsing, codegen               |
| Arrays, maps, structs           | AST, symbol tables, tokens             |
| Modules/namespaces              | Maintainable, multi-file compiler      |
| First-class functions/lambdas   | Visitors, callbacks, flexible parsing  |
| Error handling                  | Robust compiler, clear diagnostics     |
| File I/O                        | Read/write source, output QBE          |
| Memory management               | Efficient AST, symbol table handling   |
| Reflection/macros (optional)    | Advanced codegen, bootstrapping        |
| QBE output helpers              | Emit correct, efficient QBE            |
| Testing/debugging               | Reliable, maintainable development     |

---

## Next Steps

Add these features one at a time, starting with hash maps/dictionaries and dynamic arrays. Each addition should be accompanied by tests and example usage relevant to compiler construction. As features are added, incrementally port parts of the existing compiler to FasterBASIC to validate the design.
