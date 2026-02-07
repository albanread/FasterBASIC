10 REM Test: Whole-array expression - element-wise addition (SINGLE)
20 REM Tests C() = A() + B() for SINGLE arrays
30 REM Verifies NEON vectorized path and scalar remainder handling
40 DIM A(10) AS SINGLE
50 DIM B(10) AS SINGLE
60 DIM C(10) AS SINGLE
70 REM === Initialize source arrays ===
80 FOR i% = 0 TO 10
90   A(i%) = i% * 1.5
100   B(i%) = i% * 0.5
110 NEXT i%
120 REM === Whole-array add ===
130 C() = A() + B()
140 REM === Verify results ===
150 DIM pass% AS INTEGER
160 pass% = 1
170 FOR i% = 0 TO 10
180   IF C(i%) <> A(i%) + B(i%) THEN
190     PRINT "FAIL at index "; i%; ": got "; C(i%); " expected "; A(i%) + B(i%)
200     pass% = 0
210   ENDIF
220 NEXT i%
230 IF pass% = 1 THEN PRINT "PASS: array add SINGLE"
240 REM === Test 2: Verify source arrays unchanged ===
250 IF A(5) = 7.5 AND B(5) = 2.5 THEN PRINT "PASS: sources intact" ELSE PRINT "FAIL: sources modified"
260 REM === Test 3: In-place add A() = A() + B() ===
270 A() = A() + B()
280 DIM pass2% AS INTEGER
290 pass2% = 1
300 FOR i% = 0 TO 10
310   IF A(i%) <> i% * 1.5 + i% * 0.5 THEN
320     PRINT "FAIL inplace at index "; i%
330     pass2% = 0
340   ENDIF
350 NEXT i%
360 IF pass2% = 1 THEN PRINT "PASS: in-place add"
370 REM === Test 4: Non-multiple-of-4 length (remainder test) ===
380 REM Array has 11 elements (0..10), 11 SINGLE = 44 bytes
390 REM NEON processes 4 per iteration = 40 bytes, remainder = 1 element
400 REM Verify last elements are correct
410 IF C(9) <> 9.0 * 1.5 + 9.0 * 0.5 THEN PRINT "FAIL: remainder elem 9" ELSE PRINT "PASS: remainder elem 9"
420 IF C(10) <> 10.0 * 1.5 + 10.0 * 0.5 THEN PRINT "FAIL: remainder elem 10" ELSE PRINT "PASS: remainder elem 10"
430 PRINT "Array expression add tests complete."
440 END
