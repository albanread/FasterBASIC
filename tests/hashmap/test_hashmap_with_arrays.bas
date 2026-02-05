REM Test: Mixing Arrays and Hashmaps
REM Tests: Arrays and hashmaps can coexist without conflicts

DIM numbers(10) AS INTEGER
DIM names(5) AS STRING
DIM lookup AS HASHMAP

REM Fill array with integers
numbers(0) = 100
numbers(1) = 200
numbers(2) = 300
numbers(3) = 400

REM Fill array with strings
names(0) = "Alice"
names(1) = "Bob"
names(2) = "Charlie"

REM Fill hashmap
lookup("first") = "one"
lookup("second") = "two"
lookup("third") = "three"

REM Verify arrays work
IF numbers(0) <> 100 THEN
    PRINT "ERROR: integer array failed"
    END
ENDIF

IF numbers(2) <> 300 THEN
    PRINT "ERROR: integer array index 2 failed"
    END
ENDIF

IF names(0) <> "Alice" THEN
    PRINT "ERROR: string array failed"
    END
ENDIF

IF names(2) <> "Charlie" THEN
    PRINT "ERROR: string array index 2 failed"
    END
ENDIF

REM Verify hashmap works
IF lookup("first") <> "one" THEN
    PRINT "ERROR: hashmap lookup failed"
    END
ENDIF

IF lookup("third") <> "three" THEN
    PRINT "ERROR: hashmap third key failed"
    END
ENDIF

REM Interleaved access pattern
n% = numbers(1)
s$ = lookup("second")
m% = numbers(3)

IF n% <> 200 THEN
    PRINT "ERROR: interleaved array access failed"
    END
ENDIF

IF s$ <> "two" THEN
    PRINT "ERROR: interleaved hashmap access failed"
    END
ENDIF

IF m% <> 400 THEN
    PRINT "ERROR: interleaved array access 2 failed"
    END
ENDIF

REM Update both
numbers(0) = 999
lookup("first") = "updated"

IF numbers(0) <> 999 THEN
    PRINT "ERROR: array update after mixed usage failed"
    END
ENDIF

IF lookup("first") <> "updated" THEN
    PRINT "ERROR: hashmap update after mixed usage failed"
    END
ENDIF

PRINT "PASS: Arrays and hashmaps work together correctly"

END
