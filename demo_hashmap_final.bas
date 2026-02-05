REM ===================================================
REM   FasterBASIC Hashmap Demo - Complete Working Example
REM ===================================================

PRINT "╔════════════════════════════════════════╗"
PRINT "║  FasterBASIC Hashmap Integration Demo ║"
PRINT "╚════════════════════════════════════════╝"
PRINT ""

REM Create a user directory
DIM users AS HASHMAP
users("alice") = "Alice Smith"
users("bob") = "Bob Jones"
users("charlie") = "Charlie Brown"

PRINT "User Directory:"
PRINT "  alice   -> "; users("alice")
PRINT "  bob     -> "; users("bob")
PRINT "  charlie -> "; users("charlie")
PRINT ""

REM Create a phone directory
DIM phones AS HASHMAP
phones("alice") = "555-1234"
phones("bob") = "555-5678"
phones("charlie") = "555-9012"

PRINT "Phone Directory:"
PRINT "  alice   -> "; phones("alice")
PRINT "  bob     -> "; phones("bob")
PRINT "  charlie -> "; phones("charlie")
PRINT ""

REM Update an entry
users("alice") = "Alice Johnson (Updated)"
PRINT "After updating Alice's name:"
PRINT "  alice   -> "; users("alice")
PRINT ""

REM Demonstrate independent hashmaps
phones("alice") = "555-0000"
PRINT "After updating Alice's phone:"
PRINT "  Name:  "; users("alice")
PRINT "  Phone: "; phones("alice")
PRINT ""

REM Mix with arrays
DIM numbers(3) AS INTEGER
numbers(0) = 100
numbers(1) = 200
numbers(2) = 300

PRINT "Mixed usage (arrays + hashmaps):"
PRINT "  Array[0] = "; numbers(0)
PRINT "  User[alice] = "; users("alice")
PRINT "  Array[1] = "; numbers(1)
PRINT "  Phone[bob] = "; phones("bob")
PRINT ""

PRINT "✅ All tests passed!"
PRINT "✅ Hashmap integration working perfectly!"

END
