compact_repo/manuals/user_guide.md
# FasterBASIC User Guide

*Authored by the FasterBASIC Team  
Head Technical Writer: [Your Name Here]*

---

## Introduction

Welcome to FasterBASIC! This guide will help you get started with the terminal features of FasterBASIC, a modern, high-performance, and user-friendly BASIC dialect. This manual covers the essentials for writing, running, and understanding BASIC programs using the terminal. Graphics and sound extensions are not covered here and will be documented separately.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Getting Started](#getting-started)
3. [Basic Language Structure](#basic-language-structure)
4. [Variables and Data Types](#variables-and-data-types)
5. [Input and Output](#input-and-output)
6. [Control Flow](#control-flow)
7. [Functions and Subroutines](#functions-and-subroutines)
8. [Arrays and Data](#arrays-and-data)
9. [Strings](#strings)
10. [Math and Built-in Functions](#math-and-built-in-functions)
11. [Error Handling](#error-handling)
12. [File I/O (Terminal)](#file-io-terminal)
13. [Advanced Topics](#advanced-topics)
14. [Appendix](#appendix)

---

## 1. Introduction

FasterBASIC is a modern, high-performance implementation of the BASIC programming language, designed for clarity, speed, and ease of use. This guide covers the terminal-only edition, focusing on traditional BASIC features for text-based applications. Graphics, sound, and event-driven programming are not included here and will be documented separately as plugin extensions.

**Key Features (Terminal Edition):**
- Simple, readable BASIC syntax
- Fast native-code compilation
- Full support for variables, arrays, user-defined types, and structured programming
- Robust control flow: IF, FOR, WHILE, DO, SELECT CASE, GOTO, GOSUB, and more
- Modern exception handling (TRY/CATCH/FINALLY/THROW)
- Comprehensive string and math functions
- File I/O for reading and writing text and data files
- Compatible with classic BASIC dialects, with useful enhancements

**About this Manual:**  
This manual is intended for both new and experienced BASIC programmers. It provides practical examples and explanations for all terminal features of FasterBASIC. For advanced topics such as graphics, sound, or plugin development, refer to the relevant manuals.

---

## 2. Getting Started

This section will help you install FasterBASIC, write your first program, and run it from the terminal.

### Installation and Setup

1. **Build the Integrated Compiler:**
   - Open a terminal and navigate to your FasterBASIC project directory.
   - Run:
     ```
     cd qbe_basic_integrated
     ./build_qbe_basic.sh
     ```
   - This will produce the `qbe_basic` compiler executable.

2. **Verify Installation:**
   - Run:
     ```
     ./qbe_basic --help
     ```
   - You should see usage instructions for the compiler.

### Your First Program: Hello World

Create a new file called `hello.bas` with the following content:
```basic
PRINT "Hello, World!"
END
```

### Compiling and Running Programs

To compile and run your BASIC program:

1. **Compile to an executable:**
   ```
   ./qbe_basic -o hello hello.bas
   ```

2. **Run the program:**
   ```
   ./hello
   ```

You should see:
```
Hello, World!
```

### Running Test Programs

FasterBASIC includes a suite of test programs in the `tests/` directory. You can compile and run any of these to explore language features and verify your installation.

---


- Installation and setup
- Your first program (Hello World)
- Running and compiling programs

## 3. Basic Language Structure

FasterBASIC programs are composed of statements, functions, and subroutines written in a clear, line-oriented style. Each statement typically occupies its own line, but multiple statements can be separated by colons (`:`).

### Program Layout

A typical BASIC program consists of:
- Declarations (variables, arrays, user-defined types)
- Executable statements (assignments, control flow, I/O)
- Functions and subroutines (optional, for structured code)

Example:
```basic
REM Simple program
DIM total%
total% = 0
FOR i% = 1 TO 10
    total% = total% + i%
NEXT i%
PRINT "Sum is "; total%
END
```

### Comments

Use `REM` or a single quote (`'`) to add comments:
```basic
REM This is a comment
' This is also a comment
```
Comments are ignored by the compiler and can appear on their own line or after code.

### End of Program

The `END` statement marks the end of your program. Execution stops when `END` is reached, or when the last statement is executed.

---

## 4. Variables and Data Types

FasterBASIC supports several variable types, including numeric and string types. Variables must be declared before use.

### Numeric Types

- **INTEGER**: 32-bit signed integer (suffix `%`)
- **FLOAT/DOUBLE**: 64-bit floating point (suffix `!` or `#`)
- **LONG**: 64-bit integer (suffix `&`)

Example:
```basic
DIM count%      ' Integer
DIM price!      ' Float
DIM bigNum&     ' Long integer
```

### String Variables

Strings are declared with a `$` suffix:
```basic
DIM name$       ' String variable
name$ = "Alice"
PRINT name$
```

### Type Suffixes

You can use type suffixes to specify variable types:
- `%` for INTEGER
- `!` for SINGLE (float)
- `#` for DOUBLE (float)
- `$` for STRING
- `&` for LONG

If no suffix is provided, the default type is determined by the declaration or context.

### Variable Assignment

Assign values using the `=` operator:
```basic
x% = 42
y! = 3.14
s$ = "Hello"
```

### Naming Rules

- Variable names must start with a letter and may contain letters, digits, and underscores.
- Names are case-insensitive: `Total%` and `total%` refer to the same variable.

---

## 5. Input and Output

FasterBASIC provides simple commands for interacting with the user and the terminal.

### Printing Output

- **PRINT**: Displays text or values to the terminal.
  ```basic
  PRINT "Hello, World!"
  PRINT "The answer is "; 42
  PRINT x%, y!
  ```

- **PRINTHEX**: Prints an integer or pointer value as hexadecimal (useful for debugging).
  ```basic
  PRINTHEX 255
  ```

- **PRINT with Separators**: Use `;` or `,` to separate values.
  ```basic
  PRINT "A = "; a%; ", B = "; b!
  ```

### Reading Input

- **INPUT**: Reads a value from the user and stores it in a variable.
  ```basic
  INPUT "Enter your name: ", name$
  ```

- **LINE INPUT**: Reads an entire line of input, including spaces.
  ```basic
  LINE INPUT "Type a sentence: ", sentence$
  ```

### File I/O Basics

- **OPEN**: Opens a file for reading or writing.
  ```basic
  OPEN "data.txt", "r", 1   ' Open for reading on channel 1
  OPEN "output.txt", "w", 2 ' Open for writing on channel 2
  ```

- **CLOSE**: Closes a file channel.
  ```basic
  CLOSE 1
  ```

- **PRINT#**: Writes text to a file.
  ```basic
  PRINT#2, "Hello, file!"
  ```

- **INPUT#**: Reads from a file into a variable.
  ```basic
  INPUT#1, line$
  ```

---

## 6. Control Flow

FasterBASIC supports a variety of control flow constructs for structured programming.

### Conditional Statements

- **IF...THEN...ELSE**: Executes code based on a condition.
  ```basic
  IF x% > 10 THEN
      PRINT "x is greater than 10"
  ELSE
      PRINT "x is 10 or less"
  END IF
  ```

- **Single-line IF**:
  ```basic
  IF a% = 0 THEN PRINT "Zero"
  ```

### Loops

- **FOR...NEXT**: Repeats a block a specific number of times.
  ```basic
  FOR i% = 1 TO 5
      PRINT i%
  NEXT i%
  ```

- **WHILE...WEND**: Loops while a condition is true.
  ```basic
  WHILE n% > 0
      PRINT n%
      n% = n% - 1
  WEND
  ```

- **DO...LOOP**: Flexible looping with WHILE or UNTIL.
  ```basic
  DO WHILE x% < 10
      x% = x% + 1
  LOOP
  ```

- **REPEAT...UNTIL**: Loop executes at least once, then checks the condition.
  ```basic
  REPEAT
      PRINT "Repeating"
      x% = x% - 1
  UNTIL x% = 0
  ```

### Branching and Subroutines

- **GOTO**: Jumps to a labeled line (use sparingly).
  ```basic
  IF error THEN GOTO ErrorHandler
  ```

- **GOSUB...RETURN**: Calls a subroutine and returns.
  ```basic
  GOSUB PrintHeader
  ' ... code ...
  RETURN

  PrintHeader:
      PRINT "Header"
      RETURN
  ```

### SELECT CASE

- **SELECT CASE**: Multi-way branching based on a value.
  ```basic
  SELECT CASE grade$
      CASE "A"
          PRINT "Excellent"
      CASE "B"
          PRINT "Good"
      CASE ELSE
          PRINT "Needs improvement"
  END SELECT
  ```

### Other Control Flow

- **SLEEP**: Pauses execution for a specified number of seconds.
  ```basic
  SLEEP 2
  ```

- **CALL**: Calls a user-defined subroutine or function by name.
  ```basic
  CALL "MySubroutine"
  ```

---

- `PRINT`, `PRINTHEX`
- `INPUT`, `LINE INPUT`
- File I/O basics (`OPEN`, `CLOSE`, `PRINT#`, `INPUT#`)

## 6. Control Flow

- `IF...THEN...ELSE`
- `FOR...NEXT`, `WHILE...WEND`, `DO...LOOP`, `REPEAT...UNTIL`
- `GOTO`, `GOSUB`, `RETURN`
- `SELECT CASE`
- `SLEEP`, `CALL`

## 7. Functions and Subroutines

FasterBASIC supports both functions (which return values) and subroutines (which do not). These allow you to organize code into reusable blocks.

### Defining a Function

Use `FUNCTION` and `END FUNCTION` to define a function. Return a value by assigning to the function name or using `RETURN`.

```basic
FUNCTION Add%(a%, b%)
    Add% = a% + b%
END FUNCTION

PRINT "Sum: "; Add%(2, 3)
```

Or with `RETURN`:

```basic
FUNCTION Square(x%)
    RETURN x% * x%
END FUNCTION
```

### Defining a Subroutine

Use `SUB` and `END SUB` for subroutines that do not return a value.

```basic
SUB PrintGreeting(name$)
    PRINT "Hello, "; name$
END SUB

CALL PrintGreeting("Alice")
```

### Parameter Passing and Local Variables

Parameters are passed by value. You can declare local variables inside functions and subs using `DIM`.

```basic
FUNCTION Multiply(a%, b%)
    DIM result%
    result% = a% * b%
    RETURN result%
END FUNCTION
```

### Exiting Early

- Use `EXIT FUNCTION` or `EXIT SUB` to exit early from a function or subroutine.

```basic
FUNCTION SafeDivide(a%, b%)
    IF b% = 0 THEN
        PRINT "Divide by zero!"
        EXIT FUNCTION
    END IF
    SafeDivide = a% / b%
END FUNCTION
```

---


## 8. Arrays and Data

FasterBASIC supports arrays for storing sequences of values, as well as data statements for embedding constant data.

### Declaring Arrays

Use `DIM` to declare arrays:

```basic
DIM numbers%(10)      ' 11 elements: 0 to 10
DIM names$(5)         ' 6 elements: 0 to 5
```

You can specify custom bounds:

```basic
DIM scores%(1 TO 5)   ' Elements 1 to 5
```

### Accessing and Assigning Array Elements

Assign and access elements using parentheses:

```basic
numbers%(0) = 42
PRINT names$(2)
```

### Dynamic Arrays

Use `REDIM` to resize arrays (optionally with `PRESERVE` to keep existing data):

```basic
REDIM numbers%(20)
REDIM PRESERVE numbers%(30)
```

Use `ERASE` to clear an array:

```basic
ERASE numbers%
```

### DATA, READ, and RESTORE

- `DATA` statements embed constant values in your program.
- `READ` reads the next value from the DATA list into a variable.
- `RESTORE` resets the DATA pointer (optionally to a label).

Example:

```basic
DATA 10, 20, 30
READ a%, b%, c%
PRINT a%, b%, c%
RESTORE
READ x%
PRINT x%
```

---


## 9. Strings

Strings in FasterBASIC are flexible and support a wide range of operations, including assignment, concatenation, slicing, and built-in functions.

### Declaring and Assigning Strings

Declare string variables with a `$` suffix:
```basic
DIM name$
name$ = "Alice"
```

### Concatenation

Use the `+` operator to join strings:
```basic
greeting$ = "Hello, " + name$
PRINT greeting$
```

### String Slicing

Extract substrings using slice notation:
```basic
DIM s$, part$
s$ = "Hello World"
part$ = s$(1 TO 5)      ' "Hello"
part$ = s$(7 TO)        ' "World"
part$ = s$(TO 5)        ' "Hello"
PRINT part$
```

### Common String Functions

- **LEN**: Returns the length of a string.
  ```basic
  PRINT LEN(s$)
  ```
- **LEFT$ / RIGHT$ / MID$**: Extract substrings.
  ```basic
  PRINT LEFT$(s$, 5)      ' "Hello"
  PRINT RIGHT$(s$, 5)     ' "World"
  PRINT MID$(s$, 7, 3)    ' "Wor"
  ```
- **CHR$ / ASC**: Convert between characters and ASCII codes.
  ```basic
  PRINT CHR$(65)          ' "A"
  PRINT ASC("A")          ' 65
  ```
- **STR$ / VAL**: Convert numbers to strings and vice versa.
  ```basic
  PRINT STR$(123)         ' "123"
  PRINT VAL("456")        ' 456
  ```
- **UCASE$ / LCASE$**: Change case.
  ```basic
  PRINT UCASE$("abc")     ' "ABC"
  PRINT LCASE$("XYZ")     ' "xyz"
  ```

See the Reference Manual for a complete list of string functions.

---

- String assignment and concatenation
- String slicing
- Common string functions

## 10. Math and Built-in Functions

FasterBASIC provides a comprehensive set of mathematical and utility functions.

### Arithmetic Operations

Standard operators:
- `+` (addition), `-` (subtraction), `*` (multiplication), `/` (division), `^` (power), `MOD` (modulo)

Example:
```basic
a% = 5 + 3
b! = 2.5 * 4
c# = 10 / 3
d% = 7 MOD 3
```

### Math Functions

- **ABS(x)**: Absolute value
- **SQR(x)**: Square root
- **SIN(x), COS(x), TAN(x)**: Trigonometric functions (radians)
- **ATN(x), ASN(x), ACS(x)**: Inverse trig functions
- **EXP(x), LOG(x), LN(x)**: Exponential and logarithm
- **ROUND(x, n)**: Round to n decimal places
- **PI**: Mathematical constant π

Example:
```basic
PRINT ABS(-5)         ' 5
PRINT SQR(16)         ' 4
PRINT SIN(3.14159/2)  ' 1
PRINT PI              ' 3.14159...
```

### Random Numbers

- **RND**: Returns a random float between 0 and 1.
- **RAND(n)**: Returns a random integer from 0 to n-1.
- **RANDOMIZE [seed]**: Initializes the random number generator.

Example:
```basic
RANDOMIZE 42
PRINT RND
PRINT RAND(10)
```

### Type Conversion Functions

- **CINT(x)**: Convert to integer (rounded)
- **CLNG(x)**: Convert to long integer
- **CDBL(x), CSNG(x)**: Convert to double/single precision

Example:
```basic
PRINT CINT(3.7)    ' 4
PRINT CLNG(123.4)  ' 123
```

See the Reference Manual for a full list of built-in functions and their usage.

---

- Arithmetic and math functions
- Random numbers (`RND`, `RAND`, `RANDOMIZE`)
- Type conversion

## 11. Error Handling

FasterBASIC provides structured exception handling, allowing you to catch and respond to errors in your programs.

### TRY, CATCH, FINALLY, THROW

- **TRY**: Begins a block of code to monitor for errors.
- **CATCH**: Handles specific or general errors.
- **FINALLY**: Executes code regardless of whether an error occurred.
- **THROW**: Raises an error intentionally.

Example:
```basic
TRY
    PRINT "Attempting risky operation..."
    IF x% = 0 THEN THROW 10, 42  ' Error code 10, line 42
CATCH 10
    PRINT "Caught error 10: ERR() = "; ERR(); " at line "; ERL()
CATCH
    PRINT "Caught unexpected error: "; ERR()
FINALLY
    PRINT "Cleanup always runs"
END TRY
```

### Error Functions

- **ERR()**: Returns the current error code.
- **ERL()**: Returns the line number where the error occurred.

### Notes

- You can have multiple CATCH blocks for different error codes.
- The FINALLY block is optional but useful for cleanup.
- Use THROW to signal errors from your own code.

---

- `TRY`, `CATCH`, `FINALLY`, `THROW`
- `ERR()`, `ERL()`

## 12. File I/O (Terminal)

FasterBASIC supports reading from and writing to files using simple commands and functions.

### Opening and Closing Files

- **OPEN**: Opens a file for input, output, or append.
  ```basic
  OPEN "data.txt", "r", 1   ' Open for reading on channel 1
  OPEN "output.txt", "w", 2 ' Open for writing on channel 2
  ```
- **CLOSE**: Closes a file channel.
  ```basic
  CLOSE 1
  ```

### Reading and Writing

- **PRINT#**: Writes text to a file.
  ```basic
  PRINT#2, "Hello, file!"
  ```
- **INPUT#**: Reads from a file into a variable.
  ```basic
  INPUT#1, line$
  ```

### File Status Functions

- **EOF(channel)**: Returns TRUE if end of file is reached.
- **EXT(channel)**: Returns the length of the file.
- **PTR(channel)**: Returns the current file pointer position.

Example:
```basic
OPEN "data.txt", "r", 1
WHILE NOT EOF(1)
    INPUT#1, line$
    PRINT line$
WEND
CLOSE 1
```

### File Modes

- `"r"`: Read
- `"w"`: Write (overwrites existing file)
- `"a"`: Append

See the Reference Manual for advanced file operations and additional functions.

---

- Reading and writing files
- File status functions

## 13. Advanced Topics

### User-Defined Types (UDT)

FasterBASIC allows you to define your own structured types using `TYPE` and `END TYPE`. UDTs can contain multiple fields of different types, including strings and arrays.

Example:
```basic
TYPE Person
    Name AS STRING
    Age AS INTEGER
END TYPE

DIM P1 AS Person, P2 AS Person
P1.Name = "Alice"
P1.Age = 30

P2 = P1  ' Struct assignment (copies all fields)
PRINT P2.Name, P2.Age
```

You can also create arrays of UDTs:
```basic
DIM People(10) AS Person
People(0).Name = "Bob"
People(0).Age = 25
```

### Exception Handling Example

```basic
TRY
    PRINT "About to divide..."
    IF divisor% = 0 THEN THROW 100, 20
    result% = 10 / divisor%
CATCH 100
    PRINT "Divide by zero error at line "; ERL()
CATCH
    PRINT "Other error: "; ERR()
FINALLY
    PRINT "Done."
END TRY
```

---

## 14. Appendix

### Reserved Words

A partial list of reserved words in FasterBASIC (see Reference Manual for full list):

```
AND, AS, CALL, CASE, CATCH, DATA, DIM, DO, ELSE, END, ENDIF, ENDSELECT, END SUB, END FUNCTION, ERASE, EXIT, FINALLY, FOR, FUNCTION, GOSUB, GOTO, IF, INPUT, LET, LINE, LOOP, MOD, NEXT, NOT, OF, ON, OR, PRINT, READ, REDIM, REM, REPEAT, RESTORE, RETURN, SELECT, SLEEP, STEP, SUB, THEN, THROW, TO, TRY, UNTIL, WEND, WHILE
```

### Example Programs

#### Hello World

```basic
PRINT "Hello, World!"
END
```

#### Sum of Numbers

```basic
DIM total%
total% = 0
FOR i% = 1 TO 10
    total% = total% + i%
NEXT i%
PRINT "Sum is "; total%
END
```

#### String Slicing

```basic
DIM s$, m$
s$ = "Hello World"
m$ = s$(7 TO 11)
PRINT m$   ' "World"
END
```

#### Exception Handling

```basic
TRY
    PRINT "Risky code"
    THROW 42, 100
CATCH 42
    PRINT "Caught error 42 at line "; ERL()
FINALLY
    PRINT "Always runs"
END TRY
END
```

---

*This concludes the FasterBASIC User Guide (Terminal Edition). For more details, see the Reference Manual or explore the test programs in the `tests/` directory.*

*This guide is maintained by the FasterBASIC Team. For feedback or contributions, please contact the project maintainers.*