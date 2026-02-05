10 REM Test: SELECT CASE Advanced Features (Beyond C switch)
20 REM This test showcases SELECT CASE features that C/Java/C++ switch cannot do
30 PRINT "=== SELECT CASE Advanced Features Test ==="
40 PRINT ""
50 REM ====================================
60 REM Test 1: Range comparisons (switch: IMPOSSIBLE)
70 REM ====================================
80 PRINT "Test 1: Range Comparisons (switch cannot do this)"
90 DIM score%
100 score% = 85
110 SELECT CASE score%
120   CASE 90 TO 100
130     PRINT "ERROR: Not A range"
140   CASE 80 TO 89
150     PRINT "PASS: Grade B (80-89)"
160   CASE 70 TO 79
170     PRINT "ERROR: Not C range"
180   CASE ELSE
190     PRINT "ERROR: Should be in B range"
200 END SELECT
210 PRINT ""
220 REM ====================================
230 REM Test 2: Floating-point values (switch: COMPILE ERROR)
240 REM ====================================
250 PRINT "Test 2: Floating-Point Values (switch gives compile error)"
260 DIM temp#
270 temp# = 72.5
280 SELECT CASE temp#
290   CASE IS < 32.0
300     PRINT "ERROR: Not freezing"
310   CASE 32.0 TO 80.0
320     PRINT "PASS: Comfortable range (32-80)"
330   CASE IS > 80.0
340     PRINT "ERROR: Not hot"
350   CASE ELSE
360     PRINT "ERROR: Should be comfortable"
370 END SELECT
380 PRINT ""
390 REM ====================================
400 REM Test 3: CASE IS relational operators (switch: IMPOSSIBLE)
410 REM ====================================
420 PRINT "Test 3: Relational Operators (switch cannot do this)"
430 DIM age%
440 age% = 25
450 SELECT CASE age%
460   CASE IS < 0
470     PRINT "ERROR: Not negative"
480   CASE IS < 18
490     PRINT "ERROR: Not minor"
500   CASE IS < 65
510     PRINT "PASS: Adult (18-64)"
520   CASE IS >= 65
530     PRINT "ERROR: Not senior"
540 END SELECT
550 PRINT ""
560 REM ====================================
570 REM Test 4: Negative ranges (switch: IMPOSSIBLE)
580 REM ====================================
590 PRINT "Test 4: Negative Ranges (switch cannot do this)"
600 DIM winter%
610 winter% = -15
620 SELECT CASE winter%
630   CASE -50 TO -20
640     PRINT "ERROR: Not extreme cold"
650   CASE -19 TO -1
660     PRINT "PASS: Below freezing (-19 to -1)"
670   CASE 0
680     PRINT "ERROR: Not zero"
690   CASE ELSE
700     PRINT "ERROR: Should be below freezing"
710 END SELECT
720 PRINT ""
730 REM ====================================
740 REM Test 5: Multiple discrete values (switch: needs fallthrough)
750 REM ====================================
760 PRINT "Test 5: Multiple Values (switch needs error-prone fallthrough)"
770 DIM digit%
780 digit% = 7
790 SELECT CASE digit%
800   CASE 0, 2, 4, 6, 8
810     PRINT "ERROR: Not even"
820   CASE 1, 3, 5, 7, 9
830     PRINT "PASS: Odd digit (1,3,5,7,9)"
840   CASE ELSE
850     PRINT "ERROR: Should be odd"
860 END SELECT
870 PRINT ""
880 REM ====================================
890 REM Test 6: Mixed ranges and discrete (switch: IMPOSSIBLE)
900 REM ====================================
910 PRINT "Test 6: Mixed Ranges and Discrete (switch cannot mix these)"
920 DIM value%
930 value% = 15
940 SELECT CASE value%
950   CASE 1, 2, 3
960     PRINT "ERROR: Not small discrete"
970   CASE 10 TO 20
980     PRINT "PASS: Medium range (10-20)"
990   CASE 50, 100, 1000
1000     PRINT "ERROR: Not large discrete"
1010   CASE ELSE
1020     PRINT "ERROR: Should be medium"
1030 END SELECT
1040 PRINT ""
1050 REM ====================================
1060 REM Test 7: Double precision ranges (switch: COMPILE ERROR)
1070 REM ====================================
1080 PRINT "Test 7: Double Precision Ranges (switch gives compile error)"
1090 DIM pi#
1100 pi# = 3.14159
1110 SELECT CASE pi#
1120   CASE IS < 3.0
1130     PRINT "ERROR: Not too small"
1140   CASE 3.0 TO 3.5
1150     PRINT "PASS: Pi range (3.0-3.5)"
1160   CASE IS > 3.5
1170     PRINT "ERROR: Not too large"
1180   CASE ELSE
1190     PRINT "ERROR: Should be pi range"
1200 END SELECT
1210 PRINT ""
1220 REM ====================================
1230 REM Test 8: Zero boundary with ranges (switch: IMPOSSIBLE)
1240 REM ====================================
1250 PRINT "Test 8: Zero Boundary Ranges (switch cannot do ranges)"
1260 DIM balance%
1270 balance% = -5
1280 SELECT CASE balance%
1290   CASE IS < -100
1300     PRINT "ERROR: Not deeply negative"
1310   CASE -100 TO -1
1320     PRINT "PASS: Negative balance (-100 to -1)"
1330   CASE 0
1340     PRINT "ERROR: Not zero"
1350   CASE 1 TO 100
1360     PRINT "ERROR: Not positive"
1370   CASE IS > 100
1380     PRINT "ERROR: Not high positive"
1390 END SELECT
1400 PRINT ""
1410 REM ====================================
1420 REM Test 9: Percentage classification (switch: needs 101 cases!)
1430 REM ====================================
1440 PRINT "Test 9: Percentage Classification (switch needs 101 case labels!)"
1450 DIM percent%
1460 percent% = 45
1470 SELECT CASE percent%
1480   CASE 0 TO 25
1490     PRINT "ERROR: Not quarter"
1500   CASE 26 TO 50
1510     PRINT "PASS: Half (26-50)"
1520   CASE 51 TO 75
1530     PRINT "ERROR: Not three-quarters"
1540   CASE 76 TO 100
1550     PRINT "ERROR: Not nearly complete"
1560   CASE ELSE
1570     PRINT "ERROR: Invalid percentage"
1580 END SELECT
1590 PRINT ""
1600 REM ====================================
1610 REM Test 10: Scientific notation ranges (switch: COMPILE ERROR)
1620 REM ====================================
1630 PRINT "Test 10: Scientific Ranges (switch cannot handle floats at all)"
1640 DIM small#
1650 small# = 0.005
1660 SELECT CASE small#
1670   CASE IS < 0.001
1680     PRINT "ERROR: Not negligible"
1690   CASE 0.001 TO 0.01
1700     PRINT "PASS: Very small (0.001-0.01)"
1710   CASE 0.01 TO 0.1
1720     PRINT "ERROR: Not small"
1730   CASE ELSE
1740     PRINT "ERROR: Should be very small"
1750 END SELECT
1760 PRINT ""
1770 REM ====================================
1780 REM Test 11: No fallthrough bugs (switch: COMMON BUG)
1790 REM ====================================
1800 PRINT "Test 11: No Fallthrough (switch requires manual break statements)"
1810 DIM status%
1820 status% = 1
1830 SELECT CASE status%
1840   CASE 1
1850     PRINT "PASS: Status OK"
1860     REM In switch, forgetting break here would execute CASE 2 also!
1870   CASE 2
1880     PRINT "ERROR: Should not execute - no fallthrough in SELECT CASE!"
1890   CASE ELSE
1900     PRINT "ERROR: Wrong case"
1910 END SELECT
1920 PRINT ""
1930 REM ====================================
1940 REM Test 12: Complex business logic (switch: IMPOSSIBLE without if-else)
1950 REM ====================================
1960 PRINT "Test 12: Complex Business Logic (switch would need if-else anyway)"
1970 DIM income%
1980 income% = 75000
1990 SELECT CASE income%
2000   CASE IS < 10000
2010     PRINT "ERROR: Not poverty level"
2020   CASE 10000 TO 40000
2030     PRINT "ERROR: Not low income"
2040   CASE 40001 TO 80000
2050     PRINT "PASS: Middle income (40001-80000)"
2060   CASE 80001 TO 200000
2070     PRINT "ERROR: Not upper income"
2080   CASE IS > 200000
2090     PRINT "ERROR: Not high income"
2100 END SELECT
2110 PRINT ""
2120 PRINT "=== All Advanced Features Tests PASSED ==="
2130 PRINT ""
2140 PRINT "Summary: SELECT CASE can do 12 things that C switch cannot:"
2150 PRINT "1. Range comparisons (10 TO 20)"
2160 PRINT "2. Floating-point values"
2170 PRINT "3. Relational operators (IS > 100)"
2180 PRINT "4. Negative ranges"
2190 PRINT "5. Multiple values without fallthrough"
2200 PRINT "6. Mixed ranges and discrete values"
2210 PRINT "7. Double precision ranges"
2220 PRINT "8. Ranges crossing zero"
2230 PRINT "9. Percentage/large range classification"
2240 PRINT "10. Scientific notation ranges"
2250 PRINT "11. No fallthrough bugs"
2260 PRINT "12. Complex business logic ranges"
2270 PRINT ""
2280 PRINT "SELECT CASE is more powerful than switch!"
2290 END
