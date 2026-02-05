' Test MADD/FMADD fusion optimization
' This tests that multiply-add patterns are fused into single instructions

PRINT "=== MADD/FMADD Fusion Test ==="
PRINT ""

' Test 1: Simple double precision multiply-add
PRINT "Test 1: Double precision multiply-add"
DIM a AS DOUBLE, b AS DOUBLE, c AS DOUBLE, result AS DOUBLE

a = 2.0
b = 3.0
c = 5.0

' Pattern: result = c + (a * b)
' Should emit: fmadd result, a, b, c
result = c + a * b

PRINT "  a = ", a
PRINT "  b = ", b
PRINT "  c = ", c
PRINT "  result = c + a * b = ", result
IF ABS(result - 11.0) < 0.0001 THEN
    PRINT "  PASS: Expected 11.0"
ELSE
    PRINT "  FAIL: Expected 11.0, got ", result
END IF
PRINT ""

' Test 2: Commutative add (mul on left)
PRINT "Test 2: Commutative add (mul * val + acc)"
DIM x AS DOUBLE, y AS DOUBLE, acc AS DOUBLE, res2 AS DOUBLE

x = 4.0
y = 5.0
acc = 10.0

' Pattern: result = (x * y) + acc
' Should also emit: fmadd
res2 = x * y + acc

PRINT "  x = ", x
PRINT "  y = ", y
PRINT "  acc = ", acc
PRINT "  res2 = x * y + acc = ", res2
IF ABS(res2 - 30.0) < 0.0001 THEN
    PRINT "  PASS: Expected 30.0"
ELSE
    PRINT "  FAIL: Expected 30.0, got ", res2
END IF
PRINT ""

' Test 3: Subtract pattern (FMSUB)
PRINT "Test 3: Multiply-subtract (FMSUB)"
DIM p AS DOUBLE, q AS DOUBLE, baseVal AS DOUBLE, res3 AS DOUBLE

p = 3.0
q = 4.0
baseVal = 20.0

' Pattern: result = baseVal - (p * q)
' Should emit: fmsub result, p, q, baseVal
res3 = baseVal - p * q

PRINT "  p = ", p
PRINT "  q = ", q
PRINT "  baseVal = ", baseVal
PRINT "  res3 = baseVal - p * q = ", res3
IF ABS(res3 - 8.0) < 0.0001 THEN
    PRINT "  PASS: Expected 8.0"
ELSE
    PRINT "  FAIL: Expected 8.0, got ", res3
END IF
PRINT ""

' Test 4: Integer MADD
PRINT "Test 4: Integer multiply-add (MADD)"
DIM ia AS INTEGER, ib AS INTEGER, ic AS INTEGER, ires AS INTEGER

ia = 5
ib = 6
ic = 100

' Pattern: result = ic + (ia * ib)
' Should emit: madd (integer version)
ires = ic + ia * ib

PRINT "  ia = ", ia
PRINT "  ib = ", ib
PRINT "  ic = ", ic
PRINT "  ires = ic + ia * ib = ", ires
IF ires = 130 THEN
    PRINT "  PASS: Expected 130"
ELSE
    PRINT "  FAIL: Expected 130, got ", ires
END IF
PRINT ""

' Test 5: Cross-statement pattern
PRINT "Test 5: Cross-statement fusion opportunity"
DIM m1 AS DOUBLE, m2 AS DOUBLE, sum AS DOUBLE, temp AS DOUBLE

m1 = 2.5
m2 = 4.0
sum = 100.0

' This creates a temporary that's used once
temp = m1 * m2
sum = sum + temp

PRINT "  m1 = ", m1
PRINT "  m2 = ", m2
PRINT "  temp = m1 * m2 = ", temp
PRINT "  sum = 100.0 + temp = ", sum
IF ABS(sum - 110.0) < 0.0001 THEN
    PRINT "  PASS: Expected 110.0"
ELSE
    PRINT "  FAIL: Expected 110.0, got ", sum
END IF
PRINT ""

PRINT "=== All MADD/FMADD Fusion Tests Complete ==="
