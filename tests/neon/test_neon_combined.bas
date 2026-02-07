10 REM Test: Combined NEON copy + arithmetic interactions
20 REM Verifies that NEON bulk copy and element-wise arithmetic
30 REM work correctly together in realistic usage patterns.
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 TYPE Vec4F
110   X AS SINGLE
120   Y AS SINGLE
130   Z AS SINGLE
140   W AS SINGLE
150 END TYPE
160 TYPE Vec2D
170   X AS DOUBLE
180   Y AS DOUBLE
190 END TYPE
200 REM ============================================================
210 REM Test 1: Copy then arithmetic (verify copy doesn't corrupt)
220 REM ============================================================
230 DIM A AS Vec4
240 DIM B AS Vec4
250 DIM C AS Vec4
260 DIM D AS Vec4
270 A.X = 10 : A.Y = 20 : A.Z = 30 : A.W = 40
280 B = A
290 C.X = 1 : C.Y = 2 : C.Z = 3 : C.W = 4
300 D = B + C
310 IF D.X = 11 AND D.Y = 22 AND D.Z = 33 AND D.W = 44 THEN PRINT "COPY_THEN_ADD PASS" ELSE PRINT "COPY_THEN_ADD FAIL"
320 IF B.X = 10 AND B.Y = 20 AND B.Z = 30 AND B.W = 40 THEN PRINT "COPY_INTACT PASS" ELSE PRINT "COPY_INTACT FAIL"
330 REM ============================================================
340 REM Test 2: Arithmetic then copy (verify arith result copyable)
350 REM ============================================================
360 A.X = 5 : A.Y = 10 : A.Z = 15 : A.W = 20
370 B.X = 3 : B.Y = 6  : B.Z = 9  : B.W = 12
380 C = A + B
390 D = C
400 IF D.X = 8 AND D.Y = 16 AND D.Z = 24 AND D.W = 32 THEN PRINT "ADD_THEN_COPY PASS" ELSE PRINT "ADD_THEN_COPY FAIL"
410 REM ============================================================
420 REM Test 3: Multiple operations on same variables
430 REM ============================================================
440 A.X = 100 : A.Y = 200 : A.Z = 300 : A.W = 400
450 B.X = 10  : B.Y = 20  : B.Z = 30  : B.W = 40
460 C = A + B
470 D = A - B
480 IF C.X = 110 AND C.Y = 220 AND C.Z = 330 AND C.W = 440 THEN PRINT "MULTI_ADD PASS" ELSE PRINT "MULTI_ADD FAIL"
490 IF D.X = 90 AND D.Y = 180 AND D.Z = 270 AND D.W = 360 THEN PRINT "MULTI_SUB PASS" ELSE PRINT "MULTI_SUB FAIL"
500 IF A.X = 100 AND A.Y = 200 AND A.Z = 300 AND A.W = 400 THEN PRINT "MULTI_SRC_A PASS" ELSE PRINT "MULTI_SRC_A FAIL"
510 IF B.X = 10 AND B.Y = 20 AND B.Z = 30 AND B.W = 40 THEN PRINT "MULTI_SRC_B PASS" ELSE PRINT "MULTI_SRC_B FAIL"
520 REM ============================================================
530 REM Test 4: Overwrite self with arithmetic result
540 REM ============================================================
550 A.X = 1 : A.Y = 2 : A.Z = 3 : A.W = 4
560 B.X = 10 : B.Y = 20 : B.Z = 30 : B.W = 40
570 A = A + B
580 IF A.X = 11 AND A.Y = 22 AND A.Z = 33 AND A.W = 44 THEN PRINT "SELF_ADD PASS" ELSE PRINT "SELF_ADD FAIL"
590 A = A - B
600 IF A.X = 1 AND A.Y = 2 AND A.Z = 3 AND A.W = 4 THEN PRINT "SELF_SUB PASS" ELSE PRINT "SELF_SUB FAIL"
610 REM ============================================================
620 REM Test 5: Vec4F (float) copy + arithmetic
630 REM ============================================================
640 DIM FA AS Vec4F
650 DIM FB AS Vec4F
660 DIM FC AS Vec4F
670 DIM FD AS Vec4F
680 FA.X = 1.5 : FA.Y = 2.5 : FA.Z = 3.5 : FA.W = 4.5
690 FB = FA
700 FC.X = 0.5 : FC.Y = 1.0 : FC.Z = 1.5 : FC.W = 2.0
710 FD = FB + FC
720 IF FD.X = 2.0 AND FD.Y = 3.5 AND FD.Z = 5.0 AND FD.W = 6.5 THEN PRINT "F_COPY_ADD PASS" ELSE PRINT "F_COPY_ADD FAIL"
730 IF FB.X = 1.5 AND FB.Y = 2.5 AND FB.Z = 3.5 AND FB.W = 4.5 THEN PRINT "F_COPY_INTACT PASS" ELSE PRINT "F_COPY_INTACT FAIL"
740 REM ============================================================
750 REM Test 6: Vec4F division
760 REM ============================================================
770 FA.X = 10.0 : FA.Y = 20.0 : FA.Z = 30.0 : FA.W = 40.0
780 FB.X = 2.0  : FB.Y = 4.0  : FB.Z = 5.0  : FB.W = 8.0
790 FC = FA / FB
800 IF FC.X = 5.0 AND FC.Y = 5.0 AND FC.Z = 6.0 AND FC.W = 5.0 THEN PRINT "F_DIV PASS" ELSE PRINT "F_DIV FAIL"
810 REM ============================================================
820 REM Test 7: Vec2D (double) copy + arithmetic
830 REM ============================================================
840 DIM DA AS Vec2D
850 DIM DB AS Vec2D
860 DIM DC AS Vec2D
870 DIM DD AS Vec2D
880 DA.X = 100.5 : DA.Y = 200.25
890 DB = DA
900 DC.X = 0.5 : DC.Y = 0.75
910 DD = DB + DC
920 IF DD.X = 101.0 AND DD.Y = 201.0 THEN PRINT "D_COPY_ADD PASS" ELSE PRINT "D_COPY_ADD FAIL"
930 IF DB.X = 100.5 AND DB.Y = 200.25 THEN PRINT "D_COPY_INTACT PASS" ELSE PRINT "D_COPY_INTACT FAIL"
940 REM ============================================================
950 REM Test 8: Vec2D multiply and divide
960 REM ============================================================
970 DA.X = 3.0 : DA.Y = 7.0
980 DB.X = 4.0 : DB.Y = 2.0
990 DC = DA * DB
1000 IF DC.X = 12.0 AND DC.Y = 14.0 THEN PRINT "D_MUL PASS" ELSE PRINT "D_MUL FAIL"
1010 DD = DC / DB
1020 IF DD.X = 3.0 AND DD.Y = 7.0 THEN PRINT "D_MUL_DIV PASS" ELSE PRINT "D_MUL_DIV FAIL"
1030 REM ============================================================
1040 REM Test 9: Accumulate pattern (A = A + B repeated)
1050 REM ============================================================
1060 A.X = 0 : A.Y = 0 : A.Z = 0 : A.W = 0
1070 B.X = 1 : B.Y = 2 : B.Z = 3 : B.W = 4
1080 A = A + B
1090 A = A + B
1100 A = A + B
1110 IF A.X = 3 AND A.Y = 6 AND A.Z = 9 AND A.W = 12 THEN PRINT "ACCUM PASS" ELSE PRINT "ACCUM FAIL"
1120 REM ============================================================
1130 REM Test 10: Difference pattern
1140 REM ============================================================
1150 A.X = 50 : A.Y = 100 : A.Z = 150 : A.W = 200
1160 B.X = 50 : B.Y = 100 : B.Z = 150 : B.W = 200
1170 C = A - B
1180 IF C.X = 0 AND C.Y = 0 AND C.Z = 0 AND C.W = 0 THEN PRINT "DIFF_ZERO PASS" ELSE PRINT "DIFF_ZERO FAIL"
1190 REM ============================================================
1200 REM Test 11: Multiply edge cases (zeroes, ones, negatives)
1210 REM ============================================================
1220 A.X = 0 : A.Y = 1 : A.Z = -1 : A.W = 2
1230 B.X = 99 : B.Y = 99 : B.Z = 99 : B.W = -3
1240 C = A * B
1250 IF C.X = 0 AND C.Y = 99 AND C.Z = -99 AND C.W = -6 THEN PRINT "MUL_EDGE PASS" ELSE PRINT "MUL_EDGE FAIL"
1260 REM ============================================================
1270 REM Test 12: Copy result of arithmetic to another variable
1280 REM ============================================================
1290 A.X = 7 : A.Y = 14 : A.Z = 21 : A.W = 28
1300 B.X = 3 : B.Y = 6  : B.Z = 9  : B.W = 12
1310 C = A + B
1320 D = C
1330 B = D
1340 IF B.X = 10 AND B.Y = 20 AND B.Z = 30 AND B.W = 40 THEN PRINT "CHAIN_COPY PASS" ELSE PRINT "CHAIN_COPY FAIL"
1350 IF A.X = 7 AND A.Y = 14 AND A.Z = 21 AND A.W = 28 THEN PRINT "CHAIN_SRC PASS" ELSE PRINT "CHAIN_SRC FAIL"
1360 REM ============================================================
1370 REM Test 13: Large integer values near INT32 boundaries
1380 REM ============================================================
1390 A.X = 2147483640 : A.Y = -2147483640 : A.Z = 0 : A.W = 1
1400 B.X = 7 : B.Y = -7 : B.Z = 0 : B.W = -1
1410 C = A + B
1420 IF C.X = 2147483647 AND C.Y = -2147483647 AND C.Z = 0 AND C.W = 0 THEN PRINT "LARGE_INT PASS" ELSE PRINT "LARGE_INT FAIL"
1430 REM ============================================================
1440 REM Test 14: Float precision under arithmetic
1450 REM ============================================================
1460 FA.X = 0.1 : FA.Y = 0.2 : FA.Z = 0.3 : FA.W = 0.0
1470 FB.X = 0.1 : FB.Y = 0.2 : FB.Z = 0.3 : FB.W = 0.0
1480 FC = FA + FB
1490 FD = FA * FB
1500 PRINT "F_PREC ADD: "; FC.X; ","; FC.Y; ","; FC.Z; ","; FC.W
1510 PRINT "F_PREC MUL: "; FD.X; ","; FD.Y; ","; FD.Z; ","; FD.W
1520 PRINT "F_PREC test done (visual check)"
1530 REM ============================================================
1540 PRINT "All combined NEON copy+arithmetic tests complete."
1550 END
