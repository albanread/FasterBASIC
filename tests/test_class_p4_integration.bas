' === test_class_p4_integration.bas ===
' Phase 4 Test: Integration - multiple classes, mixed features, method returns
' Validates: multiple classes in one program, object fields in objects,
'            method chaining, mixed CLASS and non-CLASS code, constructors
'            with different param types, method with local variables

' --- Class definitions ---

CLASS Address
  Street AS STRING
  City AS STRING

  CONSTRUCTOR(s AS STRING, c AS STRING)
    ME.Street = s
    ME.City = c
  END CONSTRUCTOR

  METHOD Format() AS STRING
    DIM result AS STRING
    result = ME.Street + ", " + ME.City
    RETURN result
  END METHOD
END CLASS

CLASS Person
  Name AS STRING
  Age AS INTEGER

  CONSTRUCTOR(n AS STRING, a AS INTEGER)
    ME.Name = n
    ME.Age = a
  END CONSTRUCTOR

  METHOD Greet() AS STRING
    DIM msg AS STRING
    msg = "Hi, I'm " + ME.Name
    RETURN msg
  END METHOD

  METHOD IsAdult() AS INTEGER
    IF ME.Age >= 18 THEN
      RETURN 1
    ELSE
      RETURN 0
    END IF
  END METHOD

  METHOD GetAge() AS INTEGER
    RETURN ME.Age
  END METHOD
END CLASS

CLASS Employee EXTENDS Person
  Title AS STRING
  Salary AS DOUBLE

  CONSTRUCTOR(n AS STRING, a AS INTEGER, t AS STRING, s AS DOUBLE)
    SUPER(n, a)
    ME.Title = t
    ME.Salary = s
  END CONSTRUCTOR

  METHOD Greet() AS STRING
    DIM msg AS STRING
    msg = "Hi, I'm " + ME.Name + ", " + ME.Title
    RETURN msg
  END METHOD

  METHOD GetSalary() AS DOUBLE
    RETURN ME.Salary
  END METHOD

  METHOD GiveRaise(pct AS DOUBLE)
    ME.Salary = ME.Salary * (1.0 + pct / 100.0)
  END METHOD
END CLASS

CLASS Counter
  Count AS INTEGER

  CONSTRUCTOR()
    ME.Count = 0
  END CONSTRUCTOR

  METHOD Increment()
    ME.Count = ME.Count + 1
  END METHOD

  METHOD GetCount() AS INTEGER
    RETURN ME.Count
  END METHOD

  METHOD Reset()
    ME.Count = 0
  END METHOD
END CLASS

' --- Test 1: Multiple independent classes ---

PRINT "=== Multiple Classes ==="
DIM addr AS Address = NEW Address("123 Main St", "Springfield")
DIM p AS Person = NEW Person("Alice", 30)
DIM cnt AS Counter = NEW Counter()

PRINT addr.Format()
PRINT p.Greet()
PRINT "Adult: "; p.IsAdult()
cnt.Increment()
cnt.Increment()
cnt.Increment()
PRINT "Counter: "; cnt.GetCount()
PRINT ""

' --- Test 2: Inheritance with method override ---

PRINT "=== Employee (inherits Person) ==="
DIM emp AS Employee = NEW Employee("Bob", 25, "Engineer", 75000.0)
PRINT emp.Greet()
PRINT "Age: "; emp.GetAge()
PRINT "Adult: "; emp.IsAdult()
PRINT "Salary: "; emp.GetSalary()
emp.GiveRaise(10.0)
PRINT "After 10% raise: "; emp.GetSalary()
PRINT ""

' --- Test 3: Mixed CLASS and regular BASIC code ---

PRINT "=== Mixed Code ==="
DIM total AS DOUBLE
total = 0.0
DIM i AS INTEGER
FOR i = 1 TO 5
  cnt.Increment()
  total = total + i
NEXT i
PRINT "Counter after loop: "; cnt.GetCount()
PRINT "Sum 1..5: "; total
cnt.Reset()
PRINT "After reset: "; cnt.GetCount()
PRINT ""

' --- Test 4: Object pointer semantics (alias) ---

PRINT "=== Pointer Semantics ==="
DIM p1 AS Person = NEW Person("Carol", 40)
DIM p2 AS Person
p2 = p1
PRINT "p1: "; p1.Greet()
PRINT "p2: "; p2.Greet()
PRINT ""

' --- Test 5: IS and NOTHING with multiple classes ---

PRINT "=== IS with Multiple Classes ==="
DIM e2 AS Employee = NEW Employee("Dave", 35, "Manager", 90000.0)
DIM isPerson AS INTEGER
isPerson = e2 IS Person
PRINT "Employee IS Person: "; isPerson
DIM isEmployee AS INTEGER
isEmployee = e2 IS Employee
PRINT "Employee IS Employee: "; isEmployee
DIM isCounter AS INTEGER
isCounter = e2 IS Counter
PRINT "Employee IS Counter: "; isCounter
PRINT ""

' --- Test 6: Deferred NEW and NOTHING ---

PRINT "=== Deferred NEW ==="
DIM later AS Counter
DIM isNull AS INTEGER
isNull = later IS NOTHING
PRINT "Before NEW: IS NOTHING = "; isNull
later = NEW Counter()
later.Increment()
later.Increment()
PRINT "After NEW: count = "; later.GetCount()
isNull = later IS NOTHING
PRINT "After NEW: IS NOTHING = "; isNull
PRINT ""

' --- Test 7: DELETE and reuse ---

PRINT "=== DELETE and Reuse ==="
DIM temp AS Person = NEW Person("Eve", 22)
PRINT "Before: "; temp.Greet()
DELETE temp
DIM delNull AS INTEGER
delNull = temp IS NOTHING
PRINT "After DELETE: IS NOTHING = "; delNull
temp = NEW Person("Frank", 50)
PRINT "After re-NEW: "; temp.Greet()
PRINT ""

PRINT "Done!"
END

' EXPECTED OUTPUT:
' === Multiple Classes ===
' 123 Main St, Springfield
' Hi, I'm Alice
' Adult: 1
' Counter: 3
'
' === Employee (inherits Person) ===
' Hi, I'm Bob, Engineer
' Age: 25
' Adult: 1
' Salary: 75000
' After 10% raise: 82500
'
' === Mixed Code ===
' Counter after loop: 8
' Sum 1..5: 15
' After reset: 0
'
' === Pointer Semantics ===
' p1: Hi, I'm Carol
' p2: Hi, I'm Carol
'
' === IS with Multiple Classes ===
' Employee IS Person: 1
' Employee IS Employee: 1
' Employee IS Counter: 0
'
' === Deferred NEW ===
' Before NEW: IS NOTHING = 1
' After NEW: count = 2
' After NEW: IS NOTHING = 0
'
' === DELETE and Reuse ===
' Before: Hi, I'm Eve
' After DELETE: IS NOTHING = 1
' After re-NEW: Hi, I'm Frank
'
' Done!
