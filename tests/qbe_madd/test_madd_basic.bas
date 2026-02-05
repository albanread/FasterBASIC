' Test MADD/FMADD fusion with BASIC code
' These patterns should trigger multiply-add fusion in the ARM64 backend

' Test 1: Simple integer multiply-add
FUNCTION test_madd_int(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    RETURN a + b * c
END FUNCTION

' Test 2: Long integer multiply-add
FUNCTION test_madd_long(a AS LONG, b AS LONG, c AS LONG) AS LONG
    RETURN a + b * c
END FUNCTION

' Test 3: Float multiply-add
FUNCTION test_fmadd_single(a AS SINGLE, b AS SINGLE, c AS SINGLE) AS SINGLE
    RETURN a + b * c
END FUNCTION

' Test 4: Double multiply-add
FUNCTION test_fmadd_double(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    RETURN a + b * c
END FUNCTION

' Test 5: Multiply-subtract pattern
FUNCTION test_msub_int(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    RETURN a - b * c
END FUNCTION

' Test 6: Float multiply-subtract
FUNCTION test_fmsub_double(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    RETURN a - b * c
END FUNCTION

' Test 7: Complex expression with multiple opportunities
FUNCTION test_multiple_madd(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE, d AS DOUBLE) AS DOUBLE
    LOCAL result AS DOUBLE
    result = a + b * c
    result = result + d * a
    RETURN result
END FUNCTION

' Test 8: Matrix-like computation (dense MADD opportunities)
FUNCTION test_matrix_element(a11 AS DOUBLE, a12 AS DOUBLE, b1 AS DOUBLE, b2 AS DOUBLE) AS DOUBLE
    RETURN a11 * b1 + a12 * b2
END FUNCTION

' Test 9: Polynomial evaluation
FUNCTION test_polynomial(x AS DOUBLE, a0 AS DOUBLE, a1 AS DOUBLE, a2 AS DOUBLE, a3 AS DOUBLE) AS DOUBLE
    LOCAL result AS DOUBLE
    LOCAL x2 AS DOUBLE
    LOCAL x3 AS DOUBLE
    result = a0 + a1 * x
    x2 = x * x
    result = result + a2 * x2
    x3 = x2 * x
    result = result + a3 * x3
    RETURN result
END FUNCTION

' Main test driver
PRINT "Testing MADD/FMADD fusion..."

LOCAL i1 AS INTEGER
LOCAL i2 AS INTEGER
i1 = test_madd_int(10, 3, 4)
PRINT "test_madd_int(10, 3, 4) = "; i1
IF i1 <> 22 THEN
    PRINT "FAILED: Expected 22"
END IF

LOCAL l1 AS LONG
l1 = test_madd_long(100, 5, 6)
PRINT "test_madd_long(100, 5, 6) = "; l1
IF l1 <> 130 THEN
    PRINT "FAILED: Expected 130"
END IF

LOCAL f1 AS SINGLE
f1 = test_fmadd_single(1.5, 2.0, 3.0)
PRINT "test_fmadd_single(1.5, 2.0, 3.0) = "; f1
IF ABS(f1 - 7.5) > 0.001 THEN
    PRINT "FAILED: Expected 7.5"
END IF

LOCAL d1 AS DOUBLE
d1 = test_fmadd_double(10.5, 2.5, 4.0)
PRINT "test_fmadd_double(10.5, 2.5, 4.0) = "; d1
IF ABS(d1 - 20.5) > 0.0001 THEN
    PRINT "FAILED: Expected 20.5"
END IF

i2 = test_msub_int(20, 3, 4)
PRINT "test_msub_int(20, 3, 4) = "; i2
IF i2 <> 8 THEN
    PRINT "FAILED: Expected 8"
END IF

LOCAL d2 AS DOUBLE
d2 = test_fmsub_double(20.0, 2.5, 4.0)
PRINT "test_fmsub_double(20.0, 2.5, 4.0) = "; d2
IF ABS(d2 - 10.0) > 0.0001 THEN
    PRINT "FAILED: Expected 10.0"
END IF

LOCAL d3 AS DOUBLE
d3 = test_matrix_element(2.0, 3.0, 4.0, 5.0)
PRINT "test_matrix_element(2.0, 3.0, 4.0, 5.0) = "; d3
IF ABS(d3 - 23.0) > 0.0001 THEN
    PRINT "FAILED: Expected 23.0"
END IF

LOCAL d4 AS DOUBLE
d4 = test_polynomial(2.0, 1.0, 2.0, 3.0, 4.0)
PRINT "test_polynomial(2.0, 1.0, 2.0, 3.0, 4.0) = "; d4
' 1 + 2*2 + 3*4 + 4*8 = 1 + 4 + 12 + 32 = 49
IF ABS(d4 - 49.0) > 0.0001 THEN
    PRINT "FAILED: Expected 49.0"
END IF

PRINT "All tests completed!"
