10 REM Comprehensive UDT test covering multiple features
20 REM Tests: basic fields, nested UDTs, string fields, arrays of UDTs,
30 REM        UDT-to-UDT assignment, assignment from array element,
40 REM        assignment from nested member, independence after copy
50 REM
100 REM === Section 1: Basic UDT with multiple field types ===
110 TYPE Vector
120   X AS DOUBLE
130   Y AS DOUBLE
140   Z AS DOUBLE
150 END TYPE
160 DIM V AS Vector
170 V.X = 1.5
180 V.Y = 2.5
190 V.Z = 3.5
200 IF V.X > 1.4 AND V.X < 1.6 THEN PRINT "1.1 Basic double field X: PASS" ELSE PRINT "1.1 Basic double field X: FAIL"
210 IF V.Y > 2.4 AND V.Y < 2.6 THEN PRINT "1.2 Basic double field Y: PASS" ELSE PRINT "1.2 Basic double field Y: FAIL"
220 IF V.Z > 3.4 AND V.Z < 3.6 THEN PRINT "1.3 Basic double field Z: PASS" ELSE PRINT "1.3 Basic double field Z: FAIL"
230 REM
300 REM === Section 2: UDT with mixed types ===
310 TYPE Employee
320   Name AS STRING
330   Age AS INTEGER
340   Salary AS DOUBLE
350 END TYPE
360 DIM E AS Employee
370 E.Name = "Alice"
380 E.Age = 30
390 E.Salary = 75000.50
400 IF E.Name = "Alice" THEN PRINT "2.1 String field: PASS" ELSE PRINT "2.1 String field: FAIL"
410 IF E.Age = 30 THEN PRINT "2.2 Integer field: PASS" ELSE PRINT "2.2 Integer field: FAIL"
420 IF E.Salary > 75000.0 AND E.Salary < 75001.0 THEN PRINT "2.3 Double field: PASS" ELSE PRINT "2.3 Double field: FAIL"
430 REM
500 REM === Section 3: Nested UDT ===
510 TYPE Address
520   Street AS STRING
530   City AS STRING
540   ZipCode AS INTEGER
550 END TYPE
560 TYPE Contact
570   Person AS Employee
580   Home AS Address
590 END TYPE
600 DIM C AS Contact
610 C.Person.Name = "Bob"
620 C.Person.Age = 25
630 C.Person.Salary = 50000.0
640 C.Home.Street = "123 Main St"
650 C.Home.City = "Springfield"
660 C.Home.ZipCode = 62704
670 IF C.Person.Name = "Bob" THEN PRINT "3.1 Nested string field: PASS" ELSE PRINT "3.1 Nested string field: FAIL"
680 IF C.Person.Age = 25 THEN PRINT "3.2 Nested integer field: PASS" ELSE PRINT "3.2 Nested integer field: FAIL"
690 IF C.Home.Street = "123 Main St" THEN PRINT "3.3 Nested address street: PASS" ELSE PRINT "3.3 Nested address street: FAIL"
700 IF C.Home.City = "Springfield" THEN PRINT "3.4 Nested address city: PASS" ELSE PRINT "3.4 Nested address city: FAIL"
710 IF C.Home.ZipCode = 62704 THEN PRINT "3.5 Nested address zip: PASS" ELSE PRINT "3.5 Nested address zip: FAIL"
720 REM
800 REM === Section 4: Array of UDTs ===
810 DIM Points(3) AS Vector
820 Points(0).X = 0.0
830 Points(0).Y = 0.0
840 Points(0).Z = 0.0
850 Points(1).X = 1.0
860 Points(1).Y = 2.0
870 Points(1).Z = 3.0
880 Points(2).X = 10.0
890 Points(2).Y = 20.0
900 Points(2).Z = 30.0
910 IF Points(0).X < 0.1 THEN PRINT "4.1 Array(0) field: PASS" ELSE PRINT "4.1 Array(0) field: FAIL"
920 IF Points(1).Y > 1.9 AND Points(1).Y < 2.1 THEN PRINT "4.2 Array(1) field: PASS" ELSE PRINT "4.2 Array(1) field: FAIL"
930 IF Points(2).Z > 29.9 AND Points(2).Z < 30.1 THEN PRINT "4.3 Array(2) field: PASS" ELSE PRINT "4.3 Array(2) field: FAIL"
940 REM
1000 REM === Section 5: UDT-to-UDT assignment (simple) ===
1010 DIM V2 AS Vector
1020 V2 = V
1030 IF V2.X > 1.4 AND V2.X < 1.6 THEN PRINT "5.1 Copy X: PASS" ELSE PRINT "5.1 Copy X: FAIL"
1040 IF V2.Y > 2.4 AND V2.Y < 2.6 THEN PRINT "5.2 Copy Y: PASS" ELSE PRINT "5.2 Copy Y: FAIL"
1050 IF V2.Z > 3.4 AND V2.Z < 3.6 THEN PRINT "5.3 Copy Z: PASS" ELSE PRINT "5.3 Copy Z: FAIL"
1060 REM Verify independence
1070 V2.X = 999.0
1080 IF V.X > 1.4 AND V.X < 1.6 THEN PRINT "5.4 Independence after copy: PASS" ELSE PRINT "5.4 Independence after copy: FAIL"
1090 REM
1100 REM === Section 6: UDT-to-UDT assignment with strings ===
1110 DIM E2 AS Employee
1120 E2 = E
1130 IF E2.Name = "Alice" THEN PRINT "6.1 String copy: PASS" ELSE PRINT "6.1 String copy: FAIL"
1140 IF E2.Age = 30 THEN PRINT "6.2 Int copy: PASS" ELSE PRINT "6.2 Int copy: FAIL"
1150 E2.Name = "Charlie"
1160 E2.Age = 40
1170 IF E.Name = "Alice" THEN PRINT "6.3 Original string unchanged: PASS" ELSE PRINT "6.3 Original string unchanged: FAIL"
1180 IF E.Age = 30 THEN PRINT "6.4 Original int unchanged: PASS" ELSE PRINT "6.4 Original int unchanged: FAIL"
1190 IF E2.Name = "Charlie" THEN PRINT "6.5 Modified copy string: PASS" ELSE PRINT "6.5 Modified copy string: FAIL"
1200 REM
1300 REM === Section 7: UDT assignment from array element ===
1310 DIM VP AS Vector
1320 VP = Points(2)
1330 IF VP.X > 9.9 AND VP.X < 10.1 THEN PRINT "7.1 Array elem copy X: PASS" ELSE PRINT "7.1 Array elem copy X: FAIL"
1340 IF VP.Y > 19.9 AND VP.Y < 20.1 THEN PRINT "7.2 Array elem copy Y: PASS" ELSE PRINT "7.2 Array elem copy Y: FAIL"
1350 IF VP.Z > 29.9 AND VP.Z < 30.1 THEN PRINT "7.3 Array elem copy Z: PASS" ELSE PRINT "7.3 Array elem copy Z: FAIL"
1360 REM Verify independence from array
1370 VP.X = 0.0
1380 IF Points(2).X > 9.9 AND Points(2).X < 10.1 THEN PRINT "7.4 Array independence: PASS" ELSE PRINT "7.4 Array independence: FAIL"
1390 REM
1500 REM === Section 8: Nested UDT assignment ===
1510 DIM C2 AS Contact
1520 C2 = C
1530 IF C2.Person.Name = "Bob" THEN PRINT "8.1 Nested copy name: PASS" ELSE PRINT "8.1 Nested copy name: FAIL"
1540 IF C2.Person.Age = 25 THEN PRINT "8.2 Nested copy age: PASS" ELSE PRINT "8.2 Nested copy age: FAIL"
1550 IF C2.Home.Street = "123 Main St" THEN PRINT "8.3 Nested copy street: PASS" ELSE PRINT "8.3 Nested copy street: FAIL"
1560 IF C2.Home.City = "Springfield" THEN PRINT "8.4 Nested copy city: PASS" ELSE PRINT "8.4 Nested copy city: FAIL"
1570 IF C2.Home.ZipCode = 62704 THEN PRINT "8.5 Nested copy zip: PASS" ELSE PRINT "8.5 Nested copy zip: FAIL"
1580 REM Modify copy and verify independence
1590 C2.Person.Name = "Diana"
1600 C2.Home.Street = "456 Oak Ave"
1610 C2.Home.ZipCode = 90210
1620 IF C.Person.Name = "Bob" THEN PRINT "8.6 Original nested name unchanged: PASS" ELSE PRINT "8.6 Original nested name unchanged: FAIL"
1630 IF C.Home.Street = "123 Main St" THEN PRINT "8.7 Original nested street unchanged: PASS" ELSE PRINT "8.7 Original nested street unchanged: FAIL"
1640 IF C2.Person.Name = "Diana" THEN PRINT "8.8 Modified nested copy name: PASS" ELSE PRINT "8.8 Modified nested copy name: FAIL"
1650 IF C2.Home.Street = "456 Oak Ave" THEN PRINT "8.9 Modified nested copy street: PASS" ELSE PRINT "8.9 Modified nested copy street: FAIL"
1660 REM
1700 REM === Section 9: Zero-initialization of UDT fields ===
1710 DIM Fresh AS Employee
1720 IF Fresh.Age = 0 THEN PRINT "9.1 Int field zero-init: PASS" ELSE PRINT "9.1 Int field zero-init: FAIL"
1730 REM
1800 REM === Section 10: Multiple assignments (chain copy) ===
1810 DIM A1 AS Vector
1820 DIM A2 AS Vector
1830 DIM A3 AS Vector
1840 A1.X = 11.0
1850 A1.Y = 22.0
1860 A1.Z = 33.0
1870 A2 = A1
1880 A3 = A2
1890 IF A3.X > 10.9 AND A3.X < 11.1 THEN PRINT "10.1 Chain copy X: PASS" ELSE PRINT "10.1 Chain copy X: FAIL"
1900 IF A3.Y > 21.9 AND A3.Y < 22.1 THEN PRINT "10.2 Chain copy Y: PASS" ELSE PRINT "10.2 Chain copy Y: FAIL"
1910 IF A3.Z > 32.9 AND A3.Z < 33.1 THEN PRINT "10.3 Chain copy Z: PASS" ELSE PRINT "10.3 Chain copy Z: FAIL"
1920 REM Verify all are independent
1930 A2.X = 0.0
1940 A3.Y = 0.0
1950 IF A1.X > 10.9 AND A1.X < 11.1 THEN PRINT "10.4 Chain independence A1: PASS" ELSE PRINT "10.4 Chain independence A1: FAIL"
1960 IF A1.Y > 21.9 AND A1.Y < 22.1 THEN PRINT "10.5 Chain independence A1.Y: PASS" ELSE PRINT "10.5 Chain independence A1.Y: FAIL"
1970 IF A2.X < 0.1 THEN PRINT "10.6 Modified A2: PASS" ELSE PRINT "10.6 Modified A2: FAIL"
1980 IF A3.Y < 0.1 THEN PRINT "10.7 Modified A3: PASS" ELSE PRINT "10.7 Modified A3: FAIL"
1990 REM
2000 REM === Section 11: UDT field used in expressions ===
2010 DIM Calc AS Vector
2020 Calc.X = 3.0
2030 Calc.Y = 4.0
2040 Calc.Z = Calc.X + Calc.Y
2050 IF Calc.Z > 6.9 AND Calc.Z < 7.1 THEN PRINT "11.1 Field expression: PASS" ELSE PRINT "11.1 Field expression: FAIL"
2060 Calc.Z = Calc.X * Calc.Y
2070 IF Calc.Z > 11.9 AND Calc.Z < 12.1 THEN PRINT "11.2 Field multiply: PASS" ELSE PRINT "11.2 Field multiply: FAIL"
2080 REM
2100 REM === Section 12: Array of UDTs with strings ===
2110 DIM Team(2) AS Employee
2120 Team(0).Name = "Alice"
2130 Team(0).Age = 30
2140 Team(0).Salary = 70000.0
2150 Team(1).Name = "Bob"
2160 Team(1).Age = 25
2170 Team(1).Salary = 65000.0
2180 IF Team(0).Name = "Alice" THEN PRINT "12.1 Array string(0): PASS" ELSE PRINT "12.1 Array string(0): FAIL"
2190 IF Team(1).Name = "Bob" THEN PRINT "12.2 Array string(1): PASS" ELSE PRINT "12.2 Array string(1): FAIL"
2200 IF Team(0).Age = 30 THEN PRINT "12.3 Array int(0): PASS" ELSE PRINT "12.3 Array int(0): FAIL"
2210 IF Team(1).Age = 25 THEN PRINT "12.4 Array int(1): PASS" ELSE PRINT "12.4 Array int(1): FAIL"
2220 REM
2300 REM === Section 13: Overwrite UDT fields multiple times ===
2310 DIM Mut AS Employee
2320 Mut.Name = "First"
2330 Mut.Age = 1
2340 Mut.Name = "Second"
2350 Mut.Age = 2
2360 Mut.Name = "Third"
2370 Mut.Age = 3
2380 IF Mut.Name = "Third" THEN PRINT "13.1 Overwritten string: PASS" ELSE PRINT "13.1 Overwritten string: FAIL"
2390 IF Mut.Age = 3 THEN PRINT "13.2 Overwritten int: PASS" ELSE PRINT "13.2 Overwritten int: FAIL"
2400 REM
2500 PRINT "=== Comprehensive UDT test complete ==="
2510 END
