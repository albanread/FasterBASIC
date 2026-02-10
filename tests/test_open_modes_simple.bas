REM Simple test for OPEN statement modes - write only (no INPUT to avoid hanging)

PRINT "=== Testing OPEN Statement Modes (Write Only) ==="
PRINT ""

DIM test_file$ AS STRING
test_file$ = "test_modes.dat"

REM Test 1: OUTPUT mode (write text)
PRINT "Test 1: OPEN FOR OUTPUT"
OPEN test_file$ FOR OUTPUT AS #1
PRINT #1, "Line 1"
PRINT #1, "Line 2"
CLOSE #1
PRINT "  Write successful"

REM Test 2: APPEND mode (append text)
PRINT "Test 2: OPEN FOR APPEND"
OPEN test_file$ FOR APPEND AS #1
PRINT #1, "Line 3 appended"
CLOSE #1
PRINT "  Append successful"

REM Test 3: BINARY OUTPUT mode
PRINT "Test 3: OPEN FOR BINARY OUTPUT"
DIM binary_file$ AS STRING
binary_file$ = "test_binary.dat"
OPEN binary_file$ FOR BINARY OUTPUT AS #2
PRINT #2, "Binary data"
CLOSE #2
PRINT "  Binary write successful"

REM Test 4: OUTPUT BINARY (reversed order)
PRINT "Test 4: OPEN FOR OUTPUT BINARY (reversed)"
DIM rev_file$ AS STRING
rev_file$ = "test_rev.dat"
OPEN rev_file$ FOR OUTPUT BINARY AS #3
PRINT #3, "Reversed binary"
CLOSE #3
PRINT "  Write successful"

REM Test 5: RANDOM mode
PRINT "Test 5: OPEN FOR RANDOM"
DIM random_file$ AS STRING
random_file$ = "test_random.dat"
OPEN random_file$ FOR RANDOM AS #4
PRINT #4, "Random access data"
CLOSE #4
PRINT "  Random access write successful"

REM Test 6: RANDOM with record length
PRINT "Test 6: OPEN FOR RANDOM 128"
DIM random_rec$ AS STRING
random_rec$ = "test_random_rec.dat"
OPEN random_rec$ FOR RANDOM 128 AS #5
PRINT #5, "Random with 128 byte records"
CLOSE #5
PRINT "  Random with record length successful"

REM Test 7: Single letter aliases - O (OUTPUT)
PRINT "Test 7: OPEN FOR O (OUTPUT alias)"
DIM alias_file$ AS STRING
alias_file$ = "test_alias.dat"
OPEN alias_file$ FOR O AS #6
PRINT #6, "Using O alias"
CLOSE #6
PRINT "  Output alias successful"

REM Test 8: Single letter aliases - A (APPEND)
PRINT "Test 8: OPEN FOR A (APPEND alias)"
OPEN alias_file$ FOR A AS #6
PRINT #6, "Appended with A"
CLOSE #6
PRINT "  Append alias successful"

REM Test 9: B O (BINARY OUTPUT using aliases)
PRINT "Test 9: OPEN FOR B O (BINARY OUTPUT aliases)"
DIM bo_file$ AS STRING
bo_file$ = "test_bo.dat"
OPEN bo_file$ FOR B O AS #7
PRINT #7, "Binary with aliases"
CLOSE #7
PRINT "  Binary OUTPUT alias successful"

REM Test 10: R (RANDOM alias)
PRINT "Test 10: OPEN FOR R (RANDOM alias)"
DIM r_file$ AS STRING
r_file$ = "test_r.dat"
OPEN r_file$ FOR R AS #8
PRINT #8, "Random with R alias"
CLOSE #8
PRINT "  Random alias successful"

REM Test 11: R with record length
PRINT "Test 11: OPEN FOR R 256 (RANDOM alias with record length)"
DIM r2_file$ AS STRING
r2_file$ = "test_r2.dat"
OPEN r2_file$ FOR R 256 AS #9
PRINT #9, "Random 256 bytes"
CLOSE #9
PRINT "  Random alias with record length successful"

PRINT ""
PRINT "=== All OPEN mode tests completed successfully ==="
PRINT ""
PRINT "Modes tested:"
PRINT "  - OUTPUT, APPEND"
PRINT "  - BINARY OUTPUT (both orders)"
PRINT "  - RANDOM, RANDOM with record length"
PRINT "  - Single letter aliases: O, A, B, R"
PRINT "  - Combined aliases: B O"
PRINT "  - Random with record length using alias"
