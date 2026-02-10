REM Test INPUT mode - read from a file we just created
PRINT "=== Testing INPUT Mode ==="
PRINT ""

REM First, create a test file with known content
PRINT "Creating test file..."
OPEN "test_input.txt" FOR OUTPUT AS #1
PRINT #1, "Hello World"
PRINT #1, "Line 2"
PRINT #1, "Line 3"
CLOSE #1
PRINT "  File created"
PRINT ""

REM Now open it for INPUT and read it back
PRINT "Reading file with INPUT mode..."
OPEN "test_input.txt" FOR INPUT AS #1

DIM line1 AS STRING
DIM line2 AS STRING
DIM line3 AS STRING

LINE INPUT #1, line1
LINE INPUT #1, line2
LINE INPUT #1, line3

CLOSE #1

PRINT "  Line 1: "; line1
PRINT "  Line 2: "; line2
PRINT "  Line 3: "; line3
PRINT ""

REM Verify content
IF line1 = "Hello World" THEN
    PRINT "  PASS: Line 1 correct"
ELSE
    PRINT "  FAIL: Line 1 incorrect"
END IF

IF line2 = "Line 2" THEN
    PRINT "  PASS: Line 2 correct"
ELSE
    PRINT "  FAIL: Line 2 incorrect"
END IF

IF line3 = "Line 3" THEN
    PRINT "  PASS: Line 3 correct"
ELSE
    PRINT "  FAIL: Line 3 incorrect"
END IF

PRINT ""
PRINT "=== INPUT Mode Test Complete ==="
