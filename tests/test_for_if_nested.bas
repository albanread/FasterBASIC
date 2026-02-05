1000 REM Test FOR loop nested inside IF statement
1010 REM This tests the CFG fix for nested control structures
1020
1030 DIM flag AS INT
1040 DIM outer AS INT
1050 DIM inner AS INT
1060
1070 PRINT "Testing FOR loop nested inside IF"
1080 PRINT ""
1090
1100 REM Test 1: FOR inside IF THEN
1110 flag = 1
1120 outer = 0
1130
1140 IF flag = 1 THEN
1150     PRINT "Inside IF, running FOR loop:"
1160     FOR inner = 1 TO 5
1170         PRINT "  inner = "; inner
1180         outer = outer + inner
1190     NEXT inner
1200     PRINT "  Sum = "; outer
1210 END IF
1220
1230 PRINT ""
1240 PRINT "After IF: outer = "; outer; " (should be 15)"
1250 PRINT ""
1260
1270 REM Test 2: FOR inside IF ELSE
1280 flag = 0
1290 outer = 0
1300
1310 IF flag = 1 THEN
1320     PRINT "This should not execute"
1330 ELSE
1340     PRINT "Inside ELSE, running FOR loop:"
1350     FOR inner = 10 TO 13
1360         PRINT "  inner = "; inner
1370         outer = outer + 1
1380     NEXT inner
1390     PRINT "  Count = "; outer
1400 END IF
1410
1420 PRINT ""
1430 PRINT "After ELSE: outer = "; outer; " (should be 4)"
1440 PRINT ""
1450
1460 REM Test 3: Nested FOR inside IF with condition
1470 PRINT "Testing conditional FOR execution:"
1480 DIM total AS INT
1490 total = 0
1500
1510 FOR outer = 1 TO 3
1520     PRINT "Outer = "; outer
1530     IF outer = 2 THEN
1540         PRINT "  Outer is 2, running inner FOR:"
1550         FOR inner = 1 TO 3
1560             PRINT "    inner = "; inner
1570             total = total + 1
1580         NEXT inner
1590     ELSE
1600         PRINT "  Outer is not 2, skipping inner loop"
1610     END IF
1620 NEXT outer
1630
1640 PRINT ""
1650 PRINT "Total iterations: "; total; " (should be 3)"
1660 PRINT ""
1670 PRINT "All tests completed successfully!"
