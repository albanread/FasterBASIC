' Test: MARSHALL for returning multiple values from a worker
' Worker computes min, max, and average, returns them in a UDT
' Expected output:
' Min: 5
' Max: 50
' Avg: 27.5

TYPE Stats
    MinVal AS DOUBLE
    MaxVal AS DOUBLE
    AvgVal AS DOUBLE
END TYPE

WORKER ComputeStats(blob AS MARSHALLED) AS MARSHALLED
    DIM arr(4) AS DOUBLE
    UNMARSHALL arr, blob
    DIM result AS Stats
    result.MinVal = arr(0)
    result.MaxVal = arr(0)
    DIM total AS DOUBLE = 0
    DIM i AS INTEGER
    FOR i = 0 TO 3
        IF arr(i) < result.MinVal THEN result.MinVal = arr(i)
        IF arr(i) > result.MaxVal THEN result.MaxVal = arr(i)
        total = total + arr(i)
    NEXT i
    result.AvgVal = total / 4
    RETURN MARSHALL(result)
END WORKER

DIM values(4) AS DOUBLE
values(0) = 10
values(1) = 5
values(2) = 50
values(3) = 45

DIM f AS MARSHALLED
f = SPAWN ComputeStats(MARSHALL(values))
DIM answer AS MARSHALLED
answer = AWAIT f

DIM s AS Stats
UNMARSHALL s, answer
PRINT "Min: "; s.MinVal
PRINT "Max: "; s.MaxVal
PRINT "Avg: "; s.AvgVal
