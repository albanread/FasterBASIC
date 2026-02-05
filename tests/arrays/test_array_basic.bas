10 REM Test: Basic Array Operations
20 PRINT "=== Array Tests ==="
30 REM Test 1: Integer array
40 DIM A%(10)
50 FOR I = 1 TO 10
60   LET A%(I) = I * 2
70 NEXT I
80 LET SUM% = 0
90 FOR I = 1 TO 10
100   LET SUM% = SUM% + A%(I)
110 NEXT I
120 PRINT "Sum of array elements: "; SUM%
130 IF SUM% <> 110 THEN PRINT "ERROR: Array sum failed" : END
140 PRINT "PASS: Integer array"
150 PRINT ""
160 REM Test 2: Double array
170 DIM B#(5)
180 FOR I = 1 TO 5
190   LET B#(I) = I * 1.5
200 NEXT I
210 PRINT "Double array values: ";
220 FOR I = 1 TO 5
230   PRINT B#(I);
240 NEXT I
250 PRINT ""
260 PRINT "PASS: Double array"
270 PRINT ""
280 REM Test 3: String array
290 DIM C$(3)
300 LET C$(1) = "One"
310 LET C$(2) = "Two"
320 LET C$(3) = "Three"
330 PRINT "String array: ";
340 FOR I = 1 TO 3
350   PRINT C$(I); " ";
360 NEXT I
370 PRINT ""
380 PRINT "PASS: String array"
390 PRINT "=== All Array Tests PASSED ==="
400 END
