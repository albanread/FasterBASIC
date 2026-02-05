10 REM Test 2D arrays in GOSUB subroutines after END
20 REM This isolates the Levenshtein failure pattern
30 DIM matrix(3, 3) AS INTEGER
40 PRINT "Main program: initializing matrix"
50 matrix(0, 0) = 1
60 matrix(0, 1) = 2
70 matrix(1, 0) = 3
80 matrix(1, 1) = 4
90 PRINT "Before GOSUB:"
100 PRINT "matrix(0,0) = "; matrix(0, 0)
110 PRINT "matrix(1,1) = "; matrix(1, 1)
120 GOSUB 1000
130 PRINT "After GOSUB:"
140 PRINT "matrix(0,0) = "; matrix(0, 0); " (expect 100)"
150 PRINT "matrix(1,1) = "; matrix(1, 1); " (expect 400)"
160 PRINT "matrix(2,2) = "; matrix(2, 2); " (expect 99)"
170 END
1000 REM Subroutine at line 1000
1010 PRINT "In subroutine 1000"
1020 DIM i AS INTEGER
1030 DIM j AS INTEGER
1040 REM Modify existing values
1050 matrix(0, 0) = matrix(0, 0) * 100
1055 PRINT "After mult: matrix(0,0) = "; matrix(0, 0)
1060 matrix(1, 1) = matrix(1, 1) * 100
1065 PRINT "After mult: matrix(1,1) = "; matrix(1, 1)
1070 REM Set new values using loop
1075 PRINT "Before loop: matrix(0,0) = "; matrix(0, 0); " matrix(1,1) = "; matrix(1, 1)
1080 FOR i = 0 TO 2
1090     FOR j = 0 TO 2
1095         PRINT "Loop: i="; i; " j="; j; " i=j="; (i=j); " i=2="; (i=2)
1100         IF i = j AND i = 2 THEN matrix(i, j) = 99
1105         PRINT "  matrix("; i; ","; j; ")="; matrix(i, j)
1110     NEXT j
1120 NEXT i
1130 PRINT "Subroutine done"
1140 RETURN
