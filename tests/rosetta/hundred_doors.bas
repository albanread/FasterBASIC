REM ============================================================================
REM 100 Doors Problem - Rosetta Code Challenge
REM https://rosettacode.org/wiki/100_doors
REM ============================================================================
REM
REM Problem: There are 100 doors in a row that are all initially closed.
REM You make 100 passes by the doors. The first time through, visit every door
REM and toggle it (if closed, open it; if open, close it). The second time,
REM only visit every 2nd door (door #2, #4, #6, ...) and toggle it. The third
REM time, visit every 3rd door (door #3, #6, #9, ...), etc., until you only
REM visit the 100th door on the 100th pass.
REM
REM Question: What state are the doors in after the last pass? Which are open?
REM
REM Solution: A door is toggled once for each divisor it has. Only perfect
REM squares have an odd number of divisors, so only doors numbered with
REM perfect squares (1, 4, 9, 16, 25, 36, 49, 64, 81, 100) will be open.
REM ============================================================================

OPTION BOUNDS_CHECK OFF

DIM doors(100) AS INTEGER
DIM pass AS INTEGER
DIM door AS INTEGER
DIM open_count AS INTEGER

REM Initialize all doors to closed (0)
PRINT "Initializing 100 doors..."
FOR door = 0 TO 99
    doors(door) = 0
NEXT door

REM Make 100 passes
PRINT "Making 100 passes through the doors..."
FOR pass = 1 TO 100
    REM On pass N, visit every Nth door
    REM Door numbers are 1-100, but array is 0-99
    door = pass - 1
    WHILE door <= 99
        REM Toggle the door (0 becomes 1, 1 becomes 0)
        IF doors(door) = 0 THEN
            doors(door) = 1
        ELSE
            doors(door) = 0
        END IF
        door = door + pass
    WEND
NEXT pass

REM Display results
PRINT ""
PRINT "============================================"
PRINT "Final State of Doors"
PRINT "============================================"
PRINT ""

open_count = 0
FOR door = 0 TO 99
    IF doors(door) = 1 THEN
        PRINT "Door "; door + 1; " is OPEN"
        open_count = open_count + 1
    END IF
NEXT door

PRINT ""
PRINT "--------------------------------------------"
PRINT "Total open doors: "; open_count
PRINT ""
PRINT "Pattern: Only perfect squares are open!"
PRINT "1, 4, 9, 16, 25, 36, 49, 64, 81, 100"
PRINT ""

REM Verify the pattern - check if open doors are perfect squares
PRINT "Verification:"
DIM is_valid AS INTEGER
DIM sqrt_val AS INTEGER
is_valid = 1

FOR door = 0 TO 99
    REM Check if this door number is a perfect square
    REM by testing if sqrt(door)^2 = door
    sqrt_val = INT(SQR(door + 1))

    IF sqrt_val * sqrt_val = door + 1 THEN
        REM This is a perfect square, should be open
        IF doors(door) = 0 THEN
            PRINT "ERROR: Door "; door + 1; " should be open!"
            is_valid = 0
        END IF
    ELSE
        REM Not a perfect square, should be closed
        IF doors(door) = 1 THEN
            PRINT "ERROR: Door "; door + 1; " should be closed!"
            is_valid = 0
        END IF
    END IF
NEXT door

IF is_valid = 1 THEN
    PRINT "✓ All doors in correct state!"
ELSE
    PRINT "✗ Some doors in wrong state!"
END IF

PRINT ""
PRINT "Algorithm explanation:"
PRINT "A door is toggled once for each of its divisors."
PRINT "Only perfect squares have an odd number of divisors,"
PRINT "so only those doors end up open."

END
