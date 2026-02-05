REM Test type glyphs on variables and see if they work with literals

DIM a%    ' Integer
DIM b!    ' Single
DIM c#    ' Double
DIM d$    ' String

a% = 42
b! = 3.14
c# = 2.71828
d$ = "Hello"

PRINT "a% = "; a%
PRINT "b! = "; b!
PRINT "c# = "; c#
PRINT "d$ = "; d$

REM Test if we can use type glyphs in SELECT CASE
PRINT ""
PRINT "Test with type-suffixed variable:"
SELECT CASE a%
    CASE 10
        PRINT "Ten"
    CASE 42
        PRINT "Forty-two"
    CASE ELSE
        PRINT "Other"
END SELECT

END
