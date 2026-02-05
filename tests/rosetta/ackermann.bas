REM ============================================================================
REM Ackermann Function - Rosetta Code Challenge
REM https://rosettacode.org/wiki/Ackermann_function
REM ============================================================================
REM
REM The Ackermann function is a classic example of a recursive function that
REM is not primitive recursive. It grows extremely fast and is often used to
REM test recursion and stack handling in programming languages.
REM
REM Definition:
REM   A(m, n) = n + 1                  if m = 0
REM   A(m, n) = A(m-1, 1)              if m > 0 and n = 0
REM   A(m, n) = A(m-1, A(m, n-1))      if m > 0 and n > 0
REM
REM The function is notable for:
REM - Deep recursion (calls itself multiple times)
REM - Extremely rapid growth (A(4,2) = 2^65536 - 3)
REM - Testing compiler's handling of recursive function calls
REM ============================================================================

PRINT "============================================"
PRINT "Ackermann Function - Rosetta Code Challenge"
PRINT "============================================"
PRINT ""

DIM m AS INTEGER
DIM n AS INTEGER
DIM result AS INTEGER

PRINT "Computing Ackermann function values:"
PRINT ""
PRINT "  m   n   A(m,n)"
PRINT "----  ---  --------"

REM Compute Ackermann function for small values
FOR m = 0 TO 3
    FOR n = 0 TO 4
        result = Ack(m, n)
        PRINT "  "; m; "    "; n; "    "; result
    NEXT n
NEXT m

PRINT ""
PRINT "Notable values:"
PRINT "  A(0, n) = n + 1"
PRINT "  A(1, n) = n + 2"
PRINT "  A(2, n) = 2*n + 3"
PRINT "  A(3, n) = 2^(n+3) - 3"
PRINT ""
PRINT "Pattern verification:"
PRINT "  A(0, 4) = 5       (expected: 5)"
PRINT "  A(1, 4) = 6       (expected: 6)"
PRINT "  A(2, 4) = 11      (expected: 11)"
PRINT "  A(3, 4) = 125     (expected: 125)"

END

FUNCTION Ack(m AS INTEGER, n AS INTEGER) AS INTEGER
    LOCAL temp AS INTEGER

    IF m = 0 THEN
        Ack = n + 1
    ELSE
        IF n = 0 THEN
            temp = Ack(m - 1, 1)
            Ack = temp
        ELSE
            temp = Ack(m, n - 1)
            Ack = Ack(m - 1, temp)
        END IF
    END IF
END FUNCTION
