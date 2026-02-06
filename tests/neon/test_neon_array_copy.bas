10 REM Test: NEON bulk copy for Vec4 array elements
20 REM Vec4 (4x INTEGER = 128 bits) is SIMD-eligible (V4S).
30 REM Copying individual array elements should use NEON ldr/str q28.
40 TYPE Vec4
50   X AS INTEGER
60   Y AS INTEGER
70   Z AS INTEGER
80   W AS INTEGER
90 END TYPE
100 DIM Positions(5) AS Vec4
110 DIM Velocities(5) AS Vec4
120 REM Initialize array elements
130 FOR I = 0 TO 4
140   Positions(I).X = I * 10
150   Positions(I).Y = I * 10 + 1
160   Positions(I).Z = I * 10 + 2
170   Positions(I).W = I * 10 + 3
180   Velocities(I).X = I * 100
190   Velocities(I).Y = I * 100 + 10
200   Velocities(I).Z = I * 100 + 20
210   Velocities(I).W = I * 100 + 30
220 NEXT I
230 REM Verify initial values
240 PRINT "Positions(0) = "; Positions(0).X; ","; Positions(0).Y; ","; Positions(0).Z; ","; Positions(0).W
250 PRINT "Positions(3) = "; Positions(3).X; ","; Positions(3).Y; ","; Positions(3).Z; ","; Positions(3).W
260 PRINT "Velocities(2) = "; Velocities(2).X; ","; Velocities(2).Y; ","; Velocities(2).Z; ","; Velocities(2).W
270 REM Test 1: Copy one array element to another (same array)
280 Positions(4) = Positions(1)
290 IF Positions(4).X = 10 AND Positions(4).Y = 11 AND Positions(4).Z = 12 AND Positions(4).W = 13 THEN PRINT "SAME ARRAY COPY PASS" ELSE PRINT "SAME ARRAY COPY FAIL"
300 REM Verify source unchanged
310 IF Positions(1).X = 10 AND Positions(1).Y = 11 THEN PRINT "SOURCE INTACT PASS" ELSE PRINT "SOURCE INTACT FAIL"
320 REM Test 2: Copy between different arrays
330 Positions(0) = Velocities(3)
340 IF Positions(0).X = 300 AND Positions(0).Y = 310 AND Positions(0).Z = 320 AND Positions(0).W = 330 THEN PRINT "CROSS ARRAY COPY PASS" ELSE PRINT "CROSS ARRAY COPY FAIL"
350 REM Verify Velocities(3) unchanged
360 IF Velocities(3).X = 300 AND Velocities(3).Y = 310 THEN PRINT "CROSS SOURCE INTACT PASS" ELSE PRINT "CROSS SOURCE INTACT FAIL"
370 REM Test 3: Copy element to scalar UDT and back
380 DIM Temp AS Vec4
390 Temp = Positions(2)
400 IF Temp.X = 20 AND Temp.Y = 21 AND Temp.Z = 22 AND Temp.W = 23 THEN PRINT "ARRAY TO SCALAR PASS" ELSE PRINT "ARRAY TO SCALAR FAIL"
410 Temp.X = 999
420 Temp.Y = 998
430 Temp.Z = 997
440 Temp.W = 996
450 Velocities(0) = Temp
460 IF Velocities(0).X = 999 AND Velocities(0).Y = 998 AND Velocities(0).Z = 997 AND Velocities(0).W = 996 THEN PRINT "SCALAR TO ARRAY PASS" ELSE PRINT "SCALAR TO ARRAY FAIL"
470 REM Test 4: Copy with computed index
480 DIM Idx AS INTEGER
490 Idx = 2
500 Temp = Velocities(Idx)
510 IF Temp.X = 200 AND Temp.Y = 210 AND Temp.Z = 220 AND Temp.W = 230 THEN PRINT "COMPUTED INDEX PASS" ELSE PRINT "COMPUTED INDEX FAIL"
520 REM Test 5: Chained copies through array
530 Positions(1) = Velocities(4)
540 Positions(3) = Positions(1)
550 IF Positions(3).X = 400 AND Positions(3).Y = 410 AND Positions(3).Z = 420 AND Positions(3).W = 430 THEN PRINT "CHAINED COPY PASS" ELSE PRINT "CHAINED COPY FAIL"
560 REM Test 6: Loop copy — bulk copy all elements from one array to another
570 FOR I = 0 TO 4
580   Positions(I).X = I + 1
590   Positions(I).Y = (I + 1) * 2
600   Positions(I).Z = (I + 1) * 3
610   Positions(I).W = (I + 1) * 4
620 NEXT I
630 FOR I = 0 TO 4
640   Velocities(I) = Positions(I)
650 NEXT I
660 REM Verify all copied correctly
670 DIM AllOk AS INTEGER
680 AllOk = 1
690 FOR I = 0 TO 4
700   IF Velocities(I).X <> I + 1 THEN AllOk = 0
710   IF Velocities(I).Y <> (I + 1) * 2 THEN AllOk = 0
720   IF Velocities(I).Z <> (I + 1) * 3 THEN AllOk = 0
730   IF Velocities(I).W <> (I + 1) * 4 THEN AllOk = 0
740 NEXT I
750 IF AllOk = 1 THEN PRINT "LOOP COPY PASS" ELSE PRINT "LOOP COPY FAIL"
760 REM Test 7: Verify original not modified after loop copy
770 IF Positions(2).X = 3 AND Positions(2).Y = 6 AND Positions(2).Z = 9 AND Positions(2).W = 12 THEN PRINT "LOOP SOURCE PASS" ELSE PRINT "LOOP SOURCE FAIL"
780 PRINT "All Vec4 array NEON copy tests complete."
790 END
