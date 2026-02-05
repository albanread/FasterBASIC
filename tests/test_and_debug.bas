REM Test AND operator with different comparison types
PRINT "=== Testing AND operator ==="
PRINT ""

REM Test 1: Two integer comparisons
A = 10
B = 20
PRINT "Test 1: Integer comparisons"
PRINT "  A = 10, B = 20"
IF A = 10 THEN PRINT "  A = 10: TRUE" ELSE PRINT "  A = 10: FALSE"
IF B = 20 THEN PRINT "  B = 20: TRUE" ELSE PRINT "  B = 20: FALSE"
IF A = 10 AND B = 20 THEN PRINT "  A = 10 AND B = 20: TRUE" ELSE PRINT "  A = 10 AND B = 20: FALSE"
PRINT ""

REM Test 2: String and integer comparison
S$ = "Hello"
C = 5
PRINT "Test 2: String and integer comparisons"
PRINT "  S$ = Hello, C = 5"
IF S$ = "Hello" THEN PRINT "  S$ = Hello: TRUE" ELSE PRINT "  S$ = Hello: FALSE"
IF C = 5 THEN PRINT "  C = 5: TRUE" ELSE PRINT "  C = 5: FALSE"
IF S$ = "Hello" AND C = 5 THEN PRINT "  S$ = Hello AND C = 5: TRUE" ELSE PRINT "  S$ = Hello AND C = 5: FALSE"
PRINT ""

REM Test 3: Two string comparisons
S1$ = "A"
S2$ = "B"
PRINT "Test 3: Two string comparisons"
PRINT "  S1$ = A, S2$ = B"
IF S1$ = "A" THEN PRINT "  S1$ = A: TRUE" ELSE PRINT "  S1$ = A: FALSE"
IF S2$ = "B" THEN PRINT "  S2$ = B: TRUE" ELSE PRINT "  S2$ = B: FALSE"
IF S1$ = "A" AND S2$ = "B" THEN PRINT "  S1$ = A AND S2$ = B: TRUE" ELSE PRINT "  S1$ = A AND S2$ = B: FALSE"
END
