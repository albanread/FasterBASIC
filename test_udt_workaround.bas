TYPE Person
  Name AS STRING
  Age AS INTEGER
END TYPE
DIM P AS Person
P.Name = "Alice"
P.Age = 25
PRINT "Name: "; P.Name; ", Age: "; P.Age
NameOK = 0
AgeOK = 0
IF P.Name = "Alice" THEN NameOK = 1
IF P.Age = 25 THEN AgeOK = 1
IF NameOK = 1 AND AgeOK = 1 THEN PRINT "PASS" ELSE PRINT "FAIL"
END
