10 REM Test: Comparison Operators
20 REM Tests: =, <>, <, >, <=, >= with INTEGER and DOUBLE types
30 PRINT "=== Comparison Operators Tests ==="
40 PRINT ""
50 REM Integer equality
60 LET A% = 10
70 LET B% = 10
80 LET C% = 20
90 IF A% = B% THEN PRINT "PASS: 10 = 10" ELSE PRINT "ERROR: 10 = 10 failed" : END
100 IF A% = C% THEN PRINT "ERROR: 10 = 20 should be false" : END ELSE PRINT "PASS: 10 <> 20"
110 PRINT ""
120 REM Integer not equal
130 IF A% <> C% THEN PRINT "PASS: 10 <> 20" ELSE PRINT "ERROR: 10 <> 20 failed" : END
140 IF A% <> B% THEN PRINT "ERROR: 10 <> 10 should be false" : END ELSE PRINT "PASS: NOT (10 <> 10)"
150 PRINT ""
160 REM Integer less than
170 LET D% = 5
180 LET E% = 10
190 LET F% = 15
200 IF D% < E% THEN PRINT "PASS: 5 < 10" ELSE PRINT "ERROR: 5 < 10 failed" : END
210 IF E% < D% THEN PRINT "ERROR: 10 < 5 should be false" : END ELSE PRINT "PASS: NOT (10 < 5)"
220 IF E% < E% THEN PRINT "ERROR: 10 < 10 should be false" : END ELSE PRINT "PASS: NOT (10 < 10)"
230 PRINT ""
240 REM Integer greater than
250 IF F% > E% THEN PRINT "PASS: 15 > 10" ELSE PRINT "ERROR: 15 > 10 failed" : END
260 IF E% > F% THEN PRINT "ERROR: 10 > 15 should be false" : END ELSE PRINT "PASS: NOT (10 > 15)"
270 IF E% > E% THEN PRINT "ERROR: 10 > 10 should be false" : END ELSE PRINT "PASS: NOT (10 > 10)"
280 PRINT ""
290 REM Integer less than or equal
300 IF D% <= E% THEN PRINT "PASS: 5 <= 10" ELSE PRINT "ERROR: 5 <= 10 failed" : END
310 IF E% <= E% THEN PRINT "PASS: 10 <= 10" ELSE PRINT "ERROR: 10 <= 10 failed" : END
320 IF F% <= E% THEN PRINT "ERROR: 15 <= 10 should be false" : END ELSE PRINT "PASS: NOT (15 <= 10)"
330 PRINT ""
340 REM Integer greater than or equal
350 IF F% >= E% THEN PRINT "PASS: 15 >= 10" ELSE PRINT "ERROR: 15 >= 10 failed" : END
360 IF E% >= E% THEN PRINT "PASS: 10 >= 10" ELSE PRINT "ERROR: 10 >= 10 failed" : END
370 IF D% >= E% THEN PRINT "ERROR: 5 >= 10 should be false" : END ELSE PRINT "PASS: NOT (5 >= 10)"
380 PRINT ""
390 REM Double equality (with tolerance)
400 LET X# = 10.5
410 LET Y# = 10.5
420 LET Z# = 20.7
430 IF X# = Y# THEN PRINT "PASS: 10.5 = 10.5" ELSE PRINT "ERROR: 10.5 = 10.5 failed" : END
440 IF X# = Z# THEN PRINT "ERROR: 10.5 = 20.7 should be false" : END ELSE PRINT "PASS: 10.5 <> 20.7"
450 PRINT ""
460 REM Double not equal
470 IF X# <> Z# THEN PRINT "PASS: 10.5 <> 20.7" ELSE PRINT "ERROR: 10.5 <> 20.7 failed" : END
480 PRINT ""
490 REM Double less than
500 LET P# = 5.5
510 LET Q# = 10.5
520 LET R# = 15.5
530 IF P# < Q# THEN PRINT "PASS: 5.5 < 10.5" ELSE PRINT "ERROR: 5.5 < 10.5 failed" : END
540 IF Q# < P# THEN PRINT "ERROR: 10.5 < 5.5 should be false" : END ELSE PRINT "PASS: NOT (10.5 < 5.5)"
550 PRINT ""
560 REM Double greater than
570 IF R# > Q# THEN PRINT "PASS: 15.5 > 10.5" ELSE PRINT "ERROR: 15.5 > 10.5 failed" : END
580 IF Q# > R# THEN PRINT "ERROR: 10.5 > 15.5 should be false" : END ELSE PRINT "PASS: NOT (10.5 > 15.5)"
590 PRINT ""
600 REM Double less than or equal
610 IF P# <= Q# THEN PRINT "PASS: 5.5 <= 10.5" ELSE PRINT "ERROR: 5.5 <= 10.5 failed" : END
620 IF Q# <= Q# THEN PRINT "PASS: 10.5 <= 10.5" ELSE PRINT "ERROR: 10.5 <= 10.5 failed" : END
630 IF R# <= Q# THEN PRINT "ERROR: 15.5 <= 10.5 should be false" : END ELSE PRINT "PASS: NOT (15.5 <= 10.5)"
640 PRINT ""
650 REM Double greater than or equal
660 IF R# >= Q# THEN PRINT "PASS: 15.5 >= 10.5" ELSE PRINT "ERROR: 15.5 >= 10.5 failed" : END
670 IF Q# >= Q# THEN PRINT "PASS: 10.5 >= 10.5" ELSE PRINT "ERROR: 10.5 >= 10.5 failed" : END
680 IF P# >= Q# THEN PRINT "ERROR: 5.5 >= 10.5 should be false" : END ELSE PRINT "PASS: NOT (5.5 >= 10.5)"
690 PRINT ""
700 REM Negative number comparisons
710 LET M% = -10
720 LET N% = 5
730 IF M% < N% THEN PRINT "PASS: -10 < 5" ELSE PRINT "ERROR: -10 < 5 failed" : END
740 IF N% > M% THEN PRINT "PASS: 5 > -10" ELSE PRINT "ERROR: 5 > -10 failed" : END
750 PRINT ""
760 REM Zero comparisons
770 LET ZERO% = 0
780 IF ZERO% = 0 THEN PRINT "PASS: 0 = 0" ELSE PRINT "ERROR: 0 = 0 failed" : END
790 IF ZERO% < 1 THEN PRINT "PASS: 0 < 1" ELSE PRINT "ERROR: 0 < 1 failed" : END
800 IF ZERO% > -1 THEN PRINT "PASS: 0 > -1" ELSE PRINT "ERROR: 0 > -1 failed" : END
810 PRINT ""
820 PRINT "=== All Comparison Tests PASSED ==="
830 END
