REM Visual Grid Test - Shows terminal coordinate system
REM This draws a grid so you can see exactly where things appear

CLS

REM Draw column numbers across top
LOCATE 0, 0
PRINT "Col:";
DIM c%
FOR c = 0 TO 79 STEP 10
    LOCATE c, 0
    PRINT STR$(c);
NEXT c

REM Draw row numbers down left side and grid
DIM r%
FOR r = 1 TO 23
    LOCATE 0, r
    PRINT STR$(r);

    REM Draw dots every 10 columns
    FOR c = 10 TO 70 STEP 10
        LOCATE c, r
        PRINT ".";
    NEXT c
NEXT r

REM Draw a box at known coordinates
LOCATE 20, 10
PRINT "+-------+"
LOCATE 20, 11
PRINT "| (20,10)|"
LOCATE 20, 12
PRINT "+-------+"

REM Draw another box
LOCATE 50, 15
PRINT "+---------+"
LOCATE 50, 16
PRINT "| (50,15) |"
LOCATE 50, 17
PRINT "+---------+"

REM Instructions at bottom
LOCATE 0, 23
PRINT "Grid test - Press ENTER to exit"

DIM dummy$ AS STRING
INPUT dummy$
