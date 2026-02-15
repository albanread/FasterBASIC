' Test: HASMESSAGE polling with worker messaging
' Worker sends two values, main uses HASMESSAGE to poll before receiving
' Expected output:
' Waiting: 0
' Received: 42
' Received: 99
' Result: 7

WORKER Sender() AS DOUBLE
    DIM a AS DOUBLE = 42.0
    DIM b AS DOUBLE = 99.0
    SEND PARENT, a
    SEND PARENT, b
    DIM r AS DOUBLE = 7.0
    RETURN r
END WORKER

DIM f AS DOUBLE
f = SPAWN Sender()

' Brief spin to let worker start — in practice the worker may
' already have sent by the time we reach here, but the logic
' must handle both cases.
DIM waited AS INTEGER = 0
DO WHILE HASMESSAGE(f) = 0
    waited = 1
    IF READY(f) THEN EXIT DO
LOOP

' Print whether we ever saw an empty queue (may or may not happen
' depending on scheduling, so we normalise to 0 for deterministic output)
PRINT "Waiting: 0"

' Now drain messages
DIM v1 AS DOUBLE
DIM v2 AS DOUBLE
v1 = RECEIVE(f)
PRINT "Received: "; v1
v2 = RECEIVE(f)
PRINT "Received: "; v2

DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
