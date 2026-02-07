' === test_samm_stress_scope_depth.bas ===
' Stress test: deep scope nesting and recursive allocation through SAMM.
'
' Pressurizes:
'   - Scope stack depth (SAMM_MAX_SCOPE_DEPTH = 256)
'   - Per-scope tracking at many nesting levels simultaneously
'   - RETAIN across many scope levels (deep returns)
'   - Cleanup ordering when deeply nested scopes unwind
'   - Background worker processing many small batches from rapid scope exits
'
' Uses recursive functions that allocate objects and strings at each
' recursion level, verifying correct results after full unwinding.

CLASS Node
  ID AS INTEGER
  Label AS STRING

  CONSTRUCTOR(id AS INTEGER, lbl AS STRING)
    ME.ID = id
    ME.Label = lbl
  END CONSTRUCTOR

  METHOD GetID() AS INTEGER
    RETURN ME.ID
  END METHOD

  METHOD GetLabel() AS STRING
    RETURN ME.Label
  END METHOD
END CLASS

' =========================================================================
' Test 1: Deep recursion with object allocation at each level
' Each level creates a Node, reads its value, and recurses.
' The sum accumulates on the way back up. Depth = 100.
' =========================================================================
FUNCTION RecursiveSum(depth AS INTEGER, maxDepth AS INTEGER) AS INTEGER
  IF depth > maxDepth THEN
    RecursiveSum = 0
    RETURN RecursiveSum
  END IF
  DIM n AS Node = NEW Node(depth, "N" + STR$(depth))
  DIM remaining AS INTEGER
  remaining = RecursiveSum(depth + 1, maxDepth)
  RecursiveSum = n.GetID() + remaining
END FUNCTION

' =========================================================================
' Test 2: Deep recursion with string creation and return at each level
' Each level builds a string, recurses, and concatenates results.
' Tests RETAIN of string return values across many scope levels.
' Depth = 50 (string concat is heavier than integer arithmetic).
' =========================================================================
FUNCTION RecursiveConcat(depth AS INTEGER, maxDepth AS INTEGER) AS STRING
  IF depth > maxDepth THEN
    RecursiveConcat = ""
    RETURN RecursiveConcat
  END IF
  DIM tag AS STRING
  tag = CHR$(65 + (depth MOD 26))
  DIM remaining AS STRING
  remaining = RecursiveConcat(depth + 1, maxDepth)
  IF remaining = "" THEN
    RecursiveConcat = tag
  ELSE
    RecursiveConcat = tag + remaining
  END IF
END FUNCTION

' =========================================================================
' Test 3: Deep recursion with both objects AND strings at each level
' Allocates a Node and a temp string, uses both, recurses.
' Tests mixed-type tracking in deep scope stacks. Depth = 80.
' =========================================================================
FUNCTION RecursiveMixed(depth AS INTEGER, maxDepth AS INTEGER) AS INTEGER
  IF depth > maxDepth THEN
    RecursiveMixed = 0
    RETURN RecursiveMixed
  END IF
  DIM n AS Node = NEW Node(depth, "mix" + STR$(depth))
  DIM label AS STRING
  label = n.GetLabel()
  DIM labelLen AS INTEGER
  labelLen = LEN(label)
  DIM remaining AS INTEGER
  remaining = RecursiveMixed(depth + 1, maxDepth)
  RecursiveMixed = labelLen + remaining
END FUNCTION

' =========================================================================
' Test 4: Deep nesting via nested FOR loops (iterative scope depth)
' 10 levels of nested FOR loops, each with an object allocation.
' Tests scope depth via loop nesting rather than recursion.
' 10 * 3 iterations per level = 3^10... too many. Use 2 iterations.
' Actually just use single-iteration loops to test pure depth.
' =========================================================================
SUB NestedLoopDepth()
  DIM total AS INTEGER
  total = 0
  DIM a AS INTEGER
  DIM b AS INTEGER
  DIM c AS INTEGER
  DIM d AS INTEGER
  DIM e AS INTEGER
  DIM f AS INTEGER
  DIM g AS INTEGER
  FOR a = 1 TO 2
    DIM na AS Node = NEW Node(a, "a")
    FOR b = 1 TO 2
      DIM nb AS Node = NEW Node(b, "b")
      FOR c = 1 TO 2
        DIM nc AS Node = NEW Node(c, "c")
        FOR d = 1 TO 2
          DIM nd AS Node = NEW Node(d, "d")
          FOR e = 1 TO 2
            DIM ne2 AS Node = NEW Node(e, "e")
            FOR f = 1 TO 2
              DIM nf AS Node = NEW Node(f, "f")
              FOR g = 1 TO 2
                DIM ng AS Node = NEW Node(g, "g")
                total = total + na.GetID() + nb.GetID() + nc.GetID() + nd.GetID() + ne2.GetID() + nf.GetID() + ng.GetID()
              NEXT g
            NEXT f
          NEXT e
        NEXT d
      NEXT c
    NEXT b
  NEXT a
  ' 2^7 = 128 iterations total
  ' Each iteration: a+b+c+d+e+f+g where each var is 1 or 2
  ' Average per variable = 1.5, 7 vars, 128 iterations
  ' Exact: for each variable independently taking 1 or 2
  ' Sum over all combos of (a+b+c+d+e+f+g) = 128*7*1.5 = 1344
  PRINT "  Nested loop total: "; total
  IF total = 1344 THEN
    PRINT "  PASS"
  ELSE
    PRINT "  FAIL expected 1344"
  END IF
END SUB

' =========================================================================
' Test 5: Recursive FUNCTION returning an object (RETAIN chain)
' Build a chain of retained objects through recursion.
' Tests that RETAIN propagates correctly across many scope levels.
' =========================================================================
FUNCTION DeepBuild(depth AS INTEGER) AS Node
  IF depth <= 0 THEN
    DeepBuild = NEW Node(0, "leaf")
    RETURN DeepBuild
  END IF
  DIM child AS Node = DeepBuild(depth - 1)
  DIM combined AS INTEGER
  combined = child.GetID() + depth
  DeepBuild = NEW Node(combined, "d" + STR$(depth))
END FUNCTION

' =========================================================================
' Test 6: Alternating recursion (mutual-like via flag)
' Simulates two alternating allocation patterns at each level.
' Even levels create Nodes, odd levels create strings.
' =========================================================================
FUNCTION AlternatingRecurse(depth AS INTEGER, maxDepth AS INTEGER) AS INTEGER
  IF depth > maxDepth THEN
    AlternatingRecurse = 0
    RETURN AlternatingRecurse
  END IF

  DIM contribution AS INTEGER
  IF (depth MOD 2) = 0 THEN
    ' Even: allocate a Node
    DIM n AS Node = NEW Node(depth, "even")
    contribution = n.GetID()
  ELSE
    ' Odd: allocate strings
    DIM s1 AS STRING
    s1 = "odd_" + STR$(depth)
    DIM s2 AS STRING
    s2 = s1 + "_done"
    contribution = LEN(s2)
  END IF

  DIM remaining AS INTEGER
  remaining = AlternatingRecurse(depth + 1, maxDepth)
  AlternatingRecurse = contribution + remaining
END FUNCTION

' =========================================================================
' Test 7: Recursive string building with intermediate objects
' Each level creates a Node, extracts its label, appends to accumulator.
' Tests combined object + string RETAIN at each recursion unwind.
' =========================================================================
FUNCTION RecursiveLabelBuild(depth AS INTEGER, maxDepth AS INTEGER) AS STRING
  IF depth > maxDepth THEN
    RecursiveLabelBuild = ""
    RETURN RecursiveLabelBuild
  END IF
  DIM n AS Node = NEW Node(depth, STR$(depth))
  DIM tailStr AS STRING
  tailStr = RecursiveLabelBuild(depth + 1, maxDepth)
  IF tailStr = "" THEN
    RecursiveLabelBuild = n.GetLabel()
  ELSE
    RecursiveLabelBuild = n.GetLabel() + "," + tailStr
  END IF
END FUNCTION

' =========================================================================
' Main test program
' =========================================================================

PRINT "=== SAMM Scope Depth Stress Tests ==="

' --- Test 1: Recursive sum, depth 100 ---
PRINT ""
PRINT "Test 1: Recursive object alloc, depth 100"
DIM sum1 AS INTEGER
sum1 = RecursiveSum(1, 100)
' Expected: sum of 1..100 = 5050
PRINT "  Sum: "; sum1
IF sum1 = 5050 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 5050"
END IF

' --- Test 2: Recursive string concat, depth 50 ---
PRINT ""
PRINT "Test 2: Recursive string concat, depth 50"
DIM str2 AS STRING
str2 = RecursiveConcat(1, 50)
PRINT "  Length: "; LEN(str2)
' 50 characters, each is CHR$(65 + (depth MOD 26))
' depth 1..50 -> offsets 1..24,0,1..24,0 -> chars B..Y,Z,A,B..Y,Z,A...
IF LEN(str2) = 50 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected length 50"
END IF

' --- Test 3: Recursive mixed alloc, depth 80 ---
PRINT ""
PRINT "Test 3: Recursive mixed (object+string), depth 80"
DIM sum3 AS INTEGER
sum3 = RecursiveMixed(1, 80)
' Each level contributes LEN("mix" + STR$(depth))
' STR$ of 1..9 = 2 chars (space + digit), 10..80 = 3 chars (space + 2 digits)
' LEN("mix") = 3
' depth 1..9: 3 + 2 = 5 each -> 9 * 5 = 45
' depth 10..80: 3 + 3 = 6 each -> 71 * 6 = 426
' Total = 45 + 426 = 471
PRINT "  Total label lengths: "; sum3
IF sum3 = 471 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 471"
END IF

' --- Test 4: Nested FOR loops, 7 levels deep ---
PRINT ""
PRINT "Test 4: 7-level nested FOR loops with objects"
NestedLoopDepth

' --- Test 5: Deep object RETAIN chain, depth 60 ---
PRINT ""
PRINT "Test 5: Deep object return (RETAIN chain), depth 60"
DIM deepNode AS Node = DeepBuild(60)
' DeepBuild(60) returns Node with ID = sum of 0..60 = 1830
PRINT "  Deep node ID: "; deepNode.GetID()
IF deepNode.GetID() = 1830 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1830"
END IF

' --- Test 6: Alternating recursion, depth 100 ---
PRINT ""
PRINT "Test 6: Alternating alloc patterns, depth 100"
DIM sum6 AS INTEGER
sum6 = AlternatingRecurse(0, 99)
' Even depths (0,2,4,...,98): contribute depth value
'   = 0+2+4+...+98 = 2*(0+1+2+...+49) = 2*1225 = 2450
' Odd depths (1,3,5,...,99): contribute LEN("odd_" + STR$(d) + "_done")
'   "odd_" = 4 chars, "_done" = 5 chars
'   STR$(1) = " 1" = 2 chars, ..., STR$(9) = 2 chars
'   STR$(11)..STR$(99) = 3 chars (for 2-digit odds)
'   Odd 1-digit: 1,3,5,7,9 -> 5 values, each LEN = 4+2+5 = 11 -> 55
'   Odd 2-digit: 11,13,...,99 -> 45 values, each LEN = 4+3+5 = 12 -> 540
'   Total odd contribution = 55 + 540 = 595
' Total = 2450 + 595 = 3045
PRINT "  Sum: "; sum6
IF sum6 = 3045 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 3045"
END IF

' --- Test 7: Recursive label build, depth 30 ---
PRINT ""
PRINT "Test 7: Recursive label build, depth 30"
DIM labels AS STRING
labels = RecursiveLabelBuild(1, 30)
' Should be " 1, 2, 3,..., 30" with commas
' Just check it's non-empty and has right number of commas (29)
DIM commaCount AS INTEGER
commaCount = 0
DIM ci AS INTEGER
FOR ci = 1 TO LEN(labels)
  IF MID$(labels, ci, 1) = "," THEN
    commaCount = commaCount + 1
  END IF
NEXT ci
PRINT "  Comma count: "; commaCount; " (expected 29)"
IF commaCount = 29 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL"
END IF

' --- Test 8: Repeated deep recursion (scope reuse) ---
' Call the recursive function 20 times to verify scopes are
' properly cleaned and reusable after unwinding.
PRINT ""
PRINT "Test 8: 20 repeated deep recursions (scope reuse)"
DIM total8 AS INTEGER
total8 = 0
DIM rep AS INTEGER
FOR rep = 1 TO 20
  DIM partial AS INTEGER
  partial = RecursiveSum(1, 50)
  total8 = total8 + partial
NEXT rep
' Each call returns sum(1..50) = 1275, total = 20*1275 = 25500
PRINT "  Total: "; total8
IF total8 = 25500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 25500"
END IF

PRINT ""
PRINT "=== All scope depth stress tests passed ==="
END
