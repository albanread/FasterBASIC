10 REM Test: NEON element-wise Vec4 (4x INTEGER) arithmetic
20 REM Vec4 is SIMD-eligible (V4S: 4×32-bit integer, Q-reg)
30 REM Tests: addition, subtraction, multiplication
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 DIM A AS Vec4
110 DIM B AS Vec4
120 DIM C AS Vec4
130 REM === Test 1: Vector Addition ===
140 A.X = 10 : A.Y = 20 : A.Z = 30 : A.W = 40
150 B.X = 1  : B.Y = 2  : B.Z = 3  : B.W = 4
160 C = A + B
170 PRINT "ADD: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
180 IF C.X = 11 AND C.Y = 22 AND C.Z = 33 AND C.W = 44 THEN PRINT "ADD PASS" ELSE PRINT "ADD FAIL"
190 REM === Test 2: Vector Subtraction ===
200 A.X = 100 : A.Y = 200 : A.Z = 300 : A.W = 400
210 B.X = 1   : B.Y = 2   : B.Z = 3   : B.W = 4
220 C = A - B
230 PRINT "SUB: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
240 IF C.X = 99 AND C.Y = 198 AND C.Z = 297 AND C.W = 396 THEN PRINT "SUB PASS" ELSE PRINT "SUB FAIL"
250 REM === Test 3: Vector Multiplication ===
260 A.X = 2 : A.Y = 3 : A.Z = 4 : A.W = 5
270 B.X = 10 : B.Y = 20 : B.Z = 30 : B.W = 40
280 C = A * B
290 PRINT "MUL: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
300 IF C.X = 20 AND C.Y = 60 AND C.Z = 120 AND C.W = 200 THEN PRINT "MUL PASS" ELSE PRINT "MUL FAIL"
310 REM === Test 4: Negative values ===
320 A.X = -5 : A.Y = 10 : A.Z = -15 : A.W = 20
330 B.X = 3  : B.Y = -7  : B.Z = 2   : B.W = -1
340 C = A + B
350 PRINT "NEG ADD: "; C.X; ","; C.Y; ","; C.Z; ","; C.W
360 IF C.X = -2 AND C.Y = 3 AND C.Z = -13 AND C.W = 19 THEN PRINT "NEG ADD PASS" ELSE PRINT "NEG ADD FAIL"
370 REM === Test 5: Zero values ===
380 A.X = 0 : A.Y = 0 : A.Z = 0 : A.W = 0
390 B.X = 42 : B.Y = -42 : B.Z = 1 : B.W = -1
400 C = A + B
410 IF C.X = 42 AND C.Y = -42 AND C.Z = 1 AND C.W = -1 THEN PRINT "ZERO ADD PASS" ELSE PRINT "ZERO ADD FAIL"
420 REM === Test 6: Self-operation (A = A + B) ===
430 A.X = 5 : A.Y = 10 : A.Z = 15 : A.W = 20
440 B.X = 1 : B.Y = 1  : B.Z = 1  : B.W = 1
450 A = A + B
460 IF A.X = 6 AND A.Y = 11 AND A.Z = 16 AND A.W = 21 THEN PRINT "SELF ADD PASS" ELSE PRINT "SELF ADD FAIL"
470 REM === Test 7: Independence check (C = A + B should not modify A or B) ===
480 A.X = 10 : A.Y = 20 : A.Z = 30 : A.W = 40
490 B.X = 1  : B.Y = 2  : B.Z = 3  : B.W = 4
500 C = A + B
510 IF A.X = 10 AND A.Y = 20 AND A.Z = 30 AND A.W = 40 THEN PRINT "SRC A INTACT PASS" ELSE PRINT "SRC A INTACT FAIL"
520 IF B.X = 1 AND B.Y = 2 AND B.Z = 3 AND B.W = 4 THEN PRINT "SRC B INTACT PASS" ELSE PRINT "SRC B INTACT FAIL"
530 REM === Test 8: Subtract to zero ===
540 A.X = 7 : A.Y = 14 : A.Z = 21 : A.W = 28
550 B.X = 7 : B.Y = 14 : B.Z = 21 : B.W = 28
560 C = A - B
570 IF C.X = 0 AND C.Y = 0 AND C.Z = 0 AND C.W = 0 THEN PRINT "SUB ZERO PASS" ELSE PRINT "SUB ZERO FAIL"
580 PRINT "All Vec4 NEON arithmetic tests complete."
590 END
