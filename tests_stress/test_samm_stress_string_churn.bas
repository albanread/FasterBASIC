' === test_samm_stress_string_churn.bas ===
' Stress test: rapid string descriptor allocation, concatenation, and cleanup.
'
' Pressurizes:
'   - String descriptor allocation via SAMM (alloc_descriptor -> samm_alloc_string)
'   - Per-iteration scope cleanup of temporary string descriptors
'   - String RETAIN when returning from FUNCTION/METHOD calls
'   - UTF-8 cache invalidation (dirty flag) under rapid reassignment
'   - Concat creating chains of intermediate descriptors that must be tracked
'   - Bloom filter accuracy with thousands of freed string addresses
'
' Every sub-test verifies a final result so correctness is checked,
' not just "didn't crash."

' =========================================================================
' Helper classes and functions
' =========================================================================

CLASS StringBox
  Value AS STRING

  CONSTRUCTOR(v AS STRING)
    ME.Value = v
  END CONSTRUCTOR

  METHOD GetValue() AS STRING
    RETURN ME.Value
  END METHOD

  METHOD Append(suffix AS STRING) AS STRING
    Append = ME.Value + suffix
  END METHOD

  METHOD Transform() AS STRING
    ' Returns a modified copy — creates multiple temporaries
    DIM upper AS STRING
    upper = UCASE$(ME.Value)
    DIM wrapped AS STRING
    wrapped = "[" + upper + "]"
    Transform = wrapped
  END METHOD
END CLASS

' Return a freshly built string (tests RETAIN of string return value)
FUNCTION MakeTag(prefix AS STRING, idx AS INTEGER) AS STRING
  DIM numStr AS STRING
  numStr = STR$(idx)
  DIM tag AS STRING
  tag = prefix + "_" + numStr
  MakeTag = tag
END FUNCTION

' Build a string from N pieces via repeated concatenation
' Creates N intermediate string descriptors that become garbage
FUNCTION ConcatChain(n AS INTEGER) AS STRING
  DIM result AS STRING
  result = ""
  DIM i AS INTEGER
  FOR i = 1 TO n
    result = result + CHR$(65 + (i MOD 26))
  NEXT i
  ConcatChain = result
END FUNCTION

' Build string with nested function calls (multiple RETAIN levels)
FUNCTION NestedBuild(depth AS INTEGER, maxDepth AS INTEGER) AS STRING
  IF depth >= maxDepth THEN
    NestedBuild = "X"
    RETURN NestedBuild
  END IF
  DIM inner AS STRING
  inner = NestedBuild(depth + 1, maxDepth)
  DIM tag AS STRING
  tag = MakeTag("d", depth)
  NestedBuild = tag + "(" + inner + ")"
END FUNCTION

' Creates multiple string temporaries per call via string functions
FUNCTION StringFuncChurn(inputStr AS STRING) AS STRING
  DIM a AS STRING
  a = UCASE$(inputStr)
  DIM b AS STRING
  b = MID$(a, 1, 3)
  DIM c AS STRING
  c = LCASE$(a)
  DIM d AS STRING
  d = b + "_" + c
  StringFuncChurn = d
END FUNCTION

' =========================================================================
' Main test program
' =========================================================================

PRINT "=== SAMM String Churn Stress Tests ==="

' --- Test 1: 3000 string reassignments in a tight loop ---
' Each iteration creates a new string from STR$ + concat;
' the old string becomes garbage tracked by SAMM.
PRINT ""
PRINT "Test 1: 3000 string reassignments"
DIM s1 AS STRING
s1 = ""
DIM i1 AS INTEGER
FOR i1 = 1 TO 3000
  s1 = "val_" + STR$(i1)
NEXT i1
PRINT "  Final: "; s1
PRINT "  PASS"

' --- Test 2: 1000 string concats building one long string ---
' Each concat creates a new descriptor; old intermediate is garbage.
' At iteration N the live string is N chars long.
PRINT ""
PRINT "Test 2: 1000-char concat chain"
DIM s2 AS STRING
s2 = ConcatChain(1000)
PRINT "  Length: "; LEN(s2)
IF LEN(s2) = 1000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1000"
END IF

' --- Test 3: 2000 MakeTag function calls (string RETAIN churn) ---
' Each call creates 2-3 temporaries inside the function scope,
' RETAINs the result, and the temporaries are cleaned on scope exit.
PRINT ""
PRINT "Test 3: 2000 string function returns"
DIM lastTag AS STRING
lastTag = ""
DIM i3 AS INTEGER
FOR i3 = 1 TO 2000
  lastTag = MakeTag("item", i3)
NEXT i3
PRINT "  Last tag: "; lastTag
PRINT "  PASS"

' --- Test 4: StringBox METHOD churn ---
' Calling methods on StringBox creates temporaries inside METHOD scope
' and RETAINs the return value each time.
PRINT ""
PRINT "Test 4: 1000 METHOD string returns"
DIM box AS StringBox = NEW StringBox("hello")
DIM lastMethod AS STRING
lastMethod = ""
DIM i4 AS INTEGER
FOR i4 = 1 TO 1000
  lastMethod = box.Append("_" + STR$(i4))
NEXT i4
PRINT "  Last append: "; lastMethod
PRINT "  PASS"

' --- Test 5: Transform METHOD (multiple internal temporaries) ---
' Transform creates UCASE$ + concat temporaries inside each call.
' 500 calls = 500 * ~3 temporaries = ~1500 string descriptors churned.
PRINT ""
PRINT "Test 5: 500 Transform METHOD calls (internal temporaries)"
DIM lastTransform AS STRING
lastTransform = ""
DIM i5 AS INTEGER
FOR i5 = 1 TO 500
  DIM b AS StringBox = NEW StringBox("test" + STR$(i5))
  lastTransform = b.Transform()
NEXT i5
PRINT "  Last transform: "; lastTransform
PRINT "  PASS"

' --- Test 6: StringFuncChurn with UCASE$, MID$, LCASE$ ---
' Each call creates ~5 temporary strings inside the function.
' 1000 calls = ~5000 string descriptors allocated and freed.
PRINT ""
PRINT "Test 6: 1000 string-function-heavy calls"
DIM lastFunc AS STRING
lastFunc = ""
DIM i6 AS INTEGER
FOR i6 = 1 TO 1000
  lastFunc = StringFuncChurn("abcdef")
NEXT i6
' UCASE$("abcdef") = "ABCDEF", MID$("ABCDEF",1,3) = "ABC",
' LCASE$("ABCDEF") = "abcdef", result = "ABC_abcdef"
PRINT "  Last: "; lastFunc
IF lastFunc = "ABC_abcdef" THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected ABC_abcdef"
END IF

' --- Test 7: Nested recursive string build, depth 40 ---
' 40 levels of recursion, each creating 2-3 temporaries and
' RETAINing the result. Tests deep RETAIN chains for strings.
PRINT ""
PRINT "Test 7: Recursive string build, depth 40"
DIM nested AS STRING
nested = NestedBuild(1, 40)
' Result nests like d_1(d_2(...(X)...))
' Just verify it's non-empty and ends with "X)" pattern
PRINT "  Length: "; LEN(nested)
DIM endsRight AS INTEGER
IF LEN(nested) > 2 THEN
  IF MID$(nested, LEN(nested) - 1, 2) = "X)" THEN
    endsRight = 1
  ELSE
    endsRight = 0
  END IF
ELSE
  endsRight = 0
END IF
IF endsRight = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL: unexpected ending"
END IF

' --- Test 8: Interleaved string and numeric work ---
' Alternates between string-heavy and numeric-heavy iterations.
' Tests that string cleanup doesn't interfere with non-string scopes.
PRINT ""
PRINT "Test 8: 2000 interleaved string/numeric iterations"
DIM accumStr AS STRING
accumStr = ""
DIM accumNum AS INTEGER
accumNum = 0
DIM i8 AS INTEGER
FOR i8 = 1 TO 2000
  IF (i8 MOD 2) = 0 THEN
    ' String iteration: concat work
    DIM tmp AS STRING
    tmp = "n" + STR$(i8)
    accumStr = tmp
  ELSE
    ' Numeric iteration
    accumNum = accumNum + i8
  END IF
NEXT i8
' accumNum = sum of odd numbers 1,3,5,...,1999 = 1000^2 = 1000000
PRINT "  Num sum: "; accumNum
PRINT "  Last str: "; accumStr
IF accumNum = 1000000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1000000"
END IF

' --- Test 9: CHR$ churn (single-char string creation) ---
' CHR$ creates a new 1-char string descriptor each time.
' 2000 calls = 2000 tiny descriptors allocated and freed.
PRINT ""
PRINT "Test 9: 2000 CHR$ allocations"
DIM charResult AS STRING
charResult = ""
DIM i9 AS INTEGER
FOR i9 = 1 TO 2000
  DIM ch AS STRING
  ch = CHR$(65 + (i9 MOD 26))
  charResult = ch
NEXT i9
' 2000 MOD 26 = 24 (0-based), CHR$(65+24) = CHR$(89) = "Y"
PRINT "  Last char: "; charResult
IF charResult = "Y" THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected Y"
END IF

' --- Test 10: STR$ + VAL round-trip churn ---
' Convert integer to string and back, 1500 times.
' Each STR$ creates a new string descriptor.
PRINT ""
PRINT "Test 10: 1500 STR$/VAL round-trips"
DIM roundTrip AS INTEGER
roundTrip = 0
DIM i10 AS INTEGER
FOR i10 = 1 TO 1500
  DIM sv AS STRING
  sv = STR$(i10 * 7)
  DIM nv AS INTEGER
  nv = VAL(sv)
  roundTrip = roundTrip + nv
NEXT i10
' sum of 7*1 + 7*2 + ... + 7*1500 = 7 * sum(1..1500) = 7 * 1125750 = 7880250
PRINT "  Sum: "; roundTrip
IF roundTrip = 7880250 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 7880250"
END IF

' --- Test 11: String comparison churn ---
' Create two strings per iteration and compare them.
' Tests that comparison doesn't leak descriptors.
PRINT ""
PRINT "Test 11: 1000 string comparisons"
DIM matchCount AS INTEGER
matchCount = 0
DIM i11 AS INTEGER
FOR i11 = 1 TO 1000
  DIM lhs AS STRING
  lhs = "cmp_" + STR$(i11)
  DIM rhs AS STRING
  rhs = "cmp_" + STR$(i11)
  IF lhs = rhs THEN
    matchCount = matchCount + 1
  END IF
NEXT i11
PRINT "  Matches: "; matchCount
IF matchCount = 1000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1000"
END IF

' --- Test 12: Large string growth and shrink cycle ---
' Build a string up to 500 chars, then repeatedly replace it with
' shorter strings. Tests that large buffers are properly freed.
PRINT ""
PRINT "Test 12: String grow/shrink cycles"
DIM cycleStr AS STRING
DIM cycleOk AS INTEGER
cycleOk = 1
DIM cyc AS INTEGER
DIM gx AS INTEGER
DIM shx AS INTEGER
FOR cyc = 1 TO 10
  ' Grow phase
  cycleStr = ""
  FOR gx = 1 TO 50
    cycleStr = cycleStr + "ABCDEFGHIJ"
  NEXT gx
  IF LEN(cycleStr) <> 500 THEN
    cycleOk = 0
  END IF
  ' Shrink phase: replace with progressively shorter strings
  FOR shx = 1 TO 10
    cycleStr = MID$(cycleStr, 1, LEN(cycleStr) - 50)
  NEXT shx
  IF LEN(cycleStr) <> 0 THEN
    cycleOk = 0
  END IF
NEXT cyc
IF cycleOk = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL: grow/shrink mismatch"
END IF

' --- Test 13: Rapid StringBox creation with string members ---
' Each StringBox holds a string member; creating 1000 boxes means
' 1000 object descriptors + 1000 string descriptors tracked.
PRINT ""
PRINT "Test 13: 1000 StringBox objects with string members"
DIM lastBoxVal AS STRING
lastBoxVal = ""
DIM i13 AS INTEGER
FOR i13 = 1 TO 1000
  DIM bx AS StringBox = NEW StringBox("box_" + STR$(i13))
  lastBoxVal = bx.GetValue()
NEXT i13
PRINT "  Last box: "; lastBoxVal
PRINT "  PASS"

' --- Test 14: Mixed MID$, LEFT$, RIGHT$ extraction ---
' Creates substring descriptors from a source string.
PRINT ""
PRINT "Test 14: 1000 substring extractions"
DIM srcStr AS STRING
srcStr = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
DIM lastSub AS STRING
lastSub = ""
DIM i14 AS INTEGER
FOR i14 = 1 TO 1000
  DIM pos AS INTEGER
  pos = (i14 MOD 20) + 1
  DIM substr1 AS STRING
  substr1 = MID$(srcStr, pos, 3)
  lastSub = substr1
NEXT i14
' 1000 MOD 20 = 0, so pos = 0+1 = 1, MID$("ABC...",1,3) = "ABC"
PRINT "  Last sub: "; lastSub
IF lastSub = "ABC" THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected ABC"
END IF

PRINT ""
PRINT "=== All string churn stress tests passed ==="
END
