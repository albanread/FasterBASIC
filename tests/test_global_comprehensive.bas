' Comprehensive GLOBAL variable test
' Tests multiple globals, multiple functions, read-modify-write, and type handling

GLOBAL counter%
GLOBAL total#
GLOBAL message$
GLOBAL factor%

' Initialize globals
counter% = 0
total# = 0.0
message$ = "Start"
factor% = 2

PRINT "=== Initial Values ==="
PRINT "counter% ="; counter%
PRINT "total# ="; total#
PRINT "message$ ="; message$
PRINT "factor% ="; factor%
PRINT

' Call functions that modify globals
CALL Increment
CALL Increment
CALL AddValue(5.5)
CALL AddValue(3.25)
CALL UpdateMessage
CALL Multiply

PRINT "=== After Function Calls ==="
PRINT "counter% ="; counter%
PRINT "total# ="; total#
PRINT "message$ ="; message$
PRINT

' Test read-modify-write in main
counter% = counter% + 10
total# = total# * 2.0

PRINT "=== After Main Modifications ==="
PRINT "counter% ="; counter%
PRINT "total# ="; total#
PRINT

END

SUB Increment()
    SHARED counter%
    counter% = counter% + 1
    PRINT "Increment: counter% ="; counter%
END SUB

SUB AddValue(value#)
    SHARED total#
    total# = total# + value#
    PRINT "AddValue: total# ="; total#
END SUB

SUB UpdateMessage()
    SHARED message$, counter%
    message$ = "Count:" + STR$(counter%)
    PRINT "UpdateMessage: message$ ="; message$
END SUB

SUB Multiply()
    SHARED counter%, factor%
    counter% = counter% * factor%
    PRINT "Multiply: counter% ="; counter%
END SUB
