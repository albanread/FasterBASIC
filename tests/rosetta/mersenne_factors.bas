' Mersenne Number Factor Finder
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

PRINT "=== Mersenne Number Factor Finder ==="
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
        LET testq& = q&
        GOSUB PrimeCheck

        IF isprime% = 1 THEN
            ' Test if it's a factor using modular exponentiation
            LET testp& = P&
            LET testq& = q&
            GOSUB ModularPower

            IF modresult& = 1 THEN
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
' Subroutine: PrimeCheck
' Check if testq& is prime
' Output: isprime%
' ============================================================================
PrimeCheck:
    isprime% = 0

    IF testq& < 2 THEN
        RETURN
    END IF

    IF testq& = 2 THEN
        isprime% = 1
        RETURN
    END IF

    IF testq& = 3 THEN
        isprime% = 1
        RETURN
    END IF

    LET tmod2& = testq& MOD 2
    IF tmod2& = 0 THEN
        RETURN
    END IF

    ' Trial division up to square root
    LET sqrtval# = SQR(testq&)
    LET sqrtmax& = INT(sqrtval#) + 1
    LET divisor& = 3

    WHILE divisor& <= sqrtmax&
        LET divmod& = testq& MOD divisor&
        IF divmod& = 0 THEN
            RETURN
        END IF
        LET divisor& = divisor& + 2
    WEND

    isprime% = 1
    RETURN

' ============================================================================
' Subroutine: ModularPower
' Compute 2^testp& mod testq& using binary exponentiation
' Input: testp&, testq&
' Output: modresult&
' ============================================================================
ModularPower:
    LET modresult& = 1
    LET mpbase& = 2 MOD testq&
    LET mpexp& = testp&

    WHILE mpexp& > 0
        LET mpbit& = mpexp& MOD 2
        IF mpbit& = 1 THEN
            LET modresult& = (modresult& * mpbase&) MOD testq&
        END IF
        LET mpbase& = (mpbase& * mpbase&) MOD testq&
        LET mpexp& = mpexp& / 2
    WEND

    RETURN
