10 REM Test: NEON Phase 3 - Array loop vectorization (Vec4f float arithmetic)
20 REM Verifies that FOR loops over arrays of SIMD-eligible float UDTs are
30 REM vectorized with NEON instructions (ldr q28/q29, fadd/fsub/fmul v28.4s, str q28)
40 TYPE Vec4f
50   X AS SINGLE
60   Y AS SINGLE
70   Z AS SINGLE
80   W AS SINGLE
90 END TYPE
100 REM === Setup: create arrays of Vec4f ===
110 DIM A(9) AS Vec4f
120 DIM B(9) AS Vec4f
130 DIM C(9) AS Vec4f
140 REM === Initialize source arrays ===
150 FOR i% = 0 TO 9
160   A(i%).X = i% * 1.5
170   A(i%).Y = i% * 2.5
180   A(i%).Z = i% * 3.5
190   A(i%).W = i% * 4.5
200   B(i%).X = 0.5
210   B(i%).Y = 1.0
220   B(i%).Z = 1.5
230   B(i%).W = 2.0
240 NEXT i%
250 REM === Test 1: Vectorized element-wise float addition ===
260 REM This loop should be detected as Pattern A (whole-UDT binary op)
270 REM and emitted as a NEON vectorized loop with fadd v28.4s
280 FOR i% = 0 TO 9
290   C(i%) = A(i%) + B(i%)
300 NEXT i%
310 REM === Verify results for addition ===
320 PRINT "ADD C(0): "; C(0).X; ","; C(0).Y; ","; C(0).Z; ","; C(0).W
330 IF C(0).X = 0.5 AND C(0).Y = 1.0 AND C(0).Z = 1.5 AND C(0).W = 2.0 THEN PRINT "ADD ELEM0 PASS" ELSE PRINT "ADD ELEM0 FAIL"
340 PRINT "ADD C(2): "; C(2).X; ","; C(2).Y; ","; C(2).Z; ","; C(2).W
350 IF C(2).X = 3.5 AND C(2).Y = 6.0 AND C(2).Z = 8.5 AND C(2).W = 11.0 THEN PRINT "ADD ELEM2 PASS" ELSE PRINT "ADD ELEM2 FAIL"
360 DIM addPass% AS INTEGER
370 addPass% = 1
380 FOR i% = 0 TO 9
390   IF C(i%).X <> i% * 1.5 + 0.5 THEN addPass% = 0
400   IF C(i%).Y <> i% * 2.5 + 1.0 THEN addPass% = 0
410   IF C(i%).Z <> i% * 3.5 + 1.5 THEN addPass% = 0
420   IF C(i%).W <> i% * 4.5 + 2.0 THEN addPass% = 0
430 NEXT i%
440 IF addPass% = 1 THEN PRINT "FADD LOOP PASS" ELSE PRINT "FADD LOOP FAIL"
450 REM === Test 2: Vectorized element-wise float subtraction ===
460 FOR i% = 0 TO 9
470   C(i%) = A(i%) - B(i%)
480 NEXT i%
490 PRINT "SUB C(0): "; C(0).X; ","; C(0).Y; ","; C(0).Z; ","; C(0).W
500 IF C(0).X = -0.5 AND C(0).Y = -1.0 AND C(0).Z = -1.5 AND C(0).W = -2.0 THEN PRINT "SUB ELEM0 PASS" ELSE PRINT "SUB ELEM0 FAIL"
510 PRINT "SUB C(4): "; C(4).X; ","; C(4).Y; ","; C(4).Z; ","; C(4).W
520 IF C(4).X = 5.5 AND C(4).Y = 9.0 AND C(4).Z = 12.5 AND C(4).W = 16.0 THEN PRINT "SUB ELEM4 PASS" ELSE PRINT "SUB ELEM4 FAIL"
530 DIM subPass% AS INTEGER
540 subPass% = 1
550 FOR i% = 0 TO 9
560   IF C(i%).X <> i% * 1.5 - 0.5 THEN subPass% = 0
570   IF C(i%).Y <> i% * 2.5 - 1.0 THEN subPass% = 0
580   IF C(i%).Z <> i% * 3.5 - 1.5 THEN subPass% = 0
590   IF C(i%).W <> i% * 4.5 - 2.0 THEN subPass% = 0
600 NEXT i%
610 IF subPass% = 1 THEN PRINT "FSUB LOOP PASS" ELSE PRINT "FSUB LOOP FAIL"
620 REM === Test 3: Vectorized element-wise float multiplication ===
630 DIM D(9) AS Vec4f
640 DIM E(9) AS Vec4f
650 DIM F(9) AS Vec4f
660 FOR i% = 0 TO 9
670   D(i%).X = i% + 1.0
680   D(i%).Y = i% + 2.0
690   D(i%).Z = i% + 3.0
700   D(i%).W = i% + 4.0
710   E(i%).X = 2.0
720   E(i%).Y = 3.0
730   E(i%).Z = 0.5
740   E(i%).W = 0.25
750 NEXT i%
760 FOR i% = 0 TO 9
770   F(i%) = D(i%) * E(i%)
780 NEXT i%
790 PRINT "MUL F(0): "; F(0).X; ","; F(0).Y; ","; F(0).Z; ","; F(0).W
800 IF F(0).X = 2.0 AND F(0).Y = 6.0 AND F(0).Z = 1.5 AND F(0).W = 1.0 THEN PRINT "MUL ELEM0 PASS" ELSE PRINT "MUL ELEM0 FAIL"
810 PRINT "MUL F(3): "; F(3).X; ","; F(3).Y; ","; F(3).Z; ","; F(3).W
820 IF F(3).X = 8.0 AND F(3).Y = 15.0 AND F(3).Z = 3.0 AND F(3).W = 1.75 THEN PRINT "MUL ELEM3 PASS" ELSE PRINT "MUL ELEM3 FAIL"
830 DIM mulPass% AS INTEGER
840 mulPass% = 1
850 FOR i% = 0 TO 9
860   IF F(i%).X <> (i% + 1.0) * 2.0 THEN mulPass% = 0
870   IF F(i%).Y <> (i% + 2.0) * 3.0 THEN mulPass% = 0
880   IF F(i%).Z <> (i% + 3.0) * 0.5 THEN mulPass% = 0
890   IF F(i%).W <> (i% + 4.0) * 0.25 THEN mulPass% = 0
900 NEXT i%
910 IF mulPass% = 1 THEN PRINT "FMUL LOOP PASS" ELSE PRINT "FMUL LOOP FAIL"
920 REM === Test 4: Vectorized element-wise float division ===
930 DIM G(9) AS Vec4f
940 FOR i% = 0 TO 9
950   D(i%).X = (i% + 1) * 10.0
960   D(i%).Y = (i% + 1) * 20.0
970   D(i%).Z = (i% + 1) * 30.0
980   D(i%).W = (i% + 1) * 40.0
990   E(i%).X = 2.0
1000   E(i%).Y = 4.0
1010   E(i%).Z = 5.0
1020   E(i%).W = 8.0
1030 NEXT i%
1040 FOR i% = 0 TO 9
1050   G(i%) = D(i%) / E(i%)
1060 NEXT i%
1070 PRINT "DIV G(0): "; G(0).X; ","; G(0).Y; ","; G(0).Z; ","; G(0).W
1080 IF G(0).X = 5.0 AND G(0).Y = 5.0 AND G(0).Z = 6.0 AND G(0).W = 5.0 THEN PRINT "DIV ELEM0 PASS" ELSE PRINT "DIV ELEM0 FAIL"
1090 PRINT "DIV G(4): "; G(4).X; ","; G(4).Y; ","; G(4).Z; ","; G(4).W
1100 IF G(4).X = 25.0 AND G(4).Y = 25.0 AND G(4).Z = 30.0 AND G(4).W = 25.0 THEN PRINT "DIV ELEM4 PASS" ELSE PRINT "DIV ELEM4 FAIL"
1110 DIM divPass% AS INTEGER
1120 divPass% = 1
1130 FOR i% = 0 TO 9
1140   IF G(i%).X <> (i% + 1) * 10.0 / 2.0 THEN divPass% = 0
1150   IF G(i%).Y <> (i% + 1) * 20.0 / 4.0 THEN divPass% = 0
1160   IF G(i%).Z <> (i% + 1) * 30.0 / 5.0 THEN divPass% = 0
1170   IF G(i%).W <> (i% + 1) * 40.0 / 8.0 THEN divPass% = 0
1180 NEXT i%
1190 IF divPass% = 1 THEN PRINT "FDIV LOOP PASS" ELSE PRINT "FDIV LOOP FAIL"
1200 REM === Test 5: In-place update (A = A + B) with floats ===
1210 FOR i% = 0 TO 9
1220   A(i%) = A(i%) + B(i%)
1230 NEXT i%
1240 PRINT "INPLACE A(0): "; A(0).X; ","; A(0).Y; ","; A(0).Z; ","; A(0).W
1250 IF A(0).X = 0.5 AND A(0).Y = 1.0 AND A(0).Z = 1.5 AND A(0).W = 2.0 THEN PRINT "FINPLACE0 PASS" ELSE PRINT "FINPLACE0 FAIL"
1260 PRINT "INPLACE A(9): "; A(9).X; ","; A(9).Y; ","; A(9).Z; ","; A(9).W
1270 IF A(9).X = 14.0 AND A(9).Y = 23.5 AND A(9).Z = 33.0 AND A(9).W = 42.5 THEN PRINT "FINPLACE9 PASS" ELSE PRINT "FINPLACE9 FAIL"
1280 REM === Summary ===
1290 PRINT "All NEON loop Vec4f float arithmetic tests complete."
1300 END
