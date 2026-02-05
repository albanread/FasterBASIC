10 REM Test: UDT with string field
20 TYPE Person
30   Name AS STRING
40   Age AS INTEGER
50 END TYPE
60 DIM P AS Person
70 P.Name = "Alice"
80 P.Age = 25
90 PRINT "Name: "; P.Name; ", Age: "; P.Age
100 IF P.Name = "Alice" AND P.Age = 25 THEN PRINT "PASS" ELSE PRINT "FAIL"
110 END
