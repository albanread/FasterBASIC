' Advanced test for automatic function scoping with nested calls
' This demonstrates scope depth tracking and cleanup

OPTION SAMM ON

' Helper function WITH DIM - should get automatic scope
FUNCTION CreateMessage(prefix AS STRING, num AS INTEGER) AS STRING
    DIM result AS STRING
    DIM numStr AS STRING

    ' String operations that allocate
    result = prefix + " "
    numStr = STR$(num)
    result = result + numStr

    CreateMessage = result
END FUNCTION

' Helper function WITHOUT DIM - no automatic scope
FUNCTION DoubleValue(x AS INTEGER) AS INTEGER
    DoubleValue = x * 2
END FUNCTION

' Function that calls other functions - should get automatic scope
FUNCTION ProcessItem(index AS INTEGER) AS STRING
    DIM doubled AS INTEGER
    DIM message AS STRING

    ' Call function without DIM
    doubled = DoubleValue(index)

    ' Call function with DIM (creates nested scope)
    message = CreateMessage("Item", doubled)

    ProcessItem = message
END FUNCTION

' SUB with DIM and loop - should get automatic scope
SUB ProcessBatch(count AS INTEGER)
    DIM i AS INTEGER
    DIM result AS STRING

    PRINT "Processing batch of "; count; " items:"

    FOR i = 1 TO count
        ' Each iteration calls function with scope
        result = ProcessItem(i)
        PRINT "  "; result
    NEXT i
END SUB

' Function with DIM in conditional - should get automatic scope
FUNCTION ConditionalAlloc(flag AS INTEGER) AS STRING
    DIM result AS STRING

    IF flag > 0 THEN
        result = "Positive: " + STR$(flag)
    ELSE
        result = "Non-positive"
    END IF

    ConditionalAlloc = result
END FUNCTION

' ============= Main Program =============

PRINT "=== Advanced Automatic Scoping Test ==="
PRINT ""

' Test 1: Simple function call with DIM
PRINT "Test 1: Single function call with DIM"
DIM msg1 AS STRING
msg1 = CreateMessage("Hello", 42)
PRINT "Result: "; msg1
PRINT ""

' Test 2: Nested function calls
PRINT "Test 2: Nested function calls"
DIM msg2 AS STRING
msg2 = ProcessItem(10)
PRINT "Result: "; msg2
PRINT ""

' Test 3: Loop calling functions with scopes
PRINT "Test 3: Batch processing (creates multiple nested scopes)"
ProcessBatch(3)
PRINT ""

' Test 4: Conditional allocation
PRINT "Test 4: Conditional allocation"
DIM msg3 AS STRING
DIM msg4 AS STRING
msg3 = ConditionalAlloc(5)
msg4 = ConditionalAlloc(-1)
PRINT "Positive: "; msg3
PRINT "Negative: "; msg4
PRINT ""

' Test 5: Multiple calls to same function
PRINT "Test 5: Multiple calls to same function"
DIM i AS INTEGER
FOR i = 1 TO 5
    DIM temp AS STRING
    temp = CreateMessage("Call", i)
    PRINT "  "; temp
NEXT i
PRINT ""

PRINT "=== All advanced tests completed ==="
PRINT "Run with BASIC_MEMORY_STATS=1 to see scope depth!"
