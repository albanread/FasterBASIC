TYPE Inner
  Value AS INTEGER
END TYPE
TYPE Outer
  Data AS Inner
  Count AS INTEGER
END TYPE
DIM Items(2) AS Outer
Items(0).Data.Value = 100
Items(0).Count = 1
Items(1).Data.Value = 200
Items(1).Count = 2
PRINT "Item 0: Value="; Items(0).Data.Value; ", Count="; Items(0).Count
PRINT "Item 1: Value="; Items(1).Data.Value; ", Count="; Items(1).Count
IF Items(0).Data.Value = 100 AND Items(1).Count = 2 THEN PRINT "PASS" ELSE PRINT "FAIL"
END
