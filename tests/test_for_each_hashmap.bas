10 REM Test: FOR EACH / FOR...IN over HASHMAP collections
20 REM Tests hashmap key iteration, key+value pairs, nested loops, EXIT FOR
30 REM Expected: All tests should print PASS

100 REM === Test 1: FOR EACH over hashmap keys ===
110 PRINT "=== Test 1: FOR EACH hashmap keys ==="
120 DIM dict1 AS HASHMAP
130 dict1("apple") = "red"
140 dict1("banana") = "yellow"
150 dict1("grape") = "purple"
160 DIM keyCount AS INTEGER
170 keyCount = 0
180 FOR EACH k IN dict1
190   keyCount = keyCount + 1
200 NEXT
210 PRINT "Key count = "; keyCount
220 IF keyCount = 3 THEN PRINT "TEST1 PASS" ELSE PRINT "TEST1 FAIL"

300 REM === Test 2: FOR key, value IN hashmap ===
310 PRINT ""
320 PRINT "=== Test 2: FOR key, value IN hashmap ==="
330 DIM dict2 AS HASHMAP
340 dict2("x") = "10"
350 dict2("y") = "20"
360 DIM kvCount AS INTEGER
370 kvCount = 0
380 FOR k2, v2 IN dict2
390   PRINT "  "; k2; " = "; v2
400   kvCount = kvCount + 1
410 NEXT
420 PRINT "Pair count = "; kvCount
430 IF kvCount = 2 THEN PRINT "TEST2 PASS" ELSE PRINT "TEST2 FAIL"

500 REM === Test 3: Verify key values match lookup ===
510 PRINT ""
520 PRINT "=== Test 3: Key values match lookup ==="
530 DIM dict3 AS HASHMAP
540 dict3("name") = "Alice"
550 dict3("city") = "Portland"
560 DIM matchCount AS INTEGER
570 matchCount = 0
580 FOR k3, v3 IN dict3
590   IF dict3(k3) = v3 THEN matchCount = matchCount + 1
600 NEXT
610 PRINT "Matches = "; matchCount
620 IF matchCount = 2 THEN PRINT "TEST3 PASS" ELSE PRINT "TEST3 FAIL"

700 REM === Test 4: EXIT FOR inside FOR EACH hashmap ===
710 PRINT ""
720 PRINT "=== Test 4: EXIT FOR in hashmap loop ==="
730 DIM dict4 AS HASHMAP
740 dict4("a") = "1"
750 dict4("b") = "2"
760 dict4("c") = "3"
770 dict4("d") = "4"
780 dict4("e") = "5"
790 DIM earlyCount AS INTEGER
800 earlyCount = 0
810 FOR EACH k4 IN dict4
820   earlyCount = earlyCount + 1
830   IF earlyCount >= 3 THEN EXIT FOR
840 NEXT
850 PRINT "Early exit count = "; earlyCount
860 IF earlyCount = 3 THEN PRINT "TEST4 PASS" ELSE PRINT "TEST4 FAIL"

900 REM === Test 5: Empty hashmap ===
910 PRINT ""
920 PRINT "=== Test 5: Empty hashmap ==="
930 DIM dict5 AS HASHMAP
940 DIM emptyCount AS INTEGER
950 emptyCount = 0
960 FOR EACH k5 IN dict5
970   emptyCount = emptyCount + 1
980 NEXT
990 PRINT "Empty count = "; emptyCount
1000 IF emptyCount = 0 THEN PRINT "TEST5 PASS" ELSE PRINT "TEST5 FAIL"

1100 REM === Test 6: Single-entry hashmap ===
1110 PRINT ""
1120 PRINT "=== Test 6: Single-entry hashmap ==="
1130 DIM dict6 AS HASHMAP
1140 dict6("only") = "one"
1150 DIM singleKey AS STRING
1160 DIM singleVal AS STRING
1170 singleKey = ""
1180 singleVal = ""
1190 FOR k6, v6 IN dict6
1200   singleKey = k6
1210   singleVal = v6
1220 NEXT
1230 PRINT "Key = "; singleKey; ", Value = "; singleVal
1240 IF singleKey = "only" AND singleVal = "one" THEN PRINT "TEST6 PASS" ELSE PRINT "TEST6 FAIL"

1300 REM === Test 7: FOR EACH hashmap then FOR EACH array (mixed) ===
1310 PRINT ""
1320 PRINT "=== Test 7: Mixed hashmap + array FOR EACH ==="
1330 DIM dict7 AS HASHMAP
1340 dict7("p") = "100"
1350 dict7("q") = "200"
1360 DIM arr7(2) AS INTEGER
1370 arr7(0) = 10
1380 arr7(1) = 20
1390 arr7(2) = 30
1400 DIM hcount AS INTEGER
1410 DIM asum AS INTEGER
1420 hcount = 0
1430 asum = 0
1440 FOR EACH hk IN dict7
1450   hcount = hcount + 1
1460 NEXT
1470 FOR EACH av IN arr7
1480   asum = asum + av
1490 NEXT
1500 PRINT "Hashmap keys = "; hcount; ", Array sum = "; asum
1510 IF hcount = 2 AND asum = 60 THEN PRINT "TEST7 PASS" ELSE PRINT "TEST7 FAIL"

1600 REM === Test 8: Nested FOR EACH hashmap inside array loop ===
1610 PRINT ""
1620 PRINT "=== Test 8: Nested hashmap in array loop ==="
1630 DIM names(2) AS INTEGER
1640 names(0) = 1
1650 names(1) = 2
1660 names(2) = 3
1670 DIM lookup AS HASHMAP
1680 lookup("cat") = "meow"
1690 lookup("dog") = "woof"
1700 DIM outerCount AS INTEGER
1710 DIM innerCount AS INTEGER
1720 outerCount = 0
1730 innerCount = 0
1740 FOR EACH ni IN names
1750   outerCount = outerCount + 1
1760   FOR EACH lk IN lookup
1770     innerCount = innerCount + 1
1780   NEXT
1790 NEXT
1800 REM Expected: outer=3, inner=3*2=6
1810 PRINT "Outer = "; outerCount; ", Inner = "; innerCount
1820 IF outerCount = 3 AND innerCount = 6 THEN PRINT "TEST8 PASS" ELSE PRINT "TEST8 FAIL"

1900 PRINT ""
1910 PRINT "All FOR EACH hashmap tests complete."
1920 END
