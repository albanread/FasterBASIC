10 REM Test: String Comparison Operators
20 REM Tests: =, <>, <, >, <=, >= with STRING types
30 PRINT "=== String Comparison Tests ==="
40 PRINT ""
50 REM Test 1: String equality
60 LET A$ = "HELLO"
70 LET B$ = "HELLO"
80 IF A$ = B$ THEN PRINT "PASS: Equal strings match" ELSE PRINT "ERROR: Equal strings" : END
90 PRINT ""
100 REM Test 2: String inequality
110 LET C$ = "HELLO"
120 LET D$ = "WORLD"
130 IF C$ <> D$ THEN PRINT "PASS: Different strings don't match" ELSE PRINT "ERROR: String inequality" : END
140 PRINT ""
150 REM Test 3: Lexicographic less than
160 LET E$ = "APPLE"
170 LET F$ = "BANANA"
180 IF E$ < F$ THEN PRINT "PASS: APPLE < BANANA" ELSE PRINT "ERROR: String less than" : END
190 PRINT ""
200 REM Test 4: Lexicographic greater than
210 LET G$ = "ZEBRA"
220 LET H$ = "APPLE"
230 IF G$ > H$ THEN PRINT "PASS: ZEBRA > APPLE" ELSE PRINT "ERROR: String greater than" : END
240 PRINT ""
250 REM Test 5: Less than or equal (equal case)
260 LET I$ = "TEST"
270 LET J$ = "TEST"
280 IF I$ <= J$ THEN PRINT "PASS: TEST <= TEST (equal)" ELSE PRINT "ERROR: String LE equal" : END
290 PRINT ""
300 REM Test 6: Less than or equal (less case)
310 LET K$ = "AAA"
320 LET L$ = "BBB"
330 IF K$ <= L$ THEN PRINT "PASS: AAA <= BBB (less)" ELSE PRINT "ERROR: String LE less" : END
340 PRINT ""
350 REM Test 7: Greater than or equal (equal case)
360 LET M$ = "SAME"
370 LET N$ = "SAME"
380 IF M$ >= N$ THEN PRINT "PASS: SAME >= SAME (equal)" ELSE PRINT "ERROR: String GE equal" : END
390 PRINT ""
400 REM Test 8: Greater than or equal (greater case)
410 LET O$ = "ZZZ"
420 LET P$ = "AAA"
430 IF O$ >= P$ THEN PRINT "PASS: ZZZ >= AAA (greater)" ELSE PRINT "ERROR: String GE greater" : END
440 PRINT ""
450 REM Test 9: Empty string equality
460 LET Q$ = ""
470 LET R$ = ""
480 IF Q$ = R$ THEN PRINT "PASS: Empty strings equal" ELSE PRINT "ERROR: Empty string equality" : END
490 PRINT ""
500 REM Test 10: Empty string less than non-empty
510 LET S$ = ""
520 LET T$ = "A"
530 IF S$ < T$ THEN PRINT "PASS: Empty < non-empty" ELSE PRINT "ERROR: Empty string comparison" : END
540 PRINT ""
550 REM Test 11: Case sensitivity
560 LET U$ = "abc"
570 LET V$ = "ABC"
580 IF U$ <> V$ THEN PRINT "PASS: Case sensitive comparison" ELSE PRINT "ERROR: Case sensitivity" : END
590 PRINT ""
600 REM Test 12: Prefix comparison
610 LET W$ = "TEST"
620 LET X$ = "TESTING"
630 IF W$ < X$ THEN PRINT "PASS: Prefix less than longer string" ELSE PRINT "ERROR: Prefix comparison" : END
640 PRINT ""
650 REM Test 13: String comparison in conditional
660 LET Y$ = "MIDDLE"
670 IF Y$ > "APPLE" AND Y$ < "ZEBRA" THEN PRINT "PASS: Range comparison" ELSE PRINT "ERROR: Range comparison" : END
680 PRINT ""
690 REM Test 14: Numbers as strings
700 LET Z$ = "10"
710 LET AA$ = "2"
720 REM Lexicographic: "10" < "2" because '1' < '2'
730 IF Z$ < AA$ THEN PRINT "PASS: String '10' < '2' (lexicographic)" ELSE PRINT "ERROR: Numeric string comparison" : END
740 PRINT ""
750 REM Test 15: Space handling
760 LET BB$ = "A"
770 LET CC$ = "A "
780 IF BB$ <> CC$ THEN PRINT "PASS: Trailing space matters" ELSE PRINT "ERROR: Space handling" : END
790 PRINT ""
800 PRINT "=== All String Comparison Tests PASSED ==="
810 END
