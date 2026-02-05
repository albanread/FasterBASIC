REM Complete UDT Demo: Arrays, Nesting, and All Features

PRINT "=== Complete UDT Feature Demo ==="
PRINT ""

REM Define nested UDT structures
TYPE Address
  Street AS STRING
  ZipCode AS LONG
END TYPE

TYPE Person
  Name AS STRING
  Age AS INTEGER
  Home AS Address
END TYPE

REM Create an array of persons (heap-allocated UDTs!)
DIM People(2) AS Person

PRINT "Setting up person records..."
People(0).Name = "Alice"
People(0).Age = 30
People(0).Home.Street = "123 Main St"
People(0).Home.ZipCode = 90210

People(1).Name = "Bob"
People(1).Age = 25
People(1).Home.Street = "456 Oak Ave"
People(1).Home.ZipCode = 94102

PRINT ""
PRINT "Person Database:"
PRINT "  [0] "; People(0).Name; ", age "; People(0).Age
PRINT "      Lives at: "; People(0).Home.Street
PRINT "      ZIP: "; People(0).Home.ZipCode
PRINT ""
PRINT "  [1] "; People(1).Name; ", age "; People(1).Age
PRINT "      Lives at: "; People(1).Home.Street
PRINT "      ZIP: "; People(1).Home.ZipCode

PRINT ""
PRINT "Testing conditions with nested UDTs..."
IF People(0).Name = "Alice" AND People(0).Home.ZipCode = 90210 THEN
  PRINT "  Alice's record: CORRECT"
END IF

IF People(1).Age = 25 AND People(1).Home.Street = "456 Oak Ave" THEN
  PRINT "  Bob's record: CORRECT"
END IF

PRINT ""
PRINT "=== All UDT features working! ==="
PRINT "  - Arrays of UDTs (heap allocation)"
PRINT "  - Nested UDTs (Address inside Person)"
PRINT "  - Multi-level access (Person.Home.Street)"
PRINT "  - All basic types (STRING, INTEGER, LONG)"
PRINT "  - Logical operators with UDT fields"
END
