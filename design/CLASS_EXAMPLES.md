# FasterBASIC CLASS & OBJECT — Practical Examples

**Companion to:** `CLASS_OBJECT_DESIGN.md` and `CLASS_IMPLEMENTATION.md`

---

## Table of Contents

1. [Minimal Class](#1-minimal-class)
2. [Constructor & Fields](#2-constructor--fields)
3. [Methods with Return Values](#3-methods-with-return-values)
4. [Single Inheritance](#4-single-inheritance)
5. [Polymorphism with Arrays](#5-polymorphism-with-arrays)
6. [ME and Field Access Patterns](#6-me-and-field-access-patterns)
7. [SUPER Calls](#7-super-calls)
8. [IS Type Checking](#8-is-type-checking)
9. [NOTHING and Null Safety](#9-nothing-and-null-safety)
10. [Mixing CLASS and TYPE](#10-mixing-class-and-type)
11. [Objects in Collections](#11-objects-in-collections)
12. [Real-World Pattern: State Machine](#12-real-world-pattern-state-machine)
13. [Real-World Pattern: Linked List](#13-real-world-pattern-linked-list)
14. [Real-World Pattern: Plugin System](#14-real-world-pattern-plugin-system)
15. [Real-World Pattern: Game Entity System](#15-real-world-pattern-game-entity-system)
16. [Real-World Pattern: Menu System](#16-real-world-pattern-menu-system)
17. [Anti-Patterns and Pitfalls](#17-anti-patterns-and-pitfalls)

---

## 1. Minimal Class

The simplest possible class — just fields, no constructor, no methods.
Behaves like a TYPE but heap-allocated.

```basic
CLASS Counter
  Value AS INTEGER
END CLASS

DIM c AS Counter = NEW Counter()
c.Value = 0
c.Value = c.Value + 1
PRINT "Counter: "; c.Value
```

**Output:**
```
Counter: 1
```

**When to use this instead of TYPE:**
You wouldn't, usually. Once you need behaviour or inheritance, upgrade to
methods. For flat data with no behaviour, TYPE is still the right choice.

---

## 2. Constructor & Fields

A constructor initialises an object to a valid state. Without a constructor,
all fields start at their zero value (0 for numbers, "" for strings,
NOTHING for object references).

```basic
CLASS Circle
  Radius AS DOUBLE
  X AS DOUBLE
  Y AS DOUBLE

  CONSTRUCTOR(r AS DOUBLE, cx AS DOUBLE, cy AS DOUBLE)
    ME.Radius = r
    ME.X = cx
    ME.Y = cy
  END CONSTRUCTOR
END CLASS

DIM c AS Circle = NEW Circle(5.0, 10.0, 20.0)
PRINT "Circle at ("; c.X; ", "; c.Y; ") radius "; c.Radius
```

**Output:**
```
Circle at (10, 20) radius 5
```

---

## 3. Methods with Return Values

Methods that compute and return values use `AS ReturnType` and `RETURN`.

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
    RETURN 2 * (ME.Width + ME.Height)
  END METHOD

  METHOD IsSquare() AS INTEGER
    IF ME.Width = ME.Height THEN
      RETURN 1
    ELSE
      RETURN 0
    END IF
  END METHOD

  METHOD Scale(factor AS DOUBLE)
    ME.Width = ME.Width * factor
    ME.Height = ME.Height * factor
  END METHOD

  METHOD Display()
    PRINT "Rectangle "; ME.Width; " x "; ME.Height;
    PRINT "  area="; ME.Area(); "  perim="; ME.Perimeter()
  END METHOD
END CLASS


DIM r AS Rectangle = NEW Rectangle(4.0, 6.0)
r.Display()

r.Scale(2.0)
r.Display()

DIM sq AS Rectangle = NEW Rectangle(5.0, 5.0)
IF sq.IsSquare() THEN PRINT "5x5 is a square"
```

**Output:**
```
Rectangle 4 x 6  area=24  perim=20
Rectangle 8 x 12  area=96  perim=40
5x5 is a square
```

---

## 4. Single Inheritance

A child class inherits all fields and methods from its parent. It can add
new fields and methods, and override parent methods.

```basic
CLASS Vehicle
  Name AS STRING
  Speed AS INTEGER
  Fuel AS INTEGER

  CONSTRUCTOR(n AS STRING, topSpeed AS INTEGER)
    ME.Name = n
    ME.Speed = topSpeed
    ME.Fuel = 100
  END CONSTRUCTOR

  METHOD Drive(distance AS INTEGER)
    DIM fuelUsed AS INTEGER
    fuelUsed = distance / 10
    ME.Fuel = ME.Fuel - fuelUsed
    IF ME.Fuel < 0 THEN ME.Fuel = 0
    PRINT ME.Name; " drove "; distance; " km. Fuel: "; ME.Fuel; "%"
  END METHOD

  METHOD Honk()
    PRINT ME.Name; ": Beep beep!"
  END METHOD
END CLASS


CLASS Truck EXTENDS Vehicle
  CargoWeight AS INTEGER

  CONSTRUCTOR(n AS STRING, cargo AS INTEGER)
    SUPER(n, 100)
    ME.CargoWeight = cargo
  END CONSTRUCTOR

  METHOD Honk()
    PRINT ME.Name; ": HOOOONK! (carrying "; ME.CargoWeight; " kg)"
  END METHOD

  METHOD Unload()
    PRINT "Unloading "; ME.CargoWeight; " kg from "; ME.Name
    ME.CargoWeight = 0
  END METHOD
END CLASS


CLASS SportsCar EXTENDS Vehicle
  Turbo AS INTEGER

  CONSTRUCTOR(n AS STRING)
    SUPER(n, 250)
    ME.Turbo = 0
  END CONSTRUCTOR

  METHOD EngageTurbo()
    ME.Turbo = 1
    PRINT ME.Name; ": TURBO ENGAGED!"
  END METHOD

  METHOD Honk()
    PRINT ME.Name; ": *aggressive horn*"
  END METHOD
END CLASS


' --- Main ---

DIM t AS Truck = NEW Truck("Big Rig", 5000)
t.Honk()
t.Drive(50)
t.Unload()

PRINT ""

DIM s AS SportsCar = NEW SportsCar("Ferrari")
s.Honk()
s.EngageTurbo()
s.Drive(100)
```

**Output:**
```
Big Rig: HOOOONK! (carrying 5000 kg)
Big Rig drove 50 km. Fuel: 95%
Unloading 5000 kg from Big Rig

Ferrari: *aggressive horn*
Ferrari: TURBO ENGAGED!
Ferrari drove 100 km. Fuel: 90%
```

---

## 5. Polymorphism with Arrays

The core power of OOP: store objects of different classes in a single array
typed as the parent class, and method calls dispatch to the correct override.

```basic
CLASS Shape
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN 0.0
  END METHOD

  METHOD Describe()
    PRINT ME.Name; ": area = "; ME.Area()
  END METHOD
END CLASS


CLASS CircleShape EXTENDS Shape
  Radius AS DOUBLE

  CONSTRUCTOR(r AS DOUBLE)
    SUPER("Circle")
    ME.Radius = r
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN 3.14159 * ME.Radius * ME.Radius
  END METHOD
END CLASS


CLASS SquareShape EXTENDS Shape
  Side AS DOUBLE

  CONSTRUCTOR(s AS DOUBLE)
    SUPER("Square")
    ME.Side = s
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN ME.Side * ME.Side
  END METHOD
END CLASS


CLASS TriangleShape EXTENDS Shape
  Base AS DOUBLE
  Height AS DOUBLE

  CONSTRUCTOR(b AS DOUBLE, h AS DOUBLE)
    SUPER("Triangle")
    ME.Base = b
    ME.Height = h
  END CONSTRUCTOR

  METHOD Area() AS DOUBLE
    RETURN 0.5 * ME.Base * ME.Height
  END METHOD
END CLASS


' --- Main ---

DIM shapes(3) AS Shape
shapes(0) = NEW CircleShape(5.0)
shapes(1) = NEW SquareShape(4.0)
shapes(2) = NEW TriangleShape(6.0, 3.0)

PRINT "=== Shape Gallery ==="
DIM totalArea AS DOUBLE
totalArea = 0

FOR i = 0 TO 2
  shapes(i).Describe()                  ' polymorphic dispatch
  totalArea = totalArea + shapes(i).Area()
NEXT i

PRINT ""
PRINT "Total area: "; totalArea
```

**Output:**
```
=== Shape Gallery ===
Circle: area = 78.53975
Square: area = 16
Triangle: area = 9

Total area: 103.53975
```

---

## 6. ME and Field Access Patterns

`ME` is required to access fields and call methods on the current object
inside a METHOD or CONSTRUCTOR. This avoids ambiguity with local variables.

```basic
CLASS BankAccount
  Owner AS STRING
  Balance AS DOUBLE

  CONSTRUCTOR(owner AS STRING, initialDeposit AS DOUBLE)
    ME.Owner = owner            ' ME.Owner is the field
    ME.Balance = initialDeposit ' owner would be the parameter
  END CONSTRUCTOR

  METHOD Deposit(amount AS DOUBLE)
    ME.Balance = ME.Balance + amount
    PRINT ME.Owner; ": deposited "; amount; " → balance "; ME.Balance
  END METHOD

  METHOD Withdraw(amount AS DOUBLE) AS INTEGER
    IF amount > ME.Balance THEN
      PRINT ME.Owner; ": insufficient funds (need "; amount; ", have "; ME.Balance; ")"
      RETURN 0
    END IF
    ME.Balance = ME.Balance - amount
    PRINT ME.Owner; ": withdrew "; amount; " → balance "; ME.Balance
    RETURN 1
  END METHOD

  METHOD Transfer(target AS BankAccount, amount AS DOUBLE)
    IF ME.Withdraw(amount) THEN     ' ME.Withdraw calls own method
      target.Deposit(amount)
      PRINT "Transfer complete"
    ELSE
      PRINT "Transfer failed"
    END IF
  END METHOD
END CLASS


DIM alice AS BankAccount = NEW BankAccount("Alice", 1000.0)
DIM bob AS BankAccount = NEW BankAccount("Bob", 500.0)

alice.Deposit(200.0)
bob.Withdraw(100.0)
alice.Transfer(bob, 300.0)

PRINT ""
PRINT "Final balances:"
PRINT "  Alice: "; alice.Balance
PRINT "  Bob:   "; bob.Balance
```

**Output:**
```
Alice: deposited 200 → balance 1200
Bob: withdrew 100 → balance 400
Alice: withdrew 300 → balance 900
Bob: deposited 300 → balance 700
Transfer complete

Final balances:
  Alice: 900
  Bob: 700
```

---

## 7. SUPER Calls

### 7.1 SUPER() in CONSTRUCTOR

Call the parent constructor to initialise inherited fields.

```basic
CLASS Animal
  Name AS STRING
  Legs AS INTEGER

  CONSTRUCTOR(n AS STRING, l AS INTEGER)
    ME.Name = n
    ME.Legs = l
  END CONSTRUCTOR

  METHOD Info()
    PRINT ME.Name; " ("; ME.Legs; " legs)"
  END METHOD
END CLASS


CLASS Pet EXTENDS Animal
  OwnerName AS STRING

  CONSTRUCTOR(name AS STRING, legs AS INTEGER, owner AS STRING)
    SUPER(name, legs)          ' initialise Animal fields
    ME.OwnerName = owner       ' initialise own field
  END CONSTRUCTOR

  METHOD Info()
    PRINT ME.Name; " ("; ME.Legs; " legs), owned by "; ME.OwnerName
  END METHOD
END CLASS


DIM p AS Pet = NEW Pet("Buddy", 4, "Sarah")
p.Info()
```

**Output:**
```
Buddy (4 legs), owned by Sarah
```

### 7.2 SUPER.Method() in METHOD

Call the parent's version of an overridden method.

```basic
CLASS Logger
  Prefix AS STRING

  CONSTRUCTOR(prefix AS STRING)
    ME.Prefix = prefix
  END CONSTRUCTOR

  METHOD Log(message AS STRING)
    PRINT ME.Prefix; ": "; message
  END METHOD
END CLASS


CLASS TimestampLogger EXTENDS Logger

  CONSTRUCTOR(prefix AS STRING)
    SUPER(prefix)
  END CONSTRUCTOR

  METHOD Log(message AS STRING)
    PRINT "[12:34:56] ";      ' in real code, get actual time
    SUPER.Log(message)         ' call parent Logger.Log
  END METHOD
END CLASS


DIM log AS TimestampLogger = NEW TimestampLogger("APP")
log.Log("Server started")
log.Log("Ready for connections")
```

**Output:**
```
[12:34:56] APP: Server started
[12:34:56] APP: Ready for connections
```

---

## 8. IS Type Checking

`IS` checks whether an object is an instance of a specific class
(including subclasses).

```basic
CLASS Fruit
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
END CLASS

CLASS Apple EXTENDS Fruit
  Variety AS STRING

  CONSTRUCTOR(variety AS STRING)
    SUPER("Apple")
    ME.Variety = variety
  END CONSTRUCTOR
END CLASS

CLASS Banana EXTENDS Fruit
  CONSTRUCTOR()
    SUPER("Banana")
  END CONSTRUCTOR
END CLASS


' --- Main ---

DIM basket(2) AS Fruit
basket(0) = NEW Apple("Granny Smith")
basket(1) = NEW Banana()
basket(2) = NEW Apple("Fuji")

DIM appleCount AS INTEGER
appleCount = 0

FOR i = 0 TO 2
  IF basket(i) IS Apple THEN
    appleCount = appleCount + 1
  END IF
  IF basket(i) IS Fruit THEN
    PRINT basket(i).Name; " is a Fruit"      ' always true
  END IF
NEXT i

PRINT ""
PRINT "Apples in basket: "; appleCount
```

**Output:**
```
Apple is a Fruit
Banana is a Fruit
Apple is a Fruit

Apples in basket: 2
```

---

## 9. NOTHING and Null Safety

```basic
CLASS Player
  Name AS STRING
  Score AS INTEGER

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
    ME.Score = 0
  END CONSTRUCTOR

  METHOD AddPoints(pts AS INTEGER)
    ME.Score = ME.Score + pts
    PRINT ME.Name; " now has "; ME.Score; " points"
  END METHOD
END CLASS


' Variables start as NOTHING
DIM p AS Player

IF p IS NOTHING THEN
  PRINT "No player yet — creating one..."
  p = NEW Player("Hero")
END IF

p.AddPoints(100)

' Releasing the reference
DELETE p

IF p IS NOTHING THEN
  PRINT "Player has been deleted"
END IF

' This would cause a runtime error:
' p.AddPoints(50)   → ERROR: Method call on NOTHING reference
```

**Output:**
```
No player yet — creating one...
Hero now has 100 points
Player has been deleted
```

---

## 10. Mixing CLASS and TYPE

TYPE and CLASS coexist naturally. Use TYPE for small value-like data
(especially SIMD-friendly structures), and CLASS for objects with behaviour.

```basic
TYPE Vec2D
  X AS DOUBLE
  Y AS DOUBLE
END TYPE

CLASS Particle
  Position AS Vec2D
  Velocity AS Vec2D
  Mass AS DOUBLE
  Active AS INTEGER

  CONSTRUCTOR(x AS DOUBLE, y AS DOUBLE, mass AS DOUBLE)
    ME.Position.X = x
    ME.Position.Y = y
    ME.Velocity.X = 0
    ME.Velocity.Y = 0
    ME.Mass = mass
    ME.Active = 1
  END CONSTRUCTOR

  METHOD ApplyForce(fx AS DOUBLE, fy AS DOUBLE)
    ME.Velocity.X = ME.Velocity.X + fx / ME.Mass
    ME.Velocity.Y = ME.Velocity.Y + fy / ME.Mass
  END METHOD

  METHOD Update(dt AS DOUBLE)
    IF ME.Active = 0 THEN RETURN
    ME.Position.X = ME.Position.X + ME.Velocity.X * dt
    ME.Position.Y = ME.Position.Y + ME.Velocity.Y * dt
  END METHOD

  METHOD Show()
    IF ME.Active THEN
      PRINT "Particle at ("; ME.Position.X; ", "; ME.Position.Y; ")";
      PRINT " vel ("; ME.Velocity.X; ", "; ME.Velocity.Y; ")"
    ELSE
      PRINT "Particle [inactive]"
    END IF
  END METHOD
END CLASS


DIM p AS Particle = NEW Particle(0, 0, 1.0)
p.Show()

p.ApplyForce(10.0, 5.0)
p.Update(0.1)
p.Show()

p.Update(0.1)
p.Show()
```

**Output:**
```
Particle at (0, 0) vel (0, 0)
Particle at (1, 0.5) vel (10, 5)
Particle at (2, 1) vel (10, 5)
```

---

## 11. Objects in Collections

Objects can be stored in arrays and hashmaps.

```basic
CLASS Student
  Name AS STRING
  Grade AS INTEGER

  CONSTRUCTOR(name AS STRING, grade AS INTEGER)
    ME.Name = name
    ME.Grade = grade
  END CONSTRUCTOR

  METHOD Display()
    PRINT "  "; ME.Name; ": grade "; ME.Grade
  END METHOD
END CLASS


' Array of objects
DIM roster(3) AS Student
roster(0) = NEW Student("Alice", 95)
roster(1) = NEW Student("Bob", 87)
roster(2) = NEW Student("Charlie", 92)
roster(3) = NEW Student("Diana", 88)

PRINT "=== Class Roster ==="
DIM total AS INTEGER
total = 0
FOR i = 0 TO 3
  roster(i).Display()
  total = total + roster(i).Grade
NEXT i
PRINT "Average: "; total / 4

' Objects in a hashmap (stored by reference as pointer)
DIM directory AS HASHMAP
directory("alice") = roster(0)
directory("bob") = roster(1)
```

**Output:**
```
=== Class Roster ===
  Alice: grade 95
  Bob: grade 87
  Charlie: grade 92
  Diana: grade 88
Average: 90
```

---

## 12. Real-World Pattern: State Machine

A clean state-machine pattern using polymorphism — each state is a class
that handles events differently.

```basic
CLASS GameState
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD OnEnter()
    PRINT "Entering state: "; ME.Name
  END METHOD

  METHOD OnUpdate() AS INTEGER
    ' Return 1 to transition, 0 to stay
    RETURN 0
  END METHOD

  METHOD OnExit()
    PRINT "Leaving state: "; ME.Name
  END METHOD
END CLASS


CLASS MenuState EXTENDS GameState
  Selected AS INTEGER

  CONSTRUCTOR()
    SUPER("Menu")
    ME.Selected = 0
  END CONSTRUCTOR

  METHOD OnEnter()
    PRINT "=== MAIN MENU ==="
    PRINT "1. Start Game"
    PRINT "2. Quit"
  END METHOD

  METHOD OnUpdate() AS INTEGER
    ME.Selected = 1       ' simulate user picking "Start Game"
    PRINT "Player selected: Start Game"
    RETURN 1              ' transition to next state
  END METHOD
END CLASS


CLASS PlayState EXTENDS GameState
  Score AS INTEGER
  Turns AS INTEGER

  CONSTRUCTOR()
    SUPER("Playing")
    ME.Score = 0
    ME.Turns = 0
  END CONSTRUCTOR

  METHOD OnEnter()
    PRINT "=== GAME START ==="
    PRINT "Get ready!"
  END METHOD

  METHOD OnUpdate() AS INTEGER
    ME.Turns = ME.Turns + 1
    ME.Score = ME.Score + 10
    PRINT "Turn "; ME.Turns; " — Score: "; ME.Score
    IF ME.Turns >= 3 THEN RETURN 1   ' game over after 3 turns
    RETURN 0
  END METHOD

  METHOD OnExit()
    PRINT "Game over! Final score: "; ME.Score
  END METHOD
END CLASS


CLASS GameOverState EXTENDS GameState
  CONSTRUCTOR()
    SUPER("Game Over")
  END CONSTRUCTOR

  METHOD OnEnter()
    PRINT "=== GAME OVER ==="
    PRINT "Thanks for playing!"
  END METHOD
END CLASS


' --- State Machine Runner ---

DIM states(2) AS GameState
states(0) = NEW MenuState()
states(1) = NEW PlayState()
states(2) = NEW GameOverState()

DIM current AS INTEGER
current = 0

FOR step = 0 TO 10
  states(current).OnEnter()
  DIM shouldTransition AS INTEGER
  shouldTransition = states(current).OnUpdate()
  IF shouldTransition THEN
    states(current).OnExit()
    current = current + 1
    IF current > 2 THEN EXIT FOR
  ELSE
    EXIT FOR
  END IF
NEXT step
```

**Output:**
```
=== MAIN MENU ===
1. Start Game
2. Quit
Player selected: Start Game
Leaving state: Menu
=== GAME START ===
Get ready!
Turn 1 — Score: 10
Turn 2 — Score: 20
Turn 3 — Score: 30
Game over! Final score: 30
=== GAME OVER ===
Thanks for playing!
```

---

## 13. Real-World Pattern: Linked List

A simple singly-linked list built with classes. Demonstrates objects
referencing other objects of the same type.

```basic
CLASS ListNode
  Value AS STRING
  Next AS ListNode         ' self-referential: node points to next node

  CONSTRUCTOR(v AS STRING)
    ME.Value = v
    ' ME.Next starts as NOTHING (null)
  END CONSTRUCTOR
END CLASS


CLASS LinkedList
  Head AS ListNode
  Count AS INTEGER

  CONSTRUCTOR()
    ME.Count = 0
  END CONSTRUCTOR

  METHOD Prepend(value AS STRING)
    DIM node AS ListNode = NEW ListNode(value)
    node.Next = ME.Head
    ME.Head = node
    ME.Count = ME.Count + 1
  END METHOD

  METHOD Display()
    DIM current AS ListNode
    current = ME.Head
    PRINT "List ("; ME.Count; " items): ";
    DO WHILE NOT (current IS NOTHING)
      PRINT current.Value;
      IF NOT (current.Next IS NOTHING) THEN PRINT " -> ";
      current = current.Next
    LOOP
    PRINT ""
  END METHOD

  METHOD Contains(value AS STRING) AS INTEGER
    DIM current AS ListNode
    current = ME.Head
    DO WHILE NOT (current IS NOTHING)
      IF current.Value = value THEN RETURN 1
      current = current.Next
    LOOP
    RETURN 0
  END METHOD
END CLASS


' --- Main ---

DIM list AS LinkedList = NEW LinkedList()
list.Prepend("Charlie")
list.Prepend("Bob")
list.Prepend("Alice")

list.Display()

IF list.Contains("Bob") THEN PRINT "Found Bob!"
IF NOT list.Contains("Dave") THEN PRINT "Dave not found"
```

**Output:**
```
List (3 items): Alice -> Bob -> Charlie
Found Bob!
Dave not found
```

---

## 14. Real-World Pattern: Plugin System

Using inheritance to create a simple plugin architecture. Each plugin
extends a base class and provides its own behaviour.

```basic
CLASS Plugin
  Name AS STRING
  Version AS STRING
  Enabled AS INTEGER

  CONSTRUCTOR(name AS STRING, version AS STRING)
    ME.Name = name
    ME.Version = version
    ME.Enabled = 1
  END CONSTRUCTOR

  METHOD Init()
    PRINT "["; ME.Name; " v"; ME.Version; "] Initialised"
  END METHOD

  METHOD Process(data AS STRING) AS STRING
    RETURN data
  END METHOD

  METHOD Shutdown()
    PRINT "["; ME.Name; "] Shut down"
  END METHOD
END CLASS


CLASS UpperCasePlugin EXTENDS Plugin
  CONSTRUCTOR()
    SUPER("UpperCase", "1.0")
  END CONSTRUCTOR

  METHOD Process(data AS STRING) AS STRING
    RETURN UCASE$(data)
  END METHOD
END CLASS


CLASS PrefixPlugin EXTENDS Plugin
  Prefix AS STRING

  CONSTRUCTOR(prefix AS STRING)
    SUPER("Prefix", "1.2")
    ME.Prefix = prefix
  END CONSTRUCTOR

  METHOD Process(data AS STRING) AS STRING
    RETURN ME.Prefix & data
  END METHOD
END CLASS


CLASS TrimPlugin EXTENDS Plugin
  CONSTRUCTOR()
    SUPER("Trim", "1.0")
  END CONSTRUCTOR

  METHOD Process(data AS STRING) AS STRING
    RETURN LTRIM$(RTRIM$(data))
  END METHOD
END CLASS


' --- Plugin Pipeline ---

DIM plugins(2) AS Plugin
plugins(0) = NEW TrimPlugin()
plugins(1) = NEW UpperCasePlugin()
plugins(2) = NEW PrefixPlugin(">>> ")

' Initialise all plugins
PRINT "=== Initialising Plugins ==="
FOR i = 0 TO 2
  plugins(i).Init()
NEXT i

' Process data through pipeline
PRINT ""
PRINT "=== Processing ==="
DIM data AS STRING
data = "  hello world  "
PRINT "Input:  '"; data; "'"

FOR i = 0 TO 2
  IF plugins(i).Enabled THEN
    data = plugins(i).Process(data)
  END IF
NEXT i

PRINT "Output: '"; data; "'"

' Shutdown all plugins
PRINT ""
PRINT "=== Shutdown ==="
FOR i = 0 TO 2
  plugins(i).Shutdown()
NEXT i
```

**Output:**
```
=== Initialising Plugins ===
[TrimPlugin v1.0] Initialised
[UpperCase v1.0] Initialised
[Prefix v1.2] Initialised

=== Processing ===
Input:  '  hello world  '
Output: '>>> HELLO WORLD'

=== Shutdown ===
[TrimPlugin] Shut down
[UpperCase] Shut down
[Prefix] Shut down
```

---

## 15. Real-World Pattern: Game Entity System

A hierarchy of game entities that share update/render logic through
inheritance.

```basic
CLASS Entity
  X AS DOUBLE
  Y AS DOUBLE
  Width AS INTEGER
  Height AS INTEGER
  Active AS INTEGER

  CONSTRUCTOR(x AS DOUBLE, y AS DOUBLE, w AS INTEGER, h AS INTEGER)
    ME.X = x
    ME.Y = y
    ME.Width = w
    ME.Height = h
    ME.Active = 1
  END CONSTRUCTOR

  METHOD Update(dt AS DOUBLE)
    ' base: do nothing
  END METHOD

  METHOD Render()
    IF ME.Active THEN
      PRINT "Entity at ("; ME.X; ", "; ME.Y; ")"
    END IF
  END METHOD

  METHOD CollidesWith(other AS Entity) AS INTEGER
    IF ME.X < other.X + other.Width AND ME.X + ME.Width > other.X THEN
      IF ME.Y < other.Y + other.Height AND ME.Y + ME.Height > other.Y THEN
        RETURN 1
      END IF
    END IF
    RETURN 0
  END METHOD
END CLASS


CLASS Player EXTENDS Entity
  Speed AS DOUBLE
  Health AS INTEGER
  Name AS STRING

  CONSTRUCTOR(name AS STRING, x AS DOUBLE, y AS DOUBLE)
    SUPER(x, y, 32, 32)
    ME.Speed = 100.0
    ME.Health = 100
    ME.Name = name
  END CONSTRUCTOR

  METHOD MoveRight(dt AS DOUBLE)
    ME.X = ME.X + ME.Speed * dt
  END METHOD

  METHOD TakeDamage(amount AS INTEGER)
    ME.Health = ME.Health - amount
    IF ME.Health <= 0 THEN
      ME.Health = 0
      ME.Active = 0
      PRINT ME.Name; " has been defeated!"
    ELSE
      PRINT ME.Name; " took "; amount; " damage. HP: "; ME.Health
    END IF
  END METHOD

  METHOD Render()
    IF ME.Active THEN
      PRINT "[Player "; ME.Name; "] pos=("; ME.X; ","; ME.Y; ") HP="; ME.Health
    ELSE
      PRINT "[Player "; ME.Name; "] *defeated*"
    END IF
  END METHOD
END CLASS


CLASS Bullet EXTENDS Entity
  Damage AS INTEGER
  VelX AS DOUBLE

  CONSTRUCTOR(x AS DOUBLE, y AS DOUBLE, velX AS DOUBLE, damage AS INTEGER)
    SUPER(x, y, 4, 4)
    ME.VelX = velX
    ME.Damage = damage
  END CONSTRUCTOR

  METHOD Update(dt AS DOUBLE)
    ME.X = ME.X + ME.VelX * dt
    IF ME.X > 800 OR ME.X < 0 THEN
      ME.Active = 0
    END IF
  END METHOD

  METHOD Render()
    IF ME.Active THEN
      PRINT "  *bullet* at "; ME.X
    END IF
  END METHOD
END CLASS


' --- Main Game Loop Simulation ---

DIM hero AS Player = NEW Player("Hero", 50, 200)
DIM bullet AS Bullet = NEW Bullet(0, 200, 300, 25)

PRINT "=== Frame 1 ==="
hero.Render()
bullet.Render()

bullet.Update(0.5)
hero.MoveRight(0.5)

PRINT ""
PRINT "=== Frame 2 ==="
hero.Render()
bullet.Render()

IF bullet.CollidesWith(hero) THEN
  hero.TakeDamage(bullet.Damage)
  bullet.Active = 0
END IF
```

**Output:**
```
=== Frame 1 ===
[Player Hero] pos=(50,200) HP=100
  *bullet* at 0

=== Frame 2 ===
[Player Hero] pos=(100,200) HP=100
  *bullet* at 150
```

---

## 16. Real-World Pattern: Menu System

A composable menu system showing objects containing arrays of other objects.

```basic
CLASS MenuItem
  Label AS STRING
  Action AS STRING

  CONSTRUCTOR(label AS STRING, action AS STRING)
    ME.Label = label
    ME.Action = action
  END CONSTRUCTOR

  METHOD Display(indent AS INTEGER)
    DIM i AS INTEGER
    FOR i = 1 TO indent
      PRINT "  ";
    NEXT i
    PRINT ME.Label
  END METHOD

  METHOD Execute()
    PRINT ">> Executing: "; ME.Action
  END METHOD
END CLASS


CLASS Menu
  Title AS STRING
  Items(20) AS MenuItem
  Count AS INTEGER

  CONSTRUCTOR(title AS STRING)
    ME.Title = title
    ME.Count = 0
  END CONSTRUCTOR

  METHOD AddItem(item AS MenuItem)
    ME.Items(ME.Count) = item
    ME.Count = ME.Count + 1
  END METHOD

  METHOD Display(indent AS INTEGER)
    DIM i AS INTEGER
    FOR i = 1 TO indent
      PRINT "  ";
    NEXT i
    PRINT ME.Title
    FOR i = 0 TO ME.Count - 1
      ME.Items(i).Display(indent + 1)
    NEXT i
  END METHOD

  METHOD Select(index AS INTEGER)
    IF index >= 0 AND index < ME.Count THEN
      ME.Items(index).Execute()
    ELSE
      PRINT "Invalid selection"
    END IF
  END METHOD
END CLASS


' --- Build Menu ---

DIM mainMenu AS Menu = NEW Menu("=== Main Menu ===")
mainMenu.AddItem(NEW MenuItem("New Game", "START_GAME"))
mainMenu.AddItem(NEW MenuItem("Load Game", "LOAD_GAME"))
mainMenu.AddItem(NEW MenuItem("Options", "OPEN_OPTIONS"))
mainMenu.AddItem(NEW MenuItem("Quit", "EXIT"))

mainMenu.Display(0)

PRINT ""
mainMenu.Select(0)
mainMenu.Select(3)
```

**Output:**
```
=== Main Menu ===
  New Game
  Load Game
  Options
  Quit

>> Executing: START_GAME
>> Executing: EXIT
```

---

## 17. Anti-Patterns and Pitfalls

### 17.1 Don't Use CLASS When TYPE Suffices

```basic
' BAD — unnecessary overhead for pure data
CLASS Point
  X AS DOUBLE
  Y AS DOUBLE

  CONSTRUCTOR(x AS DOUBLE, y AS DOUBLE)
    ME.X = x
    ME.Y = y
  END CONSTRUCTOR
END CLASS

' GOOD — TYPE is perfect for small value types
TYPE Point
  X AS DOUBLE
  Y AS DOUBLE
END TYPE
```

**Rule of thumb:** If you don't need methods, inheritance, or polymorphism,
use TYPE. TYPE values are stack-allocated and faster for small data.

### 17.2 Don't Create Deep Inheritance Hierarchies

```basic
' BAD — too deep, hard to understand
CLASS A
END CLASS
CLASS B EXTENDS A
END CLASS
CLASS C EXTENDS B
END CLASS
CLASS D EXTENDS C
END CLASS
CLASS E EXTENDS D    ' reader must understand 5 levels
END CLASS

' GOOD — keep it to 2-3 levels max
CLASS Entity
END CLASS
CLASS Player EXTENDS Entity
END CLASS
CLASS NPC EXTENDS Entity
END CLASS
```

### 17.3 Avoid Forgetting SUPER() When Parent Has Required Args

```basic
CLASS Animal
  Name AS STRING
  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR
END CLASS

' BAD — compile error: Animal.CONSTRUCTOR requires 1 argument
CLASS Dog EXTENDS Animal
  CONSTRUCTOR()
    ' forgot SUPER(...)
  END CONSTRUCTOR
END CLASS

' GOOD
CLASS Dog EXTENDS Animal
  CONSTRUCTOR(name AS STRING)
    SUPER(name)
  END CONSTRUCTOR
END CLASS
```

### 17.4 Don't Ignore NOTHING Checks for Optional References

```basic
' RISKY — crashes if bestFriend was never assigned
CLASS Person
  Name AS STRING
  BestFriend AS Person

  METHOD GreetFriend()
    ' This will crash at runtime if BestFriend IS NOTHING!
    PRINT "Hi "; ME.BestFriend.Name
  END METHOD
END CLASS

' SAFE — check first
  METHOD GreetFriend()
    IF ME.BestFriend IS NOTHING THEN
      PRINT ME.Name; " has no best friend yet"
    ELSE
      PRINT "Hi "; ME.BestFriend.Name
    END IF
  END METHOD
```

### 17.5 Prefer Composition Over Inheritance When Behaviour Isn't Shared

```basic
' QUESTIONABLE — Logger and UserAccount don't share behaviour
CLASS Logger
  METHOD Log(msg AS STRING)
    PRINT msg
  END METHOD
END CLASS

CLASS UserAccount EXTENDS Logger    ' odd: UserAccount IS-A Logger?
  Name AS STRING
END CLASS

' BETTER — UserAccount HAS-A Logger
CLASS UserAccount
  Name AS STRING
  Log AS Logger

  CONSTRUCTOR(name AS STRING)
    ME.Name = name
    ME.Log = NEW Logger()
  END CONSTRUCTOR

  METHOD Login()
    ME.Log.Log("User " & ME.Name & " logged in")
  END METHOD
END CLASS
```

---

## Summary: When to Use What

| Need | Use |
|------|-----|
| Small data bundle (Point, Color, Rect) | **TYPE** |
| Data with behaviour (Player, Account) | **CLASS** |
| Shared behaviour across related types | **CLASS + EXTENDS** |
| Flat data, no methods, SIMD-friendly | **TYPE** |
| Heap allocation, identity, polymorphism | **CLASS** |
| Global utility functions | **SUB / FUNCTION** |
| Dictionary / key-value store | **HASHMAP** (runtime object) |
| Dynamic collection | **Array** or **CLASS with array field** |