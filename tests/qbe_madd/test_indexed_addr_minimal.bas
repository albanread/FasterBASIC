' Minimal Indexed Addressing Optimization Test
' Tests ADD+load/store -> ldr/str [base, index] fusion
' Avoids string operations to prevent unrelated QBE IL issues

DIM errors AS INTEGER
errors = 0

PRINT "=== Indexed Addressing Test ==="

' Test 1: Basic array write/read with variable index
DIM arr(10) AS INTEGER
DIM idx AS INTEGER
idx = 3
arr(idx) = 42

IF arr(3) = 42 THEN
    PRINT "Test 1: PASS (variable index store/load)"
ELSE
    PRINT "Test 1: FAIL"
    errors = errors + 1
END IF

' Test 2: Computed index (addition)
DIM bx AS INTEGER
bx = 2
arr(bx + 1) = 77
arr(bx + 2) = 88

IF arr(3) = 77 AND arr(4) = 88 THEN
    PRINT "Test 2: PASS (computed index)"
ELSE
    PRINT "Test 2: FAIL"
    errors = errors + 1
END IF

' Test 3: Loop with indexed access (squares)
DIM i AS INTEGER
FOR i = 0 TO 9
    arr(i) = i * i
NEXT i

DIM ok AS INTEGER
ok = 1
FOR i = 0 TO 9
    IF arr(i) <> i * i THEN
        ok = 0
    END IF
NEXT i

IF ok = 1 THEN
    PRINT "Test 3: PASS (loop indexed access)"
ELSE
    PRINT "Test 3: FAIL"
    errors = errors + 1
END IF

' Test 4: Nested loop 2D-like grid access
DIM grid(25) AS INTEGER
DIM row AS INTEGER
DIM col AS INTEGER
DIM gidx AS INTEGER

FOR row = 0 TO 4
    FOR col = 0 TO 4
        gidx = row * 5 + col
        grid(gidx) = row * 10 + col
    NEXT col
NEXT row

ok = 1
FOR row = 0 TO 4
    FOR col = 0 TO 4
        gidx = row * 5 + col
        IF grid(gidx) <> row * 10 + col THEN
            ok = 0
        END IF
    NEXT col
NEXT row

IF ok = 1 THEN
    PRINT "Test 4: PASS (nested index computation)"
ELSE
    PRINT "Test 4: FAIL"
    errors = errors + 1
END IF

' Test 5: Accumulation via indexed reads
DIM sum AS INTEGER
sum = 0
FOR i = 0 TO 9
    arr(i) = i + 1
NEXT i
FOR i = 0 TO 9
    sum = sum + arr(i)
NEXT i

IF sum = 55 THEN
    PRINT "Test 5: PASS (indexed accumulation = 55)"
ELSE
    PRINT "Test 5: FAIL"
    errors = errors + 1
END IF

' Test 6: Reverse traversal
FOR i = 9 TO 0 STEP -1
    arr(i) = 9 - i
NEXT i

ok = 1
FOR i = 0 TO 9
    IF arr(i) <> 9 - i THEN
        ok = 0
    END IF
NEXT i

IF ok = 1 THEN
    PRINT "Test 6: PASS (reverse traversal)"
ELSE
    PRINT "Test 6: FAIL"
    errors = errors + 1
END IF

' Test 7: Store then load same computed address
DIM key AS INTEGER
key = 6
arr(key) = 12345
DIM readback AS INTEGER
readback = arr(key)

IF readback = 12345 THEN
    PRINT "Test 7: PASS (store-load roundtrip)"
ELSE
    PRINT "Test 7: FAIL"
    errors = errors + 1
END IF

' Test 8: Adjacent elements via computed base
bx = 3
arr(bx) = 10
arr(bx + 1) = 20
arr(bx + 2) = 30
DIM s3 AS INTEGER
s3 = arr(bx) + arr(bx + 1) + arr(bx + 2)

IF s3 = 60 THEN
    PRINT "Test 8: PASS (adjacent computed base = 60)"
ELSE
    PRINT "Test 8: FAIL"
    errors = errors + 1
END IF

' Test 9: Strided access
DIM big(50) AS INTEGER
DIM stride AS INTEGER
stride = 5

FOR i = 0 TO 9
    big(i * stride) = i * 100
NEXT i

ok = 1
FOR i = 0 TO 9
    IF big(i * stride) <> i * 100 THEN
        ok = 0
    END IF
NEXT i

IF ok = 1 THEN
    PRINT "Test 9: PASS (strided access)"
ELSE
    PRINT "Test 9: FAIL"
    errors = errors + 1
END IF

' Test 10: Copy between arrays
DIM src(10) AS INTEGER
DIM dst(10) AS INTEGER

FOR i = 0 TO 9
    src(i) = (i + 1) * 11
NEXT i

FOR i = 0 TO 9
    dst(i) = src(i)
NEXT i

ok = 1
FOR i = 0 TO 9
    IF dst(i) <> (i + 1) * 11 THEN
        ok = 0
    END IF
NEXT i

IF ok = 1 THEN
    PRINT "Test 10: PASS (array copy)"
ELSE
    PRINT "Test 10: FAIL"
    errors = errors + 1
END IF

' Test 11: Index from expression (multiply)
DIM factor AS INTEGER
factor = 3
arr(factor * 2) = 666

IF arr(6) = 666 THEN
    PRINT "Test 11: PASS (multiply-derived index)"
ELSE
    PRINT "Test 11: FAIL"
    errors = errors + 1
END IF

' Test 12: Conditional indexed access
DIM sel AS INTEGER
sel = 1

IF sel = 0 THEN
    idx = 2
ELSE
    idx = 7
END IF

arr(idx) = 9999
IF arr(7) = 9999 THEN
    PRINT "Test 12: PASS (conditional index)"
ELSE
    PRINT "Test 12: FAIL"
    errors = errors + 1
END IF

' Summary
PRINT ""
IF errors = 0 THEN
    PRINT "ALL TESTS PASSED"
ELSE
    PRINT "ERRORS: "; errors
END IF
