' Test: MARSHALL / UNMARSHALL with UDT containing STRING field
' Expected output:
' Result: 5030

TYPE NamedPoint
    Label AS STRING
    X AS DOUBLE
    Y AS DOUBLE
END TYPE

WORKER ProcessNamed(blob AS MARSHALLED) AS DOUBLE
    DIM p AS NamedPoint
    UNMARSHALL p, blob
    DIM slen AS DOUBLE
    slen = LEN(p.Label)
    DIM total AS DOUBLE
    total = p.X + p.Y
    RETURN slen * 1000 + total
END WORKER

DIM pt AS NamedPoint
pt.Label = "Hello"
pt.X = 10
pt.Y = 20

DIM f AS DOUBLE
f = SPAWN ProcessNamed(MARSHALL(pt))
DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
