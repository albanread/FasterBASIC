' Test: Marshall/Unmarshall the same object twice (two independent clones)
' Expected output:
' Clone1: Alpha
' Clone2: Alpha
' Original changed: Beta
' Clone1 still: Alpha
' Clone2 still: Alpha

CLASS Named
    Value AS STRING
END CLASS

DIM orig AS Named = NEW Named()
orig.Value = "Alpha"

' Marshall twice
DIM blob1 AS MARSHALLED
blob1 = MARSHALL(orig)
DIM blob2 AS MARSHALLED
blob2 = MARSHALL(orig)

DIM c1 AS Named = NEW Named()
UNMARSHALL c1, blob1
DIM c2 AS Named = NEW Named()
UNMARSHALL c2, blob2

PRINT "Clone1: "; c1.Value
PRINT "Clone2: "; c2.Value

orig.Value = "Beta"
PRINT "Original changed: "; orig.Value
PRINT "Clone1 still: "; c1.Value
PRINT "Clone2 still: "; c2.Value
