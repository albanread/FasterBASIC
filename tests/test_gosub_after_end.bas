10 REM Test GOSUB to subroutine after END
20 PRINT "Main program start"
30 GOSUB 1000
40 PRINT "Back from subroutine"
50 END
1000 REM Subroutine starts here
1010 PRINT "In subroutine at line 1000"
1020 RETURN
