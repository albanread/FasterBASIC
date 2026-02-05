REM Example FasterBASIC program demonstrating HASHMAP usage
REM This will work once the code generator is updated to support HASHMAP types

PRINT "=== FasterBASIC HashMap Example ==="
PRINT ""

REM Declare a hashmap to store name -> age mappings
DIM ages AS HASHMAP

REM Insert some data
ages("Alice") = 30
ages("Bob") = 25
ages("Charlie") = 35
ages("Diana") = 28

PRINT "Added 4 people to the hashmap"
PRINT "Size: "; ages.SIZE()
PRINT ""

REM Lookup values
PRINT "Looking up ages:"
PRINT "Alice is "; ages("Alice"); " years old"
PRINT "Bob is "; ages("Bob"); " years old"
PRINT ""

REM Check if keys exist
IF ages.HASKEY("Alice") THEN
    PRINT "Alice is in the hashmap"
END IF

IF NOT ages.HASKEY("Eve") THEN
    PRINT "Eve is not in the hashmap"
END IF
PRINT ""

REM Update a value
ages("Alice") = 31
PRINT "Updated Alice's age to: "; ages("Alice")
PRINT ""

REM Iterate over all keys
PRINT "All people in the hashmap:"
FOR EACH name IN ages.KEYS()
    PRINT "  "; name; " = "; ages(name)
NEXT
PRINT ""

REM Using GET with default value
missing_age = ages.GET("Unknown", 0)
PRINT "Age of 'Unknown' with default: "; missing_age
PRINT ""

REM Remove an entry
ages.REMOVE("Bob")
PRINT "Removed Bob from the hashmap"
PRINT "New size: "; ages.SIZE()
PRINT ""

REM Iterate with pairs (when implemented)
PRINT "Iterating with key-value pairs:"
FOR EACH name, age IN ages.PAIRS()
    PRINT "  "; name; " is "; age; " years old"
NEXT
PRINT ""

REM Symbol table example (more advanced use case)
PRINT "=== Symbol Table Example ==="
DIM symtab AS HASHMAP

REM Simulating a simple variable environment
symtab("x") = 10
symtab("y") = 20
symtab("result") = 30

PRINT "Variables in symbol table:"
FOR EACH varname IN symtab.KEYS()
    PRINT "  "; varname; " = "; symtab(varname)
NEXT
PRINT ""

REM Clear the hashmap
ages.CLEAR()
PRINT "Cleared ages hashmap"
PRINT "Size after clear: "; ages.SIZE()
PRINT ""

PRINT "=== Example Complete ==="
