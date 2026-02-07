10 REM Test: NEON element-wise Vec4F (4x SINGLE) float arithmetic
20 REM Vec4F is SIMD-eligible (V4S: 4×32-bit float, Q-reg)
30 REM Tests: addition, subtraction, multiplication, division
40 TYPE Vec4F
50   X AS SINGLE
60   Y AS SINGLE
70   Z AS SINGLE
80   W AS SINGLE
90 END TYPE
100 DIM A AS Vec4F
110 DIM B AS Vec4F
120 DIM C AS Vec4F
130 REM === Test 1: Vector Addition ===
140 A.X = 1.5 : A.Y = 2.5 : A.Z = 3.5 : A.W = 4.5
150 B.X = 0.5 : B.Y = 1.0 : B.Z = 1.5 : B.W = 2.0
160 C = A + B
170 PRINT "FADD: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
180 IF C.X = 2.0 AND C.Y = 3.5 AND C.Z = 5.0 AND C.W = 6.5 THEN PRINT "FADD PASS" ELSE PRINT "FADD FAIL"
190 REM === Test 2: Vector Subtraction ===
200 A.X = 10.0 : A.Y = 20.0 : A.Z = 30.0 : A.W = 40.0
210 B.X = 0.5  : B.Y = 1.5  : B.Z = 2.5  : B.W = 3.5
220 C = A - B
230 PRINT "FSUB: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
240 IF C.X = 9.5 AND C.Y = 18.5 AND C.Z = 27.5 AND C.W = 36.5 THEN PRINT "FSUB PASS" ELSE PRINT "FSUB FAIL"
250 REM === Test 3: Vector Multiplication ===
260 A.X = 2.0 : A.Y = 3.0 : A.Z = 4.0 : A.W = 5.0
270 B.X = 0.5 : B.Y = 0.25 : B.Z = 0.125 : B.W = 0.1
280 C = A * B
290 PRINT "FMUL: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
300 IF C.X = 1.0 AND C.Y = 0.75 AND C.Z = 0.5 THEN PRINT "FMUL PASS" ELSE PRINT "FMUL FAIL"
310 REM === Test 4: Vector Division ===
320 A.X = 10.0 : A.Y = 20.0 : A.Z = 30.0 : A.W = 40.0
330 B.X = 2.0  : B.Y = 4.0  : B.Z = 5.0  : B.W = 8.0
340 C = A / B
350 PRINT "FDIV: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
360 IF C.X = 5.0 AND C.Y = 5.0 AND C.Z = 6.0 AND C.W = 5.0 THEN PRINT "FDIV PASS" ELSE PRINT "FDIV FAIL"
370 REM === Test 5: Negative floats ===
380 A.X = -1.5 : A.Y = 2.5 : A.Z = -3.5 : A.W = 4.5
390 B.X = 0.5  : B.Y = -0.5 : B.Z = 0.5  : B.W = -0.5
400 C = A + B
410 PRINT "FNEG ADD: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
420 IF C.X = -1.0 AND C.Y = 2.0 AND C.Z = -3.0 AND C.W = 4.0 THEN PRINT "FNEG ADD PASS" ELSE PRINT "FNEG ADD FAIL"
430 REM === Test 6: Zero handling ===
440 A.X = 0.0 : A.Y = 0.0 : A.Z = 0.0 : A.W = 0.0
450 B.X = 3.25 : B.Y = 2.75 : B.Z = 1.5 : B.W = 1.125
460 C = A + B
470 IF C.X = 3.25 AND C.Y = 2.75 AND C.Z = 1.5 AND C.W = 1.125 THEN PRINT "FZERO ADD PASS" ELSE PRINT "FZERO ADD FAIL"
480 REM === Test 7: Self-operation (A = A * B) ===
490 A.X = 2.0 : A.Y = 3.0 : A.Z = 4.0 : A.W = 5.0
500 B.X = 2.0 : B.Y = 2.0 : B.Z = 2.0 : B.W = 2.0
510 A = A * B
520 IF A.X = 4.0 AND A.Y = 6.0 AND A.Z = 8.0 AND A.W = 10.0 THEN PRINT "FSELF MUL PASS" ELSE PRINT "FSELF MUL FAIL"
530 REM === Test 8: Division by one ===
540 A.X = 7.5 : A.Y = 15.25 : A.Z = 100.0 : A.W = 0.125
550 B.X = 1.0 : B.Y = 1.0   : B.Z = 1.0   : B.W = 1.0
560 C = A / B
570 IF C.X = 7.5 AND C.Y = 15.25 AND C.Z = 100.0 AND C.W = 0.125 THEN PRINT "FDIV ONE PASS" ELSE PRINT "FDIV ONE FAIL"
580 REM === Test 9: Independence check ===
590 A.X = 1.0 : A.Y = 2.0 : A.Z = 3.0 : A.W = 4.0
600 B.X = 5.0 : B.Y = 6.0 : B.Z = 7.0 : B.W = 8.0
610 C = A + B
620 IF A.X = 1.0 AND A.Y = 2.0 AND A.Z = 3.0 AND A.W = 4.0 THEN PRINT "FSRC A INTACT PASS" ELSE PRINT "FSRC A INTACT FAIL"
630 IF B.X = 5.0 AND B.Y = 6.0 AND B.Z = 7.0 AND B.W = 8.0 THEN PRINT "FSRC B INTACT PASS" ELSE PRINT "FSRC B INTACT FAIL"
640 REM === Test 10: Subtract to zero ===
650 A.X = 1.5 : A.Y = 2.5 : A.Z = 3.5 : A.W = 4.5
660 B.X = 1.5 : B.Y = 2.5 : B.Z = 3.5 : B.W = 4.5
670 C = A - B
680 IF C.X = 0.0 AND C.Y = 0.0 AND C.Z = 0.0 AND C.W = 0.0 THEN PRINT "FSUB ZERO PASS" ELSE PRINT "FSUB ZERO FAIL"
690 PRINT "All Vec4F NEON float arithmetic tests complete."
700 END
