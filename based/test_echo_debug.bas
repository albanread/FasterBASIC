REM Echo Debug Test
REM Simple test to diagnose terminal echo and display issues

PRINT "Echo Debug Test"
PRINT "==============="
PRINT ""
PRINT "Test 1: Normal mode typing"
PRINT "Type 'hello' and press Enter:"
INPUT test$
PRINT "You typed: "; test$
PRINT ""

PRINT "Test 2: Raw mode with KBGET"
PRINT "Enabling raw mode..."
KBRAW 1
PRINT "Raw mode enabled. Press 5 keys (they should NOT echo):"
PRINT ""

count = 0
WHILE count < 5
    key = KBGET
    PRINT "Key code: "; key; " ("; CHR$(key); ")"
    count = count + 1
WEND

KBRAW 0
PRINT ""
PRINT "Raw mode disabled."
PRINT ""

PRINT "Test 3: Check cursor positioning"
CLS
PRINT "Screen cleared. Positioning at row 5, col 10..."
LOCATE 5, 10
PRINT "X"
PRINT ""
LOCATE 10, 20
PRINT "Y"
PRINT ""
LOCATE 15, 0
PRINT "Test complete."
PRINT ""
PRINT "If characters echoed in Test 2, ECHO is not properly disabled."
PRINT "If X and Y are not at specified positions, LOCATE is broken."
