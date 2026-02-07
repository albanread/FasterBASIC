' === test_class_method_dim_return.bas ===
' Tests two fixes:
'   1. DIM inside METHOD bodies (scalar and CLASS instance)
'   2. Method return via assignment (MethodName = expr)

' --- Test 1: DIM scalar variables inside METHOD ---

CLASS Counter
  Value AS INTEGER

  CONSTRUCTOR(v AS INTEGER)
    ME.Value = v
  END CONSTRUCTOR

  METHOD Add(n AS INTEGER) AS INTEGER
    DIM result AS INTEGER
    result = ME.Value + n
    RETURN result
  END METHOD

  METHOD Describe() AS STRING
    DIM msg AS STRING
    msg = "Counter value is "
    DIM suffix AS STRING
    suffix = " units"
    RETURN msg + STR$(ME.Value) + suffix
  END METHOD
END CLASS

PRINT "=== DIM Scalars in METHOD ==="
DIM c AS Counter = NEW Counter(10)
PRINT "Add(5) = "; c.Add(5)
PRINT c.Describe()
PRINT ""

' --- Test 2: Method return via assignment ---

CLASS Greeter
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD GetGreeting() AS STRING
    GetGreeting = "Hello, " + ME.Name + "!"
  END METHOD

  METHOD GetLength() AS INTEGER
    GetLength = LEN(ME.Name)
  END METHOD

  METHOD Twice(x AS INTEGER) AS INTEGER
    Twice = x * 2
  END METHOD
END CLASS

PRINT "=== Method Return via Assignment ==="
DIM g AS Greeter = NEW Greeter("World")
PRINT g.GetGreeting()
PRINT "Name length: "; g.GetLength()
PRINT "Twice(7) = "; g.Twice(7)
PRINT ""

' --- Test 3: DIM CLASS instance inside METHOD ---

CLASS Wrapper
  Label AS STRING

  CONSTRUCTOR(l AS STRING)
    ME.Label = l
  END CONSTRUCTOR

  METHOD GetLabel() AS STRING
    RETURN ME.Label
  END METHOD
END CLASS

CLASS Factory
  Prefix AS STRING

  CONSTRUCTOR(p AS STRING)
    ME.Prefix = p
  END CONSTRUCTOR

  METHOD MakeWrapper(suffix AS STRING) AS STRING
    DIM w AS Wrapper = NEW Wrapper(ME.Prefix + suffix)
    RETURN w.GetLabel()
  END METHOD
END CLASS

PRINT "=== DIM CLASS Instance in METHOD ==="
DIM f AS Factory = NEW Factory("item_")
PRINT f.MakeWrapper("alpha")
PRINT f.MakeWrapper("beta")
PRINT ""

' --- Test 4: Combining DIM and return-via-assignment ---

CLASS Calculator
  BaseVal AS INTEGER

  CONSTRUCTOR(b AS INTEGER)
    ME.BaseVal = b
  END CONSTRUCTOR

  METHOD Compute(x AS INTEGER) AS INTEGER
    DIM temp AS INTEGER
    temp = ME.BaseVal + x
    DIM doubled AS INTEGER
    doubled = temp * 2
    Compute = doubled
  END METHOD

  METHOD ComputeStr(x AS INTEGER) AS STRING
    DIM num AS INTEGER
    num = ME.BaseVal + x
    ComputeStr = "Result: " + STR$(num)
  END METHOD
END CLASS

PRINT "=== DIM + Return-via-Assignment ==="
DIM calc AS Calculator = NEW Calculator(100)
PRINT "Compute(5) = "; calc.Compute(5)
PRINT calc.ComputeStr(42)
PRINT ""

' --- Test 5: Return-via-assignment with conditional logic ---

CLASS Classifier
  Threshold AS INTEGER

  CONSTRUCTOR(t AS INTEGER)
    ME.Threshold = t
  END CONSTRUCTOR

  METHOD Classify(num AS INTEGER) AS STRING
    IF num > ME.Threshold THEN
      Classify = "HIGH"
    ELSE
      Classify = "LOW"
    END IF
  END METHOD
END CLASS

PRINT "=== Conditional Return-via-Assignment ==="
DIM cl AS Classifier = NEW Classifier(50)
PRINT "Classify(75) = "; cl.Classify(75)
PRINT "Classify(25) = "; cl.Classify(25)

PRINT ""
PRINT "Done!"
END

' EXPECTED OUTPUT:
' === DIM Scalars in METHOD ===
' Add(5) = 15
' Counter value is 10 units
'
' === Method Return via Assignment ===
' Hello, World!
' Name length: 5
' Twice(7) = 14
'
' === DIM CLASS Instance in METHOD ===
' item_alpha
' item_beta
'
' === DIM + Return-via-Assignment ===
' Compute(5) = 210
' Result: 142
'
' === Conditional Return-via-Assignment ===
' Classify(75) = HIGH
' Classify(25) = LOW
'
' Done!
