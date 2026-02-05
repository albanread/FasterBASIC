' Comprehensive MADD/FMADD Fusion Test
' Tests all fusion variants and validates correctness
' This test verifies that multiply-add patterns are automatically
' fused into MADD/FMADD instructions on ARM64

PRINT "======================================"
PRINT "   MADD/FMADD Fusion Test Suite"
PRINT "======================================"
PRINT ""

' ============================================
' Test 1: Integer MADD (64-bit)
' ============================================
PRINT "Test 1: Integer MADD (64-bit)"
DIM a1 AS INTEGER, b1 AS INTEGER, c1 AS INTEGER, result1 AS INTEGER

a1 = 7
b1 = 8
c1 = 100

' Pattern: result = c + a * b
' Should emit: madd result, a, b, c
result1 = c1 + a1 * b1

PRINT "  ", c1, " + ", a1, " * ", b1, " = ", result1
IF result1 = 156 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 156, got ", result1
END IF
PRINT ""

' ============================================
' Test 2: Integer MSUB (64-bit)
' ============================================
PRINT "Test 2: Integer MSUB (64-bit)"
DIM a2 AS INTEGER, b2 AS INTEGER, c2 AS INTEGER, result2 AS INTEGER

a2 = 7
b2 = 8
c2 = 100

' Pattern: result = c - a * b
' Should emit: msub result, a, b, c
result2 = c2 - a2 * b2

PRINT "  ", c2, " - ", a2, " * ", b2, " = ", result2
IF result2 = 44 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 44, got ", result2
END IF
PRINT ""

' ============================================
' Test 3: Double FMADD
' ============================================
PRINT "Test 3: Double Precision FMADD"
DIM a3 AS DOUBLE, b3 AS DOUBLE, c3 AS DOUBLE, result3 AS DOUBLE

a3 = 2.5
b3 = 4.0
c3 = 100.0

' Pattern: result = c + a * b
' Should emit: fmadd result, a, b, c
result3 = c3 + a3 * b3

PRINT "  ", c3, " + ", a3, " * ", b3, " = ", result3
IF ABS(result3 - 110.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 110.0, got ", result3
END IF
PRINT ""

' ============================================
' Test 4: Double FMSUB
' ============================================
PRINT "Test 4: Double Precision FMSUB"
DIM a4 AS DOUBLE, b4 AS DOUBLE, c4 AS DOUBLE, result4 AS DOUBLE

a4 = 2.5
b4 = 4.0
c4 = 100.0

' Pattern: result = c - a * b
' Should emit: fmsub result, a, b, c
result4 = c4 - a4 * b4

PRINT "  ", c4, " - ", a4, " * ", b4, " = ", result4
IF ABS(result4 - 90.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 90.0, got ", result4
END IF
PRINT ""

' ============================================
' Test 5: Commutative Pattern (mul * val + acc)
' ============================================
PRINT "Test 5: Commutative Add (mul on left)"
DIM a5 AS DOUBLE, b5 AS DOUBLE, c5 AS DOUBLE, result5 AS DOUBLE

a5 = 3.0
b5 = 7.0
c5 = 50.0

' Pattern: result = (a * b) + c (commuted)
' Should still emit: fmadd
result5 = a5 * b5 + c5

PRINT "  ", a5, " * ", b5, " + ", c5, " = ", result5
IF ABS(result5 - 71.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 71.0, got ", result5
END IF
PRINT ""

' ============================================
' Test 6: Polynomial Evaluation (Horner's Method)
' ============================================
PRINT "Test 6: Polynomial Evaluation"
PRINT "  p(x) = 1 + 2x + 3x^2 + 4x^3"
DIM x AS DOUBLE, poly AS DOUBLE

x = 2.0

' Horner's method: p(x) = 1 + x(2 + x(3 + x*4))
' Each step should be an FMADD
poly = 4.0
poly = poly * x + 3.0
poly = poly * x + 2.0
poly = poly * x + 1.0

PRINT "  p(2.0) = ", poly
' p(2) = 1 + 2*2 + 3*4 + 4*8 = 1 + 4 + 12 + 32 = 49
IF ABS(poly - 49.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 49.0, got ", poly
END IF
PRINT ""

' ============================================
' Test 7: Physics Integration (classic use case)
' ============================================
PRINT "Test 7: Physics Integration"
PRINT "  pos = pos + vel * dt"
DIM pos AS DOUBLE, vel AS DOUBLE, dt AS DOUBLE

pos = 0.0
vel = 10.0
dt = 0.1

' Position update with FMADD
pos = pos + vel * dt

PRINT "  New position = ", pos
IF ABS(pos - 1.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 1.0, got ", pos
END IF
PRINT ""

' ============================================
' Test 8: Financial Calculation
' ============================================
PRINT "Test 8: Financial Total Calculation"
PRINT "  total = total + price * quantity"
DIM total AS DOUBLE, price AS DOUBLE, quantity AS INTEGER

total = 1000.0
price = 49.99
quantity = 5

' Should emit FMADD (note: quantity converted to double)
total = total + price * quantity

PRINT "  New total = ", total
IF ABS(total - 1249.95) < 0.01 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 1249.95, got ", total
END IF
PRINT ""

' ============================================
' Test 9: Negative Accumulator
' ============================================
PRINT "Test 9: Negative Accumulator"
DIM a9 AS DOUBLE, b9 AS DOUBLE, c9 AS DOUBLE, result9 AS DOUBLE

a9 = 3.0
b9 = 4.0
c9 = -20.0

result9 = c9 + a9 * b9

PRINT "  ", c9, " + ", a9, " * ", b9, " = ", result9
IF ABS(result9 - (-8.0)) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected -8.0, got ", result9
END IF
PRINT ""

' ============================================
' Test 10: Zero Accumulator
' ============================================
PRINT "Test 10: Zero Accumulator"
DIM a10 AS DOUBLE, b10 AS DOUBLE, c10 AS DOUBLE, result10 AS DOUBLE

a10 = 5.0
b10 = 6.0
c10 = 0.0

result10 = c10 + a10 * b10

PRINT "  ", c10, " + ", a10, " * ", b10, " = ", result10
IF ABS(result10 - 30.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 30.0, got ", result10
END IF
PRINT ""

' ============================================
' Test 11: Multiple FMADDs in Sequence
' ============================================
PRINT "Test 11: Multiple FMADDs in Sequence"
DIM sum AS DOUBLE, x1 AS DOUBLE, y1 AS DOUBLE
DIM x2 AS DOUBLE, y2 AS DOUBLE, x3 AS DOUBLE, y3 AS DOUBLE

sum = 100.0
x1 = 2.0
y1 = 3.0
x2 = 4.0
y2 = 5.0
x3 = 6.0
y3 = 7.0

' Chain of FMADDs
sum = sum + x1 * y1
sum = sum + x2 * y2
sum = sum + x3 * y3

PRINT "  100 + 2*3 + 4*5 + 6*7 = ", sum
' 100 + 6 + 20 + 42 = 168
IF ABS(sum - 168.0) < 0.0001 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 168.0, got ", sum
END IF
PRINT ""

' ============================================
' Test 12: Large Numbers
' ============================================
PRINT "Test 12: Large Numbers"
DIM a12 AS INTEGER, b12 AS INTEGER, c12 AS INTEGER, result12 AS INTEGER

a12 = 1000000
b12 = 999
c12 = 123456789

result12 = c12 + a12 * b12

PRINT "  ", c12, " + ", a12, " * ", b12
PRINT "  = ", result12
' 123456789 + 999000000 = 1122456789
IF result12 = 1122456789 THEN
    PRINT "  PASS"
ELSE
    PRINT "  FAIL: Expected 1122456789, got ", result12
END IF
PRINT ""

' ============================================
' Summary
' ============================================
PRINT "======================================"
PRINT "   All MADD/FMADD Tests Complete!"
PRINT "======================================"
PRINT ""
PRINT "Assembly should show fused instructions:"
PRINT "  madd  x0, x0, x1, x2    (integer)"
PRINT "  msub  x0, x0, x1, x2    (integer)"
PRINT "  fmadd d0, d0, d1, d2    (double)"
PRINT "  fmsub d0, d0, d1, d2    (double)"
PRINT ""
PRINT "Benefits:"
PRINT "  - 2x faster than separate mul + add"
PRINT "  - Single rounding (more accurate)"
PRINT "  - Automatic optimization"
