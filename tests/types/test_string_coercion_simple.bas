' test_string_coercion_simple.bas
' Simple test for string type coercion with ASCII and UNICODE
' Tests that mixing ASCII and UNICODE promotes to UNICODE
' OPTION DETECTSTRING is the default mode

OPTION DETECTSTRING

' ASCII string literal (all chars < 128)
DIM ascii_str$
ascii_str$ = "Hello "

' Unicode string literal (contains non-ASCII)
DIM unicode_str$
unicode_str$ = "世界"

' Test ASCII + UNICODE concatenation
' The runtime should automatically promote ASCII to UTF-32
DIM result$
result$ = ascii_str$ + unicode_str$
PRINT result$

' Test reverse: UNICODE + ASCII
DIM result2$
result2$ = unicode_str$ + ascii_str$
PRINT result2$

' Test pure ASCII stays ASCII (no promotion needed)
DIM pure_ascii$
pure_ascii$ = "Hello" + " " + "World"
PRINT pure_ascii$

PRINT "DONE"
