' Test enhanced SWAP command with various lvalue types
PRINT "Testing enhanced SWAP command..."

' Test 1: Simple variable swap
DIM a AS INTEGER
DIM b AS INTEGER
a = 10
b = 20
PRINT "Before simple swap: a="; a; " b="; b
SWAP a, b
PRINT "After simple swap:  a="; a; " b="; b
IF a = 20 AND b = 10 THEN
    PRINT "Simple swap: PASS"
ELSE
    PRINT "Simple swap: FAIL"
END IF
PRINT ""

' Test 2: Array element swap (same array)
DIM arr(10) AS INTEGER
arr(1) = 100
arr(2) = 200
PRINT "Before array swap: arr(1)="; arr(1); " arr(2)="; arr(2)
SWAP arr(1), arr(2)
PRINT "After array swap:  arr(1)="; arr(1); " arr(2)="; arr(2)
IF arr(1) = 200 AND arr(2) = 100 THEN
    PRINT "Array element swap: PASS"
ELSE
    PRINT "Array element swap: FAIL"
END IF
PRINT ""

' Test 3: Array element with expression in index
DIM nums(10) AS INTEGER
DIM i AS INTEGER
i = 3
nums(i) = 333
nums(i + 1) = 444
PRINT "Before expression swap: nums(3)="; nums(3); " nums(4)="; nums(4)
SWAP nums(i), nums(i + 1)
PRINT "After expression swap:  nums(3)="; nums(3); " nums(4)="; nums(4)
IF nums(3) = 444 AND nums(4) = 333 THEN
    PRINT "Expression index swap: PASS"
ELSE
    PRINT "Expression index swap: FAIL"
END IF
PRINT ""

' Test 4: Mixed swap (variable and array element)
DIM x AS INTEGER
DIM arr2(5) AS INTEGER
x = 77
arr2(1) = 88
PRINT "Before mixed swap: x="; x; " arr2(1)="; arr2(1)
SWAP x, arr2(1)
PRINT "After mixed swap:  x="; x; " arr2(1)="; arr2(1)
IF x = 88 AND arr2(1) = 77 THEN
    PRINT "Mixed swap: PASS"
ELSE
    PRINT "Mixed swap: FAIL"
END IF
PRINT ""

' Test 5: Floating point swap
DIM f1 AS DOUBLE
DIM f2 AS DOUBLE
f1 = 3.14
f2 = 2.718
PRINT "Before float swap: f1="; f1; " f2="; f2
SWAP f1, f2
PRINT "After float swap:  f1="; f1; " f2="; f2
IF f1 > 2.7 AND f1 < 2.8 AND f2 > 3.1 AND f2 < 3.2 THEN
    PRINT "Float swap: PASS"
ELSE
    PRINT "Float swap: FAIL"
END IF
PRINT ""

PRINT "All SWAP tests completed!"
