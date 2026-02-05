10 REM Test: Array of UDT
20 TYPE Point
30   X AS INTEGER
40   Y AS INTEGER
50 END TYPE
60 DIM Points(2) AS Point
70 Points(0).X = 10
80 Points(0).Y = 20
90 Points(1).X = 30
100 Points(1).Y = 40
110 PRINT "Points(0): ("; Points(0).X; ", "; Points(0).Y; ")"
120 PRINT "Points(1): ("; Points(1).X; ", "; Points(1).Y; ")"
130 IF Points(0).X = 10 AND Points(1).Y = 40 THEN PRINT "PASS" ELSE PRINT "FAIL"
140 END
