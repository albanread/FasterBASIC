10 REM Test: Basic Double/Floating-Point Arithmetic Operations
20 REM Tests: +, -, *, / with DOUBLE types
30 PRINT "=== Double Arithmetic Tests ==="
40 PRINT ""
50 REM Addition
60 LET A# = 10.5
70 LET B# = 20.3
80 LET C# = A# + B#
90 PRINT "10.5 + 20.3 = "; C#
100 IF C# < 30.79 OR C# > 30.81 THEN PRINT "ERROR: Addition failed" : END
110 PRINT "PASS: Addition"
120 PRINT ""
130 REM Subtraction
140 LET D# = 50.7
150 LET E# = 25.2
160 LET F# = D# - E#
170 PRINT "50.7 - 25.2 = "; F#
180 IF F# < 25.49 OR F# > 25.51 THEN PRINT "ERROR: Subtraction failed" : END
190 PRINT "PASS: Subtraction"
200 PRINT ""
210 REM Multiplication
220 LET G# = 7.5
230 LET H# = 8.0
240 LET I# = G# * H#
250 PRINT "7.5 * 8.0 = "; I#
260 IF I# < 59.9 OR I# > 60.1 THEN PRINT "ERROR: Multiplication failed" : END
270 PRINT "PASS: Multiplication"
280 PRINT ""
290 REM Division
300 LET J# = 100.0
310 LET K# = 4.0
320 LET L# = J# / K#
330 PRINT "100.0 / 4.0 = "; L#
340 IF L# < 24.9 OR L# > 25.1 THEN PRINT "ERROR: Division failed" : END
350 PRINT "PASS: Division"
360 PRINT ""
370 REM Division with result
380 LET M# = 17.0
390 LET N# = 5.0
400 LET O# = M# / N#
410 PRINT "17.0 / 5.0 = "; O#
420 IF O# < 3.39 OR O# > 3.41 THEN PRINT "ERROR: Float division failed" : END
430 PRINT "PASS: Float Division"
440 PRINT ""
450 REM Negative numbers
460 LET P# = -10.5
470 LET Q# = 5.2
480 LET R# = P# + Q#
490 PRINT "-10.5 + 5.2 = "; R#
500 IF R# < -5.31 OR R# > -5.29 THEN PRINT "ERROR: Negative addition failed" : END
510 PRINT "PASS: Negative Numbers"
520 PRINT ""
530 REM Very small numbers
540 LET S# = 0.001
550 LET T# = 0.002
560 LET U# = S# + T#
570 PRINT "0.001 + 0.002 = "; U#
580 IF U# < 0.0029 OR U# > 0.0031 THEN PRINT "ERROR: Small number addition failed" : END
590 PRINT "PASS: Small Numbers"
600 PRINT ""
610 REM Mixed operations
620 LET V# = 2.0 + 3.0 * 4.0
630 PRINT "2.0 + 3.0 * 4.0 = "; V#; " (precedence test)"
640 IF V# < 13.9 OR V# > 14.1 THEN PRINT "ERROR: Operator precedence failed" : END
650 PRINT "PASS: Operator Precedence"
660 PRINT ""
670 PRINT "=== All Double Arithmetic Tests PASSED ==="
680 END
