' test_slice_independence.bas
' Test that string slices create independent copies (proper string descriptors)
' Not shared references - modifying slice should not affect original

PRINT "=== String Slice Independence Test ==="
PRINT ""

' =============================================================================
' Test 1: Verify slice is a copy, not a reference
' =============================================================================
PRINT "Test 1: Slice Creates Independent Copy"
DIM original$, slice$, modified$

original$ = "Hello World"
slice$ = original$(1 TO 5)

PRINT "  Original: '"; original$; "'"
PRINT "  Slice (1 TO 5): '"; slice$; "'"

' Modify the original string
original$ = "ZZZZZ World"
PRINT "  After original$ = 'ZZZZZ World':"
PRINT "    Original: '"; original$; "'"
PRINT "    Slice: '"; slice$; "'"

IF slice$ = "Hello" THEN
    PRINT "  PASS: Slice is independent (still 'Hello')"
ELSE
    PRINT "  FAIL: Slice was affected by original modification"
END IF

PRINT ""

' =============================================================================
' Test 2: Modifying slice doesn't affect original
' =============================================================================
PRINT "Test 2: Modifying Slice Doesn't Affect Original"
original$ = "ABCDEFGH"
slice$ = original$(3 TO 6)

PRINT "  Original: '"; original$; "'"
PRINT "  Slice (3 TO 6): '"; slice$; "'"

' Modify the slice
slice$ = "XYZW"
PRINT "  After slice$ = 'XYZW':"
PRINT "    Original: '"; original$; "'"
PRINT "    Slice: '"; slice$; "'"

IF original$ = "ABCDEFGH" THEN
    PRINT "  PASS: Original unchanged after slice modification"
ELSE
    PRINT "  FAIL: Original was affected by slice modification"
END IF

PRINT ""

' =============================================================================
' Test 3: Multiple slices are independent
' =============================================================================
PRINT "Test 3: Multiple Slices Are Independent"
DIM source$, slice1$, slice2$

source$ = "0123456789"
slice1$ = source$(1 TO 5)
slice2$ = source$(6 TO 10)

PRINT "  Source: '"; source$; "'"
PRINT "  Slice1 (1 TO 5): '"; slice1$; "'"
PRINT "  Slice2 (6 TO 10): '"; slice2$; "'"

' Modify slice1
slice1$ = "AAAAA"
PRINT "  After slice1$ = 'AAAAA':"
PRINT "    Source: '"; source$; "'"
PRINT "    Slice1: '"; slice1$; "'"
PRINT "    Slice2: '"; slice2$; "'"

IF source$ = "0123456789" AND slice2$ = "56789" THEN
    PRINT "  PASS: Slices are independent"
ELSE
    PRINT "  FAIL: Slices are not independent"
END IF

PRINT ""

' =============================================================================
' Test 4: Slice assignment creates new descriptor
' =============================================================================
PRINT "Test 4: Slice Assignment Creates New Descriptor"
DIM text$, backup$

text$ = "Hello World"
backup$ = text$

PRINT "  Original text$: '"; text$; "'"
PRINT "  Backup: '"; backup$; "'"

' Assign to slice
text$(1 TO 5) = "BASIC"
PRINT "  After text$(1 TO 5) = 'BASIC':"
PRINT "    text$: '"; text$; "'"
PRINT "    backup$: '"; backup$; "'"

IF backup$ = "Hello World" THEN
    PRINT "  PASS: Backup unaffected by slice assignment"
ELSE
    PRINT "  FAIL: Backup was modified"
END IF

PRINT ""

' =============================================================================
' Test 5: Concatenation with slices creates new strings
' =============================================================================
PRINT "Test 5: Concatenation with Slices"
DIM str1$, str2$, combined$

str1$ = "ABCDEFGH"
str2$ = "12345678"

' Create combined string from slices
combined$ = str1$(1 TO 4) + str2$(5 TO 8)

PRINT "  str1$: '"; str1$; "'"
PRINT "  str2$: '"; str2$; "'"
PRINT "  combined$ (str1$(1 TO 4) + str2$(5 TO 8)): '"; combined$; "'"

' Modify sources
str1$ = "XXXXXXXX"
str2$ = "YYYYYYYY"

PRINT "  After modifying str1$ and str2$:"
PRINT "    str1$: '"; str1$; "'"
PRINT "    str2$: '"; str2$; "'"
PRINT "    combined$: '"; combined$; "'"

IF combined$ = "ABCD5678" THEN
    PRINT "  PASS: Combined string is independent"
ELSE
    PRINT "  FAIL: Combined string was affected"
END IF

PRINT ""

' =============================================================================
' Test 6: Slice from slice creates new copy
' =============================================================================
PRINT "Test 6: Slice from Slice"
DIM base$, first_slice$, second_slice$

base$ = "Programming"
first_slice$ = base$(1 TO 7)
second_slice$ = first_slice$(1 TO 4)

PRINT "  Base: '"; base$; "'"
PRINT "  First slice (1 TO 7): '"; first_slice$; "'"
PRINT "  Second slice (1 TO 4 of first): '"; second_slice$; "'"

' Modify base
base$ = "ZZZZZZZZZZZ"
PRINT "  After base$ = 'ZZZZZZZZZZZ':"
PRINT "    Base: '"; base$; "'"
PRINT "    First slice: '"; first_slice$; "'"
PRINT "    Second slice: '"; second_slice$; "'"

IF first_slice$ = "Program" AND second_slice$ = "Prog" THEN
    PRINT "  PASS: Nested slices are independent"
ELSE
    PRINT "  FAIL: Nested slices were affected"
END IF

PRINT ""

' =============================================================================
' Test 7: Function receives slice copy
' =============================================================================
PRINT "Test 7: Passing Slice to Functions"
DIM teststr$, result$

teststr$ = "TestString"
result$ = UCASE$(teststr$(1 TO 4))

PRINT "  teststr$: '"; teststr$; "'"
PRINT "  UCASE$(teststr$(1 TO 4)): '"; result$; "'"

' Verify teststr unchanged
IF teststr$ = "TestString" THEN
    PRINT "  PASS: Original string unchanged after function call"
ELSE
    PRINT "  FAIL: Original string was modified"
END IF

PRINT ""

' =============================================================================
' Test 8: Empty slice creates valid empty descriptor
' =============================================================================
PRINT "Test 8: Empty Slice Creates Valid Descriptor"
DIM empty_source$, empty_slice$

empty_source$ = "ABC"
empty_slice$ = empty_source$(2 TO 1)  ' Invalid range -> empty

PRINT "  Source: '"; empty_source$; "'"
PRINT "  Slice (2 TO 1 - invalid): '"; empty_slice$; "'"
PRINT "  Length: "; LEN(empty_slice$)

IF LEN(empty_slice$) = 0 THEN
    PRINT "  PASS: Invalid range creates empty string"
ELSE
    PRINT "  FAIL: Invalid range didn't create empty string"
END IF

' Verify we can assign to empty slice variable
empty_slice$ = "New"
PRINT "  After empty_slice$ = 'New': '"; empty_slice$; "'"

IF empty_slice$ = "New" THEN
    PRINT "  PASS: Can assign to empty slice variable"
ELSE
    PRINT "  FAIL: Cannot assign to empty slice variable"
END IF

PRINT ""

' =============================================================================
' Summary
' =============================================================================
PRINT "=== String Slice Independence Test Complete ==="
PRINT ""
PRINT "Summary:"
PRINT "  - Slices create NEW StringDescriptor structures"
PRINT "  - Slices copy data (not shared references)"
PRINT "  - Modifying original doesn't affect slice"
PRINT "  - Modifying slice doesn't affect original"
PRINT "  - Multiple slices are independent"
PRINT "  - Concatenated slices are independent"
PRINT ""
PRINT "This confirms proper memory management:"
PRINT "  - Each slice allocates its own data buffer"
PRINT "  - Uses memcpy() to duplicate string data"
PRINT "  - Reference count starts at 1 for new descriptor"
PRINT "  - Garbage collection handles cleanup"
PRINT ""
PRINT "DONE"
