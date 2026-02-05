REM Test printing hex values to debug hashmap pointers

PRINT "Testing HEX$ function..."

DIM x AS INTEGER
x = 255
PRINT "x = "; x; " hex = "; HEX$(x)

DIM y AS LONG
y = 65535
PRINT "y = "; y; " hex = "; HEX$(y)

PRINT ""
PRINT "Creating first hashmap..."
DIM map1 AS HASHMAP

PRINT "Creating second hashmap..."
DIM map2 AS HASHMAP

PRINT ""
PRINT "Success!"

END
