DIM a AS STRING
DIM b AS STRING
DIM c AS STRING
DIM d AS STRING
DIM i AS INTEGER

a = "alpha"
b = "beta"
c = "gamma"
d = ""

FOR i = 1 TO 10
    d = d + a + " "
NEXT i

PRINT "length: "; LEN(d)
PRINT "first: "; a
PRINT "concat: "; b + "-" + c
END
