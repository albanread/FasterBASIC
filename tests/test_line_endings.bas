REM =================================================================
REM test_line_endings.bas
REM Comprehensive test for the buffered file reader.
REM
REM Verifies that LINE INPUT # and EOF() handle every line-ending
REM convention correctly:
REM   - LF        (Unix / macOS)
REM   - CR+LF     (Windows)
REM   - CR        (classic Mac)
REM   - mixed endings in a single file
REM   - file with no trailing newline (last line still returned)
REM   - empty file (EOF immediately true)
REM   - single line, no newline
REM   - blank lines (consecutive terminators)
REM =================================================================

PRINT "=== Line-Ending Tests ==="
PRINT ""

DIM f$ AS STRING
DIM line$ AS STRING
DIM count AS INTEGER

REM -----------------------------------------------------------------
REM Test 1: Unix LF endings
REM -----------------------------------------------------------------
PRINT "Test 1: Unix LF endings"
f$ = "_test_lf.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM Write raw bytes: "AAA\nBBB\nCCC\n"
PRINT #1, CHR$(65);CHR$(65);CHR$(65);CHR$(10);
PRINT #1, CHR$(66);CHR$(66);CHR$(66);CHR$(10);
PRINT #1, CHR$(67);CHR$(67);CHR$(67);CHR$(10);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "AAA" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "BBB" THEN PRINT "  Line 2 OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
    IF count = 3 THEN
        IF line$ = "CCC" THEN PRINT "  Line 3 OK" ELSE PRINT "  Line 3 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 3 THEN PRINT "  Count OK (3)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 2: Windows CR+LF endings
REM -----------------------------------------------------------------
PRINT "Test 2: Windows CR+LF endings"
f$ = "_test_crlf.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM Write raw bytes: "XX\r\nYY\r\nZZ\r\n"
PRINT #1, CHR$(88);CHR$(88);CHR$(13);CHR$(10);
PRINT #1, CHR$(89);CHR$(89);CHR$(13);CHR$(10);
PRINT #1, CHR$(90);CHR$(90);CHR$(13);CHR$(10);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "XX" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "YY" THEN PRINT "  Line 2 OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
    IF count = 3 THEN
        IF line$ = "ZZ" THEN PRINT "  Line 3 OK" ELSE PRINT "  Line 3 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 3 THEN PRINT "  Count OK (3)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 3: Classic Mac CR-only endings
REM -----------------------------------------------------------------
PRINT "Test 3: Classic Mac CR-only endings"
f$ = "_test_cr.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM Write raw bytes: "one\rtwo\rthree\r"
PRINT #1, CHR$(111);CHR$(110);CHR$(101);CHR$(13);
PRINT #1, CHR$(116);CHR$(119);CHR$(111);CHR$(13);
PRINT #1, CHR$(116);CHR$(104);CHR$(114);CHR$(101);CHR$(101);CHR$(13);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "one" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "two" THEN PRINT "  Line 2 OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
    IF count = 3 THEN
        IF line$ = "three" THEN PRINT "  Line 3 OK" ELSE PRINT "  Line 3 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 3 THEN PRINT "  Count OK (3)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 4: No trailing newline (data but no terminator at end)
REM -----------------------------------------------------------------
PRINT "Test 4: No trailing newline"
f$ = "_test_noterm.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM Write "alpha\nbeta" — no newline after "beta"
PRINT #1, CHR$(97);CHR$(108);CHR$(112);CHR$(104);CHR$(97);CHR$(10);
PRINT #1, CHR$(98);CHR$(101);CHR$(116);CHR$(97);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "alpha" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "beta" THEN PRINT "  Line 2 OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 2 THEN PRINT "  Count OK (2)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 5: Single line, no newline at all
REM -----------------------------------------------------------------
PRINT "Test 5: Single line, no newline"
f$ = "_test_single.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM Write just "HELLO" — no terminator
PRINT #1, CHR$(72);CHR$(69);CHR$(76);CHR$(76);CHR$(79);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "HELLO" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 1 THEN PRINT "  Count OK (1)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 6: Empty file (zero bytes)
REM -----------------------------------------------------------------
PRINT "Test 6: Empty file"
f$ = "_test_empty.tmp"
OPEN f$ FOR OUTPUT AS #1
CLOSE #1

OPEN f$ FOR INPUT AS #1
IF EOF(1) THEN
    PRINT "  EOF immediately: OK"
ELSE
    PRINT "  EOF immediately: FAIL (expected true)"
END IF
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
LOOP
CLOSE #1
IF count = 0 THEN PRINT "  Count OK (0)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 7: Mixed line endings in one file
REM -----------------------------------------------------------------
PRINT "Test 7: Mixed line endings (LF, CR+LF, CR, no-term)"
f$ = "_test_mixed.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM "LF-line" + LF
PRINT #1, CHR$(76);CHR$(70);CHR$(45);CHR$(108);CHR$(105);CHR$(110);CHR$(101);CHR$(10);
REM "CRLF-line" + CR+LF
PRINT #1, CHR$(67);CHR$(82);CHR$(76);CHR$(70);CHR$(45);CHR$(108);CHR$(105);CHR$(110);CHR$(101);CHR$(13);CHR$(10);
REM "CR-line" + CR
PRINT #1, CHR$(67);CHR$(82);CHR$(45);CHR$(108);CHR$(105);CHR$(110);CHR$(101);CHR$(13);
REM "last" — no terminator
PRINT #1, CHR$(108);CHR$(97);CHR$(115);CHR$(116);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "LF-line" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "CRLF-line" THEN PRINT "  Line 2 OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
    IF count = 3 THEN
        IF line$ = "CR-line" THEN PRINT "  Line 3 OK" ELSE PRINT "  Line 3 FAIL: ["; line$; "]"
    END IF
    IF count = 4 THEN
        IF line$ = "last" THEN PRINT "  Line 4 OK" ELSE PRINT "  Line 4 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 4 THEN PRINT "  Count OK (4)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

REM -----------------------------------------------------------------
REM Test 8: Blank lines (consecutive terminators)
REM -----------------------------------------------------------------
PRINT "Test 8: Blank lines (consecutive terminators)"
f$ = "_test_blanks.tmp"
OPEN f$ FOR BINARY OUTPUT AS #1
REM "first\n\n\nlast\n" — two blank lines between first and last
PRINT #1, CHR$(102);CHR$(105);CHR$(114);CHR$(115);CHR$(116);CHR$(10);
PRINT #1, CHR$(10);
PRINT #1, CHR$(10);
PRINT #1, CHR$(108);CHR$(97);CHR$(115);CHR$(116);CHR$(10);
CLOSE #1

OPEN f$ FOR INPUT AS #1
count = 0
DO WHILE NOT EOF(1)
    LINE INPUT #1, line$
    count = count + 1
    IF count = 1 THEN
        IF line$ = "first" THEN PRINT "  Line 1 OK" ELSE PRINT "  Line 1 FAIL: ["; line$; "]"
    END IF
    IF count = 2 THEN
        IF line$ = "" THEN PRINT "  Line 2 (blank) OK" ELSE PRINT "  Line 2 FAIL: ["; line$; "]"
    END IF
    IF count = 3 THEN
        IF line$ = "" THEN PRINT "  Line 3 (blank) OK" ELSE PRINT "  Line 3 FAIL: ["; line$; "]"
    END IF
    IF count = 4 THEN
        IF line$ = "last" THEN PRINT "  Line 4 OK" ELSE PRINT "  Line 4 FAIL: ["; line$; "]"
    END IF
LOOP
CLOSE #1
IF count = 4 THEN PRINT "  Count OK (4)" ELSE PRINT "  Count FAIL: "; count
PRINT ""

PRINT "=== All line-ending tests complete ==="
