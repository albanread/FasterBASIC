REM Test all hashmap methods
DIM d AS HASHMAP

REM Add entries using the working subscript operations
d("x") = "Alice"
d("y") = "Bob"
d("z") = "Charlie"

REM Test SIZE method
s% = d.SIZE()
PRINT s%

REM Test HASKEY method  
h% = d.HASKEY("x")
PRINT h%

REM Test REMOVE method
r% = d.REMOVE("y")
PRINT r%
PRINT d.SIZE()

REM Test CLEAR method
d.CLEAR()
PRINT d.SIZE()

PRINT "OK"

END
