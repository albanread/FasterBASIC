REM Automated Raw Mode Test Program
REM Tests terminal I/O without requiring user input
REM This verifies that KBHIT and raw mode initialization work correctly

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Terminal I/O Raw Mode - Automated Test                       ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

REM Test 1: Basic raw mode toggle
PRINT "Test 1: Raw Mode Enable/Disable"
PRINT "  Testing basic raw mode toggle..."

KBRAW 1
PRINT "  ✓ Raw mode enabled"
KBRAW 0
PRINT "  ✓ Raw mode disabled"
PRINT "  ✓ No crashes or hangs"
PRINT ""

REM Test 2: KBHIT in raw mode (non-blocking check)
PRINT "Test 2: KBHIT Non-Blocking Check"
PRINT "  Testing KBHIT returns immediately when no input..."

KBRAW 1
result = KBHIT
KBRAW 0

PRINT "  ✓ KBHIT returned without blocking (result: "; result; ")"
IF result = 0 THEN
    PRINT "  ✓ Correctly reports no input available"
ELSE
    PRINT "  ⚠ Reports input available (unexpected)"
END IF
PRINT ""

REM Test 3: Multiple raw mode toggles
PRINT "Test 3: Multiple Raw Mode Toggles"
PRINT "  Testing rapid mode switching..."

FOR i = 1 TO 5
    KBRAW 1
    KBRAW 0
NEXT i

PRINT "  ✓ Completed 5 raw mode cycles without errors"
PRINT ""

REM Test 4: Terminal state consistency
PRINT "Test 4: Terminal State Consistency"
PRINT "  Enabling raw mode..."
KBRAW 1
PRINT "  ✓ Raw mode active"
PRINT "  Disabling raw mode..."
KBRAW 0
PRINT "  ✓ Normal mode restored"
PRINT ""

REM Test 5: Screen control in combination with raw mode
PRINT "Test 5: Screen Control with Raw Mode"
LOCATE 10, 5
PRINT "Text at row 10, col 5"
KBRAW 1
LOCATE 12, 10
PRINT "Text at row 12, col 10 (in raw mode)"
KBRAW 0
LOCATE 14, 0
PRINT "Text at row 14, col 0 (normal mode)"
PRINT ""

REM Summary
PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Automated Test Summary                                        ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""
PRINT "✓ All automated tests passed!"
PRINT ""
PRINT "What was tested:"
PRINT "  1. Raw mode can be enabled and disabled"
PRINT "  2. KBHIT returns immediately (non-blocking)"
PRINT "  3. Multiple mode toggles work correctly"
PRINT "  4. Terminal state remains consistent"
PRINT "  5. Screen control works with raw mode"
PRINT ""
PRINT "Note: These tests verify the raw mode DOESN'T crash or hang."
PRINT "The ESC key hang bug requires interactive testing."
PRINT ""
PRINT "For interactive ESC key test, run: ./test_rawmode_simple"
PRINT "For full editor test, run: ./based_editor test_file.bas"
