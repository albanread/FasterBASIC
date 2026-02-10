' Test: MARSHALL / UNMARSHALL with UDT containing STRING fields across workers
' Verifies deep copy of string fields during marshalling.
' Expected output:
' String length: 11
' Value sum: 30
' Original: Hello World

TYPE NamedPoint
    Label AS STRING
    X AS DOUBLE
    Y AS DOUBLE
END TYPE

WORKER ProcessNamed(blob AS MARSHALLED) AS DOUBLE
    DIM p AS NamedPoint
    UNMARSHALL p, blob
    DIM s AS STRING
    s = p.Label
    RETURN LEN(s) * 1000 + p.X + p.Y
END WORKER

DIM pt AS NamedPoint
pt.Label = "Hello World"
pt.X = 10
pt.Y = 20

DIM f AS DOUBLE
f = SPAWN ProcessNamed(MARSHALL(pt))
DIM result AS DOUBLE
result = AWAIT f
DIM slen AS DOUBLE
slen = INT(result / 1000)
DIM vsum AS DOUBLE
vsum = result - slen * 1000
PRINT "String length: "; slen
PRINT "Value sum: "; vsum
PRINT "Original: "; pt.Label
