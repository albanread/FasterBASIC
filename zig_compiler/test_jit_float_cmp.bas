REM ── JIT Float Comparison Tests ──
REM Global store/load defeats QBE constant folding

DIM pass AS INTEGER
DIM fail AS INTEGER
pass = 0
fail = 0

REM ── DOUBLE equality ──
DIM d AS DOUBLE
d = 5.0
d = d + 0.0
IF d = 5.0 THEN
  PRINT "PASS: double eq true"
  pass = pass + 1
ELSE
  PRINT "FAIL: double eq true"
  fail = fail + 1
ENDIF

IF d = 3.0 THEN
  PRINT "FAIL: double eq false"
  fail = fail + 1
ELSE
  PRINT "PASS: double eq false"
  pass = pass + 1
ENDIF

REM ── DOUBLE not-equal ──
IF d <> 3.0 THEN
  PRINT "PASS: double ne true"
  pass = pass + 1
ELSE
  PRINT "FAIL: double ne true"
  fail = fail + 1
ENDIF

IF d <> 5.0 THEN
  PRINT "FAIL: double ne false"
  fail = fail + 1
ELSE
  PRINT "PASS: double ne false"
  pass = pass + 1
ENDIF

REM ── DOUBLE greater-than ──
IF d > 3.0 THEN
  PRINT "PASS: double gt true"
  pass = pass + 1
ELSE
  PRINT "FAIL: double gt true"
  fail = fail + 1
ENDIF

IF d > 5.0 THEN
  PRINT "FAIL: double gt equal"
  fail = fail + 1
ELSE
  PRINT "PASS: double gt equal"
  pass = pass + 1
ENDIF

IF d > 7.0 THEN
  PRINT "FAIL: double gt false"
  fail = fail + 1
ELSE
  PRINT "PASS: double gt false"
  pass = pass + 1
ENDIF

REM ── DOUBLE less-than ──
IF d < 7.0 THEN
  PRINT "PASS: double lt true"
  pass = pass + 1
ELSE
  PRINT "FAIL: double lt true"
  fail = fail + 1
ENDIF

IF d < 5.0 THEN
  PRINT "FAIL: double lt equal"
  fail = fail + 1
ELSE
  PRINT "PASS: double lt equal"
  pass = pass + 1
ENDIF

IF d < 3.0 THEN
  PRINT "FAIL: double lt false"
  fail = fail + 1
ELSE
  PRINT "PASS: double lt false"
  pass = pass + 1
ENDIF

REM ── DOUBLE greater-or-equal ──
IF d >= 5.0 THEN
  PRINT "PASS: double ge equal"
  pass = pass + 1
ELSE
  PRINT "FAIL: double ge equal"
  fail = fail + 1
ENDIF

IF d >= 3.0 THEN
  PRINT "PASS: double ge greater"
  pass = pass + 1
ELSE
  PRINT "FAIL: double ge greater"
  fail = fail + 1
ENDIF

IF d >= 7.0 THEN
  PRINT "FAIL: double ge false"
  fail = fail + 1
ELSE
  PRINT "PASS: double ge false"
  pass = pass + 1
ENDIF

REM ── DOUBLE less-or-equal ──
IF d <= 5.0 THEN
  PRINT "PASS: double le equal"
  pass = pass + 1
ELSE
  PRINT "FAIL: double le equal"
  fail = fail + 1
ENDIF

IF d <= 7.0 THEN
  PRINT "PASS: double le less"
  pass = pass + 1
ELSE
  PRINT "FAIL: double le less"
  fail = fail + 1
ENDIF

IF d <= 3.0 THEN
  PRINT "FAIL: double le false"
  fail = fail + 1
ELSE
  PRINT "PASS: double le false"
  pass = pass + 1
ENDIF

REM ── SINGLE equality ──
DIM s AS SINGLE
s = 5.0
s = s + 0.0
IF s = 5.0 THEN
  PRINT "PASS: single eq true"
  pass = pass + 1
ELSE
  PRINT "FAIL: single eq true"
  fail = fail + 1
ENDIF

IF s = 3.0 THEN
  PRINT "FAIL: single eq false"
  fail = fail + 1
ELSE
  PRINT "PASS: single eq false"
  pass = pass + 1
ENDIF

REM ── SINGLE greater-than ──
IF s > 3.0 THEN
  PRINT "PASS: single gt true"
  pass = pass + 1
ELSE
  PRINT "FAIL: single gt true"
  fail = fail + 1
ENDIF

IF s > 7.0 THEN
  PRINT "FAIL: single gt false"
  fail = fail + 1
ELSE
  PRINT "PASS: single gt false"
  pass = pass + 1
ENDIF

REM ── SINGLE less-than ──
IF s < 7.0 THEN
  PRINT "PASS: single lt true"
  pass = pass + 1
ELSE
  PRINT "FAIL: single lt true"
  fail = fail + 1
ENDIF

IF s < 3.0 THEN
  PRINT "FAIL: single lt false"
  fail = fail + 1
ELSE
  PRINT "PASS: single lt false"
  pass = pass + 1
ENDIF

REM ── SINGLE greater-or-equal ──
IF s >= 5.0 THEN
  PRINT "PASS: single ge equal"
  pass = pass + 1
ELSE
  PRINT "FAIL: single ge equal"
  fail = fail + 1
ENDIF

IF s >= 7.0 THEN
  PRINT "FAIL: single ge false"
  fail = fail + 1
ELSE
  PRINT "PASS: single ge false"
  pass = pass + 1
ENDIF

REM ── SINGLE less-or-equal ──
IF s <= 5.0 THEN
  PRINT "PASS: single le equal"
  pass = pass + 1
ELSE
  PRINT "FAIL: single le equal"
  fail = fail + 1
ENDIF

IF s <= 3.0 THEN
  PRINT "FAIL: single le false"
  fail = fail + 1
ELSE
  PRINT "PASS: single le false"
  pass = pass + 1
ENDIF

REM ── Fractional DOUBLE ──
DIM h AS DOUBLE
h = 0.5
h = h + 0.0
IF h = 0.5 THEN
  PRINT "PASS: double half eq"
  pass = pass + 1
ELSE
  PRINT "FAIL: double half eq"
  fail = fail + 1
ENDIF

IF h < 1.0 THEN
  PRINT "PASS: double half lt"
  pass = pass + 1
ELSE
  PRINT "FAIL: double half lt"
  fail = fail + 1
ENDIF

IF h > 0.0 THEN
  PRINT "PASS: double half gt zero"
  pass = pass + 1
ELSE
  PRINT "FAIL: double half gt zero"
  fail = fail + 1
ENDIF

REM ── Integer comparison baseline ──
DIM a AS INTEGER
a = 42
a = a + 0
IF a = 42 THEN
  PRINT "PASS: int eq"
  pass = pass + 1
ELSE
  PRINT "FAIL: int eq"
  fail = fail + 1
ENDIF

IF a > 10 THEN
  PRINT "PASS: int gt"
  pass = pass + 1
ELSE
  PRINT "FAIL: int gt"
  fail = fail + 1
ENDIF

IF a < 100 THEN
  PRINT "PASS: int lt"
  pass = pass + 1
ELSE
  PRINT "FAIL: int lt"
  fail = fail + 1
ENDIF

PRINT ""
PRINT "Results: "; pass; " passed, "; fail; " failed"
IF fail = 0 THEN
  PRINT "ALL TESTS PASSED"
ELSE
  PRINT "SOME TESTS FAILED"
ENDIF

END
