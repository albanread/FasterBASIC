10 REM Test: Nested UDT
20 TYPE Inner
30   Value AS INTEGER
40 END TYPE
50 TYPE Outer
60   Item AS Inner
70 END TYPE
80 DIM O AS Outer
90 O.Item.Value = 99
100 PRINT "O.Item.Value = "; O.Item.Value
110 IF O.Item.Value = 99 THEN PRINT "PASS" ELSE PRINT "FAIL"
120 END
