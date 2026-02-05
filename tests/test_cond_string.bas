' Test conditional string assignment without using IIF
PRINT "Testing conditional string assignment"

DIM s$
s$ = "initial"
PRINT "Initial: "; s$

' Use IF to conditionally assign
IF 1 > 0 THEN
    s$ = "true branch"
ELSE
    s$ = "false branch"
END IF

PRINT "After IF: "; s$

' Test again with false condition
IF 0 > 1 THEN
    s$ = "true branch"
ELSE
    s$ = "false branch"
END IF

PRINT "After second IF: "; s$

PRINT "Done"
END
