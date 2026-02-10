' Test: MARSHALL / UNMARSHALL without workers — pure deep copy
' Expected output:
' Copy: Hello World
' Original: Hello World
' Changed: Goodbye
' Copy still: Hello World

CLASS Message
    Text AS STRING
    Code AS DOUBLE
END CLASS

DIM original AS Message = NEW Message()
original.Text = "Hello World"
original.Code = 42

' Marshall creates an independent snapshot
DIM blob AS MARSHALLED
blob = MARSHALL(original)

' Unmarshall into a separate object
DIM clone AS Message = NEW Message()
UNMARSHALL clone, blob

PRINT "Copy: "; clone.Text
PRINT "Original: "; original.Text

' Mutate the original — copy should be unaffected
original.Text = "Goodbye"
PRINT "Changed: "; original.Text
PRINT "Copy still: "; clone.Text
