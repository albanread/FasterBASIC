10 REM Test: Whole-array expression - copy, fill, negate, scalar broadcast
20 REM Tests B() = A() (copy), A() = 0 (fill), B() = -A() (negate),
30 REM and B() = A() * 2.0 (broadcast) for SINGLE and INTEGER arrays
40 REM ============================================================
50 REM Test 1: Array Copy — B() = A()
60 REM ============================================================
70 DIM A(10) AS SINGLE
80 DIM B(10) AS SINGLE
90 FOR i% = 0 TO 10
100   A(i%) = (i% + 1) * 3.5
110 NEXT i%
120 B() = A()
130 DIM pass% AS INTEGER
140 pass% = 1
150 FOR i% = 0 TO 10
160   IF B(i%) <> A(i%) THEN
170     PRINT "FAIL copy at index "; i%; ": got "; B(i%); " expected "; A(i%)
180     pass% = 0
190   ENDIF
200 NEXT i%
210 IF pass% = 1 THEN PRINT "PASS: array copy SINGLE" ELSE PRINT "FAIL: array copy SINGLE"
220 REM Verify source unchanged
230 IF A(5) = 6 * 3.5 THEN PRINT "PASS: copy source intact" ELSE PRINT "FAIL: copy source modified"
240 REM ============================================================
250 REM Test 2: Array Fill — A() = 0
260 REM ============================================================
270 DIM C(15) AS SINGLE
280 FOR i% = 0 TO 15
290   C(i%) = 999.0
300 NEXT i%
310 C() = 0
320 pass% = 1
330 FOR i% = 0 TO 15
340   IF C(i%) <> 0 THEN
350     PRINT "FAIL fill zero at index "; i%; ": got "; C(i%)
360     pass% = 0
370   ENDIF
380 NEXT i%
390 IF pass% = 1 THEN PRINT "PASS: array fill zero SINGLE" ELSE PRINT "FAIL: array fill zero SINGLE"
400 REM ============================================================
410 REM Test 3: Fill with non-zero value — A() = 3.5
420 REM ============================================================
430 DIM D(8) AS SINGLE
440 D() = 3.5
450 pass% = 1
460 FOR i% = 0 TO 8
470   IF D(i%) <> 3.5 THEN
480     PRINT "FAIL fill 3.5 at index "; i%; ": got "; D(i%)
490     pass% = 0
500   ENDIF
510 NEXT i%
520 IF pass% = 1 THEN PRINT "PASS: array fill 3.5 SINGLE" ELSE PRINT "FAIL: array fill 3.5 SINGLE"
530 REM ============================================================
540 REM Test 4: Array Negate — B() = -A()
550 REM ============================================================
560 DIM E(10) AS SINGLE
570 DIM F(10) AS SINGLE
580 FOR i% = 0 TO 10
590   E(i%) = (i% + 1) * 2.5
600 NEXT i%
610 F() = -E()
620 pass% = 1
630 FOR i% = 0 TO 10
640   IF F(i%) <> -E(i%) THEN
650     PRINT "FAIL negate at index "; i%; ": got "; F(i%); " expected "; -E(i%)
660     pass% = 0
670   ENDIF
680 NEXT i%
690 IF pass% = 1 THEN PRINT "PASS: array negate SINGLE" ELSE PRINT "FAIL: array negate SINGLE"
700 REM Verify source unchanged after negate
710 IF E(3) = 4 * 2.5 THEN PRINT "PASS: negate source intact" ELSE PRINT "FAIL: negate source modified"
720 REM ============================================================
730 REM Test 5: Scalar Broadcast Right — B() = A() * 2.0
740 REM ============================================================
750 DIM G(10) AS SINGLE
760 DIM H(10) AS SINGLE
770 FOR i% = 0 TO 10
780   G(i%) = (i% + 1) * 1.0
790 NEXT i%
800 H() = G() * 2.0
810 pass% = 1
820 FOR i% = 0 TO 10
830   IF H(i%) <> G(i%) * 2.0 THEN
840     PRINT "FAIL broadcast mul at index "; i%; ": got "; H(i%); " expected "; G(i%) * 2.0
850     pass% = 0
860   ENDIF
870 NEXT i%
880 IF pass% = 1 THEN PRINT "PASS: broadcast A() * 2.0 SINGLE" ELSE PRINT "FAIL: broadcast A() * 2.0"
890 REM ============================================================
900 REM Test 6: Scalar Broadcast Left — B() = 100.0 - A()
910 REM ============================================================
920 H() = 100.0 - G()
930 pass% = 1
940 FOR i% = 0 TO 10
950   IF H(i%) <> 100.0 - G(i%) THEN
960     PRINT "FAIL broadcast left sub at index "; i%; ": got "; H(i%); " expected "; 100.0 - G(i%)
970     pass% = 0
980   ENDIF
990 NEXT i%
1000 IF pass% = 1 THEN PRINT "PASS: broadcast 100 - A() SINGLE" ELSE PRINT "FAIL: broadcast 100 - A()"
1010 REM ============================================================
1020 REM Test 7: Scalar Broadcast Add — B() = A() + 10.0
1030 REM ============================================================
1040 H() = G() + 10.0
1050 pass% = 1
1060 FOR i% = 0 TO 10
1070   IF H(i%) <> G(i%) + 10.0 THEN
1080     PRINT "FAIL broadcast add at index "; i%; ": got "; H(i%)
1090     pass% = 0
1100   ENDIF
1110 NEXT i%
1120 IF pass% = 1 THEN PRINT "PASS: broadcast A() + 10 SINGLE" ELSE PRINT "FAIL: broadcast A() + 10"
1130 REM ============================================================
1140 REM Test 8: Scalar Broadcast Divide — B() = A() / 2.0
1150 REM ============================================================
1160 H() = G() / 2.0
1170 pass% = 1
1180 FOR i% = 0 TO 10
1190   IF H(i%) <> G(i%) / 2.0 THEN
1200     PRINT "FAIL broadcast div at index "; i%; ": got "; H(i%)
1210     pass% = 0
1220   ENDIF
1230 NEXT i%
1240 IF pass% = 1 THEN PRINT "PASS: broadcast A() / 2 SINGLE" ELSE PRINT "FAIL: broadcast A() / 2"
1250 REM ============================================================
1260 REM Test 9: INTEGER array copy
1270 REM ============================================================
1280 DIM AI(7) AS INTEGER
1290 DIM BI(7) AS INTEGER
1300 FOR i% = 0 TO 7
1310   AI(i%) = (i% + 1) * 11
1320 NEXT i%
1330 BI() = AI()
1340 pass% = 1
1350 FOR i% = 0 TO 7
1360   IF BI(i%) <> AI(i%) THEN
1370     PRINT "FAIL int copy at "; i%; ": got "; BI(i%); " expected "; AI(i%)
1380     pass% = 0
1390   ENDIF
1400 NEXT i%
1410 IF pass% = 1 THEN PRINT "PASS: array copy INTEGER" ELSE PRINT "FAIL: array copy INTEGER"
1420 REM ============================================================
1430 REM Test 10: INTEGER array fill
1440 REM ============================================================
1450 BI() = 42
1460 pass% = 1
1470 FOR i% = 0 TO 7
1480   IF BI(i%) <> 42 THEN
1490     PRINT "FAIL int fill at "; i%; ": got "; BI(i%)
1500     pass% = 0
1510   ENDIF
1520 NEXT i%
1530 IF pass% = 1 THEN PRINT "PASS: array fill 42 INTEGER" ELSE PRINT "FAIL: array fill 42 INTEGER"
1540 REM ============================================================
1550 REM Test 11: INTEGER array negate
1560 REM ============================================================
1570 DIM CI(7) AS INTEGER
1580 FOR i% = 0 TO 7
1590   AI(i%) = (i% + 1) * 5
1600 NEXT i%
1610 CI() = -AI()
1620 pass% = 1
1630 FOR i% = 0 TO 7
1640   IF CI(i%) <> -AI(i%) THEN
1650     PRINT "FAIL int negate at "; i%; ": got "; CI(i%); " expected "; -AI(i%)
1660     pass% = 0
1670   ENDIF
1680 NEXT i%
1690 IF pass% = 1 THEN PRINT "PASS: array negate INTEGER" ELSE PRINT "FAIL: array negate INTEGER"
1700 REM ============================================================
1710 REM Test 12: INTEGER scalar broadcast multiply
1720 REM ============================================================
1730 CI() = AI() * 3
1740 pass% = 1
1750 FOR i% = 0 TO 7
1760   IF CI(i%) <> AI(i%) * 3 THEN
1770     PRINT "FAIL int broadcast mul at "; i%; ": got "; CI(i%)
1780     pass% = 0
1790   ENDIF
1800 NEXT i%
1810 IF pass% = 1 THEN PRINT "PASS: broadcast A() * 3 INTEGER" ELSE PRINT "FAIL: broadcast A() * 3 INTEGER"
1820 REM ============================================================
1830 REM Test 13: DOUBLE array copy, fill, negate
1840 REM ============================================================
1850 DIM AD(5) AS DOUBLE
1860 DIM BD(5) AS DOUBLE
1870 FOR i% = 0 TO 5
1880   AD(i%) = (i% + 1) * 1.234567890123
1890 NEXT i%
1900 BD() = AD()
1910 pass% = 1
1920 FOR i% = 0 TO 5
1930   IF BD(i%) <> AD(i%) THEN
1940     PRINT "FAIL double copy at "; i%
1950     pass% = 0
1960   ENDIF
1970 NEXT i%
1980 IF pass% = 1 THEN PRINT "PASS: array copy DOUBLE" ELSE PRINT "FAIL: array copy DOUBLE"
1990 BD() = 0
2000 pass% = 1
2010 FOR i% = 0 TO 5
2020   IF BD(i%) <> 0 THEN
2030     PRINT "FAIL double fill zero at "; i%
2040     pass% = 0
2050   ENDIF
2060 NEXT i%
2070 IF pass% = 1 THEN PRINT "PASS: array fill zero DOUBLE" ELSE PRINT "FAIL: array fill zero DOUBLE"
2080 BD() = -AD()
2090 pass% = 1
2100 FOR i% = 0 TO 5
2110   IF BD(i%) <> -AD(i%) THEN
2120     PRINT "FAIL double negate at "; i%; ": got "; BD(i%); " expected "; -AD(i%)
2130     pass% = 0
2140   ENDIF
2150 NEXT i%
2160 IF pass% = 1 THEN PRINT "PASS: array negate DOUBLE" ELSE PRINT "FAIL: array negate DOUBLE"
2170 REM ============================================================
2180 REM Test 14: DOUBLE scalar broadcast
2190 REM ============================================================
2200 BD() = AD() * 0.5
2210 pass% = 1
2220 FOR i% = 0 TO 5
2230   IF BD(i%) <> AD(i%) * 0.5 THEN
2240     PRINT "FAIL double broadcast mul at "; i%
2250     pass% = 0
2260   ENDIF
2270 NEXT i%
2280 IF pass% = 1 THEN PRINT "PASS: broadcast A() * 0.5 DOUBLE" ELSE PRINT "FAIL: broadcast A() * 0.5 DOUBLE"
2290 REM ============================================================
2300 REM Test 15: Array of length 1
2310 REM ============================================================
2320 DIM tiny(0) AS SINGLE
2330 DIM tiny2(0) AS SINGLE
2340 tiny(0) = 7.5
2350 tiny2() = tiny()
2360 IF tiny2(0) = 7.5 THEN PRINT "PASS: copy length-1 array" ELSE PRINT "FAIL: copy length-1 array"
2370 tiny2() = -tiny()
2380 IF tiny2(0) = -7.5 THEN PRINT "PASS: negate length-1 array" ELSE PRINT "FAIL: negate length-1 array"
2390 tiny2() = tiny() + 1.0
2400 IF tiny2(0) = 8.5 THEN PRINT "PASS: broadcast add length-1" ELSE PRINT "FAIL: broadcast add length-1"
2410 tiny2() = 99.0
2420 IF tiny2(0) = 99.0 THEN PRINT "PASS: fill length-1 array" ELSE PRINT "FAIL: fill length-1 array"
2430 REM ============================================================
2440 REM Test 16: Chained operations
2450 REM ============================================================
2460 DIM X(5) AS SINGLE
2470 DIM Y(5) AS SINGLE
2480 DIM Z(5) AS SINGLE
2490 FOR i% = 0 TO 5
2500   X(i%) = i% + 1.0
2510 NEXT i%
2520 Y() = X() * 2.0
2530 Z() = Y() + X()
2540 REM Z(i) should equal X(i)*2 + X(i) = X(i)*3
2550 pass% = 1
2560 FOR i% = 0 TO 5
2570   IF Z(i%) <> (i% + 1.0) * 3.0 THEN
2580     PRINT "FAIL chained at "; i%; ": got "; Z(i%); " expected "; (i% + 1.0) * 3.0
2590     pass% = 0
2600   ENDIF
2610 NEXT i%
2620 IF pass% = 1 THEN PRINT "PASS: chained Y()=X()*2, Z()=Y()+X()" ELSE PRINT "FAIL: chained ops"
2630 PRINT "Array expression copy/fill/negate/broadcast tests complete."
2640 END
