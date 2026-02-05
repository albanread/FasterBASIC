10 REM Test: Basic TRY/CATCH with Specific Error Codes
20 PRINT "=== Basic TRY/CATCH Tests ==="
30 PRINT ""
40
50 REM Test 1: Normal execution (no exception)
60 PRINT "Test 1: Normal execution (no exception)"
70 TRY
80   PRINT "  Inside TRY block"
90   LET X% = 42
100  PRINT "  X% = "; X%
110 CATCH 100
120  PRINT "  ERROR: Should not reach CATCH"
130  END
140 END TRY
150 PRINT "  PASS: Normal execution completed"
160 PRINT ""
170
180 REM Test 2: THROW and CATCH specific error code
190 PRINT "Test 2: THROW and CATCH specific error code"
200 TRY
210  PRINT "  Before THROW"
220  THROW 100
230  PRINT "  ERROR: Should not reach here"
240  END
250 CATCH 100
260  PRINT "  Caught error 100"
270  PRINT "  ERR() = "; ERR()
280  IF ERR() <> 100 THEN PRINT "  ERROR: ERR() mismatch" : END
290  PRINT "  PASS: Caught error 100"
300 END TRY
310 PRINT ""
320
330 REM Test 3: Multiple CATCH blocks
340 PRINT "Test 3: Multiple CATCH blocks"
350 TRY
360  PRINT "  Throwing error 200"
370  THROW 200
380  PRINT "  ERROR: Should not reach here"
390  END
400 CATCH 100
410  PRINT "  ERROR: Wrong CATCH block (100)"
420  END
430 CATCH 200
440  PRINT "  Caught error 200 in correct block"
450  IF ERR() <> 200 THEN PRINT "  ERROR: ERR() mismatch" : END
460  PRINT "  PASS: Correct CATCH block executed"
470 CATCH 300
480  PRINT "  ERROR: Wrong CATCH block (300)"
490  END
500 END TRY
510 PRINT ""
520
530 REM Test 4: THROW different error codes
540 PRINT "Test 4: THROW error 1"
550 TRY
560  THROW 1
570 CATCH 1
580  PRINT "  Caught error 1, ERR() = "; ERR()
590  PRINT "  PASS: Error 1 caught"
600 END TRY
610 PRINT ""
620
630 PRINT "Test 5: THROW error 999"
640 TRY
650  THROW 999
660 CATCH 999
670  PRINT "  Caught error 999, ERR() = "; ERR()
680  PRINT "  PASS: Error 999 caught"
690 END TRY
700 PRINT ""
710
720 PRINT "=== All Basic TRY/CATCH Tests PASSED ==="
730 END
