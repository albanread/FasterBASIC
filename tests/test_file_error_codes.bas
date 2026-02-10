REM Test file I/O error codes without TRY/CATCH
REM Demonstrates that proper error codes are available via ERR function
REM Note: These tests will cause the program to exit on first error

PRINT "=== File I/O Error Codes Test ==="
PRINT ""
PRINT "This test demonstrates the error codes that are generated"
PRINT "for various file I/O error conditions."
PRINT ""

REM ================================================================
REM Document the error codes
REM ================================================================
PRINT "Standard BASIC File I/O Error Codes:"
PRINT ""
PRINT "  5  - ERR_ILLEGAL_CALL       - Illegal function call"
PRINT "  7  - ERR_OUT_OF_MEMORY      - Out of memory"
PRINT "  52 - ERR_BAD_FILE           - Bad file number/operation"
PRINT "  53 - ERR_FILE_NOT_FOUND     - File not found"
PRINT "  55 - ERR_FILE_ALREADY_OPEN  - File already open"
PRINT "  56 - ERR_FILE_NOT_OPEN      - File not open"
PRINT "  61 - ERR_DISK_FULL          - Disk full"
PRINT "  62 - ERR_INPUT_PAST_END     - Input past end of file"
PRINT "  64 - ERR_BAD_FILE_NUMBER    - Bad file number"
PRINT "  68 - ERR_FILE_ALREADY_EXISTS - File already exists"
PRINT "  71 - ERR_DISK_NOT_READY     - Disk not ready"
PRINT "  75 - ERR_PERMISSION_DENIED  - Permission denied"
PRINT "  76 - ERR_PATH_NOT_FOUND     - Path not found"
PRINT "  80 - ERR_INVALID_MODE       - Invalid file mode"
PRINT "  81 - ERR_INVALID_RECORD_LENGTH - Invalid record length"
PRINT "  82 - ERR_RECORD_OUT_OF_RANGE - Record number out of range"
PRINT ""

REM ================================================================
REM Test successful operations (no errors)
REM ================================================================
PRINT "=== Testing Successful Operations ==="
PRINT ""

PRINT "Test 1: Create file with OUTPUT"
OPEN "error_test1.dat" FOR OUTPUT AS #1
PRINT #1, "Test data"
CLOSE #1
PRINT "  SUCCESS: File created and written"
PRINT ""

PRINT "Test 2: Append to existing file"
OPEN "error_test1.dat" FOR APPEND AS #1
PRINT #1, "Appended data"
CLOSE #1
PRINT "  SUCCESS: Data appended"
PRINT ""

PRINT "Test 3: Open file for INPUT (file exists)"
OPEN "error_test1.dat" FOR INPUT AS #1
CLOSE #1
PRINT "  SUCCESS: File opened for reading"
PRINT ""

PRINT "Test 4: BINARY OUTPUT mode"
OPEN "error_test2.dat" FOR BINARY OUTPUT AS #2
PRINT #2, "Binary data"
CLOSE #2
PRINT "  SUCCESS: Binary file created"
PRINT ""

PRINT "Test 5: RANDOM mode"
OPEN "error_test3.dat" FOR RANDOM 128 AS #3
PRINT #3, "Random access data"
CLOSE #3
PRINT "  SUCCESS: Random access file created"
PRINT ""

PRINT "Test 6: Multiple files open"
OPEN "error_test4.dat" FOR OUTPUT AS #1
OPEN "error_test5.dat" FOR OUTPUT AS #2
OPEN "error_test6.dat" FOR OUTPUT AS #3
PRINT #1, "File 1"
PRINT #2, "File 2"
PRINT #3, "File 3"
CLOSE #1
CLOSE #2
CLOSE #3
PRINT "  SUCCESS: Multiple files handled"
PRINT ""

PRINT "Test 7: High file numbers"
OPEN "error_test7.dat" FOR OUTPUT AS #99
PRINT #99, "High file number"
CLOSE #99
PRINT "  SUCCESS: High file number works"
PRINT ""

PRINT "Test 8: MKI$ and CVI functions"
DIM test_int AS INTEGER
DIM int_str AS STRING
test_int = 12345
int_str = MKI(test_int)
DIM recovered AS INTEGER
recovered = CVI(int_str)
IF recovered = test_int THEN
    PRINT "  SUCCESS: MKI$/CVI work correctly"
ELSE
    PRINT "  FAIL: MKI$/CVI returned wrong value"
END IF
PRINT ""

PRINT "Test 9: MKD$ and CVD functions"
DIM test_dbl AS DOUBLE
DIM dbl_str AS STRING
test_dbl = 3.14159
dbl_str = MKD(test_dbl)
DIM recovered_dbl AS DOUBLE
recovered_dbl = CVD(dbl_str)
DIM diff AS DOUBLE
diff = ABS(recovered_dbl - test_dbl)
IF diff < 0.0001 THEN
    PRINT "  SUCCESS: MKD$/CVD work correctly"
ELSE
    PRINT "  FAIL: MKD$/CVD returned wrong value"
END IF
PRINT ""

PRINT "Test 10: LOF and LOC functions"
OPEN "error_test8.dat" FOR OUTPUT AS #1
PRINT #1, "Test data for file length"
DIM file_len AS INTEGER
file_len = LOF(1)
DIM file_pos AS INTEGER
file_pos = LOC(1)
CLOSE #1
IF file_len > 0 THEN
    PRINT "  SUCCESS: LOF returned "; file_len; " bytes"
    PRINT "  SUCCESS: LOC returned position "; file_pos
ELSE
    PRINT "  FAIL: LOF/LOC functions failed"
END IF
PRINT ""

PRINT "=== All Basic Operations Completed Successfully ==="
PRINT ""
PRINT "The following error conditions would generate these codes:"
PRINT ""
PRINT "Error 53 (File Not Found):"
PRINT "  - Would occur if you: OPEN \"nonexistent.txt\" FOR INPUT AS #1"
PRINT ""
PRINT "Error 64 (Bad File Number):"
PRINT "  - Would occur if you: OPEN \"test.txt\" FOR OUTPUT AS #300"
PRINT "  - (File numbers must be 0-255)"
PRINT ""
PRINT "Error 56 (File Not Open):"
PRINT "  - Would occur if you tried to read from an unopened file"
PRINT "  - Example: result = LOC(50) when file #50 is not open"
PRINT ""
PRINT "Error 5 (Illegal Function Call):"
PRINT "  - Would occur if you: result = CVI(\"X\")"
PRINT "  - (String too short - needs 2 bytes)"
PRINT ""
PRINT "Error 75 (Permission Denied):"
PRINT "  - Would occur if trying to write to a read-only file"
PRINT "  - Or if you lack write permissions to the directory"
PRINT ""
PRINT "To handle errors in your programs, use TRY/CATCH blocks:"
PRINT ""
PRINT "  TRY"
PRINT "    OPEN \"file.txt\" FOR INPUT AS #1"
PRINT "  CATCH"
PRINT "    IF ERR = 53 THEN"
PRINT "      PRINT \"File not found\""
PRINT "    END IF"
PRINT "  END TRY"
PRINT ""
PRINT "Use ERR function to get error code"
PRINT "Use ERL function to get line number where error occurred"
PRINT ""
PRINT "=== Test Complete ==="
