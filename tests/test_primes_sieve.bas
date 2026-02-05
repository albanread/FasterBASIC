REM Sieve of Eratosthenes - Prime Number Generator
REM Tests array performance and loop optimization

DIM sieve(10000) AS INT
DIM i AS INT
DIM j AS INT
DIM count AS INT
DIM limit AS INT

REM Initialize all numbers as potentially prime (1 = prime, 0 = composite)
i = 2
WHILE i <= 100
    sieve(i) = 1
    i = i + 1
WEND

PRINT "Testing sieve with i=2"
i = 2
IF sieve(i) = 1 THEN
    PRINT "sieve(2) is prime, marking multiples"
    j = i * i
    PRINT "Starting with j = "; j
    WHILE j <= 100
        PRINT "  Marking sieve("; j; ") = 0"
        sieve(j) = 0
        PRINT "  After marking, sieve("; j; ") = "; sieve(j)
        j = j + i
        PRINT "  Next j = "; j
    WEND
    PRINT "Done marking multiples of 2"
END IF

PRINT ""
PRINT "Verification after i=2:"
PRINT "sieve(2) = "; sieve(2); " (should be 1)"
PRINT "sieve(3) = "; sieve(3); " (should be 1)"
PRINT "sieve(4) = "; sieve(4); " (should be 0)"
PRINT "sieve(5) = "; sieve(5); " (should be 1)"
PRINT "sieve(6) = "; sieve(6); " (should be 0)"
PRINT "sieve(7) = "; sieve(7); " (should be 1)"
PRINT "sieve(8) = "; sieve(8); " (should be 0)"
PRINT "sieve(9) = "; sieve(9); " (should be 1)"
PRINT "sieve(10) = "; sieve(10); " (should be 0)"
