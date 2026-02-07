10 REM Test: Assembly verification — confirm NEON instructions are emitted
20 REM
30 REM This test is designed to be compiled with -c (assembly output)
40 REM and then grepped for NEON-specific ARM64 instructions.
50 REM
60 REM It also runs as a normal correctness test to verify results.
70 REM
80 REM Usage for assembly verification:
90 REM   ./fbc_qbe tests/neon/test_neon_asm_verify.bas -c -o /tmp/neon_asm.s
91 REM   grep -c 'ldr.*q28' /tmp/neon_asm.s    # expect > 0
92 REM   grep -c 'str.*q28' /tmp/neon_asm.s    # expect > 0
93 REM   grep -c 'add.*v28' /tmp/neon_asm.s    # expect > 0
94 REM   grep -c 'sub.*v28' /tmp/neon_asm.s    # expect > 0
95 REM   grep -c 'mul.*v28' /tmp/neon_asm.s    # expect > 0
96 REM   grep -c 'fadd.*v28' /tmp/neon_asm.s   # expect > 0
97 REM   grep -c 'fdiv.*v28' /tmp/neon_asm.s   # expect > 0
98 REM
99 REM === Section 1: Vec4 (integer 4×32-bit, V4S) ===
100 TYPE Vec4
110   X AS INTEGER
120   Y AS INTEGER
130   Z AS INTEGER
140   W AS INTEGER
150 END TYPE
160 REM
170 REM === Section 2: Vec4F (float 4×32-bit, V4S float) ===
180 TYPE Vec4F
190   X AS SINGLE
200   Y AS SINGLE
210   Z AS SINGLE
220   W AS SINGLE
230 END TYPE
240 REM
250 REM === Section 3: Vec2D (double 2×64-bit, V2D) ===
260 TYPE Vec2D
270   X AS DOUBLE
280   Y AS DOUBLE
290 END TYPE
300 REM
310 REM ============================================================
320 REM Test A: Vec4 NEON bulk copy (should emit ldr q28 / str q28)
330 REM ============================================================
340 DIM A4 AS Vec4
350 DIM B4 AS Vec4
360 A4.X = 100 : A4.Y = 200 : A4.Z = 300 : A4.W = 400
370 B4 = A4
380 IF B4.X = 100 AND B4.Y = 200 AND B4.Z = 300 AND B4.W = 400 THEN PRINT "ASM_COPY_V4S PASS" ELSE PRINT "ASM_COPY_V4S FAIL"
390 REM
400 REM ============================================================
410 REM Test B: Vec4 NEON add (should emit add v28.4s, v28.4s, v29.4s)
420 REM ============================================================
430 DIM C4 AS Vec4
440 A4.X = 10 : A4.Y = 20 : A4.Z = 30 : A4.W = 40
450 B4.X = 1  : B4.Y = 2  : B4.Z = 3  : B4.W = 4
460 C4 = A4 + B4
470 IF C4.X = 11 AND C4.Y = 22 AND C4.Z = 33 AND C4.W = 44 THEN PRINT "ASM_ADD_V4S PASS" ELSE PRINT "ASM_ADD_V4S FAIL"
480 REM
490 REM ============================================================
500 REM Test C: Vec4 NEON sub (should emit sub v28.4s, v28.4s, v29.4s)
510 REM ============================================================
520 C4 = A4 - B4
530 IF C4.X = 9 AND C4.Y = 18 AND C4.Z = 27 AND C4.W = 36 THEN PRINT "ASM_SUB_V4S PASS" ELSE PRINT "ASM_SUB_V4S FAIL"
540 REM
550 REM ============================================================
560 REM Test D: Vec4 NEON mul (should emit mul v28.4s, v28.4s, v29.4s)
570 REM ============================================================
580 A4.X = 3 : A4.Y = 4 : A4.Z = 5 : A4.W = 6
590 B4.X = 7 : B4.Y = 8 : B4.Z = 9 : B4.W = 10
600 C4 = A4 * B4
610 IF C4.X = 21 AND C4.Y = 32 AND C4.Z = 45 AND C4.W = 60 THEN PRINT "ASM_MUL_V4S PASS" ELSE PRINT "ASM_MUL_V4S FAIL"
620 REM
630 REM ============================================================
640 REM Test E: Vec4F NEON fadd (should emit fadd v28.4s, v28.4s, v29.4s)
650 REM ============================================================
660 DIM AF AS Vec4F
670 DIM BF AS Vec4F
680 DIM CF AS Vec4F
690 AF.X = 1.0 : AF.Y = 2.0 : AF.Z = 3.0 : AF.W = 4.0
700 BF.X = 0.5 : BF.Y = 1.5 : BF.Z = 2.5 : BF.W = 3.5
710 CF = AF + BF
720 IF CF.X = 1.5 AND CF.Y = 3.5 AND CF.Z = 5.5 AND CF.W = 7.5 THEN PRINT "ASM_FADD_V4S PASS" ELSE PRINT "ASM_FADD_V4S FAIL"
730 REM
740 REM ============================================================
750 REM Test F: Vec4F NEON fsub (should emit fsub v28.4s)
760 REM ============================================================
770 CF = AF - BF
780 IF CF.X = 0.5 AND CF.Y = 0.5 AND CF.Z = 0.5 AND CF.W = 0.5 THEN PRINT "ASM_FSUB_V4S PASS" ELSE PRINT "ASM_FSUB_V4S FAIL"
790 REM
800 REM ============================================================
810 REM Test G: Vec4F NEON fmul (should emit fmul v28.4s)
820 REM ============================================================
830 AF.X = 2.0 : AF.Y = 3.0 : AF.Z = 4.0 : AF.W = 5.0
840 BF.X = 0.5 : BF.Y = 0.5 : BF.Z = 0.5 : BF.W = 0.5
850 CF = AF * BF
860 IF CF.X = 1.0 AND CF.Y = 1.5 AND CF.Z = 2.0 AND CF.W = 2.5 THEN PRINT "ASM_FMUL_V4S PASS" ELSE PRINT "ASM_FMUL_V4S FAIL"
870 REM
880 REM ============================================================
890 REM Test H: Vec4F NEON fdiv (should emit fdiv v28.4s)
900 REM ============================================================
910 AF.X = 10.0 : AF.Y = 20.0 : AF.Z = 30.0 : AF.W = 40.0
920 BF.X = 2.0  : BF.Y = 5.0  : BF.Z = 6.0  : BF.W = 8.0
930 CF = AF / BF
940 IF CF.X = 5.0 AND CF.Y = 4.0 AND CF.Z = 5.0 AND CF.W = 5.0 THEN PRINT "ASM_FDIV_V4S PASS" ELSE PRINT "ASM_FDIV_V4S FAIL"
950 REM
960 REM ============================================================
970 REM Test I: Vec2D NEON fadd (should emit fadd v28.2d, v28.2d, v29.2d)
980 REM ============================================================
990 DIM AD AS Vec2D
1000 DIM BD AS Vec2D
1010 DIM CD AS Vec2D
1020 AD.X = 100.25 : AD.Y = 200.75
1030 BD.X = 0.75   : BD.Y = 0.25
1040 CD = AD + BD
1050 IF CD.X = 101.0 AND CD.Y = 201.0 THEN PRINT "ASM_FADD_V2D PASS" ELSE PRINT "ASM_FADD_V2D FAIL"
1060 REM
1070 REM ============================================================
1080 REM Test J: Vec2D NEON fsub (should emit fsub v28.2d)
1090 REM ============================================================
1100 CD = AD - BD
1110 IF CD.X = 99.5 AND CD.Y = 200.5 THEN PRINT "ASM_FSUB_V2D PASS" ELSE PRINT "ASM_FSUB_V2D FAIL"
1120 REM
1130 REM ============================================================
1140 REM Test K: Vec2D NEON fmul (should emit fmul v28.2d)
1150 REM ============================================================
1160 AD.X = 3.0 : AD.Y = 7.0
1170 BD.X = 4.0 : BD.Y = 3.0
1180 CD = AD * BD
1190 IF CD.X = 12.0 AND CD.Y = 21.0 THEN PRINT "ASM_FMUL_V2D PASS" ELSE PRINT "ASM_FMUL_V2D FAIL"
1200 REM
1210 REM ============================================================
1220 REM Test L: Vec2D NEON fdiv (should emit fdiv v28.2d)
1230 REM ============================================================
1240 AD.X = 15.0 : AD.Y = 28.0
1250 BD.X = 3.0  : BD.Y = 4.0
1260 CD = AD / BD
1270 IF CD.X = 5.0 AND CD.Y = 7.0 THEN PRINT "ASM_FDIV_V2D PASS" ELSE PRINT "ASM_FDIV_V2D FAIL"
1280 REM
1290 REM ============================================================
1300 REM Test M: Vec2D NEON bulk copy (should emit ldr q28 / str q28)
1310 REM ============================================================
1320 AD.X = 99.99 : AD.Y = 77.77
1330 BD = AD
1340 IF BD.X = 99.99 AND BD.Y = 77.77 THEN PRINT "ASM_COPY_V2D PASS" ELSE PRINT "ASM_COPY_V2D FAIL"
1350 REM
1360 REM ============================================================
1370 REM Test N: Vec4F NEON bulk copy (should emit ldr q28 / str q28)
1380 REM ============================================================
1390 AF.X = 1.0 : AF.Y = 2.0 : AF.Z = 3.0 : AF.W = 4.0
1400 BF = AF
1410 IF BF.X = 1.0 AND BF.Y = 2.0 AND BF.Z = 3.0 AND BF.W = 4.0 THEN PRINT "ASM_COPY_V4SF PASS" ELSE PRINT "ASM_COPY_V4SF FAIL"
1420 REM
1430 REM ============================================================
1440 REM Test O: Array loop — Vec4 add (should emit NEON loop with add v28.4s)
1450 REM ============================================================
1460 DIM LA(4) AS Vec4
1470 DIM LB(4) AS Vec4
1480 DIM LC(4) AS Vec4
1490 FOR i% = 0 TO 4
1500   LA(i%).X = (i% + 1) * 10
1510   LA(i%).Y = (i% + 1) * 20
1520   LA(i%).Z = (i% + 1) * 30
1530   LA(i%).W = (i% + 1) * 40
1540   LB(i%).X = 1
1550   LB(i%).Y = 2
1560   LB(i%).Z = 3
1570   LB(i%).W = 4
1580 NEXT i%
1590 FOR i% = 0 TO 4
1600   LC(i%) = LA(i%) + LB(i%)
1610 NEXT i%
1620 IF LC(0).X = 11 AND LC(0).Y = 22 AND LC(0).Z = 33 AND LC(0).W = 44 THEN PRINT "ASM_LOOP_ADD0 PASS" ELSE PRINT "ASM_LOOP_ADD0 FAIL"
1630 IF LC(4).X = 51 AND LC(4).Y = 102 AND LC(4).Z = 153 AND LC(4).W = 204 THEN PRINT "ASM_LOOP_ADD4 PASS" ELSE PRINT "ASM_LOOP_ADD4 FAIL"
1640 REM
1650 REM ============================================================
1660 REM Test P: Array loop — Vec4 copy (should emit NEON loop with ldr/str q28)
1670 REM ============================================================
1680 DIM LD(4) AS Vec4
1690 FOR i% = 0 TO 4
1700   LD(i%) = LA(i%)
1710 NEXT i%
1720 IF LD(0).X = 10 AND LD(0).Y = 20 AND LD(0).Z = 30 AND LD(0).W = 40 THEN PRINT "ASM_LOOP_CPY0 PASS" ELSE PRINT "ASM_LOOP_CPY0 FAIL"
1730 IF LD(4).X = 50 AND LD(4).Y = 100 AND LD(4).Z = 150 AND LD(4).W = 200 THEN PRINT "ASM_LOOP_CPY4 PASS" ELSE PRINT "ASM_LOOP_CPY4 FAIL"
1740 REM
1750 REM ============================================================
1760 REM Test Q: Multiple operations in sequence — ensures q28/q29 aren't
1770 REM corrupted across consecutive NEON operations
1780 REM ============================================================
1790 DIM S1 AS Vec4
1800 DIM S2 AS Vec4
1810 DIM S3 AS Vec4
1820 DIM S4 AS Vec4
1830 DIM S5 AS Vec4
1840 S1.X = 10 : S1.Y = 20 : S1.Z = 30 : S1.W = 40
1850 S2.X = 5  : S2.Y = 10 : S2.Z = 15 : S2.W = 20
1860 S3 = S1 + S2
1870 S4 = S1 - S2
1880 S5 = S1 * S2
1890 IF S3.X = 15 AND S3.Y = 30 AND S3.Z = 45 AND S3.W = 60 THEN PRINT "ASM_SEQ_ADD PASS" ELSE PRINT "ASM_SEQ_ADD FAIL"
1900 IF S4.X = 5 AND S4.Y = 10 AND S4.Z = 15 AND S4.W = 20 THEN PRINT "ASM_SEQ_SUB PASS" ELSE PRINT "ASM_SEQ_SUB FAIL"
1910 IF S5.X = 50 AND S5.Y = 200 AND S5.Z = 450 AND S5.W = 800 THEN PRINT "ASM_SEQ_MUL PASS" ELSE PRINT "ASM_SEQ_MUL FAIL"
1920 REM ============================================================
1930 PRINT "All assembly verification tests complete."
1940 END
