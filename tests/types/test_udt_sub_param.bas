10 REM Test: Passing UDT to SUB as parameter
20 TYPE Point
30   X AS INTEGER
40   Y AS INTEGER
50 END TYPE
60 DIM P AS Point
70 P.X = 10
80 P.Y = 20
90 PRINT "Before SUB call:"
100 PRINT "P.X = "; P.X; ", P.Y = "; P.Y
110 CALL PrintPoint(P)
120 CALL DoublePoint(P)
130 PRINT "After DoublePoint:"
140 PRINT "P.X = "; P.X; ", P.Y = "; P.Y
150 IF P.X = 20 AND P.Y = 40 THEN PRINT "PASS" ELSE PRINT "FAIL"
160 END
170 SUB PrintPoint(Pt AS Point)
180   PRINT "In SUB: Pt.X = "; Pt.X; ", Pt.Y = "; Pt.Y
190 END SUB
200 SUB DoublePoint(Pt AS Point)
210   Pt.X = Pt.X * 2
220   Pt.Y = Pt.Y * 2
230 END SUB
