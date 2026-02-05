' Test string assignment with proper memory management
' This tests the reference counting and copy-on-write fixes

PRINT "=== String Assignment Memory Management Tests ==="
PRINT

' Test 1: Simple assignment
PRINT "Test 1: Simple string assignment"
a$ = "hello"
PRINT "a$ = "; a$
b$ = "world"
PRINT "b$ = "; b$
PRINT

' Test 2: Assignment chain (should not leak memory)
PRINT "Test 2: Multiple assignments to same variable"
x$ = "first"
PRINT "x$ = "; x$
x$ = "second"
PRINT "x$ = "; x$
x$ = "third"
PRINT "x$ = "; x$
PRINT

' Test 3: Assignment from variable to variable
PRINT "Test 3: Variable to variable assignment"
s1$ = "original"
s2$ = s1$
PRINT "s1$ = "; s1$
PRINT "s2$ = "; s2$
PRINT

' Test 4: Concatenation and assignment
PRINT "Test 4: Concatenation with assignment"
name$ = "Alice"
greeting$ = "Hello, " + name$ + "!"
PRINT greeting$
PRINT

' Test 5: Loop with reassignment (stress test for memory leaks)
PRINT "Test 5: Loop with reassignments (1000 iterations)"
FOR i = 1 TO 1000
    temp$ = "iteration"
    ' Reassign in loop - should not leak
    temp$ = "value"
NEXT i
PRINT "Completed 1000 iterations without crash"
PRINT

' Test 6: Empty string assignment
PRINT "Test 6: Empty string handling"
empty$ = ""
PRINT "empty$ length = "; LEN(empty$)
empty$ = "not empty"
PRINT "empty$ = "; empty$
empty$ = ""
PRINT "empty$ length after re-assignment = "; LEN(empty$)
PRINT

' Test 7: String functions with assignment
PRINT "Test 7: String functions with assignment"
text$ = "Hello World"
upper$ = UCASE$(text$)
lower$ = LCASE$(text$)
PRINT "Original: "; text$
PRINT "Upper:    "; upper$
PRINT "Lower:    "; lower$
PRINT

' Test 8: MID$, LEFT$, RIGHT$ with assignment
PRINT "Test 8: Substring functions"
phrase$ = "The quick brown fox"
part1$ = LEFT$(phrase$, 9)
part2$ = MID$(phrase$, 11, 5)
part3$ = RIGHT$(phrase$, 3)
PRINT "Full:  "; phrase$
PRINT "Left:  "; part1$
PRINT "Mid:   "; part2$
PRINT "Right: "; part3$
PRINT

' Test 9: STR$ conversion with assignment
PRINT "Test 9: STR$ with assignment"
num = 42
numstr$ = STR$(num)
PRINT "Number: "; num
PRINT "String: "; numstr$
PRINT

' Test 10: Multiple string variables
PRINT "Test 10: Multiple string variables"
DIM arr$(5)
FOR i = 1 TO 5
    arr$(i) = "String " + STR$(i)
NEXT i
FOR i = 1 TO 5
    PRINT "arr$("; i; ") = "; arr$(i)
NEXT i
PRINT

PRINT "=== All tests completed successfully ==="
END
