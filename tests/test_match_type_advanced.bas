OPTION SAMM ON

' =====================================================================
' Advanced MATCH TYPE Tests
' Covers: single-variable FOR EACH, two-variable FOR EACH T/E form,
' binding variable usage in expressions, accumulation patterns,
' ENDMATCH syntax, empty list, type counting, IF/FOR control flow
' inside arms, multiple sequential blocks, and single-element lists.
' =====================================================================

' === Test 1: Single-variable FOR EACH with MATCH TYPE ===
PRINT "=== Test 1: Single-variable FOR EACH ==="
DIM sv AS LIST OF ANY = LIST(100, "hello", 2.718)

FOR EACH E IN sv
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Dbl: "; f#
        CASE ELSE
            PRINT "Other"
    END MATCH
NEXT E

' === Test 2: Two-variable FOR EACH T, E with MATCH TYPE ===
PRINT ""
PRINT "=== Test 2: Two-variable FOR EACH ==="
DIM tv AS LIST OF ANY = LIST(42, "world", 3.14)

FOR EACH T, E IN tv
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Dbl: "; f#
    END MATCH
NEXT T

' === Test 3: ENDMATCH syntax variant ===
PRINT ""
PRINT "=== Test 3: ENDMATCH syntax ==="
DIM em AS LIST OF ANY = LIST("alpha", 42)

FOR EACH T, E IN em
    MATCH TYPE E
        CASE STRING s$
            PRINT "String: "; s$
        CASE INTEGER n%
            PRINT "Number: "; n%
    ENDMATCH
NEXT T

' === Test 4: Binding variable used in arithmetic expressions ===
PRINT ""
PRINT "=== Test 4: Binding in expressions ==="
DIM expr AS LIST OF ANY = LIST(10, 20, 30)

FOR EACH E IN expr
    MATCH TYPE E
        CASE INTEGER n%
            DIM doubled AS INTEGER
            LET doubled = n% * 2
            PRINT n%; " * 2 = "; doubled
        CASE ELSE
            PRINT "Not integer"
    END MATCH
NEXT E

' === Test 5: Accumulation pattern — sum integers, concat strings ===
PRINT ""
PRINT "=== Test 5: Accumulation pattern ==="
DIM accum AS LIST OF ANY = LIST(5, "hi", 10, " ", 15, "world")
DIM intSum AS INTEGER
DIM strConcat AS STRING
LET intSum = 0
LET strConcat = ""

FOR EACH T, E IN accum
    MATCH TYPE E
        CASE INTEGER n%
            LET intSum = intSum + n%
        CASE STRING s$
            LET strConcat = strConcat + s$
    END MATCH
NEXT T

PRINT "Integer sum: "; intSum
PRINT "String concat: "; strConcat

' === Test 6: Type counting pattern ===
PRINT ""
PRINT "=== Test 6: Type counting ==="
DIM counts AS LIST OF ANY = LIST(1, "a", 2.718, "b", 3, 1.414, "c", 5)
DIM intCount AS INTEGER
DIM strCount AS INTEGER
DIM dblCount AS INTEGER
DIM otherCount AS INTEGER
LET intCount = 0
LET strCount = 0
LET dblCount = 0
LET otherCount = 0

FOR EACH T, E IN counts
    MATCH TYPE E
        CASE INTEGER n%
            LET intCount = intCount + 1
        CASE STRING s$
            LET strCount = strCount + 1
        CASE DOUBLE f#
            LET dblCount = dblCount + 1
        CASE ELSE
            LET otherCount = otherCount + 1
    END MATCH
NEXT T

PRINT "Integers: "; intCount
PRINT "Strings: "; strCount
PRINT "Doubles: "; dblCount
PRINT "Others: "; otherCount

' === Test 7: Empty list — MATCH TYPE never executes ===
PRINT ""
PRINT "=== Test 7: Empty list ==="
DIM emptyList AS LIST OF ANY = LIST()
DIM emptyHits AS INTEGER
LET emptyHits = 0

FOR EACH E IN emptyList
    MATCH TYPE E
        CASE INTEGER n%
            LET emptyHits = emptyHits + 1
        CASE STRING s$
            LET emptyHits = emptyHits + 1
        CASE ELSE
            LET emptyHits = emptyHits + 1
    END MATCH
NEXT E

PRINT "Hits on empty list: "; emptyHits

' === Test 8: Single-element lists ===
PRINT ""
PRINT "=== Test 8: Single element ==="
DIM oneStr AS LIST OF ANY = LIST("only")

FOR EACH E IN oneStr
    MATCH TYPE E
        CASE STRING s$
            PRINT "Single element: "; s$
        CASE ELSE
            PRINT "Unexpected type"
    END MATCH
NEXT E

' === Test 9: Only CASE ELSE arm ===
PRINT ""
PRINT "=== Test 9: Only CASE ELSE ==="
DIM onlyElse AS LIST OF ANY = LIST(42, "test", 3.14)
DIM elseCount AS INTEGER
LET elseCount = 0

FOR EACH E IN onlyElse
    MATCH TYPE E
        CASE ELSE
            LET elseCount = elseCount + 1
    END MATCH
NEXT E

PRINT "CASE ELSE count: "; elseCount

' === Test 10: IF/ELSE inside MATCH TYPE arms ===
PRINT ""
PRINT "=== Test 10: Control flow inside arms ==="
DIM cf AS LIST OF ANY = LIST(5, -3, "short", "a longer string")

FOR EACH E IN cf
    MATCH TYPE E
        CASE INTEGER n%
            IF n% > 0 THEN
                PRINT n%; " is positive"
            ELSE
                PRINT n%; " is negative"
            END IF
        CASE STRING s$
            IF LEN(s$) > 5 THEN
                PRINT s$; " is long"
            ELSE
                PRINT s$; " is short"
            END IF
    END MATCH
NEXT E

' === Test 11: FOR loop inside MATCH TYPE arm ===
PRINT ""
PRINT "=== Test 11: FOR loop inside arm ==="
DIM fl AS LIST OF ANY = LIST(4, "skip", 3)

FOR EACH E IN fl
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Counting to "; n%; ":"
            DIM i AS INTEGER
            FOR i = 1 TO n%
                PRINT "  "; i
            NEXT i
        CASE STRING s$
            PRINT "Skipping string: "; s$
    END MATCH
NEXT E

' === Test 12: Multiple sequential MATCH TYPE blocks ===
PRINT ""
PRINT "=== Test 12: Sequential MATCH blocks ==="
DIM seq AS LIST OF ANY = LIST(7, "seven", 7.77)

PRINT "First pass (INT only):"
FOR EACH E IN seq
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "  INT "; n%
        CASE ELSE
            PRINT "  not-int"
    END MATCH
NEXT E

PRINT "Second pass (STR only):"
FOR EACH E IN seq
    MATCH TYPE E
        CASE STRING s$
            PRINT "  STR "; s$
        CASE ELSE
            PRINT "  not-str"
    END MATCH
NEXT E

PRINT "Third pass (DBL only):"
FOR EACH E IN seq
    MATCH TYPE E
        CASE DOUBLE f#
            PRINT "  DBL "; f#
        CASE ELSE
            PRINT "  not-dbl"
    END MATCH
NEXT E

' === Test 13: MATCH TYPE after list mutation ===
PRINT ""
PRINT "=== Test 13: Match after mutation ==="
DIM mut AS LIST OF ANY = LIST(1, "two")
mut.APPEND(3)
mut.PREPEND("zero")

PRINT "After prepend and append:"
FOR EACH T, E IN mut
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "  Int: "; n%
        CASE STRING s$
            PRINT "  Str: "; s$
        CASE ELSE
            PRINT "  Other"
    END MATCH
NEXT T

' === Test 14: String operations in STRING arm ===
PRINT ""
PRINT "=== Test 14: String ops in STRING arm ==="
DIM so AS LIST OF ANY = LIST("Hello", "WORLD", "fOo")

FOR EACH E IN so
    MATCH TYPE E
        CASE STRING s$
            PRINT "Original: "; s$; " Length: "; LEN(s$)
        CASE ELSE
            PRINT "Not a string"
    END MATCH
NEXT E

' === Test 15: All doubles — accumulate sum ===
PRINT ""
PRINT "=== Test 15: All doubles ==="
DIM allDbls AS LIST OF ANY = LIST(1.1, 2.2, 3.3, 4.4)
DIM dblSum AS DOUBLE
LET dblSum = 0.0

FOR EACH E IN allDbls
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Unexpected int"
        CASE DOUBLE f#
            LET dblSum = dblSum + f#
        CASE STRING s$
            PRINT "Unexpected string"
    END MATCH
NEXT E

PRINT "Double sum: "; dblSum

' === Test 16: All strings with separator ===
PRINT ""
PRINT "=== Test 16: All strings ==="
DIM allStrs AS LIST OF ANY = LIST("red", "green", "blue")
DIM result AS STRING
LET result = ""
DIM isFirst AS INTEGER
LET isFirst = 1

FOR EACH E IN allStrs
    MATCH TYPE E
        CASE STRING s$
            IF isFirst = 1 THEN
                LET result = s$
                LET isFirst = 0
            ELSE
                LET result = result + ", " + s$
            END IF
        CASE ELSE
            PRINT "Unexpected non-string"
    END MATCH
NEXT E

PRINT "Colors: "; result

' === Test 17: No matching arm, no CASE ELSE — silent skip ===
PRINT ""
PRINT "=== Test 17: No matching arm ==="
DIM nomatch AS LIST OF ANY = LIST(1.1, 2.2, 3.3)
DIM nmCount AS INTEGER
LET nmCount = 0

FOR EACH E IN nomatch
    MATCH TYPE E
        CASE INTEGER n%
            LET nmCount = nmCount + 1
        CASE STRING s$
            LET nmCount = nmCount + 1
    END MATCH
NEXT E

PRINT "Unmatched items hit count: "; nmCount

' === Test 18: Two MATCH TYPE blocks in same FOR EACH loop ===
PRINT ""
PRINT "=== Test 18: Two MATCH blocks per iteration ==="
DIM dual AS LIST OF ANY = LIST(42, "test")

FOR EACH T, E IN dual
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "First block: int "; n%
        CASE STRING s$
            PRINT "First block: str "; s$
    END MATCH

    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Second block: int "; n%
        CASE STRING s$
            PRINT "Second block: str "; s$
    END MATCH
NEXT T

' === Test 19: Arithmetic across multiple arms ===
PRINT ""
PRINT "=== Test 19: Arithmetic in multiple arms ==="
DIM arith AS LIST OF ANY = LIST(10, 3.14, 20, 2.718)
DIM runningTotal AS DOUBLE
LET runningTotal = 0.0

FOR EACH E IN arith
    MATCH TYPE E
        CASE INTEGER n%
            LET runningTotal = runningTotal + n%
            PRINT "Added int "; n%; " total: "; runningTotal
        CASE DOUBLE f#
            LET runningTotal = runningTotal + f#
            PRINT "Added dbl "; f#; " total: "; runningTotal
    END MATCH
NEXT E

PRINT "Final total: "; runningTotal

' === Test 20: Verify only one arm executes ===
PRINT ""
PRINT "=== Test 20: Single arm execution ==="
DIM singleElem AS LIST OF ANY = LIST(77)
DIM armHits AS INTEGER
LET armHits = 0

FOR EACH E IN singleElem
    MATCH TYPE E
        CASE INTEGER n%
            LET armHits = armHits + 1
            PRINT "Integer arm hit: "; n%
        CASE ELSE
            LET armHits = armHits + 1
            PRINT "Else arm hit"
    END MATCH
NEXT E

PRINT "Total arm hits: "; armHits

PRINT ""
PRINT "=== All advanced MATCH TYPE tests complete ==="

END
