# UDT Quick Reference Guide

## Overview

User-Defined Types (UDTs) allow you to create custom data structures with multiple fields of different types. This is similar to `struct` in C or records in other languages.

## Syntax

### Defining a UDT

```basic
TYPE typename
  fieldname1 AS type1
  fieldname2 AS type2
  ...
END TYPE
```

### Declaring UDT Variables

```basic
DIM variablename AS typename
```

### Accessing Fields

```basic
' Reading a field
value = variablename.fieldname

' Writing to a field
variablename.fieldname = expression
```

## Supported Field Types

- `INTEGER` - 32-bit signed integer (4 bytes)
- `LONG` - 64-bit signed integer (8 bytes)
- `SINGLE` - 32-bit floating point (4 bytes)
- `DOUBLE` - 64-bit floating point (8 bytes)
- `STRING` - String descriptor pointer (8 bytes)

## Examples

### Example 1: Simple Point Type

```basic
TYPE Point
  X AS INTEGER
  Y AS INTEGER
END TYPE

DIM P AS Point
P.X = 10
P.Y = 20
PRINT "Point: ("; P.X; ", "; P.Y; ")"
```

### Example 2: Person Record

```basic
TYPE Person
  Name AS STRING
  Age AS INTEGER
  Height AS DOUBLE
END TYPE

DIM Employee AS Person
Employee.Name = "Alice"
Employee.Age = 30
Employee.Height = 5.7

PRINT "Name: "; Employee.Name
PRINT "Age: "; Employee.Age
PRINT "Height: "; Employee.Height
```

### Example 3: Rectangle with Calculated Area

```basic
TYPE Rectangle
  Width AS INTEGER
  Height AS INTEGER
  Area AS LONG
END TYPE

DIM R AS Rectangle
R.Width = 25
R.Height = 40
R.Area = R.Width * R.Height

PRINT "Rectangle: "; R.Width; " x "; R.Height
PRINT "Area: "; R.Area
```

### Example 4: Using UDT Fields in Expressions

```basic
TYPE Circle
  Radius AS DOUBLE
  Diameter AS DOUBLE
END TYPE

DIM C AS Circle
C.Radius = 5.0
C.Diameter = C.Radius * 2

IF C.Diameter > 10 THEN
  PRINT "Large circle"
ELSE
  PRINT "Small circle"
END IF
```

## Memory Layout

Fields are stored sequentially in memory:

```basic
TYPE Example
  A AS INTEGER    ' Offset 0, size 4
  B AS DOUBLE     ' Offset 4, size 8
  C AS INTEGER    ' Offset 12, size 4
END TYPE
' Total size: 16 bytes
```

## Current Limitations

### ❌ Not Yet Supported

1. **Arrays of UDTs**
   ```basic
   DIM Points(10) AS Point  ' Not yet supported
   ```

2. **Nested UDTs**
   ```basic
   TYPE Address
     Street AS STRING
   END TYPE
   
   TYPE Person
     Name AS STRING
     Home AS Address  ' Not yet supported
   END TYPE
   ```

3. **Multi-level Member Access**
   ```basic
   P.Address.Street  ' Not yet supported
   ```

4. **UDT Parameters**
   ```basic
   SUB PrintPoint(P AS Point)  ' Not yet supported
   ```

5. **UDT Return Values**
   ```basic
   FUNCTION MakePoint() AS Point  ' Not yet supported
   ```

6. **UDT Assignment**
   ```basic
   P1 = P2  ' Not yet supported (assign entire UDT)
   ```

### ✅ Workarounds

**Instead of array of UDTs:**
```basic
' Use parallel arrays
DIM PointX(10) AS INTEGER
DIM PointY(10) AS INTEGER
PointX(0) = 5
PointY(0) = 10
```

**Instead of nested UDTs:**
```basic
' Flatten the structure
TYPE Person
  Name AS STRING
  Street AS STRING
  City AS STRING
END TYPE
```

## Best Practices

### 1. Initialize Fields After Declaration
```basic
DIM P AS Point
P.X = 0  ' Good practice: explicit initialization
P.Y = 0
```

### 2. Use Descriptive Field Names
```basic
' Good
TYPE Person
  FirstName AS STRING
  LastName AS STRING
END TYPE

' Avoid
TYPE Person
  FN AS STRING
  LN AS STRING
END TYPE
```

### 3. Group Related Data
```basic
' Good: Related data in one UDT
TYPE Customer
  Name AS STRING
  ID AS LONG
  Balance AS DOUBLE
END TYPE

' Less ideal: Separate variables
DIM CustomerName AS STRING
DIM CustomerID AS LONG
DIM CustomerBalance AS DOUBLE
```

### 4. Keep UDTs Simple
```basic
' Good: Flat structure
TYPE Rectangle
  Width AS INTEGER
  Height AS INTEGER
END TYPE

' Avoid (not supported yet):
TYPE Rectangle
  TopLeft AS Point
  BottomRight AS Point
END TYPE
```

## Common Patterns

### Pattern 1: Using UDTs for Configuration

```basic
TYPE Config
  MaxItems AS INTEGER
  Timeout AS DOUBLE
  DebugMode AS INTEGER  ' Use 0/1 as boolean
END TYPE

DIM Settings AS Config
Settings.MaxItems = 100
Settings.Timeout = 30.0
Settings.DebugMode = 1
```

### Pattern 2: UDTs for Return-by-Reference

```basic
TYPE Result
  Success AS INTEGER
  ErrorCode AS INTEGER
  Value AS DOUBLE
END TYPE

DIM R AS Result
' ... some operation ...
R.Success = 1
R.ErrorCode = 0
R.Value = 42.5

IF R.Success = 1 THEN
  PRINT "Value: "; R.Value
END IF
```

### Pattern 3: Multiple Related Instances

```basic
TYPE Player
  Name AS STRING
  Score AS LONG
  Lives AS INTEGER
END TYPE

DIM Player1 AS Player
DIM Player2 AS Player

Player1.Name = "Alice"
Player1.Score = 1000
Player1.Lives = 3

Player2.Name = "Bob"
Player2.Score = 1500
Player2.Lives = 2
```

## Troubleshooting

### Problem: Field value is wrong after assignment

**Check:**
- Field names are spelled correctly (case-sensitive)
- You're assigning the right type to the field
- No typos in the UDT name

### Problem: Compilation error "UDT not found"

**Solution:**
- Make sure the TYPE definition comes before DIM
- Check TYPE name spelling matches DIM AS clause

### Problem: String field shows garbage

**Solution:**
- Always assign a string value before reading
- String fields start as NULL (not empty string)

```basic
DIM P AS Person
P.Name = ""  ' Initialize to empty string
```

## Performance Notes

- UDT field access is fast (direct memory offset)
- No overhead compared to separate variables
- Fields stored inline (no pointer indirection)
- Global UDTs stored in data segment
- Local UDTs stored on stack

## See Also

- `UDT_IMPLEMENTATION_SUMMARY.md` - Technical implementation details
- `FasterBASIC_QuickRef.md` - General language reference
- `tests/types/test_udt_*.bas` - Example test programs