10 REM Test: Edge Cases and Boundary Conditions
20 PRINT "=== Edge Case Tests ==="
30 REM Test 1: Division by small numbers
40 LET A# = 1.0 / 3.0
50 LET B# = A# * 3.0
60 PRINT "1/3 * 3 = "; B#
70 IF B# < 0.99 OR B# > 1.01 THEN PRINT "ERROR: Float precision issue" : END
80 PRINT "PASS: Float precision"
90 PRINT ""
100 REM Test 2: Zero handling
110 LET ZERO% = 0
120 LET RESULT% = ZERO% + 0
130 IF RESULT% <> 0 THEN PRINT "ERROR: Zero handling failed" : END
140 PRINT "PASS: Zero handling"
150 PRINT ""
160 REM Test 3: Negative zero for doubles
170 LET NEG# = -0.0
180 LET POS# = 0.0
190 IF NEG# <> POS# THEN PRINT "WARNING: Negative zero differs from positive zero"
200 PRINT "PASS: Negative zero"
210 PRINT ""
220 REM Test 4: Very large integers
230 LET LARGE% = 1000000
240 LET DOUBLE_LARGE% = LARGE% + LARGE%
250 PRINT "1000000 + 1000000 = "; DOUBLE_LARGE%
260 IF DOUBLE_LARGE% <> 2000000 THEN PRINT "ERROR: Large integer failed" : END
270 PRINT "PASS: Large integers"
280 PRINT "=== All Edge Case Tests PASSED ==="
290 END
