# Automatic Function Scoping

## Overview

The FasterBASIC compiler now includes **automatic function scoping** that intelligently detects when functions and SUBs need SAMM (Scope-Aware Memory Management) scope tracking. This feature helps prevent memory leaks without requiring manual scope management in every function.

## How It Works

The compiler analyzes each FUNCTION and SUB definition to determine if it needs automatic scope management. A function/SUB gets automatic scoping if it:

1. **Uses DIM statements** - Local variable declarations that may allocate dynamic memory
2. **Uses REDIM statements** - Dynamic array resizing
3. **Has loops with allocations** - Combines loop constructs (FOR/WHILE/DO/REPEAT) with operations that create managed memory (NEW, string literals, etc.)

When automatic scoping is detected, the compiler injects:
- `samm_enter_scope()` at the function prologue (after the function label)
- `samm_exit_scope()` at all function exit points (before return)

## Examples

### Function WITH Automatic Scoping

```basic
FUNCTION ProcessData(count AS INTEGER) AS INTEGER
    DIM result AS INTEGER        ' ← DIM detected!
    DIM temp AS STRING
    DIM i AS INTEGER
    
    result = 0
    FOR i = 1 TO count
        temp = "Processing"
        result = result + i
    NEXT i
    
    ProcessData = result
END FUNCTION
```

**Generated IL includes:**
```qbe
export function w $func_PROCESSDATA(w %count) {
@prologue
# SAMM: Enter function scope (auto-detected)
    call $samm_enter_scope()
    
    ; ... function body ...
    
@ProcessData_exit
# SAMM: Exit function scope (auto-detected)
    call $samm_exit_scope()
    ret %result
}
```

### Function WITHOUT Automatic Scoping

```basic
FUNCTION SimpleCalc(x AS INTEGER, y AS INTEGER) AS INTEGER
    ' No DIM, no allocations - no automatic scope needed
    SimpleCalc = x * y + 10
END FUNCTION
```

**Generated IL:**
```qbe
export function w $func_SIMPLECALC(w %x, w %y) {
@prologue
    ; ... function body (NO scope calls) ...
@SimpleCalc_exit
    ret %result
}
```

## CLASS Methods Always Get Scopes

CLASS constructors, destructors, and methods **always** receive automatic scoping regardless of DIM usage, because they commonly work with object state and temporary allocations:

```basic
CLASS MyClass
    PRIVATE:
        value AS INTEGER
    
    PUBLIC:
        METHOD SetValue(v AS INTEGER)
            ' Automatic scope injected even without DIM
            ME.value = v
        END METHOD
END CLASS
```

## Benefits

1. **Memory Safety** - Prevents leaks in functions that allocate strings, objects, or dynamic arrays
2. **Developer Convenience** - No need to manually add scope management to every function
3. **Performance** - Functions without allocations skip scope overhead entirely
4. **Compatibility** - Works seamlessly with existing code; transparent to the programmer

## Detection Logic

The `FunctionScopeAnalyzer` examines the CFG (Control Flow Graph) for each function:

```zig
pub const FunctionScopeAnalyzer = struct {
    needs_scope: bool = false,
    has_dim: bool = false,
    has_loops: bool = false,
    has_allocations: bool = false,
    
    pub fn analyze(the_cfg: *const cfg_mod.CFG) FunctionScopeAnalyzer {
        // Walks all blocks in the CFG
        // Detects: DIM, REDIM, loop constructs, NEW expressions
        // Returns: needs_scope = has_dim OR (has_loops AND has_allocations)
    }
};
```

### Key Detection Points:

- **DIM statements** (`stmt.dim`) - Always triggers scoping
- **REDIM statements** (`stmt.redim`) - Always triggers scoping
- **Loop blocks** (`block.kind == .loop_header/body/increment`) - Sets `has_loops` flag
- **NEW expressions** (`expr.new`) - Sets `has_allocations` flag
- **String literals in assignments** - Sets `has_allocations` flag (may accumulate in loops)

## Compiler Implementation

The automatic scoping is implemented in `codegen.zig`:

1. **Analysis Phase** - Before generating a function, analyze its CFG:
   ```zig
   const scope_analysis = FunctionScopeAnalyzer.analyze(func_cfg);
   ```

2. **Code Generation** - Pass the analysis result to `emitCFGFunction`:
   ```zig
   try self.emitCFGFunction(
       func_cfg, 
       mangled_name, 
       return_type, 
       params, 
       is_main, 
       &func_ctx, 
       scope_analysis.needs_scope  // ← Auto-scope flag
   );
   ```

3. **Scope Injection** - Emit scope calls when `auto_scope` is true:
   ```zig
   // At function prologue:
   if (!is_main and auto_scope and self.samm_enabled) {
       try self.builder.emitComment("SAMM: Enter function scope (auto-detected)");
       try self.runtime.callVoid("samm_enter_scope", "");
   }
   
   // At function exit:
   if (auto_scope and self.samm_enabled) {
       try self.builder.emitComment("SAMM: Exit function scope (auto-detected)");
       try self.runtime.callVoid("samm_exit_scope", "");
   }
   ```

## Verifying Automatic Scoping

To verify that automatic scoping is working:

1. **Compile with IL output:**
   ```bash
   ./fbc myprogram.bas -i -o myprogram.il
   ```

2. **Inspect the IL for scope calls:**
   ```bash
   grep -A 10 "function.*\$func_YourFunction" myprogram.il
   ```

3. **Look for comments:**
   ```qbe
   # SAMM: Enter function scope (auto-detected)
   # SAMM: Exit function scope (auto-detected)
   ```

## Disabling Automatic Scoping

Automatic scoping respects the `OPTION SAMM OFF` directive:

```basic
OPTION SAMM OFF

FUNCTION MyFunction() AS INTEGER
    DIM x AS INTEGER
    ' Even with DIM, no automatic scope because SAMM is OFF
    MyFunction = 42
END FUNCTION
```

## Performance Considerations

- **Minimal Overhead** - Only functions that actually need scoping get it
- **No Cost for Simple Functions** - Pure computation functions have zero scope overhead
- **Efficient Detection** - Analysis is performed once during compilation, not at runtime

## Future Enhancements

Potential improvements to automatic scoping:

1. **More Precise Analysis** - Detect specific allocating function calls (STR$, CHR$, LEFT$, etc.)
2. **Multi-dimensional Array Support** - Better detection of complex array operations
3. **UDT Field Analysis** - Detect when UDT fields contain strings or managed types
4. **Explicit Override** - Allow `SCOPED FUNCTION` or `UNSCOPED FUNCTION` keywords for manual control
5. **Compile-Time Stats** - Report which functions got automatic scoping during verbose builds

## Related Documentation

- `SAMM_SCOPE_LOGIC.md` - Details on SAMM scope behavior and CLASS-specific scoping
- `runtime/samm_core.zig` - SAMM implementation and scope tracking
- `src/codegen.zig` - Code generation and automatic scope injection

## Testing

Test automatic scoping with:
```bash
./fbc tests/test_auto_scope.bas -r
```

This test verifies:
- Functions with DIM get automatic scoping
- Functions without DIM do not get scoping
- SUBs with DIM in loops get scoping
- String operations in functions with DIM work correctly