' === test_dim_in_loops.bas ===
' Tests DIM declarations inside FOR loops, IF blocks, and nested structures.
' These are patterns beginners commonly write that must "just work."

' --- Test 1: DIM scalar inside FOR loop ---

PRINT "=== DIM Scalar in FOR Loop ==="
DIM total AS INTEGER
total = 0
FOR i% = 1 TO 5
  DIM x AS INTEGER
  x = i% * 10
  total = total + x
NEXT i%
PRINT "Total: "; total

' --- Test 2: DIM string inside FOR loop ---

PRINT ""
PRINT "=== DIM String in FOR Loop ==="
DIM result AS STRING
result = ""
FOR j% = 1 TO 3
  DIM s AS STRING
  s = "item" + STR$(j%)
  result = result + s + " "
NEXT j%
PRINT "Result: "; result

' --- Test 3: DIM inside IF block ---

PRINT ""
PRINT "=== DIM in IF Block ==="
DIM score AS INTEGER
score = 85
IF score > 70 THEN
  DIM grade AS STRING
  grade = "Pass"
  PRINT "Grade: "; grade
ELSE
  DIM grade2 AS STRING
  grade2 = "Fail"
  PRINT "Grade: "; grade2
END IF

' --- Test 4: DIM inside nested FOR loops ---

PRINT ""
PRINT "=== DIM in Nested FOR Loops ==="
DIM sum AS INTEGER
sum = 0
FOR a% = 1 TO 3
  DIM outer AS INTEGER
  outer = a% * 100
  FOR b% = 1 TO 2
    DIM inner AS INTEGER
    inner = b% * 10
    sum = sum + outer + inner
  NEXT b%
NEXT a%
PRINT "Sum: "; sum

' --- Test 5: DIM CLASS instance inside FOR loop ---

CLASS Widget
  Tag AS STRING

  CONSTRUCTOR(t AS STRING)
    ME.Tag = t
  END CONSTRUCTOR

  METHOD GetTag() AS STRING
    RETURN ME.Tag
  END METHOD
END CLASS

PRINT ""
PRINT "=== DIM CLASS in FOR Loop ==="
FOR k% = 1 TO 3
  DIM w AS Widget = NEW Widget("w" + STR$(k%))
  PRINT w.GetTag()
NEXT k%

' --- Test 6: DIM inside IF inside FOR ---

PRINT ""
PRINT "=== DIM in IF inside FOR ==="
FOR n% = 1 TO 4
  IF n% > 2 THEN
    DIM msg AS STRING
    msg = "big:" + STR$(n%)
    PRINT msg
  ELSE
    DIM msg2 AS STRING
    msg2 = "small:" + STR$(n%)
    PRINT msg2
  END IF
NEXT n%

' --- Test 7: DIM inside WHILE loop ---

PRINT ""
PRINT "=== DIM in WHILE Loop ==="
DIM counter AS INTEGER
counter = 1
DIM wtotal AS INTEGER
wtotal = 0
WHILE counter <= 4
  DIM wval AS INTEGER
  wval = counter * 5
  wtotal = wtotal + wval
  counter = counter + 1
WEND
PRINT "While total: "; wtotal

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' === DIM Scalar in FOR Loop ===
' Total: 150
'
' === DIM String in FOR Loop ===
' Result: item1 item2 item3
'
' === DIM in IF Block ===
' Grade: Pass
'
' === DIM in Nested FOR Loops ===
' Sum: 1290
'
' === DIM CLASS in FOR Loop ===
' w1
' w2
' w3
'
' === DIM in IF inside FOR ===
' small:1
' small:2
' big:3
' big:4
'
' === DIM in WHILE Loop ===
' While total: 50
'
' Done!
