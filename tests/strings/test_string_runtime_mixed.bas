' test_string_runtime_functions.bas
' Comprehensive test of runtime string functions with both ASCII and UNICODE strings
' Tests: LEN, MID$, LEFT$, RIGHT$, INSTR, LCASE$, UCASE$, CHR$, ASC, LTRIM$, RTRIM$, TRIM$

OPTION DETECTSTRING

PRINT "=== String Runtime Functions Test (ASCII + UNICODE) ==="
PRINT ""

' =============================================================================
' Test 1: LEN - String length
' =============================================================================
PRINT "Test 1: LEN Function"
DIM ascii_text$, unicode_text$
ascii_text$ = "Hello"
unicode_text$ = "世界"

PRINT "  ASCII 'Hello' length: "; LEN(ascii_text$)
IF LEN(ascii_text$) = 5 THEN PRINT "  ✓ PASS: ASCII LEN" ELSE PRINT "  ✗ FAIL: ASCII LEN"

PRINT "  UNICODE '世界' length: "; LEN(unicode_text$)
IF LEN(unicode_text$) = 2 THEN PRINT "  ✓ PASS: UNICODE LEN" ELSE PRINT "  ✗ FAIL: UNICODE LEN"

DIM mixed$
mixed$ = "Hello世界"
PRINT "  Mixed 'Hello世界' length: "; LEN(mixed$)
IF LEN(mixed$) = 7 THEN PRINT "  ✓ PASS: Mixed LEN" ELSE PRINT "  ✗ FAIL: Mixed LEN"
PRINT ""

' =============================================================================
' Test 2: MID$ - Substring extraction
' =============================================================================
PRINT "Test 2: MID$ Function"
DIM ascii_mid$, unicode_mid$, mixed_mid$

ascii_mid$ = MID$("Hello World", 7, 5)
PRINT "  MID$('Hello World', 7, 5) = '"; ascii_mid$; "'"
IF ascii_mid$ = "World" THEN PRINT "  ✓ PASS: ASCII MID$" ELSE PRINT "  ✗ FAIL: ASCII MID$"

unicode_mid$ = MID$("こんにちは", 2, 2)
PRINT "  MID$('こんにちは', 2, 2) = '"; unicode_mid$; "'"
IF LEN(unicode_mid$) = 2 THEN PRINT "  ✓ PASS: UNICODE MID$ length" ELSE PRINT "  ✗ FAIL: UNICODE MID$ length"

mixed_mid$ = MID$("ABC世界XYZ", 4, 2)
PRINT "  MID$('ABC世界XYZ', 4, 2) = '"; mixed_mid$; "'"
IF LEN(mixed_mid$) = 2 THEN PRINT "  ✓ PASS: Mixed MID$ length" ELSE PRINT "  ✗ FAIL: Mixed MID$ length"
PRINT ""

' =============================================================================
' Test 3: LEFT$ - Left substring
' =============================================================================
PRINT "Test 3: LEFT$ Function"
DIM ascii_left$, unicode_left$

ascii_left$ = LEFT$("Testing", 4)
PRINT "  LEFT$('Testing', 4) = '"; ascii_left$; "'"
IF ascii_left$ = "Test" THEN PRINT "  ✓ PASS: ASCII LEFT$" ELSE PRINT "  ✗ FAIL: ASCII LEFT$"

unicode_left$ = LEFT$("日本語", 2)
PRINT "  LEFT$('日本語', 2) = '"; unicode_left$; "'"
IF LEN(unicode_left$) = 2 THEN PRINT "  ✓ PASS: UNICODE LEFT$ length" ELSE PRINT "  ✗ FAIL: UNICODE LEFT$ length"
PRINT ""

' =============================================================================
' Test 4: RIGHT$ - Right substring
' =============================================================================
PRINT "Test 4: RIGHT$ Function"
DIM ascii_right$, unicode_right$

ascii_right$ = RIGHT$("Testing", 3)
PRINT "  RIGHT$('Testing', 3) = '"; ascii_right$; "'"
IF ascii_right$ = "ing" THEN PRINT "  ✓ PASS: ASCII RIGHT$" ELSE PRINT "  ✗ FAIL: ASCII RIGHT$"

unicode_right$ = RIGHT$("日本語", 2)
PRINT "  RIGHT$('日本語', 2) = '"; unicode_right$; "'"
IF LEN(unicode_right$) = 2 THEN PRINT "  ✓ PASS: UNICODE RIGHT$ length" ELSE PRINT "  ✗ FAIL: UNICODE RIGHT$ length"
PRINT ""

' =============================================================================
' Test 5: INSTR - Find substring position
' =============================================================================
PRINT "Test 5: INSTR Function"
DIM pos1, pos2, pos3

pos1 = INSTR("Hello World", "World")
PRINT "  INSTR('Hello World', 'World') = "; pos1
IF pos1 = 7 THEN PRINT "  ✓ PASS: ASCII INSTR" ELSE PRINT "  ✗ FAIL: ASCII INSTR"

pos2 = INSTR("こんにちは", "にち")
PRINT "  INSTR('こんにちは', 'にち') = "; pos2
IF pos2 > 0 THEN PRINT "  ✓ PASS: UNICODE INSTR found" ELSE PRINT "  ✗ FAIL: UNICODE INSTR"

pos3 = INSTR("Hello World", "xyz")
PRINT "  INSTR('Hello World', 'xyz') = "; pos3
IF pos3 = 0 THEN PRINT "  ✓ PASS: ASCII INSTR not found" ELSE PRINT "  ✗ FAIL: ASCII INSTR not found"
PRINT ""

' =============================================================================
' Test 6: LCASE$ and UCASE$ - Case conversion
' =============================================================================
PRINT "Test 6: LCASE$ and UCASE$ Functions"
DIM lower$, upper$

lower$ = LCASE$("HELLO WORLD")
PRINT "  LCASE$('HELLO WORLD') = '"; lower$; "'"
IF lower$ = "hello world" THEN PRINT "  ✓ PASS: ASCII LCASE$" ELSE PRINT "  ✗ FAIL: ASCII LCASE$"

upper$ = UCASE$("hello world")
PRINT "  UCASE$('hello world') = '"; upper$; "'"
IF upper$ = "HELLO WORLD" THEN PRINT "  ✓ PASS: ASCII UCASE$" ELSE PRINT "  ✗ FAIL: ASCII UCASE$"

' Unicode case conversion (may not change non-Latin characters)
DIM unicode_lower$, unicode_upper$
unicode_lower$ = LCASE$("世界HELLO")
unicode_upper$ = UCASE$("世界hello")
PRINT "  LCASE$('世界HELLO') = '"; unicode_lower$; "'"
PRINT "  UCASE$('世界hello') = '"; unicode_upper$; "'"
PRINT "  ✓ INFO: UNICODE case conversion completed"
PRINT ""

' =============================================================================
' Test 7: CHR$ and ASC - Character/ASCII conversion
' =============================================================================
PRINT "Test 7: CHR$ and ASC Functions"
DIM ch$, code

ch$ = CHR$(65)
PRINT "  CHR$(65) = '"; ch$; "'"
IF ch$ = "A" THEN PRINT "  ✓ PASS: CHR$(65)" ELSE PRINT "  ✗ FAIL: CHR$(65)"

code = ASC("A")
PRINT "  ASC('A') = "; code
IF code = 65 THEN PRINT "  ✓ PASS: ASC('A')" ELSE PRINT "  ✗ FAIL: ASC('A')"

code = ASC("Hello")
PRINT "  ASC('Hello') = "; code; " (first char)"
IF code = 72 THEN PRINT "  ✓ PASS: ASC('Hello')" ELSE PRINT "  ✗ FAIL: ASC('Hello')"
PRINT ""

' =============================================================================
' Test 8: TRIM$, LTRIM$, RTRIM$ - Whitespace removal
' =============================================================================
PRINT "Test 8: TRIM$, LTRIM$, RTRIM$ Functions"
DIM trimmed$, ltrimmed$, rtrimmed$

trimmed$ = TRIM$("  Hello  ")
PRINT "  TRIM$('  Hello  ') = '"; trimmed$; "'"
IF trimmed$ = "Hello" THEN PRINT "  ✓ PASS: ASCII TRIM$" ELSE PRINT "  ✗ FAIL: ASCII TRIM$"

ltrimmed$ = LTRIM$("  Hello  ")
PRINT "  LTRIM$('  Hello  ') = '"; ltrimmed$; "'"
IF ltrimmed$ = "Hello  " THEN PRINT "  ✓ PASS: ASCII LTRIM$" ELSE PRINT "  ✗ FAIL: ASCII LTRIM$"

rtrimmed$ = RTRIM$("  Hello  ")
PRINT "  RTRIM$('  Hello  ') = '"; rtrimmed$; "'"
IF rtrimmed$ = "  Hello" THEN PRINT "  ✓ PASS: ASCII RTRIM$" ELSE PRINT "  ✗ FAIL: ASCII RTRIM$"

' Test with UNICODE
DIM unicode_trimmed$
unicode_trimmed$ = TRIM$("  世界  ")
PRINT "  TRIM$('  世界  ') = '"; unicode_trimmed$; "'"
IF unicode_trimmed$ = "世界" THEN PRINT "  ✓ PASS: UNICODE TRIM$" ELSE PRINT "  ✗ FAIL: UNICODE TRIM$"
PRINT ""

' =============================================================================
' Test 9: String concatenation with function results
' =============================================================================
PRINT "Test 9: Concatenation with Functions"
DIM concat1$, concat2$

concat1$ = LEFT$("Hello", 3) + RIGHT$("World", 3)
PRINT "  LEFT$('Hello', 3) + RIGHT$('World', 3) = '"; concat1$; "'"
IF concat1$ = "Helrld" THEN PRINT "  ✓ PASS: ASCII concat" ELSE PRINT "  ✗ FAIL: ASCII concat"

concat2$ = LEFT$("ABC", 2) + "世界" + RIGHT$("XYZ", 2)
PRINT "  LEFT$('ABC', 2) + '世界' + RIGHT$('XYZ', 2) = '"; concat2$; "'"
IF LEN(concat2$) = 6 THEN PRINT "  ✓ PASS: Mixed concat length" ELSE PRINT "  ✗ FAIL: Mixed concat length"
PRINT ""

' =============================================================================
' Test 10: Empty strings and edge cases
' =============================================================================
PRINT "Test 10: Edge Cases"
DIM empty$
empty$ = ""

PRINT "  LEN('') = "; LEN(empty$)
IF LEN(empty$) = 0 THEN PRINT "  ✓ PASS: Empty string length" ELSE PRINT "  ✗ FAIL: Empty string length"

DIM mid_empty$
mid_empty$ = MID$("Test", 1, 0)
PRINT "  MID$('Test', 1, 0) length = "; LEN(mid_empty$)
IF LEN(mid_empty$) = 0 THEN PRINT "  ✓ PASS: MID$ with 0 length" ELSE PRINT "  ✗ FAIL: MID$ with 0 length"

DIM left_overflow$
left_overflow$ = LEFT$("Hi", 10)
PRINT "  LEFT$('Hi', 10) = '"; left_overflow$; "'"
IF left_overflow$ = "Hi" THEN PRINT "  ✓ PASS: LEFT$ overflow" ELSE PRINT "  ✗ FAIL: LEFT$ overflow"
PRINT ""

' =============================================================================
' Summary
' =============================================================================
PRINT "=== String Runtime Functions Test Complete ==="
PRINT "All major string functions tested with ASCII and UNICODE"
PRINT "DONE"
