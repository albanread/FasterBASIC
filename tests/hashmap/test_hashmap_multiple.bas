REM Test: Multiple Hashmaps
REM Tests: Multiple independent hashmap instances

DIM users AS HASHMAP
DIM scores AS HASHMAP
DIM phones AS HASHMAP

REM Fill first hashmap
users("alice") = "Alice Smith"
users("bob") = "Bob Jones"
users("charlie") = "Charlie Brown"

REM Fill second hashmap
scores("alice") = "95"
scores("bob") = "87"
scores("charlie") = "92"

REM Fill third hashmap
phones("alice") = "555-1234"
phones("bob") = "555-5678"
phones("charlie") = "555-9012"

REM Verify independence - each hashmap has its own data
IF users("alice") <> "Alice Smith" THEN
    PRINT "ERROR: users hashmap failed"
    END
ENDIF

IF scores("alice") <> "95" THEN
    PRINT "ERROR: scores hashmap failed"
    END
ENDIF

IF phones("alice") <> "555-1234" THEN
    PRINT "ERROR: phones hashmap failed"
    END
ENDIF

REM Verify different keys work independently
IF users("bob") <> "Bob Jones" THEN
    PRINT "ERROR: users bob lookup failed"
    END
ENDIF

IF scores("charlie") <> "92" THEN
    PRINT "ERROR: scores charlie lookup failed"
    END
ENDIF

PRINT "PASS: Multiple independent hashmaps work correctly"

END
