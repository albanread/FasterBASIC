' Test: Marshall/Unmarshall CLASS with only string fields
' Verifies offset table works when every field needs deep copy
' Expected output:
' First: John
' Last: Doe
' Middle: Q

CLASS FullName
    First AS STRING
    Last AS STRING
    Middle AS STRING
END CLASS

DIM n AS FullName = NEW FullName()
n.First = "John"
n.Last = "Doe"
n.Middle = "Q"

DIM blob AS MARSHALLED
blob = MARSHALL(n)

DIM n2 AS FullName = NEW FullName()
UNMARSHALL n2, blob

PRINT "First: "; n2.First
PRINT "Last: "; n2.Last
PRINT "Middle: "; n2.Middle
