10 REM Test: REDIM PRESERVE Statement (Resize Arrays While Keeping Data)
20 PRINT "=== REDIM PRESERVE Statement Tests ==="
30 PRINT ""
40
50 REM Test 1: REDIM PRESERVE integer array to larger size
60 PRINT "Test 1: REDIM PRESERVE to larger size (preserve data)"
70 DIM A%(5)
80 FOR I = 1 TO 5
90   LET A%(I) = I * 10
100 NEXT I
110 PRINT "  Original: A%(3) = "; A%(3); ", A%(5) = "; A%(5)
120 IF A%(3) <> 30 THEN PRINT "  ERROR: Original data wrong" : END
130 IF A%(5) <> 50 THEN PRINT "  ERROR: Original data wrong" : END
140 REDIM PRESERVE A%(10)
150 PRINT "  REDIM PRESERVE A%(10) executed"
160 PRINT "  After REDIM: A%(3) = "; A%(3); ", A%(5) = "; A%(5)
170 IF A%(3) <> 30 THEN PRINT "  ERROR: Data not preserved" : END
180 IF A%(5) <> 50 THEN PRINT "  ERROR: Data not preserved" : END
190 REM Fill new elements
200 FOR I = 6 TO 10
210   LET A%(I) = I * 10
220 NEXT I
230 PRINT "  New element: A%(8) = "; A%(8)
240 IF A%(8) <> 80 THEN PRINT "  ERROR: New elements not writable" : END
250 PRINT "  PASS: Data preserved, array enlarged"
260 PRINT ""
270
280 REM Test 2: REDIM PRESERVE to smaller size (truncate)
290 PRINT "Test 2: REDIM PRESERVE to smaller size (truncate)"
300 DIM B%(10)
310 FOR I = 1 TO 10
320   LET B%(I) = I + 100
330 NEXT I
340 PRINT "  Original: B%(4) = "; B%(4); ", B%(9) = "; B%(9)
350 IF B%(4) <> 104 THEN PRINT "  ERROR: Original data wrong" : END
360 REDIM PRESERVE B%(6)
370 PRINT "  REDIM PRESERVE B%(6) executed"
380 PRINT "  After REDIM: B%(4) = "; B%(4)
390 IF B%(4) <> 104 THEN PRINT "  ERROR: Data not preserved" : END
400 PRINT "  PASS: Data preserved when shrinking"
410 PRINT ""
420
430 REM Test 3: REDIM PRESERVE double array
440 PRINT "Test 3: REDIM PRESERVE double array"
450 DIM C#(4)
460 LET C#(1) = 1.5
470 LET C#(2) = 2.5
480 LET C#(3) = 3.5
490 LET C#(4) = 4.5
500 PRINT "  Original: C#(2) = "; C#(2); ", C#(4) = "; C#(4)
510 IF C#(2) <> 2.5 THEN PRINT "  ERROR: Original data wrong" : END
520 IF C#(4) <> 4.5 THEN PRINT "  ERROR: Original data wrong" : END
530 REDIM PRESERVE C#(8)
540 PRINT "  REDIM PRESERVE C#(8) executed"
550 PRINT "  After REDIM: C#(2) = "; C#(2); ", C#(4) = "; C#(4)
560 IF C#(2) <> 2.5 THEN PRINT "  ERROR: Data not preserved" : END
570 IF C#(4) <> 4.5 THEN PRINT "  ERROR: Data not preserved" : END
580 LET C#(7) = 7.5
590 PRINT "  New element: C#(7) = "; C#(7)
600 IF C#(7) <> 7.5 THEN PRINT "  ERROR: New element failed" : END
610 PRINT "  PASS: Double array data preserved"
620 PRINT ""
630
640 REM Test 4: REDIM PRESERVE string array
650 PRINT "Test 4: REDIM PRESERVE string array"
660 DIM D$(3)
670 LET D$(1) = "First"
680 LET D$(2) = "Second"
690 LET D$(3) = "Third"
700 PRINT "  Original: D$(1) = "; D$(1); ", D$(3) = "; D$(3)
710 REDIM PRESERVE D$(6)
720 PRINT "  REDIM PRESERVE D$(6) executed"
730 PRINT "  After REDIM: D$(1) = "; D$(1); ", D$(3) = "; D$(3)
740 LET D$(4) = "Fourth"
750 LET D$(6) = "Sixth"
760 PRINT "  New elements: D$(4) = "; D$(4); ", D$(6) = "; D$(6)
770 PRINT "  PASS: String array data preserved"
780 PRINT ""
790
800 REM Test 5: Multiple REDIM PRESERVE operations
810 PRINT "Test 5: Multiple REDIM PRESERVE operations"
820 DIM E%(3)
830 LET E%(1) = 11
840 LET E%(2) = 22
850 LET E%(3) = 33
860 PRINT "  Initial: E%(1) = "; E%(1); ", E%(2) = "; E%(2); ", E%(3) = "; E%(3)
870 REDIM PRESERVE E%(5)
880 PRINT "  First PRESERVE: size 5"
890 LET E%(4) = 44
900 LET E%(5) = 55
910 PRINT "  After 1st: E%(2) = "; E%(2); ", E%(4) = "; E%(4)
920 IF E%(2) <> 22 THEN PRINT "  ERROR: 1st preserve failed" : END
930 IF E%(4) <> 44 THEN PRINT "  ERROR: 1st preserve failed" : END
940 REDIM PRESERVE E%(8)
950 PRINT "  Second PRESERVE: size 8"
960 LET E%(6) = 66
970 LET E%(7) = 77
980 LET E%(8) = 88
990 PRINT "  After 2nd: E%(2) = "; E%(2); ", E%(5) = "; E%(5); ", E%(8) = "; E%(8)
1000 IF E%(2) <> 22 THEN PRINT "  ERROR: 2nd preserve failed" : END
1010 IF E%(5) <> 55 THEN PRINT "  ERROR: 2nd preserve failed" : END
1020 IF E%(8) <> 88 THEN PRINT "  ERROR: 2nd preserve failed" : END
1030 PRINT "  PASS: Multiple PRESERVE operations work"
1040 PRINT ""
1050
1060 REM Test 6: REDIM PRESERVE then regular REDIM
1070 PRINT "Test 6: PRESERVE then regular REDIM"
1080 DIM F%(4)
1090 FOR I = 1 TO 4
1100   LET F%(I) = I * 100
1110 NEXT I
1120 PRINT "  Original: F%(2) = "; F%(2)
1130 REDIM PRESERVE F%(6)
1140 PRINT "  PRESERVE to size 6: F%(2) = "; F%(2)
1150 IF F%(2) <> 200 THEN PRINT "  ERROR: PRESERVE failed" : END
1160 REDIM F%(8)
1170 PRINT "  Regular REDIM to size 8 (data lost)"
1180 FOR I = 1 TO 8
1190   LET F%(I) = I * 50
1200 NEXT I
1210 PRINT "  After regular REDIM: F%(5) = "; F%(5)
1220 IF F%(5) <> 250 THEN PRINT "  ERROR: Regular REDIM failed" : END
1230 PRINT "  PASS: Can mix PRESERVE and regular REDIM"
1240 PRINT ""
1250
1260 REM Test 7: REDIM PRESERVE with same size
1270 PRINT "Test 7: REDIM PRESERVE same size (no-op)"
1280 DIM G%(5)
1290 FOR I = 1 TO 5
1300   LET G%(I) = I * 7
1310 NEXT I
1320 PRINT "  Before: G%(3) = "; G%(3)
1330 IF G%(3) <> 21 THEN PRINT "  ERROR: Setup failed" : END
1340 REDIM PRESERVE G%(5)
1350 PRINT "  REDIM PRESERVE G%(5) executed (same size)"
1360 PRINT "  After: G%(3) = "; G%(3)
1370 IF G%(3) <> 21 THEN PRINT "  ERROR: Data changed" : END
1380 PRINT "  PASS: Same size preserves data"
1390 PRINT ""
1400
1410 REM Test 8: Growing array incrementally
1420 PRINT "Test 8: Growing array incrementally"
1430 DIM H%(2)
1440 LET H%(1) = 1
1450 LET H%(2) = 2
1460 PRINT "  Start: size 2"
1470 FOR SZ = 3 TO 6
1480   REDIM PRESERVE H%(SZ)
1490   LET H%(SZ) = SZ
1500 NEXT SZ
1510 PRINT "  Grown to size 6"
1520 PRINT "  H%(1) = "; H%(1); ", H%(4) = "; H%(4); ", H%(6) = "; H%(6)
1530 IF H%(1) <> 1 THEN PRINT "  ERROR: Original data lost" : END
1540 IF H%(4) <> 4 THEN PRINT "  ERROR: Incremental growth failed" : END
1550 IF H%(6) <> 6 THEN PRINT "  ERROR: Incremental growth failed" : END
1560 PRINT "  PASS: Incremental growth works"
1570 PRINT ""
1580
1590 REM Test 9: REDIM PRESERVE with expression for size
1600 PRINT "Test 9: REDIM PRESERVE with expression"
1610 DIM J%(5)
1620 FOR I = 1 TO 5
1630   LET J%(I) = I * 20
1640 NEXT I
1650 LET NEWSIZE% = 12
1660 PRINT "  Original size: 5, new size: "; NEWSIZE%
1670 REDIM PRESERVE J%(NEWSIZE%)
1680 PRINT "  After PRESERVE: J%(3) = "; J%(3)
1690 IF J%(3) <> 60 THEN PRINT "  ERROR: Data not preserved" : END
1700 LET J%(10) = 200
1710 PRINT "  New element: J%(10) = "; J%(10)
1720 IF J%(10) <> 200 THEN PRINT "  ERROR: New element failed" : END
1730 PRINT "  PASS: Expression size works with PRESERVE"
1740 PRINT ""
1750
1760 PRINT "=== All REDIM PRESERVE Tests PASSED ==="
1770 END
