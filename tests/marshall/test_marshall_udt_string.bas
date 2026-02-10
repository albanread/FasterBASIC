' Test: Marshall/Unmarshall a UDT with STRING fields (deep copy)
' Expected output:
' Name: Alice
' City: London
' Original: Alice
' After change: Bob
' Clone still: Alice

TYPE Person
    Name AS STRING
    City AS STRING
    Age AS DOUBLE
END TYPE

DIM p AS Person
p.Name = "Alice"
p.City = "London"
p.Age = 30

DIM blob AS MARSHALLED
blob = MARSHALL(p)

DIM p2 AS Person
UNMARSHALL p2, blob

PRINT "Name: "; p2.Name
PRINT "City: "; p2.City
PRINT "Original: "; p.Name

' Mutate original — clone must be independent
p.Name = "Bob"
PRINT "After change: "; p.Name
PRINT "Clone still: "; p2.Name
