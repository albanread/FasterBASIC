10 REM Test: OPTION DETECTSTRING - automatic string type detection
20 OPTION DETECTSTRING
30 REM ASCII string (all chars < 128)
40 LET A$ = "Hello World"
50 REM Unicode string (contains emoji)
60 LET B$ = "Hello 🌍"
70 REM Another ASCII string
80 LET C$ = "Testing 123"
90 PRINT "ASCII: "; A$
100 PRINT "Unicode: "; B$
110 PRINT "ASCII: "; C$
120 IF LEN(A$) > 0 AND LEN(B$) > 0 AND LEN(C$) > 0 THEN PRINT "PASS" ELSE PRINT "FAIL"
130 END
