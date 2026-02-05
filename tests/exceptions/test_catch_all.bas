10 REM Test: CATCH-all (CATCH without error code)
20 PRINT "=== CATCH-all Tests ==="
30 PRINT ""
40
50 REM Test 1: CATCH-all catches any error
60 PRINT "Test 1: CATCH-all catches any error"
70 TRY
80   PRINT "  Throwing error 123"
90   THROW 123
100  PRINT "  ERROR: Should not reach here"
110  END
120 CATCH
130  PRINT "  CATCH-all caught error"
140  PRINT "  ERR() = "; ERR()
150  IF ERR() <> 123 THEN PRINT "  ERROR: ERR() mismatch" : END
160  PRINT "  PASS: CATCH-all caught error 123"
170 END TRY
180 PRINT ""
190
200 REM Test 2: CATCH-all catches different errors
210 PRINT "Test 2: CATCH-all catches error 999"
220 TRY
230  PRINT "  Throwing error 999"
240  THROW 999
250 CATCH
260  PRINT "  CATCH-all caught error"
270  PRINT "  ERR() = "; ERR()
280  IF ERR() <> 999 THEN PRINT "  ERROR: ERR() mismatch" : END
290  PRINT "  PASS: CATCH-all caught error 999"
300 END TRY
310 PRINT ""
320
330 REM Test 3: Specific CATCH before CATCH-all
340 PRINT "Test 3: Specific CATCH takes precedence"
350 TRY
360  PRINT "  Throwing error 42"
370  THROW 42
380 CATCH 42
390  PRINT "  Specific CATCH 42 executed"
400  PRINT "  PASS: Specific CATCH took precedence"
410 CATCH
420  PRINT "  ERROR: CATCH-all should not execute"
430  END
440 END TRY
450 PRINT ""
460
470 REM Test 4: CATCH-all for unmatched error
480 PRINT "Test 4: CATCH-all for unmatched error"
490 TRY
500  PRINT "  Throwing error 777"
510  THROW 777
520 CATCH 100
530  PRINT "  ERROR: Wrong CATCH block"
540  END
550 CATCH 200
560  PRINT "  ERROR: Wrong CATCH block"
570  END
580 CATCH
590  PRINT "  CATCH-all caught unmatched error 777"
600  PRINT "  ERR() = "; ERR()
610  IF ERR() <> 777 THEN PRINT "  ERROR: ERR() mismatch" : END
620  PRINT "  PASS: CATCH-all caught unmatched error"
630 END TRY
640 PRINT ""
650
660 PRINT "=== All CATCH-all Tests PASSED ==="
670 END
