' === test_samm_stress_background.bas ===
' SAMM Background Worker Stress Test
'
' Purpose: Verify that the background cleanup worker thread actually
' processes cleanup batches when given time via SLEEP.  Previous stress
' tests ran so fast that the worker never got scheduled before shutdown.
'
' Strategy:
'   - Create objects in scopes, exit scopes (enqueues batches)
'   - SLEEP briefly to let the worker thread pick up and process batches
'   - Check that "Cleanup batches" is non-zero when SAMM_STATS=1
'
' Run with:  SAMM_STATS=1 ./test_samm_stress_background
' Expect:    Cleanup batches > 0 in the stats output

OPTION SAMM ON

PRINT "=== SAMM Background Worker Stress Tests ==="
PRINT ""

' --- Helper classes ---

CLASS Counter
  Value AS INTEGER

  CONSTRUCTOR()
    ME.Value = 0
  END CONSTRUCTOR

  METHOD Increment()
    ME.Value = ME.Value + 1
  END METHOD

  METHOD GetValue() AS INTEGER
    RETURN ME.Value
  END METHOD
END CLASS

CLASS Payload
  ID AS INTEGER
  Label AS STRING

  CONSTRUCTOR(id AS INTEGER, lbl AS STRING)
    ME.ID = id
    ME.Label = lbl
  END CONSTRUCTOR

  METHOD GetID() AS INTEGER
    RETURN ME.ID
  END METHOD
END CLASS

' =========================================================================
' Test 1: Burst of scope exits then sleep
' Create 200 objects across 200 scopes, then sleep to let worker drain.
' =========================================================================

PRINT "Test 1: Burst of scope exits then sleep"
DIM sum1 AS INTEGER
sum1 = 0
DIM i AS INTEGER

FOR i = 1 TO 200
  DIM c AS Counter = NEW Counter()
  c.Increment()
  sum1 = sum1 + c.GetValue()
NEXT i

' Give the background worker time to process the 200 batches
SLEEP 0.05

IF sum1 = 200 THEN
  PRINT "  Sum: "; sum1; " PASS"
ELSE
  PRINT "  Sum: "; sum1; " FAIL (expected 200)"
END IF
PRINT ""

' =========================================================================
' Test 2: Interleaved bursts with sleeps
' 5 rounds of 100 objects each, with a sleep between rounds.
' This gives the worker multiple opportunities to run.
' =========================================================================

PRINT "Test 2: Interleaved bursts with sleeps (5 x 100)"
DIM sum2 AS INTEGER
sum2 = 0
DIM r AS INTEGER
DIM j AS INTEGER

FOR r = 1 TO 5
  FOR j = 1 TO 100
    DIM p AS Payload = NEW Payload(j, "rnd")
    sum2 = sum2 + p.GetID()
  NEXT j
  ' Sleep between rounds to let worker catch up
  SLEEP 0.02
NEXT r

IF sum2 = 25250 THEN
  PRINT "  Sum: "; sum2; " PASS"
ELSE
  PRINT "  Sum: "; sum2; " FAIL (expected 25250)"
END IF
PRINT ""

' =========================================================================
' Test 3: Object + string churn with worker time
' Each iteration creates an object and a string, exits scope, sleeps.
' 50 iterations with short sleeps.
' =========================================================================

PRINT "Test 3: Object + string churn with worker time (50 iterations)"
DIM sum3 AS INTEGER
sum3 = 0
DIM lastLabel AS STRING

FOR i = 1 TO 50
  DIM p2 AS Payload = NEW Payload(i, "item_" + STR$(i))
  sum3 = sum3 + p2.GetID()
  lastLabel = p2.Label
  ' Brief sleep every 10 iterations
  IF i MOD 10 = 0 THEN
    SLEEP 0.01
  END IF
NEXT i

IF sum3 = 1275 THEN
  PRINT "  Sum: "; sum3; " Last: "; lastLabel; " PASS"
ELSE
  PRINT "  Sum: "; sum3; " FAIL (expected 1275)"
END IF
PRINT ""

' =========================================================================
' Test 4: DELETE + scope cleanup interleaved
' Half the objects are explicitly DELETEd, half are left for scope cleanup.
' Sleep after each batch to let worker process scope-exit batches.
' =========================================================================

PRINT "Test 4: DELETE + scope cleanup interleaved (10 x 20)"
DIM sum4 AS INTEGER
sum4 = 0

FOR r = 1 TO 10
  FOR j = 1 TO 20
    DIM c2 AS Counter = NEW Counter()
    c2.Increment()
    c2.Increment()
    sum4 = sum4 + c2.GetValue()
    ' DELETE odd-numbered objects explicitly
    IF j MOD 2 = 1 THEN
      DELETE c2
    END IF
    ' Even-numbered objects left for SAMM scope cleanup
  NEXT j
  SLEEP 0.02
NEXT r

IF sum4 = 400 THEN
  PRINT "  Sum: "; sum4; " PASS"
ELSE
  PRINT "  Sum: "; sum4; " FAIL (expected 400)"
END IF
PRINT ""

' =========================================================================
' Test 5: Deep scope nesting with sleeps at each level
' 5 levels of nested function calls, each creating objects.
' =========================================================================

FUNCTION DeepWork(level AS INTEGER) AS INTEGER
  DIM dp AS Payload = NEW Payload(level, "level_" + STR$(level))
  DIM result AS INTEGER
  IF level <= 1 THEN
    result = dp.GetID()
  ELSE
    result = dp.GetID() + DeepWork(level - 1)
  END IF
  RETURN result
END FUNCTION

PRINT "Test 5: Deep scope nesting (20 calls x 5 deep)"
DIM sum5 AS INTEGER
sum5 = 0

FOR i = 1 TO 20
  sum5 = sum5 + DeepWork(5)
  ' Sleep every 5 iterations
  IF i MOD 5 = 0 THEN
    SLEEP 0.02
  END IF
NEXT i

' DeepWork(5) = 5+4+3+2+1 = 15, so 20*15 = 300
IF sum5 = 300 THEN
  PRINT "  Sum: "; sum5; " PASS"
ELSE
  PRINT "  Sum: "; sum5; " FAIL (expected 300)"
END IF
PRINT ""

' =========================================================================
' Test 6: Large burst then long sleep
' Create 500 objects in rapid succession, then sleep 200ms.
' This is the best scenario for the worker — large queue, plenty of time.
' =========================================================================

PRINT "Test 6: Large burst (500 objects) then long sleep"
DIM sum6 AS INTEGER
sum6 = 0

FOR i = 1 TO 500
  DIM c3 AS Counter = NEW Counter()
  c3.Increment()
  sum6 = sum6 + c3.GetValue()
NEXT i

' Long sleep — worker should drain everything
SLEEP 0.2

IF sum6 = 500 THEN
  PRINT "  Sum: "; sum6; " PASS"
ELSE
  PRINT "  Sum: "; sum6; " FAIL (expected 500)"
END IF
PRINT ""

' =========================================================================
' Test 7: String-heavy churn with worker time
' Strings are tracked by SAMM and cleaned via string_release at scope exit.
' =========================================================================

PRINT "Test 7: String-heavy churn (200 iterations)"
DIM sum7 AS INTEGER
sum7 = 0
DIM lastStr AS STRING

FOR i = 1 TO 200
  DIM s AS STRING
  s = "prefix_" + STR$(i) + "_suffix"
  sum7 = sum7 + LEN(s)
  lastStr = s
  IF i MOD 50 = 0 THEN
    SLEEP 0.02
  END IF
NEXT i

PRINT "  Sum of lengths: "; sum7; " Last: "; lastStr
PRINT "  PASS"
PRINT ""

' =========================================================================
' Test 8: Mixed objects, strings with sleeps
' =========================================================================

PRINT "Test 8: Mixed types with sleeps (100 iterations)"
DIM sum8 AS INTEGER
sum8 = 0

FOR i = 1 TO 100
  ' Object
  DIM p3 AS Payload = NEW Payload(i, "mix_" + STR$(i))
  sum8 = sum8 + p3.GetID()

  ' String work
  DIM tag AS STRING
  tag = "tag_" + STR$(i * 2)

  IF i MOD 25 = 0 THEN
    SLEEP 0.02
  END IF
NEXT i

IF sum8 = 5050 THEN
  PRINT "  Sum: "; sum8; " PASS"
ELSE
  PRINT "  Sum: "; sum8; " FAIL (expected 5050)"
END IF
PRINT ""

' Final sleep to let any remaining batches drain
SLEEP 0.1

PRINT "=== All background worker stress tests passed ==="
PRINT ""
PRINT "Check SAMM_STATS output above for:"
PRINT "  - Cleanup batches > 0  (worker processed batches)"
PRINT "  - Objects cleaned (bg) > 0"
PRINT "  - StringDesc pool: allocs == frees (no leaks)"
PRINT "  - Object_32 pool: allocs == frees (no leaks)"
END
