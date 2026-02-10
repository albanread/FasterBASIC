REM Test all OPEN syntax variants
REM Demonstrates long form, short form, aliases, and flexible ordering

PRINT "=== Testing All OPEN Syntax Variants ==="
PRINT ""

REM Test 1: Long form OUTPUT
PRINT "Test 1: OPEN FOR OUTPUT (long form)"
OPEN "syntax1.dat" FOR OUTPUT AS #1
PRINT #1, "Test 1"
CLOSE #1
PRINT "  SUCCESS: Long form OUTPUT"

REM Test 2: Short form OUTPUT (O alias)
PRINT "Test 2: OPEN FOR O (short form)"
OPEN "syntax2.dat" FOR O AS #1
PRINT #1, "Test 2"
CLOSE #1
PRINT "  SUCCESS: Short form O"

REM Test 3: Long form APPEND
PRINT "Test 3: OPEN FOR APPEND (long form)"
OPEN "syntax3.dat" FOR APPEND AS #1
PRINT #1, "Test 3"
CLOSE #1
PRINT "  SUCCESS: Long form APPEND"

REM Test 4: Short form APPEND (A alias)
PRINT "Test 4: OPEN FOR A (short form)"
OPEN "syntax4.dat" FOR A AS #1
PRINT #1, "Test 4"
CLOSE #1
PRINT "  SUCCESS: Short form A"

REM Test 5: BINARY OUTPUT (long form)
PRINT "Test 5: OPEN FOR BINARY OUTPUT"
OPEN "syntax5.dat" FOR BINARY OUTPUT AS #1
PRINT #1, "Test 5"
CLOSE #1
PRINT "  SUCCESS: BINARY OUTPUT"

REM Test 6: OUTPUT BINARY (reversed order)
PRINT "Test 6: OPEN FOR OUTPUT BINARY (reversed)"
OPEN "syntax6.dat" FOR OUTPUT BINARY AS #1
PRINT #1, "Test 6"
CLOSE #1
PRINT "  SUCCESS: OUTPUT BINARY"

REM Test 7: B O (short form binary output)
PRINT "Test 7: OPEN FOR B O (aliases)"
OPEN "syntax7.dat" FOR B O AS #1
PRINT #1, "Test 7"
CLOSE #1
PRINT "  SUCCESS: B O aliases"

REM Test 8: O B (reversed short form)
PRINT "Test 8: OPEN FOR O B (reversed aliases)"
OPEN "syntax8.dat" FOR O B AS #1
PRINT #1, "Test 8"
CLOSE #1
PRINT "  SUCCESS: O B reversed"

REM Test 9: RANDOM (long form)
PRINT "Test 9: OPEN FOR RANDOM"
OPEN "syntax9.dat" FOR RANDOM AS #1
PRINT #1, "Test 9"
CLOSE #1
PRINT "  SUCCESS: RANDOM"

REM Test 10: R (short form random)
PRINT "Test 10: OPEN FOR R (alias)"
OPEN "syntax10.dat" FOR R AS #1
PRINT #1, "Test 10"
CLOSE #1
PRINT "  SUCCESS: R alias"

REM Test 11: RANDOM with record length
PRINT "Test 11: OPEN FOR RANDOM 128"
OPEN "syntax11.dat" FOR RANDOM 128 AS #1
PRINT #1, "Test 11"
CLOSE #1
PRINT "  SUCCESS: RANDOM 128"

REM Test 12: R with record length (alias)
PRINT "Test 12: OPEN FOR R 256 (alias with length)"
OPEN "syntax12.dat" FOR R 256 AS #1
PRINT #1, "Test 12"
CLOSE #1
PRINT "  SUCCESS: R 256"

REM Test 13: BINARY APPEND
PRINT "Test 13: OPEN FOR BINARY APPEND"
OPEN "syntax13.dat" FOR BINARY APPEND AS #1
PRINT #1, "Test 13"
CLOSE #1
PRINT "  SUCCESS: BINARY APPEND"

REM Test 14: B A (short form binary append)
PRINT "Test 14: OPEN FOR B A"
OPEN "syntax14.dat" FOR B A AS #1
PRINT #1, "Test 14"
CLOSE #1
PRINT "  SUCCESS: B A"

REM Test 15: Variable filenames
PRINT "Test 15: OPEN with variable filename"
DIM fname AS STRING
fname = "syntax15.dat"
OPEN fname FOR OUTPUT AS #1
PRINT #1, "Test 15"
CLOSE #1
PRINT "  SUCCESS: Variable filename"

REM Test 16: Expression for file number
PRINT "Test 16: OPEN with expression for file number"
DIM fnum AS INTEGER
fnum = 5
OPEN "syntax16.dat" FOR OUTPUT AS #fnum
PRINT #fnum, "Test 16"
CLOSE #fnum
PRINT "  SUCCESS: Expression file number"

PRINT ""
PRINT "=== Summary ==="
PRINT "  16 syntax variants tested"
PRINT "  All variants compiled and executed successfully"
PRINT ""
PRINT "Syntax variants demonstrated:"
PRINT "  - Long form: OUTPUT, APPEND, BINARY OUTPUT, RANDOM"
PRINT "  - Short form: O, A, B O, R"
PRINT "  - Flexible ordering: BINARY OUTPUT vs OUTPUT BINARY"
PRINT "  - Record lengths: RANDOM 128, R 256"
PRINT "  - Variable filenames and file numbers"
PRINT ""
PRINT "ALL TESTS PASSED!"
