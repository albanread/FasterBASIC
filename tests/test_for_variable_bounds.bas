10 REM Test FOR loop with variable bounds in subroutine after END
20 DIM n AS INTEGER
30 DIM sum AS INTEGER
40 n = 5
50 sum = 0
60 PRINT "Main: n = "; n; ", sum = "; sum
70 GOSUB 1000
80 PRINT "Main: After GOSUB, sum = "; sum
90 END
1000 REM Subroutine: Sum from 0 to n
1010 PRINT "Sub: Starting loop from 0 TO "; n
1020 FOR i = 0 TO n
1030   PRINT "  Sub: i = "; i
1040   sum = sum + i
1050 NEXT i
1060 PRINT "Sub: After loop, sum = "; sum
1070 RETURN
