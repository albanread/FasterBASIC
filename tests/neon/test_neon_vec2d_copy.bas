10 REM Test: NEON bulk copy for Vec2D (2x DOUBLE = 128 bits)
20 REM This UDT should be detected as SIMD-eligible (V2D: 2×64-bit)
30 REM and copied via a single NEON ldr q28/str q28 pair.
40 TYPE Vec2D
50   X AS DOUBLE
60   Y AS DOUBLE
70 END TYPE
80 DIM A AS Vec2D
90 DIM B AS Vec2D
100 REM Set up source values
110 A.X = 3.14159
120 A.Y = 2.71828
130 PRINT "Before copy:"
140 PRINT "A.X = "; A.X; ", A.Y = "; A.Y
150 PRINT "B.X = "; B.X; ", B.Y = "; B.Y
160 REM Whole-struct assignment (should use NEON bulk copy)
170 B = A
180 PRINT "After B = A:"
190 PRINT "A.X = "; A.X; ", A.Y = "; A.Y
200 PRINT "B.X = "; B.X; ", B.Y = "; B.Y
210 REM Verify B got correct values (within floating-point tolerance)
220 IF B.X > 3.14 AND B.X < 3.15 AND B.Y > 2.71 AND B.Y < 2.72 THEN PRINT "COPY PASS" ELSE PRINT "COPY FAIL"
230 REM Modify B to verify independence
240 B.X = 100.5
250 B.Y = 200.75
260 PRINT "After modifying B:"
270 PRINT "A.X = "; A.X; ", A.Y = "; A.Y
280 PRINT "B.X = "; B.X; ", B.Y = "; B.Y
290 REM Verify A unchanged
300 IF A.X > 3.14 AND A.X < 3.15 AND A.Y > 2.71 AND A.Y < 2.72 THEN PRINT "INDEP PASS" ELSE PRINT "INDEP FAIL"
310 REM Verify B has new values
320 IF B.X > 100.4 AND B.X < 100.6 AND B.Y > 200.7 AND B.Y < 200.8 THEN PRINT "MODIFY PASS" ELSE PRINT "MODIFY FAIL"
330 REM Test copy in reverse direction
340 A = B
350 IF A.X > 100.4 AND A.X < 100.6 AND A.Y > 200.7 AND A.Y < 200.8 THEN PRINT "REVERSE PASS" ELSE PRINT "REVERSE FAIL"
360 REM Test with special floating-point values
370 A.X = 0.0
380 A.Y = -0.0
390 B = A
400 IF B.X = 0.0 AND B.Y = 0.0 THEN PRINT "ZERO PASS" ELSE PRINT "ZERO FAIL"
410 REM Test with very small values
420 A.X = 0.000001
430 A.Y = -0.000001
440 B = A
450 IF B.X > 0.0000009 AND B.X < 0.0000011 AND B.Y < -0.0000009 AND B.Y > -0.0000011 THEN PRINT "SMALL PASS" ELSE PRINT "SMALL FAIL"
460 REM Test with very large values
470 A.X = 1000000000.5
480 A.Y = -1000000000.5
490 B = A
500 IF B.X > 999999999.0 AND B.X < 1000000001.0 AND B.Y < -999999999.0 AND B.Y > -1000000001.0 THEN PRINT "LARGE PASS" ELSE PRINT "LARGE FAIL"
510 PRINT "All Vec2D NEON copy tests complete."
520 END
