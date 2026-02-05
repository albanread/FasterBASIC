REM Tests 1+2 combined with verbose output to debug hang

PRINT "Test 1: Basic Operations"
PRINT "========================"

PRINT "Creating contacts hashmap..."
DIM contacts AS HASHMAP

PRINT "Inserting contacts Alice..."
contacts("Alice") = "alice@example.com"

PRINT "Inserting contacts Bob..."
contacts("Bob") = "bob@example.com"

PRINT "Inserting contacts Charlie..."
contacts("Charlie") = "charlie@example.com"

PRINT "Checking contacts Alice..."
IF contacts("Alice") <> "alice@example.com" THEN
    PRINT "ERROR: Basic lookup failed"
    END
ENDIF

PRINT "✓ Basic insert and lookup"

REM ===================================================================
REM Test 2: Multiple Independent Hashmaps
REM ===================================================================
PRINT ""
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

PRINT "Checking contacts Alice (should still be alice@example.com)..."
IF contacts("Alice") <> "alice@example.com" THEN
    PRINT "ERROR: First hashmap corrupted"
    END
ENDIF

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

PRINT ""
PRINT "ALL TESTS 1-2 PASSED!"

END
