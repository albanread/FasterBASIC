REM Test SELECT CASE with mixed integer/double types
PRINT "Test 1: Integer SELECT, literal CASE values"
DIM i%
i% = 42
SELECT CASE i%
    CASE 10
        PRINT "Ten"
    CASE 42
        PRINT "Forty-two!"
    CASE 100
        PRINT "Hundred"
    CASE ELSE
        PRINT "Other"
END SELECT

PRINT ""
PRINT "Test 2: Double SELECT, integer range"
DIM d#
d# = 15.7
SELECT CASE d#
    CASE 1 TO 10
        PRINT "Low"
    CASE 11 TO 20
        PRINT "Medium"
    CASE 21 TO 30
        PRINT "High"
END SELECT

PRINT ""
PRINT "Test 3: Using type-suffixed variables in SELECT"
DIM x%, y#
x% = 5
y# = 5.0

PRINT "Integer 5 vs CASE 5:"
SELECT CASE x%
    CASE 5
        PRINT "Match!"
END SELECT

PRINT "Double 5.0 vs CASE 5:"
SELECT CASE y#
    CASE 5
        PRINT "Match!"
END SELECT

END
