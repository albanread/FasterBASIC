# FasterBASIC CLASS & OBJECT — Design Decisions & Rationale

**Version:** 1.0 Draft  
**Date:** July 2025  
**Companion to:** `CLASS_OBJECT_DESIGN.md`, `CLASS_IMPLEMENTATION.md`, `CLASS_EXAMPLES.md`

---

## Purpose of This Document

Every design has trade-offs. This document captures *why* each decision was
made so that future contributors understand the reasoning and can make
informed changes if requirements evolve.

---

## Decision 1: CLASS as a New Keyword (Not Extending TYPE)

**Choice:** Introduce `CLASS...END CLASS` as a distinct declaration, separate
from `TYPE...END TYPE`.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Add methods directly to TYPE | TYPE is a value type (stack-allocated, copyable, SIMD-friendly). Adding vtables, heap allocation, and method dispatch would break the mental model and lose SIMD optimisation for existing UDTs. |
| Use TYPE with a `METHODS` section | Conflates two different allocation semantics (value vs. reference) under one keyword. Confusing for beginners. |
| Use OBJECT keyword instead of CLASS | CLASS is the universally understood term across VB, Java, Python, C#, FreeBASIC, PureBasic, etc. OBJECT is better as the name for the concept ("an object is an instance of a class"). |

**Rationale:**

- TYPE remains a lightweight value type — no vtable overhead, no heap allocation,
  SIMD-friendly. Perfect for `Point`, `Color`, `Vec2D`.
- CLASS is explicitly a reference type — heap-allocated, identity-bearing, with
  vtable dispatch. Perfect for `Player`, `TaskList`, `Logger`.
- Two keywords for two semantically different things. No ambiguity, no surprises.
- Programs can freely mix TYPE and CLASS (a CLASS can have TYPE fields and vice
  versa), giving users the best of both worlds.

---

## Decision 2: ME (Not THIS, SELF, or Implicit)

**Choice:** Use `ME` as the keyword to reference the current object instance.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `THIS` | C++/Java convention. Feels alien in BASIC. |
| `SELF` | Python/Swift convention. Reasonable but less BASIC-ish. |
| Implicit (no prefix needed) | Creates ambiguity between field names and local variables/parameters. E.g., if a parameter is named `Name` and a field is named `Name`, which one does bare `Name` refer to? |
| `MY` | Reads well (`MY.Name`) but uncommon in existing BASIC dialects. |

**Rationale:**

- `ME` is the established convention in Visual Basic and VBA, which are the
  closest mainstream BASIC dialects with OOP support.
- `ME` reads naturally in English: `ME.Name = n`, `ME.Score = ME.Score + 1`.
- Requiring `ME.` for field access inside methods eliminates all ambiguity
  between fields, parameters, and local variables — no implicit scoping rules
  needed.
- Short (2 characters) and easy to type.

---

## Decision 3: Single Inheritance Only (No Interfaces, No Mixins)

**Choice:** A class can `EXTENDS` at most one parent class. No interfaces,
no multiple inheritance, no mixins.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Multiple inheritance | Dramatically complicates vtable layout (diamond problem, ambiguous fields). C++ experts regularly advise against it. |
| Interfaces / IMPLEMENTS | Adds a second dispatch mechanism (interface tables). Significant implementation complexity. Can be layered on later. |
| Mixins / Traits | Requires a composition model for method resolution order. Complex and unfamiliar to BASIC programmers. |

**Rationale:**

- Single inheritance covers the vast majority of real-world OOP use cases:
  Shape → Circle/Square, Entity → Player/NPC, Plugin → ConcretePlugin.
- The vtable layout is trivially simple: parent methods first, then child
  methods. No ambiguity, no diamond problem.
- For cases where "multiple types of behaviour" are needed, composition
  works well: give a class a field of another class type and delegate.
- Interfaces can be added in a future version without breaking any programs
  written with single inheritance today.

---

## Decision 4: All Methods Are Virtual (No VIRTUAL/OVERRIDE Keywords)

**Choice:** Every method participates in vtable dispatch automatically.
No `VIRTUAL`, `OVERRIDE`, or `ABSTRACT` keywords.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Explicit `VIRTUAL` / non-virtual default | Adds ceremony. In BASIC's target audience, the distinction between virtual and non-virtual methods is a source of confusion, not clarity. |
| Require `OVERRIDE` keyword | Extra boilerplate for a common operation. Also requires the user to understand the concept of "overriding" vs "defining" — a distinction beginners struggle with. |
| `ABSTRACT` methods | Useful but adds complexity (classes that can't be instantiated, pure virtual errors). Defer to phase 2 if demand appears. |

**Rationale:**

- Simplicity. When you define a method with the same name as a parent method,
  it overrides it. Period. No keywords to remember, no "forgot to say OVERRIDE"
  bugs.
- Every method goes through the vtable, so polymorphism always works. This
  matches the behaviour of Java, Python, and Ruby — languages known for being
  approachable.
- The performance cost is one extra indirection per call. For a BASIC dialect
  targeting application/game scripting (not HPC), this is negligible.
- For hot paths where devirtualisation matters, the compiler can optimise
  statically-known types to direct calls (phase 4).

---

## Decision 5: EXTENDS (Not INHERITS or SUBCLASS)

**Choice:** Use `EXTENDS` as the inheritance keyword.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `INHERITS` | Used by VB.NET. Slightly longer and less intuitive — "inherits" focuses on what you get, not the relationship. |
| `SUBCLASS OF` | Too verbose for a header line. |
| `BASED ON` | Unusual, no precedent. |
| `: ParentClass` (colon syntax) | Too terse, un-BASIC-like. |

**Rationale:**

- `EXTENDS` is used by Java, TypeScript, Kotlin, and FreeBASIC (proposed).
  It's the most widely recognised keyword for single inheritance.
- It reads naturally: "CLASS Dog EXTENDS Animal" — "a Dog extends the
  concept of an Animal by adding more features."
- One word, clear meaning, no ambiguity.

---

## Decision 6: CONSTRUCTOR / END CONSTRUCTOR (Not SUB New)

**Choice:** Use a dedicated `CONSTRUCTOR...END CONSTRUCTOR` block inside
the class body.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `SUB New(...)` | Overloading SUB for a special role is confusing. Is `New` just a sub name? Can I call other subs `New`? What about `FUNCTION New`? |
| `SUB Init(...)` | Same issues. Plus, `Init` doesn't signal "this runs automatically on NEW". |
| No constructor (use a factory function) | Workable but forces all initialisation to be external. Objects can be created in an invalid state. |
| Implicit constructor from field defaults | Too limited. Can't take parameters. |

**Rationale:**

- `CONSTRUCTOR` is self-documenting. A beginner reading a CLASS block
  immediately knows "this code runs when the object is created."
- It's visually distinct from METHOD, making the class body easy to scan.
- One constructor per class (no overloading). Use optional parameters or
  factory functions if you need multiple creation patterns. This keeps the
  mental model simple.
- Maps directly to a QBE function (`ClassName__CONSTRUCTOR`) with `ME` as
  the first parameter — clean, no special cases in codegen.

---

## Decision 7: METHOD (Not SUB/FUNCTION Inside CLASS)

**Choice:** Use `METHOD...END METHOD` for class methods, not `SUB`/`FUNCTION`.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `SUB` / `FUNCTION` inside CLASS | Ambiguous — does `SUB Foo` inside a CLASS mean a method or a nested subroutine? If it's a method, why does it look identical to a standalone SUB? |
| `DEF METHOD` | Unnecessary extra keyword. |
| `PROC` / `PROCEDURE` | Not a BASIC tradition. |

**Rationale:**

- `METHOD` explicitly signals "this belongs to the class and operates on ME."
- `SUB` and `FUNCTION` remain for standalone procedures, maintaining their
  existing meaning with zero ambiguity.
- Return values use `AS ReturnType` on the METHOD line (like FUNCTION does),
  so the distinction between "method that returns" and "method that doesn't"
  is uniform:
  ```
  METHOD Speak()                    ' no return value
  METHOD Area() AS DOUBLE           ' returns a DOUBLE
  ```
- Consistent `END METHOD` closing (parallel to `END SUB`, `END FUNCTION`,
  `END TYPE`, `END CLASS`).

---

## Decision 8: No Visibility Modifiers (Everything Is PUBLIC)

**Choice:** All fields and methods are public. No `PRIVATE`, `PROTECTED`,
or `PUBLIC` keywords in phase 1.

**Alternatives Considered:**

| Alternative | Why Rejected (for now) |
|-------------|----------------------|
| `PRIVATE` fields | Useful for encapsulation, but adds parsing complexity and requires getter/setter patterns that increase boilerplate. Most BASIC dialects don't enforce access control. |
| `PROTECTED` methods | Only meaningful with deep inheritance. Premature for a first version. |
| Convention-based (`_` prefix) | Zero implementation cost. Adequate for the initial user base. |

**Rationale:**

- FasterBASIC's target audience is writing programs of hundreds to low thousands
  of lines. At this scale, encapsulation via convention (`_` prefix for internal
  fields) is sufficient.
- Adding PRIVATE later is backward-compatible: existing all-public programs
  remain valid. Nothing breaks.
- Keeps the implementation simpler: no access-checking pass in the semantic
  analyser, no "field is private" error messages to design.
- If real demand appears (e.g., library authors distributing compiled classes),
  PRIVATE can be added as a field/method modifier in a future version.

---

## Decision 9: Heap Allocation via NEW (Not Stack or Mixed)

**Choice:** Objects are always heap-allocated. `NEW` returns a pointer.
Variables hold pointers (reference semantics).

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Stack-allocated objects (like TYPE) | Incompatible with polymorphism — a `Dog` stored in an `Animal`-sized stack slot would be sliced. |
| Mixed (sometimes stack, sometimes heap) | Complex ownership semantics. When does a copy happen? When does it not? Confusing. |
| Mandatory `NEW` even for TYPE | Breaks existing programs. TYPE is fine as-is. |

**Rationale:**

- Reference semantics are essential for polymorphism: an `Animal` variable must
  be able to hold a `Dog` (which is larger) without slicing.
- Heap allocation is what users of Python, Java, C#, and VB expect for objects.
  No surprises.
- Assignment copies the pointer, not the object. This is consistent with how
  STRING and HASHMAP already work in FasterBASIC.
- Stack-allocated value types are already handled perfectly by TYPE. No need
  to duplicate that capability under CLASS.

---

## Decision 10: NOTHING Instead of NULL/NIL

**Choice:** Use `NOTHING` as the null object reference constant.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `NULL` | C/C++ convention. Works but feels technical, not BASIC-ish. |
| `NIL` | Lua/Ruby convention. Less recognisable to VB users. |
| `EMPTY` | Already used in some BASICs for empty strings/variants. Ambiguous. |
| `0` (bare zero) | Too easy to confuse with integer 0. No type safety. |

**Rationale:**

- `NOTHING` is the established VB/VBA convention. FasterBASIC users who have
  touched VB will recognise it instantly.
- It reads naturally: `IF player IS NOTHING THEN ...`, `dog = NOTHING`.
- It's unambiguous: NOTHING is always an object reference, never confused with
  an empty string, zero integer, or false boolean.
- Implementation is trivial: NOTHING is the integer constant 0 (null pointer).

---

## Decision 11: IS Operator for Type Checking (Not TYPEOF or INSTANCEOF)

**Choice:** Use `obj IS ClassName` syntax for runtime type checks.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `TYPEOF(obj) = "ClassName"` | String-based comparison is error-prone and slow. |
| `INSTANCEOF(obj, ClassName)` | Function-call syntax is verbose. |
| `obj IS A ClassName` | Extra word with no added clarity. |

**Rationale:**

- `IS` is already a keyword in many BASICs (VB uses `obj Is Nothing`).
- Dual-purpose: works for both type checks (`dog IS Animal`) and null checks
  (`dog IS NOTHING`).
- Reads as natural English: "if the dog is an Animal then..."
- Implementation: compare class_id fields, walking the parent chain. Fast
  (1-3 pointer hops for typical hierarchies).

---

## Decision 12: VTable-Based Dispatch (Not Message Passing or Hash Lookup)

**Choice:** Use C++-style vtables for method dispatch.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Hash table lookup by method name (Smalltalk/ObjC-style) | Much slower (hash + string compare per call). Overkill for a statically-typed language. |
| Inline caching (V8/SpiderMonkey-style) | Complex to implement. Appropriate for dynamically-typed languages, not needed here. |
| Fat pointers (Rust trait objects) | Complex memory model. Unfamiliar. |

**Rationale:**

- FasterBASIC is statically typed. Method names are resolved at compile time
  to vtable slot indices. This gives O(1) dispatch: 3 loads + 1 indirect call.
- Identical to how C++, Java, and C# implement virtual dispatch. Well-understood,
  well-optimised by hardware (branch predictors handle indirect calls well).
- The vtable is a simple QBE `data` section with function pointers. No runtime
  data structures to build or manage.
- Devirtualisation (direct calls when the type is statically known) is a
  straightforward optimisation that can be added later.

---

## Decision 13: Implicit Default Constructor (Not Always Required)

**Choice:** If a class has no CONSTRUCTOR declared, `NEW ClassName()` is
valid and produces an object with all-zero fields.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Require every class to declare a CONSTRUCTOR | Too much boilerplate for simple classes. Forces the user to write an empty constructor. |
| Generate a constructor with one parameter per field | Fragile — adding a field breaks all `NEW` call sites. Also, field order shouldn't matter. |

**Rationale:**

- Zero-initialisation via `calloc` gives every field a sane default: integers
  are 0, floats are 0.0, strings are empty, object references are NOTHING.
- A class with no constructor is still useful — the user can set fields after
  creation:
  ```basic
  DIM p AS Point2D = NEW Point2D()
  p.X = 10
  p.Y = 20
  ```
- If the parent has a constructor with required arguments and the child has no
  constructor, it's a compile error. This catches the dangerous case while
  allowing the convenient case.

---

## Decision 14: SUPER() Must Be First Statement in CONSTRUCTOR

**Choice:** If a derived class's CONSTRUCTOR calls SUPER(), it must be the
first executable statement.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| Allow SUPER() anywhere in the constructor | Parent fields might be accessed before being initialised, leading to subtle bugs. |
| Implicit SUPER() at the start (always) | Can't pass computed arguments to the parent constructor. |
| No SUPER() — parent fields auto-initialise to zero | Violates the parent's invariants. If the parent constructor validates input, skipping it defeats the purpose. |

**Rationale:**

- Matches Java's rule ("super() must be the first statement"). Well-understood,
  prevents accessing uninitialised parent state.
- If the parent has no constructor or a zero-argument constructor and the child
  doesn't call SUPER(), the compiler inserts an implicit SUPER() at the top.
  This is safe because a zero-argument constructor doesn't need input from the
  child.
- The constraint is simple to implement (check first statement in AST) and
  simple to explain in error messages.

---

## Decision 15: No Operator Overloading (Phase 1)

**Choice:** Classes cannot define custom behaviour for `+`, `-`, `=`, `<>`,
`PRINT`, etc.

**Rationale:**

- Operator overloading is a convenience feature, not a structural one. The core
  goal — enabling clean program structure — is fully served by methods.
- Implicit operator calls make code harder to reason about ("what does `a + b`
  do if `a` is a Matrix?"). This is especially problematic for beginners.
- The one exception is `ToString()` integration with PRINT, which is planned
  for phase 4 as a specific, well-defined convention rather than general
  operator overloading.
- If needed later, operator overloading can be added as special METHOD names
  (e.g., `METHOD OPERATOR_ADD(other AS MyClass) AS MyClass`) without changing
  the core design.

---

## Decision 16: Manual Memory Management (Phase 1), Ref-Counting Later

**Choice:** Phase 1 uses explicit `DELETE` or leak-on-exit. Phase 2 can add
transparent reference counting.

**Alternatives Considered:**

| Alternative | Why Rejected (for phase 1) |
|-------------|--------------------------|
| Reference counting from day one | Significant implementation complexity (cycle detection, weak references, thread safety). Delays the initial release. |
| Tracing garbage collector | Even more complex. Requires stop-the-world pauses or concurrent GC. Completely out of scope for a BASIC compiler. |
| Arena allocator | Good for batch allocation but doesn't solve individual object lifetime. |

**Rationale:**

- Most FasterBASIC programs are short-lived scripts or games with a main loop.
  Leaking objects until program exit is acceptable for the initial version.
- `DELETE` provides an escape hatch for long-running programs or tight loops
  that allocate many objects.
- Reference counting can be added transparently later by:
  1. Adding a refcount field to the object header (after class_id).
  2. Incrementing on assignment, decrementing on variable going out of scope.
  3. Calling the destructor and freeing when refcount hits zero.
  This change is invisible to user code — programs written for phase 1 continue
  to work without modification.

---

## Decision 17: DESTRUCTOR Is Optional (Not Required)

**Choice:** Classes may optionally define a DESTRUCTOR that runs when DELETE
is called.

**Rationale:**

- Most classes don't need cleanup logic. Requiring a destructor would be pure
  boilerplate.
- When cleanup IS needed (closing files, releasing resources), the destructor
  provides a clean hook.
- Destructors chain automatically: child destructor runs first, then parent
  destructor. The compiler inserts the parent destructor call at the end of
  the child's destructor body. The user never needs to call SUPER in a
  destructor.

---

## Decision 18: Name Mangling Convention

**Choice:** `ClassName__MethodName` with double underscores.

**Alternatives Considered:**

| Alternative | Why Rejected |
|-------------|-------------|
| `ClassName_MethodName` (single underscore) | Ambiguous — could collide with user-defined SUB names containing underscores. |
| `ClassName.MethodName` (dot) | Dots are not valid in QBE identifiers. |
| `ClassName$MethodName` (dollar) | `$` is the QBE global prefix. Confusing. |

**Rationale:**

- Double underscore is a common convention (C++ name mangling uses similar
  patterns) and is extremely unlikely to collide with user-defined names.
- Produces readable QBE IL:
  ```
  $Dog__Speak
  $Dog__CONSTRUCTOR
  $Animal__Describe
  $vtable_Dog
  ```
- Easy to parse back to class + method name for error messages and debugging.

---

## Summary: Design Philosophy

The CLASS extension follows three overarching principles:

1. **Familiar to BASIC programmers.** Every keyword, every syntax pattern,
   every convention was chosen to feel natural to someone who already knows
   FasterBASIC's TYPE, SUB, FUNCTION, and HASHMAP features.

2. **Simple enough to learn in an afternoon.** A user who reads one example
   program should be able to write their own CLASS with fields, a constructor,
   and a couple of methods. Inheritance and polymorphism are one small step
   beyond that.

3. **Extensible without breaking.** Every feature deferred (PRIVATE, interfaces,
   operator overloading, ref-counting) can be added later without changing the
   meaning of any program written today. The initial design deliberately leaves
   room for growth.