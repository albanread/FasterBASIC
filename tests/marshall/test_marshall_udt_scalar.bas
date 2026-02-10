' Test: Marshall/Unmarshall a UDT with scalar fields only
' Expected output:
' X: 10
' Y: 20
' Z: 30
' Original X: 10

TYPE Vec3
    X AS DOUBLE
    Y AS DOUBLE
    Z AS DOUBLE
END TYPE

DIM v AS Vec3
v.X = 10
v.Y = 20
v.Z = 30

DIM blob AS MARSHALLED
blob = MARSHALL(v)

DIM v2 AS Vec3
UNMARSHALL v2, blob

PRINT "X: "; v2.X
PRINT "Y: "; v2.Y
PRINT "Z: "; v2.Z
PRINT "Original X: "; v.X
