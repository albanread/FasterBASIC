10 REM Test: Simple nested UDT assignment
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
130 REM Set up P1
140 P1.Name = "Alice"
150 P1.Age = 30
160 P1.Addr.Street = "Main St"
170 P1.Addr.Number = 123
180 REM Copy P1 to P2
190 P2 = P1
200 REM Verify P2 got the values
210 PRINT P2.Name
220 PRINT P2.Age
230 PRINT P2.Addr.Street
240 PRINT P2.Addr.Number
250 REM Modify P2 to test independence
260 P2.Name = "Bob"
270 P2.Age = 25
280 P2.Addr.Street = "Oak Ave"
290 P2.Addr.Number = 456
300 REM Verify P1 is unchanged
310 PRINT P1.Name
320 PRINT P1.Age
330 PRINT P1.Addr.Street
340 PRINT P1.Addr.Number
350 REM Verify P2 has new values
360 PRINT P2.Name
370 PRINT P2.Age
380 PRINT P2.Addr.Street
390 PRINT P2.Addr.Number
400 END
