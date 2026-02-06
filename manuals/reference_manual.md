compact_repo/manuals/reference_manual.md
# FasterBASIC Reference Manual

**Version:** Terminal Edition  
**Authorship:** FasterBASIC Team (Head Technical Writer)  
**License:** See project repository

---

## About This Manual

This reference manual provides a comprehensive, objective, and technical description of the FasterBASIC language as implemented in the single-threaded, terminal-only edition. It covers all core language features, commands, statements, functions, and syntax available in the base system. Graphics, sound, and event-driven extensions are not included here and will be documented separately.

---

## Table of Contents

1. [Introduction](#introduction)
2. [Lexical Structure](#lexical-structure)
   - Tokens and Identifiers
   - Literals
   - Comments
3. [Syntax Reference](#syntax-reference)
   - Program Structure
   - Statements and Expressions
4. [Commands and Statements](#commands-and-statements)
   ## 4. Commands and Statements

   ### 4.1 Control Flow Commands

   This section lists all control flow commands, grouped by category and ordered alphabetically within the category.

   ---

   #### CALL

   **Syntax:**  
   `CALL subroutineName [(arguments)]`

   **Description:**  
   Calls a user-defined subroutine or function by name.

   **Example:**  
   ```basic
   CALL PrintGreeting("Alice")
   ```

   ---

   #### CATCH

   **Syntax:**  
   `CATCH [errorCode]`

   **Description:**  
   Begins a block to handle a specific error code or any error if no code is given. Used within TRY...END TRY blocks.

   **Example:**  
   ```basic
   TRY
       ' ...
   CATCH 10
       PRINT "Caught error 10"
   CATCH
       PRINT "Caught any error"
   END TRY
   ```

   ---

   #### DO

   **Syntax:**  
   `DO [WHILE condition]`  
   `DO [UNTIL condition]`

   **Description:**  
   Begins a loop that continues until a condition is met. Must be paired with LOOP.

   **Example:**  
   ```basic
   DO WHILE x% < 10
       x% = x% + 1
   LOOP
   ```

   ---

   #### ELSE

   **Syntax:**  
   `ELSE`

   **Description:**  
   Begins the alternative branch of an IF...THEN...ELSE block.

   **Example:**  
   ```basic
   IF x% > 0 THEN
       PRINT "Positive"
   ELSE
       PRINT "Zero or negative"
   END IF
   ```

   ---

   #### END

   **Syntax:**  
   `END`

   **Description:**  
   Terminates program execution.

   **Example:**  
   ```basic
   PRINT "Done"
   END
   ```

   ---

   #### END IF

   **Syntax:**  
   `END IF`

   **Description:**  
   Marks the end of an IF...THEN...ELSE block.

   ---

   #### END SELECT

   **Syntax:**  
   `END SELECT`

   **Description:**  
   Marks the end of a SELECT CASE block.

   ---

   #### EXIT

   **Syntax:**  
   `EXIT [FOR|FUNCTION|SUB|DO|WHILE|REPEAT]`

   **Description:**  
   Exits the nearest enclosing loop, function, or subroutine.

   **Example:**  
   ```basic
   FOR i% = 1 TO 10
       IF i% = 5 THEN EXIT FOR
   NEXT i%
   ```

   ---

   #### EXIT FOR

   **Syntax:**  
   `EXIT FOR`

   **Description:**  
   Exits the nearest enclosing FOR loop.

   ---

   ### 4.3 Input/Output Commands

   This section lists all commands related to terminal and file input/output, in alphabetical order.

   ---

   #### INPUT

   **Syntax:**  
   `INPUT ["prompt", ] variable`

   **Description:**  
   Reads a value from the user and stores it in a variable. An optional prompt can be displayed.

   **Example:**  
   ```basic
   INPUT "Enter your name: ", name$
   ```

   ---

   #### INPUT#

   **Syntax:**  
   `INPUT#channel, variable`

   **Description:**  
   Reads a value from an open file channel into a variable.

   **Example:**  
   ```basic
   INPUT#1, line$
   ```

   ---

   #### LINE INPUT

   **Syntax:**  
   `LINE INPUT ["prompt", ] variable`

   **Description:**  
   Reads an entire line of input from the user, including spaces and punctuation. An optional prompt can be displayed.

   **Example:**  
   ```basic
   LINE INPUT "Type a sentence: ", sentence$
   ```

   ---

   #### PRINT

   **Syntax:**  
   `PRINT [expression-list]`

   **Description:**  
   Outputs text or values to the terminal. Multiple values can be separated by commas or semicolons.

   **Example:**  
   ```basic
   PRINT "Hello, World!"
   PRINT "A = "; a%; ", B = "; b!
   ```

   ---

   #### PRINT#

   **Syntax:**  
   `PRINT#channel, expression-list`

   **Description:**  
   Writes text or values to an open file channel.

   **Example:**  
   ```basic
   PRINT#2, "Hello, file!"
   ```

   ---

   #### PRINTHEX

   **Syntax:**  
   `PRINTHEX value`

   **Description:**  
   Prints an integer or pointer value as hexadecimal (useful for debugging).

   **Example:**  
   ```basic
   PRINTHEX 255
   ```
   
   ---

   ### 4.4 File I/O Commands

   This section lists all commands related to file input/output, in alphabetical order.

   ---

   #### BGET

   **Syntax:**  
   `BGET(fileNumber)`

   **Description:**  
   Reads a single byte from the specified file number. Returns the byte as an integer.

   **Example:**  
   ```basic
   byte% = BGET(1)
   ```

   ---

   #### BPUT

   **Syntax:**  
   `BPUT fileNumber, byte`

   **Description:**  
   Writes a single byte to the specified file number.

   **Example:**  
   ```basic
   BPUT 1, 65
   ```

   ---

   #### CLOSE

   **Syntax:**  
   `CLOSE channel`

   **Description:**  
   Closes the specified file channel.

   **Example:**  
   ```basic
   CLOSE 1
   ```

   ---

   #### OPEN

   **Syntax:**  
   `OPEN "filename", "mode", channel`

   **Description:**  
   Opens a file for input, output, or append on the specified channel.  
   Modes: `"r"` (read), `"w"` (write), `"a"` (append).

   **Example:**  
   ```basic
   OPEN "data.txt", "r", 1
   OPEN "output.txt", "w", 2
   ```

   ---

   #### OPENIN

   **Syntax:**  
   `OPENIN("filename")`

   **Description:**  
   Opens a file for input only. Returns a file number.

   **Example:**  
   ```basic
   fn% = OPENIN("input.txt")
   ```

   ---

   #### OPENOUT

   **Syntax:**  
   `OPENOUT("filename")`

   **Description:**  
   Opens a file for output only. Returns a file number.

   **Example:**  
   ```basic
   fn% = OPENOUT("output.txt")
   ```

   ---

   #### OPENUP

   **Syntax:**  
   `OPENUP("filename")`

   **Description:**  
   Opens a file for read/write. Returns a file number.

   **Example:**  
   ```basic
   fn% = OPENUP("data.txt")
   ```

   ---

   #### PTRSET

   **Syntax:**  
   `PTRSET fileNumber, position`

   **Description:**  
   Sets the file pointer position for the specified file number.

   **Example:**  
   ```basic
   PTRSET 1, 100
   ```

   ---

   ### 4.5 Miscellaneous/System Commands

   This section lists miscellaneous and system-related commands, in alphabetical order.

   ---

   #### END

   **Syntax:**  
   `END`

   **Description:**  
   Terminates program execution immediately.

   **Example:**  
   ```basic
   PRINT "Done"
   END
   ```

   ---

   #### REM

   **Syntax:**  
   `REM comment text`  
   `' comment text`

   **Description:**  
   Introduces a comment. The rest of the line is ignored by the compiler.

   **Example:**  
   ```basic
   REM This is a comment
   ' This is also a comment
   ```

   ---

   #### SLEEP

   **Syntax:**  
   `SLEEP seconds`

   **Description:**  
   Pauses execution for the specified number of seconds.

   **Example:**  
   ```basic
   SLEEP 2
   ```

   ---

   #### SYSTEM

   **Syntax:**  
   `SYSTEM`

   **Description:**  
   (If implemented) Terminates the program and returns control to the operating system. Equivalent to END in most terminal editions.

   ---

   #### TIMER

   **Syntax:**  
   `TIMER`

   **Description:**  
   Returns the elapsed time in seconds since the program started.

   **Example:**  
   ```basic
   PRINT "Elapsed time: "; TIMER
   ```

   ---

  ## 5. Functions

  ### 5.1 Math Functions

  This section lists all built-in math functions, in alphabetical order. All functions can be used in expressions and assignments.

  ---

  #### ABS

  **Syntax:**  
  `ABS(x)`

  **Description:**  
  Returns the absolute value of `x`.

  **Example:**  
  ```basic
  PRINT ABS(-5)   ' 5
  ```

  ---

  #### ACS / ACOS

  **Syntax:**  
  `ACS(x)`  
  `ACOS(x)`

  **Description:**  
  Returns the arc-cosine (inverse cosine) of `x` in radians.

  ---

  #### ACOSH

  **Syntax:**  
  `ACOSH(x)`

  **Description:**  
  Returns the inverse hyperbolic cosine of `x`.

  ---

  #### ASN / ASIN

  **Syntax:**  
  `ASN(x)`  
  `ASIN(x)`

  **Description:**  
  Returns the arc-sine (inverse sine) of `x` in radians.

  ---

  #### ASINH

  **Syntax:**  
  `ASINH(x)`

  **Description:**  
  Returns the inverse hyperbolic sine of `x`.

  ---

  #### ATAN2

  **Syntax:**  
  `ATAN2(y, x)`

  **Description:**  
  Returns the arctangent of `y/x` in radians, using the signs of both arguments to determine the quadrant.

  ---

  #### ATN / ATAN

  **Syntax:**  
  `ATN(x)`  
  `ATAN(x)`

  **Description:**  
  Returns the arctangent (inverse tangent) of `x` in radians.

  ---

  #### ATANH

  **Syntax:**  
  `ATANH(x)`

  **Description:**  
  Returns the inverse hyperbolic tangent of `x`.

  ---

  #### CEIL

  **Syntax:**  
  `CEIL(x)`

  **Description:**  
  Returns the smallest integer greater than or equal to `x`.

  ---

  #### CLAMP

  **Syntax:**  
  `CLAMP(x, min, max)`

  **Description:**  
  Restricts `x` to the range `[min, max]`.

  ---

  #### COS

  **Syntax:**  
  `COS(x)`

  **Description:**  
  Returns the cosine of `x` (in radians).

  ---

  #### COSH

  **Syntax:**  
  `COSH(x)`

  **Description:**  
  Returns the hyperbolic cosine of `x`.

  ---

  #### DEG

  **Syntax:**  
  `DEG(x)`

  **Description:**  
  Converts radians to degrees.

  ---

  #### EXP

  **Syntax:**  
  `EXP(x)`

  **Description:**  
  Returns `e` raised to the power of `x`.

  ---

  #### EXP2

  **Syntax:**  
  `EXP2(x)`

  **Description:**  
  Returns `2` raised to the power of `x`.

  ---

  #### EXPM1

  **Syntax:**  
  `EXPM1(x)`

  **Description:**  
  Returns `e^x - 1` (exponential minus one).

  ---

  #### FACT

  **Syntax:**  
  `FACT(n)`

  **Description:**  
  Returns the factorial of `n` (for non-negative integers).

  ---

  #### FIX

  **Syntax:**  
  `FIX(x)`

  **Description:**  
  Truncates `x` toward zero.

  ---

  #### FLOOR

  **Syntax:**  
  `FLOOR(x)`

  **Description:**  
  Returns the largest integer less than or equal to `x`.

  ---

  #### FMOD

  **Syntax:**  
  `FMOD(x, y)`

  **Description:**  
  Returns the floating-point remainder of `x / y`.

  ---

  #### FRAC

  **Syntax:**  
  `FRAC(x)`

  **Description:**  
  Returns the fractional part of `x`.

  ---

  #### FMA

  **Syntax:**  
  `FMA(x, y, z)`

  **Description:**  
  Returns the fused multiply-add of `x * y + z`.

  ---

  #### FMAX

  **Syntax:**  
  `FMAX(a, b)`

  **Description:**  
  Returns the maximum of `a` and `b`.

  ---

  #### FMIN

  **Syntax:**  
  `FMIN(a, b)`

  **Description:**  
  Returns the minimum of `a` and `b`.

  ---

  #### HEX2DEC

  **Syntax:**  
  `HEX2DEC(hexStr$)`

  **Description:**  
  Converts a hexadecimal string to a decimal integer.

  ---

  #### HYPOT

  **Syntax:**  
  `HYPOT(x, y)`

  **Description:**  
  Returns the length of the hypotenuse of a right triangle with sides `x` and `y`.

  ---

  #### INT

  **Syntax:**  
  `INT(x)`

  **Description:**  
  Returns the integer part of `x` (rounded toward negative infinity).

  ---

  #### LCM

  **Syntax:**  
  `LCM(a, b)`

  **Description:**  
  Returns the least common multiple of `a` and `b`.

  ---

  #### LGAMMA

  **Syntax:**  
  `LGAMMA(x)`

  **Description:**  
  Returns the natural logarithm of the absolute value of the gamma function of `x`.

  ---

  #### LN

  **Syntax:**  
  `LN(x)`

  **Description:**  
  Returns the natural logarithm of `x`.

  ---

  #### LOG

  **Syntax:**  
  `LOG(x)`

  **Description:**  
  Returns the natural logarithm of `x`.

  ---

  #### LOG10

  **Syntax:**  
  `LOG10(x)`

  **Description:**  
  Returns the base-10 logarithm of `x`.

  ---

  #### LOG1P

  **Syntax:**  
  `LOG1P(x)`

  **Description:**  
  Returns the natural logarithm of `1 + x`.

  ---

  #### MAX

  **Syntax:**  
  `MAX(a, b)`

  **Description:**  
  Returns the maximum of `a` and `b`.

  ---

  #### MIN

  **Syntax:**  
  `MIN(a, b)`

  **Description:**  
  Returns the minimum of `a` and `b`.

  ---

  #### MOD

  **Syntax:**  
  `MOD(x, y)`

  **Description:**  
  Returns the remainder of `x / y`.

  ---

  #### NORMCDF

  **Syntax:**  
  `NORMCDF(x)`

  **Description:**  
  Returns the cumulative distribution function of the standard normal distribution at `x`.

  ---

  #### NORMPDF

  **Syntax:**  
  `NORMPDF(x)`

  **Description:**  
  Returns the probability density function of the standard normal distribution at `x`.

  ---

  #### PERM

  **Syntax:**  
  `PERM(n, k)`

  **Description:**  
  Returns the number of permutations of `n` items taken `k` at a time.

  ---

  #### PI

  **Syntax:**  
  `PI`

  **Description:**  
  Returns the mathematical constant π.

  ---

  #### PMT

  **Syntax:**  
  `PMT(rate, nper, pv)`

  **Description:**  
  Returns the payment for a loan based on constant payments and a constant interest rate.

  ---

  #### POW

  **Syntax:**  
  `POW(x, y)`

  **Description:**  
  Returns `x` raised to the power of `y`.

  ---

  #### RAD

  **Syntax:**  
  `RAD(x)`

  **Description:**  
  Converts degrees to radians.

  ---

  #### RAND

  **Syntax:**  
  `RAND(n)`

  **Description:**  
  Returns a random integer from 0 to `n-1`.

  ---

  #### RANDOMIZE

  **Syntax:**  
  `RANDOMIZE [seed]`

  **Description:**  
  Initializes the random number generator with an optional seed.

  ---

  #### REMAINDER

  **Syntax:**  
  `REMAINDER(x, y)`

  **Description:**  
  Returns the IEEE remainder of `x / y`.

  ---

  #### RND

  **Syntax:**  
  `RND`

  **Description:**  
  Returns a random floating-point number between 0 and 1.

  ---

  #### ROUND

  **Syntax:**  
  `ROUND(x, places)`

  **Description:**  
  Rounds `x` to the specified number of decimal places.

  ---

  #### SGN

  **Syntax:**  
  `SGN(x)`

  **Description:**  
  Returns the sign of `x` (-1, 0, or 1).

  ---

  #### SIGMOID

  **Syntax:**  
  `SIGMOID(x)`

  **Description:**  
  Returns the logistic sigmoid of `x`.

  ---

  #### SIN

  **Syntax:**  
  `SIN(x)`

  **Description:**  
  Returns the sine of `x` (in radians).

  ---

  #### SINH

  **Syntax:**  
  `SINH(x)`

  **Description:**  
  Returns the hyperbolic sine of `x`.

  ---

  #### SQR

  **Syntax:**  
  `SQR(x)`

  **Description:**  
  Returns the square root of `x`.

  ---

  #### SQUARE

  **Syntax:**  
  `SQUARE(x)`

  **Description:**  
  Returns `x` squared.

  ---

  #### TAN

  **Syntax:**  
  `TAN(x)`

  **Description:**  
  Returns the tangent of `x` (in radians).

  ---

  #### TANH

  **Syntax:**  
  `TANH(x)`

  **Description:**  
  Returns the hyperbolic tangent of `x`.

  ---

  #### TGAMMA

  **Syntax:**  
  `TGAMMA(x)`

  **Description:**  
  Returns the gamma function of `x`.

  ---

  #### TRUNC

  **Syntax:**  
  `TRUNC(x)`

  **Description:**  
  Truncates `x` toward zero.

  ---

   #### EXIT FUNCTION

   **Syntax:**  
   `EXIT FUNCTION`

   **Description:**  
   Exits the current FUNCTION immediately.

   ---

   #### EXIT SUB

   **Syntax:**  
   `EXIT SUB`

   **Description:**  
   Exits the current SUB immediately.

   ---

   #### FINALLY

   **Syntax:**  
   `FINALLY`

   **Description:**  
   Begins a block that always executes after TRY/CATCH blocks, regardless of errors.

   ---

   #### FOR

   **Syntax:**  
   `FOR variable = start TO end [STEP increment]`  
   `...`  
   `NEXT [variable]`

   **Description:**  
   Begins a counted loop.

   **Example:**  
   ```basic
   FOR i% = 1 TO 5
       PRINT i%
   NEXT i%
   ```

   ---

   #### GOSUB

   **Syntax:**  
   `GOSUB label`

   **Description:**  
   Calls a subroutine at the specified label. Returns with RETURN.

   **Example:**  
   ```basic
   GOSUB PrintHeader
   ' ...
   RETURN

   PrintHeader:
       PRINT "Header"
       RETURN
   ```

   ---

   #### GOTO

   **Syntax:**  
   `GOTO label`

   **Description:**  
   Jumps to the specified label.

   ---

   #### IF

   **Syntax:**  
   `IF condition THEN [statements] [ELSE [statements]]`  
   `IF condition THEN ... END IF`

   **Description:**  
   Conditional execution of statements.

   **Example:**  
   ```basic
   IF x% > 0 THEN
       PRINT "Positive"
   ELSE
       PRINT "Zero or negative"
   END IF
   ```

   ---

   #### LOOP

   **Syntax:**  
   `LOOP [WHILE condition]`  
   `LOOP [UNTIL condition]`

   **Description:**  
   Ends a DO loop.

   ---

   #### NEXT

   **Syntax:**  
   `NEXT [variable]`

   **Description:**  
   Ends a FOR loop and increments the loop variable.

   ---

   #### ON ERROR

   **Syntax:**  
   `ON ERROR GOTO label`

   **Description:**  
   (Not implemented in all versions; see TRY/CATCH for structured error handling.)

   ---

   #### REPEAT

   **Syntax:**  
   `REPEAT ... UNTIL condition`

   **Description:**  
   Begins a loop that executes at least once and continues until the condition is true.

   **Example:**  
   ```basic
   REPEAT
       PRINT "Repeating"
       x% = x% - 1
   UNTIL x% = 0
   ```

   ---

   #### RETURN

   **Syntax:**  
   `RETURN`

   **Description:**  
   Returns from a GOSUB subroutine.

   ---

   #### SELECT CASE

   **Syntax:**  
   `SELECT CASE expression`  
   `CASE value`  
   `CASE ELSE`  
   `END SELECT`

   **Description:**  
   Multi-way branching based on the value of an expression.

   **Example:**  
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

   ---

   #### SLEEP

   **Syntax:**  
   `SLEEP seconds`

   **Description:**  
   Pauses execution for the specified number of seconds.

   ---

   #### STEP

   **Syntax:**  
   `FOR variable = start TO end STEP increment`

   **Description:**  
   Specifies the increment for a FOR loop.

   ---

   #### THEN

   **Syntax:**  
   `IF condition THEN [statements]`

   **Description:**  
   Introduces the statements to execute if the IF condition is true.

   ---

   #### THROW

   **Syntax:**  
   `THROW errorCode, lineNumber`

   **Description:**  
   Raises an error with the specified code and line number.

   ---

   #### TO

   **Syntax:**  
   `FOR variable = start TO end`  
   `DIM array(start TO end)`

   **Description:**  
   Specifies the end value in FOR loops and array bounds.

   ---

   #### TRY

   **Syntax:**  
   `TRY ... CATCH ... [FINALLY ...] END TRY`

   **Description:**  
   Begins a block for structured exception handling.

   ---

   #### UNTIL

   **Syntax:**  
   `DO ... LOOP UNTIL condition`  
   `REPEAT ... UNTIL condition`

   **Description:**  
   Specifies the loop exit condition.

   ---

   #### WEND

   **Syntax:**  
   `WHILE condition ... WEND`

   **Description:**  
   Ends a WHILE loop.

   ---

   #### WHILE

   **Syntax:**  
   `WHILE condition ... WEND`

   **Description:**  
   Begins a loop that continues while the condition is true.

   ---

5. [Functions](#functions)
   - Math Functions (alphabetical)
   - String Functions (alphabetical)
   - File Functions (alphabetical)
   - Type Conversion/Utility Functions (alphabetical)
   - System/Other Functions (alphabetical)
6. [Data Types](#data-types)
   - Numeric Types
   - String Types
   - Arrays
   - User-Defined Types (UDTs)
7. [Error Handling](#error-handling)
   - TRY, CATCH, FINALLY, THROW
   - Error Codes and Handling
8. [Appendices](#appendices)
    - Reserved Keywords
    - Operator Precedence
    - Type Suffixes
    - Compatibility Notes

---

### 4.2 Data/Variable Management Commands

This section lists all commands related to data storage, variable and array management, and data statements, in alphabetical order.

---

#### DATA

**Syntax:**  
`DATA value1, value2, ...`

**Description:**  
Stores a list of constant values in the program for later retrieval using READ.

**Example:**  
```basic
DATA 10, 20, 30
READ a%, b%, c%
```

---

#### DIM

**Syntax:**  
`DIM variable[(bounds)] [AS type]`

**Description:**  
Declares one or more variables or arrays. Arrays can have specified bounds.

**Example:**  
```basic
DIM x%, y!, name$
DIM numbers%(10)
DIM matrix%(1 TO 5, 1 TO 5)
```

---

#### ERASE

**Syntax:**  
`ERASE arrayName`

**Description:**  
Clears the contents of an array, releasing its memory.

**Example:**  
```basic
ERASE numbers%
```

---

#### LET

**Syntax:**  
`LET variable = expression`

**Description:**  
Assigns a value to a variable. The LET keyword is optional; assignment can be done with or without it.

**Example:**  
```basic
LET x% = 5
y! = 3.14
```

---

#### READ

**Syntax:**  
`READ variable1, variable2, ...`

**Description:**  
Reads values from DATA statements into variables, in order.

**Example:**  
```basic
DATA 1, 2, 3
READ a%, b%, c%
```

---

#### REDIM

**Syntax:**  
`REDIM variable(bounds)`

**Description:**  
Redimensions an existing array, optionally preserving its contents.

**Example:**  
```basic
REDIM numbers%(20)
REDIM PRESERVE numbers%(30)
```

---

#### REM

**Syntax:**  
`REM comment text`  
`' comment text`

**Description:**  
Introduces a comment. The rest of the line is ignored by the compiler.

**Example:**  
```basic
REM This is a comment
' This is also a comment
```

---

#### RESTORE

**Syntax:**  
`RESTORE [label]`

**Description:**  
Resets the DATA pointer to the start or to a labeled DATA statement.

**Example:**  
```basic
RESTORE
READ x%
```

---

#### TYPE / END TYPE

**Syntax:**  
`TYPE typeName ... END TYPE`

**Description:**  
Defines a user-defined type (UDT) with one or more fields.

**Example:**  
```basic
TYPE Person
    Name AS STRING
    Age AS INTEGER
END TYPE

DIM P AS Person
P.Name = "Alice"
P.Age = 30
```

---

---

## 1. Introduction

This manual provides a comprehensive, objective, and technical reference for the FasterBASIC language (terminal edition). It is organized by category for ease of use, with commands and functions listed alphabetically within each category.

- **Scope:** Covers all core language features, commands, statements, and functions available in the single-threaded, terminal-only edition of FasterBASIC. Graphics, sound, and event-driven extensions are not included here.
- **Conventions:** Syntax is shown in code blocks. Optional parameters are indicated in brackets. Keywords are in uppercase for clarity, but the language is case-insensitive.
- **Versioning:** This manual matches the current implementation as of [2025]. For updates, see the project repository.


## 2. Lexical Structure

FasterBASIC source code is composed of tokens, which include keywords, identifiers, literals, operators, and punctuation.

### Tokens and Identifiers

- **Identifiers** are names for variables, arrays, functions, subroutines, and user-defined types.
  - Must start with a letter (A-Z, a-z).
  - May contain letters, digits (0-9), and underscores.
  - Are case-insensitive: `Total%` and `total%` refer to the same variable.
  - May have a type suffix (`%`, `!`, `#`, `$`, `&`).

### Numeric and String Literals

- **Numeric literals**: Integers (`42`), floats (`3.14`), scientific notation (`1.2E3`), hexadecimal (`&HFF`), octal (`&O77`), binary (`&B1010`).
- **String literals**: Enclosed in double quotes (`"Hello, World!"`).

### Comment Syntax

- Use `REM` or a single quote (`'`) to start a comment.
  - `REM This is a comment`
  - `' This is also a comment`
- Comments can appear on their own line or after code.

### Whitespace and Line Endings

- Whitespace (spaces, tabs) is ignored except within string literals.
- Each statement typically appears on its own line, but multiple statements can be separated by colons (`:`).
- Lines end with a newline character.


## 3. Syntax Reference

This section describes the formal structure of FasterBASIC programs, including statements, expressions, blocks, and indentation.

### Program Structure

A FasterBASIC program consists of a sequence of statements, declarations, and (optionally) function or subroutine definitions. The program is executed from the top down, unless control flow statements alter the order.

Example:
```basic
REM Main program
DIM x%
x% = 10
PRINT x%
END
```

### Statements

- Each statement typically appears on its own line.
- Multiple statements can be placed on a single line using a colon (`:`) as a separator:
  ```basic
  x% = 1 : y% = 2 : PRINT x%, y%
  ```
- Statements may include assignments, control flow, I/O, declarations, and calls to functions or subroutines.

### Expressions

- Expressions are combinations of variables, literals, operators, and function calls that produce a value.
- Used in assignments, conditions, function arguments, etc.
  ```basic
  total% = a% + b% * 2
  IF x% > 10 THEN PRINT "Large"
  ```

### Blocks and Indentation

- Blocks are groups of statements enclosed by keywords (e.g., `IF ... END IF`, `FOR ... NEXT`, `FUNCTION ... END FUNCTION`).
- Indentation is not required by the compiler but is strongly recommended for readability.
- Example:
  ```basic
  IF x% > 0 THEN
      PRINT "Positive"
  ELSE
      PRINT "Zero or negative"
  END IF
  ```

### End of Program

- The `END` statement marks the end of execution. If omitted, execution stops after the last statement.


- Program structure and file layout
- Statement and expression grammar
- Block structure and indentation

## 4. Commands and Statements

- Alphabetical listing of all commands and statements
- Syntax, parameters, and usage notes for each
- Examples where appropriate

## 5. Functions

- Complete list of built-in functions (math, string, system, file)
- Return types and parameter details
- Usage notes and edge cases

## 6. Data Types

- Numeric types: INTEGER, FLOAT, DOUBLE, etc.
- String types and handling
- Arrays: declaration, access, and bounds
- User-Defined Types (UDTs): structure and usage

## 7. Control Flow Constructs

- IF...THEN...ELSE
- FOR...NEXT, WHILE...WEND, DO...LOOP, REPEAT...UNTIL
- SELECT CASE
- GOTO, GOSUB, RETURN
- SLEEP, CALL, EXIT

## 8. Error Handling

- TRY, CATCH, FINALLY, THROW
- ERR(), ERL(), and error codes
- Exception handling patterns

## 9. File I/O

- File commands: OPEN, CLOSE, PRINT#, INPUT#, etc.
- File functions: EOF, EXT, PTR, etc.
- File modes and channel management

## 10. Appendices

- Reserved keywords (alphabetical)
- Operator precedence table
- Type suffixes and conventions
- Compatibility notes (with other BASIC dialects)

---

*This manual is maintained by the FasterBASIC Team. For questions, contributions, or errata, please refer to the project repository.*
