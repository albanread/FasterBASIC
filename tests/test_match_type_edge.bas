OPTION SAMM ON

' =====================================================================
' MATCH TYPE Edge Case Tests
' Covers: nested MATCH TYPE via regular FOR, two-variable T/E form,
' double precision edge values, empty strings, single-char strings,
' integer edge values, arm ordering variations, repeated iteration,
' incrementally built lists, CASE ELSE work, ENDMATCH syntax,
' multiple lists sequentially, alternating types, cross-arm
' computation, one-element lists, partial arm coverage.
' =====================================================================

' === Test 1: Nested MATCH TYPE (inner uses same list, separate passes) ===
PRINT "=== Test 1: Nested MATCH TYPE ==="
DIM outer AS LIST OF ANY = LIST(1, "two", 3.14)
DIM inner AS LIST OF ANY = LIST("a", 100, 2.718)

' Outer loop — when we hit an integer, do an inner pass
FOR EACH E IN outer
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Outer int: "; n%
            ' Inner MATCH TYPE over a different list using a second FOR EACH
            DIM j AS INTEGER
            DIM innerLen AS INTEGER
            LET innerLen = inner.LENGTH()
            FOR j = 1 TO innerLen
                PRINT "  inner("; j; ")"
            NEXT j
        CASE STRING s$
            PRINT "Outer str: "; s$
        CASE DOUBLE f#
            PRINT "Outer dbl: "; f#
    END MATCH
NEXT E

' === Test 2: Two-variable form — verify T tag is accessible ===
PRINT ""
PRINT "=== Test 2: T variable still accessible ==="
DIM tvList AS LIST OF ANY = LIST(42, "hello", 9.99)

FOR EACH T, E IN tvList
    PRINT "Tag T = "; T;
    MATCH TYPE E
        CASE INTEGER n%
            PRINT " => INT "; n%
        CASE STRING s$
            PRINT " => STR "; s$
        CASE DOUBLE f#
            PRINT " => DBL "; f#
    END MATCH
NEXT T

' === Test 3: Double precision edge values ===
PRINT ""
PRINT "=== Test 3: Double edge values ==="
DIM dblEdge AS LIST OF ANY = LIST(0.1, -1.5, 999999.999)

FOR EACH E IN dblEdge
    MATCH TYPE E
        CASE DOUBLE f#
            IF f# < 0 THEN
                PRINT "Negative double: "; f#
            ELSE
                IF f# < 1 THEN
                    PRINT "Small double: "; f#
                ELSE
                    PRINT "Large double: "; f#
                END IF
            END IF
        CASE ELSE
            PRINT "Not a double"
    END MATCH
NEXT E

' === Test 4: Empty string and single-char string ===
PRINT ""
PRINT "=== Test 4: String edge cases ==="
DIM strEdge AS LIST OF ANY = LIST("", "x", "hello world")

FOR EACH E IN strEdge
    MATCH TYPE E
        CASE STRING s$
            IF LEN(s$) = 0 THEN
                PRINT "Empty string"
            ELSE
                IF LEN(s$) = 1 THEN
                    PRINT "Single char: "; s$
                ELSE
                    PRINT "Multi char ("; LEN(s$); "): "; s$
                END IF
            END IF
        CASE ELSE
            PRINT "Not a string"
    END MATCH
NEXT E

' === Test 5: Integer edge values — zero, negative, large ===
PRINT ""
PRINT "=== Test 5: Integer edge values ==="
DIM intEdge AS LIST OF ANY = LIST(0, -1, 32767, -32768, 1)

FOR EACH E IN intEdge
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE ELSE
            PRINT "Not an integer"
    END MATCH
NEXT E

' === Test 6: CASE arm ordering — STRING before INTEGER ===
PRINT ""
PRINT "=== Test 6: Reversed arm order ==="
DIM rev AS LIST OF ANY = LIST(10, "ten", 10.55)

FOR EACH E IN rev
    MATCH TYPE E
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Dbl: "; f#
        CASE INTEGER n%
            PRINT "Int: "; n%
    END MATCH
NEXT E

' === Test 7: Repeated iteration over same list ===
PRINT ""
PRINT "=== Test 7: Repeated iteration ==="
DIM rep AS LIST OF ANY = LIST(1, "two", 3.14)

DIM pass AS INTEGER
FOR pass = 1 TO 3
    PRINT "Pass "; pass; ":"
    FOR EACH E IN rep
        MATCH TYPE E
            CASE INTEGER n%
                PRINT "  int "; n%
            CASE STRING s$
                PRINT "  str "; s$
            CASE DOUBLE f#
                PRINT "  dbl "; f#
        END MATCH
    NEXT E
NEXT pass

' === Test 8: MATCH TYPE on list built incrementally ===
PRINT ""
PRINT "=== Test 8: Incrementally built list ==="
DIM incList AS LIST OF ANY = LIST()
incList.APPEND(100)
incList.APPEND("middle")
incList.APPEND(3.14)
incList.APPEND("end")
incList.APPEND(200)

FOR EACH E IN incList
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Appended int: "; n%
        CASE STRING s$
            PRINT "Appended str: "; s$
        CASE DOUBLE f#
            PRINT "Appended dbl: "; f#
    END MATCH
NEXT E

' === Test 9: CASE ELSE doing real work ===
PRINT ""
PRINT "=== Test 9: CASE ELSE with work ==="
DIM elseWork AS LIST OF ANY = LIST(1.1, 2.2, 3.3)
DIM elseSum AS INTEGER
LET elseSum = 0

FOR EACH E IN elseWork
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Should not happen"
        CASE ELSE
            LET elseSum = elseSum + 1
    END MATCH
NEXT E

PRINT "CASE ELSE hit count: "; elseSum

' === Test 10: ENDMATCH with all arms and mixed content ===
PRINT ""
PRINT "=== Test 10: ENDMATCH with mixed ==="
DIM emTest AS LIST OF ANY = LIST("first", 2, 3.14, "last")

FOR EACH T, E IN emTest
    MATCH TYPE E
        CASE STRING s$
            PRINT "S: "; s$
        CASE INTEGER n%
            PRINT "I: "; n%
        CASE DOUBLE f#
            PRINT "D: "; f#
        CASE ELSE
            PRINT "?: unknown"
    ENDMATCH
NEXT T

' === Test 11: Multiple lists, multiple MATCH TYPE in sequence ===
PRINT ""
PRINT "=== Test 11: Multiple lists sequentially ==="
DIM listA AS LIST OF ANY = LIST(1, "a")
DIM listB AS LIST OF ANY = LIST(2.718, "b")

PRINT "List A:"
FOR EACH E IN listA
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "  A int: "; n%
        CASE STRING s$
            PRINT "  A str: "; s$
    END MATCH
NEXT E

PRINT "List B:"
FOR EACH E IN listB
    MATCH TYPE E
        CASE DOUBLE f#
            PRINT "  B dbl: "; f#
        CASE STRING s$
            PRINT "  B str: "; s$
    END MATCH
NEXT E

' === Test 12: Alternating types pattern ===
PRINT ""
PRINT "=== Test 12: Alternating types ==="
DIM alt AS LIST OF ANY = LIST(1, "a", 2, "b", 3, "c")
DIM altIdx AS INTEGER
LET altIdx = 0

FOR EACH E IN alt
    LET altIdx = altIdx + 1
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Pos "; altIdx; " int: "; n%
        CASE STRING s$
            PRINT "Pos "; altIdx; " str: "; s$
    END MATCH
NEXT E

' === Test 13: Cross-arm computation ===
PRINT ""
PRINT "=== Test 13: Cross-arm computation ==="
DIM comp AS LIST OF ANY = LIST(10, 3.5, 20, 1.5)
DIM compTotal AS DOUBLE
LET compTotal = 0.0

FOR EACH E IN comp
    MATCH TYPE E
        CASE INTEGER n%
            LET compTotal = compTotal + n%
        CASE DOUBLE f#
            LET compTotal = compTotal + f#
    END MATCH
NEXT E

PRINT "Cross-arm total: "; compTotal

' === Test 14: One-element integer ===
PRINT ""
PRINT "=== Test 14: One-element integer ==="
DIM oneInt AS LIST OF ANY = LIST(999)
DIM oneIntResult AS INTEGER
LET oneIntResult = 0

FOR EACH E IN oneInt
    MATCH TYPE E
        CASE INTEGER n%
            LET oneIntResult = n%
        CASE ELSE
            PRINT "Not an integer"
    END MATCH
NEXT E

PRINT "One int result: "; oneIntResult

' === Test 15: One-element string ===
PRINT ""
PRINT "=== Test 15: One-element string ==="
DIM oneStrList AS LIST OF ANY = LIST("solitary")

FOR EACH E IN oneStrList
    MATCH TYPE E
        CASE STRING s$
            PRINT "One string: "; s$; " len="; LEN(s$)
        CASE ELSE
            PRINT "Not a string"
    END MATCH
NEXT E

' === Test 16: One-element double ===
PRINT ""
PRINT "=== Test 16: One-element double ==="
DIM oneDbl AS LIST OF ANY = LIST(2.71828)

FOR EACH E IN oneDbl
    MATCH TYPE E
        CASE DOUBLE f#
            PRINT "One double: "; f#
        CASE ELSE
            PRINT "Not a double"
    END MATCH
NEXT E

' === Test 17: INT + ELSE on mixed list ===
PRINT ""
PRINT "=== Test 17: INT + ELSE on mixed ==="
DIM intElse AS LIST OF ANY = LIST(1, "skip", 2.22, 2, "skip2")
DIM intElseInts AS INTEGER
DIM intElseOthers AS INTEGER
LET intElseInts = 0
LET intElseOthers = 0

FOR EACH E IN intElse
    MATCH TYPE E
        CASE INTEGER n%
            LET intElseInts = intElseInts + 1
        CASE ELSE
            LET intElseOthers = intElseOthers + 1
    END MATCH
NEXT E

PRINT "Ints: "; intElseInts; " Others: "; intElseOthers

' === Test 18: Only DOUBLE arm — non-doubles skip silently ===
PRINT ""
PRINT "=== Test 18: Only DOUBLE arm ==="
DIM onlyDbl AS LIST OF ANY = LIST(1, 2.22, "three", 4.44)
DIM dblHits AS INTEGER
LET dblHits = 0

FOR EACH E IN onlyDbl
    MATCH TYPE E
        CASE DOUBLE f#
            LET dblHits = dblHits + 1
            PRINT "Double: "; f#
    END MATCH
NEXT E

PRINT "Double hits: "; dblHits

' === Test 19: Only STRING arm — non-strings skip silently ===
PRINT ""
PRINT "=== Test 19: Only STRING arm ==="
DIM onlyStr AS LIST OF ANY = LIST(1, "hello", 2.22, "world", 3)
DIM strHits AS INTEGER
LET strHits = 0

FOR EACH E IN onlyStr
    MATCH TYPE E
        CASE STRING s$
            LET strHits = strHits + 1
            PRINT "String: "; s$
    END MATCH
NEXT E

PRINT "String hits: "; strHits

' === Test 20: Regular FOR loop inside arm with binding variable ===
PRINT ""
PRINT "=== Test 20: FOR loop with binding ==="
DIM forBind AS LIST OF ANY = LIST(3, "skip", 5)

FOR EACH E IN forBind
    MATCH TYPE E
        CASE INTEGER n%
            DIM k AS INTEGER
            DIM ksum AS INTEGER
            LET ksum = 0
            FOR k = 1 TO n%
                LET ksum = ksum + k
            NEXT k
            PRINT "Sum 1.."; n%; " = "; ksum
        CASE STRING s$
            PRINT "Skipped: "; s$
    END MATCH
NEXT E

PRINT ""
PRINT "=== All MATCH TYPE edge case tests complete ==="

END
