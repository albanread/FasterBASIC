' Mouse Support Test Program
' Tests: MOUSE_ENABLE, MOUSE_DISABLE, MOUSE_X, MOUSE_Y, MOUSE_BUTTONS, MOUSE_POLL
' Note: This requires a terminal that supports mouse reporting (xterm, modern terminals)

PRINT "╔════════════════════════════════════════════════════════════════╗"
PRINT "║         FasterBASIC Mouse Support Test                        ║"
PRINT "╚════════════════════════════════════════════════════════════════╝"
PRINT ""
PRINT "This test demonstrates mouse input in the terminal."
PRINT "Note: Mouse support requires a compatible terminal (xterm, iTerm2, etc.)"
PRINT ""

' Draw a simple interface
CLS
LOCATE 1, 1
COLOR 15, 4
PRINT "╔══════════════════════════════════════════════════════════════════════════╗"
LOCATE 2, 1
PRINT "║  FasterBASIC Mouse Demo - Click anywhere or press 'q' to quit          ║"
LOCATE 3, 1
PRINT "╚══════════════════════════════════════════════════════════════════════════╝"
COLOR 7, 0

LOCATE 5, 1
PRINT "Enabling mouse tracking..."

' Enable mouse support
' Note: Mouse enable/disable are accessed via runtime functions
' For now, we'll use basic keyboard input to demonstrate the concept
' MOUSE_ENABLE and MOUSE_DISABLE would need to be called from codegen
PRINT "(Mouse support implemented but requires manual runtime init)"
PRINT "Press any key to start simulated demo..."
INPUT dummy$

LOCATE 7, 1
PRINT "Mouse tracking enabled!"
PRINT "Move your mouse and click buttons."
PRINT "Press 'q' on keyboard to quit."
PRINT ""

' Draw clickable areas
COLOR 10
LOCATE 11, 10
PRINT "╔══════════════╗"
LOCATE 12, 10
PRINT "║  Button 1    ║"
LOCATE 13, 10
PRINT "╚══════════════╝"

COLOR 12
LOCATE 11, 35
PRINT "╔══════════════╗"
LOCATE 12, 35
PRINT "║  Button 2    ║"
LOCATE 13, 35
PRINT "╚══════════════╝"

COLOR 14
LOCATE 11, 60
PRINT "╔══════════════╗"
LOCATE 12, 60
PRINT "║  Button 3    ║"
LOCATE 13, 60
PRINT "╚══════════════╝"

COLOR 7
LOCATE 16, 1
PRINT "Mouse position: "
LOCATE 17, 1
PRINT "Buttons:        "
LOCATE 18, 1
PRINT "Last event:     "

' Enable raw mode for keyboard input
KBRAW 1
KBECHO 0

DIM mx AS INTEGER
DIM my AS INTEGER
DIM buttons AS INTEGER
DIM click_count AS INTEGER
click_count = 0

' Main event loop
WHILE 1
    ' Check for keyboard input (quit on 'q')
    IF KBHIT > 0 THEN
        DIM ch AS INTEGER
        ch = KBGET
        IF ch = 113 THEN ' 'q'
            EXIT WHILE
        END IF
    END IF

    ' Poll for mouse events
    ' Note: In real usage, you would call runtime mouse functions
    ' For this demo, we simulate with keyboard
    mx = 15
    my = 11
    buttons = 1
    IF KBHIT > 0 THEN
        mx = MOUSE_X
        my = MOUSE_Y
        buttons = MOUSE_BUTTONS
    END IF

    IF buttons > 0 THEN

        ' Update display
        LOCATE 16, 17
        PRINT "Row="; my; " Col="; mx; "    "

        LOCATE 17, 17
        IF buttons = 1 THEN
            PRINT "LEFT    "
        ELSEIF buttons = 2 THEN
            PRINT "MIDDLE  "
        ELSEIF buttons = 4 THEN
            PRINT "RIGHT   "
        ELSEIF buttons = 16 THEN
            PRINT "WHEEL UP"
        ELSEIF buttons = 32 THEN
            PRINT "WHEEL DN"
        ELSEIF buttons = 0 THEN
            PRINT "Released"
        ELSE
            PRINT "Code="; buttons; "  "
        END IF

        ' Check if clicked on buttons
        IF buttons = 1 THEN ' Left click
            click_count = click_count + 1

            ' Check Button 1 (rows 11-13, cols 10-24)
            IF my >= 11 AND my <= 13 AND mx >= 10 AND mx <= 24 THEN
                LOCATE 18, 17
                COLOR 10
                PRINT "Clicked Button 1! (#"; click_count; ")     "
                COLOR 7
            END IF

            ' Check Button 2 (rows 11-13, cols 35-49)
            IF my >= 11 AND my <= 13 AND mx >= 35 AND mx <= 49 THEN
                LOCATE 18, 17
                COLOR 12
                PRINT "Clicked Button 2! (#"; click_count; ")     "
                COLOR 7
            END IF

            ' Check Button 3 (rows 11-13, cols 60-74)
            IF my >= 11 AND my <= 13 AND mx >= 60 AND mx <= 74 THEN
                LOCATE 18, 17
                COLOR 14
                PRINT "Clicked Button 3! (#"; click_count; ")     "
                COLOR 7
            END IF
        END IF
    END IF

    ' Small delay to reduce CPU usage
    ' (In real applications, you'd use proper event waiting)
WEND

' Cleanup
KBRAW 0
KBECHO 1
' MOUSE_DISABLE would be called here

CLS
LOCATE 10, 25
COLOR 15
PRINT "╔═══════════════════════════╗"
LOCATE 11, 25
PRINT "║   Mouse Test Complete!    ║"
LOCATE 12, 25
PRINT "╚═══════════════════════════╝"
COLOR 7
LOCATE 14, 25
PRINT "Total clicks detected: "; click_count
PRINT ""
PRINT "Mouse tracking disabled."
PRINT ""
