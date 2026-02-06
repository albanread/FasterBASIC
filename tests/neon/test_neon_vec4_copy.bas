10 REM Test: NEON bulk copy for Vec4 (4x INTEGER = 128 bits)
20 REM This UDT should be detected as SIMD-eligible (V4S: 4×32-bit)
30 REM and copied via a single NEON ldr q28/str q28 pair.
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 DIM A AS Vec4
110 DIM B AS Vec4
120 REM Set up source values
130 A.X = 10
140 A.Y = 20
150 A.Z = 30
160 A.W = 40
170 PRINT "Before copy:"
180 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
190 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
200 REM Whole-struct assignment (should use NEON bulk copy)
210 B = A
220 PRINT "After B = A:"
230 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
240 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
250 REM Verify B got correct values
260 IF B.X = 10 AND B.Y = 20 AND B.Z = 30 AND B.W = 40 THEN PRINT "COPY PASS" ELSE PRINT "COPY FAIL"
270 REM Modify B to verify independence (no aliasing)
280 B.X = 100
290 B.Y = 200
300 B.Z = 300
310 B.W = 400
320 PRINT "After modifying B:"
330 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
340 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
350 REM Verify A unchanged
360 IF A.X = 10 AND A.Y = 20 AND A.Z = 30 AND A.W = 40 THEN PRINT "INDEP PASS" ELSE PRINT "INDEP FAIL"
370 REM Verify B has new values
380 IF B.X = 100 AND B.Y = 200 AND B.Z = 300 AND B.W = 400 THEN PRINT "MODIFY PASS" ELSE PRINT "MODIFY FAIL"
390 REM Test copy in the other direction
400 A = B
410 IF A.X = 100 AND A.Y = 200 AND A.Z = 300 AND A.W = 400 THEN PRINT "REVERSE PASS" ELSE PRINT "REVERSE FAIL"
420 REM Test with negative values and zero
430 A.X = -1
440 A.Y = 0
450 A.Z = 2147483647
460 A.W = -2147483647
470 B = A
480 IF B.X = -1 AND B.Y = 0 AND B.Z = 2147483647 AND B.W = -2147483647 THEN PRINT "EDGE PASS" ELSE PRINT "EDGE FAIL"
490 PRINT "All Vec4 NEON copy tests complete."
500 END
