10 REM Test: UDT passed to FUNCTION and SUB with member access
20 TYPE Point
30   X AS INTEGER
40   Y AS INTEGER
50 END TYPE
60 DIM P AS Point
70 P.X = 3
80 P.Y = 4
90 REM Test reading UDT fields in a FUNCTION
100 DIM D AS DOUBLE
110 D = Distance(P)
120 PRINT "Distance squared = "; D
130 IF D > 24.9 AND D < 25.1 THEN PRINT "PASS: Distance" ELSE PRINT "FAIL: Distance"
140 REM Test modifying UDT fields through a SUB (pass-by-reference)
150 CALL SetPoint(P, 10, 20)
160 PRINT "After SetPoint: P.X = "; P.X; ", P.Y = "; P.Y
170 IF P.X = 10 AND P.Y = 20 THEN PRINT "PASS: SetPoint" ELSE PRINT "FAIL: SetPoint"
180 REM Test reading modified values in a FUNCTION
190 D = Distance(P)
200 PRINT "New distance squared = "; D
210 IF D > 499.9 AND D < 500.1 THEN PRINT "PASS: New distance" ELSE PRINT "FAIL: New distance"
220 REM Test SUB that swaps two fields
230 CALL SwapXY(P)
240 PRINT "After SwapXY: P.X = "; P.X; ", P.Y = "; P.Y
250 IF P.X = 20 AND P.Y = 10 THEN PRINT "PASS: SwapXY" ELSE PRINT "FAIL: SwapXY"
260 END
270 FUNCTION Distance(Pt AS Point) AS DOUBLE
280   Distance = Pt.X * Pt.X + Pt.Y * Pt.Y
290 END FUNCTION
300 SUB SetPoint(Pt AS Point, NewX AS INTEGER, NewY AS INTEGER)
310   Pt.X = NewX
320   Pt.Y = NewY
330 END SUB
340 SUB SwapXY(Pt AS Point)
350   LOCAL Tmp AS INTEGER
360   Tmp = Pt.X
370   Pt.X = Pt.Y
380   Pt.Y = Tmp
390 END SUB
