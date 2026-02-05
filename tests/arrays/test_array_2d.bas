10 REM Test: Two-Dimensional Arrays
20 PRINT "=== 2D Array Tests ==="
30 REM Test 1: 2D integer array
40 DIM M%(3, 3)
50 FOR I = 1 TO 3
60   FOR J = 1 TO 3
70     LET M%(I, J) = I * 10 + J
80   NEXT J
90 NEXT I
100 PRINT "2D Array (3x3):"
110 FOR I = 1 TO 3
120   FOR J = 1 TO 3
130     PRINT M%(I, J);
140   NEXT J
150   PRINT ""
160 NEXT I
170 IF M%(2, 3) <> 23 THEN PRINT "ERROR: 2D array access failed" : END
180 PRINT "PASS: 2D array"
190 PRINT "=== All 2D Array Tests PASSED ==="
200 END
