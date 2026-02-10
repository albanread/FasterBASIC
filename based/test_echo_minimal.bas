REM Minimal Echo Test - Check if ECHO is actually disabled in raw mode

PRINT "Minimal Raw Mode Echo Test"
PRINT "=========================="
PRINT ""
PRINT "This will test if characters are being echoed when they shouldn't be."
PRINT ""
PRINT "Step 1: Normal mode - type 'abc' and press Enter:"
INPUT test$
PRINT "Normal mode: You typed '"; test$; "'"
PRINT ""

PRINT "Step 2: Enabling raw mode with ECHO disabled..."
KBRAW 1
PRINT "Raw mode enabled."
PRINT ""
PRINT "Now press 3 keys (a, b, c). They should NOT appear on screen!"
PRINT "If you see the letters echoing, ECHO is NOT disabled."
PRINT ""

key1 = KBGET
key2 = KBGET
key3 = KBGET

KBRAW 0
PRINT ""
PRINT "Raw mode disabled."
PRINT ""
PRINT "Results:"
PRINT "  Key 1: "; key1; " = '"; CHR$(key1); "'"
PRINT "  Key 2: "; key2; " = '"; CHR$(key2); "'"
PRINT "  Key 3: "; key3; " = '"; CHR$(key3); "'"
PRINT ""
PRINT "If you SAW the letters appear above while typing, ECHO is broken!"
PRINT "If you did NOT see them, ECHO is working correctly."
