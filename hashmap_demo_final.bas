REM ============================================
REM   FasterBASIC Hashmap - Working Demo
REM ============================================

PRINT "FasterBASIC Hashmap Integration"
PRINT "================================"
PRINT ""

REM Create a phone directory
DIM phones AS HASHMAP
phones("Alice") = "555-1234"
phones("Bob") = "555-5678"
phones("Charlie") = "555-9012"

PRINT "Phone Directory:"
PRINT "  Alice:   "; phones("Alice")
PRINT "  Bob:     "; phones("Bob")
PRINT "  Charlie: "; phones("Charlie")
PRINT ""

REM Update a number
phones("Alice") = "555-0000"
PRINT "Updated Alice's number:"
PRINT "  Alice:   "; phones("Alice")
PRINT ""

REM Create a second hashmap
DIM emails AS HASHMAP
emails("Alice") = "alice@example.com"
emails("Bob") = "bob@example.com"

PRINT "Email Directory (separate hashmap):"
PRINT "  Alice: "; emails("Alice")
PRINT "  Bob:   "; emails("Bob")
PRINT ""

REM Mix with traditional arrays
DIM scores(3) AS INTEGER
scores(0) = 95
scores(1) = 87
scores(2) = 92

PRINT "Mixing Arrays and Hashmaps:"
PRINT "  Array[0] = "; scores(0)
PRINT "  Phone[Bob] = "; phones("Bob")
PRINT "  Email[Alice] = "; emails("Alice")
PRINT "  Array[2] = "; scores(2)
PRINT ""

PRINT "================================"
PRINT "All Features Working! ✅"
PRINT "================================"

END
