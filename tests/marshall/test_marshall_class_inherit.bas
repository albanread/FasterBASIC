' Test: Marshall/Unmarshall a CLASS that inherits from a superclass (scalars)
' Expected output:
' X: 10
' Y: 20
' Z: 30
' W: 40

CLASS Point2D
    X AS DOUBLE
    Y AS DOUBLE
END CLASS

CLASS Point3D EXTENDS Point2D
    Z AS DOUBLE
END CLASS

CLASS Point4D EXTENDS Point3D
    W AS DOUBLE
END CLASS

DIM p AS Point4D = NEW Point4D()
p.X = 10
p.Y = 20
p.Z = 30
p.W = 40

DIM blob AS MARSHALLED
blob = MARSHALL(p)

DIM p2 AS Point4D = NEW Point4D()
UNMARSHALL p2, blob

PRINT "X: "; p2.X
PRINT "Y: "; p2.Y
PRINT "Z: "; p2.Z
PRINT "W: "; p2.W
