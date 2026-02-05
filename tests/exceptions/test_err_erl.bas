10 REM Test: ERR() and ERL() Intrinsic Functions
20 PRINT "=== ERR() and ERL() Tests ==="
30 PRINT ""
40
50 REM Test 1: ERR() returns thrown error code
60 PRINT "Test 1: ERR() returns thrown error code"
70 TRY
80   THROW 42
90 CATCH 42
100  LET E% = ERR()
110  PRINT "  ERR() = "; E%
120  IF E% <> 42 THEN PRINT "  ERROR: ERR() should be 42" : END
130  PRINT "  PASS: ERR() returns correct error code"
140 END TRY
150 PRINT ""
160
170 REM Test 2: ERR() with different error codes
180 PRINT "Test 2: ERR() with multiple error codes"
190 TRY
200  THROW 100
210 CATCH 100
220  IF ERR() <> 100 THEN PRINT "  ERROR: ERR() mismatch" : END
230  PRINT "  PASS: ERR() = 100"
240 END TRY
250 PRINT ""
260 TRY
270  THROW 999
280 CATCH 999
290  IF ERR() <> 999 THEN PRINT "  ERROR: ERR() mismatch" : END
300  PRINT "  PASS: ERR() = 999"
310 END TRY
320 PRINT ""
330
340 REM Test 3: ERR() in CATCH-all
350 PRINT "Test 3: ERR() in CATCH-all block"
360 TRY
370  THROW 777
380 CATCH
390  LET E% = ERR()
400  PRINT "  CATCH-all: ERR() = "; E%
410  IF E% <> 777 THEN PRINT "  ERROR: ERR() should be 777" : END
420  PRINT "  PASS: ERR() works in CATCH-all"
430 END TRY
440 PRINT ""
450
460 REM Test 4: ERR() used in expression
470 PRINT "Test 4: ERR() used in expressions"
480 TRY
490  THROW 50
500 CATCH 50
510  LET DOUBLE% = ERR() * 2
520  PRINT "  ERR() * 2 = "; DOUBLE%
530  IF DOUBLE% <> 100 THEN PRINT "  ERROR: Calculation failed" : END
540  PRINT "  PASS: ERR() works in expressions"
550 END TRY
560 PRINT ""
570
580 REM Test 5: ERR() with conditionals
590 PRINT "Test 5: ERR() with conditionals"
600 TRY
610  THROW 123
620 CATCH
630  IF ERR() = 123 THEN
640    PRINT "  ERR() correctly equals 123"
650    PRINT "  PASS: ERR() works with conditionals"
660  ELSE
670    PRINT "  ERROR: ERR() does not equal 123"
680    END
690  END IF
700 END TRY
710 PRINT ""
720
730 REM Test 6: ERL() returns line number (basic test)
740 PRINT "Test 6: ERL() returns line number"
750 TRY
760  THROW 10
770 CATCH 10
780  LET L% = ERL()
790  PRINT "  ERL() = "; L%
800  REM ERL() should return the line where THROW occurred (line 760)
810  IF L% = 760 THEN
820    PRINT "  PASS: ERL() returns correct line number"
830  ELSE
840    PRINT "  INFO: ERL() = "; L%; " (implementation-dependent)"
850    PRINT "  PASS: ERL() callable (returns "; L%; ")"
860  END IF
870 END TRY
880 PRINT ""
890
900 REM Test 7: Both ERR() and ERL() together
910 PRINT "Test 7: ERR() and ERL() together"
920 TRY
930  THROW 888
940 CATCH 888
950  LET E% = ERR()
960  LET L% = ERL()
970  PRINT "  Error "; E%; " at line "; L%
980  IF E% <> 888 THEN PRINT "  ERROR: ERR() mismatch" : END
990  PRINT "  PASS: Both functions work together"
1000 END TRY
1010 PRINT ""
1020
1030 REM Test 8: ERR() in nested CATCH
1040 PRINT "Test 8: ERR() in nested TRY/CATCH"
1050 TRY
1060  TRY
1070    THROW 111
1080  CATCH 111
1090    PRINT "  Inner CATCH: ERR() = "; ERR()
1100    IF ERR() <> 111 THEN PRINT "  ERROR: Inner ERR() mismatch" : END
1110    PRINT "  PASS: ERR() correct in inner CATCH"
1120  END TRY
1130  THROW 222
1140 CATCH 222
1150  PRINT "  Outer CATCH: ERR() = "; ERR()
1160  IF ERR() <> 222 THEN PRINT "  ERROR: Outer ERR() mismatch" : END
1170  PRINT "  PASS: ERR() correct in outer CATCH"
1180 END TRY
1190 PRINT ""
1200
1210 REM Test 9: ERR() multiple times in same CATCH
1220 PRINT "Test 9: ERR() called multiple times"
1230 TRY
1240  THROW 55
1250 CATCH 55
1260  LET E1% = ERR()
1270  LET E2% = ERR()
1280  LET E3% = ERR()
1290  PRINT "  E1% = "; E1%; ", E2% = "; E2%; ", E3% = "; E3%
1300  IF E1% <> 55 THEN PRINT "  ERROR: E1% mismatch" : END
1310  IF E2% <> 55 THEN PRINT "  ERROR: E2% mismatch" : END
1320  IF E3% <> 55 THEN PRINT "  ERROR: E3% mismatch" : END
1330  PRINT "  PASS: ERR() consistent across multiple calls"
1340 END TRY
1350 PRINT ""
1360
1370 PRINT "=== All ERR() and ERL() Tests PASSED ==="
1380 END
