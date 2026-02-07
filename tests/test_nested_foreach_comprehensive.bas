10 REM Comprehensive nested FOR EACH tests
20 REM Tests: hashmap-in-FOR, hashmap-in-hashmap, hashmap-in-array, array-in-hashmap

100 DIM passed AS INTEGER
110 DIM failed AS INTEGER
120 passed = 0
130 failed = 0

200 REM === Test 1: Hashmap FOR EACH nested inside regular FOR loop ===
210 PRINT "=== Test 1: Hashmap in FOR loop ==="
220 DIM colors AS HASHMAP
230 colors("red") = "FF0000"
240 colors("blue") = "0000FF"
250 DIM outerCount AS INTEGER
260 DIM innerCount AS INTEGER
270 outerCount = 0
280 innerCount = 0
290 FOR i = 1 TO 4
300   outerCount = outerCount + 1
310   FOR EACH c IN colors
320     innerCount = innerCount + 1
330   NEXT
340 NEXT i
350 PRINT "Outer="; outerCount; " Inner="; innerCount
360 IF outerCount = 4 AND innerCount = 8 THEN PRINT "TEST1 PASS" : passed = passed + 1 ELSE PRINT "TEST1 FAIL" : failed = failed + 1

400 REM === Test 2: Hashmap FOR EACH nested inside array FOR EACH ===
410 PRINT "=== Test 2: Hashmap in array FOR EACH ==="
420 DIM scores AS HASHMAP
430 scores("math") = "90"
440 scores("art") = "85"
450 DIM nums(2) AS INTEGER
460 nums(0) = 10
470 nums(1) = 20
480 nums(2) = 30
490 DIM totalKeys AS INTEGER
500 DIM numSum AS INTEGER
510 totalKeys = 0
520 numSum = 0
530 FOR EACH n IN nums
540   numSum = numSum + n
550   FOR EACH s IN scores
560     totalKeys = totalKeys + 1
570   NEXT
580 NEXT
590 PRINT "numSum="; numSum; " totalKeys="; totalKeys
600 IF numSum = 60 AND totalKeys = 6 THEN PRINT "TEST2 PASS" : passed = passed + 1 ELSE PRINT "TEST2 FAIL" : failed = failed + 1

700 REM === Test 3: Key+value hashmap nested in FOR loop ===
710 PRINT "=== Test 3: Key+value hashmap in FOR ==="
720 DIM items AS HASHMAP
730 items("a") = "1"
740 items("b") = "2"
750 DIM kvCount AS INTEGER
760 kvCount = 0
770 FOR j = 1 TO 2
780   FOR ik, iv IN items
790     kvCount = kvCount + 1
800   NEXT
810 NEXT j
820 PRINT "kvCount="; kvCount
830 IF kvCount = 4 THEN PRINT "TEST3 PASS" : passed = passed + 1 ELSE PRINT "TEST3 FAIL" : failed = failed + 1

900 REM === Test 4: EXIT FOR inside nested hashmap loop ===
910 PRINT "=== Test 4: EXIT FOR in nested hashmap ==="
920 DIM letters AS HASHMAP
930 letters("x") = "24"
940 letters("y") = "25"
950 letters("z") = "26"
960 DIM exitCount AS INTEGER
970 exitCount = 0
980 FOR k = 1 TO 3
990   FOR EACH lt IN letters
1000    exitCount = exitCount + 1
1010    IF exitCount >= 2 * k THEN EXIT FOR
1020  NEXT
1030 NEXT k
1040 PRINT "exitCount="; exitCount
1050 IF exitCount >= 3 AND exitCount <= 9 THEN PRINT "TEST4 PASS" : passed = passed + 1 ELSE PRINT "TEST4 FAIL" : failed = failed + 1

1100 REM === Test 5: Empty hashmap nested in loop ===
1110 PRINT "=== Test 5: Empty hashmap in loop ==="
1120 DIM empty AS HASHMAP
1130 DIM emptyCount AS INTEGER
1140 emptyCount = 0
1150 FOR m = 1 TO 5
1160   FOR EACH em IN empty
1170     emptyCount = emptyCount + 1
1180   NEXT
1190 NEXT m
1200 PRINT "emptyCount="; emptyCount
1210 IF emptyCount = 0 THEN PRINT "TEST5 PASS" : passed = passed + 1 ELSE PRINT "TEST5 FAIL" : failed = failed + 1

1300 REM === Test 6: Deeply nested - FOR > FOR EACH array > FOR EACH hashmap ===
1310 PRINT "=== Test 6: FOR > array FOREACH > hashmap FOREACH ==="
1320 DIM tags AS HASHMAP
1330 tags("t1") = "tag1"
1340 tags("t2") = "tag2"
1350 DIM vals(1) AS INTEGER
1360 vals(0) = 100
1370 vals(1) = 200
1380 DIM deepCount AS INTEGER
1390 deepCount = 0
1400 FOR p = 1 TO 2
1410   FOR EACH v IN vals
1420     FOR EACH tg IN tags
1430       deepCount = deepCount + 1
1440     NEXT
1450   NEXT
1460 NEXT p
1470 PRINT "deepCount="; deepCount
1480 IF deepCount = 8 THEN PRINT "TEST6 PASS" : passed = passed + 1 ELSE PRINT "TEST6 FAIL" : failed = failed + 1

1500 REM === Test 7: Two consecutive hashmap loops inside a FOR ===
1510 PRINT "=== Test 7: Two consecutive hashmap loops in FOR ==="
1520 DIM mapA AS HASHMAP
1530 DIM mapB AS HASHMAP
1540 mapA("one") = "1"
1550 mapA("two") = "2"
1560 mapB("alpha") = "a"
1570 mapB("beta") = "b"
1580 mapB("gamma") = "c"
1590 DIM countA AS INTEGER
1600 DIM countB AS INTEGER
1610 countA = 0
1620 countB = 0
1630 FOR q = 1 TO 3
1640   FOR EACH ma IN mapA
1650     countA = countA + 1
1660   NEXT
1670   FOR EACH mb IN mapB
1680     countB = countB + 1
1690   NEXT
1700 NEXT q
1710 PRINT "countA="; countA; " countB="; countB
1720 IF countA = 6 AND countB = 9 THEN PRINT "TEST7 PASS" : passed = passed + 1 ELSE PRINT "TEST7 FAIL" : failed = failed + 1

1800 REM === Summary ===
1810 PRINT ""
1820 PRINT "Results: "; passed; " passed, "; failed; " failed out of 7"
1830 IF failed = 0 THEN PRINT "ALL TESTS PASSED" ELSE PRINT "SOME TESTS FAILED"
1840 END
