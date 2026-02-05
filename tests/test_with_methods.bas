DIM d AS HASHMAP

d("name") = "Alice"
d("age") = "30"
d("city") = "Portland"

PRINT "Initial size: "; d.SIZE()
PRINT "Name: "; d("name")

IF d.HASKEY("name") THEN
    PRINT "Has name key"
ENDIF

result% = d.REMOVE("age")
PRINT "Remove result: "; result%
PRINT "Size after remove: "; d.SIZE()

d.CLEAR()
PRINT "Size after clear: "; d.SIZE()

END
