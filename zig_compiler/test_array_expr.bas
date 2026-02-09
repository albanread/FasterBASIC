REM Test array expression operations
DIM a(5) AS INTEGER
DIM b(5) AS INTEGER
DIM c(5) AS INTEGER

REM Initialize arrays
a(0) = 1
a(1) = 2
a(2) = 3
a(3) = 4
a(4) = 5

b(0) = 10
b(1) = 20
b(2) = 30
b(3) = 40
b(4) = 50

REM Test array + array
c = a + b
PRINT "Array addition: c = a + b"
PRINT "c(0) = "; c(0); " (expect 11)"
PRINT "c(1) = "; c(1); " (expect 22)"
PRINT "c(2) = "; c(2); " (expect 33)"

REM Test array - array
c = a - b
PRINT ""
PRINT "Array subtraction: c = a - b"
PRINT "c(0) = "; c(0); " (expect -9)"
PRINT "c(1) = "; c(1); " (expect -18)"
PRINT "c(2) = "; c(2); " (expect -27)"

REM Test array * array
c = a * b
PRINT ""
PRINT "Array multiplication: c = a * b"
PRINT "c(0) = "; c(0); " (expect 10)"
PRINT "c(1) = "; c(1); " (expect 40)"
PRINT "c(2) = "; c(2); " (expect 90)"

REM Test array + scalar
c = a + 100
PRINT ""
PRINT "Array + scalar: c = a + 100"
PRINT "c(0) = "; c(0); " (expect 101)"
PRINT "c(1) = "; c(1); " (expect 102)"
PRINT "c(2) = "; c(2); " (expect 103)"

REM Test array * scalar
c = a * 10
PRINT ""
PRINT "Array * scalar: c = a * 10"
PRINT "c(0) = "; c(0); " (expect 10)"
PRINT "c(1) = "; c(1); " (expect 20)"
PRINT "c(2) = "; c(2); " (expect 30)"

END
