10 REM Test: Dedicated neondup (broadcast) and neonneg (vector negation) opcodes
20 REM Exercises the optimized NEON opcode paths introduced to replace
30 REM manual lane-by-lane broadcast and zero-subtract workarounds.
40 REM These tests specifically target emitArrayFill (neondup) and
50 REM emitArrayNegate (neonneg) code paths in the AST emitter.
55 REM NOTE: Fill values must be exactly representable in the target type
56 REM to avoid false failures from FP comparison imprecision.
60 DIM pass% AS INTEGER
70 REM ============================================================
80 REM PART 1: neondup — array fill broadcast tests
90 REM ============================================================
100 REM Test 1: Fill SINGLE array with positive value (4 lanes per NEON reg)
110 DIM FS(15) AS SINGLE
120 FS() = 3.25
130 pass% = 1
140 FOR i% = 0 TO 15
150   IF FS(i%) <> 3.25 THEN
160     PRINT "FAIL: fill single 3.25 at "; i%; ": got "; FS(i%)
170     pass% = 0
180   ENDIF
190 NEXT i%
200 IF pass% = 1 THEN PRINT "PASS: neondup fill SINGLE 3.25 (16 elements)" ELSE PRINT "FAIL: neondup fill SINGLE"
210 REM Test 2: Fill SINGLE array with negative value
220 DIM FSN(11) AS SINGLE
230 FSN() = -42.5
240 pass% = 1
250 FOR i% = 0 TO 11
260   IF FSN(i%) <> -42.5 THEN
270     PRINT "FAIL: fill single -42.5 at "; i%; ": got "; FSN(i%)
280     pass% = 0
290   ENDIF
300 NEXT i%
310 IF pass% = 1 THEN PRINT "PASS: neondup fill SINGLE -42.5 (12 elements)" ELSE PRINT "FAIL: neondup fill SINGLE neg"
320 REM Test 3: Fill SINGLE array with zero
330 DIM FSZ(9) AS SINGLE
340 FOR i% = 0 TO 9
350   FSZ(i%) = 999.0
360 NEXT i%
370 FSZ() = 0.0
380 pass% = 1
390 FOR i% = 0 TO 9
400   IF FSZ(i%) <> 0.0 THEN
410     PRINT "FAIL: fill single zero at "; i%; ": got "; FSZ(i%)
420     pass% = 0
430   ENDIF
440 NEXT i%
450 IF pass% = 1 THEN PRINT "PASS: neondup fill SINGLE zero (10 elements)" ELSE PRINT "FAIL: neondup fill SINGLE zero"
460 REM Test 4: Fill INTEGER array (32-bit integer lanes via neondup)
470 DIM FI(19) AS INTEGER
480 FI() = 12345
490 pass% = 1
500 FOR i% = 0 TO 19
510   IF FI(i%) <> 12345 THEN
520     PRINT "FAIL: fill int 12345 at "; i%; ": got "; FI(i%)
530     pass% = 0
540   ENDIF
550 NEXT i%
560 IF pass% = 1 THEN PRINT "PASS: neondup fill INTEGER 12345 (20 elements)" ELSE PRINT "FAIL: neondup fill INTEGER"
570 REM Test 5: Fill INTEGER array with negative
580 DIM FIN(7) AS INTEGER
590 FIN() = -9999
600 pass% = 1
610 FOR i% = 0 TO 7
620   IF FIN(i%) <> -9999 THEN
630     PRINT "FAIL: fill int -9999 at "; i%; ": got "; FIN(i%)
640     pass% = 0
650   ENDIF
660 NEXT i%
670 IF pass% = 1 THEN PRINT "PASS: neondup fill INTEGER -9999 (8 elements)" ELSE PRINT "FAIL: neondup fill INTEGER neg"
680 REM Test 6: Fill DOUBLE array (2 lanes per NEON reg — stack-slot broadcast)
690 DIM FD(9) AS DOUBLE
700 FD() = 2.75
710 pass% = 1
720 FOR i% = 0 TO 9
730   IF FD(i%) <> 2.75 THEN
740     PRINT "FAIL: fill double at "; i%; ": got "; FD(i%)
750     pass% = 0
760   ENDIF
770 NEXT i%
780 IF pass% = 1 THEN PRINT "PASS: fill DOUBLE 2.75 (10 elements)" ELSE PRINT "FAIL: fill DOUBLE"
790 REM Test 7: Fill DOUBLE array with negative
800 DIM FDN(6) AS DOUBLE
810 FDN() = -1.25
820 pass% = 1
830 FOR i% = 0 TO 6
840   IF FDN(i%) <> -1.25 THEN
850     PRINT "FAIL: fill double neg at "; i%; ": got "; FDN(i%)
860     pass% = 0
870   ENDIF
880 NEXT i%
890 IF pass% = 1 THEN PRINT "PASS: fill DOUBLE negative -1.25 (7 elements)" ELSE PRINT "FAIL: fill DOUBLE neg"
900 REM Test 8: Fill with remainder — 5 SINGLE elements (4+1 remainder)
910 DIM FR5(4) AS SINGLE
920 FR5() = 7.75
930 pass% = 1
940 FOR i% = 0 TO 4
950   IF FR5(i%) <> 7.75 THEN
960     PRINT "FAIL: fill 5-elem at "; i%; ": got "; FR5(i%)
970     pass% = 0
980   ENDIF
990 NEXT i%
1000 IF pass% = 1 THEN PRINT "PASS: neondup fill SINGLE remainder (5 elements)" ELSE PRINT "FAIL: neondup fill remainder"
1010 REM Test 9: Fill single-element array (pure remainder, no NEON iter)
1020 DIM FR1(0) AS SINGLE
1030 FR1() = 99.5
1040 IF FR1(0) = 99.5 THEN PRINT "PASS: neondup fill SINGLE length-1" ELSE PRINT "FAIL: neondup fill length-1: got "; FR1(0)
1050 REM Test 10: Fill then overwrite — ensure neondup doesn't leave stale data
1060 DIM FOV(7) AS SINGLE
1070 FOV() = 111.0
1080 FOV() = 222.0
1090 pass% = 1
1100 FOR i% = 0 TO 7
1110   IF FOV(i%) <> 222.0 THEN
1120     PRINT "FAIL: fill overwrite at "; i%; ": got "; FOV(i%)
1130     pass% = 0
1140   ENDIF
1150 NEXT i%
1160 IF pass% = 1 THEN PRINT "PASS: neondup fill overwrite (no stale data)" ELSE PRINT "FAIL: neondup fill overwrite"
1170 REM ============================================================
1180 REM PART 2: neonneg — array negation tests
1190 REM ============================================================
1200 REM Test 11: Negate SINGLE array (positive source)
1210 DIM NS(15) AS SINGLE
1220 DIM NSD(15) AS SINGLE
1230 FOR i% = 0 TO 15
1240   NS(i%) = (i% + 1) * 1.5
1250 NEXT i%
1260 NSD() = -NS()
1270 pass% = 1
1280 FOR i% = 0 TO 15
1290   IF NSD(i%) <> -(i% + 1) * 1.5 THEN
1300     PRINT "FAIL: negate single at "; i%; ": got "; NSD(i%); " expected "; -(i% + 1) * 1.5
1310     pass% = 0
1320   ENDIF
1330 NEXT i%
1340 IF pass% = 1 THEN PRINT "PASS: neonneg SINGLE positive (16 elements)" ELSE PRINT "FAIL: neonneg SINGLE"
1350 REM Test 12: Negate SINGLE array (negative source → positive result)
1360 DIM NNS(11) AS SINGLE
1370 DIM NNSD(11) AS SINGLE
1380 FOR i% = 0 TO 11
1390   NNS(i%) = -(i% + 1) * 2.0
1400 NEXT i%
1410 NNSD() = -NNS()
1420 pass% = 1
1430 FOR i% = 0 TO 11
1440   IF NNSD(i%) <> (i% + 1) * 2.0 THEN
1450     PRINT "FAIL: negate neg-to-pos at "; i%; ": got "; NNSD(i%)
1460     pass% = 0
1470   ENDIF
1480 NEXT i%
1490 IF pass% = 1 THEN PRINT "PASS: neonneg SINGLE neg-to-pos (12 elements)" ELSE PRINT "FAIL: neonneg neg-to-pos"
1500 REM Test 13: Negate zero array — should remain zero (no sign bit issues)
1510 DIM NZ(7) AS SINGLE
1520 DIM NZR(7) AS SINGLE
1530 NZ() = 0.0
1540 NZR() = -NZ()
1550 pass% = 1
1560 FOR i% = 0 TO 7
1570   IF NZR(i%) <> 0.0 THEN
1580     PRINT "FAIL: negate zero at "; i%; ": got "; NZR(i%)
1590     pass% = 0
1600   ENDIF
1610 NEXT i%
1620 IF pass% = 1 THEN PRINT "PASS: neonneg SINGLE zero array (8 elements)" ELSE PRINT "FAIL: neonneg zero"
1630 REM Test 14: Negate INTEGER array
1640 DIM NI(19) AS INTEGER
1650 DIM NID(19) AS INTEGER
1660 FOR i% = 0 TO 19
1670   NI(i%) = (i% + 1) * 100
1680 NEXT i%
1690 NID() = -NI()
1700 pass% = 1
1710 FOR i% = 0 TO 19
1720   IF NID(i%) <> -(i% + 1) * 100 THEN
1730     PRINT "FAIL: negate int at "; i%; ": got "; NID(i%)
1740     pass% = 0
1750   ENDIF
1760 NEXT i%
1770 IF pass% = 1 THEN PRINT "PASS: neonneg INTEGER (20 elements)" ELSE PRINT "FAIL: neonneg INTEGER"
1780 REM Test 15: Negate DOUBLE array (2 lanes per NEON reg)
1790 DIM ND(9) AS DOUBLE
1800 DIM NDD(9) AS DOUBLE
1810 FOR i% = 0 TO 9
1820   ND(i%) = (i% + 1) * 1.111111111111
1830 NEXT i%
1840 NDD() = -ND()
1850 pass% = 1
1860 FOR i% = 0 TO 9
1870   IF NDD(i%) <> -(i% + 1) * 1.111111111111 THEN
1880     PRINT "FAIL: negate double at "; i%; ": got "; NDD(i%)
1890     pass% = 0
1900   ENDIF
1910 NEXT i%
1920 IF pass% = 1 THEN PRINT "PASS: neonneg DOUBLE (10 elements)" ELSE PRINT "FAIL: neonneg DOUBLE"
1930 REM Test 16: Negate with remainder — 5 SINGLE elements (4+1 remainder)
1940 DIM NR5(4) AS SINGLE
1950 DIM NR5D(4) AS SINGLE
1960 FOR i% = 0 TO 4
1970   NR5(i%) = (i% + 1) * 10.0
1980 NEXT i%
1990 NR5D() = -NR5()
2000 pass% = 1
2010 FOR i% = 0 TO 4
2020   IF NR5D(i%) <> -(i% + 1) * 10.0 THEN
2030     PRINT "FAIL: negate 5-elem at "; i%; ": got "; NR5D(i%)
2040     pass% = 0
2050   ENDIF
2060 NEXT i%
2070 IF pass% = 1 THEN PRINT "PASS: neonneg SINGLE remainder (5 elements)" ELSE PRINT "FAIL: neonneg remainder"
2080 REM Test 17: Negate single-element array (pure remainder path)
2090 DIM NR1(0) AS SINGLE
2100 NR1(0) = 77.0
2110 DIM NR1D(0) AS SINGLE
2120 NR1D() = -NR1()
2130 IF NR1D(0) = -77.0 THEN PRINT "PASS: neonneg SINGLE length-1" ELSE PRINT "FAIL: neonneg length-1: got "; NR1D(0)
2140 REM Test 18: Double negate — negate(negate(A)) should equal A
2150 DIM DN(7) AS SINGLE
2160 DIM DN1(7) AS SINGLE
2170 DIM DN2(7) AS SINGLE
2180 FOR i% = 0 TO 7
2190   DN(i%) = (i% + 1) * 3.5
2200 NEXT i%
2210 DN1() = -DN()
2220 DN2() = -DN1()
2230 pass% = 1
2240 FOR i% = 0 TO 7
2250   IF DN2(i%) <> DN(i%) THEN
2260     PRINT "FAIL: double negate at "; i%; ": got "; DN2(i%); " expected "; DN(i%)
2270     pass% = 0
2280   ENDIF
2290 NEXT i%
2300 IF pass% = 1 THEN PRINT "PASS: neonneg double negate = identity" ELSE PRINT "FAIL: double negate"
2310 REM Test 19: Source unchanged after negate
2320 DIM SU(7) AS SINGLE
2330 DIM SUR(7) AS SINGLE
2340 FOR i% = 0 TO 7
2350   SU(i%) = (i% + 1) * 5.0
2360 NEXT i%
2370 SUR() = -SU()
2380 pass% = 1
2390 FOR i% = 0 TO 7
2400   IF SU(i%) <> (i% + 1) * 5.0 THEN
2410     PRINT "FAIL: source changed at "; i%; ": got "; SU(i%)
2420     pass% = 0
2430   ENDIF
2440 NEXT i%
2450 IF pass% = 1 THEN PRINT "PASS: neonneg source array unchanged" ELSE PRINT "FAIL: source changed"
2460 REM ============================================================
2470 REM PART 3: Combined neondup + neonneg interaction
2480 REM ============================================================
2490 REM Test 20: Fill then negate — neondup followed by neonneg
2500 DIM CF(11) AS SINGLE
2510 DIM CFN(11) AS SINGLE
2520 CF() = 25.0
2530 CFN() = -CF()
2540 pass% = 1
2550 FOR i% = 0 TO 11
2560   IF CFN(i%) <> -25.0 THEN
2570     PRINT "FAIL: fill-then-negate at "; i%; ": got "; CFN(i%)
2580     pass% = 0
2590   ENDIF
2600 NEXT i%
2610 IF pass% = 1 THEN PRINT "PASS: neondup fill then neonneg negate" ELSE PRINT "FAIL: fill-then-negate"
2620 REM Test 21: Fill with large value then negate (stress test broadcast precision)
2630 DIM CLRG(15) AS SINGLE
2640 DIM CLRGN(15) AS SINGLE
2650 CLRG() = 1000000.0
2660 CLRGN() = -CLRG()
2670 pass% = 1
2680 FOR i% = 0 TO 15
2690   IF CLRGN(i%) <> -1000000.0 THEN
2700     PRINT "FAIL: large fill-negate at "; i%; ": got "; CLRGN(i%)
2710     pass% = 0
2720   ENDIF
2730 NEXT i%
2740 IF pass% = 1 THEN PRINT "PASS: neondup + neonneg large values" ELSE PRINT "FAIL: large fill-negate"
2750 REM Test 22: Fill DOUBLE, negate, verify precision
2760 DIM FDD(5) AS DOUBLE
2770 DIM FDDN(5) AS DOUBLE
2780 FDD() = 3.125
2790 FDDN() = -FDD()
2800 pass% = 1
2810 FOR i% = 0 TO 5
2820   IF FDDN(i%) <> -3.125 THEN
2830     PRINT "FAIL: double fill-negate at "; i%; ": got "; FDDN(i%)
2840     pass% = 0
2850   ENDIF
2860 NEXT i%
2870 IF pass% = 1 THEN PRINT "PASS: neondup + neonneg DOUBLE precision" ELSE PRINT "FAIL: double fill-negate"
2880 REM ============================================================
2890 PRINT "All neondup/neonneg opcode tests complete."
2900 END
