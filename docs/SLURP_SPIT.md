# SLURP and SPIT - Whole-File I/O Functions

## Overview

`SLURP` and `SPIT` are convenience functions for reading and writing entire files at once. They are much more efficient than `LINE INPUT` for loading complete files into memory, which is ideal for text editors and other applications that need to work with entire file contents.

## SLURP Function

### Syntax
```basic
content$ = SLURP(filename$)
```

### Description
Reads an entire file into a string variable in a single operation.

### Parameters
- `filename$` - The name/path of the file to read

### Return Value
Returns a string containing the entire contents of the file, including all newlines and special characters. If the file cannot be opened or read, returns an empty string and displays an error message.

### Example
```basic
REM Load entire file into memory
content$ = SLURP("myfile.txt")

REM Parse into lines
line_count = 0
line_start = 1
FOR i = 1 TO LEN(content$)
    IF MID$(content$, i, 1) = CHR$(10) THEN
        lines$(line_count) = MID$(content$, line_start, i - line_start)
        line_count = line_count + 1
        line_start = i + 1
    ENDIF
NEXT i
```

## SPIT Statement

### Syntax
```basic
SPIT filename$, content$
```

### Description
Writes an entire string to a file in a single operation, replacing any existing file contents.

### Parameters
- `filename$` - The name/path of the file to write
- `content$` - The string content to write to the file

### Return Value
None (this is a statement, not a function)

### Example
```basic
REM Build content from lines array
content$ = ""
FOR i = 0 TO line_count - 1
    content$ = content$ + lines$(i)
    IF i < line_count - 1 THEN
        content$ = content$ + CHR$(10)
    ENDIF
NEXT i

REM Write entire file at once
SPIT "output.txt", content$
```

## Advantages over LINE INPUT

### Performance
- **SLURP**: Reads the entire file in one system call vs. multiple calls for LINE INPUT
- **SPIT**: Writes the entire file in one system call vs. multiple PRINT # calls

### Simplicity
```basic
REM Old way (LINE INPUT)
OPEN "file.txt" FOR INPUT AS #1
line_count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, lines$(line_count)
    line_count = line_count + 1
LOOP
CLOSE #1

REM New way (SLURP)
content$ = SLURP("file.txt")
REM Then parse as needed
```

### Memory Efficiency
- Both approaches load the file into memory, but SLURP does it more efficiently
- SLURP uses binary mode (`rb`/`wb`) to preserve exact byte content

## Binary Mode

SLURP and SPIT use binary mode internally, which means:
- Exact file contents are preserved
- Works with both text and binary files
- No platform-specific line ending conversion
- `CHR$(10)` = LF (Unix), `CHR$(13)` = CR, `CHR$(13)+CHR$(10)` = CRLF (Windows)

## Error Handling

Both functions handle errors gracefully:

**SLURP**:
- Returns empty string if file cannot be opened
- Returns empty string if file cannot be read
- Returns empty string if out of memory
- Displays error message via `basic_error_msg`

**SPIT**:
- Does nothing if file cannot be opened
- Does nothing if write fails
- Displays error message via `basic_error_msg`

## Implementation Details

### Runtime Functions
Located in `runtime/io_ops.zig`:
- `basic_slurp(filename)` - Returns string descriptor
- `basic_spit(filename, content)` - Void function

### Parser
- `SLURP` is parsed as a function call with one argument
- `SPIT` is parsed as a statement with two arguments (filename, content)

### Code Generation
- `SLURP` maps to `basic_slurp` runtime call (return type `l` = pointer)
- `SPIT` generates `emitSpitStatement` which calls `basic_spit`

## Use Cases

1. **Text Editors** - Load/save entire files efficiently
2. **Configuration Files** - Read entire config in one go
3. **Data Processing** - Load data file into memory for parsing
4. **Code Generation** - Build and write output file as single string
5. **File Templates** - Load template, modify, write back

## Compatibility Notes

- Line endings are preserved as-is (no automatic conversion)
- Empty files are handled correctly (SLURP returns "", SPIT creates empty file)
- Large files are limited by available memory
- No file locking is performed (standard C `fopen` behavior)

## See Also

- `OPEN` - Traditional file opening
- `CLOSE` - Close file handle
- `LINE INPUT #` - Read file line by line
- `PRINT #` - Write to file
- `EOF()` - Check for end of file