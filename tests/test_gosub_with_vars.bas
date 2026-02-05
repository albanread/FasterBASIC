10 REM Test GOSUB with variable scope after END
20 DIM x AS INTEGER
30 DIM y AS INTEGER
40 DIM result AS INTEGER
50 x = 5
60 y = 10
70 PRINT "Main: x="; x; " y="; y
80 GOSUB 1000
90 PRINT "Main: result="; result
100 END
1000 REM Subroutine: Add x and y
1010 PRINT "Sub: x="; x; " y="; y
1020 result = x + y
1030 PRINT "Sub: result="; result
1040 FOR x = 1 TO 3
1050   PRINT "  Loop iteration x="; x
1060 NEXT x
1070 PRINT "Sub: After loop, x="; x
1080 RETURN
