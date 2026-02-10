' Keyboard Input Test Program
' Tests: KBHIT, KBGET, KBRAW, KBECHO, INKEY$, POS, ROW

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║         FasterBASIC Keyboard Input Test                       ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""

' Test 1: Basic keyboard polling (normal mode)
PRINT "Test 1: KBHIT and KBGET (normal mode)"
PRINT "Press any key (will echo)..."
WHILE KBHIT = 0
    ' Wait for keypress
WEND
DIM ch AS INTEGER
ch = KBGET
PRINT "You pressed: ASCII code "; ch

PRINT ""
PRINT "Test 2: INKEY$ function"
PRINT "Press a key within 3 seconds..."
DIM start_time AS DOUBLE
start_time = TIMER
DIM key$ AS STRING
key$ = ""
WHILE TIMER - start_time < 3.0
    key$ = INKEY$
    IF LEN(key$) > 0 THEN
        PRINT "INKEY$ returned: '"; key$; "' (ASCII "; ASC(key$); ")"
        EXIT WHILE
    END IF
WEND
IF LEN(key$) = 0 THEN
    PRINT "No key pressed (timeout)"
END IF

PRINT ""
PRINT "Test 3: Position query functions"
PRINT "Current position: ROW="; ROW; " POS="; POS; " CSRLIN="; CSRLIN

LOCATE 15, 20
PRINT "Moved to (15,20)"
PRINT "Current position: ROW="; ROW; " POS="; POS

PRINT ""
PRINT "Test 4: Raw mode (no echo)"
PRINT "Enabling raw mode and disabling echo..."
KBRAW 1
KBECHO 0

LOCATE 20, 1
PRINT "Press keys (won't echo). Press 'q' to quit."
LOCATE 21, 1
PRINT "Keys pressed: "

DIM keys_pressed AS INTEGER
keys_pressed = 0
WHILE 1
    IF KBHIT > 0 THEN
        ch = KBGET
        IF ch = 113 THEN ' 'q' key
            EXIT WHILE
        END IF
        ' Display key code
        LOCATE 21, 15 + keys_pressed * 4
        PRINT ch;
        keys_pressed = keys_pressed + 1
        IF keys_pressed > 15 THEN EXIT WHILE
    END IF
WEND

' Restore normal mode
KBRAW 0
KBECHO 1

PRINT ""
PRINT ""
PRINT "Test 5: Special keys detection"
PRINT "Press arrow keys, function keys, or ESC to quit"
PRINT "(This test may not work perfectly in all terminals)"
PRINT ""

KBRAW 1
WHILE 1
    IF KBHIT > 0 THEN
        ch = KBGET
        IF ch = 27 THEN ' ESC
            PRINT "ESC pressed - exiting"
            EXIT WHILE
        ELSEIF ch >= 32 AND ch <= 126 THEN
            PRINT "Character: '"; CHR$(ch); "' ("; ch; ")"
        ELSEIF ch > 255 THEN
            PRINT "Special key code: "; ch
            ' Common special key codes (implementation-specific)
            IF ch = 328 THEN PRINT "  -> UP ARROW"
            IF ch = 336 THEN PRINT "  -> DOWN ARROW"
            IF ch = 331 THEN PRINT "  -> LEFT ARROW"
            IF ch = 333 THEN PRINT "  -> RIGHT ARROW"
        ELSE
            PRINT "Control character: "; ch
        END IF
    END IF
WEND

' Restore normal terminal mode
KBRAW 0
KBECHO 1

PRINT ""
PRINT "═══════════════════════════════════════════════════════════════"
PRINT "Keyboard input tests complete!"
PRINT "All functions tested: KBHIT, KBGET, KBRAW, KBECHO, INKEY$"
PRINT "Position functions: POS, ROW, CSRLIN"
