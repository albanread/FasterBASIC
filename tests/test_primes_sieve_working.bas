REM Sieve of Eratosthenes - Prime Number Generator
REM Working version using GOTO to avoid nested WHILE inside IF bug

DIM sieve(10000) AS INT
DIM i AS INT
DIM j AS INT
DIM count AS INT
DIM limit AS INT

REM Initialize all numbers as potentially prime (1 = prime, 0 = composite)
i = 2
WHILE i <= 10000
    sieve(i) = 1
    i = i + 1
WEND

REM Sieve algorithm - limit is sqrt(10000) = 100
limit = 100
i = 2
WHILE i <= limit
    REM Check if i is prime - if not, skip marking multiples
    IF sieve(i) <> 1 THEN GOTO skip_marking

    REM Mark all multiples of i as composite
    j = i * i
    WHILE j <= 10000
        sieve(j) = 0
        j = j + i
    WEND

skip_marking:
    i = i + 1
WEND

REM Count primes
count = 0
i = 2
WHILE i <= 10000
    IF sieve(i) = 1 THEN count = count + 1
    i = i + 1
WEND

PRINT "Found "; count; " primes up to 10000"
PRINT "(Expected: 1229)"
PRINT ""

REM Print first 25 primes
PRINT "First 25 primes:"
count = 0
i = 2
WHILE i <= 10000
    IF sieve(i) <> 1 THEN GOTO next_first
    PRINT i; " ";
    count = count + 1
    IF count >= 25 THEN GOTO done_first
next_first:
    i = i + 1
WEND
done_first:
PRINT
PRINT ""

REM Print last 10 primes
PRINT "Last 10 primes up to 10000:"
count = 0
i = 10000
WHILE i >= 2
    IF sieve(i) <> 1 THEN GOTO next_last
    PRINT i; " ";
    count = count + 1
    IF count >= 10 THEN GOTO done_last
next_last:
    i = i - 1
WEND
done_last:
PRINT
