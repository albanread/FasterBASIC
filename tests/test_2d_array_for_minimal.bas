10 REM Minimal test to isolate array corruption in FOR loop
20 DIM arr(2, 2) AS INTEGER
30 arr(0, 0) = 100
40 arr(1, 1) = 200
50 PRINT "Before loop: arr(0,0)="; arr(0, 0); " arr(1,1)="; arr(1, 1)
60 DIM i AS INTEGER
70 DIM j AS INTEGER
80 FOR i = 0 TO 2
90     PRINT "Start of loop iteration i="; i; " arr(0,0)="; arr(0, 0); " arr(1,1)="; arr(1, 1)
100     FOR j = 0 TO 2
110         PRINT "  Inner loop j="; j; " arr("; i; ","; j; ")="; arr(i, j)
120     NEXT j
130 NEXT i
140 PRINT "After loop: arr(0,0)="; arr(0, 0); " arr(1,1)="; arr(1, 1)
150 END
