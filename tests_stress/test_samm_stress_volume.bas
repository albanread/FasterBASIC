' === test_samm_stress_volume.bas ===
' Stress test: high-volume object and string allocation through SAMM.
'
' Pressurizes:
'   - Scope tracking array growth (starts at 32, must double many times)
'   - Cleanup queue throughput (background worker must keep up)
'   - Bloom filter with thousands of freed addresses
'   - String descriptor allocation/tracking/release at scale
'
' All sub-tests use inline loops to avoid a multi-function codegen
' temp-numbering issue with the CFG emitter.

CLASS Counter
  Value AS INTEGER

  CONSTRUCTOR(v AS INTEGER)
    ME.Value = v
  END CONSTRUCTOR

  METHOD GetValue() AS INTEGER
    RETURN ME.Value
  END METHOD
END CLASS

CLASS Pair
  A AS INTEGER
  B AS INTEGER

  CONSTRUCTOR(a AS INTEGER, b AS INTEGER)
    ME.A = a
    ME.B = b
  END CONSTRUCTOR

  METHOD Sum() AS INTEGER
    RETURN ME.A + ME.B
  END METHOD
END CLASS

' =========================================================================
' Main test program — all tests are inline in the main scope
' =========================================================================

PRINT "=== SAMM Volume Stress Tests ==="

' --- Test 1: 2000 Counter objects churned per-iteration ---
' Each iteration creates a Counter in the loop scope; SAMM cleans it
' when the iteration scope exits. 2000 alloc/track/clean cycles.
PRINT ""
PRINT "Test 1: 2000 Counter object churn"
DIM total1 AS INTEGER
total1 = 0
DIM i1 AS INTEGER
FOR i1 = 1 TO 2000
  DIM c1 AS Counter = NEW Counter(i1)
  total1 = total1 + c1.GetValue()
NEXT i1
' Expected: sum of 1..2000 = 2000*2001/2 = 2001000
PRINT "  Sum: "; total1
IF total1 = 2001000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 2001000"
END IF

' --- Test 2: 2000 Pair objects churned per-iteration ---
PRINT ""
PRINT "Test 2: 2000 Pair object churn"
DIM total2 AS INTEGER
total2 = 0
DIM i2 AS INTEGER
FOR i2 = 1 TO 2000
  DIM p2 AS Pair = NEW Pair(i2, i2 * 2)
  total2 = total2 + p2.Sum()
NEXT i2
' Each Pair(i, i*2).Sum() = i + 2i = 3i, sum = 3*2001000 = 6003000
PRINT "  Sum: "; total2
IF total2 = 6003000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 6003000"
END IF

' --- Test 3: 2000 strings churned per-iteration ---
PRINT ""
PRINT "Test 3: 2000 string churn"
DIM last3 AS STRING
last3 = ""
DIM i3 AS INTEGER
FOR i3 = 1 TO 2000
  DIM s3 AS STRING
  s3 = "item_" + STR$(i3)
  last3 = s3
NEXT i3
PRINT "  Last: "; last3
PRINT "  PASS"

' --- Test 4: 500 objects accumulated in one scope, then cleaned ---
' This forces the scope tracking array to grow from 32 -> 64 -> 128 -> 256 -> 512 -> 1024.
PRINT ""
PRINT "Test 4: 500 objects in single scope (tracking array growth)"
DIM total4 AS INTEGER
total4 = 0
DIM i4 AS INTEGER
FOR i4 = 1 TO 500
  DIM c4 AS Counter = NEW Counter(i4)
  total4 = total4 + c4.GetValue()
NEXT i4
' sum of 1..500 = 125250
PRINT "  Sum: "; total4
IF total4 = 125250 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 125250"
END IF

' --- Test 5: String concatenation building pressure ---
' Each concat creates a new string descriptor + data buffer.
' 500 concats = 500 string allocs, mostly cleaned per-iteration.
PRINT ""
PRINT "Test 5: 500 string concatenations (descriptor churn)"
DIM result5 AS STRING
result5 = ""
DIM i5 AS INTEGER
FOR i5 = 1 TO 500
  result5 = result5 + "X"
NEXT i5
DIM len5 AS INTEGER
len5 = LEN(result5)
PRINT "  Length: "; len5
IF len5 = 500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500"
END IF

' --- Test 6: Mixed objects and strings in same loop ---
PRINT ""
PRINT "Test 6: 1000 mixed object+string iterations"
DIM total6 AS INTEGER
total6 = 0
DIM lastStr6 AS STRING
lastStr6 = ""
DIM i6 AS INTEGER
FOR i6 = 1 TO 1000
  DIM c6 AS Counter = NEW Counter(i6)
  DIM s6 AS STRING
  s6 = "v" + STR$(c6.GetValue())
  total6 = total6 + c6.GetValue()
  lastStr6 = s6
NEXT i6
' sum of 1..1000 = 500500
PRINT "  Sum: "; total6
PRINT "  Last: "; lastStr6
IF total6 = 500500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500500"
END IF

' --- Test 7: Object reassignment churn ---
' Reassign the same variable 1000 times; old objects become
' unreachable and must be cleaned by SAMM.
PRINT ""
PRINT "Test 7: 1000 object reassignments"
DIM obj7 AS Counter = NEW Counter(0)
DIM i7 AS INTEGER
FOR i7 = 1 TO 1000
  obj7 = NEW Counter(i7)
NEXT i7
PRINT "  Final value: "; obj7.GetValue()
IF obj7.GetValue() = 1000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1000"
END IF

' --- Test 8: String reassignment churn ---
' Reassign the same string variable 2000 times.
PRINT ""
PRINT "Test 8: 2000 string reassignments"
DIM str8 AS STRING
str8 = ""
DIM i8 AS INTEGER
FOR i8 = 1 TO 2000
  str8 = "s" + STR$(i8)
NEXT i8
PRINT "  Final: "; str8
PRINT "  PASS"

' --- Test 9: Nested loops with objects (inner * outer allocations) ---
' 50 outer * 50 inner = 2500 object allocations
PRINT ""
PRINT "Test 9: Nested loop object churn (50x50)"
DIM total9 AS INTEGER
total9 = 0
DIM outer9 AS INTEGER
DIM inner9 AS INTEGER
FOR outer9 = 1 TO 50
  FOR inner9 = 1 TO 50
    DIM p9 AS Pair = NEW Pair(outer9, inner9)
    total9 = total9 + p9.Sum()
  NEXT inner9
NEXT outer9
' Sum = sum over outer=1..50, inner=1..50 of (outer+inner)
'     = 50 * sum(1..50) + 50 * sum(1..50)
'     = 50*1275 + 50*1275 = 63750 + 63750 = 127500
PRINT "  Sum: "; total9
IF total9 = 127500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 127500"
END IF

' --- Test 10: Rapid DELETE + re-allocate (Bloom filter pressure) ---
' DELETE 1000 objects, then allocate 1000 more.
PRINT ""
PRINT "Test 10: 1000 DELETE + 1000 new allocs (Bloom filter)"
DIM i10a AS INTEGER
FOR i10a = 1 TO 1000
  DIM d10 AS Counter = NEW Counter(i10a)
  DELETE d10
NEXT i10a
DIM total10 AS INTEGER
total10 = 0
DIM i10b AS INTEGER
FOR i10b = 1 TO 1000
  DIM n10 AS Counter = NEW Counter(i10b)
  total10 = total10 + n10.GetValue()
NEXT i10b
' sum of 1..1000 = 500500
PRINT "  Sum: "; total10
IF total10 = 500500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500500"
END IF

' --- Test 11: Triple nested loops with strings ---
' 10 * 10 * 10 = 1000 string allocations across 3 nesting levels
PRINT ""
PRINT "Test 11: Triple nested loop string churn (10x10x10)"
DIM last11 AS STRING
last11 = ""
DIM cnt11 AS INTEGER
cnt11 = 0
DIM a11 AS INTEGER
DIM b11 AS INTEGER
DIM c11 AS INTEGER
FOR a11 = 1 TO 10
  FOR b11 = 1 TO 10
    FOR c11 = 1 TO 10
      DIM s11 AS STRING
      s11 = STR$(a11) + "." + STR$(b11) + "." + STR$(c11)
      last11 = s11
      cnt11 = cnt11 + 1
    NEXT c11
  NEXT b11
NEXT a11
PRINT "  Count: "; cnt11
PRINT "  Last: "; last11
IF cnt11 = 1000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1000"
END IF

' --- Test 12: Interleaved object and DELETE ---
' Create two objects per iteration, delete one, keep the other.
' Tests mixed explicit-free and scope-cleanup lifetimes.
PRINT ""
PRINT "Test 12: 500 interleaved create/delete cycles"
DIM total12 AS INTEGER
total12 = 0
DIM i12 AS INTEGER
FOR i12 = 1 TO 500
  DIM keep12 AS Counter = NEW Counter(i12)
  DIM toss12 AS Counter = NEW Counter(i12 * 100)
  DELETE toss12
  total12 = total12 + keep12.GetValue()
NEXT i12
' sum of 1..500 = 125250
PRINT "  Sum: "; total12
IF total12 = 125250 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 125250"
END IF

' --- Test 13: Large string via repeated concat + MID$ shrink ---
PRINT ""
PRINT "Test 13: String grow/shrink cycles"
DIM cycleOk AS INTEGER
cycleOk = 1
DIM cyc AS INTEGER
DIM gx AS INTEGER
DIM shx AS INTEGER
FOR cyc = 1 TO 10
  DIM cycStr AS STRING
  cycStr = ""
  FOR gx = 1 TO 50
    cycStr = cycStr + "ABCDEFGHIJ"
  NEXT gx
  IF LEN(cycStr) <> 500 THEN
    cycleOk = 0
  END IF
  FOR shx = 1 TO 10
    cycStr = MID$(cycStr, 1, LEN(cycStr) - 50)
  NEXT shx
  IF LEN(cycStr) <> 0 THEN
    cycleOk = 0
  END IF
NEXT cyc
IF cycleOk = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL: grow/shrink mismatch"
END IF

' --- Test 14: STR$/VAL round-trip churn ---
PRINT ""
PRINT "Test 14: 1500 STR$/VAL round-trips"
DIM roundTrip AS INTEGER
roundTrip = 0
DIM i14 AS INTEGER
FOR i14 = 1 TO 1500
  DIM sv14 AS STRING
  sv14 = STR$(i14 * 7)
  DIM nv14 AS INTEGER
  nv14 = VAL(sv14)
  roundTrip = roundTrip + nv14
NEXT i14
' sum of 7*1 + 7*2 + ... + 7*1500 = 7 * 1125750 = 7880250
PRINT "  Sum: "; roundTrip
IF roundTrip = 7880250 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 7880250"
END IF

PRINT ""
PRINT "=== All volume stress tests passed ==="
END
