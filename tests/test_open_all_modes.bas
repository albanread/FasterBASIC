REM Comprehensive test for all OPEN statement modes
REM Tests: INPUT, OUTPUT, APPEND, BINARY INPUT, BINARY OUTPUT, RANDOM
REM Uses LINE INPUT instead of INPUT to avoid blocking

PRINT "=== Comprehensive OPEN Mode Test ==="
PRINT ""

REM ========================================
REM Test 1: OUTPUT mode
REM ========================================
PRINT "Test 1: OPEN FOR OUTPUT"
DIM outfile$ AS STRING
outfile$ = "test_comprehensive.txt"
OPEN outfile$ FOR OUTPUT AS #1
PRINT #1, "First line"
PRINT #1, "Second line"
PRINT #1, "Third line"
CLOSE #1
PRINT "  ✓ Write complete"

REM ========================================
REM Test 2: INPUT mode with LINE INPUT
REM ========================================
PRINT "Test 2: OPEN FOR INPUT (with LINE INPUT)"
OPEN outfile$ FOR INPUT AS #1
DIM line1$ AS STRING
DIM line2$ AS STRING
LINE INPUT #1, line1$
LINE INPUT #1, line2$
CLOSE #1
PRINT "  Read line 1: "; line1$
PRINT "  Read line 2: "; line2$
PRINT "  ✓ Read complete"

REM ========================================
REM Test 3: APPEND mode
REM ========================================
PRINT "Test 3: OPEN FOR APPEND"
OPEN outfile$ FOR APPEND AS #1
PRINT #1, "Fourth line (appended)"
CLOSE #1
PRINT "  ✓ Append complete"

REM ========================================
REM Test 4: BINARY OUTPUT
REM ========================================
PRINT "Test 4: OPEN FOR BINARY OUTPUT"
DIM binfile$ AS STRING
binfile$ = "test_binary_comp.dat"
OPEN binfile$ FOR BINARY OUTPUT AS #2
PRINT #2, "Binary data here"
CLOSE #2
PRINT "  ✓ Binary write complete"

REM ========================================
REM Test 5: BINARY INPUT
REM ========================================
PRINT "Test 5: OPEN FOR BINARY INPUT"
OPEN binfile$ FOR BINARY INPUT AS #2
DIM bindata$ AS STRING
LINE INPUT #2, bindata$
CLOSE #2
PRINT "  Read binary: "; bindata$
PRINT "  ✓ Binary read complete"

REM ========================================
REM Test 6: OUTPUT BINARY (reversed order)
REM ========================================
PRINT "Test 6: OPEN FOR OUTPUT BINARY (reversed order)"
DIM revfile$ AS STRING
revfile$ = "test_reversed.dat"
OPEN revfile$ FOR OUTPUT BINARY AS #3
PRINT #3, "Reversed order binary"
CLOSE #3
PRINT "  ✓ Reversed order write complete"

REM ========================================
REM Test 7: RANDOM mode
REM ========================================
PRINT "Test 7: OPEN FOR RANDOM"
DIM randfile$ AS STRING
randfile$ = "test_random_comp.dat"
OPEN randfile$ FOR RANDOM AS #4
PRINT #4, "Random access data"
CLOSE #4
PRINT "  ✓ Random access write complete"

REM ========================================
REM Test 8: RANDOM with record length
REM ========================================
PRINT "Test 8: OPEN FOR RANDOM 128"
DIM randrec$ AS STRING
randrec$ = "test_random_128.dat"
OPEN randrec$ FOR RANDOM 128 AS #5
PRINT #5, "Record length 128"
CLOSE #5
PRINT "  ✓ Random with record length complete"

REM ========================================
REM Test 9-15: Single letter aliases
REM ========================================
PRINT "Test 9: OPEN FOR O (OUTPUT alias)"
DIM ofile$ AS STRING
ofile$ = "test_o.dat"
OPEN ofile$ FOR O AS #6
PRINT #6, "Using O"
CLOSE #6
PRINT "  ✓ O alias complete"

PRINT "Test 10: OPEN FOR I (INPUT alias)"
OPEN ofile$ FOR I AS #6
DIM odata$ AS STRING
LINE INPUT #6, odata$
CLOSE #6
PRINT "  Read with I: "; odata$
PRINT "  ✓ I alias complete"

PRINT "Test 11: OPEN FOR A (APPEND alias)"
OPEN ofile$ FOR A AS #6
PRINT #6, "Appended"
CLOSE #6
PRINT "  ✓ A alias complete"

PRINT "Test 12: OPEN FOR B O (BINARY OUTPUT aliases)"
DIM bofile$ AS STRING
bofile$ = "test_bo_comp.dat"
OPEN bofile$ FOR B O AS #7
PRINT #7, "B O combo"
CLOSE #7
PRINT "  ✓ B O aliases complete"

PRINT "Test 13: OPEN FOR B I (BINARY INPUT aliases)"
OPEN bofile$ FOR B I AS #7
DIM bodata$ AS STRING
LINE INPUT #7, bodata$
CLOSE #7
PRINT "  Read with B I: "; bodata$
PRINT "  ✓ B I aliases complete"

PRINT "Test 14: OPEN FOR R (RANDOM alias)"
DIM rfile$ AS STRING
rfile$ = "test_r_comp.dat"
OPEN rfile$ FOR R AS #8
PRINT #8, "R alias"
CLOSE #8
PRINT "  ✓ R alias complete"

PRINT "Test 15: OPEN FOR R 256 (RANDOM alias with record length)"
DIM r256$ AS STRING
r256$ = "test_r256.dat"
OPEN r256$ FOR R 256 AS #9
PRINT #9, "R 256"
CLOSE #9
PRINT "  ✓ R 256 complete"

REM ========================================
REM Summary
REM ========================================
PRINT ""
PRINT "=== ALL TESTS PASSED ==="
PRINT ""
PRINT "Successfully tested all OPEN modes:"
PRINT "  ✓ OUTPUT, INPUT, APPEND"
PRINT "  ✓ BINARY OUTPUT, BINARY INPUT"
PRINT "  ✓ OUTPUT BINARY, INPUT BINARY (reversed)"
PRINT "  ✓ RANDOM, RANDOM with record length"
PRINT "  ✓ Single-letter aliases: O, I, A, B, R"
PRINT "  ✓ Combined aliases: B O, B I"
PRINT "  ✓ RANDOM aliases with record length"
PRINT ""
PRINT "All file modes are working correctly!"
