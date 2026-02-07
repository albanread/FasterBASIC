' Test CLASS method with string concatenation RETURN
CLASS Greeter
  Greeting AS STRING
  Target AS STRING

  CONSTRUCTOR(g AS STRING, t AS STRING)
    ME.Greeting = g
    ME.Target = t
  END CONSTRUCTOR

  METHOD SayHello()
    PRINT ME.Greeting
    PRINT ME.Target
  END METHOD

  METHOD GetMessage() AS STRING
    DIM result AS STRING
    result = ME.Greeting
    RETURN result
  END METHOD
END CLASS

DIM g AS Greeter = NEW Greeter("Hello", "World")
g.SayHello()
PRINT g.GetMessage()
END
