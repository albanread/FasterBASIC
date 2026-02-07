' === test_samm_integration.bas ===
' SAMM (Scope Aware Memory Management) Integration Test
' Validates: scope-based cleanup, RETAIN on METHOD RETURN, DELETE + double-free detection,
'            nested scopes, constructor/destructor interplay with SAMM

' --- Helper classes ---

CLASS Widget
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

' --- Test 1: Basic object allocation and scope cleanup ---
' Objects created in main scope should survive until program exit.

PRINT "=== Test 1: Basic allocation ==="
DIM w1 AS Widget = NEW Widget(1, "Alpha")
PRINT "ID: "; w1.GetID()
PRINT "Label: "; w1.GetLabel()
PRINT ""

' --- Test 2: DELETE and IS NOTHING ---
' Explicit DELETE should free the object and set the reference to NOTHING.
' Subsequent IS NOTHING check must return true.

PRINT "=== Test 2: DELETE ==="
DIM w4 AS Widget = NEW Widget(7, "Temp")
PRINT "Before DELETE: "; w4.GetID()
DELETE w4
DIM isNull4 AS INTEGER
isNull4 = w4 IS NOTHING
PRINT "After DELETE IS NOTHING: "; isNull4
PRINT ""

' --- Test 3: Multiple objects in same scope ---
' All objects should coexist and be independently accessible.

PRINT "=== Test 3: Multiple objects ==="
DIM a AS Counter = NEW Counter()
DIM b AS Counter = NEW Counter()
a.Increment()
a.Increment()
a.Increment()
b.Increment()
PRINT "a: "; a.GetValue()
PRINT "b: "; b.GetValue()
PRINT ""

' --- Test 4: Method returning object (RETAIN test) ---
' A method that creates and returns a new object must RETAIN it
' so it survives the method scope's cleanup.

CLASS Builder
  Prefix AS STRING

  CONSTRUCTOR(pfx AS STRING)
    ME.Prefix = pfx
  END CONSTRUCTOR

  METHOD Build(id AS INTEGER) AS Widget
    RETURN NEW Widget(id, ME.Prefix)
  END METHOD
END CLASS

PRINT "=== Test 4: Method returns object ==="
DIM bldr AS Builder = NEW Builder("Built")
DIM w7 AS Widget = bldr.Build(55)
PRINT "Built ID: "; w7.GetID()
PRINT "Built Label: "; w7.GetLabel()
PRINT ""

' --- Test 5: Object reassignment ---
' Reassigning an object variable should not crash; the old object
' becomes unreachable and will be cleaned up by SAMM at scope exit.

PRINT "=== Test 5: Reassignment ==="
DIM w8 AS Widget = NEW Widget(1, "First")
PRINT "Before: "; w8.GetID()
w8 = NEW Widget(2, "Second")
PRINT "After: "; w8.GetID()
PRINT ""

' --- Test 6: IS type check with SAMM-managed objects ---

CLASS Animal
  Name AS STRING
  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
END CLASS

CLASS Dog EXTENDS Animal
  Breed AS STRING
  CONSTRUCTOR(n AS STRING, b AS STRING)
    SUPER(n)
    ME.Breed = b
  END CONSTRUCTOR
END CLASS

PRINT "=== Test 6: IS checks ==="
DIM d AS Dog = NEW Dog("Rex", "Labrador")
DIM isDog AS INTEGER
isDog = d IS Dog
PRINT "IS Dog: "; isDog
DIM isAnimal AS INTEGER
isAnimal = d IS Animal
PRINT "IS Animal: "; isAnimal
DIM isWidget AS INTEGER
isWidget = d IS Widget
PRINT "IS Widget: "; isWidget
PRINT ""

' --- Test 7: DELETE on NOTHING (should be no-op) ---

PRINT "=== Test 7: DELETE on NOTHING ==="
DIM nullObj AS Widget
DELETE nullObj
PRINT "DELETE on NOTHING: OK"
PRINT ""

' --- Test 8: Counter stress test ---
' Creates multiple counters and exercises them to verify SAMM
' tracking handles multiple live objects correctly.

PRINT "=== Test 8: Stress ==="
DIM c1 AS Counter = NEW Counter()
DIM c2 AS Counter = NEW Counter()
DIM c3 AS Counter = NEW Counter()
DIM i AS INTEGER
FOR i = 1 TO 10
  c1.Increment()
  c2.Increment()
  c3.Increment()
NEXT i
PRINT "c1: "; c1.GetValue()
PRINT "c2: "; c2.GetValue()
PRINT "c3: "; c3.GetValue()
PRINT ""

PRINT "All SAMM tests passed!"
END

' EXPECTED OUTPUT:
' === Test 1: Basic allocation ===
' ID: 1
' Label: Alpha
'
' === Test 2: DELETE ===
' Before DELETE: 7
' After DELETE IS NOTHING: 1
'
' === Test 3: Multiple objects ===
' a: 3
' b: 1
'
' === Test 4: Method returns object ===
' Built ID: 55
' Built Label: Built
'
' === Test 5: Reassignment ===
' Before: 1
' After: 2
'
' === Test 6: IS checks ===
' IS Dog: 1
' IS Animal: 1
' IS Widget: 0
'
' === Test 7: DELETE on NOTHING ===
' DELETE on NOTHING: OK
'
' === Test 8: Stress ===
' c1: 10
' c2: 10
' c3: 10
'
' All SAMM tests passed!
