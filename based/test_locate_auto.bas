REM Test LOCATE and PRINT interaction (non-interactive)
REM This test verifies that LOCATE and PRINT work correctly together
REM without display corruption

CLS

REM Test 1: Simple LOCATE and PRINT
LOCATE 0, 0
PRINT "Test 1: Top-left corner (0,0)"

LOCATE 5, 10
PRINT "Test 2: Row 5, Col 10"

LOCATE 10, 20
PRINT "Test 3: Row 10, Col 20"

REM Test 2: Draw a box
LOCATE 0, 15
PRINT "+------------------+"
LOCATE 0, 16
PRINT "|   LOCATE TEST    |"
LOCATE 0, 17
PRINT "+------------------+"

REM Test 3: Multiple lines in sequence
LOCATE 0, 19
PRINT "Line 1: This should be on row 19"
LOCATE 0, 20
PRINT "Line 2: This should be on row 20"
LOCATE 0, 21
PRINT "Line 3: This should be on row 21"

REM Test 4: Status line at bottom
LOCATE 0, 23
PRINT "Test complete - all text should be properly positioned"

REM Test 5: Overwrite test (on separate screen)
REM Wait a moment then clear
PRINT ""
PRINT "Press ENTER to test overwrite..."
DIM dummy$ AS STRING
INPUT dummy$

CLS
LOCATE 5, 5
PRINT "AAAAA"
LOCATE 5, 5
PRINT "BBBBB"

LOCATE 0, 10
PRINT "The text at row 5, col 5 should show BBBBB (not AAAAA)"

LOCATE 0, 23
PRINT "Test complete!"
