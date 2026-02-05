10 REM Test: UDT assignment with string fields (deep copy)
20 TYPE Person
30   Name AS STRING
40   Age AS INTEGER
50 END TYPE
60 DIM P1 AS Person
70 DIM P2 AS Person
80 REM Set up P1
90 P1.Name = "Alice"
100 P1.Age = 30
110 PRINT "Before assignment:"
120 PRINT "P1: "; P1.Name; ", Age "; P1.Age
130 PRINT "P2: "; P2.Name; ", Age "; P2.Age
140 REM Assign P1 to P2 (should deep copy strings)
150 P2 = P1
160 PRINT "After P2 = P1:"
170 PRINT "P1: "; P1.Name; ", Age "; P1.Age
180 PRINT "P2: "; P2.Name; ", Age "; P2.Age
190 REM Modify P2 to verify independence
200 P2.Name = "Bob"
210 P2.Age = 25
220 PRINT "After modifying P2:"
230 PRINT "P1: "; P1.Name; ", Age "; P1.Age
240 PRINT "P2: "; P2.Name; ", Age "; P2.Age
250 REM Verify correct values
260 IF P1.Name = "Alice" AND P1.Age = 30 THEN PRINT "P1 PASS" ELSE PRINT "P1 FAIL"
270 IF P2.Name = "Bob" AND P2.Age = 25 THEN PRINT "P2 PASS" ELSE PRINT "P2 FAIL"
280 END
