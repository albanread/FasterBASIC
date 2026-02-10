' Test: Marshall/Unmarshall nested UDT with STRING fields at both levels
' Verifies recursive deep copy across nested types
' Expected output:
' Street: 10 Downing St
' City: London
' Name: PM
' Mutated name: King
' Clone name: PM

TYPE Address
    Street AS STRING
    City AS STRING
END TYPE

TYPE Contact
    Name AS STRING
    Addr AS Address
END TYPE

DIM c AS Contact
c.Name = "PM"
c.Addr.Street = "10 Downing St"
c.Addr.City = "London"

DIM blob AS MARSHALLED
blob = MARSHALL(c)

DIM c2 AS Contact
UNMARSHALL c2, blob

PRINT "Street: "; c2.Addr.Street
PRINT "City: "; c2.Addr.City
PRINT "Name: "; c2.Name

' Mutate original — clone must remain independent
c.Name = "King"
PRINT "Mutated name: "; c.Name
PRINT "Clone name: "; c2.Name
