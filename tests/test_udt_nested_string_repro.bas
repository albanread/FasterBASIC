10 REM Minimal repro: nested UDT string field read/print bug
20 TYPE Address
30   Street AS STRING
40   Number AS INTEGER
50 END TYPE
60 TYPE Person
70   Name AS STRING
80   Age AS INTEGER
90   Addr AS Address
100 END TYPE
110 DIM P AS Person
120 P.Name = "Alice"
130 P.Age = 30
140 P.Addr.Street = "Main St"
150 P.Addr.Number = 123
160 REM Top-level fields work fine
170 PRINT "Name: "; P.Name
180 PRINT "Age: "; P.Age
190 REM Nested integer field works
200 PRINT "Number: "; P.Addr.Number
210 REM Nested string field prints raw pointer instead of string
220 PRINT "Street: "; P.Addr.Street
230 REM Nested string comparison crashes
240 IF P.Addr.Street = "Main St" THEN PRINT "PASS" ELSE PRINT "FAIL"
250 END
