' Mersenne Number Factor Finder (Function-Based Version)
' Rosetta Code Challenge: Find factors of Mersenne numbers (2^P - 1)
'
' This program finds factors of Mersenne numbers using efficient modular
' exponentiation and the properties of Mersenne number factors.
'
' Key properties used:
' 1. Any factor q of 2^P-1 must be of the form 2kP+1 (k >= 0)
' 2. q must be 1 or 7 (mod 8)
' 3. q must be prime
'
' Test case: Find a factor of 2^929 - 1 (M929)

PRINT "=== Mersenne Number Factor Finder (Function Version) ==="
PRINT ""
PRINT "Finding factors of 2^929 - 1 (M929)"
PRINT ""

' Target exponent
LET P& = 929

' Main search loop
LET k& = 1
LET found% = 0
LET maxk& = 1000000

PRINT "Searching for factors of the form q = 2kP + 1..."
PRINT ""

WHILE k& <= maxk& AND found% = 0
    ' Calculate potential factor q = 2kP + 1
    LET q& = 2 * k& * P& + 1

    ' Check if q is 1 or 7 (mod 8)
    LET mod8& = q& MOD 8
    LET okmod8% = 0
    IF mod8& = 1 THEN
        okmod8% = 1
    END IF
    IF mod8& = 7 THEN
        okmod8% = 1
    END IF

    ' If passes mod 8 test, check if prime and test as factor
    IF okmod8% = 1 THEN
        ' Check primality
        IF IsPrime&(q&) = 1 THEN
            ' Test if it's a factor using modular exponentiation
            IF ModularPower&(2, P&, q&) = 1 THEN
                ' Found a factor!
                PRINT ""
                PRINT "======================================"
                PRINT "FOUND FACTOR!"
                PRINT "======================================"
                PRINT "Factor: "; q&
                PRINT "k = "; k&
                PRINT "2^"; P&; " mod "; q&; " = 1"
                PRINT ""
                PRINT "Therefore "; q&; " is a factor of M"; P&
                PRINT "======================================"
                found% = 1
            END IF
        END IF
    END IF

    ' Progress report
    LET checkprog& = k& MOD 5000
    IF checkprog& = 0 THEN
        PRINT "Tested k = "; k&; " (q = "; q&; ")..."
    END IF

    LET k& = k& + 1
WEND

IF found% = 0 THEN
    PRINT ""
    PRINT "No factor found in range k = 1 to "; maxk&
END IF

END

' ============================================================================
' Function: IsPrime&
' Check if n is prime
' Parameters: n& - number to test
' Returns: 1 if prime, 0 otherwise
' ============================================================================
FUNCTION IsPrime&(n AS LONG) AS LONG
    LOCAL tmod2&
    LOCAL sqrtval#
    LOCAL sqrtmax&
    LOCAL divisor&
    LOCAL divmod&

    IF n < 2 THEN
        RETURN 0&
    END IF

    IF n = 2 THEN
        RETURN 1&
    END IF

    IF n = 3 THEN
        RETURN 1&
    END IF

    LET tmod2& = n MOD 2
    IF tmod2& = 0 THEN
        RETURN 0&
    END IF

    ' Trial division up to square root
    LET sqrtval# = SQR(n)
    LET sqrtmax& = INT(sqrtval#) + 1
    LET divisor& = 3

    WHILE divisor& <= sqrtmax&
        LET divmod& = n MOD divisor&
        IF divmod& = 0 THEN
            RETURN 0&
        END IF
        LET divisor& = divisor& + 2
    WEND

    RETURN 1&
END FUNCTION

' ============================================================================
' Function: ModularPower&
' Compute base^exponent mod modulus using binary exponentiation
' Parameters:
'   basenum& - base number
'   exponent& - exponent
'   m& - modulus for result
' Returns: basenum^exponent mod m
' ============================================================================
FUNCTION ModularPower&(basenum AS LONG, exponent AS LONG, m AS LONG) AS LONG
    LOCAL res&
    LOCAL b&
    LOCAL e&
    LOCAL bit&

    LET res& = 1
    LET b& = basenum MOD m
    LET e& = exponent

    WHILE e& > 0
        LET bit& = e& MOD 2
        IF bit& = 1 THEN
            LET res& = (res& * b&) MOD m
        END IF
        LET b& = (b& * b&) MOD m
        LET e& = e& \ 2
    WEND

    RETURN res&
END FUNCTION
