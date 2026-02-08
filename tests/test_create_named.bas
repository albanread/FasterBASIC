REM ============================================================
REM test_create_named.bas
REM Test named-field CREATE syntax for UDT value-type initialization
REM
REM Tests:
REM   - Named-field CREATE with all fields specified
REM   - Named-field CREATE with fields in different order
REM   - Named-field CREATE with partial fields (defaults)
REM   - Named-field CREATE with string fields
REM   - Named-field CREATE with mixed field types
REM   - Named-field CREATE with SINGLE and DOUBLE fields
REM   - Named-field CREATE with nested UDTs
REM   - Named-field CREATE combined with equality comparison
REM   - Named-field CREATE combined with PRINT
REM   - Named-field CREATE in assignment (not just DIM)
REM   - Named-field CREATE with expression arguments
REM   - Positional CREATE still works (regression check)
REM
REM Uses T-prefixed type names to avoid keyword clashes.
REM ============================================================

REM --- Define test types ---

TYPE TPoint
  X AS INTEGER
  Y AS INTEGER
END TYPE

TYPE TVec3
  X AS DOUBLE
  Y AS DOUBLE
  Z AS DOUBLE
END TYPE

TYPE TColor
  R AS SINGLE
  G AS SINGLE
  B AS SINGLE
  A AS SINGLE
END TYPE

TYPE TPerson
  Name AS STRING
  Age AS INTEGER
END TYPE

TYPE TMixed
  ID AS INTEGER
  Label AS STRING
  Score AS DOUBLE
  Active AS INTEGER
END TYPE

TYPE TRect
  TopLeft AS TPoint
  BottomRight AS TPoint
END TYPE

REM ============================================================
REM Test 1: Named-field CREATE with all fields (same order)
REM ============================================================

DIM P1 AS TPoint = CREATE TPoint(X := 10, Y := 20)
PRINT "Test 1a - Named TPoint.X: ";
IF P1.X = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 1b - Named TPoint.Y: ";
IF P1.Y = 20 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 2: Named-field CREATE with fields in reverse order
REM ============================================================

DIM P2 AS TPoint = CREATE TPoint(Y := 99, X := 42)
PRINT "Test 2a - Reversed TPoint.X: ";
IF P2.X = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2b - Reversed TPoint.Y: ";
IF P2.Y = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 3: Named-field CREATE with partial fields (defaults)
REM Only X specified; Y should default to 0
REM ============================================================

DIM P3 AS TPoint = CREATE TPoint(X := 50)
PRINT "Test 3a - Partial TPoint.X: ";
IF P3.X = 50 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3b - Partial TPoint.Y (default 0): ";
IF P3.Y = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 4: Named-field CREATE with only second field
REM ============================================================

DIM P4 AS TPoint = CREATE TPoint(Y := 77)
PRINT "Test 4a - Partial TPoint.X (default 0): ";
IF P4.X = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4b - Partial TPoint.Y: ";
IF P4.Y = 77 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 5: Named-field CREATE with string fields
REM ============================================================

DIM Per1 AS TPerson = CREATE TPerson(Name := "Alice", Age := 30)
PRINT "Test 5a - Named TPerson.Name: ";
IF Per1.Name = "Alice" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 5b - Named TPerson.Age: ";
IF Per1.Age = 30 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 6: Named-field CREATE with string in reverse order
REM ============================================================

DIM Per2 AS TPerson = CREATE TPerson(Age := 25, Name := "Bob")
PRINT "Test 6a - Reversed TPerson.Name: ";
IF Per2.Name = "Bob" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 6b - Reversed TPerson.Age: ";
IF Per2.Age = 25 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 7: Named-field CREATE with partial string type
REM Only Name specified; Age should default to 0
REM ============================================================

DIM Per3 AS TPerson = CREATE TPerson(Name := "Charlie")
PRINT "Test 7a - Partial TPerson.Name: ";
IF Per3.Name = "Charlie" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 7b - Partial TPerson.Age (default 0): ";
IF Per3.Age = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 8: Named-field CREATE with partial — only Age
REM Name should default to empty string
REM ============================================================

DIM Per4 AS TPerson = CREATE TPerson(Age := 40)
PRINT "Test 8a - Partial TPerson.Name (default empty): ";
IF Per4.Name = "" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8b - Partial TPerson.Age: ";
IF Per4.Age = 40 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 9: Named-field CREATE with double-precision fields
REM ============================================================

DIM V1 AS TVec3 = CREATE TVec3(Z := 3.5, X := 1.5, Y := 2.5)
PRINT "Test 9a - Reordered TVec3.X: ";
IF V1.X = 1.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9b - Reordered TVec3.Y: ";
IF V1.Y = 2.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9c - Reordered TVec3.Z: ";
IF V1.Z = 3.5 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 10: Named-field CREATE with partial doubles
REM Only Z specified; X, Y default to 0.0
REM ============================================================

DIM V2 AS TVec3 = CREATE TVec3(Z := 9.9)
PRINT "Test 10a - Partial TVec3.X (default 0): ";
IF V2.X = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10b - Partial TVec3.Y (default 0): ";
IF V2.Y = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10c - Partial TVec3.Z: ";
IF V2.Z = 9.9 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 11: Named-field CREATE with single-precision fields
REM ============================================================

DIM C1 AS TColor = CREATE TColor(A := 1.0, R := 0.5, B := 0.25, G := 0.75)
PRINT "Test 11a - Reordered TColor.R: ";
IF C1.R = 0.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 11b - Reordered TColor.G: ";
IF C1.G = 0.75 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 11c - Reordered TColor.B: ";
IF C1.B = 0.25 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 11d - Reordered TColor.A: ";
IF C1.A = 1.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 12: Named-field CREATE with mixed field types
REM ============================================================

DIM M1 AS TMixed = CREATE TMixed(Score := 3.14, Label := "hello", Active := 1, ID := 42)
PRINT "Test 12a - Mixed.ID: ";
IF M1.ID = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 12b - Mixed.Label: ";
IF M1.Label = "hello" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 12c - Mixed.Score: ";
IF M1.Score = 3.14 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 12d - Mixed.Active: ";
IF M1.Active = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 13: Named-field CREATE with partial mixed fields
REM Only ID and Label specified; Score and Active default
REM ============================================================

DIM M2 AS TMixed = CREATE TMixed(ID := 99, Label := "partial")
PRINT "Test 13a - Partial Mixed.ID: ";
IF M2.ID = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 13b - Partial Mixed.Label: ";
IF M2.Label = "partial" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 13c - Partial Mixed.Score (default 0): ";
IF M2.Score = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 13d - Partial Mixed.Active (default 0): ";
IF M2.Active = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 14: Named-field CREATE in assignment (not DIM)
REM ============================================================

DIM P5 AS TPoint
P5 = CREATE TPoint(Y := 300, X := 100)
PRINT "Test 14a - Assignment TPoint.X: ";
IF P5.X = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 14b - Assignment TPoint.Y: ";
IF P5.Y = 300 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 15: Named-field CREATE re-assignment
REM ============================================================

P5 = CREATE TPoint(X := 999)
PRINT "Test 15a - Re-assigned TPoint.X: ";
IF P5.X = 999 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 15b - Re-assigned TPoint.Y (default 0): ";
IF P5.Y = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 16: Named-field CREATE with expression arguments
REM ============================================================

DIM A AS INTEGER = 5
DIM B AS INTEGER = 7
DIM P6 AS TPoint = CREATE TPoint(Y := B + 3, X := A * 2)
PRINT "Test 16a - Expression TPoint.X (5*2=10): ";
IF P6.X = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 16b - Expression TPoint.Y (7+3=10): ";
IF P6.Y = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 17: Named-field CREATE with string expression
REM ============================================================

DIM first$ AS STRING = "Bob"
DIM last$ AS STRING = "Smith"
DIM Per5 AS TPerson = CREATE TPerson(Age := 25, Name := first$ + " " + last$)
PRINT "Test 17a - String expr Name: ";
IF Per5.Name = "Bob Smith" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 17b - String expr Age: ";
IF Per5.Age = 25 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 18: Named-field CREATE equality comparison
REM Named and positional CREATE with same values should be equal
REM ============================================================

DIM PA AS TPoint = CREATE TPoint(10, 20)
DIM PB AS TPoint = CREATE TPoint(Y := 20, X := 10)
PRINT "Test 18a - Named = Positional (equal): ";
IF PA = PB THEN PRINT "PASS" ELSE PRINT "FAIL"

DIM PC AS TPoint = CREATE TPoint(X := 10, Y := 99)
PRINT "Test 18b - Named <> Positional (not equal): ";
IF PA <> PC THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 19: Named-field CREATE with PRINT
REM ============================================================

DIM PP AS TPoint = CREATE TPoint(Y := 20, X := 10)
PRINT "Test 19 - PRINT named CREATE: ";
PRINT PP

DIM PPer AS TPerson = CREATE TPerson(Age := 30, Name := "Alice")
PRINT "Test 20 - PRINT named TPerson: ";
PRINT PPer

REM ============================================================
REM Test 21: Named-field CREATE with nested UDT member assign
REM ============================================================

DIM R1 AS TRect
R1.TopLeft = CREATE TPoint(Y := 0, X := 0)
R1.BottomRight = CREATE TPoint(X := 640, Y := 480)
PRINT "Test 21a - Nested named TopLeft.X: ";
IF R1.TopLeft.X = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 21b - Nested named TopLeft.Y: ";
IF R1.TopLeft.Y = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 21c - Nested named BottomRight.X: ";
IF R1.BottomRight.X = 640 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 21d - Nested named BottomRight.Y: ";
IF R1.BottomRight.Y = 480 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 22: Named-field CREATE with negative values
REM ============================================================

DIM PN AS TPoint = CREATE TPoint(Y := -20, X := -10)
PRINT "Test 22a - Negative named X: ";
IF PN.X = -10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 22b - Negative named Y: ";
IF PN.Y = -20 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 23: Copy independence after named CREATE
REM ============================================================

DIM Src AS TPoint = CREATE TPoint(X := 42, Y := 99)
DIM Cpy AS TPoint
Cpy = Src
Cpy.X = 999
PRINT "Test 23a - Original unchanged after copy modify: ";
IF Src.X = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 23b - Copy was modified: ";
IF Cpy.X = 999 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 24: Positional CREATE regression check
REM ============================================================

DIM PR AS TPoint = CREATE TPoint(100, 200)
PRINT "Test 24a - Positional still works X: ";
IF PR.X = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 24b - Positional still works Y: ";
IF PR.Y = 200 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 25: Multiple named CREATEs on same type
REM ============================================================

DIM MA AS TPoint = CREATE TPoint(X := 1, Y := 2)
DIM MB AS TPoint = CREATE TPoint(X := 3, Y := 4)
DIM MC AS TPoint = CREATE TPoint(X := 5, Y := 6)
PRINT "Test 25a - MA.X: ";
IF MA.X = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 25b - MB.X: ";
IF MB.X = 3 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 25c - MC.X: ";
IF MC.X = 5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 25d - Sum of Y fields = 12: ";
IF MA.Y + MB.Y + MC.Y = 12 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 26: Empty named CREATE (all defaults)
REM ============================================================

DIM PZ AS TPoint = CREATE TPoint()
PRINT "Test 26a - Empty CREATE X (default 0): ";
IF PZ.X = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 26b - Empty CREATE Y (default 0): ";
IF PZ.Y = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 27: Named-field CREATE with single field specified
REM for a 4-field type
REM ============================================================

DIM M3 AS TMixed = CREATE TMixed(Score := 9.99)
PRINT "Test 27a - Single named field ID (default 0): ";
IF M3.ID = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 27b - Single named field Label (default empty): ";
IF M3.Label = "" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 27c - Single named field Score: ";
IF M3.Score = 9.99 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 27d - Single named field Active (default 0): ";
IF M3.Active = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT ""
PRINT "All named-field CREATE tests complete."

END
