10 REM Test: NEON Phase 3 - Array loop vectorization (Vec4 integer addition)
20 REM Verifies that FOR loops over arrays of SIMD-eligible UDTs are
30 REM vectorized with NEON instructions (ldr q28/q29, add v28.4s, str q28)
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 REM === Setup: create arrays of Vec4 ===
110 DIM A(9) AS Vec4
120 DIM B(9) AS Vec4
130 DIM C(9) AS Vec4
140 REM === Initialize source arrays ===
150 FOR i% = 0 TO 9
160   A(i%).X = i% * 10
170   A(i%).Y = i% * 20
180   A(i%).Z = i% * 30
190   A(i%).W = i% * 40
200   B(i%).X = 1
210   B(i%).Y = 2
220   B(i%).Z = 3
230   B(i%).W = 4
240 NEXT i%
250 REM === Test 1: Vectorized element-wise addition ===
260 REM This loop should be detected as Pattern A (whole-UDT binary op)
270 REM and emitted as a NEON vectorized loop
280 FOR i% = 0 TO 9
290   C(i%) = A(i%) + B(i%)
300 NEXT i%
310 REM === Verify results with individual element checks ===
320 PRINT "C(0): "; C(0).X; ","; C(0).Y; ","; C(0).Z; ","; C(0).W
330 IF C(0).X = 1 AND C(0).Y = 2 AND C(0).Z = 3 AND C(0).W = 4 THEN PRINT "ELEM0 PASS" ELSE PRINT "ELEM0 FAIL"
340 PRINT "C(1): "; C(1).X; ","; C(1).Y; ","; C(1).Z; ","; C(1).W
350 IF C(1).X = 11 AND C(1).Y = 22 AND C(1).Z = 33 AND C(1).W = 44 THEN PRINT "ELEM1 PASS" ELSE PRINT "ELEM1 FAIL"
360 PRINT "C(3): "; C(3).X; ","; C(3).Y; ","; C(3).Z; ","; C(3).W
370 IF C(3).X = 31 AND C(3).Y = 62 AND C(3).Z = 93 AND C(3).W = 124 THEN PRINT "ELEM3 PASS" ELSE PRINT "ELEM3 FAIL"
380 PRINT "C(5): "; C(5).X; ","; C(5).Y; ","; C(5).Z; ","; C(5).W
390 IF C(5).X = 51 AND C(5).Y = 102 AND C(5).Z = 153 AND C(5).W = 204 THEN PRINT "ELEM5 PASS" ELSE PRINT "ELEM5 FAIL"
400 PRINT "C(9): "; C(9).X; ","; C(9).Y; ","; C(9).Z; ","; C(9).W
410 IF C(9).X = 91 AND C(9).Y = 182 AND C(9).Z = 273 AND C(9).W = 364 THEN PRINT "ELEM9 PASS" ELSE PRINT "ELEM9 FAIL"
420 REM === Test 2: Source arrays should be unmodified ===
430 IF A(3).X = 30 AND A(3).Y = 60 AND A(3).Z = 90 AND A(3).W = 120 THEN PRINT "SRC A INTACT PASS" ELSE PRINT "SRC A INTACT FAIL"
440 IF B(3).X = 1 AND B(3).Y = 2 AND B(3).Z = 3 AND B(3).W = 4 THEN PRINT "SRC B INTACT PASS" ELSE PRINT "SRC B INTACT FAIL"
450 REM === Test 3: In-place addition (A = A + B) ===
460 FOR i% = 0 TO 9
470   A(i%) = A(i%) + B(i%)
480 NEXT i%
490 IF A(0).X = 1 AND A(0).Y = 2 AND A(0).Z = 3 AND A(0).W = 4 THEN PRINT "INPLACE0 PASS" ELSE PRINT "INPLACE0 FAIL"
500 IF A(5).X = 51 AND A(5).Y = 102 AND A(5).Z = 153 AND A(5).W = 204 THEN PRINT "INPLACE5 PASS" ELSE PRINT "INPLACE5 FAIL"
510 IF A(9).X = 91 AND A(9).Y = 182 AND A(9).Z = 273 AND A(9).W = 364 THEN PRINT "INPLACE9 PASS" ELSE PRINT "INPLACE9 FAIL"
520 REM === Test 4: Subtraction ===
530 DIM D(4) AS Vec4
540 DIM E(4) AS Vec4
550 DIM F(4) AS Vec4
560 FOR i% = 0 TO 4
570   D(i%).X = 100 : D(i%).Y = 200 : D(i%).Z = 300 : D(i%).W = 400
580   E(i%).X = i% : E(i%).Y = i% * 2 : E(i%).Z = i% * 3 : E(i%).W = i% * 4
590 NEXT i%
600 FOR i% = 0 TO 4
610   F(i%) = D(i%) - E(i%)
620 NEXT i%
630 IF F(0).X = 100 AND F(0).Y = 200 AND F(0).Z = 300 AND F(0).W = 400 THEN PRINT "SUB0 PASS" ELSE PRINT "SUB0 FAIL"
640 IF F(3).X = 97 AND F(3).Y = 194 AND F(3).Z = 291 AND F(3).W = 388 THEN PRINT "SUB3 PASS" ELSE PRINT "SUB3 FAIL"
650 REM === Test 5: Multiplication ===
660 DIM G(4) AS Vec4
670 FOR i% = 0 TO 4
680   D(i%).X = i% + 1 : D(i%).Y = i% + 2 : D(i%).Z = i% + 3 : D(i%).W = i% + 4
690   E(i%).X = 2 : E(i%).Y = 3 : E(i%).Z = 4 : E(i%).W = 5
700 NEXT i%
710 FOR i% = 0 TO 4
720   G(i%) = D(i%) * E(i%)
730 NEXT i%
740 IF G(0).X = 2 AND G(0).Y = 6 AND G(0).Z = 12 AND G(0).W = 20 THEN PRINT "MUL0 PASS" ELSE PRINT "MUL0 FAIL"
750 IF G(2).X = 6 AND G(2).Y = 12 AND G(2).Z = 20 AND G(2).W = 30 THEN PRINT "MUL2 PASS" ELSE PRINT "MUL2 FAIL"
760 PRINT "All NEON loop Vec4 add tests complete."
770 END
