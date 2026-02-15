' Comprehensive Terminal I/O Demo
' Demonstrates CLS, LOCATE, COLOR, GCLS, and various terminal features

' Header
CLS
LOCATE 1, 1
COLOR 15, 4
PRINT "╔════════════════════════════════════════════════════════════════════════════╗"
LOCATE 2, 1
PRINT "║         FasterBASIC Terminal I/O - Comprehensive Demo                     ║"
LOCATE 3, 1
PRINT "╚════════════════════════════════════════════════════════════════════════════╝"

' Reset colors
COLOR 7, 0

' Test 1: Basic positioning
LOCATE 5, 5
COLOR 14
PRINT "Test 1: Basic LOCATE positioning"
COLOR 7
LOCATE 6, 5
PRINT "Row 6, Column 5"
LOCATE 7, 10
PRINT "Row 7, Column 10"
LOCATE 8, 15
PRINT "Row 8, Column 15"

' Test 2: Color palette
LOCATE 10, 5
COLOR 14
PRINT "Test 2: 16-Color Palette"
COLOR 7

DIM c AS INTEGER
FOR c = 0 TO 15
    LOCATE 11 + c, 5
    COLOR c
    PRINT "Color "; c; " - The quick brown fox jumps over the lazy dog"
NEXT c
COLOR 7

' Test 3: Background colors
LOCATE 28, 5
COLOR 15, 1
PRINT " Blue BG  "
COLOR 15, 2
PRINT " Green BG "
COLOR 0, 14
PRINT " Yellow BG "
COLOR 15, 4
PRINT " Red BG "
COLOR 0, 7
PRINT " Gray BG "

' Wait for user
LOCATE 30, 1
COLOR 7, 0
INPUT "Press Enter to see box drawing demo..."; dummy$

' Clear and show box drawing
GCLS
COLOR 11
LOCATE 5, 20
PRINT "╔══════════════════════════════════╗"
LOCATE 6, 20
PRINT "║  Box Drawing with LOCATE & CLS  ║"
LOCATE 7, 20
PRINT "║                                  ║"
LOCATE 8, 20
PRINT "║  ┌─────────────────────────┐    ║"
LOCATE 9, 20
PRINT "║  │  Nested box example     │    ║"
LOCATE 10, 20
PRINT "║  └─────────────────────────┘    ║"
LOCATE 11, 20
PRINT "║                                  ║"
LOCATE 12, 20
PRINT "╚══════════════════════════════════╝"

COLOR 10
LOCATE 15, 25
PRINT "★ ─── ★ ─── ★ ─── ★ ─── ★"

' Animated positioning demo
COLOR 12
LOCATE 18, 5
PRINT "Animating with LOCATE..."

DIM x AS INTEGER
DIM y AS INTEGER
y = 20

FOR x = 10 TO 60 STEP 2
    LOCATE y, x
    COLOR 9 + (x MOD 7)
    PRINT "█"
NEXT x

' Rainbow bar
LOCATE 22, 10
FOR c = 0 TO 15
    COLOR 15, c
    PRINT "  "
NEXT c
COLOR 7, 0

' Final message
LOCATE 25, 25
COLOR 15, 4
PRINT " ★ DEMO COMPLETE ★ "
COLOR 7, 0

LOCATE 27, 1
PRINT "This demo showed:"
PRINT "  • CLS and GCLS (clear screen)"
PRINT "  • LOCATE (cursor positioning)"
PRINT "  • COLOR (foreground and background)"
PRINT "  • Box drawing characters"
PRINT "  • Animation with positioning"
PRINT ""
COLOR 10
PRINT "Terminal I/O system is fully operational!"
COLOR 7
