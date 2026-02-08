REM ============================================================
REM test_udt_compare_print.bas
REM Test UDT equality comparison (= and <>) and PRINT whole UDT
REM
REM Tests:
REM   - Equality (=) and inequality (<>) for integer UDTs
REM   - Equality for UDTs with DOUBLE fields
REM   - Equality for UDTs with SINGLE fields
REM   - Equality for UDTs with STRING fields
REM   - Equality for UDTs with mixed field types
REM   - Inequality after field modification
REM   - Self-comparison (A = A)
REM   - Comparison after copy (independent values)
REM   - Nested UDT comparison
REM   - PRINT whole UDT (integer, double, string, mixed, nested)
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
END TYPE

TYPE TRect
  TopLeft AS TPoint
  BottomRight AS TPoint
END TYPE

REM ============================================================
REM Test 1: Integer UDT equality (same values)
REM ============================================================

DIM P1 AS TPoint = CREATE TPoint(10, 20)
DIM P2 AS TPoint = CREATE TPoint(10, 20)
PRINT "Test 1a - TPoint equal (same values): ";
IF P1 = P2 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 2: Integer UDT inequality (different values)
REM ============================================================

DIM P3 AS TPoint = CREATE TPoint(10, 20)
DIM P4 AS TPoint = CREATE TPoint(30, 40)
PRINT "Test 2a - TPoint not equal (different values): ";
IF P3 <> P4 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 2b - TPoint = returns false for different: ";
IF P3 = P4 THEN PRINT "FAIL" ELSE PRINT "PASS"

REM ============================================================
REM Test 3: Partial difference (only one field differs)
REM ============================================================

DIM P5 AS TPoint = CREATE TPoint(10, 20)
DIM P6 AS TPoint = CREATE TPoint(10, 99)
PRINT "Test 3a - TPoint partial diff (Y differs): ";
IF P5 <> P6 THEN PRINT "PASS" ELSE PRINT "FAIL"

DIM P7 AS TPoint = CREATE TPoint(99, 20)
DIM P8 AS TPoint = CREATE TPoint(10, 20)
PRINT "Test 3b - TPoint partial diff (X differs): ";
IF P7 <> P8 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 4: Self-comparison (variable compared to itself)
REM ============================================================

DIM PSelf AS TPoint = CREATE TPoint(42, 99)
PRINT "Test 4a - Self-comparison (A = A): ";
IF PSelf = PSelf THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 4b - Self not-equal (A <> A) is false: ";
IF PSelf <> PSelf THEN PRINT "FAIL" ELSE PRINT "PASS"

REM ============================================================
REM Test 5: Comparison after copy
REM ============================================================

DIM Src AS TPoint = CREATE TPoint(100, 200)
DIM Cpy AS TPoint
Cpy = Src
PRINT "Test 5a - Copy equals original: ";
IF Src = Cpy THEN PRINT "PASS" ELSE PRINT "FAIL"

Cpy.X = 999
PRINT "Test 5b - Modified copy not equal to original: ";
IF Src <> Cpy THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 6: Double-precision UDT equality
REM ============================================================

DIM V1 AS TVec3 = CREATE TVec3(1.5, 2.5, 3.5)
DIM V2 AS TVec3 = CREATE TVec3(1.5, 2.5, 3.5)
DIM V3 AS TVec3 = CREATE TVec3(1.5, 2.5, 9.9)
PRINT "Test 6a - TVec3 equal (same doubles): ";
IF V1 = V2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 6b - TVec3 not equal (Z differs): ";
IF V1 <> V3 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 7: Single-precision UDT equality
REM ============================================================

DIM C1 AS TColor = CREATE TColor(1.0, 0.5, 0.25, 1.0)
DIM C2 AS TColor = CREATE TColor(1.0, 0.5, 0.25, 1.0)
DIM C3 AS TColor = CREATE TColor(1.0, 0.5, 0.25, 0.0)
PRINT "Test 7a - TColor equal (same singles): ";
IF C1 = C2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 7b - TColor not equal (A differs): ";
IF C1 <> C3 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 8: String field UDT equality
REM ============================================================

DIM Per1 AS TPerson = CREATE TPerson("Alice", 30)
DIM Per2 AS TPerson = CREATE TPerson("Alice", 30)
DIM Per3 AS TPerson = CREATE TPerson("Bob", 30)
DIM Per4 AS TPerson = CREATE TPerson("Alice", 25)
PRINT "Test 8a - TPerson equal (same name & age): ";
IF Per1 = Per2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8b - TPerson not equal (name differs): ";
IF Per1 <> Per3 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 8c - TPerson not equal (age differs): ";
IF Per1 <> Per4 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 9: Mixed field type UDT equality
REM ============================================================

DIM M1 AS TMixed = CREATE TMixed(1, "hello", 3.14)
DIM M2 AS TMixed = CREATE TMixed(1, "hello", 3.14)
DIM M3 AS TMixed = CREATE TMixed(2, "hello", 3.14)
DIM M4 AS TMixed = CREATE TMixed(1, "world", 3.14)
DIM M5 AS TMixed = CREATE TMixed(1, "hello", 2.71)
PRINT "Test 9a - TMixed equal (all fields same): ";
IF M1 = M2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9b - TMixed not equal (ID differs): ";
IF M1 <> M3 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9c - TMixed not equal (Label differs): ";
IF M1 <> M4 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 9d - TMixed not equal (Score differs): ";
IF M1 <> M5 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 10: Comparison with zero/empty values
REM ============================================================

DIM Z1 AS TPoint = CREATE TPoint(0, 0)
DIM Z2 AS TPoint = CREATE TPoint(0, 0)
PRINT "Test 10a - Zero-valued TPoint equal: ";
IF Z1 = Z2 THEN PRINT "PASS" ELSE PRINT "FAIL"

DIM E1 AS TPerson = CREATE TPerson("", 0)
DIM E2 AS TPerson = CREATE TPerson("", 0)
PRINT "Test 10b - Empty string TPerson equal: ";
IF E1 = E2 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 11: Nested UDT comparison
REM ============================================================

DIM R1 AS TRect
R1.TopLeft = CREATE TPoint(0, 0)
R1.BottomRight = CREATE TPoint(100, 200)

DIM R2 AS TRect
R2.TopLeft = CREATE TPoint(0, 0)
R2.BottomRight = CREATE TPoint(100, 200)

DIM R3 AS TRect
R3.TopLeft = CREATE TPoint(0, 0)
R3.BottomRight = CREATE TPoint(100, 999)

PRINT "Test 11a - TRect equal (same nested points): ";
IF R1 = R2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 11b - TRect not equal (nested Y differs): ";
IF R1 <> R3 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 12: Re-assignment then comparison
REM ============================================================

DIM RA AS TPoint = CREATE TPoint(1, 2)
DIM RB AS TPoint = CREATE TPoint(3, 4)
PRINT "Test 12a - Before re-assign, not equal: ";
IF RA <> RB THEN PRINT "PASS" ELSE PRINT "FAIL"

RB = CREATE TPoint(1, 2)
PRINT "Test 12b - After re-assign, equal: ";
IF RA = RB THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 13: Negative values comparison
REM ============================================================

DIM N1 AS TPoint = CREATE TPoint(-10, -20)
DIM N2 AS TPoint = CREATE TPoint(-10, -20)
DIM N3 AS TPoint = CREATE TPoint(-10, 20)
PRINT "Test 13a - Negative values equal: ";
IF N1 = N2 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 13b - Mixed sign not equal: ";
IF N1 <> N3 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM ============================================================
REM Test 14: PRINT whole integer UDT
REM ============================================================

PRINT ""
PRINT "=== PRINT UDT Tests ==="

DIM PP AS TPoint = CREATE TPoint(10, 20)
PRINT "Test 14 - PRINT TPoint: ";
PRINT PP

REM ============================================================
REM Test 15: PRINT whole double UDT
REM ============================================================

DIM VV AS TVec3 = CREATE TVec3(1.5, 2.5, 3.5)
PRINT "Test 15 - PRINT TVec3: ";
PRINT VV

REM ============================================================
REM Test 16: PRINT whole single-precision UDT
REM ============================================================

DIM CC AS TColor = CREATE TColor(1.0, 0.5, 0.25, 1.0)
PRINT "Test 16 - PRINT TColor: ";
PRINT CC

REM ============================================================
REM Test 17: PRINT UDT with string field
REM ============================================================

DIM PPer AS TPerson = CREATE TPerson("Alice", 30)
PRINT "Test 17 - PRINT TPerson: ";
PRINT PPer

REM ============================================================
REM Test 18: PRINT mixed-type UDT
REM ============================================================

DIM MM AS TMixed = CREATE TMixed(42, "hello", 3.14)
PRINT "Test 18 - PRINT TMixed: ";
PRINT MM

REM ============================================================
REM Test 19: PRINT nested UDT
REM ============================================================

DIM RR AS TRect
RR.TopLeft = CREATE TPoint(0, 0)
RR.BottomRight = CREATE TPoint(640, 480)
PRINT "Test 19 - PRINT TRect (nested): ";
PRINT RR

REM ============================================================
REM Test 20: PRINT inline with other items
REM ============================================================

DIM PX AS TPoint = CREATE TPoint(7, 8)
PRINT "Test 20 - Inline: Point is "; PX

PRINT ""
PRINT "All UDT comparison and PRINT tests complete."

END
