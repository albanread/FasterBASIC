' Bubblesort Benchmark
' Sorts an array of 1000 integers, 100 times to measure array access and conditional swap performance

PRINT "Running Bubblesort (1000 items, 100 iterations)..."

DIM size AS INTEGER
size = 1000

' Allocate slightly more to be safe with 1-based indexing
DIM arr(1005) AS INTEGER

DIM i AS INTEGER
DIM j AS INTEGER
DIM iter AS INTEGER

FOR iter = 1 TO 100
    ' Fill array with reverse ordered data (Worst case for Bubble Sort)
    FOR i = 1 TO size
        arr(i) = size - i
    NEXT i

    ' Bubble Sort Algorithm
    FOR i = 1 TO size - 1
        FOR j = 1 TO size - i
            IF arr(j) > arr(j + 1) THEN
                SWAP arr(j), arr(j + 1)
            END IF
        NEXT j
    NEXT i
NEXT iter

' Verify result of the last iteration
PRINT "Verifying sort..."
FOR i = 1 TO size - 1
    IF arr(i) > arr(i + 1) THEN
        PRINT "Error: Sort failed at index "; i; " ("; arr(i); " > "; arr(i + 1); ")"
    END IF
NEXT i

PRINT "Done."
