' Iterative Fibonacci Benchmark
' Calculates Fib(40) 1,000,000 times to measure loop and basic arithmetic performance

FUNCTION FibIter(n AS INTEGER) AS INTEGER
    DIM res AS INTEGER

    IF n < 2 THEN
        res = n
    ELSE
        DIM a AS INTEGER
        DIM b AS INTEGER
        DIM temp AS INTEGER
        DIM i AS INTEGER

        a = 0
        b = 1

        FOR i = 2 TO n
            temp = a + b
            a = b
            b = temp
        NEXT i
        res = b
    END IF
    FibIter = res
END FUNCTION

PRINT "Calculating Fib(40) 1,000,000 times..."
DIM result AS INTEGER
DIM k AS INTEGER

FOR k = 1 TO 1000000
    result = FibIter(40)
NEXT k

PRINT "Last Result: "; result
