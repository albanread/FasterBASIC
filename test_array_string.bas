TYPE Person
  Name AS STRING
  Age AS INTEGER
END TYPE
DIM P(1) AS Person
P(0).Name = "Alice"
P(0).Age = 30
PRINT "Name: "; P(0).Name
PRINT "Age: "; P(0).Age
END
