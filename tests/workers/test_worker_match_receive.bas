' Test: MATCH RECEIVE with scalar types (DOUBLE, INTEGER, STRING)
' Worker sends three different typed messages, main dispatches via MATCH RECEIVE
' Expected output:
' Got double: 3.14
' Got integer: 42
' Got string: hello
' Done

WORKER Sender() AS DOUBLE
    DIM d AS DOUBLE = 3.14
    SEND PARENT, d
    DIM i AS INTEGER = 42
    SEND PARENT, i
    DIM s AS STRING = "hello"
    SEND PARENT, s
    DIM ret AS DOUBLE = 0.0
    RETURN ret
END WORKER

DIM f AS DOUBLE
f = SPAWN Sender()

DIM count AS INTEGER = 0

WHILE count < 3
    MATCH RECEIVE(f)
        CASE DOUBLE x
            PRINT "Got double: "; x
            count = count + 1
        CASE INTEGER n%
            PRINT "Got integer: "; n%
            count = count + 1
        CASE STRING s$
            PRINT "Got string: "; s$
            count = count + 1
        CASE ELSE
            PRINT "Unknown message"
            count = count + 1
    END MATCH
WEND

DIM result AS DOUBLE
result = AWAIT f
PRINT "Done"
