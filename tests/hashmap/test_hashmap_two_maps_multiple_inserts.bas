REM Test: Two Hashmaps with Multiple Insertions
REM Tests: Regression test for signed remainder bug in hashmap_compute_index
REM
REM This test specifically exercises the bug that was fixed by changing
REM rem (signed remainder) to urem (unsigned remainder) in hashmap.qbe.
REM
REM The bug manifested when hash values > 2^31 were treated as negative,
REM causing entries to be written to wrong memory locations.
REM
REM Keys like "Bob" and "David" have large hash values that trigger this.

DIM map1 AS HASHMAP
DIM map2 AS HASHMAP

REM Insert into first hashmap
REM Alice has hash 0x2cdd8587 (small, positive)
map1("Alice") = "Engineer"

REM Bob has hash 0xebcba174 (large, would be negative if signed)
REM This was the key that exposed the bug
map1("Bob") = "Designer"

REM Insert into second hashmap
REM Charlie has hash 0x2fb8f9e1 (small-ish, positive)
map2("Charlie") = "Manager"

REM David has hash 0x8aba8bfd (large, would be negative if signed)
REM Before the fix, David would end up in map1's entries array!
map2("David") = "Developer"

REM Verify map1 entries
IF map1("Alice") <> "Engineer" THEN
    PRINT "ERROR: map1(Alice) incorrect"
    END
ENDIF

IF map1("Bob") <> "Designer" THEN
    PRINT "ERROR: map1(Bob) incorrect"
    END
ENDIF

REM Verify map2 entries
IF map2("Charlie") <> "Manager" THEN
    PRINT "ERROR: map2(Charlie) incorrect"
    END
ENDIF

IF map2("David") <> "Developer" THEN
    PRINT "ERROR: map2(David) incorrect"
    END
ENDIF

REM Additional insertions to stress test
map1("Eve") = "Analyst"
map2("Frank") = "Tester"
map1("Grace") = "Director"
map2("Henry") = "Intern"

REM Verify all entries still accessible
IF map1("Alice") <> "Engineer" THEN
    PRINT "ERROR: map1(Alice) after more inserts"
    END
ENDIF

IF map1("Bob") <> "Designer" THEN
    PRINT "ERROR: map1(Bob) after more inserts"
    END
ENDIF

IF map1("Eve") <> "Analyst" THEN
    PRINT "ERROR: map1(Eve) incorrect"
    END
ENDIF

IF map1("Grace") <> "Director" THEN
    PRINT "ERROR: map1(Grace) incorrect"
    END
ENDIF

IF map2("Charlie") <> "Manager" THEN
    PRINT "ERROR: map2(Charlie) after more inserts"
    END
ENDIF

IF map2("David") <> "Developer" THEN
    PRINT "ERROR: map2(David) after more inserts"
    END
ENDIF

IF map2("Frank") <> "Tester" THEN
    PRINT "ERROR: map2(Frank) incorrect"
    END
ENDIF

IF map2("Henry") <> "Intern" THEN
    PRINT "ERROR: map2(Henry) incorrect"
    END
ENDIF

PRINT "PASS: Two hashmaps with multiple insertions work correctly"

END
