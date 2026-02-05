DIM d AS HASHMAP

d("a") = "one"
d("b") = "two"
d("c") = "three"

PRINT d.SIZE()

IF d.HASKEY("a") THEN
    PRINT "found a"
ENDIF

d.CLEAR()

PRINT d.SIZE()

END
