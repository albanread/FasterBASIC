REM Test FLUSH, BEGINPAINT, ENDPAINT output batching
REM This test verifies that output batching keywords work correctly
REM and produce the expected visual output.

PRINT "FLUSH / BEGINPAINT / ENDPAINT Test"
PRINT "==================================="
PRINT

REM Test 1: Basic FLUSH
PRINT "Test 1: FLUSH after WRSTR"
PRINT "Expected: 'Hello World' on one line"
WRSTR "Hello "
WRSTR "World"
FLUSH
PRINT
PRINT

REM Test 2: BEGINPAINT / ENDPAINT batching
PRINT "Test 2: BEGINPAINT / ENDPAINT"
PRINT "Expected: 'ABCDE' on one line (written inside paint block)"
BEGINPAINT
WRSTR "A"
WRSTR "B"
WRSTR "C"
WRSTR "D"
WRSTR "E"
ENDPAINT
PRINT
PRINT

REM Test 3: LOCATE inside paint block
PRINT "Test 3: LOCATE + WRSTR inside paint block"
PRINT "Expected: 'X' at column 10, 'Y' at column 20 on the NEXT line"
PRINT "          (row below this text)"

DIM save_row%
save_row = 12

BEGINPAINT
LOCATE 10, save_row
WRSTR "X"
LOCATE 20, save_row
WRSTR "Y"
ENDPAINT
PRINT
PRINT

REM Test 4: COLOR inside paint block
LOCATE 0, 14
PRINT "Test 4: COLOR changes inside paint block"
PRINT "Expected: colored text 'RED GREEN BLUE' below"
BEGINPAINT
LOCATE 0, 16
COLOR 1, 0
WRSTR "RED "
COLOR 2, 0
WRSTR "GREEN "
COLOR 4, 0
WRSTR "BLUE"
COLOR 7, 0
ENDPAINT
PRINT
PRINT

REM Test 5: Nested-style usage (BEGINPAINT is not nestable, second call is a no-op)
LOCATE 0, 18
PRINT "Test 5: Multiple WRSTR calls batched"
PRINT "Expected: '1234567890' on one line"
BEGINPAINT
FOR i = 0 TO 9
    WRSTR STR$(i)
NEXT i
ENDPAINT
PRINT
PRINT

REM Test 6: FLUSH works outside paint mode
LOCATE 0, 21
PRINT "Test 6: Standalone FLUSH"
PRINT "Expected: 'Done!' below"
WRSTR "Done!"
FLUSH
PRINT

PRINT
PRINT "All paint/flush tests complete."
