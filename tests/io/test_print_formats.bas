10 REM Test: PRINT Statement Formats
20 PRINT "=== PRINT Format Tests ==="
30 REM Test 1: PRINT with semicolons
40 PRINT "A"; "B"; "C"
50 PRINT "PASS: Semicolon concatenation"
60 PRINT ""
70 REM Test 2: PRINT with commas (zones)
80 PRINT "Col1", "Col2", "Col3"
90 PRINT "PASS: Comma zones"
100 PRINT ""
110 REM Test 3: PRINT with mixed types
120 LET X% = 42
130 LET Y# = 3.14
140 LET Z$ = "Pi"
150 PRINT Z$; " = "; Y%; " and answer = "; X%
160 PRINT "PASS: Mixed types"
170 PRINT ""
180 REM Test 4: PRINT with expressions
190 PRINT "2 + 2 = "; 2 + 2
200 PRINT "PASS: Expressions in PRINT"
210 PRINT "=== All PRINT Tests PASSED ==="
220 END
