' Test: Marshall/Unmarshall inherited CLASS with STRING fields at multiple levels
' Verifies deep copy across inheritance hierarchy
' Expected output:
' Name: Animal
' Sound: Woof
' Breed: Labrador
' Mutated sound: Meow
' Clone sound: Woof

CLASS Animal
    Name AS STRING
    Sound AS STRING
END CLASS

CLASS Dog EXTENDS Animal
    Breed AS STRING
END CLASS

DIM d AS Dog = NEW Dog()
d.Name = "Animal"
d.Sound = "Woof"
d.Breed = "Labrador"

DIM blob AS MARSHALLED
blob = MARSHALL(d)

DIM d2 AS Dog = NEW Dog()
UNMARSHALL d2, blob

PRINT "Name: "; d2.Name
PRINT "Sound: "; d2.Sound
PRINT "Breed: "; d2.Breed

' Mutate original — clone must be independent
d.Sound = "Meow"
PRINT "Mutated sound: "; d.Sound
PRINT "Clone sound: "; d2.Sound
