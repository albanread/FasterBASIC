10 REM Test: Whole-array expression - subtraction, multiplication, division
20 REM Tests all four arithmetic operations for SINGLE arrays
30 REM Verifies NEON vectorized path and scalar remainder handling
40 DIM A(12) AS SINGLE
50 DIM B(12) AS SINGLE
60 DIM C(12) AS SINGLE
70 REM === Initialize source arrays ===
80 FOR i% = 0 TO 12
90   A(i%) = (i% + 1) * 10.0
100   B(i%) = (i% + 1) * 2.0
110 NEXT i%
120 REM ============================================================
130 REM Test 1: Subtraction C() = A() - B()
140 REM ============================================================
150 C() = A() - B()
160 DIM pass% AS INTEGER
170 pass% = 1
180 FOR i% = 0 TO 12
190   IF C(i%) <> A(i%) - B(i%) THEN
200     PRINT "FAIL sub at index "; i%; ": got "; C(i%); " expected "; A(i%) - B(i%)
210     pass% = 0
220   ENDIF
230 NEXT i%
240 IF pass% = 1 THEN PRINT "PASS: array subtract SINGLE" ELSE PRINT "FAIL: array subtract SINGLE"
250 REM ============================================================
260 REM Test 2: Multiplication C() = A() * B()
270 REM ============================================================
280 C() = A() * B()
290 pass% = 1
300 FOR i% = 0 TO 12
310   IF C(i%) <> A(i%) * B(i%) THEN
320     PRINT "FAIL mul at index "; i%; ": got "; C(i%); " expected "; A(i%) * B(i%)
330     pass% = 0
340   ENDIF
350 NEXT i%
360 IF pass% = 1 THEN PRINT "PASS: array multiply SINGLE" ELSE PRINT "FAIL: array multiply SINGLE"
370 REM ============================================================
380 REM Test 3: Division C() = A() / B()
390 REM ============================================================
400 C() = A() / B()
410 pass% = 1
420 FOR i% = 0 TO 12
430   IF C(i%) <> A(i%) / B(i%) THEN
440     PRINT "FAIL div at index "; i%; ": got "; C(i%); " expected "; A(i%) / B(i%)
450     pass% = 0
460   ENDIF
470 NEXT i%
480 IF pass% = 1 THEN PRINT "PASS: array divide SINGLE" ELSE PRINT "FAIL: array divide SINGLE"
490 REM ============================================================
500 REM Test 4: Verify with INTEGER arrays (uses scalar fallback for div)
510 REM ============================================================
520 DIM AI(8) AS INTEGER
530 DIM BI(8) AS INTEGER
540 DIM CI(8) AS INTEGER
550 FOR i% = 0 TO 8
560   AI(i%) = (i% + 1) * 100
570   BI(i%) = (i% + 1) * 3
580 NEXT i%
590 REM Integer add
600 CI() = AI() + BI()
610 pass% = 1
620 FOR i% = 0 TO 8
630   IF CI(i%) <> AI(i%) + BI(i%) THEN
640     PRINT "FAIL int add at "; i%; ": got "; CI(i%)
650     pass% = 0
660   ENDIF
670 NEXT i%
680 IF pass% = 1 THEN PRINT "PASS: array add INTEGER" ELSE PRINT "FAIL: array add INTEGER"
690 REM Integer subtract
700 CI() = AI() - BI()
710 pass% = 1
720 FOR i% = 0 TO 8
730   IF CI(i%) <> AI(i%) - BI(i%) THEN
740     PRINT "FAIL int sub at "; i%; ": got "; CI(i%)
750     pass% = 0
760   ENDIF
770 NEXT i%
780 IF pass% = 1 THEN PRINT "PASS: array subtract INTEGER" ELSE PRINT "FAIL: array subtract INTEGER"
790 REM Integer multiply
800 CI() = AI() * BI()
810 pass% = 1
820 FOR i% = 0 TO 8
830   IF CI(i%) <> AI(i%) * BI(i%) THEN
840     PRINT "FAIL int mul at "; i%; ": got "; CI(i%)
850     pass% = 0
860   ENDIF
870 NEXT i%
880 IF pass% = 1 THEN PRINT "PASS: array multiply INTEGER" ELSE PRINT "FAIL: array multiply INTEGER"
890 REM ============================================================
900 REM Test 5: DOUBLE arrays
910 REM ============================================================
920 DIM AD(7) AS DOUBLE
930 DIM BD(7) AS DOUBLE
940 DIM CD(7) AS DOUBLE
950 FOR i% = 0 TO 7
960   AD(i%) = (i% + 1) * 1.111111
970   BD(i%) = (i% + 1) * 0.333333
980 NEXT i%
990 CD() = AD() + BD()
1000 pass% = 1
1010 FOR i% = 0 TO 7
1020   IF CD(i%) <> AD(i%) + BD(i%) THEN
1030     PRINT "FAIL double add at "; i%; ": got "; CD(i%)
1040     pass% = 0
1050   ENDIF
1060 NEXT i%
1070 IF pass% = 1 THEN PRINT "PASS: array add DOUBLE" ELSE PRINT "FAIL: array add DOUBLE"
1080 CD() = AD() - BD()
1090 pass% = 1
1100 FOR i% = 0 TO 7
1110   IF CD(i%) <> AD(i%) - BD(i%) THEN
1120     PRINT "FAIL double sub at "; i%; ": got "; CD(i%)
1130     pass% = 0
1140   ENDIF
1150 NEXT i%
1160 IF pass% = 1 THEN PRINT "PASS: array subtract DOUBLE" ELSE PRINT "FAIL: array subtract DOUBLE"
1170 CD() = AD() * BD()
1180 pass% = 1
1190 FOR i% = 0 TO 7
1200   IF CD(i%) <> AD(i%) * BD(i%) THEN
1210     PRINT "FAIL double mul at "; i%; ": got "; CD(i%)
1220     pass% = 0
1230   ENDIF
1240 NEXT i%
1250 IF pass% = 1 THEN PRINT "PASS: array multiply DOUBLE" ELSE PRINT "FAIL: array multiply DOUBLE"
1260 CD() = AD() / BD()
1270 pass% = 1
1280 FOR i% = 0 TO 7
1290   IF CD(i%) <> AD(i%) / BD(i%) THEN
1300     PRINT "FAIL double div at "; i%; ": got "; CD(i%)
1310     pass% = 0
1320   ENDIF
1330 NEXT i%
1340 IF pass% = 1 THEN PRINT "PASS: array divide DOUBLE" ELSE PRINT "FAIL: array divide DOUBLE"
1350 REM ============================================================
1360 REM Test 6: Same array on both sides A() = A() + A()
1370 REM ============================================================
1380 DIM D(5) AS SINGLE
1390 FOR i% = 0 TO 5
1400   D(i%) = i% + 1.0
1410 NEXT i%
1420 D() = D() + D()
1430 pass% = 1
1440 FOR i% = 0 TO 5
1450   IF D(i%) <> (i% + 1.0) * 2.0 THEN
1460     PRINT "FAIL self-add at "; i%; ": got "; D(i%); " expected "; (i% + 1.0) * 2.0
1470     pass% = 0
1480   ENDIF
1490 NEXT i%
1500 IF pass% = 1 THEN PRINT "PASS: self-add A() = A() + A()" ELSE PRINT "FAIL: self-add"
1510 PRINT "Array expression arithmetic tests complete."
1520 END
