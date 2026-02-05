10 REM Test: Comprehensive Exception Handling Test
20 REM This test combines multiple exception features in realistic scenarios
30 PRINT "=== Comprehensive Exception Handling Test ==="
40 PRINT ""
50
60 REM Test 1: Division by zero simulation with cleanup
70 PRINT "Test 1: Division check with FINALLY cleanup"
80 LET DIVISOR% = 0
90 LET RESULT% = 0
100 LET CLEANUP% = 0
110 TRY
120   IF DIVISOR% = 0 THEN THROW 11
130   LET RESULT% = 100 / DIVISOR%
140   PRINT "  Result: "; RESULT%
150 CATCH 11
160   PRINT "  Caught division by zero error"
170   PRINT "  ERR() = "; ERR()
180   LET RESULT% = -1
190 FINALLY
200   PRINT "  FINALLY: Cleanup performed"
210   LET CLEANUP% = 1
220 END TRY
230 IF CLEANUP% <> 1 THEN PRINT "  ERROR: FINALLY did not run" : END
240 IF RESULT% <> -1 THEN PRINT "  ERROR: Result not set correctly" : END
250 PRINT "  PASS: Division check with cleanup"
260 PRINT ""
270
280 REM Test 2: Resource acquisition/release pattern
290 PRINT "Test 2: Resource management pattern"
300 LET FILE_OPEN% = 0
310 LET FILE_CLOSED% = 0
320 TRY
330   PRINT "  Opening resource..."
340   LET FILE_OPEN% = 1
350   PRINT "  Processing resource..."
360   REM Simulate error during processing
370   THROW 99
380   PRINT "  ERROR: Should not reach here"
390 CATCH 99
400   PRINT "  Error during processing: "; ERR()
410 FINALLY
420   IF FILE_OPEN% = 1 THEN
430     PRINT "  Closing resource in FINALLY"
440     LET FILE_CLOSED% = 1
450   END IF
460 END TRY
470 IF FILE_CLOSED% <> 1 THEN PRINT "  ERROR: Resource not closed" : END
480 PRINT "  PASS: Resource properly cleaned up"
490 PRINT ""
500
510 REM Test 3: Multiple operations with selective error handling
520 PRINT "Test 3: Multiple operations with different errors"
530 LET OP1% = 0
540 LET OP2% = 0
550 LET OP3% = 0
560 REM Operation 1
570 TRY
580   PRINT "  Operation 1: Checking permissions..."
590   LET PERM% = 1
600   IF PERM% = 0 THEN THROW 403
610   LET OP1% = 1
620   PRINT "  Operation 1: PASS"
630 CATCH 403
640   PRINT "  Permission denied"
650 END TRY
660 REM Operation 2
670 TRY
680   PRINT "  Operation 2: Validating data..."
690   LET DATA% = 0
700   IF DATA% = 0 THEN THROW 400
710   LET OP2% = 1
720 CATCH 400
730   PRINT "  Invalid data, using default"
740   LET OP2% = -1
750 END TRY
760 REM Operation 3
770 TRY
780   PRINT "  Operation 3: Saving..."
790   LET OP3% = 1
800   PRINT "  Operation 3: PASS"
810 CATCH
820   PRINT "  Save failed"
830 END TRY
840 IF OP1% <> 1 THEN PRINT "  ERROR: OP1 failed" : END
850 IF OP2% <> -1 THEN PRINT "  ERROR: OP2 failed" : END
860 IF OP3% <> 1 THEN PRINT "  ERROR: OP3 failed" : END
870 PRINT "  PASS: Multiple operations handled correctly"
880 PRINT ""
890
900 REM Test 4: Error propagation through call chain simulation
910 PRINT "Test 4: Error propagation simulation"
920 LET LEVEL% = 0
930 TRY
940   PRINT "  Level 1: Starting..."
950   LET LEVEL% = 1
960   TRY
970     PRINT "    Level 2: Processing..."
980     LET LEVEL% = 2
990     TRY
1000      PRINT "      Level 3: Critical error!"
1010      LET LEVEL% = 3
1020      THROW 500
1030    CATCH 404
1040      PRINT "      ERROR: Wrong handler at level 3"
1050      END
1060    END TRY
1070    PRINT "    ERROR: Should not reach level 2 continuation"
1080    END
1090  CATCH 500
1100    PRINT "    Level 2: Caught error from level 3"
1110    PRINT "    ERR() = "; ERR()
1120    IF LEVEL% <> 3 THEN PRINT "    ERROR: Level tracking failed" : END
1130    LET LEVEL% = 2
1140  END TRY
1150  PRINT "  Level 1: Continuing after level 2 handled error"
1160  LET LEVEL% = 1
1170 CATCH
1180  PRINT "  ERROR: Level 1 should not catch anything"
1190  END
1200 END TRY
1210 IF LEVEL% <> 1 THEN PRINT "  ERROR: Final level incorrect" : END
1220 PRINT "  PASS: Error propagation works correctly"
1230 PRINT ""
1240
1250 REM Test 5: State machine with error recovery
1260 PRINT "Test 5: State machine with error recovery"
1270 LET STATE% = 0
1280 LET RETRY% = 0
1290 LET SUCCESS% = 0
1300 REM State 0: Initial
1310 PRINT "  State 0: Initializing..."
1320 LET STATE% = 1
1330 REM State 1: Processing (with error)
1340 TRY
1350   PRINT "  State 1: Processing..."
1360   IF RETRY% = 0 THEN
1370     PRINT "    First attempt fails"
1380     THROW 503
1390   END IF
1400   PRINT "    Second attempt succeeds"
1410   LET STATE% = 2
1420 CATCH 503
1430   PRINT "    Service unavailable, retrying..."
1440   LET RETRY% = 1
1450   LET STATE% = 1
1460 END TRY
1470 REM Retry if needed
1480 IF STATE% = 1 AND RETRY% = 1 THEN
1490   TRY
1500     PRINT "  State 1: Retry processing..."
1510     LET STATE% = 2
1520     LET SUCCESS% = 1
1530   CATCH
1540     PRINT "    Retry failed"
1550   END TRY
1560 END IF
1570 IF STATE% <> 2 THEN PRINT "  ERROR: State machine failed" : END
1580 IF SUCCESS% <> 1 THEN PRINT "  ERROR: Retry failed" : END
1590 PRINT "  PASS: State machine with retry works"
1600 PRINT ""
1610
1620 REM Test 6: Complex FINALLY with multiple cleanups
1630 PRINT "Test 6: Complex cleanup in FINALLY"
1640 LET LOCK% = 0
1650 LET CONN% = 0
1660 LET TRANS% = 0
1670 LET ALL_CLEANED% = 0
1680 TRY
1690   PRINT "  Acquiring lock..."
1700   LET LOCK% = 1
1710   PRINT "  Opening connection..."
1720   LET CONN% = 1
1730   PRINT "  Starting transaction..."
1740   LET TRANS% = 1
1750   PRINT "  Transaction fails!"
1760   THROW 999
1770 CATCH 999
1780   PRINT "  Transaction error caught: "; ERR()
1790 FINALLY
1800   PRINT "  FINALLY: Cleaning up resources..."
1810   IF TRANS% = 1 THEN
1820     PRINT "    Rolling back transaction"
1830     LET TRANS% = 0
1840   END IF
1850   IF CONN% = 1 THEN
1860     PRINT "    Closing connection"
1870     LET CONN% = 0
1880   END IF
1890   IF LOCK% = 1 THEN
1900     PRINT "    Releasing lock"
1910     LET LOCK% = 0
1920   END IF
1930   IF LOCK% = 0 AND CONN% = 0 AND TRANS% = 0 THEN
1940     LET ALL_CLEANED% = 1
1950   END IF
1960 END TRY
1970 IF ALL_CLEANED% <> 1 THEN PRINT "  ERROR: Cleanup incomplete" : END
1980 PRINT "  PASS: Complex cleanup successful"
1990 PRINT ""
2000
2010 REM Test 7: Error code dispatch table simulation
2020 PRINT "Test 7: Error code dispatch"
2030 LET ERROR_HANDLED% = 0
2040 LET ERROR_CODE% = 404
2050 TRY
2060   PRINT "  Simulating error "; ERROR_CODE%
2070   THROW ERROR_CODE%
2080 CATCH 400
2090   PRINT "  Bad Request"
2100   LET ERROR_HANDLED% = 400
2110 CATCH 401
2120   PRINT "  Unauthorized"
2130   LET ERROR_HANDLED% = 401
2140 CATCH 403
2150   PRINT "  Forbidden"
2160   LET ERROR_HANDLED% = 403
2170 CATCH 404
2180   PRINT "  Not Found - this is the correct handler"
2190   LET ERROR_HANDLED% = 404
2200 CATCH 500
2210   PRINT "  Internal Server Error"
2220   LET ERROR_HANDLED% = 500
2230 CATCH
2240   PRINT "  Unknown Error"
2250   LET ERROR_HANDLED% = -1
2260 END TRY
2270 IF ERROR_HANDLED% <> 404 THEN PRINT "  ERROR: Wrong handler" : END
2280 PRINT "  PASS: Correct error handler dispatched"
2290 PRINT ""
2300
2310 REM Final summary
2320 PRINT "=== All Comprehensive Tests PASSED ==="
2330 PRINT ""
2340 PRINT "Summary:"
2350 PRINT "  - Division check with cleanup: OK"
2360 PRINT "  - Resource management: OK"
2370 PRINT "  - Multiple operations: OK"
2380 PRINT "  - Error propagation: OK"
2390 PRINT "  - State machine recovery: OK"
2400 PRINT "  - Complex FINALLY cleanup: OK"
2410 PRINT "  - Error dispatch table: OK"
2420 PRINT ""
2430 PRINT "Exception handling system fully operational!"
2440 END
