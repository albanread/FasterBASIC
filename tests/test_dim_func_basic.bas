' Test: DIM inside FUNCTION/SUB bodies (basic types only)
' Verifies that DIM creates local stack variables inside functions
' and that type inference works correctly for parameters and locals.

' ============================================================
' Test A: DIM INTEGER inside FUNCTION
' ============================================================

FUNCTION AddDoubled(x AS INTEGER, y AS INTEGER) AS INTEGER
    DIM temp AS INTEGER
    temp = x * 2
    DIM temp2 AS INTEGER
    temp2 = y * 2
    AddDoubled = temp + temp2
END FUNCTION

PRINT "=== Test A: DIM INTEGER in FUNCTION ==="
PRINT "AddDoubled(3, 5) = "; AddDoubled(3, 5)

' ============================================================
' Test B: DIM with FOR loop inside FUNCTION
' ============================================================

FUNCTION SumRange(lo AS INTEGER, hi AS INTEGER) AS INTEGER
    DIM total AS INTEGER
    DIM i AS INTEGER
    total = 0
    FOR i = lo TO hi
        total = total + i
    NEXT i
    SumRange = total
END FUNCTION

PRINT "=== Test B: DIM + FOR in FUNCTION ==="
PRINT "SumRange(1,10) = "; SumRange(1, 10)

' ============================================================
' Test C: DIM inside SUB
' ============================================================

SUB PrintSum(p AS INTEGER, q AS INTEGER)
    DIM s AS INTEGER
    s = p + q
    PRINT "Sum = "; s
END SUB

PRINT "=== Test C: DIM in SUB ==="
CALL PrintSum(7, 8)

' ============================================================
' Test D: Multiple DIM in same FUNCTION
' ============================================================

FUNCTION MultiDim(x AS INTEGER) AS INTEGER
    DIM a AS INTEGER
    DIM b AS INTEGER
    DIM c AS INTEGER
    a = x + 1
    b = a * 2
    c = b - 3
    MultiDim = c
END FUNCTION

PRINT "=== Test D: Multiple DIM in FUNCTION ==="
PRINT "MultiDim(10) = "; MultiDim(10)

' ============================================================
' Test E: FUNCTION with double parameters and locals
' ============================================================

FUNCTION Average(a AS DOUBLE, b AS DOUBLE) AS DOUBLE
    DIM sum AS DOUBLE
    sum = a + b
    Average = sum / 2.0
END FUNCTION

PRINT "=== Test E: DIM DOUBLE in FUNCTION ==="
PRINT "Average(10, 20) = "; Average(10, 20)

' ============================================================
' Test F: FOR loop with integer parameters (type inference)
' ============================================================

FUNCTION CountDown(start AS INTEGER) AS INTEGER
    DIM result AS INTEGER
    DIM i AS INTEGER
    result = 0
    FOR i = start TO 1 STEP -1
        result = result + i
    NEXT i
    CountDown = result
END FUNCTION

PRINT "=== Test F: FOR with STEP -1 in FUNCTION ==="
PRINT "CountDown(5) = "; CountDown(5)

' ============================================================
' Test G: INC/DEC on integer local
' ============================================================

FUNCTION IncTest(x AS INTEGER) AS INTEGER
    DIM counter AS INTEGER
    counter = x
    INC counter
    INC counter
    INC counter
    IncTest = counter
END FUNCTION

PRINT "=== Test G: INC on local integer ==="
PRINT "IncTest(10) = "; IncTest(10)

PRINT "=== All DIM-in-function tests passed ==="
