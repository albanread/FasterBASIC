' Sieve of Eratosthenes Benchmark
' Finds primes up to 8190 using the classic sieve algorithm
' Repeated 5000 times

PRINT "Running Sieve of Eratosthenes (5000 iterations)..."

DIM Size AS INTEGER
Size = 8190

DIM flags(8191) AS INTEGER
DIM i AS INTEGER
DIM k AS INTEGER
DIM prime AS INTEGER
DIM count AS INTEGER
DIM iter AS INTEGER

FOR iter = 1 TO 5000
    count = 0

    ' Reset flags
    FOR i = 0 TO Size
        flags(i) = 1
    NEXT i

    ' Sieve
    FOR i = 0 TO Size
        IF flags(i) = 1 THEN
            prime = i + i + 3
            k = i + prime

            WHILE k <= Size
                flags(k) = 0
                k = k + prime
            WEND

            count = count + 1
        END IF
    NEXT i
NEXT iter

PRINT "Iterations: 5000"
PRINT "Primes found: "; count
