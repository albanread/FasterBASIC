10 REM Test: NEON loop edge cases
20 REM Single-element arrays, large arrays, accumulation patterns
30 TYPE Vec4
40   X AS INTEGER
50   Y AS INTEGER
60   Z AS INTEGER
70   W AS INTEGER
80 END TYPE
90 DIM passCount% AS INTEGER
100 passCount% = 0
110 REM ============================================================
120 REM Test 1: Single-element array loop (FOR i=0 TO 0)
130 REM ============================================================
140 DIM S1(1) AS Vec4
150 DIM S2(1) AS Vec4
160 DIM S3(1) AS Vec4
170 S1(0).X = 100 : S1(0).Y = 200 : S1(0).Z = 300 : S1(0).W = 400
180 S2(0).X = 1   : S2(0).Y = 2   : S2(0).Z = 3   : S2(0).W = 4
190 FOR i% = 0 TO 0
200   S3(i%) = S1(i%) + S2(i%)
210 NEXT i%
220 IF S3(0).X = 101 AND S3(0).Y = 202 AND S3(0).Z = 303 AND S3(0).W = 404 THEN PRINT "SINGLE_ADD PASS" : passCount% = passCount% + 1 ELSE PRINT "SINGLE_ADD FAIL"
230 REM ============================================================
240 REM Test 2: Single-element array copy loop
250 REM ============================================================
260 DIM S4(1) AS Vec4
270 FOR i% = 0 TO 0
280   S4(i%) = S1(i%)
290 NEXT i%
300 IF S4(0).X = 100 AND S4(0).Y = 200 AND S4(0).Z = 300 AND S4(0).W = 400 THEN PRINT "SINGLE_COPY PASS" : passCount% = passCount% + 1 ELSE PRINT "SINGLE_COPY FAIL"
310 REM ============================================================
320 REM Test 3: Single-element subtraction
330 REM ============================================================
340 FOR i% = 0 TO 0
350   S3(i%) = S1(i%) - S2(i%)
360 NEXT i%
370 IF S3(0).X = 99 AND S3(0).Y = 198 AND S3(0).Z = 297 AND S3(0).W = 396 THEN PRINT "SINGLE_SUB PASS" : passCount% = passCount% + 1 ELSE PRINT "SINGLE_SUB FAIL"
380 REM ============================================================
390 REM Test 4: Single-element multiplication
400 REM ============================================================
410 S1(0).X = 3 : S1(0).Y = 5 : S1(0).Z = 7 : S1(0).W = 11
420 S2(0).X = 2 : S2(0).Y = 4 : S2(0).Z = 6 : S2(0).W = 8
430 FOR i% = 0 TO 0
440   S3(i%) = S1(i%) * S2(i%)
450 NEXT i%
460 IF S3(0).X = 6 AND S3(0).Y = 20 AND S3(0).Z = 42 AND S3(0).W = 88 THEN PRINT "SINGLE_MUL PASS" : passCount% = passCount% + 1 ELSE PRINT "SINGLE_MUL FAIL"
470 REM ============================================================
480 REM Test 5: Large array (100 elements) addition
490 REM ============================================================
500 DIM L1(99) AS Vec4
510 DIM L2(99) AS Vec4
520 DIM L3(99) AS Vec4
530 FOR i% = 0 TO 99
540   L1(i%).X = i%
550   L1(i%).Y = i% * 2
560   L1(i%).Z = i% * 3
570   L1(i%).W = i% * 4
580   L2(i%).X = 1
590   L2(i%).Y = 1
600   L2(i%).Z = 1
610   L2(i%).W = 1
620 NEXT i%
630 FOR i% = 0 TO 99
640   L3(i%) = L1(i%) + L2(i%)
650 NEXT i%
660 IF L3(0).X = 1 AND L3(0).Y = 1 AND L3(0).Z = 1 AND L3(0).W = 1 THEN PRINT "LARGE_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGE_E0 FAIL"
670 IF L3(50).X = 51 AND L3(50).Y = 101 AND L3(50).Z = 151 AND L3(50).W = 201 THEN PRINT "LARGE_E50 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGE_E50 FAIL"
680 IF L3(99).X = 100 AND L3(99).Y = 199 AND L3(99).Z = 298 AND L3(99).W = 397 THEN PRINT "LARGE_E99 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGE_E99 FAIL"
690 IF L1(99).X = 99 AND L1(99).Y = 198 THEN PRINT "LARGE_SRC PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGE_SRC FAIL"
700 REM ============================================================
710 REM Test 6: Large array copy
720 REM ============================================================
730 DIM L4(99) AS Vec4
740 FOR i% = 0 TO 99
750   L4(i%) = L1(i%)
760 NEXT i%
770 IF L4(0).X = 0 AND L4(0).Y = 0 AND L4(0).Z = 0 AND L4(0).W = 0 THEN PRINT "LARGECPY_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGECPY_E0 FAIL"
780 IF L4(49).X = 49 AND L4(49).Y = 98 AND L4(49).Z = 147 AND L4(49).W = 196 THEN PRINT "LARGECPY_E49 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGECPY_E49 FAIL"
790 IF L4(99).X = 99 AND L4(99).Y = 198 AND L4(99).Z = 297 AND L4(99).W = 396 THEN PRINT "LARGECPY_E99 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGECPY_E99 FAIL"
800 REM ============================================================
810 REM Test 7: Large array subtraction
820 REM ============================================================
830 DIM L5(99) AS Vec4
840 FOR i% = 0 TO 99
850   L5(i%) = L3(i%) - L1(i%)
860 NEXT i%
870 IF L5(0).X = 1 AND L5(0).Y = 1 AND L5(0).Z = 1 AND L5(0).W = 1 THEN PRINT "LARGESUB_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGESUB_E0 FAIL"
880 IF L5(99).X = 1 AND L5(99).Y = 1 AND L5(99).Z = 1 AND L5(99).W = 1 THEN PRINT "LARGESUB_E99 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGESUB_E99 FAIL"
890 REM ============================================================
900 REM Test 8: Large array multiplication
910 REM ============================================================
920 DIM M1(99) AS Vec4
930 DIM M2(99) AS Vec4
940 DIM M3(99) AS Vec4
950 FOR i% = 0 TO 99
960   M1(i%).X = 2 : M1(i%).Y = 3 : M1(i%).Z = 4 : M1(i%).W = 5
970   M2(i%).X = i% + 1
980   M2(i%).Y = i% + 1
990   M2(i%).Z = i% + 1
1000   M2(i%).W = i% + 1
1010 NEXT i%
1020 FOR i% = 0 TO 99
1030   M3(i%) = M1(i%) * M2(i%)
1040 NEXT i%
1050 IF M3(0).X = 2 AND M3(0).Y = 3 AND M3(0).Z = 4 AND M3(0).W = 5 THEN PRINT "LARGEMUL_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGEMUL_E0 FAIL"
1060 IF M3(49).X = 100 AND M3(49).Y = 150 AND M3(49).Z = 200 AND M3(49).W = 250 THEN PRINT "LARGEMUL_E49 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGEMUL_E49 FAIL"
1070 IF M3(99).X = 200 AND M3(99).Y = 300 AND M3(99).Z = 400 AND M3(99).W = 500 THEN PRINT "LARGEMUL_E99 PASS" : passCount% = passCount% + 1 ELSE PRINT "LARGEMUL_E99 FAIL"
1080 REM ============================================================
1090 REM Test 9: In-place accumulation with large array (A = A + B)
1100 REM ============================================================
1110 DIM AC(99) AS Vec4
1120 DIM AI(99) AS Vec4
1130 FOR i% = 0 TO 99
1140   AC(i%).X = 0 : AC(i%).Y = 0 : AC(i%).Z = 0 : AC(i%).W = 0
1150   AI(i%).X = 1 : AI(i%).Y = 2 : AI(i%).Z = 3 : AI(i%).W = 4
1160 NEXT i%
1170 REM Accumulate 5 times: AC should become 5*AI
1180 FOR j% = 1 TO 5
1190   FOR i% = 0 TO 99
1200     AC(i%) = AC(i%) + AI(i%)
1210   NEXT i%
1220 NEXT j%
1230 IF AC(0).X = 5 AND AC(0).Y = 10 AND AC(0).Z = 15 AND AC(0).W = 20 THEN PRINT "ACCUM_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "ACCUM_E0 FAIL"
1240 IF AC(50).X = 5 AND AC(50).Y = 10 AND AC(50).Z = 15 AND AC(50).W = 20 THEN PRINT "ACCUM_E50 PASS" : passCount% = passCount% + 1 ELSE PRINT "ACCUM_E50 FAIL"
1250 IF AC(99).X = 5 AND AC(99).Y = 10 AND AC(99).Z = 15 AND AC(99).W = 20 THEN PRINT "ACCUM_E99 PASS" : passCount% = passCount% + 1 ELSE PRINT "ACCUM_E99 FAIL"
1260 REM ============================================================
1270 REM Test 10: Partial range loop (non-zero start)
1280 REM ============================================================
1290 DIM PR1(19) AS Vec4
1300 DIM PR2(19) AS Vec4
1310 DIM PR3(19) AS Vec4
1320 FOR i% = 0 TO 19
1330   PR1(i%).X = i% * 10 : PR1(i%).Y = i% * 20 : PR1(i%).Z = i% * 30 : PR1(i%).W = i% * 40
1340   PR2(i%).X = 1 : PR2(i%).Y = 2 : PR2(i%).Z = 3 : PR2(i%).W = 4
1350   PR3(i%).X = 0 : PR3(i%).Y = 0 : PR3(i%).Z = 0 : PR3(i%).W = 0
1360 NEXT i%
1370 REM Only operate on elements 5..14
1380 FOR i% = 5 TO 14
1390   PR3(i%) = PR1(i%) + PR2(i%)
1400 NEXT i%
1410 REM Elements outside [5,14] should still be zero
1420 IF PR3(0).X = 0 AND PR3(0).Y = 0 AND PR3(0).Z = 0 AND PR3(0).W = 0 THEN PRINT "PARTIAL_BEFORE PASS" : passCount% = passCount% + 1 ELSE PRINT "PARTIAL_BEFORE FAIL"
1430 IF PR3(19).X = 0 AND PR3(19).Y = 0 AND PR3(19).Z = 0 AND PR3(19).W = 0 THEN PRINT "PARTIAL_AFTER PASS" : passCount% = passCount% + 1 ELSE PRINT "PARTIAL_AFTER FAIL"
1440 REM Elements inside [5,14] should be PR1 + PR2
1450 IF PR3(5).X = 51 AND PR3(5).Y = 102 AND PR3(5).Z = 153 AND PR3(5).W = 204 THEN PRINT "PARTIAL_E5 PASS" : passCount% = passCount% + 1 ELSE PRINT "PARTIAL_E5 FAIL"
1460 IF PR3(14).X = 141 AND PR3(14).Y = 282 AND PR3(14).Z = 423 AND PR3(14).W = 564 THEN PRINT "PARTIAL_E14 PASS" : passCount% = passCount% + 1 ELSE PRINT "PARTIAL_E14 FAIL"
1470 REM ============================================================
1480 REM Test 11: Two-element array (minimum for meaningful loop)
1490 REM ============================================================
1500 DIM T1(1) AS Vec4
1510 DIM T2(1) AS Vec4
1520 DIM T3(1) AS Vec4
1530 T1(0).X = 10 : T1(0).Y = 20 : T1(0).Z = 30 : T1(0).W = 40
1540 T1(1).X = 50 : T1(1).Y = 60 : T1(1).Z = 70 : T1(1).W = 80
1550 T2(0).X = 1  : T2(0).Y = 2  : T2(0).Z = 3  : T2(0).W = 4
1560 T2(1).X = 5  : T2(1).Y = 6  : T2(1).Z = 7  : T2(1).W = 8
1570 FOR i% = 0 TO 1
1580   T3(i%) = T1(i%) + T2(i%)
1590 NEXT i%
1600 IF T3(0).X = 11 AND T3(0).Y = 22 AND T3(0).Z = 33 AND T3(0).W = 44 THEN PRINT "TWO_ELEM_E0 PASS" : passCount% = passCount% + 1 ELSE PRINT "TWO_ELEM_E0 FAIL"
1610 IF T3(1).X = 55 AND T3(1).Y = 66 AND T3(1).Z = 77 AND T3(1).W = 88 THEN PRINT "TWO_ELEM_E1 PASS" : passCount% = passCount% + 1 ELSE PRINT "TWO_ELEM_E1 FAIL"
1620 REM ============================================================
1630 REM Summary
1640 REM ============================================================
1650 PRINT ""
1660 PRINT "Passed: "; passCount%; " / 25"
1670 IF passCount% = 25 THEN PRINT "ALL LOOP EDGE CASE TESTS PASSED" ELSE PRINT "SOME TESTS FAILED"
1680 END
