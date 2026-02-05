REM Test nested WHILE with IF inside
DIM sieve(100) AS INT
DIM i AS INT
DIM j AS INT

REM Initialize
i = 1
WHILE i <= 10
    sieve(i) = 1
    i = i + 1
WEND

PRINT "Testing nested WHILE with IF"
i = 2
WHILE i <= 3
    PRINT "Outer i = "; i
    IF sieve(i) = 1 THEN
        PRINT "  sieve("; i; ") is 1, marking multiples"
        j = i * i
        PRINT "  Starting j = "; j
        WHILE j <= 10
            PRINT "    Inner j = "; j
            sieve(j) = 0
            j = j + i
        WEND
        PRINT "  Done with multiples"
    END IF
    i = i + 1
WEND

PRINT "Results:"
PRINT "sieve(2) = "; sieve(2)
PRINT "sieve(3) = "; sieve(3)
PRINT "sieve(4) = "; sieve(4)
PRINT "sieve(6) = "; sieve(6)
PRINT "sieve(8) = "; sieve(8)
PRINT "sieve(9) = "; sieve(9)
