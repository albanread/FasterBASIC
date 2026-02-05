10 REM Test: Mixed Type Arithmetic
20 REM Tests: Operations mixing INT and DOUBLE types
30 PRINT "=== Mixed Type Arithmetic Tests ==="
40 PRINT ""
50 REM Test 1: INT + DOUBLE
60 LET A% = 10
70 LET B# = 3.5
80 LET C# = A% + B#
90 PRINT "10 + 3.5 = "; C#
100 IF C# < 13.4 OR C# > 13.6 THEN PRINT "ERROR: INT + DOUBLE failed" : END
110 PRINT "PASS: INT + DOUBLE = 13.5"
120 PRINT ""
130 REM Test 2: DOUBLE + INT
140 LET D# = 5.5
150 LET E% = 4
160 LET F# = D# + E%
170 PRINT "5.5 + 4 = "; F#
180 IF F# < 9.4 OR F# > 9.6 THEN PRINT "ERROR: DOUBLE + INT failed" : END
190 PRINT "PASS: DOUBLE + INT = 9.5"
200 PRINT ""
210 REM Test 3: INT * DOUBLE
220 LET G% = 3
230 LET H# = 2.5
240 LET I# = G% * H#
250 PRINT "3 * 2.5 = "; I#
260 IF I# < 7.4 OR I# > 7.6 THEN PRINT "ERROR: INT * DOUBLE failed" : END
270 PRINT "PASS: INT * DOUBLE = 7.5"
280 PRINT ""
290 REM Test 4: INT / DOUBLE
300 LET J% = 15
310 LET K# = 4.0
320 LET L# = J% / K#
330 PRINT "15 / 4.0 = "; L#
340 IF L# < 3.7 OR L# > 3.8 THEN PRINT "ERROR: INT / DOUBLE failed" : END
350 PRINT "PASS: INT / DOUBLE = 3.75"
360 PRINT ""
370 REM Test 5: DOUBLE - INT
380 LET M# = 10.5
390 LET N% = 3
400 LET O# = M# - N%
410 PRINT "10.5 - 3 = "; O#
420 IF O# < 7.4 OR O# > 7.6 THEN PRINT "ERROR: DOUBLE - INT failed" : END
430 PRINT "PASS: DOUBLE - INT = 7.5"
440 PRINT ""
450 REM Test 6: INT - DOUBLE
460 LET P% = 20
470 LET Q# = 7.5
480 LET R# = P% - Q#
490 PRINT "20 - 7.5 = "; R#
500 IF R# < 12.4 OR R# > 12.6 THEN PRINT "ERROR: INT - DOUBLE failed" : END
510 PRINT "PASS: INT - DOUBLE = 12.5"
520 PRINT ""
530 REM Test 7: Assigning DOUBLE to INT (truncation)
540 LET S# = 42.8
550 LET T% = S#
560 PRINT "INT% = 42.8 => "; T%
570 IF T% <> 42 THEN PRINT "ERROR: DOUBLE to INT truncation failed" : END
580 PRINT "PASS: DOUBLE to INT truncates to 42"
590 PRINT ""
600 REM Test 8: Assigning INT to DOUBLE (promotion)
610 LET U% = 100
620 LET V# = U%
630 PRINT "DOUBLE# = 100% => "; V#
640 IF V# < 99.9 OR V# > 100.1 THEN PRINT "ERROR: INT to DOUBLE promotion failed" : END
650 PRINT "PASS: INT to DOUBLE promotes to 100.0"
660 PRINT ""
670 REM Test 9: Complex expression
680 LET W% = 5
690 LET X# = 2.5
700 LET Y% = 3
710 LET Z# = (W% + X#) * Y%
720 PRINT "(5 + 2.5) * 3 = "; Z#
730 IF Z# < 22.4 OR Z# > 22.6 THEN PRINT "ERROR: Complex mixed expression failed" : END
740 PRINT "PASS: Complex expression = 22.5"
750 PRINT ""
760 REM Test 10: Division with type preservation
770 LET AA% = 7
780 LET BB% = 2
790 LET CC# = AA% / BB%
800 PRINT "7% / 2% in DOUBLE# = "; CC#
810 IF CC# < 3.4 OR CC# > 3.6 THEN PRINT "ERROR: INT/INT to DOUBLE failed" : END
820 PRINT "PASS: INT/INT to DOUBLE = 3.5"
830 PRINT ""
840 REM Test 11: Negative numbers
850 LET DD% = -5
860 LET EE# = 3.5
870 LET FF# = DD% + EE#
880 PRINT "-5 + 3.5 = "; FF#
890 IF FF# < -1.6 OR FF# > -1.4 THEN PRINT "ERROR: Negative mixed arithmetic failed" : END
900 PRINT "PASS: -5 + 3.5 = -1.5"
910 PRINT ""
920 REM Test 12: Zero handling
930 LET GG% = 0
940 LET HH# = 5.5
950 LET II# = GG% + HH#
960 PRINT "0 + 5.5 = "; II#
970 IF II# < 5.4 OR II# > 5.6 THEN PRINT "ERROR: Zero in mixed arithmetic failed" : END
980 PRINT "PASS: 0 + 5.5 = 5.5"
990 PRINT ""
1000 REM Test 13: Literal coercion
1010 LET JJ% = 10 + 0.5
1020 PRINT "INT% = 10 + 0.5 => "; JJ%
1030 IF JJ% <> 10 THEN PRINT "ERROR: Literal mixed to INT failed" : END
1040 PRINT "PASS: 10 + 0.5 to INT% = 10"
1050 PRINT ""
1060 REM Test 14: Comparison mixed types
1070 LET KK% = 5
1080 LET LL# = 5.0
1090 IF KK% = LL# THEN PRINT "PASS: 5% = 5.0# comparison" ELSE PRINT "ERROR: Mixed type comparison" : END
1100 PRINT ""
1110 REM Test 15: Mixed in conditional
1120 LET MM% = 10
1130 LET NN# = 9.5
1140 IF MM% > NN# THEN PRINT "PASS: 10% > 9.5# comparison" ELSE PRINT "ERROR: Mixed comparison" : END
1150 PRINT ""
1160 PRINT "=== All Mixed Type Arithmetic Tests PASSED ==="
1170 END
