' Simple CLASS constructor test
CLASS Dog
  Name AS STRING

  CONSTRUCTOR(n AS STRING)
    ME.Name = n
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name
  END METHOD
END CLASS

DIM d AS Dog = NEW Dog("Rex")
d.Speak()
END
