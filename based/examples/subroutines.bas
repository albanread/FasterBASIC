REM Subroutines Example
REM Demonstrates SUB and FUNCTION definitions in FasterBASIC

REM ============================================================================
REM MAIN PROGRAM
REM ============================================================================

PRINT "Subroutines and Functions Demo"
PRINT "==============================="
PRINT

REM Test simple subroutine
CALL greet("Alice")
CALL greet("Bob")
PRINT

REM Test function
DIM result AS INTEGER
result = add_numbers(5, 7)
PRINT "5 + 7 = "; result
PRINT

REM Test function with strings
DIM full_name$ AS STRING
full_name$ = make_full_name$("John", "Doe")
PRINT "Full name: "; full_name$
PRINT

REM Test math functions
PRINT "Math Functions:"
PRINT "Square of 5: "; square(5)
PRINT "Cube of 3: "; cube(3)
PRINT "Factorial of 5: "; factorial(5)
PRINT

REM Test area calculations
CALL calculate_circle_area(5.0)
CALL calculate_rectangle_area(4.0, 6.0)
PRINT

REM Test max/min functions
PRINT "Max of 10 and 20: "; max(10, 20)
PRINT "Min of 10 and 20: "; min(10, 20)
PRINT

REM Test string functions
PRINT "Is 'hello' palindrome? "; is_palindrome$("hello")
PRINT "Is 'racecar' palindrome? "; is_palindrome$("racecar")
PRINT

PRINT "Demo complete!"

REM ============================================================================
REM SUBROUTINES
REM ============================================================================

SUB greet(name$ AS STRING)
    PRINT "Hello, "; name$; "! Welcome to FasterBASIC!"
END SUB

SUB calculate_circle_area(radius AS DOUBLE)
    DIM area AS DOUBLE
    DIM pi AS DOUBLE
    pi = 3.14159
    area = pi * radius * radius
    PRINT "Circle with radius "; radius; " has area: "; area
END SUB

SUB calculate_rectangle_area(width AS DOUBLE, height AS DOUBLE)
    DIM area AS DOUBLE
    area = width * height
    PRINT "Rectangle "; width; "x"; height; " has area: "; area
END SUB

REM ============================================================================
REM FUNCTIONS
REM ============================================================================

FUNCTION add_numbers(a AS INTEGER, b AS INTEGER) AS INTEGER
    RETURN a + b
END FUNCTION

FUNCTION make_full_name$(first$ AS STRING, last$ AS STRING) AS STRING
    RETURN first$ + " " + last$
END FUNCTION

FUNCTION square(n AS INTEGER) AS INTEGER
    RETURN n * n
END FUNCTION

FUNCTION cube(n AS INTEGER) AS INTEGER
    RETURN n * n * n
END FUNCTION

FUNCTION factorial(n AS INTEGER) AS INTEGER
    IF n <= 1 THEN
        RETURN 1
    ELSE
        RETURN n * factorial(n - 1)
    END IF
END FUNCTION

FUNCTION max(a AS INTEGER, b AS INTEGER) AS INTEGER
    IF a > b THEN
        RETURN a
    ELSE
        RETURN b
    END IF
END FUNCTION

FUNCTION min(a AS INTEGER, b AS INTEGER) AS INTEGER
    IF a < b THEN
        RETURN a
    ELSE
        RETURN b
    END IF
END FUNCTION

FUNCTION is_palindrome$(text$ AS STRING) AS STRING
    DIM i AS INTEGER
    DIM len AS INTEGER
    DIM is_pal AS INTEGER

    len = LEN(text$)
    is_pal = 1

    FOR i = 1 TO len / 2
        IF MID$(text$, i, 1) <> MID$(text$, len - i + 1, 1) THEN
            is_pal = 0
            EXIT FOR
        END IF
    NEXT i

    IF is_pal THEN
        RETURN "Yes"
    ELSE
        RETURN "No"
    END IF
END FUNCTION
