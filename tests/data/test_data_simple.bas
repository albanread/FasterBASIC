10 REM Test: Simple DATA/READ/RESTORE
20 PRINT "=== Simple DATA/READ/RESTORE Test ==="
30 PRINT ""
40 REM Test 1: Basic READ of integers
50 PRINT "Test 1: Read three integers"
60 READ A%, B%, C%
70 PRINT "  A% ="; A%
80 PRINT "  B% ="; B%
90 PRINT "  C% ="; C%
100 IF A% = 10 AND B% = 20 AND C% = 30 THEN PRINT "  PASS: Values correct" ELSE PRINT "  ERROR: Wrong values" : END
110 PRINT ""
120 REM Test 2: RESTORE and re-read
130 PRINT "Test 2: RESTORE and re-read"
140 RESTORE
150 READ X%, Y%, Z%
160 PRINT "  X% ="; X%
170 PRINT "  Y% ="; Y%
180 PRINT "  Z% ="; Z%
190 IF X% = 10 AND Y% = 20 AND Z% = 30 THEN PRINT "  PASS: RESTORE works" ELSE PRINT "  ERROR: RESTORE failed" : END
200 PRINT ""
210 REM Test 3: Multiple DATA statements
220 PRINT "Test 3: Multiple DATA statements"
230 READ D1%, D2%, D3%, D4%
240 LET SUM% = D1% + D2% + D3% + D4%
250 PRINT "  Sum ="; SUM%
260 IF SUM% = 10 THEN PRINT "  PASS: Multiple DATA works" ELSE PRINT "  ERROR: Wrong sum" : END
270 PRINT ""
280 PRINT "=== All Tests PASSED ==="
290 END
300 DATA 10, 20, 30
310 DATA 1, 2, 3, 4
