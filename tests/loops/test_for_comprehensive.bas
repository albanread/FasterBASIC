10 REM Test: Comprehensive FOR Loop Tests
20 REM Tests: Basic FOR, STEP, negative STEP, nested loops, EXIT FOR
30 REM Note: FOR loop variables are implicitly INTEGER type
40 PRINT "=== FOR Loop Comprehensive Tests ==="
50 PRINT ""
60 REM Test 1: Basic FOR loop counting up
70 PRINT "Test 1: Basic FOR loop 1 TO 5"
80 LET SUM% = 0
90 FOR I = 1 TO 5
100   PRINT I;
110   LET SUM% = SUM% + I
120 NEXT I
130 PRINT ""
140 IF SUM% <> 15 THEN PRINT "ERROR: Basic FOR loop failed" : END
150 PRINT "PASS: Sum = "; SUM%; " (expected 15)"
160 PRINT ""
170 REM Test 2: FOR loop with STEP 2
180 PRINT "Test 2: FOR loop 1 TO 10 STEP 2"
190 LET COUNT% = 0
200 FOR J = 1 TO 10 STEP 2
210   PRINT J;
220   LET COUNT% = COUNT% + 1
230 NEXT J
240 PRINT ""
250 IF COUNT% <> 5 THEN PRINT "ERROR: STEP 2 loop failed" : END
260 PRINT "PASS: Iterations = "; COUNT%; " (expected 5)"
270 PRINT ""
280 REM Test 3: FOR loop with STEP 3
290 PRINT "Test 3: FOR loop 0 TO 12 STEP 3"
300 LET RESULT% = 0
310 FOR K = 0 TO 12 STEP 3
320   PRINT K;
330   LET RESULT% = RESULT% + K
340 NEXT K
350 PRINT ""
360 IF RESULT% <> 30 THEN PRINT "ERROR: STEP 3 loop failed, got "; RESULT% : END
370 PRINT "PASS: Sum = "; RESULT%; " (expected 30)"
380 PRINT ""
390 REM Test 4: FOR loop counting down (negative STEP)
400 PRINT "Test 4: FOR loop 10 TO 1 STEP -1"
410 LET DOWN_SUM% = 0
420 FOR L = 10 TO 1 STEP -1
430   PRINT L;
440   LET DOWN_SUM% = DOWN_SUM% + L
450 NEXT L
460 PRINT ""
470 IF DOWN_SUM% <> 55 THEN PRINT "ERROR: Negative STEP loop failed" : END
480 PRINT "PASS: Sum = "; DOWN_SUM%; " (expected 55)"
490 PRINT ""
500 REM Test 5: FOR loop counting down with STEP -2
510 PRINT "Test 5: FOR loop 10 TO 2 STEP -2"
520 LET COUNT2% = 0
530 FOR M = 10 TO 2 STEP -2
540   PRINT M;
550   LET COUNT2% = COUNT2% + 1
560 NEXT M
570 PRINT ""
580 IF COUNT2% <> 5 THEN PRINT "ERROR: STEP -2 loop failed" : END
590 PRINT "PASS: Iterations = "; COUNT2%; " (expected 5)"
600 PRINT ""
610 REM Test 6: FOR loop with zero iterations
620 PRINT "Test 6: FOR loop 10 TO 1 STEP 1 (should not execute)"
630 LET ZERO_COUNT% = 0
640 FOR N = 10 TO 1 STEP 1
650   LET ZERO_COUNT% = ZERO_COUNT% + 1
660   PRINT "ERROR: This should not execute"
670 NEXT N
680 IF ZERO_COUNT% <> 0 THEN PRINT "ERROR: Zero iteration loop failed" : END
690 PRINT "PASS: Loop correctly skipped (0 iterations)"
700 PRINT ""
710 REM Test 7: Single iteration loop
720 PRINT "Test 7: FOR loop 5 TO 5 (single iteration)"
730 LET SINGLE% = 0
740 FOR O = 5 TO 5
750   LET SINGLE% = O
760   PRINT O
770 NEXT O
780 IF SINGLE% <> 5 THEN PRINT "ERROR: Single iteration loop failed" : END
790 PRINT "PASS: Single iteration = "; SINGLE%
800 PRINT ""
810 REM Test 8: Nested FOR loops
820 PRINT "Test 8: Nested FOR loops (multiplication table)"
830 LET NESTED_SUM% = 0
840 FOR P = 1 TO 3
850   FOR Q = 1 TO 3
860     LET PRODUCT% = P * Q
870     PRINT P; "*"; Q; "="; PRODUCT%; " ";
880     LET NESTED_SUM% = NESTED_SUM% + PRODUCT%
890   NEXT Q
900   PRINT ""
910 NEXT P
920 IF NESTED_SUM% <> 36 THEN PRINT "ERROR: Nested loops failed" : END
930 PRINT "PASS: Nested sum = "; NESTED_SUM%; " (expected 36)"
940 PRINT ""
950 REM Test 9: EXIT FOR
960 PRINT "Test 9: EXIT FOR when I = 3"
970 LET EXIT_COUNT% = 0
980 FOR S = 1 TO 10
990   PRINT S;
1000   LET EXIT_COUNT% = EXIT_COUNT% + 1
1010   IF S = 3 THEN EXIT FOR
1020 NEXT S
1030 PRINT ""
1040 IF EXIT_COUNT% <> 3 THEN PRINT "ERROR: EXIT FOR failed" : END
1050 PRINT "PASS: Exited after "; EXIT_COUNT%; " iterations"
1060 PRINT ""
1070 REM Test 10: Large range FOR loop
1080 PRINT "Test 10: FOR loop 1 TO 100"
1090 LET LARGE_SUM% = 0
1100 FOR T = 1 TO 100
1110   LET LARGE_SUM% = LARGE_SUM% + T
1120 NEXT T
1130 PRINT "Sum of 1 to 100 = "; LARGE_SUM%
1140 IF LARGE_SUM% <> 5050 THEN PRINT "ERROR: Large range failed" : END
1150 PRINT "PASS: Large sum = "; LARGE_SUM%; " (expected 5050)"
1160 PRINT ""
1170 REM Test 11: FOR loop variable value after completion
1180 PRINT "Test 11: Loop variable value after completion"
1190 FOR U = 1 TO 5
1200 NEXT U
1210 PRINT "U after loop = "; U
1220 IF U <> 6 THEN PRINT "ERROR: Loop variable wrong after loop" : END
1230 PRINT "PASS: Loop variable = "; U; " (expected 6)"
1240 PRINT ""
1250 PRINT "=== All FOR Loop Tests PASSED ==="
1260 END
