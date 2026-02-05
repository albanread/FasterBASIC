10 REM Test: Math Intrinsic Functions
20 PRINT "=== Math Intrinsic Tests ==="
30 REM Test 1: ABS
40 LET A% = -10
50 LET B% = ABS(A%)
60 PRINT "ABS(-10) = "; B%
70 IF B% <> 10 THEN PRINT "ERROR: ABS failed" : END
80 PRINT "PASS: ABS"
90 PRINT ""
100 REM Test 2: SGN
110 LET C% = SGN(-5)
120 LET D% = SGN(0)
130 LET E% = SGN(5)
140 PRINT "SGN(-5) = "; C%; ", SGN(0) = "; D%; ", SGN(5) = "; E%
150 IF C% <> -1 OR D% <> 0 OR E% <> 1 THEN PRINT "ERROR: SGN failed" : END
160 PRINT "PASS: SGN"
170 PRINT ""
180 REM Test 3: INT
190 LET F# = 42.7
200 LET G% = INT(F#)
210 PRINT "INT(42.7) = "; G%
220 IF G% <> 42 THEN PRINT "ERROR: INT failed" : END
230 PRINT "PASS: INT"
240 PRINT ""
250 REM Test 4: SQR
260 LET H# = SQR(16.0)
270 PRINT "SQR(16.0) = "; H#
280 IF H# < 3.9 OR H# > 4.1 THEN PRINT "ERROR: SQR failed" : END
290 PRINT "PASS: SQR"
300 PRINT ""
310 REM Test 5: SIN, COS, TAN
320 LET ZERO# = 0.0
330 LET S# = SIN(ZERO#)
340 LET C# = COS(ZERO#)
350 PRINT "SIN(0) = "; S%; ", COS(0) = "; C#
360 IF S# < -0.1 OR S# > 0.1 THEN PRINT "ERROR: SIN failed" : END
370 IF C# < 0.9 OR C# > 1.1 THEN PRINT "ERROR: COS failed" : END
380 PRINT "PASS: Trigonometric functions"
390 PRINT "=== All Math Intrinsic Tests PASSED ==="
400 END
