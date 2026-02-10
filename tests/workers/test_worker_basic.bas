' Test: Basic WORKER / SPAWN / AWAIT
' Expected output:
' Result: 30

WORKER Add(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    RETURN a + b
END WORKER

DIM f AS DOUBLE
f = SPAWN Add(10, 20)
DIM result AS DOUBLE
result = AWAIT f
PRINT "Result: "; result
