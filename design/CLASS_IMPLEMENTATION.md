# FasterBASIC CLASS & OBJECT — Implementation Architecture

**Version:** 1.1  
**Date:** July 2025  
**Status:** In Progress — Core Implementation Complete  
**Companion to:** `CLASS_OBJECT_DESIGN.md` (language specification)

---

## Table of Contents

1. [Memory Model](#1-memory-model)
2. [VTable Layout & Method Dispatch](#2-vtable-layout--method-dispatch)
3. [Inheritance & Field Layout](#3-inheritance--field-layout)
4. [QBE IL Lowering](#4-qbe-il-lowering)
5. [Runtime Library Additions](#5-runtime-library-additions)
6. [Compiler Pipeline Changes](#6-compiler-pipeline-changes)
7. [Type System Integration](#7-type-system-integration)
8. [Constructor & Destructor Mechanics](#8-constructor--destructor-mechanics)
9. [SUPER Dispatch](#9-super-dispatch)
10. [IS Type-Check Operator](#10-is-type-check-operator)
11. [NOTHING & Null Safety](#11-nothing--null-safety)
12. [Worked Example: Full QBE Output](#12-worked-example-full-qbe-output)
13. [Phase Plan](#13-phase-plan)

---

## 1. Memory Model

### 1.1 Object Layout

Every object instance is a contiguous heap allocation with the following layout:

```
Offset  Size   Content
──────  ────   ───────────────────────────
0       8      vtable pointer (ptr to class vtable data)
8       8      class_id (int64, unique per class — used by IS)
16      ...    fields (inherited fields first, then own fields)
```

**Why class_id as a field, not in the vtable?**  
Having class_id directly in the object header makes `IS` checks a single
load + compare without touching the vtable cache line.  The vtable already
holds the class_id too (for walking the inheritance chain), but the object
copy enables the fast-path check.

### 1.2 Object Pointer Semantics

Object variables hold **pointers** (QBE type `l`, 64-bit).  This is
identical to how HASHMAP and STRING descriptors work today:

```
DIM dog AS Dog          →  storel 0, %var_dog   (NOTHING = null = 0)
dog = NEW Dog(...)      →  %ptr =l call $Dog__new(...)
                           storel %ptr, %var_dog
dog.Speak()             →  %obj =l loadl %var_dog
                           ... vtable dispatch ...
```

Assignment copies the pointer, not the object:

```basic
DIM a AS Dog = NEW Dog("Rex", "Lab")
DIM b AS Dog = a       ' b and a point to the SAME object
b.Name = "Max"         ' a.Name is also "Max" now
```

### 1.3 Allocation & Deallocation

| Operation | Implementation |
|-----------|---------------|
| `NEW ClassName(args)` | `calloc(1, sizeof_ClassName)` → fill vtable ptr → fill class_id → call constructor |
| `DELETE obj` | call destructor (if any) → `free(obj)` → set variable to 0 |
| Program exit | all heap is released by OS (phase 1); ref-counting in phase 2 |

We use `calloc` so all fields start at zero/null — integers are 0, strings
are null descriptors, object references are NOTHING.

---

## 2. VTable Layout & Method Dispatch

### 2.1 VTable Structure

Each class has a single, statically-allocated vtable emitted as a QBE `data`
section.  The vtable contains:

```
Offset  Size   Content
──────  ────   ───────────────────────────
0       8      class_id (int64)
8       8      parent_vtable pointer (0 if root class)
16      8      class_name pointer (ptr to string constant, for error messages / IS)
24      8      destructor pointer (0 if none)
32      ...    method pointers, in declaration order (parent methods first)
```

Example for the Animal → Dog hierarchy:

```
data $vtable_Animal = {
    l 1,                        # class_id = 1
    l 0,                        # parent_vtable = null (root)
    l $classname_Animal,        # class name string
    l 0,                        # no destructor
    l $Animal__Speak,           # method[0] = Speak
    l $Animal__Describe         # method[1] = Describe
}

data $vtable_Dog = {
    l 2,                        # class_id = 2
    l $vtable_Animal,           # parent_vtable
    l $classname_Dog,           # class name string
    l 0,                        # no destructor
    l $Dog__Speak,              # method[0] = Speak (overridden)
    l $Animal__Describe,        # method[1] = Describe (inherited)
    l $Dog__Fetch               # method[2] = Fetch (new)
}
```

### 2.2 Method Slot Assignment

Methods are assigned vtable slots during semantic analysis:

1. **Inherited methods** retain their parent's slot index.
2. **Overriding methods** reuse the parent's slot (different function pointer).
3. **New methods** (not in parent) get the next available slot.

This means the slot for `Speak` is always 0 in Animal and all subclasses,
regardless of what other methods are added.

### 2.3 Dispatch Sequence

For a call `obj.Speak()`:

```
# 1. Load object pointer
%obj =l loadl %var_obj

# 2. Null check (optional, enabled by default)
%is_null =w ceql %obj, 0
jnz %is_null, @null_error, @ok

@ok
# 3. Load vtable pointer from object[0]
%vtable =l loadl %obj

# 4. Load method pointer from vtable[HEADER + slot * 8]
#    Speak is slot 0, header is 32 bytes
%method_ptr =l add %vtable, 32       # 32 + 0*8 = 32
%method =l loadl %method_ptr

# 5. Call with ME as first argument
call %method(l %obj)
```

**Cost:** 3 loads + 1 indirect call.  This is the standard vtable dispatch
cost, identical to C++ virtual methods.

### 2.4 Direct Dispatch Optimisation

When the compiler can prove the concrete type (e.g. immediately after `NEW`,
or for variables typed as a leaf class with no subclasses), it can emit a
direct call instead:

```
# Instead of vtable dispatch:
call $Dog__Speak(l %obj)
```

This is a straightforward optimisation the compiler can apply in `cfg_emitter`
or as a later QBE IL pass.  Not required for correctness in phase 1.

---

## 3. Inheritance & Field Layout

### 3.1 Field Ordering

Fields are laid out in order: vtable pointer, class_id, parent fields
(recursively), then own fields.

```
CLASS Animal                    CLASS Dog EXTENDS Animal
  Name AS STRING                  Breed AS STRING
  Sound AS STRING
  Legs AS INTEGER

Animal object:                  Dog object:
  [0]  vtable ptr                 [0]  vtable ptr
  [8]  class_id                   [8]  class_id
  [16] Name (8 bytes, ptr)        [16] Name (8 bytes, inherited)
  [24] Sound (8 bytes, ptr)       [24] Sound (8 bytes, inherited)
  [32] Legs (4 bytes, int)        [32] Legs (4 bytes, inherited)
  [36] padding (4 bytes)          [36] padding (4 bytes)
  Total: 40 bytes                 [40] Breed (8 bytes, own)
                                  Total: 48 bytes
```

### 3.2 Alignment Rules

Fields are aligned to their natural alignment (same as TYPE fields today):

| Type | Size | Alignment |
|------|------|-----------|
| INTEGER | 4 | 4 |
| LONG | 8 | 8 |
| SINGLE | 4 | 4 |
| DOUBLE | 8 | 8 |
| STRING | 8 | 8 (pointer) |
| Object ref | 8 | 8 (pointer) |

Padding is inserted between fields as needed.  The overall object size is
rounded up to 8-byte alignment.

### 3.3 QBE Type Declaration

Each class gets a QBE aggregate type:

```
type :Animal = { l, l, l, l, w, }      # vtable, class_id, Name, Sound, Legs
type :Dog = { l, l, l, l, w, :pad4, l } # + padding + Breed
```

Or using the simpler flat byte-size form:

```
type :Animal = align 8 { 40 }
type :Dog = align 8 { 48 }
```

The flat form is simpler and avoids encoding individual field types in the
QBE type — field accesses use explicit offsets anyway.

### 3.4 Field Offset Calculation

The semantic analyzer computes field offsets during class registration:

```
ClassSymbol {
    name: "Dog"
    classId: 2
    parentClass: &ClassSymbol("Animal")
    objectSize: 48
    fields: [
        { name: "Name",  type: STRING,  offset: 16, inherited: true  },
        { name: "Sound", type: STRING,  offset: 24, inherited: true  },
        { name: "Legs",  type: INTEGER, offset: 32, inherited: true  },
        { name: "Breed", type: STRING,  offset: 40, inherited: false },
    ]
    methods: [
        { name: "Speak",    slot: 0, function: "Dog__Speak",    override: true },
        { name: "Describe", slot: 1, function: "Animal__Describe", override: false },
        { name: "Fetch",    slot: 2, function: "Dog__Fetch",    override: false },
    ]
}
```

---

## 4. QBE IL Lowering

### 4.1 Field Access

Reading `obj.Name`:

```
# obj.Name  (Name is at offset 16, type STRING = pointer = l)
%obj =l loadl %var_obj
%field_addr =l add %obj, 16
%value =l loadl %field_addr
```

Writing `obj.Legs = 4`:

```
# obj.Legs = 4  (Legs is at offset 32, type INTEGER = w)
%obj =l loadl %var_obj
%field_addr =l add %obj, 32
storew 4, %field_addr
```

This is identical to how UDT field access works today — the only difference
is that the base pointer comes from a heap-allocated object rather than a
stack-allocated or global TYPE variable.

### 4.2 Method Call

```basic
result$ = dog.Describe()
```

Lowers to:

```
%obj =l loadl %var_dog
# null check
%is_null =w ceql %obj, 0
jnz %is_null, @null_err_42, @dispatch_42

@dispatch_42
%vtable =l loadl %obj                    # load vtable ptr from obj[0]
%slot_addr =l add %vtable, 40            # method Describe is slot 1: 32 + 1*8 = 40
%method =l loadl %slot_addr              # load function pointer
%result =l call %method(l %obj)          # call with ME = obj
storel %result, %var_result
jmp @continue_42

@null_err_42
# call runtime error handler
call $class_null_method_error(l $str_line_42, l $str_Describe)
hlt
```

### 4.3 NEW Expression

```basic
DIM dog AS Dog = NEW Dog("Rex", "Lab")
```

Lowers to:

```
# 1. Allocate
%size =l copy 48                        # sizeof(Dog)
%obj =l call $calloc(l 1, l %size)

# 2. Install vtable pointer
storel $vtable_Dog, %obj

# 3. Install class_id
%id_addr =l add %obj, 8
storel 2, %id_addr                      # class_id = 2

# 4. Call constructor with args
%arg0 =l call $string_new_utf8(l $str_Rex)
%arg1 =l call $string_new_utf8(l $str_Lab)
call $Dog__CONSTRUCTOR(l %obj, l %arg0, l %arg1)

# 5. Store result
storel %obj, %var_dog
```

### 4.4 DELETE Statement

```basic
DELETE dog
```

Lowers to:

```
%obj =l loadl %var_dog
%is_null =w ceql %obj, 0
jnz %is_null, @del_skip_55, @del_do_55

@del_do_55
# Call destructor if vtable has one (slot at offset 24)
%vtable =l loadl %obj
%dtor =l loadl %vtable_dtor_addr       # vtable + 24
%has_dtor =w cnel %dtor, 0
jnz %has_dtor, @del_dtor_55, @del_free_55

@del_dtor_55
call %dtor(l %obj)

@del_free_55
call $free(l %obj)
storel 0, %var_dog                     # set to NOTHING

@del_skip_55
```

### 4.5 Constructor Function

The constructor is emitted as a regular QBE function.  `ME` is the first
parameter.  The SUPER call (if any) is emitted as a direct call to the
parent constructor:

```basic
CONSTRUCTOR(name AS STRING, breed AS STRING)
    SUPER(name, "Woof!", 4)
    ME.Breed = breed
END CONSTRUCTOR
```

Becomes:

```
function $Dog__CONSTRUCTOR(l %me, l %name, l %breed) {
@start
    # SUPER call → direct call to parent constructor
    %woof =l call $string_new_utf8(l $str_Woof)
    call $Animal__CONSTRUCTOR(l %me, l %name, l %woof, w 4)

    # ME.Breed = breed  (Breed at offset 40)
    %addr =l add %me, 40
    storel %breed, %addr

    ret
}
```

### 4.6 Method Function

Methods are emitted as regular QBE functions with `ME` as the first (hidden)
parameter.  The method name is mangled as `ClassName__MethodName`:

```basic
METHOD Speak()
    PRINT ME.Name; " the "; ME.Breed; " barks: "; ME.Sound
END METHOD
```

Becomes:

```
function $Dog__Speak(l %me) {
@start
    # ME.Name  (offset 16)
    %name_addr =l add %me, 16
    %name =l loadl %name_addr

    # ME.Breed  (offset 40)
    %breed_addr =l add %me, 40
    %breed =l loadl %breed_addr

    # ME.Sound  (offset 24)
    %sound_addr =l add %me, 24
    %sound =l loadl %sound_addr

    # PRINT ME.Name; " the "; ME.Breed; " barks: "; ME.Sound
    call $basic_print_string_desc(l %name)
    %s1 =l call $string_new_utf8(l $str_the)
    call $basic_print_string_desc(l %s1)
    call $basic_print_string_desc(l %breed)
    %s2 =l call $string_new_utf8(l $str_barks)
    call $basic_print_string_desc(l %s2)
    call $basic_print_string_desc(l %sound)
    call $basic_print_newline()

    ret
}
```

---

## 5. Runtime Library Additions

### 5.1 New Runtime Functions

```c
// === Object System Runtime (class_runtime.c) ===

// Allocate a new object of the given size, install vtable and class_id.
// Returns pointer to the new object (never NULL — aborts on OOM).
void* class_object_new(int64_t object_size, void* vtable, int64_t class_id);

// Free an object. Calls destructor via vtable if present.
// Sets *obj_ref to NULL (NOTHING).
void class_object_delete(void** obj_ref);

// Runtime error: method call on NOTHING.
// Prints error message and aborts.
void class_null_method_error(const char* location, const char* method_name);

// Runtime error: field access on NOTHING.
void class_null_field_error(const char* location, const char* field_name);

// IS type check: walk the inheritance chain via parent_vtable pointers.
// Returns 1 if obj's class is target_class_id or a subclass of it.
int32_t class_is_instance(void* obj, int64_t target_class_id);

// Debug: print object info (class name, address, field count).
void class_object_debug(void* obj);
```

### 5.2 class_object_new Implementation

```c
void* class_object_new(int64_t object_size, void* vtable, int64_t class_id) {
    void* obj = calloc(1, (size_t)object_size);
    if (!obj) {
        fprintf(stderr, "ERROR: Out of memory allocating object (%lld bytes)\n",
                (long long)object_size);
        exit(1);
    }
    // obj[0] = vtable pointer
    ((void**)obj)[0] = vtable;
    // obj[1] = class_id
    ((int64_t*)obj)[1] = class_id;
    return obj;
}
```

### 5.3 class_is_instance Implementation

```c
// VTable layout:
//   [0] int64  class_id
//   [1] ptr    parent_vtable (NULL for root)
//   [2] ptr    class_name
//   [3] ptr    destructor
//   [4..] ptr  method pointers

int32_t class_is_instance(void* obj, int64_t target_class_id) {
    if (!obj) return 0;  // NOTHING IS Anything → false

    // Fast path: check object's class_id directly
    int64_t obj_class_id = ((int64_t*)obj)[1];
    if (obj_class_id == target_class_id) return 1;

    // Slow path: walk parent chain via vtable
    void* vtable = ((void**)obj)[0];
    while (vtable) {
        int64_t vt_class_id = ((int64_t*)vtable)[0];
        if (vt_class_id == target_class_id) return 1;
        vtable = ((void**)vtable)[1];  // parent_vtable
    }
    return 0;
}
```

### 5.4 File Organisation

```
runtime_c/
  class_runtime.c      ← NEW: object system runtime
  class_runtime.h      ← NEW: header
  basic_runtime.c      ← existing (unchanged)
  ...
```

---

## 6. Compiler Pipeline Changes

### 6.1 Overview of Affected Components

```
Source (.bas)
    │
    ▼
┌─────────────────┐
│  Lexer          │  Add tokens: CLASS, EXTENDS, CONSTRUCTOR, DESTRUCTOR,
│  (fasterbasic_  │  METHOD, END_METHOD, END_CLASS, END_CONSTRUCTOR,
│   lexer.cpp)    │  END_DESTRUCTOR, ME, SUPER, NEW, DELETE, NOTHING, IS
└────────┬────────┘
         ▼
┌─────────────────┐
│  Parser         │  Add: parseClassDeclaration(), parseMethod(),
│  (fasterbasic_  │  parseConstructor(), parseNewExpression()
│   parser.cpp)   │  New AST nodes: ClassStatement, MethodStatement,
└────────┬────────┘  ConstructorStatement, NewExpression, etc.
         ▼
┌─────────────────┐
│  Semantic       │  Add: ClassSymbol, field offset computation,
│  Analyzer       │  vtable slot assignment, ME resolution,
│  (fasterbasic_  │  inheritance validation, IS type resolution
│   semantic.cpp) │
└────────┬────────┘
         ▼
┌─────────────────┐
│  CFG Builder    │  CLASS bodies generate separate ControlFlowGraphs
│  (cfg/)         │  for each method/constructor (like SUB/FUNCTION)
└────────┬────────┘
         ▼
┌─────────────────┐
│  CodeGen V2     │  Emit vtable data sections, constructor/method
│  (codegen_v2/)  │  functions, NEW lowering, vtable dispatch,
│  ast_emitter    │  field access via offsets, IS checks
│  cfg_emitter    │
└────────┬────────┘
         ▼
    QBE IL (.qbe)
         │
         ▼
┌─────────────────┐
│  QBE Backend    │  No changes needed (classes compile to standard
│  (qbe_source/)  │  QBE IL: data sections, functions, loads, stores)
└────────┬────────┘
         ▼
    Assembly / Executable
```

### 6.2 Lexer Changes

New keywords to add to `fasterbasic_token.h` and `fasterbasic_lexer.cpp`:

```cpp
// In TokenType enum:
KW_CLASS,           // CLASS
KW_END_CLASS,       // END CLASS
KW_EXTENDS,         // EXTENDS
KW_CONSTRUCTOR,     // CONSTRUCTOR
KW_END_CONSTRUCTOR, // END CONSTRUCTOR
KW_DESTRUCTOR,      // DESTRUCTOR
KW_END_DESTRUCTOR,  // END DESTRUCTOR
KW_METHOD,          // METHOD
KW_END_METHOD,      // END METHOD
KW_ME,              // ME
KW_SUPER,           // SUPER
KW_NEW,             // NEW
KW_DELETE,          // DELETE
KW_NOTHING,         // NOTHING
KW_IS,              // IS (for type checking)
```

**Note:** `END CLASS`, `END METHOD`, etc. are two-token sequences parsed
by the parser (like `END IF`, `END SUB` today).

### 6.3 AST Node Additions

```cpp
// --- New AST Nodes (in fasterbasic_ast.h) ---

enum class ASTNodeType {
    // ... existing entries ...
    STMT_CLASS,             // CLASS ... END CLASS
    STMT_METHOD,            // METHOD ... END METHOD (inside CLASS)
    STMT_CONSTRUCTOR,       // CONSTRUCTOR ... END CONSTRUCTOR
    STMT_DESTRUCTOR,        // DESTRUCTOR ... END DESTRUCTOR
    STMT_DELETE,            // DELETE obj
    EXPR_NEW,               // NEW ClassName(args)
    EXPR_ME,                // ME
    EXPR_SUPER,             // SUPER (as expression prefix)
    EXPR_IS_TYPE,           // obj IS ClassName
    EXPR_NOTHING,           // NOTHING
};


class ClassStatement : public Statement {
public:
    std::string className;
    std::string parentClassName;                    // empty if no EXTENDS
    std::vector<TypeDeclarationStatement::TypeField> fields;
    std::unique_ptr<ConstructorStatement> constructor;   // nullable
    std::unique_ptr<DestructorStatement> destructor;      // nullable
    std::vector<std::unique_ptr<MethodStatement>> methods;

    ASTNodeType getType() const override { return ASTNodeType::STMT_CLASS; }
};


class MethodStatement : public Statement {
public:
    std::string methodName;
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;
    std::vector<bool> parameterIsByRef;
    TokenType returnTypeSuffix;
    std::string returnTypeAsName;
    bool hasReturnType;
    std::vector<StatementPtr> body;

    ASTNodeType getType() const override { return ASTNodeType::STMT_METHOD; }
};


class ConstructorStatement : public Statement {
public:
    std::vector<std::string> parameters;
    std::vector<TokenType> parameterTypes;
    std::vector<std::string> parameterAsTypes;
    std::vector<bool> parameterIsByRef;
    std::vector<StatementPtr> body;
    // SUPER call info (extracted during parsing)
    bool hasSuperCall;
    std::vector<ExpressionPtr> superArgs;

    ASTNodeType getType() const override { return ASTNodeType::STMT_CONSTRUCTOR; }
};


class DestructorStatement : public Statement {
public:
    std::vector<StatementPtr> body;
    ASTNodeType getType() const override { return ASTNodeType::STMT_DESTRUCTOR; }
};


class NewExpression : public Expression {
public:
    std::string className;
    std::vector<ExpressionPtr> arguments;
    ASTNodeType getType() const override { return ASTNodeType::EXPR_NEW; }
};


class DeleteStatement : public Statement {
public:
    std::string variableName;
    ASTNodeType getType() const override { return ASTNodeType::STMT_DELETE; }
};


class MeExpression : public Expression {
public:
    ASTNodeType getType() const override { return ASTNodeType::EXPR_ME; }
};


class NothingExpression : public Expression {
public:
    ASTNodeType getType() const override { return ASTNodeType::EXPR_NOTHING; }
};


class IsTypeExpression : public Expression {
public:
    ExpressionPtr object;
    std::string className;          // NOTHING for "IS NOTHING"
    bool isNothingCheck;
    ASTNodeType getType() const override { return ASTNodeType::EXPR_IS_TYPE; }
};
```

### 6.4 Parser Changes

Add `parseClassDeclaration()` to the top-level statement parser, triggered
when the current token is `CLASS`:

```
parseClassDeclaration():
    consume CLASS
    className = consume IDENTIFIER
    if peek == EXTENDS:
        consume EXTENDS
        parentClassName = consume IDENTIFIER

    while peek != END:
        if peek is field declaration (IDENTIFIER AS TYPE):
            parse field, add to ClassStatement.fields
        else if peek == CONSTRUCTOR:
            parse constructor block → ConstructorStatement
        else if peek == DESTRUCTOR:
            parse destructor block → DestructorStatement
        else if peek == METHOD:
            parse method block → MethodStatement
        else if peek == REM / comment:
            skip
        else:
            error "unexpected statement inside CLASS"

    consume END CLASS
    return ClassStatement
```

**NEW expression** is parsed in `parseAtom()` / `parsePrimary()`:

```
if token == NEW:
    consume NEW
    className = consume IDENTIFIER
    consume LPAREN
    args = parseArgumentList()
    consume RPAREN
    return NewExpression(className, args)
```

**ME** is parsed as a primary expression, then member access / method call
follows naturally through the existing `.field` and `.method()` parsing.

**IS** is parsed as a binary operator between an expression and a type name:

```
expr IS ClassName     →  IsTypeExpression(expr, className)
expr IS NOTHING       →  IsTypeExpression(expr, isNothingCheck=true)
```

### 6.5 Semantic Analyzer Changes

#### New Symbol: ClassSymbol

```cpp
struct ClassSymbol {
    std::string name;
    int classId;                        // unique, assigned at registration time
    ClassSymbol* parentClass;           // nullptr for root classes
    SourceLocation declaration;
    bool isDeclared;

    // Object layout
    int objectSize;                     // total bytes including header + padding
    int headerSize;                     // 16 (vtable ptr + class_id)

    // Fields (includes inherited)
    struct FieldInfo {
        std::string name;
        TypeDescriptor typeDesc;
        int offset;                     // byte offset from object start
        bool inherited;                 // true if from parent class
    };
    std::vector<FieldInfo> fields;

    // Methods (includes inherited)
    struct MethodInfo {
        std::string name;
        std::string mangledName;        // "ClassName__MethodName"
        int vtableSlot;                 // index in method portion of vtable
        bool isOverride;                // true if overriding parent method
        std::string originClass;        // class where method was first defined
        // Signature info for validation
        std::vector<TypeDescriptor> parameterTypes;
        TypeDescriptor returnType;
    };
    std::vector<MethodInfo> methods;

    // Constructor & destructor
    bool hasConstructor;
    std::string constructorMangledName; // "ClassName__CONSTRUCTOR"
    std::vector<TypeDescriptor> constructorParamTypes;
    bool hasDestructor;
    std::string destructorMangledName;  // "ClassName__DESTRUCTOR"

    // Helpers
    const FieldInfo* findField(const std::string& name) const;
    const MethodInfo* findMethod(const std::string& name) const;
    int getMethodCount() const;          // total slots including inherited
    bool isSubclassOf(const ClassSymbol* other) const;
};
```

#### Registration Steps (in pass 1 — collectDeclarations)

```
collectClassDeclarations():
    for each ClassStatement in program:
        1. Resolve parent class (if EXTENDS). Error if not found or circular.
        2. Assign unique class_id.
        3. Compute inherited fields (copy from parent, mark inherited=true).
        4. Add own fields. Compute offsets with alignment.
        5. Compute inherited method slots (copy from parent).
        6. For each own METHOD:
            - If name matches a parent method → override (same slot, check signature)
            - Otherwise → new slot (append)
        7. Record constructor/destructor info.
        8. Compute objectSize.
        9. Register in SymbolTable.classes.
```

#### Validation Steps (in pass 2)

- `ME` used only inside METHOD/CONSTRUCTOR/DESTRUCTOR bodies.
- `SUPER()` used only in CONSTRUCTOR as first statement.
- `SUPER.Method()` used only in METHOD bodies of classes with parents.
- `NEW ClassName(args)` — class exists, constructor args match.
- `obj.FieldName` — obj is a class type (or parent type), field exists.
- `obj.MethodName()` — obj is a class type, method exists, args match.
- `obj IS ClassName` — obj is a class type, ClassName is defined.
- Assignment type checking: RHS class must be same as or subclass of LHS class.
- Override signature matching: parameter types must match exactly.

### 6.6 CFG Builder Changes

CLASS declarations are processed similarly to SUB/FUNCTION declarations:

1. The main program CFG skips over CLASS bodies (they are top-level
   declarations, not executable code).
2. Each METHOD and CONSTRUCTOR/DESTRUCTOR generates its own
   `ControlFlowGraph` (just like `buildSub()` / `buildDefFn()` today).
3. The `ME` parameter is added as the first parameter of each method's CFG.

### 6.7 CodeGen V2 Changes

#### Data Section Emission

Before emitting the main function, emit for each class:

1. **Class name string constant:**
   ```
   data $classname_Dog = { b "Dog", b 0 }
   ```

2. **VTable:**
   ```
   data $vtable_Dog = {
       l 2,                    # class_id
       l $vtable_Animal,       # parent_vtable
       l $classname_Dog,       # class_name
       l 0,                    # destructor (0 = none)
       l $Dog__Speak,          # method slot 0
       l $Animal__Describe,    # method slot 1
       l $Dog__Fetch           # method slot 2
   }
   ```

#### Method Emission

Each method is emitted as a standalone QBE function:

```
function $Dog__Speak(l %me) {
    @start
    ...
    ret
}

function $Dog__Fetch(l %me, l %item) {
    @start
    ...
    ret
}
```

The `ASTEmitter` gains a method `emitMethodBody()` that handles:
- `ME` references → `%me` parameter
- `ME.Field` → load from `%me + offset`
- `SUPER.Method()` → direct call to parent method function

#### NEW Expression Emission

The `ASTEmitter` gains `emitNewExpression()`:

```cpp
std::string ASTEmitter::emitNewExpression(const NewExpression* expr) {
    auto* cls = lookupClass(expr->className);

    // 1. Allocate
    auto obj = builder.newTemp("l");
    emit("call", obj, "$class_object_new",
         {getcon(cls->objectSize), "$vtable_" + cls->name, getcon(cls->classId)});

    // 2. Call constructor (if any)
    if (cls->hasConstructor) {
        std::vector<std::string> args = {obj};
        for (auto& arg : expr->arguments) {
            args.push_back(emitExpression(arg.get()));
        }
        emit("call", "$" + cls->constructorMangledName, args);
    }

    return obj;
}
```

#### Method Call Emission

The `ASTEmitter::emitMethodCall()` is extended to handle class methods:

```cpp
// Check if the object type is a CLASS (vs. runtime object like HASHMAP)
if (isClassType(objectType)) {
    auto* cls = lookupClass(objectType.className);
    auto* method = cls->findMethod(methodName);
    int slotOffset = VTABLE_HEADER_SIZE + method->vtableSlot * 8;

    // Null check
    emitNullCheck(objTemp, lineNumber, methodName);

    // VTable dispatch
    auto vtable = builder.newTemp("l");
    emit("loadl", vtable, objTemp);
    auto slotAddr = builder.newTemp("l");
    emit("add", slotAddr, vtable, getcon(slotOffset));
    auto methodPtr = builder.newTemp("l");
    emit("loadl", methodPtr, slotAddr);

    // Call with ME as first arg
    std::vector<std::string> allArgs = {objTemp};
    allArgs.insert(allArgs.end(), argTemps.begin(), argTemps.end());
    return emitIndirectCall(methodPtr, allArgs, method->returnType);
}
```

---

## 7. Type System Integration

### 7.1 BaseType Extension

Add to `BaseType` enum:

```cpp
enum class BaseType {
    // ... existing ...
    CLASS_INSTANCE,    // User-defined CLASS instance (pointer to heap object)
};
```

Or alternatively, reuse `USER_DEFINED` with an additional flag to distinguish
TYPE (value, stack/inline) vs CLASS (pointer, heap).  The latter approach
requires less type-system surgery:

```cpp
struct TypeDescriptor {
    // ... existing ...
    bool isClassType;          // true = CLASS (heap pointer), false = TYPE (value)
    std::string className;     // populated for isClassType == true
};
```

### 7.2 Assignment Compatibility

```
Compatible assignments (LHS = RHS):
  Animal = Animal       ✓ same class
  Animal = Dog          ✓ Dog extends Animal (upcast)
  Animal = Cat          ✓ Cat extends Animal (upcast)
  Dog = Animal          ✗ compile error (downcast not implicit)
  Dog = Cat             ✗ compile error (sibling classes)
  Animal = NOTHING      ✓ null assignment
  INTEGER = Dog         ✗ compile error (not an object)
```

### 7.3 Interaction with Runtime Objects

CLASS instances and runtime objects (HASHMAP, etc.) are both pointer-typed
but belong to separate type universes:

- `HASHMAP` is registered in `RuntimeObjectRegistry` with its own methods.
- `Dog` is registered as a `ClassSymbol` in the `SymbolTable`.

The `emitMethodCall()` dispatcher checks which universe the object belongs
to and routes accordingly.  A CLASS field can contain a HASHMAP (or vice
versa), but a CLASS cannot EXTENDS a runtime object type.

---

## 8. Constructor & Destructor Mechanics

### 8.1 Constructor Execution Order

For `NEW Dog("Rex", "Lab")`:

```
1. class_object_new()           → allocate + install vtable + class_id
2. Dog__CONSTRUCTOR(%obj, ...)
   2a. Animal__CONSTRUCTOR(%obj, ...)   ← SUPER call (explicit or implicit)
       2a-i. (fields are already zeroed by calloc)
       2a-ii. execute Animal constructor body
   2b. execute Dog constructor body
```

### 8.2 Default Constructor

If a class has no CONSTRUCTOR declared:
- If the parent has no constructor, no constructor call is needed.
- If the parent has a zero-argument constructor, the compiler generates
  an implicit constructor that calls `SUPER()`.
- If the parent has a constructor with required arguments, it is a
  **compile error** — the derived class must declare a CONSTRUCTOR with
  an explicit `SUPER(args)` call.

### 8.3 Destructor Execution Order

For `DELETE dog`:

```
1. Dog__DESTRUCTOR(%obj)
   1a. execute Dog destructor body
   1b. Animal__DESTRUCTOR(%obj)        ← implicit parent destructor call
       1b-i. execute Animal destructor body
2. free(%obj)
3. set variable to NOTHING
```

Destructors chain automatically — the compiler inserts the parent destructor
call at the end of each destructor body.

---

## 9. SUPER Dispatch

### 9.1 SUPER() in CONSTRUCTOR

`SUPER(args)` is a **direct call** to the parent constructor:

```
call $Animal__CONSTRUCTOR(l %me, l %arg0, l %arg1, w %arg2)
```

No vtable dispatch is needed — the parent is statically known.

### 9.2 SUPER.Method() in METHOD

`SUPER.Speak()` is a **direct call** to the parent class's implementation
of the method:

```
call $Animal__Speak(l %me)
```

Again, no vtable dispatch — the parent class and method are statically known
at compile time.  This is correct even in deeply nested hierarchies: SUPER
always refers to the **immediate parent** of the class where the METHOD is
defined.

---

## 10. IS Type-Check Operator

### 10.1 Compile-Time Optimisation

If the compiler can statically determine the result:

```basic
DIM d AS Dog = NEW Dog(...)
IF d IS Dog THEN ...           ' always true → optimise to true
IF d IS Animal THEN ...        ' always true (Dog extends Animal) → true
IF d IS Cat THEN ...           ' always false (Dog is not Cat) → false
```

### 10.2 Runtime Check

When the type is not statically known (e.g. variable typed as `Animal`
but holding a `Dog`):

```
%obj =l loadl %var_a
%result =w call $class_is_instance(l %obj, l 2)   # 2 = Dog's class_id
jnz %result, @is_true, @is_false
```

### 10.3 IS NOTHING

```
%obj =l loadl %var_a
%result =w ceql %obj, 0
jnz %result, @is_nothing, @not_nothing
```

This is a simple null-pointer check — no runtime call needed.

---

## 11. NOTHING & Null Safety

### 11.1 Default Value

All object variables initialise to NOTHING (0 / null pointer):

```
DIM d AS Dog            →  storel 0, %var_d
```

### 11.2 Null Checks

By default, the compiler inserts null checks before every field access and
method call.  These can be disabled with a compiler flag for performance:

```
fbc_qbe --no-null-checks program.bas
```

The null check pattern:

```
%obj =l loadl %var_d
%is_null =w ceql %obj, 0
jnz %is_null, @null_error_LINE, @ok_LINE
```

The error block calls a runtime function that prints a clear error message
including the line number, then aborts:

```
@null_error_42
    call $class_null_method_error(l $str_42, l $str_Speak)
    hlt
```

### 11.3 Cost of Null Checks

Each null check is one compare + one conditional branch.  On the non-error
path (the common case), the branch is predicted taken, so the cost is
effectively zero in steady-state execution.  For tight loops over known-
non-null objects, `--no-null-checks` eliminates even this minimal overhead.

---

## 12. Worked Example: Full QBE Output

Input program:

```basic
CLASS Greeter
  Greeting AS STRING

  CONSTRUCTOR(g AS STRING)
    ME.Greeting = g
  END CONSTRUCTOR

  METHOD SayHello(name AS STRING)
    PRINT ME.Greeting; ", "; name; "!"
  END METHOD
END CLASS

DIM g AS Greeter = NEW Greeter("Hello")
g.SayHello("World")
END
```

Complete QBE IL output:

```
# === String Constants ===
data $str_Hello = { b "Hello", b 0 }
data $str_World = { b "World", b 0 }
data $str_comma = { b ", ", b 0 }
data $str_bang = { b "!", b 0 }
data $classname_Greeter = { b "Greeter", b 0 }
data $str_line_14 = { b "line 14", b 0 }
data $str_SayHello = { b "SayHello", b 0 }

# === VTable ===
data $vtable_Greeter = {
    l 1,                        # class_id = 1
    l 0,                        # parent_vtable = null
    l $classname_Greeter,       # class name
    l 0,                        # destructor = null
    l $Greeter__SayHello        # method slot 0
}

# === Constructor ===
function $Greeter__CONSTRUCTOR(l %me, l %g) {
@start
    # ME.Greeting = g  (Greeting at offset 16)
    %addr =l add %me, 16
    storel %g, %addr
    ret
}

# === Method: SayHello ===
function $Greeter__SayHello(l %me, l %name) {
@start
    # ME.Greeting  (offset 16)
    %greeting_addr =l add %me, 16
    %greeting =l loadl %greeting_addr

    # PRINT ME.Greeting; ", "; name; "!"
    call $basic_print_string_desc(l %greeting)
    %s1 =l call $string_new_utf8(l $str_comma)
    call $basic_print_string_desc(l %s1)
    call $basic_print_string_desc(l %name)
    %s2 =l call $string_new_utf8(l $str_bang)
    call $basic_print_string_desc(l %s2)
    call $basic_print_newline()
    ret
}

# === Main Program ===
export function w $main() {
@block_0
    # DIM g AS Greeter (local variable, pointer)
    %var_g =l alloc8 8
    storel 0, %var_g

    # NEW Greeter("Hello")
    %obj =l call $class_object_new(l 24, l $vtable_Greeter, l 1)
    %hello =l call $string_new_utf8(l $str_Hello)
    call $Greeter__CONSTRUCTOR(l %obj, l %hello)
    storel %obj, %var_g

    # g.SayHello("World")
    %g =l loadl %var_g

    # null check
    %is_null =w ceql %g, 0
    jnz %is_null, @null_err_14, @dispatch_14

@dispatch_14
    %vtable =l loadl %g
    %slot =l add %vtable, 32        # header(32) + slot(0)*8
    %method =l loadl %slot
    %world =l call $string_new_utf8(l $str_World)
    call %method(l %g, l %world)
    ret 0

@null_err_14
    call $class_null_method_error(l $str_line_14, l $str_SayHello)
    hlt
}
```

---

## 13. Phase Plan

### Phase 1: Core CLASS (MVP)

**Goal:** CLASS, fields, CONSTRUCTOR, METHOD, NEW, ME, field access, method
dispatch via vtable.

| Task | Component | Estimate |
|------|-----------|----------|
| Add tokens (CLASS, METHOD, NEW, ME, etc.) | Lexer | 1 hr |
| Add AST nodes (ClassStatement, MethodStatement, etc.) | AST | 2 hr |
| Parse CLASS...END CLASS block | Parser | 4 hr |
| Parse NEW expression | Parser | 1 hr |
| ClassSymbol + field offset computation | Semantic | 4 hr |
| VTable slot assignment | Semantic | 2 hr |
| ME / CONSTRUCTOR / METHOD validation | Semantic | 3 hr |
| CFG builder for METHOD/CONSTRUCTOR bodies | CFG | 2 hr |
| Emit vtable data sections | CodeGen | 2 hr |
| Emit constructor/method functions | CodeGen | 4 hr |
| Emit NEW (alloc + vtable install + ctor call) | CodeGen | 2 hr |
| Emit vtable method dispatch | CodeGen | 3 hr |
| Emit field access (ME.Field, obj.Field) | CodeGen | 2 hr |
| class_runtime.c (class_object_new, null error) | Runtime | 2 hr |
| Basic test suite | Tests | 3 hr |
| **Phase 1 total** | | **~35 hr** |

### Phase 2: Inheritance

**Goal:** EXTENDS, SUPER(), SUPER.Method(), override validation.

| Task | Component | Estimate |
|------|-----------|----------|
| Parse EXTENDS clause | Parser | 0.5 hr |
| Inherited field + method computation | Semantic | 3 hr |
| SUPER() in CONSTRUCTOR | Parser + Semantic + CodeGen | 3 hr |
| SUPER.Method() in METHOD | Parser + Semantic + CodeGen | 2 hr |
| Override signature validation | Semantic | 2 hr |
| Polymorphic dispatch tests | Tests | 3 hr |
| **Phase 2 total** | | **~14 hr** |

### Phase 3: IS, NOTHING, DELETE

**Goal:** Type checking, null safety, explicit cleanup.

| Task | Component | Estimate |
|------|-----------|----------|
| Parse IS expression | Parser | 1 hr |
| IS type check (compile-time + runtime) | Semantic + CodeGen | 3 hr |
| NOTHING literal | Parser + CodeGen | 1 hr |
| Null check insertion | CodeGen | 2 hr |
| DELETE statement + DESTRUCTOR | Parser + Semantic + CodeGen | 3 hr |
| class_is_instance runtime function | Runtime | 1 hr |
| Error message quality pass | Runtime | 1 hr |
| **Phase 3 total** | | **~12 hr** |

### Phase 4: Polish & Optimisation

| Task | Estimate |
|------|----------|
| Direct dispatch optimisation (devirtualisation) | 4 hr |
| ToString() integration with PRINT | 2 hr |
| Arrays of objects + polymorphism tests | 3 hr |
| Comprehensive test suite (20+ tests) | 4 hr |
| Documentation and examples | 2 hr |
| **Phase 4 total** | **~15 hr** |

### Total estimated effort: ~76 hours

---

## Appendix A: Constants

```cpp
// Object header layout
constexpr int CLASS_VTABLE_PTR_OFFSET = 0;   // offset of vtable pointer in object
constexpr int CLASS_ID_OFFSET = 8;            // offset of class_id in object
constexpr int CLASS_HEADER_SIZE = 16;         // total header size (before fields)

// VTable header layout
constexpr int VTABLE_CLASS_ID_OFFSET = 0;
constexpr int VTABLE_PARENT_PTR_OFFSET = 8;
constexpr int VTABLE_NAME_PTR_OFFSET = 16;
constexpr int VTABLE_DESTRUCTOR_OFFSET = 24;
constexpr int VTABLE_METHODS_OFFSET = 32;     // first method pointer

// Class ID allocation
constexpr int CLASS_ID_NOTHING = 0;           // reserved for NOTHING
constexpr int CLASS_ID_FIRST = 1;             // first user class
```

## Appendix B: Name Mangling

```
Class constructor:    ClassName__CONSTRUCTOR
Class destructor:     ClassName__DESTRUCTOR
Class method:         ClassName__MethodName
VTable:               vtable_ClassName
Class name string:    classname_ClassName
```

All names are prefixed with `$` in QBE IL (global symbols).

Examples:
```
$Dog__CONSTRUCTOR
$Dog__Speak
$Dog__Fetch
$Animal__Describe
$vtable_Dog
$classname_Dog
```
