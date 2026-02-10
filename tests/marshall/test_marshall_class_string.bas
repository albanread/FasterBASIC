' Test: Marshall/Unmarshall a CLASS with STRING fields (deep copy)
' Expected output:
' Title: Hamlet
' Author: Shakespeare
' Pages: 300
' Mutated: Macbeth
' Clone: Hamlet

CLASS Book
    Title AS STRING
    Author AS STRING
    Pages AS DOUBLE
END CLASS

DIM b AS Book = NEW Book()
b.Title = "Hamlet"
b.Author = "Shakespeare"
b.Pages = 300

DIM blob AS MARSHALLED
blob = MARSHALL(b)

DIM b2 AS Book = NEW Book()
UNMARSHALL b2, blob

PRINT "Title: "; b2.Title
PRINT "Author: "; b2.Author
PRINT "Pages: "; b2.Pages

' Mutate original — clone must be independent
b.Title = "Macbeth"
PRINT "Mutated: "; b.Title
PRINT "Clone: "; b2.Title
