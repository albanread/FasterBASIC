REM Loops Example
REM Demonstrates FOR and WHILE loops in FasterBASIC

PRINT "FOR Loop Example:"
PRINT "Counting from 1 to 10:"
PRINT

FOR i = 1 TO 10
    PRINT i; " ";
NEXT i

PRINT
PRINT

PRINT "Counting by 2s from 0 to 20:"
FOR i = 0 TO 20 STEP 2
    PRINT i; " ";
NEXT i

PRINT
PRINT

PRINT "Countdown from 10 to 1:"
FOR i = 10 TO 1 STEP -1
    PRINT i; " ";
NEXT i

PRINT
PRINT

PRINT "Nested FOR loops (multiplication table):"
FOR row = 1 TO 5
    FOR col = 1 TO 5
        PRINT row * col; " ";
    NEXT col
    PRINT
NEXT row

PRINT

PRINT "WHILE loop example:"
PRINT "Doubling numbers until > 1000:"
DIM n AS INTEGER
n = 1

WHILE n <= 1000
    PRINT n; " ";
    n = n * 2
WEND

PRINT
PRINT

PRINT "DO-WHILE loop example:"
PRINT "Enter numbers (0 to quit):"

DIM value AS INTEGER
DO
    INPUT "Enter a number: ", value
    IF value <> 0 THEN
        PRINT "You entered: "; value
        PRINT "Squared: "; value * value
    END IF
LOOP UNTIL value = 0

PRINT "Thanks for using the loops demo!"
