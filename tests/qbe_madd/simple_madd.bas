' Simple MADD/FMADD fusion test
' Test basic multiply-add patterns

FUNCTION test_madd_int(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    RETURN a + b * c
END FUNCTION

FUNCTION test_madd_long(a AS LONG, b AS LONG, c AS LONG) AS LONG
    RETURN a + b * c
END FUNCTION

FUNCTION test_fmadd_single(a AS SINGLE, b AS SINGLE, c AS SINGLE) AS SINGLE
    RETURN a + b * c
END FUNCTION

FUNCTION test_fmadd_double(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    RETURN a + b * c
END FUNCTION

FUNCTION test_msub_int(a AS INTEGER, b AS INTEGER, c AS INTEGER) AS INTEGER
    RETURN a - b * c
END FUNCTION

FUNCTION test_fmsub_double(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    RETURN a - b * c
END FUNCTION

' Test them
PRINT "Integer MADD: 10 + 3*4 = "; test_madd_int(10, 3, 4)
PRINT "Long MADD: 100 + 5*6 = "; test_madd_long(100, 5, 6)
PRINT "Float FMADD: 1.5 + 2.0*3.0 = "; test_fmadd_single(1.5, 2.0, 3.0)
PRINT "Double FMADD: 10.5 + 2.5*4.0 = "; test_fmadd_double(10.5, 2.5, 4.0)
PRINT "Integer MSUB: 20 - 3*4 = "; test_msub_int(20, 3, 4)
PRINT "Double FMSUB: 20.0 - 2.5*4.0 = "; test_fmsub_double(20.0, 2.5, 4.0)
