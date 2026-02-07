REM Test GOTO to labels inside and outside WHILE loops
DIM i AS INTEGER

REM Test 1: GOTO to label inside WHILE (skip an iteration)
PRINT "Test 1: Skip iteration 3"
i = 1
WHILE i <= 5
    IF i = 3 THEN GOTO skip_print
    PRINT i; " ";
skip_print:
    i = i + 1
WEND
PRINT ""

REM Test 2: GOTO to label outside WHILE (exit loop early)
PRINT "Test 2: Exit at 3"
i = 1
WHILE i <= 10
    PRINT i; " ";
    IF i = 3 THEN GOTO done_loop
    i = i + 1
WEND
done_loop:
PRINT ""

REM Test 3: Multiple labels in different WHILE loops
PRINT "Test 3: Two loops with labels"
i = 1
WHILE i <= 5
    IF i = 3 THEN GOTO skip2
    PRINT i; " ";
skip2:
    i = i + 1
WEND
PRINT ""

i = 10
WHILE i >= 1
    IF i = 7 THEN GOTO skip3
    PRINT i; " ";
skip3:
    i = i - 1
WEND
PRINT ""

PRINT "Done!"
