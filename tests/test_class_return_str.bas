' Test CLASS with RETURN string value
CLASS Greeter
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD GetName() AS STRING
    RETURN ME.Name
  END METHOD
END CLASS

DIM g AS Greeter = NEW Greeter("Alice")
PRINT g.GetName()
END
