' Test: FUNCTION returning CLASS_INSTANCE (factory function pattern)
' This tests the #1 priority feature: standalone FUNCTIONs that return CLASS instances
' with proper SAMM RETAIN semantics so the object survives scope exit.

CLASS Animal
    Name AS STRING
    Sound AS STRING
    Legs AS INTEGER

    CONSTRUCTOR()
        ME.Name = "Unknown"
        ME.Sound = "..."
        ME.Legs = 0
    END CONSTRUCTOR

    METHOD Describe() AS STRING
        RETURN ME.Name + " says " + ME.Sound + " and has " + STR$(ME.Legs) + " legs"
    END METHOD
END CLASS

' --- Factory FUNCTION returning a CLASS instance ---
' Uses direct assignment to return variable to avoid DIM-in-function issue (#2)
FUNCTION CreateAnimal(n AS STRING, s AS STRING, l AS INTEGER) AS Animal
    CreateAnimal = NEW Animal()
    CreateAnimal.Name = n
    CreateAnimal.Sound = s
    CreateAnimal.Legs = l
END FUNCTION

' === Test 1: Basic factory function call ===
PRINT "=== Test 1: Basic factory function ==="
DIM dog AS Animal = CreateAnimal("Dog", "Woof", 4)
PRINT dog.Describe()

' === Test 2: Multiple factory calls ===
PRINT "=== Test 2: Multiple factory calls ==="
DIM cat AS Animal = CreateAnimal("Cat", "Meow", 4)
DIM bird AS Animal = CreateAnimal("Bird", "Tweet", 2)
PRINT cat.Describe()
PRINT bird.Describe()

' === Test 3: Using factory result directly in expression ===
PRINT "=== Test 3: Factory in expression ==="
DIM snake AS Animal = CreateAnimal("Snake", "Hiss", 0)
PRINT snake.Name + " has " + STR$(snake.Legs) + " legs"

' === Test 4: Reassignment from factory ===
PRINT "=== Test 4: Reassignment ==="
DIM pet AS Animal = CreateAnimal("Hamster", "Squeak", 4)
PRINT pet.Name
pet = CreateAnimal("Parrot", "Polly wants a cracker", 2)
PRINT pet.Name

' === Test 5: Pass CLASS instance to a FUNCTION ===
PRINT "=== Test 5: CLASS as function parameter ==="

FUNCTION DescribeAnimal(a AS Animal) AS STRING
    RETURN a.Name + " (" + STR$(a.Legs) + " legs)"
END FUNCTION

DIM fox AS Animal = CreateAnimal("Fox", "Ring-ding-ding", 4)
PRINT DescribeAnimal(fox)

' === Test 6: Function-to-function chaining ===
PRINT "=== Test 6: Function chaining ==="
PRINT DescribeAnimal(CreateAnimal("Octopus", "Blub", 8))

' === Test 7: Multiple CLASS params ===
PRINT "=== Test 7: Compare two CLASS instances ==="

FUNCTION HasMoreLegs(a AS Animal, b AS Animal) AS INTEGER
    IF a.Legs > b.Legs THEN
        HasMoreLegs = 1
    ELSE
        HasMoreLegs = 0
    END IF
END FUNCTION

DIM fish AS Animal = CreateAnimal("Fish", "Glub", 0)
DIM horse AS Animal = CreateAnimal("Horse", "Neigh", 4)
PRINT "Fish > Horse legs: "; STR$(HasMoreLegs(fish, horse))
PRINT "Horse > Fish legs: "; STR$(HasMoreLegs(horse, fish))

PRINT "=== All factory function tests passed ==="
