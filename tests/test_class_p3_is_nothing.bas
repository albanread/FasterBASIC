' === test_class_p3_is_nothing.bas ===
' Phase 3 Test: IS type check, NOTHING, DELETE
' Validates: IS operator, IS NOTHING, NOTHING assignment, DELETE statement

' --- Setup: class hierarchy for IS tests ---

CLASS Shape
  Kind AS STRING

  CONSTRUCTOR(k AS STRING)
    ME.Kind = k
  END CONSTRUCTOR

  METHOD GetKind() AS STRING
    RETURN ME.Kind
  END METHOD
END CLASS

CLASS CircleShape EXTENDS Shape
  Radius AS DOUBLE

  CONSTRUCTOR(r AS DOUBLE)
    SUPER("Circle")
    ME.Radius = r
  END CONSTRUCTOR
END CLASS

CLASS SquareShape EXTENDS Shape
  Side AS DOUBLE

  CONSTRUCTOR(s AS DOUBLE)
    SUPER("Square")
    ME.Side = s
  END CONSTRUCTOR
END CLASS

' --- Test 1: IS type check (same type) ---

PRINT "=== IS Type Check ==="
DIM c AS CircleShape = NEW CircleShape(5.0)
DIM isCircle AS INTEGER
isCircle = c IS CircleShape
PRINT "c IS Circle: "; isCircle

' --- Test 2: IS type check (subclass) ---

DIM s AS Shape = NEW CircleShape(3.0)
DIM isShape AS INTEGER
isShape = s IS Shape
PRINT "s IS Shape: "; isShape
DIM isCircle2 AS INTEGER
isCircle2 = s IS CircleShape
PRINT "s IS Circle: "; isCircle2

' --- Test 3: IS type check (negative) ---

DIM sq AS SquareShape = NEW SquareShape(4.0)
DIM sqIsCircle AS INTEGER
sqIsCircle = sq IS CircleShape
PRINT "sq IS Circle: "; sqIsCircle
DIM sqIsShape AS INTEGER
sqIsShape = sq IS Shape
PRINT "sq IS Shape: "; sqIsShape
PRINT ""

' --- Test 4: IS NOTHING check ---

PRINT "=== IS NOTHING ==="
DIM obj AS Shape = NEW Shape("Test")
DIM isNothing1 AS INTEGER
isNothing1 = obj IS NOTHING
PRINT "obj IS NOTHING: "; isNothing1

DIM emptyObj AS Shape
DIM isNothing2 AS INTEGER
isNothing2 = emptyObj IS NOTHING
PRINT "emptyObj IS NOTHING: "; isNothing2
PRINT ""

' --- Test 5: NOTHING assignment ---

PRINT "=== NOTHING Assignment ==="
DIM p AS Shape = NEW Shape("Point")
PRINT "Before: "; p.GetKind()
p = NOTHING
DIM isNothingAfter AS INTEGER
isNothingAfter = p IS NOTHING
PRINT "After NOTHING: IS NOTHING = "; isNothingAfter
PRINT ""

' --- Test 6: DELETE statement ---

PRINT "=== DELETE ==="
DIM d AS Shape = NEW Shape("Deletable")
PRINT "Before DELETE: "; d.GetKind()
DELETE d
DIM isNothingDel AS INTEGER
isNothingDel = d IS NOTHING
PRINT "After DELETE: IS NOTHING = "; isNothingDel
PRINT ""

' --- Test 7: DELETE on NOTHING (no-op, should not crash) ---

PRINT "=== DELETE on NOTHING ==="
DIM already AS Shape
DELETE already
PRINT "DELETE on NOTHING: OK"
PRINT ""

PRINT "Done!"
END

' EXPECTED OUTPUT:
' === IS Type Check ===
' c IS Circle: 1
' s IS Shape: 1
' s IS Circle: 1
' sq IS Circle: 0
' sq IS Shape: 1
'
' === IS NOTHING ===
' obj IS NOTHING: 0
' emptyObj IS NOTHING: 1
'
' === NOTHING Assignment ===
' Before: Point
' After NOTHING: IS NOTHING = 1
'
' === DELETE ===
' Before DELETE: Deletable
' After DELETE: IS NOTHING = 1
'
' === DELETE on NOTHING ===
' DELETE on NOTHING: OK
'
' Done!
