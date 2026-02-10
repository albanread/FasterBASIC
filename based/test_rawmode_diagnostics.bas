REM Raw Mode Diagnostics Test Program
REM Tests the terminal I/O raw mode fixes on macOS
REM This program helps verify that ESC key and escape sequences work correctly

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Terminal I/O Raw Mode Diagnostics                            ║"
PRINT "║  Testing ESC key and escape sequence handling                 ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

REM Test 1: Basic raw mode toggle
PRINT "Test 1: Basic Raw Mode Toggle"
PRINT "  Enabling raw mode..."
KBRAW 1
PRINT "  ✓ Raw mode enabled"
PRINT "  Disabling raw mode..."
KBRAW 0
PRINT "  ✓ Raw mode disabled"
PRINT ""

REM Test 2: ESC key alone (critical test)
PRINT "Test 2: ESC Key Alone (Critical)"
PRINT "  This tests if ESC key returns without hanging"
PRINT "  Press ESC key (program should NOT hang)..."
PRINT "  [Waiting for ESC - timeout in 5 seconds if hanging]"
PRINT ""

KBRAW 1
start_time = 0
timeout = 50  REM 5 seconds in 0.1s units

REM Use non-blocking check with timeout
escaped = 0
WHILE timeout > 0 AND escaped = 0
    IF KBHIT > 0 THEN
        key = KBGET
        IF key = 27 THEN
            escaped = 1
            PRINT "  ✓ ESC key received immediately (code: 27)"
            PRINT "  ✓ NO HANG - Fix is working!"
        ELSE
            PRINT "  ⚠ Wrong key pressed (code: "; key; ")"
        END IF
    END IF
    timeout = timeout - 1
WEND

IF escaped = 0 THEN
    PRINT "  ✗ TIMEOUT - ESC key not received"
    PRINT "  ✗ This indicates the raw mode fix may not be working"
END IF

KBRAW 0
PRINT ""

REM Test 3: Arrow keys (escape sequences)
PRINT "Test 3: Arrow Keys (Escape Sequences)"
PRINT "  Testing if arrow keys return correct codes"
PRINT "  Press: Up, Down, Left, Right (or Q to skip)"
PRINT ""

KBRAW 1
arrow_count = 0
max_arrows = 4

WHILE arrow_count < max_arrows
    IF KBHIT > 0 THEN
        key = KBGET

        IF key = 81 OR key = 113 THEN
            PRINT "  → Skipped by user"
            arrow_count = max_arrows
        ELSE IF key = 256 + 72 OR key = 328 THEN
            PRINT "  ✓ Up Arrow detected (code: "; key; ")"
            arrow_count = arrow_count + 1
        ELSE IF key = 256 + 80 OR key = 336 THEN
            PRINT "  ✓ Down Arrow detected (code: "; key; ")"
            arrow_count = arrow_count + 1
        ELSE IF key = 256 + 75 OR key = 331 THEN
            PRINT "  ✓ Left Arrow detected (code: "; key; ")"
            arrow_count = arrow_count + 1
        ELSE IF key = 256 + 77 OR key = 333 THEN
            PRINT "  ✓ Right Arrow detected (code: "; key; ")"
            arrow_count = arrow_count + 1
        ELSE IF key = 27 THEN
            PRINT "  ⚠ ESC pressed (code: 27)"
        ELSE
            PRINT "  ⚠ Unknown key (code: "; key; ")"
        END IF
    END IF
WEND

KBRAW 0
PRINT ""

REM Test 4: Rapid ESC presses
PRINT "Test 4: Rapid ESC Presses"
PRINT "  Testing multiple ESC presses in quick succession"
PRINT "  Press ESC 3 times rapidly..."
PRINT ""

KBRAW 1
esc_count = 0
timeout = 30  REM 3 seconds

WHILE esc_count < 3 AND timeout > 0
    IF KBHIT > 0 THEN
        key = KBGET
        IF key = 27 THEN
            esc_count = esc_count + 1
            PRINT "  ✓ ESC #"; esc_count; " received"
        END IF
    END IF
    timeout = timeout - 1
WEND

IF esc_count = 3 THEN
    PRINT "  ✓ All ESC keys processed correctly"
    PRINT "  ✓ No hanging or blocking"
ELSE
    PRINT "  ⚠ Only received "; esc_count; " ESC presses"
END IF

KBRAW 0
PRINT ""

REM Test 5: Mixed input (ESC and arrows)
PRINT "Test 5: Mixed Input"
PRINT "  Testing ESC key mixed with arrow keys"
PRINT "  Press: ESC, Up, ESC, Down (or Q to skip)"
PRINT ""

KBRAW 1
mixed_count = 0
expected_pattern$(0) = "ESC"
expected_pattern$(1) = "Up"
expected_pattern$(2) = "ESC"
expected_pattern$(3) = "Down"

WHILE mixed_count < 4
    IF KBHIT > 0 THEN
        key = KBGET
        detected$ = ""

        IF key = 81 OR key = 113 THEN
            PRINT "  → Skipped by user"
            mixed_count = 4
        ELSE IF key = 27 THEN
            detected$ = "ESC"
        ELSE IF key = 256 + 72 OR key = 328 THEN
            detected$ = "Up"
        ELSE IF key = 256 + 80 OR key = 336 THEN
            detected$ = "Down"
        ELSE IF key = 256 + 75 OR key = 331 THEN
            detected$ = "Left"
        ELSE IF key = 256 + 77 OR key = 333 THEN
            detected$ = "Right"
        ELSE
            detected$ = "Unknown"
        END IF

        IF detected$ <> "" AND detected$ <> "Unknown" THEN
            IF detected$ = expected_pattern$(mixed_count) THEN
                PRINT "  ✓ "; detected$; " (expected)"
            ELSE
                PRINT "  ⚠ "; detected$; " (expected "; expected_pattern$(mixed_count); ")"
            END IF
            mixed_count = mixed_count + 1
        ELSE IF detected$ = "Unknown" THEN
            PRINT "  ⚠ Unknown key (code: "; key; ")"
        END IF
    END IF
WEND

KBRAW 0
PRINT ""

REM Test 6: Terminal state restoration
PRINT "Test 6: Terminal State Restoration"
PRINT "  Testing if terminal returns to normal after raw mode"
PRINT ""

PRINT "  Before raw mode - type a character: ";
INPUT normal_char$
PRINT "  ✓ Normal input works"

KBRAW 1
PRINT "  Raw mode enabled - press any key..."
key = KBGET
PRINT "  ✓ Raw key received (code: "; key; ")"
KBRAW 0

PRINT "  After raw mode - type a character: ";
INPUT restored_char$
PRINT "  ✓ Normal input restored"
PRINT ""

REM Summary
PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║  Test Summary                                                  ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""
PRINT "Key Findings:"
PRINT "  1. ESC key alone should return immediately (no hang)"
PRINT "  2. Arrow keys should return extended codes (256+)"
PRINT "  3. Rapid ESC presses should all be processed"
PRINT "  4. Mixed input should work without interference"
PRINT "  5. Terminal state should restore properly"
PRINT ""
PRINT "Expected Behavior After Fix:"
PRINT "  ✓ ESC key timeout = ~0.1 seconds (not forever)"
PRINT "  ✓ Arrow keys parsed correctly as escape sequences"
PRINT "  ✓ No input loss or corruption"
PRINT "  ✓ Terminal returns to normal mode on exit"
PRINT ""
PRINT "If ESC key hangs forever, the raw mode fix is NOT working."
PRINT "If ESC key returns quickly, the fix is WORKING correctly."
PRINT ""
PRINT "Test complete. Thank you!"
