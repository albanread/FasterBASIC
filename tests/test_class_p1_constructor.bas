' === test_class_p1_constructor.bas ===
' Phase 1 Test: CLASS with CONSTRUCTOR, METHOD, and ME keyword
' Validates: CONSTRUCTOR parsing, ME keyword, method dispatch via vtable,
'            field initialisation from constructor, methods with return values

' --- Test 1: Constructor with arguments and ME field access ---

CLASS Greeter
  Greeting AS STRING
  Target AS STRING

  CONSTRUCTOR(g AS STRING, t AS STRING)
    ME.Greeting = g
    ME.Target = t
  END CONSTRUCTOR

  METHOD SayHello()
    PRINT ME.Greeting; ", "; ME.Target; "!"
  END METHOD

  METHOD GetMessage() AS STRING
    RETURN ME.Greeting + ", " + ME.Target + "!"
  END METHOD
END CLASS

DIM g AS Greeter = NEW Greeter("Hello", "World")
g.SayHello()
PRINT g.GetMessage()

' --- Test 2: Constructor with zero arguments ---

CLASS Counter
  Value AS INTEGER

  CONSTRUCTOR()
    ME.Value = 0
  END CONSTRUCTOR

  METHOD Increment()
    ME.Value = ME.Value + 1
  END METHOD

  METHOD IncrementBy(n AS INTEGER)
    ME.Value = ME.Value + n
  END METHOD

  METHOD GetValue() AS INTEGER
    RETURN ME.Value
  END METHOD

  METHOD Reset()
    ME.Value = 0
  END METHOD
END CLASS

DIM c AS Counter = NEW Counter()
PRINT "Initial: "; c.GetValue()
c.Increment()
c.Increment()
c.Increment()
PRINT "After 3 increments: "; c.GetValue()
c.IncrementBy(7)
PRINT "After +7: "; c.GetValue()
c.Reset()
PRINT "After reset: "; c.GetValue()

' --- Test 3: Multiple fields of different types ---

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

  METHOD IsAdult() AS INTEGER
    IF ME.Age >= 18 THEN
      RETURN 1
    ELSE
      RETURN 0
    END IF
  END METHOD
END CLASS

DIM alice AS Person = NEW Person("Alice", 30, 1.72)
DIM bob AS Person = NEW Person("Bob", 12, 1.45)
alice.Describe()
bob.Describe()
PRINT "Alice is adult: "; alice.IsAdult()
PRINT "Bob is adult: "; bob.IsAdult()

' --- Test 4: Multiple independent instances ---

DIM c1 AS Counter = NEW Counter()
DIM c2 AS Counter = NEW Counter()
c1.Increment()
c1.Increment()
c2.IncrementBy(100)
PRINT "c1 = "; c1.GetValue(); ", c2 = "; c2.GetValue()

' --- Test 5: Method calling another method via ME ---

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
PRINT "Calculator result: "; calc.GetResult()

' --- Test 6: Object assignment (pointer semantics) ---

DIM g1 AS Greeter = NEW Greeter("Hi", "There")
DIM g2 AS Greeter = g1
g2.Target = "Everyone"
PRINT "g1: "; g1.Target
PRINT "g2: "; g2.Target

' Both should print "Everyone" because g1 and g2 point to the same object

' --- Test 7: DIM with deferred NEW ---

DIM later AS Counter
later = NEW Counter()
later.IncrementBy(42)
PRINT "Deferred: "; later.GetValue()

END

' EXPECTED OUTPUT:
' Hello, World!
' Hello, World!
' Initial: 0
' After 3 increments: 3
' After +7: 10
' After reset: 0
' Alice is 30 years old, 1.72m tall
' Bob is 12 years old, 1.45m tall
' Alice is adult: 1
' Bob is adult: 0
' c1 = 2, c2 = 100
' Calculator result: 13
' g1: Everyone
' g2: Everyone
' Deferred: 42
