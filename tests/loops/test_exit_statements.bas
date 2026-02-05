10 REM Test: EXIT Statements (EXIT FOR, EXIT DO)
20 REM Tests: Early exit from loops
30 PRINT "=== EXIT Statements Tests ==="
40 PRINT ""
50 REM Test 1: EXIT FOR - simple exit
60 LET COUNT% = 0
70 FOR I% = 1 TO 10
80     COUNT% = COUNT% + 1
90     IF I% = 5 THEN EXIT FOR
100 NEXT I%
110 PRINT "Exit FOR at 5, COUNT = "; COUNT%
120 IF COUNT% <> 5 THEN PRINT "ERROR: EXIT FOR failed" : END
130 PRINT "PASS: EXIT FOR at iteration 5"
140 PRINT ""
150 REM Test 2: EXIT FOR - no exit (normal completion)
160 LET SUM% = 0
170 FOR J% = 1 TO 5
180     SUM% = SUM% + J%
190 NEXT J%
200 PRINT "Normal FOR completion, SUM = "; SUM%
210 IF SUM% <> 15 THEN PRINT "ERROR: Normal FOR failed" : END
220 PRINT "PASS: Normal FOR = 15"
230 PRINT ""
240 REM Test 3: EXIT FOR with condition
250 LET FOUND% = 0
260 FOR K% = 1 TO 100
270     IF K% * K% > 50 THEN
280         FOUND% = K%
290         EXIT FOR
300     END IF
310 NEXT K%
320 PRINT "First K where K*K > 50: "; FOUND%
330 IF FOUND% <> 8 THEN PRINT "ERROR: EXIT FOR condition failed" : END
340 PRINT "PASS: Found K = 8"
350 PRINT ""
360 REM Test 4: EXIT DO - WHILE loop
370 LET N% = 0
380 DO WHILE N% < 100
390     N% = N% + 1
400     IF N% = 7 THEN EXIT DO
410 LOOP
420 PRINT "Exit DO WHILE at 7, N = "; N%
430 IF N% <> 7 THEN PRINT "ERROR: EXIT DO WHILE failed" : END
440 PRINT "PASS: EXIT DO WHILE at 7"
450 PRINT ""
460 REM Test 5: EXIT DO - UNTIL loop
470 LET M% = 0
480 DO
490     M% = M% + 1
500     IF M% = 3 THEN EXIT DO
510 LOOP UNTIL M% > 10
520 PRINT "Exit DO UNTIL at 3, M = "; M%
530 IF M% <> 3 THEN PRINT "ERROR: EXIT DO UNTIL failed" : END
540 PRINT "PASS: EXIT DO UNTIL at 3"
550 PRINT ""
560 REM Test 6: EXIT FOR - nested loops (exit inner)
570 LET OUTER% = 0
580 LET INNER% = 0
590 FOR A% = 1 TO 3
600     OUTER% = OUTER% + 1
610     FOR B% = 1 TO 5
620         INNER% = INNER% + 1
630         IF B% = 2 THEN EXIT FOR
640     NEXT B%
650 NEXT A%
660 PRINT "Nested: OUTER = "; OUTER%; ", INNER = "; INNER%
670 IF OUTER% <> 3 THEN PRINT "ERROR: Outer count wrong" : END
680 IF INNER% <> 6 THEN PRINT "ERROR: Inner count wrong (expected 6)" : END
690 PRINT "PASS: Nested EXIT FOR (inner only)"
700 PRINT ""
710 REM Test 7: EXIT FOR at first iteration
720 LET FIRST% = 0
730 FOR X% = 1 TO 10
740     FIRST% = X%
750     EXIT FOR
760 NEXT X%
770 PRINT "Exit at first iteration: "; FIRST%
780 IF FIRST% <> 1 THEN PRINT "ERROR: First iteration exit failed" : END
790 PRINT "PASS: Exit at first iteration"
800 PRINT ""
810 REM Test 8: Multiple EXIT conditions
820 LET VAL% = 0
830 FOR Y% = 1 TO 20
840     IF Y% = 5 THEN EXIT FOR
850     IF Y% = 10 THEN EXIT FOR
860     VAL% = Y%
870 NEXT Y%
880 PRINT "Multiple EXIT conditions, VAL = "; VAL%
890 IF VAL% <> 4 THEN PRINT "ERROR: Multiple EXIT failed" : END
900 PRINT "PASS: First EXIT triggered at 5"
910 PRINT ""
920 REM Test 9: EXIT DO - infinite loop protection
930 LET SAFETY% = 0
940 DO
950     SAFETY% = SAFETY% + 1
960     IF SAFETY% > 5 THEN EXIT DO
970 LOOP
980 PRINT "Safety exit at "; SAFETY%
990 IF SAFETY% <> 6 THEN PRINT "ERROR: Safety exit failed" : END
1000 PRINT "PASS: Safety exit at 6"
1010 PRINT ""
1020 REM Test 10: EXIT FOR with STEP
1030 LET STEP_COUNT% = 0
1040 FOR Z% = 10 TO 1 STEP -2
1050     STEP_COUNT% = STEP_COUNT% + 1
1060     IF Z% <= 4 THEN EXIT FOR
1070 NEXT Z%
1080 PRINT "Exit FOR with STEP, count = "; STEP_COUNT%
1090 IF STEP_COUNT% <> 4 THEN PRINT "ERROR: EXIT with STEP failed" : END
1100 PRINT "PASS: EXIT FOR with STEP = 4"
1110 PRINT ""
1120 PRINT "=== All EXIT Statements Tests PASSED ==="
1130 END
