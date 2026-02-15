REM Simple test to see if LINE INPUT is being lexed correctly
DIM x AS STRING
OPEN "test.txt" FOR OUTPUT AS #1
PRINT #1, "Test line"
CLOSE #1
OPEN "test.txt" FOR INPUT AS #1
LINE INPUT #1, x
CLOSE #1
PRINT "Read: "; x
PRINT "Done"
