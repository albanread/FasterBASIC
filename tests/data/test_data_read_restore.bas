10 REM Test: DATA/READ/RESTORE Statements
20 PRINT "=== DATA/READ/RESTORE Tests ==="
30 PRINT ""
40 REM =========================================================================
50 REM Test 1: Basic READ of integers
60 REM =========================================================================
70 PRINT "Test 1: Basic READ of integers"
80 READ A%, B%, C%
90 IF A% <> 10 THEN PRINT "  ERROR: Expected 10, got"; A% : END
100 IF B% <> 20 THEN PRINT "  ERROR: Expected 20, got"; B% : END
110 IF C% <> 30 THEN PRINT "  ERROR: Expected 30, got"; C% : END
120 PRINT "  PASS: Read three integers (10, 20, 30)"
130 PRINT ""
140 REM =========================================================================
150 REM Test 2: READ doubles
160 REM =========================================================================
170 PRINT "Test 2: READ doubles"
180 READ X#, Y#, Z#
190 IF X# < 3.14 OR X# > 3.15 THEN PRINT "  ERROR: Expected ~3.14, got"; X# : END
200 IF Y# < 2.71 OR Y# > 2.72 THEN PRINT "  ERROR: Expected ~2.718, got"; Y# : END
210 IF Z# < 1.41 OR Z# > 1.42 THEN PRINT "  ERROR: Expected ~1.414, got"; Z# : END
220 PRINT "  PASS: Read three doubles (3.14, 2.718, 1.414)"
230 PRINT ""
240 REM =========================================================================
250 REM Test 3: READ strings
260 REM =========================================================================
270 PRINT "Test 3: READ strings"
280 READ S1$, S2$, S3$
290 IF S1$ <> "Hello" THEN PRINT "  ERROR: Expected 'Hello', got"; S1$ : END
300 IF S2$ <> "World" THEN PRINT "  ERROR: Expected 'World', got"; S2$ : END
310 IF S3$ <> "BASIC" THEN PRINT "  ERROR: Expected 'BASIC', got"; S3$ : END
320 PRINT "  PASS: Read three strings (Hello, World, BASIC)"
330 PRINT ""
340 REM =========================================================================
350 REM Test 4: RESTORE and re-read
360 REM =========================================================================
370 PRINT "Test 4: RESTORE and re-read"
380 RESTORE
390 READ VAL1%, VAL2%, VAL3%
400 IF VAL1% <> 10 THEN PRINT "  ERROR: After RESTORE, expected 10, got"; VAL1% : END
410 IF VAL2% <> 20 THEN PRINT "  ERROR: After RESTORE, expected 20, got"; VAL2% : END
420 IF VAL3% <> 30 THEN PRINT "  ERROR: After RESTORE, expected 30, got"; VAL3% : END
430 PRINT "  PASS: RESTORE reset data pointer to beginning"
440 PRINT ""
450 REM =========================================================================
460 REM Test 5: Mixed types in DATA
470 REM =========================================================================
480 PRINT "Test 5: Mixed types in DATA"
490 RESTORE 1000
500 READ MIX1%, MIX2#, MIX3$, MIX4%
510 IF MIX1% <> 42 THEN PRINT "  ERROR: Expected 42, got"; MIX1% : END
520 IF MIX2# < 9.9 OR MIX2# > 10.1 THEN PRINT "  ERROR: Expected 10.0, got"; MIX2# : END
530 IF MIX3$ <> "Test" THEN PRINT "  ERROR: Expected 'Test', got"; MIX3$ : END
540 IF MIX4% <> 99 THEN PRINT "  ERROR: Expected 99, got"; MIX4% : END
550 PRINT "  PASS: Read mixed types (42, 10.0, Test, 99)"
560 PRINT ""
570 REM =========================================================================
580 REM Test 6: Multiple DATA statements
590 REM =========================================================================
600 PRINT "Test 6: Multiple DATA statements"
610 RESTORE 2000
620 READ D1%, D2%, D3%, D4%, D5%, D6%
630 LET SUM% = D1% + D2% + D3% + D4% + D5% + D6%
640 IF SUM% <> 21 THEN PRINT "  ERROR: Expected sum 21, got"; SUM% : END
650 PRINT "  PASS: Read from multiple DATA statements (sum = 21)"
660 PRINT ""
670 REM =========================================================================
680 REM Test 7: RESTORE to specific line
690 REM =========================================================================
700 PRINT "Test 7: RESTORE to specific line"
710 RESTORE 3000
720 READ R1%, R2%, R3%
730 IF R1% <> 100 THEN PRINT "  ERROR: Expected 100, got"; R1% : END
740 IF R2% <> 200 THEN PRINT "  ERROR: Expected 200, got"; R2% : END
750 IF R3% <> 300 THEN PRINT "  ERROR: Expected 300, got"; R3% : END
760 PRINT "  PASS: RESTORE to line 3000 worked"
770 PRINT ""
780 REM =========================================================================
790 REM Test 8: Negative numbers in DATA
800 REM =========================================================================
810 PRINT "Test 8: Negative numbers in DATA"
820 RESTORE 4000
830 READ NEG1%, NEG2#, NEG3%
840 IF NEG1% <> -10 THEN PRINT "  ERROR: Expected -10, got"; NEG1% : END
850 IF NEG2# > -5.49 OR NEG2# < -5.51 THEN PRINT "  ERROR: Expected -5.5, got"; NEG2# : END
860 IF NEG3% <> -999 THEN PRINT "  ERROR: Expected -999, got"; NEG3% : END
870 PRINT "  PASS: Read negative numbers (-10, -5.5, -999)"
880 PRINT ""
890 REM =========================================================================
900 REM Test 9: Zero values in DATA
910 REM =========================================================================
920 PRINT "Test 9: Zero values in DATA"
930 RESTORE 5000
940 READ ZERO1%, ZERO2#, ZERO3%
950 IF ZERO1% <> 0 THEN PRINT "  ERROR: Expected 0, got"; ZERO1% : END
960 IF ZERO2# <> 0.0 THEN PRINT "  ERROR: Expected 0.0, got"; ZERO2# : END
970 IF ZERO3% <> 0 THEN PRINT "  ERROR: Expected 0, got"; ZERO3% : END
980 PRINT "  PASS: Read zero values (0, 0.0, 0)"
990 PRINT ""
1000 DATA 42, 10.0, "Test", 99
1010 REM =========================================================================
1020 REM Test 10: String with spaces
1030 REM =========================================================================
1040 PRINT "Test 10: String with spaces"
1050 RESTORE 6000
1060 READ SPACE1$, SPACE2$
1070 IF SPACE1$ <> "Hello World" THEN PRINT "  ERROR: Expected 'Hello World', got"; SPACE1$ : END
1080 IF SPACE2$ <> "Multiple Words Here" THEN PRINT "  ERROR: Expected 'Multiple Words Here', got"; SPACE2$ : END
1090 PRINT "  PASS: Read strings with spaces"
1100 PRINT ""
1110 REM =========================================================================
1120 REM Test 11: Sequential READ without RESTORE
1130 REM =========================================================================
1140 PRINT "Test 11: Sequential READ"
1150 RESTORE 7000
1160 READ SEQ1%, SEQ2%, SEQ3%
1170 READ SEQ4%, SEQ5%, SEQ6%
1180 LET TOTAL% = SEQ1% + SEQ2% + SEQ3% + SEQ4% + SEQ5% + SEQ6%
1190 IF TOTAL% <> 21 THEN PRINT "  ERROR: Expected total 21, got"; TOTAL% : END
1200 PRINT "  PASS: Sequential READ (1+2+3+4+5+6 = 21)"
1210 PRINT ""
1220 REM =========================================================================
1230 REM Test 12: Large numbers
1240 REM =========================================================================
1250 PRINT "Test 12: Large numbers"
1260 RESTORE 8000
1270 READ BIG1%, BIG2#
1280 IF BIG1% <> 1000000 THEN PRINT "  ERROR: Expected 1000000, got"; BIG1% : END
1290 IF BIG2# < 999999.9 OR BIG2# > 1000000.1 THEN PRINT "  ERROR: Expected 1000000.0, got"; BIG2# : END
1300 PRINT "  PASS: Read large numbers (1000000, 1000000.0)"
1310 PRINT ""
1320 PRINT "=== All DATA/READ/RESTORE Tests PASSED ==="
1330 END
1340 REM =========================================================================
1350 REM DATA statements at end
1360 REM =========================================================================
1370 DATA 10, 20, 30
1380 DATA 3.14, 2.718, 1.414
1390 DATA "Hello", "World", "BASIC"
2000 DATA 1, 2, 3
2010 DATA 4, 5, 6
3000 DATA 100, 200, 300
4000 DATA -10, -5.5, -999
5000 DATA 0, 0.0, 0
6000 DATA "Hello World", "Multiple Words Here"
7000 DATA 1, 2, 3, 4, 5, 6
8000 DATA 1000000, 1000000.0
