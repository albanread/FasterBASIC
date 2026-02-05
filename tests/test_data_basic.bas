REM Test basic DATA/READ functionality
REM This tests reading integers and strings from DATA statements

DATA 10, 20, 30
DATA "Hello", "World"

DIM a AS INTEGER
DIM b AS INTEGER
DIM c AS INTEGER
DIM s1 AS STRING
DIM s2 AS STRING

READ a, b, c
READ s1, s2

PRINT "Integers: "; a; ", "; b; ", "; c
PRINT "Strings: "; s1; ", "; s2

END
