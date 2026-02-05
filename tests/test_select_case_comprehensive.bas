REM Test SELECT CASE with various types and cases

PRINT "Test 1: Integer SELECT CASE"
DIM i%
i% = 3
SELECT CASE i%
    CASE 1
        PRINT "One"
    CASE 2
        PRINT "Two"
    CASE 3
        PRINT "Three"
    CASE ELSE
        PRINT "Other"
END SELECT

PRINT ""
PRINT "Test 2: Double SELECT CASE"
DIM d#
d# = 2.5
SELECT CASE d#
    CASE 1.5
        PRINT "1.5"
    CASE 2.5
        PRINT "2.5"
    CASE 3.5
        PRINT "3.5"
    CASE ELSE
        PRINT "Other"
END SELECT

PRINT ""
PRINT "Test 3: Range test (integers)"
i% = 15
SELECT CASE i%
    CASE 1 TO 10
        PRINT "1-10"
    CASE 11 TO 20
        PRINT "11-20"
    CASE 21 TO 30
        PRINT "21-30"
    CASE ELSE
        PRINT "Outside range"
END SELECT

PRINT ""
PRINT "Test 4: Range test (doubles)"
d# = 2.5
SELECT CASE d#
    CASE 0.0 TO 1.0
        PRINT "0-1"
    CASE 1.0 TO 3.0
        PRINT "1-3"
    CASE 3.0 TO 5.0
        PRINT "3-5"
    CASE ELSE
        PRINT "Outside range"
END SELECT

PRINT ""
PRINT "Test 5: Multiple values (integers)"
i% = 7
SELECT CASE i%
    CASE 2, 4, 6, 8
        PRINT "Even (2,4,6,8)"
    CASE 1, 3, 5, 7, 9
        PRINT "Odd (1,3,5,7,9)"
    CASE ELSE
        PRINT "Other"
END SELECT

PRINT ""
PRINT "Test 6: CASE IS (integers)"
i% = 42
SELECT CASE i%
    CASE IS < 10
        PRINT "Less than 10"
    CASE IS < 50
        PRINT "Less than 50"
    CASE IS >= 50
        PRINT "50 or more"
END SELECT

PRINT ""
PRINT "Test 7: CASE IS (doubles)"
d# = 3.14159
SELECT CASE d#
    CASE IS < 1.0
        PRINT "Less than 1"
    CASE IS < 4.0
        PRINT "Less than 4"
    CASE IS >= 4.0
        PRINT "4 or more"
END SELECT

END
