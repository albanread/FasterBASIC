REM Simple Raw Mode Test Program
REM Tests ESC key and arrow keys without complex data structures

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Terminal I/O Raw Mode Test - Simplified                      ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

REM Test 1: ESC key alone (critical test for hang bug)
PRINT "Test 1: ESC Key Test (Critical - Press ESC)"
PRINT "  This tests if ESC key returns without hanging..."
PRINT "  If this hangs forever, the raw mode fix is NOT working."
PRINT "  If it returns quickly (~0.1 sec), the fix IS working."
PRINT ""
PRINT "  Press ESC key now..."

KBRAW 1
key = KBGET
KBRAW 0

IF key = 27 THEN
    PRINT "  ✓ SUCCESS: ESC key received (code: 27)"
    PRINT "  ✓ NO HANG - Raw mode fix is working!"
ELSE
    PRINT "  ✗ Wrong key pressed (code: "; key; ")"
END IF
PRINT ""

REM Test 2: Arrow keys
PRINT "Test 2: Arrow Key Test"
PRINT "  Press Up Arrow key..."

KBRAW 1
key = KBGET
KBRAW 0

IF key > 255 THEN
    PRINT "  ✓ Arrow key detected (extended code: "; key; ")"
ELSE IF key = 27 THEN
    PRINT "  ⚠ ESC pressed instead (code: 27)"
ELSE
    PRINT "  ⚠ Regular key pressed (code: "; key; ")"
END IF
PRINT ""

REM Test 3: Rapid ESC presses
PRINT "Test 3: Multiple ESC Presses"
PRINT "  Press ESC 3 times in quick succession..."
PRINT ""

KBRAW 1
count = 0
WHILE count < 3
    key = KBGET
    IF key = 27 THEN
        count = count + 1
        PRINT "  ✓ ESC #"; count; " received"
    END IF
WEND
KBRAW 0

PRINT ""
PRINT "  ✓ All 3 ESC keys processed without hanging!"
PRINT ""

REM Summary
PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Test Complete                                                 ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""
PRINT "Results:"
PRINT "  If ESC key returned quickly: Fix is WORKING ✓"
PRINT "  If program hung on ESC: Fix is NOT working ✗"
PRINT ""
PRINT "Next step: Test the editor with 'based_editor test_file.bas'"
