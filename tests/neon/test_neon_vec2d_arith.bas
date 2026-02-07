10 REM Test: NEON element-wise Vec2D (2x DOUBLE) arithmetic
20 REM Vec2D is SIMD-eligible (V2D: 2×64-bit float, Q-reg)
30 REM Tests: addition, subtraction, multiplication, division
40 TYPE Vec2D
50   X AS DOUBLE
60   Y AS DOUBLE
70 END TYPE
100 DIM A AS Vec2D
110 DIM B AS Vec2D
120 DIM C AS Vec2D
130 REM === Test 1: Vector Addition ===
140 A.X = 1.5 : A.Y = 2.5
150 B.X = 0.5 : B.Y = 1.0
160 C = A + B
170 PRINT "DADD: "; C.X; ","; C.Y
180 IF C.X = 2.0 AND C.Y = 3.5 THEN PRINT "DADD PASS" ELSE PRINT "DADD FAIL"
190 REM === Test 2: Vector Subtraction ===
200 A.X = 10.0 : A.Y = 20.0
210 B.X = 0.5  : B.Y = 1.5
220 C = A - B
230 PRINT "DSUB: "; C.X; ","; C.Y
240 IF C.X = 9.5 AND C.Y = 18.5 THEN PRINT "DSUB PASS" ELSE PRINT "DSUB FAIL"
250 REM === Test 3: Vector Multiplication ===
260 A.X = 3.0 : A.Y = 4.0
270 B.X = 2.0 : B.Y = 0.5
280 C = A * B
290 PRINT "DMUL: "; C.X; ","; C.Y
300 IF C.X = 6.0 AND C.Y = 2.0 THEN PRINT "DMUL PASS" ELSE PRINT "DMUL FAIL"
310 REM === Test 4: Vector Division ===
320 A.X = 10.0 : A.Y = 20.0
330 B.X = 2.0  : B.Y = 4.0
340 C = A / B
350 PRINT "DDIV: "; C.X; ","; C.Y
360 IF C.X = 5.0 AND C.Y = 5.0 THEN PRINT "DDIV PASS" ELSE PRINT "DDIV FAIL"
370 REM === Test 5: Negative doubles ===
380 A.X = -1.5 : A.Y = 2.5
390 B.X = 0.5  : B.Y = -0.5
400 C = A + B
410 PRINT "DNEG ADD: "; C.X; ","; C.Y
420 IF C.X = -1.0 AND C.Y = 2.0 THEN PRINT "DNEG ADD PASS" ELSE PRINT "DNEG ADD FAIL"
430 REM === Test 6: Zero handling ===
440 A.X = 0.0 : A.Y = 0.0
450 B.X = 3.14159265358979 : B.Y = 2.71828182845905
460 C = A + B
470 IF C.X = 3.14159265358979 AND C.Y = 2.71828182845905 THEN PRINT "DZERO ADD PASS" ELSE PRINT "DZERO ADD FAIL"
480 REM === Test 7: Self-operation (A = A * B) ===
490 A.X = 3.0 : A.Y = 5.0
500 B.X = 2.0 : B.Y = 2.0
510 A = A * B
520 IF A.X = 6.0 AND A.Y = 10.0 THEN PRINT "DSELF MUL PASS" ELSE PRINT "DSELF MUL FAIL"
530 REM === Test 8: Division by one ===
540 A.X = 7.5 : A.Y = 15.25
550 B.X = 1.0 : B.Y = 1.0
560 C = A / B
570 IF C.X = 7.5 AND C.Y = 15.25 THEN PRINT "DDIV ONE PASS" ELSE PRINT "DDIV ONE FAIL"
580 REM === Test 9: Independence check ===
590 A.X = 1.0 : A.Y = 2.0
600 B.X = 5.0 : B.Y = 6.0
610 C = A + B
620 IF A.X = 1.0 AND A.Y = 2.0 THEN PRINT "DSRC A INTACT PASS" ELSE PRINT "DSRC A INTACT FAIL"
630 IF B.X = 5.0 AND B.Y = 6.0 THEN PRINT "DSRC B INTACT PASS" ELSE PRINT "DSRC B INTACT FAIL"
640 REM === Test 10: Subtract to zero ===
650 A.X = 1.5 : A.Y = 2.5
660 B.X = 1.5 : B.Y = 2.5
670 C = A - B
680 IF C.X = 0.0 AND C.Y = 0.0 THEN PRINT "DSUB ZERO PASS" ELSE PRINT "DSUB ZERO FAIL"
690 REM === Test 11: Large values ===
700 A.X = 1000000.0 : A.Y = 999999.0
710 B.X = 1.0       : B.Y = 1.0
720 C = A + B
730 IF C.X = 1000001.0 AND C.Y = 1000000.0 THEN PRINT "DLARGE ADD PASS" ELSE PRINT "DLARGE ADD FAIL"
740 REM === Test 12: Small values (precision) ===
750 A.X = 0.001 : A.Y = 0.002
760 B.X = 0.001 : B.Y = 0.002
770 C = A + B
780 IF C.X = 0.002 AND C.Y = 0.004 THEN PRINT "DSMALL ADD PASS" ELSE PRINT "DSMALL ADD FAIL"
790 PRINT "All Vec2D NEON double arithmetic tests complete."
800 END
