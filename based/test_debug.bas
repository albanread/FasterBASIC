REM Minimal debug test for terminal I/O
REM This shows exactly what LOCATE and PRINT do

PRINT "Debug Test Starting..."
PRINT "Screen should be 80x24"
PRINT ""

REM Test 1: Simple positioning
PRINT "Test 1: Moving cursor to row 5, col 10..."
LOCATE 10, 5
PRINT "AAAAA"

PRINT ""
PRINT "Test 2: Moving cursor to row 7, col 20..."
LOCATE 20, 7
PRINT "BBBBB"

PRINT ""
PRINT "Test 3: Moving cursor to row 10, col 0..."
LOCATE 0, 10
PRINT "CCCCC"

REM Test 4: Drawing a simple box
LOCATE 0, 15
PRINT "+-----+"
LOCATE 0, 16
PRINT "| BOX |"
LOCATE 0, 17
PRINT "+-----+"

REM Test 5: Bottom of screen
LOCATE 0, 23
PRINT "Bottom line (row 23)"

REM Done
LOCATE 0, 22
PRINT "Press ENTER to exit..."
DIM dummy$ AS STRING
INPUT dummy$
