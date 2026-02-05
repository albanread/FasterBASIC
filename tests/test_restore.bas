REM Test RESTORE functionality
REM This tests RESTORE to reset data pointer and read from specific positions

DATA 1, 2, 3, 4, 5

DIM a AS INTEGER
DIM b AS INTEGER
DIM c AS INTEGER

READ a, b, c
PRINT "First read: "; a; ", "; b; ", "; c

RESTORE
READ a, b
PRINT "After RESTORE: "; a; ", "; b

END
