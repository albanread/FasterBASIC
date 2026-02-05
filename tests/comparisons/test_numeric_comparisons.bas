10 REM Test: Comprehensive Numeric Comparisons
20 PRINT "=== Numeric Comparison Tests ==="
30 PRINT ""
40 REM =========================================================================
50 REM Test 1: Integer Equality
60 REM =========================================================================
70 PRINT "Test 1: Integer Equality (=)"
80 LET A% = 42
90 LET B% = 42
100 LET C% = 43
110 IF A% = B% THEN PRINT "  PASS: 42 = 42"
120 IF A% <> B% THEN PRINT "  ERROR: 42 = 42 failed" : END
130 IF A% = C% THEN PRINT "  ERROR: 42 = 43 should be false" : END
140 IF A% <> C% THEN PRINT "  PASS: 42 <> 43"
150 PRINT ""
160 REM =========================================================================
170 REM Test 2: Integer Inequality
180 REM =========================================================================
190 PRINT "Test 2: Integer Inequality (<>)"
200 LET X% = 10
210 LET Y% = 20
220 LET Z% = 10
230 IF X% <> Y% THEN PRINT "  PASS: 10 <> 20"
240 IF X% = Y% THEN PRINT "  ERROR: 10 <> 20 failed" : END
250 IF X% <> Z% THEN PRINT "  ERROR: 10 <> 10 should be false" : END
260 IF X% = Z% THEN PRINT "  PASS: 10 = 10"
270 PRINT ""
280 REM =========================================================================
290 REM Test 3: Integer Less Than
300 REM =========================================================================
310 PRINT "Test 3: Integer Less Than (<)"
320 LET P% = 5
330 LET Q% = 10
340 IF P% < Q% THEN PRINT "  PASS: 5 < 10"
350 IF P% >= Q% THEN PRINT "  ERROR: 5 < 10 failed" : END
360 IF Q% < P% THEN PRINT "  ERROR: 10 < 5 should be false" : END
370 IF Q% >= P% THEN PRINT "  PASS: NOT (10 < 5)"
380 IF P% < P% THEN PRINT "  ERROR: 5 < 5 should be false" : END
390 IF P% >= P% THEN PRINT "  PASS: NOT (5 < 5)"
400 PRINT ""
410 REM =========================================================================
420 REM Test 4: Integer Greater Than
430 REM =========================================================================
440 PRINT "Test 4: Integer Greater Than (>)"
450 LET M% = 15
460 LET N% = 10
470 IF M% > N% THEN PRINT "  PASS: 15 > 10"
480 IF M% <= N% THEN PRINT "  ERROR: 15 > 10 failed" : END
490 IF N% > M% THEN PRINT "  ERROR: 10 > 15 should be false" : END
500 IF N% <= M% THEN PRINT "  PASS: NOT (10 > 15)"
510 IF M% > M% THEN PRINT "  ERROR: 15 > 15 should be false" : END
520 IF M% <= M% THEN PRINT "  PASS: NOT (15 > 15)"
530 PRINT ""
540 REM =========================================================================
550 REM Test 5: Integer Less Than or Equal
560 REM =========================================================================
570 PRINT "Test 5: Integer Less Than or Equal (<=)"
580 LET U% = 7
590 LET V% = 12
600 LET W% = 7
610 IF U% <= V% THEN PRINT "  PASS: 7 <= 12"
620 IF U% > V% THEN PRINT "  ERROR: 7 <= 12 failed" : END
630 IF U% <= W% THEN PRINT "  PASS: 7 <= 7"
640 IF U% > W% THEN PRINT "  ERROR: 7 <= 7 failed" : END
650 IF V% <= U% THEN PRINT "  ERROR: 12 <= 7 should be false" : END
660 IF V% > U% THEN PRINT "  PASS: NOT (12 <= 7)"
670 PRINT ""
680 REM =========================================================================
690 REM Test 6: Integer Greater Than or Equal
700 REM =========================================================================
710 PRINT "Test 6: Integer Greater Than or Equal (>=)"
720 LET R% = 20
730 LET S% = 15
740 LET T% = 20
750 IF R% >= S% THEN PRINT "  PASS: 20 >= 15"
760 IF R% < S% THEN PRINT "  ERROR: 20 >= 15 failed" : END
770 IF R% >= T% THEN PRINT "  PASS: 20 >= 20"
780 IF R% < T% THEN PRINT "  ERROR: 20 >= 20 failed" : END
790 IF S% >= R% THEN PRINT "  ERROR: 15 >= 20 should be false" : END
800 IF S% < R% THEN PRINT "  PASS: NOT (15 >= 20)"
810 PRINT ""
820 REM =========================================================================
830 REM Test 7: Double Equality
840 REM =========================================================================
850 PRINT "Test 7: Double Equality (=)"
860 LET D1# = 3.14
870 LET D2# = 3.14
880 LET D3# = 3.15
890 IF D1# = D2# THEN PRINT "  PASS: 3.14 = 3.14"
900 IF D1# <> D2# THEN PRINT "  ERROR: 3.14 = 3.14 failed" : END
910 IF D1# = D3# THEN PRINT "  ERROR: 3.14 = 3.15 should be false" : END
920 IF D1# <> D3# THEN PRINT "  PASS: 3.14 <> 3.15"
930 PRINT ""
940 REM =========================================================================
950 REM Test 8: Double Inequality
960 REM =========================================================================
970 PRINT "Test 8: Double Inequality (<>)"
980 LET E1# = 2.5
990 LET E2# = 5.5
1000 LET E3# = 2.5
1010 IF E1# <> E2# THEN PRINT "  PASS: 2.5 <> 5.5"
1020 IF E1# = E2# THEN PRINT "  ERROR: 2.5 <> 5.5 failed" : END
1030 IF E1# <> E3# THEN PRINT "  ERROR: 2.5 <> 2.5 should be false" : END
1040 IF E1# = E3# THEN PRINT "  PASS: 2.5 = 2.5"
1050 PRINT ""
1060 REM =========================================================================
1070 REM Test 9: Double Less Than
1080 REM =========================================================================
1090 PRINT "Test 9: Double Less Than (<)"
1100 LET F1# = 1.5
1110 LET F2# = 2.5
1120 IF F1# < F2# THEN PRINT "  PASS: 1.5 < 2.5"
1130 IF F1# >= F2# THEN PRINT "  ERROR: 1.5 < 2.5 failed" : END
1140 IF F2# < F1# THEN PRINT "  ERROR: 2.5 < 1.5 should be false" : END
1150 IF F2# >= F1# THEN PRINT "  PASS: NOT (2.5 < 1.5)"
1160 IF F1# < F1# THEN PRINT "  ERROR: 1.5 < 1.5 should be false" : END
1170 IF F1# >= F1# THEN PRINT "  PASS: NOT (1.5 < 1.5)"
1180 PRINT ""
1190 REM =========================================================================
1200 REM Test 10: Double Greater Than
1210 REM =========================================================================
1220 PRINT "Test 10: Double Greater Than (>)"
1230 LET G1# = 10.5
1240 LET G2# = 5.25
1250 IF G1# > G2# THEN PRINT "  PASS: 10.5 > 5.25"
1260 IF G1# <= G2# THEN PRINT "  ERROR: 10.5 > 5.25 failed" : END
1270 IF G2# > G1# THEN PRINT "  ERROR: 5.25 > 10.5 should be false" : END
1280 IF G2# <= G1# THEN PRINT "  PASS: NOT (5.25 > 10.5)"
1290 IF G1# > G1# THEN PRINT "  ERROR: 10.5 > 10.5 should be false" : END
1300 IF G1# <= G1# THEN PRINT "  PASS: NOT (10.5 > 10.5)"
1310 PRINT ""
1320 REM =========================================================================
1330 REM Test 11: Double Less Than or Equal
1340 REM =========================================================================
1350 PRINT "Test 11: Double Less Than or Equal (<=)"
1360 LET H1# = 7.7
1370 LET H2# = 12.2
1380 LET H3# = 7.7
1390 IF H1# <= H2# THEN PRINT "  PASS: 7.7 <= 12.2"
1400 IF H1# > H2# THEN PRINT "  ERROR: 7.7 <= 12.2 failed" : END
1410 IF H1# <= H3# THEN PRINT "  PASS: 7.7 <= 7.7"
1420 IF H1# > H3# THEN PRINT "  ERROR: 7.7 <= 7.7 failed" : END
1430 IF H2# <= H1# THEN PRINT "  ERROR: 12.2 <= 7.7 should be false" : END
1440 IF H2# > H1# THEN PRINT "  PASS: NOT (12.2 <= 7.7)"
1450 PRINT ""
1460 REM =========================================================================
1470 REM Test 12: Double Greater Than or Equal
1480 REM =========================================================================
1490 PRINT "Test 12: Double Greater Than or Equal (>=)"
1500 LET I1# = 9.9
1510 LET I2# = 4.4
1520 LET I3# = 9.9
1530 IF I1# >= I2# THEN PRINT "  PASS: 9.9 >= 4.4"
1540 IF I1# < I2# THEN PRINT "  ERROR: 9.9 >= 4.4 failed" : END
1550 IF I1# >= I3# THEN PRINT "  PASS: 9.9 >= 9.9"
1560 IF I1# < I3# THEN PRINT "  ERROR: 9.9 >= 9.9 failed" : END
1570 IF I2# >= I1# THEN PRINT "  ERROR: 4.4 >= 9.9 should be false" : END
1580 IF I2# < I1# THEN PRINT "  PASS: NOT (4.4 >= 9.9)"
1590 PRINT ""
1600 REM =========================================================================
1610 REM Test 13: Mixed Integer and Double Comparisons
1620 REM =========================================================================
1630 PRINT "Test 13: Mixed Integer and Double Comparisons"
1640 LET J% = 5
1650 LET K# = 5.0
1660 LET L# = 5.5
1670 IF J% = K# THEN PRINT "  PASS: 5 = 5.0"
1680 IF J% <> K# THEN PRINT "  ERROR: 5 = 5.0 failed" : END
1690 IF J% < L# THEN PRINT "  PASS: 5 < 5.5"
1700 IF J% >= L# THEN PRINT "  ERROR: 5 < 5.5 failed" : END
1710 IF L# > J% THEN PRINT "  PASS: 5.5 > 5"
1720 IF L# <= J% THEN PRINT "  ERROR: 5.5 > 5 failed" : END
1730 IF J% <> L# THEN PRINT "  PASS: 5 <> 5.5"
1740 IF J% = L# THEN PRINT "  ERROR: 5 <> 5.5 failed" : END
1750 PRINT ""
1760 REM =========================================================================
1770 REM Test 14: Negative Number Comparisons
1780 REM =========================================================================
1790 PRINT "Test 14: Negative Number Comparisons"
1800 LET NEG1% = -10
1810 LET NEG2% = -5
1820 LET POS% = 5
1830 IF NEG1% < NEG2% THEN PRINT "  PASS: -10 < -5"
1840 IF NEG1% >= NEG2% THEN PRINT "  ERROR: -10 < -5 failed" : END
1850 IF NEG1% < POS% THEN PRINT "  PASS: -10 < 5"
1860 IF NEG1% >= POS% THEN PRINT "  ERROR: -10 < 5 failed" : END
1870 IF NEG2% > NEG1% THEN PRINT "  PASS: -5 > -10"
1880 IF NEG2% <= NEG1% THEN PRINT "  ERROR: -5 > -10 failed" : END
1890 IF POS% > NEG1% THEN PRINT "  PASS: 5 > -10"
1900 IF POS% <= NEG1% THEN PRINT "  ERROR: 5 > -10 failed" : END
1910 PRINT ""
1920 REM =========================================================================
1930 REM Test 15: Zero Comparisons
1940 REM =========================================================================
1950 PRINT "Test 15: Zero Comparisons"
1960 LET ZERO% = 0
1970 LET ZEROD# = 0.0
1980 LET ONE% = 1
1990 IF ZERO% = ZEROD# THEN PRINT "  PASS: 0 = 0.0"
2000 IF ZERO% <> ZEROD# THEN PRINT "  ERROR: 0 = 0.0 failed" : END
2010 IF ZERO% < ONE% THEN PRINT "  PASS: 0 < 1"
2020 IF ZERO% >= ONE% THEN PRINT "  ERROR: 0 < 1 failed" : END
2030 IF ONE% > ZERO% THEN PRINT "  PASS: 1 > 0"
2040 IF ONE% <= ZERO% THEN PRINT "  ERROR: 1 > 0 failed" : END
2050 IF ZERO% <> ONE% THEN PRINT "  PASS: 0 <> 1"
2060 IF ZERO% = ONE% THEN PRINT "  ERROR: 0 <> 1 failed" : END
2070 PRINT ""
2080 REM =========================================================================
2090 REM Test 16: Large Number Comparisons
2100 REM =========================================================================
2110 PRINT "Test 16: Large Number Comparisons"
2120 LET BIG1% = 1000000
2130 LET BIG2% = 1000001
2140 LET BIG3# = 1000000.5
2150 IF BIG1% < BIG2% THEN PRINT "  PASS: 1000000 < 1000001"
2160 IF BIG1% >= BIG2% THEN PRINT "  ERROR: Large int comparison failed" : END
2170 IF BIG1% < BIG3# THEN PRINT "  PASS: 1000000 < 1000000.5"
2180 IF BIG1% >= BIG3# THEN PRINT "  ERROR: Large mixed comparison failed" : END
2190 IF BIG2% > BIG1% THEN PRINT "  PASS: 1000001 > 1000000"
2200 IF BIG2% <= BIG1% THEN PRINT "  ERROR: Large int > failed" : END
2210 PRINT ""
2220 REM =========================================================================
2230 REM Test 17: Comparison in Expressions
2240 REM =========================================================================
2250 PRINT "Test 17: Comparisons in Expressions"
2260 LET RESULT% = (5 > 3)
2270 IF RESULT% <> 0 THEN PRINT "  PASS: (5 > 3) is true"
2280 IF RESULT% = 0 THEN PRINT "  ERROR: Comparison expression failed" : END
2290 LET RESULT2% = (2 > 8)
2300 IF RESULT2% = 0 THEN PRINT "  PASS: (2 > 8) is false"
2310 IF RESULT2% <> 0 THEN PRINT "  ERROR: False comparison expression failed" : END
2320 PRINT ""
2330 PRINT "=== All Numeric Comparison Tests PASSED ==="
2340 END
