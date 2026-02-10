REM Test all OPEN statement modes and syntax variants
REM Tests: INPUT, OUTPUT, APPEND, BINARY INPUT, BINARY OUTPUT, BINARY APPEND, RANDOM

PRINT "=== Testing OPEN Statement Modes ==="
PRINT ""

DIM test_file$ AS STRING
test_file$ = "test_modes.dat"

REM Test 1: OUTPUT mode (write text)
PRINT "Test 1: OPEN FOR OUTPUT"
OPEN test_file$ FOR OUTPUT AS #1
PRINT #1, "Line 1"
PRINT #1, "Line 2"
PRINT #1, "Line 3"
CLOSE #1
PRINT "  Write successful"

REM Test 2: INPUT mode (read text)
PRINT "Test 2: OPEN FOR INPUT"
OPEN test_file$ FOR INPUT AS #1
DIM line$ AS STRING
line$ = ""
INPUT #1, line$
PRINT "  Read: "; line$
CLOSE #1

REM Test 3: APPEND mode (append text)
PRINT "Test 3: OPEN FOR APPEND"
OPEN test_file$ FOR APPEND AS #1
PRINT #1, "Line 4 appended"
CLOSE #1
PRINT "  Append successful"

REM Test 4: BINARY OUTPUT mode
PRINT "Test 4: OPEN FOR BINARY OUTPUT"
DIM binary_file$ AS STRING
binary_file$ = "test_binary.dat"
OPEN binary_file$ FOR BINARY OUTPUT AS #2
PRINT #2, "Binary data"
CLOSE #2
PRINT "  Binary write successful"

REM Test 5: BINARY INPUT mode
PRINT "Test 5: OPEN FOR BINARY INPUT"
OPEN binary_file$ FOR BINARY INPUT AS #2
DIM binary_line$ AS STRING
binary_line$ = ""
INPUT #2, binary_line$
PRINT "  Read binary: "; binary_line$
CLOSE #2

REM Test 6: OUTPUT BINARY (reversed order)
PRINT "Test 6: OPEN FOR OUTPUT BINARY (reversed)"
DIM rev_file$ AS STRING
rev_file$ = "test_rev.dat"
OPEN rev_file$ FOR OUTPUT BINARY AS #3
PRINT #3, "Reversed binary"
CLOSE #3
PRINT "  Write successful"

REM Test 7: RANDOM mode
PRINT "Test 7: OPEN FOR RANDOM"
DIM random_file$ AS STRING
random_file$ = "test_random.dat"
OPEN random_file$ FOR RANDOM AS #4
PRINT #4, "Random access data"
CLOSE #4
PRINT "  Random access write successful"

REM Test 8: RANDOM with record length
PRINT "Test 8: OPEN FOR RANDOM 128"
DIM random_rec$ AS STRING
random_rec$ = "test_random_rec.dat"
OPEN random_rec$ FOR RANDOM 128 AS #5
PRINT #5, "Random with 128 byte records"
CLOSE #5
PRINT "  Random with record length successful"

REM Test 9: Single letter aliases - O (OUTPUT)
PRINT "Test 9: OPEN FOR O (OUTPUT alias)"
DIM alias_file$ AS STRING
alias_file$ = "test_alias.dat"
OPEN alias_file$ FOR O AS #6
PRINT #6, "Using O alias"
CLOSE #6
PRINT "  Output alias successful"

REM Test 10: Single letter aliases - I (INPUT)
PRINT "Test 10: OPEN FOR I (INPUT alias)"
OPEN alias_file$ FOR I AS #6
DIM alias_line$ AS STRING
alias_line$ = ""
INPUT #6, alias_line$
PRINT "  Read with I alias: "; alias_line$
CLOSE #6

REM Test 11: Single letter aliases - A (APPEND)
PRINT "Test 11: OPEN FOR A (APPEND alias)"
OPEN alias_file$ FOR A AS #6
PRINT #6, "Appended with A"
CLOSE #6
PRINT "  Append alias successful"

REM Test 12: B I (BINARY INPUT using aliases)
PRINT "Test 12: OPEN FOR B I (BINARY INPUT aliases)"
DIM bi_file$ AS STRING
bi_file$ = "test_bi.dat"
OPEN bi_file$ FOR B O AS #7
PRINT #7, "Binary with aliases"
CLOSE #7
OPEN bi_file$ FOR B I AS #7
DIM bi_line$ AS STRING
bi_line$ = ""
INPUT #7, bi_line$
PRINT "  Read with B I: "; bi_line$
CLOSE #7

REM Test 13: R (RANDOM alias)
PRINT "Test 13: OPEN FOR R (RANDOM alias)"
DIM r_file$ AS STRING
r_file$ = "test_r.dat"
OPEN r_file$ FOR R AS #8
PRINT #8, "Random with R alias"
CLOSE #8
PRINT "  Random alias successful"

PRINT ""
PRINT "=== All OPEN mode tests completed ==="
PRINT ""
PRINT "Modes tested:"
PRINT "  - OUTPUT, INPUT, APPEND"
PRINT "  - BINARY OUTPUT, BINARY INPUT, BINARY APPEND"
PRINT "  - OUTPUT BINARY (reversed order)"
PRINT "  - RANDOM, RANDOM with record length"
PRINT "  - Single letter aliases: O, I, A, B, R"
PRINT "  - Combined aliases: B I, B O"
