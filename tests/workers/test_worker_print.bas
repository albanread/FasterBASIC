' Test: Thread-safe PRINT from inside workers
' Workers can now use PRINT — output is protected by a statement-level mutex
' so lines never interleave mid-statement.
'
' Expected output (order of worker lines may vary, but each line is intact):
' Main: starting workers
' Worker 1: hello from worker 1
' Worker 1: count 1
' Worker 1: count 2
' Worker 1: count 3
' Worker 2: hello from worker 2
' Worker 2: count 1
' Worker 2: count 2
' Worker 2: count 3
' Worker 1: done
' Worker 2: done
' Main: all workers finished

WORKER Printer(id AS DOUBLE) AS DOUBLE
    PRINT "Worker "; id; ": hello from worker "; id
    DIM i AS INTEGER = 1
    WHILE i <= 3
        PRINT "Worker "; id; ": count "; i
        i = i + 1
    WEND
    PRINT "Worker "; id; ": done"
    RETURN id
END WORKER

PRINT "Main: starting workers"

DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
f1 = SPAWN Printer(1)
f2 = SPAWN Printer(2)

DIM r1 AS DOUBLE
DIM r2 AS DOUBLE
r1 = AWAIT f1
r2 = AWAIT f2

PRINT "Main: all workers finished"
