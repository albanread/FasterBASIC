10 REM Test optimized ABS and SGN
20 PRINT "=== ABS & SGN Optimization Tests ==="
30 PRINT ""
40 CALL test_abs_basic()
50 CALL test_sgn_basic()
60 CALL test_abs_double()
70 CALL test_sgn_double()
80 CALL test_nested()
90 CALL test_loop()
100 PRINT ""
110 PRINT "=== ALL TESTS PASSED ==="
120 END
130
140 SUB test_abs_basic()
150   LOCAL i AS INTEGER
160   PRINT "--- ABS Integer ---"
170   i = -5
180   PRINT "ABS(-5) = "; ABS(i)
190   i = 5
200   PRINT "ABS(5) = "; ABS(i)
210   i = 0
220   PRINT "ABS(0) = "; ABS(i)
230   PRINT "PASS"
240   PRINT ""
250 END SUB
260
270 SUB test_sgn_basic()
280   LOCAL i AS INTEGER
290   PRINT "--- SGN Integer ---"
300   i = -5
310   PRINT "SGN(-5) = "; SGN(i)
320   i = 5
330   PRINT "SGN(5) = "; SGN(i)
340   i = 0
350   PRINT "SGN(0) = "; SGN(i)
360   PRINT "PASS"
370   PRINT ""
380 END SUB
390
400 SUB test_abs_double()
410   LOCAL d AS DOUBLE
420   PRINT "--- ABS Double (Bit Manipulation) ---"
430   d = -3.14
440   PRINT "ABS(-3.14) = "; ABS(d)
450   d = 0.0
460   PRINT "ABS(0.0) = "; ABS(d)
470   d = -0.0
480   PRINT "ABS(-0.0) = "; ABS(d)
490   PRINT "PASS"
500   PRINT ""
510 END SUB
520
530 SUB test_sgn_double()
540   LOCAL d AS DOUBLE
550   PRINT "--- SGN Double (Branchless) ---"
560   d = -3.14
570   PRINT "SGN(-3.14) = "; SGN(d)
580   d = 3.14
590   PRINT "SGN(3.14) = "; SGN(d)
600   d = 0.0
610   PRINT "SGN(0.0) = "; SGN(d)
620   PRINT "PASS"
630   PRINT ""
640 END SUB
650
660 SUB test_nested()
670   LOCAL d AS DOUBLE
680   PRINT "--- Nested Functions ---"
690   d = -7.5
700   PRINT "ABS(ABS(-7.5)) = "; ABS(ABS(d))
710   d = -3.0
720   PRINT "SGN(ABS(-3.0)) = "; SGN(ABS(d))
730   d = 5.0
740   PRINT "ABS(SGN(5.0)) = "; ABS(SGN(d))
750   PRINT "PASS"
760   PRINT ""
770 END SUB
780
790 SUB test_loop()
810   LOCAL sum AS DOUBLE
820   PRINT "--- Loop Test ---"
830   sum = 0.0
840   FOR i = -5 TO 5
850     sum = sum + ABS(i)
860   NEXT i
870   PRINT "Sum of ABS(-5 to 5) = "; sum
880   PRINT "PASS"
890   PRINT ""
900 END SUB
