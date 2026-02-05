' Test basic GLOBAL statement functionality
' This tests that GLOBAL variables are properly declared and initialized

GLOBAL x%
GLOBAL y#
GLOBAL z$

x% = 10
y# = 3.14
z$ = "Hello"

PRINT "x% ="; x%
PRINT "y# ="; y#
PRINT "z$ ="; z$

CALL TestSub

PRINT "After sub: x% ="; x%

END

SUB TestSub()
    SHARED x%
    x% = x% + 5
END SUB
