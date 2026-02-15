' Test: CANCEL / CANCELLED cooperative cancellation
' Main spawns a worker, sends cancel, worker checks CANCELLED(PARENT)
' Expected output:
' Cancelled: 1
' Result: -1

WORKER CancellableTask() AS DOUBLE
    DIM i AS DOUBLE = 0.0
    DIM neg1 AS DOUBLE = -1.0
    DO
        i = i + 1.0
        IF CANCELLED(PARENT) THEN
            RETURN neg1
        END IF
        IF i > 1000000.0 THEN EXIT DO
    LOOP
    RETURN i
END WORKER

DIM f AS DOUBLE
f = SPAWN CancellableTask()

CANCEL f

DIM result AS DOUBLE
result = AWAIT f

' The worker should have seen the cancellation
IF result = -1.0 THEN
    PRINT "Cancelled: 1"
ELSE
    PRINT "Cancelled: 0"
END IF
PRINT "Result: "; result
