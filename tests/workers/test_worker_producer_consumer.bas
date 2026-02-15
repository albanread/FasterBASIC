' Test: Producer-consumer pattern with worker messaging
' Main sends values to a running worker, worker sums them and returns total
' Expected output:
' Total: 55

WORKER Summer() AS DOUBLE
    DIM total AS DOUBLE = 0.0
    DIM i AS INTEGER
    FOR i = 1 TO 10
        DIM val AS DOUBLE
        val = RECEIVE(PARENT)
        total = total + val
    NEXT i
    RETURN total
END WORKER

DIM f AS DOUBLE
f = SPAWN Summer()

' Feed 10 values to the worker
DIM i AS INTEGER
DIM v AS DOUBLE
FOR i = 1 TO 10
    v = i
    SEND f, v
NEXT i

DIM result AS DOUBLE
result = AWAIT f
PRINT "Total: "; result
