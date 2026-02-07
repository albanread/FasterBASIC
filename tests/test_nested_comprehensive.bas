10 REM Comprehensive nested FOR EACH test
20 REM Tests deeply nested loops: FOR > array FOR EACH > hashmap FOR EACH
30 REM and hashmap-in-hashmap nesting

100 REM === Test 1: Nested hashmap FOR EACH inside regular FOR loop ===
110 PRINT "=== Test 1: Hashmap FOR EACH inside FOR loop ==="
120 DIM colors AS HASHMAP
130 colors("red") = "FF0000"
140 colors("green") = "00FF00"
150 colors("blue") = "0000FF"
160 DIM totalKeys AS INTEGER
170 totalKeys = 0
180 FOR i = 1 TO 3
190   FOR EACH c IN colors
200     totalKeys = totalKeys + 1
210   NEXT
220 NEXT i
230 PRINT "Total key visits = "; totalKeys
240 IF totalKeys = 9 THEN PRINT "TEST1 PASS" ELSE PRINT "TEST1 FAIL"

300 REM === Test 2: FOR > array FOR EACH > hashmap FOR EACH ===
310 PRINT ""
320 PRINT "=== Test 2: FOR > array FOREACH > hashmap FOREACH ==="
330 DIM nums(1) AS INTEGER
340 nums(0) = 10
350 nums(1) = 20
360 DIM props AS HASHMAP
370 props("a") = "1"
380 props("b") = "2"
390 DIM outerCount AS INTEGER
400 DIM midCount AS INTEGER
410 DIM innerCount AS INTEGER
420 outerCount = 0
430 midCount = 0
440 innerCount = 0
450 FOR j = 1 TO 2
460   outerCount = outerCount + 1
470   FOR EACH n IN nums
480     midCount = midCount + 1
490     FOR EACH pk IN props
500       innerCount = innerCount + 1
510     NEXT
520   NEXT
530 NEXT j
540 PRINT "Outer = "; outerCount; ", Mid = "; midCount; ", Inner = "; innerCount
550 REM Expected: outer=2, mid=2*2=4, inner=2*2*2=8
560 IF outerCount = 2 AND midCount = 4 AND innerCount = 8 THEN PRINT "TEST2 PASS" ELSE PRINT "TEST2 FAIL"

600 REM === Test 3: Two sequential hashmap FOR EACH loops ===
610 PRINT ""
620 PRINT "=== Test 3: Two sequential hashmap FOR EACH ==="
630 DIM mapA AS HASHMAP
640 mapA("x") = "10"
650 mapA("y") = "20"
660 mapA("z") = "30"
670 DIM mapB AS HASHMAP
680 mapB("p") = "100"
690 mapB("q") = "200"
700 DIM countA AS INTEGER
710 DIM countB AS INTEGER
720 countA = 0
730 countB = 0
740 FOR EACH ka IN mapA
750   countA = countA + 1
760 NEXT
770 FOR EACH kb IN mapB
780   countB = countB + 1
790 NEXT
800 PRINT "Count A = "; countA; ", Count B = "; countB
810 IF countA = 3 AND countB = 2 THEN PRINT "TEST3 PASS" ELSE PRINT "TEST3 FAIL"

900 REM === Test 4: Hashmap FOR EACH nested inside another hashmap FOR EACH ===
910 PRINT ""
920 PRINT "=== Test 4: Hashmap inside hashmap FOR EACH ==="
930 DIM outer AS HASHMAP
940 outer("cat") = "meow"
950 outer("dog") = "woof"
960 DIM inner AS HASHMAP
970 inner("small") = "1"
980 inner("big") = "2"
990 inner("med") = "3"
1000 DIM outerH AS INTEGER
1010 DIM innerH AS INTEGER
1020 outerH = 0
1030 innerH = 0
1040 FOR EACH ok IN outer
1050   outerH = outerH + 1
1060   FOR EACH ik IN inner
1070     innerH = innerH + 1
1080   NEXT
1090 NEXT
1100 PRINT "Outer hashmap = "; outerH; ", Inner hashmap = "; innerH
1110 REM Expected: outer=2, inner=2*3=6
1120 IF outerH = 2 AND innerH = 6 THEN PRINT "TEST4 PASS" ELSE PRINT "TEST4 FAIL"

1200 REM === Test 5: Hashmap key-value with nested array FOR EACH ===
1210 PRINT ""
1220 PRINT "=== Test 5: Hashmap k,v with nested array FOREACH ==="
1230 DIM scores AS HASHMAP
1240 scores("alice") = "90"
1250 scores("bob") = "85"
1260 DIM weights(2) AS INTEGER
1270 weights(0) = 1
1280 weights(1) = 2
1290 weights(2) = 3
1300 DIM pairCount AS INTEGER
1310 DIM weightSum AS INTEGER
1320 pairCount = 0
1330 weightSum = 0
1340 FOR sk, sv IN scores
1350   pairCount = pairCount + 1
1360   FOR EACH w IN weights
1370     weightSum = weightSum + w
1380   NEXT
1390 NEXT
1400 PRINT "Pairs = "; pairCount; ", Weight sum = "; weightSum
1410 REM Expected: pairs=2, weightSum=2*(1+2+3)=12
1420 IF pairCount = 2 AND weightSum = 12 THEN PRINT "TEST5 PASS" ELSE PRINT "TEST5 FAIL"

1500 REM === Test 6: EXIT FOR inside nested hashmap loops ===
1510 PRINT ""
1520 PRINT "=== Test 6: EXIT FOR in nested hashmap ==="
1530 DIM outerMap AS HASHMAP
1540 outerMap("a") = "1"
1550 outerMap("b") = "2"
1560 outerMap("c") = "3"
1570 DIM innerMap AS HASHMAP
1580 innerMap("x") = "10"
1590 innerMap("y") = "20"
1600 innerMap("z") = "30"
1610 innerMap("w") = "40"
1620 DIM oVisits AS INTEGER
1630 DIM iVisits AS INTEGER
1640 oVisits = 0
1650 iVisits = 0
1660 FOR EACH om IN outerMap
1670   oVisits = oVisits + 1
1680   FOR EACH im IN innerMap
1690     iVisits = iVisits + 1
1700     IF iVisits >= 2 THEN EXIT FOR
1710   NEXT
1720   IF oVisits >= 2 THEN EXIT FOR
1730 NEXT
1740 PRINT "Outer visits = "; oVisits; ", Inner visits = "; iVisits
1750 REM First outer: inner runs, exits at iVisits=2 (2 visits)
1760 REM Second outer: inner runs, exits at iVisits=4... but outer exits after oVisits=2
1770 REM Actually iVisits is cumulative: iter1 inner does 2, iter2 inner EXIT immediately at first (iVisits=3>=2)
1780 REM So: oVisits=2, iVisits=3
1790 IF oVisits = 2 AND iVisits = 3 THEN PRINT "TEST6 PASS" ELSE PRINT "TEST6 FAIL - got oVisits="; oVisits; " iVisits="; iVisits

1900 REM === Test 7: Array FOR EACH inside array FOR EACH ===
1910 PRINT ""
1920 PRINT "=== Test 7: Array FOREACH inside array FOREACH ==="
1930 DIM arrX(2) AS INTEGER
1940 arrX(0) = 1
1950 arrX(1) = 2
1960 arrX(2) = 3
1970 DIM arrY(1) AS INTEGER
1980 arrY(0) = 10
1990 arrY(1) = 20
2000 DIM crossSum AS INTEGER
2010 crossSum = 0
2020 FOR EACH ax IN arrX
2030   FOR EACH ay IN arrY
2040     crossSum = crossSum + ax * ay
2050   NEXT
2060 NEXT
2070 PRINT "Cross sum = "; crossSum
2080 REM Expected: (1*10+1*20)+(2*10+2*20)+(3*10+3*20) = 30+60+90 = 180
2090 IF crossSum = 180 THEN PRINT "TEST7 PASS" ELSE PRINT "TEST7 FAIL"

2100 PRINT ""
2110 PRINT "All comprehensive nested tests complete."
2120 END
