REM Test that arrays still work after hashmap changes
DIM numbers(10) AS INTEGER
DIM names(5) AS STRING

numbers(0) = 10
numbers(1) = 20
numbers(2) = 30

names(0) = "Alice"
names(1) = "Bob"
names(2) = "Charlie"

PRINT "Numbers:"
PRINT numbers(0)
PRINT numbers(1)
PRINT numbers(2)

PRINT ""
PRINT "Names:"
PRINT names(0)
PRINT names(1)
PRINT names(2)

REM Test 2D array
DIM grid(3, 3) AS INTEGER
grid(0, 0) = 1
grid(0, 1) = 2
grid(1, 0) = 3
grid(1, 1) = 4

PRINT ""
PRINT "Grid:"
PRINT grid(0, 0); " "; grid(0, 1)
PRINT grid(1, 0); " "; grid(1, 1)

END
