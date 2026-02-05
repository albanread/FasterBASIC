' test_slice_cow_debug.bas
' Debug version with explicit checks

PRINT "=== Debug: String Assignment and Slice Mutation ==="
PRINT ""

' Test: Does backup$ remain independent when text$ slice is assigned?
DIM text$, backup$

text$ = "Hello World"
PRINT "1. text$ = 'Hello World'"
PRINT "   text$ = '"; text$; "'"

backup$ = text$
PRINT "2. backup$ = text$"
PRINT "   text$ = '"; text$; "'"
PRINT "   backup$ = '"; backup$; "'"

text$(1 TO 5) = "BASIC"
PRINT "3. After text$(1 TO 5) = 'BASIC'"
PRINT "   text$ = '"; text$; "'"
PRINT "   backup$ = '"; backup$; "'"

PRINT ""
PRINT "Expected results:"
PRINT "  text$ should be 'BASIC World'"
PRINT "  backup$ should be 'Hello World'"

PRINT ""
PRINT "Actual results:"
IF text$ = "BASIC World" THEN
    PRINT "  text$ is 'BASIC World' - CORRECT"
ELSE
    PRINT "  text$ is '"; text$; "' - WRONG!"
END IF

IF backup$ = "Hello World" THEN
    PRINT "  backup$ is 'Hello World' - CORRECT (independent)"
ELSE
    PRINT "  backup$ is '"; backup$; "' - BUG (was mutated)"
END IF

PRINT ""
PRINT "DONE"
