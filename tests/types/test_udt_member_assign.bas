10 REM Test: UDT assignment from nested member access
20 TYPE Inner
30   Value AS INTEGER
40   Label AS STRING
50 END TYPE
60 TYPE Outer
70   Item AS Inner
80   Count AS INTEGER
90 END TYPE
100 DIM Container AS Outer
110 DIM CopyUDT AS Inner
120 REM Set up the container with nested values
130 Container.Item.Value = 42
140 Container.Item.Label = "Hello"
150 Container.Count = 7
160 PRINT "Container.Item.Value = "; Container.Item.Value
170 PRINT "Container.Item.Label = "; Container.Item.Label
180 PRINT "Container.Count = "; Container.Count
190 REM Assign nested UDT member to another UDT variable
200 CopyUDT = Container.Item
210 PRINT "CopyUDT.Value = "; CopyUDT.Value
220 PRINT "CopyUDT.Label = "; CopyUDT.Label
230 IF CopyUDT.Value = 42 THEN PRINT "Value copy: PASS" ELSE PRINT "Value copy: FAIL"
240 IF CopyUDT.Label = "Hello" THEN PRINT "Label copy: PASS" ELSE PRINT "Label copy: FAIL"
250 REM Verify independence after copy
260 CopyUDT.Value = 100
270 CopyUDT.Label = "World"
280 IF Container.Item.Value = 42 THEN PRINT "Source unchanged value: PASS" ELSE PRINT "Source unchanged value: FAIL"
290 IF Container.Item.Label = "Hello" THEN PRINT "Source unchanged label: PASS" ELSE PRINT "Source unchanged label: FAIL"
300 IF CopyUDT.Value = 100 THEN PRINT "Modified copy value: PASS" ELSE PRINT "Modified copy value: FAIL"
310 IF CopyUDT.Label = "World" THEN PRINT "Modified copy label: PASS" ELSE PRINT "Modified copy label: FAIL"
320 END
