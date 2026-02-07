10 REM Test: FOR EACH / FOR...IN loop support
20 REM Tests basic array iteration with FOR EACH syntax
30 REM Expected: All tests should print PASS

100 REM === Test 1: Basic FOR EACH over integer array ===
110 PRINT "=== Test 1: FOR EACH integer array ==="
120 DIM nums(4) AS INTEGER
130 nums(0) = 10
140 nums(1) = 20
150 nums(2) = 30
160 nums(3) = 40
170 nums(4) = 50
180 DIM sum1 AS INTEGER
190 sum1 = 0
200 FOR EACH n IN nums
210   sum1 = sum1 + n
220 NEXT
230 PRINT "Sum = "; sum1
240 IF sum1 = 150 THEN PRINT "TEST1 PASS" ELSE PRINT "TEST1 FAIL"

300 REM === Test 2: FOR EACH over double array ===
310 PRINT ""
320 PRINT "=== Test 2: FOR EACH double array ==="
330 DIM vals(2) AS DOUBLE
340 vals(0) = 1.5
350 vals(1) = 2.5
360 vals(2) = 3.0
370 DIM sum2 AS DOUBLE
380 sum2 = 0.0
390 FOR EACH v IN vals
400   sum2 = sum2 + v
410 NEXT
420 PRINT "Sum = "; sum2
430 IF sum2 = 7.0 THEN PRINT "TEST2 PASS" ELSE PRINT "TEST2 FAIL"

500 REM === Test 3: FOR...IN with index variable ===
510 PRINT ""
520 PRINT "=== Test 3: FOR...IN with index ==="
530 DIM letters(3) AS INTEGER
540 letters(0) = 65
550 letters(1) = 66
560 letters(2) = 67
570 letters(3) = 68
580 DIM idxSum AS INTEGER
590 DIM valSum AS INTEGER
600 idxSum = 0
610 valSum = 0
620 FOR item, idx IN letters
630   idxSum = idxSum + idx
640   valSum = valSum + item
650 NEXT
660 PRINT "Index sum = "; idxSum; ", Value sum = "; valSum
670 IF idxSum = 6 AND valSum = 266 THEN PRINT "TEST3 PASS" ELSE PRINT "TEST3 FAIL"

700 REM === Test 4: FOR EACH with single element ===
710 PRINT ""
720 PRINT "=== Test 4: Single element array ==="
730 DIM one(1) AS INTEGER
740 one(0) = 99
750 one(1) = 77
760 DIM count4 AS INTEGER
770 DIM val4 AS INTEGER
780 count4 = 0
790 val4 = 0
800 FOR EACH s IN one
810   count4 = count4 + 1
820   val4 = val4 + s
830 NEXT
840 PRINT "Count = "; count4; ", Value sum = "; val4
850 IF count4 = 2 AND val4 = 176 THEN PRINT "TEST4 PASS" ELSE PRINT "TEST4 FAIL"

900 REM === Test 5: FOR EACH body modifies external variable ===
910 PRINT ""
920 PRINT "=== Test 5: Body modifies external var ==="
930 DIM arr5(4) AS INTEGER
940 arr5(0) = 5
950 arr5(1) = 3
960 arr5(2) = 8
970 arr5(3) = 1
980 arr5(4) = 6
990 DIM maxVal AS INTEGER
1000 maxVal = 0
1010 FOR EACH d IN arr5
1020   IF d > maxVal THEN maxVal = d
1030 NEXT
1040 PRINT "Max = "; maxVal
1050 IF maxVal = 8 THEN PRINT "TEST5 PASS" ELSE PRINT "TEST5 FAIL"

1100 REM === Test 6: Nested FOR EACH ===
1110 PRINT ""
1120 PRINT "=== Test 6: FOR EACH followed by FOR EACH ==="
1130 DIM a1(2) AS INTEGER
1140 a1(0) = 1
1150 a1(1) = 2
1160 a1(2) = 3
1170 DIM a2(2) AS INTEGER
1180 a2(0) = 10
1190 a2(1) = 20
1200 a2(2) = 30
1210 DIM sumA AS INTEGER
1220 DIM sumB AS INTEGER
1230 sumA = 0
1240 sumB = 0
1250 FOR EACH x IN a1
1260   sumA = sumA + x
1270 NEXT
1280 FOR EACH y IN a2
1290   sumB = sumB + y
1300 NEXT
1310 PRINT "Sum A = "; sumA; ", Sum B = "; sumB
1320 IF sumA = 6 AND sumB = 60 THEN PRINT "TEST6 PASS" ELSE PRINT "TEST6 FAIL"

1400 REM === Test 7: FOR...IN (without EACH keyword) ===
1410 PRINT ""
1420 PRINT "=== Test 7: FOR...IN syntax (no EACH) ==="
1430 DIM scores(3) AS INTEGER
1440 scores(0) = 85
1450 scores(1) = 92
1460 scores(2) = 78
1470 scores(3) = 95
1480 DIM total7 AS INTEGER
1490 total7 = 0
1500 FOR sc IN scores
1510   total7 = total7 + sc
1520 NEXT
1530 PRINT "Total = "; total7
1540 IF total7 = 350 THEN PRINT "TEST7 PASS" ELSE PRINT "TEST7 FAIL"

1600 PRINT ""
1610 PRINT "=== Test 8: Nested FOR EACH ==="
1620 DIM outer(2) AS INTEGER
1630 outer(0) = 1
1640 outer(1) = 2
1650 outer(2) = 3
1660 DIM inner(1) AS INTEGER
1670 inner(0) = 10
1680 inner(1) = 100
1690 DIM crossSum AS INTEGER
1700 crossSum = 0
1710 FOR EACH ov IN outer
1720   FOR EACH iv IN inner
1730     crossSum = crossSum + ov * iv
1740   NEXT
1750 NEXT
1760 REM Expected: (1*10+1*100) + (2*10+2*100) + (3*10+3*100) = 110+220+330 = 660
1770 PRINT "Cross sum = "; crossSum
1780 IF crossSum = 660 THEN PRINT "TEST8 PASS" ELSE PRINT "TEST8 FAIL"

1800 PRINT ""
1810 PRINT "=== Test 9: EXIT FOR inside FOR EACH ==="
1820 DIM big(5) AS INTEGER
1830 big(0) = 2
1840 big(1) = 4
1850 big(2) = 99
1860 big(3) = 6
1870 big(4) = 8
1880 big(5) = 10
1890 DIM partialSum AS INTEGER
1900 partialSum = 0
1910 FOR EACH b IN big
1920   IF b > 50 THEN EXIT FOR
1930   partialSum = partialSum + b
1940 NEXT
1950 REM Expected: 2 + 4 = 6 (exits when 99 > 50)
1960 PRINT "Partial sum = "; partialSum
1970 IF partialSum = 6 THEN PRINT "TEST9 PASS" ELSE PRINT "TEST9 FAIL"

2000 PRINT ""
2010 PRINT "=== Test 10: FOR EACH with nested index ==="
2020 DIM matrix(2) AS INTEGER
2030 matrix(0) = 5
2040 matrix(1) = 15
2050 matrix(2) = 25
2060 DIM weightedSum AS INTEGER
2070 weightedSum = 0
2080 FOR elem, ei IN matrix
2090   weightedSum = weightedSum + elem * (ei + 1)
2100 NEXT
2110 REM Expected: 5*1 + 15*2 + 25*3 = 5 + 30 + 75 = 110
2120 PRINT "Weighted sum = "; weightedSum
2130 IF weightedSum = 110 THEN PRINT "TEST10 PASS" ELSE PRINT "TEST10 FAIL"

2200 PRINT ""
2210 PRINT "All FOR EACH tests complete."
2220 END
