' test_string_funcs_simple.bas
' Simple test to identify which string functions work correctly
' Tests one function at a time to isolate issues

OPTION DETECTSTRING

PRINT "Testing string functions one by one..."
PRINT ""

' Test 1: LEN
PRINT "Test 1: LEN"
DIM test1$
test1$ = "Hello"
PRINT "LEN('Hello') = "; LEN(test1$)
PRINT ""

' Test 2: MID$
PRINT "Test 2: MID$"
DIM test2$
test2$ = MID$("Hello World", 7, 5)
PRINT "MID$('Hello World', 7, 5) = "; test2$
PRINT ""

' Test 3: LEFT$
PRINT "Test 3: LEFT$"
DIM test3$
test3$ = LEFT$("Testing", 4)
PRINT "LEFT$('Testing', 4) = "; test3$
PRINT ""

' Test 4: RIGHT$
PRINT "Test 4: RIGHT$"
DIM test4$
test4$ = RIGHT$("Testing", 3)
PRINT "RIGHT$('Testing', 3) = "; test4$
PRINT ""

' Test 5: CHR$
PRINT "Test 5: CHR$"
DIM test5$
test5$ = CHR$(65)
PRINT "CHR$(65) = "; test5$
PRINT ""

' Test 6: UNICODE string with LEN
PRINT "Test 6: UNICODE LEN"
DIM test6$
test6$ = "世界"
PRINT "LEN('世界') = "; LEN(test6$)
PRINT ""

' Test 7: UNICODE MID$
PRINT "Test 7: UNICODE MID$"
DIM test7$
test7$ = MID$("こんにちは", 2, 2)
PRINT "MID$('こんにちは', 2, 2) = "; test7$
PRINT ""

PRINT "Basic test complete"
PRINT "DONE"
