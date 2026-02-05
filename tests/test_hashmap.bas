REM Test Hashmap Syntax
REM This program tests the basic hashmap declaration and operations

PRINT "FasterBASIC Hashmap Test"
PRINT "========================"
PRINT ""

REM Declare a hashmap
DIM dict AS HASHMAP

PRINT "Hashmap created"

REM Insert some values
dict("name") = "Alice"
dict("age") = "25"
dict("city") = "Portland"

PRINT "Values inserted"

REM Lookup values
PRINT "Name: "; dict("name")
PRINT "Age: "; dict("age")
PRINT "City: "; dict("city")

REM Test with multiple hashmaps
DIM scores AS HASHMAP
scores("alice") = "95"
scores("bob") = "87"
scores("charlie") = "92"

PRINT ""
PRINT "Scores:"
PRINT "Alice: "; scores("alice")
PRINT "Bob: "; scores("bob")
PRINT "Charlie: "; scores("charlie")

REM Test method calls
PRINT ""
PRINT "Method Call Tests:"
PRINT "------------------"

REM Test HASKEY method
IF dict.HASKEY("name") THEN
    PRINT "HASKEY: 'name' key exists"
ENDIF

IF dict.HASKEY("missing") THEN
    PRINT "HASKEY: 'missing' key exists (ERROR)"
ELSE
    PRINT "HASKEY: 'missing' key does not exist"
ENDIF

REM Test SIZE method
PRINT "SIZE: Dictionary has "; dict.SIZE(); " entries"

REM Test REMOVE method
PRINT "Removing 'age' key..."
result% = dict.REMOVE("age")
IF result% = 1 THEN
    PRINT "REMOVE: Successfully removed 'age'"
ELSE
    PRINT "REMOVE: Failed to remove 'age' (ERROR)"
ENDIF

PRINT "SIZE after remove: "; dict.SIZE(); " entries"

REM Try to remove non-existent key
result% = dict.REMOVE("missing")
IF result% = 0 THEN
    PRINT "REMOVE: Correctly returned 0 for missing key"
ENDIF

REM Test SIZE on scores hashmap
PRINT ""
PRINT "Scores SIZE: "; scores.SIZE(); " entries"

REM Test CLEAR method
PRINT "Clearing scores hashmap..."
scores.CLEAR()
PRINT "SIZE after CLEAR: "; scores.SIZE(); " entries"

PRINT ""
PRINT "Test complete!"

END
