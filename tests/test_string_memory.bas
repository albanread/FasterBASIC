' Test string assignment memory management
' Focus on reference counting and preventing leaks

PRINT "=== String Memory Management Test ==="
PRINT

' Test 1: Simple assignment
PRINT "Test 1: Simple assignment"
a$ = "hello"
PRINT a$

' Test 2: Reassignment (should release old value)
PRINT "Test 2: Reassignment"
a$ = "world"
PRINT a$

' Test 3: Multiple reassignments in loop
PRINT "Test 3: Loop with 100 reassignments"
FOR i = 1 TO 100
    temp$ = "iteration"
    temp$ = "value"
NEXT i
PRINT "Completed without crash"

' Test 4: String concatenation
PRINT "Test 4: Concatenation"
s1$ = "Hello"
s2$ = "World"
s3$ = s1$ + " " + s2$
PRINT s3$

' Test 5: Variable to variable assignment
PRINT "Test 5: Variable to variable"
orig$ = "original"
copy$ = orig$
PRINT "orig$ = "; orig$
PRINT "copy$ = "; copy$

' Test 6: Empty strings
PRINT "Test 6: Empty strings"
empty$ = ""
PRINT "LEN(empty$) = "; LEN(empty$)
empty$ = "not empty"
PRINT empty$
empty$ = ""
PRINT "LEN(empty$) = "; LEN(empty$)

' Test 7: String functions
PRINT "Test 7: String functions"
text$ = "Hello World"
upper$ = UCASE$(text$)
lower$ = LCASE$(text$)
PRINT "Original: "; text$
PRINT "Upper:    "; upper$
PRINT "Lower:    "; lower$

PRINT
PRINT "=== All tests passed ==="
END
