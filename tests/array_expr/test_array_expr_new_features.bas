10 REM Test: New array expression features
20 REM Tests BYTE/SHORT types, compound FMA, reductions, and unary array functions
30 REM ============================================================
40 REM Test 1: BYTE array add
50 REM ============================================================
60 DIM AB(15) AS BYTE
70 DIM BB(15) AS BYTE
80 DIM CB(15) AS BYTE
90 FOR i% = 0 TO 15
100   AB(i%) = i% + 1
110   BB(i%) = 10
120 NEXT i%
130 CB() = AB() + BB()
140 DIM pass% AS INTEGER
150 pass% = 1
160 FOR i% = 0 TO 15
170   IF CB(i%) <> (i% + 1) + 10 THEN
180     PRINT "FAIL byte add at "; i%; ": got "; CB(i%); " expected "; (i% + 1) + 10
190     pass% = 0
200   ENDIF
210 NEXT i%
220 IF pass% = 1 THEN PRINT "PASS: array add BYTE" ELSE PRINT "FAIL: array add BYTE"
230 REM ============================================================
240 REM Test 2: BYTE array subtract
250 REM ============================================================
260 CB() = AB() - BB()
270 pass% = 1
280 FOR i% = 0 TO 15
290   IF CB(i%) <> (i% + 1) - 10 THEN pass% = 0
300 NEXT i%
310 IF pass% = 1 THEN PRINT "PASS: array subtract BYTE" ELSE PRINT "FAIL: array subtract BYTE"
320 REM ============================================================
330 REM Test 3: BYTE array copy
340 REM ============================================================
350 DIM DB(15) AS BYTE
360 DB() = AB()
370 pass% = 1
380 FOR i% = 0 TO 15
390   IF DB(i%) <> AB(i%) THEN pass% = 0
400 NEXT i%
410 IF pass% = 1 THEN PRINT "PASS: array copy BYTE" ELSE PRINT "FAIL: array copy BYTE"
420 REM ============================================================
430 REM Test 4: BYTE array fill
440 REM ============================================================
450 DB() = 42
460 pass% = 1
470 FOR i% = 0 TO 15
480   IF DB(i%) <> 42 THEN pass% = 0
490 NEXT i%
500 IF pass% = 1 THEN PRINT "PASS: array fill BYTE" ELSE PRINT "FAIL: array fill BYTE"
510 REM ============================================================
520 REM Test 5: BYTE array negate
530 REM ============================================================
540 DIM EB(7) AS BYTE
550 DIM FB(7) AS BYTE
560 FOR i% = 0 TO 7
570   EB(i%) = i% + 1
580 NEXT i%
590 FB() = -EB()
600 pass% = 1
610 FOR i% = 0 TO 7
620   IF FB(i%) <> -(i% + 1) THEN pass% = 0
630 NEXT i%
640 IF pass% = 1 THEN PRINT "PASS: array negate BYTE" ELSE PRINT "FAIL: array negate BYTE"
650 REM ============================================================
660 REM Test 6: BYTE scalar broadcast
670 REM ============================================================
680 CB() = AB() * 2
690 pass% = 1
700 FOR i% = 0 TO 15
710   IF CB(i%) <> (i% + 1) * 2 THEN pass% = 0
720 NEXT i%
730 IF pass% = 1 THEN PRINT "PASS: array broadcast BYTE * 2" ELSE PRINT "FAIL: array broadcast BYTE * 2"
740 REM ============================================================
750 REM Test 7: SHORT array add
760 REM ============================================================
770 DIM AW(10) AS SHORT
780 DIM BS(10) AS SHORT
790 DIM CS(10) AS SHORT
800 FOR i% = 0 TO 10
810   AW(i%) = (i% + 1) * 100
820   BS(i%) = 50
830 NEXT i%
840 CS() = AW() + BS()
850 pass% = 1
860 FOR i% = 0 TO 10
870   IF CS(i%) <> (i% + 1) * 100 + 50 THEN
880     PRINT "FAIL short add at "; i%; ": got "; CS(i%); " expected "; (i% + 1) * 100 + 50
890     pass% = 0
900   ENDIF
910 NEXT i%
920 IF pass% = 1 THEN PRINT "PASS: array add SHORT" ELSE PRINT "FAIL: array add SHORT"
930 REM ============================================================
940 REM Test 8: SHORT array subtract
950 REM ============================================================
960 CS() = AW() - BS()
970 pass% = 1
980 FOR i% = 0 TO 10
990   IF CS(i%) <> (i% + 1) * 100 - 50 THEN pass% = 0
1000 NEXT i%
1010 IF pass% = 1 THEN PRINT "PASS: array subtract SHORT" ELSE PRINT "FAIL: array subtract SHORT"
1020 REM ============================================================
1030 REM Test 9: SHORT array multiply
1040 REM ============================================================
1050 DIM DS(10) AS SHORT
1060 FOR i% = 0 TO 10
1070   BS(i%) = 3
1080 NEXT i%
1090 DS() = AW() * BS()
1100 pass% = 1
1110 FOR i% = 0 TO 10
1120   IF DS(i%) <> (i% + 1) * 100 * 3 THEN pass% = 0
1130 NEXT i%
1140 IF pass% = 1 THEN PRINT "PASS: array multiply SHORT" ELSE PRINT "FAIL: array multiply SHORT"
1150 REM ============================================================
1160 REM Test 10: SHORT array copy
1170 REM ============================================================
1180 DIM ES(10) AS SHORT
1190 ES() = AW()
1200 pass% = 1
1210 FOR i% = 0 TO 10
1220   IF ES(i%) <> AW(i%) THEN pass% = 0
1230 NEXT i%
1240 IF pass% = 1 THEN PRINT "PASS: array copy SHORT" ELSE PRINT "FAIL: array copy SHORT"
1250 REM ============================================================
1260 REM Test 11: SHORT array fill
1270 REM ============================================================
1280 ES() = 999
1290 pass% = 1
1300 FOR i% = 0 TO 10
1310   IF ES(i%) <> 999 THEN pass% = 0
1320 NEXT i%
1330 IF pass% = 1 THEN PRINT "PASS: array fill SHORT" ELSE PRINT "FAIL: array fill SHORT"
1340 REM ============================================================
1350 REM Test 12: SHORT array negate
1360 REM ============================================================
1370 DIM FS(10) AS SHORT
1380 FS() = -AW()
1390 pass% = 1
1400 FOR i% = 0 TO 10
1410   IF FS(i%) <> -((i% + 1) * 100) THEN pass% = 0
1420 NEXT i%
1430 IF pass% = 1 THEN PRINT "PASS: array negate SHORT" ELSE PRINT "FAIL: array negate SHORT"
1440 REM ============================================================
1450 REM Test 13: SHORT scalar broadcast
1460 REM ============================================================
1470 CS() = AW() + 7
1480 pass% = 1
1490 FOR i% = 0 TO 10
1500   IF CS(i%) <> (i% + 1) * 100 + 7 THEN pass% = 0
1510 NEXT i%
1520 IF pass% = 1 THEN PRINT "PASS: array broadcast SHORT + 7" ELSE PRINT "FAIL: array broadcast SHORT + 7"
1530 REM ============================================================
1540 REM Test 14: BYTE adjacency check (verify no corruption)
1550 REM Ensures store operations use storeb, not storew
1560 REM ============================================================
1570 DIM checkB(3) AS BYTE
1580 checkB(0) = 11
1590 checkB(1) = 22
1600 checkB(2) = 33
1610 checkB(3) = 44
1620 DIM oneB(3) AS BYTE
1630 oneB(0) = 1
1640 oneB(1) = 1
1650 oneB(2) = 1
1660 oneB(3) = 1
1670 DIM resB(3) AS BYTE
1680 resB() = checkB() + oneB()
1690 IF resB(0) = 12 AND resB(1) = 23 AND resB(2) = 34 AND resB(3) = 45 THEN PRINT "PASS: BYTE adjacency intact" ELSE PRINT "FAIL: BYTE adjacency corrupted"
1700 REM ============================================================
1710 REM Test 15: SHORT adjacency check
1720 REM ============================================================
1730 DIM checkS(3) AS SHORT
1740 checkS(0) = 1000
1750 checkS(1) = 2000
1760 checkS(2) = 3000
1770 checkS(3) = 4000
1780 DIM oneS(3) AS SHORT
1790 oneS(0) = 1
1800 oneS(1) = 1
1810 oneS(2) = 1
1820 oneS(3) = 1
1830 DIM resS(3) AS SHORT
1840 resS() = checkS() + oneS()
1850 IF resS(0) = 1001 AND resS(1) = 2001 AND resS(2) = 3001 AND resS(3) = 4001 THEN PRINT "PASS: SHORT adjacency intact" ELSE PRINT "FAIL: SHORT adjacency corrupted"
1860 REM ============================================================
1870 REM Test 16: Compound FMA — D() = A() + B() * C()
1880 REM ============================================================
1890 DIM FA(10) AS SINGLE
1900 DIM FBB(10) AS SINGLE
1910 DIM FC(10) AS SINGLE
1920 DIM FD(10) AS SINGLE
1930 FOR i% = 0 TO 10
1940   FA(i%) = i% * 1.0
1950   FBB(i%) = 2.0
1960   FC(i%) = (i% + 1) * 0.5
1970 NEXT i%
1980 FD() = FA() + FBB() * FC()
1990 pass% = 1
2000 FOR i% = 0 TO 10
2010   DIM expected! AS SINGLE
2020   expected! = FA(i%) + FBB(i%) * FC(i%)
2030   IF FD(i%) <> expected! THEN
2040     PRINT "FAIL FMA at "; i%; ": got "; FD(i%); " expected "; expected!
2050     pass% = 0
2060   ENDIF
2070 NEXT i%
2080 IF pass% = 1 THEN PRINT "PASS: FMA D() = A() + B() * C() SINGLE" ELSE PRINT "FAIL: FMA SINGLE"
2090 REM ============================================================
2100 REM Test 17: FMA commuted — D() = B() * C() + A()
2110 REM ============================================================
2120 DIM FE(10) AS SINGLE
2130 FE() = FBB() * FC() + FA()
2140 pass% = 1
2150 FOR i% = 0 TO 10
2160   IF FE(i%) <> FD(i%) THEN
2170     PRINT "FAIL FMA commuted at "; i%; ": got "; FE(i%); " expected "; FD(i%)
2180     pass% = 0
2190   ENDIF
2200 NEXT i%
2210 IF pass% = 1 THEN PRINT "PASS: FMA commuted B()*C()+A() SINGLE" ELSE PRINT "FAIL: FMA commuted"
2220 REM ============================================================
2230 REM Test 18: FMA with INTEGER arrays
2240 REM ============================================================
2250 DIM IA(8) AS INTEGER
2260 DIM IB(8) AS INTEGER
2270 DIM IC(8) AS INTEGER
2280 DIM ID(8) AS INTEGER
2290 FOR i% = 0 TO 8
2300   IA(i%) = i%
2310   IB(i%) = 3
2320   IC(i%) = i% + 1
2330 NEXT i%
2340 ID() = IA() + IB() * IC()
2350 pass% = 1
2360 FOR i% = 0 TO 8
2370   IF ID(i%) <> i% + 3 * (i% + 1) THEN
2380     PRINT "FAIL FMA INT at "; i%; ": got "; ID(i%); " expected "; i% + 3 * (i% + 1)
2390     pass% = 0
2400   ENDIF
2410 NEXT i%
2420 IF pass% = 1 THEN PRINT "PASS: FMA D() = A() + B() * C() INTEGER" ELSE PRINT "FAIL: FMA INTEGER"
2430 REM ============================================================
2440 REM Test 19: FMA with DOUBLE arrays
2450 REM ============================================================
2460 DIM DA(6) AS DOUBLE
2470 DIM DBB(6) AS DOUBLE
2480 DIM DC(6) AS DOUBLE
2490 DIM DD(6) AS DOUBLE
2500 FOR i% = 0 TO 6
2510   DA(i%) = i% * 1.1
2520   DBB(i%) = 2.5
2530   DC(i%) = (i% + 1) * 0.3
2540 NEXT i%
2550 DD() = DA() + DBB() * DC()
2560 pass% = 1
2570 FOR i% = 0 TO 6
2580   DIM dexp# AS DOUBLE
2590   dexp# = DA(i%) + DBB(i%) * DC(i%)
2600   IF DD(i%) <> dexp# THEN
2610     PRINT "FAIL FMA DOUBLE at "; i%; ": got "; DD(i%); " expected "; dexp#
2620     pass% = 0
2630   ENDIF
2640 NEXT i%
2650 IF pass% = 1 THEN PRINT "PASS: FMA D() = A() + B() * C() DOUBLE" ELSE PRINT "FAIL: FMA DOUBLE"
2660 REM ============================================================
2670 REM Test 20: SUM() reduction — SINGLE
2680 REM ============================================================
2690 DIM SA(5) AS SINGLE
2700 FOR i% = 0 TO 5
2710   SA(i%) = (i% + 1) * 1.0
2720 NEXT i%
2730 REM SA = 1+2+3+4+5+6 = 21
2740 DIM total! AS SINGLE
2750 total! = SUM(SA())
2760 IF total! = 21.0 THEN PRINT "PASS: SUM() SINGLE = 21" ELSE PRINT "FAIL: SUM() SINGLE got "; total!
2770 REM ============================================================
2780 REM Test 21: SUM() reduction — INTEGER
2790 REM ============================================================
2800 DIM SI(9) AS INTEGER
2810 FOR i% = 0 TO 9
2820   SI(i%) = i% + 1
2830 NEXT i%
2840 REM SI = 1+2+...+10 = 55
2850 DIM itotal% AS INTEGER
2860 itotal% = SUM(SI())
2870 IF itotal% = 55 THEN PRINT "PASS: SUM() INTEGER = 55" ELSE PRINT "FAIL: SUM() INTEGER got "; itotal%
2880 REM ============================================================
2890 REM Test 22: MAX() reduction
2900 REM ============================================================
2910 DIM MA(7) AS SINGLE
2920 MA(0) = 3.0
2930 MA(1) = 7.5
2940 MA(2) = 1.0
2950 MA(3) = 9.0
2960 MA(4) = 2.5
2970 MA(5) = 8.0
2980 MA(6) = 4.0
2990 MA(7) = 6.0
3000 DIM maxval! AS SINGLE
3010 maxval! = MAX(MA())
3020 IF maxval! = 9.0 THEN PRINT "PASS: MAX() SINGLE = 9.0" ELSE PRINT "FAIL: MAX() SINGLE got "; maxval!
3030 REM ============================================================
3040 REM Test 23: MIN() reduction
3050 REM ============================================================
3060 DIM minval! AS SINGLE
3070 minval! = MIN(MA())
3080 IF minval! = 1.0 THEN PRINT "PASS: MIN() SINGLE = 1.0" ELSE PRINT "FAIL: MIN() SINGLE got "; minval!
3090 REM ============================================================
3100 REM Test 24: AVG() reduction
3110 REM ============================================================
3120 DIM avgA(3) AS SINGLE
3130 avgA(0) = 10.0
3140 avgA(1) = 20.0
3150 avgA(2) = 30.0
3160 avgA(3) = 40.0
3170 DIM avgval! AS SINGLE
3180 avgval! = AVG(avgA())
3190 IF avgval! = 25.0 THEN PRINT "PASS: AVG() SINGLE = 25.0" ELSE PRINT "FAIL: AVG() SINGLE got "; avgval!
3200 REM ============================================================
3210 REM Test 25: DOT() product
3220 REM ============================================================
3230 DIM dotA(3) AS SINGLE
3240 DIM dotB(3) AS SINGLE
3250 dotA(0) = 1.0
3260 dotA(1) = 2.0
3270 dotA(2) = 3.0
3280 dotA(3) = 4.0
3290 dotB(0) = 5.0
3300 dotB(1) = 6.0
3310 dotB(2) = 7.0
3320 dotB(3) = 8.0
3330 REM DOT = 1*5 + 2*6 + 3*7 + 4*8 = 5+12+21+32 = 70
3340 DIM dotval! AS SINGLE
3350 dotval! = DOT(dotA(), dotB())
3360 IF dotval! = 70.0 THEN PRINT "PASS: DOT() SINGLE = 70.0" ELSE PRINT "FAIL: DOT() SINGLE got "; dotval!
3370 REM ============================================================
3380 REM Test 26: MAX() INTEGER reduction
3390 REM ============================================================
3400 DIM MI(5) AS INTEGER
3410 MI(0) = 42
3420 MI(1) = 17
3430 MI(2) = 99
3440 MI(3) = 3
3450 MI(4) = 88
3460 MI(5) = 55
3470 DIM imax% AS INTEGER
3480 imax% = MAX(MI())
3490 IF imax% = 99 THEN PRINT "PASS: MAX() INTEGER = 99" ELSE PRINT "FAIL: MAX() INTEGER got "; imax%
3500 REM ============================================================
3510 REM Test 27: MIN() INTEGER reduction
3520 REM ============================================================
3530 DIM imin% AS INTEGER
3540 imin% = MIN(MI())
3550 IF imin% = 3 THEN PRINT "PASS: MIN() INTEGER = 3" ELSE PRINT "FAIL: MIN() INTEGER got "; imin%
3560 REM ============================================================
3570 REM Test 28: ABS() element-wise — SINGLE
3580 REM ============================================================
3590 DIM absA(7) AS SINGLE
3600 DIM absB(7) AS SINGLE
3610 absA(0) = -3.5
3620 absA(1) = 2.0
3630 absA(2) = -7.25
3640 absA(3) = 0.0
3650 absA(4) = -1.0
3660 absA(5) = 5.5
3670 absA(6) = -0.5
3680 absA(7) = 100.0
3690 absB() = ABS(absA())
3700 pass% = 1
3710 IF absB(0) <> 3.5 THEN pass% = 0
3720 IF absB(1) <> 2.0 THEN pass% = 0
3730 IF absB(2) <> 7.25 THEN pass% = 0
3740 IF absB(3) <> 0.0 THEN pass% = 0
3750 IF absB(4) <> 1.0 THEN pass% = 0
3760 IF absB(5) <> 5.5 THEN pass% = 0
3770 IF absB(6) <> 0.5 THEN pass% = 0
3780 IF absB(7) <> 100.0 THEN pass% = 0
3790 IF pass% = 1 THEN PRINT "PASS: ABS() element-wise SINGLE" ELSE PRINT "FAIL: ABS() element-wise SINGLE"
3800 REM ============================================================
3810 REM Test 29: ABS() element-wise — INTEGER
3820 REM ============================================================
3830 DIM absI(5) AS INTEGER
3840 DIM absIR(5) AS INTEGER
3850 absI(0) = -10
3860 absI(1) = 20
3870 absI(2) = -30
3880 absI(3) = 0
3890 absI(4) = -1
3900 absI(5) = 99
3910 absIR() = ABS(absI())
3920 pass% = 1
3930 IF absIR(0) <> 10 THEN pass% = 0
3940 IF absIR(1) <> 20 THEN pass% = 0
3950 IF absIR(2) <> 30 THEN pass% = 0
3960 IF absIR(3) <> 0 THEN pass% = 0
3970 IF absIR(4) <> 1 THEN pass% = 0
3980 IF absIR(5) <> 99 THEN pass% = 0
3990 IF pass% = 1 THEN PRINT "PASS: ABS() element-wise INTEGER" ELSE PRINT "FAIL: ABS() element-wise INTEGER"
4000 REM ============================================================
4010 REM Test 30: SQR() element-wise — SINGLE
4020 REM ============================================================
4030 DIM sqA(3) AS SINGLE
4040 DIM sqB(3) AS SINGLE
4050 sqA(0) = 1.0
4060 sqA(1) = 4.0
4070 sqA(2) = 9.0
4080 sqA(3) = 16.0
4090 sqB() = SQR(sqA())
4100 pass% = 1
4110 IF sqB(0) <> 1.0 THEN pass% = 0
4120 IF sqB(1) <> 2.0 THEN pass% = 0
4130 IF sqB(2) <> 3.0 THEN pass% = 0
4140 IF sqB(3) <> 4.0 THEN pass% = 0
4150 IF pass% = 1 THEN PRINT "PASS: SQR() element-wise SINGLE" ELSE PRINT "FAIL: SQR() element-wise SINGLE"
4160 REM ============================================================
4170 REM Test 31: SQR() element-wise — DOUBLE
4180 REM ============================================================
4190 DIM sqDA(3) AS DOUBLE
4200 DIM sqDB(3) AS DOUBLE
4210 sqDA(0) = 25.0
4220 sqDA(1) = 100.0
4230 sqDA(2) = 49.0
4240 sqDA(3) = 64.0
4250 sqDB() = SQR(sqDA())
4260 pass% = 1
4270 IF sqDB(0) <> 5.0 THEN pass% = 0
4280 IF sqDB(1) <> 10.0 THEN pass% = 0
4290 IF sqDB(2) <> 7.0 THEN pass% = 0
4300 IF sqDB(3) <> 8.0 THEN pass% = 0
4310 IF pass% = 1 THEN PRINT "PASS: SQR() element-wise DOUBLE" ELSE PRINT "FAIL: SQR() element-wise DOUBLE"
4320 REM ============================================================
4330 REM Test 32: SUM() with DOUBLE for precision check
4340 REM ============================================================
4350 DIM SD(3) AS DOUBLE
4360 SD(0) = 0.1
4370 SD(1) = 0.2
4380 SD(2) = 0.3
4390 SD(3) = 0.4
4400 DIM dtotal# AS DOUBLE
4410 dtotal# = SUM(SD())
4420 REM 0.1+0.2+0.3+0.4 = 1.0 (exact in double)
4430 IF dtotal# = 1.0 THEN PRINT "PASS: SUM() DOUBLE = 1.0" ELSE PRINT "FAIL: SUM() DOUBLE got "; dtotal#
4440 REM ============================================================
4450 REM Test 33: Verify scalar MAX/MIN still work (2-arg overload)
4460 REM ============================================================
4470 DIM scmax% AS INTEGER
4480 scmax% = MAX(10, 20)
4490 IF scmax% = 20 THEN PRINT "PASS: scalar MAX(10,20) = 20" ELSE PRINT "FAIL: scalar MAX got "; scmax%
4500 DIM scmin% AS INTEGER
4510 scmin% = MIN(10, 20)
4520 IF scmin% = 10 THEN PRINT "PASS: scalar MIN(10,20) = 10" ELSE PRINT "FAIL: scalar MIN got "; scmin%
4530 REM ============================================================
4540 PRINT "All new array expression feature tests complete."
4550 END
