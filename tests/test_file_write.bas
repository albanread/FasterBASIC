REM Simple File Write/Read Test
REM Tests OPEN, PRINT #, CLOSE, LINE INPUT # without EOF

DIM filename$ AS STRING
filename$ = "test_output.txt"

REM Write to file
PRINT "Writing to file..."
OPEN filename$ FOR OUTPUT AS #1
PRINT #1, "Hello from FasterBASIC!"
PRINT #1, "Line 2"
PRINT #1, "Line 3"
CLOSE #1
PRINT "File written successfully"

REM Read from file
PRINT "Reading from file..."
OPEN filename$ FOR INPUT AS #2

DIM line$ AS STRING
LINE INPUT #2, line$
PRINT "Line 1: "; line$

LINE INPUT #2, line$
PRINT "Line 2: "; line$

LINE INPUT #2, line$
PRINT "Line 3: "; line$

CLOSE #2
PRINT "File read successfully"
