REM ============================================
REM Demonstration: SELECT CASE Type Handling
REM All variants work with automatic type matching
REM ============================================

PRINT "FasterBASIC SELECT CASE Type Handling Demo"
PRINT "============================================"
PRINT ""

REM Test 1: Integer variable, integer literals (optimal - no conversion)
PRINT "1. Integer SELECT, integer CASE values:"
DIM score%
score% = 85
SELECT CASE score%
    CASE 90 TO 100
        PRINT "   Grade: A"
    CASE 80 TO 89
        PRINT "   Grade: B"
    CASE 70 TO 79
        PRINT "   Grade: C"
    CASE ELSE
        PRINT "   Grade: F"
END SELECT

REM Test 2: Double variable, double literals (optimal - no conversion)
PRINT ""
PRINT "2. Double SELECT, double CASE values:"
DIM pi#
pi# = 3.14159
SELECT CASE pi#
    CASE IS < 3.0
        PRINT "   Less than 3"
    CASE 3.0 TO 3.5
        PRINT "   Between 3 and 3.5 - This is pi!"
    CASE IS > 3.5
        PRINT "   Greater than 3.5"
END SELECT

REM Test 3: Integer SELECT, mixed CASE types (auto-converts doubles to int)
PRINT ""
PRINT "3. Integer SELECT with mixed CASE types:"
DIM days%
days% = 3
SELECT CASE days%
    CASE 1
        PRINT "   Monday"
    CASE 2.9       ' Will be truncated to 2
        PRINT "   Tuesday (won't match - 2.9 becomes 2)"
    CASE 3
        PRINT "   Wednesday"
    CASE 4, 5
        PRINT "   Thursday or Friday"
END SELECT

REM Test 4: All CASE variants work
PRINT ""
PRINT "4. All CASE syntax variants:"
DIM value%
value% = 15
SELECT CASE value%
    CASE 1, 2, 3
        PRINT "   Small (1-3)"
    CASE 10 TO 20
        PRINT "   Medium (10-20)"
    CASE IS > 100
        PRINT "   Large (>100)"
    CASE ELSE
        PRINT "   Other"
END SELECT

REM Test 5: Real-world example - temperature ranges
PRINT ""
PRINT "5. Real-world: Temperature classification:"
DIM temp#
temp# = 72.5
SELECT CASE temp#
    CASE IS < 32.0
        PRINT "   Freezing"
    CASE 32.0 TO 50.0
        PRINT "   Cold"
    CASE 50.0 TO 68.0
        PRINT "   Cool"
    CASE 68.0 TO 78.0
        PRINT "   Comfortable"
    CASE 78.0 TO 90.0
        PRINT "   Warm"
    CASE IS > 90.0
        PRINT "   Hot"
END SELECT

PRINT ""
PRINT "============================================"
PRINT "All SELECT CASE variants work correctly!"
PRINT "Automatic type matching - no sigils needed."
PRINT "============================================"

END
