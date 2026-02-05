' test_iif.bas
' Test IIF (Immediate IF) function - inline conditional expression
' Syntax: result = IIF(condition, trueValue, falseValue)

PRINT "=== IIF (Immediate IF) Function Test ==="
PRINT ""

' =============================================================================
' Test 1: Basic IIF with integer values
' =============================================================================
PRINT "Test 1: Basic IIF with Integers"
DIM x, result

x = 10
result = IIF(x > 5, 100, 200)
PRINT "  x = 10, IIF(x > 5, 100, 200) = "; result
IF result = 100 THEN
    PRINT "  PASS: Condition true, returned 100"
ELSE
    PRINT "  FAIL: Expected 100, got "; result
END IF

x = 3
result = IIF(x > 5, 100, 200)
PRINT "  x = 3, IIF(x > 5, 100, 200) = "; result
IF result = 200 THEN
    PRINT "  PASS: Condition false, returned 200"
ELSE
    PRINT "  FAIL: Expected 200, got "; result
END IF

PRINT ""

' =============================================================================
' Test 2: IIF with string values
' =============================================================================
PRINT "Test 2: IIF with Strings"
DIM name$, greeting$, age

name$ = "Alice"
age = 25

greeting$ = IIF(age >= 18, "Adult", "Minor")
PRINT "  age = 25, IIF(age >= 18, 'Adult', 'Minor') = '"; greeting$; "'"
IF greeting$ = "Adult" THEN
    PRINT "  PASS: Adult greeting"
ELSE
    PRINT "  FAIL: Expected 'Adult', got '"; greeting$; "'"
END IF

age = 15
greeting$ = IIF(age >= 18, "Adult", "Minor")
PRINT "  age = 15, IIF(age >= 18, 'Adult', 'Minor') = '"; greeting$; "'"
IF greeting$ = "Minor" THEN
    PRINT "  PASS: Minor greeting"
ELSE
    PRINT "  FAIL: Expected 'Minor', got '"; greeting$; "'"
END IF

PRINT ""

' =============================================================================
' Test 3: IIF with expressions
' =============================================================================
PRINT "Test 3: IIF with Expressions"
DIM a, b, maximum

a = 42
b = 17
maximum = IIF(a > b, a, b)
PRINT "  a = 42, b = 17"
PRINT "  maximum = IIF(a > b, a, b) = "; maximum
IF maximum = 42 THEN
    PRINT "  PASS: Returned larger value"
ELSE
    PRINT "  FAIL: Expected 42, got "; maximum
END IF

a = 8
b = 23
maximum = IIF(a > b, a, b)
PRINT "  a = 8, b = 23"
PRINT "  maximum = IIF(a > b, a, b) = "; maximum
IF maximum = 23 THEN
    PRINT "  PASS: Returned larger value"
ELSE
    PRINT "  FAIL: Expected 23, got "; maximum
END IF

PRINT ""

' =============================================================================
' Test 4: Nested IIF
' =============================================================================
PRINT "Test 4: Nested IIF"
DIM score, grade$

score = 85
grade$ = IIF(score >= 90, "A", IIF(score >= 80, "B", IIF(score >= 70, "C", "F")))
PRINT "  score = 85"
PRINT "  grade$ = IIF(score >= 90, 'A', IIF(score >= 80, 'B', IIF(score >= 70, 'C', 'F')))"
PRINT "  grade$ = '"; grade$; "'"
IF grade$ = "B" THEN
    PRINT "  PASS: Nested IIF returned 'B'"
ELSE
    PRINT "  FAIL: Expected 'B', got '"; grade$; "'"
END IF

score = 65
grade$ = IIF(score >= 90, "A", IIF(score >= 80, "B", IIF(score >= 70, "C", "F")))
PRINT "  score = 65"
PRINT "  grade$ = '"; grade$; "'"
IF grade$ = "F" THEN
    PRINT "  PASS: Nested IIF returned 'F'"
ELSE
    PRINT "  FAIL: Expected 'F', got '"; grade$; "'"
END IF

PRINT ""

' =============================================================================
' Test 5: IIF with arithmetic expressions
' =============================================================================
PRINT "Test 5: IIF with Arithmetic"
DIM num, doubled_or_halved

num = 10
doubled_or_halved = IIF(num < 20, num * 2, num / 2)
PRINT "  num = 10"
PRINT "  IIF(num < 20, num * 2, num / 2) = "; doubled_or_halved
IF doubled_or_halved = 20 THEN
    PRINT "  PASS: Doubled when < 20"
ELSE
    PRINT "  FAIL: Expected 20, got "; doubled_or_halved
END IF

num = 30
doubled_or_halved = IIF(num < 20, num * 2, num / 2)
PRINT "  num = 30"
PRINT "  IIF(num < 20, num * 2, num / 2) = "; doubled_or_halved
IF doubled_or_halved = 15 THEN
    PRINT "  PASS: Halved when >= 20"
ELSE
    PRINT "  FAIL: Expected 15, got "; doubled_or_halved
END IF

PRINT ""

' =============================================================================
' Test 6: IIF with equality comparisons
' =============================================================================
PRINT "Test 6: IIF with Equality"
DIM status$, code

code = 200
status$ = IIF(code = 200, "OK", "ERROR")
PRINT "  code = 200, IIF(code = 200, 'OK', 'ERROR') = '"; status$; "'"
IF status$ = "OK" THEN
    PRINT "  PASS: Equality test"
ELSE
    PRINT "  FAIL: Expected 'OK', got '"; status$; "'"
END IF

code = 404
status$ = IIF(code = 200, "OK", "ERROR")
PRINT "  code = 404, IIF(code = 200, 'OK', 'ERROR') = '"; status$; "'"
IF status$ = "ERROR" THEN
    PRINT "  PASS: Inequality test"
ELSE
    PRINT "  FAIL: Expected 'ERROR', got '"; status$; "'"
END IF

PRINT ""

' =============================================================================
' Test 7: IIF in PRINT statement
' =============================================================================
PRINT "Test 7: IIF in PRINT Statement"
DIM value, sign$

value = 42
PRINT "  value = 42"
PRINT "  Sign: "; IIF(value >= 0, "positive", "negative")

value = -17
PRINT "  value = -17"
PRINT "  Sign: "; IIF(value >= 0, "positive", "negative")

PRINT "  PASS: IIF used directly in PRINT"
PRINT ""

' =============================================================================
' Test 8: IIF with boolean-like values
' =============================================================================
PRINT "Test 8: IIF with Boolean Values"
DIM flag, message$

flag = 1
message$ = IIF(flag, "Enabled", "Disabled")
PRINT "  flag = 1, IIF(flag, 'Enabled', 'Disabled') = '"; message$; "'"
IF message$ = "Enabled" THEN
    PRINT "  PASS: Non-zero is true"
ELSE
    PRINT "  FAIL: Expected 'Enabled', got '"; message$; "'"
END IF

flag = 0
message$ = IIF(flag, "Enabled", "Disabled")
PRINT "  flag = 0, IIF(flag, 'Enabled', 'Disabled') = '"; message$; "'"
IF message$ = "Disabled" THEN
    PRINT "  PASS: Zero is false"
ELSE
    PRINT "  FAIL: Expected 'Disabled', got '"; message$; "'"
END IF

PRINT ""

' =============================================================================
' Test 9: IIF with function calls
' =============================================================================
PRINT "Test 9: IIF with Function Calls"
DIM text$, upper_or_lower$

text$ = "Hello"
upper_or_lower$ = IIF(LEN(text$) > 3, UCASE$(text$), LCASE$(text$))
PRINT "  text$ = 'Hello' (length > 3)"
PRINT "  IIF(LEN(text$) > 3, UCASE$(text$), LCASE$(text$)) = '"; upper_or_lower$; "'"
IF upper_or_lower$ = "HELLO" THEN
    PRINT "  PASS: Uppercase when length > 3"
ELSE
    PRINT "  FAIL: Expected 'HELLO', got '"; upper_or_lower$; "'"
END IF

text$ = "Hi"
upper_or_lower$ = IIF(LEN(text$) > 3, UCASE$(text$), LCASE$(text$))
PRINT "  text$ = 'Hi' (length <= 3)"
PRINT "  IIF(LEN(text$) > 3, UCASE$(text$), LCASE$(text$)) = '"; upper_or_lower$; "'"
IF upper_or_lower$ = "hi" THEN
    PRINT "  PASS: Lowercase when length <= 3"
ELSE
    PRINT "  FAIL: Expected 'hi', got '"; upper_or_lower$; "'"
END IF

PRINT ""

' =============================================================================
' Test 10: IIF with AND/OR conditions
' =============================================================================
PRINT "Test 10: IIF with AND/OR"
DIM temp, weather$

temp = 75
weather$ = IIF(temp > 70 AND temp < 85, "Pleasant", "Extreme")
PRINT "  temp = 75, IIF(temp > 70 AND temp < 85, 'Pleasant', 'Extreme') = '"; weather$; "'"
IF weather$ = "Pleasant" THEN
    PRINT "  PASS: AND condition"
ELSE
    PRINT "  FAIL: Expected 'Pleasant', got '"; weather$; "'"
END IF

temp = 95
weather$ = IIF(temp > 70 AND temp < 85, "Pleasant", "Extreme")
PRINT "  temp = 95, IIF(temp > 70 AND temp < 85, 'Pleasant', 'Extreme') = '"; weather$; "'"
IF weather$ = "Extreme" THEN
    PRINT "  PASS: AND condition false"
ELSE
    PRINT "  FAIL: Expected 'Extreme', got '"; weather$; "'"
END IF

PRINT ""

' =============================================================================
' Summary
' =============================================================================
PRINT "=== IIF Function Test Complete ==="
PRINT "IIF provides inline conditional expressions like:"
PRINT "  result = IIF(condition, trueValue, falseValue)"
PRINT ""
PRINT "Benefits:"
PRINT "  - More concise than IF/THEN/ELSE for simple cases"
PRINT "  - Can be used in expressions"
PRINT "  - Can be nested for multi-way decisions"
PRINT ""
PRINT "DONE"
