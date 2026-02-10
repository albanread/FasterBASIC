# Command-Line Arguments in FasterBASIC

## Overview

FasterBASIC programs can access command-line arguments passed when the program is executed. This allows programs to accept input files, configuration options, and other parameters directly from the command line.

## Functions

### COMMANDCOUNT

Returns the total number of command-line arguments, including the program name.

#### Syntax
```basic
count = COMMANDCOUNT
```

#### Return Value
Integer - The number of arguments (minimum 1, which is the program name)

#### Example
```basic
arg_count = COMMANDCOUNT
PRINT "Total arguments: "; arg_count
```

### COMMAND(n)

Returns the command-line argument at index `n` as a string.

#### Syntax
```basic
arg$ = COMMAND(n)
```

#### Parameters
- `n` - Integer index of the argument (0-based)
  - `COMMAND(0)` returns the program name/path
  - `COMMAND(1)` returns the first user argument
  - `COMMAND(2)` returns the second user argument
  - etc.

#### Return Value
String - The argument at the specified index, or empty string if index is out of range

#### Example
```basic
IF COMMANDCOUNT > 1 THEN
    filename$ = COMMAND(1)
    PRINT "Opening file: "; filename$
ELSE
    PRINT "No filename provided"
ENDIF
```

## Complete Examples

### Example 1: Simple File Processor

```basic
REM File processor that accepts filename as argument

IF COMMANDCOUNT < 2 THEN
    PRINT "Usage: "; COMMAND(0); " <filename>"
    END
ENDIF

filename$ = COMMAND(1)
PRINT "Processing file: "; filename$

content$ = SLURP(filename$)
PRINT "File size: "; LEN(content$); " bytes"
```

### Example 2: Multiple Arguments

```basic
REM Program that accepts multiple arguments

PRINT "Program: "; COMMAND(0)
PRINT "Arguments: "; COMMANDCOUNT - 1
PRINT

FOR i = 1 TO COMMANDCOUNT - 1
    PRINT "Arg "; i; ": "; COMMAND(i)
NEXT i
```

### Example 3: Text Editor with Optional File

```basic
REM Text editor that optionally loads a file

DIM filename$ AS STRING

IF COMMANDCOUNT > 1 THEN
    REM Load file from command line
    filename$ = COMMAND(1)
    CALL load_file(filename$)
ELSE
    REM Start with empty file
    filename$ = "untitled.txt"
    CALL new_file()
ENDIF

REM Main editor loop...
```

### Example 4: Configuration Flags

```basic
REM Program with command-line flags

verbose = 0
filename$ = ""

REM Parse arguments
FOR i = 1 TO COMMANDCOUNT - 1
    arg$ = COMMAND(i)
    
    IF arg$ = "-v" OR arg$ = "--verbose" THEN
        verbose = 1
        PRINT "Verbose mode enabled"
    ELSEIF LEFT$(arg$, 1) <> "-" THEN
        REM Not a flag, must be filename
        filename$ = arg$
    ENDIF
NEXT i

IF filename$ = "" THEN
    PRINT "Error: No filename provided"
    END
ENDIF

PRINT "Processing: "; filename$
```

## Implementation Notes

### Argument Indexing
- Arguments are 0-indexed (like C/C++)
- `COMMAND(0)` always returns the program name or path
- User arguments start at index 1

### Empty Arguments
- Requesting an out-of-range index returns an empty string
- No error is generated for invalid indices

### Argument Parsing
- All arguments are returned as strings
- Use `VAL()` to convert numeric arguments: `n = VAL(COMMAND(1))`
- Use string comparison for flags: `IF COMMAND(1) = "-v" THEN`

### Special Characters
- Arguments with spaces should be quoted in the shell: `./program "file with spaces.txt"`
- Shell escape sequences are handled by the shell before BASIC sees them

## Runtime Behavior

### Initialization
Command-line arguments are initialized automatically when the program starts. The runtime function `basic_init_args()` is called from the generated `main()` function with the system `argc` and `argv` values.

### Memory Management
Argument strings are allocated using the FasterBASIC string system and are automatically reference-counted like all other strings in the language.

## Platform Support

Command-line argument support works on all platforms that support standard C `argc`/`argv` conventions:
- Unix/Linux
- macOS
- Windows (when compiled with compatible toolchain)

## Error Handling

- `COMMANDCOUNT` always returns at least 1 (the program name)
- `COMMAND(n)` with invalid `n` returns empty string ""
- No runtime errors are generated for invalid indices

## Use Cases

1. **File Editors** - Load file specified on command line
2. **Batch Processing** - Process files named as arguments
3. **Configuration** - Accept config file path or options
4. **Utilities** - Build command-line tools with switches
5. **Data Import** - Accept input file and output file paths

## Comparison with Other BASICs

### FreeBASIC
```basic
' FreeBASIC uses COMMAND$ function
filename$ = COMMAND$(1)
```

### QBasic/QuickBASIC
```basic
' QBasic uses COMMAND$ for entire command line (must parse)
args$ = COMMAND$
```

### FasterBASIC (This Implementation)
```basic
' FasterBASIC provides indexed access
count = COMMANDCOUNT
arg$ = COMMAND(1)
```

The FasterBASIC approach provides easier access to individual arguments without manual parsing.

## See Also

- `SLURP(filename$)` - Read entire file efficiently
- `SPIT filename$, content$` - Write entire file efficiently
- `SHELL command$` - Execute system commands