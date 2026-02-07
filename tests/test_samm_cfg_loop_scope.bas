' === test_samm_cfg_loop_scope.bas ===
' Tests that SAMM loop-iteration scopes work correctly in CFG-based
' FUNCTION and SUB bodies (not METHOD — those use the direct emitter).
'
' FOR loops in FUNCTIONs go through the CFG emitter path where
' For_Body / For_Increment blocks handle samm_enter_scope / samm_exit_scope.
' WHILE loops in FUNCTIONs also get SAMM scoping when the body is a
' single CFG block.
'
' Run with SAMM_STATS=1 to verify scope enter/exit counts match.

' --- Test A: DIM scalar inside FOR loop in FUNCTION ---
FUNCTION SumSquares(n AS INTEGER) AS INTEGER
  DIM total AS INTEGER
  total = 0
  FOR i% = 1 TO n
    DIM sq AS INTEGER
    sq = i% * i%
    total = total + sq
  NEXT i%
  SumSquares = total
END FUNCTION

' --- Test B: DIM scalar inside WHILE loop in FUNCTION ---
FUNCTION CountDown(start AS INTEGER) AS INTEGER
  DIM total AS INTEGER
  total = 0
  DIM c AS INTEGER
  c = start
  WHILE c > 0
    DIM v AS INTEGER
    v = c * 2
    total = total + v
    c = c - 1
  WEND
  CountDown = total
END FUNCTION

' --- Test C: FOR loop with NO DIM in body (should NOT emit SAMM scope) ---
FUNCTION SimpleSum(n AS INTEGER) AS INTEGER
  DIM acc AS INTEGER
  acc = 0
  FOR j% = 1 TO n
    acc = acc + j%
  NEXT j%
  SimpleSum = acc
END FUNCTION

' --- Test D: Nested FOR loops, inner has DIM ---
FUNCTION NestedSum(rows AS INTEGER, cols AS INTEGER) AS INTEGER
  DIM total AS INTEGER
  total = 0
  FOR r% = 1 TO rows
    FOR c% = 1 TO cols
      DIM product AS INTEGER
      product = r% * c%
      total = total + product
    NEXT c%
  NEXT r%
  NestedSum = total
END FUNCTION

' --- Test E: DIM string inside FOR loop ---
FUNCTION BuildList(n AS INTEGER) AS STRING
  DIM result AS STRING
  result = ""
  FOR k% = 1 TO n
    DIM item AS STRING
    item = STR$(k%)
    IF result <> "" THEN
      result = result + "," + item
    ELSE
      result = item
    END IF
  NEXT k%
  BuildList = result
END FUNCTION

' === Run tests ===

PRINT "=== SAMM CFG Loop Scope Tests ==="

' Test A: DIM scalar inside FOR in FUNCTION
PRINT "SumSquares(5) = "; SumSquares(5)

' Test B: DIM scalar inside WHILE in FUNCTION
PRINT "CountDown(4) = "; CountDown(4)

' Test C: Simple loop with no DIM in body (no extra scopes)
PRINT "SimpleSum(10) = "; SimpleSum(10)

' Test D: Nested FOR loops with DIM
PRINT "NestedSum(3,4) = "; NestedSum(3, 4)

' Test E: String DIM in FOR loop
PRINT "BuildList(4) = "; BuildList(4)

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' === SAMM CFG Loop Scope Tests ===
' SumSquares(5) = 55
' CountDown(4) = 20
' SimpleSum(10) = 55
' NestedSum(3,4) = 60
' BuildList(4) = 1,2,3,4
'
' Done!
