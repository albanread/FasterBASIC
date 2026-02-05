10 PRINT "Testing simple SUB"
CALL test_abs_basic()
30 PRINT "Done"
40 END
50
60 SUB test_abs_basic()
70   LOCAL i AS INTEGER
80   PRINT "In SUB"
90   i = -5
100   PRINT "ABS(-5) = "; ABS(i)
110   IF ABS(i) <> 5 THEN
120     PRINT "ERROR: Expected 5"
130     EXIT SUB
140   END IF
150   PRINT "PASS"
160 END SUB
