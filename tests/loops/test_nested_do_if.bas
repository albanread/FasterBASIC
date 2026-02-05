REM Test: Nested DO LOOP with IF statements
REM Purpose: Verify CFG builder handles DO...LOOP nested with IF
REM Expected: All loop variants should execute correctly
REM Covers: DO WHILE, DO UNTIL, DO...LOOP WHILE, DO...LOOP UNTIL

PRINT "=== Test 1: DO WHILE in IF THEN ==="
DIM outer%
DIM inner%
DIM count%

outer% = 1
DO WHILE outer% <= 3
    IF outer% = 2 THEN
        inner% = 1
        count% = 0
        DO WHILE inner% <= 4
            PRINT "  Inner: "; inner%
            count% = count% + 1
            inner% = inner% + 1
        LOOP
        PRINT "  Inner loop ran "; count%; " times"
    END IF
    PRINT "Outer: "; outer%
    outer% = outer% + 1
LOOP
PRINT "Test 1 complete"
PRINT ""

PRINT "=== Test 2: DO UNTIL in IF ELSE ==="
outer% = 1
DO UNTIL outer% > 3
    IF outer% > 5 THEN
        PRINT "  Should not see this"
    ELSE
        inner% = 10
        DO UNTIL inner% > 12
            PRINT "  Else branch: "; inner%
            inner% = inner% + 1
        LOOP
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: DO...LOOP WHILE in IF ==="
outer% = 1
DO WHILE outer% <= 2
    IF outer% = 1 THEN
        inner% = 100
        DO
            PRINT "  Post-test loop: "; inner%
            inner% = inner% + 1
        LOOP WHILE inner% <= 102
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: DO...LOOP UNTIL in IF ==="
outer% = 1
DO WHILE outer% <= 2
    IF outer% = 2 THEN
        inner% = 200
        DO
            PRINT "  Until post-test: "; inner%
            inner% = inner% + 1
        LOOP UNTIL inner% > 202
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: IF inside DO WHILE ==="
DIM i%
i% = 1
DO WHILE i% <= 5
    IF i% MOD 2 = 0 THEN
        PRINT "Even: "; i%
    ELSE
        PRINT "Odd: "; i%
    END IF
    i% = i% + 1
LOOP
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: IF inside DO UNTIL ==="
i% = 1
DO UNTIL i% > 5
    IF i% <= 3 THEN
        PRINT "Low: "; i%
    ELSE
        PRINT "High: "; i%
    END IF
    i% = i% + 1
LOOP
PRINT "Test 6 complete"
PRINT ""

PRINT "=== Test 7: Multiple DOs in same IF ==="
DIM x%
x% = 1
IF x% = 1 THEN
    PRINT "First DO WHILE:"
    inner% = 1
    DO WHILE inner% <= 3
        PRINT "  A: "; inner%
        inner% = inner% + 1
    LOOP

    PRINT "Second DO UNTIL:"
    inner% = 20
    DO UNTIL inner% > 22
        PRINT "  B: "; inner%
        inner% = inner% + 1
    LOOP
END IF
PRINT "Test 7 complete"
PRINT ""

PRINT "=== Test 8: Deep nesting - DO in IF in DO ==="
outer% = 1
DO WHILE outer% <= 2
    PRINT "Outer: "; outer%
    IF outer% = 1 THEN
        DIM mid%
        mid% = 1
        DO WHILE mid% <= 2
            PRINT "  Mid: "; mid%
            IF mid% = 1 THEN
                inner% = 1
                DO WHILE inner% <= 3
                    PRINT "    Deep: "; inner%
                    inner% = inner% + 1
                LOOP
            END IF
            mid% = mid% + 1
        LOOP
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 8 complete"
PRINT ""

PRINT "=== Test 9: Mixed DO variants in IF branches ==="
i% = 1
DO WHILE i% <= 2
    IF i% = 1 THEN
        inner% = 50
        DO WHILE inner% <= 52
            PRINT "  WHILE branch: "; inner%
            inner% = inner% + 1
        LOOP
    ELSE
        inner% = 60
        DO UNTIL inner% > 62
            PRINT "  UNTIL branch: "; inner%
            inner% = inner% + 1
        LOOP
    END IF
    i% = i% + 1
LOOP
PRINT "Test 9 complete"
PRINT ""

PRINT "=== Test 10: DO with complex nested conditions ==="
outer% = 1
DO WHILE outer% <= 3
    IF outer% > 1 THEN
        inner% = 1
        DO WHILE inner% <= 4
            IF inner% = 2 OR inner% = 3 THEN
                PRINT "  Special value at outer="; outer%; " inner="; inner%
            END IF
            inner% = inner% + 1
        LOOP
    END IF
    outer% = outer% + 1
LOOP
PRINT "Test 10 complete"
PRINT ""

PRINT "=== Test 11: DO with early termination ==="
i% = 1
count% = 0
DO WHILE i% <= 10
    IF i% > 5 THEN
        PRINT "Breaking at: "; i%
        i% = 100  REM Force exit
    ELSE
        count% = count% + 1
        PRINT "Iteration: "; count%
    END IF
    i% = i% + 1
LOOP
PRINT "Terminated after "; count%; " iterations"
PRINT ""

PRINT "=== Test 12: Post-test DO...LOOP with IF ==="
i% = 1
DO
    IF i% = 3 THEN
        PRINT "Midpoint reached"
    END IF
    PRINT "Value: "; i%
    i% = i% + 1
LOOP WHILE i% <= 5
PRINT "Test 12 complete"
PRINT ""

PRINT "=== All nested DO-IF tests passed ==="
END
