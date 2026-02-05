10 REM Minimal test for AND condition evaluation
20 DIM i AS INTEGER
30 DIM j AS INTEGER
40 i = 0
50 j = 0
60 PRINT "i="; i; " j="; j
70 PRINT "Testing: i = 0 AND j = 0"
80 IF i = 0 AND j = 0 THEN PRINT "  TRUE (correct)"
90 PRINT "Testing: i = 1 AND j = 1"
100 IF i = 1 AND j = 1 THEN PRINT "  TRUE (WRONG!)"
110 PRINT "Testing: i = 2 AND j = 2"
120 IF i = 2 AND j = 2 THEN PRINT "  TRUE (WRONG!)"
130 PRINT "Testing individual conditions:"
140 IF i = 0 THEN PRINT "  i = 0 is TRUE (correct)"
150 IF j = 0 THEN PRINT "  j = 0 is TRUE (correct)"
160 IF i = 1 THEN PRINT "  i = 1 is TRUE (WRONG!)"
170 IF j = 1 THEN PRINT "  j = 1 is TRUE (WRONG!)"
180 END
