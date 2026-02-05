10 REM Test: UDT assignment with nested UDTs
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
180 PRINT "Before assignment:"
190 PRINT "P1: "; P1.Name; ", Age "; P1.Age; ", Lives at "; P1.Addr.Street; " #"; P1.Addr.Number
200 PRINT "P2: "; P2.Name; ", Age "; P2.Age; ", Lives at "; P2.Addr.Street; " #"; P2.Addr.Number
210 REM Assign P1 to P2 (whole struct copy including nested UDT)
220 P2 = P1
230 PRINT "After P2 = P1:"
240 PRINT "P1: "; P1.Name; ", Age "; P1.Age; ", Lives at "; P1.Addr.Street; " #"; P1.Addr.Number
250 PRINT "P2: "; P2.Name; ", Age "; P2.Age; ", Lives at "; P2.Addr.Street; " #"; P2.Addr.Number
260 REM Modify P2 to verify independence
270 P2.Name = "Bob"
280 P2.Age = 25
290 P2.Addr.Street = "Oak Ave"
300 P2.Addr.Number = 456
310 PRINT "After modifying P2:"
320 PRINT "P1: "; P1.Name; ", Age "; P1.Age; ", Lives at "; P1.Addr.Street; " #"; P1.Addr.Number
330 PRINT "P2: "; P2.Name; ", Age "; P2.Age; ", Lives at "; P2.Addr.Street; " #"; P2.Addr.Number
340 REM Verify correct values
350 IF P1.Name = "Alice" AND P1.Age = 30 AND P1.Addr.Street = "Main St" AND P1.Addr.Number = 123 THEN PRINT "P1 PASS" ELSE PRINT "P1 FAIL"
360 IF P2.Name = "Bob" AND P2.Age = 25 AND P2.Addr.Street = "Oak Ave" AND P2.Addr.Number = 456 THEN PRINT "P2 PASS" ELSE PRINT "P2 FAIL"
370 END
