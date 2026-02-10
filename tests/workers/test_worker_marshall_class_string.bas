' Test: MARSHALL / UNMARSHALL with CLASS containing STRING fields across workers
' Verifies deep copy of string fields in CLASS objects during marshalling.
' Expected output:
' Name length: 5
' Age: 30
' Original: Alice

CLASS Person
    Name AS STRING
    Age AS DOUBLE
END CLASS

WORKER GreetPerson(blob AS MARSHALLED) AS DOUBLE
    DIM p AS Person = NEW Person()
    UNMARSHALL p, blob
    DIM slen AS DOUBLE
    slen = LEN(p.Name)
    RETURN slen * 1000 + p.Age
END WORKER

DIM somebody AS Person = NEW Person()
somebody.Name = "Alice"
somebody.Age = 30

DIM f AS DOUBLE
f = SPAWN GreetPerson(MARSHALL(somebody))
DIM result AS DOUBLE
result = AWAIT f
DIM slen AS DOUBLE
slen = INT(result / 1000)
DIM age AS DOUBLE
age = result - slen * 1000
PRINT "Name length: "; slen
PRINT "Age: "; age
PRINT "Original: "; somebody.Name
