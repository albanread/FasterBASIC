10 REM Test: NEON Phase 3 - Array loop vectorization (Vec4 array copy)
20 REM Verifies that FOR loops copying arrays of SIMD-eligible UDTs are
30 REM vectorized with NEON instructions (ldr q28, str q28 per element)
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 REM === Setup: create arrays of Vec4 ===
110 DIM Src(9) AS Vec4
120 DIM Dst(9) AS Vec4
130 REM === Initialize source array ===
140 FOR i% = 0 TO 9
150   Src(i%).X = (i% + 1) * 100
160   Src(i%).Y = (i% + 1) * 200
170   Src(i%).Z = (i% + 1) * 300
180   Src(i%).W = (i% + 1) * 400
190 NEXT i%
200 REM === Test 1: Vectorized array copy ===
210 REM This loop should be detected as Pattern B (whole-UDT copy)
220 REM and emitted as a NEON vectorized loop (ldr q28 / str q28)
230 FOR i% = 0 TO 9
240   Dst(i%) = Src(i%)
250 NEXT i%
260 REM === Verify all elements were copied correctly ===
270 DIM pass% AS INTEGER
280 pass% = 1
290 FOR i% = 0 TO 9
300   IF Dst(i%).X <> (i% + 1) * 100 THEN pass% = 0
310   IF Dst(i%).Y <> (i% + 1) * 200 THEN pass% = 0
320   IF Dst(i%).Z <> (i% + 1) * 300 THEN pass% = 0
330   IF Dst(i%).W <> (i% + 1) * 400 THEN pass% = 0
340 NEXT i%
350 IF pass% = 1 THEN PRINT "COPY ALL PASS" ELSE PRINT "COPY ALL FAIL"
360 REM === Check specific elements ===
370 PRINT "Dst(0): "; Dst(0).X; ","; Dst(0).Y; ","; Dst(0).Z; ","; Dst(0).W
380 IF Dst(0).X = 100 AND Dst(0).Y = 200 AND Dst(0).Z = 300 AND Dst(0).W = 400 THEN PRINT "ELEM0 PASS" ELSE PRINT "ELEM0 FAIL"
390 PRINT "Dst(4): "; Dst(4).X; ","; Dst(4).Y; ","; Dst(4).Z; ","; Dst(4).W
400 IF Dst(4).X = 500 AND Dst(4).Y = 1000 AND Dst(4).Z = 1500 AND Dst(4).W = 2000 THEN PRINT "ELEM4 PASS" ELSE PRINT "ELEM4 FAIL"
410 PRINT "Dst(9): "; Dst(9).X; ","; Dst(9).Y; ","; Dst(9).Z; ","; Dst(9).W
420 IF Dst(9).X = 1000 AND Dst(9).Y = 2000 AND Dst(9).Z = 3000 AND Dst(9).W = 4000 THEN PRINT "ELEM9 PASS" ELSE PRINT "ELEM9 FAIL"
430 REM === Test 2: Copy should be independent (modify source, check dest) ===
440 Src(0).X = 9999
450 Src(0).Y = 8888
460 IF Dst(0).X = 100 AND Dst(0).Y = 200 THEN PRINT "INDEPENDENCE PASS" ELSE PRINT "INDEPENDENCE FAIL"
470 REM === Test 3: Partial range copy (subset of array) ===
480 DIM A2(19) AS Vec4
490 DIM B2(19) AS Vec4
500 FOR i% = 0 TO 19
510   A2(i%).X = i%
520   A2(i%).Y = i% * 2
530   A2(i%).Z = i% * 3
540   A2(i%).W = i% * 4
550 NEXT i%
560 REM Copy elements 5..14 (the loop analyser should still vectorize this)
570 FOR i% = 5 TO 14
580   B2(i%) = A2(i%)
590 NEXT i%
600 REM Elements outside [5,14] should still be zero
610 IF B2(0).X = 0 AND B2(0).Y = 0 THEN PRINT "ZERO BEFORE PASS" ELSE PRINT "ZERO BEFORE FAIL"
620 IF B2(19).X = 0 AND B2(19).Y = 0 THEN PRINT "ZERO AFTER PASS" ELSE PRINT "ZERO AFTER FAIL"
630 REM Elements inside [5,14] should match A2
640 IF B2(5).X = 5 AND B2(5).Y = 10 AND B2(5).Z = 15 AND B2(5).W = 20 THEN PRINT "RANGE5 PASS" ELSE PRINT "RANGE5 FAIL"
650 IF B2(14).X = 14 AND B2(14).Y = 28 AND B2(14).Z = 42 AND B2(14).W = 56 THEN PRINT "RANGE14 PASS" ELSE PRINT "RANGE14 FAIL"
660 PRINT "All NEON loop copy tests complete."
670 END
