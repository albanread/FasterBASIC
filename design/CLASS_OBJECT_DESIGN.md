# FasterBASIC CLASS & OBJECT Extension

## Design Document — Language Specification

**Version:** 1.0  
**Date:** July 2025  
**Status:** Ready for Implementation  
**Author:** FasterBASIC Team

---

## 1. Overview

This document specifies a simple, single-inheritance CLASS system for FasterBASIC
that lets users organise larger programs into modular, object-oriented structures.

### Design Principles

1. **BASIC heritage** — Readable, explicit, minimal punctuation. A beginner who
   knows TYPE…END TYPE and SUB/FUNCTION should feel at home immediately.
2. **Build on what exists** — CLASS extends the existing TYPE (fields), SUB/FUNCTION
   (methods), runtime object registry (method dispatch), and member-access syntax
   (`obj.field`, `obj.method()`).
3. **Low ceremony** — Declaring a class, creating an object, and calling methods
   should each be one obvious line of code.
4. **Single inheritance only** — Keeps the mental model, vtable layout, and
   implementation simple.  Composition is always available for more complex designs.
5. **Pragmatic scope** — Ship the 80% that enables clean program structure.
   Advanced features (interfaces, abstract classes, operator overloading) can
   be layered on later without breaking programs written today.

---

## 2. Syntax Reference

### 2.1 Defining a Class

```basic
CLASS ClassName [EXTENDS ParentClass]
  ' --- Fields ---
  FieldName AS Type
  ...

  ' --- Constructor (optional, at most one) ---
  CONSTRUCTOR([param AS Type, ...])
    ...
  END CONSTRUCTOR

  ' --- Methods ---
  METHOD MethodName([param AS Type, ...]) [AS ReturnType]
    ...
  END METHOD
  ...
END CLASS
```

**Rules:**

| Rule | Detail |
|------|--------|
| Names | Class names follow identifier rules. Convention: PascalCase. |
| Fields | Declared exactly like TYPE fields. Inherited fields come first automatically. |
| CONSTRUCTOR | Optional. Zero or one per class. Runs when `NEW` is called. |
| EXTENDS | Names exactly one parent class. Omit for a root class. |
| Nesting | Classes cannot be nested inside other classes, SUBs, or FUNCTIONs. |
| Forward refs | A class must be declared before it is used as a parent or variable type. |

### 2.2 Creating Objects

```basic
DIM obj AS ClassName = NEW ClassName(args...)
```

Or in two steps:

```basic
DIM obj AS ClassName
obj = NEW ClassName(args...)
```

Or with a short form when the type is unambiguous:

```basic
DIM obj = NEW ClassName(args...)     ' type inferred from NEW
```

**`NEW` always returns a heap-allocated object.** The variable holds a pointer
(like strings and hashmaps today).

### 2.3 Accessing Fields and Methods

```basic
obj.FieldName = value           ' write field
x = obj.FieldName               ' read field
obj.MethodName(args...)          ' call method (no return value)
result = obj.MethodName(args...) ' call method with return value
```

This reuses the existing `MemberAccessExpression` and `MethodCallExpression`
AST nodes — no new syntax is needed for access.

### 2.4 The ME Keyword

Inside a METHOD or CONSTRUCTOR, `ME` refers to the current object instance:

```basic
METHOD SetName(n AS STRING)
  ME.Name = n
END METHOD
```

`ME` is always available implicitly; it does not appear in the parameter list.

### 2.5 Calling the Parent Constructor

Inside a CONSTRUCTOR in a derived class, use `SUPER()` to invoke the parent
class constructor.  It must be the **first executable statement** in the
constructor body:

```basic
CLASS Dog EXTENDS Animal
  Breed AS STRING

  CONSTRUCTOR(name AS STRING, breed AS STRING)
    SUPER(name, "Woof!", 4)     ' calls Animal's CONSTRUCTOR
    ME.Breed = breed
  END CONSTRUCTOR
END CLASS
```

If the parent has no constructor (or a zero-argument constructor), `SUPER()`
may be omitted and the compiler inserts an implicit `SUPER()` call.

### 2.6 Method Overriding

A derived class may define a METHOD with the same name and parameter signature
as a parent method.  The derived version replaces the parent version for objects
of the derived type:

```basic
CLASS Animal
  METHOD Speak()
    PRINT "..."
  END METHOD
END CLASS

CLASS Cat EXTENDS Animal
  METHOD Speak()               ' overrides Animal.Speak
    PRINT "Meow!"
  END METHOD
END CLASS
```

No `OVERRIDE` or `VIRTUAL` keyword is required.  **All methods are
virtual** — dispatch goes through the vtable, so calling `Speak()` on an
`Animal` variable that holds a `Cat` will print "Meow!".

### 2.7 Calling a Parent Method

Inside a method, use `SUPER.MethodName(args...)` to call the parent class
implementation:

```basic
CLASS Cat EXTENDS Animal
  METHOD Speak()
    PRINT "The cat says: ";
    SUPER.Speak()              ' calls Animal.Speak
  END METHOD
END CLASS
```

### 2.8 Type Checking

```basic
IF obj IS ClassName THEN ...
```

`IS` evaluates to true if `obj` is an instance of `ClassName` or any class
that extends `ClassName` (i.e. it checks the inheritance chain).

### 2.9 Nothing (Null Reference)

```basic
DIM obj AS Animal              ' initially NOTHING
IF obj IS NOTHING THEN PRINT "No object yet"
obj = NEW Animal("Cat", "Meow", 4)
obj = NOTHING                  ' release reference
```

`NOTHING` is the null/empty object reference, analogous to null in other
languages.  All object variables start as `NOTHING` before assignment.

### 2.10 Deleting Objects

```basic
DELETE obj                     ' explicit cleanup (optional)
```

`DELETE` calls the destructor (if defined), frees the object memory, and
sets the variable to `NOTHING`.  If no `DELETE` is called, memory is
reclaimed when the program exits (phase 1) or by reference counting
(phase 2, future work).

An optional destructor can be defined:

```basic
CLASS FileWrapper
  Handle AS INTEGER

  DESTRUCTOR()
    CLOSE #ME.Handle
  END DESTRUCTOR
END CLASS
```

---

## 3. Complete Example

```basic
' =============================================
'  Animal Hierarchy — FasterBASIC OOP Demo
' =============================================

CLASS Animal
  Name AS STRING
  Sound AS STRING
  Legs AS INTEGER

  CONSTRUCTOR(n AS STRING, s AS STRING, l AS INTEGER)
    ME.Name = n
    ME.Sound = s
    ME.Legs = l
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " says "; ME.Sound
  END METHOD

  METHOD Describe() AS STRING
    RETURN ME.Name & " (" & STR$(ME.Legs) & " legs)"
  END METHOD
END CLASS


CLASS Dog EXTENDS Animal
  Breed AS STRING

  CONSTRUCTOR(name AS STRING, breed AS STRING)
    SUPER(name, "Woof!", 4)
    ME.Breed = breed
  END CONSTRUCTOR

  METHOD Speak()
    PRINT ME.Name; " the "; ME.Breed; " barks: "; ME.Sound
  END METHOD

  METHOD Fetch(item AS STRING)
    PRINT ME.Name; " fetches the "; item; "!"
  END METHOD
END CLASS


CLASS Cat EXTENDS Animal
  Indoor AS INTEGER             ' 1 = indoor, 0 = outdoor

  CONSTRUCTOR(name AS STRING, indoor AS INTEGER)
    SUPER(name, "Meow!", 4)
    ME.Indoor = indoor
  END CONSTRUCTOR

  METHOD Speak()
    IF ME.Indoor THEN
      PRINT ME.Name; " purrs softly"
    ELSE
      PRINT ME.Name; " yowls: "; ME.Sound
    END IF
  END METHOD
END CLASS


' --- Main Program ---

PRINT "=== FasterBASIC OOP Demo ==="
PRINT ""

DIM rex AS Dog = NEW Dog("Rex", "Labrador")
DIM whiskers AS Cat = NEW Cat("Whiskers", 1)
DIM eagle AS Animal = NEW Animal("Eagle", "Screech!", 2)

rex.Speak()
rex.Fetch("tennis ball")
PRINT rex.Describe()
PRINT ""

whiskers.Speak()
PRINT whiskers.Describe()
PRINT ""

eagle.Speak()
PRINT eagle.Describe()
PRINT ""

' --- Polymorphism with an array ---
PRINT "=== Polymorphic Array ==="

DIM zoo(2) AS Animal
zoo(0) = rex            ' Dog stored as Animal
zoo(1) = whiskers       ' Cat stored as Animal
zoo(2) = eagle           ' Animal stored as Animal

FOR i = 0 TO 2
  zoo(i).Speak()         ' dispatches to correct override
NEXT i

PRINT ""
PRINT "=== Type Checking ==="
FOR i = 0 TO 2
  IF zoo(i) IS Dog THEN
    PRINT zoo(i).Describe(); " is a Dog"
  ELSE IF zoo(i) IS Cat THEN
    PRINT zoo(i).Describe(); " is a Cat"
  ELSE
    PRINT zoo(i).Describe(); " is a generic Animal"
  END IF
NEXT i

PRINT ""
PRINT "Done!"
END
```

**Expected output:**

```
=== FasterBASIC OOP Demo ===

Rex the Labrador barks: Woof!
Rex fetches the tennis ball!
Rex (4 legs)

Whiskers purrs softly
Whiskers (4 legs)

Eagle says Screech!
Eagle (2 legs)

=== Polymorphic Array ===
Rex the Labrador barks: Woof!
Whiskers purrs softly
Eagle says Screech!

=== Type Checking ===
Rex (4 legs) is a Dog
Whiskers (4 legs) is a Cat
Eagle (2 legs) is a generic Animal

Done!
```

---

## 4. Practical Example — Structured Application

This example shows how CLASS enables clean program structure for a larger
application (a simple task manager):

```basic
' =============================================
'  Task Manager — Structured with Classes
' =============================================

CLASS Task
  Title AS STRING
  Done AS INTEGER
  Priority AS INTEGER          ' 1=High, 2=Medium, 3=Low

  CONSTRUCTOR(title AS STRING, priority AS INTEGER)
    ME.Title = title
    ME.Priority = priority
    ME.Done = 0
  END CONSTRUCTOR

  METHOD Complete()
    ME.Done = 1
  END METHOD

  METHOD PriorityLabel() AS STRING
    IF ME.Priority = 1 THEN RETURN "HIGH"
    IF ME.Priority = 2 THEN RETURN "MEDIUM"
    RETURN "LOW"
  END METHOD

  METHOD Display()
    DIM status AS STRING
    IF ME.Done THEN status = "[X]" ELSE status = "[ ]"
    PRINT status; " ["; ME.PriorityLabel(); "] "; ME.Title
  END METHOD
END CLASS


CLASS TaskList
  Tasks(100) AS Task
  Count AS INTEGER

  CONSTRUCTOR()
    ME.Count = 0
  END CONSTRUCTOR

  METHOD Add(task AS Task)
    ME.Tasks(ME.Count) = task
    ME.Count = ME.Count + 1
  END METHOD

  METHOD ShowAll()
    PRINT "--- Tasks ("; ME.Count; " total) ---"
    FOR i = 0 TO ME.Count - 1
      ME.Tasks(i).Display()
    NEXT i
    PRINT "---"
  END METHOD

  METHOD CountDone() AS INTEGER
    DIM n AS INTEGER
    n = 0
    FOR i = 0 TO ME.Count - 1
      IF ME.Tasks(i).Done THEN n = n + 1
    NEXT i
    RETURN n
  END METHOD
END CLASS


' --- Main ---

DIM list AS TaskList = NEW TaskList()

list.Add(NEW Task("Write report", 1))
list.Add(NEW Task("Buy groceries", 2))
list.Add(NEW Task("Clean garage", 3))
list.Add(NEW Task("Call dentist", 1))

list.ShowAll()

PRINT ""
PRINT "Completing first task..."
list.Tasks(0).Complete()

list.ShowAll()
PRINT "Done: "; list.CountDone(); " / "; list.Count

END
```

---

## 5. Comparison with Existing Features

| Feature | TYPE (existing) | CLASS (new) |
|---------|----------------|-------------|
| Fields | ✓ | ✓ (same syntax) |
| Nesting | ✓ (field of another TYPE) | ✓ (field of another CLASS or TYPE) |
| Arrays | ✓ `DIM arr(N) AS MyType` | ✓ `DIM arr(N) AS MyClass` |
| Methods | ✗ | ✓ METHOD...END METHOD |
| Constructor | ✗ | ✓ CONSTRUCTOR...END CONSTRUCTOR |
| Inheritance | ✗ | ✓ EXTENDS (single) |
| Polymorphism | ✗ | ✓ vtable dispatch |
| Heap alloc | Manual via runtime | Automatic via NEW |
| ME reference | ✗ | ✓ |
| SIMD accel | ✓ (NEON for numeric UDTs) | Not initially (fields only) |

**TYPE is not going away.** TYPE remains the right choice for small, flat,
value-like data structures (points, rectangles, colours) — especially those
that benefit from SIMD.  CLASS is for when you need behaviour (methods),
hierarchy (inheritance), or polymorphism.

Programs can freely mix TYPE and CLASS:

```basic
TYPE Point
  X AS DOUBLE
  Y AS DOUBLE
END TYPE

CLASS Shape
  Origin AS Point              ' TYPE used as a field in a CLASS
  Color AS STRING

  METHOD MoveTo(p AS Point)
    ME.Origin = p
  END METHOD
END CLASS
```

---

## 6. What Is Intentionally Left Out (For Now)

These features are deliberately omitted from the initial version to keep
the implementation tractable and the language simple.  Each can be added
later without breaking existing programs.

| Feature | Rationale for deferral |
|---------|----------------------|
| **PRIVATE / PUBLIC** | Everything is public. Encapsulation via convention (prefix `_` for internal fields). Keeps the mental model simple. |
| **ABSTRACT / INTERFACE** | Single inheritance + composition covers most needs. Interfaces add complexity to vtables and type checking. |
| **OPERATOR overloading** | Useful but not essential for structuring programs. Can be added as syntactic sugar later. |
| **STATIC methods/fields** | Module-level SUB/FUNCTION already fills this role. No need to duplicate. |
| **Generics / Templates** | Way too complex for a BASIC dialect. Use HASHMAP or typed arrays instead. |
| **Automatic memory management** | Phase 1 uses explicit DELETE or leak-on-exit. Phase 2 can add reference counting transparently. |
| **PROTECTED visibility** | Only meaningful with deeper inheritance hierarchies. Defer until real demand appears. |
| **Multiple constructors** | Use optional parameters or a factory FUNCTION instead. |

---

## 7. Interaction with Existing Language Features

### 7.1 FOR EACH

Objects that expose an iterator interface (future work) could support
`FOR EACH`.  For now, iterate manually or use array fields.

### 7.2 HASHMAP

Objects can be stored in hashmaps:

```basic
DIM registry AS HASHMAP
DIM dog AS Dog = NEW Dog("Rex", "Lab")
registry("rex") = dog
```

The hashmap stores the object pointer (like it stores string descriptor
pointers today).

### 7.3 PRINT

`PRINT obj` will print the class name and pointer by default:

```basic
PRINT rex    ' → [Dog@0x1a2b3c]
```

A class can override this by defining a `ToString` method which PRINT
will call automatically if present:

```basic
CLASS Dog EXTENDS Animal
  METHOD ToString() AS STRING
    RETURN ME.Name & " the " & ME.Breed
  END METHOD
END CLASS

PRINT rex    ' → Rex the Labrador
```

### 7.4 SUB / FUNCTION

Objects can be passed to and returned from standalone SUB/FUNCTION:

```basic
FUNCTION MakeDog(name AS STRING) AS Dog
  RETURN NEW Dog(name, "Mutt")
END FUNCTION

SUB WalkDog(d AS Dog)
  PRINT "Walking "; d.Name
END SUB

DIM myDog AS Dog = MakeDog("Buddy")
WalkDog(myDog)
```

Objects are passed **by reference** (pointer copy) — the called function
operates on the same object, not a copy.

### 7.5 IS NOTHING / Null Safety

```basic
DIM d AS Dog
IF d IS NOTHING THEN PRINT "Not yet created"
d = NEW Dog("Rex", "Lab")
IF NOT (d IS NOTHING) THEN d.Speak()
```

Calling a method on NOTHING is a runtime error with a clear message:

```
ERROR: Method call on NOTHING reference at line 42
```

---

## 8. Keyword Summary

| Keyword | Context | Purpose |
|---------|---------|---------|
| `CLASS` | Top-level | Begin class declaration |
| `END CLASS` | Top-level | End class declaration |
| `EXTENDS` | CLASS header | Name parent class |
| `CONSTRUCTOR` | Inside CLASS | Begin constructor |
| `END CONSTRUCTOR` | Inside CLASS | End constructor |
| `DESTRUCTOR` | Inside CLASS | Begin destructor (optional) |
| `END DESTRUCTOR` | Inside CLASS | End destructor |
| `METHOD` | Inside CLASS | Begin method |
| `END METHOD` | Inside CLASS | End method |
| `ME` | Inside METHOD/CONSTRUCTOR | Current object reference |
| `SUPER` | Inside CONSTRUCTOR/METHOD | Parent class reference |
| `NEW` | Expression | Create object instance |
| `DELETE` | Statement | Destroy object instance |
| `NOTHING` | Expression | Null object reference |
| `IS` | Expression | Type-check operator |

---

## 9. Error Messages

The compiler and runtime should produce clear, BASIC-friendly error messages:

| Situation | Error Message |
|-----------|--------------|
| Unknown class | `CLASS 'Foo' is not defined` |
| Wrong constructor args | `CONSTRUCTOR for 'Dog' expects 2 arguments, got 3` |
| Unknown method | `CLASS 'Animal' has no method 'Fly'` |
| Unknown field | `CLASS 'Animal' has no field 'Wings'` |
| SUPER without parent | `SUPER can only be used in a class that EXTENDS another class` |
| SUPER not first | `SUPER() must be the first statement in CONSTRUCTOR` |
| Circular inheritance | `Circular inheritance detected: Dog → Animal → Dog` |
| ME outside class | `ME can only be used inside a METHOD or CONSTRUCTOR` |
| Method on NOTHING | `Runtime error: Method call on NOTHING reference at line 42` |
| Field on NOTHING | `Runtime error: Field access on NOTHING reference at line 42` |
| Type mismatch | `Cannot assign 'Cat' to variable of type 'Dog' (not in inheritance chain)` |
| Duplicate method | `METHOD 'Speak' is already defined in CLASS 'Cat'` |
| Override signature | `METHOD 'Speak' in 'Cat' has different parameters than in parent 'Animal'` |

---

## 10. Migration Path

Existing FasterBASIC programs are **100% unaffected**.  CLASS adds new
keywords but does not change the meaning of any existing syntax.

Users can adopt CLASS incrementally:

1. **Start** — Keep using TYPE for data, SUB/FUNCTION for logic
2. **Explore** — Convert one TYPE to a CLASS, add a constructor and a method
3. **Grow** — Use inheritance to share behaviour across related classes
4. **Structure** — Organise a larger program around a class hierarchy

No "big bang" rewrite is needed.  TYPE and CLASS coexist happily.