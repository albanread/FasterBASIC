10 REM Test: MOD Operator (Modulo/Remainder)
20 REM Tests: MOD with INTEGER types, positive, negative, edge cases
30 PRINT "=== MOD Operator Tests ==="
40 PRINT ""
50 REM Test 1: Basic modulo
60 LET A% = 17
70 LET B% = 5
80 LET C% = A% MOD B%
90 PRINT "17 MOD 5 = "; C%
100 IF C% <> 2 THEN PRINT "ERROR: Basic MOD failed" : END
110 PRINT "PASS: 17 MOD 5 = 2"
120 PRINT ""
130 REM Test 2: Even division (no remainder)
140 LET D% = 20
150 LET E% = 4
160 LET F% = D% MOD E%
170 PRINT "20 MOD 4 = "; F%
180 IF F% <> 0 THEN PRINT "ERROR: MOD with even division failed" : END
190 PRINT "PASS: 20 MOD 4 = 0"
200 PRINT ""
210 REM Test 3: MOD with 1 (always zero)
220 LET G% = 100
230 LET H% = 1
240 LET I% = G% MOD H%
250 PRINT "100 MOD 1 = "; I%
260 IF I% <> 0 THEN PRINT "ERROR: MOD 1 failed" : END
270 PRINT "PASS: 100 MOD 1 = 0"
280 PRINT ""
290 REM Test 4: Dividend less than divisor
300 LET J% = 3
310 LET K% = 7
320 LET L% = J% MOD K%
330 PRINT "3 MOD 7 = "; L%
340 IF L% <> 3 THEN PRINT "ERROR: Small dividend MOD failed" : END
350 PRINT "PASS: 3 MOD 7 = 3"
360 PRINT ""
370 REM Test 5: MOD 10 (extract last digit)
380 LET M% = 12345
390 LET N% = 10
400 LET O% = M% MOD N%
410 PRINT "12345 MOD 10 = "; O%
420 IF O% <> 5 THEN PRINT "ERROR: MOD 10 failed" : END
430 PRINT "PASS: 12345 MOD 10 = 5"
440 PRINT ""
450 REM Test 6: Negative dividend
460 LET P% = -17
470 LET Q% = 5
480 LET R% = P% MOD Q%
490 PRINT "-17 MOD 5 = "; R%
500 REM Result depends on implementation: could be -2 or 3
510 REM Most BASIC implementations give -2 (same sign as dividend)
520 IF R% <> -2 THEN PRINT "ERROR: Negative MOD failed (got "; R%; ", expected -2)" : END
530 PRINT "PASS: -17 MOD 5 = "; R%
540 PRINT ""
550 REM Test 7: Negative divisor
560 LET S% = 17
570 LET T% = -5
580 LET U% = S% MOD T%
590 PRINT "17 MOD -5 = "; U%
600 REM Result: 2 (same sign as dividend in most BASICs)
610 IF U% <> 2 THEN PRINT "ERROR: MOD negative divisor failed (got "; U%; ", expected 2)" : END
620 PRINT "PASS: 17 MOD -5 = "; U%
630 PRINT ""
640 REM Test 8: Both negative
650 LET V% = -17
660 LET W% = -5
670 LET X% = V% MOD W%
680 PRINT "-17 MOD -5 = "; X%
690 IF X% <> -2 THEN PRINT "ERROR: Both negative MOD failed (got "; X%; ", expected -2)" : END
700 PRINT "PASS: -17 MOD -5 = "; X%
710 PRINT ""
720 REM Test 9: MOD with 2 (test even/odd)
730 LET Y% = 42
740 LET Z% = Y% MOD 2
750 PRINT "42 MOD 2 = "; Z%; " (even)"
760 IF Z% <> 0 THEN PRINT "ERROR: Even number MOD 2 failed" : END
770 PRINT "PASS: 42 is even"
780 PRINT ""
790 REM Test 10: Odd number MOD 2
800 LET AA% = 43
810 LET BB% = AA% MOD 2
820 PRINT "43 MOD 2 = "; BB%; " (odd)"
830 IF BB% <> 1 THEN PRINT "ERROR: Odd number MOD 2 failed" : END
840 PRINT "PASS: 43 is odd"
850 PRINT ""
860 REM Test 11: Large numbers
870 LET CC% = 1000000
880 LET DD% = 7
890 LET EE% = CC% MOD DD%
900 PRINT "1000000 MOD 7 = "; EE%
910 IF EE% <> 1 THEN PRINT "ERROR: Large number MOD failed" : END
920 PRINT "PASS: 1000000 MOD 7 = 1"
930 PRINT ""
940 REM Test 12: MOD in expression
950 LET FF% = 25
960 LET GG% = (FF% MOD 10) + 100
970 PRINT "(25 MOD 10) + 100 = "; GG%
980 IF GG% <> 105 THEN PRINT "ERROR: MOD in expression failed" : END
990 PRINT "PASS: (25 MOD 10) + 100 = 105"
1000 PRINT ""
1010 PRINT "=== All MOD Operator Tests PASSED ==="
1020 END
