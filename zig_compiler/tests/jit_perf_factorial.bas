' ============================================================================
' JIT Performance Test: Factorial
'
' Computes factorial iteratively inside a tight outer loop.
' Run with:  fbc --jit --metrics tests/jit_perf_factorial.bas
'
' Expected output:
'   Repetitions: 50000000
'   12! = 479001600
'   Checksum:    -64771072
' ============================================================================

DIM outer AS LONG
DIM n AS LONG
DIM fact AS LONG
DIM i AS LONG
DIM total AS LONG
DIM reps AS LONG

reps = 50000000
total = 0

' --- Outer loop: repeat factorial computation many times ---
outer = 0
WHILE outer < reps
    ' Compute 12! iteratively (max that fits in 32-bit signed long)
    n = 12
    fact = 1
    i = 2
    WHILE i <= n
        fact = fact * i
        i = i + 1
    WEND

    ' Accumulate low bits so the work cannot be optimised away
    total = total + (fact MOD 1000)

    outer = outer + 1
WEND

PRINT "Repetitions: "; reps
PRINT "12! = "; fact
PRINT "Checksum:    "; total
END
