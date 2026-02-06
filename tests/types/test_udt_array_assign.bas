10 REM Test: UDT assignment from array element
20 TYPE Point
30   X AS INTEGER
40   Y AS INTEGER
50 END TYPE
60 DIM Points(3) AS Point
70 DIM P AS Point
80 Points(0).X = 10
90 Points(0).Y = 20
100 Points(1).X = 30
110 Points(1).Y = 40
120 Points(2).X = 50
130 Points(2).Y = 60
140 REM Assign from array element to scalar UDT
150 P = Points(1)
160 PRINT "P.X = "; P.X; ", P.Y = "; P.Y
170 IF P.X = 30 AND P.Y = 40 THEN PRINT "Copy from array(1): PASS" ELSE PRINT "Copy from array(1): FAIL"
180 REM Verify independence (modifying P should not change array)
190 P.X = 999
200 P.Y = 888
210 IF Points(1).X = 30 AND Points(1).Y = 40 THEN PRINT "Independence: PASS" ELSE PRINT "Independence: FAIL"
220 REM Assign from different array element
230 P = Points(2)
240 IF P.X = 50 AND P.Y = 60 THEN PRINT "Copy from array(2): PASS" ELSE PRINT "Copy from array(2): FAIL"
250 REM Assign from array element at index 0
260 P = Points(0)
270 IF P.X = 10 AND P.Y = 20 THEN PRINT "Copy from array(0): PASS" ELSE PRINT "Copy from array(0): FAIL"
280 END
