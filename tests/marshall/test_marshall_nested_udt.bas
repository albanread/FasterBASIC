' Test: Marshall/Unmarshall a UDT nested inside another UDT (scalars only)
' Expected output:
' Street: 42
' City code: 7
' Name: 99

TYPE Address
    Street AS DOUBLE
    CityCode AS DOUBLE
END TYPE

TYPE Contact
    Name AS DOUBLE
    Addr AS Address
END TYPE

DIM c AS Contact
c.Name = 99
c.Addr.Street = 42
c.Addr.CityCode = 7

DIM blob AS MARSHALLED
blob = MARSHALL(c)

DIM c2 AS Contact
UNMARSHALL c2, blob

PRINT "Street: "; c2.Addr.Street
PRINT "City code: "; c2.Addr.CityCode
PRINT "Name: "; c2.Name
