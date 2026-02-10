' Test: Worker receives marshalled strings, creates new strings, returns them marshalled
' Proves deep copy works in both directions with string manipulation
' Expected output:
' Greeting: Hello, Alice!
' Original: Alice

CLASS Person
    Name AS STRING
    Age AS DOUBLE
END CLASS

CLASS Greeting
    Message AS STRING
END CLASS

WORKER MakeGreeting(blob AS MARSHALLED) AS MARSHALLED
    DIM p AS Person = NEW Person()
    UNMARSHALL p, blob

    DIM g AS Greeting = NEW Greeting()
    g.Message = "Hello, " + p.Name + "!"

    RETURN MARSHALL(g)
END WORKER

DIM somebody AS Person = NEW Person()
somebody.Name = "Alice"
somebody.Age = 30

DIM f AS MARSHALLED
f = SPAWN MakeGreeting(MARSHALL(somebody))
DIM answer AS MARSHALLED
answer = AWAIT f

DIM result AS Greeting = NEW Greeting()
UNMARSHALL result, answer
PRINT "Greeting: "; result.Message
PRINT "Original: "; somebody.Name
