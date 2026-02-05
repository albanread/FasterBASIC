10 REM Test: UDT with two fields of different types
20 TYPE Point
30   X AS INTEGER
40   Y AS DOUBLE
50 END TYPE
60 DIM P AS Point
70 P.X = 10
80 P.Y = 20.5
90 PRINT "P.X = "; P.X; ", P.Y = "; P.Y
100 IF P.X = 10 AND P.Y > 20.4 AND P.Y < 20.6 THEN PRINT "PASS" ELSE PRINT "FAIL"
110 END
