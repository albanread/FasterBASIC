REM Test: Mixed nested control flow structures
REM Purpose: Verify CFG builder handles complex nested combinations
REM Expected: All combinations of control structures should work correctly
REM Covers: WHILE+FOR+IF, DO+REPEAT+IF, SELECT CASE with loops, etc.

PRINT "=== Test 1: WHILE inside FOR inside IF ==="
DIM outer%
DIM mid%
DIM inner%

IF 1 = 1 THEN
    FOR outer% = 1 TO 2
        PRINT "FOR level: "; outer%
        mid% = 1
        WHILE mid% <= 2
            PRINT "  WHILE level: "; mid%
            mid% = mid% + 1
        WEND
    NEXT outer%
END IF
PRINT "Test 1 complete"
PRINT ""

PRINT "=== Test 2: FOR inside WHILE inside IF ==="
IF 1 = 1 THEN
    outer% = 1
    WHILE outer% <= 2
        PRINT "WHILE level: "; outer%
        FOR inner% = 1 TO 3
            PRINT "  FOR level: "; inner%
        NEXT inner%
        outer% = outer% + 1
    WEND
END IF
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: DO inside REPEAT inside IF ==="
IF 1 = 1 THEN
    outer% = 1
    REPEAT
        PRINT "REPEAT level: "; outer%
        inner% = 1
        DO WHILE inner% <= 2
            PRINT "  DO WHILE level: "; inner%
            inner% = inner% + 1
        LOOP
        outer% = outer% + 1
    UNTIL outer% > 2
END IF
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: REPEAT inside DO inside IF ==="
IF 1 = 1 THEN
    outer% = 1
    DO WHILE outer% <= 2
        PRINT "DO level: "; outer%
        inner% = 1
        REPEAT
            PRINT "  REPEAT level: "; inner%
            inner% = inner% + 1
        UNTIL inner% > 2
        outer% = outer% + 1
    LOOP
END IF
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: IF inside WHILE inside FOR ==="
FOR outer% = 1 TO 2
    mid% = 1
    WHILE mid% <= 2
        IF mid% = 1 THEN
            PRINT "FOR="; outer%; " WHILE="; mid%; " [THEN]"
        ELSE
            PRINT "FOR="; outer%; " WHILE="; mid%; " [ELSE]"
        END IF
        mid% = mid% + 1
    WEND
NEXT outer%
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: IF inside FOR inside DO ==="
outer% = 1
DO WHILE outer% <= 2
    FOR mid% = 1 TO 2
        IF mid% = 1 THEN
            PRINT "DO="; outer%; " FOR="; mid%; " [THEN]"
        END IF
    NEXT mid%
    outer% = outer% + 1
LOOP
PRINT "Test 6 complete"
PRINT ""

PRINT "=== Test 7: Mixed loops with multiple IFs ==="
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        mid% = 1
        WHILE mid% <= 2
            IF mid% = 1 THEN
                PRINT "Branch A: "; mid%
            ELSE
                PRINT "Branch B: "; mid%
            END IF
            mid% = mid% + 1
        WEND
    END IF
NEXT outer%
PRINT "Test 7 complete"
PRINT ""

PRINT "=== Test 8: FOR with WHILE and REPEAT ==="
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        PRINT "First branch - WHILE:"
        mid% = 1
        WHILE mid% <= 2
            PRINT "  WHILE: "; mid%
            mid% = mid% + 1
        WEND
    ELSE
        PRINT "Second branch - REPEAT:"
        mid% = 1
        REPEAT
            PRINT "  REPEAT: "; mid%
            mid% = mid% + 1
        UNTIL mid% > 2
    END IF
NEXT outer%
PRINT "Test 8 complete"
PRINT ""

PRINT "=== Test 9: Triple nesting with mixed types ==="
outer% = 1
WHILE outer% <= 2
    PRINT "WHILE: "; outer%
    IF outer% = 1 THEN
        FOR mid% = 1 TO 2
            PRINT "  FOR: "; mid%
            inner% = 1
            DO WHILE inner% <= 2
                PRINT "    DO: "; inner%
                inner% = inner% + 1
            LOOP
        NEXT mid%
    END IF
    outer% = outer% + 1
WEND
PRINT "Test 9 complete"
PRINT ""

PRINT "=== Test 10: Quadruple nesting ==="
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        mid% = 1
        WHILE mid% <= 2
            inner% = 1
            REPEAT
                DIM deep%
                deep% = 1
                DO WHILE deep% <= 2
                    PRINT "Depth 4: o="; outer%; " m="; mid%; " i="; inner%; " d="; deep%
                    deep% = deep% + 1
                LOOP
                inner% = inner% + 1
            UNTIL inner% > 1
            mid% = mid% + 1
        WEND
    END IF
NEXT outer%
PRINT "Test 10 complete"
PRINT ""

PRINT "=== Test 11: All loop types in one IF ==="
IF 1 = 1 THEN
    PRINT "WHILE section:"
    outer% = 1
    WHILE outer% <= 2
        PRINT "  WHILE: "; outer%
        outer% = outer% + 1
    WEND

    PRINT "FOR section:"
    FOR outer% = 1 TO 2
        PRINT "  FOR: "; outer%
    NEXT outer%

    PRINT "DO WHILE section:"
    outer% = 1
    DO WHILE outer% <= 2
        PRINT "  DO: "; outer%
        outer% = outer% + 1
    LOOP

    PRINT "REPEAT section:"
    outer% = 1
    REPEAT
        PRINT "  REPEAT: "; outer%
        outer% = outer% + 1
    UNTIL outer% > 2
END IF
PRINT "Test 11 complete"
PRINT ""

PRINT "=== Test 12: Nested IFs with different loops ==="
outer% = 1
WHILE outer% <= 2
    IF outer% = 1 THEN
        IF 1 = 1 THEN
            FOR inner% = 1 TO 2
                PRINT "Nested IF: "; inner%
            NEXT inner%
        END IF
    ELSE
        IF 1 = 1 THEN
            inner% = 1
            DO WHILE inner% <= 2
                PRINT "Other branch: "; inner%
                inner% = inner% + 1
            LOOP
        END IF
    END IF
    outer% = outer% + 1
WEND
PRINT "Test 12 complete"
PRINT ""

PRINT "=== Test 13: Alternating IF and loops ==="
FOR outer% = 1 TO 2
    PRINT "Level 1 FOR: "; outer%
    IF outer% = 1 THEN
        mid% = 1
        WHILE mid% <= 2
            PRINT "  Level 2 WHILE: "; mid%
            IF mid% = 1 THEN
                inner% = 1
                REPEAT
                    PRINT "    Level 3 REPEAT: "; inner%
                    inner% = inner% + 1
                UNTIL inner% > 2
            END IF
            mid% = mid% + 1
        WEND
    END IF
NEXT outer%
PRINT "Test 13 complete"
PRINT ""

PRINT "=== Test 14: Complex conditional nesting ==="
DIM x%
DIM y%
FOR x% = 1 TO 2
    IF x% > 0 THEN
        FOR y% = 1 TO 2
            IF y% > 0 THEN
                outer% = 1
                WHILE outer% <= 2
                    IF outer% = 1 THEN
                        PRINT "Deep: x="; x%; " y="; y%; " o="; outer%
                    END IF
                    outer% = outer% + 1
                WEND
            END IF
        NEXT y%
    END IF
NEXT x%
PRINT "Test 14 complete"
PRINT ""

PRINT "=== Test 15: Mixed post-test and pre-test loops ==="
outer% = 1
DO WHILE outer% <= 2
    PRINT "DO WHILE (pre-test): "; outer%
    IF outer% = 1 THEN
        inner% = 1
        DO
            PRINT "  DO...LOOP (post-test): "; inner%
            inner% = inner% + 1
        LOOP WHILE inner% <= 2
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 15 complete"
PRINT ""

PRINT "=== All mixed nested control flow tests passed ==="
END
