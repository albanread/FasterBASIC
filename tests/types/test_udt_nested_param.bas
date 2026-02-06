10 REM Test: Nested UDT passed to SUB as parameter
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
160 PRINT "Before SUB calls:"
170 PRINT "Name: "; P.Name; ", Age: "; P.Age
180 PRINT "Street: "; P.Addr.Street; ", Number: "; P.Addr.Number
190 REM Test reading nested UDT fields in a SUB
200 CALL PrintPerson(P)
210 REM Test modifying nested UDT fields through a SUB (pass-by-reference)
220 CALL UpdateAddress(P, "Oak Ave", 456)
230 PRINT "After UpdateAddress:"
240 PRINT "Name: "; P.Name; ", Age: "; P.Age
250 PRINT "Street: "; P.Addr.Street; ", Number: "; P.Addr.Number
260 IF P.Addr.Street = "Oak Ave" THEN PRINT "PASS: Street updated" ELSE PRINT "FAIL: Street updated"
270 IF P.Addr.Number = 456 THEN PRINT "PASS: Number updated" ELSE PRINT "FAIL: Number updated"
280 IF P.Name = "Alice" THEN PRINT "PASS: Name unchanged" ELSE PRINT "FAIL: Name unchanged"
290 IF P.Age = 30 THEN PRINT "PASS: Age unchanged" ELSE PRINT "FAIL: Age unchanged"
300 REM Test modifying top-level and nested fields together
310 CALL RenamePerson(P, "Bob", 25)
320 IF P.Name = "Bob" THEN PRINT "PASS: Name changed" ELSE PRINT "FAIL: Name changed"
330 IF P.Age = 25 THEN PRINT "PASS: Age changed" ELSE PRINT "FAIL: Age changed"
340 IF P.Addr.Street = "Oak Ave" THEN PRINT "PASS: Street still ok" ELSE PRINT "FAIL: Street still ok"
350 END
360 SUB PrintPerson(Who AS Person)
370   PRINT "In SUB PrintPerson:"
380   PRINT "  Name: "; Who.Name
390   PRINT "  Age: "; Who.Age
400   PRINT "  Street: "; Who.Addr.Street
410   PRINT "  Number: "; Who.Addr.Number
420   IF Who.Name = "Alice" THEN PRINT "PASS: Read name in SUB" ELSE PRINT "FAIL: Read name in SUB"
430   IF Who.Age = 30 THEN PRINT "PASS: Read age in SUB" ELSE PRINT "FAIL: Read age in SUB"
440   IF Who.Addr.Street = "Main St" THEN PRINT "PASS: Read street in SUB" ELSE PRINT "FAIL: Read street in SUB"
450   IF Who.Addr.Number = 123 THEN PRINT "PASS: Read number in SUB" ELSE PRINT "FAIL: Read number in SUB"
460 END SUB
470 SUB UpdateAddress(Who AS Person, NewStreet AS STRING, NewNumber AS INTEGER)
480   Who.Addr.Street = NewStreet
490   Who.Addr.Number = NewNumber
500 END SUB
510 SUB RenamePerson(Who AS Person, NewName AS STRING, NewAge AS INTEGER)
520   Who.Name = NewName
530   Who.Age = NewAge
540 END SUB
