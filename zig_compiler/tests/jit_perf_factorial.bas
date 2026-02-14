' ============================================================================
' JIT Performance Test: Factorial
'
' Computes 18! iteratively inside a tight outer loop, 500 million times.
' 18! = 6402373705728000  (fits comfortably in a 64-bit signed LONG)
'
' Run with:  fbc --jit --metrics tests/jit_perf_factorial.bas
'
' Expected output:
'   Repetitions: 500000000
'   18! = 6402373705728000
'   Checksum:    388000000000
' ============================================================================

DIM outer AS LONG
DIM n AS LONG
DIM fact AS LONG
DIM i AS LONG
DIM total AS LONG
DIM reps AS LONG

reps = 500000000
total = 0

' --- Outer loop: repeat factorial computation many times ---
outer = 0
WHILE outer < reps
    ' Compute 18! iteratively (fits in 64-bit signed long)
    n = 18
    fact = 1
    i = 2
    WHILE i <= n
        fact = fact * i
        i = i + 1
    WEND

    ' Accumulate with prime modulus so the work cannot be optimised away
    ' (18! MOD 1000 = 0, so we use 997 instead for a non-trivial checksum)
    total = total + (fact MOD 997)

    outer = outer + 1
WEND

PRINT "Repetitions: "; reps
PRINT "18! = "; fact
PRINT "Checksum:    "; total
END
