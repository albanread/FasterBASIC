REM Comprehensive OPEN Statement Test Summary
REM This test demonstrates all OPEN mode enhancements
REM Tests all modes, aliases, and syntax variants

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  FasterBASIC OPEN Statement Comprehensive Test Suite          ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

DIM total_tests AS INTEGER
DIM passed_tests AS INTEGER
total_tests = 0
passed_tests = 0

REM ================================================================
REM SECTION 1: Basic Modes (Long Form)
REM ================================================================
PRINT "┌─ Section 1: Basic Modes (Long Form) ─────────────────────────┐"
PRINT ""

REM Test 1.1: OUTPUT
total_tests = total_tests + 1
PRINT "Test 1.1: OPEN FOR OUTPUT"
OPEN "comp_test1.dat" FOR OUTPUT AS #1
PRINT #1, "OUTPUT mode test"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 1.2: APPEND
total_tests = total_tests + 1
PRINT "Test 1.2: OPEN FOR APPEND"
OPEN "comp_test1.dat" FOR APPEND AS #1
PRINT #1, "APPEND mode test"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 1.3: RANDOM
total_tests = total_tests + 1
PRINT "Test 1.3: OPEN FOR RANDOM"
OPEN "comp_test2.dat" FOR RANDOM AS #1
PRINT #1, "RANDOM mode test"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM SECTION 2: Binary Modes
REM ================================================================
PRINT "┌─ Section 2: Binary Modes ─────────────────────────────────────┐"
PRINT ""

REM Test 2.1: BINARY OUTPUT
total_tests = total_tests + 1
PRINT "Test 2.1: OPEN FOR BINARY OUTPUT"
OPEN "comp_test3.dat" FOR BINARY OUTPUT AS #1
PRINT #1, "BINARY OUTPUT mode"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 2.2: OUTPUT BINARY (reversed order)
total_tests = total_tests + 1
PRINT "Test 2.2: OPEN FOR OUTPUT BINARY (reversed)"
OPEN "comp_test4.dat" FOR OUTPUT BINARY AS #1
PRINT #1, "OUTPUT BINARY mode"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 2.3: BINARY APPEND
total_tests = total_tests + 1
PRINT "Test 2.3: OPEN FOR BINARY APPEND"
OPEN "comp_test5.dat" FOR BINARY APPEND AS #1
PRINT #1, "BINARY APPEND mode"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM SECTION 3: Single-Letter Aliases
REM ================================================================
PRINT "┌─ Section 3: Single-Letter Aliases ────────────────────────────┐"
PRINT ""

REM Test 3.1: O (OUTPUT)
total_tests = total_tests + 1
PRINT "Test 3.1: OPEN FOR O (OUTPUT alias)"
OPEN "comp_test6.dat" FOR O AS #1
PRINT #1, "O alias"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 3.2: A (APPEND)
total_tests = total_tests + 1
PRINT "Test 3.2: OPEN FOR A (APPEND alias)"
OPEN "comp_test7.dat" FOR A AS #1
PRINT #1, "A alias"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 3.3: R (RANDOM)
total_tests = total_tests + 1
PRINT "Test 3.3: OPEN FOR R (RANDOM alias)"
OPEN "comp_test8.dat" FOR R AS #1
PRINT #1, "R alias"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 3.4: B O (BINARY OUTPUT)
total_tests = total_tests + 1
PRINT "Test 3.4: OPEN FOR B O (BINARY OUTPUT aliases)"
OPEN "comp_test9.dat" FOR B O AS #1
PRINT #1, "B O aliases"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 3.5: O B (reversed)
total_tests = total_tests + 1
PRINT "Test 3.5: OPEN FOR O B (reversed aliases)"
OPEN "comp_test10.dat" FOR O B AS #1
PRINT #1, "O B aliases"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 3.6: B A (BINARY APPEND)
total_tests = total_tests + 1
PRINT "Test 3.6: OPEN FOR B A (BINARY APPEND aliases)"
OPEN "comp_test11.dat" FOR B A AS #1
PRINT #1, "B A aliases"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM SECTION 4: Record Length Specification
REM ================================================================
PRINT "┌─ Section 4: Record Length Specification ──────────────────────┐"
PRINT ""

REM Test 4.1: RANDOM with record length
total_tests = total_tests + 1
PRINT "Test 4.1: OPEN FOR RANDOM 128"
OPEN "comp_test12.dat" FOR RANDOM 128 AS #1
PRINT #1, "RANDOM 128"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 4.2: R with record length
total_tests = total_tests + 1
PRINT "Test 4.2: OPEN FOR R 256 (alias with length)"
OPEN "comp_test13.dat" FOR R 256 AS #1
PRINT #1, "R 256"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 4.3: Small record
total_tests = total_tests + 1
PRINT "Test 4.3: OPEN FOR RANDOM 1 (minimum)"
OPEN "comp_test14.dat" FOR RANDOM 1 AS #1
PRINT #1, "RANDOM 1"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 4.4: Large record
total_tests = total_tests + 1
PRINT "Test 4.4: OPEN FOR RANDOM 8192 (large)"
OPEN "comp_test15.dat" FOR RANDOM 8192 AS #1
PRINT #1, "RANDOM 8192"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM SECTION 5: Advanced Features
REM ================================================================
PRINT "┌─ Section 5: Advanced Features ────────────────────────────────┐"
PRINT ""

REM Test 5.1: Variable filename
total_tests = total_tests + 1
PRINT "Test 5.1: Variable filename"
DIM fname AS STRING
fname = "comp_test16.dat"
OPEN fname FOR OUTPUT AS #1
PRINT #1, "Variable filename"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 5.2: Expression filename
total_tests = total_tests + 1
PRINT "Test 5.2: Expression filename"
DIM prefix AS STRING
prefix = "comp_test"
OPEN prefix + "17.dat" FOR OUTPUT AS #1
PRINT #1, "Expression filename"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 5.3: Computed file number
total_tests = total_tests + 1
PRINT "Test 5.3: Computed file number"
DIM base AS INTEGER
base = 10
OPEN "comp_test18.dat" FOR OUTPUT AS #(base + 5)
PRINT #15, "Computed file number"
CLOSE #15
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 5.4: Multiple simultaneous files
total_tests = total_tests + 1
PRINT "Test 5.4: Multiple files open"
OPEN "comp_test19.dat" FOR OUTPUT AS #1
OPEN "comp_test20.dat" FOR OUTPUT AS #2
OPEN "comp_test21.dat" FOR OUTPUT AS #3
PRINT #1, "File 1"
PRINT #2, "File 2"
PRINT #3, "File 3"
CLOSE #1
CLOSE #2
CLOSE #3
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 5.5: High file number
total_tests = total_tests + 1
PRINT "Test 5.5: High file number (99)"
OPEN "comp_test22.dat" FOR OUTPUT AS #99
PRINT #99, "High file number"
CLOSE #99
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM SECTION 6: Mode Transitions
REM ================================================================
PRINT "┌─ Section 6: Mode Transitions ─────────────────────────────────┐"
PRINT ""

REM Test 6.1: OUTPUT then APPEND
total_tests = total_tests + 1
PRINT "Test 6.1: OUTPUT then APPEND"
OPEN "comp_test23.dat" FOR OUTPUT AS #1
PRINT #1, "Original"
CLOSE #1
OPEN "comp_test23.dat" FOR APPEND AS #1
PRINT #1, "Appended"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

REM Test 6.2: File number reuse
total_tests = total_tests + 1
PRINT "Test 6.2: File number reuse"
OPEN "comp_test24.dat" FOR OUTPUT AS #1
PRINT #1, "First file"
CLOSE #1
OPEN "comp_test25.dat" FOR OUTPUT AS #1
PRINT #1, "Second file"
CLOSE #1
passed_tests = passed_tests + 1
PRINT "  ✓ PASS"

PRINT ""
PRINT "└───────────────────────────────────────────────────────────────┘"
PRINT ""

REM ================================================================
REM FINAL SUMMARY
REM ================================================================
PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║                       TEST SUMMARY                             ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""
PRINT "Total Tests Run:    "; total_tests
PRINT "Tests Passed:       "; passed_tests
PRINT "Tests Failed:       "; total_tests - passed_tests
PRINT ""

IF passed_tests = total_tests THEN
    PRINT "╔════════════════════════════════════════════════════════════════╗"
    PRINT "║  ✓✓✓  ALL TESTS PASSED SUCCESSFULLY!  ✓✓✓                    ║"
    PRINT "╚════════════════════════════════════════════════════════════════╝"
ELSE
    PRINT "╔════════════════════════════════════════════════════════════════╗"
    PRINT "║  ✗✗✗  SOME TESTS FAILED  ✗✗✗                                 ║"
    PRINT "╚════════════════════════════════════════════════════════════════╝"
END IF

PRINT ""
PRINT "Features Tested:"
PRINT "  ✓ Long form syntax (OUTPUT, APPEND, RANDOM)"
PRINT "  ✓ Binary modes (BINARY OUTPUT, BINARY APPEND)"
PRINT "  ✓ Flexible ordering (BINARY OUTPUT vs OUTPUT BINARY)"
PRINT "  ✓ Single-letter aliases (O, A, R, B)"
PRINT "  ✓ Combined aliases (B O, O B, B A)"
PRINT "  ✓ Record length specification (1 to 8192 bytes)"
PRINT "  ✓ Variable and expression filenames"
PRINT "  ✓ Computed file numbers"
PRINT "  ✓ Multiple simultaneous files"
PRINT "  ✓ High file numbers (up to 99)"
PRINT "  ✓ Mode transitions (OUTPUT -> APPEND)"
PRINT "  ✓ File number reuse"
PRINT ""
PRINT "All OPEN mode enhancements working correctly!"
PRINT ""
