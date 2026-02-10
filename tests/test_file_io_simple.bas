REM Simple File I/O Test
REM Tests OPEN, PRINT #, CLOSE, LINE INPUT #

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
OPEN filename$ FOR INPUT AS #1

DIM line$ AS STRING
DIM count AS INTEGER
count = 0

DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    PRINT "Line "; count; ": "; line$
LOOP

CLOSE #1
PRINT "File read successfully"
PRINT "Total lines: "; count
