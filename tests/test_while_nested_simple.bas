REM Simple nested WHILE test
DIM arr(10) AS INT
DIM i AS INT
DIM j AS INT

i = 1
WHILE i <= 3
    PRINT "Outer: "; i
    j = 1
    WHILE j <= 3
        PRINT "  Inner: "; j
        j = j + 1
    WEND
    i = i + 1
WEND
PRINT "Done"
