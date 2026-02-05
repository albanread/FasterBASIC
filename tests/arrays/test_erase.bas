10 REM Test: ERASE Statement (Free Array Memory)
20 PRINT "=== ERASE Statement Tests ==="
30 PRINT ""
40
50 REM Test 1: ERASE integer array
60 PRINT "Test 1: ERASE integer array"
70 DIM A%(10)
80 FOR I = 1 TO 10
90   LET A%(I) = I * 10
100 NEXT I
110 PRINT "  Array populated: A%(5) = "; A%(5)
120 IF A%(5) <> 50 THEN PRINT "  ERROR: Array not populated" : END
130 ERASE A%
140 PRINT "  ERASE A% executed"
150 PRINT "  PASS: Integer array erased"
160 PRINT ""
170
180 REM Test 2: ERASE double array
190 PRINT "Test 2: ERASE double array"
200 DIM B#(5)
210 FOR I = 1 TO 5
220   LET B#(I) = I * 2.5
230 NEXT I
240 PRINT "  Array populated: B#(3) = "; B#(3)
250 IF B#(3) <> 7.5 THEN PRINT "  ERROR: Array not populated" : END
260 ERASE B#
270 PRINT "  ERASE B# executed"
280 PRINT "  PASS: Double array erased"
290 PRINT ""
300
310 REM Test 3: ERASE string array
320 PRINT "Test 3: ERASE string array"
330 DIM C$(3)
340 LET C$(1) = "Alpha"
350 LET C$(2) = "Beta"
360 LET C$(3) = "Gamma"
370 PRINT "  Array populated: C$(2) = "; C$(2)
380 ERASE C$
390 PRINT "  ERASE C$ executed"
400 PRINT "  PASS: String array erased"
410 PRINT ""
420
430 REM Test 4: ERASE multiple arrays at once
440 PRINT "Test 4: ERASE multiple arrays"
450 DIM D%(5)
460 DIM E#(5)
470 DIM F$(5)
480 FOR I = 1 TO 5
490   LET D%(I) = I
500   LET E#(I) = I * 1.1
510   LET F$(I) = "Item"
520 NEXT I
530 PRINT "  Three arrays populated"
540 ERASE D%, E#, F$
550 PRINT "  ERASE D%, E#, F$ executed"
560 PRINT "  PASS: Multiple arrays erased"
570 PRINT ""
580
590 REM Test 5: ERASE large array (memory cleanup test)
600 PRINT "Test 5: ERASE large array"
610 DIM H%(100)
620 FOR I = 1 TO 100
630   LET H%(I) = I * 5
640 NEXT I
650 PRINT "  Large array populated: H%(50) = "; H%(50)
660 IF H%(50) <> 250 THEN PRINT "  ERROR: Large array not populated" : END
670 ERASE H%
680 PRINT "  ERASE H% executed (memory freed)"
690 PRINT "  PASS: Large array erased"
700 PRINT ""
710
720 REM Test 6: ERASE string array with multiple strings
730 PRINT "Test 6: ERASE string array (string memory test)"
740 DIM S$(10)
750 LET S$(1) = "String One"
760 LET S$(2) = "String Two"
770 LET S$(3) = "String Three"
780 LET S$(4) = "String Four"
790 LET S$(5) = "String Five"
800 PRINT "  String array populated: S$(3) = "; S$(3)
810 ERASE S$
820 PRINT "  ERASE S$ executed (strings freed)"
830 PRINT "  PASS: String array memory freed"
840 PRINT ""
850
860 REM Test 7: Arrays with different sizes
870 PRINT "Test 7: ERASE arrays of different sizes"
880 DIM X%(1)
890 DIM Y%(50)
900 DIM Z%(200)
910 LET X%(1) = 99
920 LET Y%(25) = 250
930 LET Z%(100) = 1000
940 PRINT "  Small, medium, large arrays populated"
950 ERASE X%, Y%, Z%
960 PRINT "  All arrays erased"
970 PRINT "  PASS: Different sized arrays erased"
980 PRINT ""
990
1000 PRINT "=== All ERASE Tests PASSED ==="
1010 PRINT ""
1020 PRINT "Note: ERASE frees array memory but the array"
1030 PRINT "      name remains declared. Use REDIM to"
1040 PRINT "      reallocate with a different size."
1050 END
