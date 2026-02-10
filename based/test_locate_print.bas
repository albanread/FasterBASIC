REM Test LOCATE and PRINT interaction
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

REM Test 3: Status line at bottom
LOCATE 0, 23
PRINT "Press ENTER to continue..."

REM Wait for keypress
DIM dummy$ AS STRING
INPUT dummy$

REM Test 4: Overwrite test
CLS
LOCATE 5, 5
PRINT "AAAAA"
LOCATE 5, 5
PRINT "BBBBB"

LOCATE 0, 10
PRINT "The line above should show BBBBB (not AAAAA)"

LOCATE 0, 23
PRINT "Press ENTER to exit..."
INPUT dummy$

CLS
LOCATE 0, 0
PRINT "Test complete!"
