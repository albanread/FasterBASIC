10 REM Test: NEON kill-switch verification
20 REM When ENABLE_NEON_COPY=0 or ENABLE_NEON_ARITH=0, the compiler
30 REM should fall back to scalar code paths. This test verifies that
40 REM the program produces CORRECT results regardless of whether
50 REM NEON is enabled or disabled — i.e. scalar fallback works.
60 REM
70 REM Run with:
80 REM   ./fbc_qbe tests/neon/test_neon_killswitch.bas -o ks_on
90 REM   ENABLE_NEON_COPY=0 ENABLE_NEON_ARITH=0 ENABLE_NEON_LOOP=0 ./fbc_qbe tests/neon/test_neon_killswitch.bas -o ks_off
100 REM Both binaries should produce identical output with all PASS.
110 REM
120 TYPE Vec4
130   X AS INTEGER
140   Y AS INTEGER
150   Z AS INTEGER
160   W AS INTEGER
170 END TYPE
180 TYPE Vec2D
190   X AS DOUBLE
200   Y AS DOUBLE
210 END TYPE
220 DIM passCount% AS INTEGER
230 DIM totalTests% AS INTEGER
240 passCount% = 0
250 totalTests% = 17
260 REM ============================================================
270 REM Test 1: UDT copy (uses NEON bulk copy when enabled)
280 REM ============================================================
290 DIM A AS Vec4
300 DIM B AS Vec4
310 A.X = 11 : A.Y = 22 : A.Z = 33 : A.W = 44
320 B = A
330 IF B.X = 11 AND B.Y = 22 AND B.Z = 33 AND B.W = 44 THEN PRINT "KS_COPY PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_COPY FAIL"
340 REM Verify independence
350 B.X = 999
360 IF A.X = 11 THEN PRINT "KS_COPY_INDEP PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_COPY_INDEP FAIL"
370 REM ============================================================
380 REM Test 2: UDT addition (uses NEON arithmetic when enabled)
390 REM ============================================================
400 DIM C AS Vec4
410 A.X = 10 : A.Y = 20 : A.Z = 30 : A.W = 40
420 B.X = 1  : B.Y = 2  : B.Z = 3  : B.W = 4
430 C = A + B
440 IF C.X = 11 AND C.Y = 22 AND C.Z = 33 AND C.W = 44 THEN PRINT "KS_ADD PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_ADD FAIL"
450 REM ============================================================
460 REM Test 3: UDT subtraction
470 REM ============================================================
480 C = A - B
490 IF C.X = 9 AND C.Y = 18 AND C.Z = 27 AND C.W = 36 THEN PRINT "KS_SUB PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_SUB FAIL"
500 REM ============================================================
510 REM Test 4: UDT multiplication
520 REM ============================================================
530 A.X = 2 : A.Y = 3 : A.Z = 4 : A.W = 5
540 B.X = 10 : B.Y = 10 : B.Z = 10 : B.W = 10
550 C = A * B
560 IF C.X = 20 AND C.Y = 30 AND C.Z = 40 AND C.W = 50 THEN PRINT "KS_MUL PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_MUL FAIL"
570 REM ============================================================
580 REM Test 5: Vec2D copy
590 REM ============================================================
600 DIM DA AS Vec2D
610 DIM DB AS Vec2D
620 DA.X = 3.14 : DA.Y = 2.718
630 DB = DA
640 IF DB.X = 3.14 AND DB.Y = 2.718 THEN PRINT "KS_DCOPY PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_DCOPY FAIL"
650 REM ============================================================
660 REM Test 6: Vec2D arithmetic
670 REM ============================================================
680 DIM DC AS Vec2D
690 DA.X = 10.5 : DA.Y = 20.5
700 DB.X = 0.5  : DB.Y = 0.5
710 DC = DA + DB
720 IF DC.X = 11.0 AND DC.Y = 21.0 THEN PRINT "KS_DADD PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_DADD FAIL"
730 DC = DA - DB
740 IF DC.X = 10.0 AND DC.Y = 20.0 THEN PRINT "KS_DSUB PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_DSUB FAIL"
750 DA.X = 3.0 : DA.Y = 5.0
760 DB.X = 4.0 : DB.Y = 2.0
770 DC = DA * DB
780 IF DC.X = 12.0 AND DC.Y = 10.0 THEN PRINT "KS_DMUL PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_DMUL FAIL"
790 DC = DA / DB
800 IF DC.X = 0.75 AND DC.Y = 2.5 THEN PRINT "KS_DDIV PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_DDIV FAIL"
810 REM ============================================================
820 REM Test 7: Self-assignment arithmetic (A = A + B)
830 REM ============================================================
840 A.X = 5 : A.Y = 10 : A.Z = 15 : A.W = 20
850 B.X = 1 : B.Y = 1  : B.Z = 1  : B.W = 1
860 A = A + B
870 IF A.X = 6 AND A.Y = 11 AND A.Z = 16 AND A.W = 21 THEN PRINT "KS_SELFADD PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_SELFADD FAIL"
880 REM ============================================================
890 REM Test 8: Copy after arithmetic
900 REM ============================================================
910 A.X = 100 : A.Y = 200 : A.Z = 300 : A.W = 400
920 B.X = 50  : B.Y = 100 : B.Z = 150 : B.W = 200
930 C = A - B
940 DIM D AS Vec4
950 D = C
960 IF D.X = 50 AND D.Y = 100 AND D.Z = 150 AND D.W = 200 THEN PRINT "KS_ARITH_COPY PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_ARITH_COPY FAIL"
970 REM ============================================================
980 REM Test 9: Array loop vectorization (uses NEON loop when enabled)
990 REM ============================================================
1000 DIM AArr(4) AS Vec4
1010 DIM BArr(4) AS Vec4
1020 DIM CArr(4) AS Vec4
1030 FOR i% = 0 TO 4
1040   AArr(i%).X = (i% + 1) * 10
1050   AArr(i%).Y = (i% + 1) * 20
1060   AArr(i%).Z = (i% + 1) * 30
1070   AArr(i%).W = (i% + 1) * 40
1080   BArr(i%).X = 1
1090   BArr(i%).Y = 2
1100   BArr(i%).Z = 3
1110   BArr(i%).W = 4
1120 NEXT i%
1130 FOR i% = 0 TO 4
1140   CArr(i%) = AArr(i%) + BArr(i%)
1150 NEXT i%
1160 IF CArr(0).X = 11 AND CArr(0).Y = 22 AND CArr(0).Z = 33 AND CArr(0).W = 44 THEN PRINT "KS_LOOP0 PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_LOOP0 FAIL"
1170 IF CArr(2).X = 31 AND CArr(2).Y = 62 AND CArr(2).Z = 93 AND CArr(2).W = 124 THEN PRINT "KS_LOOP2 PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_LOOP2 FAIL"
1180 IF CArr(4).X = 51 AND CArr(4).Y = 102 AND CArr(4).Z = 153 AND CArr(4).W = 204 THEN PRINT "KS_LOOP4 PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_LOOP4 FAIL"
1190 REM ============================================================
1200 REM Test 10: Array loop copy
1210 REM ============================================================
1220 DIM DArr(4) AS Vec4
1230 FOR i% = 0 TO 4
1240   DArr(i%) = AArr(i%)
1250 NEXT i%
1260 IF DArr(0).X = 10 AND DArr(0).Y = 20 AND DArr(0).Z = 30 AND DArr(0).W = 40 THEN PRINT "KS_LCOPY0 PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_LCOPY0 FAIL"
1270 IF DArr(4).X = 50 AND DArr(4).Y = 100 AND DArr(4).Z = 150 AND DArr(4).W = 200 THEN PRINT "KS_LCOPY4 PASS" : passCount% = passCount% + 1 ELSE PRINT "KS_LCOPY4 FAIL"
1280 REM ============================================================
1290 REM Summary
1300 REM ============================================================
1310 PRINT ""
1320 PRINT "Passed: "; passCount%; " / "; totalTests%
1330 IF passCount% = totalTests% THEN PRINT "ALL KILL-SWITCH TESTS PASSED" ELSE PRINT "SOME TESTS FAILED"
1340 END
