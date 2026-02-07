OPTION SAMM ON

' =====================================================================
' MATCH TYPE — CLASS, UDT, and Basic Type Dispatch Tests
' Covers: class-specific matching with inheritance, generic OBJECT
' fallback, multiple class arms, class + basic type mixing,
' method calls on matched class instances, CASE ELSE with classes,
' and UDT type name resolution.
' =====================================================================

' --- Define a simple class hierarchy ---

CLASS Animal
    Name AS STRING
    Legs AS INTEGER

    CONSTRUCTOR(n AS STRING, l AS INTEGER)
        ME.Name = n
        ME.Legs = l
    END CONSTRUCTOR

    METHOD Speak() AS STRING
        RETURN "..."
    END METHOD

    METHOD Describe() AS STRING
        RETURN ME.Name + " with " + STR$(ME.Legs) + " legs"
    END METHOD
END CLASS

CLASS Dog EXTENDS Animal
    CONSTRUCTOR(n AS STRING)
        SUPER(n, 4)
    END CONSTRUCTOR

    METHOD Speak() AS STRING
        RETURN "Woof!"
    END METHOD
END CLASS

CLASS Cat EXTENDS Animal
    CONSTRUCTOR(n AS STRING)
        SUPER(n, 4)
    END CONSTRUCTOR

    METHOD Speak() AS STRING
        RETURN "Meow!"
    END METHOD
END CLASS

CLASS Bird EXTENDS Animal
    CONSTRUCTOR(n AS STRING)
        SUPER(n, 2)
    END CONSTRUCTOR

    METHOD Speak() AS STRING
        RETURN "Tweet!"
    END METHOD
END CLASS

' --- A standalone class (not in the Animal hierarchy) ---

CLASS Vehicle
    Brand AS STRING

    CONSTRUCTOR(b AS STRING)
        ME.Brand = b
    END CONSTRUCTOR

    METHOD Info() AS STRING
        RETURN "Vehicle: " + ME.Brand
    END METHOD
END CLASS

' =====================================================================
' Test 1: Basic class-specific matching — Dog, Cat, Bird
' =====================================================================
PRINT "=== Test 1: Basic class dispatch ==="
DIM zoo AS LIST OF ANY = LIST(NEW Dog("Rex"), NEW Cat("Whiskers"), NEW Bird("Tweety"))

FOR EACH E IN zoo
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog: "; d.Speak()
        CASE Cat c
            PRINT "Cat: "; c.Speak()
        CASE Bird b
            PRINT "Bird: "; b.Speak()
    END MATCH
NEXT E

' Expected:
'   Dog: Woof!
'   Cat: Meow!
'   Bird: Tweet!

' =====================================================================
' Test 2: Class matching with CASE ELSE fallback
' =====================================================================
PRINT ""
PRINT "=== Test 2: Class + CASE ELSE ==="
DIM mix AS LIST OF ANY = LIST(NEW Dog("Buddy"), NEW Vehicle("Toyota"), NEW Cat("Luna"))

FOR EACH E IN mix
    MATCH TYPE E
        CASE Dog d
            PRINT "Found dog: "; d.Describe()
        CASE Cat c
            PRINT "Found cat: "; c.Describe()
        CASE ELSE
            PRINT "Something else"
    END MATCH
NEXT E

' Expected:
'   Found dog: Buddy with 4 legs
'   Something else
'   Found cat: Luna with 4 legs

' =====================================================================
' Test 3: Mixing class and basic-type arms
' =====================================================================
PRINT ""
PRINT "=== Test 3: Classes + basic types ==="
DIM mixed AS LIST OF ANY = LIST(42, NEW Dog("Fido"), "hello", NEW Bird("Polly"), 3.14)

FOR EACH E IN mixed
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Int: "; n%
        CASE STRING s$
            PRINT "Str: "; s$
        CASE DOUBLE f#
            PRINT "Dbl: "; f#
        CASE Dog d
            PRINT "Dog says: "; d.Speak()
        CASE Bird b
            PRINT "Bird says: "; b.Speak()
        CASE ELSE
            PRINT "Other"
    END MATCH
NEXT E

' Expected:
'   Int: 42
'   Dog says: Woof!
'   Str: hello
'   Bird says: Tweet!
'   Dbl: 3.14

' =====================================================================
' Test 4: Inheritance matching — CASE Animal catches all animals
' =====================================================================
PRINT ""
PRINT "=== Test 4: Inheritance matching ==="
DIM animals AS LIST OF ANY = LIST(NEW Dog("Rex"), NEW Cat("Mimi"), NEW Bird("Jay"), NEW Vehicle("Ford"))

FOR EACH E IN animals
    MATCH TYPE E
        CASE Animal a
            PRINT "Animal: "; a.Describe(); " says "; a.Speak()
        CASE ELSE
            PRINT "Not an animal"
    END MATCH
NEXT E

' Expected:
'   Animal: Rex with 4 legs says Woof!
'   Animal: Mimi with 4 legs says Meow!
'   Animal: Jay with 2 legs says Tweet!
'   Not an animal

' =====================================================================
' Test 5: Specific before general — Dog before Animal
' =====================================================================
PRINT ""
PRINT "=== Test 5: Specific before general ==="
DIM priority AS LIST OF ANY = LIST(NEW Dog("Spot"), NEW Cat("Felix"), NEW Bird("Robin"))

FOR EACH E IN priority
    MATCH TYPE E
        CASE Dog d
            PRINT "Specifically a Dog: "; d.Describe()
        CASE Animal a
            PRINT "Some other Animal: "; a.Describe()
    END MATCH
NEXT E

' Expected:
'   Specifically a Dog: Spot with 4 legs
'   Some other Animal: Felix with 4 legs
'   Some other Animal: Robin with 2 legs

' =====================================================================
' Test 6: Generic OBJECT arm catches any object
' =====================================================================
PRINT ""
PRINT "=== Test 6: Generic OBJECT catch-all ==="
DIM objects AS LIST OF ANY = LIST(NEW Dog("Duke"), NEW Vehicle("Honda"), 99)

FOR EACH E IN objects
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "Integer: "; n%
        CASE OBJECT obj
            PRINT "Some object found"
    END MATCH
NEXT E

' Expected:
'   Some object found
'   Some object found
'   Integer: 99

' =====================================================================
' Test 7: Class + OBJECT ordering — specific class before generic OBJECT
' =====================================================================
PRINT ""
PRINT "=== Test 7: Class before OBJECT ==="
DIM ordered AS LIST OF ANY = LIST(NEW Dog("Max"), NEW Vehicle("BMW"), NEW Cat("Nala"))

FOR EACH E IN ordered
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog: "; d.Speak()
        CASE OBJECT obj
            PRINT "Generic object"
    END MATCH
NEXT E

' Expected:
'   Dog: Woof!
'   Generic object
'   Generic object

' =====================================================================
' Test 8: Method calls inside class arm bodies
' =====================================================================
PRINT ""
PRINT "=== Test 8: Method calls in arms ==="
DIM pets AS LIST OF ANY = LIST(NEW Dog("Biscuit"), NEW Cat("Shadow"), NEW Bird("Kiwi"))

FOR EACH E IN pets
    MATCH TYPE E
        CASE Dog d
            PRINT d.Describe(); " — "; d.Speak()
        CASE Cat c
            PRINT c.Describe(); " — "; c.Speak()
        CASE Bird b
            PRINT b.Describe(); " — "; b.Speak()
    END MATCH
NEXT E

' Expected:
'   Biscuit with 4 legs — Woof!
'   Shadow with 4 legs — Meow!
'   Kiwi with 2 legs — Tweet!

' =====================================================================
' Test 9: Two-variable FOR EACH with class matching
' =====================================================================
PRINT ""
PRINT "=== Test 9: Two-variable FOR EACH + classes ==="
DIM items AS LIST OF ANY = LIST(NEW Dog("Ace"), 100, NEW Vehicle("Tesla"))

FOR EACH T, E IN items
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog: "; d.Speak()
        CASE INTEGER n%
            PRINT "Number: "; n%
        CASE Vehicle v
            PRINT "Car: "; v.Info()
    END MATCH
NEXT T

' Expected:
'   Dog: Woof!
'   Number: 100
'   Car: Vehicle: Tesla

' =====================================================================
' Test 10: Counting by class type
' =====================================================================
PRINT ""
PRINT "=== Test 10: Class counting ==="
DIM countList AS LIST OF ANY = LIST(NEW Dog("A"), NEW Cat("B"), NEW Dog("C"), NEW Bird("D"), NEW Cat("E"), 42, "hi")
DIM dogCount AS INTEGER
DIM catCount AS INTEGER
DIM birdCount AS INTEGER
DIM otherCount AS INTEGER
LET dogCount = 0
LET catCount = 0
LET birdCount = 0
LET otherCount = 0

FOR EACH E IN countList
    MATCH TYPE E
        CASE Dog d
            LET dogCount = dogCount + 1
        CASE Cat c
            LET catCount = catCount + 1
        CASE Bird b
            LET birdCount = birdCount + 1
        CASE ELSE
            LET otherCount = otherCount + 1
    END MATCH
NEXT E

PRINT "Dogs: "; dogCount
PRINT "Cats: "; catCount
PRINT "Birds: "; birdCount
PRINT "Others: "; otherCount

' Expected:
'   Dogs: 2
'   Cats: 2
'   Birds: 1
'   Others: 2

' =====================================================================
' Test 11: Only one arm executes per element
' =====================================================================
PRINT ""
PRINT "=== Test 11: Single arm execution ==="
DIM singleItem AS LIST OF ANY = LIST(NEW Dog("Solo"))
DIM armHits AS INTEGER
LET armHits = 0

FOR EACH E IN singleItem
    MATCH TYPE E
        CASE Dog d
            LET armHits = armHits + 1
            PRINT "Dog arm"
        CASE Animal a
            LET armHits = armHits + 1
            PRINT "Animal arm"
        CASE OBJECT obj
            LET armHits = armHits + 1
            PRINT "Object arm"
        CASE ELSE
            LET armHits = armHits + 1
            PRINT "Else arm"
    END MATCH
NEXT E

PRINT "Arm hits: "; armHits

' Expected:
'   Dog arm
'   Arm hits: 1

' =====================================================================
' Test 12: No class arm matches — falls to CASE ELSE
' =====================================================================
PRINT ""
PRINT "=== Test 12: No class match ==="
DIM noMatch AS LIST OF ANY = LIST(NEW Vehicle("Mazda"))

FOR EACH E IN noMatch
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog"
        CASE Cat c
            PRINT "Cat"
        CASE ELSE
            PRINT "No dog or cat here"
    END MATCH
NEXT E

' Expected:
'   No dog or cat here

' =====================================================================
' Test 13: Empty list — no arms execute
' =====================================================================
PRINT ""
PRINT "=== Test 13: Empty list ==="
DIM emptyList AS LIST OF ANY = LIST()
DIM emptyHits AS INTEGER
LET emptyHits = 0

FOR EACH E IN emptyList
    MATCH TYPE E
        CASE Dog d
            LET emptyHits = emptyHits + 1
        CASE ELSE
            LET emptyHits = emptyHits + 1
    END MATCH
NEXT E

PRINT "Hits on empty list: "; emptyHits

' Expected:
'   Hits on empty list: 0

' =====================================================================
' Test 14: IF/ELSE inside class arm
' =====================================================================
PRINT ""
PRINT "=== Test 14: Control flow in class arm ==="
DIM cf AS LIST OF ANY = LIST(NEW Dog("Tiny"), NEW Dog("Giant"))

FOR EACH E IN cf
    MATCH TYPE E
        CASE Dog d
            IF d.Name = "Tiny" THEN
                PRINT d.Name; " is small"
            ELSE
                PRINT d.Name; " is big"
            END IF
        CASE ELSE
            PRINT "Not a dog"
    END MATCH
NEXT E

' Expected:
'   Tiny is small
'   Giant is big

' =====================================================================
' Test 15: Sequential MATCH TYPE blocks — same list, different class focus
' =====================================================================
PRINT ""
PRINT "=== Test 15: Sequential match blocks ==="
DIM seq AS LIST OF ANY = LIST(NEW Dog("D1"), NEW Cat("C1"), NEW Bird("B1"))

PRINT "Pass 1 — Dogs only:"
FOR EACH E IN seq
    MATCH TYPE E
        CASE Dog d
            PRINT "  Dog: "; d.Name
        CASE ELSE
            PRINT "  skip"
    END MATCH
NEXT E

PRINT "Pass 2 — Cats only:"
FOR EACH E IN seq
    MATCH TYPE E
        CASE Cat c
            PRINT "  Cat: "; c.Name
        CASE ELSE
            PRINT "  skip"
    END MATCH
NEXT E

PRINT "Pass 3 — Birds only:"
FOR EACH E IN seq
    MATCH TYPE E
        CASE Bird b
            PRINT "  Bird: "; b.Name
        CASE ELSE
            PRINT "  skip"
    END MATCH
NEXT E

' Expected:
'   Pass 1 — Dogs only:
'     Dog: D1
'     skip
'     skip
'   Pass 2 — Cats only:
'     skip
'     Cat: C1
'     skip
'   Pass 3 — Birds only:
'     skip
'     skip
'     Bird: B1

' =====================================================================
' Test 16: All basic types still work alongside class arms
' =====================================================================
PRINT ""
PRINT "=== Test 16: All basic types + classes ==="
DIM full AS LIST OF ANY = LIST(1, "two", 3.14, NEW Dog("Four"))

FOR EACH T, E IN full
    MATCH TYPE E
        CASE INTEGER n%
            PRINT "INTEGER: "; n%
        CASE STRING s$
            PRINT "STRING: "; s$
        CASE DOUBLE f#
            PRINT "DOUBLE: "; f#
        CASE Dog d
            PRINT "DOG: "; d.Name
        CASE ELSE
            PRINT "ELSE"
    END MATCH
NEXT T

' Expected:
'   INTEGER: 1
'   STRING: two
'   DOUBLE: 3.14
'   DOG: Four

' =====================================================================
' Test 17: Multiple unrelated class types
' =====================================================================
PRINT ""
PRINT "=== Test 17: Multiple unrelated classes ==="
DIM unrelated AS LIST OF ANY = LIST(NEW Dog("Rover"), NEW Vehicle("Jeep"), NEW Cat("Simba"), NEW Vehicle("Audi"))

FOR EACH E IN unrelated
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog: "; d.Name
        CASE Vehicle v
            PRINT "Vehicle: "; v.Brand
        CASE Cat c
            PRINT "Cat: "; c.Name
    END MATCH
NEXT E

' Expected:
'   Dog: Rover
'   Vehicle: Jeep
'   Cat: Simba
'   Vehicle: Audi

' =====================================================================
' Test 18: Accumulate names by class type
' =====================================================================
PRINT ""
PRINT "=== Test 18: Accumulate by class ==="
DIM accum AS LIST OF ANY = LIST(NEW Dog("A"), NEW Cat("B"), NEW Dog("C"), NEW Cat("D"))
DIM dogNames AS STRING
DIM catNames AS STRING
LET dogNames = ""
LET catNames = ""

FOR EACH E IN accum
    MATCH TYPE E
        CASE Dog d
            IF LEN(dogNames) > 0 THEN
                LET dogNames = dogNames + ", " + d.Name
            ELSE
                LET dogNames = d.Name
            END IF
        CASE Cat c
            IF LEN(catNames) > 0 THEN
                LET catNames = catNames + ", " + c.Name
            ELSE
                LET catNames = c.Name
            END IF
    END MATCH
NEXT E

PRINT "Dogs: "; dogNames
PRINT "Cats: "; catNames

' Expected:
'   Dogs: A, C
'   Cats: B, D

' =====================================================================
' Test 19: ENDMATCH syntax with classes
' =====================================================================
PRINT ""
PRINT "=== Test 19: ENDMATCH syntax ==="
DIM em AS LIST OF ANY = LIST(NEW Dog("Pal"), 55)

FOR EACH E IN em
    MATCH TYPE E
        CASE Dog d
            PRINT "Dog: "; d.Speak()
        CASE INTEGER n%
            PRINT "Int: "; n%
    ENDMATCH
NEXT E

' Expected:
'   Dog: Woof!
'   Int: 55

' =====================================================================
' Test 20: Two MATCH TYPE blocks per iteration with classes
' =====================================================================
PRINT ""
PRINT "=== Test 20: Two match blocks per iteration ==="
DIM dual AS LIST OF ANY = LIST(NEW Dog("Duo"), NEW Cat("Pair"))

FOR EACH T, E IN dual
    MATCH TYPE E
        CASE Dog d
            PRINT "Block1 Dog: "; d.Name
        CASE Cat c
            PRINT "Block1 Cat: "; c.Name
    END MATCH

    MATCH TYPE E
        CASE Animal a
            PRINT "Block2 Animal: "; a.Describe()
    END MATCH
NEXT T

' Expected:
'   Block1 Dog: Duo
'   Block2 Animal: Duo with 4 legs
'   Block1 Cat: Pair
'   Block2 Animal: Pair with 4 legs

PRINT ""
PRINT "=== All MATCH TYPE class tests complete ==="

END
