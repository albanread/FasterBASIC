' === test_class_p2_inheritance.bas ===
' Phase 2 Test: Inheritance with EXTENDS, SUPER, method override, polymorphism
' Validates: EXTENDS keyword, inherited fields, SUPER() constructor call,
'            SUPER.Method() call, method overriding, vtable dispatch,
'            polymorphic arrays, upcast assignment, multi-level inheritance

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

  METHOD Describe() AS STRING
    RETURN ME.Name + " (" + STR$(ME.Legs) + " legs)"
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
PRINT rex.Describe()
PRINT ""

whiskers.Speak()
PRINT whiskers.Describe()
PRINT ""

eagle.Speak()
PRINT eagle.Describe()
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

' --- Test 3: Polymorphic array ---

PRINT "=== Polymorphic Array ==="

DIM zoo(2) AS Animal
zoo(0) = rex
zoo(1) = whiskers
zoo(2) = eagle

FOR i = 0 TO 2
  zoo(i).Speak()
NEXT i
PRINT ""

' --- Test 4: SUPER.Method() in overridden method ---

CLASS Base
  METHOD Greet()
    PRINT "Hello from Base"
  END METHOD
END CLASS

CLASS Child EXTENDS Base
  METHOD Greet()
    PRINT "Hello from Child"
    SUPER.Greet()
  END METHOD
END CLASS

CLASS GrandChild EXTENDS Child
  METHOD Greet()
    PRINT "Hello from GrandChild"
    SUPER.Greet()
  END METHOD
END CLASS

PRINT "=== SUPER.Method() Chaining ==="
DIM gc AS GrandChild = NEW GrandChild()
gc.Greet()
PRINT ""

' --- Test 5: Three-level inheritance chain ---

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

DIM obj1 AS Level1
obj1 = NEW Level1()
obj1 = obj3
PRINT obj1.Who()
PRINT ""

' --- Test 6: Mixed inherited and new methods ---

CLASS Shape
  METHOD Area() AS DOUBLE
    RETURN 0.0
  END METHOD

  METHOD Kind() AS STRING
    RETURN "Shape"
  END METHOD
END CLASS

CLASS Circle EXTENDS Shape
  Radius AS DOUBLE

  CONSTRUCTOR(r AS DOUBLE)
    ME.Radius = r
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN 3.14159 * ME.Radius * ME.Radius
  END METHOD

  METHOD Kind() AS STRING
    RETURN "Circle"
  END METHOD

  METHOD Diameter() AS DOUBLE
    RETURN ME.Radius * 2.0
  END METHOD
END CLASS

CLASS Square EXTENDS Shape
  Side AS DOUBLE

  CONSTRUCTOR(s AS DOUBLE)
    ME.Side = s
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN ME.Side * ME.Side
  END METHOD

  METHOD Kind() AS STRING
    RETURN "Square"
  END METHOD

  METHOD Perimeter() AS DOUBLE
    RETURN ME.Side * 4.0
  END METHOD
END CLASS

PRINT "=== Shape Hierarchy ==="

DIM circ AS Circle = NEW Circle(5.0)
PRINT circ.Kind(); " area: "; circ.Area()
PRINT "Diameter: "; circ.Diameter()

DIM sq AS Square = NEW Square(4.0)
PRINT sq.Kind(); " area: "; sq.Area()
PRINT "Perimeter: "; sq.Perimeter()

' Polymorphic dispatch through base type
DIM shapes(1) AS Shape
shapes(0) = circ
shapes(1) = sq

PRINT ""
PRINT "=== Polymorphic Shape Dispatch ==="
FOR i = 0 TO 1
  PRINT shapes(i).Kind(); " -> area = "; shapes(i).Area()
NEXT i
PRINT ""

' --- Test 7: Upcast preserves object identity ---

PRINT "=== Upcast Test ==="
DIM anAnimal AS Animal
DIM aDog AS Dog = NEW Dog("Buddy", "Beagle")
anAnimal = aDog
anAnimal.Speak()
PRINT anAnimal.Describe()
PRINT ""

' --- Test 8: SUPER() with zero-arg parent constructor ---

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

' --- Test 9: Constructor field init order ---

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
' Rex (4 legs)
'
' Whiskers purrs softly
' Whiskers (4 legs)
'
' Eagle says Screech!
' Eagle (2 legs)
'
' Speed: 120
' Doors: 4
'
' === Polymorphic Array ===
' Rex the Labrador barks: Woof!
' Whiskers purrs softly
' Eagle says Screech!
'
' === SUPER.Method() Chaining ===
' Hello from GrandChild
' Hello from Child
' Hello from Base
'
' === Three-Level Inheritance ===
' 10 20 30
' Level3
' Level3
'
' === Shape Hierarchy ===
' Circle area: 78.53975
' Diameter: 10
' Square area: 16
' Perimeter: 16
'
' === Polymorphic Shape Dispatch ===
' Circle -> area = 78.53975
' Square -> area = 16
'
' === Upcast Test ===
' Buddy the Beagle barks: Woof!
' Buddy (4 legs)
'
' === Zero-Arg SUPER ===
' Widget (ready=1)
'
' === Constructor Init Order ===
' 1 2 3 4
'
' Done!
