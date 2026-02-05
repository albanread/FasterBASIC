REM Test DATA/READ/RESTORE with labels and line numbers
REM Tests basic READ, RESTORE, RESTORE to label, and RESTORE to line

REM Define DATA with labels and line numbers
DATA 10, 20, 30

NUMBERS_START:
DATA 100, 200, 300

1000 DATA 1000, 2000, 3000

STRINGS_START:
DATA "Hello", "World", "Test"

REM Main program
DIM a AS INTEGER
DIM b AS INTEGER
DIM c AS INTEGER
DIM s AS STRING

PRINT "=== DATA/READ/RESTORE Test ==="
PRINT ""

REM Test 1: Basic READ
PRINT "Test 1: Basic READ"
READ a, b, c
PRINT "First three values: "; a; ", "; b; ", "; c
IF a <> 10 OR b <> 20 OR c <> 30 THEN
    PRINT "ERROR: Expected 10, 20, 30"
    END
END IF
PRINT "PASS: Basic READ"
PRINT ""

REM Test 2: RESTORE (back to start)
PRINT "Test 2: RESTORE to start"
RESTORE
READ a
PRINT "After RESTORE, first value: "; a
IF a <> 10 THEN
    PRINT "ERROR: Expected 10 after RESTORE"
    END
END IF
PRINT "PASS: RESTORE to start"
PRINT ""

REM Test 3: RESTORE to label
PRINT "Test 3: RESTORE NUMBERS_START"
RESTORE NUMBERS_START
READ a, b, c
PRINT "Values at NUMBERS_START: "; a; ", "; b; ", "; c
IF a <> 100 OR b <> 200 OR c <> 300 THEN
    PRINT "ERROR: Expected 100, 200, 300"
    END
END IF
PRINT "PASS: RESTORE to label"
PRINT ""

REM Test 4: RESTORE to line number
PRINT "Test 4: RESTORE 1000"
RESTORE 1000
READ a, b, c
PRINT "Values at line 1000: "; a; ", "; b; ", "; c
IF a <> 1000 OR b <> 2000 OR c <> 3000 THEN
    PRINT "ERROR: Expected 1000, 2000, 3000"
    END
END IF
PRINT "PASS: RESTORE to line number"
PRINT ""

REM Test 5: READ strings
PRINT "Test 5: READ strings"
RESTORE STRINGS_START
READ s
PRINT "First string: '"; s; "'"
IF s <> "Hello" THEN
    PRINT "ERROR: Expected 'Hello'"
    END
END IF
PRINT "PASS: READ strings"
PRINT ""

REM Test 6: Multiple READs with RESTORE between
PRINT "Test 6: Multiple operations"
RESTORE
READ a
READ b
RESTORE
READ c
PRINT "a="; a; " b="; b; " c="; c
IF a <> 10 OR b <> 20 OR c <> 10 THEN
    PRINT "ERROR: Expected 10, 20, 10"
    END
END IF
PRINT "PASS: Multiple operations"
PRINT ""

PRINT "=== All DATA/READ/RESTORE Tests PASSED ==="
END
