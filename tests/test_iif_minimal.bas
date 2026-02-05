' Minimal IIF string test
PRINT "Testing IIF with strings"
DIM s$
s$ = "initial"
PRINT "Before IIF: "; s$
s$ = IIF(1 > 0, "true", "false")
PRINT "After IIF: "; s$
PRINT "Done"
END
