REM Terminal Demo
REM Demonstrates terminal I/O features in FasterBASIC
REM This program shows colors, cursor control, and keyboard input

REM Initialize
CLS
KBRAW 1

REM Title screen with colors
COLOR 15, 1
PRINT "                                                                      "
PRINT "              FASTERBASIC TERMINAL I/O DEMONSTRATION                 "
PRINT "                                                                      "
COLOR 7, 0
PRINT
PRINT

REM Color demonstration
PRINT "Color Demonstration:"
PRINT "==================="
PRINT

FOR i = 0 TO 15
    COLOR i, 0
    PRINT "Color "; i; " ";
    COLOR 7, 0
    IF i MOD 4 = 3 THEN PRINT
NEXT i

PRINT
PRINT

REM Background colors
PRINT "Background Colors:"
FOR i = 0 TO 7
    COLOR 15, i
    PRINT " BG "; i; " ";
NEXT i
COLOR 7, 0
PRINT
PRINT
PRINT

REM Cursor positioning demo
PRINT "Cursor Positioning Demo:"
PRINT "========================"
PRINT

LOCATE 10, 15
PRINT "This text is at column 10, row 15"

LOCATE 20, 16
COLOR 10, 0
PRINT "Green text here!"

LOCATE 30, 17
COLOR 14, 0
PRINT "Yellow text!"

LOCATE 0, 18
COLOR 7, 0
PRINT

REM Styles demonstration
PRINT "Text Styles:"
PRINT "============"
PRINT

STYLE_BOLD 1
PRINT "This is BOLD text"
STYLE_BOLD 0

STYLE_ITALIC 1
PRINT "This is ITALIC text"
STYLE_ITALIC 0

STYLE_UNDERLINE 1
PRINT "This is UNDERLINED text"
STYLE_UNDERLINE 0

STYLE_BOLD 1
COLOR 12, 0
PRINT "Bold RED text!"
STYLE_BOLD 0
COLOR 7, 0

PRINT
PRINT

REM Keyboard input demo
COLOR 15, 4
PRINT "                                                                      "
PRINT "                      KEYBOARD INPUT TEST                            "
PRINT "                                                                      "
COLOR 7, 0
PRINT
PRINT "Press keys to see their codes (ESC to continue)..."
PRINT

DIM key AS INTEGER
DO
    key = KBGET()

    IF key = 27 THEN
        EXIT DO
    END IF

    PRINT "Key pressed: ";

    IF key >= 32 AND key < 127 THEN
        PRINT "'"; CHR$(key); "' ";
    END IF

    PRINT "(code: "; key; ")"

    REM Special keys
    IF key = 256 THEN PRINT "  -> Arrow UP"
    IF key = 257 THEN PRINT "  -> Arrow DOWN"
    IF key = 258 THEN PRINT "  -> Arrow LEFT"
    IF key = 259 THEN PRINT "  -> Arrow RIGHT"
    IF key = 260 THEN PRINT "  -> HOME key"
    IF key = 261 THEN PRINT "  -> END key"
    IF key = 262 THEN PRINT "  -> PAGE UP"
    IF key = 263 THEN PRINT "  -> PAGE DOWN"
    IF key = 264 THEN PRINT "  -> DELETE key"
    IF key = 13 THEN PRINT "  -> ENTER key"
    IF key = 8 THEN PRINT "  -> BACKSPACE"
LOOP

REM Clear screen for animation demo
CLS
COLOR 14, 0
PRINT "Animation Demo:"
PRINT "==============="
COLOR 7, 0
PRINT
PRINT "Watch the moving asterisk..."
PRINT

REM Simple animation
DIM x AS INTEGER
DIM y AS INTEGER
DIM dx AS INTEGER
DIM dy AS INTEGER
DIM count AS INTEGER

x = 10
y = 10
dx = 1
dy = 1

FOR count = 1 TO 100
    REM Draw asterisk
    LOCATE x, y
    COLOR 11, 0
    PRINT "*";

    REM Small delay (check for keypress)
    IF KBHIT() THEN
        DIM dummy AS INTEGER
        dummy = KBGET()
        EXIT FOR
    END IF

    REM Erase asterisk
    LOCATE x, y
    PRINT " ";

    REM Update position
    x = x + dx
    y = y + dy

    REM Bounce off edges
    IF x <= 0 OR x >= 70 THEN dx = -dx
    IF y <= 5 OR y >= 20 THEN dy = -dy
NEXT count

REM Final screen
CLS
COLOR 10, 0
PRINT "                                                                      "
PRINT "                    DEMONSTRATION COMPLETE!                          "
PRINT "                                                                      "
COLOR 7, 0
PRINT
PRINT
PRINT "Terminal I/O Features Demonstrated:"
PRINT "  - CLS (clear screen)"
PRINT "  - COLOR (foreground and background)"
PRINT "  - LOCATE (cursor positioning)"
PRINT "  - STYLE_BOLD, STYLE_ITALIC, STYLE_UNDERLINE"
PRINT "  - KBRAW (raw keyboard mode)"
PRINT "  - KBGET (blocking keyboard input)"
PRINT "  - KBHIT (check for key press)"
PRINT "  - Special key detection (arrows, function keys, etc.)"
PRINT
PRINT
COLOR 15, 0
PRINT "Press any key to exit..."
COLOR 7, 0

key = KBGET()

REM Cleanup
KBRAW 0
CLS
PRINT "Thank you for watching the demo!"
