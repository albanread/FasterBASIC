' Test automatic function scoping based on DIM detection
' Functions with DIM should get automatic SAMM scopes

OPTION SAMM ON

' Test 1: Function with DIM - should get automatic scope
FUNCTION TestWithDim() AS INTEGER
    DIM result AS INTEGER
    DIM temp AS STRING

    result = 42
    temp = "Hello"

    PRINT "Function with DIM: "; result
    TestWithDim = result
END FUNCTION

' Test 2: Function without DIM - should not get automatic scope
FUNCTION TestNoDim(x AS INTEGER) AS INTEGER
    PRINT "Function without DIM: "; x
    TestNoDim = x * 2
END FUNCTION

' Test 3: Function with DIM and loop - should get automatic scope
FUNCTION TestDimWithLoop(n AS INTEGER) AS INTEGER
    DIM i AS INTEGER
    DIM sum AS INTEGER

    sum = 0
    FOR i = 1 TO n
        sum = sum + i
    NEXT i

    PRINT "Sum from 1 to "; n; " = "; sum
    TestDimWithLoop = sum
END FUNCTION

' Test 4: SUB with DIM in a loop - should get automatic scope
SUB TestDimInLoop(n AS INTEGER)
    DIM i AS INTEGER
    DIM temp AS STRING

    FOR i = 1 TO n
        temp = "Iteration"
        PRINT temp; " "; i
    NEXT i
END SUB

' Test 5: Function with NEW (class instantiation)
' Note: This requires a class, so we'll skip actual NEW for now
FUNCTION TestStringOps() AS STRING
    DIM s1 AS STRING
    DIM s2 AS STRING

    s1 = "Auto"
    s2 = "Scope"

    TestStringOps = s1 + " " + s2
END FUNCTION

' Main program
PRINT "=== Testing Automatic Function Scoping ==="
PRINT ""

PRINT "Test 1: Function with DIM"
DIM result1 AS INTEGER
result1 = TestWithDim()
PRINT "Returned: "; result1
PRINT ""

PRINT "Test 2: Function without DIM"
DIM result2 AS INTEGER
result2 = TestNoDim(21)
PRINT "Returned: "; result2
PRINT ""

PRINT "Test 3: Function with DIM and loop"
DIM result3 AS INTEGER
result3 = TestDimWithLoop(10)
PRINT "Returned: "; result3
PRINT ""

PRINT "Test 4: SUB with DIM in loop"
TestDimInLoop(3)
PRINT ""

PRINT "Test 5: Function with string operations"
DIM result5 AS STRING
result5 = TestStringOps()
PRINT "Returned: "; result5
PRINT ""

PRINT "=== All tests completed ==="
