10 REM Test: Comprehensive Array Memory Management
20 REM Tests ERASE, REDIM, and REDIM PRESERVE together
30 PRINT "=== Array Memory Management Tests ==="
40 PRINT ""
50
60 REM Test 1: Memory lifecycle - DIM, use, ERASE, REDIM
70 PRINT "Test 1: Complete memory lifecycle"
80 DIM A%(10)
90 FOR I = 1 TO 10
100   LET A%(I) = I * 5
110 NEXT I
120 PRINT "  DIM A%(10): A%(6) = "; A%(6)
130 IF A%(6) <> 30 THEN PRINT "  ERROR: Initial DIM failed" : END
140 ERASE A%
150 PRINT "  ERASE A% executed"
160 REDIM A%(8)
170 FOR I = 1 TO 8
180   LET A%(I) = I + 50
190 NEXT I
200 PRINT "  REDIM A%(8): A%(5) = "; A%(5)
210 IF A%(5) <> 55 THEN PRINT "  ERROR: Re-allocation failed" : END
220 PRINT "  PASS: DIM -> ERASE -> REDIM works"
230 PRINT ""
240
250 REM Test 2: ERASE then REDIM multiple times
260 PRINT "Test 2: Memory reuse pattern"
270 DIM M%(100)
280 FOR I = 1 TO 100
290   LET M%(I) = I
300 NEXT I
310 PRINT "  Large array: M%(50) = "; M%(50)
320 ERASE M%
330 PRINT "  ERASE M% (freed 100 elements)"
340 REDIM M%(50)
350 FOR I = 1 TO 50
360   LET M%(I) = I * 2
370 NEXT I
380 PRINT "  Reallocated smaller: M%(25) = "; M%(25)
390 IF M%(25) <> 50 THEN PRINT "  ERROR: Reallocation failed" : END
400 ERASE M%
410 PRINT "  ERASE M% again"
420 REDIM M%(150)
430 FOR I = 1 TO 150
440   LET M%(I) = I + 1000
450 NEXT I
460 PRINT "  Reallocated larger: M%(100) = "; M%(100)
470 IF M%(100) <> 1100 THEN PRINT "  ERROR: Large reallocation failed" : END
480 PRINT "  PASS: Memory reuse pattern works"
490 PRINT ""
500
510 REM Test 3: PRESERVE vs regular REDIM
520 PRINT "Test 3: PRESERVE vs regular REDIM"
530 DIM B%(5)
540 FOR I = 1 TO 5
550   LET B%(I) = I * 100
560 NEXT I
570 PRINT "  Initial: B%(3) = "; B%(3)
580 REDIM B%(8)
590 FOR I = 1 TO 8
600   LET B%(I) = I * 10
610 NEXT I
620 PRINT "  After REDIM: B%(3) = "; B%(3); " (new data)"
630 IF B%(3) <> 30 THEN PRINT "  ERROR: REDIM failed" : END
640 REDIM PRESERVE B%(12)
650 PRINT "  After PRESERVE: B%(3) = "; B%(3); " (preserved)"
660 IF B%(3) <> 30 THEN PRINT "  ERROR: PRESERVE failed" : END
670 PRINT "  PASS: REDIM vs PRESERVE behavior correct"
680 PRINT ""
690
700 PRINT "=== All Array Memory Management Tests PASSED ==="
710 PRINT ""
720 PRINT "Memory Management Summary:"
730 PRINT "  * DIM creates array descriptor and allocates memory"
740 PRINT "  * ERASE frees memory, keeps descriptor"
750 PRINT "  * REDIM reallocates on existing descriptor (loses data)"
760 PRINT "  * REDIM PRESERVE reallocates and keeps data"
770 END
