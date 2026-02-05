REM Test: Nested REPEAT UNTIL loops with IF statements
REM Purpose: Verify CFG builder handles REPEAT...UNTIL nested with IF
REM Expected: All loops should execute correctly with proper exit conditions

PRINT "=== Test 1: REPEAT in IF THEN ==="
DIM outer%
DIM inner%
DIM count%

outer% = 1
REPEAT
    IF outer% = 2 THEN
        inner% = 1
        count% = 0
        REPEAT
            PRINT "  Inner: "; inner%
            count% = count% + 1
            inner% = inner% + 1
        UNTIL inner% > 4
        PRINT "  Inner loop ran "; count%; " times"
    END IF
    PRINT "Outer: "; outer%
    outer% = outer% + 1
UNTIL outer% > 3
PRINT "Test 1 complete"
PRINT ""

PRINT "=== Test 2: REPEAT in IF ELSE ==="
outer% = 1
REPEAT
    IF outer% > 5 THEN
        PRINT "  Should not see this"
    ELSE
        inner% = 10
        REPEAT
            PRINT "  Else branch: "; inner%
            inner% = inner% + 1
        UNTIL inner% > 12
    END IF
    outer% = outer% + 1
UNTIL outer% > 2
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: IF inside REPEAT ==="
DIM i%
i% = 1
REPEAT
    IF i% MOD 2 = 0 THEN
        PRINT "Even: "; i%
    ELSE
        PRINT "Odd: "; i%
    END IF
    i% = i% + 1
UNTIL i% > 5
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: REPEAT with nested IF conditions ==="
outer% = 1
REPEAT
    PRINT "Processing: "; outer%
    IF outer% > 1 THEN
        inner% = 1
        REPEAT
            IF inner% = 2 THEN
                PRINT "  Found special value: "; inner%
            END IF
            inner% = inner% + 1
        UNTIL inner% > 3
    END IF
    outer% = outer% + 1
UNTIL outer% > 3
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: Multiple REPEATs in IF branches ==="
DIM x%
x% = 1
IF x% = 1 THEN
    PRINT "First REPEAT:"
    inner% = 1
    REPEAT
        PRINT "  A: "; inner%
        inner% = inner% + 1
    UNTIL inner% > 3

    PRINT "Second REPEAT:"
    inner% = 20
    REPEAT
        PRINT "  B: "; inner%
        inner% = inner% + 1
    UNTIL inner% > 22
END IF
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: REPEAT with complex exit conditions ==="
outer% = 1
REPEAT
    IF outer% = 2 THEN
        inner% = 1
        count% = 0
        REPEAT
            count% = count% + 1
            IF count% >= 3 THEN
                PRINT "  Breaking early at count: "; count%
                inner% = 100  REM Force exit
            ELSE
                PRINT "  Count: "; count%
            END IF
            inner% = inner% + 1
        UNTIL inner% > 5
    END IF
    outer% = outer% + 1
UNTIL outer% > 3
PRINT "Test 6 complete"
PRINT ""

PRINT "=== Test 7: Deep nesting - REPEAT in IF in REPEAT ==="
outer% = 1
REPEAT
    PRINT "Outer: "; outer%
    IF outer% <= 2 THEN
        DIM mid%
        mid% = 1
        REPEAT
            PRINT "  Mid: "; mid%
            IF mid% = 1 THEN
                inner% = 1
                REPEAT
                    PRINT "    Deep: "; inner%
                    inner% = inner% + 1
                UNTIL inner% > 2
            END IF
            mid% = mid% + 1
        UNTIL mid% > 2
    END IF
    outer% = outer% + 1
UNTIL outer% > 2
PRINT "Test 7 complete"
PRINT ""

PRINT "=== Test 8: REPEAT with early termination ==="
i% = 1
count% = 0
REPEAT
    IF i% > 3 THEN
        PRINT "Terminating at: "; i%
        i% = 100  REM Force exit
    ELSE
        count% = count% + 1
        PRINT "Iteration: "; count%
    END IF
    i% = i% + 1
UNTIL i% > 10
PRINT "Loop terminated after "; count%; " iterations"
PRINT ""

PRINT "=== All nested REPEAT-IF tests passed ==="
END
