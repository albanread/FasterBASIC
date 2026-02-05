REM Test AND, OR, and NOT with different types
PRINT "=== Testing Logical Operators ==="
PRINT ""

REM Test AND
A$ = "Hello"
B = 10
IF A$ = "Hello" AND B = 10 THEN PRINT "AND test: PASS" ELSE PRINT "AND test: FAIL"

REM Test OR
C$ = "World"
D = 5
IF C$ = "Wrong" OR D = 5 THEN PRINT "OR test: PASS" ELSE PRINT "OR test: FAIL"

REM Test NOT with string comparison
E$ = "Test"
IF NOT (E$ = "Wrong") THEN PRINT "NOT test: PASS" ELSE PRINT "NOT test: FAIL"

REM Complex expression
F$ = "A"
G = 1
H$ = "B"
I = 2
IF (F$ = "A" AND G = 1) OR (H$ = "B" AND I = 2) THEN
  PRINT "Complex test: PASS"
ELSE
  PRINT "Complex test: FAIL"
END IF
END
