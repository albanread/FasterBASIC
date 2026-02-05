TYPE Person
  Name AS STRING
  Age AS INTEGER
END TYPE
DIM P AS Person
P.Name = "Alice"
P.Age = 25
PRINT "Name is: "; P.Name
IF P.Name = "Alice" THEN PRINT "Name check PASS" ELSE PRINT "Name check FAIL"
IF P.Age = 25 THEN PRINT "Age check PASS" ELSE PRINT "Age check FAIL"
END
