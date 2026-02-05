10 REM Test: String Functions
20 PRINT "=== String Function Tests ==="
30 REM Test 1: LEN function
40 LET A$ = "Hello"
50 LET L% = LEN(A$)
60 PRINT "LEN(\"Hello\") = "; L%
70 IF L% <> 5 THEN PRINT "ERROR: LEN failed" : END
80 PRINT "PASS: LEN"
90 PRINT ""
100 REM Test 2: LEFT$ function
110 LET B$ = "FasterBASIC"
120 LET C$ = LEFT$(B$, 6)
130 PRINT "LEFT$(\"FasterBASIC\", 6) = "; C$
140 IF C$ <> "Faster" THEN PRINT "ERROR: LEFT$ failed" : END
150 PRINT "PASS: LEFT$"
160 PRINT ""
170 REM Test 3: RIGHT$ function
180 LET D$ = RIGHT$(B$, 5)
190 PRINT "RIGHT$(\"FasterBASIC\", 5) = "; D$
200 IF D$ <> "BASIC" THEN PRINT "ERROR: RIGHT$ failed" : END
210 PRINT "PASS: RIGHT$"
220 PRINT ""
230 REM Test 4: MID$ function
240 LET E$ = MID$(B$, 7, 5)
250 PRINT "MID$(\"FasterBASIC\", 7, 5) = "; E$
260 IF E$ <> "BASIC" THEN PRINT "ERROR: MID$ failed" : END
270 PRINT "PASS: MID$"
280 PRINT ""
290 REM Test 5: CHR$ function
300 LET F$ = CHR$(65)
310 PRINT "CHR$(65) = "; F$
320 IF F$ <> "A" THEN PRINT "ERROR: CHR$ failed" : END
330 PRINT "PASS: CHR$"
340 PRINT ""
350 REM Test 6: ASC function
360 LET G$ = "A"
370 LET H% = ASC(G$)
380 PRINT "ASC(\"A\") = "; H%
390 IF H% <> 65 THEN PRINT "ERROR: ASC failed" : END
400 PRINT "PASS: ASC"
410 PRINT "=== All String Function Tests PASSED ==="
420 END
