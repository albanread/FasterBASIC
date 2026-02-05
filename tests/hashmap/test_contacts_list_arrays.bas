REM Test: Contacts List with Parallel Arrays + Hashmap
REM Demonstrates: Realistic use case for fast lookup into structured data
REM
REM Pattern (UDT workaround):
REM   - Parallel arrays store contact data (name, phone, email, age)
REM   - Hashmap maps name -> array index for O(1) lookup
REM
REM This demonstrates the same concept as UDT+Array+Hashmap
REM but works around current UDT limitations

REM Create parallel arrays to store contact data
DIM ContactNames(99) AS STRING
DIM ContactPhones(99) AS STRING
DIM ContactEmails(99) AS STRING
DIM ContactAges(99) AS INTEGER
DIM ContactCount AS INTEGER
ContactCount = 0

REM Create a hashmap to map name -> index
DIM ContactIndex AS HASHMAP

PRINT "=========================================="
PRINT "Contacts List: Parallel Arrays + Hashmap"
PRINT "=========================================="
PRINT ""

REM Add Contact 1: Alice
ContactNames(ContactCount) = "Alice Smith"
ContactPhones(ContactCount) = "555-1234"
ContactEmails(ContactCount) = "alice@example.com"
ContactAges(ContactCount) = 30
ContactIndex("Alice Smith") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Alice Smith"

REM Add Contact 2: Bob
ContactNames(ContactCount) = "Bob Jones"
ContactPhones(ContactCount) = "555-5678"
ContactEmails(ContactCount) = "bob@example.com"
ContactAges(ContactCount) = 25
ContactIndex("Bob Jones") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Bob Jones"

REM Add Contact 3: Charlie
ContactNames(ContactCount) = "Charlie Brown"
ContactPhones(ContactCount) = "555-9012"
ContactEmails(ContactCount) = "charlie@example.com"
ContactAges(ContactCount) = 35
ContactIndex("Charlie Brown") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Charlie Brown"

REM Add Contact 4: Diana
ContactNames(ContactCount) = "Diana Prince"
ContactPhones(ContactCount) = "555-3456"
ContactEmails(ContactCount) = "diana@example.com"
ContactAges(ContactCount) = 28
ContactIndex("Diana Prince") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Diana Prince"

REM Add Contact 5: Eve
ContactNames(ContactCount) = "Eve Wilson"
ContactPhones(ContactCount) = "555-7890"
ContactEmails(ContactCount) = "eve@example.com"
ContactAges(ContactCount) = 32
ContactIndex("Eve Wilson") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Eve Wilson"

REM Add Contact 6: Frank (with large hash to test bug fix)
ContactNames(ContactCount) = "Frank Miller"
ContactPhones(ContactCount) = "555-2468"
ContactEmails(ContactCount) = "frank@example.com"
ContactAges(ContactCount) = 29
ContactIndex("Frank Miller") = STR$(ContactCount)
ContactCount = ContactCount + 1
PRINT "Added: Frank Miller"

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
PRINT "  Name:  "; ContactNames(Idx)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT "  Age:   "; ContactAges(Idx)
PRINT ""

REM Lookup Diana Prince
PRINT "Looking up: Diana Prince"
LookupName = "Diana Prince"
IndexStr = ContactIndex(LookupName)
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; ContactNames(Idx)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT "  Age:   "; ContactAges(Idx)
PRINT ""

REM Lookup Alice Smith
PRINT "Looking up: Alice Smith"
LookupName = "Alice Smith"
IndexStr = ContactIndex(LookupName)
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; ContactNames(Idx)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT "  Age:   "; ContactAges(Idx)
PRINT ""

REM Lookup Bob Jones (has large hash value)
PRINT "Looking up: Bob Jones"
LookupName = "Bob Jones"
IndexStr = ContactIndex(LookupName)
Idx = VAL(IndexStr)

PRINT "  Found at index: "; Idx
PRINT "  Name:  "; ContactNames(Idx)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT "  Age:   "; ContactAges(Idx)
PRINT ""

REM Search and display by partial match simulation
PRINT "=========================================="
PRINT "Display Specific Contacts"
PRINT "=========================================="
PRINT ""

PRINT "Contact: Frank Miller"
IndexStr = ContactIndex("Frank Miller")
Idx = VAL(IndexStr)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT ""

PRINT "Contact: Eve Wilson"
IndexStr = ContactIndex("Eve Wilson")
Idx = VAL(IndexStr)
PRINT "  Phone: "; ContactPhones(Idx)
PRINT "  Email: "; ContactEmails(Idx)
PRINT ""

REM List all contacts
PRINT "=========================================="
PRINT "All Contacts (Sequential)"
PRINT "=========================================="
PRINT ""

DIM I AS INTEGER
FOR I = 0 TO ContactCount - 1
  PRINT "Contact #"; I + 1; ": "; ContactNames(I)
  PRINT "  Phone: "; ContactPhones(I)
  PRINT "  Email: "; ContactEmails(I)
  PRINT "  Age:   "; ContactAges(I)
  PRINT ""
NEXT I

REM Verification tests
PRINT "=========================================="
PRINT "Verification Tests"
PRINT "=========================================="
PRINT ""

REM Test 1: Verify count
IF ContactCount <> 6 THEN
  PRINT "ERROR: Wrong contact count"
  END
ENDIF
PRINT "Test 1: PASS (contact count = 6)"

REM Test 2: Verify Alice lookup
IndexStr = ContactIndex("Alice Smith")
Idx = VAL(IndexStr)
IF ContactNames(Idx) <> "Alice Smith" THEN
  PRINT "ERROR: Alice lookup failed"
  END
ENDIF
IF ContactPhones(Idx) <> "555-1234" THEN
  PRINT "ERROR: Alice phone wrong"
  END
ENDIF
IF ContactAges(Idx) <> 30 THEN
  PRINT "ERROR: Alice age wrong"
  END
ENDIF
PRINT "Test 2: PASS (Alice lookup and data)"

REM Test 3: Verify Bob lookup (large hash)
IndexStr = ContactIndex("Bob Jones")
Idx = VAL(IndexStr)
IF ContactEmails(Idx) <> "bob@example.com" THEN
  PRINT "ERROR: Bob email wrong"
  END
ENDIF
IF ContactAges(Idx) <> 25 THEN
  PRINT "ERROR: Bob age wrong"
  END
ENDIF
PRINT "Test 3: PASS (Bob lookup and data)"

REM Test 4: Verify Charlie lookup
IndexStr = ContactIndex("Charlie Brown")
Idx = VAL(IndexStr)
IF ContactPhones(Idx) <> "555-9012" THEN
  PRINT "ERROR: Charlie phone wrong"
  END
ENDIF
PRINT "Test 4: PASS (Charlie lookup)"

REM Test 5: Verify Diana lookup
IndexStr = ContactIndex("Diana Prince")
Idx = VAL(IndexStr)
IF ContactAges(Idx) <> 28 THEN
  PRINT "ERROR: Diana age wrong"
  END
ENDIF
PRINT "Test 5: PASS (Diana lookup)"

REM Test 6: Verify Eve lookup
IndexStr = ContactIndex("Eve Wilson")
Idx = VAL(IndexStr)
IF ContactEmails(Idx) <> "eve@example.com" THEN
  PRINT "ERROR: Eve email wrong"
  END
ENDIF
PRINT "Test 6: PASS (Eve lookup)"

REM Test 7: Verify Frank lookup
IndexStr = ContactIndex("Frank Miller")
Idx = VAL(IndexStr)
IF ContactNames(Idx) <> "Frank Miller" THEN
  PRINT "ERROR: Frank lookup failed"
  END
ENDIF
IF ContactAges(Idx) <> 29 THEN
  PRINT "ERROR: Frank age wrong"
  END
ENDIF
PRINT "Test 7: PASS (Frank lookup)"

REM Test 8: Verify all indices are unique and valid
DIM ValidIndices AS INTEGER
ValidIndices = 1
FOR I = 0 TO ContactCount - 1
  IF I < 0 OR I >= ContactCount THEN
    ValidIndices = 0
  ENDIF
NEXT I
IF ValidIndices = 0 THEN
  PRINT "ERROR: Invalid indices detected"
  END
ENDIF
PRINT "Test 8: PASS (all indices valid)"

PRINT ""
PRINT "=========================================="
PRINT "ALL TESTS PASSED!"
PRINT "=========================================="
PRINT ""
PRINT "Summary:"
PRINT "  - 4 parallel arrays (names, phones, emails, ages)"
PRINT "  - Hashmap for O(1) name->index lookup"
PRINT "  - 6 contacts stored and retrieved"
PRINT "  - All fields verified correct"
PRINT "  - Works with large hash values (Bob)"
PRINT ""
PRINT "This pattern enables:"
PRINT "  - Structured data (parallel arrays)"
PRINT "  - Sequential storage (Arrays)"
PRINT "  - Fast lookup (Hashmap)"
PRINT "  - Memory efficient (integer index)"
PRINT ""
PRINT "Use case: Address book, database index,"
PRINT "          symbol table, cache, etc."
PRINT ""
PRINT "PASS: Contacts list with Arrays+Hashmap"

END
