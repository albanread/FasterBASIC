' test_string_slices.bas
' Comprehensive test for string slice operations
' Tests both slice extraction (copy) and slice assignment
' Syntax: S$(start TO end) for extraction, S$(start TO end) = value for assignment
' Works with both ASCII and Unicode strings

PRINT "=== String Slice Operations Test ==="
PRINT ""

' =============================================================================
' Test 1: Basic slice extraction - S$(start TO end)
' =============================================================================
PRINT "Test 1: Basic Slice Extraction"
DIM text$, slice$
text$ = "Hello World"

' Extract "Hello"
slice$ = text$(1 TO 5)
PRINT "  text$(1 TO 5) = '"; slice$; "' (expected 'Hello')"
IF slice$ = "Hello" THEN
    PRINT "  PASS: Extract first 5 chars"
ELSE
    PRINT "  FAIL: Expected 'Hello', got '"; slice$; "'"
END IF

' Extract "World"
slice$ = text$(7 TO 11)
PRINT "  text$(7 TO 11) = '"; slice$; "' (expected 'World')"
IF slice$ = "World" THEN
    PRINT "  PASS: Extract last 5 chars"
ELSE
    PRINT "  FAIL: Expected 'World', got '"; slice$; "'"
END IF

' Extract middle portion "o Wo"
slice$ = text$(5 TO 8)
PRINT "  text$(5 TO 8) = '"; slice$; "' (expected 'o Wo')"
IF slice$ = "o Wo" THEN
    PRINT "  PASS: Extract middle chars"
ELSE
    PRINT "  FAIL: Expected 'o Wo', got '"; slice$; "'"
END IF

' Single character slice
slice$ = text$(1 TO 1)
PRINT "  text$(1 TO 1) = '"; slice$; "' (expected 'H')"
IF slice$ = "H" THEN
    PRINT "  PASS: Extract single char"
ELSE
    PRINT "  FAIL: Expected 'H', got '"; slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 2: Slice with implied start (TO end) - from beginning
' =============================================================================
PRINT "Test 2: Slice from Beginning (TO end)"
text$ = "Testing"

slice$ = text$(TO 4)
PRINT "  text$(TO 4) = '"; slice$; "' (expected 'Test')"
IF slice$ = "Test" THEN
    PRINT "  PASS: Slice from beginning to position 4"
ELSE
    PRINT "  FAIL: Expected 'Test', got '"; slice$; "'"
END IF

slice$ = text$(TO 1)
PRINT "  text$(TO 1) = '"; slice$; "' (expected 'T')"
IF slice$ = "T" THEN
    PRINT "  PASS: Slice from beginning to first char"
ELSE
    PRINT "  FAIL: Expected 'T', got '"; slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 3: Slice with implied end (start TO) - to end of string
' =============================================================================
PRINT "Test 3: Slice to End (start TO)"
text$ = "Programming"

slice$ = text$(8 TO)
PRINT "  text$(8 TO) = '"; slice$; "' (expected 'ming')"
IF slice$ = "ming" THEN
    PRINT "  PASS: Slice from position 8 to end"
ELSE
    PRINT "  FAIL: Expected 'ming', got '"; slice$; "'"
END IF

slice$ = text$(1 TO)
PRINT "  text$(1 TO) = '"; slice$; "' (expected 'Programming')"
IF slice$ = "Programming" THEN
    PRINT "  PASS: Slice from beginning to end (full string)"
ELSE
    PRINT "  FAIL: Expected 'Programming', got '"; slice$; "'"
END IF

slice$ = text$(11 TO)
PRINT "  text$(11 TO) = '"; slice$; "' (expected 'g')"
IF slice$ = "g" THEN
    PRINT "  PASS: Slice last char to end"
ELSE
    PRINT "  FAIL: Expected 'g', got '"; slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 4: Slice assignment - S$(start TO end) = value
' =============================================================================
PRINT "Test 4: Basic Slice Assignment"
text$ = "Hello World"

' Replace "Hello" with "BASIC"
text$(1 TO 5) = "BASIC"
PRINT "  After text$(1 TO 5) = 'BASIC': '"; text$; "'"
IF text$(1 TO 5) = "BASIC" THEN
    PRINT "  PASS: Replace first 5 chars"
ELSE
    PRINT "  FAIL: Expected first 5 chars to be 'BASIC'"
END IF

' Replace "World" with "CODE"
text$ = "Hello World"
text$(7 TO 11) = "CODE"
PRINT "  After text$(7 TO 11) = 'CODE': '"; text$; "'"
' Check if "CODE" is in the string
IF text$(7 TO 10) = "CODE" THEN
    PRINT "  PASS: Replace last word"
ELSE
    PRINT "  FAIL: Slice assignment didn't work correctly"
END IF

PRINT ""

' =============================================================================
' Test 5: Slice assignment with different lengths
' =============================================================================
PRINT "Test 5: Slice Assignment with Different Lengths"
text$ = "1234567890"

' Replace 5 chars with 3 chars (shorter)
text$(3 TO 7) = "ABC"
PRINT "  After text$(3 TO 7) = 'ABC': '"; text$; "'"
PRINT "  New length: "; LEN(text$)
IF text$(3 TO 5) = "ABC" THEN
    PRINT "  PASS: Replace with shorter string"
ELSE
    PRINT "  FAIL: Shorter replacement didn't work"
END IF

' Replace 3 chars with 5 chars (longer)
text$ = "1234567890"
text$(3 TO 5) = "ABCDE"
PRINT "  After text$(3 TO 5) = 'ABCDE': '"; text$; "'"
PRINT "  New length: "; LEN(text$)
IF text$(3 TO 7) = "ABCDE" THEN
    PRINT "  PASS: Replace with longer string"
ELSE
    PRINT "  FAIL: Longer replacement didn't work"
END IF

PRINT ""

' =============================================================================
' Test 6: Slice Assignment at Edges
' =============================================================================
PRINT "Test 6: Slice Assignment at Edges"
text$ = "ABCDEFGH"

' Replace at beginning (using explicit start index)
text$(1 TO 3) = "123"
PRINT "  After text$(1 TO 3) = '123': '"; text$; "'"
IF text$(1 TO 3) = "123" THEN
    PRINT "  PASS: Replace at beginning"
ELSE
    PRINT "  FAIL: Beginning replacement didn't work"
END IF

' Replace at end (using explicit end index)
text$ = "ABCDEFGH"
text$(6 TO 8) = "XYZ"
PRINT "  After text$(6 TO 8) = 'XYZ': '"; text$; "'"
' Check if XYZ appears at the end
IF text$(6 TO 8) = "XYZ" THEN
    PRINT "  PASS: Replace at end"
ELSE
    PRINT "  FAIL: End replacement didn't work"
END IF

PRINT ""

' =============================================================================
' Test 7: Edge cases
' =============================================================================
PRINT "Test 7: Edge Cases"

' Single character slice (start = end)
text$ = "Testing"
slice$ = text$(3 TO 3)
PRINT "  text$(3 TO 3) = '"; slice$; "' (single char)"
IF LEN(slice$) = 1 THEN
    PRINT "  PASS: Single character slice"
ELSE
    PRINT "  FAIL: Expected length 1"
END IF

' Slice beyond string length (should clamp)
text$ = "Short"
slice$ = text$(3 TO 100)
PRINT "  text$(3 TO 100) = '"; slice$; "' (should be 'ort')"
IF slice$ = "ort" THEN
    PRINT "  PASS: Slice clamped to string length"
ELSE
    PRINT "  FAIL: Expected 'ort', got '"; slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 8: Slices with variable indices
' =============================================================================
PRINT "Test 8: Slice with Variable Indices"
DIM start_pos, end_pos
text$ = "0123456789"
start_pos = 3
end_pos = 7

slice$ = text$(start_pos TO end_pos)
PRINT "  text$ = '0123456789'"
PRINT "  start_pos = 3, end_pos = 7"
PRINT "  text$(start_pos TO end_pos) = '"; slice$; "'"
IF slice$ = "23456" THEN
    PRINT "  PASS: Variable indices"
ELSE
    PRINT "  FAIL: Variable indices didn't work"
END IF

text$(start_pos TO end_pos) = "XXXXX"
PRINT "  After text$(start_pos TO end_pos) = 'XXXXX': '"; text$; "'"
IF text$ = "01XXXXX789" THEN
    PRINT "  PASS: Assign with variables"
ELSE
    PRINT "  FAIL: Assign with variables didn't work"
END IF

PRINT ""

' =============================================================================
' Test 9: Slice with expressions
' =============================================================================
PRINT "Test 9: Slice with Expressions"
DIM pos
text$ = "ABCDEFGHIJ"
pos = 5

slice$ = text$(pos - 2 TO pos + 2)
PRINT "  text$ = 'ABCDEFGHIJ', pos = 5"
PRINT "  text$(pos - 2 TO pos + 2) = '"; slice$; "'"
IF slice$ = "CDEFG" THEN
    PRINT "  PASS: Expression indices"
ELSE
    PRINT "  FAIL: Expected 'CDEFG', got '"; slice$; "'"
END IF

slice$ = text$(2 * 2 TO 3 * 3)
PRINT "  text$(2 * 2 TO 3 * 3) = '"; slice$; "'"
IF slice$ = "DEFGHI" THEN
    PRINT "  PASS: Math expression indices"
ELSE
    PRINT "  FAIL: Expected 'DEFGHI', got '"; slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 10: Concatenation with slices
' =============================================================================
PRINT "Test 10: Concatenating Slices"
DIM result$
text$ = "Hello World"

result$ = text$(1 TO 5) + " " + text$(7 TO 11)
PRINT "  text$(1 TO 5) + ' ' + text$(7 TO 11) = '"; result$; "'"
IF result$ = "Hello World" THEN
    PRINT "  PASS: Concatenate two slices"
ELSE
    PRINT "  FAIL: Expected 'Hello World', got '"; result$; "'"
END IF

result$ = text$(7 TO 11) + text$(1 TO 5)
PRINT "  text$(7 TO 11) + text$(1 TO 5) = '"; result$; "'"
IF result$ = "WorldHello" THEN
    PRINT "  PASS: Concatenate reversed slices"
ELSE
    PRINT "  FAIL: Expected 'WorldHello', got '"; result$; "'"
END IF

PRINT ""

' =============================================================================
' Test 11: Using slices with string functions
' =============================================================================
PRINT "Test 11: Slices with String Functions"
text$ = "  Hello World  "

' Combine with slice to extract middle without padding
DIM trimmed$
trimmed$ = text$(3 TO 13)
PRINT "  Slice of padded string: '"; trimmed$; "'"
IF trimmed$ = "Hello World" THEN
    PRINT "  PASS: Slice extracts middle without padding"
ELSE
    PRINT "  FAIL: Expected 'Hello World'"
END IF

' Uppercase a slice
text$ = "Hello World"
DIM upper_slice$
upper_slice$ = UCASE$(text$(1 TO 5))
PRINT "  UCASE$(text$(1 TO 5)) = '"; upper_slice$; "'"
IF upper_slice$ = "HELLO" THEN
    PRINT "  PASS: UCASE$ on slice"
ELSE
    PRINT "  FAIL: Expected 'HELLO', got '"; upper_slice$; "'"
END IF

' Lowercase a slice
DIM lower_slice$
lower_slice$ = LCASE$(text$(7 TO 11))
PRINT "  LCASE$(text$(7 TO 11)) = '"; lower_slice$; "'"
IF lower_slice$ = "world" THEN
    PRINT "  PASS: LCASE$ on slice"
ELSE
    PRINT "  FAIL: Expected 'world', got '"; lower_slice$; "'"
END IF

PRINT ""

' =============================================================================
' Test 12: Multiple string variables and slicing
' =============================================================================
PRINT "Test 12: Multiple String Variables and Slicing"
DIM str1$, str2$, str3$

str1$ = "AAAAA"
str2$ = "BBBBB"
str3$ = "CCCCC"

' Extract and combine slices from different strings
result$ = str1$(1 TO 2) + str2$(2 TO 4) + str3$(4 TO 5)
PRINT "  str1$(1 TO 2) + str2$(2 TO 4) + str3$(4 TO 5) = '"; result$; "'"
IF result$ = "AABBBCC" THEN
    PRINT "  PASS: Combine slices from multiple strings"
ELSE
    PRINT "  FAIL: Expected 'AABBBCC', got '"; result$; "'"
END IF

PRINT ""

' =============================================================================
' Test 13: Slice comparison
' =============================================================================
PRINT "Test 13: Comparing Slices"
text$ = "Hello World"

IF text$(1 TO 5) = "Hello" THEN
    PRINT "  text$(1 TO 5) = 'Hello' comparison: TRUE"
    PRINT "  PASS: Slice comparison"
ELSE
    PRINT "  FAIL: Slice comparison failed"
END IF

IF text$(1 TO 5) <> text$(7 TO 11) THEN
    PRINT "  text$(1 TO 5) <> text$(7 TO 11): TRUE"
    PRINT "  PASS: Inequality comparison"
ELSE
    PRINT "  FAIL: Inequality comparison failed"
END IF

PRINT ""

' =============================================================================
' Test 14: Empty String Replacement
' =============================================================================
PRINT "Test 14: Empty String Replacement"
text$ = "ABCDEFGH"

text$(3 TO 5) = ""
PRINT "  Original: 'ABCDEFGH'"
PRINT "  After text$(3 TO 5) = '': '"; text$; "'"
IF text$ = "ABFGH" THEN
    PRINT "  PASS: Empty replacement deletes"
ELSE
    PRINT "  FAIL: Empty replacement deletes"
END IF

text$ = "Testing"
text$(1 TO 4) = ""
PRINT "  After text$(1 TO 4) = '': '"; text$; "'"
IF text$ = "ing" THEN
    PRINT "  PASS: Empty replacement at start"
ELSE
    PRINT "  FAIL: Empty replacement at start"
END IF

PRINT ""

' =============================================================================
' Test 15: Multiple assignments
' =============================================================================
PRINT "Test 15: Multiple Slice Assignments"
text$ = "AAABBBCCCDDD"

text$(1 TO 3) = "111"
text$(4 TO 6) = "222"
text$(7 TO 9) = "333"
PRINT "  Original: 'AAABBBCCCDDD'"
PRINT "  After multiple assigns: '"; text$; "'"
IF text$ = "111222333DDD" THEN
    PRINT "  PASS: Multiple assigns"
ELSE
    PRINT "  FAIL: Multiple assigns"
END IF

PRINT ""

' =============================================================================
' Summary
' =============================================================================
PRINT "=== String Slice Operations Test Complete ==="
PRINT "Tested:"
PRINT "  - Basic slice extraction (S$(start TO end))"
PRINT "  - Slice from beginning (S$(TO end))"
PRINT "  - Slice to end (S$(start TO))"
PRINT "  - Slice assignment"
PRINT "  - Variable and expression indices"
PRINT "  - Concatenation and string functions"
PRINT "  - Edge cases and bounds checking"
PRINT "DONE"
