10 REM Test: NEON Phase 3 - Array loop vectorization (Vec2d double arithmetic)
20 REM Verifies that FOR loops over arrays of SIMD-eligible double UDTs are
30 REM vectorized with NEON instructions (ldr q28/q29, fadd/fsub/fmul v28.2d, str q28)
40 TYPE Vec2d
50   X AS DOUBLE
60   Y AS DOUBLE
70 END TYPE
80 REM === Setup: create arrays of Vec2d ===
90 DIM A(9) AS Vec2d
100 DIM B(9) AS Vec2d
110 DIM C(9) AS Vec2d
120 REM === Initialize source arrays ===
130 FOR i% = 0 TO 9
140   A(i%).X = i% * 1.25
150   A(i%).Y = i% * 3.75
160   B(i%).X = 0.5
170   B(i%).Y = 1.5
180 NEXT i%
190 REM === Test 1: Vectorized element-wise double addition ===
200 REM This loop should be detected as Pattern A (whole-UDT binary op)
210 REM and emitted as a NEON vectorized loop with fadd v28.2d
220 FOR i% = 0 TO 9
230   C(i%) = A(i%) + B(i%)
240 NEXT i%
250 REM === Verify addition results ===
260 PRINT "ADD C(0): "; C(0).X; ","; C(0).Y
270 IF C(0).X = 0.5 AND C(0).Y = 1.5 THEN PRINT "ADD ELEM0 PASS" ELSE PRINT "ADD ELEM0 FAIL"
280 PRINT "ADD C(4): "; C(4).X; ","; C(4).Y
290 IF C(4).X = 5.5 AND C(4).Y = 16.5 THEN PRINT "ADD ELEM4 PASS" ELSE PRINT "ADD ELEM4 FAIL"
300 PRINT "ADD C(9): "; C(9).X; ","; C(9).Y
310 IF C(9).X = 11.75 AND C(9).Y = 35.25 THEN PRINT "ADD ELEM9 PASS" ELSE PRINT "ADD ELEM9 FAIL"
320 DIM addPass% AS INTEGER
330 addPass% = 1
340 FOR i% = 0 TO 9
350   IF C(i%).X <> i% * 1.25 + 0.5 THEN addPass% = 0
360   IF C(i%).Y <> i% * 3.75 + 1.5 THEN addPass% = 0
370 NEXT i%
380 IF addPass% = 1 THEN PRINT "DADD LOOP PASS" ELSE PRINT "DADD LOOP FAIL"
390 REM === Test 2: Vectorized element-wise double subtraction ===
400 FOR i% = 0 TO 9
410   C(i%) = A(i%) - B(i%)
420 NEXT i%
430 PRINT "SUB C(0): "; C(0).X; ","; C(0).Y
440 IF C(0).X = -0.5 AND C(0).Y = -1.5 THEN PRINT "SUB ELEM0 PASS" ELSE PRINT "SUB ELEM0 FAIL"
450 PRINT "SUB C(6): "; C(6).X; ","; C(6).Y
460 IF C(6).X = 7.0 AND C(6).Y = 21.0 THEN PRINT "SUB ELEM6 PASS" ELSE PRINT "SUB ELEM6 FAIL"
470 DIM subPass% AS INTEGER
480 subPass% = 1
490 FOR i% = 0 TO 9
500   IF C(i%).X <> i% * 1.25 - 0.5 THEN subPass% = 0
510   IF C(i%).Y <> i% * 3.75 - 1.5 THEN subPass% = 0
520 NEXT i%
530 IF subPass% = 1 THEN PRINT "DSUB LOOP PASS" ELSE PRINT "DSUB LOOP FAIL"
540 REM === Test 3: Vectorized element-wise double multiplication ===
550 DIM D(9) AS Vec2d
560 DIM E(9) AS Vec2d
570 DIM F(9) AS Vec2d
580 FOR i% = 0 TO 9
590   D(i%).X = i% + 1.0
600   D(i%).Y = i% + 2.0
610   E(i%).X = 2.5
620   E(i%).Y = 0.5
630 NEXT i%
640 FOR i% = 0 TO 9
650   F(i%) = D(i%) * E(i%)
660 NEXT i%
670 PRINT "MUL F(0): "; F(0).X; ","; F(0).Y
680 IF F(0).X = 2.5 AND F(0).Y = 1.0 THEN PRINT "MUL ELEM0 PASS" ELSE PRINT "MUL ELEM0 FAIL"
690 PRINT "MUL F(3): "; F(3).X; ","; F(3).Y
700 IF F(3).X = 10.0 AND F(3).Y = 2.5 THEN PRINT "MUL ELEM3 PASS" ELSE PRINT "MUL ELEM3 FAIL"
710 DIM mulPass% AS INTEGER
720 mulPass% = 1
730 FOR i% = 0 TO 9
740   IF F(i%).X <> (i% + 1.0) * 2.5 THEN mulPass% = 0
750   IF F(i%).Y <> (i% + 2.0) * 0.5 THEN mulPass% = 0
760 NEXT i%
770 IF mulPass% = 1 THEN PRINT "DMUL LOOP PASS" ELSE PRINT "DMUL LOOP FAIL"
780 REM === Test 4: Vectorized element-wise double division ===
790 DIM G(9) AS Vec2d
800 FOR i% = 0 TO 9
810   D(i%).X = (i% + 1) * 10.0
820   D(i%).Y = (i% + 1) * 20.0
830   E(i%).X = 2.0
840   E(i%).Y = 5.0
850 NEXT i%
860 FOR i% = 0 TO 9
870   G(i%) = D(i%) / E(i%)
880 NEXT i%
890 PRINT "DIV G(0): "; G(0).X; ","; G(0).Y
900 IF G(0).X = 5.0 AND G(0).Y = 4.0 THEN PRINT "DIV ELEM0 PASS" ELSE PRINT "DIV ELEM0 FAIL"
910 PRINT "DIV G(7): "; G(7).X; ","; G(7).Y
920 IF G(7).X = 40.0 AND G(7).Y = 32.0 THEN PRINT "DIV ELEM7 PASS" ELSE PRINT "DIV ELEM7 FAIL"
930 DIM divPass% AS INTEGER
940 divPass% = 1
950 FOR i% = 0 TO 9
960   IF G(i%).X <> (i% + 1) * 10.0 / 2.0 THEN divPass% = 0
970   IF G(i%).Y <> (i% + 1) * 20.0 / 5.0 THEN divPass% = 0
980 NEXT i%
990 IF divPass% = 1 THEN PRINT "DDIV LOOP PASS" ELSE PRINT "DDIV LOOP FAIL"
1000 REM === Test 5: Array copy with Vec2d ===
1010 DIM H(9) AS Vec2d
1020 FOR i% = 0 TO 9
1030   H(i%) = A(i%)
1040 NEXT i%
1050 DIM copyPass% AS INTEGER
1060 copyPass% = 1
1070 FOR i% = 0 TO 9
1080   IF H(i%).X <> A(i%).X THEN copyPass% = 0
1090   IF H(i%).Y <> A(i%).Y THEN copyPass% = 0
1100 NEXT i%
1110 IF copyPass% = 1 THEN PRINT "DCOPY LOOP PASS" ELSE PRINT "DCOPY LOOP FAIL"
1120 REM === Test 6: In-place update (A = A + B) with doubles ===
1130 FOR i% = 0 TO 9
1140   A(i%) = A(i%) + B(i%)
1150 NEXT i%
1160 PRINT "INPLACE A(0): "; A(0).X; ","; A(0).Y
1170 IF A(0).X = 0.5 AND A(0).Y = 1.5 THEN PRINT "DINPLACE0 PASS" ELSE PRINT "DINPLACE0 FAIL"
1180 PRINT "INPLACE A(9): "; A(9).X; ","; A(9).Y
1190 IF A(9).X = 11.75 AND A(9).Y = 35.25 THEN PRINT "DINPLACE9 PASS" ELSE PRINT "DINPLACE9 FAIL"
1200 REM === Test 7: Partial range operation ===
1210 DIM P(19) AS Vec2d
1220 DIM Q(19) AS Vec2d
1230 DIM R(19) AS Vec2d
1240 FOR i% = 0 TO 19
1250   P(i%).X = i% * 1.0
1260   P(i%).Y = i% * 2.0
1270   Q(i%).X = 100.0
1280   Q(i%).Y = 200.0
1290 NEXT i%
1300 REM Only vectorize the range 3..12
1310 FOR i% = 3 TO 12
1320   R(i%) = P(i%) + Q(i%)
1330 NEXT i%
1340 REM Elements outside [3,12] should be zero (uninitialised)
1350 IF R(0).X = 0.0 AND R(0).Y = 0.0 THEN PRINT "RANGE ZERO0 PASS" ELSE PRINT "RANGE ZERO0 FAIL"
1360 IF R(19).X = 0.0 AND R(19).Y = 0.0 THEN PRINT "RANGE ZERO19 PASS" ELSE PRINT "RANGE ZERO19 FAIL"
1370 REM Elements inside [3,12] should be P + Q
1380 IF R(3).X = 103.0 AND R(3).Y = 206.0 THEN PRINT "RANGE3 PASS" ELSE PRINT "RANGE3 FAIL"
1390 IF R(12).X = 112.0 AND R(12).Y = 224.0 THEN PRINT "RANGE12 PASS" ELSE PRINT "RANGE12 FAIL"
1400 REM === Summary ===
1410 PRINT "All NEON loop Vec2d double arithmetic tests complete."
1420 END
