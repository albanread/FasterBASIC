' Test basic terminal I/O commands
' Tests: CLS, LOCATE, COLOR, GCLS

PRINT "Terminal I/O Test - Basic Commands"
PRINT "==================================="
PRINT ""
PRINT "Press Enter to clear screen..."
INPUT dummy$

' Test CLS
CLS
PRINT "Screen cleared with CLS"
PRINT ""

' Test LOCATE
LOCATE 5, 10
PRINT "This is at row 5, column 10"

LOCATE 10, 20
PRINT "This is at row 10, column 20"

LOCATE 15, 1
PRINT "Back to column 1"

' Test COLOR (foreground only)
LOCATE 20, 1
COLOR 14
PRINT "This text is yellow (color 14)"

COLOR 12
PRINT "This text is light red (color 12)"

COLOR 10
PRINT "This text is light green (color 10)"

' Test COLOR with background
LOCATE 24, 1
COLOR 15, 4
PRINT "White on red background"

COLOR 0, 14
PRINT "Black on yellow background"

' Test GCLS (should work same as CLS in text mode)
INPUT "Press Enter to test GCLS..."; dummy$
GCLS

LOCATE 12, 30
PRINT "Screen cleared with GCLS"

PRINT ""
PRINT "Test complete!"
