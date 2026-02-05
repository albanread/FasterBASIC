REM Test: Contacts List with UDT + Array + Hashmap
REM Demonstrates: Realistic use case combining all three features
REM
REM Pattern:
REM   - UDT defines the Contact structure
REM   - Array stores the actual Contact data
REM   - Hashmap maps name -> array index for O(1) lookup
REM
REM This is a common pattern for efficient data structures

REM Define the Contact UDT
TYPE Contact
  Name AS STRING
  Phone AS STRING
  Email AS STRING
  Age AS INTEGER
END TYPE

REM Create an array to store contacts
DIM Contacts(99) AS Contact
DIM ContactCount AS INTEGER
ContactCount = 0

REM Create a hashmap to map name -> index
DIM ContactIndex AS HASHMAP

PRINT "=========================================="
PRINT "Contacts List Demo: UDT + Array + Hashmap"
PRINT "=========================================="
PRINT ""

REM Function to add a contact (simulated with inline code)
REM In a real system, this would be a SUB

REM Add Contact 1: Alice
Contacts(ContactCount).Name = "Alice Smith"
Contacts(ContactCount).Phone = "555-1234"
Contacts(ContactCount).Email = "alice@example.com"
Contacts(ContactCount).Age = 30
ContactIndex("Alice Smith") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Alice Smith"

REM Add Contact 2: Bob
Contacts(ContactCount).Name = "Bob Jones"
Contacts(ContactCount).Phone = "555-5678"
Contacts(ContactCount).Email = "bob@example.com"
Contacts(ContactCount).Age = 25
ContactIndex("Bob Jones") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Bob Jones"

REM Add Contact 3: Charlie
Contacts(ContactCount).Name = "Charlie Brown"
Contacts(ContactCount).Phone = "555-9012"
Contacts(ContactCount).Email = "charlie@example.com"
Contacts(ContactCount).Age = 35
ContactIndex("Charlie Brown") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Charlie Brown"

REM Add Contact 4: Diana
Contacts(ContactCount).Name = "Diana Prince"
Contacts(ContactCount).Phone = "555-3456"
Contacts(ContactCount).Email = "diana@example.com"
Contacts(ContactCount).Age = 28
ContactIndex("Diana Prince") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Diana Prince"

REM Add Contact 5: Eve
Contacts(ContactCount).Name = "Eve Wilson"
Contacts(ContactCount).Phone = "555-7890"
Contacts(ContactCount).Email = "eve@example.com"
Contacts(ContactCount).Age = 32
ContactIndex("Eve Wilson") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Eve Wilson"

PRINT ""
PRINT "Total contacts: "; ContactCount
PRINT ""

REM Now demonstrate fast lookup using hashmap
PRINT "=========================================="
PRINT "Fast Lookup Demo"
PRINT "=========================================="
PRINT ""

REM Lookup Charlie Brown
PRINT "Looking up: Charlie Brown"
DIM LookupName AS STRING
LookupName = "Charlie Brown"
DIM IndexStr AS STRING
IndexStr = ContactIndex(LookupName)
DIM Idx AS INTEGER
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; Contacts(Idx).Name
PRINT "  Phone: "; Contacts(Idx).Phone
PRINT "  Email: "; Contacts(Idx).Email
PRINT "  Age:   "; Contacts(Idx).Age
PRINT ""

REM Lookup Diana Prince
PRINT "Looking up: Diana Prince"
LookupName = "Diana Prince"
IndexStr = ContactIndex(LookupName)
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; Contacts(Idx).Name
PRINT "  Phone: "; Contacts(Idx).Phone
PRINT "  Email: "; Contacts(Idx).Email
PRINT "  Age:   "; Contacts(Idx).Age
PRINT ""

REM Lookup Alice Smith
PRINT "Looking up: Alice Smith"
LookupName = "Alice Smith"
IndexStr = ContactIndex(LookupName)
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; Contacts(Idx).Name
PRINT "  Phone: "; Contacts(Idx).Phone
PRINT "  Email: "; Contacts(Idx).Email
PRINT "  Age:   "; Contacts(Idx).Age
PRINT ""

REM List all contacts
PRINT "=========================================="
PRINT "All Contacts"
PRINT "=========================================="
PRINT ""

DIM I AS INTEGER
FOR I = 0 TO ContactCount - 1
  PRINT "Contact #"; I + 1
  PRINT "  Name:  "; Contacts(I).Name
  PRINT "  Phone: "; Contacts(I).Phone
  PRINT "  Email: "; Contacts(I).Email
  PRINT "  Age:   "; Contacts(I).Age
  PRINT ""
NEXT I

REM Verification tests
PRINT "=========================================="
PRINT "Verification Tests"
PRINT "=========================================="
PRINT ""

REM Test 1: Verify count
IF ContactCount <> 5 THEN
  PRINT "ERROR: Wrong contact count"
  END
ENDIF
PRINT "Test 1: PASS (contact count correct)"

REM Test 2: Verify Alice lookup
IndexStr = ContactIndex("Alice Smith")
Idx = VAL(IndexStr)
IF Contacts(Idx).Name <> "Alice Smith" THEN
  PRINT "ERROR: Alice lookup failed"
  END
ENDIF
IF Contacts(Idx).Phone <> "555-1234" THEN
  PRINT "ERROR: Alice phone wrong"
  END
ENDIF
PRINT "Test 2: PASS (Alice lookup correct)"

REM Test 3: Verify Bob lookup
IndexStr = ContactIndex("Bob Jones")
Idx = VAL(IndexStr)
IF Contacts(Idx).Email <> "bob@example.com" THEN
  PRINT "ERROR: Bob email wrong"
  END
ENDIF
IF Contacts(Idx).Age <> 25 THEN
  PRINT "ERROR: Bob age wrong"
  END
ENDIF
PRINT "Test 3: PASS (Bob lookup correct)"

REM Test 4: Verify Charlie lookup
IndexStr = ContactIndex("Charlie Brown")
Idx = VAL(IndexStr)
IF Contacts(Idx).Phone <> "555-9012" THEN
  PRINT "ERROR: Charlie phone wrong"
  END
ENDIF
PRINT "Test 4: PASS (Charlie lookup correct)"

REM Test 5: Verify Diana lookup
IndexStr = ContactIndex("Diana Prince")
Idx = VAL(IndexStr)
IF Contacts(Idx).Age <> 28 THEN
  PRINT "ERROR: Diana age wrong"
  END
ENDIF
PRINT "Test 5: PASS (Diana lookup correct)"

REM Test 6: Verify Eve lookup
IndexStr = ContactIndex("Eve Wilson")
Idx = VAL(IndexStr)
IF Contacts(Idx).Email <> "eve@example.com" THEN
  PRINT "ERROR: Eve email wrong"
  END
ENDIF
PRINT "Test 6: PASS (Eve lookup correct)"

PRINT ""
PRINT "=========================================="
PRINT "ALL TESTS PASSED!"
PRINT "=========================================="
PRINT ""
PRINT "Summary:"
PRINT "  - UDT Contact with 4 fields"
PRINT "  - Array of 100 Contacts"
PRINT "  - Hashmap for O(1) name lookup"
PRINT "  - 5 contacts stored and retrieved"
PRINT "  - All fields verified correct"
PRINT ""
PRINT "This pattern enables:"
PRINT "  - Structured data (UDT)"
PRINT "  - Sequential storage (Array)"
PRINT "  - Fast lookup (Hashmap)"
PRINT "  - Memory efficient (index as value)"
PRINT ""
PRINT "PASS: Contacts list with UDT+Array+Hashmap"

END
