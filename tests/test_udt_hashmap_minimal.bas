REM Minimal reproduction of UDT array crash
REM Isolate: VAL conversion vs direct assignment

TYPE Contact
  Name AS STRING
  Phone AS STRING
END TYPE

DIM Contacts(9) AS Contact

Contacts(2).Name = "Charlie"
Contacts(2).Phone = "555-9012"

PRINT "=== Test 1: Literal index ==="
PRINT "Name = "; Contacts(2).Name
PRINT "Phone = "; Contacts(2).Phone
PRINT "Test 1 OK"
PRINT ""

PRINT "=== Test 2: Variable assigned directly ==="
DIM Idx AS INTEGER
Idx = 2
PRINT "Name = "; Contacts(Idx).Name
PRINT "Phone = "; Contacts(Idx).Phone
PRINT "Test 2 OK"
PRINT ""

PRINT "=== Test 3: Variable from VAL ==="
DIM ValIdx AS INTEGER
ValIdx = VAL("2")
PRINT "ValIdx = "; ValIdx
PRINT "Name = "; Contacts(ValIdx).Name
PRINT "Phone = "; Contacts(ValIdx).Phone
PRINT "Test 3 OK"
PRINT ""

PRINT "=== Test 4: INT conversion ==="
DIM IntIdx AS INTEGER
DIM TmpDbl AS DOUBLE
TmpDbl = 2.0
IntIdx = INT(TmpDbl)
PRINT "IntIdx = "; IntIdx
PRINT "Name = "; Contacts(IntIdx).Name
PRINT "Phone = "; Contacts(IntIdx).Phone
PRINT "Test 4 OK"
PRINT ""

PRINT "=== Test 5: dtosi from literal double ==="
DIM DtosiIdx AS INTEGER
DtosiIdx = 2.0
PRINT "DtosiIdx = "; DtosiIdx
PRINT "Name = "; Contacts(DtosiIdx).Name
PRINT "Phone = "; Contacts(DtosiIdx).Phone
PRINT "Test 5 OK"
PRINT ""

PRINT "ALL TESTS PASSED"
END
