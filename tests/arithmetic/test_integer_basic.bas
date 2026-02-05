10 REM Test: Basic Integer Arithmetic Operations
20 REM Tests: +, -, *, /, MOD with INTEGER types
30 PRINT "=== Integer Arithmetic Tests ==="
40 PRINT ""
50 REM Addition
60 LET A% = 10
70 LET B% = 20
80 LET C% = A% + B%
90 PRINT "10 + 20 = "; C%
100 IF C% <> 30 THEN PRINT "ERROR: Addition failed" : END
110 PRINT "PASS: Addition"
120 PRINT ""
130 REM Subtraction
140 LET D% = 50
150 LET E% = 25
160 LET F% = D% - E%
170 PRINT "50 - 25 = "; F%
180 IF F% <> 25 THEN PRINT "ERROR: Subtraction failed" : END
190 PRINT "PASS: Subtraction"
200 PRINT ""
210 REM Multiplication
220 LET G% = 7
230 LET H% = 8
240 LET I% = G% * H%
250 PRINT "7 * 8 = "; I%
260 IF I% <> 56 THEN PRINT "ERROR: Multiplication failed" : END
270 PRINT "PASS: Multiplication"
280 PRINT ""
290 REM Division (integer division)
300 LET J% = 100
310 LET K% = 4
320 LET L% = J% / K%
330 PRINT "100 / 4 = "; L%
340 IF L% <> 25 THEN PRINT "ERROR: Division failed" : END
350 PRINT "PASS: Division"
360 PRINT ""
370 REM Integer division with truncation
380 LET M% = 17
390 LET N% = 5
400 LET O% = M% / N%
410 PRINT "17 / 5 = "; O%; " (truncated)"
420 IF O% <> 3 THEN PRINT "ERROR: Integer division truncation failed" : END
430 PRINT "PASS: Integer Division Truncation"
440 PRINT ""
450 REM Modulo
460 LET P% = 17
470 LET Q% = 5
480 LET R% = P% MOD Q%
490 PRINT "17 MOD 5 = "; R%
500 IF R% <> 2 THEN PRINT "ERROR: Modulo failed" : END
510 PRINT "PASS: Modulo"
520 PRINT ""
530 REM Negative numbers
540 LET S% = -10
550 LET T% = 5
560 LET U% = S% + T%
570 PRINT "-10 + 5 = "; U%
580 IF U% <> -5 THEN PRINT "ERROR: Negative addition failed" : END
590 PRINT "PASS: Negative Numbers"
600 PRINT ""
610 REM Mixed operations
620 LET V% = 2 + 3 * 4
630 PRINT "2 + 3 * 4 = "; V%; " (precedence test)"
640 IF V% <> 14 THEN PRINT "ERROR: Operator precedence failed" : END
650 PRINT "PASS: Operator Precedence"
660 PRINT ""
670 PRINT "=== All Integer Arithmetic Tests PASSED ==="
680 END
