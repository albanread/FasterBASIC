REM Test: Nested FOR loops with IF statements
REM Purpose: Verify CFG builder handles FOR...NEXT nested with IF
REM Expected: All nested FOR loops should iterate completely
REM Covers: FOR in IF branches, IF in FOR, nested combinations

PRINT "=== Test 1: FOR in IF THEN ==="
DIM outer%
DIM inner%
DIM count%

FOR outer% = 1 TO 3
    IF outer% = 2 THEN
        count% = 0
        FOR inner% = 1 TO 4
            PRINT "  Inner: "; inner%
            count% = count% + 1
        NEXT inner%
        PRINT "  Inner loop ran "; count%; " times"
    END IF
    PRINT "Outer: "; outer%
NEXT outer%
PRINT "Test 1 complete"
PRINT ""

PRINT "=== Test 2: FOR in IF ELSE ==="
FOR outer% = 1 TO 3
    IF outer% > 5 THEN
        PRINT "  Should not see this"
    ELSE
        FOR inner% = 10 TO 12
            PRINT "  Else branch: "; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: FOR with STEP in IF ==="
FOR outer% = 1 TO 3
    IF outer% = 2 THEN
        FOR inner% = 100 TO 106 STEP 2
            PRINT "  Step by 2: "; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: Negative STEP FOR in IF ==="
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        FOR inner% = 10 TO 5 STEP -1
            PRINT "  Countdown: "; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: IF inside FOR ==="
DIM i%
FOR i% = 1 TO 6
    IF i% MOD 2 = 0 THEN
        PRINT "Even: "; i%
    ELSE
        PRINT "Odd: "; i%
    END IF
NEXT i%
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: Multiple IFs in FOR ==="
FOR i% = 1 TO 6
    IF i% MOD 2 = 0 THEN
        PRINT "  Divisible by 2: "; i%
    END IF
    IF i% MOD 3 = 0 THEN
        PRINT "  Divisible by 3: "; i%
    END IF
NEXT i%
PRINT "Test 6 complete"
PRINT ""

PRINT "=== Test 7: Multiple FORs in same IF ==="
DIM x%
x% = 1
IF x% = 1 THEN
    PRINT "First FOR:"
    FOR inner% = 1 TO 3
        PRINT "  A: "; inner%
    NEXT inner%

    PRINT "Second FOR:"
    FOR inner% = 20 TO 22
        PRINT "  B: "; inner%
    NEXT inner%
END IF
PRINT "Test 7 complete"
PRINT ""

PRINT "=== Test 8: FOR in both IF branches ==="
FOR i% = 1 TO 2
    IF i% = 1 THEN
        FOR inner% = 50 TO 52
            PRINT "  THEN branch: "; inner%
        NEXT inner%
    ELSE
        FOR inner% = 60 TO 62
            PRINT "  ELSE branch: "; inner%
        NEXT inner%
    END IF
NEXT i%
PRINT "Test 8 complete"
PRINT ""

PRINT "=== Test 9: Deep nesting - FOR in IF in FOR ==="
FOR outer% = 1 TO 2
    PRINT "Outer: "; outer%
    IF outer% = 1 THEN
        DIM mid%
        FOR mid% = 1 TO 2
            PRINT "  Mid: "; mid%
            IF mid% = 1 THEN
                FOR inner% = 1 TO 3
                    PRINT "    Deep: "; inner%
                NEXT inner%
            END IF
        NEXT mid%
    END IF
NEXT outer%
PRINT "Test 9 complete"
PRINT ""

PRINT "=== Test 10: FOR with nested IF conditions ==="
FOR outer% = 1 TO 4
    IF outer% > 1 THEN
        FOR inner% = 1 TO 3
            IF inner% = 2 THEN
                PRINT "  Found special: outer="; outer%; " inner="; inner%
            END IF
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 10 complete"
PRINT ""

PRINT "=== Test 11: FOR with complex range expressions ==="
DIM start%
DIM end%
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        start% = 1
        end% = 3
        FOR inner% = start% TO end%
            PRINT "  Dynamic range: "; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 11 complete"
PRINT ""

PRINT "=== Test 12: Nested FOR with different STEPs ==="
FOR outer% = 2 TO 6 STEP 2
    IF outer% = 4 THEN
        FOR inner% = 1 TO 5 STEP 2
            PRINT "  Outer="; outer%; " Inner="; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 12 complete"
PRINT ""

PRINT "=== Test 13: FOR with EXIT FOR in IF ==="
FOR outer% = 1 TO 10
    IF outer% > 5 THEN
        PRINT "Exiting at: "; outer%
        EXIT FOR
    END IF
    PRINT "Value: "; outer%
NEXT outer%
PRINT "Test 13 complete"
PRINT ""

PRINT "=== Test 14: Nested FOR with inner EXIT FOR ==="
FOR outer% = 1 TO 3
    PRINT "Outer: "; outer%
    IF outer% = 2 THEN
        FOR inner% = 1 TO 10
            IF inner% > 3 THEN
                PRINT "  Inner EXIT at: "; inner%
                EXIT FOR
            END IF
            PRINT "  Inner: "; inner%
        NEXT inner%
    END IF
NEXT outer%
PRINT "Test 14 complete"
PRINT ""

PRINT "=== Test 15: Triple nesting - FOR in IF in FOR in IF ==="
FOR outer% = 1 TO 2
    IF outer% = 1 THEN
        FOR mid% = 1 TO 2
            IF mid% = 1 THEN
                FOR inner% = 1 TO 3
                    PRINT "Triple nested: o="; outer%; " m="; mid%; " i="; inner%
                NEXT inner%
            END IF
        NEXT mid%
    END IF
NEXT outer%
PRINT "Test 15 complete"
PRINT ""

PRINT "=== All nested FOR-IF tests passed ==="
END
