REM Test WRCH character output function
REM WRCH writes a single character without newline

PRINT "WRCH Character Output Test"
PRINT "=========================="
PRINT ""

PRINT "Test 1: Write individual characters with WRCH"
PRINT "Expected: 'Hello' on one line"
WRCH 72  REM H
WRCH 101 REM e
WRCH 108 REM l
WRCH 108 REM l
WRCH 111 REM o
PRINT ""
PRINT ""

PRINT "Test 2: Build a line character by character"
PRINT "Expected: '12345' on one line"
FOR i = 49 TO 53
    WRCH i
NEXT i
PRINT ""
PRINT ""

PRINT "Test 3: Mix WRCH and PRINT"
PRINT "Line 1: ";
WRCH 65  REM A
WRCH 66  REM B
WRCH 67  REM C
PRINT ""

PRINT "Test 4: Position with LOCATE and use WRCH"
LOCATE 10, 10
WRCH 88  REM X at row 10, col 10
LOCATE 12, 20
WRCH 89  REM Y at row 12, col 20
PRINT ""
LOCATE 15, 0
PRINT "Test complete."
PRINT ""
PRINT "If WRCH works correctly:"
PRINT "  - 'Hello' appears as a single word"
PRINT "  - '12345' appears as a single number"
PRINT "  - X and Y appear at specified positions"
PRINT "  - No extra newlines or scrolling"
