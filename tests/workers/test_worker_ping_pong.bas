' Test: Ping-pong ownership transfer between main and worker
' Main sends a Point, worker increments and sends back, main prints and sends again.
' Each round-trip both sides modify the same logical data (via marshal/unmarshal copies).
'
' Expected output:
' Start: 1 1
' Main got: 2 2
' Main got: 4 4
' Main got: 6 6
' Final: 7 7
' Done

TYPE Point
    x AS DOUBLE
    y AS DOUBLE
END TYPE

WORKER PingWorker() AS DOUBLE
    DIM rounds AS INTEGER = 3
    DIM i AS INTEGER = 0
    DIM p AS Point

    WHILE i < rounds
        MATCH RECEIVE(PARENT)
            CASE Point p
                p.x = p.x + 1
                p.y = p.y + 1
                SEND PARENT, p
                i = i + 1
        END MATCH
    WEND

    DIM ret AS DOUBLE = 0.0
    RETURN ret
END WORKER

DIM f AS DOUBLE
f = SPAWN PingWorker()

DIM p AS Point
p.x = 1
p.y = 1
PRINT "Start: "; p.x; " "; p.y

DIM rounds AS INTEGER = 3
DIM i AS INTEGER = 0

WHILE i < rounds
    SEND f, p

    MATCH RECEIVE(f)
        CASE Point p
            PRINT "Main got: "; p.x; " "; p.y
            p.x = p.x + 1
            p.y = p.y + 1
            i = i + 1
    END MATCH
WEND

PRINT "Final: "; p.x; " "; p.y

DIM result AS DOUBLE
result = AWAIT f
PRINT "Done"
