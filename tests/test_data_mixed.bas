REM Test mixed DATA types
REM This tests reading integers, doubles, and strings in mixed order

DATA 42, 3.14159, "PI"
DATA 100, 2.71828, "Euler's number"

DIM num1 AS INTEGER
DIM val1 AS DOUBLE
DIM name1 AS STRING
DIM num2 AS INTEGER
DIM val2 AS DOUBLE
DIM name2 AS STRING

READ num1, val1, name1
READ num2, val2, name2

PRINT "First: "; num1; ", "; val1; ", "; name1
PRINT "Second: "; num2; ", "; val2; ", "; name2

END
