# Array Expressions in FasterBASIC

*Whole-array operations — write `C() = A() + B()` and let the compiler handle the loop, the SIMD, and the details.*

---

## Introduction

FasterBASIC supports **array expressions** — arithmetic and assignment operations that apply to every element of an array in a single statement. Instead of writing a FOR loop to add two arrays element by element, you write:

```basic
C() = A() + B()
```

The compiler generates a tight, vectorized loop behind the scenes. On ARM64, it emits NEON SIMD instructions that process multiple elements per clock cycle. On all platforms, it eliminates the boilerplate and lets you focus on what you're computing, not how to loop over it.

If you've used array operations in Fortran, MATLAB, or NumPy, you'll feel right at home. The difference is that this is compiled BASIC, producing native machine code.

---

## The Basics

### Syntax

The `()` suffix marks a variable as a whole-array reference. Any array declared with `DIM` can be used this way:

```basic
DIM A(100) AS SINGLE
DIM B(100) AS SINGLE
DIM C(100) AS SINGLE

' Element-wise addition — applies to every element
C() = A() + B()
```

This is equivalent to:

```basic
FOR i = 0 TO 100
  C(i) = A(i) + B(i)
NEXT i
```

But the array expression form is shorter, clearer, and gives the compiler more freedom to optimize.

### Why the Parentheses?

The empty `()` is intentional. It makes array operations visually distinct from scalar operations:

```basic
x = a + b        ' scalar: adds two numbers
C() = A() + B()  ' array: adds every element of A to every element of B
```

There's never any ambiguity about what's happening.

---

## Supported Operations

### Element-Wise Arithmetic

All four arithmetic operators work element by element across entire arrays:

```basic
DIM A(1000) AS SINGLE
DIM B(1000) AS SINGLE
DIM C(1000) AS SINGLE

C() = A() + B()    ' addition
C() = A() - B()    ' subtraction
C() = A() * B()    ' multiplication
C() = A() / B()    ' division
```

Each operation produces a result array where element `i` is the result of applying the operator to `A(i)` and `B(i)`.

### Array Copy

Copy the entire contents of one array to another:

```basic
DIM source(500) AS INTEGER
DIM dest(500) AS INTEGER

dest() = source()
```

This copies every element. On ARM64, it uses 128-bit NEON loads and stores, copying 4 integers (or 4 floats, or 2 doubles) per instruction.

### Scalar Broadcast

Combine an array with a scalar value. The scalar is applied to every element:

```basic
DIM temperatures(365) AS SINGLE
DIM adjusted(365) AS SINGLE

' Add a constant to every element
adjusted() = temperatures() + 1.5

' Scale every element
adjusted() = temperatures() * 1.8

' Scalar on the left works too
adjusted() = 32.0 + temperatures() * 1.8
```

### Array Fill

Assign a single value to every element of an array:

```basic
DIM scores(100) AS INTEGER
DIM weights(100) AS SINGLE

scores() = 0          ' zero the entire array
weights() = 1.0       ' fill with 1.0
```

This is much faster than a loop, especially for large arrays. The compiler uses NEON to broadcast the value across a 128-bit register and store 4 (or more) elements at once.

### Negation

Negate every element:

```basic
DIM velocity(100) AS SINGLE
DIM reversed(100) AS SINGLE

reversed() = -velocity()
```

---

## Supported Array Types

Array expressions work with all numeric array types:

| Element Type | Size | Elements per NEON Register | SIMD Benefit |
|---|---|---|---|
| `BYTE` | 8-bit | 16 | Excellent |
| `SHORT` | 16-bit | 8 | Excellent |
| `INTEGER` | 32-bit | 4 | Very good |
| `SINGLE` | 32-bit float | 4 | Very good |
| `LONG` | 64-bit | 2 | Good |
| `DOUBLE` | 64-bit float | 2 | Good |
| SIMD-eligible UDT | 128-bit | 1 | Good |

Smaller types pack more elements into each NEON register, so `BYTE` and `SHORT` arrays see the biggest throughput gains.

### UDT Arrays

Array expressions also work with arrays of SIMD-eligible User-Defined Types (UDTs that have all fields the same numeric type):

```basic
TYPE Vec4
  X AS SINGLE
  Y AS SINGLE
  Z AS SINGLE
  W AS SINGLE
END TYPE

DIM positions(1000) AS Vec4
DIM velocities(1000) AS Vec4

' Add velocity to position for every element
positions() = positions() + velocities()
```

Each `Vec4` fits in one 128-bit NEON register. The loop processes one complete vector per iteration with a single `fadd v0.4s, v0.4s, v1.4s` instruction.

### String Arrays

String arrays (`STRING$`) are **not supported** for array expressions. Strings use reference counting and variable-length storage, which don't map to SIMD operations.

---

## Complete Examples

### Example 1: Vector Addition

```basic
' Add two float arrays
DIM A(100) AS SINGLE
DIM B(100) AS SINGLE
DIM C(100) AS SINGLE

' Initialize
FOR i = 0 TO 100
  A(i) = i * 1.5
  B(i) = i * 0.5
NEXT i

' Array expression — one line instead of a loop
C() = A() + B()

' Verify
PRINT "C(0) = "; C(0)     ' 0.0
PRINT "C(10) = "; C(10)   ' 20.0
PRINT "C(100) = "; C(100) ' 200.0
```

### Example 2: Scaling and Offset

```basic
' Convert Celsius to Fahrenheit for an entire dataset
DIM celsius(365) AS SINGLE
DIM fahrenheit(365) AS SINGLE

' ... populate celsius() with daily temperatures ...

' One expression does the entire conversion
fahrenheit() = celsius() * 1.8 + 32.0
```

### Example 3: Physics Simulation

```basic
TYPE Vec4
  X AS SINGLE
  Y AS SINGLE
  Z AS SINGLE
  W AS SINGLE
END TYPE

DIM pos(10000) AS Vec4
DIM vel(10000) AS Vec4
DIM acc(10000) AS Vec4

' ... initialize particles ...

' Physics update — three array expressions replace nested loops
vel() = vel() + acc()
pos() = pos() + vel()

' Damping
vel() = vel() * 0.99
```

### Example 4: Image Processing

```basic
' Brighten an image stored as integer pixel values
DIM pixels(1920 * 1080) AS INTEGER
DIM brightened(1920 * 1080) AS INTEGER

brightened() = pixels() + 20

' Blend two images (50/50 average)
DIM imageA(1920 * 1080) AS INTEGER
DIM imageB(1920 * 1080) AS INTEGER
DIM blended(1920 * 1080) AS INTEGER

' Each pixel is the average of the two source pixels
blended() = imageA() / 2 + imageB() / 2
```

### Example 5: Array Initialization Patterns

```basic
DIM data(1000) AS DOUBLE

' Zero everything
data() = 0

' Fill with a sentinel value
data() = -1.0

' Copy from a template
DIM template(1000) AS DOUBLE
' ... set up template ...
data() = template()
```

---

## How It Works

When the compiler encounters an array expression like `C() = A() + B()`, it:

1. **Verifies compatibility** — all arrays must have the same element type and compatible dimensions
2. **Checks SIMD eligibility** — determines whether the element type maps to NEON registers
3. **Emits a vectorized loop** — generates a pointer-based loop that processes elements in bulk

On ARM64, the generated loop uses NEON 128-bit registers. For `SINGLE` arrays, this processes 4 elements per iteration:

```
loop:
    ldr   q28, [src_a], #16     ; load 4 floats from A
    ldr   q29, [src_b], #16     ; load 4 floats from B
    fadd  v28.4s, v28.4s, v29.4s ; add all 4 in parallel
    str   q28, [dest], #16      ; store 4 results to C
    cmp   dest, end
    b.lt  loop
```

A scalar remainder loop handles any leftover elements when the array length isn't a multiple of the SIMD lane count.

### Comparison with FOR Loops

The compiler also vectorizes explicit FOR loops that follow recognizable patterns:

```basic
' These produce the same machine code:

' Array expression
C() = A() + B()

' Explicit FOR loop (auto-vectorized)
FOR i = 0 TO 100
  C(i) = A(i) + B(i)
NEXT i
```

The array expression form is preferred because:
- It's shorter and more readable
- It communicates intent more clearly
- The compiler doesn't need to analyze loop structure to find the pattern
- There's no risk of accidental loop-carried dependencies

---

## Rules and Constraints

### Arrays Must Be Compatible

All arrays in an expression must have the same element type:

```basic
DIM A(100) AS SINGLE
DIM B(100) AS DOUBLE

' ERROR: mismatched types
C() = A() + B()
```

### Division by Zero

Array division follows the same rules as scalar division. For integer arrays, division by zero in any element will cause a runtime error. For floating-point arrays, division by zero produces infinity or NaN per IEEE 754 rules.

### In-Place Operations

You can use the same array on both sides of the assignment:

```basic
DIM A(100) AS SINGLE

A() = A() + 1.0      ' increment every element
A() = A() * 2.0      ' double every element
A() = A() * A()      ' square every element
```

This is safe because the compiler processes elements sequentially (or in non-overlapping SIMD chunks).

### Integer Division

Integer division truncates toward zero, just like scalar integer division in BASIC:

```basic
DIM A(10) AS INTEGER
DIM B(10) AS INTEGER
DIM C(10) AS INTEGER

' Integer division — results are truncated
C() = A() / B()    ' same as C(i) = A(i) \ B(i) for each element
```

> **Note:** NEON hardware integer division is only available for floating-point lanes. For integer arrays, the compiler uses a scalar fallback for division. Addition, subtraction, and multiplication still use NEON.

---

## Performance

### Throughput Gains

The speedup depends on the element type and operation:

| Element Type | Elements per NEON Op | Theoretical Speedup |
|---|---|---|
| `BYTE` | 16 | Up to 16× |
| `SHORT` | 8 | Up to 8× |
| `INTEGER` / `SINGLE` | 4 | Up to 4× |
| `LONG` / `DOUBLE` | 2 | Up to 2× |

Real-world gains are typically 60–80% of theoretical due to memory bandwidth limits.

### When to Use Array Expressions

Array expressions shine when:
- **Large arrays** — the overhead of the loop setup is amortized over many elements
- **Simple operations** — arithmetic on contiguous arrays maps perfectly to SIMD
- **Hot loops** — replacing inner-loop array operations with expressions saves instruction count

For small arrays (under ~16 elements), the overhead of setting up the SIMD loop may exceed the benefit. The compiler will fall back to scalar code when appropriate.

### Disabling SIMD

If you need to disable NEON acceleration (for debugging or compatibility testing), use:

```basic
OPTION NO_NEON
```

Or set the environment variable:

```bash
ENABLE_NEON_LOOP=0 ./fbc_qbe program.bas
```

The compiler will generate scalar loops instead. The array expression syntax still works — only the generated code changes.

---

## Future Extensions

### Reduction Functions

Functions that reduce an array to a single scalar value:

```basic
total = SUM(A())        ' sum of all elements
mx = MAX(A())           ' maximum element
mn = MIN(A())           ' minimum element
dp = DOT(A(), B())      ' dot product
avg = AVG(A())          ' average value
```

### Unary Functions

Element-wise application of math functions:

```basic
B() = ABS(A())          ' absolute value of every element
B() = SQR(A())          ' square root of every element
```

### Compound Expressions

Multiple operations in a single expression, potentially using fused multiply-add (FMLA) on ARM64:

```basic
D() = A() + B() * C()   ' fused multiply-add
D() = A() * B() + C()   ' also eligible for FMLA
```

---

## Quick Reference

| Expression | Meaning |
|---|---|
| `C() = A() + B()` | Element-wise addition |
| `C() = A() - B()` | Element-wise subtraction |
| `C() = A() * B()` | Element-wise multiplication |
| `C() = A() / B()` | Element-wise division |
| `B() = A()` | Whole-array copy |
| `B() = A() + 5` | Scalar broadcast (add 5 to every element) |
| `B() = A() * 2.0` | Scalar broadcast (multiply every element by 2) |
| `A() = 0` | Fill entire array with zero |
| `A() = value` | Fill entire array with value |
| `B() = -A()` | Negate every element |
| `A() = A() + 1` | In-place increment |

## Compatibility

| Platform | SIMD Acceleration | Scalar Fallback |
|---|---|---|
| macOS ARM64 (Apple Silicon) | ✅ NEON | ✅ |
| Linux ARM64 | ✅ NEON | ✅ |
| x86_64 (Intel/AMD) | ❌ (future SSE/AVX) | ✅ |
| RISC-V | ❌ (future RVV) | ✅ |

Array expressions work on all platforms. SIMD acceleration is currently available on ARM64 only. On other platforms, the compiler generates an efficient scalar loop.

---

## Tips

1. **Use `()` consistently** — always include the empty parentheses to make array operations obvious in your code.

2. **Prefer array expressions over FOR loops** — the compiler can vectorize both, but array expressions are clearer and easier to optimize.

3. **Keep element types consistent** — don't mix `SINGLE` and `DOUBLE` arrays in the same expression. Convert first if needed.

4. **Use `SINGLE` for best throughput** — 32-bit floats pack 4 per NEON register versus 2 for `DOUBLE`. Use `SINGLE` unless you need the precision.

5. **Array fill is fast** — `A() = 0` is significantly faster than a FOR loop for zeroing large arrays.

6. **Check your types** — array expressions require matching element types. The compiler will report an error if types don't match.

---

## Further Reading

- [NEON SIMD Support](neon-simd-support.md) — how automatic vectorization works under the hood
- [Classes and Objects](classes-and-objects.md) — UDTs that benefit from SIMD
- [Quick Reference](../docs/FasterBASIC_QuickRef.md) — complete syntax reference