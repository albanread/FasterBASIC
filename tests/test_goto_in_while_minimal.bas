REM Test: GOTO label with nested WHILE inside outer WHILE
DIM i AS INTEGER
DIM j AS INTEGER
i = 1
WHILE i <= 3
    IF i = 2 THEN GOTO skip_inner
    j = 1
    WHILE j <= 2
        PRINT i; ","; j
        j = j + 1
    WEND
skip_inner:
    i = i + 1
WEND
PRINT "done"
END
