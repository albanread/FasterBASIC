REM Test: Hashmap Stress Test
REM Tests: Many entries, collision handling

DIM dict AS HASHMAP
DIM count AS INTEGER
DIM i AS INTEGER

REM Insert 30 entries
dict("item1") = "data1"
dict("item2") = "data2"
dict("item3") = "data3"
dict("item4") = "data4"
dict("item5") = "data5"
dict("item6") = "data6"
dict("item7") = "data7"
dict("item8") = "data8"
dict("item9") = "data9"
dict("item10") = "data10"
dict("item11") = "data11"
dict("item12") = "data12"
dict("item13") = "data13"
dict("item14") = "data14"
dict("item15") = "data15"
dict("item16") = "data16"
dict("item17") = "data17"
dict("item18") = "data18"
dict("item19") = "data19"
dict("item20") = "data20"
dict("item21") = "data21"
dict("item22") = "data22"
dict("item23") = "data23"
dict("item24") = "data24"
dict("item25") = "data25"
dict("item26") = "data26"
dict("item27") = "data27"
dict("item28") = "data28"
dict("item29") = "data29"
dict("item30") = "data30"

REM Verify entries
IF dict("item1") <> "data1" THEN
    PRINT "ERROR: item1 failed"
    END
ENDIF

IF dict("item15") <> "data15" THEN
    PRINT "ERROR: item15 failed"
    END
ENDIF

IF dict("item30") <> "data30" THEN
    PRINT "ERROR: item30 failed"
    END
ENDIF

REM Test updates
dict("item1") = "updated1"
dict("item15") = "updated15"
dict("item30") = "updated30"

IF dict("item1") <> "updated1" THEN
    PRINT "ERROR: item1 update failed"
    END
ENDIF

IF dict("item15") <> "updated15" THEN
    PRINT "ERROR: item15 update failed"
    END
ENDIF

IF dict("item30") <> "updated30" THEN
    PRINT "ERROR: item30 update failed"
    END
ENDIF

REM Add more diverse keys
dict("alpha") = "a"
dict("beta") = "b"
dict("gamma") = "g"
dict("delta") = "d"
dict("epsilon") = "e"

IF dict("alpha") <> "a" THEN
    PRINT "ERROR: alpha failed"
    END
ENDIF

IF dict("epsilon") <> "e" THEN
    PRINT "ERROR: epsilon failed"
    END
ENDIF

REM Verify original entries still work
IF dict("item10") <> "data10" THEN
    PRINT "ERROR: item10 corrupted"
    END
ENDIF

IF dict("item20") <> "data20" THEN
    PRINT "ERROR: item20 corrupted"
    END
ENDIF

PRINT "PASS: Hashmap handles 35+ entries correctly"

END
