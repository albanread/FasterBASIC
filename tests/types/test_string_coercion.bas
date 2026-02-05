' test_string_coercion.bas
' Test string type coercion when mixing ASCII and UNICODE strings
' OPTION DETECTSTRING is the default, so ASCII literals stay ASCII
' and UNICODE literals (with non-ASCII characters) are UTF-32
' When concatenating, the runtime should promote ASCII to UNICODE automatically

OPTION DETECTSTRING

' Test 1: ASCII + ASCII should remain ASCII
DIM a$, b$, result1$
a$ = "Hello"
b$ = " World"
result1$ = a$ + b$
PRINT "ASCII+ASCII: "; result1$

' Test 2: ASCII + UNICODE should promote to UNICODE
DIM ascii$, unicode$, result2$
ascii$ = "Hello"
unicode$ = "世界"
result2$ = ascii$ + unicode$
PRINT "ASCII+UNICODE: "; result2$

' Test 3: UNICODE + ASCII should promote to UNICODE
DIM result3$
result3$ = unicode$ + ascii$
PRINT "UNICODE+ASCII: "; result3$

' Test 4: UNICODE + UNICODE should remain UNICODE
DIM unicode2$, result4$
unicode2$ = "こんにちは"
result4$ = unicode$ + unicode2$
PRINT "UNICODE+UNICODE: "; result4$

' Test 5: Multiple concatenations with mixed types
DIM result5$
result5$ = "Start " + "middle " + "文字 " + "end"
PRINT "Mixed literals: "; result5$

' Test 6: Comparison between ASCII and UNICODE
DIM cmp_ascii$, cmp_unicode$
cmp_ascii$ = "test"
cmp_unicode$ = "test"
IF cmp_ascii$ = cmp_unicode$ THEN
    PRINT "ASCII==UNICODE comparison works"
ELSE
    PRINT "ERROR: ASCII==UNICODE comparison failed"
END IF

' Test 7: DETECTSTRING mode - ASCII literal
DIM auto_ascii$
auto_ascii$ = "plain ascii text 123"
PRINT "Auto ASCII: "; auto_ascii$

' Test 8: DETECTSTRING mode - UNICODE literal (has non-ASCII)
DIM auto_unicode$
auto_unicode$ = "Unicode: café"
PRINT "Auto UNICODE: "; auto_unicode$

' Test 9: Complex expression with mixed types
DIM part1$, part2$, part3$, complex$
part1$ = "Hello"
part2$ = " 世界 "
part3$ = "World"
complex$ = part1$ + part2$ + part3$
PRINT "Complex: "; complex$

PRINT "All string coercion tests completed!"
