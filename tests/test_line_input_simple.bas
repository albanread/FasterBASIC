REM Very simple LINE INPUT test
PRINT "Creating test file..."

REM Create a file with known content
OPEN "test_simple.txt" FOR OUTPUT AS #1
PRINT #1, "First line"
PRINT #1, "Second line"
PRINT #1, "Third line"
CLOSE #1
PRINT "File created"
PRINT ""

REM Read it back with LINE INPUT
PRINT "Reading with LINE INPUT..."
OPEN "test_simple.txt" FOR INPUT AS #1

DIM line1 AS STRING
DIM line2 AS STRING
DIM line3 AS STRING

LINE INPUT #1, line1
LINE INPUT #1, line2
LINE INPUT #1, line3

CLOSE #1

PRINT "Line 1: "; line1
PRINT "Line 2: "; line2
PRINT "Line 3: "; line3

IF line1 = "First line" THEN
    PRINT "PASS: Line 1 correct"
ELSE
    PRINT "FAIL: Line 1 incorrect"
END IF

IF line2 = "Second line" THEN
    PRINT "PASS: Line 2 correct"
ELSE
    PRINT "FAIL: Line 2 incorrect"
END IF

IF line3 = "Third line" THEN
    PRINT "PASS: Line 3 correct"
ELSE
    PRINT "FAIL: Line 3 incorrect"
END IF

PRINT ""
PRINT "Test complete"
