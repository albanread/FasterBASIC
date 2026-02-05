REM Test DATA/READ/RESTORE with numbers only
REM This avoids needing string runtime functions

DATA 10, 20, 30, 40, 50

DIM a AS INTEGER
DIM b AS INTEGER
DIM c AS INTEGER

READ a, b, c
PRINT a
PRINT b
PRINT c

RESTORE
READ a
PRINT a

END
