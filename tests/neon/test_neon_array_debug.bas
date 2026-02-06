10 REM Minimal debug test for NEON array element copy
20 TYPE Vec4
30   X AS INTEGER
40   Y AS INTEGER
50   Z AS INTEGER
60   W AS INTEGER
70 END TYPE
80 DIM Arr(3) AS Vec4
90 DIM Temp AS Vec4
100 REM Set up array element 0
110 Arr(0).X = 11
120 Arr(0).Y = 22
130 Arr(0).Z = 33
140 Arr(0).W = 44
150 PRINT "Arr(0) = "; Arr(0).X; ","; Arr(0).Y; ","; Arr(0).Z; ","; Arr(0).W
160 REM Copy array element to scalar (this should work)
170 Temp = Arr(0)
180 PRINT "Temp after Temp=Arr(0): "; Temp.X; ","; Temp.Y; ","; Temp.Z; ","; Temp.W
190 IF Temp.X = 11 AND Temp.Y = 22 AND Temp.Z = 33 AND Temp.W = 44 THEN PRINT "ARR-TO-SCALAR PASS" ELSE PRINT "ARR-TO-SCALAR FAIL"
200 REM Now copy scalar to array element 1
210 Arr(1) = Temp
220 PRINT "Arr(1) after Arr(1)=Temp: "; Arr(1).X; ","; Arr(1).Y; ","; Arr(1).Z; ","; Arr(1).W
230 IF Arr(1).X = 11 AND Arr(1).Y = 22 AND Arr(1).Z = 33 AND Arr(1).W = 44 THEN PRINT "SCALAR-TO-ARR PASS" ELSE PRINT "SCALAR-TO-ARR FAIL"
240 REM Now copy between array elements
250 Arr(0).X = 100
260 Arr(0).Y = 200
270 Arr(0).Z = 300
280 Arr(0).W = 400
290 Arr(2) = Arr(0)
300 PRINT "Arr(2) after Arr(2)=Arr(0): "; Arr(2).X; ","; Arr(2).Y; ","; Arr(2).Z; ","; Arr(2).W
310 IF Arr(2).X = 100 AND Arr(2).Y = 200 AND Arr(2).Z = 300 AND Arr(2).W = 400 THEN PRINT "ARR-TO-ARR PASS" ELSE PRINT "ARR-TO-ARR FAIL"
320 END
