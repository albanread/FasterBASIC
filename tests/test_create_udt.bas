REM ============================================================
REM test_create_udt.bas
REM Test CREATE expression for UDT value-type initialization
REM
REM CREATE TypeName(args...) initializes a stack-allocated TYPE
REM with positional arguments mapped to fields in declaration order.
REM
REM Uses T-prefixed type names (TPoint, TPerson, etc.) to avoid
REM any potential clashes with reserved words.
REM ============================================================

REM --- Define test types ---

TYPE TPoint
  X AS INTEGER
  Y AS INTEGER
END TYPE

TYPE TPerson
  Name AS STRING
  Age AS INTEGER
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

REM --- Test 1: Basic integer UDT creation ---

DIM P AS TPoint = CREATE TPoint(10, 20)
PRINT "Test 1a - TPoint.X: ";
IF P.X = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 1b - TPoint.Y: ";
IF P.Y = 20 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 2: UDT with string and integer fields ---

DIM Pr AS TPerson = CREATE TPerson("Alice", 30)
PRINT "Test 2a - TPerson.Name: ";
IF Pr.Name = "Alice" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2b - TPerson.Age: ";
IF Pr.Age = 30 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 3: Double-precision UDT ---

DIM V AS TVec3 = CREATE TVec3(1.5, 2.5, 3.5)
PRINT "Test 3a - TVec3.X: ";
IF V.X = 1.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3b - TVec3.Y: ";
IF V.Y = 2.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3c - TVec3.Z: ";
IF V.Z = 3.5 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 4: Single-precision UDT (TColor) ---

DIM C AS TColor = CREATE TColor(1.0, 0.5, 0.25, 1.0)
PRINT "Test 4a - TColor.R: ";
IF C.R = 1.0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4b - TColor.G: ";
IF C.G = 0.5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4c - TColor.B: ";
IF C.B = 0.25 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4d - TColor.A: ";
IF C.A = 1.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 5: Assignment with CREATE (not just DIM) ---

DIM Q AS TPoint
Q = CREATE TPoint(100, 200)
PRINT "Test 5a - Assigned TPoint.X: ";
IF Q.X = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 5b - Assigned TPoint.Y: ";
IF Q.Y = 200 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 6: Re-assignment with CREATE ---

Q = CREATE TPoint(300, 400)
PRINT "Test 6a - Re-assigned TPoint.X: ";
IF Q.X = 300 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 6b - Re-assigned TPoint.Y: ";
IF Q.Y = 400 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 7: CREATE with expressions (not just literals) ---

DIM A AS INTEGER = 5
DIM B AS INTEGER = 7
DIM EP AS TPoint = CREATE TPoint(A * 2, B + 3)
PRINT "Test 7a - Expression TPoint.X (5*2=10): ";
IF EP.X = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 7b - Expression TPoint.Y (7+3=10): ";
IF EP.Y = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 8: CREATE with string expressions ---

DIM first$ AS STRING = "Bob"
DIM last$ AS STRING = "Smith"
DIM P2 AS TPerson = CREATE TPerson(first$ + " " + last$, 25)
PRINT "Test 8a - Concat TPerson.Name: ";
IF P2.Name = "Bob Smith" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8b - TPerson.Age: ";
IF P2.Age = 25 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 9: Multiple CREATEs on the same type ---

DIM P3 AS TPerson = CREATE TPerson("Charlie", 40)
DIM P4 AS TPerson = CREATE TPerson("Diana", 35)
PRINT "Test 9a - P3.Name: ";
IF P3.Name = "Charlie" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9b - P4.Name: ";
IF P4.Name = "Diana" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9c - P3.Age: ";
IF P3.Age = 40 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9d - P4.Age: ";
IF P4.Age = 35 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 10: CREATE with function call arguments ---

DIM VP AS TVec3 = CREATE TVec3(SIN(0), COS(0), SQR(4))
PRINT "Test 10a - TVec3.X = SIN(0) = 0: ";
IF VP.X = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10b - TVec3.Y = COS(0) = 1: ";
IF VP.Y = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10c - TVec3.Z = SQR(4) = 2: ";
IF VP.Z = 2 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 11: Copy a CREATEd value to another variable ---

DIM Src AS TPoint = CREATE TPoint(42, 99)
DIM Dst AS TPoint
Dst = Src
PRINT "Test 11a - Copied TPoint.X: ";
IF Dst.X = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 11b - Copied TPoint.Y: ";
IF Dst.Y = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 12: Modify fields after CREATE ---

DIM M AS TPerson = CREATE TPerson("Eve", 28)
M.Age = 29
PRINT "Test 12a - Modified TPerson.Name unchanged: ";
IF M.Name = "Eve" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 12b - Modified TPerson.Age: ";
IF M.Age = 29 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT ""
PRINT "All CREATE UDT tests complete."

END
