# FasterBASIC LIST Design Document

**Version:** 2.0  
**Date:** February 2026  
**Status:** Design / Pre-Implementation  

---

## 1. Motivation

FasterBASIC currently supports fixed-size arrays (`DIM`) and hashmaps as collection types. Lists fill an important gap: a **dynamically-sized, ordered collection** that grows and shrinks without requiring the programmer to predict sizes or call `REDIM`. Lists are the natural choice for accumulating results, building queues, stacks, and processing sequences of data.

The NBCPL compiler already proved out a ListHeader/ListAtom architecture with SAMM integration, O(1) append via a tail pointer, type-tagged atoms, and freelist-based allocation. FasterBASIC inherits this runtime foundation and wraps it in a BASIC-friendly syntax that feels familiar to BASIC programmers while exposing the full power of the underlying linked structure.

---

## 2. Design Goals

| Goal | Detail |
|------|--------|
| **BASIC-native syntax** | Reads like BASIC, not Lisp. No pointer arithmetic exposed to the user. |
| **Typed lists** | `LIST OF INTEGER`, `LIST OF STRING`, `LIST OF ANY` — the compiler knows what the list holds. |
| **Compile-time enforcement** | `LIST OF INTEGER` rejects `.APPEND "hello"` at compile time, not runtime. |
| **Type inference** | `LIST(1, 2, 3)` infers `LIST OF INTEGER`; `LIST(1, "x", 3.14)` infers `LIST OF ANY`. |
| **O(1) append and prepend** | Head and tail pointers in the header make both ends cheap. |
| **SAMM-managed** | Lists are scope-tracked. No manual cleanup required (though `ERASE` is available). |
| **FOR EACH integration** | Lists work with the existing `FOR EACH ... IN` loop syntax, with statically-typed iteration variables for typed lists. |
| **Object-method style** | Uses the same `object.METHOD(args)` pattern established by HASHMAP. |
| **Codegen reuse** | Registered as a built-in object type via `RuntimeObjectRegistry`, same path as HASHMAP. |

---

## 3. The Type System: LIST OF WHAT?

This is the central design question. A `LIST` is not a type — `LIST OF INTEGER` is a type. The element type flows through the entire compiler: parsing, semantic analysis, codegen dispatch, and FOR EACH variable typing.

### 3.1 Supported Element Types

| Declaration | Element BaseType | Atom Tag | Notes |
|-------------|-----------------|----------|-------|
| `LIST OF INTEGER` | `BaseType::INTEGER` | `ATOM_INT` | 32-bit signed integer (widened to 64-bit in atom) |
| `LIST OF LONG` | `BaseType::LONG` | `ATOM_INT` | 64-bit signed integer |
| `LIST OF DOUBLE` | `BaseType::DOUBLE` | `ATOM_FLOAT` | 64-bit float |
| `LIST OF SINGLE` | `BaseType::SINGLE` | `ATOM_FLOAT` | 32-bit float (stored as 64-bit in atom) |
| `LIST OF STRING` | `BaseType::STRING` | `ATOM_STRING` | StringDescriptor pointer |
| `LIST OF LIST` | `BaseType::OBJECT` ("LIST") | `ATOM_LIST` | Nested ListHeader pointer |
| `LIST OF HASHMAP` | `BaseType::OBJECT` ("HASHMAP") | `ATOM_OBJECT` | Nested hashmap pointer |
| `LIST OF ANY` | `BaseType::UNKNOWN` | varies | Heterogeneous — each atom carries its own type tag |
| `LIST` (bare) | `BaseType::UNKNOWN` | varies | Shorthand for `LIST OF ANY` |

### 3.2 TypeDescriptor Representation

The existing `TypeDescriptor` already has the field we need:

```cpp
struct TypeDescriptor {
    BaseType baseType;              // BaseType::OBJECT
    std::string objectTypeName;     // "LIST"
    BaseType elementType;           // ← THIS: what the list holds
    // ...
};
```

For arrays, `elementType` already carries the element type. Lists reuse the same field:

```cpp
// LIST OF INTEGER
TypeDescriptor listOfInt = TypeDescriptor::makeObject("LIST");
listOfInt.elementType = BaseType::INTEGER;

// LIST OF STRING
TypeDescriptor listOfStr = TypeDescriptor::makeObject("LIST");
listOfStr.elementType = BaseType::STRING;

// LIST OF ANY (heterogeneous)
TypeDescriptor listOfAny = TypeDescriptor::makeObject("LIST");
listOfAny.elementType = BaseType::UNKNOWN;

// LIST OF LIST (nested)
TypeDescriptor listOfList = TypeDescriptor::makeObject("LIST");
listOfList.elementType = BaseType::OBJECT;
// listOfList.nestedObjectTypeName = "LIST";  // potential extension for deep nesting
```

### 3.3 Factory Method

Add a convenience factory to `TypeDescriptor`:

```cpp
static TypeDescriptor makeList(BaseType elemType = BaseType::UNKNOWN) {
    TypeDescriptor desc = makeObject("LIST");
    desc.elementType = elemType;
    return desc;
}

// Usage:
auto intList  = TypeDescriptor::makeList(BaseType::INTEGER);
auto strList  = TypeDescriptor::makeList(BaseType::STRING);
auto anyList  = TypeDescriptor::makeList();  // LIST OF ANY
```

### 3.4 Type Predicates

```cpp
bool isList() const {
    return baseType == BaseType::OBJECT && objectTypeName == "LIST";
}

bool isTypedList() const {
    return isList() && elementType != BaseType::UNKNOWN;
}

bool isHeterogeneousList() const {
    return isList() && elementType == BaseType::UNKNOWN;
}

BaseType listElementType() const {
    return isList() ? elementType : BaseType::UNKNOWN;
}
```

### 3.5 Type Inference from LIST(...) Literals

When the programmer writes `LIST(...)` without an explicit type declaration, the compiler infers the element type from the arguments:

```basic
LET a = LIST(1, 2, 3)              ' Inferred: LIST OF INTEGER
LET b = LIST(1.5, 2.7, 3.9)       ' Inferred: LIST OF DOUBLE
LET c = LIST("x", "y", "z")       ' Inferred: LIST OF STRING
LET d = LIST(1, "hello", 3.14)    ' Inferred: LIST OF ANY (mixed)
LET e = LIST()                     ' Inferred: LIST OF ANY (empty, no info)
```

**Inference rules:**

1. If all arguments have the same base type → `LIST OF <that type>`
2. If all arguments are numeric but mixed int/double → `LIST OF DOUBLE` (widening)
3. If arguments have different base types (e.g. int + string) → `LIST OF ANY`
4. Empty `LIST()` → `LIST OF ANY` (no information to infer from)
5. If `LIST()` is assigned to a typed variable, the variable's type wins

```basic
DIM nums AS LIST OF INTEGER
nums = LIST()                      ' Empty list, but typed as LIST OF INTEGER
nums = LIST(1, 2, 3)              ' OK — all integers
nums = LIST(1, "oops", 3)         ' COMPILE ERROR: "oops" is STRING, expected INTEGER
```

### 3.6 Compile-Time Type Checking

For typed lists, the compiler enforces element type compatibility at every operation:

```basic
DIM nums AS LIST OF INTEGER
nums.APPEND 42                     ' OK
nums.APPEND 3.14                   ' COMPILE ERROR: DOUBLE not compatible with INTEGER
nums.APPEND "hello"                ' COMPILE ERROR: STRING not compatible with INTEGER

DIM things AS LIST OF ANY
things.APPEND 42                   ' OK — any type accepted
things.APPEND "hello"              ' OK
things.APPEND 3.14                 ' OK

DIM words AS LIST OF STRING
words.APPEND "hello"               ' OK
words.APPEND 42                    ' COMPILE ERROR: INTEGER not compatible with STRING
```

**Numeric widening:** `LIST OF DOUBLE` accepts integer arguments (widened silently), but `LIST OF INTEGER` does not accept doubles:

```basic
DIM values AS LIST OF DOUBLE
values.APPEND 42                   ' OK — 42 widened to 42.0
values.APPEND 3.14                 ' OK

DIM counts AS LIST OF INTEGER
counts.APPEND 3.14                 ' COMPILE ERROR: would lose precision
```

### 3.7 Impact on Codegen

The element type determines which runtime function the codegen emits — **at compile time, with no runtime dispatch overhead for typed lists**:

| List Type | `.APPEND x` emits | `.GET(n)` emits | `.HEAD` emits |
|-----------|-------------------|-----------------|---------------|
| `LIST OF INTEGER` | `list_append_int` | `list_get_int` | `list_head_int` |
| `LIST OF DOUBLE` | `list_append_float` | `list_get_float` | `list_head_float` |
| `LIST OF STRING` | `list_append_string` | `list_get_ptr` | `list_head_ptr` |
| `LIST OF LIST` | `list_append_list` | `list_get_ptr` | `list_head_ptr` |
| `LIST OF ANY` | dispatch by argument type | `list_get_int` + type tag | `list_head_int` + type tag |

For `LIST OF ANY`, the codegen dispatches APPEND based on the compile-time type of the *argument expression*:

```basic
DIM mixed AS LIST OF ANY
mixed.APPEND 42         ' Codegen checks expr type → INTEGER → list_append_int
mixed.APPEND "hello"    ' Codegen checks expr type → STRING  → list_append_string
mixed.APPEND 3.14       ' Codegen checks expr type → DOUBLE  → list_append_float
```

For GET/HEAD on `LIST OF ANY`, the codegen must emit runtime type dispatch — load the atom's type tag, then branch to the appropriate extraction.

### 3.8 Impact on FOR EACH

The element type determines the iteration variable's type:

```basic
' Typed list — compiler knows the iteration variable type statically
DIM nums AS LIST OF INTEGER
FOR EACH n IN nums           ' n is INTEGER — no runtime type check needed
    PRINT n * 2              ' Codegen emits integer multiply directly
NEXT n

DIM words AS LIST OF STRING
FOR EACH w IN words          ' w is STRING — loadl, passed to print_string
    PRINT UCASE$(w)
NEXT w

' Heterogeneous list — iteration variable is loaded as raw 64-bit
DIM mixed AS LIST OF ANY
FOR EACH item IN mixed       ' item is "variant" — 64-bit value
    SELECT CASE TYPEOF(item) ' TYPEOF() reads the atom's type tag
        CASE LIST_TYPE_INT:    PRINT "Int: "; item
        CASE LIST_TYPE_STRING: PRINT "Str: "; item
        CASE LIST_TYPE_FLOAT:  PRINT "Flt: "; item
    END SELECT
NEXT item
```

For `LIST OF ANY`, the FOR EACH loop stores the current atom's type tag in a hidden variable (`__foreach_type_<var>`) that `TYPEOF()` reads. This is only needed for heterogeneous lists — typed lists skip this overhead entirely.

### 3.9 Assignment Compatibility

```basic
DIM a AS LIST OF INTEGER
DIM b AS LIST OF INTEGER
DIM c AS LIST OF ANY
DIM d AS LIST OF STRING

b = a                          ' OK — same element type
c = a                          ' OK — ANY accepts anything (widens)
a = c                          ' COMPILE WARNING: narrowing from ANY to INTEGER
d = a                          ' COMPILE ERROR: incompatible element types
```

| From → To | Rule |
|-----------|------|
| Same type → Same type | OK |
| Typed → ANY | OK (always safe) |
| ANY → Typed | Warning (runtime elements may not match) |
| Typed → Different typed | Error |

---

## 4. Runtime Data Structures

### 4.1 ListHeader (32 bytes)

The list variable points to a `ListHeader`. This is the "handle" that the BASIC program holds. The header carries metadata and pointers to both ends of the element chain.

```
┌─────────────────────────────────────────────────────────────────┐
│  type (i32)  │  flags (i32)  │  length (i64)                   │
├─────────────────────────────────────────────────────────────────┤
│  head (ptr)                  │  tail (ptr)                      │
└─────────────────────────────────────────────────────────────────┘
```

```c
typedef struct ListHeader {
    int32_t  type;       /* Always ATOM_SENTINEL (0) — distinguishes header from atom */
    int32_t  flags;      /* Bit flags: immutable, element_type hint, etc. */
    int64_t  length;     /* Number of elements — maintained on every add/remove */
    struct ListAtom* head;  /* First element (NULL if empty) */
    struct ListAtom* tail;  /* Last element  (NULL if empty) */
} ListHeader;
```

**Key invariant:** `type == 0` (ATOM_SENTINEL) distinguishes a header from an atom in memory. This is how runtime code can tell whether a `void*` is pointing at a list-as-a-whole or at an individual node. The NBCPL implementation uses this same sentinel approach.

**The `flags` field** can optionally encode the list's element type at runtime (for debugging, TYPEOF on the list itself, and runtime safety checks). This is secondary to compile-time enforcement but useful for `LIST OF ANY` validation:

```c
#define LIST_FLAG_ELEM_ANY     0x0000
#define LIST_FLAG_ELEM_INT     0x0100
#define LIST_FLAG_ELEM_FLOAT   0x0200
#define LIST_FLAG_ELEM_STRING  0x0300
#define LIST_FLAG_ELEM_LIST    0x0400
#define LIST_FLAG_ELEM_OBJECT  0x0500
#define LIST_FLAG_ELEM_MASK    0x0F00
#define LIST_FLAG_IMMUTABLE    0x0001
```

### 4.2 ListAtom (24 bytes)

Each element in the list is a type-tagged atom with a next pointer.

```
┌─────────────────────────────────────────────────────────────────┐
│  type (i32)  │  pad (i32)   │  value (i64 union)               │
├─────────────────────────────────────────────────────────────────┤
│  next (ptr)                                                     │
└─────────────────────────────────────────────────────────────────┘
```

```c
typedef struct ListAtom {
    int32_t type;      /* ATOM_INT, ATOM_FLOAT, ATOM_STRING, ATOM_LIST, ... */
    int32_t pad;       /* Alignment padding */
    union {
        int64_t int_value;       /* Integer value */
        double  float_value;     /* Double value */
        void*   ptr_value;       /* String descriptor, nested list header, object */
    } value;
    struct ListAtom* next;       /* Next atom in chain (NULL = last) */
} ListAtom;
```

**For typed lists** (`LIST OF INTEGER`, etc.) the atom `type` field is redundant — every atom has the same type tag. But it is always set correctly so that:

1. Runtime functions work identically whether called on typed or untyped lists.
2. `list_free()` knows how to clean up each atom (release strings, recurse into nested lists).
3. A `LIST OF INTEGER` that gets assigned to a `LIST OF ANY` variable keeps its type tags.

### 4.3 Atom Type Tags

```c
#define ATOM_SENTINEL     0    /* ListHeader marker — never used on atoms */
#define ATOM_INT          1    /* int64_t */
#define ATOM_FLOAT        2    /* double */
#define ATOM_STRING       3    /* StringDescriptor* */
#define ATOM_LIST         4    /* Nested ListHeader* */
#define ATOM_OBJECT       5    /* Generic object pointer */
```

### 4.4 Head vs. Normal Element

The `ListHeader` is what the BASIC variable points to. It is **not** an element — it is the container. Individual atoms are the elements. This distinction matters because:

- **Append** creates a new atom and links it after `tail`, then updates `tail`.
- **Prepend** creates a new atom and links it before `head`, then updates `head`.
- **Iteration** starts at `header->head` and follows `atom->next` pointers.
- The user never sees or handles raw atoms — they always work through the header.

Since the header's `type` field is `ATOM_SENTINEL (0)` and atoms always have `type >= 1`, any runtime function receiving a `void*` can distinguish between "this is a list handle" and "this is a bare element pointer" with a single integer check. This is the same approach NBCPL uses and it enables safe defensive coding in the runtime.

---

## 5. BASIC Syntax

### 5.1 Declaration & Creation

```basic
' === Typed declarations ===
DIM nums AS LIST OF INTEGER
DIM values AS LIST OF DOUBLE
DIM words AS LIST OF STRING
DIM matrix AS LIST OF LIST
DIM things AS LIST OF ANY         ' Explicit heterogeneous
DIM bag AS LIST                   ' Shorthand for LIST OF ANY

' === Declaration with initialisation ===
DIM nums AS LIST OF INTEGER = LIST(1, 2, 3, 4, 5)
DIM words AS LIST OF STRING = LIST("hello", "world", "BASIC")

' === Inferred types from LIST() literals ===
LET a = LIST(1, 2, 3)            ' Inferred: LIST OF INTEGER
LET b = LIST("x", "y")           ' Inferred: LIST OF STRING
LET c = LIST(1, "mixed", 3.14)   ' Inferred: LIST OF ANY
LET d = LIST()                    ' Inferred: LIST OF ANY (empty)

' === Empty typed list via function ===
DIM nums AS LIST OF INTEGER
LET nums = LIST()                 ' Empty, but variable type constrains to INTEGER

' === Nested lists ===
DIM grid AS LIST OF LIST = LIST( _
    LIST(1, 2, 3), _
    LIST(4, 5, 6), _
    LIST(7, 8, 9)  _
)
```

`LIST(...)` is a **list constructor expression**. When the arguments are all compile-time constants the compiler can emit a static template in the data section and deep-copy at runtime (the NBCPL "static path"). When any argument is a variable or expression, the compiler emits the "dynamic path": create empty header, then append each element.

### 5.2 Adding Elements

```basic
DIM nums AS LIST OF INTEGER
nums.APPEND 42                    ' OK — integer into integer list
nums.APPEND 99

DIM things AS LIST OF ANY
things.APPEND 42                  ' OK — any type accepted
things.APPEND "hello"             ' OK
things.APPEND 3.14                ' OK

' Prepend to beginning — O(1) via head pointer
nums.PREPEND 0

' Append another list's elements (concatenate)
nums.EXTEND otherNums
```

These are **method-call statements**, parsed exactly like HASHMAP method calls. The first argument after the method name is the value.

### 5.3 Removing Elements

```basic
' Remove first element and return its value
LET first% = nums.SHIFT

' Remove last element and return its value
LET last% = nums.POP

' Remove element at position (1-based) — O(n) traversal
nums.REMOVE 3

' Remove all elements
nums.CLEAR
```

`SHIFT` and `POP` are methods that return a value. For typed lists, the return type matches the element type. For `LIST OF ANY`, the return type is `LONG` (64-bit raw value) and `TYPEOF()` can be used to interpret it.

### 5.4 Accessing Elements

```basic
' Head and rest — functional style
LET first% = nums.HEAD          ' Value of first element (INTEGER for LIST OF INTEGER)
DIM rest AS LIST OF INTEGER = nums.REST   ' New list: everything except first

' Indexed access (1-based) — O(n), traverses from head
LET x% = nums.GET(3)            ' Third element

' Length
PRINT nums.LENGTH                ' Number of elements (O(1), stored in header)
' or equivalently:
PRINT LEN(nums)

' Check for empty
IF nums.EMPTY THEN PRINT "List is empty"
```

**Note on subscript syntax:** We deliberately avoid `myList(3)` syntax for indexed access because the parser already interprets `name(expr)` as an array access or object subscript. Using `.GET(n)` keeps the grammar unambiguous. If subscript access is added later, the object subscript infrastructure (`enableSubscript`) provides a clean path — the key type would be `INTEGER` and the return type would be the element type.

### 5.5 Iteration

Lists integrate with the existing `FOR EACH` loop. The iteration variable's type is determined by the list's element type:

```basic
' === Typed list — iteration variable type is known at compile time ===
DIM nums AS LIST OF INTEGER
FOR EACH n IN nums               ' n is INTEGER
    PRINT n * 2                   ' Integer arithmetic, no type dispatch
NEXT n

DIM words AS LIST OF STRING
FOR EACH w IN words              ' w is STRING
    PRINT UCASE$(w)              ' String operations work directly
NEXT w

' === With index variable (1-based position) ===
FOR EACH item, idx IN nums
    PRINT idx; ": "; item
NEXT item

' === Heterogeneous list — need TYPEOF() for dispatch ===
DIM mixed AS LIST OF ANY
FOR EACH item IN mixed           ' item is 64-bit raw value
    SELECT CASE TYPEOF(item)
        CASE LIST_TYPE_INT
            PRINT "Integer: "; item
        CASE LIST_TYPE_FLOAT
            PRINT "Float: "; item
        CASE LIST_TYPE_STRING
            PRINT "String: "; item
        CASE LIST_TYPE_LIST
            PRINT "Nested list"
    END SELECT
NEXT item
```

**Codegen strategy:** The FOR EACH loop over a list is lowered to a cursor-based traversal:

```
cursor = header->head
idx = 1
while cursor != NULL:
    [for typed lists: item = cursor->value.int_value (or float, or ptr)]
    [for LIST OF ANY: item = cursor->value.int_value; type = cursor->type]
    <body>
    cursor = cursor->next
    idx += 1
```

For typed lists the codegen emits a direct field access (no type-tag switch). For `LIST OF ANY` it stores the type tag in a hidden variable for `TYPEOF()`.

### 5.6 Type Inspection

```basic
' Built-in constants (defined by compiler, match ATOM_* tags)
CONST LIST_TYPE_INT    = 1
CONST LIST_TYPE_FLOAT  = 2
CONST LIST_TYPE_STRING = 3
CONST LIST_TYPE_LIST   = 4
CONST LIST_TYPE_OBJECT = 5
```

`TYPEOF()` is meaningful inside a `FOR EACH` loop over a `LIST OF ANY`. For typed lists, `TYPEOF()` always returns the same constant — the compiler can optimise the call away entirely.

### 5.7 List Operations

```basic
' Copy (deep copy — new header, new atoms, strings retained)
DIM copy AS LIST OF INTEGER = nums.COPY

' Reverse (returns new reversed list; original unchanged)
DIM rev AS LIST OF INTEGER = nums.REVERSE

' Search
IF nums.CONTAINS(42) THEN PRINT "Found it"
LET pos = nums.INDEXOF(42)    ' 0 if not found, 1-based position if found

' Join elements with separator (converts each element to string)
DIM words AS LIST OF STRING = LIST("hello", "world")
PRINT words.JOIN(", ")         ' "hello, world"

' Convert to array (for typed numeric/string lists)
DIM arr%() = nums.TOARRAY
```

### 5.8 Memory Management

```basic
' Automatic — SAMM tracks the list header and cleans up at scope exit.
' No action needed in most code.

' Explicit cleanup (optional — for early release of large lists)
ERASE myList

' SAMM awareness:
' - LIST() constructor auto-tracks the new header in the current SAMM scope.
' - APPEND auto-tracks each new atom.
' - When scope exits, SAMM releases all tracked atoms and the header.
' - String atoms: string_release() is called (drops list's ownership claim).
' - Nested list atoms: list_free() is called recursively.
' - If a list is returned from a function, samm_retain_parent() moves it
'   to the parent scope (same pattern as strings and objects).
```

---

## 6. Complete Example Program

```basic
' list_demo.bas — Demonstrates typed list operations in FasterBASIC

PRINT "=== FasterBASIC List Demo ==="
PRINT ""

' === Typed list of doubles ===
DIM temps AS LIST OF DOUBLE = LIST(72.5, 68.0, 75.3, 80.1, 65.7)
temps.APPEND 77.2

PRINT "Temperatures recorded:"
FOR EACH t, day IN temps
    PRINT "  Day "; day; ": "; t; " F"
NEXT t
PRINT "Total readings: "; temps.LENGTH
PRINT ""

' === Typed list of strings ===
DIM names AS LIST OF STRING = LIST("Alice", "Bob", "Charlie")
names.APPEND "Diana"
names.PREPEND "Zara"

PRINT "Team roster:"
FOR EACH name IN names
    PRINT "  - "; name
NEXT name
PRINT ""

' === Nested list (LIST OF LIST) ===
DIM grid AS LIST OF LIST = LIST( _
    LIST(1, 2, 3), _
    LIST(4, 5, 6), _
    LIST(7, 8, 9)  _
)

PRINT "Grid:"
FOR EACH row IN grid
    FOR EACH cell IN row
        PRINT cell; " ";
    NEXT cell
    PRINT ""
NEXT row
PRINT ""

' === Heterogeneous list with type inspection ===
DIM record AS LIST = LIST("John Doe", 42, 75000.50)

PRINT "Employee record:"
FOR EACH field IN record
    SELECT CASE TYPEOF(field)
        CASE LIST_TYPE_STRING
            PRINT "  Text:   "; field
        CASE LIST_TYPE_INT
            PRINT "  Number: "; field
        CASE LIST_TYPE_FLOAT
            PRINT "  Amount: "; field
    END SELECT
NEXT field
PRINT ""

' === Stack usage (LIFO) with typed list ===
DIM stack AS LIST OF STRING
stack.APPEND "first"
stack.APPEND "second"
stack.APPEND "third"
LET top$ = stack.POP
PRINT "Popped from stack: "; top$

' === Queue usage (FIFO) with typed list ===
DIM queue AS LIST OF STRING
queue.APPEND "job-1"
queue.APPEND "job-2"
queue.APPEND "job-3"
LET next_job$ = queue.SHIFT
PRINT "Next job from queue: "; next_job$

PRINT ""
PRINT "=== Demo Complete ==="
' No cleanup needed — SAMM handles it
```

---

## 7. Method Reference

### 7.1 Mutating Methods (modify the list in-place)

| Method | Signature | Description | Complexity | Type Check |
|--------|-----------|-------------|------------|------------|
| `APPEND` | `.APPEND value` | Add element to end | O(1) | Value must match element type |
| `PREPEND` | `.PREPEND value` | Add element to beginning | O(1) | Value must match element type |
| `INSERT` | `.INSERT pos, value` | Insert at 1-based position | O(n) | Value must match element type |
| `REMOVE` | `.REMOVE pos` | Remove element at 1-based position | O(n) | — |
| `CLEAR` | `.CLEAR` | Remove all elements | O(n) | — |
| `EXTEND` | `.EXTEND otherList` | Append all elements from another list | O(m) | Other list element type must be compatible |

### 7.2 Accessor Methods (return a value, do not modify)

| Method | Return Type | Description | Complexity |
|--------|-------------|-------------|------------|
| `HEAD` | element type | Value of first element | O(1) |
| `REST` | LIST OF same type | New list of all elements except first | O(n) |
| `GET(pos)` | element type | Value at 1-based position | O(n) |
| `LENGTH` | INTEGER | Number of elements | O(1) |
| `EMPTY` | INTEGER | 1 if empty, 0 if not | O(1) |
| `CONTAINS(val)` | INTEGER | 1 if value found, 0 if not | O(n) |
| `INDEXOF(val)` | INTEGER | 1-based position, or 0 if not found | O(n) |
| `JOIN(sep$)` | STRING | Concatenate elements with separator | O(n) |

"Element type" means: INTEGER for `LIST OF INTEGER`, STRING for `LIST OF STRING`, etc. For `LIST OF ANY`, HEAD/GET return LONG (raw 64-bit) and the caller uses `TYPEOF()` to interpret.

### 7.3 Methods That Return New Lists

| Method | Return Type | Description | Complexity |
|--------|-------------|-------------|------------|
| `COPY` | LIST OF same type | Deep copy of the list | O(n) |
| `REVERSE` | LIST OF same type | New list in reversed order | O(n) |
| `SHIFT` | element type | Remove and return first element | O(1) |
| `POP` | element type | Remove and return last element | O(n)* |

*\*POP is O(n) in a singly-linked list because we must find the new tail. If profiling shows POP is hot, we can add a `prev` pointer to make it doubly-linked, or maintain a "second-to-last" cache.*

---

## 8. Runtime API (C Functions)

These are the C functions the codegen will call. They follow the naming convention `list_*` to parallel `string_*` and `hashmap_*`.

```c
/* === Creation === */
ListHeader* list_create(void);                          /* New empty list */
ListHeader* list_create_typed(int32_t elem_type_flag);  /* New empty list with element type hint in flags */

/* === Adding Elements (type-specific) === */
void list_append_int(ListHeader* list, int64_t value);
void list_append_float(ListHeader* list, double value);
void list_append_string(ListHeader* list, StringDescriptor* value);
void list_append_list(ListHeader* list, ListHeader* nested);
void list_append_object(ListHeader* list, void* object_ptr);

void list_prepend_int(ListHeader* list, int64_t value);
void list_prepend_float(ListHeader* list, double value);
void list_prepend_string(ListHeader* list, StringDescriptor* value);
void list_prepend_list(ListHeader* list, ListHeader* nested);

void list_insert_int(ListHeader* list, int64_t pos, int64_t value);
void list_insert_float(ListHeader* list, int64_t pos, double value);
void list_insert_string(ListHeader* list, int64_t pos, StringDescriptor* value);

void list_extend(ListHeader* dest, ListHeader* src);

/* === Removing Elements === */
int64_t  list_shift_int(ListHeader* list);              /* Remove+return first as int */
double   list_shift_float(ListHeader* list);            /* Remove+return first as float */
void*    list_shift_ptr(ListHeader* list);               /* Remove+return first as pointer */
int32_t  list_shift_type(ListHeader* list);              /* Type tag of first element */
void     list_shift(ListHeader* list);                   /* Remove first, discard value */

int64_t  list_pop_int(ListHeader* list);                /* Remove+return last as int */
double   list_pop_float(ListHeader* list);
void*    list_pop_ptr(ListHeader* list);
void     list_pop(ListHeader* list);                     /* Remove last, discard value */

void list_remove(ListHeader* list, int64_t pos);        /* Remove at 1-based position */
void list_clear(ListHeader* list);                       /* Remove all elements */

/* === Access === */
int64_t  list_get_int(ListHeader* list, int64_t pos);   /* Get int at 1-based position */
double   list_get_float(ListHeader* list, int64_t pos);
void*    list_get_ptr(ListHeader* list, int64_t pos);    /* Get string/list/object pointer */
int32_t  list_get_type(ListHeader* list, int64_t pos);  /* Type tag at position */

int64_t  list_head_int(ListHeader* list);               /* First element as int */
double   list_head_float(ListHeader* list);
void*    list_head_ptr(ListHeader* list);
int32_t  list_head_type(ListHeader* list);               /* Type tag of first element */

int64_t  list_length(ListHeader* list);                  /* O(1) from header */
int32_t  list_empty(ListHeader* list);                   /* 1 if empty, 0 otherwise */

/* === Iteration Support === */
ListAtom* list_iter_begin(ListHeader* list);             /* Returns header->head */
ListAtom* list_iter_next(ListAtom* current);             /* Returns current->next */
int32_t   list_iter_type(ListAtom* current);             /* Returns current->type */
int64_t   list_iter_value_int(ListAtom* current);        /* current->value.int_value */
double    list_iter_value_float(ListAtom* current);      /* current->value.float_value */
void*     list_iter_value_ptr(ListAtom* current);        /* current->value.ptr_value */

/* === Operations === */
ListHeader* list_copy(ListHeader* list);                 /* Deep copy */
ListHeader* list_rest(ListHeader* list);                 /* Copy of tail (all but first) */
ListHeader* list_reverse(ListHeader* list);              /* New reversed list */
int32_t     list_contains_int(ListHeader* list, int64_t value);
int32_t     list_contains_float(ListHeader* list, double value);
int32_t     list_contains_string(ListHeader* list, StringDescriptor* value);
int64_t     list_indexof_int(ListHeader* list, int64_t value);
int64_t     list_indexof_float(ListHeader* list, double value);
int64_t     list_indexof_string(ListHeader* list, StringDescriptor* value);
StringDescriptor* list_join(ListHeader* list, StringDescriptor* separator);

/* === Memory Management === */
void list_free(ListHeader* list);     /* Free header + all atoms + release strings */
```

### 8.1 Type-Dispatch: Compile-Time vs. Runtime

For **typed lists**, the codegen picks the right `_int` / `_float` / `_string` / `_list` variant at compile time. Zero runtime overhead:

```basic
DIM nums AS LIST OF INTEGER
nums.APPEND 42          ' Codegen emits: call $list_append_int(l %header, l 42)
                        ' No type check. No dispatch. Direct call.
```

For **LIST OF ANY**, the codegen inspects the argument expression's compile-time type and dispatches accordingly:

```basic
DIM bag AS LIST OF ANY
bag.APPEND 42           ' Argument is integer literal → list_append_int
bag.APPEND name$        ' Argument is string variable → list_append_string
bag.APPEND 3.14         ' Argument is double literal  → list_append_float
bag.APPEND subList      ' Argument is LIST variable   → list_append_list
```

The distinction: typed lists validate *and* dispatch at compile time; `LIST OF ANY` dispatches at compile time but skips validation (any type is accepted).

---

## 9. SAMM Integration

### 9.1 Tracking Strategy

| Allocation | SAMM Type | Tracked When | Cleaned How |
|------------|-----------|--------------|-------------|
| `ListHeader` | `SAMM_ALLOC_LIST` | On `list_create()` | `list_free()` via cleanup path |
| `ListAtom` | `SAMM_ALLOC_LIST_ATOM` | On each append/prepend/insert | Return to freelist |
| String values inside atoms | Already tracked as `SAMM_ALLOC_STRING` | On string creation | `string_release()` (existing) |
| Nested list headers | `SAMM_ALLOC_LIST` | On nested `list_create()` | Recursive `list_free()` |

### 9.2 Cleanup Path

When SAMM exits a scope containing tracked lists:

```
SAMM scope exit
  └─ for each tracked ptr of type SAMM_ALLOC_LIST:
       └─ list_free(ptr)
            ├─ samm_untrack(ptr)  ← same pattern as string_release()!
            ├─ walk atom chain from head to tail
            │   ├─ if atom->type == ATOM_STRING: string_release(atom->value.ptr_value)
            │   ├─ if atom->type == ATOM_LIST: list_free(atom->value.ptr_value)  [recursive]
            │   └─ return atom to freelist (or free)
            └─ return header to freelist (or free)
```

**Important:** Just as with strings, when a list is explicitly freed (via `ERASE` or `list_free`), the `list_free` function must call `samm_untrack(header)` before freeing — exactly the same pattern we established for `string_release()`. This prevents SAMM from double-freeing an already-cleaned list.

Atoms tracked as `SAMM_ALLOC_LIST_ATOM` in the SAMM scope are a secondary safety net. In normal operation, `list_free` walks the chain and frees all atoms itself. The per-atom SAMM tracking catches orphaned atoms if something goes wrong (e.g., a partial list construction that throws an error before the header is fully linked).

### 9.3 Returning Lists from Functions

Same pattern as strings and objects:

```basic
FUNCTION MakeNums() AS LIST OF INTEGER
    DIM result AS LIST OF INTEGER = LIST(1, 2, 3)
    MakeNums = result
END FUNCTION
```

The codegen emits `samm_retain_parent(result_ptr)` before the function returns, moving the list header to the parent scope so it survives the function's scope exit. This is identical to how string and CLASS returns work.

The return type `LIST OF INTEGER` is part of the function signature, enabling the caller to know the element type:

```basic
DIM myNums AS LIST OF INTEGER = MakeNums()   ' Types match
DIM myThings AS LIST OF ANY = MakeNums()     ' OK: widening to ANY
DIM myWords AS LIST OF STRING = MakeNums()   ' COMPILE ERROR: incompatible
```

### 9.4 Loop Scoping

When SAMM detects list-producing statements inside a loop body (via `bodyContainsDim` or equivalent heuristic), it emits per-iteration `samm_enter_scope()` / `samm_exit_scope()` to prevent accumulation of temporary lists:

```basic
FOR i = 1 TO 1000
    DIM temp AS LIST OF INTEGER = LIST(i, i*2, i*3)
    temp.APPEND i * 4
    PRINT temp.LENGTH
NEXT i   ' Per-iteration scope exits, temp is freed each iteration
```

---

## 10. Freelist Allocator (Performance)

For programs that create and destroy many lists and atoms (e.g., in tight loops or recursive algorithms), a freelist allocator avoids the overhead of `malloc`/`free` on every operation.

### 10.1 Design

```c
/* Thread-local freelists for headers and atoms */
static __thread ListHeader* header_freelist = NULL;
static __thread ListAtom*   atom_freelist   = NULL;
static __thread int         header_freelist_count = 0;
static __thread int         atom_freelist_count   = 0;

#define FREELIST_MAX_HEADERS  64
#define FREELIST_MAX_ATOMS   256

ListHeader* list_header_alloc(void) {
    if (header_freelist) {
        ListHeader* h = header_freelist;
        header_freelist = (ListHeader*)h->head;  /* reuse head ptr as freelist next */
        header_freelist_count--;
        memset(h, 0, sizeof(ListHeader));
        return h;
    }
    return (ListHeader*)calloc(1, sizeof(ListHeader));
}

void list_header_release(ListHeader* h) {
    if (header_freelist_count < FREELIST_MAX_HEADERS) {
        h->head = (ListAtom*)header_freelist;
        header_freelist = h;
        header_freelist_count++;
    } else {
        free(h);
    }
}

/* Same pattern for atoms */
```

### 10.2 Interaction with SAMM

The SAMM cleanup path for `SAMM_ALLOC_LIST` calls `list_free()` which returns headers and atoms to the freelist. The cleanup path for `SAMM_ALLOC_LIST_ATOM` returns individual atoms to the freelist. Only when the freelist is full does actual `free()` happen. This means the steady-state allocation cost for list-heavy programs is near zero.

---

## 11. Object Type Registration

LIST is registered as a built-in object type, exactly like HASHMAP. The key difference is that method return types and argument validation depend on the list's element type, which the codegen resolves at compile time.

```cpp
void RuntimeObjectRegistry::registerListType() {
    ObjectTypeDescriptor list;
    list.typeName = "LIST";
    list.description = "Ordered, dynamically-sized collection (typed or heterogeneous)";

    // Constructor: list_create() — no arguments
    list.setConstructor("list_create", {});

    // --- Mutating methods ---

    MethodSignature append("APPEND", BaseType::UNKNOWN, "list_append_int");
    append.addParam("value", BaseType::ANY)
          .withDescription("Append an element to the end of the list");
    // NOTE: actual runtime function is selected by codegen based on
    //       argument type and list element type:
    //       list_append_int / list_append_float / list_append_string / list_append_list
    list.addMethod(append);

    MethodSignature prepend("PREPEND", BaseType::UNKNOWN, "list_prepend_int");
    prepend.addParam("value", BaseType::ANY)
           .withDescription("Prepend an element to the beginning of the list");
    list.addMethod(prepend);

    MethodSignature insert("INSERT", BaseType::UNKNOWN, "list_insert_int");
    insert.addParam("pos", BaseType::INTEGER)
          .addParam("value", BaseType::ANY)
          .withDescription("Insert an element at a 1-based position");
    list.addMethod(insert);

    MethodSignature remove("REMOVE", BaseType::UNKNOWN, "list_remove");
    remove.addParam("pos", BaseType::INTEGER)
          .withDescription("Remove element at 1-based position");
    list.addMethod(remove);

    MethodSignature clear("CLEAR", BaseType::UNKNOWN, "list_clear");
    clear.withDescription("Remove all elements");
    list.addMethod(clear);

    MethodSignature extend("EXTEND", BaseType::UNKNOWN, "list_extend");
    extend.addParam("other", BaseType::OBJECT)
          .withDescription("Append all elements from another list");
    list.addMethod(extend);

    // --- Accessor methods ---
    // Return types shown here are defaults for LIST OF INTEGER.
    // The codegen overrides based on the list's actual element type.

    MethodSignature head("HEAD", BaseType::INTEGER, "list_head_int");
    head.withDescription("Get the value of the first element");
    list.addMethod(head);

    MethodSignature rest("REST", BaseType::OBJECT, "list_rest");
    rest.withDescription("New list containing all elements except the first");
    list.addMethod(rest);

    MethodSignature get("GET", BaseType::INTEGER, "list_get_int");
    get.addParam("pos", BaseType::INTEGER)
       .withDescription("Get element value at 1-based position");
    list.addMethod(get);

    MethodSignature length("LENGTH", BaseType::INTEGER, "list_length");
    length.withDescription("Number of elements (O(1))");
    list.addMethod(length);

    MethodSignature empty("EMPTY", BaseType::INTEGER, "list_empty");
    empty.withDescription("Check if the list is empty (1=yes, 0=no)");
    list.addMethod(empty);

    MethodSignature contains("CONTAINS", BaseType::INTEGER, "list_contains_int");
    contains.addParam("value", BaseType::ANY)
            .withDescription("Check if the list contains a value");
    list.addMethod(contains);

    MethodSignature indexof("INDEXOF", BaseType::INTEGER, "list_indexof_int");
    indexof.addParam("value", BaseType::ANY)
           .withDescription("Find 1-based position of value (0=not found)");
    list.addMethod(indexof);

    MethodSignature join("JOIN", BaseType::STRING, "list_join");
    join.addParam("separator", BaseType::STRING)
        .withDescription("Join elements into a string with separator");
    list.addMethod(join);

    // --- Methods returning new lists ---

    MethodSignature copy("COPY", BaseType::OBJECT, "list_copy");
    copy.withDescription("Create a deep copy of the list");
    list.addMethod(copy);

    MethodSignature reverse("REVERSE", BaseType::OBJECT, "list_reverse");
    reverse.withDescription("Create a new list in reversed order");
    list.addMethod(reverse);

    // --- Stack/Queue methods ---

    MethodSignature shift("SHIFT", BaseType::INTEGER, "list_shift_int");
    shift.withDescription("Remove and return the first element");
    list.addMethod(shift);

    MethodSignature pop("POP", BaseType::INTEGER, "list_pop_int");
    pop.withDescription("Remove and return the last element");
    list.addMethod(pop);

    registerObjectType(list);
}
```

### 11.1 Codegen Override Table

The registered `runtimeFunctionName` is a default. The codegen selects the actual function based on the list's element type:

| Method | LIST OF INTEGER | LIST OF DOUBLE | LIST OF STRING | LIST OF LIST | LIST OF ANY |
|--------|----------------|----------------|----------------|--------------|-------------|
| `APPEND` | `list_append_int` | `list_append_float` | `list_append_string` | `list_append_list` | by argument type |
| `PREPEND` | `list_prepend_int` | `list_prepend_float` | `list_prepend_string` | `list_prepend_list` | by argument type |
| `HEAD` | `list_head_int` | `list_head_float` | `list_head_ptr` | `list_head_ptr` | `list_head_int` + tag |
| `GET(n)` | `list_get_int` | `list_get_float` | `list_get_ptr` | `list_get_ptr` | `list_get_int` + tag |
| `SHIFT` | `list_shift_int` | `list_shift_float` | `list_shift_ptr` | `list_shift_ptr` | `list_shift_int` + tag |
| `POP` | `list_pop_int` | `list_pop_float` | `list_pop_ptr` | `list_pop_ptr` | `list_pop_int` + tag |
| `CONTAINS` | `list_contains_int` | `list_contains_float` | `list_contains_string` | n/a | by argument type |
| `INDEXOF` | `list_indexof_int` | `list_indexof_float` | `list_indexof_string` | n/a | by argument type |

---

## 12. Parser Changes

### 12.1 New Keywords

| Keyword | Role |
|---------|------|
| `LIST` | Type name in DIM/AS, and constructor expression `LIST(...)` |
| `OF` | Element type qualifier in `LIST OF <type>` |

`OF` may already be used in some dialects. If it conflicts, we can make it context-sensitive (only recognised after `LIST`).

### 12.2 Grammar Additions

```
dim-statement:
    DIM identifier AS LIST
    DIM identifier AS LIST OF type-name
    DIM identifier AS LIST = list-expression
    DIM identifier AS LIST OF type-name = list-expression

type-name:
    INTEGER | LONG | SINGLE | DOUBLE | STRING | LIST | HASHMAP | ANY

list-expression:
    LIST ( )
    LIST ( expression-list )

expression-list:
    expression
    expression-list , expression
```

### 12.3 Parsing LIST OF type-name

```cpp
// In DIM statement parsing, after consuming "AS":
if (match(TOKEN_LIST)) {
    TypeDescriptor listType = TypeDescriptor::makeObject("LIST");

    if (match(TOKEN_OF)) {
        // Explicit element type
        if (match(TOKEN_INTEGER))      listType.elementType = BaseType::INTEGER;
        else if (match(TOKEN_LONG))    listType.elementType = BaseType::LONG;
        else if (match(TOKEN_SINGLE))  listType.elementType = BaseType::SINGLE;
        else if (match(TOKEN_DOUBLE))  listType.elementType = BaseType::DOUBLE;
        else if (match(TOKEN_STRING))  listType.elementType = BaseType::STRING;
        else if (match(TOKEN_LIST))    listType.elementType = BaseType::OBJECT;  // nested
        else if (match(TOKEN_HASHMAP)) listType.elementType = BaseType::OBJECT;
        else if (match(TOKEN_ANY))     listType.elementType = BaseType::UNKNOWN;
        else error("Expected type name after LIST OF");
    } else {
        // Bare "LIST" — defaults to LIST OF ANY
        listType.elementType = BaseType::UNKNOWN;
    }
    // ... continue with optional = initialiser
}
```

### 12.4 FOR EACH Extension

The existing `FOR EACH item IN collection` grammar already supports arrays and hashmaps. For lists, the parser recognises the collection variable's type as LIST (via the semantic layer) and the codegen emits the cursor-based traversal pattern instead of the index-based array pattern.

The element type of the list determines the iteration variable's type:

```cpp
// In preAllocateForEachSlots, when collection is a LIST:
if (varSym->typeDesc.isList()) {
    BaseType elemType = varSym->typeDesc.listElementType();
    if (elemType == BaseType::UNKNOWN) {
        // LIST OF ANY — iteration variable is LONG (raw 64-bit)
        forEachVarTypes_[stmt->variable] = BaseType::LONG;
        // Also allocate a type-tag slot for TYPEOF()
        // __foreach_type_<var>
    } else {
        // Typed list — iteration variable matches element type
        forEachVarTypes_[stmt->variable] = elemType;
    }
}
```

---

## 13. Codegen Strategy

### 13.1 List Literal — Static Path

When all elements of `LIST(...)` are compile-time constants:

1. Emit a static `ListHeader` + chain of `ListAtom` structs in the data section.
2. At runtime, call `list_deep_copy_static(static_ptr)` to create a mutable copy.
3. Track the new copy with SAMM.

This avoids N individual `list_append_*` calls for constant lists.

### 13.2 List Literal — Dynamic Path

When any element is a variable or expression:

```
%header =l call $list_create()
call $samm_track_list(l %header)

# For each element — function selected by element's compile-time type:
%val1 =w 42
call $list_append_int(l %header, l %val1)

%val2 =l call $string_new_ascii(l %str_ptr)
call $list_append_string(l %header, l %val2)

# Store header pointer to variable
storel %header, %varaddr
```

### 13.3 Method Calls with Type Override

Method calls on LIST variables follow the existing `emitMethodCall` path, but with an extra step: the codegen checks the list variable's `elementType` and overrides the default runtime function name:

```cpp
// In emitMethodCall, when object type is LIST:
std::string runtimeFunc = method->runtimeFunctionName;  // default: "list_append_int"

BaseType elemType = objectTypeDesc.elementType;  // from the variable's TypeDescriptor
if (methodName == "APPEND" || methodName == "PREPEND") {
    // Override based on element type (for typed lists) or argument type (for ANY)
    BaseType dispatchType = (elemType != BaseType::UNKNOWN) ? elemType : getExpressionType(arg);
    if (isFloat(dispatchType))      runtimeFunc = "list_append_float";
    else if (isString(dispatchType)) runtimeFunc = "list_append_string";
    else if (isList(dispatchType))   runtimeFunc = "list_append_list";
    // else: keep _int default
}
```

### 13.4 FOR EACH over LIST

Pre-allocate slots:
- `__foreach_cursor_<var>` — pointer to current `ListAtom` (l)
- `__foreach_slot_<var>` — element value (l or d depending on element type)
- `__foreach_type_<var>` — current element type tag (w) — **only for LIST OF ANY**
- `__foreach_idx_<var>` — 1-based index counter (w), if index variable present

Loop structure for **typed list** (e.g., LIST OF INTEGER):
```
@foreach_init:
    %cursor =l call $list_iter_begin(l %header)
    storel %cursor, %cursor_addr
    storew 1, %idx_addr

@foreach_test:
    %cur =l loadl %cursor_addr
    jnz %cur, @foreach_body, @foreach_end

@foreach_body:
    # Direct field access — no type dispatch needed
    %val =l call $list_iter_value_int(l %cur)
    storel %val, %slot_addr

    <user body>

    %next =l call $list_iter_next(l %cur)
    storel %next, %cursor_addr
    %i =w loadw %idx_addr
    %i2 =w add %i, 1
    storew %i2, %idx_addr
    jmp @foreach_test

@foreach_end:
```

Loop structure for **LIST OF ANY** adds a type-tag load:
```
@foreach_body:
    %type =w call $list_iter_type(l %cur)
    storew %type, %type_addr                    # for TYPEOF()
    %val =l call $list_iter_value_int(l %cur)   # raw 64-bit
    storel %val, %slot_addr

    <user body — uses TYPEOF() to dispatch>
    ...
```

---

## 14. Semantic Validation

### 14.1 APPEND/PREPEND/INSERT Type Checking

```cpp
void SemanticAnalyzer::validateListAppend(const MethodCallExpression& expr) {
    TypeDescriptor listType = getVariableType(expr.objectName);
    if (!listType.isList()) return;  // not our problem

    BaseType elemType = listType.listElementType();
    if (elemType == BaseType::UNKNOWN) return;  // LIST OF ANY — anything goes

    BaseType argType = inferExpressionType(expr.arguments[0]);

    // Check compatibility
    if (elemType == BaseType::INTEGER || elemType == BaseType::LONG) {
        if (!isIntegerType(argType)) {
            error("Cannot append " + typeName(argType) + " to LIST OF " + typeName(elemType));
        }
    } else if (elemType == BaseType::DOUBLE || elemType == BaseType::SINGLE) {
        if (!isNumericType(argType)) {
            error("Cannot append " + typeName(argType) + " to LIST OF " + typeName(elemType));
        }
        // Integer → double widening is OK
    } else if (elemType == BaseType::STRING) {
        if (!isStringType(argType)) {
            error("Cannot append " + typeName(argType) + " to LIST OF STRING");
        }
    }
    // ... etc for OBJECT types
}
```

### 14.2 Assignment Compatibility

```cpp
void SemanticAnalyzer::validateListAssignment(const TypeDescriptor& target, const TypeDescriptor& source) {
    if (!target.isList() || !source.isList()) return;

    BaseType targetElem = target.listElementType();
    BaseType sourceElem = source.listElementType();

    if (targetElem == BaseType::UNKNOWN) {
        // LIST OF ANY accepts anything
        return;
    }

    if (sourceElem == BaseType::UNKNOWN) {
        // Assigning LIST OF ANY to a typed list — warn
        warning("Assigning LIST OF ANY to LIST OF " + typeName(targetElem) +
                "; elements may not match at runtime");
        return;
    }

    if (targetElem != sourceElem) {
        // Allow numeric widening (INTEGER → DOUBLE)
        if (isNumericType(targetElem) && isNumericType(sourceElem) &&
            numericWidth(targetElem) >= numericWidth(sourceElem)) {
            return;  // OK: widening
        }
        error("Cannot assign LIST OF " + typeName(sourceElem) +
              " to LIST OF " + typeName(targetElem));
    }
}
```

### 14.3 LIST() Literal Type Inference

```cpp
TypeDescriptor SemanticAnalyzer::inferListLiteralType(const ListExpression& expr) {
    if (expr.initializers.empty()) {
        return TypeDescriptor::makeList(BaseType::UNKNOWN);  // LIST OF ANY
    }

    BaseType firstType = inferExpressionBaseType(expr.initializers[0]);
    bool allSame = true;
    bool allNumeric = isNumericType(firstType);

    for (size_t i = 1; i < expr.initializers.size(); i++) {
        BaseType t = inferExpressionBaseType(expr.initializers[i]);
        if (t != firstType) allSame = false;
        if (!isNumericType(t)) allNumeric = false;
    }

    if (allSame) {
        return TypeDescriptor::makeList(firstType);           // e.g. LIST OF INTEGER
    } else if (allNumeric) {
        return TypeDescriptor::makeList(BaseType::DOUBLE);    // widen to DOUBLE
    } else {
        return TypeDescriptor::makeList(BaseType::UNKNOWN);   // LIST OF ANY
    }
}
```

---

## 15. Implementation Phases

### Phase 1: Runtime Foundation

- [ ] Create `list_ops.c` / `list_ops.h` with the C runtime functions
- [ ] Implement `ListHeader` and `ListAtom` structures
- [ ] Implement `list_create`, `list_create_typed`, `list_free`
- [ ] Implement `list_append_int/float/string/list`, `list_prepend_*`
- [ ] Implement `list_length`, `list_empty`, `list_head_*`, `list_get_*`
- [ ] Implement `list_shift_*`, `list_pop_*`, `list_remove`, `list_clear`
- [ ] Implement iteration helpers: `list_iter_begin/next/type/value_*`
- [ ] Wire up SAMM: `list_create` calls `samm_track_list`, `list_free` calls `samm_untrack`
- [ ] Update `cleanup_batch` in `samm_core.c` to call `list_free` instead of raw `free`
- [ ] Add `list_ops.c` to the runtime build list in `fbc_qbe.cpp`
- [ ] Write standalone C test to validate runtime correctness

### Phase 2: Type System & Parsing

- [ ] Add `TypeDescriptor::makeList()` factory method
- [ ] Add `isList()`, `isTypedList()`, `listElementType()` predicates
- [ ] Add `registerListType()` to `RuntimeObjectRegistry`
- [ ] Call `registerListType()` from `RuntimeObjectRegistry::initialize()`
- [ ] Add `LIST` keyword to the lexer
- [ ] Add `OF` keyword (context-sensitive, only after `LIST`)
- [ ] Parse `DIM x AS LIST OF INTEGER` etc.
- [ ] Parse `LIST(...)` constructor expressions with type inference
- [ ] Semantic validation: element type checking for APPEND, PREPEND, INSERT
- [ ] Semantic validation: assignment compatibility between list types
- [ ] Semantic validation: LIST literal type inference

### Phase 3: Codegen — Creation & Methods

- [ ] Emit `list_create()` / `list_create_typed()` for `DIM x AS LIST OF <type>`
- [ ] Emit `LIST(...)` constructor (dynamic path: create + N appends)
- [ ] Emit method calls via `emitMethodCall` with type-aware function override
- [ ] Emit `samm_retain_parent()` for list returns from functions
- [ ] Handle `ERASE` for list variables (emit `list_free` + `samm_untrack`)
- [ ] Support `FUNCTION ... AS LIST OF <type>` return type declarations

### Phase 4: FOR EACH Support

- [ ] Detect LIST type in `preAllocateForEachSlots`
- [ ] Set iteration variable type from list's element type
- [ ] Emit cursor-based loop for typed lists (direct value access)
- [ ] Emit cursor-based loop for LIST OF ANY (with type-tag slot)
- [ ] Support `TYPEOF()` reading the type-tag slot in LIST OF ANY loops
- [ ] Support index variable (second variable in `FOR EACH x, i IN list`)

### Phase 5: Operations & Polish

- [ ] Implement `list_copy`, `list_reverse`, `list_rest`
- [ ] Implement `list_contains_int/float/string`, `list_indexof_*`
- [ ] Implement `list_join`
- [ ] Implement `list_extend` (with element type compatibility check)
- [ ] Static list path (data section for constant lists)
- [ ] Freelist allocator for headers and atoms
- [ ] Comprehensive BASIC test suite

### Phase 6: Future / Nice-to-Have

- [ ] `CONST` / manifest lists (read-only, no deep copy needed)
- [ ] Subscript access: `myList(3)` as syntax sugar for `.GET(3)`
- [ ] `list_sort` with configurable comparator
- [ ] `list_map` / `list_filter` (requires lambda or function-pointer support)
- [ ] `LIST OF <UDT>` — user-defined types as elements
- [ ] Deep nested types: `LIST OF LIST OF STRING`
- [ ] List comprehensions: `LIST(x * 2 FOR x IN source WHERE x > 0)`
- [ ] Contiguous backing array optimisation for `LIST OF INTEGER` / `LIST OF DOUBLE`

---

## 16. Comparison with NBCPL

| Aspect | NBCPL | FasterBASIC |
|--------|-------|-------------|
| **Syntax** | `LIST(1,2,3)`, `HD(L)`, `TL(L)` | `LIST(1,2,3)`, `L.HEAD`, `L.REST` |
| **Mutation** | `APND(L, val)` | `L.APPEND val` |
| **Iteration** | `FOREACH item IN L DO $(...)$)` | `FOR EACH item IN L ... NEXT` |
| **Type inspection** | `TYPEOF(node)`, `AS_INT(node)` | `TYPEOF(item)`, implicit in typed lists |
| **Memory** | SAMM + explicit `FREELIST` | SAMM + optional `ERASE` |
| **Manifest lists** | `MANIFESTLIST(...)` | Phase 6: `CONST LIST(...)` |
| **Type system** | Bitwise `POINTER_TO \| LIST \| INT` | `BaseType::OBJECT`, objectTypeName="LIST", **elementType=BaseType::INTEGER** |
| **Element type tracking** | Inferred, bitwise flags | Explicit (`LIST OF INTEGER`) + inferred from literals |
| **Compile-time checking** | Type flags checked at codegen | Full semantic validation before codegen |
| **Codegen dispatch** | Register-level type check | Compile-time: typed lists = direct call, ANY = argument-type dispatch |
| **FOR EACH typing** | Runtime `TYPEOF()` always | Typed lists: static variable type. ANY: TYPEOF() available |
| **Data structures** | Same `ListHeader`/`ListAtom` | Same `ListHeader`/`ListAtom` |
| **Atom sizes** | 24 bytes | 24 bytes |
| **Header size** | 32 bytes | 32 bytes |
| **Freelist** | Thread-local freelists | Same design planned |

The runtime data structures are byte-compatible. The key differences are:

1. **Type system depth:** NBCPL uses bitwise type flags (`POINTER_TO | LIST | INT`). FasterBASIC carries the element type as a `BaseType` field on `TypeDescriptor`, enabling the semantic analyzer to validate operations before codegen ever runs.

2. **Compile-time vs. runtime dispatch:** NBCPL relies more on runtime type tags for dispatch. FasterBASIC's typed lists (`LIST OF INTEGER`) eliminate all runtime type dispatch — the codegen picks the right function at compile time and the FOR EACH variable has a known static type. Only `LIST OF ANY` needs runtime type inspection.

3. **User-facing syntax:** NBCPL uses BCPL-flavoured functional style (`HD`, `TL`, `FOREACH ... DO`). FasterBASIC uses method calls and `FOR EACH ... NEXT` with BASIC-native type declarations.

---

## 17. Memory Layout Examples

### Empty LIST OF INTEGER

```
Variable nums ──→ ListHeader (32 bytes)
                  ┌────────────────────────────────────┐
                  │ type=0  flags=0x0100  length=0     │
                  │ head=NULL             tail=NULL     │
                  └────────────────────────────────────┘
                         flags encodes LIST_FLAG_ELEM_INT

Total: 32 bytes
```

### LIST OF INTEGER = LIST(10, 20, 30)

```
Variable nums ──→ ListHeader
                  ┌────────────────────────────────────┐
                  │ type=0  flags=0x0100  length=3     │
                  │ head=──────→          tail=───────→│
                  └────────┼──────────────────────────┼┘
                           │                          │
                           ▼                          │
                  ListAtom (24 bytes)                  │
                  ┌────────────────────┐               │
                  │ type=1 (INT)       │               │
                  │ value.int_value=10 │               │
                  │ next=──────→       │               │
                  └────────┼───────────┘               │
                           │                           │
                           ▼                           │
                  ListAtom (24 bytes)                  │
                  ┌────────────────────┐               │
                  │ type=1 (INT)       │               │
                  │ value.int_value=20 │               │
                  │ next=──────→       │               │
                  └────────┼───────────┘               │
                           │                           │
                           ▼                           ▼
                  ListAtom (24 bytes)    ◄──────────────
                  ┌────────────────────┐
                  │ type=1 (INT)       │
                  │ value.int_value=30 │
                  │ next=NULL          │
                  └────────────────────┘

All atoms have type=1 (ATOM_INT) — homogeneous.
Total: 32 + 3×24 = 104 bytes
```

### LIST OF ANY = LIST(42, "hello", 3.14)

```
Variable mixed ──→ ListHeader
                   ┌──────────────────────────────────────┐
                   │ type=0  flags=0x0000  length=3       │
                   │ head=──────→            tail=───────→ │
                   └────────┼─────────────────────────────┼┘
                            │                              │
                            ▼                              │
                   ListAtom (24 bytes)                     │
                   ┌──────────────────────┐                │
                   │ type=1 (INT)         │                │
                   │ value.int_value=42   │                │
                   │ next=──────→         │                │
                   └────────┼─────────────┘                │
                            │                              │
                            ▼                              │
                   ListAtom (24 bytes)                     │
                   ┌──────────────────────┐                │
                   │ type=3 (STRING)      │                │
                   │ value.ptr_value=→SD  │ (StringDescriptor for "hello")
                   │ next=──────→         │                │
                   └────────┼─────────────┘                │
                            │                              │
                            ▼                              ▼
                   ListAtom (24 bytes)    ◄─────────────────
                   ┌──────────────────────┐
                   │ type=2 (FLOAT)       │
                   │ value.float_value=3.14│
                   │ next=NULL            │
                   └──────────────────────┘

Each atom has a DIFFERENT type tag — heterogeneous.
FOR EACH needs TYPEOF() to dispatch.
Total: 32 + 3×24 = 104 bytes (plus StringDescriptor for "hello")
```

---

## 18. Open Questions

1. **Should `.GET(n)` support negative indices?** Python-style `L.GET(-1)` for last element. Recommendation: yes, in Phase 5.

2. **Should APPEND return the list for chaining?** `L.APPEND(1).APPEND(2)`. Recommendation: not in Phase 1 — keep it as a void statement.

3. **Should we support `L(n)` subscript syntax?** It conflicts with array/hashmap in the parser. Recommendation: defer to Phase 6, use `enableSubscript` with INTEGER key type and element-type return.

4. **Do we need doubly-linked atoms?** Singly-linked is simpler and sufficient. POP is O(n) but rarely called in tight loops. Recommendation: start singly-linked, add `prev` only if profiling demands it.

5. **Should string elements be retained or copied?** When `list_append_string` is called, it should `string_retain()` the descriptor (shared ownership). When the atom is freed, `string_release()` drops the list's claim. Same as string arrays.

6. **Should `LIST OF DOUBLE` auto-widen `LIST OF INTEGER` on assignment?** E.g., `DIM d AS LIST OF DOUBLE = intList`. Recommendation: yes, with element-by-element widening in `list_copy` or `list_extend`.

7. **Should `LIST OF LIST` carry the inner list's element type?** I.e., `LIST OF LIST OF INTEGER`. The current `elementType` field is a single `BaseType` — it can't express nested parameterisation. Recommendation: defer deep nesting to Phase 6. For now, `LIST OF LIST` means "a list whose elements are lists of unknown element type."

---

## 19. Summary

Lists in FasterBASIC will be:

- **Typed**: `LIST OF INTEGER`, `LIST OF STRING`, `LIST OF ANY` — the compiler knows what goes in and enforces it
- **Easy to use**: `DIM L AS LIST OF INTEGER`, `L.APPEND x`, `FOR EACH item IN L`
- **Efficient**: O(1) append/prepend, compile-time type dispatch (no runtime overhead for typed lists), freelist allocation, SAMM-managed
- **Flexible**: `LIST OF ANY` allows heterogeneous collections with runtime `TYPEOF()` inspection
- **Consistent**: Same method-call syntax and SAMM patterns as HASHMAP and STRING
- **Compatible**: Same underlying `ListHeader`/`ListAtom` structures as NBCPL, byte-compatible at the runtime level
- **Safe**: Compile-time element type checking prevents type mismatches before the program runs

The type system integration is the key differentiator from NBCPL: where NBCPL uses bitwise type flags and runtime dispatch, FasterBASIC carries the element type through `TypeDescriptor.elementType` and resolves all dispatch at compile time for typed lists. `LIST OF ANY` preserves full NBCPL-style flexibility for programs that need heterogeneous collections.