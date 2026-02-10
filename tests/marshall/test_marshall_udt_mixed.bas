' Test: Marshall/Unmarshall a UDT with mixed scalar and string fields
' Verifies correct offsets when strings are interspersed with scalars
' Expected output:
' Label: Point-A
' X: 100
' Y: 200
' Tag: origin
' Weight: 9.5

TYPE TaggedPoint
    Label AS STRING
    X AS DOUBLE
    Y AS DOUBLE
    Tag AS STRING
    Weight AS DOUBLE
END TYPE

DIM tp AS TaggedPoint
tp.Label = "Point-A"
tp.X = 100
tp.Y = 200
tp.Tag = "origin"
tp.Weight = 9.5

DIM blob AS MARSHALLED
blob = MARSHALL(tp)

DIM tp2 AS TaggedPoint
UNMARSHALL tp2, blob

PRINT "Label: "; tp2.Label
PRINT "X: "; tp2.X
PRINT "Y: "; tp2.Y
PRINT "Tag: "; tp2.Tag
PRINT "Weight: "; tp2.Weight
