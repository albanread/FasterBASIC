# SAMM Scope Management in Code Generation

## Overview

SAMM (Scope-Aware Memory Management) uses **enter/exit scope** calls to track object lifetimes and automatically clean up memory when scopes exit. This document explains when and why the compiler inserts these calls.

## Core Concept

SAMM maintains a **scope stack** at runtime:
- `samm_enter_scope()` - Pushes a new scope frame
- `samm_exit_scope()` - Pops the current scope and frees all objects allocated within it

Objects allocated within a scope are automatically freed when that scope exits, unless they are:
1. Explicitly deleted with `DEL`
2. Retained with `RETAIN` to survive scope exit
3. Returned from a function (automatically retained)

## Current Implementation Status

### ✅ Scoped (Automatic Cleanup)

SAMM scope management is **currently enabled** for:

1. **CLASS Constructors**
   - `samm_enter_scope()` at constructor start
   - `samm_exit_scope()` before returning
   - Objects created in constructor are cleaned up automatically

2. **CLASS Destructors**
   - `samm_enter_scope()` at destructor start
   - `samm_exit_scope()` before returning
   - Temporary objects during destruction are cleaned up

3. **CLASS Methods**
   - `samm_enter_scope()` at method start
   - Return value is retained before scope exit (if it's an object)
   - `samm_exit_scope()` at all exit points (RETURN, EXIT METHOD, fall-through)
   - Local objects in method are cleaned up

### ❌ Not Currently Scoped

SAMM scope management is **NOT enabled** for:

1. **Regular FUNCTIONs**
   - No enter/exit scope calls
   - Objects allocated in functions persist until program exit or manual deletion
   - Rationale: Performance (most functions don't create many temporary objects)

2. **SUBs (Subroutines)**
   - No enter/exit scope calls
   - Same behavior as FUNCTIONs

3. **Main Program**
   - No scope management (main runs in global scope)
   - Only `samm_init()` at start and `samm_shutdown()` at end

4. **Control Flow (FOR/WHILE/IF/etc.)**
   - No automatic scopes for loops or conditionals
   - Objects created in loops persist beyond loop exit

## Why CLASS Methods Have Scopes

CLASS methods use scope management because:

1. **Object-oriented patterns** - Methods often create temporary objects for calculations
2. **Encapsulation** - Method internals should clean up after themselves
3. **Safety** - Prevents memory leaks in complex object hierarchies
4. **Consistency** - Matches behavior of modern OOP languages

Example:
```basic
METHOD Calculate() AS INTEGER
    ' These strings are automatically cleaned up when method returns
    DIM temp AS STRING
    temp = "Processing: " + ME.Name
    PRINT temp
    
    DIM result AS INTEGER
    result = ME.Value * 2
    Calculate = result
    ' temp string automatically freed here
END METHOD
```

## Code Generation Details

### CLASS Constructor Example

Generated QBE IL:
```qbe
export function w $class_MyClass__constructor(l %self) {
@start
    # SAMM: Enter CONSTRUCTOR scope
    call $samm_enter_scope()
    
    # ... constructor code ...
    # Allocate member variables, call parent constructor, etc.
    
    # SAMM: Exit CONSTRUCTOR scope
    call $samm_exit_scope()
    ret 0
}
```

### CLASS Method with Return Value

Generated QBE IL:
```qbe
export function l $class_MyClass__GetData(l %self) {
@start
    # SAMM: Enter METHOD scope
    call $samm_enter_scope()
    
    # ... method code ...
    # Allocate return slot
    %ret_slot =l alloc8 8
    
    # ... compute result, store in %ret_slot ...
    
    # Load return value
    %ret_val =l loadl %ret_slot
    
    # SAMM: Retain returned object before scope exit
    call $samm_retain(l %ret_val, w 1)
    
    # SAMM: Exit METHOD scope
    call $samm_exit_scope()
    
    ret %ret_val
}
```

### Regular FUNCTION (No Scopes)

Generated QBE IL:
```qbe
export function w $function_Calculate(w %x) {
@prologue
    # ... parameter setup ...
    %x_slot =l alloc4 4
    storew %x, %x_slot
    
@start
    # NO samm_enter_scope() call!
    
    # ... function code ...
    # Any strings/objects created here persist until program exit
    
    # NO samm_exit_scope() call!
    ret %result
}
```

## Implementation in codegen.zig

### Where Scopes Are Added

1. **`emitClassConstructor()`** (line ~9688)
   ```zig
   if (self.samm_enabled) {
       try self.builder.emitComment("SAMM: Enter CONSTRUCTOR scope");
       try self.builder.emitCall("", "", "samm_enter_scope", "");
   }
   ```

2. **`emitClassDestructor()`** (line ~9811)
   ```zig
   if (self.samm_enabled) {
       try self.builder.emitComment("SAMM: Enter DESTRUCTOR scope");
       try self.builder.emitCall("", "", "samm_enter_scope", "");
   }
   ```

3. **`emitClassMethod()`** (line ~9890)
   ```zig
   if (self.samm_enabled) {
       try self.builder.emitComment("SAMM: Enter METHOD scope");
       try self.builder.emitCall("", "", "samm_enter_scope", "");
   }
   ```

4. **Exit points** in methods:
   - Explicit RETURN statements
   - EXIT METHOD statements
   - Fall-through at end of method
   - Each checks `self.samm_enabled` and calls `samm_exit_scope()`

### Where Scopes Are NOT Added

1. **`emitCFGFunction()`** - Regular FUNCTIONs/SUBs
   - Only calls `basic_runtime_init()` for main
   - No scope management for user functions
   - Location: line ~9300-9370

2. **`emitBlock()`** - Control flow blocks
   - Entry blocks for functions don't add scopes
   - Loop blocks don't add scopes
   - Location: line ~9395-9470

## Control Flow: samm_enabled Flag

The `samm_enabled` flag controls whether scopes are emitted:

```zig
pub const CFGCodeGenerator = struct {
    samm_enabled: bool,
    // ...
    
    pub fn init(...) CFGCodeGenerator {
        return .{
            // ...
            .samm_enabled = true,  // Can be controlled via OPTION SAMM
        };
    }
};
```

Users can disable SAMM with:
```basic
OPTION SAMM OFF
```

Even with SAMM OFF:
- `samm_init()` still called (initializes string pools)
- `samm_shutdown()` still called (frees pools)
- Only scope tracking is disabled

## Memory Statistics and Scopes

When you see in memory stats:
```
Scopes entered:       4001
Scopes exited:        4001
```

This counts:
- Each CLASS method/constructor/destructor invocation
- NOT regular function calls (they don't create scopes)

Example program:
```basic
CLASS MyClass
    METHOD DoWork()
        ' Creates 1 scope enter/exit
    END METHOD
END CLASS

DIM obj AS MyClass
obj.CREATE()           ' Constructor: 1 scope enter/exit
FOR i = 1 TO 1000
    obj.DoWork()       ' Each call: 1 scope enter/exit
NEXT i
' Total: 1 constructor + 1000 method calls = 1001 scopes
```

## Performance Implications

### Overhead of Scopes

Each scope enter/exit:
- **Time**: ~100-500 nanoseconds (very fast)
- **Memory**: ~40 bytes per scope frame
- **Cleanup**: Proportional to objects in scope

### Why Not Scope Everything?

**Regular functions/SUBs are not scoped because:**

1. **Performance** - Most functions don't create many temporary objects
2. **Predictability** - Objects live until explicit deletion or program exit
3. **Backwards compatibility** - Traditional BASIC behavior
4. **Flexibility** - Allows functions to return objects without retention

**CLASS methods ARE scoped because:**

1. **Safety** - OOP patterns create many temporary objects
2. **Encapsulation** - Method internals shouldn't leak memory
3. **Modern expectations** - Matches Java/C#/Python behavior

## Future Enhancements

Potential improvements:

### Option 1: Per-Function Scope Control

```basic
FUNCTION Calculate(x AS INTEGER) AS INTEGER SCOPED
    ' Automatic cleanup enabled for this function
    DIM temp AS STRING
    temp = "Processing " + STR(x)
    ' temp automatically freed at return
    Calculate = LEN(temp) * x
END FUNCTION
```

### Option 2: Block-Level Scopes

```basic
FOR i = 1 TO 1000
    SCOPE
        DIM temp AS STRING
        temp = "Item " + STR(i)
        PRINT temp
    END SCOPE
    ' temp automatically freed here
NEXT i
```

### Option 3: Automatic Function Scoping

Analyze functions and add scopes only when they:
- Allocate strings/lists/objects
- Have loops that create temporaries
- Call other functions that allocate

## Debugging Scope Issues

### Memory Leak in Method

If you see:
```
Leaked objects:       50
```

And you have CLASS methods, check:
1. Are you storing objects in globals from within methods?
2. Are you using RETAIN without corresponding cleanup?
3. Are circular references preventing cleanup?

### Function Memory Growth

If a function grows memory over time:
1. It's NOT using SAMM scopes (expected)
2. Consider explicit `DEL` statements
3. Or refactor into a CLASS method with automatic cleanup

### Enabling Scope Tracing

Set environment variable:
```bash
SAMM_TRACE=1 ./your_program
```

This prints:
- Every scope enter/exit
- Every object allocation/cleanup
- Useful for debugging scope lifetime issues

## Reference: Runtime Functions

### samm_enter_scope()

**Signature**: `void samm_enter_scope(void)`

**Purpose**: Push new scope frame onto stack

**Called by**:
- CLASS constructor entry
- CLASS destructor entry  
- CLASS method entry

**Side effects**:
- Increments scope depth counter
- Allocates scope frame (if needed)
- Updates scope statistics

### samm_exit_scope()

**Signature**: `void samm_exit_scope(void)`

**Purpose**: Pop current scope and free objects

**Called by**:
- CLASS constructor exit
- CLASS destructor exit
- CLASS method exit (all paths)

**Side effects**:
- Frees all objects in current scope
- Decrements scope depth counter
- May trigger background cleanup thread
- Updates scope statistics

### samm_retain()

**Signature**: `void samm_retain(void* ptr, int offset)`

**Purpose**: Increment reference count to keep object alive

**Called by**:
- Before returning object from METHOD
- Explicit RETAIN statements (future feature)

**Effect**: Object survives scope exit

## Summary

**Current behavior:**
- ✅ CLASS methods/constructors/destructors use scopes
- ❌ Regular FUNCTIONs/SUBs do NOT use scopes
- ❌ Control flow (FOR/WHILE/IF) does NOT create scopes

**Rationale:**
- Balance between safety and performance
- CLASS methods need cleanup for OOP patterns
- Regular functions match traditional BASIC behavior

**Memory implications:**
- Objects in CLASS methods are automatically freed
- Objects in FUNCTIONs persist until program exit or DEL
- Use CLASS methods when you want automatic cleanup
- Use FUNCTIONs when you want manual control

**To see scope activity:**
```bash
BASIC_MEMORY_STATS=1 ./your_program
```

Look for "Scopes entered/exited" in the output.