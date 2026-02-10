' Test: Marshall/Unmarshall a CLASS with scalar fields only
' Expected output:
' R: 255
' G: 128
' B: 0

CLASS Color
    R AS DOUBLE
    G AS DOUBLE
    B AS DOUBLE
END CLASS

DIM c AS Color = NEW Color()
c.R = 255
c.G = 128
c.B = 0

DIM blob AS MARSHALLED
blob = MARSHALL(c)

DIM c2 AS Color = NEW Color()
UNMARSHALL c2, blob

PRINT "R: "; c2.R
PRINT "G: "; c2.G
PRINT "B: "; c2.B
