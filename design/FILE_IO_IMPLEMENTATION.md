# File I/O and Process Execution Implementation

## Overview

This document describes the implementation of file I/O operations and process execution for FasterBASIC, required for the BASED editor to save/load files and compile/run programs.

## File I/O Operations

### Syntax Support

#### OPEN Statement
```basic
OPEN "filename" FOR INPUT AS #1
OPEN "filename" FOR OUTPUT AS #2
OPEN "filename" FOR APPEND AS #3
OPEN filename$ FOR INPUT AS file_num
```

#### CLOSE Statement
```basic
CLOSE #1
CLOSE file_num
CLOSE          ' Close all open files
```

#### PRINT # Statement
```basic
PRINT #1, "Hello World"
PRINT #file_num, x; y; z
PRINT #1, value
```

#### LINE INPUT # Statement
```basic
LINE INPUT #1, line$
LINE INPUT #file_num, buffer$
```

#### INPUT # Statement
```basic
INPUT #1, x, y, z
INPUT #file_num, name$, age
```

#### EOF Function
```basic
IF EOF(1) THEN ...
WHILE NOT EOF(file_num)
```

### Runtime Functions (Already Exist in io_ops.zig)

✓ `file_open(filename, mode) -> *BasicFile`
✓ `file_close(file)`
✓ `file_print_string(file, str)`
✓ `file_print_int(file, value)`
✓ `file_print_newline(file)`
✓ `file_read_line(file) -> string`
✓ `file_eof(file) -> bool`

### Additional Runtime Functions Needed

```zig
// File handle management by number
export fn file_get_handle(file_number: i32) ?*BasicFile
export fn file_set_handle(file_number: i32, file: ?*BasicFile)

// Input parsing
export fn file_input_string(file: ?*BasicFile) ?*anyopaque
export fn file_input_int(file: ?*BasicFile) i32
export fn file_input_double(file: ?*BasicFile) f64
```

### AST Nodes

#### OpenStmt
```zig
pub const OpenStmt = struct {
    filename: ExprPtr,           // Expression for filename
    mode: []const u8,            // "INPUT", "OUTPUT", "APPEND"
    file_number: ExprPtr,        // Expression for file number
};
```

#### CloseStmt (Already Exists)
```zig
pub const CloseStmt = struct {
    file_number: i32,
    close_all: bool,
};
```

#### PrintFileStmt
```zig
pub const PrintFileStmt = struct {
    file_number: ExprPtr,        // Expression for file number
    values: []ExprPtr,           // Values to print
    newline: bool,               // Add newline at end
};
```

#### LineInputFileStmt
```zig
pub const LineInputFileStmt = struct {
    file_number: ExprPtr,        // Expression for file number
    variable: []const u8,        // Variable name to store result
};
```

#### InputFileStmt
```zig
pub const InputFileStmt = struct {
    file_number: ExprPtr,        // Expression for file number
    variables: [][]const u8,     // Variable names
};
```

### Parser Implementation

#### Parse OPEN Statement
```zig
fn parseOpenStatement(self: *Parser) ExprError!ast.StmtPtr {
    const loc = self.currentLocation();
    _ = self.advance(); // consume OPEN

    // Parse filename expression
    const filename = try self.parseExpression();

    // Expect FOR keyword
    _ = try self.consume(.kw_for, "Expected FOR after filename");

    // Parse mode (INPUT, OUTPUT, APPEND)
    var mode: []const u8 = undefined;
    if (self.check(.kw_input)) {
        mode = "INPUT";
        _ = self.advance();
    } else if (self.check(.identifier)) {
        const id = self.current().lexeme;
        if (std.mem.eql(u8, id, "OUTPUT")) {
            mode = "OUTPUT";
            _ = self.advance();
        } else if (std.mem.eql(u8, id, "APPEND")) {
            mode = "APPEND";
            _ = self.advance();
        } else {
            try self.addError("Expected INPUT, OUTPUT, or APPEND");
            return error.ParseError;
        }
    } else {
        try self.addError("Expected file mode");
        return error.ParseError;
    }

    // Expect AS keyword
    _ = try self.consume(.kw_as, "Expected AS");

    // Expect # token
    _ = try self.consume(.hash, "Expected # before file number");

    // Parse file number expression
    const file_number = try self.parseExpression();

    return self.builder.stmt(loc, .{ 
        .open = .{
            .filename = filename,
            .mode = mode,
            .file_number = file_number,
        }
    });
}
```

#### Parse PRINT # Statement
```zig
fn parsePrintStatement(self: *Parser) ExprError!ast.StmtPtr {
    const loc = self.currentLocation();
    _ = self.advance(); // consume PRINT

    // Check for file output: PRINT #n, ...
    if (self.check(.hash)) {
        _ = self.advance();
        const file_number = try self.parseExpression();
        _ = try self.consume(.comma, "Expected comma after file number");

        var values = std.ArrayList(ast.ExprPtr).init(self.allocator);
        defer values.deinit();

        var newline = true;
        while (!self.check(.end_of_line) and !self.isAtEnd()) {
            try values.append(try self.parseExpression());
            
            if (self.check(.semicolon)) {
                _ = self.advance();
                newline = false;
            } else if (self.check(.comma)) {
                _ = self.advance();
                newline = true;
            } else {
                break;
            }
        }

        const values_slice = try values.toOwnedSlice();
        return self.builder.stmt(loc, .{
            .print_file = .{
                .file_number = file_number,
                .values = values_slice,
                .newline = newline,
            }
        });
    }

    // Regular PRINT to console (existing code)
    ...
}
```

#### Parse LINE INPUT # Statement
```zig
fn parseLineInputStatement(self: *Parser) ExprError!ast.StmtPtr {
    // Handle LINE INPUT #n, var$
    if (self.check(.hash)) {
        _ = self.advance();
        const file_number = try self.parseExpression();
        _ = try self.consume(.comma, "Expected comma");
        
        if (!self.check(.identifier)) {
            try self.addError("Expected variable name");
            return error.ParseError;
        }
        const var_name = self.current().lexeme;
        _ = self.advance();

        return self.builder.stmt(loc, .{
            .line_input_file = .{
                .file_number = file_number,
                .variable = var_name,
            }
        });
    }

    // Regular LINE INPUT (existing code)
    ...
}
```

### Code Generation

#### Generate OPEN Statement
```zig
fn generateOpen(self: *Codegen, stmt: ast.OpenStmt) !void {
    // Evaluate filename expression
    const filename_result = try self.generateExpr(stmt.filename);
    
    // Evaluate file number expression
    const file_number_result = try self.generateExpr(stmt.file_number);
    
    // Create mode string
    const mode_str = try self.createStringLiteral(stmt.mode);
    
    // Call runtime: file_open(filename, mode)
    const file_handle = try self.nextTemp();
    try self.emit("    {s} =l call $file_open(l {s}, l {s})", .{
        file_handle, filename_result, mode_str
    });
    
    // Store in file handle table: file_set_handle(file_number, handle)
    try self.emit("    call $file_set_handle(w {s}, l {s})", .{
        file_number_result, file_handle
    });
}
```

#### Generate PRINT # Statement
```zig
fn generatePrintFile(self: *Codegen, stmt: ast.PrintFileStmt) !void {
    // Get file number
    const file_num_result = try self.generateExpr(stmt.file_number);
    
    // Get file handle
    const file_handle = try self.nextTemp();
    try self.emit("    {s} =l call $file_get_handle(w {s})", .{
        file_handle, file_num_result
    });
    
    // Print each value
    for (stmt.values) |value_expr| {
        const value_result = try self.generateExpr(value_expr);
        const value_type = try self.getExprType(value_expr);
        
        if (value_type.isString()) {
            try self.emit("    call $file_print_string(l {s}, l {s})", .{
                file_handle, value_result
            });
        } else if (value_type.isInteger()) {
            try self.emit("    call $file_print_int(l {s}, w {s})", .{
                file_handle, value_result
            });
        } else if (value_type.isDouble()) {
            try self.emit("    call $file_print_double(l {s}, d {s})", .{
                file_handle, value_result
            });
        }
    }
    
    // Print newline if requested
    if (stmt.newline) {
        try self.emit("    call $file_print_newline(l {s})", .{file_handle});
    }
}
```

#### Generate LINE INPUT # Statement
```zig
fn generateLineInputFile(self: *Codegen, stmt: ast.LineInputFileStmt) !void {
    // Get file number
    const file_num_result = try self.generateExpr(stmt.file_number);
    
    // Get file handle
    const file_handle = try self.nextTemp();
    try self.emit("    {s} =l call $file_get_handle(w {s})", .{
        file_handle, file_num_result
    });
    
    // Read line
    const line_result = try self.nextTemp();
    try self.emit("    {s} =l call $file_read_line(l {s})", .{
        line_result, file_handle
    });
    
    // Store in variable
    try self.generateVariableStore(stmt.variable, line_result, .string);
}
```

## Process Execution

### Syntax Support

#### SHELL / SYSTEM Statement
```basic
SHELL "ls -la"
SYSTEM "gcc program.c"
SHELL command$
```

#### EXEC Function (returns exit code)
```basic
result = EXEC("make")
exitcode = EXEC(command$)
```

### Runtime Functions Needed

```zig
// Execute command and return exit code
export fn basic_system(command: ?*anyopaque) callconv(.C) i32 {
    const cmd_str = string_to_utf8(command) orelse return -1;
    
    // Use std.process.Child or C system()
    const result = std.c.system(cmd_str);
    return @intCast(result);
}

// Execute command and wait (no return value)
export fn basic_shell(command: ?*anyopaque) callconv(.C) void {
    _ = basic_system(command);
}
```

### AST Nodes

```zig
pub const ShellStmt = struct {
    command: ExprPtr,  // Command expression
};

// EXEC as function expression (already handled by function call)
```

### Parser Implementation

```zig
fn parseShellStatement(self: *Parser) ExprError!ast.StmtPtr {
    const loc = self.currentLocation();
    _ = self.advance(); // consume SHELL or SYSTEM

    const command = try self.parseExpression();

    return self.builder.stmt(loc, .{
        .shell = .{ .command = command }
    });
}
```

### Code Generation

```zig
fn generateShell(self: *Codegen, stmt: ast.ShellStmt) !void {
    const cmd_result = try self.generateExpr(stmt.command);
    try self.emit("    call $basic_shell(l {s})", .{cmd_result});
}
```

## Implementation Plan

### Phase 1: File Handle Management
1. Add global file handle table in runtime
2. Implement `file_get_handle` and `file_set_handle`
3. Add `file_print_double` runtime function

### Phase 2: Parser Support
1. Update `parseOpenStatement` with full implementation
2. Update `parsePrintStatement` to handle PRINT #
3. Add `parseLineInputStatement` file variant
4. Add keywords for SHELL/SYSTEM if not present

### Phase 3: AST Updates
1. Add new AST node types (OpenStmt, PrintFileStmt, etc.)
2. Update AST visitor/display functions

### Phase 4: Code Generation
1. Implement codegen for OPEN
2. Implement codegen for PRINT #
3. Implement codegen for LINE INPUT #
4. Implement codegen for CLOSE
5. Implement codegen for SHELL

### Phase 5: Testing
1. Create test programs for file I/O
2. Create test programs for SHELL
3. Test with BASED editor

## Example Usage in BASED

```basic
REM Save file
DIM file_num AS INTEGER
file_num = 1

OPEN filename$ FOR OUTPUT AS #file_num

DIM i AS INTEGER
FOR i = 0 TO line_count - 1
    PRINT #file_num, lines$(i)
NEXT i

CLOSE #file_num

REM Load file
OPEN filename$ FOR INPUT AS #file_num

line_count = 0
DO WHILE NOT EOF(file_num)
    LINE INPUT #file_num, lines$(line_count)
    line_count = line_count + 1
LOOP

CLOSE #file_num

REM Compile and run
SHELL "fbc program.bas -o program"
exitcode = EXEC("./program")
```

## Notes

- File numbers are typically 1-255 in classic BASIC
- File handle table can be a simple array indexed by file number
- Need proper error handling for file operations
- SHELL should flush stdout before executing
- Consider security implications of SHELL command

---

**Status**: Design Complete - Ready for Implementation
**Version**: 1.0
**Date**: 2024