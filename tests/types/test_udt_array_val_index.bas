REM Test: UDT array access with VAL-derived indices
REM Regression test for QBE ARM64 miscompilation where the
REM index*element_size multiplication is dropped on the second
REM and subsequent field accesses when the index originates
REM from a float-to-int conversion (dtosi), as happens with VAL().
REM
REM This test exercises multiple field accesses on the same
REM array element using indices derived from VAL(), INT(),
REM direct assignment, and literal values to ensure all paths
REM produce correct results.

TYPE Item
  Label AS STRING
  Value AS INTEGER
  Tag AS STRING
END TYPE

DIM Items(9) AS Item

REM Populate several elements
Items(0).Label = "Zero"
Items(0).Value = 100
Items(0).Tag = "tag0"

Items(1).Label = "One"
Items(1).Value = 200
Items(1).Tag = "tag1"

Items(2).Label = "Two"
Items(2).Value = 300
Items(2).Tag = "tag2"

Items(3).Label = "Three"
Items(3).Value = 400
Items(3).Tag = "tag3"

REM =============================================
REM Test 1: Literal index - all three fields
REM =============================================
IF Items(2).Label <> "Two" THEN
  PRINT "ERROR: Test 1a - literal index Label wrong"
  END
ENDIF
IF Items(2).Value <> 300 THEN
  PRINT "ERROR: Test 1b - literal index Value wrong"
  END
ENDIF
IF Items(2).Tag <> "tag2" THEN
  PRINT "ERROR: Test 1c - literal index Tag wrong"
  END
ENDIF
PRINT "Test 1: PASS (literal index, 3 fields)"

REM =============================================
REM Test 2: Direct integer variable index
REM =============================================
DIM DirectIdx AS INTEGER
DirectIdx = 1
IF Items(DirectIdx).Label <> "One" THEN
  PRINT "ERROR: Test 2a - direct index Label wrong"
  END
ENDIF
IF Items(DirectIdx).Value <> 200 THEN
  PRINT "ERROR: Test 2b - direct index Value wrong"
  END
ENDIF
IF Items(DirectIdx).Tag <> "tag1" THEN
  PRINT "ERROR: Test 2c - direct index Tag wrong"
  END
ENDIF
PRINT "Test 2: PASS (direct integer index, 3 fields)"

REM =============================================
REM Test 3: VAL-derived index (triggers dtosi)
REM This is the primary regression target.
REM =============================================
DIM ValIdx AS INTEGER
ValIdx = VAL("3")
IF Items(ValIdx).Label <> "Three" THEN
  PRINT "ERROR: Test 3a - VAL index Label wrong, got: "; Items(ValIdx).Label
  END
ENDIF
IF Items(ValIdx).Value <> 400 THEN
  PRINT "ERROR: Test 3b - VAL index Value wrong, got: "; Items(ValIdx).Value
  END
ENDIF
IF Items(ValIdx).Tag <> "tag3" THEN
  PRINT "ERROR: Test 3c - VAL index Tag wrong, got: "; Items(ValIdx).Tag
  END
ENDIF
PRINT "Test 3: PASS (VAL-derived index, 3 fields)"

REM =============================================
REM Test 4: VAL-derived index with element 0
REM Edge case: index 0 where mul produces 0
REM =============================================
DIM ZeroIdx AS INTEGER
ZeroIdx = VAL("0")
IF Items(ZeroIdx).Label <> "Zero" THEN
  PRINT "ERROR: Test 4a - VAL(0) Label wrong"
  END
ENDIF
IF Items(ZeroIdx).Value <> 100 THEN
  PRINT "ERROR: Test 4b - VAL(0) Value wrong"
  END
ENDIF
IF Items(ZeroIdx).Tag <> "tag0" THEN
  PRINT "ERROR: Test 4c - VAL(0) Tag wrong"
  END
ENDIF
PRINT "Test 4: PASS (VAL-derived zero index, 3 fields)"

REM =============================================
REM Test 5: INT() derived index (also uses dtosi)
REM =============================================
DIM IntIdx AS INTEGER
DIM TmpDbl AS DOUBLE
TmpDbl = 2.7
IntIdx = INT(TmpDbl)
IF Items(IntIdx).Label <> "Two" THEN
  PRINT "ERROR: Test 5a - INT() index Label wrong"
  END
ENDIF
IF Items(IntIdx).Value <> 300 THEN
  PRINT "ERROR: Test 5b - INT() index Value wrong"
  END
ENDIF
IF Items(IntIdx).Tag <> "tag2" THEN
  PRINT "ERROR: Test 5c - INT() index Tag wrong"
  END
ENDIF
PRINT "Test 5: PASS (INT-derived index, 3 fields)"

REM =============================================
REM Test 6: Multiple different VAL indices in sequence
REM Ensures cache invalidation works correctly
REM =============================================
DIM SeqIdx AS INTEGER
SeqIdx = VAL("0")
IF Items(SeqIdx).Label <> "Zero" THEN
  PRINT "ERROR: Test 6a - sequential VAL(0) Label wrong"
  END
ENDIF
IF Items(SeqIdx).Value <> 100 THEN
  PRINT "ERROR: Test 6b - sequential VAL(0) Value wrong"
  END
ENDIF

SeqIdx = VAL("2")
IF Items(SeqIdx).Label <> "Two" THEN
  PRINT "ERROR: Test 6c - sequential VAL(2) Label wrong"
  END
ENDIF
IF Items(SeqIdx).Value <> 300 THEN
  PRINT "ERROR: Test 6d - sequential VAL(2) Value wrong"
  END
ENDIF
IF Items(SeqIdx).Tag <> "tag2" THEN
  PRINT "ERROR: Test 6e - sequential VAL(2) Tag wrong"
  END
ENDIF

SeqIdx = VAL("1")
IF Items(SeqIdx).Label <> "One" THEN
  PRINT "ERROR: Test 6f - sequential VAL(1) Label wrong"
  END
ENDIF
IF Items(SeqIdx).Tag <> "tag1" THEN
  PRINT "ERROR: Test 6g - sequential VAL(1) Tag wrong"
  END
ENDIF
PRINT "Test 6: PASS (sequential VAL indices with reassignment)"

REM =============================================
REM Test 7: PRINT all fields via VAL index
REM Exercises the common PRINT pattern that originally crashed
REM =============================================
DIM PrintIdx AS INTEGER
PrintIdx = VAL("3")
PRINT "  Label: "; Items(PrintIdx).Label
PRINT "  Value: "; Items(PrintIdx).Value
PRINT "  Tag:   "; Items(PrintIdx).Tag
PRINT "Test 7: PASS (PRINT all fields via VAL index)"

REM =============================================
REM Test 8: FOR loop with array element field access
REM =============================================
DIM I AS INTEGER
FOR I = 0 TO 3
  IF Items(I).Value <> (I + 1) * 100 THEN
    PRINT "ERROR: Test 8 - FOR loop field access wrong at index "; I
    END
  ENDIF
NEXT I
PRINT "Test 8: PASS (FOR loop with field access)"

PRINT ""
PRINT "ALL TESTS PASSED"
END
