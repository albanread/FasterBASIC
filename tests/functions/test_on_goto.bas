10 REM Test: ON GOTO Statement
20 PRINT "=== ON GOTO Tests ==="
30 PRINT ""
40 REM Test 1: Basic ON GOTO with index 1
50 LET INDEX% = 1
60 ON INDEX% GOTO 1000, 2000, 3000
70 PRINT "ERROR: ON GOTO fell through (index 1)"
80 END
1000 REM Target 1
1010 PRINT "PASS: ON GOTO index 1 reached target 1"
1020 GOTO 100
2000 REM Target 2
2010 PRINT "ERROR: Reached target 2 instead of target 1"
2020 END
3000 REM Target 3
3010 PRINT "ERROR: Reached target 3 instead of target 1"
3020 END
100 REM Test 2: ON GOTO with index 2
110 LET INDEX% = 2
120 ON INDEX% GOTO 1100, 2100, 3100
130 PRINT "ERROR: ON GOTO fell through (index 2)"
140 END
1100 REM Target 1 for test 2
1110 PRINT "ERROR: Reached target 1 instead of target 2"
1120 END
2100 REM Target 2 for test 2
2110 PRINT "PASS: ON GOTO index 2 reached target 2"
2120 GOTO 200
3100 REM Target 3 for test 2
3110 PRINT "ERROR: Reached target 3 instead of target 2"
3120 END
200 REM Test 3: ON GOTO with index 3
210 LET INDEX% = 3
220 ON INDEX% GOTO 1200, 2200, 3200
230 PRINT "ERROR: ON GOTO fell through (index 3)"
240 END
1200 REM Target 1 for test 3
1210 PRINT "ERROR: Reached target 1 instead of target 3"
1220 END
2200 REM Target 2 for test 3
2210 PRINT "ERROR: Reached target 2 instead of target 3"
2220 END
3200 REM Target 3 for test 3
3210 PRINT "PASS: ON GOTO index 3 reached target 3"
3220 GOTO 300
300 REM Test 4: ON GOTO with computed expression
310 LET A% = 5
320 LET B% = 3
330 ON A% - B% GOTO 1300, 2300, 3300
340 PRINT "ERROR: ON GOTO with expression fell through"
350 END
1300 REM Target 1 for test 4
1310 PRINT "ERROR: Expression computed to 1 instead of 2"
1320 END
2300 REM Target 2 for test 4
2310 PRINT "PASS: ON GOTO with expression (5-3=2) works"
2320 GOTO 400
3300 REM Target 3 for test 4
3310 PRINT "ERROR: Expression computed to 3 instead of 2"
3320 END
400 REM Test 5: ON GOTO with index 0 (should fall through)
410 LET INDEX% = 0
420 ON INDEX% GOTO 1400, 2400, 3400
430 PRINT "PASS: ON GOTO with index 0 falls through"
440 GOTO 500
1400 REM Target 1 for test 5
1410 PRINT "ERROR: Index 0 jumped to target 1"
1420 END
2400 REM Target 2 for test 5
2410 PRINT "ERROR: Index 0 jumped to target 2"
2420 END
3400 REM Target 3 for test 5
3410 PRINT "ERROR: Index 0 jumped to target 3"
3420 END
500 REM Test 6: ON GOTO with index > number of targets (should fall through)
510 LET INDEX% = 5
520 ON INDEX% GOTO 1500, 2500, 3500
530 PRINT "PASS: ON GOTO with out-of-range index falls through"
540 GOTO 600
1500 REM Target 1 for test 6
1510 PRINT "ERROR: Out-of-range index jumped to target 1"
1520 END
2500 REM Target 2 for test 6
2510 PRINT "ERROR: Out-of-range index jumped to target 2"
2520 END
3500 REM Target 3 for test 6
3510 PRINT "ERROR: Out-of-range index jumped to target 3"
3520 END
600 REM Test 7: ON GOTO with negative index (should fall through)
610 LET INDEX% = -1
620 ON INDEX% GOTO 1600, 2600
630 PRINT "PASS: ON GOTO with negative index falls through"
640 GOTO 700
1600 REM Target 1 for test 7
1610 PRINT "ERROR: Negative index jumped to target 1"
1620 END
2600 REM Target 2 for test 7
2610 PRINT "ERROR: Negative index jumped to target 2"
2620 END
700 REM Test 8: ON GOTO with single target
710 LET INDEX% = 1
720 ON INDEX% GOTO 1700
730 PRINT "ERROR: Single-target ON GOTO fell through"
740 END
1700 REM Single target for test 8
1710 PRINT "PASS: ON GOTO with single target works"
1720 GOTO 800
800 REM Test 9: ON GOTO with many targets
810 LET INDEX% = 5
820 ON INDEX% GOTO 1800, 2800, 3800, 4800, 5800, 6800
830 PRINT "ERROR: Many-target ON GOTO fell through"
840 END
1800 REM Target 1 for test 9
1810 PRINT "ERROR: Reached target 1 instead of target 5"
1820 END
2800 REM Target 2 for test 9
2810 PRINT "ERROR: Reached target 2 instead of target 5"
2820 END
3800 REM Target 3 for test 9
3810 PRINT "ERROR: Reached target 3 instead of target 5"
3820 END
4800 REM Target 4 for test 9
4810 PRINT "ERROR: Reached target 4 instead of target 5"
4820 END
5800 REM Target 5 for test 9
5810 PRINT "PASS: ON GOTO with many targets (index 5)"
5820 GOTO 900
6800 REM Target 6 for test 9
6810 PRINT "ERROR: Reached target 6 instead of target 5"
6820 END
900 REM Test 10: ON GOTO with expression involving MOD
910 LET N% = 17
920 ON (N% MOD 3) + 1 GOTO 1900, 2900, 3900
930 PRINT "ERROR: ON GOTO with MOD expression fell through"
940 END
1900 REM Target 1 for test 10
1910 PRINT "ERROR: MOD expression computed to 1"
1920 END
2900 REM Target 2 for test 10
2910 REM 17 MOD 3 = 2, plus 1 = 3
2920 PRINT "ERROR: MOD expression computed to 2"
2930 END
3900 REM Target 3 for test 10
3910 REM 17 MOD 3 = 2, plus 1 = 3
3920 PRINT "PASS: ON GOTO with MOD expression works"
3930 GOTO 9000
9000 REM All tests passed
9010 PRINT ""
9020 PRINT "=== All ON GOTO Tests PASSED ==="
9030 END
