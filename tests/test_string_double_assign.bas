' Test consecutive string assignments
' This should work without hanging

DIM s$ AS STRING

PRINT "Assigning first value..."
s$ = "first"
PRINT "First assignment complete: "; s$

PRINT "Assigning second value..."
s$ = "second"
PRINT "Second assignment complete: "; s$

PRINT "Assigning third value..."
s$ = "third"
PRINT "Third assignment complete: "; s$

PRINT "All assignments successful!"
