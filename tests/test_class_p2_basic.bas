' === test_class_p2_basic.bas ===
' Phase 2 Test: Basic inheritance with EXTENDS, SUPER, method override
' Avoids: polymorphic arrays, array-element method calls (not yet supported)

' --- Test 1: Basic EXTENDS with field inheritance ---

CLASS Animal
  Name AS STRING
  Sound AS STRING
  Legs AS INTEGER

  CONSTRUCTOR(n AS STRING, s AS STRING, l AS INTEGER)
    ME.Name = n
    ME.Sound = s
    ME.Legs = l
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " says "; ME.Sound
  END METHOD

  METHOD GetLegs() AS INTEGER
    RETURN ME.Legs
  END METHOD
END CLASS

CLASS Dog EXTENDS Animal
  Breed AS STRING

  CONSTRUCTOR(name AS STRING, breed AS STRING)
    SUPER(name, "Woof!", 4)
    ME.Breed = breed
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " the "; ME.Breed; " barks: "; ME.Sound
  END METHOD

  METHOD Fetch(item AS STRING)
    PRINT ME.Name; " fetches the "; item; "!"
  END METHOD
END CLASS

CLASS Cat EXTENDS Animal
  Indoor AS INTEGER

  CONSTRUCTOR(name AS STRING, indoor AS INTEGER)
    SUPER(name, "Meow!", 4)
    ME.Indoor = indoor
  END CONSTRUCTOR

  METHOD Speak()
    IF ME.Indoor THEN
      PRINT ME.Name; " purrs softly"
    ELSE
      PRINT ME.Name; " yowls: "; ME.Sound
    END IF
  END METHOD
END CLASS

DIM rex AS Dog = NEW Dog("Rex", "Labrador")
DIM whiskers AS Cat = NEW Cat("Whiskers", 1)
DIM eagle AS Animal = NEW Animal("Eagle", "Screech!", 2)

rex.Speak()
rex.Fetch("tennis ball")
PRINT "Rex legs: "; rex.GetLegs()
PRINT ""

whiskers.Speak()
PRINT "Whiskers legs: "; whiskers.GetLegs()
PRINT ""

eagle.Speak()
PRINT "Eagle legs: "; eagle.GetLegs()
PRINT ""

' --- Test 2: Inherited method without override ---

CLASS Vehicle
  Speed AS INTEGER

  CONSTRUCTOR(s AS INTEGER)
    ME.Speed = s
  END CONSTRUCTOR

  METHOD ShowSpeed()
    PRINT "Speed: "; ME.Speed
  END METHOD
END CLASS

CLASS Car EXTENDS Vehicle
  Doors AS INTEGER

  CONSTRUCTOR(s AS INTEGER, d AS INTEGER)
    SUPER(s)
    ME.Doors = d
  END CONSTRUCTOR
END CLASS

DIM myCar AS Car = NEW Car(120, 4)
myCar.ShowSpeed()
PRINT "Doors: "; myCar.Doors
PRINT ""

' --- Test 3: SUPER.Method() in overridden method ---

CLASS BaseClass
  METHOD Greet()
    PRINT "Hello from Base"
  END METHOD
END CLASS

CLASS ChildClass EXTENDS BaseClass
  METHOD Greet()
    PRINT "Hello from Child"
    SUPER.Greet()
  END METHOD
END CLASS

CLASS GrandChildClass EXTENDS ChildClass
  METHOD Greet()
    PRINT "Hello from GrandChild"
    SUPER.Greet()
  END METHOD
END CLASS

PRINT "=== SUPER.Method() Chaining ==="
DIM gc AS GrandChildClass = NEW GrandChildClass()
gc.Greet()
PRINT ""

' --- Test 4: Three-level inheritance chain with fields ---

CLASS Level1
  Val1 AS INTEGER

  CONSTRUCTOR(v AS INTEGER)
    ME.Val1 = v
  END CONSTRUCTOR

  METHOD Who() AS STRING
    RETURN "Level1"
  END METHOD
END CLASS

CLASS Level2 EXTENDS Level1
  Val2 AS INTEGER

  CONSTRUCTOR(v1 AS INTEGER, v2 AS INTEGER)
    SUPER(v1)
    ME.Val2 = v2
  END CONSTRUCTOR

  METHOD Who() AS STRING
    RETURN "Level2"
  END METHOD
END CLASS

CLASS Level3 EXTENDS Level2
  Val3 AS INTEGER

  CONSTRUCTOR(v1 AS INTEGER, v2 AS INTEGER, v3 AS INTEGER)
    SUPER(v1, v2)
    ME.Val3 = v3
  END CONSTRUCTOR

  METHOD Who() AS STRING
    RETURN "Level3"
  END METHOD
END CLASS

PRINT "=== Three-Level Inheritance ==="
DIM obj3 AS Level3 = NEW Level3(10, 20, 30)
PRINT obj3.Val1; " "; obj3.Val2; " "; obj3.Val3
PRINT obj3.Who()
PRINT ""

' --- Test 5: Upcast assignment preserves vtable ---

PRINT "=== Upcast Test ==="
DIM anAnimal AS Animal
DIM aDog AS Dog = NEW Dog("Buddy", "Beagle")
anAnimal = aDog
anAnimal.Speak()
PRINT "Legs: "; anAnimal.GetLegs()
PRINT ""

' --- Test 6: Zero-arg SUPER constructor chaining ---

CLASS SimpleBase
  Ready AS INTEGER

  CONSTRUCTOR()
    ME.Ready = 1
  END CONSTRUCTOR

  METHOD IsReady() AS INTEGER
    RETURN ME.Ready
  END METHOD
END CLASS

CLASS SimpleChild EXTENDS SimpleBase
  Label AS STRING

  CONSTRUCTOR(l AS STRING)
    SUPER()
    ME.Label = l
  END CONSTRUCTOR

  METHOD ShowLabel()
    PRINT ME.Label; " (ready="; ME.IsReady(); ")"
  END METHOD
END CLASS

PRINT "=== Zero-Arg SUPER ==="
DIM sc AS SimpleChild = NEW SimpleChild("Widget")
sc.ShowLabel()
PRINT ""

' --- Test 7: Constructor field init order ---

CLASS Ordered
  A AS INTEGER
  B AS INTEGER
  C AS INTEGER

  CONSTRUCTOR()
    ME.A = 1
    ME.B = ME.A + 1
    ME.C = ME.B + 1
  END CONSTRUCTOR

  METHOD Show()
    PRINT ME.A; " "; ME.B; " "; ME.C
  END METHOD
END CLASS

CLASS OrderedChild EXTENDS Ordered
  D AS INTEGER

  CONSTRUCTOR()
    SUPER()
    ME.D = ME.C + 1
  END CONSTRUCTOR

  METHOD Show()
    PRINT ME.A; " "; ME.B; " "; ME.C; " "; ME.D
  END METHOD
END CLASS

PRINT "=== Constructor Init Order ==="
DIM oc AS OrderedChild = NEW OrderedChild()
oc.Show()

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' Rex the Labrador barks: Woof!
' Rex fetches the tennis ball!
' Rex legs: 4
'
' Whiskers purrs softly
' Whiskers legs: 4
'
' Eagle says Screech!
' Eagle legs: 2
'
' Speed: 120
' Doors: 4
'
' === SUPER.Method() Chaining ===
' Hello from GrandChild
' Hello from Child
' Hello from Base
'
' === Three-Level Inheritance ===
' 10 20 30
' Level3
'
' === Upcast Test ===
' Buddy the Beagle barks: Woof!
' Legs: 4
'
' === Zero-Arg SUPER ===
' Widget (ready=1)
'
' === Constructor Init Order ===
' 1 2 3 4
'
' Done!
