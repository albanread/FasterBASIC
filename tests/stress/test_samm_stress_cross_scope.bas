' === test_samm_stress_cross_scope.bas ===
' Stress test: objects crossing scope boundaries, DELETE in nested scopes,
' reassignment under SAMM pressure, and RETAIN correctness.
'
' Pressurizes:
'   - RETAIN mechanism: objects returned from deep functions/methods survive
'   - samm_free_object: DELETE in inner scope for object allocated in outer
'   - samm_untrack outward search: untracking across scope boundaries
'   - Bloom filter: many DELETE'd addresses checked on subsequent allocs
'   - Object reassignment: old objects become garbage tracked by SAMM
'   - IS NOTHING checks after DELETE in nested contexts
'   - Mixed object lifetimes: some retained, some deleted, some left for scope cleanup

CLASS Item
  ID AS INTEGER
  Name AS STRING

  CONSTRUCTOR(id AS INTEGER, name AS STRING)
    ME.ID = id
    ME.Name = name
  END CONSTRUCTOR

  METHOD GetID() AS INTEGER
    RETURN ME.ID
  END METHOD

  METHOD GetName() AS STRING
    RETURN ME.Name
  END METHOD
END CLASS

CLASS Container
  Label AS STRING
  Count AS INTEGER

  CONSTRUCTOR(lbl AS STRING)
    ME.Label = lbl
    ME.Count = 0
  END CONSTRUCTOR

  METHOD GetLabel() AS STRING
    RETURN ME.Label
  END METHOD

  METHOD GetCount() AS INTEGER
    RETURN ME.Count
  END METHOD

  METHOD Increment()
    ME.Count = ME.Count + 1
  END METHOD

  ' Create and return an Item (tests RETAIN from METHOD scope)
  METHOD MakeItem(id AS INTEGER) AS Item
    DIM itm AS Item = NEW Item(id, ME.Label + "_item_" + STR$(id))
    MakeItem = itm
  END METHOD
END CLASS

CLASS Factory
  Prefix AS STRING

  CONSTRUCTOR(pfx AS STRING)
    ME.Prefix = pfx
  END CONSTRUCTOR

  ' Create a Container (object returned from METHOD, tests RETAIN)
  METHOD Build(idx AS INTEGER) AS Container
    DIM c AS Container = NEW Container(ME.Prefix + "_" + STR$(idx))
    Build = c
  END METHOD

  ' Create an Item through a Container (double RETAIN chain)
  METHOD BuildItem(containerIdx AS INTEGER, itemIdx AS INTEGER) AS Item
    DIM c AS Container = Build(containerIdx)
    DIM itm AS Item = c.MakeItem(itemIdx)
    BuildItem = itm
  END METHOD
END CLASS

' =========================================================================
' Helper functions
' =========================================================================

' Create and return an object from a FUNCTION (tests RETAIN from FUNCTION)
FUNCTION CreateItem(id AS INTEGER, name AS STRING) AS Item
  DIM itm AS Item = NEW Item(id, name)
  CreateItem = itm
END FUNCTION

' Create an object, use it, then return a different one (old is garbage)
FUNCTION CreateWithDiscard(id AS INTEGER) AS Item
  DIM throwaway AS Item = NEW Item(id * 100, "discard")
  DIM keep AS Item = NEW Item(id, "kept_" + STR$(id))
  CreateWithDiscard = keep
END FUNCTION

' Recursive creation: each level creates an object, recurses, returns result
FUNCTION RecursiveCreate(depth AS INTEGER, maxDepth AS INTEGER) AS Item
  IF depth >= maxDepth THEN
    RecursiveCreate = NEW Item(depth, "leaf_" + STR$(depth))
    RETURN RecursiveCreate
  END IF
  ' Create a local object that becomes garbage when scope exits
  DIM local AS Item = NEW Item(depth, "local_" + STR$(depth))
  DIM id AS INTEGER
  id = local.GetID()
  ' Recurse — the returned Item is RETAIN'd across scope boundary
  DIM child AS Item = RecursiveCreate(depth + 1, maxDepth)
  ' Create final result combining info from both
  RecursiveCreate = NEW Item(id + child.GetID(), "r_" + STR$(depth))
END FUNCTION

' Delete an object passed from outer scope (tests cross-scope DELETE)
SUB DeleteInner(obj AS Item)
  DIM id AS INTEGER
  id = obj.GetID()
  DELETE obj
END SUB

' Create N items, delete half, return the count of survivors
FUNCTION CreateAndDeleteHalf(n AS INTEGER) AS INTEGER
  DIM survived AS INTEGER
  survived = 0
  DIM i AS INTEGER
  FOR i = 1 TO n
    DIM itm AS Item = NEW Item(i, "half_" + STR$(i))
    IF (i MOD 2) = 0 THEN
      DELETE itm
    ELSE
      survived = survived + 1
    END IF
  NEXT i
  CreateAndDeleteHalf = survived
END FUNCTION

' =========================================================================
' Main test program
' =========================================================================

PRINT "=== SAMM Cross-Scope Stress Tests ==="

' --- Test 1: Object returned from FUNCTION, used in main scope ---
PRINT ""
PRINT "Test 1: Object returned from FUNCTION (RETAIN)"
DIM item1 AS Item = CreateItem(42, "alpha")
PRINT "  ID: "; item1.GetID()
PRINT "  Name: "; item1.GetName()
IF item1.GetID() = 42 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 42"
END IF

' --- Test 2: Object returned from METHOD, used in main scope ---
PRINT ""
PRINT "Test 2: Object returned from METHOD (RETAIN)"
DIM factory AS Factory = NEW Factory("fac")
DIM container1 AS Container = factory.Build(1)
PRINT "  Label: "; container1.GetLabel()
IF container1.GetLabel() = "fac_ 1" THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL"
END IF

' --- Test 3: Double RETAIN chain (METHOD returns object from nested METHOD) ---
PRINT ""
PRINT "Test 3: Double RETAIN chain (METHOD -> METHOD -> return)"
DIM chainItem AS Item = factory.BuildItem(5, 10)
PRINT "  ID: "; chainItem.GetID()
PRINT "  Name: "; chainItem.GetName()
IF chainItem.GetID() = 10 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 10"
END IF

' --- Test 4: 500 objects returned from FUNCTION calls ---
' Each call creates, RETAINs, and returns an object.
' The previous result becomes garbage on reassignment.
PRINT ""
PRINT "Test 4: 500 function-returned objects (RETAIN churn)"
DIM lastItem AS Item = CreateItem(0, "init")
DIM i4 AS INTEGER
FOR i4 = 1 TO 500
  lastItem = CreateItem(i4, "item_" + STR$(i4))
NEXT i4
PRINT "  Final ID: "; lastItem.GetID()
IF lastItem.GetID() = 500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500"
END IF

' --- Test 5: Objects with discard (garbage inside function) ---
' CreateWithDiscard allocates a throwaway object inside the function.
' That object should be cleaned when the function scope exits.
PRINT ""
PRINT "Test 5: 500 function calls with internal garbage"
DIM lastKept AS Item
DIM i5 AS INTEGER
FOR i5 = 1 TO 500
  lastKept = CreateWithDiscard(i5)
NEXT i5
PRINT "  Final ID: "; lastKept.GetID()
PRINT "  Final Name: "; lastKept.GetName()
IF lastKept.GetID() = 500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500"
END IF

' --- Test 6: DELETE in main scope, IS NOTHING check ---
PRINT ""
PRINT "Test 6: DELETE + IS NOTHING (200 cycles)"
DIM deleteOk AS INTEGER
deleteOk = 1
DIM i6 AS INTEGER
FOR i6 = 1 TO 200
  DIM temp AS Item = NEW Item(i6, "del_" + STR$(i6))
  DIM beforeId AS INTEGER
  beforeId = temp.GetID()
  DELETE temp
  DIM isNull AS INTEGER
  isNull = temp IS NOTHING
  IF isNull <> 1 THEN
    deleteOk = 0
  END IF
NEXT i6
IF deleteOk = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL: IS NOTHING returned wrong value"
END IF

' --- Test 7: DELETE on NOTHING (should be no-op, no crash) ---
PRINT ""
PRINT "Test 7: DELETE on NOTHING (500 times, no crash)"
DIM i7 AS INTEGER
FOR i7 = 1 TO 500
  DIM nullItem AS Item
  DELETE nullItem
NEXT i7
PRINT "  PASS"

' --- Test 8: Create and delete half (mixed lifetimes) ---
' Half the objects are explicitly DELETE'd, half are left for SAMM
' scope cleanup when the function exits.
PRINT ""
PRINT "Test 8: Create 500, delete half (mixed lifetimes)"
DIM survivors AS INTEGER
survivors = CreateAndDeleteHalf(500)
' Odd numbers 1,3,5,...,499 = 250 survivors
PRINT "  Survivors: "; survivors
IF survivors = 250 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 250"
END IF

' --- Test 9: Recursive create, depth 60 (deep cross-scope RETAIN) ---
PRINT ""
PRINT "Test 9: Recursive create, depth 60"
DIM recItem AS Item = RecursiveCreate(1, 60)
' RecursiveCreate builds sum: at leaf depth=60, returns Item(60,...)
' At depth 59: local.ID=59, child.ID=60, returns Item(119,...)
' At depth 58: local.ID=58, child.ID=119, returns Item(177,...)
' Pattern: at depth d, returned ID = sum(d..60) = sum(1..60) - sum(1..d-1)
' At depth 1: returned ID = sum(1..60) = 1830
PRINT "  Recursive item ID: "; recItem.GetID()
IF recItem.GetID() = 1830 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 1830"
END IF

' --- Test 10: Object reassignment churn with METHOD returns ---
' Create containers from factory, reassign same variable.
' Old containers become garbage; new ones must survive via RETAIN.
PRINT ""
PRINT "Test 10: 500 METHOD-returned object reassignments"
DIM ctr AS Container = factory.Build(0)
DIM i10 AS INTEGER
FOR i10 = 1 TO 500
  ctr = factory.Build(i10)
  ctr.Increment()
NEXT i10
PRINT "  Final label: "; ctr.GetLabel()
PRINT "  Final count: "; ctr.GetCount()
IF ctr.GetCount() = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected count 1"
END IF

' --- Test 11: Nested loop with objects created outer, used inner ---
' Object allocated in outer loop; inner loop reads from it.
' Tests that outer-scope objects remain valid during inner scope work.
PRINT ""
PRINT "Test 11: Outer-allocated objects used in inner loops"
DIM total11 AS INTEGER
total11 = 0
DIM outer AS INTEGER
DIM innerv AS INTEGER
FOR outer = 1 TO 50
  DIM outerItem AS Item = NEW Item(outer, "outer")
  FOR innerv = 1 TO 20
    DIM innerVal AS INTEGER
    innerVal = outerItem.GetID() + innerv
    total11 = total11 + innerVal
  NEXT innerv
NEXT outer
' total = sum over outer=1..50 of sum over inner=1..20 of (outer + inner)
'       = sum over outer of (20*outer + sum(1..20))
'       = sum over outer of (20*outer + 210)
'       = 20 * sum(1..50) + 50 * 210
'       = 20 * 1275 + 10500
'       = 25500 + 10500 = 36000
PRINT "  Total: "; total11
IF total11 = 36000 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 36000"
END IF

' --- Test 12: Triple nested METHOD return chain ---
' Factory.BuildItem calls Factory.Build which creates Container,
' then Container.MakeItem creates Item. 200 iterations.
PRINT ""
PRINT "Test 12: 200 triple-nested METHOD return chains"
DIM lastChain AS Item
DIM total12 AS INTEGER
total12 = 0
DIM i12 AS INTEGER
FOR i12 = 1 TO 200
  lastChain = factory.BuildItem(i12, i12 * 2)
  total12 = total12 + lastChain.GetID()
NEXT i12
' Each BuildItem returns Item with ID = i%*2
' sum of 2,4,6,...,400 = 2 * sum(1..200) = 2 * 20100 = 40200
PRINT "  Sum of IDs: "; total12
IF total12 = 40200 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 40200"
END IF

' --- Test 13: Repeated recursive creation (scope reuse after unwind) ---
' Call RecursiveCreate 15 times, each with depth 40.
' Verifies scopes are properly cleaned and reusable after deep unwinding.
PRINT ""
PRINT "Test 13: 15 repeated deep recursive creates (scope reuse)"
DIM total13 AS INTEGER
total13 = 0
DIM rep AS INTEGER
FOR rep = 1 TO 15
  DIM rItem AS Item = RecursiveCreate(1, 40)
  total13 = total13 + rItem.GetID()
NEXT rep
' RecursiveCreate(1,40) returns sum(1..40) = 820
' 15 * 820 = 12300
PRINT "  Total: "; total13
IF total13 = 12300 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 12300"
END IF

' --- Test 14: Interleaved create, use, delete, create ---
' Simulates a real-world pattern where objects are created, used briefly,
' some are explicitly freed, and new ones take their place.
PRINT ""
PRINT "Test 14: 300 interleaved create/delete/create cycles"
DIM total14 AS INTEGER
total14 = 0
DIM i14 AS INTEGER
FOR i14 = 1 TO 300
  ' Create first object
  DIM a AS Item = NEW Item(i14, "first")
  total14 = total14 + a.GetID()

  ' Create second object, delete first
  DIM b AS Item = NEW Item(i14 * 10, "second")
  DELETE a

  ' Use second object (first is gone)
  total14 = total14 + b.GetID()

  ' Create third, let second be cleaned by scope exit
  DIM c AS Item = NEW Item(i14 * 100, "third")
  total14 = total14 + c.GetID()
NEXT i14
' Per iteration: i + 10i + 100i = 111i
' sum = 111 * sum(1..300) = 111 * 45150 = 5011650
PRINT "  Total: "; total14
IF total14 = 5011650 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 5011650"
END IF

' --- Test 15: Object with string member, string survives after object DELETE ---
' Create an Item, extract its string Name, then DELETE the Item.
' The extracted string should still be valid (separate descriptor).
PRINT ""
PRINT "Test 15: String extraction before DELETE (500 cycles)"
DIM extractOk AS INTEGER
extractOk = 1
DIM i15 AS INTEGER
FOR i15 = 1 TO 500
  DIM srcItem AS Item = NEW Item(i15, "extract_" + STR$(i15))
  DIM extractedName AS STRING
  extractedName = srcItem.GetName()
  DELETE srcItem
  ' The extracted string should still be accessible
  IF LEN(extractedName) < 1 THEN
    extractOk = 0
  END IF
NEXT i15
IF extractOk = 1 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL: extracted string corrupted after DELETE"
END IF

' --- Test 16: Stress the Bloom filter with many freed addresses ---
' DELETE 1000 objects, then allocate 1000 more. The Bloom filter
' tracks freed addresses; new allocations should not false-positive.
PRINT ""
PRINT "Test 16: 1000 DELETE + 1000 new allocs (Bloom filter stress)"
DIM i16a AS INTEGER
FOR i16a = 1 TO 1000
  DIM dItem AS Item = NEW Item(i16a, "bloom")
  DELETE dItem
NEXT i16a
DIM bloomTotal AS INTEGER
bloomTotal = 0
DIM i16b AS INTEGER
FOR i16b = 1 TO 1000
  DIM nItem AS Item = NEW Item(i16b, "fresh")
  bloomTotal = bloomTotal + nItem.GetID()
NEXT i16b
' sum of 1..1000 = 500500
PRINT "  Sum: "; bloomTotal
IF bloomTotal = 500500 THEN
  PRINT "  PASS"
ELSE
  PRINT "  FAIL expected 500500"
END IF

PRINT ""
PRINT "=== All cross-scope stress tests passed ==="
END
