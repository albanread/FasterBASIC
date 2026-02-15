' Test: Thread-safe PRINT combined with MATCH RECEIVE messaging
' Workers print progress while exchanging typed messages with main.
' Validates that the print mutex and message queues don't interfere.
'
' Expected output (worker print order may vary, but lines are intact):
' Main: dispatching work
' Worker 1: received task 1 value 10.5
' Worker 2: received task 2 value 20.5
' Worker 3: received task 3 value 30.5
' Worker 1: result = 21
' Worker 2: result = 41
' Worker 3: result = 61
' Main: got result from task 1 = 21
' Main: got result from task 2 = 41
' Main: got result from task 3 = 61
' Main: total = 123
' Done

TYPE Task
    id AS INTEGER
    value AS DOUBLE
END TYPE

TYPE Result
    task_id AS INTEGER
    answer AS DOUBLE
END TYPE

WORKER Computer(label AS DOUBLE) AS DOUBLE
    DIM t AS Task
    DIM r AS Result

    MATCH RECEIVE(PARENT)
        CASE Task t
            PRINT "Worker "; label; ": received task "; t.id; " value "; t.value
            r.task_id = t.id
            r.answer = t.value * 2
            PRINT "Worker "; label; ": result = "; r.answer
            SEND PARENT, r
    END MATCH

    RETURN label
END WORKER

PRINT "Main: dispatching work"

DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
DIM f3 AS DOUBLE
f1 = SPAWN Computer(1)
f2 = SPAWN Computer(2)
f3 = SPAWN Computer(3)

DIM t AS Task

t.id = 1
t.value = 10.5
SEND f1, t

t.id = 2
t.value = 20.5
SEND f2, t

t.id = 3
t.value = 30.5
SEND f3, t

DIM total AS DOUBLE = 0
DIM r AS Result

MATCH RECEIVE(f1)
    CASE Result r
        PRINT "Main: got result from task "; r.task_id; " = "; r.answer
        total = total + r.answer
END MATCH

MATCH RECEIVE(f2)
    CASE Result r
        PRINT "Main: got result from task "; r.task_id; " = "; r.answer
        total = total + r.answer
END MATCH

MATCH RECEIVE(f3)
    CASE Result r
        PRINT "Main: got result from task "; r.task_id; " = "; r.answer
        total = total + r.answer
END MATCH

DIM d AS DOUBLE
d = AWAIT f1
d = AWAIT f2
d = AWAIT f3

PRINT "Main: total = "; total
PRINT "Done"
