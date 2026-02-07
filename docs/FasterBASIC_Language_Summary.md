# FasterBASIC Language Summary

## Overview

FasterBASIC is a modern, compiled BASIC dialect that combines the ease of traditional BASIC with advanced features like exception handling, user-defined types, and event-driven programming. The compiler generates native machine code via the QBE backend for AMD64, ARM64, and RISC-V architectures.

## Key Language Features

### 1. Type System

#### Primitive Types
- **INTEGER** (`%`) - 32-bit signed integer
- **LONG** (`&`) - 64-bit signed integer  
- **SINGLE** (`!`) - 32-bit floating point
- **DOUBLE** (`#`) - 64-bit floating point
- **STRING** (`$`) - String (ASCII or Unicode UTF-32)
- **BYTE** (`@`) - 8-bit unsigned integer
- **SHORT** (`^`) - 16-bit signed integer
- **UBYTE**, **USHORT**, **UINTEGER**, **ULONG** - Unsigned variants

#### Type Declaration
```basic
' Type suffix
DIM count%
DIM name$
DIM value#

' AS keyword
DIM count AS INTEGER
DIM name AS STRING
DIM value AS DOUBLE

' Implicit (if OPTION EXPLICIT not set)
count = 42
```

#### User-Defined Types
```basic
TYPE Point
  X AS INTEGER
  Y AS INTEGER
END TYPE

DIM p AS Point
p.X = 10
p.Y = 20
```

*Note: FasterBASIC automatically uses SIMD (NEON) instructions for UDTs with homogenous numeric fields (e.g., 4x FLOAT) on supported platforms.*

### 2. Variables, Arrays, Lists, and Maps

#### Variable Declaration
```basic
DIM x AS INTEGER
DIM name AS STRING
LOCAL temp AS DOUBLE      ' Function/sub local
GLOBAL config AS STRING   ' Global variable
SHARED counter AS INTEGER ' Access global in sub/function
```

#### Lists (Dynamic Collections)
```basic
' Uniform List
DIM nums AS LIST OF INTEGER
nums.APPEND(10)
nums.APPEND(20)
PRINT nums.GET(1)  ' Method access: 10
PRINT nums(1)      ' Array-style sugar: 10

' Polymorphic List
DIM objects AS LIST OF ANY
objects.APPEND(42)
objects.APPEND("Hello")

' List Initializer
DIM primes AS LIST OF INTEGER = LIST(2, 3, 5, 7)

' Operations
len = nums.LENGTH()
head = nums.HEAD()
found = nums.CONTAINS(20)
idx = nums.INDEXOF(20)
val = nums.POP()   ' Remove from end
val = nums.SHIFT() ' Remove from start
ERASE nums         ' Clear list
```

#### Arrays
```basic
' Single dimension
DIM numbers%(10)

' Multi-dimensional
DIM matrix#(10, 20)

' Dynamic resizing
REDIM numbers%(20)
REDIM PRESERVE numbers%(30)

' Base index (0 or 1)
OPTION BASE 0
```

#### HashMaps
```basic
' Declaration
DIM map AS HASHMAP

' Assignment & Retrieval
map("name") = "Alice"
map("score") = "100"
PRINT map("name")

' Updates
map("score") = "101"
```

### 3. Control Flow

#### Conditional Statements
```basic
' Single-line IF
IF x > 10 THEN PRINT "Greater"

IF x > 10 THEN PRINT "Greater" ELSE PRINT "Less"

' Multi-line IF
IF x > 10 THEN
  PRINT "Greater than 10"
ELSEIF x > 5 THEN
  PRINT "Greater than 5"
ELSE
  PRINT "5 or less"
ENDIF

' SELECT CASE
SELECT CASE score
  CASE 90 TO 100
    PRINT "A"
  CASE 80 TO 89
    PRINT "B"
  CASE IS < 60
    PRINT "F"
  FOR EACH (HashMap)
FOR EACH key IN map
  PRINT key
NEXT

' FOR Key, Value (HashMap)
FOR k, v IN map
  PRINT k; " => "; v
NEXT

' Type Pattern Matching (for LIST OF ANY)
FOR EACH item IN objects
  MATCH TYPE item
    CASE INTEGER i
      PRINT "Integer: "; i
    CASE STRING s
      PRINT "String: "; s
    CASE ELSE
      PRINT "Unknown type"
  END MATCH
NEXT

' OTHERWISE
    PRINT "C or D"
ENDCASE
```

#### Loops
```basic
' FOR loop
FOR i = 1 TO 10 STEP 2
  PRINT i
NEXT i

' FOR EACH loop
FOR EACH item IN array()
  PRINT item
NEXT

' WHILE loop
WHILE x < 100
  x = x + 1
WEND

' REPEAT loop
REPEAT
  x = x + 1
UNTIL x >= 100

' DO loop (flexible)
DO WHILE x < 100
  x = x + 1
LOOP

DO
  x = x + 1
LOOP UNTIL x >= 100

' EXIT statements
EXIT FOR
EXIT WHILE
EXIT DO
```

#### Branching
```basic
GOTO 100
GOSUB 1000
RETURN

' Computed branching
ON x GOTO 100, 200, 300
ON x GOSUB 1000, 2000, 3000
ON x CALL Sub1, Sub2, Sub3
```

### 4. Subroutines and Functions

#### SUB (Procedure)
```basic
SUB PrintSum(a%, b%)
  PRINT "Sum = "; a% + b%
END SUB

CALL PrintSum(5, 10)
```

#### FUNCTION (Returns value)
```basic
FUNCTION Add(a%, b%) AS INTEGER
  RETURN a% + b%
END FUNCTION

result% = Add(5, 10)
```

#### Parameter Passing
```basic
SUB ModifyValue(BYREF x%, BYVAL y%)
  x% = x% + 1  ' Modifies original
  y% = y% + 1  ' Local copy only
END SUB
```

#### DEF FN (Single-line function)
```basic
DEF FN Square(x) = x * x
PRINT FN Square(5)
```

### 5. Exception Handling

```basic
TRY
  THROW 100
CATCH 100
  PRINT "Caught error 100"
  PRINT "Error code: "; ERR()
CATCH 200, 201, 202
  PRINT "Caught errors 200-202"
FINALLY
  PRINT "Cleanup (always runs)"
END TRY
```

### 6. Input/Output

#### Console I/O
```basic
' Print
PRINT "Hello, World!"
PRINT x; y; z
PRINT "Value: "; x,
? "Question mark is shorthand for PRINT"

' Console (stderr)
CONSOLE "Error message"

' Input
INPUT "Enter name: "; name$
INPUT x%, y%, z%
```

#### File I/O
```basic
OPEN "data.txt" FOR INPUT AS #1
OPEN "output.txt" FOR OUTPUT AS #2

PRINT #2, "Line of text"
INPUT #1, value$
LINE INPUT #1, line$

CLOSE #1
CLOSE #2
```

#### Positioned Text
```basic
AT 10, 5: PRINT "At row 10, col 5"
PRINT_AT 10, 5, "Hello"
INPUT_AT 10, 5, "Name: "; name$
```

### 7. String Operations

#### String Functions
```basic
s$ = "Hello World"
length% = LEN(s$)
left$ = LEFT$(s$, 5)
right$ = RIGHT$(s$, 5)
mid$ = MID$(s$, 7, 5)
pos% = INSTR(s$, "World")
upper$ = UCASE$(s$)
lower$ = LCASE$(s$)
```

#### String Slicing
```basic
s$ = "Hello World"
sub$ = s$[0:5]        ' "Hello"
s$[6:11] = "BASIC"    ' "Hello BASIC"
```

#### MID$ Assignment
```basic
s$ = "Hello World"
MID$(s$, 1, 5) = "Greet"  ' "Greetings World"
```

### 8. Graphics and Multimedia

#### Basic Graphics
```basic
CLS              ' Clear screen
GCLS             ' Clear graphics layer
COLOR 15, 0      ' Set foreground, background

PSET (100, 100), color
LINE (10, 10) - (100, 100), color
RECT x, y, width, height, color
RECTF x, y, width, height, color  ' Filled
CIRCLE x, y, radius, color
CIRCLEF x, y, radius, color       ' Filled
HLINE x, y, length, color
VLINE x, y, length, color
```

#### Text Layer
```basic
TEXTPUT x, y, "Text", fg, bg
TCHAR x, y, char_code, fg, bg
TGRID width, height
TSCROLL direction
TCLEAR x, y, width, height
```

#### Sprites
```basic
SPRLOAD sprite_id, "filename.png"
SPRSHOW sprite_id
SPRHIDE sprite_id
SPRMOVE sprite_id, dx, dy
SPRPOS sprite_id, x, y, angle, scale_x, scale_y
SPRTINT sprite_id, color
SPRSCALE sprite_id, scale_x, scale_y
SPRROT sprite_id, angle
SPREXPLODE sprite_id, pieces, duration
SPRFREE sprite_id
```

#### Audio
```basic
PLAY "music.ogg", "ogg"
PLAY_SOUND sound_id, volume
```

### 9. Timer Events and Event Loop

#### Timer Events
```basic
' One-shot timers
AFTER 1000 MS GOSUB Timer1Handler
AFTER 5 SECS CALL TimerFunction

' Repeating timers
EVERY 100 MS GOSUB GameLoop
EVERY 1 SECS CALL UpdateScore

' Frame-based
AFTERFRAMES 60 GOSUB DelayedAction
EVERYFRAME 1 GOSUB RenderFrame

' Inline handlers
EVERY 1000 MS DO
  PRINT "Tick"
  counter% = counter% + 1
DONE

' Control timers
TIMER STOP HandlerName
TIMER STOP

' Main event loop
RUN              ' Run until quit
RUN UNTIL done%  ' Run with condition
```

#### Frame Synchronization
```basic
VSYNC      ' Wait for next frame
VSYNC 2    ' Wait 2 frames
WAIT       ' Wait 1 frame
WAIT 10    ' Wait 10 frames
WAIT_MS 1000  ' Wait 1000 milliseconds
```

### 10. Data Statements
Object-Oriented Programming (Classes)
```basic
CLASS Animal
  Name AS STRING
  CONSTRUCTOR(n$)
    ME.Name = n$
  END CONSTRUCTOR
  METHOD Speak()
    PRINT ME.Name; " makes a sound."
  END METHOD
END CLASS

CLASS Dog INHERITS Animal
  METHOD Speak()
    PRINT ME.Name; " says Woof!"
  END METHOD
END CLASS

DIM d AS Dog = NEW Dog("Rex")
d.Speak()
```

#### Plugins
FasterBASIC supports a modular plugin system. C-native plugins placed in the `plugins/enabled/` directory are automatically loaded at compile time, making their commands available to your BASIC programs seamlessly.

#### 
```basic
DATA 10, 20, 30, 40
DATA "Apple", "Banana", "Cherry"

READ x%, y%, z%
READ fruit$

RESTORE       ' Reset to first DATA
RESTORE 100   ' Restore to line 100
```

### 11. Advanced Features

#### Constants
```basic
CONSTANT PI = 3.14159
CONSTANT MAX_SIZE = 1000
```

#### IIF Expression (Immediate IF)
```basic
result$ = IIF(x > 10, "Greater", "Less")
max% = IIF(a% > b%, a%, b%)
```

#### SWAP
```basic
SWAP a%, b%
```

#### INC/DEC
```basic
INC counter%
INC counter%, 5
DEC counter%
DEC counter%, 2
```

### 12. Compiler Options

```basic
' Array base index
OPTION BASE 0
OPTION BASE 1

' Logical vs Bitwise operators
OPTION LOGICAL   ' AND/OR/NOT are logical (default)
OPTION BITWISE   ' AND/OR/NOT are bitwise

' Variable declaration
OPTION EXPLICIT  ' All variables must be declared

' String encoding
OPTION ASCII         ' ASCII strings (default)
OPTION UNICODE       ' UTF-32 strings
OPTION DETECTSTRING  ' Auto-detect based on content

' Error tracking
OPTION ERROR ON      ' Track line numbers (default)
OPTION ERROR OFF     ' Disable for performance

' Runtime features
OPTION CANCELLABLE ON     ' Allow loop cancellation
OPTION BOUNDS_CHECK ON    ' Array bounds checking
OPTION FORCE_YIELD ON     ' Quasi-preemptive handlers

' File inclusion
OPTION INCLUDE "library.bas"
OPTION ONCE  ' Include file only once (header guard)
```

### 13. Operators

#### Arithmetic
```basic
+    ' Addition
-    ' Subtraction
*    ' Multiplication
/    ' Division
\    ' Integer division
MOD  ' Modulo
^    ' Exponentiation
```

#### Comparison
```basic
=    ' Equal
<>   ' Not equal
!=   ' Not equal (alternative)
<    ' Less than
<=   ' Less than or equal
>    ' Greater than
>=   ' Greater than or equal
```

#### Logical
```basic
AND  ' Logical AND
OR   ' Logical OR
NOT  ' Logical NOT
XOR  ' Exclusive OR
EQV  ' Equivalence
IMP  ' Implication
```

### 14. Built-in Functions

#### Math Functions
```basic
ABS(x)    ' Absolute value
SGN(x)    ' Sign (-1, 0, 1)
INT(x)    ' Integer part (floor)
FIX(x)    ' Fix towards zero
SQR(x)    ' Square root
SIN(x), COS(x), TAN(x)
ATN(x)    ' Arctangent
EXP(x)    ' e^x
LOG(x)    ' Natural logarithm
RND()     ' Random number [0, 1)
```

#### Type Conversion
```basic
CINT(x)   ' Convert to INTEGER
CLNG(x)   ' Convert to LONG
CSNG(x)   ' Convert to SINGLE
CDBL(x)   ' Convert to DOUBLE
CSTR(x)   ' Convert to STRING
VAL(s$)   ' String to number
STR$(x)   ' Number to string
ASC(s$)   ' Character to ASCII code
CHR$(n)   ' ASCII code to character
```

#### System Functions
```basic
ERR()       ' Current error code
ERL()       ' Error line number
TIMER()     ' System time
EOF(n)      ' End of file test
LOF(n)      ' Length of file
```

## Example Programs

### Hello World
```basic
PRINT "Hello, World!"
END
```

### Simple Loop
```basic
FOR i = 1 TO 10
  PRINT i; " squared = "; i * i
NEXT i
END
```

### Subroutine Example
```basic
FUNCTION Factorial(n%) AS LONG
  IF n% <= 1 THEN
    RETURN 1
  ELSE
    RETURN n% * Factorial(n% - 1)
  ENDIF
END FUNCTION

PRINT "5! = "; Factorial(5)
END
```

### Exception Handling
```basic
TRY
  INPUT "Enter a number: "; x%
  IF x% < 0 THEN THROW 100
  PRINT "Square root: "; SQR(x%)
CATCH 100
  PRINT "Error: Negative number"
FINALLY
  PRINT "Done"
END TRY
END
```

### Timer Event Example
```basic
counter% = 0

EVERY 1000 MS DO
  counter% = counter% + 1
  PRINT "Second "; counter%
DONE

AFTER 10 SECS DO
  PRINT "Time's up!"
  END
DONE

RUN  ' Enter event loop
```

### Graphics Example
```basic
GCLS
COLOR 15

FOR i = 0 TO 100
  CIRCLE 320, 240, i, i MOD 16
NEXT i

PRINT_AT 10, 10, "Press any key..."
INPUT dummy$
END
```

## Compilation and Execution

### Command Line
```bash
# Compile BASIC program
fbc_qbe program.bas -o program

# Run compiled program
./program
```

### Build Process
1. **Lexical Analysis** - Source code → Tokens
2. **Parsing** - Tokens → Abstract Syntax Tree (AST)
3. **Semantic Analysis** - Type checking, scope resolution
4. **CFG Construction** - AST → Control Flow Graph
5. **Code Generation** - CFG → QBE Intermediate Language
6. **QBE Compilation** - QBE IL → Assembly
7. **Assembly** - Assembly → Native machine code
8. **Linking** - Link with runtime library

### Target Platforms
- **AMD64** (x86-64) - Intel/AMD processors
- **ARM64** (AArch64) - Apple Silicon, Raspberry Pi 4+
- **RISC-V** (RV64) - RISC-V 64-bit processors

## Language Design Philosophy

1. **Ease of Use** - Simple syntax, readable code
2. **Performance** - Compiled to native code, not interpreted
3. **Modern Features** - Exception handling, UDTs, events
4. **Extensibility** - Modular command registry system
5. **Multimedia** - Built-in graphics, sprites, audio
6. **Cross-Platform** - Multiple architecture support

## Differences from Traditional BASIC

### Enhancements
- Exception handling (TRY/CATCH/FINALLY)
- User-defined types (TYPE...END TYPE)
- String slicing syntax
- IIF() expressions
- FOR EACH loops
- Flexible DO loops
- Timer and event system
- BYREF/BYVAL parameters
- LOCAL/GLOBAL/SHARED scoping
- Unicode support
- Graphics and multimedia primitives

### Compatibility Notes
- Line numbers are optional
- LET keyword is optional
- Multiple loop styles (WHILE/WEND, DO/LOOP, REPEAT/UNTIL)
- Both GOTO/GOSUB and structured programming supported
- Type suffixes and AS keyword both supported

## Architecture

### Compiler Components
- **Lexer** (`fasterbasic_lexer.cpp`) - Tokenization
- **Parser** (`fasterbasic_parser.cpp`) - Syntax analysis
- **AST** (`fasterbasic_ast.h`) - Abstract representation
- **CFG Builder** (`cfg/cfg_builder_*.cpp`) - Control flow
- **CodeGen V2** (`codegen_v2/`) - Code generation
- **QBE Backend** (`qbe_source/`) - Native code generation

### Runtime Components
- **C Runtime** (`runtime_c/`) - Low-level operations
- **C++ Runtime** (`runtime/`) - High-level abstractions
- **String Pool** - Efficient string management
- **Array Manager** - Dynamic array handling
- **Event Queue** - Timer and event system
- **I/O Manager** - File and terminal I/O

## Resources

- Source code: `/Users/oberon/compact_repo`
- Test suite: `/Users/oberon/compact_repo/tests`
- BNF Grammar: `FasterBASIC_BNF.md`
- Build script: `qbe_basic_integrated/build_qbe_basic.sh`
- Test runner: `scripts/run_tests_simple.sh`

## License

See LICENSE file in the project root.