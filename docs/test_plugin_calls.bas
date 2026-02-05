' test_plugin_calls.bas
' Test program for Phase 3 plugin system
' Tests native C plugin functions called from BASIC

PRINT "=== FasterBASIC Plugin System Test ==="
PRINT ""

' Test simple integer functions
PRINT "Testing DOUBLE()..."
x% = 21
result% = DOUBLE(x%)
PRINT "  DOUBLE("; x%; ") = "; result%
IF result% = 42 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected 42, got"; result%
END IF
PRINT ""

' Test TRIPLE
PRINT "Testing TRIPLE()..."
y% = 10
result% = TRIPLE(y%)
PRINT "  TRIPLE("; y%; ") = "; result%
IF result% = 30 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected 30, got"; result%
END IF
PRINT ""

' Test ADD with two parameters
PRINT "Testing ADD()..."
a% = 15
b% = 27
sum% = ADD(a%, b%)
PRINT "  ADD("; a%; ","; b%; ") = "; sum%
IF sum% = 42 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected 42, got"; sum%
END IF
PRINT ""

' Test MULTIPLY
PRINT "Testing MULTIPLY()..."
m% = 6
n% = 7
prod% = MULTIPLY(m%, n%)
PRINT "  MULTIPLY("; m%; ","; n%; ") = "; prod%
IF prod% = 42 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected 42, got"; prod%
END IF
PRINT ""

' Test AVERAGE (returns float)
PRINT "Testing AVERAGE()..."
avg! = AVERAGE(10.0, 20.0)
PRINT "  AVERAGE(10.0, 20.0) = "; avg!
IF avg! >= 14.9 AND avg! <= 15.1 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected ~15.0, got"; avg!
END IF
PRINT ""

' Test POWER (returns double)
PRINT "Testing POWER()..."
p# = POWER(2.0, 8.0)
PRINT "  POWER(2.0, 8.0) = "; p#
IF p# >= 255.9 AND p# <= 256.1 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected ~256.0, got"; p#
END IF
PRINT ""

' Test FACTORIAL
PRINT "Testing FACTORIAL()..."
f% = FACTORIAL(5)
PRINT "  FACTORIAL(5) = "; f%
IF f% = 120 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected 120, got"; f%
END IF
PRINT ""

' Test IS_EVEN (returns bool)
PRINT "Testing IS_EVEN()..."
even% = IS_EVEN(42)
odd% = IS_EVEN(43)
PRINT "  IS_EVEN(42) = "; even%
PRINT "  IS_EVEN(43) = "; odd%
IF even% <> 0 AND odd% = 0 THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL"
END IF
PRINT ""

' Test REPEAT$ (string function)
PRINT "Testing REPEAT$()..."
s$ = REPEAT$("Hi", 3)
PRINT "  REPEAT$(""Hi"", 3) = """; s$; """"
IF s$ = "HiHiHi" THEN
    PRINT "  ✓ PASS"
ELSE
    PRINT "  ✗ FAIL: Expected ""HiHiHi"", got """; s$; """"
END IF
PRINT ""

' Test DEBUG_PRINT command (void return)
PRINT "Testing DEBUG_PRINT command..."
DEBUG_PRINT "This is a debug message from plugin"
PRINT "  ✓ PASS (if debug message printed above)"
PRINT ""

' Test error handling - factorial with negative number
PRINT "Testing error handling..."
PRINT "  (This should trigger an error and exit)"
bad% = FACTORIAL(-5)
PRINT "  ✗ FAIL: Should have exited with error"

END
