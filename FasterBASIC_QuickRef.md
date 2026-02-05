# FasterBASIC Quick Reference Card

## Basic Syntax

```basic
' Comments start with REM or apostrophe
REM This is a comment
' This is also a comment

' Line numbers are optional
10 PRINT "Line 10"
PRINT "No line number"

' Multiple statements per line (colon separator)
X = 5 : Y = 10 : PRINT X + Y

' Case insensitive
PRINT "Hello"
print "Hello"
Print "Hello"
```

## Data Types & Variables

```basic
' Type Suffixes
INTEGER%  ' 32-bit integer
LONG&     ' 64-bit integer
SINGLE!   ' 32-bit float
DOUBLE#   ' 64-bit float
STRING$   ' String
BYTE@     ' 8-bit unsigned
SHORT^    ' 16-bit integer

' Declaration
DIM count%
DIM name$
DIM x AS INTEGER
DIM y AS DOUBLE

' Arrays
DIM arr%(10)              ' Single dimension
DIM matrix#(10, 20)       ' Multi-dimensional
REDIM arr%(20)            ' Resize
REDIM PRESERVE arr%(30)   ' Resize keeping data

' Constants
CONSTANT PI = 3.14159
CONSTANT MAX = 100
```

## Operators

```basic
' Arithmetic
+ - * / \ MOD ^

' Comparison
= <> != < <= > >=

' Logical
AND OR NOT XOR EQV IMP

' Precedence (high to low)
' 1. ^ (power)
' 2. * / \ MOD
' 3. + -
' 4. = <> < <= > >=
' 5. NOT
' 6. AND
' 7. XOR OR
' 8. EQV IMP
```

## Control Flow

```basic
' IF-THEN-ELSE (single line)
IF x > 10 THEN PRINT "Yes" ELSE PRINT "No"

' IF-THEN-ELSE (multi-line)
IF x > 10 THEN
  PRINT "Greater"
ELSEIF x > 5 THEN
  PRINT "Middle"
ELSE
  PRINT "Less"
ENDIF

' SELECT CASE
SELECT CASE score
  CASE 90 TO 100
    grade$ = "A"
  CASE 80 TO 89
    grade$ = "B"
  CASE IS < 60
    grade$ = "F"
  OTHERWISE
    grade$ = "C"
ENDCASE

' GOTO/GOSUB
GOTO 100
GOSUB 1000
RETURN

' ON...GOTO/GOSUB
ON x GOTO 100, 200, 300
ON x GOSUB 1000, 2000
```

## Loops

```basic
' FOR loop
FOR i = 1 TO 10
  PRINT i
NEXT i

FOR i = 1 TO 10 STEP 2
  PRINT i
NEXT i

FOR i = 10 TO 1 STEP -1
  PRINT i
NEXT

' FOR EACH
FOR EACH item IN array()
  PRINT item
NEXT

' WHILE loop
WHILE condition
  ' statements
WEND

' DO loop
DO WHILE condition
  ' statements
LOOP

DO
  ' statements
LOOP UNTIL condition

' REPEAT loop
REPEAT
  ' statements
UNTIL condition

' EXIT statements
EXIT FOR
EXIT DO
EXIT WHILE
EXIT REPEAT
```

## Subroutines & Functions

```basic
' SUB (no return value)
SUB PrintSum(a%, b%)
  PRINT "Sum: "; a% + b%
END SUB

CALL PrintSum(5, 10)

' FUNCTION (returns value)
FUNCTION Add(a%, b%) AS INTEGER
  RETURN a% + b%
END FUNCTION

result% = Add(5, 10)

' Parameters
SUB Test(BYVAL x%, BYREF y%)
  x% = x% + 1  ' local copy
  y% = y% + 1  ' modifies original
END SUB

' DEF FN (single-line)
DEF FN Square(x) = x * x
y = FN Square(5)

' Variable scope
LOCAL x%      ' Local to sub/function
GLOBAL g%     ' Global variable
SHARED s%     ' Access global in sub
```

## I/O Statements

```basic
' Output
PRINT "Hello"
PRINT x; y; z
PRINT "Value: "; x,
? "Shorthand for PRINT"
CONSOLE "To stderr"

' Input
INPUT "Name: "; name$
INPUT x%, y%, z%
LINE INPUT text$

' File I/O
OPEN "file.txt" FOR INPUT AS #1
OPEN "out.txt" FOR OUTPUT AS #2
INPUT #1, data$
PRINT #2, "Text"
LINE INPUT #1, line$
CLOSE #1
CLOSE

' Positioned I/O
AT 10, 5
PRINT_AT 10, 5, "Text"
INPUT_AT 10, 5, "Prompt: "; var$
```

## String Functions

```basic
LEN(s$)              ' Length
LEFT$(s$, n)         ' Left n characters
RIGHT$(s$, n)        ' Right n characters
MID$(s$, start, len) ' Substring
INSTR(s$, find$)     ' Find position
CHR$(n)              ' Code to character
ASC(s$)              ' Character to code
STR$(n)              ' Number to string
VAL(s$)              ' String to number
UCASE$(s$)           ' To uppercase
LCASE$(s$)           ' To lowercase
LTRIM$(s$)           ' Trim left
RTRIM$(s$)           ' Trim right
TRIM$(s$)            ' Trim both

' String slicing
sub$ = s$[0:5]
s$[6:11] = "Text"

' MID$ assignment
MID$(s$, 1, 5) = "Hello"
```

## Math Functions

```basic
ABS(x)    ' Absolute value
SGN(x)    ' Sign (-1, 0, 1)
INT(x)    ' Integer part
FIX(x)    ' Fix towards zero
SQR(x)    ' Square root
SIN(x)    ' Sine
COS(x)    ' Cosine
TAN(x)    ' Tangent
ATN(x)    ' Arctangent
EXP(x)    ' e^x
LOG(x)    ' Natural log
RND()     ' Random [0,1)
```

## Type Conversion

```basic
CINT(x)   ' To INTEGER
CLNG(x)   ' To LONG
CSNG(x)   ' To SINGLE
CDBL(x)   ' To DOUBLE
CSTR(x)   ' To STRING
```

## Exception Handling

```basic
TRY
  ' code that may throw
  THROW 100
CATCH 100
  PRINT "Error: "; ERR()
CATCH 200, 201
  PRINT "Other errors"
FINALLY
  ' cleanup (always runs)
END TRY

' Error functions
ERR()  ' Error code
ERL()  ' Error line
```

## User-Defined Types

```basic
TYPE Point
  X AS INTEGER
  Y AS INTEGER
END TYPE

DIM p AS Point
p.X = 10
p.Y = 20
PRINT p.X, p.Y
```

## Data Statements

```basic
DATA 1, 2, 3, 4, 5
DATA "Apple", "Banana"

READ a%, b%, c%
READ fruit$

RESTORE        ' Reset to first
RESTORE 100    ' Restore to line
```

## Graphics

```basic
' Screen
CLS              ' Clear screen
GCLS             ' Clear graphics
COLOR fg, bg     ' Set colors

' Primitives
PSET (x, y), color
LINE (x1, y1) - (x2, y2), color
RECT x, y, w, h, color
RECTF x, y, w, h, color    ' Filled
CIRCLE x, y, r, color
CIRCLEF x, y, r, color     ' Filled
HLINE x, y, len, color
VLINE x, y, len, color

' Text layer
TEXTPUT x, y, "Text", fg, bg
TCHAR x, y, code, fg, bg
TGRID w, h
TSCROLL dir
TCLEAR x, y, w, h
```

## Sprites

```basic
SPRLOAD id, "file.png"
SPRSHOW id
SPRHIDE id
SPRMOVE id, dx, dy
SPRPOS id, x, y, angle, sx, sy
SPRTINT id, color
SPRSCALE id, sx, sy
SPRROT id, angle
SPREXPLODE id, pieces, time
SPRFREE id
```

## Timer Events

```basic
' One-shot timers
AFTER 1000 MS GOSUB Handler
AFTER 5 SECS CALL Function
AFTERFRAMES 60 GOSUB Delayed

' Repeating timers
EVERY 100 MS GOSUB Loop
EVERY 1 SECS CALL Update
EVERYFRAME 1 GOSUB Render

' Inline handlers
EVERY 1000 MS DO
  PRINT "Tick"
DONE

' Control
TIMER STOP HandlerName
TIMER STOP  ' Stop all

' Event loop
RUN              ' Run forever
RUN UNTIL done%  ' Run with condition

' Synchronization
VSYNC            ' Wait 1 frame
VSYNC 2          ' Wait 2 frames
WAIT 10          ' Wait 10 frames
WAIT_MS 1000     ' Wait milliseconds
```

## Audio

```basic
PLAY "music.ogg", "ogg"
PLAY_SOUND id, volume
```

## Utility Statements

```basic
SWAP a%, b%      ' Swap variables
INC x%           ' Increment by 1
INC x%, 5        ' Increment by 5
DEC x%           ' Decrement by 1
DEC x%, 3        ' Decrement by 3

' IIF expression
result$ = IIF(x > 10, "Yes", "No")
max% = IIF(a > b, a, b)
```

## Compiler Options

```basic
OPTION BASE 0             ' Array base 0
OPTION BASE 1             ' Array base 1
OPTION EXPLICIT           ' Must declare vars
OPTION BITWISE            ' Bitwise operators
OPTION LOGICAL            ' Logical operators
OPTION UNICODE            ' UTF-32 strings
OPTION ASCII              ' ASCII strings
OPTION DETECTSTRING       ' Auto-detect
OPTION ERROR ON           ' Track line numbers
OPTION ERROR OFF          ' No tracking
OPTION CANCELLABLE ON     ' Loop cancellation
OPTION BOUNDS_CHECK ON    ' Array checking
OPTION FORCE_YIELD ON     ' Preemptive handlers
OPTION INCLUDE "file.bas" ' Include file
OPTION ONCE               ' Include once
```

## Common Patterns

```basic
' Loop counter
FOR i = 1 TO 10
  PRINT i
NEXT

' Input validation
DO
  INPUT "Enter positive: "; x%
LOOP UNTIL x% > 0

' Array sum
sum% = 0
FOR i = 0 TO 9
  sum% = sum% + arr%(i)
NEXT

' String concatenation
result$ = "Hello" + " " + "World"

' Min/Max
min% = IIF(a < b, a, b)
max% = IIF(a > b, a, b)

' Absolute value
abs% = IIF(x < 0, -x, x)

' Range check
IF x >= min% AND x <= max% THEN
  PRINT "In range"
ENDIF

' Menu selection
PRINT "1. Option 1"
PRINT "2. Option 2"
PRINT "3. Exit"
INPUT choice%
ON choice% GOSUB Opt1, Opt2, Quit
```

## Program Structure

```basic
' Typical program layout
OPTION EXPLICIT
OPTION BASE 0

' Constants
CONSTANT SCREEN_W = 640
CONSTANT SCREEN_H = 480

' Global variables
GLOBAL score%
GLOBAL lives%

' Initialization
CALL Initialize()

' Main loop
REPEAT
  CALL ProcessInput()
  CALL Update()
  CALL Render()
UNTIL quit%

END

' Subroutines
SUB Initialize()
  score% = 0
  lives% = 3
END SUB

SUB ProcessInput()
  ' Input handling
END SUB

SUB Update()
  ' Game logic
END SUB

SUB Render()
  ' Drawing
END SUB
```

## Quick Tips

- **Case insensitive**: PRINT = print = Print
- **LET optional**: `X = 5` same as `LET X = 5`
- **Line numbers optional**: Use for GOTO/GOSUB targets
- **Multiple statements**: Use `:` to separate
- **PRINT shorthand**: `?` is same as `PRINT`
- **Type suffix optional**: If using AS keyword
- **Arrays 0-based**: Unless OPTION BASE 1
- **String concatenation**: Use `+` operator
- **Comments**: REM or ' (apostrophe)
- **Implicit LET**: Assignment without LET keyword

## System Functions

```basic
TIMER()    ' System time
EOF(n)     ' End of file
LOF(n)     ' Length of file
ERR()      ' Error code
ERL()      ' Error line
```

## Compilation

```bash
# Compile program
fbc_qbe program.bas -o program

# Run program
./program

# Run tests
./scripts/run_tests_simple.sh
```

## Target Platforms

- AMD64 (x86-64)
- ARM64 (Apple Silicon, RPi)
- RISC-V (RV64)