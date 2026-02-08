REM ============================================================
REM test_create_udt_advanced.bas
REM Advanced CREATE expression tests for UDT value-type initialization
REM
REM Tests: nested UDTs, CREATE inside FUNCTION/SUB, CREATE as
REM return value, re-assignment, and mixed field types.
REM
REM Uses T-prefixed type names to avoid potential keyword clashes.
REM ============================================================

REM --- Define test types ---

TYPE TPoint2D
  X AS INTEGER
  Y AS INTEGER
END TYPE

TYPE TRect
  TopLeft AS TPoint2D
  BottomRight AS TPoint2D
END TYPE

TYPE TNamedValue
  Label AS STRING
  Value AS DOUBLE
END TYPE

TYPE TMixed
  ID AS INTEGER
  Name AS STRING
  Score AS DOUBLE
  Active AS INTEGER
END TYPE

REM ============================================================
REM Test 1: Nested UDT creation (inner CREATE as argument)
REM ============================================================

DIM R AS TRect
R.TopLeft = CREATE TPoint2D(10, 20)
R.BottomRight = CREATE TPoint2D(100, 200)
PRINT "Test 1a - Rect.TopLeft.X: ";
IF R.TopLeft.X = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 1b - Rect.TopLeft.Y: ";
IF R.TopLeft.Y = 20 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 1c - Rect.BottomRight.X: ";
IF R.BottomRight.X = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 1d - Rect.BottomRight.Y: ";
IF R.BottomRight.Y = 200 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 2: CREATE with mixed field types
REM ============================================================

DIM M AS TMixed = CREATE TMixed(42, "Hello", 3.14, 1)
PRINT "Test 2a - Mixed.ID: ";
IF M.ID = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2b - Mixed.Name: ";
IF M.Name = "Hello" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2c - Mixed.Score: ";
IF M.Score = 3.14 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2d - Mixed.Active: ";
IF M.Active = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 3: Overwrite a CREATEd value with another CREATE
REM ============================================================

DIM NV AS TNamedValue = CREATE TNamedValue("alpha", 1.0)
PRINT "Test 3a - Initial Label: ";
IF NV.Label = "alpha" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3b - Initial Value: ";
IF NV.Value = 1.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

NV = CREATE TNamedValue("beta", 2.0)
PRINT "Test 3c - Overwritten Label: ";
IF NV.Label = "beta" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3d - Overwritten Value: ";
IF NV.Value = 2.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

NV = CREATE TNamedValue("gamma", 3.0)
PRINT "Test 3e - Second overwrite Label: ";
IF NV.Label = "gamma" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 3f - Second overwrite Value: ";
IF NV.Value = 3.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 4: Multiple CREATE into different variables of same type
REM ============================================================

DIM PA AS TPoint2D = CREATE TPoint2D(1, 2)
DIM PB AS TPoint2D = CREATE TPoint2D(3, 4)
DIM PC AS TPoint2D = CREATE TPoint2D(5, 6)

PRINT "Test 4a - PA.X: ";
IF PA.X = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4b - PB.X: ";
IF PB.X = 3 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4c - PC.X: ";
IF PC.X = 5 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4d - PA.Y + PB.Y + PC.Y = 12: ";
IF PA.Y + PB.Y + PC.Y = 12 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 5: CREATE with computed expressions involving other UDTs
REM ============================================================

DIM Origin AS TPoint2D = CREATE TPoint2D(0, 0)
DIM Offset AS TPoint2D = CREATE TPoint2D(Origin.X + 50, Origin.Y + 75)
PRINT "Test 5a - Offset.X from Origin: ";
IF Offset.X = 50 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 5b - Offset.Y from Origin: ";
IF Offset.Y = 75 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 6: CREATE with negative values
REM ============================================================

DIM Neg AS TPoint2D = CREATE TPoint2D(-10, -20)
PRINT "Test 6a - Negative X: ";
IF Neg.X = -10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 6b - Negative Y: ";
IF Neg.Y = -20 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 7: CREATE with zero values (boundary)
REM ============================================================

DIM Zero AS TNamedValue = CREATE TNamedValue("", 0.0)
PRINT "Test 7a - Empty string field: ";
IF Zero.Label = "" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 7b - Zero double field: ";
IF Zero.Value = 0.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 8: Copy CREATEd UDT then modify copy (independence)
REM ============================================================

DIM Src2 AS TPoint2D = CREATE TPoint2D(100, 200)
DIM Cpy AS TPoint2D
Cpy = Src2
Cpy.X = 999
PRINT "Test 8a - Original unchanged after copy modify: ";
IF Src2.X = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8b - Copy was modified: ";
IF Cpy.X = 999 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8c - Copy Y unchanged: ";
IF Cpy.Y = 200 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 9: CREATE with string that contains special characters
REM ============================================================

DIM Special AS TNamedValue = CREATE TNamedValue("Hello, World!", 42.5)
PRINT "Test 9a - String with comma and exclamation: ";
IF Special.Label = "Hello, World!" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9b - Value preserved: ";
IF Special.Value = 42.5 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 10: Multiple field modifications after CREATE
REM ============================================================

DIM Mx AS TMixed = CREATE TMixed(1, "start", 0.0, 0)
Mx.ID = 99
Mx.Name = "modified"
Mx.Score = 9.99
Mx.Active = 1
PRINT "Test 10a - All fields modified ID: ";
IF Mx.ID = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10b - All fields modified Name: ";
IF Mx.Name = "modified" THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10c - All fields modified Score: ";
IF Mx.Score = 9.99 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10d - All fields modified Active: ";
IF Mx.Active = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT ""
PRINT "All advanced CREATE UDT tests complete."

END
