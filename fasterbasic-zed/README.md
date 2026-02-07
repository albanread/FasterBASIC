# FasterBASIC for Zed

A [Zed](https://zed.dev) extension providing syntax highlighting, code navigation, auto-indentation, and bracket matching for the **FasterBASIC** programming language.

## Features

- **Syntax Highlighting** — Full Tree-sitter grammar-based highlighting for all FasterBASIC constructs:
  - Keywords, control flow, operators, literals
  - CLASS declarations with inheritance, constructors, destructors, methods, and fields
  - SUB / FUNCTION / DEF FN declarations
  - TYPE (UDT) declarations
  - LIST OF / HASHMAP types
  - MATCH TYPE pattern matching with class-specific CASE arms
  - FOR EACH iteration
  - TRY / CATCH / FINALLY exception handling
  - OPTION compiler directives
  - Graphics, sprite, timer, and audio statements
  - Type suffixes (`%`, `&`, `!`, `#`, `$`, `@`, `^`)

- **Code Outline** — Navigate your code via the symbols panel with entries for:
  - Classes, methods, constructors, destructors, fields
  - Subroutines and functions
  - TYPE declarations and fields
  - Labels and constants

- **Auto-Indentation** — Smart indent/outdent for block structures:
  - IF/ELSEIF/ELSE/ENDIF
  - FOR/NEXT, WHILE/WEND, REPEAT/UNTIL, DO/LOOP
  - SUB/END SUB, FUNCTION/END FUNCTION
  - CLASS/END CLASS, METHOD/END METHOD, CONSTRUCTOR/END CONSTRUCTOR
  - SELECT CASE/CASE/OTHERWISE/ENDCASE
  - MATCH TYPE/CASE/END MATCH
  - TRY/CATCH/FINALLY/END TRY

- **Bracket Matching** — Highlights matching pairs for:
  - Parentheses `()`  and brackets `[]`
  - All block keyword pairs (IF↔ENDIF, FOR↔NEXT, CLASS↔END CLASS, etc.)

## Installation

### From Zed Extensions (coming soon)

1. Open Zed
2. Open the Extensions panel (`Cmd+Shift+X` on macOS)
3. Search for "FasterBASIC"
4. Click **Install**

### Manual Installation (Development)

1. Clone this repository or copy the `fasterbasic-zed/` directory
2. In Zed, open **Settings** → **Extensions** → **Install Dev Extension**
3. Select the `fasterbasic-zed/` directory
4. Zed will build the Tree-sitter grammar and load the extension

## File Associations

The extension recognises the following file extensions:

| Extension | Description |
|-----------|-------------|
| `.bas`    | FasterBASIC source file |
| `.bi`     | FasterBASIC include file (declarations) |
| `.bm`     | FasterBASIC include file (module) |

## Project Structure

```
fasterbasic-zed/
├── extension.toml                        # Zed extension manifest
├── grammars/
│   └── fasterbasic/
│       ├── grammar.js                    # Tree-sitter grammar definition
│       └── package.json                  # Tree-sitter build configuration
├── languages/
│   └── fasterbasic/
│       ├── config.toml                   # Language configuration
│       ├── highlights.scm                # Syntax highlighting queries
│       ├── outline.scm                   # Code outline / symbols queries
│       ├── indents.scm                   # Auto-indentation queries
│       └── brackets.scm                  # Bracket matching queries
└── README.md
```

## Grammar Coverage

The Tree-sitter grammar covers the full FasterBASIC language including:

| Category | Constructs |
|----------|-----------|
| **Declarations** | DIM, REDIM, ERASE, LOCAL, GLOBAL, SHARED, CONSTANT, LET |
| **Control Flow** | IF/THEN/ELSE/ELSEIF/ENDIF, SELECT CASE, GOTO, GOSUB, ON...GOTO |
| **Loops** | FOR/NEXT, FOR EACH/IN, WHILE/WEND, REPEAT/UNTIL, DO/LOOP, EXIT, CONTINUE |
| **Procedures** | SUB, FUNCTION, DEF FN, CALL, RETURN |
| **OOP** | CLASS, EXTENDS, CONSTRUCTOR, DESTRUCTOR, METHOD, NEW, ME, SUPER |
| **Types** | TYPE/END TYPE, all primitives, LIST OF, HASHMAP, type suffixes |
| **Pattern Matching** | MATCH TYPE, CASE with type/class names, CASE ELSE |
| **Error Handling** | TRY, CATCH, FINALLY, THROW |
| **I/O** | PRINT, CONSOLE, INPUT, LINE INPUT, OPEN, CLOSE |
| **Data** | DATA, READ, RESTORE |
| **Graphics** | CLS, GCLS, COLOR, PSET, LINE, RECT, CIRCLE, HLINE, VLINE |
| **Text** | AT, LOCATE, TEXTPUT, TEXT_PUT, TCHAR |
| **Sprites** | SPRLOAD, SPRSHOW, SPRHIDE, SPRMOVE, SPRPOS, SPRSCALE, SPRROT, etc. |
| **Timer/Events** | AFTER, EVERY, AFTERFRAMES, EVERYFRAME, TIMER STOP, RUN, VSYNC, WAIT |
| **Audio** | PLAY, PLAY_SOUND |
| **Expressions** | Full operator precedence, IIF(), member access, array subscripts, string slicing |
| **Compiler** | OPTION SAMM/EXPLICIT/UNICODE/BASE/BITWISE/INCLUDE/etc. |

## Comparison: VS Code vs Zed Extension

| Feature | VS Code (TextMate) | Zed (Tree-sitter) |
|---------|--------------------|--------------------|
| Highlighting engine | Regex-based | Grammar-based (proper parser) |
| Accuracy | Good for flat constructs | Excellent — understands nesting and structure |
| Code outline | Limited | Full symbol navigation |
| Bracket matching | Punctuation only | Keyword pairs (IF↔ENDIF, etc.) |
| Auto-indent | Regex heuristics | Structure-aware |
| Performance | Fast | Fast (incremental parsing) |

The Zed extension provides significantly better structural understanding of your code compared to the TextMate grammar used by the VS Code extension, because Tree-sitter builds an actual parse tree rather than matching line-by-line with regular expressions.

## Development

To modify the grammar:

1. Edit `grammars/fasterbasic/grammar.js`
2. Install Tree-sitter CLI: `npm install -g tree-sitter-cli`
3. Generate and test: `cd grammars/fasterbasic && tree-sitter generate && tree-sitter parse ../../tests/test_list_basic.bas`
4. Reload the dev extension in Zed

To modify highlighting:

1. Edit `languages/fasterbasic/highlights.scm`
2. Reload the extension in Zed — no rebuild needed for query changes

## Case Insensitivity

FasterBASIC is a case-insensitive language. The Tree-sitter grammar handles this by generating case-insensitive regex patterns for all keywords (e.g., `PRINT`, `Print`, `print` are all valid). This is implemented via the `kw()` helper function in `grammar.js`.

## License

MIT