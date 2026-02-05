10 REM Test: Basic WHILE Loop
20 PRINT "=== WHILE Loop Tests ==="
30 REM Test 1: Basic WHILE counting
40 LET X% = 1
50 LET SUM% = 0
60 WHILE X% <= 5
70   PRINT X%;
80   LET SUM% = SUM% + X%
90   LET X% = X% + 1
100 WEND
110 PRINT ""
120 IF SUM% <> 15 THEN PRINT "ERROR: WHILE sum failed" : END
130 PRINT "PASS: Sum = "; SUM%
140 PRINT ""
150 REM Test 2: WHILE with zero iterations
160 LET Y% = 10
170 LET COUNT% = 0
180 WHILE Y% < 5
190   LET COUNT% = COUNT% + 1
200 WEND
210 IF COUNT% <> 0 THEN PRINT "ERROR: Zero iteration failed" : END
220 PRINT "PASS: Zero iterations"
230 PRINT ""
240 REM Test 3: Nested WHILE
250 LET I% = 1
260 LET TOTAL% = 0
270 WHILE I% <= 3
280   LET J% = 1
290   WHILE J% <= 2
300     LET TOTAL% = TOTAL% + 1
310     LET J% = J% + 1
320   WEND
330   LET I% = I% + 1
340 WEND
350 IF TOTAL% <> 6 THEN PRINT "ERROR: Nested WHILE failed" : END
360 PRINT "PASS: Nested WHILE = "; TOTAL%
370 PRINT "=== All WHILE Tests PASSED ==="
380 END
