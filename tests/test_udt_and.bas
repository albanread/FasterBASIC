TYPE Person
  Name AS STRING
  Age AS INTEGER
END TYPE
DIM P AS Person
P.Name = "Alice"
P.Age = 25
PRINT "Name: "; P.Name; ", Age: "; P.Age
PRINT "Testing P.Name = Alice: "; 
IF P.Name = "Alice" THEN PRINT "TRUE" ELSE PRINT "FALSE"
PRINT "Testing P.Age = 25: ";
IF P.Age = 25 THEN PRINT "TRUE" ELSE PRINT "FALSE"
PRINT "Testing AND: ";
IF P.Name = "Alice" AND P.Age = 25 THEN PRINT "PASS" ELSE PRINT "FAIL"
END
