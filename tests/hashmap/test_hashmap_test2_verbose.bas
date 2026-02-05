REM Test 2 with verbose output to debug hang

PRINT "Test 2: Multiple Hashmaps"
PRINT "========================="

PRINT "Creating scores hashmap..."
DIM scores AS HASHMAP

PRINT "Creating ages hashmap..."
DIM ages AS HASHMAP

PRINT "Inserting scores Alice..."
scores("Alice") = "95"

PRINT "Inserting scores Bob..."
scores("Bob") = "87"

PRINT "Inserting scores Charlie..."
scores("Charlie") = "92"

PRINT "Inserting ages Alice..."
ages("Alice") = "25"

PRINT "Inserting ages Bob..."
ages("Bob") = "30"

PRINT "Inserting ages Charlie..."
ages("Charlie") = "28"

PRINT "Checking scores Alice..."
IF scores("Alice") <> "95" THEN
    PRINT "ERROR: Second hashmap failed"
    END
ENDIF

PRINT "Checking ages Alice..."
IF ages("Alice") <> "25" THEN
    PRINT "ERROR: Third hashmap failed"
    END
ENDIF

PRINT "✓ Multiple independent hashmaps work"

END
