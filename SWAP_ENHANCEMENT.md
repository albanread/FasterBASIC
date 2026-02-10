# SWAP Command Enhancement

## Overview

The SWAP command has been enhanced to support array elements and complex lvalue expressions, not just simple variables. This allows for more flexible and efficient code, particularly in sorting algorithms and data manipulation routines.

## Changes Made

### 1. AST Updates (`zig_compiler/src/ast.zig`)

Extended `SwapStmt` structure to include array indices and member chains:

```zig
pub const SwapStmt = struct {
    var1: []const u8,
    var1_indices: []ExprPtr = &.{},
    var1_member_chain: []const []const u8 = &.{},
    var2: []const u8,
    var2_indices: []ExprPtr = &.{},
    var2_member_chain: []const []const u8 = &.{},
};
```

### 2. Parser Updates (`zig_compiler/src/parser.zig`)

Updated `parseSwapStatement` to:
- Parse array indices for both operands using the same pattern as assignment statements
- Parse member chains for both operands
- Accept keywords as variable names (like DATA, READ, etc.) in addition to identifiers
- Properly handle complex index expressions like `arr(i + 1)`

### 3. Codegen Updates (`zig_compiler/src/codegen.zig`)

Rewrote `emitSwapStatement` to:
- Compute lvalue addresses for both operands
- Handle simple variables, array elements, and potentially member access
- Use runtime array bounds checking for array element swaps
- Call `fbc_array_element_addr` to get proper element addresses
- Preserve correct type information for different element types

## Supported SWAP Patterns

### 1. Simple Variable Swap
```basic
DIM a AS INTEGER, b AS INTEGER
a = 10
b = 20
SWAP a, b
' Result: a=20, b=10
```

### 2. Array Element Swap (Same Array)
```basic
DIM arr(10) AS INTEGER
arr(1) = 100
arr(2) = 200
SWAP arr(1), arr(2)
' Result: arr(1)=200, arr(2)=100
```

### 3. Array Elements with Expression Indices
```basic
DIM nums(10) AS INTEGER
DIM i AS INTEGER
i = 3
nums(i) = 333
nums(i + 1) = 444
SWAP nums(i), nums(i + 1)
' Result: nums(3)=444, nums(4)=333
```

### 4. Mixed Swap (Variable and Array Element)
```basic
DIM x AS INTEGER
DIM arr(5) AS INTEGER
x = 77
arr(1) = 88
SWAP x, arr(1)
' Result: x=88, arr(1)=77
```

### 5. Different Data Types
```basic
DIM f1 AS DOUBLE, f2 AS DOUBLE
f1 = 3.14
f2 = 2.718
SWAP f1, f2
' Result: f1=2.718, f2=3.14
```

## Use Case: Bubble Sort

The enhancement was specifically designed to support efficient sorting algorithms:

```basic
' Bubble Sort with SWAP
DIM arr(1000) AS INTEGER
FOR i = 1 TO size - 1
    FOR j = 1 TO size - i
        IF arr(j) > arr(j + 1) THEN
            SWAP arr(j), arr(j + 1)  ' ← Now supported!
        END IF
    NEXT j
NEXT i
```

Previously, this would have required manual swapping with a temporary variable:
```basic
' Old way (still works)
IF arr(j) > arr(j + 1) THEN
    DIM temp AS INTEGER
    temp = arr(j)
    arr(j) = arr(j + 1)
    arr(j + 1) = temp
END IF
```

## Implementation Details

### Address Computation

For array elements, the codegen:
1. Evaluates the index expression
2. Converts the index to an integer if necessary
3. Loads the array descriptor
4. Performs bounds checking via `fbc_array_bounds_check`
5. Computes the element address via `fbc_array_element_addr`
6. Uses the element address for the swap operation

### Type Safety

- Array element types are looked up from the symbol table
- Correct QBE memory operations are used based on element type
- Type conversions are handled automatically when needed

### Keyword Variables

The parser now accepts BASIC keywords as variable names in SWAP statements, consistent with how assignment statements work. This means variables named `DATA`, `READ`, etc. can be used in SWAP operations.

## Testing

### Test Suite

A comprehensive test suite (`tests/test_swap_enhanced.bas`) verifies:
- Simple variable swaps
- Array element swaps
- Expression indices
- Mixed variable/array swaps
- Floating-point swaps

All tests pass successfully.

### Benchmarks

The bubblesort benchmark (`performance_tests/benchmark_bubblesort.bas`) demonstrates real-world usage:
- Sorts 1000 integers using bubble sort with SWAP
- Runs 100 iterations
- Verifies correctness
- Measures performance

## Backward Compatibility

All existing SWAP usage with simple variables continues to work exactly as before. The enhancement is purely additive and does not break any existing code.

## Future Enhancements

Potential future improvements:
- Support for UDT member swaps (e.g., `SWAP obj1.field, obj2.field`)
- Support for 2D/3D array element swaps
- Optimization for common patterns (e.g., adjacent element swaps)
- SIMD optimizations for bulk array element swaps

## Performance Notes

Array element swaps include runtime bounds checking for safety. This adds a small overhead compared to simple variable swaps, but ensures program correctness and prevents buffer overflows.

The generated code for `SWAP arr(i), arr(j)`:
1. Evaluates both indices
2. Performs bounds checks for both
3. Computes both element addresses
4. Loads both values into temporaries
5. Stores values back in swapped order

This is still more efficient than manually coding the swap, as it's done in a single statement and benefits from future compiler optimizations.

## Build and Test Commands

```bash
# Rebuild compiler
cd zig_compiler && zig build

# Run enhanced swap tests
cd tests && ../zig_compiler/zig-out/bin/fbc test_swap_enhanced.bas && ./test_swap_enhanced

# Run bubblesort benchmark
cd performance_tests && ../zig_compiler/zig-out/bin/fbc benchmark_bubblesort.bas && ./benchmark_bubblesort

# Run all benchmarks
./run_benchmarks.sh

# Run all stress tests
./run_stress_tests.sh
```

## References

- Parser implementation: `zig_compiler/src/parser.zig` (parseSwapStatement)
- AST definition: `zig_compiler/src/ast.zig` (SwapStmt)
- Code generation: `zig_compiler/src/codegen.zig` (emitSwapStatement)
- Test suite: `tests/test_swap_enhanced.bas`
- Benchmark: `performance_tests/benchmark_bubblesort.bas`
