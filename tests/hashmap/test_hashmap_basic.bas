REM Test: Basic Hashmap Operations
REM Tests: DIM, insert, lookup

DIM dict AS HASHMAP

REM Insert values
dict("name") = "Alice"
dict("age") = "30"
dict("city") = "Portland"

REM Lookup values
IF dict("name") <> "Alice" THEN
    PRINT "ERROR: name lookup failed"
    END
ENDIF

IF dict("age") <> "30" THEN
    PRINT "ERROR: age lookup failed"
    END
ENDIF

IF dict("city") <> "Portland" THEN
    PRINT "ERROR: city lookup failed"
    END
ENDIF

PRINT "PASS: Basic hashmap insert and lookup"

END
