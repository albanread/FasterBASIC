' test_slice_cow_bug.bas
' Demonstrates the copy-on-write bug with slice assignment
'
' EXPECTED BEHAVIOR:
'   text$ = "Hello"
'   backup$ = text$
'   text$(1 TO 5) = "WORLD"
'   => text$ should be "WORLD"
'   => backup$ should STILL be "Hello" (independent copy)
'
' ACTUAL BEHAVIOR (BUG):
'   => BOTH text$ and backup$ become "WORLD" (shared descriptor mutated)

PRINT "=== Copy-On-Write Bug with Slice Assignment ==="
PRINT ""

' =============================================================================
' Test 1: Simple assignment should create independent strings
' =============================================================================
PRINT "Test 1: Regular String Assignment"
DIM a$, b$

a$ = "Original"
b$ = a$

PRINT "  After a$ = 'Original' and b$ = a$:"
PRINT "    a$ = '"; a$; "'"
PRINT "    b$ = '"; b$; "'"

' Now reassign a$ completely
a$ = "Changed"
PRINT "  After a$ = 'Changed':"
PRINT "    a$ = '"; a$; "'"
PRINT "    b$ = '"; b$; "'"

IF b$ = "Original" THEN
    PRINT "  PASS: b$ is still 'Original' (independent)"
ELSE
    PRINT "  FAIL: b$ was affected by a$ reassignment"
END IF

PRINT ""

' =============================================================================
' Test 2: Slice assignment on shared string (THE BUG)
' =============================================================================
PRINT "Test 2: Slice Assignment on Shared String"
DIM text$, backup$

text$ = "Hello World"
backup$ = text$

PRINT "  After text$ = 'Hello World' and backup$ = text$:"
PRINT "    text$ = '"; text$; "'"
PRINT "    backup$ = '"; backup$; "'"

' Now use SLICE ASSIGNMENT (not full reassignment)
text$(1 TO 5) = "BASIC"
PRINT "  After text$(1 TO 5) = 'BASIC':"
PRINT "    text$ = '"; text$; "'"
PRINT "    backup$ = '"; backup$; "'"

IF backup$ = "Hello World" THEN
    PRINT "  PASS: backup$ is still 'Hello World' (independent)"
ELSE
    PRINT "  BUG: backup$ was changed to '"; backup$; "'"
    PRINT "       This means slice assignment mutated the shared StringDescriptor!"
END IF

PRINT ""

' =============================================================================
' Test 3: Another example with different slice
' =============================================================================
PRINT "Test 3: Slice Assignment at End"
DIM orig$, copy$

orig$ = "ABCDEFGH"
copy$ = orig$

PRINT "  After orig$ = 'ABCDEFGH' and copy$ = orig$:"
PRINT "    orig$ = '"; orig$; "'"
PRINT "    copy$ = '"; copy$; "'"

orig$(6 TO 8) = "XYZ"
PRINT "  After orig$(6 TO 8) = 'XYZ':"
PRINT "    orig$ = '"; orig$; "'"
PRINT "    copy$ = '"; copy$; "'"

IF copy$ = "ABCDEFGH" THEN
    PRINT "  PASS: copy$ is still 'ABCDEFGH'"
ELSE
    PRINT "  BUG: copy$ was changed to '"; copy$; "'"
END IF

PRINT ""

' =============================================================================
' Test 4: Three variables sharing same string
' =============================================================================
PRINT "Test 4: Multiple Variables Sharing String"
DIM str1$, str2$, str3$

str1$ = "Testing"
str2$ = str1$
str3$ = str1$

PRINT "  After str1$ = 'Testing', str2$ = str1$, str3$ = str1$:"
PRINT "    str1$ = '"; str1$; "'"
PRINT "    str2$ = '"; str2$; "'"
PRINT "    str3$ = '"; str3$; "'"

str1$(1 TO 4) = "****"
PRINT "  After str1$(1 TO 4) = '****':"
PRINT "    str1$ = '"; str1$; "'"
PRINT "    str2$ = '"; str2$; "'"
PRINT "    str3$ = '"; str3$; "'"

IF str2$ = "Testing" AND str3$ = "Testing" THEN
    PRINT "  PASS: str2$ and str3$ unchanged"
ELSE
    PRINT "  BUG: str2$ = '"; str2$; "', str3$ = '"; str3$; "'"
    PRINT "       All three variables were affected by slice assignment!"
END IF

PRINT ""

' =============================================================================
' Summary
' =============================================================================
PRINT "=== Bug Summary ==="
PRINT ""
PRINT "PROBLEM: string_mid_assign() and string_slice_assign() mutate"
PRINT "         the StringDescriptor without checking refcount."
PRINT ""
PRINT "When you do:"
PRINT "  a$ = 'Hello'"
PRINT "  b$ = a$              ' Both share same StringDescriptor (refcount=2)"
PRINT "  a$(1 TO 5) = 'World' ' Mutates shared descriptor!"
PRINT ""
PRINT "RESULT: Both a$ and b$ become 'World' (WRONG!)"
PRINT ""
PRINT "EXPECTED: Only a$ should change; b$ should remain 'Hello'"
PRINT ""
PRINT "FIX NEEDED: Check refcount before mutating:"
PRINT "  if (str->refcount > 1) {"
PRINT "    // Create a new copy first"
PRINT "    StringDescriptor* new_str = string_copy(str);"
PRINT "    // Decrement old refcount"
PRINT "    str->refcount--;"
PRINT "    str = new_str;"
PRINT "  }"
PRINT "  // Now safe to mutate str"
PRINT ""
PRINT "DONE"
