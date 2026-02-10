' Test: Multiple workers and READY polling
' Expected output:
' Sum: 300
' Product: 200

WORKER ComputeSum(a AS DOUBLE, b AS DOUBLE, c AS DOUBLE) AS DOUBLE
    RETURN a + b + c
END WORKER

WORKER ComputeProduct(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    RETURN a * b
END WORKER

DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
f1 = SPAWN ComputeSum(100, 100, 100)
f2 = SPAWN ComputeProduct(10, 20)

DIM r1 AS DOUBLE
DIM r2 AS DOUBLE
r1 = AWAIT f1
r2 = AWAIT f2

PRINT "Sum: "; r1
PRINT "Product: "; r2
