' Simple test for string slice assignment
' Tests basic slice assignment functionality

DIM text$ AS STRING

PRINT "=== String Slice Assignment Test ==="
PRINT ""

' Test 1: Replace first 5 characters
text$ = "Hello World"
PRINT "Original: "; text$
text$(1 TO 5) = "BASIC"
PRINT "After text$(1 TO 5) = 'BASIC': "; text$

IF text$ = "BASIC World" THEN
    PRINT "PASS: First 5 chars replaced"
ELSE
    PRINT "FAIL: Expected 'BASIC World', got '"; text$; "'"
END IF
PRINT ""

' Test 2: Replace last word
text$ = "Hello World"
PRINT "Original: "; text$
text$(7 TO 11) = "BASIC"
PRINT "After text$(7 TO 11) = 'BASIC': "; text$

IF text$ = "Hello BASIC" THEN
    PRINT "PASS: Last word replaced"
ELSE
    PRINT "FAIL: Expected 'Hello BASIC', got '"; text$; "'"
END IF
PRINT ""

' Test 3: Replace with shorter string
text$ = "1234567890"
PRINT "Original: "; text$
text$(3 TO 7) = "ABC"
PRINT "After text$(3 TO 7) = 'ABC': "; text$

IF text$ = "12ABC890" THEN
    PRINT "PASS: Shorter replacement worked"
ELSE
    PRINT "FAIL: Expected '12ABC890', got '"; text$; "'"
END IF
PRINT ""

' Test 4: Replace with longer string
text$ = "1234567890"
PRINT "Original: "; text$
text$(3 TO 5) = "ABCDE"
PRINT "After text$(3 TO 5) = 'ABCDE': "; text$

IF text$ = "12ABCDE67890" THEN
    PRINT "PASS: Longer replacement worked"
ELSE
    PRINT "FAIL: Expected '12ABCDE67890', got '"; text$; "'"
END IF
PRINT ""

PRINT "=== Test Complete ==="
