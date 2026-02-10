' Recursive Fibonacci Benchmark
' Calculates fib(35) to measure function call overhead and recursion performance

FUNCTION Fib(n AS INTEGER) AS INTEGER
    IF n < 2 THEN
        Fib = n
    ELSE
        Fib = Fib(n - 1) + Fib(n - 2)
    END IF
END FUNCTION

PRINT "Calculating Fib(35)..."
DIM result AS INTEGER
result = Fib(35)
PRINT "Result: "; result
