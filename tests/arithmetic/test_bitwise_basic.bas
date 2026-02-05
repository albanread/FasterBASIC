10 REM Test: Bitwise Operators (AND, OR, XOR)
20 REM Tests: AND, OR, XOR with INTEGER types
30 PRINT "=== Bitwise Operators Tests ==="
40 PRINT ""
50 REM Test 1: AND operator
60 LET A% = 12
70 LET B% = 10
80 LET C% = A% AND B%
90 PRINT "12 AND 10 = "; C%
100 IF C% <> 8 THEN PRINT "ERROR: AND failed" : END
110 PRINT "PASS: 12 AND 10 = 8"
120 PRINT ""
130 REM Test 2: OR operator
140 LET D% = 12
150 LET E% = 10
160 LET F% = D% OR E%
170 PRINT "12 OR 10 = "; F%
180 IF F% <> 14 THEN PRINT "ERROR: OR failed" : END
190 PRINT "PASS: 12 OR 10 = 14"
200 PRINT ""
210 REM Test 3: XOR operator
220 LET G% = 12
230 LET H% = 10
240 LET I% = G% XOR H%
250 PRINT "12 XOR 10 = "; I%
260 IF I% <> 6 THEN PRINT "ERROR: XOR failed" : END
270 PRINT "PASS: 12 XOR 10 = 6"
280 PRINT ""
290 REM Test 4: AND with zero
300 LET J% = 255
310 LET K% = 0
320 LET L% = J% AND K%
330 PRINT "255 AND 0 = "; L%
340 IF L% <> 0 THEN PRINT "ERROR: AND with zero failed" : END
350 PRINT "PASS: 255 AND 0 = 0"
360 PRINT ""
370 REM Test 5: OR with zero
380 LET M% = 42
390 LET N% = 0
400 LET O% = M% OR N%
410 PRINT "42 OR 0 = "; O%
420 IF O% <> 42 THEN PRINT "ERROR: OR with zero failed" : END
430 PRINT "PASS: 42 OR 0 = 42"
440 PRINT ""
450 REM Test 6: XOR with zero
460 LET P% = 99
470 LET Q% = 0
480 LET R% = P% XOR Q%
490 PRINT "99 XOR 0 = "; R%
500 IF R% <> 99 THEN PRINT "ERROR: XOR with zero failed" : END
510 PRINT "PASS: 99 XOR 0 = 99"
520 PRINT ""
530 REM Test 7: XOR with self (should be zero)
540 LET S% = 123
550 LET T% = S% XOR S%
560 PRINT "123 XOR 123 = "; T%
570 IF T% <> 0 THEN PRINT "ERROR: XOR with self failed" : END
580 PRINT "PASS: 123 XOR 123 = 0"
590 PRINT ""
600 REM Test 8: AND with -1 (all bits set)
610 LET U% = 42
620 LET V% = -1
630 LET W% = U% AND V%
640 PRINT "42 AND -1 = "; W%
650 IF W% <> 42 THEN PRINT "ERROR: AND with -1 failed" : END
660 PRINT "PASS: 42 AND -1 = 42"
670 PRINT ""
680 REM Test 9: OR with -1 (all bits set)
690 LET X% = 42
700 LET Y% = -1
710 LET Z% = X% OR Y%
720 PRINT "42 OR -1 = "; Z%
730 IF Z% <> -1 THEN PRINT "ERROR: OR with -1 failed" : END
740 PRINT "PASS: 42 OR -1 = -1"
750 PRINT ""
760 REM Test 10: Combined operations
770 LET AA% = 15
780 LET BB% = 7
790 LET CC% = (AA% AND BB%) OR (AA% XOR BB%)
800 PRINT "(15 AND 7) OR (15 XOR 7) = "; CC%
810 IF CC% <> 15 THEN PRINT "ERROR: Combined operations failed" : END
820 PRINT "PASS: Combined operations = 15"
830 PRINT ""
840 REM Test 11: Mask operation (common pattern)
850 LET DATA% = 170
860 LET MASK% = 15
870 LET RESULT% = DATA% AND MASK%
880 PRINT "170 AND 15 (extract lower 4 bits) = "; RESULT%
890 IF RESULT% <> 10 THEN PRINT "ERROR: Mask operation failed" : END
900 PRINT "PASS: Mask operation = 10"
910 PRINT ""
920 REM Test 12: Negative numbers
930 LET DD% = -5
940 LET EE% = 3
950 LET FF% = DD% AND EE%
960 PRINT "-5 AND 3 = "; FF%
970 IF FF% <> 3 THEN PRINT "ERROR: AND with negative failed" : END
980 PRINT "PASS: -5 AND 3 = 3"
990 PRINT ""
1000 PRINT "=== All Bitwise Operators Tests PASSED ==="
1010 END
