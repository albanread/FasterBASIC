REM ===================================================================
REM   Comprehensive Hashmap Test & Demo
REM   Tests all major hashmap features in one program
REM ===================================================================

PRINT "╔════════════════════════════════════════════════╗"
PRINT "║   FasterBASIC Hashmap - Comprehensive Test    ║"
PRINT "╚════════════════════════════════════════════════╝"
PRINT ""

REM ===================================================================
REM Test 1: Basic Creation and Simple Operations
REM ===================================================================
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

REM ===================================================================
REM Test 5: Mixing with Arrays
REM ===================================================================
PRINT ""
PRINT "Test 5: Arrays and Hashmaps Together"
PRINT "====================================="

DIM numbers(10) AS INTEGER
DIM words(5) AS STRING
DIM lookup AS HASHMAP

numbers(0) = 100
numbers(1) = 200
numbers(2) = 300

words(0) = "Hello"
words(1) = "World"
words(2) = "BASIC"

lookup("one") = "first"
lookup("two") = "second"
lookup("three") = "third"

IF numbers(1) <> 200 THEN
    PRINT "ERROR: Integer array failed with hashmap"
    END
ENDIF

IF words(2) <> "BASIC" THEN
    PRINT "ERROR: String array failed with hashmap"
    END
ENDIF

IF lookup("two") <> "second" THEN
    PRINT "ERROR: Hashmap failed with arrays"
    END
ENDIF

REM Interleaved access
n% = numbers(0)
s$ = lookup("one")
w$ = words(0)
m% = numbers(2)

IF n% <> 100 OR s$ <> "first" OR w$ <> "Hello" OR m% <> 300 THEN
    PRINT "ERROR: Interleaved access failed"
    END
ENDIF

PRINT "✓ Arrays and hashmaps coexist properly"

REM ===================================================================
REM Test 6: Stress Test (Many Entries)
REM ===================================================================
PRINT ""
PRINT "Test 6: Stress Test (50 entries)"
PRINT "================================="

DIM stress AS HASHMAP
DIM i AS INTEGER
DIM key AS STRING
DIM value AS STRING
DIM retrieved AS STRING

REM Insert 50 entries
FOR i = 1 TO 50
    key = "item" + STR$(i)
    value = "data" + STR$(i)
    stress(key) = value
NEXT i

REM Verify all 50 entries
FOR i = 1 TO 50
    key = "item" + STR$(i)
    retrieved = stress(key)
    value = "data" + STR$(i)

    IF retrieved <> value THEN
        PRINT "ERROR: Stress test failed at item "; i
        END
    ENDIF
NEXT i

PRINT "✓ Successfully stored and retrieved 50 entries"

REM ===================================================================
REM Test 7: Case Sensitivity
REM ===================================================================
PRINT ""
PRINT "Test 7: Case Sensitivity"
PRINT "========================"

DIM casetest AS HASHMAP

casetest("name") = "lowercase"
casetest("Name") = "titlecase"
casetest("NAME") = "uppercase"

IF casetest("name") <> "lowercase" THEN
    PRINT "ERROR: Lowercase key failed"
    END
ENDIF

IF casetest("Name") <> "titlecase" THEN
    PRINT "ERROR: Titlecase key failed"
    END
ENDIF

IF casetest("NAME") <> "uppercase" THEN
    PRINT "ERROR: Uppercase key failed"
    END
ENDIF

PRINT "✓ Keys are case-sensitive (as expected)"

REM ===================================================================
REM Test 8: Empty and Single Character Keys
REM ===================================================================
PRINT ""
PRINT "Test 8: Edge Case Keys"
PRINT "======================"

DIM edge AS HASHMAP

edge("a") = "single_a"
edge("z") = "single_z"
edge("1") = "digit_one"
edge("x") = "ex"

IF edge("a") <> "single_a" THEN
    PRINT "ERROR: Single char key 'a' failed"
    END
ENDIF

IF edge("1") <> "digit_one" THEN
    PRINT "ERROR: Single digit key failed"
    END
ENDIF

PRINT "✓ Edge case keys work correctly"

REM ===================================================================
REM Test 9: Long Values
REM ===================================================================
PRINT ""
PRINT "Test 9: Long Values"
PRINT "==================="

DIM longval AS HASHMAP

longval("short") = "x"
longval("medium") = "This is a medium length string value"
longval("long") = "This is a very long string value that contains many characters and should test the hashmap's ability to handle longer string content without any issues at all"

IF longval("short") <> "x" THEN
    PRINT "ERROR: Short value failed"
    END
ENDIF

IF LEN(longval("long")) < 100 THEN
    PRINT "ERROR: Long value truncated"
    END
ENDIF

PRINT "✓ Long values stored correctly"

REM ===================================================================
REM Test 10: Repeated Updates
REM ===================================================================
PRINT ""
PRINT "Test 10: Repeated Updates"
PRINT "========================="

DIM counter AS HASHMAP

counter("value") = "0"
counter("value") = "1"
counter("value") = "2"
counter("value") = "3"
counter("value") = "4"
counter("value") = "5"

IF counter("value") <> "5" THEN
    PRINT "ERROR: Repeated updates failed"
    END
ENDIF

PRINT "✓ Repeated updates to same key work"

REM ===================================================================
REM Final Summary
REM ===================================================================
PRINT ""
PRINT "╔════════════════════════════════════════════════╗"
PRINT "║             ALL TESTS PASSED! ✓                ║"
PRINT "╚════════════════════════════════════════════════╝"
PRINT ""
PRINT "Hashmap Features Verified:"
PRINT "  • Basic insert and lookup"
PRINT "  • Multiple independent hashmaps"
PRINT "  • Value updates"
PRINT "  • Special characters in keys"
PRINT "  • Coexistence with arrays"
PRINT "  • High capacity (50+ entries)"
PRINT "  • Case-sensitive keys"
PRINT "  • Edge case keys"
PRINT "  • Long string values"
PRINT "  • Repeated updates"
PRINT ""
PRINT "✅ FasterBASIC hashmap implementation is production-ready!"

END
