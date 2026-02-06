10 REM Test: NEON bulk copy for Vec4F (4x SINGLE = 128 bits)
20 REM This UDT should be detected as SIMD-eligible (V4S float: 4×32-bit)
30 REM and copied via a single NEON ldr q28/str q28 pair.
40 TYPE Vec4F
50   X AS SINGLE
60   Y AS SINGLE
70   Z AS SINGLE
80   W AS SINGLE
90 END TYPE
100 DIM A AS Vec4F
110 DIM B AS Vec4F
120 REM Set up source values
130 A.X = 1.5
140 A.Y = 2.5
150 A.Z = 3.5
160 A.W = 4.5
170 PRINT "Before copy:"
180 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
190 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
200 REM Whole-struct assignment (should use NEON bulk copy)
210 B = A
220 PRINT "After B = A:"
230 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
240 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
250 REM Verify B got correct values (within SINGLE precision tolerance)
260 IF B.X > 1.4 AND B.X < 1.6 AND B.Y > 2.4 AND B.Y < 2.6 AND B.Z > 3.4 AND B.Z < 3.6 AND B.W > 4.4 AND B.W < 4.6 THEN PRINT "COPY PASS" ELSE PRINT "COPY FAIL"
270 REM Modify B to verify independence (no aliasing)
280 B.X = 10.25
290 B.Y = 20.75
300 B.Z = 30.125
310 B.W = 40.875
320 PRINT "After modifying B:"
330 PRINT "A = "; A.X; ","; A.Y; ","; A.Z; ","; A.W
340 PRINT "B = "; B.X; ","; B.Y; ","; B.Z; ","; B.W
350 REM Verify A unchanged
360 IF A.X > 1.4 AND A.X < 1.6 AND A.Y > 2.4 AND A.Y < 2.6 AND A.Z > 3.4 AND A.Z < 3.6 AND A.W > 4.4 AND A.W < 4.6 THEN PRINT "INDEP PASS" ELSE PRINT "INDEP FAIL"
370 REM Verify B has new values
380 IF B.X > 10.2 AND B.X < 10.3 AND B.Y > 20.7 AND B.Y < 20.8 AND B.Z > 30.1 AND B.Z < 30.2 AND B.W > 40.8 AND B.W < 40.9 THEN PRINT "MODIFY PASS" ELSE PRINT "MODIFY FAIL"
390 REM Test copy in the other direction
400 A = B
410 IF A.X > 10.2 AND A.X < 10.3 AND A.Y > 20.7 AND A.Y < 20.8 THEN PRINT "REVERSE PASS" ELSE PRINT "REVERSE FAIL"
420 REM Test with zero and negative values
430 A.X = 0.0
440 A.Y = -1.0
450 A.Z = -0.5
460 A.W = 0.001
470 B = A
480 IF B.X = 0.0 AND B.Y < -0.9 AND B.Y > -1.1 AND B.Z < -0.4 AND B.Z > -0.6 AND B.W > 0.0009 AND B.W < 0.0011 THEN PRINT "NEGZERO PASS" ELSE PRINT "NEGZERO FAIL"
490 REM Test with array of Vec4F
500 DIM Colors(4) AS Vec4F
510 FOR I = 0 TO 3
520   Colors(I).X = I * 0.25
530   Colors(I).Y = I * 0.5
540   Colors(I).Z = I * 0.75
550   Colors(I).W = 1.0
560 NEXT I
570 REM Copy array elements
580 DIM Temp AS Vec4F
590 Temp = Colors(2)
600 IF Temp.X > 0.49 AND Temp.X < 0.51 AND Temp.Y > 0.99 AND Temp.Y < 1.01 AND Temp.Z > 1.49 AND Temp.Z < 1.51 AND Temp.W > 0.99 AND Temp.W < 1.01 THEN PRINT "ARRAY ELEM PASS" ELSE PRINT "ARRAY ELEM FAIL"
610 REM Copy between array elements
620 Colors(0) = Colors(3)
630 IF Colors(0).X > 0.74 AND Colors(0).X < 0.76 AND Colors(0).Y > 1.49 AND Colors(0).Y < 1.51 THEN PRINT "ARRAY CROSS PASS" ELSE PRINT "ARRAY CROSS FAIL"
640 REM Verify Colors(3) not modified
650 IF Colors(3).X > 0.74 AND Colors(3).X < 0.76 AND Colors(3).Y > 1.49 AND Colors(3).Y < 1.51 THEN PRINT "ARRAY SRC PASS" ELSE PRINT "ARRAY SRC FAIL"
660 REM Test chained copy through scalar
670 Temp.X = 99.5
680 Temp.Y = 88.5
690 Temp.Z = 77.5
700 Temp.W = 66.5
710 Colors(1) = Temp
720 DIM Temp2 AS Vec4F
730 Temp2 = Colors(1)
740 IF Temp2.X > 99.4 AND Temp2.X < 99.6 AND Temp2.Y > 88.4 AND Temp2.Y < 88.6 AND Temp2.Z > 77.4 AND Temp2.Z < 77.6 AND Temp2.W > 66.4 AND Temp2.W < 66.6 THEN PRINT "CHAIN PASS" ELSE PRINT "CHAIN FAIL"
750 PRINT "All Vec4F NEON copy tests complete."
760 END
