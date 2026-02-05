REM Test: Hashmap Method Calls
REM Tests: SIZE(), HASKEY(), REMOVE(), CLEAR()

DIM dict AS HASHMAP

REM Insert values
dict("name") = "Alice"
dict("age") = "30"
dict("city") = "Portland"

REM Test SIZE method
size1% = dict.SIZE()
IF size1% <> 3 THEN
    PRINT "ERROR: SIZE should be 3, got "; size1%
    END
ENDIF
PRINT "SIZE: "; size1%

REM Test HASKEY method - existing key
hasname% = dict.HASKEY("name")
IF hasname% <> 1 THEN
    PRINT "ERROR: HASKEY should find name"
    END
ENDIF
PRINT "HASKEY(name): "; hasname%

REM Test HASKEY method - missing key
hasmissing% = dict.HASKEY("missing")
IF hasmissing% <> 0 THEN
    PRINT "ERROR: HASKEY should not find missing"
    END
ENDIF
PRINT "HASKEY(missing): "; hasmissing%

REM Test REMOVE method - existing key
removed% = dict.REMOVE("age")
IF removed% <> 1 THEN
    PRINT "ERROR: REMOVE should return 1"
    END
ENDIF
PRINT "REMOVE(age): "; removed%

REM Check size after remove
size2% = dict.SIZE()
IF size2% <> 2 THEN
    PRINT "ERROR: SIZE after remove should be 2"
    END
ENDIF
PRINT "SIZE after remove: "; size2%

REM Test REMOVE method - missing key
notremoved% = dict.REMOVE("nothere")
IF notremoved% <> 0 THEN
    PRINT "ERROR: REMOVE should return 0 for missing key"
    END
ENDIF
PRINT "REMOVE(nothere): "; notremoved%

REM Test CLEAR method
dict.CLEAR()
size3% = dict.SIZE()
IF size3% <> 0 THEN
    PRINT "ERROR: SIZE after CLEAR should be 0"
    END
ENDIF
PRINT "SIZE after CLEAR: "; size3%

PRINT "PASS: All method calls working!"

END
