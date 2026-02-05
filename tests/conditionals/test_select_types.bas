10 REM Test: SELECT CASE Type Handling - Edge Cases
20 PRINT "=== SELECT CASE Type Handling Tests ==="
30 PRINT ""
40 REM ====================================
50 REM Test 1: Integer SELECT, integer CASE (no conversion)
60 REM ====================================
70 PRINT "Test 1: Integer/Integer (no conversion)"
80 DIM i%
90 i% = 42
100 SELECT CASE i%
110   CASE 42
120     PRINT "PASS: Integer match"
130   CASE ELSE
140     PRINT "ERROR: Should match 42"
150 END SELECT
160 PRINT ""
170 REM ====================================
180 REM Test 2: Double SELECT, double CASE (no conversion)
190 REM ====================================
200 PRINT "Test 2: Double/Double (no conversion)"
210 DIM d#
220 d# = 3.14159
230 SELECT CASE d#
240   CASE 3.14159
250     PRINT "PASS: Double match"
260   CASE ELSE
270     PRINT "ERROR: Should match 3.14159"
280 END SELECT
290 PRINT ""
300 REM ====================================
310 REM Test 3: Integer SELECT with range (auto-convert)
320 REM ====================================
330 PRINT "Test 3: Integer SELECT with range"
340 DIM x%
350 x% = 15
360 SELECT CASE x%
370   CASE 1 TO 10
380     PRINT "ERROR: Not in 1-10"
390   CASE 11 TO 20
400     PRINT "PASS: In range 11-20"
410   CASE 21 TO 30
420     PRINT "ERROR: Not in 21-30"
430   CASE ELSE
440     PRINT "ERROR: Should be in range"
450 END SELECT
460 PRINT ""
470 REM ====================================
480 REM Test 4: Double SELECT with range
490 REM ====================================
500 PRINT "Test 4: Double SELECT with range"
510 DIM y#
520 y# = 2.5
530 SELECT CASE y#
540   CASE 0.0 TO 1.0
550     PRINT "ERROR: Not in 0-1"
560   CASE 1.0 TO 3.0
570     PRINT "PASS: In range 1-3"
580   CASE 3.0 TO 5.0
590     PRINT "ERROR: Not in 3-5"
600   CASE ELSE
610     PRINT "ERROR: Should be in range"
620 END SELECT
630 PRINT ""
640 REM ====================================
650 REM Test 5: Integer SELECT with multiple values
660 REM ====================================
670 PRINT "Test 5: Integer SELECT, multiple values"
680 DIM a%
690 a% = 7
700 SELECT CASE a%
710   CASE 2, 4, 6, 8
720     PRINT "ERROR: Not even"
730   CASE 1, 3, 5, 7, 9
740     PRINT "PASS: Odd number 7"
750   CASE ELSE
760     PRINT "ERROR: Should match 7"
770 END SELECT
780 PRINT ""
790 REM ====================================
800 REM Test 6: Double SELECT with multiple values
810 REM ====================================
820 PRINT "Test 6: Double SELECT, multiple values"
830 DIM b#
840 b# = 2.5
850 SELECT CASE b#
860   CASE 1.5, 2.5, 3.5
870     PRINT "PASS: Match 2.5 in list"
880   CASE ELSE
890     PRINT "ERROR: Should match 2.5"
900 END SELECT
910 PRINT ""
920 REM ====================================
930 REM Test 7: CASE IS with integer
940 REM ====================================
950 PRINT "Test 7: CASE IS with integer"
960 DIM c%
970 c% = 42
980 SELECT CASE c%
990   CASE IS < 10
1000     PRINT "ERROR: Not < 10"
1010   CASE IS < 50
1020     PRINT "PASS: 42 < 50"
1030   CASE IS >= 50
1040     PRINT "ERROR: Not >= 50"
1050   CASE ELSE
1060     PRINT "ERROR: Should match < 50"
1070 END SELECT
1080 PRINT ""
1090 REM ====================================
1100 REM Test 8: CASE IS with double
1110 REM ====================================
1120 PRINT "Test 8: CASE IS with double"
1130 DIM e#
1140 e# = 3.14159
1150 SELECT CASE e#
1160   CASE IS < 1.0
1170     PRINT "ERROR: Not < 1.0"
1180   CASE IS < 4.0
1190     PRINT "PASS: Pi < 4.0"
1200   CASE IS >= 4.0
1210     PRINT "ERROR: Not >= 4.0"
1220   CASE ELSE
1230     PRINT "ERROR: Should match < 4.0"
1240 END SELECT
1250 PRINT ""
1260 REM ====================================
1270 REM Test 9: Integer boundary test
1280 REM ====================================
1290 PRINT "Test 9: Integer boundary (0)"
1300 DIM zero%
1310 zero% = 0
1320 SELECT CASE zero%
1330   CASE 0
1340     PRINT "PASS: Zero matches"
1350   CASE ELSE
1360     PRINT "ERROR: Should match 0"
1370 END SELECT
1380 PRINT ""
1390 REM ====================================
1400 REM Test 10: Double boundary test
1410 REM ====================================
1420 PRINT "Test 10: Double boundary (0.0)"
1430 DIM zerod#
1440 zerod# = 0.0
1450 SELECT CASE zerod#
1460   CASE 0.0
1470     PRINT "PASS: 0.0 matches"
1480   CASE ELSE
1490     PRINT "ERROR: Should match 0.0"
1500 END SELECT
1510 PRINT ""
1520 REM ====================================
1530 REM Test 11: Negative integer
1540 REM ====================================
1550 PRINT "Test 11: Negative integer"
1560 DIM neg%
1570 neg% = -5
1580 SELECT CASE neg%
1590   CASE -10 TO -1
1600     PRINT "PASS: Negative in range"
1610   CASE ELSE
1620     PRINT "ERROR: Should match negative range"
1630 END SELECT
1640 PRINT ""
1650 REM ====================================
1660 REM Test 12: Negative double
1670 REM ====================================
1680 PRINT "Test 12: Negative double"
1690 DIM negd#
1700 negd# = -3.5
1710 SELECT CASE negd#
1720   CASE -5.0 TO -1.0
1730     PRINT "PASS: Negative double in range"
1740   CASE ELSE
1750     PRINT "ERROR: Should match negative range"
1760 END SELECT
1770 PRINT ""
1780 PRINT "=== All Type Handling Tests PASSED ==="
1790 END
