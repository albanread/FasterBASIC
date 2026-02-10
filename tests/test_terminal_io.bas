' Test Terminal I/O Functions
' Tests LOCATE, CLS, COLOR, and cursor positioning

PRINT "=== Terminal I/O Test ==="
PRINT ""
PRINT "Press ENTER after each test..."
INPUT dummy$

' Test 1: LOCATE - Position cursor at specific locations
PRINT "Test 1: LOCATE (cursor positioning)"
LOCATE 5, 10
PRINT "This should be at row 5, column 10"
LOCATE 7, 20
PRINT "This should be at row 7, column 20"
LOCATE 10, 1
PRINT "Back to column 1, row 10"
INPUT dummy$

' Test 2: CLS - Clear screen
PRINT "Test 2: CLS (clear screen)"
PRINT "This text will be cleared in 2 seconds..."
SLEEP 2
CLS
PRINT "Screen cleared! Now at top."
INPUT dummy$

' Test 3: Multiple LOCATE calls
CLS
PRINT "Test 3: Drawing a box with LOCATE"
LOCATE 5, 20
PRINT "+------------+"
LOCATE 6, 20
PRINT "|            |"
LOCATE 7, 20
PRINT "|   HELLO    |"
LOCATE 8, 20
PRINT "|            |"
LOCATE 9, 20
PRINT "+------------+"
LOCATE 12, 1
INPUT dummy$

' Test 4: Menu simulation
CLS
PRINT "Test 4: Menu Display"
LOCATE 3, 30
PRINT "=== MAIN MENU ==="
LOCATE 5, 32
PRINT "1. Start Game"
LOCATE 6, 32
PRINT "2. Options"
LOCATE 7, 32
PRINT "3. Exit"
LOCATE 10, 28
PRINT "Enter choice (1-3):"
LOCATE 15, 1
INPUT dummy$

' Test 5: Status bar simulation
CLS
PRINT "Test 5: Status Bar"
LOCATE 1, 1
PRINT "Top Status Bar: Score=1000 Lives=3 Level=5"
LOCATE 3, 1
PRINT "Main content area starts here..."
LOCATE 4, 1
PRINT "Player position: (10, 20)"
LOCATE 24, 1
PRINT "Bottom Status: Time=120s HP=85%"
LOCATE 10, 1
INPUT dummy$

' Test 6: Centered text
CLS
PRINT "Test 6: Centered Text"
DIM message AS STRING
message = "*** GAME OVER ***"
DIM center AS INTEGER
center = 40 - (LEN(message) / 2)
LOCATE 12, center
PRINT message
LOCATE 20, 1
INPUT dummy$

' Test 7: Countdown
CLS
PRINT "Test 7: Countdown (using LOCATE for updates)"
DIM i AS INTEGER
FOR i = 10 TO 1 STEP -1
    LOCATE 10, 35
    PRINT "Countdown: "; i; "  "
    SLEEP 1
NEXT i
LOCATE 10, 35
PRINT "Blast off!    "
LOCATE 15, 1
INPUT dummy$

' Final cleanup
CLS
PRINT "=== All Terminal I/O Tests Complete ==="
PRINT ""
PRINT "Summary:"
PRINT "  - LOCATE: Cursor positioning works"
PRINT "  - CLS: Screen clearing works"
PRINT "  - Screen coordinates: 1-based (row, col)"
PRINT ""
PRINT "Test completed successfully!"
