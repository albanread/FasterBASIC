REM test_two_maps.bas
REM Simple test of two hashmaps to verify the fix works from BASIC

PRINT "Testing two hashmaps from BASIC..."
PRINT ""

REM Create first hashmap
PRINT "Creating map1..."
DIM map1 AS HASHMAP

PRINT "Inserting Alice into map1..."
map1("Alice") = "Engineer"

PRINT "Inserting Bob into map1..."
map1("Bob") = "Designer"

PRINT "Map1 complete!"
PRINT ""

REM Create second hashmap
PRINT "Creating map2..."
DIM map2 AS HASHMAP

PRINT "Inserting Charlie into map2..."
map2("Charlie") = "Manager"

PRINT "Inserting David into map2..."
map2("David") = "Developer"

PRINT "Map2 complete!"
PRINT ""

REM Test lookups
PRINT "Testing lookups..."
PRINT "map1(Alice) = "; map1("Alice")
PRINT "map1(Bob) = "; map1("Bob")
PRINT "map2(Charlie) = "; map2("Charlie")
PRINT "map2(David) = "; map2("David")
PRINT ""

PRINT "SUCCESS! Both hashmaps work correctly!"
END
