10 REM Test: UDT with LONG fields
20 TYPE BigNumber
30   Value AS LONG
40   Count AS LONG
50 END TYPE
60 DIM Big AS BigNumber
70 Big.Value = 9999999999
80 Big.Count = 123456789
90 PRINT "Big.Value = "; Big.Value
100 PRINT "Big.Count = "; Big.Count
110 IF Big.Value = 9999999999 AND Big.Count = 123456789 THEN PRINT "PASS" ELSE PRINT "FAIL"
120 END
