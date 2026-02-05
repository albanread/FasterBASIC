REM Test SELECT CASE with double values
DIM x#
x# = 2.5

SELECT CASE x#
    CASE 1.5
        PRINT "1.5"
    CASE 2.5
        PRINT "2.5"
    CASE 3.5
        PRINT "3.5"
    CASE ELSE
        PRINT "Other"
END SELECT
