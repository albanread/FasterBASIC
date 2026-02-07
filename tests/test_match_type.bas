OPTION SAMM ON

' === Test 1: Basic MATCH TYPE with single-variable FOR EACH ===
PRINT "=== Test 1: MATCH TYPE with FOR EACH ==="
DIM mixed AS LIST OF ANY = LIST(42, "hello", 3.14)

FOR EACH E IN mixed
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Flt: "; f#
    END MATCH
NEXT E

' === Test 2: MATCH TYPE with two-variable FOR EACH and CASE ELSE ===
PRINT ""
PRINT "=== Test 2: MATCH TYPE with CASE ELSE ==="
DIM mixed2 AS LIST OF ANY = LIST(99, "world")

FOR EACH T, E IN mixed2
    MATCH TYPE E
        CASE STRING s$
            PRINT "Got string: "; s$
        CASE ELSE
            PRINT "Got something else"
    END MATCH
NEXT T

' === Test 3: All integer values ===
PRINT ""
PRINT "=== Test 3: All integers ==="
DIM nums AS LIST OF ANY = LIST(10, 20, 30)

FOR EACH E IN nums
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Value: "; n%
        CASE ELSE
            PRINT "Not an integer"
    END MATCH
NEXT E

' === Test 4: Mixed types with all arms (two-variable form) ===
PRINT ""
PRINT "=== Test 4: Full type coverage ==="
DIM full AS LIST OF ANY = LIST(1, 2.718, "pi", 42, "test")

FOR EACH T, E IN full
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "INT: "; n%
        CASE DOUBLE f#
            PRINT "DBL: "; f#
        CASE STRING s$
            PRINT "STR: "; s$
        CASE ELSE
            PRINT "OTHER"
    END MATCH
NEXT T

' === Test 5: No matching arm — silent skip ===
PRINT ""
PRINT "=== Test 5: No matching arm ==="
DIM only_ints AS LIST OF ANY = LIST(1, 2, 3)

FOR EACH E IN only_ints
    MATCH TYPE E
        CASE STRING s$
            PRINT "Should not print"
        CASE INTEGER n%
            PRINT "Found int: "; n%
    END MATCH
NEXT E

PRINT ""
PRINT "=== All MATCH TYPE tests complete ==="

END
