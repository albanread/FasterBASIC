10 REM Test: Whole-array expression edge cases
20 REM Tests boundary conditions: length-1, length not multiple of NEON lanes,
30 REM in-place ops, same array both sides, fill zero/negative, etc.
40 DIM pass% AS INTEGER
50 REM ============================================================
60 REM Test 1: Array of length 1 (0 TO 0) — only remainder path
70 REM ============================================================
80 DIM A1(0) AS SINGLE
90 DIM B1(0) AS SINGLE
100 DIM C1(0) AS SINGLE
110 A1(0) = 42.5
120 B1(0) = 7.5
130 C1() = A1() + B1()
140 IF C1(0) = 50.0 THEN PRINT "PASS: len-1 add" ELSE PRINT "FAIL: len-1 add: got "; C1(0)
150 C1() = A1() - B1()
160 IF C1(0) = 35.0 THEN PRINT "PASS: len-1 sub" ELSE PRINT "FAIL: len-1 sub: got "; C1(0)
170 C1() = A1() * B1()
180 IF C1(0) = 318.75 THEN PRINT "PASS: len-1 mul" ELSE PRINT "FAIL: len-1 mul: got "; C1(0)
190 C1() = A1()
200 IF C1(0) = 42.5 THEN PRINT "PASS: len-1 copy" ELSE PRINT "FAIL: len-1 copy: got "; C1(0)
210 C1() = -A1()
220 IF C1(0) = -42.5 THEN PRINT "PASS: len-1 negate" ELSE PRINT "FAIL: len-1 negate: got "; C1(0)
230 C1() = 0
240 IF C1(0) = 0 THEN PRINT "PASS: len-1 fill zero" ELSE PRINT "FAIL: len-1 fill zero"
250 C1() = A1() * 2.0
260 IF C1(0) = 85.0 THEN PRINT "PASS: len-1 broadcast mul" ELSE PRINT "FAIL: len-1 broadcast mul: got "; C1(0)
270 REM ============================================================
280 REM Test 2: Length not multiple of 4 (SINGLE) — remainder handling
290 REM 0 TO 5 = 6 elements, NEON processes 4 per iter = 4 + 2 remainder
300 REM ============================================================
310 DIM A6(5) AS SINGLE
320 DIM B6(5) AS SINGLE
330 DIM C6(5) AS SINGLE
340 FOR i% = 0 TO 5
350   A6(i%) = (i% + 1) * 10.0
360   B6(i%) = (i% + 1) * 3.0
370 NEXT i%
380 C6() = A6() + B6()
390 pass% = 1
400 FOR i% = 0 TO 5
410   IF C6(i%) <> (i% + 1) * 13.0 THEN
420     PRINT "FAIL: len-6 add at "; i%; ": got "; C6(i%); " expected "; (i% + 1) * 13.0
430     pass% = 0
440   ENDIF
450 NEXT i%
460 IF pass% = 1 THEN PRINT "PASS: len-6 SINGLE add (4+2 remainder)" ELSE PRINT "FAIL: len-6 add"
470 REM ============================================================
480 REM Test 3: Length not multiple of 4 — 7 elements (4+3 remainder)
490 REM ============================================================
500 DIM A7(6) AS SINGLE
510 DIM B7(6) AS SINGLE
520 DIM C7(6) AS SINGLE
530 FOR i% = 0 TO 6
540   A7(i%) = (i% + 1) * 5.0
550   B7(i%) = 1.0
560 NEXT i%
570 C7() = A7() + B7()
580 pass% = 1
590 FOR i% = 0 TO 6
600   IF C7(i%) <> (i% + 1) * 5.0 + 1.0 THEN
610     PRINT "FAIL: len-7 add at "; i%; ": got "; C7(i%)
620     pass% = 0
630   ENDIF
640 NEXT i%
650 IF pass% = 1 THEN PRINT "PASS: len-7 SINGLE add (4+3 remainder)" ELSE PRINT "FAIL: len-7 add"
660 REM ============================================================
670 REM Test 4: Exact multiple of 4 — no remainder needed
680 REM 0 TO 7 = 8 elements = 2 full NEON iterations
690 REM ============================================================
700 DIM A8(7) AS SINGLE
710 DIM B8(7) AS SINGLE
720 DIM C8(7) AS SINGLE
730 FOR i% = 0 TO 7
740   A8(i%) = i% * 100.0
750   B8(i%) = i% * 0.01
760 NEXT i%
770 C8() = A8() + B8()
780 pass% = 1
790 FOR i% = 0 TO 7
800   IF C8(i%) <> A8(i%) + B8(i%) THEN
810     PRINT "FAIL: len-8 add at "; i%; ": got "; C8(i%)
820     pass% = 0
830   ENDIF
840 NEXT i%
850 IF pass% = 1 THEN PRINT "PASS: len-8 SINGLE add (exact 4x, no remainder)" ELSE PRINT "FAIL: len-8 add"
860 REM ============================================================
870 REM Test 5: DOUBLE array with odd count (remainder = 1)
880 REM 0 TO 2 = 3 elements, NEON processes 2 per iter = 2 + 1 remainder
890 REM ============================================================
900 DIM AD3(2) AS DOUBLE
910 DIM BD3(2) AS DOUBLE
920 DIM CD3(2) AS DOUBLE
930 AD3(0) = 1.111111111111
940 AD3(1) = 2.222222222222
950 AD3(2) = 3.333333333333
960 BD3(0) = 0.000000000001
970 BD3(1) = 0.000000000002
980 BD3(2) = 0.000000000003
990 CD3() = AD3() + BD3()
1000 pass% = 1
1010 FOR i% = 0 TO 2
1020   IF CD3(i%) <> AD3(i%) + BD3(i%) THEN
1030     PRINT "FAIL: double len-3 at "; i%
1040     pass% = 0
1050   ENDIF
1060 NEXT i%
1070 IF pass% = 1 THEN PRINT "PASS: len-3 DOUBLE add (2+1 remainder)" ELSE PRINT "FAIL: double len-3 add"
1080 REM ============================================================
1090 REM Test 6: INTEGER with 5 elements (4+1 remainder)
1100 REM ============================================================
1110 DIM AI5(4) AS INTEGER
1120 DIM BI5(4) AS INTEGER
1130 DIM CI5(4) AS INTEGER
1140 FOR i% = 0 TO 4
1150   AI5(i%) = (i% + 1) * 1000
1160   BI5(i%) = (i% + 1)
1170 NEXT i%
1180 CI5() = AI5() + BI5()
1190 pass% = 1
1200 FOR i% = 0 TO 4
1210   IF CI5(i%) <> (i% + 1) * 1000 + (i% + 1) THEN
1220     PRINT "FAIL: int len-5 at "; i%; ": got "; CI5(i%)
1230     pass% = 0
1240   ENDIF
1250 NEXT i%
1260 IF pass% = 1 THEN PRINT "PASS: len-5 INTEGER add (4+1 remainder)" ELSE PRINT "FAIL: int len-5 add"
1270 REM ============================================================
1280 REM Test 7: In-place operation A() = A() + B()
1290 REM ============================================================
1300 DIM IP(6) AS SINGLE
1310 DIM IPB(6) AS SINGLE
1320 FOR i% = 0 TO 6
1330   IP(i%) = i% * 10.0
1340   IPB(i%) = 1.0
1350 NEXT i%
1360 IP() = IP() + IPB()
1370 pass% = 1
1380 FOR i% = 0 TO 6
1390   IF IP(i%) <> i% * 10.0 + 1.0 THEN
1400     PRINT "FAIL: in-place at "; i%; ": got "; IP(i%); " expected "; i% * 10.0 + 1.0
1410     pass% = 0
1420   ENDIF
1430 NEXT i%
1440 IF pass% = 1 THEN PRINT "PASS: in-place A() = A() + B()" ELSE PRINT "FAIL: in-place add"
1450 REM ============================================================
1460 REM Test 8: Same array on both sides — A() = A() + A()
1470 REM ============================================================
1480 DIM SA(5) AS SINGLE
1490 FOR i% = 0 TO 5
1500   SA(i%) = (i% + 1) * 1.0
1510 NEXT i%
1520 SA() = SA() + SA()
1530 pass% = 1
1540 FOR i% = 0 TO 5
1550   IF SA(i%) <> (i% + 1) * 2.0 THEN
1560     PRINT "FAIL: self-add at "; i%; ": got "; SA(i%)
1570     pass% = 0
1580   ENDIF
1590 NEXT i%
1600 IF pass% = 1 THEN PRINT "PASS: A() = A() + A() (double each)" ELSE PRINT "FAIL: self-add"
1610 REM ============================================================
1620 REM Test 9: Fill with negative value
1630 REM ============================================================
1640 DIM NF(4) AS SINGLE
1650 NF() = -99.5
1660 pass% = 1
1670 FOR i% = 0 TO 4
1680   IF NF(i%) <> -99.5 THEN
1690     PRINT "FAIL: fill negative at "; i%; ": got "; NF(i%)
1700     pass% = 0
1710   ENDIF
1720 NEXT i%
1730 IF pass% = 1 THEN PRINT "PASS: fill with negative value" ELSE PRINT "FAIL: fill negative"
1740 REM ============================================================
1750 REM Test 10: Fill with large value
1760 REM ============================================================
1770 DIM FL(3) AS SINGLE
1780 FL() = 1000000.0
1790 pass% = 1
1800 FOR i% = 0 TO 3
1810   IF FL(i%) <> 1000000.0 THEN
1820     PRINT "FAIL: fill large at "; i%; ": got "; FL(i%)
1830     pass% = 0
1840   ENDIF
1850 NEXT i%
1860 IF pass% = 1 THEN PRINT "PASS: fill with large value" ELSE PRINT "FAIL: fill large"
1870 REM ============================================================
1880 REM Test 11: Negate zero array — all elements should remain 0
1890 REM ============================================================
1900 DIM NZ(5) AS SINGLE
1910 NZ() = 0
1920 DIM NZR(5) AS SINGLE
1930 NZR() = -NZ()
1940 pass% = 1
1950 FOR i% = 0 TO 5
1960   IF NZR(i%) <> 0 THEN
1970     PRINT "FAIL: negate zero at "; i%; ": got "; NZR(i%)
1980     pass% = 0
1990   ENDIF
2000 NEXT i%
2010 IF pass% = 1 THEN PRINT "PASS: negate zero array" ELSE PRINT "FAIL: negate zero"
2020 REM ============================================================
2030 REM Test 12: Broadcast with zero scalar — A() * 0
2040 REM ============================================================
2050 DIM BZ(5) AS SINGLE
2060 FOR i% = 0 TO 5
2070   BZ(i%) = (i% + 1) * 99.0
2080 NEXT i%
2090 DIM BZR(5) AS SINGLE
2100 BZR() = BZ() * 0.0
2110 pass% = 1
2120 FOR i% = 0 TO 5
2130   IF BZR(i%) <> 0.0 THEN
2140     PRINT "FAIL: broadcast *0 at "; i%; ": got "; BZR(i%)
2150     pass% = 0
2160   ENDIF
2170 NEXT i%
2180 IF pass% = 1 THEN PRINT "PASS: broadcast multiply by zero" ELSE PRINT "FAIL: broadcast *0"
2190 REM ============================================================
2200 REM Test 13: Broadcast add 0 — identity operation
2210 REM ============================================================
2220 DIM IDR(5) AS SINGLE
2230 IDR() = BZ() + 0.0
2240 pass% = 1
2250 FOR i% = 0 TO 5
2260   IF IDR(i%) <> BZ(i%) THEN
2270     PRINT "FAIL: broadcast +0 at "; i%; ": got "; IDR(i%); " expected "; BZ(i%)
2280     pass% = 0
2290   ENDIF
2300 NEXT i%
2310 IF pass% = 1 THEN PRINT "PASS: broadcast add zero (identity)" ELSE PRINT "FAIL: broadcast +0"
2320 REM ============================================================
2330 REM Test 14: Left-side scalar broadcast — 10 * A()
2340 REM ============================================================
2350 DIM LS(4) AS SINGLE
2360 FOR i% = 0 TO 4
2370   LS(i%) = (i% + 1) * 1.0
2380 NEXT i%
2390 DIM LSR(4) AS SINGLE
2400 LSR() = 10.0 * LS()
2410 pass% = 1
2420 FOR i% = 0 TO 4
2430   IF LSR(i%) <> 10.0 * LS(i%) THEN
2440     PRINT "FAIL: left broadcast *10 at "; i%; ": got "; LSR(i%)
2450     pass% = 0
2460   ENDIF
2470 NEXT i%
2480 IF pass% = 1 THEN PRINT "PASS: left broadcast 10 * A()" ELSE PRINT "FAIL: left broadcast"
2490 REM ============================================================
2500 REM Test 15: Chained operations — Y()=X()*2, Z()=Y()+X()
2510 REM ============================================================
2520 DIM CX(5) AS SINGLE
2530 DIM CY(5) AS SINGLE
2540 DIM CZ(5) AS SINGLE
2550 FOR i% = 0 TO 5
2560   CX(i%) = (i% + 1) * 1.0
2570 NEXT i%
2580 CY() = CX() * 2.0
2590 CZ() = CY() + CX()
2600 pass% = 1
2610 FOR i% = 0 TO 5
2620   IF CZ(i%) <> (i% + 1) * 3.0 THEN
2630     PRINT "FAIL: chained at "; i%; ": got "; CZ(i%); " expected "; (i% + 1) * 3.0
2640     pass% = 0
2650   ENDIF
2660 NEXT i%
2670 IF pass% = 1 THEN PRINT "PASS: chained Y=X*2, Z=Y+X" ELSE PRINT "FAIL: chained ops"
2680 REM ============================================================
2690 REM Test 16: INTEGER fill with zero
2700 REM ============================================================
2710 DIM IZ(7) AS INTEGER
2720 FOR i% = 0 TO 7
2730   IZ(i%) = 9999
2740 NEXT i%
2750 IZ() = 0
2760 pass% = 1
2770 FOR i% = 0 TO 7
2780   IF IZ(i%) <> 0 THEN
2790     PRINT "FAIL: int fill zero at "; i%; ": got "; IZ(i%)
2800     pass% = 0
2810   ENDIF
2820 NEXT i%
2830 IF pass% = 1 THEN PRINT "PASS: INTEGER fill zero" ELSE PRINT "FAIL: int fill zero"
2840 REM ============================================================
2850 REM Test 17: Large array — 100 elements
2860 REM ============================================================
2870 DIM LA(99) AS SINGLE
2880 DIM LB(99) AS SINGLE
2890 DIM LC(99) AS SINGLE
2900 FOR i% = 0 TO 99
2910   LA(i%) = i% * 1.0
2920   LB(i%) = 0.5
2930 NEXT i%
2940 LC() = LA() + LB()
2950 pass% = 1
2960 FOR i% = 0 TO 99
2970   IF LC(i%) <> i% * 1.0 + 0.5 THEN
2980     PRINT "FAIL: large array at "; i%; ": got "; LC(i%)
2990     pass% = 0
3000   ENDIF
3010 NEXT i%
3020 IF pass% = 1 THEN PRINT "PASS: large array (100 elements)" ELSE PRINT "FAIL: large array"
3030 REM ============================================================
3040 REM Test 18: Verify array expression matches FOR loop (SINGLE)
3050 REM ============================================================
3060 DIM refA(10) AS SINGLE
3070 DIM refB(10) AS SINGLE
3080 DIM refC(10) AS SINGLE
3090 DIM exprC(10) AS SINGLE
3100 FOR i% = 0 TO 10
3110   refA(i%) = i% * 7.7
3120   refB(i%) = i% * 3.3
3130 NEXT i%
3140 REM FOR loop reference
3150 FOR i% = 0 TO 10
3160   refC(i%) = refA(i%) + refB(i%)
3170 NEXT i%
3180 REM Array expression
3190 exprC() = refA() + refB()
3200 REM Compare
3210 pass% = 1
3220 FOR i% = 0 TO 10
3230   IF exprC(i%) <> refC(i%) THEN
3240     PRINT "FAIL: expr vs loop at "; i%; ": expr="; exprC(i%); " loop="; refC(i%)
3250     pass% = 0
3260   ENDIF
3270 NEXT i%
3280 IF pass% = 1 THEN PRINT "PASS: array expr matches FOR loop" ELSE PRINT "FAIL: expr vs loop"
3290 PRINT "All array expression edge case tests complete."
3300 END
