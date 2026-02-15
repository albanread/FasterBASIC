' Test: AFTER ... SEND — one-shot timer message
' Main spawns a worker, then uses AFTER to send it a message after a short delay.
' The worker waits for the message via MATCH RECEIVE, processes it, and returns.
'
' Expected output:
' Main: setting up timer
' Main: waiting for result
' Worker: got ping 42
' Worker: done
' Result: 42
' Done

TYPE Ping
    value AS INTEGER
END TYPE

WORKER Listener() AS DOUBLE
    DIM p AS Ping
    DIM result AS DOUBLE = 0

    MATCH RECEIVE(PARENT)
        CASE Ping p
            PRINT "Worker: got ping "; p.value
            result = p.value
    END MATCH

    PRINT "Worker: done"
    RETURN result
END WORKER

DIM f AS DOUBLE
f = SPAWN Listener()

PRINT "Main: setting up timer"

DIM p AS Ping
p.value = 42

' Send the message after 100 milliseconds
AFTER 100 MS SEND f, p

PRINT "Main: waiting for result"

DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
PRINT "Done"
