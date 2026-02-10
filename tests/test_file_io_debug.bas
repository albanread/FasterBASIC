REM Minimal File I/O debug test
REM Tests OPEN FOR OUTPUT, PRINT #, CLOSE, OPEN FOR INPUT, EOF, LINE INPUT #

DIM f$ AS STRING
f$ = "debug_io.txt"

REM Write two lines
OPEN f$ FOR OUTPUT AS #1
PRINT #1, "AAA"
PRINT #1, "BBB"
CLOSE #1
PRINT "Write done"

REM Read back and check EOF
OPEN f$ FOR INPUT AS #1

PRINT "EOF before read: "; EOF(1)

DIM a$ AS STRING
LINE INPUT #1, a$
PRINT "First line: ["; a$; "]"
PRINT "EOF after first read: "; EOF(1)

DIM b$ AS STRING
LINE INPUT #1, b$
PRINT "Second line: ["; b$; "]"
PRINT "EOF after second read: "; EOF(1)

CLOSE #1
PRINT "Read done"
