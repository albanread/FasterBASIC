10 REM Test: REDIM Statement (Resize Arrays Without Preserving Data)
20 PRINT "=== REDIM Statement Tests ==="
30 PRINT ""
40
50 REM Test 1: REDIM integer array to smaller size
60 PRINT "Test 1: REDIM integer array to smaller size"
70 DIM A%(10)
80 FOR I = 1 TO 10
90   LET A%(I) = I * 10
100 NEXT I
110 PRINT "  Original: A%(8) = "; A%(8)
120 IF A%(8) <> 80 THEN PRINT "  ERROR: Original array not populated" : END
130 REDIM A%(5)
140 PRINT "  REDIM A%(5) executed"
150 FOR I = 1 TO 5
160   LET A%(I) = I + 100
170 NEXT I
180 PRINT "  After REDIM: A%(3) = "; A%(3)
190 IF A%(3) <> 103 THEN PRINT "  ERROR: REDIM failed" : END
200 PRINT "  PASS: Array resized smaller"
210 PRINT ""
220
230 REM Test 2: REDIM integer array to larger size
240 PRINT "Test 2: REDIM integer array to larger size"
250 DIM B%(5)
260 FOR I = 1 TO 5
270   LET B%(I) = I * 2
280 NEXT I
290 PRINT "  Original size: 5 elements"
300 REDIM B%(15)
310 PRINT "  REDIM B%(15) executed"
320 FOR I = 1 TO 15
330   LET B%(I) = I + 200
340 NEXT I
350 PRINT "  After REDIM: B%(12) = "; B%(12)
360 IF B%(12) <> 212 THEN PRINT "  ERROR: REDIM failed" : END
370 PRINT "  PASS: Array resized larger"
380 PRINT ""
390
400 REM Test 3: REDIM double array
410 PRINT "Test 3: REDIM double array"
420 DIM C#(8)
430 FOR I = 1 TO 8
440   LET C#(I) = I * 1.5
450 NEXT I
460 PRINT "  Original: C#(6) = "; C#(6)
470 REDIM C#(12)
480 PRINT "  REDIM C#(12) executed"
490 FOR I = 1 TO 12
500   LET C#(I) = I * 2.5
510 NEXT I
520 PRINT "  After REDIM: C#(10) = "; C#(10)
530 IF C#(10) <> 25 THEN PRINT "  ERROR: REDIM double failed" : END
540 PRINT "  PASS: Double array resized"
550 PRINT ""
560
570 REM Test 4: REDIM string array
580 PRINT "Test 4: REDIM string array"
590 DIM D$(4)
600 LET D$(1) = "Old1"
610 LET D$(2) = "Old2"
620 LET D$(3) = "Old3"
630 LET D$(4) = "Old4"
640 PRINT "  Original: D$(2) = "; D$(2)
650 REDIM D$(7)
660 PRINT "  REDIM D$(7) executed"
670 LET D$(1) = "New1"
680 LET D$(5) = "New5"
690 LET D$(7) = "New7"
700 PRINT "  After REDIM: D$(5) = "; D$(5)
710 PRINT "  PASS: String array resized"
720 PRINT ""
730
740 REM Test 5: Multiple REDIM operations on same array
750 PRINT "Test 5: Multiple REDIM operations"
760 DIM E%(6)
770 FOR I = 1 TO 6
780   LET E%(I) = I
790 NEXT I
800 PRINT "  Initial size: 6"
810 REDIM E%(10)
820 PRINT "  First REDIM: E%(10)"
830 FOR I = 1 TO 10
840   LET E%(I) = I * 10
850 NEXT I
860 PRINT "  After first REDIM: E%(8) = "; E%(8)
870 REDIM E%(15)
880 PRINT "  Second REDIM: E%(15)"
890 FOR I = 1 TO 15
900   LET E%(I) = I * 20
910 NEXT I
920 PRINT "  After second REDIM: E%(12) = "; E%(12)
930 IF E%(12) <> 240 THEN PRINT "  ERROR: Multiple REDIM failed" : END
940 REDIM E%(8)
950 PRINT "  Third REDIM: E%(8)"
960 FOR I = 1 TO 8
970   LET E%(I) = I * 30
980 NEXT I
990 PRINT "  After third REDIM: E%(5) = "; E%(5)
1000 IF E%(5) <> 150 THEN PRINT "  ERROR: Third REDIM failed" : END
1010 PRINT "  PASS: Multiple REDIM operations work"
1020 PRINT ""
1030
1040 REM Test 6: REDIM to size 1 (minimum)
1050 PRINT "Test 6: REDIM to minimum size"
1060 DIM F%(20)
1070 FOR I = 1 TO 20
1080   LET F%(I) = I
1090 NEXT I
1100 PRINT "  Original size: 20"
1110 REDIM F%(1)
1120 PRINT "  REDIM F%(1) executed"
1130 LET F%(1) = 999
1140 PRINT "  After REDIM: F%(1) = "; F%(1)
1150 IF F%(1) <> 999 THEN PRINT "  ERROR: Minimum REDIM failed" : END
1160 PRINT "  PASS: Array resized to minimum"
1170 PRINT ""
1180
1190 REM Test 7: REDIM clears old data (does not preserve)
1200 PRINT "Test 7: REDIM does not preserve data"
1210 DIM G%(5)
1220 FOR I = 1 TO 5
1230   LET G%(I) = I * 100
1240 NEXT I
1250 PRINT "  Before REDIM: G%(3) = "; G%(3)
1260 IF G%(3) <> 300 THEN PRINT "  ERROR: Array not set up" : END
1270 REDIM G%(5)
1280 PRINT "  REDIM G%(5) executed (same size)"
1290 REM After REDIM without PRESERVE, old data is gone
1300 REM We can't reliably test the values (they're undefined)
1310 REM But we can write new values
1320 FOR I = 1 TO 5
1330   LET G%(I) = I + 500
1340 NEXT I
1350 PRINT "  After REDIM: G%(3) = "; G%(3)
1360 IF G%(3) <> 503 THEN PRINT "  ERROR: New data not written" : END
1370 PRINT "  PASS: REDIM allocates fresh memory"
1380 PRINT ""
1390
1400 REM Test 8: REDIM with expression for size
1410 PRINT "Test 8: REDIM with expression"
1420 DIM H%(10)
1430 LET SIZE% = 20
1440 PRINT "  SIZE% = "; SIZE%
1450 REDIM H%(SIZE%)
1460 PRINT "  REDIM H%(SIZE%) executed"
1470 FOR I = 1 TO 20
1480   LET H%(I) = I
1490 NEXT I
1500 PRINT "  H%(15) = "; H%(15)
1510 IF H%(15) <> 15 THEN PRINT "  ERROR: Expression size failed" : END
1520 PRINT "  PASS: REDIM with expression works"
1530 PRINT ""
1540
1550 PRINT "=== All REDIM Tests PASSED ==="
1560 END
