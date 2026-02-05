10 REM Test to verify loop indices are correct
20 DIM arr(2, 2) AS INTEGER
30 DIM i AS INTEGER
40 DIM j AS INTEGER
50 REM Initialize array with known pattern
60 arr(0, 0) = 100
70 arr(0, 1) = 101
80 arr(0, 2) = 102
90 arr(1, 0) = 110
100 arr(1, 1) = 111
110 arr(1, 2) = 112
120 arr(2, 0) = 120
130 arr(2, 1) = 121
140 arr(2, 2) = 122
150 REM Now loop and verify
160 FOR i = 0 TO 2
170     FOR j = 0 TO 2
180         PRINT "i="; i; " j="; j; " arr(i,j)="; arr(i, j)
190         REM Manually check specific cases
200         IF i = 0 AND j = 0 THEN PRINT "  Should be 100, is "; arr(i, j)
210         IF i = 1 AND j = 1 THEN PRINT "  Should be 111, is "; arr(i, j)
220         IF i = 2 AND j = 2 THEN PRINT "  Should be 122, is "; arr(i, j)
230     NEXT j
240 NEXT i
250 END
