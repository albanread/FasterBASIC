REM Test: Hashmap Value Updates
REM Tests: Updating existing keys with new values

DIM dict AS HASHMAP

REM Insert initial values
dict("status") = "pending"
dict("count") = "0"
dict("name") = "original"

REM Verify initial values
IF dict("status") <> "pending" THEN
    PRINT "ERROR: initial status wrong"
    END
ENDIF

IF dict("count") <> "0" THEN
    PRINT "ERROR: initial count wrong"
    END
ENDIF

REM Update values
dict("status") = "completed"
dict("count") = "42"
dict("name") = "updated"

REM Verify updated values
IF dict("status") <> "completed" THEN
    PRINT "ERROR: status update failed"
    END
ENDIF

IF dict("count") <> "42" THEN
    PRINT "ERROR: count update failed"
    END
ENDIF

IF dict("name") <> "updated" THEN
    PRINT "ERROR: name update failed"
    END
ENDIF

REM Update same key multiple times
dict("counter") = "1"
dict("counter") = "2"
dict("counter") = "3"
dict("counter") = "4"
dict("counter") = "5"

IF dict("counter") <> "5" THEN
    PRINT "ERROR: multiple updates failed"
    END
ENDIF

PRINT "PASS: Hashmap value updates work correctly"

END
