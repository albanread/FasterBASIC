REM Test basic 2D array operations
REM This test verifies array assignment, access, and modification

DIM arr(3, 3) AS INTEGER

REM Initialize array with known values
arr(0, 0) = 10
arr(0, 1) = 11
arr(0, 2) = 12
arr(1, 0) = 20
arr(1, 1) = 21
arr(1, 2) = 22
arr(2, 0) = 30
arr(2, 1) = 31
arr(2, 2) = 32

REM Read and verify values
PRINT "Testing basic reads:"
PRINT "arr(0,0) = "; arr(0, 0); " (expect 10)"
PRINT "arr(1,1) = "; arr(1, 1); " (expect 21)"
PRINT "arr(2,2) = "; arr(2, 2); " (expect 32)"

REM Test modification
arr(1, 1) = 999
PRINT "After arr(1,1) = 999:"
PRINT "arr(1,1) = "; arr(1, 1); " (expect 999)"

REM Test with variables as indices
DIM i AS INTEGER
DIM j AS INTEGER
i = 2
j = 1
PRINT "Using variables i=2, j=1:"
PRINT "arr(i,j) = "; arr(i, j); " (expect 31)"

REM Test with expressions as indices
PRINT "Using expressions:"
PRINT "arr(1+1, 2-1) = "; arr(1+1, 2-1); " (expect 31)"

END
