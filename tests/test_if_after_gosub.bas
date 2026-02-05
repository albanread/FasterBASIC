10 REM Test IF statement after GOSUB to code after END
20 DIM result AS INTEGER
30 result = 0
40 PRINT "Main: Before GOSUB"
50 GOSUB 1000
60 PRINT "Main: result = "; result
70 IF result = 5 THEN
80     PRINT "  PASS: result is 5"
90 ELSE
100     PRINT "  FAIL: result is "; result; ", expected 5"
110 END IF
120 END
1000 REM Subroutine that sets result
1010 PRINT "Sub: Setting result to 5"
1020 result = 5
1030 PRINT "Sub: result = "; result
1040 RETURN
