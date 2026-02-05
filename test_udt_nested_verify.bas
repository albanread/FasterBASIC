10 REM Test: Nested UDT assignment with string verification
20 TYPE Address
30   Street AS STRING
40   Number AS INTEGER
50 END TYPE
60 TYPE Person
70   Name AS STRING
80   Age AS INTEGER
90   Addr AS Address
100 END TYPE
110 DIM P1 AS Person
120 DIM P2 AS Person
130 REM Set up P1 with nested data
140 P1.Name = "Alice"
150 P1.Age = 30
160 P1.Addr.Street = "Main St"
170 P1.Addr.Number = 123
180 REM Copy P1 to P2
190 P2 = P1
200 REM Test that P2 got the correct values
210 IF P2.Name = "Alice" THEN PRINT "P2.Name: PASS" ELSE PRINT "P2.Name: FAIL"
220 IF P2.Age = 30 THEN PRINT "P2.Age: PASS" ELSE PRINT "P2.Age: FAIL"
230 IF P2.Addr.Street = "Main St" THEN PRINT "P2.Addr.Street: PASS" ELSE PRINT "P2.Addr.Street: FAIL"
240 IF P2.Addr.Number = 123 THEN PRINT "P2.Addr.Number: PASS" ELSE PRINT "P2.Addr.Number: FAIL"
250 REM Modify P2 to test independence
260 P2.Name = "Bob"
270 P2.Age = 25
280 P2.Addr.Street = "Oak Ave"
290 P2.Addr.Number = 456
300 REM Verify P1 is unchanged
310 IF P1.Name = "Alice" THEN PRINT "P1.Name unchanged: PASS" ELSE PRINT "P1.Name unchanged: FAIL"
320 IF P1.Age = 30 THEN PRINT "P1.Age unchanged: PASS" ELSE PRINT "P1.Age unchanged: FAIL"
330 IF P1.Addr.Street = "Main St" THEN PRINT "P1.Addr.Street unchanged: PASS" ELSE PRINT "P1.Addr.Street unchanged: FAIL"
340 IF P1.Addr.Number = 123 THEN PRINT "P1.Addr.Number unchanged: PASS" ELSE PRINT "P1.Addr.Number unchanged: FAIL"
350 REM Verify P2 has new values
360 IF P2.Name = "Bob" THEN PRINT "P2.Name modified: PASS" ELSE PRINT "P2.Name modified: FAIL"
370 IF P2.Age = 25 THEN PRINT "P2.Age modified: PASS" ELSE PRINT "P2.Age modified: FAIL"
380 IF P2.Addr.Street = "Oak Ave" THEN PRINT "P2.Addr.Street modified: PASS" ELSE PRINT "P2.Addr.Street modified: FAIL"
390 IF P2.Addr.Number = 456 THEN PRINT "P2.Addr.Number modified: PASS" ELSE PRINT "P2.Addr.Number modified: FAIL"
400 END
