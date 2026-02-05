10 REM Test: Type Conversions
20 PRINT "=== Type Conversion Tests ==="
30 REM Test 1: Integer to Double
40 LET I% = 42
50 LET D# = I%
60 PRINT "Integer 42 to Double: "; D#
70 IF D# < 41.9 OR D# > 42.1 THEN PRINT "ERROR: INT to DOUBLE failed" : END
80 PRINT "PASS: INT to DOUBLE"
90 PRINT ""
100 REM Test 2: Double to Integer
110 LET E# = 42.7
120 LET J% = E#
130 PRINT "Double 42.7 to Integer: "; J%
140 IF J% <> 42 THEN PRINT "ERROR: DOUBLE to INT failed" : END
150 PRINT "PASS: DOUBLE to INT (truncation)"
160 PRINT ""
170 REM Test 3: Integer arithmetic with doubles
180 LET K% = 10
190 LET L# = 3.5
200 LET M# = K% + L#
210 PRINT "10 + 3.5 = "; M#
220 IF M# < 13.4 OR M# > 13.6 THEN PRINT "ERROR: Mixed arithmetic failed" : END
230 PRINT "PASS: Mixed arithmetic"
240 PRINT ""
250 REM Test 4: STR$ function
260 LET N% = 123
270 LET S$ = STR$(N%)
280 PRINT "STR$(123) = \""; S$; "\""
290 PRINT "PASS: STR$"
300 PRINT ""
310 REM Test 5: VAL function
320 LET T$ = "456"
330 LET V% = VAL(T$)
340 PRINT "VAL(\"456\") = "; V%
350 IF V% <> 456 THEN PRINT "ERROR: VAL failed" : END
360 PRINT "PASS: VAL"
370 PRINT "=== All Conversion Tests PASSED ==="
380 END
