10 REM Test: Basic String Operations
20 PRINT "=== String Operations Tests ==="
30 REM Test 1: String assignment
40 LET A$ = "Hello"
50 PRINT "A$ = "; A$
60 IF A$ <> "Hello" THEN PRINT "ERROR: String assignment failed" : END
70 PRINT "PASS: String assignment"
80 PRINT ""
90 REM Test 2: String concatenation
100 LET B$ = "Hello"
110 LET C$ = "World"
120 LET D$ = B$ + " " + C$
130 PRINT "Concatenation: "; D$
140 IF D$ <> "Hello World" THEN PRINT "ERROR: Concatenation failed" : END
150 PRINT "PASS: Concatenation"
160 PRINT ""
170 REM Test 3: Empty string
180 LET E$ = ""
190 PRINT "Empty string length: "; LEN(E$)
200 IF LEN(E$) <> 0 THEN PRINT "ERROR: Empty string failed" : END
210 PRINT "PASS: Empty string"
220 PRINT ""
230 REM Test 4: String comparison
240 LET F$ = "ABC"
250 LET G$ = "ABC"
260 LET H$ = "XYZ"
270 IF F$ = G$ THEN PRINT "PASS: ABC = ABC" ELSE PRINT "ERROR: String equality failed" : END
280 IF F$ <> H$ THEN PRINT "PASS: ABC <> XYZ" ELSE PRINT "ERROR: String inequality failed" : END
290 PRINT "=== All String Tests PASSED ==="
300 END
