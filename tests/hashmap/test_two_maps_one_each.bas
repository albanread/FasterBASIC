REM Test two hashmaps with one insert each

PRINT "Creating first hashmap..."
DIM map1 AS HASHMAP

PRINT "Inserting into first hashmap..."
map1("Alice") = "value1"

PRINT "First hashmap complete!"

PRINT ""
PRINT "Creating second hashmap..."
DIM map2 AS HASHMAP

PRINT "Inserting into second hashmap..."
map2("Bob") = "value2"

PRINT "Second hashmap complete!"

PRINT ""
PRINT "Success!"

END
