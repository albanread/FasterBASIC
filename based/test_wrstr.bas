REM Test WRSTR - Write String without newline
REM Verifies that WRSTR outputs strings correctly without appending newlines

REM Declare string variables up front
DIM a$ AS STRING
DIM b$ AS STRING
DIM combined$ AS STRING
DIM test$ AS STRING
DIM long$ AS STRING

PRINT "WRSTR String Output Test"
PRINT "========================"
PRINT

REM Test 1: Basic WRSTR
PRINT "Test 1: Basic WRSTR output"
PRINT "Expected: 'Hello World' on one line"
WRSTR "Hello "
WRSTR "World"
PRINT
PRINT

REM Test 2: WRSTR with string variables
PRINT "Test 2: WRSTR with string variables"
PRINT "Expected: 'FasterBASIC' on one line"
a$ = "Faster"
b$ = "BASIC"
WRSTR a$
WRSTR b$
PRINT
PRINT

REM Test 3: WRSTR with string concatenation
PRINT "Test 3: WRSTR with concatenated string"
PRINT "Expected: 'ABC-DEF-GHI' on one line"
combined$ = "ABC" + "-" + "DEF" + "-" + "GHI"
WRSTR combined$
PRINT
PRINT

REM Test 4: WRSTR with string functions
PRINT "Test 4: WRSTR with LEFT$/RIGHT$/MID$"
PRINT "Expected: 'Hel-rld-llo' on one line"
test$ = "Hello World"
WRSTR LEFT$(test$, 3)
WRSTR "-"
WRSTR RIGHT$(test$, 3)
WRSTR "-"
WRSTR MID$(test$, 3, 3)
PRINT
PRINT

REM Test 5: WRSTR with empty string
PRINT "Test 5: WRSTR with empty string (should output nothing)"
PRINT "Expected: 'BEFORE AFTER' on one line"
WRSTR "BEFORE "
WRSTR ""
WRSTR "AFTER"
PRINT
PRINT

REM Test 6: WRSTR with STR$ conversion
PRINT "Test 6: WRSTR with numeric-to-string conversion"
PRINT "Expected: 'Count: 42 Value: 3.14' on one line"
WRSTR "Count: "
WRSTR STR$(42)
WRSTR " Value: "
WRSTR STR$(3.14)
PRINT
PRINT

REM Test 7: Multiple WRSTR building a line
PRINT "Test 7: Building a line character by character"
PRINT "Expected: 'ABCDEFGHIJ' on one line"
FOR j = 0 TO 9
    WRSTR CHR$(65 + j)
NEXT j
PRINT
PRINT

REM Test 8: WRSTR followed by PRINT
PRINT "Test 8: WRSTR followed by PRINT"
PRINT "Expected: 'Start...End' on one line, then 'Next line' below"
WRSTR "Start..."
PRINT "End"
PRINT "Next line"
PRINT

REM Test 9: Long string output
PRINT "Test 9: Long string (80 chars)"
PRINT "Expected: 80 '=' characters on one line"
long$ = ""
FOR m = 1 TO 80
    long$ = long$ + "="
NEXT m
WRSTR long$
PRINT
PRINT

REM Test 10: WRSTR with LOCATE
PRINT "Test 10: WRSTR with cursor positioning"
PRINT "Expected: 'X' and 'Y' placed at specific positions below"
DIM save_row%
save_row = 20
LOCATE 5, save_row
WRSTR "X"
LOCATE 15, save_row
WRSTR "Y"
LOCATE 25, save_row
WRSTR "Z"
LOCATE 0, save_row + 1
PRINT

PRINT
PRINT "All WRSTR tests complete."
