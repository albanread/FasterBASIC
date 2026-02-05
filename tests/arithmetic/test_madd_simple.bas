' Simple MADD/FMADD fusion test
' Forces runtime computation to see actual madd/fmadd instructions

FUNCTION TestMaddDouble(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    ' This should emit: fmadd result, a, b, c
    RETURN c + a * b
END FUNCTION

FUNCTION TestMsubDouble(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    ' This should emit: fmsub result, a, b, c
    RETURN c - a * b
END FUNCTION

FUNCTION TestMaddInt(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    ' This should emit: madd result, a, b, c
    RETURN c + a * b
END FUNCTION

FUNCTION TestMsubInt(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    ' This should emit: msub result, a, b, c
    RETURN c - a * b
END FUNCTION

DIM x AS DOUBLE, y AS DOUBLE, z AS DOUBLE, result AS DOUBLE
DIM ix AS INTEGER, iy AS INTEGER, iz AS INTEGER, iresult AS INTEGER

' Test double precision multiply-add
x = 2.0
y = 3.0
z = 5.0

result = TestMaddDouble(x, y, z)
PRINT "FMADD: ", z, " + ", x, " * ", y, " = ", result

IF ABS(result - 11.0) < 0.0001 THEN
    PRINT "PASS: FMADD"
ELSE
    PRINT "FAIL: FMADD"
END IF

' Test double precision multiply-subtract
result = TestMsubDouble(x, y, z)
PRINT "FMSUB: ", z, " - ", x, " * ", y, " = ", result

IF ABS(result - (-1.0)) < 0.0001 THEN
    PRINT "PASS: FMSUB"
ELSE
    PRINT "FAIL: FMSUB"
END IF

' Test integer multiply-add
ix = 5
iy = 6
iz = 100

iresult = TestMaddInt(ix, iy, iz)
PRINT "MADD: ", iz, " + ", ix, " * ", iy, " = ", iresult

IF iresult = 130 THEN
    PRINT "PASS: MADD"
ELSE
    PRINT "FAIL: MADD"
END IF

' Test integer multiply-subtract
iresult = TestMsubInt(ix, iy, iz)
PRINT "MSUB: ", iz, " - ", ix, " * ", iy, " = ", iresult

IF iresult = 70 THEN
    PRINT "PASS: MSUB"
ELSE
    PRINT "FAIL: MSUB"
END IF

PRINT "Done"
