' Test Memory Tracking
' This test allocates arrays and UDTs to exercise the memory allocator

PRINT "Testing memory allocation tracking..."
PRINT ""

' Test 1: Basic array allocation
PRINT "Test 1: Allocating integer array (1000 elements)"
DIM arr1(1000) AS INTEGER
DIM i AS INTEGER
FOR i = 1 TO 1000
    arr1(i) = i
NEXT i
PRINT "  Allocated and initialized"
PRINT ""

' Test 2: Multiple arrays
PRINT "Test 2: Allocating multiple arrays"
DIM arr2(500) AS DOUBLE
DIM arr3(200) AS INTEGER
DIM arr4(100) AS INTEGER
FOR i = 1 TO 500
    arr2(i) = i * 1.5
NEXT i
PRINT "  Allocated 3 more arrays"
PRINT ""

' Test 3: String array (exercises string allocation)
PRINT "Test 3: Allocating string array"
DIM names(50) AS STRING
FOR i = 1 TO 50
    names(i) = "Name_" + STR(i)
NEXT i
PRINT "  Allocated and filled string array"
PRINT ""

' Test 4: Nested loops with temporary allocations
PRINT "Test 4: String concatenations (temporary allocations)"
DIM result AS STRING
result = ""
FOR i = 1 TO 100
    result = result + "X"
NEXT i
PRINT "  Created string of length "; LEN(result)
PRINT ""

PRINT "All memory allocation tests completed"
PRINT "Memory statistics will be printed at program exit..."
