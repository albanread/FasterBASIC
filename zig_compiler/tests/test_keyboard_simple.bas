' Simple Keyboard Input Test Program
' Tests: KBHIT, KBGET, KBRAW, KBECHO, POS, ROW

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║         FasterBASIC Keyboard Input Test (Simple)              ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

' Test 1: Position query functions
PRINT "Test 1: Position query functions"
PRINT "Current position: ROW="; ROW; " POS="; POS; " CSRLIN="; CSRLIN
PRINT ""

LOCATE 8, 20
PRINT "Moved to (8,20)"
LOCATE 9, 20
PRINT "Position: ROW="; ROW; " POS="; POS
PRINT ""

' Test 2: Basic keyboard input (normal mode)
LOCATE 12, 1
PRINT "Test 2: KBHIT and KBGET (normal mode)"
PRINT "Press 5 keys (they will echo)..."

DIM i AS INTEGER
DIM ch AS INTEGER
FOR i = 1 TO 5
    PRINT "Key "; i; ": ";
    WHILE KBHIT = 0
        ' Wait for keypress
    WEND
    ch = KBGET
    PRINT "ASCII "; ch
NEXT i

PRINT ""
PRINT "Test 3: Raw mode (no echo)"
PRINT "Enabling raw mode and disabling echo..."
KBRAW 1
KBECHO 0

LOCATE 22, 1
PRINT "Press 5 keys (won't echo). Current codes: "

DIM keys_pressed AS INTEGER
keys_pressed = 0
WHILE keys_pressed < 5
    IF KBHIT > 0 THEN
        ch = KBGET
        LOCATE 22, 45 + keys_pressed * 5
        PRINT ch;
        keys_pressed = keys_pressed + 1
    END IF
WEND

' Restore normal mode
KBRAW 0
KBECHO 1

PRINT ""
PRINT ""
PRINT "═══════════════════════════════════════════════════════════════"
PRINT "Keyboard input tests complete!"
PRINT "Tested: KBHIT, KBGET, KBRAW, KBECHO, POS, ROW, CSRLIN"
