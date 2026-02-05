REM Test: Nested IF statements inside WHILE loops
REM Purpose: Verify CFG builder handles IF inside WHILE correctly
REM Expected: All iterations should process IF conditions correctly

PRINT "=== Test 1: Simple IF in WHILE ==="
DIM i%
DIM count%

count% = 0
i% = 1
WHILE i% <= 5
    IF i% MOD 2 = 0 THEN
        PRINT "Even: "; i%
        count% = count% + 1
    END IF
    i% = i% + 1
WEND
PRINT "Found "; count%; " even numbers"
PRINT ""

PRINT "=== Test 2: IF-ELSE in WHILE ==="
i% = 1
WHILE i% <= 5
    IF i% <= 3 THEN
        PRINT "Low: "; i%
    ELSE
        PRINT "High: "; i%
    END IF
    i% = i% + 1
WEND
PRINT "Test 2 complete"
PRINT ""

PRINT "=== Test 3: Multiple IFs in WHILE ==="
i% = 1
WHILE i% <= 6
    IF i% MOD 2 = 0 THEN
        PRINT "  Divisible by 2: "; i%
    END IF
    IF i% MOD 3 = 0 THEN
        PRINT "  Divisible by 3: "; i%
    END IF
    i% = i% + 1
WEND
PRINT "Test 3 complete"
PRINT ""

PRINT "=== Test 4: Nested IF in WHILE ==="
i% = 1
WHILE i% <= 4
    PRINT "Outer i="; i%
    IF i% > 1 THEN
        IF i% < 4 THEN
            PRINT "  Middle range: "; i%
        ELSE
            PRINT "  At boundary: "; i%
        END IF
    ELSE
        PRINT "  First iteration"
    END IF
    i% = i% + 1
WEND
PRINT "Test 4 complete"
PRINT ""

PRINT "=== Test 5: IF with complex conditions in WHILE ==="
DIM x%
DIM y%
i% = 1
WHILE i% <= 3
    x% = i% * 2
    y% = i% * 3
    IF x% > 2 AND y% < 10 THEN
        PRINT "Match at i="; i%; " x="; x%; " y="; y%
    END IF
    i% = i% + 1
WEND
PRINT "Test 5 complete"
PRINT ""

PRINT "=== Test 6: IF affecting WHILE control ==="
i% = 1
count% = 0
WHILE i% <= 10
    IF i% >= 6 THEN
        PRINT "Breaking at i="; i%
        i% = 11  REM Force exit
    ELSE
        count% = count% + 1
        PRINT "Counting: "; count%
    END IF
    i% = i% + 1
WEND
PRINT "Test 6 complete - counted to "; count%
PRINT ""

PRINT "=== All nested IF-WHILE tests passed ==="
END
