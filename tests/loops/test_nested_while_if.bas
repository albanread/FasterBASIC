REM Test: Nested WHILE loops inside IF statements
REM Purpose: Verify CFG builder handles nested control flow correctly
REM Expected: All nested loops should execute fully, not just once

PRINT "=== Test 1: WHILE in IF THEN ==="
DIM outer%
DIM inner%
DIM found%

outer% = 1
WHILE outer% <= 3
    IF outer% = 2 THEN
        inner% = 1
        WHILE inner% <= 4
            PRINT "  Inner loop: "; inner%
            inner% = inner% + 1
        WEND
        PRINT "  Inner loop completed"
    END IF
    PRINT "Outer: "; outer%
    outer% = outer% + 1
WEND
PRINT "Test 1 complete"
PRINT ""

PRINT "=== Test 2: WHILE in IF ELSE ==="
outer% = 1
WHILE outer% <= 3
    IF outer% = 5 THEN
        PRINT "  Should not see this"
    ELSE
        inner% = 10
        WHILE inner% <= 12
            PRINT "  Else inner: "; inner%
            inner% = inner% + 1
        WEND
    END IF
    outer% = outer% + 1
WEND
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: WHILE in multiple IF branches ==="
DIM x%
x% = 1
WHILE x% <= 2
    IF x% = 1 THEN
        inner% = 100
        WHILE inner% <= 102
            PRINT "  Branch 1: "; inner%
            inner% = inner% + 1
        WEND
    ELSE
        inner% = 200
        WHILE inner% <= 202
            PRINT "  Branch 2: "; inner%
            inner% = inner% + 1
        WEND
    END IF
    x% = x% + 1
WEND
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: Nested WHILE with conditions ==="
outer% = 1
WHILE outer% <= 3
    found% = 0
    IF outer% > 1 THEN
        inner% = 1
        WHILE inner% <= 5 AND found% = 0
            IF inner% = 3 THEN
                found% = 1
                PRINT "  Found at: "; inner%
            END IF
            inner% = inner% + 1
        WEND
    END IF
    outer% = outer% + 1
WEND
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: Deep nesting - WHILE in IF in WHILE ==="
outer% = 1
WHILE outer% <= 2
    PRINT "Outer level: "; outer%
    IF outer% = 1 THEN
        DIM mid%
        mid% = 1
        WHILE mid% <= 2
            PRINT "  Mid level: "; mid%
            IF mid% = 1 THEN
                inner% = 1
                WHILE inner% <= 3
                    PRINT "    Deep level: "; inner%
                    inner% = inner% + 1
                WEND
            END IF
            mid% = mid% + 1
        WEND
    END IF
    outer% = outer% + 1
WEND
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: Multiple WHILEs in same IF ==="
x% = 1
IF x% = 1 THEN
    PRINT "First WHILE:"
    inner% = 1
    WHILE inner% <= 3
        PRINT "  A: "; inner%
        inner% = inner% + 1
    WEND

    PRINT "Second WHILE:"
    inner% = 10
    WHILE inner% <= 12
        PRINT "  B: "; inner%
        inner% = inner% + 1
    WEND
END IF
PRINT "Test 6 complete"
PRINT ""

PRINT "=== All nested WHILE-IF tests passed ==="
END
