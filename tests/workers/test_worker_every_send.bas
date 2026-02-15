' Test: EVERY ... SEND — repeating timer sends ticks to a worker
' Main spawns a worker, then uses EVERY to send tick messages to the worker.
' The worker receives 3 ticks via MATCH RECEIVE(PARENT), then returns the count.
' Main stops the timer and collects the result.
'
' Expected output:
' Main: starting worker and timer
' Worker: waiting for ticks
' Worker: tick 1
' Worker: tick 2
' Worker: tick 3
' Worker: done
' Result: 3
' Done

TYPE Tick
    value AS INTEGER
END TYPE

WORKER TickCounter() AS DOUBLE
    PRINT "Worker: waiting for ticks"

    DIM count AS INTEGER = 0
    DIM tk AS Tick

    WHILE count < 3
        MATCH RECEIVE(PARENT)
            CASE Tick tk
                count = count + 1
                PRINT "Worker: tick "; count
            CASE ELSE
                ' ignore unexpected messages
        END MATCH
    WEND

    PRINT "Worker: done"
    DIM ret AS DOUBLE = count
    RETURN ret
END WORKER

DIM f AS DOUBLE
f = SPAWN TickCounter()

PRINT "Main: starting worker and timer"

DIM t AS Tick
t.value = 1

' Send a tick to the worker every 50ms
EVERY 50 MS SEND f, t

DIM result AS DOUBLE
result = AWAIT f

TIMER STOP ALL

PRINT "Result: "; result
PRINT "Done"
