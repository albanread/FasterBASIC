10 REM Test GOSUB to line 2000 after END
20 PRINT "Main: Before GOSUB"
30 GOSUB 2000
40 PRINT "Main: After GOSUB"
50 END
2000 REM Subroutine at line 2000
2010 PRINT "Subroutine: Inside line 2000"
2020 RETURN
