REM Test file I/O error handling with TRY/CATCH
REM Demonstrates proper error codes for various file error conditions

PRINT "=== File I/O Error Handling Test ==="
PRINT ""

DIM error_count AS INTEGER
DIM success_count AS INTEGER
error_count = 0
success_count = 0

REM ================================================================
REM Test 1: File Not Found (Error 53)
REM ================================================================
PRINT "Test 1: File Not Found (Error 53)"
TRY
    OPEN "nonexistent_file_xyz.txt" FOR INPUT AS #1
    PRINT "  FAIL: Should have thrown error"
    CLOSE #1
CATCH
    IF ERR = 53 THEN
        PRINT "  PASS: Caught error 53 (File Not Found)"
        success_count = success_count + 1
    ELSE
        PRINT "  FAIL: Wrong error code: "; ERR
        error_count = error_count + 1
    END IF
END TRY
PRINT ""

REM ================================================================
REM Test 2: Bad File Number (Error 64)
REM ================================================================
PRINT "Test 2: Bad File Number (Error 64)"
TRY
    REM Try to use file number 300 (exceeds MAX_FILE_HANDLES)
    OPEN "test.txt" FOR OUTPUT AS #300
    PRINT "  FAIL: Should have thrown error"
    CLOSE #300
CATCH
    IF ERR = 64 THEN
        PRINT "  PASS: Caught error 64 (Bad File Number)"
        success_count = success_count + 1
    ELSE
        PRINT "  FAIL: Wrong error code: "; ERR
        error_count = error_count + 1
    END IF
END TRY
PRINT ""

REM ================================================================
REM Test 3: File Not Open (Error 56)
REM ================================================================
PRINT "Test 3: File Not Open (Error 56)"
TRY
    REM Try to read from unopened file handle
    DIM result AS INTEGER
    result = LOC(99)
    PRINT "  FAIL: Should have thrown error"
CATCH
    IF ERR = 56 OR ERR = 64 THEN
        PRINT "  PASS: Caught error "; ERR; " (File Not Open/Bad Number)"
        success_count = success_count + 1
    ELSE
        PRINT "  FAIL: Wrong error code: "; ERR
        error_count = error_count + 1
    END IF
END TRY
PRINT ""

REM ================================================================
REM Test 4: Successful File Operation (No Error)
REM ================================================================
PRINT "Test 4: Successful File Operation (No Error)"
TRY
    OPEN "error_test_file.txt" FOR OUTPUT AS #1
    PRINT #1, "Test data"
    CLOSE #1
    PRINT "  PASS: File operation succeeded"
    success_count = success_count + 1
CATCH
    PRINT "  FAIL: Unexpected error: "; ERR
    error_count = error_count + 1
END TRY
PRINT ""

REM ================================================================
REM Test 5: Invalid Parameters to CV functions (Error 5)
REM ================================================================
PRINT "Test 5: Invalid Parameters (Error 5)"
TRY
    DIM short_str AS STRING
    short_str = "X"
    DIM result AS INTEGER
    result = CVI(short_str)
    PRINT "  FAIL: Should have thrown error"
CATCH
    IF ERR = 5 THEN
        PRINT "  PASS: Caught error 5 (Illegal Function Call)"
        success_count = success_count + 1
    ELSE
        PRINT "  FAIL: Wrong error code: "; ERR
        error_count = error_count + 1
    END IF
END TRY
PRINT ""

REM ================================================================
REM Test 6: Multiple Error Conditions in Sequence
REM ================================================================
PRINT "Test 6: Multiple Error Conditions"
DIM multi_errors AS INTEGER
multi_errors = 0

TRY
    OPEN "nonexistent1.txt" FOR INPUT AS #1
CATCH
    IF ERR = 53 THEN multi_errors = multi_errors + 1
END TRY

TRY
    OPEN "nonexistent2.txt" FOR INPUT AS #2
CATCH
    IF ERR = 53 THEN multi_errors = multi_errors + 1
END TRY

IF multi_errors = 2 THEN
    PRINT "  PASS: Caught multiple errors correctly"
    success_count = success_count + 1
ELSE
    PRINT "  FAIL: Did not catch all errors"
    error_count = error_count + 1
END IF
PRINT ""

REM ================================================================
REM Test 7: Nested TRY/CATCH
REM ================================================================
PRINT "Test 7: Nested TRY/CATCH"
DIM outer_caught AS INTEGER
DIM inner_caught AS INTEGER
outer_caught = 0
inner_caught = 0

TRY
    TRY
        OPEN "nested_nonexistent.txt" FOR INPUT AS #1
    CATCH
        inner_caught = 1
        PRINT "  Inner CATCH: Error "; ERR
    END TRY

    REM This should still be in outer TRY
    IF inner_caught = 1 THEN
        PRINT "  Outer TRY: Continuing after inner CATCH"
    END IF
CATCH
    outer_caught = 1
    PRINT "  FAIL: Should not reach outer CATCH"
END TRY

IF inner_caught = 1 AND outer_caught = 0 THEN
    PRINT "  PASS: Nested TRY/CATCH works correctly"
    success_count = success_count + 1
ELSE
    PRINT "  FAIL: Nested TRY/CATCH failed"
    error_count = error_count + 1
END IF
PRINT ""

REM ================================================================
REM Test 8: Error Information Functions (ERR and ERL)
REM ================================================================
PRINT "Test 8: ERR and ERL Functions"
TRY
    OPEN "error_info_test.txt" FOR INPUT AS #1
CATCH
    DIM err_code AS INTEGER
    DIM err_line AS INTEGER
    err_code = ERR
    err_line = ERL

    IF err_code = 53 THEN
        PRINT "  ERR function returned: "; err_code
        PRINT "  ERL function returned: "; err_line
        PRINT "  PASS: Error information functions work"
        success_count = success_count + 1
    ELSE
        PRINT "  FAIL: ERR function returned unexpected value"
        error_count = error_count + 1
    END IF
END TRY
PRINT ""

REM ================================================================
REM Final Summary
REM ================================================================
PRINT "=== Test Summary ==="
PRINT "Tests Passed:  "; success_count
PRINT "Tests Failed:  "; error_count
PRINT "Total Tests:   "; success_count + error_count
PRINT ""

IF error_count = 0 THEN
    PRINT "ALL ERROR HANDLING TESTS PASSED!"
ELSE
    PRINT "SOME TESTS FAILED - See details above"
END IF
PRINT ""

PRINT "Error Codes Tested:"
PRINT "  5  - Illegal Function Call"
PRINT "  53 - File Not Found"
PRINT "  56 - File Not Open"
PRINT "  64 - Bad File Number"
PRINT ""
PRINT "Features Tested:"
PRINT "  - TRY/CATCH blocks"
PRINT "  - ERR function (error code)"
PRINT "  - ERL function (error line)"
PRINT "  - Multiple sequential errors"
PRINT "  - Nested TRY/CATCH blocks"
PRINT "  - Error recovery and continuation"
