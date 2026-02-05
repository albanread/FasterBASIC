10 REM Test: NOT Operator (Bitwise NOT)
20 REM Tests: NOT with INTEGER types and coercion
30 PRINT "=== NOT Operator Tests ==="
40 PRINT ""
50 REM Test 1: NOT of zero
60 LET A% = 0
70 LET B% = NOT A%
80 PRINT "NOT 0 = "; B%
90 IF B% <> -1 THEN PRINT "ERROR: NOT 0 failed" : END
100 PRINT "PASS: NOT 0 = -1"
110 PRINT ""
120 REM Test 2: NOT of -1 (all bits set)
130 LET C% = -1
140 LET D% = NOT C%
150 PRINT "NOT -1 = "; D%
160 IF D% <> 0 THEN PRINT "ERROR: NOT -1 failed" : END
170 PRINT "PASS: NOT -1 = 0"
180 PRINT ""
190 REM Test 3: NOT of positive number
200 LET E% = 5
210 LET F% = NOT E%
220 PRINT "NOT 5 = "; F%
230 IF F% <> -6 THEN PRINT "ERROR: NOT 5 failed" : END
240 PRINT "PASS: NOT 5 = -6"
250 PRINT ""
260 REM Test 4: NOT of negative number
270 LET G% = -10
280 LET H% = NOT G%
290 PRINT "NOT -10 = "; H%
300 IF H% <> 9 THEN PRINT "ERROR: NOT -10 failed" : END
310 PRINT "PASS: NOT -10 = 9"
320 PRINT ""
330 REM Test 5: Double NOT (should return original)
340 LET I% = 42
350 LET J% = NOT (NOT I%)
360 PRINT "NOT (NOT 42) = "; J%
370 IF J% <> 42 THEN PRINT "ERROR: Double NOT failed" : END
380 PRINT "PASS: NOT (NOT 42) = 42"
390 PRINT ""
400 REM Test 6: NOT with coercion from double literal
410 LET K% = NOT 10
420 PRINT "NOT 10 = "; K%
430 IF K% <> -11 THEN PRINT "ERROR: NOT 10 (literal) failed" : END
440 PRINT "PASS: NOT 10 (literal) = -11"
450 PRINT ""
460 REM Test 7: NOT of 1
470 LET L% = 1
480 LET M% = NOT L%
490 PRINT "NOT 1 = "; M%
500 IF M% <> -2 THEN PRINT "ERROR: NOT 1 failed" : END
510 PRINT "PASS: NOT 1 = -2"
520 PRINT ""
530 REM Test 8: NOT of large number
540 LET N% = 255
550 LET O% = NOT N%
560 PRINT "NOT 255 = "; O%
570 IF O% <> -256 THEN PRINT "ERROR: NOT 255 failed" : END
580 PRINT "PASS: NOT 255 = -256"
590 PRINT ""
600 REM Test 9: NOT in expression
610 LET P% = 10
620 LET Q% = (NOT P%) + 1
630 PRINT "(NOT 10) + 1 = "; Q%
640 IF Q% <> -10 THEN PRINT "ERROR: NOT in expression failed" : END
650 PRINT "PASS: (NOT 10) + 1 = -10"
660 PRINT ""
670 PRINT "=== All NOT Operator Tests PASSED ==="
680 END
