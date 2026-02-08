REM ============================================================
REM test_suffix_disambiguation.bas
REM Test suffix-aware variable name disambiguation
REM
REM Verifies that variable names ending in type suffixes do not
REM clash with keywords and built-in function names.
REM
REM Known limitation: array names that clash with $-functions
REM (e.g. DIM str$(5)) cannot be used in expression context
REM because str$(0) is ambiguous with STR$(0) function call.
REM Scalar string variables with clashing names DO work.
REM ============================================================

REM --- Test 1: Numeric suffix variables that share names with functions ---
REM These should all work as plain variables, not function calls.

val% = 42
PRINT "Test 1a - val% as integer variable: ";
IF val% = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"

sin! = 3.14
PRINT "Test 1b - sin! as single variable: ";
IF sin! > 3.0 AND sin! < 3.2 THEN PRINT "PASS" ELSE PRINT "FAIL"

cos# = 2.718
PRINT "Test 1c - cos# as double variable: ";
IF cos# > 2.7 AND cos# < 2.8 THEN PRINT "PASS" ELSE PRINT "FAIL"

exp% = 100
PRINT "Test 1d - exp% as integer variable: ";
IF exp% = 100 THEN PRINT "PASS" ELSE PRINT "FAIL"

log% = 55
PRINT "Test 1e - log% as integer variable: ";
IF log% = 55 THEN PRINT "PASS" ELSE PRINT "FAIL"

sqr! = 1.5
PRINT "Test 1f - sqr! as single variable: ";
IF sqr! > 1.4 AND sqr! < 1.6 THEN PRINT "PASS" ELSE PRINT "FAIL"

sgn% = -1
PRINT "Test 1g - sgn% as integer variable: ";
IF sgn% = -1 THEN PRINT "PASS" ELSE PRINT "FAIL"

rnd# = 0.5
PRINT "Test 1h - rnd# as double variable: ";
IF rnd# > 0.4 AND rnd# < 0.6 THEN PRINT "PASS" ELSE PRINT "FAIL"

int% = 99
PRINT "Test 1i - int% as integer variable: ";
IF int% = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 2: String variables with $ suffix that share names with functions ---
REM These should work as string variables, NOT as function calls,
REM because they are not followed by '('.

left$ = "hello"
PRINT "Test 2a - left$ as string variable: ";
IF left$ = "hello" THEN PRINT "PASS" ELSE PRINT "FAIL"

right$ = "world"
PRINT "Test 2b - right$ as string variable: ";
IF right$ = "world" THEN PRINT "PASS" ELSE PRINT "FAIL"

mid$ = "test"
PRINT "Test 2c - mid$ as string variable: ";
IF mid$ = "test" THEN PRINT "PASS" ELSE PRINT "FAIL"

chr$ = "A"
PRINT "Test 2d - chr$ as string variable: ";
IF chr$ = "A" THEN PRINT "PASS" ELSE PRINT "FAIL"

str$ = "1234"
PRINT "Test 2e - str$ as string variable: ";
IF str$ = "1234" THEN PRINT "PASS" ELSE PRINT "FAIL"

hex$ = "FF"
PRINT "Test 2f - hex$ as string variable: ";
IF hex$ = "FF" THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 3: The actual functions still work when called with () ---
REM Make sure the built-in functions are not broken.

PRINT "Test 3a - LEFT$() still works as function: ";
IF LEFT$("abcdef", 3) = "abc" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3b - RIGHT$() still works as function: ";
IF RIGHT$("abcdef", 3) = "def" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3c - MID$() still works as function: ";
IF MID$("abcdef", 2, 3) = "bcd" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3d - CHR$() still works as function: ";
IF CHR$(65) = "A" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3e - STR$() still works as function: ";
IF VAL(STR$(42)) = 42 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3f - VAL() still works as function: ";
IF VAL("123") = 123 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3g - SIN() still works as function: ";
IF SIN(0) = 0 THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 3h - COS() still works as function: ";
IF COS(0) = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 4: Mixed use - variable and function with same root name ---
REM Use the variable and the function in the same program.

val% = 10
PRINT "Test 4a - val% variable alongside VAL() function: ";
IF val% + VAL("5") = 15 THEN PRINT "PASS" ELSE PRINT "FAIL"

left$ = "prefix"
PRINT "Test 4b - left$ variable alongside LEFT$() function: ";
IF left$ + LEFT$("_suffix", 4) = "prefix_suf" THEN PRINT "PASS" ELSE PRINT "FAIL"

sin! = 1.0
PRINT "Test 4c - sin! variable alongside SIN() function: ";
IF sin! + SIN(0) = 1.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

mid$ = "middle"
PRINT "Test 4d - mid$ variable alongside MID$() function: ";
IF mid$ + MID$("XYZ", 2, 1) = "middleY" THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 5: Assignment and re-assignment of clashing names ---

str$ = "first"
str$ = "second"
PRINT "Test 5a - str$ re-assignment: ";
IF str$ = "second" THEN PRINT "PASS" ELSE PRINT "FAIL"

val% = 1
val% = val% + 1
PRINT "Test 5b - val% self-assignment: ";
IF val% = 2 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 6: Bare names LEFT, MID, RIGHT no longer reserved as keywords ---
REM (They were dead keyword registrations serving no purpose.)

left% = 7
PRINT "Test 6a - left% as integer variable: ";
IF left% = 7 THEN PRINT "PASS" ELSE PRINT "FAIL"

right% = 8
PRINT "Test 6b - right% as integer variable: ";
IF right% = 8 THEN PRINT "PASS" ELSE PRINT "FAIL"

mid% = 9
PRINT "Test 6c - mid% as integer variable: ";
IF mid% = 9 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 7: Expressions using suffixed variables ---

val% = 10
exp% = 20
PRINT "Test 7a - arithmetic with suffixed vars: ";
IF val% * exp% = 200 THEN PRINT "PASS" ELSE PRINT "FAIL"

left$ = "Hello"
right$ = " World"
PRINT "Test 7b - string concat with suffixed vars: ";
IF left$ + right$ = "Hello World" THEN PRINT "PASS" ELSE PRINT "FAIL"

sin! = 2.5
cos# = 1.5
PRINT "Test 7c - mixed float suffixed vars: ";
IF sin! + cos# = 4.0 THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 8: DIM with non-clashing string array name ---
REM Note: DIM with names that CLASH with $-functions (e.g. DIM str$(5))
REM works for DIM and assignment, but array reads in expressions are
REM ambiguous with function calls. Use non-clashing array names instead.

DIM words$(3)
words$(0) = "alpha"
words$(1) = "beta"
words$(2) = "gamma"
PRINT "Test 8a - DIM words$() array: ";
IF words$(0) = "alpha" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 8b - words$() array element 1: ";
IF words$(1) = "beta" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT "Test 8c - words$() array element 2: ";
IF words$(2) = "gamma" THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 9: Verify PRINT works with suffixed variable names ---
REM The variable should be printed, not interpreted as a function.

hex$ = "DEADBEEF"
PRINT "Test 9a - PRINT hex$ value: ";
IF hex$ = "DEADBEEF" THEN PRINT "PASS" ELSE PRINT "FAIL"

chr$ = "Z"
PRINT "Test 9b - PRINT chr$ value: ";
IF chr$ = "Z" THEN PRINT "PASS" ELSE PRINT "FAIL"

REM --- Test 10: Multiple suffixed vars on same base name ---

val% = 10
val! = 3.14
val# = 2.718
val$ = "ten"
PRINT "Test 10a - val% is 10: ";
IF val% = 10 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10b - val! is 3.14: ";
IF val! > 3.13 AND val! < 3.15 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10c - val# is 2.718: ";
IF val# > 2.717 AND val# < 2.719 THEN PRINT "PASS" ELSE PRINT "FAIL"
PRINT "Test 10d - val$ is ten: ";
IF val$ = "ten" THEN PRINT "PASS" ELSE PRINT "FAIL"

PRINT ""
PRINT "All suffix disambiguation tests complete."

END
