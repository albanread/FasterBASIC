' Test: Basic SEND / RECEIVE between worker and main
' Worker sends three values back via PARENT, main receives them
' Expected output:
' Got: 10
' Got: 20
' Got: 30
' Result: 100

WORKER Counter() AS DOUBLE
    DIM a AS DOUBLE = 10.0
    DIM b AS DOUBLE = 20.0
    DIM c AS DOUBLE = 30.0
    SEND PARENT, a
    SEND PARENT, b
    SEND PARENT, c
    DIM r AS DOUBLE = 100.0
    RETURN r
END WORKER

DIM f AS DOUBLE
f = SPAWN Counter()

DIM v1 AS DOUBLE
DIM v2 AS DOUBLE
DIM v3 AS DOUBLE
v1 = RECEIVE(f)
v2 = RECEIVE(f)
v3 = RECEIVE(f)

PRINT "Got: "; v1
PRINT "Got: "; v2
PRINT "Got: "; v3

DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
