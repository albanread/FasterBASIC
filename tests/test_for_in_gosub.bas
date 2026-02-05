10 REM Test FOR loop in subroutine after END
20 DIM total AS INTEGER
30 total = 0
40 PRINT "Main: Calling subroutine"
50 GOSUB 1000
60 PRINT "Main: total = "; total
70 END
1000 REM Subroutine with FOR loop
1010 PRINT "Sub: Starting FOR loop"
1020 FOR i = 1 TO 5
1030   PRINT "  Sub: i = "; i
1040   total = total + i
1050 NEXT i
1060 PRINT "Sub: After loop, total = "; total
1070 RETURN
