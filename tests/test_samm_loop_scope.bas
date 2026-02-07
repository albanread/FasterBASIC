' === test_samm_loop_scope.bas ===
' Tests that SAMM loop-iteration scopes work correctly inside METHOD bodies.
' When a FOR or WHILE loop inside a METHOD creates objects via DIM,
' those objects should be cleaned up at the end of each iteration —
' NOT accumulated until the METHOD returns.
'
' Run with SAMM_STATS=1 to verify scope enter/exit counts.

CLASS Token
  Tag AS STRING

  CONSTRUCTOR(t AS STRING)
    ME.Tag = t
  END CONSTRUCTOR

  METHOD GetTag() AS STRING
    RETURN ME.Tag
  END METHOD
END CLASS

CLASS Processor
  Prefix AS STRING

  CONSTRUCTOR(p AS STRING)
    ME.Prefix = p
  END CONSTRUCTOR

  ' --- Test A: DIM CLASS instance inside FOR loop in METHOD ---
  ' Each iteration creates a Token; SAMM loop scope should clean it up.
  METHOD ProcessItems(count AS INTEGER) AS STRING
    DIM last AS STRING
    last = ""
    FOR idx% = 1 TO count
      DIM t AS Token = NEW Token(ME.Prefix + STR$(idx%))
      last = t.GetTag()
    NEXT idx%
    ProcessItems = last
  END METHOD

  ' --- Test B: DIM scalar + CLASS inside WHILE loop in METHOD ---
  METHOD SumWhile(limit AS INTEGER) AS INTEGER
    DIM total AS INTEGER
    total = 0
    DIM cnt AS INTEGER
    cnt = 1
    WHILE cnt <= limit
      DIM amt AS INTEGER
      amt = cnt * 10
      total = total + amt
      cnt = cnt + 1
    WEND
    SumWhile = total
  END METHOD

  ' --- Test C: FOR loop with no DIM (should NOT emit SAMM scope) ---
  METHOD SimpleLoop(n AS INTEGER) AS INTEGER
    DIM acc AS INTEGER
    acc = 0
    FOR m% = 1 TO n
      acc = acc + m%
    NEXT m%
    SimpleLoop = acc
  END METHOD
END CLASS

' === Run tests ===

PRINT "=== SAMM Loop Scope Tests ==="

DIM p AS Processor = NEW Processor("item_")

' Test A: DIM CLASS inside FOR in METHOD
PRINT "Last tag: "; p.ProcessItems(5)

' Test B: DIM scalar inside WHILE in METHOD
PRINT "While sum: "; p.SumWhile(4)

' Test C: Simple loop with no DIM in body (no extra scopes)
PRINT "Simple sum: "; p.SimpleLoop(10)

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' === SAMM Loop Scope Tests ===
' Last tag: item_5
' While sum: 100
' Simple sum: 55
'
' Done!
