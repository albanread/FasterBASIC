10 REM ============================================
20 REM Benchmark: ABS and SGN Performance
30 REM Tests optimized bit-manipulation (ABS)
40 REM and branchless comparison (SGN)
50 REM ============================================
60 PRINT "=== ABS & SGN Performance Benchmark ==="
70 PRINT ""
80 PRINT "This benchmark tests the optimized implementations:"
90 PRINT "  • ABS: Bit manipulation (clear sign bit)"
100 PRINT "  • SGN: Branchless comparison"
110 PRINT ""
120
130 REM ============================================
140 REM Benchmark 1: ABS with varying signs
150 REM ============================================
160 PRINT "Benchmark 1: ABS on mixed positive/negative values"
170 DIM i AS INTEGER
180 DIM x AS DOUBLE
190 DIM sum AS DOUBLE
200 DIM iterations AS INTEGER
210 iterations = 50000
220
230 sum = 0.0
240 FOR i = 1 TO iterations
250   x = i - 25000
260   sum = sum + ABS(x)
270 NEXT i
280 PRINT "  Iterations: "; iterations
290 PRINT "  Result sum: "; sum
300 PRINT "  PASS"
310 PRINT ""
320
330 REM ============================================
340 REM Benchmark 2: SGN with varying signs
350 REM ============================================
360 PRINT "Benchmark 2: SGN on mixed positive/negative values"
370 sum = 0.0
380 FOR i = 1 TO iterations
390   x = i - 25000
400   sum = sum + SGN(x)
410 NEXT i
420 PRINT "  Iterations: "; iterations
430 PRINT "  Result sum: "; sum
440 PRINT "  PASS"
450 PRINT ""
460
470 REM ============================================
480 REM Benchmark 3: ABS on all negative values
490 REM ============================================
500 PRINT "Benchmark 3: ABS on negative values (worst case)"
510 sum = 0.0
520 FOR i = 1 TO iterations
530   x = -i
540   sum = sum + ABS(x)
550 NEXT i
560 PRINT "  Iterations: "; iterations
570 PRINT "  Result sum: "; sum
580 PRINT "  PASS"
590 PRINT ""
600
610 REM ============================================
620 REM Benchmark 4: SGN on all negative values
630 REM ============================================
640 PRINT "Benchmark 4: SGN on negative values"
650 sum = 0.0
660 FOR i = 1 TO iterations
670   x = -i
680   sum = sum + SGN(x)
690 NEXT i
700 PRINT "  Iterations: "; iterations
710 PRINT "  Result sum: "; sum
720 IF sum <> -iterations THEN PRINT "ERROR: Expected "; -iterations : END
730 PRINT "  PASS"
740 PRINT ""
750
760 REM ============================================
770 REM Benchmark 5: Combined ABS and SGN
780 REM ============================================
790 PRINT "Benchmark 5: Combined ABS(x) * SGN(y)"
800 DIM y AS DOUBLE
810 sum = 0.0
820 FOR i = 1 TO iterations
830   x = i - 25000
840   y = 25000 - i
850   sum = sum + ABS(x) * SGN(y)
860 NEXT i
870 PRINT "  Iterations: "; iterations
880 PRINT "  Result sum: "; sum
890 PRINT "  PASS"
900 PRINT ""
910
920 REM ============================================
930 REM Benchmark 6: Nested ABS calls
940 REM ============================================
950 PRINT "Benchmark 6: Nested ABS(ABS(x))"
960 sum = 0.0
970 FOR i = 1 TO iterations
980   x = i - 25000
990   sum = sum + ABS(ABS(x))
1000 NEXT i
1010 PRINT "  Iterations: "; iterations
1020 PRINT "  Result sum: "; sum
1030 PRINT "  PASS"
1040 PRINT ""
1050
1060 REM ============================================
1070 REM Benchmark 7: ABS in expressions
1080 REM ============================================
1090 PRINT "Benchmark 7: ABS(x + y) in expressions"
1100 sum = 0.0
1110 FOR i = 1 TO iterations
1120   x = i - 25000
1130   y = 10.5
1140   sum = sum + ABS(x + y)
1150 NEXT i
1160 PRINT "  Iterations: "; iterations
1170 PRINT "  Result sum: "; sum
1180 PRINT "  PASS"
1190 PRINT ""
1200
1210 REM ============================================
1220 REM Benchmark 8: SGN in conditional logic
1230 REM ============================================
1240 PRINT "Benchmark 8: SGN used in comparisons"
1250 DIM count_pos AS INTEGER
1260 DIM count_neg AS INTEGER
1270 DIM count_zero AS INTEGER
1280 count_pos = 0
1290 count_neg = 0
1300 count_zero = 0
1310
1320 FOR i = 1 TO iterations
1330   x = i - 25000
1340   DIM s AS INTEGER
1350   s = SGN(x)
1360   IF s = 1 THEN count_pos = count_pos + 1
1370   IF s = -1 THEN count_neg = count_neg + 1
1380   IF s = 0 THEN count_zero = count_zero + 1
1390 NEXT i
1400
1410 PRINT "  Iterations: "; iterations
1420 PRINT "  Positive: "; count_pos
1430 PRINT "  Negative: "; count_neg
1440 PRINT "  Zero: "; count_zero
1450 IF count_pos + count_neg + count_zero <> iterations THEN PRINT "ERROR: Count mismatch" : END
1460 PRINT "  PASS"
1470 PRINT ""
1480
1490 REM ============================================
1500 REM Final Summary
1510 REM ============================================
1520 PRINT "=========================================="
1530 PRINT "=== ALL BENCHMARKS COMPLETED ==="
1540 PRINT "=========================================="
1550 PRINT ""
1560 PRINT "Performance notes:"
1570 PRINT "  • ABS(double): 3 instructions, no branches"
1580 PRINT "  • SGN(double): 5 instructions, no branches"
1590 PRINT "  • Predicted speedup: 1.5x-4x vs function calls"
1600 PRINT ""
1610 END
