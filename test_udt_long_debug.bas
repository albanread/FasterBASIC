TYPE BigNumber
  Value AS LONG
  Count AS LONG
END TYPE
DIM Big AS BigNumber
Big.Value = 9999999999
Big.Count = 123456789
PRINT "Big.Value = "; Big.Value
PRINT "Big.Count = "; Big.Count

IF Big.Value = 9999999999 THEN PRINT "Value check: PASS" ELSE PRINT "Value check: FAIL"
IF Big.Count = 123456789 THEN PRINT "Count check: PASS" ELSE PRINT "Count check: FAIL"

IF Big.Value = 9999999999 AND Big.Count = 123456789 THEN
  PRINT "Combined: PASS"
ELSE
  PRINT "Combined: FAIL"
END IF
END
