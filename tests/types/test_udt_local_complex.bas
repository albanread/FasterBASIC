10 REM Test: LOCAL UDT with string fields and nested UDTs inside SUB
20 TYPE Address
30   Street AS STRING
40   Number AS INTEGER
50 END TYPE
60 TYPE Person
70   Name AS STRING
80   Age AS INTEGER
90   Addr AS Address
100 END TYPE
110 CALL TestLocalUDTSimple()
120 CALL TestLocalUDTString()
130 CALL TestLocalUDTNested()
140 CALL TestLocalUDTCopy()
150 END
160 SUB TestLocalUDTSimple()
170   PRINT "=== Test LOCAL UDT simple ==="
180   LOCAL P AS Person
190   P.Name = "Alice"
200   P.Age = 30
210   PRINT "Name: "; P.Name; ", Age: "; P.Age
220   IF P.Name = "Alice" THEN PRINT "PASS: local name" ELSE PRINT "FAIL: local name"
230   IF P.Age = 30 THEN PRINT "PASS: local age" ELSE PRINT "FAIL: local age"
240 END SUB
250 SUB TestLocalUDTString()
260   PRINT "=== Test LOCAL UDT string overwrite ==="
270   LOCAL P AS Person
280   P.Name = "First"
290   P.Name = "Second"
300   P.Name = "Third"
310   IF P.Name = "Third" THEN PRINT "PASS: string overwrite" ELSE PRINT "FAIL: string overwrite"
320   P.Age = 99
330   IF P.Age = 99 THEN PRINT "PASS: int after string ops" ELSE PRINT "FAIL: int after string ops"
340 END SUB
350 SUB TestLocalUDTNested()
360   PRINT "=== Test LOCAL nested UDT ==="
370   LOCAL P AS Person
380   P.Name = "Bob"
390   P.Age = 25
400   P.Addr.Street = "Elm St"
410   P.Addr.Number = 42
420   IF P.Name = "Bob" THEN PRINT "PASS: nested name" ELSE PRINT "FAIL: nested name"
430   IF P.Age = 25 THEN PRINT "PASS: nested age" ELSE PRINT "FAIL: nested age"
440   IF P.Addr.Street = "Elm St" THEN PRINT "PASS: nested street" ELSE PRINT "FAIL: nested street"
450   IF P.Addr.Number = 42 THEN PRINT "PASS: nested number" ELSE PRINT "FAIL: nested number"
460 END SUB
470 SUB TestLocalUDTCopy()
480   PRINT "=== Test LOCAL UDT copy ==="
490   LOCAL P1 AS Person
500   LOCAL P2 AS Person
510   P1.Name = "Carol"
520   P1.Age = 40
530   P1.Addr.Street = "Pine Rd"
540   P1.Addr.Number = 88
550   P2 = P1
560   IF P2.Name = "Carol" THEN PRINT "PASS: copy name" ELSE PRINT "FAIL: copy name"
570   IF P2.Age = 40 THEN PRINT "PASS: copy age" ELSE PRINT "FAIL: copy age"
580   IF P2.Addr.Street = "Pine Rd" THEN PRINT "PASS: copy street" ELSE PRINT "FAIL: copy street"
590   IF P2.Addr.Number = 88 THEN PRINT "PASS: copy number" ELSE PRINT "FAIL: copy number"
600   REM Verify independence
610   P2.Name = "Dave"
620   P2.Addr.Street = "Oak Ln"
630   IF P1.Name = "Carol" THEN PRINT "PASS: original unchanged" ELSE PRINT "FAIL: original unchanged"
640   IF P1.Addr.Street = "Pine Rd" THEN PRINT "PASS: original street unchanged" ELSE PRINT "FAIL: original street unchanged"
650 END SUB
