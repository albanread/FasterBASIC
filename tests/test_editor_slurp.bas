REM Test editor-style usage of SLURP and SPIT
REM Simpler test to verify basic functionality

PRINT "Editor SLURP/SPIT Test"
PRINT "======================"
PRINT

REM Test 1: Create a simple BASIC program with SPIT
PRINT "Creating test program..."
program$ = "PRINT " + CHR$(34) + "Hello from test!" + CHR$(34) + CHR$(10)
program$ = program$ + "FOR i = 1 TO 5" + CHR$(10)
program$ = program$ + "  PRINT i" + CHR$(10)
program$ = program$ + "NEXT i" + CHR$(10)

SPIT "test_program.bas", program$
PRINT "Written test_program.bas"
PRINT

REM Test 2: Read it back
PRINT "Reading back..."
loaded$ = SLURP("test_program.bas")
PRINT "Content:"
PRINT loaded$
PRINT

REM Test 3: Verify
IF loaded$ = program$ THEN
    PRINT "SUCCESS: Content matches!"
ELSE
    PRINT "ERROR: Content differs"
    PRINT "Expected length: "; LEN(program$)
    PRINT "Got length: "; LEN(loaded$)
ENDIF
PRINT

REM Test 4: Count lines (editor operation)
PRINT "Counting lines..."
line_count = 0
FOR i = 1 TO LEN(loaded$)
    IF MID$(loaded$, i, 1) = CHR$(10) THEN
        line_count = line_count + 1
    ENDIF
NEXT i
PRINT "Lines found: "; line_count
PRINT

PRINT "Test complete!"
