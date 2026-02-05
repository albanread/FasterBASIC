REM Combined Tests 1-4 to isolate hang issue

PRINT "Test 1: Basic Operations"
PRINT "========================"

DIM contacts AS HASHMAP
contacts("Alice") = "alice@example.com"
contacts("Bob") = "bob@example.com"
contacts("Charlie") = "charlie@example.com"

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

DIM scores AS HASHMAP
DIM ages AS HASHMAP

scores("Alice") = "95"
scores("Bob") = "87"
scores("Charlie") = "92"

ages("Alice") = "25"
ages("Bob") = "30"
ages("Charlie") = "28"

IF contacts("Alice") <> "alice@example.com" THEN
    PRINT "ERROR: First hashmap corrupted"
    END
ENDIF

IF scores("Alice") <> "95" THEN
    PRINT "ERROR: Second hashmap failed"
    END
ENDIF

IF ages("Alice") <> "25" THEN
    PRINT "ERROR: Third hashmap failed"
    END
ENDIF

PRINT "✓ Multiple independent hashmaps work"

REM ===================================================================
REM Test 3: Value Updates
REM ===================================================================
PRINT ""
PRINT "Test 3: Value Updates"
PRINT "====================="

contacts("Alice") = "newalice@example.com"

IF contacts("Alice") <> "newalice@example.com" THEN
    PRINT "ERROR: Value update failed"
    END
ENDIF

IF contacts("Bob") <> "bob@example.com" THEN
    PRINT "ERROR: Other values corrupted after update"
    END
ENDIF

PRINT "✓ Value updates work correctly"

REM ===================================================================
REM Test 4: Special Characters in Keys
REM ===================================================================
PRINT ""
PRINT "Test 4: Special Key Characters"
PRINT "==============================="

DIM special AS HASHMAP

special("user@domain.com") = "email"
special("file.txt") = "filename"
special("path/to/file") = "filepath"
special("key-with-dashes") = "dashed"
special("key_with_underscore") = "underscored"
special("key with spaces") = "spaced"
special("123") = "numeric"
special("!@#$%") = "symbols"

IF special("user@domain.com") <> "email" THEN
    PRINT "ERROR: Email-like key failed"
    END
ENDIF

IF special("key with spaces") <> "spaced" THEN
    PRINT "ERROR: Space key failed"
    END
ENDIF

IF special("123") <> "numeric" THEN
    PRINT "ERROR: Numeric string key failed"
    END
ENDIF

PRINT "✓ Special characters in keys work"
PRINT ""
PRINT "ALL TESTS 1-4 PASSED!"

END
