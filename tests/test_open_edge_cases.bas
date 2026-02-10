REM Test OPEN statement edge cases and boundary conditions
PRINT "=== Testing OPEN Statement Edge Cases ==="
PRINT ""

REM Test 1: Multiple files open simultaneously
PRINT "Test 1: Multiple files open at once"
OPEN "edge1.dat" FOR OUTPUT AS #1
OPEN "edge2.dat" FOR OUTPUT AS #2
OPEN "edge3.dat" FOR OUTPUT AS #3
PRINT #1, "File 1"
PRINT #2, "File 2"
PRINT #3, "File 3"
CLOSE #1
CLOSE #2
CLOSE #3
PRINT "  SUCCESS: Multiple files"

REM Test 2: Reopen same file number
PRINT "Test 2: Reuse file number"
OPEN "edge4.dat" FOR OUTPUT AS #1
PRINT #1, "First open"
CLOSE #1
OPEN "edge5.dat" FOR OUTPUT AS #1
PRINT #1, "Second open"
CLOSE #1
PRINT "  SUCCESS: File number reuse"

REM Test 3: High file numbers
PRINT "Test 3: High file number (99)"
OPEN "edge6.dat" FOR OUTPUT AS #99
PRINT #99, "High file number"
CLOSE #99
PRINT "  SUCCESS: High file number"

REM Test 4: Appending to non-existent file
PRINT "Test 4: Append to new file"
OPEN "edge7.dat" FOR APPEND AS #1
PRINT #1, "Created via APPEND"
CLOSE #1
PRINT "  SUCCESS: APPEND creates file"

REM Test 5: RANDOM mode with various record sizes
PRINT "Test 5: RANDOM with different record sizes"
OPEN "edge8.dat" FOR RANDOM 1 AS #1
PRINT #1, "Size 1"
CLOSE #1
OPEN "edge9.dat" FOR RANDOM 1024 AS #1
PRINT #1, "Size 1024"
CLOSE #1
OPEN "edge10.dat" FOR RANDOM 8192 AS #1
PRINT #1, "Size 8192"
CLOSE #1
PRINT "  SUCCESS: Various record sizes"

REM Test 6: String concatenation in filename
PRINT "Test 6: Filename expression"
DIM prefix AS STRING
DIM suffix AS STRING
prefix = "edge"
suffix = ".dat"
OPEN prefix + "11" + suffix FOR OUTPUT AS #1
PRINT #1, "Expression filename"
CLOSE #1
PRINT "  SUCCESS: Filename expression"

REM Test 7: Computed file number
PRINT "Test 7: Computed file number"
DIM base_num AS INTEGER
base_num = 10
OPEN "edge12.dat" FOR OUTPUT AS #(base_num + 5)
PRINT #15, "Computed file num"
CLOSE #15
PRINT "  SUCCESS: Computed file number"

REM Test 8: Mixed mode operations
PRINT "Test 8: Create with OUTPUT, then APPEND"
OPEN "edge13.dat" FOR OUTPUT AS #1
PRINT #1, "Original"
CLOSE #1
OPEN "edge13.dat" FOR APPEND AS #1
PRINT #1, "Appended"
CLOSE #1
PRINT "  SUCCESS: OUTPUT then APPEND"

REM Test 9: BINARY with different data
PRINT "Test 9: BINARY output with various data"
OPEN "edge14.dat" FOR BINARY OUTPUT AS #1
PRINT #1, "Text in binary"
PRINT #1, 12345
PRINT #1, 3.14159
CLOSE #1
PRINT "  SUCCESS: Mixed data in BINARY"

REM Test 10: Very long filename
PRINT "Test 10: Long filename"
DIM longname AS STRING
longname = "edge_very_long_filename_test_123456789.dat"
OPEN longname FOR OUTPUT AS #1
PRINT #1, "Long filename"
CLOSE #1
PRINT "  SUCCESS: Long filename"

REM Test 11: Empty writes
PRINT "Test 11: Empty write operations"
OPEN "edge15.dat" FOR OUTPUT AS #1
CLOSE #1
PRINT "  SUCCESS: Empty file"

REM Test 12: Rapid open/close cycles
PRINT "Test 12: Rapid open/close (10 cycles)"
DIM i AS INTEGER
FOR i = 1 TO 10
    OPEN "edge16.dat" FOR OUTPUT AS #1
    PRINT #1, "Cycle "; i
    CLOSE #1
NEXT i
PRINT "  SUCCESS: Rapid cycles"

REM Test 13: All aliases in one program
PRINT "Test 13: All mode aliases"
OPEN "edge17.dat" FOR O AS #1
PRINT #1, "O"
CLOSE #1
OPEN "edge17.dat" FOR I AS #1
CLOSE #1
OPEN "edge17.dat" FOR A AS #1
PRINT #1, "A"
CLOSE #1
OPEN "edge18.dat" FOR B O AS #1
PRINT #1, "BO"
CLOSE #1
OPEN "edge19.dat" FOR R AS #1
PRINT #1, "R"
CLOSE #1
PRINT "  SUCCESS: All aliases"

REM Test 14: Whitespace in modes (flexible parsing)
PRINT "Test 14: Mode keyword flexibility"
OPEN "edge20.dat" FOR OUTPUT AS #1
PRINT #1, "Standard"
CLOSE #1
OPEN "edge21.dat" FOR BINARY OUTPUT AS #1
PRINT #1, "With space"
CLOSE #1
PRINT "  SUCCESS: Keyword parsing"

REM Test 15: File numbers in various forms
PRINT "Test 15: File number variations"
OPEN "edge22.dat" FOR OUTPUT AS #1
PRINT #1, "Hash 1"
CLOSE #1
OPEN "edge23.dat" FOR OUTPUT AS 2
PRINT #2, "No hash"
CLOSE #2
PRINT "  SUCCESS: File number variations"

PRINT ""
PRINT "=== Summary ==="
PRINT "  15 edge case tests completed"
PRINT "  All tests passed successfully"
PRINT ""
PRINT "Edge cases tested:"
PRINT "  - Multiple simultaneous files"
PRINT "  - File number reuse"
PRINT "  - High file numbers (99)"
PRINT "  - APPEND to new files"
PRINT "  - Various RANDOM record sizes (1 to 8192)"
PRINT "  - Expression-based filenames"
PRINT "  - Computed file numbers"
PRINT "  - Mode transitions (OUTPUT -> APPEND)"
PRINT "  - BINARY with mixed data types"
PRINT "  - Long filenames"
PRINT "  - Empty files"
PRINT "  - Rapid open/close cycles"
PRINT "  - All mode aliases (I, O, A, B, R)"
PRINT "  - Flexible keyword parsing"
PRINT "  - File number format variations"
PRINT ""
PRINT "ALL EDGE CASE TESTS PASSED!"
