10 TYPE Inner
20   Value AS INTEGER
30 END TYPE
40 TYPE Outer
50   Data AS Inner
60   Count AS INTEGER
70 END TYPE
80 DIM Items(2) AS Outer
90 Items(0).Data.Value = 100
100 Items(0).Count = 1
110 Items(1).Data.Value = 200
120 Items(1).Count = 2
130 PRINT "Item 0: Value="; Items(0).Data.Value; ", Count="; Items(0).Count
140 PRINT "Item 1: Value="; Items(1).Data.Value; ", Count="; Items(1).Count
150 IF Items(0).Data.Value = 100 AND Items(1).Count = 2 THEN PRINT "PASS" ELSE PRINT "FAIL"
160 END
