REM Test Hashmap Method Calls
DIM dict AS HASHMAP

dict("alice") = "Alice Smith"
dict("bob") = "Bob Jones"
dict("charlie") = "Charlie Brown"

REM Test SIZE
PRINT "Size: "; dict.SIZE()

REM Test HASKEY
IF dict.HASKEY("alice") THEN
    PRINT "HASKEY: alice exists"
ENDIF

IF dict.HASKEY("missing") THEN
    PRINT "ERROR: missing should not exist"
ELSE
    PRINT "HASKEY: missing not found"
ENDIF

REM Test REMOVE
result% = dict.REMOVE("bob")
PRINT "REMOVE bob: "; result%
PRINT "Size after remove: "; dict.SIZE()

REM Test CLEAR
dict.CLEAR()
PRINT "Size after CLEAR: "; dict.SIZE()

END
