10 REM Test: Logical Operators
20 REM Tests: AND, OR, XOR, NOT with INTEGER types
30 PRINT "=== Logical Operators Tests ==="
40 PRINT ""
50 REM AND operator
60 LET A% = 1
70 LET B% = 1
80 LET C% = 0
90 IF A% AND B% THEN PRINT "PASS: 1 AND 1 = TRUE" ELSE PRINT "ERROR: 1 AND 1 failed" : END
100 IF A% AND C% THEN PRINT "ERROR: 1 AND 0 should be FALSE" : END ELSE PRINT "PASS: 1 AND 0 = FALSE"
110 IF C% AND C% THEN PRINT "ERROR: 0 AND 0 should be FALSE" : END ELSE PRINT "PASS: 0 AND 0 = FALSE"
120 PRINT ""
130 REM OR operator
140 IF A% OR B% THEN PRINT "PASS: 1 OR 1 = TRUE" ELSE PRINT "ERROR: 1 OR 1 failed" : END
150 IF A% OR C% THEN PRINT "PASS: 1 OR 0 = TRUE" ELSE PRINT "ERROR: 1 OR 0 failed" : END
160 IF C% OR C% THEN PRINT "ERROR: 0 OR 0 should be FALSE" : END ELSE PRINT "PASS: 0 OR 0 = FALSE"
170 PRINT ""
180 REM XOR operator
190 IF A% XOR C% THEN PRINT "PASS: 1 XOR 0 = TRUE" ELSE PRINT "ERROR: 1 XOR 0 failed" : END
200 IF C% XOR A% THEN PRINT "PASS: 0 XOR 1 = TRUE" ELSE PRINT "ERROR: 0 XOR 1 failed" : END
210 IF A% XOR B% THEN PRINT "ERROR: 1 XOR 1 should be FALSE" : END ELSE PRINT "PASS: 1 XOR 1 = FALSE"
220 IF C% XOR C% THEN PRINT "ERROR: 0 XOR 0 should be FALSE" : END ELSE PRINT "PASS: 0 XOR 0 = FALSE"
230 PRINT ""
240 REM NOT operator
250 LET D% = 5
260 LET E% = 0
270 IF NOT E% THEN PRINT "PASS: NOT 0 = TRUE" ELSE PRINT "ERROR: NOT 0 failed" : END
280 IF NOT D% THEN PRINT "ERROR: NOT 5 should be FALSE" : END ELSE PRINT "PASS: NOT 5 = FALSE"
290 PRINT ""
300 REM Compound logical expressions
310 LET X% = 1
320 LET Y% = 1
330 LET Z% = 0
340 IF (X% AND Y%) OR Z% THEN PRINT "PASS: (1 AND 1) OR 0 = TRUE" ELSE PRINT "ERROR: compound expression failed" : END
350 IF (X% OR Z%) AND Y% THEN PRINT "PASS: (1 OR 0) AND 1 = TRUE" ELSE PRINT "ERROR: compound expression failed" : END
360 IF X% AND (Y% OR Z%) THEN PRINT "PASS: 1 AND (1 OR 0) = TRUE" ELSE PRINT "ERROR: compound expression failed" : END
370 PRINT ""
380 REM Logical with comparisons
390 LET M% = 10
400 LET N% = 20
410 IF (M% < N%) AND (M% > 0) THEN PRINT "PASS: (10 < 20) AND (10 > 0)" ELSE PRINT "ERROR: comparison combo failed" : END
420 IF (M% > N%) OR (M% < 15) THEN PRINT "PASS: (10 > 20) OR (10 < 15)" ELSE PRINT "ERROR: comparison combo failed" : END
430 IF NOT (M% > N%) THEN PRINT "PASS: NOT (10 > 20)" ELSE PRINT "ERROR: NOT comparison failed" : END
440 PRINT ""
450 REM Bitwise AND (integer values)
460 LET P% = 12
470 LET Q% = 10
480 LET R% = P% AND Q%
490 PRINT "12 AND 10 = "; R%; " (bitwise)"
500 IF R% = 8 THEN PRINT "PASS: Bitwise AND" ELSE PRINT "WARNING: May be logical AND"
510 PRINT ""
520 REM Bitwise OR (integer values)
530 LET S% = 12
540 LET T% = 10
550 LET U% = S% OR T%
560 PRINT "12 OR 10 = "; U%; " (bitwise)"
570 IF U% = 14 THEN PRINT "PASS: Bitwise OR" ELSE PRINT "WARNING: May be logical OR"
580 PRINT ""
590 REM Bitwise XOR (integer values)
600 LET V% = 12
610 LET W% = 10
620 LET XX% = V% XOR W%
630 PRINT "12 XOR 10 = "; XX%; " (bitwise)"
640 IF XX% = 6 THEN PRINT "PASS: Bitwise XOR" ELSE PRINT "WARNING: May be logical XOR"
650 PRINT ""
660 REM Truth table verification
670 PRINT "Truth Table Verification:"
680 FOR I% = 0 TO 1
690   FOR J% = 0 TO 1
700     LET AND_RESULT% = I% AND J%
710     LET OR_RESULT% = I% OR J%
720     LET XOR_RESULT% = I% XOR J%
730     PRINT I%; " AND "; J%; " = "; AND_RESULT%
740     PRINT I%; " OR "; J%; " = "; OR_RESULT%
750     PRINT I%; " XOR "; J%; " = "; XOR_RESULT%
760     PRINT ""
770   NEXT J%
780 NEXT I%
790 PRINT "=== All Logical Operator Tests PASSED ==="
800 END
