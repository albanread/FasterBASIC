' Test LDP/STP pairing optimization
' Exercises adjacent memory stores and loads that should be paired
' into STP/LDP instructions on ARM64

DIM result AS INTEGER
DIM errors AS INTEGER
errors = 0

PRINT "=== LDP/STP Pairing Optimization Test ==="
PRINT ""

' Test 1: Adjacent integer array stores and loads
PRINT "Test 1: Adjacent integer array stores/loads"
DIM arr(10) AS INTEGER
arr(0) = 100
arr(1) = 200
arr(2) = 300
arr(3) = 400
arr(4) = 500

IF arr(0) = 100 AND arr(1) = 200 THEN
    PRINT "  PASS: arr(0)=100, arr(1)=200"
ELSE
    PRINT "  FAIL: arr(0)="; arr(0); " arr(1)="; arr(1)
    errors = errors + 1
END IF

IF arr(2) = 300 AND arr(3) = 400 THEN
    PRINT "  PASS: arr(2)=300, arr(3)=400"
ELSE
    PRINT "  FAIL: arr(2)="; arr(2); " arr(3)="; arr(3)
    errors = errors + 1
END IF

IF arr(4) = 500 THEN
    PRINT "  PASS: arr(4)=500"
ELSE
    PRINT "  FAIL: arr(4)="; arr(4)
    errors = errors + 1
END IF

' Test 2: UDT with multiple fields (adjacent field stores/loads)
PRINT ""
PRINT "Test 2: UDT adjacent field stores/loads"
TYPE Point
    x AS INTEGER
    y AS INTEGER
END TYPE

DIM p AS Point
p.x = 42
p.y = 99

IF p.x = 42 AND p.y = 99 THEN
    PRINT "  PASS: p.x=42, p.y=99"
ELSE
    PRINT "  FAIL: p.x="; p.x; " p.y="; p.y
    errors = errors + 1
END IF

' Test 3: UDT array with adjacent element access
PRINT ""
PRINT "Test 3: UDT array adjacent access"
DIM points(5) AS Point
points(0).x = 10
points(0).y = 20
points(1).x = 30
points(1).y = 40
points(2).x = 50
points(2).y = 60

IF points(0).x = 10 AND points(0).y = 20 THEN
    PRINT "  PASS: points(0) = (10, 20)"
ELSE
    PRINT "  FAIL: points(0) = ("; points(0).x; ","; points(0).y; ")"
    errors = errors + 1
END IF

IF points(1).x = 30 AND points(1).y = 40 THEN
    PRINT "  PASS: points(1) = (30, 40)"
ELSE
    PRINT "  FAIL: points(1) = ("; points(1).x; ","; points(1).y; ")"
    errors = errors + 1
END IF

IF points(2).x = 50 AND points(2).y = 60 THEN
    PRINT "  PASS: points(2) = (50, 60)"
ELSE
    PRINT "  FAIL: points(2) = ("; points(2).x; ","; points(2).y; ")"
    errors = errors + 1
END IF

' Test 4: Larger UDT (4 fields — good candidate for multiple pairs)
PRINT ""
PRINT "Test 4: Larger UDT with 4 fields"
TYPE MyRect
    lft AS INTEGER
    tp AS INTEGER
    rgt AS INTEGER
    btm AS INTEGER
END TYPE

DIM r AS MyRect
r.lft = 10
r.tp = 20
r.rgt = 110
r.btm = 120

IF r.lft = 10 AND r.tp = 20 AND r.rgt = 110 AND r.btm = 120 THEN
    PRINT "  PASS: Rect = (10, 20, 110, 120)"
ELSE
    PRINT "  FAIL: Rect = ("; r.lft; ","; r.tp; ","; r.rgt; ","; r.btm; ")"
    errors = errors + 1
END IF

' Test 5: Copy between UDTs (generates paired loads then paired stores)
PRINT ""
PRINT "Test 5: UDT copy (paired loads + paired stores)"
DIM r2 AS MyRect
r2.lft = r.lft
r2.tp = r.tp
r2.rgt = r.rgt
r2.btm = r.btm

IF r2.lft = 10 AND r2.tp = 20 AND r2.rgt = 110 AND r2.btm = 120 THEN
    PRINT "  PASS: Copied Rect matches"
ELSE
    PRINT "  FAIL: Copied Rect = ("; r2.lft; ","; r2.tp; ","; r2.rgt; ","; r2.btm; ")"
    errors = errors + 1
END IF

' Test 6: Multiple local variables (callee-save pairing in prologue/epilogue)
PRINT ""
PRINT "Test 6: Multiple locals (callee-save pairing)"
DIM a AS INTEGER
DIM b AS INTEGER
DIM c AS INTEGER
DIM d AS INTEGER
DIM e AS INTEGER
DIM f AS INTEGER
a = 1
b = 2
c = 3
d = 4
e = 5
f = 6

result = a + b + c + d + e + f
IF result = 21 THEN
    PRINT "  PASS: Sum of 6 locals = 21"
ELSE
    PRINT "  FAIL: Sum = "; result
    errors = errors + 1
END IF

' Test 7: Array initialization pattern (sequential stores)
PRINT ""
PRINT "Test 7: Sequential array initialization"
DIM vals(8) AS INTEGER
DIM idx AS INTEGER
FOR idx = 0 TO 7
    vals(idx) = idx * 10
NEXT idx

DIM ok AS INTEGER
ok = 1
FOR idx = 0 TO 7
    IF vals(idx) <> idx * 10 THEN
        ok = 0
    END IF
NEXT idx

IF ok = 1 THEN
    PRINT "  PASS: All 8 array values correct"
ELSE
    PRINT "  FAIL: Array values mismatch"
    errors = errors + 1
END IF

' Test 8: Swapping adjacent values (load pair, store pair)
PRINT ""
PRINT "Test 8: Swap adjacent array elements"
DIM tmp AS INTEGER
arr(0) = 111
arr(1) = 222

tmp = arr(0)
arr(0) = arr(1)
arr(1) = tmp

IF arr(0) = 222 AND arr(1) = 111 THEN
    PRINT "  PASS: Swapped arr(0)=222, arr(1)=111"
ELSE
    PRINT "  FAIL: arr(0)="; arr(0); " arr(1)="; arr(1)
    errors = errors + 1
END IF

' Summary
PRINT ""
PRINT "================================="
IF errors = 0 THEN
    PRINT "ALL TESTS PASSED"
ELSE
    PRINT "ERRORS: "; errors
END IF
PRINT "================================="
