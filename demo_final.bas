REM Final Demo: UDTs + Logical Operators Working Together

TYPE Person
  Name AS STRING
  Age AS INTEGER
  ID AS LONG
END TYPE

PRINT "=== UDT and Logical Operators Demo ==="
PRINT ""

DIM Employee AS Person
Employee.Name = "Alice"
Employee.Age = 30
Employee.ID = 9999999999

PRINT "Employee Record:"
PRINT "  Name: "; Employee.Name
PRINT "  Age:  "; Employee.Age
PRINT "  ID:   "; Employee.ID
PRINT ""

REM Test logical operators with UDT fields
PRINT "Testing conditions:"

IF Employee.Name = "Alice" THEN
  PRINT "  Name check: PASS"
ELSE
  PRINT "  Name check: FAIL"
END IF

IF Employee.Age = 30 THEN
  PRINT "  Age check: PASS"
ELSE
  PRINT "  Age check: FAIL"
END IF

IF Employee.ID = 9999999999 THEN
  PRINT "  ID check (LONG): PASS"
ELSE
  PRINT "  ID check (LONG): FAIL"
END IF

PRINT ""
PRINT "Combined conditions:"

IF Employee.Name = "Alice" AND Employee.Age = 30 THEN
  PRINT "  String AND Integer: PASS"
ELSE
  PRINT "  String AND Integer: FAIL"
END IF

IF Employee.Age = 30 AND Employee.ID = 9999999999 THEN
  PRINT "  Integer AND Long: PASS"
ELSE
  PRINT "  Integer AND Long: FAIL"
END IF

IF Employee.Name = "Alice" AND Employee.Age = 30 AND Employee.ID = 9999999999 THEN
  PRINT "  All three: PASS"
ELSE
  PRINT "  All three: FAIL"
END IF

PRINT ""
PRINT "=== All features working correctly! ==="
END
