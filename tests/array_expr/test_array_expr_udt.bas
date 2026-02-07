10 REM Test: Whole-array expressions with UDT arrays (Vec4)
20 REM Tests C() = A() + B(), B() = A() (copy), and other ops
30 REM on arrays of SIMD-eligible UDT types (16-byte Vec4)
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 REM ============================================================
110 REM Test 1: Element-wise add — C() = A() + B()
120 REM ============================================================
130 DIM A(9) AS Vec4
140 DIM B(9) AS Vec4
150 DIM C(9) AS Vec4
160 FOR i% = 0 TO 9
170   A(i%).X = i% * 10
180   A(i%).Y = i% * 20
190   A(i%).Z = i% * 30
200   A(i%).W = i% * 40
210   B(i%).X = 1
220   B(i%).Y = 2
230   B(i%).Z = 3
240   B(i%).W = 4
250 NEXT i%
260 C() = A() + B()
270 DIM pass% AS INTEGER
280 pass% = 1
290 FOR i% = 0 TO 9
300   IF C(i%).X <> i% * 10 + 1 THEN pass% = 0
310   IF C(i%).Y <> i% * 20 + 2 THEN pass% = 0
320   IF C(i%).Z <> i% * 30 + 3 THEN pass% = 0
330   IF C(i%).W <> i% * 40 + 4 THEN pass% = 0
340 NEXT i%
350 IF pass% = 1 THEN PRINT "PASS: UDT array add Vec4" ELSE PRINT "FAIL: UDT array add Vec4"
360 REM Spot-check specific elements
370 PRINT "C(0): "; C(0).X; ","; C(0).Y; ","; C(0).Z; ","; C(0).W
380 PRINT "C(5): "; C(5).X; ","; C(5).Y; ","; C(5).Z; ","; C(5).W
390 PRINT "C(9): "; C(9).X; ","; C(9).Y; ","; C(9).Z; ","; C(9).W
400 REM ============================================================
410 REM Test 2: Element-wise subtract — C() = A() - B()
420 REM ============================================================
430 C() = A() - B()
440 pass% = 1
450 FOR i% = 0 TO 9
460   IF C(i%).X <> i% * 10 - 1 THEN pass% = 0
470   IF C(i%).Y <> i% * 20 - 2 THEN pass% = 0
480   IF C(i%).Z <> i% * 30 - 3 THEN pass% = 0
490   IF C(i%).W <> i% * 40 - 4 THEN pass% = 0
500 NEXT i%
510 IF pass% = 1 THEN PRINT "PASS: UDT array subtract Vec4" ELSE PRINT "FAIL: UDT array subtract Vec4"
520 REM ============================================================
530 REM Test 3: Element-wise multiply — C() = A() * B()
540 REM ============================================================
550 FOR i% = 0 TO 9
560   B(i%).X = 2
570   B(i%).Y = 3
580   B(i%).Z = 4
590   B(i%).W = 5
600 NEXT i%
610 C() = A() * B()
620 pass% = 1
630 FOR i% = 0 TO 9
640   IF C(i%).X <> i% * 10 * 2 THEN pass% = 0
650   IF C(i%).Y <> i% * 20 * 3 THEN pass% = 0
660   IF C(i%).Z <> i% * 30 * 4 THEN pass% = 0
670   IF C(i%).W <> i% * 40 * 5 THEN pass% = 0
680 NEXT i%
690 IF pass% = 1 THEN PRINT "PASS: UDT array multiply Vec4" ELSE PRINT "FAIL: UDT array multiply Vec4"
700 REM ============================================================
710 REM Test 4: Whole-array copy — B() = A()
720 REM ============================================================
730 DIM D(9) AS Vec4
740 D() = A()
750 pass% = 1
760 FOR i% = 0 TO 9
770   IF D(i%).X <> A(i%).X THEN pass% = 0
780   IF D(i%).Y <> A(i%).Y THEN pass% = 0
790   IF D(i%).Z <> A(i%).Z THEN pass% = 0
800   IF D(i%).W <> A(i%).W THEN pass% = 0
810 NEXT i%
820 IF pass% = 1 THEN PRINT "PASS: UDT array copy Vec4" ELSE PRINT "FAIL: UDT array copy Vec4"
830 REM Verify source unchanged
840 IF A(5).X = 50 AND A(5).Y = 100 AND A(5).Z = 150 AND A(5).W = 200 THEN PRINT "PASS: copy source intact" ELSE PRINT "FAIL: copy source modified"
850 REM ============================================================
860 REM Test 5: In-place operation — A() = A() + B()
870 REM ============================================================
880 REM Reset B to simple values
890 FOR i% = 0 TO 9
900   B(i%).X = 1
910   B(i%).Y = 1
920   B(i%).Z = 1
930   B(i%).W = 1
940 NEXT i%
950 REM Save original A values for verification
960 DIM origAX(9) AS INTEGER
970 DIM origAY(9) AS INTEGER
980 DIM origAZ(9) AS INTEGER
990 DIM origAW(9) AS INTEGER
1000 FOR i% = 0 TO 9
1010   origAX(i%) = A(i%).X
1020   origAY(i%) = A(i%).Y
1030   origAZ(i%) = A(i%).Z
1040   origAW(i%) = A(i%).W
1050 NEXT i%
1060 A() = A() + B()
1070 pass% = 1
1080 FOR i% = 0 TO 9
1090   IF A(i%).X <> origAX(i%) + 1 THEN pass% = 0
1100   IF A(i%).Y <> origAY(i%) + 1 THEN pass% = 0
1110   IF A(i%).Z <> origAZ(i%) + 1 THEN pass% = 0
1120   IF A(i%).W <> origAW(i%) + 1 THEN pass% = 0
1130 NEXT i%
1140 IF pass% = 1 THEN PRINT "PASS: in-place A() = A() + B() Vec4" ELSE PRINT "FAIL: in-place add Vec4"
1150 REM ============================================================
1160 REM Test 6: Same array both sides — A() = A() + A()
1170 REM ============================================================
1180 DIM E(4) AS Vec4
1190 FOR i% = 0 TO 4
1200   E(i%).X = i% + 1
1210   E(i%).Y = (i% + 1) * 10
1220   E(i%).Z = (i% + 1) * 100
1230   E(i%).W = (i% + 1) * 1000
1240 NEXT i%
1250 REM Save originals
1260 DIM eX(4) AS INTEGER
1270 DIM eY(4) AS INTEGER
1280 DIM eZ(4) AS INTEGER
1290 DIM eW(4) AS INTEGER
1300 FOR i% = 0 TO 4
1310   eX(i%) = E(i%).X
1320   eY(i%) = E(i%).Y
1330   eZ(i%) = E(i%).Z
1340   eW(i%) = E(i%).W
1350 NEXT i%
1360 E() = E() + E()
1370 pass% = 1
1380 FOR i% = 0 TO 4
1390   IF E(i%).X <> eX(i%) * 2 THEN pass% = 0
1400   IF E(i%).Y <> eY(i%) * 2 THEN pass% = 0
1410   IF E(i%).Z <> eZ(i%) * 2 THEN pass% = 0
1420   IF E(i%).W <> eW(i%) * 2 THEN pass% = 0
1430 NEXT i%
1440 IF pass% = 1 THEN PRINT "PASS: self-add E() = E() + E() Vec4" ELSE PRINT "FAIL: self-add Vec4"
1450 REM ============================================================
1460 REM Test 7: Vec4 float type (Vec4F)
1470 REM ============================================================
1480 TYPE Vec4F
1490   X AS SINGLE
1500   Y AS SINGLE
1510   Z AS SINGLE
1520   W AS SINGLE
1530 END TYPE
1540 DIM AF(6) AS Vec4F
1550 DIM BF(6) AS Vec4F
1560 DIM CF(6) AS Vec4F
1570 FOR i% = 0 TO 6
1580   AF(i%).X = i% * 1.5
1590   AF(i%).Y = i% * 2.5
1600   AF(i%).Z = i% * 3.5
1610   AF(i%).W = i% * 4.5
1620   BF(i%).X = 0.1
1630   BF(i%).Y = 0.2
1640   BF(i%).Z = 0.3
1650   BF(i%).W = 0.4
1660 NEXT i%
1670 CF() = AF() + BF()
1680 pass% = 1
1690 FOR i% = 0 TO 6
1700   IF CF(i%).X <> AF(i%).X + BF(i%).X THEN pass% = 0
1710   IF CF(i%).Y <> AF(i%).Y + BF(i%).Y THEN pass% = 0
1720   IF CF(i%).Z <> AF(i%).Z + BF(i%).Z THEN pass% = 0
1730   IF CF(i%).W <> AF(i%).W + BF(i%).W THEN pass% = 0
1740 NEXT i%
1750 IF pass% = 1 THEN PRINT "PASS: UDT array add Vec4F (float)" ELSE PRINT "FAIL: UDT array add Vec4F"
1760 REM ============================================================
1770 REM Test 8: Vec4F division (float divide via NEON)
1780 REM ============================================================
1790 FOR i% = 0 TO 6
1800   AF(i%).X = (i% + 1) * 10.0
1810   AF(i%).Y = (i% + 1) * 20.0
1820   AF(i%).Z = (i% + 1) * 30.0
1830   AF(i%).W = (i% + 1) * 40.0
1840   BF(i%).X = 2.0
1850   BF(i%).Y = 4.0
1860   BF(i%).Z = 5.0
1870   BF(i%).W = 10.0
1880 NEXT i%
1890 CF() = AF() / BF()
1900 pass% = 1
1910 FOR i% = 0 TO 6
1920   IF CF(i%).X <> AF(i%).X / BF(i%).X THEN pass% = 0
1930   IF CF(i%).Y <> AF(i%).Y / BF(i%).Y THEN pass% = 0
1940   IF CF(i%).Z <> AF(i%).Z / BF(i%).Z THEN pass% = 0
1950   IF CF(i%).W <> AF(i%).W / BF(i%).W THEN pass% = 0
1960 NEXT i%
1970 IF pass% = 1 THEN PRINT "PASS: UDT array divide Vec4F" ELSE PRINT "FAIL: UDT array divide Vec4F"
1980 REM ============================================================
1990 REM Test 9: Vec4F copy
2000 REM ============================================================
2010 DIM DF(6) AS Vec4F
2020 DF() = AF()
2030 pass% = 1
2040 FOR i% = 0 TO 6
2050   IF DF(i%).X <> AF(i%).X THEN pass% = 0
2060   IF DF(i%).Y <> AF(i%).Y THEN pass% = 0
2070   IF DF(i%).Z <> AF(i%).Z THEN pass% = 0
2080   IF DF(i%).W <> AF(i%).W THEN pass% = 0
2090 NEXT i%
2100 IF pass% = 1 THEN PRINT "PASS: UDT array copy Vec4F" ELSE PRINT "FAIL: UDT array copy Vec4F"
2110 REM ============================================================
2120 REM Test 10: Vec2D (DOUBLE pair, 16 bytes = full Q register)
2130 REM ============================================================
2140 TYPE Vec2D
2150   X AS DOUBLE
2160   Y AS DOUBLE
2170 END TYPE
2180 DIM AV(5) AS Vec2D
2190 DIM BV(5) AS Vec2D
2200 DIM CV(5) AS Vec2D
2210 FOR i% = 0 TO 5
2220   AV(i%).X = (i% + 1) * 1.11
2230   AV(i%).Y = (i% + 1) * 2.22
2240   BV(i%).X = 0.01
2250   BV(i%).Y = 0.02
2260 NEXT i%
2270 CV() = AV() + BV()
2280 pass% = 1
2290 FOR i% = 0 TO 5
2300   IF CV(i%).X <> AV(i%).X + BV(i%).X THEN pass% = 0
2310   IF CV(i%).Y <> AV(i%).Y + BV(i%).Y THEN pass% = 0
2320 NEXT i%
2330 IF pass% = 1 THEN PRINT "PASS: UDT array add Vec2D" ELSE PRINT "FAIL: UDT array add Vec2D"
2340 REM Copy Vec2D
2350 DIM DV(5) AS Vec2D
2360 DV() = AV()
2370 pass% = 1
2380 FOR i% = 0 TO 5
2390   IF DV(i%).X <> AV(i%).X THEN pass% = 0
2400   IF DV(i%).Y <> AV(i%).Y THEN pass% = 0
2410 NEXT i%
2420 IF pass% = 1 THEN PRINT "PASS: UDT array copy Vec2D" ELSE PRINT "FAIL: UDT array copy Vec2D"
2430 REM Vec2D subtract
2440 CV() = AV() - BV()
2450 pass% = 1
2460 FOR i% = 0 TO 5
2470   IF CV(i%).X <> AV(i%).X - BV(i%).X THEN pass% = 0
2480   IF CV(i%).Y <> AV(i%).Y - BV(i%).Y THEN pass% = 0
2490 NEXT i%
2500 IF pass% = 1 THEN PRINT "PASS: UDT array subtract Vec2D" ELSE PRINT "FAIL: UDT array subtract Vec2D"
2510 REM Vec2D multiply
2520 CV() = AV() * BV()
2530 pass% = 1
2540 FOR i% = 0 TO 5
2550   IF CV(i%).X <> AV(i%).X * BV(i%).X THEN pass% = 0
2560   IF CV(i%).Y <> AV(i%).Y * BV(i%).Y THEN pass% = 0
2570 NEXT i%
2580 IF pass% = 1 THEN PRINT "PASS: UDT array multiply Vec2D" ELSE PRINT "FAIL: UDT array multiply Vec2D"
2590 REM ============================================================
2600 REM Test 11: Comparison with FOR-loop equivalent
2610 REM Ensure array expression produces same results as FOR loop
2620 REM ============================================================
2630 DIM ref(9) AS Vec4
2640 DIM res(9) AS Vec4
2650 REM Reinitialize A and B
2660 FOR i% = 0 TO 9
2670   A(i%).X = i% * 7
2680   A(i%).Y = i% * 13
2690   A(i%).Z = i% * 17
2700   A(i%).W = i% * 23
2710   B(i%).X = 5
2720   B(i%).Y = 10
2730   B(i%).Z = 15
2740   B(i%).W = 20
2750 NEXT i%
2760 REM FOR loop reference
2770 FOR i% = 0 TO 9
2780   ref(i%) = A(i%) + B(i%)
2790 NEXT i%
2800 REM Array expression
2810 res() = A() + B()
2820 REM Compare
2830 pass% = 1
2840 FOR i% = 0 TO 9
2850   IF res(i%).X <> ref(i%).X THEN pass% = 0
2860   IF res(i%).Y <> ref(i%).Y THEN pass% = 0
2870   IF res(i%).Z <> ref(i%).Z THEN pass% = 0
2880   IF res(i%).W <> ref(i%).W THEN pass% = 0
2890 NEXT i%
2900 IF pass% = 1 THEN PRINT "PASS: array expr matches FOR loop" ELSE PRINT "FAIL: array expr vs FOR loop mismatch"
2910 PRINT "All UDT array expression tests complete."
2920 END
