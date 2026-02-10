' Test: MARSHALL / UNMARSHALL with arrays across workers
' Expected output:
' Sum: 150

WORKER SumArray(blob AS MARSHALLED) AS DOUBLE
    DIM arr(5) AS DOUBLE
    UNMARSHALL arr, blob
    DIM total AS DOUBLE
    total = 0
    DIM i AS INTEGER
    FOR i = 0 TO 4
        total = total + arr(i)
    NEXT i
    RETURN total
END WORKER

DIM myArr(5) AS DOUBLE
myArr(0) = 10
myArr(1) = 20
myArr(2) = 30
myArr(3) = 40
myArr(4) = 50

DIM f AS DOUBLE
f = SPAWN SumArray(MARSHALL(myArr))
DIM result AS DOUBLE
result = AWAIT f
PRINT "Sum: "; result
