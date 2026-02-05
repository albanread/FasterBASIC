10 REM Test: Nested TRY blocks
20 PRINT "=== Nested TRY Block Tests ==="
30 PRINT ""
40
50 REM Test 1: Inner TRY catches exception
60 PRINT "Test 1: Inner TRY catches exception"
70 TRY
80   PRINT "  Outer TRY block"
90   TRY
100    PRINT "    Inner TRY block"
110    THROW 100
120    PRINT "    ERROR: Should not reach here"
130  CATCH 100
140    PRINT "    Inner CATCH caught error 100"
150    PRINT "    PASS: Inner CATCH executed"
160  END TRY
170  PRINT "  Back in outer TRY"
180  PRINT "  PASS: Outer TRY continues normally"
190 CATCH 100
200  PRINT "  ERROR: Outer CATCH should not execute"
210  END
220 END TRY
230 PRINT ""
240
250 REM Test 2: Inner TRY doesn't catch, outer does
260 PRINT "Test 2: Inner TRY doesn't catch, outer does"
270 TRY
280  PRINT "  Outer TRY block"
290  TRY
300    PRINT "    Inner TRY block"
310    THROW 200
320    PRINT "    ERROR: Should not reach here"
330  CATCH 100
340    PRINT "    ERROR: Inner CATCH 100 should not match"
350    END
360  END TRY
370  PRINT "  ERROR: Should not reach here after inner TRY"
380  END
390 CATCH 200
400  PRINT "  Outer CATCH caught error 200"
410  IF ERR() <> 200 THEN PRINT "  ERROR: ERR() mismatch" : END
420  PRINT "  PASS: Outer CATCH executed correctly"
430 END TRY
440 PRINT ""
450
460 REM Test 3: Both levels have CATCH-all
470 PRINT "Test 3: Inner CATCH-all takes precedence"
480 TRY
490  PRINT "  Outer TRY"
500  TRY
510    PRINT "    Inner TRY"
520    THROW 999
530  CATCH
540    PRINT "    Inner CATCH-all caught error"
550    PRINT "    ERR() = "; ERR()
560    IF ERR() <> 999 THEN PRINT "    ERROR: ERR() mismatch" : END
570    PRINT "    PASS: Inner CATCH-all executed"
580  END TRY
590  PRINT "  Back in outer TRY"
600 CATCH
610  PRINT "  ERROR: Outer CATCH-all should not execute"
620  END
630 END TRY
640 PRINT ""
650
660 REM Test 4: Three levels deep
670 PRINT "Test 4: Three levels of nesting"
680 TRY
690  PRINT "  Level 1 TRY"
700  TRY
710    PRINT "    Level 2 TRY"
720    TRY
730      PRINT "      Level 3 TRY"
740      THROW 333
750    CATCH 333
760      PRINT "      Level 3 CATCH caught error 333"
770      PRINT "      PASS: Innermost level caught exception"
780    END TRY
790    PRINT "    Back at level 2"
800  CATCH
810    PRINT "    ERROR: Level 2 CATCH should not execute"
820    END
830  END TRY
840  PRINT "  Back at level 1"
850 CATCH
860  PRINT "  ERROR: Level 1 CATCH should not execute"
870  END
880 END TRY
890 PRINT ""
900
910 REM Test 5: Nested with FINALLY
920 PRINT "Test 5: Nested TRY with FINALLY blocks"
930 LET OUTER% = 0
940 LET INNER% = 0
950 TRY
960  PRINT "  Outer TRY"
970  TRY
980    PRINT "    Inner TRY"
990    THROW 555
1000 CATCH 555
1010   PRINT "    Inner CATCH"
1020 FINALLY
1030   PRINT "    Inner FINALLY"
1040   LET INNER% = 1
1050 END TRY
1060 PRINT "  After inner TRY"
1070 FINALLY
1080  PRINT "  Outer FINALLY"
1090  LET OUTER% = 1
1100 END TRY
1110 IF INNER% <> 1 THEN PRINT "  ERROR: Inner FINALLY did not execute" : END
1120 IF OUTER% <> 1 THEN PRINT "  ERROR: Outer FINALLY did not execute" : END
1130 PRINT "  PASS: Both FINALLY blocks executed"
1140 PRINT ""
1150
1160 PRINT "=== All Nested TRY Tests PASSED ==="
1170 END
