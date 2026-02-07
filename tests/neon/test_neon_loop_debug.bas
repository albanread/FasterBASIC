10 REM Minimal NEON loop vectorization debug test
20 TYPE Vec4
30   X AS INTEGER
40   Y AS INTEGER
50   Z AS INTEGER
60   W AS INTEGER
70 END TYPE
80 DIM A(4) AS Vec4
90 DIM B(4) AS Vec4
100 DIM C(4) AS Vec4
110 REM Initialize
120 FOR i% = 0 TO 4
130   A(i%).X = 10 : A(i%).Y = 20 : A(i%).Z = 30 : A(i%).W = 40
140   B(i%).X = 1  : B(i%).Y = 2  : B(i%).Z = 3  : B(i%).W = 4
150 NEXT i%
160 REM This loop should be NEON vectorized
170 FOR i% = 0 TO 4
180   C(i%) = A(i%) + B(i%)
190 NEXT i%
200 REM Check each element
210 PRINT "C(0): "; C(0).X; ","; C(0).Y; ","; C(0).Z; ","; C(0).W
220 PRINT "C(1): "; C(1).X; ","; C(1).Y; ","; C(1).Z; ","; C(1).W
230 PRINT "C(2): "; C(2).X; ","; C(2).Y; ","; C(2).Z; ","; C(2).W
240 PRINT "C(3): "; C(3).X; ","; C(3).Y; ","; C(3).Z; ","; C(3).W
250 PRINT "C(4): "; C(4).X; ","; C(4).Y; ","; C(4).Z; ","; C(4).W
260 IF C(0).X = 11 AND C(0).Y = 22 AND C(0).Z = 33 AND C(0).W = 44 THEN PRINT "E0 PASS" ELSE PRINT "E0 FAIL"
270 IF C(1).X = 11 AND C(1).Y = 22 AND C(1).Z = 33 AND C(1).W = 44 THEN PRINT "E1 PASS" ELSE PRINT "E1 FAIL"
280 IF C(2).X = 11 AND C(2).Y = 22 AND C(2).Z = 33 AND C(2).W = 44 THEN PRINT "E2 PASS" ELSE PRINT "E2 FAIL"
290 IF C(3).X = 11 AND C(3).Y = 22 AND C(3).Z = 33 AND C(3).W = 44 THEN PRINT "E3 PASS" ELSE PRINT "E3 FAIL"
300 IF C(4).X = 11 AND C(4).Y = 22 AND C(4).Z = 33 AND C(4).W = 44 THEN PRINT "E4 PASS" ELSE PRINT "E4 FAIL"
310 PRINT "Debug test complete."
320 END
