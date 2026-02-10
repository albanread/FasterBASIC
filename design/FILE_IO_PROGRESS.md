# File I/O and Process Execution Implementation Progress

## Date: 2024
**Status**: In Progress - Lexer Issue with # Token

## Summary

We have been implementing file I/O and process execution commands for FasterBASIC to enable the BASED editor to save/load files and compile/run programs from within the editor.

## Completed Work

### 1. Runtime Functions (io_ops.zig) ✅

Added the following runtime functions:

```zig
// File handle management by number
export fn file_get_handle(file_number: i32) ?*BasicFile
export fn file_set_handle(file_number: i32, file: ?*BasicFile)

// File output
export fn file_print_double(file: ?*BasicFile, value: f64)

// Process execution
export fn basic_system(command: ?*anyopaque) -> i32
export fn basic_shell(command: ?*anyopaque)
```

These work alongside existing runtime functions:
- `file_open(filename, mode) -> *BasicFile`
- `file_close(file)`
- `file_print_string(file, str)`
- `file_print_int(file, value)`
- `file_print_newline(file)`
- `file_read_line(file) -> string`
- `file_eof(file) -> bool`

### 2. Keywords Added ✅

Added to token.zig:
- `kw_shell` - SHELL command
- `kw_system` - SYSTEM command (alias for SHELL)

Existing keywords work:
- `kw_open`, `kw_close`, `kw_input`, `kw_line`, `kw_for`, `kw_as`

### 3. AST Nodes Updated ✅

Updated AST structures to use expressions instead of literals:

```zig
pub const OpenStmt = struct {
    filename: ExprPtr,        // Was: []const u8
    mode: []const u8,
    file_number: ExprPtr,     // Was: i32
    record_length: i32 = 0,
};

pub const CloseStmt = struct {
    file_number: ?ExprPtr,    // Was: i32
    close_all: bool,
};

pub const PrintStmt = struct {
    file_number: ?ExprPtr,    // Was: i32 (null = console)
    items: []PrintItem,
    trailing_newline: bool,
    // ... other fields
};

pub const InputStmt = struct {
    prompt: []const u8,
    variables: []const []const u8,
    file_number: ?ExprPtr,    // Was: i32 (null = console)
    is_line_input: bool,
};

pub const ShellStmt = struct {
    command: ExprPtr,
};
```

### 4. Parser Implementation ✅

Implemented full parsers for:

**parseOpenStatement()**: 
- Syntax: `OPEN filename$ FOR INPUT/OUTPUT/APPEND AS [#]n`
- Parses filename expression
- Recognizes INPUT, OUTPUT, APPEND modes
- Parses file number expression
- Hash (#) is optional before file number

**parseCloseStatement()**:
- Syntax: `CLOSE [#]n` or `CLOSE` (all files)
- Handles optional # before file number
- Supports close-all with no arguments

**parsePrintStatement()**: Updated to handle file output
- Syntax: `PRINT [#]n, expr1, expr2, ...`
- Detects # or file number expression after PRINT
- Separates file output from console output logic

**parseInputStatement()**: Updated to handle file input
- Syntax: `INPUT [#]n, var1, var2` or `LINE INPUT [#]n, var$`
- Handles LINE INPUT variant
- Detects # or file number expression
- Supports both file and console input

**parseShellStatement()**:
- Syntax: `SHELL command$` or `SYSTEM command$`
- Parses command expression

### 5. Code Generation ✅

Implemented emitters in codegen.zig:

**emitOpenStatement()**:
- Evaluates filename and file number expressions
- Creates mode string literal
- Calls `file_open(filename, mode)`
- Stores handle with `file_set_handle(file_number, handle)`

**emitCloseStatement()**:
- Gets file handle with `file_get_handle(file_number)`
- Calls `file_close(handle)`
- Clears handle with `file_set_handle(file_number, 0)`

**emitPrintStatement()**: Updated
- Checks for file_number expression
- If present, uses `file_print_*` functions
- Otherwise uses console `basic_print_*` functions
- Handles strings, integers, doubles

**emitInputStatement()**:
- Gets file handle for file input
- Calls `file_read_line(handle)`
- Stores result in variable
- TODO: Console input handling

**emitShellStatement()**:
- Evaluates command expression
- Calls `basic_shell(command)`

### 6. Build System ✅

- Runtime compiles successfully
- Compiler (fbc) builds successfully

## Current Issue: Lexer Handling of # Token ⚠️

### Problem

The `#` character has dual meaning in BASIC:
1. **Type suffix**: `x#` means x is a DOUBLE variable
2. **File number indicator**: `PRINT #1, "hello"` means print to file 1

### Current Behavior

The lexer's `scanOperator()` was lexing `#` as `.type_double` always. We attempted to make it context-aware:

```zig
'#' => {
    // Check if previous token was identifier/keyword
    const is_suffix = if (self.tokens.items.len > 0) blk: {
        const prev = self.tokens.items[self.tokens.items.len - 1];
        break :blk prev.tag == .identifier or prev.isKeyword();
    } else false;

    if (is_suffix) {
        try self.addToken(.type_double, ...);
    } else {
        try self.addToken(.hash, ...);
    }
},
```

### The Problem with This Approach

This doesn't work because:
1. `scanToken()` calls `skipWhitespace()` BEFORE scanning each token
2. By the time we see `#`, whitespace is already consumed
3. We can't tell if there was whitespace between `PRINT` and `#`

In `PRINT #1`, there IS whitespace, so `#` should be `.hash`.
In `x#`, there is NO whitespace, so `#` should be `.type_double`.

But after `skipWhitespace()`, we can't distinguish these cases.

### Solution Options

**Option 1: Track whitespace** (Recommended)
Add a field to Lexer:
```zig
pub const Lexer = struct {
    // ... existing fields
    had_whitespace_before: bool,
};
```

Update `scanToken()`:
```zig
fn scanToken(self: *Lexer) !void {
    const had_ws = self.pos > 0 and isWhitespace(self.source[self.pos - 1]);
    self.skipWhitespace();
    self.had_whitespace_before = had_ws or self.pos > 0;
    // ... rest of scanning
}
```

Use in # handling:
```zig
'#' => {
    if (self.had_whitespace_before) {
        try self.addToken(.hash, ...);
    } else {
        // Check if after identifier
        const after_id = self.tokens.items.len > 0 and 
                        self.tokens.items[self.tokens.items.len - 1].tag == .identifier;
        if (after_id) {
            try self.addToken(.type_double, ...);
        } else {
            try self.addToken(.hash, ...);
        }
    }
},
```

**Option 2: Special case in identifier scanning**
When scanning identifiers, check for `#` suffix and emit both tokens. For standalone `#`, always emit `.hash`.

**Option 3: Parser workaround**
Make `#` always lex as `.type_double`, and have the parser treat it as `.hash` in file I/O contexts. This is less clean but simpler.

## Test Case

Created `tests/test_file_io_simple.bas`:
```basic
DIM filename$ AS STRING
filename$ = "test_output.txt"

PRINT "Writing to file..."
OPEN filename$ FOR OUTPUT AS #1
PRINT #1, "Hello from FasterBASIC!"
PRINT #1, "Line 2"
CLOSE #1

PRINT "Reading from file..."
OPEN filename$ FOR INPUT AS #1
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    PRINT line$
LOOP
CLOSE #1
```

Current parse errors on lines with `#` because lexer produces wrong token type.

## Next Steps

1. **Fix Lexer** - Implement Option 1 (track whitespace) or Option 2
2. **Test File I/O** - Compile and run test_file_io_simple.bas
3. **Test SHELL** - Create test that uses SHELL/SYSTEM command
4. **Update BASED** - Update based.bas to use working file I/O
5. **Test BASED** - Compile and test the editor
6. **Documentation** - Update user docs with file I/O and SHELL syntax

## Files Modified

- `zig_compiler/runtime/io_ops.zig` - Added file handle management and shell functions
- `zig_compiler/src/token.zig` - Added kw_shell, kw_system
- `zig_compiler/src/ast.zig` - Updated OpenStmt, CloseStmt, PrintStmt, InputStmt, added ShellStmt
- `zig_compiler/src/parser.zig` - Implemented/updated parseOpen, parseClose, parsePrint, parseInput, parseShell
- `zig_compiler/src/codegen.zig` - Implemented emit functions for all new statements
- `zig_compiler/src/lexer.zig` - Attempted # token disambiguation (incomplete)

## Reference Documents

- `design/FILE_IO_IMPLEMENTATION.md` - Full design specification
- `based/DESIGN.md` - BASED editor design
- `based/based.bas` - Full editor implementation (needs file I/O to work)
- `based/based_simple.bas` - Simplified editor without file I/O

---

**Status**: Paused at lexer # token issue
**Next Action**: Implement whitespace tracking in lexer to properly distinguish # contexts