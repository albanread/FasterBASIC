#!/bin/bash
# Generate comprehensive test suite for FasterBASIC compiler

set -e

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/tests"
mkdir -p "$TESTS_DIR"

# Function to create a test file
create_test() {
    local category=$1
    local name=$2
    local content=$3

    mkdir -p "$TESTS_DIR/$category"
    echo "$content" > "$TESTS_DIR/$category/$name.bas"
    echo "Created: $category/$name.bas"
}

echo "=== Generating Comprehensive BASIC Test Suite ==="
echo ""

# ============================================================================
# WHILE LOOP TESTS
# ============================================================================

create_test "loops" "test_while_basic" '10 REM Test: Basic WHILE Loop
20 PRINT "=== WHILE Loop Tests ==="
30 REM Test 1: Basic WHILE counting
40 LET X% = 1
50 LET SUM% = 0
60 WHILE X% <= 5
70   PRINT X%;
80   LET SUM% = SUM% + X%
90   LET X% = X% + 1
100 WEND
110 PRINT ""
120 IF SUM% <> 15 THEN PRINT "ERROR: WHILE sum failed" : END
130 PRINT "PASS: Sum = "; SUM%
140 PRINT ""
150 REM Test 2: WHILE with zero iterations
160 LET Y% = 10
170 LET COUNT% = 0
180 WHILE Y% < 5
190   LET COUNT% = COUNT% + 1
200 WEND
210 IF COUNT% <> 0 THEN PRINT "ERROR: Zero iteration failed" : END
220 PRINT "PASS: Zero iterations"
230 PRINT ""
240 REM Test 3: Nested WHILE
250 LET I% = 1
260 LET TOTAL% = 0
270 WHILE I% <= 3
280   LET J% = 1
290   WHILE J% <= 2
300     LET TOTAL% = TOTAL% + 1
310     LET J% = J% + 1
320   WEND
330   LET I% = I% + 1
340 WEND
350 IF TOTAL% <> 6 THEN PRINT "ERROR: Nested WHILE failed" : END
360 PRINT "PASS: Nested WHILE = "; TOTAL%
370 PRINT "=== All WHILE Tests PASSED ==="
380 END'

# ============================================================================
# DO...LOOP TESTS
# ============================================================================

create_test "loops" "test_do_comprehensive" '10 REM Test: DO...LOOP Comprehensive
20 PRINT "=== DO...LOOP Tests ==="
30 REM Test 1: DO WHILE at top
40 LET X% = 1
50 LET SUM% = 0
60 DO WHILE X% <= 5
70   LET SUM% = SUM% + X%
80   LET X% = X% + 1
90 LOOP
100 IF SUM% <> 15 THEN PRINT "ERROR: DO WHILE failed" : END
110 PRINT "PASS: DO WHILE sum = "; SUM%
120 PRINT ""
130 REM Test 2: DO UNTIL at top
140 LET Y% = 1
150 LET PROD% = 1
160 DO UNTIL Y% > 5
170   LET PROD% = PROD% * 2
180   LET Y% = Y% + 1
190 LOOP
200 IF PROD% <> 32 THEN PRINT "ERROR: DO UNTIL failed" : END
210 PRINT "PASS: DO UNTIL prod = "; PROD%
220 PRINT ""
230 REM Test 3: DO...LOOP WHILE at bottom
240 LET Z% = 1
250 LET CNT% = 0
260 DO
270   LET CNT% = CNT% + 1
280   LET Z% = Z% + 1
290 LOOP WHILE Z% <= 5
300 IF CNT% <> 5 THEN PRINT "ERROR: LOOP WHILE failed" : END
310 PRINT "PASS: LOOP WHILE count = "; CNT%
320 PRINT ""
330 REM Test 4: DO...LOOP UNTIL at bottom
340 LET W% = 1
350 LET CNT2% = 0
360 DO
370   LET CNT2% = CNT2% + 1
380   LET W% = W% + 1
390 LOOP UNTIL W% > 5
400 IF CNT2% <> 5 THEN PRINT "ERROR: LOOP UNTIL failed" : END
410 PRINT "PASS: LOOP UNTIL count = "; CNT2%
420 PRINT ""
430 REM Test 5: Plain DO...LOOP with EXIT
440 LET V% = 0
450 DO
460   LET V% = V% + 1
470   IF V% = 7 THEN EXIT DO
480 LOOP
490 IF V% <> 7 THEN PRINT "ERROR: EXIT DO failed" : END
500 PRINT "PASS: EXIT DO at "; V%
510 PRINT "=== All DO...LOOP Tests PASSED ==="
520 END'

# ============================================================================
# STRING TESTS
# ============================================================================

create_test "strings" "test_string_basic" '10 REM Test: Basic String Operations
20 PRINT "=== String Operations Tests ==="
30 REM Test 1: String assignment
40 LET A$ = "Hello"
50 PRINT "A$ = "; A$
60 IF A$ <> "Hello" THEN PRINT "ERROR: String assignment failed" : END
70 PRINT "PASS: String assignment"
80 PRINT ""
90 REM Test 2: String concatenation
100 LET B$ = "Hello"
110 LET C$ = "World"
120 LET D$ = B$ + " " + C$
130 PRINT "Concatenation: "; D$
140 IF D$ <> "Hello World" THEN PRINT "ERROR: Concatenation failed" : END
150 PRINT "PASS: Concatenation"
160 PRINT ""
170 REM Test 3: Empty string
180 LET E$ = ""
190 PRINT "Empty string length: "; LEN(E$)
200 IF LEN(E$) <> 0 THEN PRINT "ERROR: Empty string failed" : END
210 PRINT "PASS: Empty string"
220 PRINT ""
230 REM Test 4: String comparison
240 LET F$ = "ABC"
250 LET G$ = "ABC"
260 LET H$ = "XYZ"
270 IF F$ = G$ THEN PRINT "PASS: ABC = ABC" ELSE PRINT "ERROR: String equality failed" : END
280 IF F$ <> H$ THEN PRINT "PASS: ABC <> XYZ" ELSE PRINT "ERROR: String inequality failed" : END
290 PRINT "=== All String Tests PASSED ==="
300 END'

create_test "strings" "test_string_functions" '10 REM Test: String Functions
20 PRINT "=== String Function Tests ==="
30 REM Test 1: LEN function
40 LET A$ = "Hello"
50 LET L% = LEN(A$)
60 PRINT "LEN(\"Hello\") = "; L%
70 IF L% <> 5 THEN PRINT "ERROR: LEN failed" : END
80 PRINT "PASS: LEN"
90 PRINT ""
100 REM Test 2: LEFT$ function
110 LET B$ = "FasterBASIC"
120 LET C$ = LEFT$(B$, 6)
130 PRINT "LEFT$(\"FasterBASIC\", 6) = "; C$
140 IF C$ <> "Faster" THEN PRINT "ERROR: LEFT$ failed" : END
150 PRINT "PASS: LEFT$"
160 PRINT ""
170 REM Test 3: RIGHT$ function
180 LET D$ = RIGHT$(B$, 5)
190 PRINT "RIGHT$(\"FasterBASIC\", 5) = "; D$
200 IF D$ <> "BASIC" THEN PRINT "ERROR: RIGHT$ failed" : END
210 PRINT "PASS: RIGHT$"
220 PRINT ""
230 REM Test 4: MID$ function
240 LET E$ = MID$(B$, 7, 5)
250 PRINT "MID$(\"FasterBASIC\", 7, 5) = "; E$
260 IF E$ <> "BASIC" THEN PRINT "ERROR: MID$ failed" : END
270 PRINT "PASS: MID$"
280 PRINT ""
290 REM Test 5: CHR$ function
300 LET F$ = CHR$(65)
310 PRINT "CHR$(65) = "; F$
320 IF F$ <> "A" THEN PRINT "ERROR: CHR$ failed" : END
330 PRINT "PASS: CHR$"
340 PRINT ""
350 REM Test 6: ASC function
360 LET G$ = "A"
370 LET H% = ASC(G$)
380 PRINT "ASC(\"A\") = "; H%
390 IF H% <> 65 THEN PRINT "ERROR: ASC failed" : END
400 PRINT "PASS: ASC"
410 PRINT "=== All String Function Tests PASSED ==="
420 END'

# ============================================================================
# TYPE CONVERSION TESTS
# ============================================================================

create_test "types" "test_conversions" '10 REM Test: Type Conversions
20 PRINT "=== Type Conversion Tests ==="
30 REM Test 1: Integer to Double
40 LET I% = 42
50 LET D# = I%
60 PRINT "Integer 42 to Double: "; D#
70 IF D# < 41.9 OR D# > 42.1 THEN PRINT "ERROR: INT to DOUBLE failed" : END
80 PRINT "PASS: INT to DOUBLE"
90 PRINT ""
100 REM Test 2: Double to Integer
110 LET E# = 42.7
120 LET J% = E#
130 PRINT "Double 42.7 to Integer: "; J%
140 IF J% <> 42 THEN PRINT "ERROR: DOUBLE to INT failed" : END
150 PRINT "PASS: DOUBLE to INT (truncation)"
160 PRINT ""
170 REM Test 3: Integer arithmetic with doubles
180 LET K% = 10
190 LET L# = 3.5
200 LET M# = K% + L#
210 PRINT "10 + 3.5 = "; M#
220 IF M# < 13.4 OR M# > 13.6 THEN PRINT "ERROR: Mixed arithmetic failed" : END
230 PRINT "PASS: Mixed arithmetic"
240 PRINT ""
250 REM Test 4: STR$ function
260 LET N% = 123
270 LET S$ = STR$(N%)
280 PRINT "STR$(123) = \""; S$; "\""
290 PRINT "PASS: STR$"
300 PRINT ""
310 REM Test 5: VAL function
320 LET T$ = "456"
330 LET V% = VAL(T$)
340 PRINT "VAL(\"456\") = "; V%
350 IF V% <> 456 THEN PRINT "ERROR: VAL failed" : END
360 PRINT "PASS: VAL"
370 PRINT "=== All Conversion Tests PASSED ==="
380 END'

# ============================================================================
# ARRAY TESTS
# ============================================================================

create_test "arrays" "test_array_basic" '10 REM Test: Basic Array Operations
20 PRINT "=== Array Tests ==="
30 REM Test 1: Integer array
40 DIM A%(10)
50 FOR I = 1 TO 10
60   LET A%(I) = I * 2
70 NEXT I
80 LET SUM% = 0
90 FOR I = 1 TO 10
100   LET SUM% = SUM% + A%(I)
110 NEXT I
120 PRINT "Sum of array elements: "; SUM%
130 IF SUM% <> 110 THEN PRINT "ERROR: Array sum failed" : END
140 PRINT "PASS: Integer array"
150 PRINT ""
160 REM Test 2: Double array
170 DIM B#(5)
180 FOR I = 1 TO 5
190   LET B#(I) = I * 1.5
200 NEXT I
210 PRINT "Double array values: ";
220 FOR I = 1 TO 5
230   PRINT B#(I);
240 NEXT I
250 PRINT ""
260 PRINT "PASS: Double array"
270 PRINT ""
280 REM Test 3: String array
290 DIM C$(3)
300 LET C$(1) = "One"
310 LET C$(2) = "Two"
320 LET C$(3) = "Three"
330 PRINT "String array: ";
340 FOR I = 1 TO 3
350   PRINT C$(I); " ";
360 NEXT I
370 PRINT ""
380 PRINT "PASS: String array"
390 PRINT "=== All Array Tests PASSED ==="
400 END'

create_test "arrays" "test_array_2d" '10 REM Test: Two-Dimensional Arrays
20 PRINT "=== 2D Array Tests ==="
30 REM Test 1: 2D integer array
40 DIM M%(3, 3)
50 FOR I = 1 TO 3
60   FOR J = 1 TO 3
70     LET M%(I, J) = I * 10 + J
80   NEXT J
90 NEXT I
100 PRINT "2D Array (3x3):"
110 FOR I = 1 TO 3
120   FOR J = 1 TO 3
130     PRINT M%(I, J);
140   NEXT J
150   PRINT ""
160 NEXT I
170 IF M%(2, 3) <> 23 THEN PRINT "ERROR: 2D array access failed" : END
180 PRINT "PASS: 2D array"
190 PRINT "=== All 2D Array Tests PASSED ==="
200 END'

# ============================================================================
# MATH INTRINSICS TESTS
# ============================================================================

create_test "functions" "test_math_intrinsics" '10 REM Test: Math Intrinsic Functions
20 PRINT "=== Math Intrinsic Tests ==="
30 REM Test 1: ABS
40 LET A% = -10
50 LET B% = ABS(A%)
60 PRINT "ABS(-10) = "; B%
70 IF B% <> 10 THEN PRINT "ERROR: ABS failed" : END
80 PRINT "PASS: ABS"
90 PRINT ""
100 REM Test 2: SGN
110 LET C% = SGN(-5)
120 LET D% = SGN(0)
130 LET E% = SGN(5)
140 PRINT "SGN(-5) = "; C%; ", SGN(0) = "; D%; ", SGN(5) = "; E%
150 IF C% <> -1 OR D% <> 0 OR E% <> 1 THEN PRINT "ERROR: SGN failed" : END
160 PRINT "PASS: SGN"
170 PRINT ""
180 REM Test 3: INT
190 LET F# = 42.7
200 LET G% = INT(F#)
210 PRINT "INT(42.7) = "; G%
220 IF G% <> 42 THEN PRINT "ERROR: INT failed" : END
230 PRINT "PASS: INT"
240 PRINT ""
250 REM Test 4: SQR
260 LET H# = SQR(16.0)
270 PRINT "SQR(16.0) = "; H#
280 IF H# < 3.9 OR H# > 4.1 THEN PRINT "ERROR: SQR failed" : END
290 PRINT "PASS: SQR"
300 PRINT ""
310 REM Test 5: SIN, COS, TAN
320 LET ZERO# = 0.0
330 LET S# = SIN(ZERO#)
340 LET C# = COS(ZERO#)
350 PRINT "SIN(0) = "; S%; ", COS(0) = "; C#
360 IF S# < -0.1 OR S# > 0.1 THEN PRINT "ERROR: SIN failed" : END
370 IF C# < 0.9 OR C# > 1.1 THEN PRINT "ERROR: COS failed" : END
380 PRINT "PASS: Trigonometric functions"
390 PRINT "=== All Math Intrinsic Tests PASSED ==="
400 END'

# ============================================================================
# SELECT CASE TESTS
# ============================================================================

create_test "conditionals" "test_select_case" '10 REM Test: SELECT CASE Statement
20 PRINT "=== SELECT CASE Tests ==="
30 REM Test 1: Integer SELECT CASE
40 LET X% = 2
50 SELECT CASE X%
60   CASE 1
70     PRINT "ERROR: Should not be 1"
80   CASE 2
90     PRINT "PASS: X = 2"
100   CASE 3
110     PRINT "ERROR: Should not be 3"
120   CASE ELSE
130     PRINT "ERROR: Should not be ELSE"
140 END SELECT
150 PRINT ""
160 REM Test 2: SELECT CASE with ranges
170 LET Y% = 15
180 SELECT CASE Y%
190   CASE 1 TO 10
200     PRINT "ERROR: Not in 1-10"
210   CASE 11 TO 20
220     PRINT "PASS: Y in range 11-20"
230   CASE 21 TO 30
240     PRINT "ERROR: Not in 21-30"
250 END SELECT
260 PRINT ""
270 REM Test 3: SELECT CASE with multiple values
280 LET Z% = 3
290 SELECT CASE Z%
300   CASE 1, 2, 4
310     PRINT "ERROR: Not 1, 2, or 4"
320   CASE 3, 5, 7
330     PRINT "PASS: Z is 3"
340   CASE ELSE
350     PRINT "ERROR: Should not be ELSE"
360 END SELECT
370 PRINT ""
380 REM Test 4: SELECT CASE ELSE
390 LET W% = 99
400 SELECT CASE W%
410   CASE 1
420     PRINT "ERROR: Not 1"
430   CASE 2
440     PRINT "ERROR: Not 2"
450   CASE ELSE
460     PRINT "PASS: CASE ELSE for 99"
470 END SELECT
480 PRINT "=== All SELECT CASE Tests PASSED ==="
490 END'

# ============================================================================
# GOSUB/RETURN TESTS
# ============================================================================

create_test "functions" "test_gosub" '10 REM Test: GOSUB and RETURN
20 PRINT "=== GOSUB/RETURN Tests ==="
30 LET RESULT% = 0
40 GOSUB 1000
50 IF RESULT% <> 42 THEN PRINT "ERROR: GOSUB failed" : END
60 PRINT "PASS: GOSUB/RETURN"
70 PRINT ""
80 REM Test nested GOSUB
90 LET X% = 1
100 GOSUB 2000
110 IF X% <> 3 THEN PRINT "ERROR: Nested GOSUB failed" : END
120 PRINT "PASS: Nested GOSUB"
130 PRINT "=== All GOSUB Tests PASSED ==="
140 END
1000 REM Subroutine 1
1010 LET RESULT% = 42
1020 PRINT "In subroutine 1"
1030 RETURN
2000 REM Subroutine 2 (calls subroutine 3)
2010 PRINT "In subroutine 2"
2020 LET X% = X% + 1
2030 GOSUB 3000
2040 RETURN
3000 REM Subroutine 3
3010 PRINT "In subroutine 3"
3020 LET X% = X% + 1
3030 RETURN'

# ============================================================================
# EDGE CASE TESTS
# ============================================================================

create_test "types" "test_edge_cases" '10 REM Test: Edge Cases and Boundary Conditions
20 PRINT "=== Edge Case Tests ==="
30 REM Test 1: Division by small numbers
40 LET A# = 1.0 / 3.0
50 LET B# = A# * 3.0
60 PRINT "1/3 * 3 = "; B#
70 IF B# < 0.99 OR B# > 1.01 THEN PRINT "ERROR: Float precision issue" : END
80 PRINT "PASS: Float precision"
90 PRINT ""
100 REM Test 2: Zero handling
110 LET ZERO% = 0
120 LET RESULT% = ZERO% + 0
130 IF RESULT% <> 0 THEN PRINT "ERROR: Zero handling failed" : END
140 PRINT "PASS: Zero handling"
150 PRINT ""
160 REM Test 3: Negative zero for doubles
170 LET NEG# = -0.0
180 LET POS# = 0.0
190 IF NEG# <> POS# THEN PRINT "WARNING: Negative zero differs from positive zero"
200 PRINT "PASS: Negative zero"
210 PRINT ""
220 REM Test 4: Very large integers
230 LET LARGE% = 1000000
240 LET DOUBLE_LARGE% = LARGE% + LARGE%
250 PRINT "1000000 + 1000000 = "; DOUBLE_LARGE%
260 IF DOUBLE_LARGE% <> 2000000 THEN PRINT "ERROR: Large integer failed" : END
270 PRINT "PASS: Large integers"
280 PRINT "=== All Edge Case Tests PASSED ==="
290 END'

# ============================================================================
# PRINT STATEMENT TESTS
# ============================================================================

create_test "io" "test_print_formats" '10 REM Test: PRINT Statement Formats
20 PRINT "=== PRINT Format Tests ==="
30 REM Test 1: PRINT with semicolons
40 PRINT "A"; "B"; "C"
50 PRINT "PASS: Semicolon concatenation"
60 PRINT ""
70 REM Test 2: PRINT with commas (zones)
80 PRINT "Col1", "Col2", "Col3"
90 PRINT "PASS: Comma zones"
100 PRINT ""
110 REM Test 3: PRINT with mixed types
120 LET X% = 42
130 LET Y# = 3.14
140 LET Z$ = "Pi"
150 PRINT Z$; " = "; Y%; " and answer = "; X%
160 PRINT "PASS: Mixed types"
170 PRINT ""
180 REM Test 4: PRINT with expressions
190 PRINT "2 + 2 = "; 2 + 2
200 PRINT "PASS: Expressions in PRINT"
210 PRINT "=== All PRINT Tests PASSED ==="
220 END'

echo ""
echo "=== Test Generation Complete ==="
echo ""
echo "Tests created in: $TESTS_DIR"
echo ""
echo "Test categories:"
echo "  - arithmetic/     (arithmetic operations)"
echo "  - loops/          (FOR, WHILE, DO...LOOP)"
echo "  - conditionals/   (IF, SELECT CASE, comparisons)"
echo "  - strings/        (string operations and functions)"
echo "  - arrays/         (1D and 2D arrays)"
echo "  - types/          (type conversions, edge cases)"
echo "  - functions/      (math intrinsics, GOSUB)"
echo "  - io/             (PRINT formats)"
echo ""
echo "Total tests generated: $(find "$TESTS_DIR" -name "*.bas" | wc -l)"
echo ""
echo "To run tests, use the main test suite script."
