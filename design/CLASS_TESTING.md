# FasterBASIC CLASS & OBJECT — Test Plan

**Version:** 1.0
**Date:** July 2025
**Status:** Ready for Implementation
**Companion to:** `CLASS_IMPLEMENTATION.md`, `CLASS_OBJECT_DESIGN.md`

---

## Table of Contents

1. [Test Strategy](#1-test-strategy)
2. [Phase 1 Tests: Core CLASS (MVP)](#2-phase-1-tests-core-class-mvp)
3. [Phase 2 Tests: Inheritance](#3-phase-2-tests-inheritance)
4. [Phase 3 Tests: IS, NOTHING, DELETE](#4-phase-3-tests-is-nothing-delete)
5. [Phase 4 Tests: Polish & Integration](#5-phase-4-tests-polish--integration)
6. [Compiler Error Tests](#6-compiler-error-tests)
7. [Runtime Error Tests](#7-runtime-error-tests)
8. [QBE IL Verification Tests](#8-qbe-il-verification-tests)
9. [Regression Tests](#9-regression-tests)
10. [Performance Benchmarks](#10-performance-benchmarks)

---

## 1. Test Strategy

### 1.1 Test Levels

| Level | Description | Method |
|-------|-------------|--------|
| **IL Verification** | Check generated QBE IL matches expected patterns | `fbc_qbe -i` + grep/diff |
| **Compile & Run** | Compile to executable, run, check stdout | `fbc_qbe prog.bas && ./prog` |
| **Error Rejection** | Verify compiler rejects invalid programs with correct error messages | Check stderr for expected error text |
| **Runtime Error** | Verify runtime errors produce correct diagnostics | Run program, check stderr exit code |
| **Regression** | Existing programs still compile and produce identical output | Full test suite re-run |

### 1.2 Test Naming Convention

```
test_class_<phase>_<feature>_<case>.bas
```

Examples:
```
test_class_p1_minimal.bas
test_class_p1_constructor_args.bas
test_class_p2_inherit_basic.bas
test_class_p3_is_nothing.bas
test_class_err_unknown_class.bas
```

### 1.3 Test Execution

Each test is a `.bas` file with expected output embedded in a trailing comment
block.  The test runner compiles, executes, and compares stdout against the
expected output:

```basic
' === test_class_p1_minimal.bas ===
CLASS Greeter
  Name AS STRING
END CLASS

DIM g AS Greeter = NEW Greeter()
g.Name = "World"
PRINT "Hello, "; g.Name
END

' EXPECTED OUTPUT:
' Hello, World
```

---

## 2. Phase 1 Tests: Core CLASS (MVP)

### T1.01 — Minimal class (fields only, no constructor)

```basic
CLASS Point
  X AS INTEGER
  Y AS INTEGER
END CLASS

DIM p AS Point = NEW Point()
p.X = 10
p.Y = 20
PRINT p.X; ","; p.Y
END
```

**Expected output:**
```
10,20
```

**Validates:** CLASS declaration, field declaration, NEW with no constructor,
field read/write via dot notation.

---

### T1.02 — Constructor with arguments

```basic
CLASS Greeter
  Greeting AS STRING

  CONSTRUCTOR(g AS STRING)
    ME.Greeting = g
  END CONSTRUCTOR
END CLASS

DIM g AS Greeter = NEW Greeter("Hello")
PRINT g.Greeting
END
```

**Expected output:**
```
Hello
```

**Validates:** CONSTRUCTOR parsing, ME keyword, constructor argument passing,
field initialisation from constructor.

---

### T1.03 — Method with no return value

```basic
CLASS Counter
  Value AS INTEGER

  CONSTRUCTOR()
    ME.Value = 0
  END CONSTRUCTOR

  METHOD Increment()
    ME.Value = ME.Value + 1
  END METHOD
END CLASS

DIM c AS Counter = NEW Counter()
c.Increment()
c.Increment()
c.Increment()
PRINT c.Value
END
```

**Expected output:**
```
3
```

**Validates:** METHOD declaration, method dispatch via vtable, ME field
access inside methods.

---

### T1.04 — Method with return value

```basic
CLASS Rectangle
  Width AS DOUBLE
  Height AS DOUBLE

  CONSTRUCTOR(w AS DOUBLE, h AS DOUBLE)
    ME.Width = w
    ME.Height = h
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN ME.Width * ME.Height
  END METHOD

  METHOD Perimeter() AS DOUBLE
    RETURN 2.0 * (ME.Width + ME.Height)
  END METHOD
END CLASS

DIM r AS Rectangle = NEW Rectangle(5.0, 3.0)
PRINT "Area: "; r.Area()
PRINT "Perimeter: "; r.Perimeter()
END
```

**Expected output:**
```
Area: 15
Perimeter: 16
```

**Validates:** Method return values, DOUBLE field types, multiple methods
on one class.

---

### T1.05 — Multiple fields of different types

```basic
CLASS Person
  Name AS STRING
  Age AS INTEGER
  Height AS DOUBLE

  CONSTRUCTOR(n AS STRING, a AS INTEGER, h AS DOUBLE)
    ME.Name = n
    ME.Age = a
    ME.Height = h
  END CONSTRUCTOR

  METHOD Describe()
    PRINT ME.Name; " is "; ME.Age; " years old, "; ME.Height; "m tall"
  END METHOD
END CLASS

DIM p AS Person = NEW Person("Alice", 30, 1.72)
p.Describe()
END
```

**Expected output:**
```
Alice is 30 years old, 1.72m tall
```

**Validates:** Mixed field types (STRING, INTEGER, DOUBLE), field alignment,
correct offsets in generated code.

---

### T1.06 — Multiple objects of the same class

```basic
CLASS Dog
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD Bark()
    PRINT ME.Name; " says Woof!"
  END METHOD
END CLASS

DIM a AS Dog = NEW Dog("Rex")
DIM b AS Dog = NEW Dog("Buddy")
DIM c AS Dog = NEW Dog("Max")
a.Bark()
b.Bark()
c.Bark()
END
```

**Expected output:**
```
Rex says Woof!
Buddy says Woof!
Max says Woof!
```

**Validates:** Multiple independent instances, each with own field storage.

---

### T1.07 — Object assignment (pointer semantics)

```basic
CLASS Box
  Label AS STRING

  CONSTRUCTOR(l AS STRING)
    ME.Label = l
  END CONSTRUCTOR
END CLASS

DIM a AS Box = NEW Box("Original")
DIM b AS Box = a
b.Label = "Modified"
PRINT a.Label
PRINT b.Label
END
```

**Expected output:**
```
Modified
Modified
```

**Validates:** Object variables hold pointers — assigning copies the pointer,
not the object.  Both `a` and `b` point to the same object.

---

### T1.08 — Constructor with zero arguments (explicit)

```basic
CLASS Timer
  Ticks AS INTEGER

  CONSTRUCTOR()
    ME.Ticks = 0
  END CONSTRUCTOR

  METHOD Tick()
    ME.Ticks = ME.Ticks + 1
  END METHOD
END CLASS

DIM t AS Timer = NEW Timer()
t.Tick()
t.Tick()
PRINT t.Ticks
END
```

**Expected output:**
```
2
```

**Validates:** Explicit zero-argument constructor.

---

### T1.09 — Class with no constructor (implicit default)

```basic
CLASS Flags
  A AS INTEGER
  B AS INTEGER
  C AS INTEGER
END CLASS

DIM f AS Flags = NEW Flags()
PRINT f.A; " "; f.B; " "; f.C
f.A = 1
f.B = 2
f.C = 3
PRINT f.A; " "; f.B; " "; f.C
END
```

**Expected output:**
```
0 0 0
1 2 3
```

**Validates:** Fields default to zero (calloc), no constructor needed for
simple data classes.

---

### T1.10 — Method calling another method via ME

```basic
CLASS Calculator
  Result AS DOUBLE

  CONSTRUCTOR()
    ME.Result = 0.0
  END CONSTRUCTOR

  METHOD Add(x AS DOUBLE)
    ME.Result = ME.Result + x
  END METHOD

  METHOD AddTwice(x AS DOUBLE)
    ME.Add(x)
    ME.Add(x)
  END METHOD

  METHOD GetResult() AS DOUBLE
    RETURN ME.Result
  END METHOD
END CLASS

DIM calc AS Calculator = NEW Calculator()
calc.AddTwice(5.0)
calc.Add(3.0)
PRINT calc.GetResult()
END
```

**Expected output:**
```
13
```

**Validates:** Methods calling other methods on the same object via ME,
vtable dispatch from within a method body.

---

### T1.11 — DIM with deferred NEW

```basic
CLASS Pair
  A AS INTEGER
  B AS INTEGER

  CONSTRUCTOR(a AS INTEGER, b AS INTEGER)
    ME.A = a
    ME.B = b
  END CONSTRUCTOR
END CLASS

DIM p AS Pair
p = NEW Pair(10, 20)
PRINT p.A; " "; p.B
END
```

**Expected output:**
```
10 20
```

**Validates:** Two-step declaration — DIM without NEW (initialises to NOTHING),
then assign a NEW object later.

---

### T1.12 — Passing object to SUB

```basic
CLASS Item
  Name AS STRING
  Price AS DOUBLE

  CONSTRUCTOR(n AS STRING, p AS DOUBLE)
    ME.Name = n
    ME.Price = p
  END CONSTRUCTOR
END CLASS

SUB ShowItem(item AS Item)
  PRINT item.Name; ": $"; item.Price
END SUB

DIM i AS Item = NEW Item("Widget", 9.99)
ShowItem(i)
END
```

**Expected output:**
```
Widget: $9.99
```

**Validates:** Passing objects to standalone SUBs, field access on parameter.

---

### T1.13 — Returning object from FUNCTION

```basic
CLASS Color
  R AS INTEGER
  G AS INTEGER
  B AS INTEGER

  CONSTRUCTOR(r AS INTEGER, g AS INTEGER, b AS INTEGER)
    ME.R = r
    ME.G = g
    ME.B = b
  END CONSTRUCTOR
END CLASS

FUNCTION MakeRed() AS Color
  RETURN NEW Color(255, 0, 0)
END FUNCTION

DIM c AS Color = MakeRed()
PRINT c.R; " "; c.G; " "; c.B
END
```

**Expected output:**
```
255 0 0
```

**Validates:** Returning class instances from FUNCTION, NEW inside FUNCTION body.

---

## 3. Phase 2 Tests: Inheritance

### T2.01 — Basic EXTENDS (field inheritance)

```basic
CLASS Animal
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
END CLASS

CLASS Dog EXTENDS Animal
  Breed AS STRING

  CONSTRUCTOR(n AS STRING, b AS STRING)
    SUPER(n)
    ME.Breed = b
  END CONSTRUCTOR
END CLASS

DIM d AS Dog = NEW Dog("Rex", "Labrador")
PRINT d.Name; " the "; d.Breed
END
```

**Expected output:**
```
Rex the Labrador
```

**Validates:** EXTENDS keyword, inherited fields accessible on child, SUPER()
constructor call.

---

### T2.02 — Method inheritance (no override)

```basic
CLASS Vehicle
  Speed AS INTEGER

  CONSTRUCTOR(s AS INTEGER)
    ME.Speed = s
  END CONSTRUCTOR

  METHOD Describe()
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

DIM c AS Car = NEW Car(120, 4)
c.Describe()
PRINT "Doors: "; c.Doors
END
```

**Expected output:**
```
Speed: 120
Doors: 4
```

**Validates:** Inherited methods work on child objects without override.

---

### T2.03 — Method override (polymorphism)

```basic
CLASS Shape
  METHOD Name() AS STRING
    RETURN "Shape"
  END METHOD
END CLASS

CLASS Circle EXTENDS Shape
  METHOD Name() AS STRING
    RETURN "Circle"
  END METHOD
END CLASS

CLASS Square EXTENDS Shape
  METHOD Name() AS STRING
    RETURN "Square"
  END METHOD
END CLASS

DIM s AS Shape = NEW Shape()
DIM c AS Shape = NEW Circle()
DIM q AS Shape = NEW Square()
PRINT s.Name()
PRINT c.Name()
PRINT q.Name()
END
```

**Expected output:**
```
Shape
Circle
Square
```

**Validates:** Virtual dispatch — calling method on Animal-typed variable
dispatches to the correct override based on actual object type.

---

### T2.04 — Polymorphic array

```basic
CLASS Animal
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " says ..."
  END METHOD
END CLASS

CLASS Dog EXTENDS Animal
  CONSTRUCTOR(n AS STRING)
    SUPER(n)
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " says Woof!"
  END METHOD
END CLASS

CLASS Cat EXTENDS Animal
  CONSTRUCTOR(n AS STRING)
    SUPER(n)
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " says Meow!"
  END METHOD
END CLASS

DIM zoo(2) AS Animal
zoo(0) = NEW Dog("Rex")
zoo(1) = NEW Cat("Whiskers")
zoo(2) = NEW Animal("Eagle")

FOR i = 0 TO 2
  zoo(i).Speak()
NEXT i
END
```

**Expected output:**
```
Rex says Woof!
Whiskers says Meow!
Eagle says ...
```

**Validates:** Array of base-type variables holding different derived objects,
vtable dispatch through array element access.

---

### T2.05 — SUPER.Method() in overridden method

```basic
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

DIM c AS Child = NEW Child()
c.Greet()
END
```

**Expected output:**
```
Hello from Child
Hello from Base
```

**Validates:** SUPER.Method() as a direct (non-virtual) call to parent
implementation from within an override.

---

### T2.06 — Three-level inheritance chain

```basic
CLASS A
  METHOD Who() AS STRING
    RETURN "A"
  END METHOD
END CLASS

CLASS B EXTENDS A
  METHOD Who() AS STRING
    RETURN "B"
  END METHOD
END CLASS

CLASS C EXTENDS B
  METHOD Who() AS STRING
    RETURN "C"
  END METHOD
END CLASS

DIM x AS A

x = NEW A()
PRINT x.Who()

x = NEW B()
PRINT x.Who()

x = NEW C()
PRINT x.Who()
END
```

**Expected output:**
```
A
B
C
```

**Validates:** Multi-level inheritance with correct vtable dispatch at each
level.

---

### T2.07 — SUPER() chaining through three levels

```basic
CLASS Level1
  Val1 AS INTEGER

  CONSTRUCTOR(v AS INTEGER)
    ME.Val1 = v
  END CONSTRUCTOR
END CLASS

CLASS Level2 EXTENDS Level1
  Val2 AS INTEGER

  CONSTRUCTOR(v1 AS INTEGER, v2 AS INTEGER)
    SUPER(v1)
    ME.Val2 = v2
  END CONSTRUCTOR
END CLASS

CLASS Level3 EXTENDS Level2
  Val3 AS INTEGER

  CONSTRUCTOR(v1 AS INTEGER, v2 AS INTEGER, v3 AS INTEGER)
    SUPER(v1, v2)
    ME.Val3 = v3
  END CONSTRUCTOR
END CLASS

DIM obj AS Level3 = NEW Level3(10, 20, 30)
PRINT obj.Val1; " "; obj.Val2; " "; obj.Val3
END
```

**Expected output:**
```
10 20 30
```

**Validates:** Constructor chaining via SUPER() through three levels of
inheritance, correct field layout across hierarchy.

---

### T2.08 — Mixed inherited and new methods

```basic
CLASS Base
  METHOD Alpha()
    PRINT "Alpha"
  END METHOD

  METHOD Beta()
    PRINT "Beta"
  END METHOD
END CLASS

CLASS Derived EXTENDS Base
  METHOD Beta()
    PRINT "Derived Beta"
  END METHOD

  METHOD Gamma()
    PRINT "Gamma"
  END METHOD
END CLASS

DIM d AS Derived = NEW Derived()
d.Alpha()
d.Beta()
d.Gamma()
END
```

**Expected output:**
```
Alpha
Derived Beta
Gamma
```

**Validates:** Inherited method (Alpha), overridden method (Beta), and new
method (Gamma) coexist correctly.  VTable slots assigned properly.

---

### T2.09 — Upcast assignment

```basic
CLASS Animal
  METHOD Kind() AS STRING
    RETURN "Animal"
  END METHOD
END CLASS

CLASS Dog EXTENDS Animal
  METHOD Kind() AS STRING
    RETURN "Dog"
  END METHOD
END CLASS

DIM a AS Animal
DIM d AS Dog = NEW Dog()

a = d
PRINT a.Kind()
END
```

**Expected output:**
```
Dog
```

**Validates:** Assigning a derived-type variable to a base-type variable
(upcast) preserves the actual object identity and dispatch.

---

## 4. Phase 3 Tests: IS, NOTHING, DELETE

### T3.01 — IS type check (same type)

```basic
CLASS Widget
END CLASS

DIM w AS Widget = NEW Widget()
IF w IS Widget THEN
  PRINT "Yes"
ELSE
  PRINT "No"
END IF
END
```

**Expected output:**
```
Yes
```

**Validates:** `IS` operator for same-type check.

---

### T3.02 — IS type check (subclass)

```basic
CLASS Animal
END CLASS

CLASS Dog EXTENDS Animal
END CLASS

DIM d AS Animal = NEW Dog()
IF d IS Animal THEN PRINT "Is Animal"
IF d IS Dog THEN PRINT "Is Dog"
END
```

**Expected output:**
```
Is Animal
Is Dog
```

**Validates:** `IS` walks the inheritance chain — a Dog IS both Dog and Animal.

---

### T3.03 — IS type check (negative)

```basic
CLASS Animal
END CLASS

CLASS Dog EXTENDS Animal
END CLASS

CLASS Cat EXTENDS Animal
END CLASS

DIM d AS Animal = NEW Dog()
IF d IS Cat THEN
  PRINT "Is Cat"
ELSE
  PRINT "Not Cat"
END IF
END
```

**Expected output:**
```
Not Cat
```

**Validates:** `IS` returns false for unrelated sibling classes.

---

### T3.04 — IS NOTHING check

```basic
CLASS Foo
END CLASS

DIM f AS Foo
IF f IS NOTHING THEN PRINT "Nothing"
f = NEW Foo()
IF f IS NOTHING THEN
  PRINT "Still nothing"
ELSE
  PRINT "Has value"
END IF
END
```

**Expected output:**
```
Nothing
Has value
```

**Validates:** `IS NOTHING` null-pointer check, before and after NEW.

---

### T3.05 — NOTHING assignment

```basic
CLASS Obj
  Value AS INTEGER

  CONSTRUCTOR(v AS INTEGER)
    ME.Value = v
  END CONSTRUCTOR
END CLASS

DIM o AS Obj = NEW Obj(42)
PRINT o.Value
o = NOTHING
IF o IS NOTHING THEN PRINT "Released"
END
```

**Expected output:**
```
42
Released
```

**Validates:** Assigning NOTHING to an object variable clears it.

---

### T3.06 — DELETE statement

```basic
CLASS Resource
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  DESTRUCTOR()
    PRINT "Destroying "; ME.Name
  END DESTRUCTOR
END CLASS

DIM r AS Resource = NEW Resource("File1")
PRINT "Before delete"
DELETE r
PRINT "After delete"
IF r IS NOTHING THEN PRINT "Variable is NOTHING"
END
```

**Expected output:**
```
Before delete
Destroying File1
After delete
Variable is NOTHING
```

**Validates:** DELETE calls destructor, frees memory, sets variable to NOTHING.

---

### T3.07 — DELETE on NOTHING (no-op)

```basic
CLASS Obj
END CLASS

DIM o AS Obj
DELETE o
PRINT "OK"
END
```

**Expected output:**
```
OK
```

**Validates:** DELETE on a NOTHING variable is a no-op (no crash).

---

### T3.08 — DESTRUCTOR chaining

```basic
CLASS Base
  DESTRUCTOR()
    PRINT "~Base"
  END DESTRUCTOR
END CLASS

CLASS Child EXTENDS Base
  DESTRUCTOR()
    PRINT "~Child"
  END DESTRUCTOR
END CLASS

DIM c AS Child = NEW Child()
DELETE c
END
```

**Expected output:**
```
~Child
~Base
```

**Validates:** Destructors chain automatically — child destructor runs first,
then parent destructor.

---

## 5. Phase 4 Tests: Polish & Integration

### T4.01 — Object field in another object

```basic
CLASS Engine
  Horsepower AS INTEGER

  CONSTRUCTOR(hp AS INTEGER)
    ME.Horsepower = hp
  END CONSTRUCTOR
END CLASS

CLASS Car
  Name AS STRING
  Motor AS Engine

  CONSTRUCTOR(n AS STRING, hp AS INTEGER)
    ME.Name = n
    ME.Motor = NEW Engine(hp)
  END CONSTRUCTOR

  METHOD Describe()
    PRINT ME.Name; " has "; ME.Motor.Horsepower; "hp"
  END METHOD
END CLASS

DIM c AS Car = NEW Car("Mustang", 450)
c.Describe()
END
```

**Expected output:**
```
Mustang has 450hp
```

**Validates:** Object fields (composition), chained member access (`obj.field.field`).

---

### T4.02 — Object in HASHMAP

```basic
CLASS User
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
END CLASS

DIM users AS HASHMAP
users("admin") = NEW User("Alice")
users("guest") = NEW User("Bob")

DIM u AS User = users("admin")
PRINT u.Name
END
```

**Expected output:**
```
Alice
```

**Validates:** Storing and retrieving object pointers in hashmaps.

---

### T4.03 — Multiple classes in one program

```basic
CLASS Point
  X AS INTEGER
  Y AS INTEGER

  CONSTRUCTOR(x AS INTEGER, y AS INTEGER)
    ME.X = x
    ME.Y = y
  END CONSTRUCTOR
END CLASS

CLASS Line
  Start AS Point
  Finish AS Point

  CONSTRUCTOR(x1 AS INTEGER, y1 AS INTEGER, x2 AS INTEGER, y2 AS INTEGER)
    ME.Start = NEW Point(x1, y1)
    ME.Finish = NEW Point(x2, y2)
  END CONSTRUCTOR

  METHOD Length() AS DOUBLE
    DIM dx AS DOUBLE = ME.Finish.X - ME.Start.X
    DIM dy AS DOUBLE = ME.Finish.Y - ME.Start.Y
    RETURN SQR(dx * dx + dy * dy)
  END METHOD
END CLASS

DIM l AS Line = NEW Line(0, 0, 3, 4)
PRINT "Length: "; l.Length()
END
```

**Expected output:**
```
Length: 5
```

**Validates:** Multiple interacting classes, composition, method with
computation across composed objects.

---

### T4.04 — Mixing CLASS and TYPE in same program

```basic
TYPE Coord
  X AS DOUBLE
  Y AS DOUBLE
END TYPE

CLASS Entity
  Name AS STRING
  Pos AS Coord

  CONSTRUCTOR(n AS STRING, x AS DOUBLE, y AS DOUBLE)
    ME.Name = n
    ME.Pos.X = x
    ME.Pos.Y = y
  END CONSTRUCTOR

  METHOD Show()
    PRINT ME.Name; " at ("; ME.Pos.X; ","; ME.Pos.Y; ")"
  END METHOD
END CLASS

DIM e AS Entity = NEW Entity("Player", 10.0, 20.0)
e.Show()
END
```

**Expected output:**
```
Player at (10,20)
```

**Validates:** TYPE used as a field inside a CLASS, accessing TYPE fields
through an object.

---

### T4.05 — Large class with many methods

```basic
CLASS MathHelper
  METHOD Square(x AS INTEGER) AS INTEGER
    RETURN x * x
  END METHOD

  METHOD Cube(x AS INTEGER) AS INTEGER
    RETURN x * x * x
  END METHOD

  METHOD Double(x AS INTEGER) AS INTEGER
    RETURN x * 2
  END METHOD

  METHOD Half(x AS INTEGER) AS INTEGER
    RETURN x / 2
  END METHOD

  METHOD Negate(x AS INTEGER) AS INTEGER
    RETURN 0 - x
  END METHOD
END CLASS

DIM m AS MathHelper = NEW MathHelper()
PRINT m.Square(5)
PRINT m.Cube(3)
PRINT m.Double(7)
PRINT m.Half(10)
PRINT m.Negate(42)
END
```

**Expected output:**
```
25
27
14
5
-42
```

**Validates:** Class with 5+ methods, correct vtable slot assignment for
each, no method-slot confusion.

---

## 6. Compiler Error Tests

These tests verify that the compiler rejects invalid programs with clear,
helpful error messages.

### E6.01 — Unknown class in NEW

```basic
DIM x AS Foo = NEW Foo()
END
```

**Expected error:** `CLASS 'Foo' is not defined`

---

### E6.02 — Wrong number of constructor arguments

```basic
CLASS Dog
  CONSTRUCTOR(name AS STRING, breed AS STRING)
  END CONSTRUCTOR
END CLASS

DIM d AS Dog = NEW Dog("Rex")
END
```

**Expected error:** `CONSTRUCTOR for 'Dog' expects 2 arguments, got 1`

---

### E6.03 — Unknown method

```basic
CLASS Cat
END CLASS

DIM c AS Cat = NEW Cat()
c.Fly()
END
```

**Expected error:** `CLASS 'Cat' has no method 'Fly'`

---

### E6.04 — Unknown field

```basic
CLASS Cat
END CLASS

DIM c AS Cat = NEW Cat()
PRINT c.Wings
END
```

**Expected error:** `CLASS 'Cat' has no field 'Wings'`

---

### E6.05 — ME outside class

```basic
PRINT ME.Name
END
```

**Expected error:** `ME can only be used inside a METHOD or CONSTRUCTOR`

---

### E6.06 — SUPER without parent

```basic
CLASS Root
  CONSTRUCTOR()
    SUPER()
  END CONSTRUCTOR
END CLASS
```

**Expected error:** `SUPER can only be used in a class that EXTENDS another class`

---

### E6.07 — SUPER not first statement

```basic
CLASS Base
  CONSTRUCTOR()
  END CONSTRUCTOR
END CLASS

CLASS Child EXTENDS Base
  CONSTRUCTOR()
    PRINT "Before super"
    SUPER()
  END CONSTRUCTOR
END CLASS
```

**Expected error:** `SUPER() must be the first statement in CONSTRUCTOR`

---

### E6.08 — Circular inheritance

```basic
CLASS A EXTENDS B
END CLASS

CLASS B EXTENDS A
END CLASS
```

**Expected error:** `Circular inheritance detected: A → B → A`

---

### E6.09 — Duplicate method in same class

```basic
CLASS Foo
  METHOD Bar()
  END METHOD

  METHOD Bar()
  END METHOD
END CLASS
```

**Expected error:** `METHOD 'Bar' is already defined in CLASS 'Foo'`

---

### E6.10 — Override signature mismatch

```basic
CLASS Base
  METHOD Calc(x AS INTEGER) AS INTEGER
    RETURN x
  END METHOD
END CLASS

CLASS Child EXTENDS Base
  METHOD Calc(x AS STRING) AS STRING
    RETURN x
  END METHOD
END CLASS
```

**Expected error:** `METHOD 'Calc' in 'Child' has different parameters than in parent 'Base'`

---

### E6.11 — Type mismatch on assignment (sibling classes)

```basic
CLASS Dog
END CLASS

CLASS Cat
END CLASS

DIM d AS Dog = NEW Dog()
DIM c AS Cat = d
END
```

**Expected error:** `Cannot assign 'Dog' to variable of type 'Cat' (not in inheritance chain)`

---

### E6.12 — Nested class declaration

```basic
CLASS Outer
  CLASS Inner
  END CLASS
END CLASS
```

**Expected error:** `CLASS declarations cannot be nested`

---

### E6.13 — Class inside SUB

```basic
SUB Foo()
  CLASS Inner
  END CLASS
END SUB
```

**Expected error:** `CLASS declarations must be at the top level`

---

### E6.14 — Forward reference to undeclared parent

```basic
CLASS Child EXTENDS Parent
END CLASS

CLASS Parent
END CLASS
```

**Expected error:** `CLASS 'Parent' is not defined` (forward references not allowed)

---

## 7. Runtime Error Tests

These tests compile successfully but produce runtime errors.

### R7.01 — Method call on NOTHING

```basic
CLASS Obj
  METHOD DoSomething()
    PRINT "Hi"
  END METHOD
END CLASS

DIM o AS Obj
o.DoSomething()
END
```

**Expected runtime error:**
```
ERROR: Method call on NOTHING reference at line 8
```

---

### R7.02 — Field access on NOTHING

```basic
CLASS Obj
  Value AS INTEGER
END CLASS

DIM o AS Obj
PRINT o.Value
END
```

**Expected runtime error:**
```
ERROR: Field access on NOTHING reference at line 6
```

---

## 8. QBE IL Verification Tests

These tests check that the generated QBE IL contains the expected patterns
rather than running the program.  Use `fbc_qbe -i prog.bas` and grep
for patterns.

### IL8.01 — VTable data section emitted

```basic
CLASS Dog
  METHOD Bark()
    PRINT "Woof"
  END METHOD
END CLASS
```

**Check IL contains:**
```
data $vtable_Dog = {
```
and
```
l $Dog__Bark
```

---

### IL8.02 — Constructor emitted as function

```basic
CLASS Foo
  X AS INTEGER
  CONSTRUCTOR(x AS INTEGER)
    ME.X = x
  END CONSTRUCTOR
END CLASS
```

**Check IL contains:**
```
function $Foo__CONSTRUCTOR(l %me, w %x) {
```

---

### IL8.03 — NEW calls class_object_new

```basic
CLASS Bar
END CLASS

DIM b AS Bar = NEW Bar()
END
```

**Check IL contains:**
```
call $class_object_new(
```

---

### IL8.04 — Method dispatch through vtable

```basic
CLASS Obj
  METHOD Test()
  END METHOD
END CLASS

DIM o AS Obj = NEW Obj()
o.Test()
END
```

**Check IL contains (dispatch sequence):**
```
loadl %           # load vtable from object
add %             # compute method slot address
loadl %           # load function pointer from slot
call %            # indirect call
```

---

### IL8.05 — Null check before method call

```basic
CLASS Obj
  METHOD Test()
  END METHOD
END CLASS

DIM o AS Obj = NEW Obj()
o.Test()
END
```

**Check IL contains:**
```
ceql %            # compare with 0
jnz %             # branch to error or ok
```
and
```
call $class_null_method_error(
```

---

## 9. Regression Tests

### R9.01 — Existing TYPE programs unchanged

All existing `.bas` test files that use TYPE declarations must continue to
compile and produce identical output after CLASS support is added.

**Test method:** Run the full existing test suite; compare output
against golden files.

---

### R9.02 — IS keyword backward compatibility

The `IS` keyword is already used in `CASE IS` / `SELECT CASE` contexts.
Verify that existing SELECT CASE programs still work:

```basic
DIM x AS INTEGER = 3
SELECT CASE x
  CASE IS < 5
    PRINT "Small"
  CASE IS >= 5
    PRINT "Big"
END SELECT
END
```

**Expected output:**
```
Small
```

**Validates:** `IS` in SELECT CASE context still works correctly alongside
the new `IS` type-check operator.

---

### R9.03 — NEW keyword doesn't conflict

Verify that `NEW` as a keyword doesn't break any existing programs.  Search
all existing test files for any variable or function named `NEW` — there
should be none since `NEW` is being reserved.

---

## 10. Performance Benchmarks

### B10.01 — Object creation throughput

```basic
CLASS Obj
  X AS INTEGER
  CONSTRUCTOR(x AS INTEGER)
    ME.X = x
  END CONSTRUCTOR
END CLASS

DIM start AS DOUBLE = TIMER
FOR i = 1 TO 1000000
  DIM o AS Obj = NEW Obj(i)
  DELETE o
NEXT i
DIM elapsed AS DOUBLE = TIMER - start
PRINT "1M create+delete: "; elapsed; " seconds"
END
```

**Target:** < 1 second on Apple M-series.

---

### B10.02 — Method dispatch throughput

```basic
CLASS Counter
  N AS INTEGER
  METHOD Inc()
    ME.N = ME.N + 1
  END METHOD
END CLASS

DIM c AS Counter = NEW Counter()
DIM start AS DOUBLE = TIMER
FOR i = 1 TO 10000000
  c.Inc()
NEXT i
DIM elapsed AS DOUBLE = TIMER - start
PRINT "10M method calls: "; elapsed; " seconds"
PRINT "Count: "; c.N
END
```

**Target:** < 0.5 seconds on Apple M-series (vtable dispatch should be
near-zero overhead with branch prediction).

---

### B10.03 — Polymorphic dispatch throughput

```basic
CLASS Base
  METHOD Work()
  END METHOD
END CLASS

CLASS Impl1 EXTENDS Base
  METHOD Work()
  END METHOD
END CLASS

CLASS Impl2 EXTENDS Base
  METHOD Work()
  END METHOD
END CLASS

DIM a AS Base = NEW Impl1()
DIM b AS Base = NEW Impl2()
DIM start AS DOUBLE = TIMER
FOR i = 1 TO 5000000
  a.Work()
  b.Work()
NEXT i
DIM elapsed AS DOUBLE = TIMER - start
PRINT "10M polymorphic calls: "; elapsed; " seconds"
END
```

**Target:** < 0.5 seconds (indirect call overhead is minimal).

---

## Appendix: Test Matrix Summary

| ID | Category | Description | Phase |
|----|----------|-------------|-------|
| T1.01–T1.13 | Core CLASS | Fields, constructor, methods, NEW, ME | 1 |
| T2.01–T2.09 | Inheritance | EXTENDS, SUPER, override, polymorphism | 2 |
| T3.01–T3.08 | IS/NOTHING/DELETE | Type checks, null safety, cleanup | 3 |
| T4.01–T4.05 | Integration | Composition, HASHMAP, TYPE, multi-class | 4 |
| E6.01–E6.14 | Compiler errors | Invalid programs rejected with clear messages | 1–3 |
| R7.01–R7.02 | Runtime errors | Null dereference diagnostics | 3 |
| IL8.01–IL8.05 | IL verification | QBE output structure correctness | 1–2 |
| R9.01–R9.03 | Regression | Existing programs unaffected | 1 |
| B10.01–B10.03 | Performance | Creation, dispatch, polymorphism throughput | 4 |
| **Total** | | **49 tests** | |