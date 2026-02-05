10 REM Test: UDT-to-UDT assignment (whole struct copy)
20 TYPE Point
30   X AS INTEGER
40   Y AS DOUBLE
50 END TYPE
60 DIM P1 AS Point
70 DIM P2 AS Point
80 REM Set up P1
90 P1.X = 100
100 P1.Y = 200.5
110 PRINT "Before assignment:"
120 PRINT "P1.X = "; P1.X; ", P1.Y = "; P1.Y
130 PRINT "P2.X = "; P2.X; ", P2.Y = "; P2.Y
140 REM Assign P1 to P2 (whole struct copy)
150 P2 = P1
160 PRINT "After P2 = P1:"
170 PRINT "P1.X = "; P1.X; ", P1.Y = "; P1.Y
180 PRINT "P2.X = "; P2.X; ", P2.Y = "; P2.Y
190 REM Modify P2 to verify independence
200 P2.X = 999
210 P2.Y = 888.8
220 PRINT "After modifying P2:"
230 PRINT "P1.X = "; P1.X; ", P1.Y = "; P1.Y
240 PRINT "P2.X = "; P2.X; ", P2.Y = "; P2.Y
250 REM Verify correct values
260 IF P1.X = 100 AND P1.Y > 200.4 AND P1.Y < 200.6 THEN PRINT "P1 PASS" ELSE PRINT "P1 FAIL"
270 IF P2.X = 999 AND P2.Y > 888.7 AND P2.Y < 888.9 THEN PRINT "P2 PASS" ELSE PRINT "P2 FAIL"
280 END
