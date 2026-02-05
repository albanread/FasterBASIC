10 REM Test: FINALLY block execution
20 PRINT "=== FINALLY Block Tests ==="
30 PRINT ""
40
50 REM Test 1: FINALLY executes on normal exit
60 PRINT "Test 1: FINALLY on normal exit"
70 LET FLAG% = 0
80 TRY
90   PRINT "  Inside TRY block"
100  LET X% = 42
110  PRINT "  X% = "; X%
120 CATCH 100
130  PRINT "  ERROR: Should not reach CATCH"
140  END
150 FINALLY
160  PRINT "  FINALLY block executed"
170  LET FLAG% = 1
180 END TRY
190 IF FLAG% <> 1 THEN PRINT "  ERROR: FINALLY did not execute" : END
200 PRINT "  PASS: FINALLY executed on normal exit"
210 PRINT ""
220
230 REM Test 2: FINALLY executes on exception
240 PRINT "Test 2: FINALLY on exception"
250 LET FLAG% = 0
260 TRY
270  PRINT "  Before THROW"
280  THROW 100
290  PRINT "  ERROR: Should not reach here"
300 CATCH 100
310  PRINT "  In CATCH block"
320 FINALLY
330  PRINT "  FINALLY block executed after exception"
340  LET FLAG% = 2
350 END TRY
360 IF FLAG% <> 2 THEN PRINT "  ERROR: FINALLY did not execute" : END
370 PRINT "  PASS: FINALLY executed on exception"
380 PRINT ""
390
400 REM Test 3: FINALLY without CATCH (normal exit)
410 PRINT "Test 3: FINALLY without CATCH (normal exit)"
420 LET FLAG% = 0
430 TRY
440  PRINT "  Normal execution"
450  LET Y% = 123
460 FINALLY
470  PRINT "  FINALLY executed"
480  LET FLAG% = 3
490 END TRY
500 IF FLAG% <> 3 THEN PRINT "  ERROR: FINALLY did not execute" : END
510 PRINT "  PASS: FINALLY without CATCH works"
520 PRINT ""
530
540 REM Test 4: Multiple operations in FINALLY
550 PRINT "Test 4: Multiple operations in FINALLY"
560 LET A% = 0
570 LET B% = 0
580 LET C% = 0
590 TRY
600  PRINT "  Setting values in TRY"
610  LET A% = 10
620  THROW 200
630 CATCH 200
640  PRINT "  In CATCH, A% = "; A%
650  LET B% = 20
660 FINALLY
670  PRINT "  In FINALLY, A% = "; A%; ", B% = "; B%
680  LET C% = A% + B%
690  PRINT "  C% = A% + B% = "; C%
700 END TRY
710 IF C% <> 30 THEN PRINT "  ERROR: FINALLY calculation failed" : END
720 PRINT "  PASS: Multiple FINALLY operations work"
730 PRINT ""
740
750 PRINT "=== All FINALLY Tests PASSED ==="
760 END
