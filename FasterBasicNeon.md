# ARM64 NEON SIMD Design for FasterBASIC UDT Vectorization

**Status:** Design Document  
**Author:** FasterBASIC Compiler Team  
**Date:** 2026  
**Depends on:** MADD peephole fixes (7275aee), LDP/STP + indexed addressing (ad34474)

---

## 1. Executive Summary

This document describes a design for packing eligible User-Defined Types (UDTs) into
ARM64 NEON 128-bit Q registers and generating vectorized NEON instructions for
arithmetic, copy, and reduction operations — with particular emphasis on **arrays of
SIMD-eligible UDTs**, where the payoff is transformative.

A UDT like:

```basic
TYPE Vec4
    x AS INTEGER
    y AS INTEGER
    z AS INTEGER
    w AS INTEGER
END TYPE
```

packs exactly into a single Q register (128 bits = 4 × 32-bit lanes). An array
operation such as:

```basic
DIM positions(1000) AS Vec4
DIM velocities(1000) AS Vec4

FOR i = 0 TO 999
    positions(i).x = positions(i).x + velocities(i).x
    positions(i).y = positions(i).y + velocities(i).y
    positions(i).z = positions(i).z + velocities(i).z
    positions(i).w = positions(i).w + velocities(i).w
NEXT i
```

currently generates **16 scalar instructions per iteration** (4 loads + 4 loads +
4 adds + 4 stores). With NEON, this becomes **4 instructions per iteration**:

```asm
ldr   q0, [x0]              ; load positions(i) — all 4 fields
ldr   q1, [x1]              ; load velocities(i) — all 4 fields
add   v0.4s, v0.4s, v1.4s   ; parallel add across all 4 lanes
str   q0, [x0]              ; store result back
```

With loop unrolling and LDP/STP on Q registers, this can reach **3 instructions
per 2 elements**:

```asm
ldp   q0, q1, [x0]          ; load positions(i) and positions(i+1)
ldp   q2, q3, [x1]          ; load velocities(i) and velocities(i+1)
add   v0.4s, v0.4s, v2.4s
add   v1.4s, v1.4s, v3.4s
stp   q0, q1, [x0]          ; store both results
```

---

## 2. SIMD Eligibility Rules

### 2.1 Qualifying UDTs

A UDT is SIMD-eligible when ALL of the following hold:

| Rule | Rationale |
|------|-----------|
| All fields are the **same numeric base type** | NEON lanes must be homogeneous |
| No STRING, UNICODE, USER_DEFINED, or OBJECT fields | These are pointers; arithmetic is meaningless |
| Total packed size ≤ 128 bits | Must fit in a single Q register |
| Field count is a power of 2 (2, 4, 8, 16) or 3 with padding | NEON operates on fixed lane widths |

### 2.2 Lane Configurations

| Fields | Base Type | Bits/Field | Total Bits | NEON Arrangement | Register |
|--------|-----------|------------|------------|------------------|----------|
| 2 | DOUBLE | 64 | 128 | `v.2d` | Q (full) |
| 2 | LONG/ULONG | 64 | 128 | `v.2d` | Q (full) |
| 2 | INTEGER | 32 | 64 | `v.2s` | D (half) |
| 2 | SINGLE | 32 | 64 | `v.2s` | D (half) |
| 2 | SHORT | 16 | 32 | `v.2h` | S (quarter) |
| 4 | INTEGER | 32 | 128 | `v.4s` | Q (full) |
| 4 | SINGLE | 32 | 128 | `v.4s` | Q (full) |
| 4 | SHORT | 16 | 64 | `v.4h` | D (half) |
| 8 | SHORT | 16 | 128 | `v.8h` | Q (full) |
| 8 | BYTE | 8 | 64 | `v.8b` | D (half) |
| 16 | BYTE | 8 | 128 | `v.16b` | Q (full) |
| 3 | INTEGER | 32 | 96→128* | `v.4s` | Q (padded) |
| 3 | SINGLE | 32 | 96→128* | `v.4s` | Q (padded) |

*3-field types are padded to 4 lanes with a zero lane. This wastes 25% of register
width but enables full Q-register operations. The padding lane is zeroed on load
and masked/ignored on store.

### 2.3 Existing Scaffolding

The semantic analyzer already has SIMD classification infrastructure:

- `TypeDeclarationStatement::SIMDType` enum (`NONE`, `PAIR`, `QUAD`)
- `TypeSymbol::simdType` field — propagated through the symbol table
- Detection logic in `processTypeDeclarationStatement()` for 2×DOUBLE and 4×SINGLE
- `analyzeArrayExpression()` for whole-array SIMD operation detection

This design extends that foundation to cover all eligible configurations and
generate actual NEON code.

### 2.4 Extended SIMDType Enum

Replace the current three-value enum with a richer classification:

```cpp
enum class SIMDType {
    NONE,           // Not SIMD-capable
    
    // Full Q register (128-bit) configurations
    V2D,            // 2 × DOUBLE/LONG    (v.2d) — 128 bits
    V4S,            // 4 × SINGLE/INTEGER (v.4s) — 128 bits
    V8H,            // 8 × SHORT          (v.8h) — 128 bits
    V16B,           // 16 × BYTE          (v.16b) — 128 bits
    
    // Half register (64-bit, D register) configurations
    V2S,            // 2 × SINGLE/INTEGER (v.2s) — 64 bits
    V4H,            // 4 × SHORT          (v.4h) — 64 bits
    V8B,            // 8 × BYTE           (v.8b) — 64 bits
    
    // Padded configurations (3 fields + 1 padding lane)
    V4S_PAD1,       // 3 × INTEGER/SINGLE padded to v.4s
};
```

### 2.5 SIMDInfo Descriptor

Computed at semantic analysis time and stored on `TypeSymbol`:

```cpp
struct SIMDInfo {
    SIMDType  type;             // Lane configuration
    int       laneCount;        // Number of active lanes (2, 3, 4, 8, 16)
    int       physicalLanes;    // Lanes in register (may differ from laneCount for padded)
    int       laneBitWidth;     // Bits per lane (8, 16, 32, 64)
    int       totalBytes;       // Storage size in bytes (8 or 16)
    bool      isFullQ;          // true = 128-bit Q register, false = 64-bit D
    bool      isPadded;         // true if laneCount < physicalLanes
    bool      isFloatingPoint;  // true if lanes are SINGLE/DOUBLE
    BaseType  laneType;         // The uniform base type of each lane
    
    // ARM64 arrangement specifier for asm emission
    const char* arrangement() const;   // Returns "4s", "2d", "8h", etc.
    const char* regPrefix() const;     // Returns "q" for 128-bit, "d" for 64-bit
};
```

---

## 3. Architecture Overview

```
┌──────────────────────────────────────────────────────────────────────┐
│                         FasterBASIC Source                          │
│  TYPE Vec4                   DIM pos(1000) AS Vec4                  │
│    x AS INTEGER              FOR i = 0 TO 999                      │
│    y AS INTEGER                pos(i).x = pos(i).x + vel(i).x     │
│    z AS INTEGER                ...                                  │
│    w AS INTEGER              NEXT i                                 │
│  END TYPE                                                           │
└──────────────┬───────────────────────────────┬───────────────────────┘
               │                               │
               ▼                               ▼
┌──────────────────────────┐    ┌──────────────────────────────────────┐
│   Semantic Analyzer      │    │         AST / CFG                    │
│                          │    │                                      │
│  • Classify UDTs         │    │  • FOR loops with UDT array access   │
│  • Set SIMDInfo on       │    │  • Element-wise assignment patterns  │
│    TypeSymbol             │    │  • Reduction expressions             │
│  • Tag arrays of SIMD    │    │                                      │
│    UDTs                   │    │                                      │
└──────────┬───────────────┘    └──────────────┬───────────────────────┘
           │                                   │
           ▼                                   ▼
┌──────────────────────────────────────────────────────────────────────┐
│                    CodeGen V2 (ASTEmitter)                          │
│                                                                      │
│  ┌─────────────────────┐   ┌────────────────────────────────────┐   │
│  │  Scalar Path        │   │  NEON Path                         │   │
│  │  (existing)         │   │  (new)                             │   │
│  │                     │   │                                    │   │
│  │  Field-by-field     │   │  • Bulk copy (ldr/str q)           │   │
│  │  loads, stores,     │   │  • Element-wise ops (add v.4s)     │   │
│  │  arithmetic         │   │  • Loop vectorization              │   │
│  │                     │   │  • Reductions (addv, faddp)        │   │
│  │  → Standard QBE IL  │   │  → QBE IL with NEON directives    │   │
│  └─────────────────────┘   └────────────────────────────────────┘   │
│                                                                      │
│  Decision: Use NEON path when SIMDInfo.type != NONE and the          │
│  operation pattern matches a vectorizable template.                  │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         QBE Backend                                  │
│                                                                      │
│  ┌────────────────────┐    ┌─────────────────────────────────────┐   │
│  │  Standard Pipeline  │    │  NEON Extension                     │   │
│  │                     │    │                                     │   │
│  │  parse → isel →     │    │  Custom opcodes in ops.h:           │   │
│  │  regalloc → emit    │    │    Oneonld, Oneonst, Oneonadd, ... │   │
│  │                     │    │                                     │   │
│  │  Scalar W/X/S/D     │    │  isel.c: pass-through               │   │
│  │  registers          │    │  emit.c: emit NEON mnemonics        │   │
│  │                     │    │  Reserved V regs: V28-V30           │   │
│  └────────────────────┘    └─────────────────────────────────────┘   │
│                                                                      │
└──────────────────────────────────────┬───────────────────────────────┘
                                       │
                                       ▼
┌──────────────────────────────────────────────────────────────────────┐
│                      ARM64 Assembly Output                           │
│                                                                      │
│  ldr   q28, [x19, x0]          ; NEON load full UDT                 │
│  ldr   q29, [x20, x0]          ; NEON load full UDT                 │
│  add   v28.4s, v28.4s, v29.4s  ; NEON parallel add                 │
│  str   q28, [x19, x0]          ; NEON store full UDT               │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## 4. Implementation Strategy

The design uses **custom QBE opcodes** rather than inline assembly strings. This
keeps the IL well-formed, allows QBE's infrastructure (block layout, branch
resolution, debug info) to work normally, and confines the NEON knowledge to
the ARM64 backend where it belongs.

### 4.1 Strategy: Custom QBE Opcodes

Add NEON operations to `ops.h` as target-specific opcodes. These are emitted by
the FasterBASIC codegen and handled by the ARM64 `isel.c` and `emit.c`.

**Why not inline assembly?**  
QBE has no inline asm facility. Adding one would require parsing arbitrary
strings through the register allocator, which is far more invasive than adding
well-typed opcodes.

**Why not emitter-level pattern matching?**  
The emitter sees post-regalloc scalar instructions. Detecting that four
consecutive scalar adds on adjacent stack slots should become a vector add is
fragile after register allocation has reordered and interleaved instructions.
The decision must be made in the frontend where the type information exists.

**Why not bypass QBE entirely for NEON sections?**  
The NEON operations interact with surrounding scalar code (loading addresses,
computing indices, branching). Keeping them in the QBE IL ensures they're
placed correctly relative to labels, jumps, and register spills.

### 4.2 Reserved NEON Registers

QBE's register allocator uses V0-V30 as scalar floating-point registers.
To avoid conflicts, we reserve a small pool of V registers for NEON scratch use:

| Register | Purpose |
|----------|---------|
| V28 (q28) | NEON scratch operand 1 / result |
| V29 (q29) | NEON scratch operand 2 |
| V30 (q30) | NEON scratch operand 3 / accumulator |

These are removed from `arm64_rsave[]` so the register allocator never assigns
them to scalar values. Three registers suffice because NEON operations in this
design are memory-to-memory: load into scratch, operate, store back. There is
no need to keep UDT values live in vector registers across many instructions.

For the unrolled array loop case (processing 2 elements per iteration), we need
4 scratch registers. V27 can be added to the reserved pool if needed, or the
unroll factor can be limited to 1.

**Change in `targ.c`:**

```c
int arm64_rsave[] = {
    R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,
    R8,  R9,  R10, R11, R12, R13, R14, R15,
    IP0, IP1, R18, LR,
    V0,  V1,  V2,  V3,  V4,  V5,  V6,  V7,
    V16, V17, V18, V19, V20, V21, V22, V23,
    V24, V25, V26, V27,
    /* V28, V29, V30 reserved for NEON */
    -1
};
```

### 4.3 New QBE Opcodes

Added to `ops.h` as architecture-specific operations (similar to `Oacmp`, `Oafcmp`):

```c
/* ARM64 NEON vector operations (target-specific) */
O(neonldr,  T(l,e,e,e, x,e,e,e), ...) /* vector load:  neonldr addr          → V28 */
O(neonstr,  T(e,e,e,e, l,e,e,e), ...) /* vector store: neonstr addr          ← V28 */
O(neonadd,  T(e,e,e,e, e,e,e,e), ...) /* vector add:   V28 = V28 + V29            */
O(neonsub,  T(e,e,e,e, e,e,e,e), ...) /* vector sub:   V28 = V28 - V29            */
O(neonmul,  T(e,e,e,e, e,e,e,e), ...) /* vector mul:   V28 = V28 * V29            */
O(neonldr2, T(l,e,e,e, x,e,e,e), ...) /* vector load:  neonldr2 addr         → V29 */
O(neonstr2, T(e,e,e,e, l,e,e,e), ...) /* vector store: neonstr2 addr         ← V29 */
O(neonaddv, T(e,e,e,e, e,e,e,e), ...) /* horiz sum:    result = sum(V28 lanes)     */
```

The `cls` field on each instruction encodes the arrangement:
- `Kw` → `.4s` (4×32-bit integer) or `.2s` (2×32-bit)
- `Kl` → `.2d` (2×64-bit integer)
- `Ks` → `.4s` (4×32-bit float) — same encoding, different semantics
- `Kd` → `.2d` (2×64-bit float)

An additional immediate argument (via `arg[1]` as `RCon`) carries the lane
count to disambiguate `.4s` vs `.2s`.

### 4.4 Emitter Handling

In `arm64/emit.c`, the NEON opcodes are handled in `emitins()`:

```c
case Oneonldr:
    /* Load 128 bits from memory into V28 */
    fprintf(e->f, "\tldr\tq28, [%s]\n", rname(i->arg[0].val, Kl));
    break;
case Oneonldr2:
    /* Load 128 bits from memory into V29 */
    fprintf(e->f, "\tldr\tq29, [%s]\n", rname(i->arg[0].val, Kl));
    break;
case Oneonadd:
    /* cls determines arrangement */
    fprintf(e->f, "\tadd\tv28.%s, v28.%s, v29.%s\n", arr, arr, arr);
    break;
case Oneonstr:
    /* Store 128 bits from V28 to memory */
    fprintf(e->f, "\tstr\tq28, [%s]\n", rname(i->arg[0].val, Kl));
    break;
case Oneonaddv:
    /* Horizontal sum: addv s28, v28.4s  then  fmov w_dest, s28 */
    fprintf(e->f, "\taddv\ts28, v28.4s\n");
    fprintf(e->f, "\tfmov\t%s, s28\n", rname(i->to.val, Kw));
    break;
```

The NEON instructions don't go through register allocation for the vector
registers (V28-V30 are reserved). The address operands (base pointers, indices)
are normal GPR temporaries that DO go through regalloc.

---

## 5. Operations Catalog

### 5.1 Tier 1: Bulk Copy (Highest Impact, Simplest)

**Pattern:** UDT-to-UDT assignment for SIMD-eligible types.

```basic
DIM a AS Vec4, b AS Vec4
b = a                        ' or field-by-field equivalent
```

**Current codegen** (from `emitUDTCopyFieldByField`):

```
%t1 =w loadw %src_addr
storew %t1, %dst_addr
%t2 =w loadw %src_addr_plus_4
storew %t2, %dst_addr_plus_4
%t3 =w loadw %src_addr_plus_8
storew %t3, %dst_addr_plus_8
%t4 =w loadw %src_addr_plus_12
storew %t4, %dst_addr_plus_12
```

8 instructions.

**NEON codegen:**

```
neonldr %src_addr
neonstr %dst_addr
```

2 instructions → **4× reduction**.

**Array element copy** benefits identically:

```basic
positions(j) = positions(i)
```

### 5.2 Tier 2: Element-Wise Arithmetic on Single UDTs

**Pattern:** All fields of result assigned from same operation on corresponding
fields of two operands.

```basic
c.x = a.x + b.x
c.y = a.y + b.y
c.z = a.z + b.z
c.w = a.w + b.w
```

**NEON codegen:**

```
neonldr  %addr_a       ; V28 ← a
neonldr2 %addr_b       ; V29 ← b
neonadd                 ; V28 ← V28 + V29
neonstr  %addr_c       ; c ← V28
```

4 instructions instead of 12 → **3× reduction**.

Supported operations:

| BASIC Op | NEON Integer | NEON Float | Notes |
|----------|-------------|------------|-------|
| `+` | `add v.Ns` | `fadd v.Nd` | |
| `-` | `sub v.Ns` | `fsub v.Nd` | |
| `*` | `mul v.Ns` | `fmul v.Nd` | |
| `/` | — | `fdiv v.Nd` | Integer division has no direct NEON instruction |
| negate | `neg v.Ns` | `fneg v.Nd` | Unary |
| `AND` | `and v.16b` | — | Bitwise, integer only |
| `OR` | `orr v.16b` | — | Bitwise, integer only |
| `XOR` | `eor v.16b` | — | Bitwise, integer only |

Integer division falls back to scalar — NEON has no `sdiv` for vectors.

### 5.3 Tier 3: Array Loop Vectorization (Highest Payoff)

**Pattern:** FOR loop iterating over array indices, with body performing
element-wise operations on SIMD-eligible UDT array elements.

```basic
FOR i = 0 TO n
    result(i).x = a(i).x + b(i).x
    result(i).y = a(i).y + b(i).y
    result(i).z = a(i).z + b(i).z
    result(i).w = a(i).w + b(i).w
NEXT i
```

This is where the design delivers its maximum impact.

#### 5.3.1 Detection

The ASTEmitter recognizes this pattern by checking:

1. **Loop structure:** FOR loop with integer index, constant step of 1 (or -1).
2. **Body:** All statements are assignments to fields of `result(i)`.
3. **Fields:** Every field of the SIMD-eligible UDT is assigned.
4. **RHS:** Each assignment's RHS is the same binary operation applied to
   corresponding fields of `a(i)` and `b(i)`.
5. **No side effects:** No function calls, no other array accesses, no
   branches in the loop body.

When detected, the entire loop body is replaced with NEON instructions, and
the loop itself may be unrolled.

#### 5.3.2 Generated Code

**Basic (no unroll):**

```asm
; Precompute: x0 = &result.data, x1 = &a.data, x2 = &b.data
; x3 = i * 16 (byte offset), x4 = n * 16 (end offset)
.Lloop:
    ldr   q28, [x1, x3]          ; load a(i)
    ldr   q29, [x2, x3]          ; load b(i)
    add   v28.4s, v28.4s, v29.4s ; result = a + b
    str   q28, [x0, x3]          ; store result(i)
    add   x3, x3, #16            ; i += 1 (in bytes)
    cmp   x3, x4
    b.lt  .Lloop
```

7 instructions per iteration (4 NEON + 3 loop control).

**Unrolled ×2:**

```asm
.Lloop:
    ldp   q28, q29, [x1, x3]     ; load a(i), a(i+1)
    ldp   q30, q27, [x2, x3]     ; load b(i), b(i+1)
    add   v28.4s, v28.4s, v30.4s ; result(i)
    add   v29.4s, v29.4s, v27.4s ; result(i+1)
    stp   q28, q29, [x0, x3]     ; store result(i), result(i+1)
    add   x3, x3, #32
    cmp   x3, x4
    b.lt  .Lloop
; remainder loop for odd count
```

8 instructions per 2 iterations = **4 instructions per element** (vs 16 scalar).

**Unrolled ×4 (with 6 scratch registers):**

Possible but requires reserving V25-V30. Diminishing returns for code size.
×2 unroll is the sweet spot.

#### 5.3.3 Alignment Considerations

NEON `ldr q` and `str q` do not require 16-byte alignment on ARMv8 (they
handle unaligned access in hardware), but aligned accesses are faster.

For arrays of SIMD-eligible UDTs:
- Element size equals the NEON register width (16 bytes for Q, 8 for D).
- Array base address should be 16-byte aligned.
- The `alloc16` QBE directive ensures stack alignment.
- For heap-allocated arrays (via `array_create`), the runtime already uses
  `malloc` which returns 16-byte aligned memory on ARM64.

#### 5.3.4 Loop Vectorization Constraints

A loop is vectorizable when:

| Constraint | Why |
|------------|-----|
| Index step = 1 or -1 | Predictable stride for offset computation |
| All array accesses use the loop index | No cross-iteration dependencies |
| No function calls in body | May clobber V28-V30 |
| No string operations | Strings are pointers, not vectorizable |
| All accessed arrays are of the same SIMD-eligible UDT | Lane configurations must match |
| No early exit (EXIT FOR) | Loop count must be known at entry or handled by remainder |
| Body is pure element-wise | No operations that mix fields (e.g., `a.x + a.y`) within an element |

Cross-field operations (like dot product) are handled separately as reductions
(Tier 4), not as loop vectorization.

### 5.4 Tier 4: Horizontal Reductions

**Pattern:** Combining all fields of a single UDT into a scalar result.

```basic
DIM v AS Vec4
sum = v.x + v.y + v.z + v.w
```

**NEON codegen:**

```asm
ldr    q28, [x0]         ; load all 4 fields
addv   s28, v28.4s       ; horizontal add → s28
fmov   w0, s28           ; move to integer register
```

3 instructions instead of 3 loads + 3 adds = 6.

**Supported reductions:**

| Reduction | Integer NEON | Float NEON | Notes |
|-----------|-------------|------------|-------|
| SUM | `addv sN, v.4s` | `faddp` pairs | Float needs pairwise reduction chain |
| MIN | `sminv sN, v.4s` / `uminv` | `fminp` pairs | |
| MAX | `smaxv sN, v.4s` / `umaxv` | `fmaxp` pairs | |

**Array-wide reduction** (sum across all elements of an array):

```basic
DIM values(100) AS Vec4
total = 0
FOR i = 0 TO 99
    total = total + values(i).x + values(i).y + values(i).z + values(i).w
NEXT i
```

This becomes a vectorized loop with horizontal sum per element accumulated
into a scalar:

```asm
movi  v30.4s, #0              ; accumulator = {0,0,0,0}
.Lloop:
    ldr   q28, [x0, x3]       ; load values(i)
    add   v30.4s, v30.4s, v28.4s ; accumulate lane-wise
    add   x3, x3, #16
    cmp   x3, x4
    b.lt  .Lloop
addv  s30, v30.4s              ; horizontal sum of accumulator
fmov  w0, s30                  ; total
```

This accumulates in lanes and does a single horizontal sum at the end,
which is significantly more efficient than per-element horizontal sums.

### 5.5 Tier 5: Scalar Broadcast and Initialization

**Pattern:** Setting all fields of a UDT to the same value.

```basic
DIM v AS Vec4
v.x = 0 : v.y = 0 : v.z = 0 : v.w = 0
```

**NEON codegen:**

```asm
movi  v28.4s, #0         ; zero all lanes
str   q28, [x0]          ; store
```

2 instructions instead of 4 stores.

For non-zero broadcast:

```basic
v.x = 42 : v.y = 42 : v.z = 42 : v.w = 42
```

```asm
mov   w8, #42
dup   v28.4s, w8          ; broadcast scalar to all lanes
str   q28, [x0]
```

3 instructions instead of 4 stores.

**Array initialization** (all elements to same value):

```basic
FOR i = 0 TO 99
    arr(i).x = 0 : arr(i).y = 0 : arr(i).z = 0 : arr(i).w = 0
NEXT i
```

```asm
movi  v28.4s, #0
mov   x3, #0
.Lloop:
    str   q28, [x0, x3]
    add   x3, x3, #16
    cmp   x3, x4
    b.lt  .Lloop
```

4 instructions per iteration instead of 4 stores + 3 loop overhead = 7.
With STP unrolling: 2 elements per 5 instructions.

---

## 6. Detailed Implementation Plan

### Phase 1: Foundation (SIMD Classification + Bulk Copy)

**Estimated scope:** ~400 LOC across 4 files  
**Impact:** Every UDT copy of eligible types becomes 2 instructions  

#### 6.1.1 Extend SIMDType Enum

**File:** `fsh/FasterBASICT/src/fasterbasic_ast.h`

- Replace `SIMDType { NONE, PAIR, QUAD }` with the extended enum from §2.4.
- Add `SIMDInfo` struct.

**File:** `fsh/FasterBASICT/src/fasterbasic_semantic.h`

- Add `SIMDInfo simdInfo` field to `TypeSymbol` (alongside existing `simdType`
  for backward compat).

#### 6.1.2 Generalize SIMD Detection

**File:** `fsh/FasterBASICT/src/fasterbasic_semantic.cpp`

- Rewrite the detection logic in `processTypeDeclarationStatement()`.
- Check: all fields same base type, no strings/UDTs, total ≤ 128 bits,
  lane count is 2/3/4/8/16.
- Populate `SIMDInfo` struct.

```cpp
SIMDInfo classifySIMDType(const TypeSymbol& udt) {
    SIMDInfo info = {};
    info.type = SIMDType::NONE;
    
    if (udt.fields.empty() || udt.fields.size() > 16) return info;
    
    // All fields must be same base numeric type
    BaseType lane = udt.fields[0].typeDesc.baseType;
    for (const auto& f : udt.fields) {
        if (f.typeDesc.baseType != lane) return info;
    }
    
    // Must be numeric, not string/UDT
    if (!TypeDescriptor(lane).isInteger() && !TypeDescriptor(lane).isFloat())
        return info;
    
    int bits = TypeDescriptor(lane).getBitWidth();
    int count = (int)udt.fields.size();
    int totalBits = count * bits;
    
    if (totalBits > 128) return info;
    
    // Classify
    info.laneCount = count;
    info.laneBitWidth = bits;
    info.laneType = lane;
    info.isFloatingPoint = TypeDescriptor(lane).isFloat();
    
    // Determine arrangement and physical lanes
    if (count == 3 && bits == 32) {
        // 3 fields padded to 4 lanes
        info.type = SIMDType::V4S_PAD1;
        info.physicalLanes = 4;
        info.totalBytes = 16;
        info.isFullQ = true;
        info.isPadded = true;
    } else {
        info.physicalLanes = count;
        info.totalBytes = (count * bits) / 8;
        info.isFullQ = (info.totalBytes == 16);
        info.isPadded = false;
        // ... map to SIMDType enum based on count + bits
    }
    
    return info;
}
```

#### 6.1.3 Add NEON Opcodes to QBE

**File:** `qbe_source/ops.h`

Add NEON opcodes after the existing target-specific operations. These are
gated to ARM64 only.

**File:** `qbe_source/arm64/isel.c`

Pass NEON opcodes through instruction selection unchanged (they're already
in their final form).

**File:** `qbe_source/arm64/emit.c`

Add cases in `emitins()` for each NEON opcode. Emit the corresponding
ARM64 NEON mnemonic using the reserved V28-V30 registers.

#### 6.1.4 Emit Bulk Copy as NEON

**File:** `fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp`

Modify `emitUDTCopyFieldByField()`:

```cpp
void ASTEmitter::emitUDTCopyFieldByField(...) {
    // Check if this UDT is SIMD-eligible
    SIMDInfo simd = typeManager_.getSIMDInfo(udtDef);
    if (simd.type != SIMDType::NONE && !hasStringFields(udtDef)) {
        // NEON bulk copy: 2 instructions instead of N load/store pairs
        builder_.emitComment("NEON bulk copy: " + udtDef.name);
        builder_.emitRaw("    neonldr " + sourceAddr);  // V28 ← source
        builder_.emitRaw("    neonstr " + targetAddr);   // target ← V28
        return;
    }
    
    // ... existing field-by-field path ...
}
```

#### 6.1.5 Storage Alignment

**File:** `fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp`

When allocating stack space for SIMD-eligible UDTs, use `alloc16` instead
of `alloc8`:

```cpp
std::string allocOp = (simdInfo.isFullQ) ? "alloc16" : "alloc8";
```

For arrays, ensure element size is padded to the NEON register width:

```cpp
int elemSize = (simdInfo.isFullQ) ? 16 : 8;
// Even if UDT fields sum to 12 bytes (3×INTEGER), allocate 16 per element
```

#### 6.1.6 Reserve V28-V30

**File:** `qbe_source/arm64/targ.c`

Remove V28, V29, V30 from `arm64_rsave[]`.

### Phase 2: Element-Wise Arithmetic

**Estimated scope:** ~600 LOC  
**Impact:** Arithmetic on all fields of a UDT → 4 instructions  

#### 6.2.1 Pattern Detection in ASTEmitter

Add a new method `tryEmitSIMDElementWiseOp()` that examines consecutive
LET statements to detect element-wise patterns.

The detection works at the statement level in `emitBlock()` or
`emitStatements()`:

```
When processing statements[k]:
  If stmt is LET to field F of UDT variable C:
    Look ahead at statements[k+1 .. k+N-1] where N = field count
    Check: do they assign to ALL other fields of C?
    Check: all RHS have same binary operator?
    Check: all RHS operands are corresponding fields of same UDTs A, B?
    If YES → emit NEON element-wise operation
              skip ahead by N statements
```

This lookahead is safe because BASIC statements within a line or block
execute sequentially with no interleaving.

#### 6.2.2 Emit NEON Arithmetic

```cpp
void ASTEmitter::emitSIMDElementWiseOp(
    const std::string& destAddr,
    const std::string& srcAAddr,
    const std::string& srcBAddr,
    const std::string& op,        // "add", "sub", "mul"
    const SIMDInfo& simd)
{
    builder_.emitComment("NEON element-wise " + op);
    builder_.emitRaw("    neonldr " + srcAAddr);
    builder_.emitRaw("    neonldr2 " + srcBAddr);
    
    // Map BASIC op to NEON opcode
    if (op == "add")
        builder_.emitRaw("    neonadd");
    else if (op == "sub")
        builder_.emitRaw("    neonsub");
    else if (op == "mul")
        builder_.emitRaw("    neonmul");
    
    builder_.emitRaw("    neonstr " + destAddr);
}
```

### Phase 3: Array Loop Vectorization

**Estimated scope:** ~1000 LOC  
**Impact:** Array operations → 4 instructions per element (instead of 16)  

This is the highest-payoff phase and the most complex.

#### 6.3.1 Loop Analysis

Add a `SIMDLoopAnalyzer` class that examines FOR loop bodies:

```cpp
struct SIMDLoopInfo {
    bool isVectorizable;
    
    // Loop bounds
    std::string indexVar;          // "i"
    int startVal, endVal, stepVal; // 0, 999, 1
    
    // Array operands
    struct ArrayOperand {
        std::string arrayName;     // "positions"
        std::string udtTypeName;   // "Vec4"
        SIMDInfo simdInfo;
        bool isReadOnly;           // true if only loaded, not stored
    };
    std::vector<ArrayOperand> operands;
    
    // Operation
    std::string operation;         // "add", "sub", "mul"
    int destArrayIndex;            // index into operands for destination
    int srcAArrayIndex;            // index into operands for source A
    int srcBArrayIndex;            // index into operands for source B
    
    // Or: operation = "copy" for simple array-to-array copy
    // Or: operation = "broadcast" for initialization
    
    // Unroll factor (1 or 2)
    int unrollFactor;
};

SIMDLoopInfo analyzeSIMDLoop(const ForStatement* forStmt,
                              const SymbolTable& symbols);
```

#### 6.3.2 Loop Code Generation

When a vectorizable loop is detected, the ASTEmitter replaces the entire
FOR/NEXT with NEON-optimized assembly:

```cpp
void ASTEmitter::emitSIMDLoop(const SIMDLoopInfo& info) {
    // 1. Emit loop prelude: compute base addresses and end offset
    //    base_A = array_get_data_ptr(A)
    //    base_B = array_get_data_ptr(B)
    //    base_C = array_get_data_ptr(C)
    //    end_offset = (endVal - startVal + 1) * elemSize
    //    byte_offset = startVal * elemSize
    
    // 2. Emit loop label
    
    // 3. Emit NEON body (unrolled)
    //    neonldr  [base_A + byte_offset]
    //    neonldr2 [base_B + byte_offset]
    //    neonadd
    //    neonstr  [base_C + byte_offset]
    //    byte_offset += elemSize
    
    // 4. Emit loop control
    //    cmp byte_offset, end_offset
    //    blt loop_label
    
    // 5. Emit remainder for non-divisible counts (if unrolled)
}
```

#### 6.3.3 Runtime Array Data Pointer Access

The current array implementation uses `array_get_address()` to get individual
element addresses. For NEON loops, we need direct access to the contiguous
data buffer. Add a runtime function:

```c
/* Returns pointer to the raw data buffer of a BasicArray.
 * Elements are stored contiguously at elem_size stride.
 */
void* array_get_data_ptr(BasicArray* arr);
```

This avoids calling `array_get_address()` inside the loop (which validates
bounds on each call).

For bounds checking, a single check before the loop suffices:

```c
array_check_range(arr, startIdx, endIdx);  // one-time validation
```

#### 6.3.4 Loop Patterns

**Pattern A: Element-wise binary operation**

```basic
FOR i = 0 TO n
    C(i).f1 = A(i).f1 OP B(i).f1
    C(i).f2 = A(i).f2 OP B(i).f2
    ...
NEXT i
```

**Pattern B: In-place update**

```basic
FOR i = 0 TO n
    A(i).f1 = A(i).f1 OP B(i).f1   ' A is both source and dest
    ...
NEXT i
```

Same as Pattern A but dest = srcA. Saves one load per iteration.

**Pattern C: Array copy**

```basic
FOR i = 0 TO n
    B(i) = A(i)                      ' or field-by-field
NEXT i
```

Emits `ldr q` / `str q` loop. With ×2 unroll: `ldp q,q` / `stp q,q`.

**Pattern D: Scalar broadcast initialization**

```basic
FOR i = 0 TO n
    A(i).x = 0 : A(i).y = 0 : A(i).z = 0 : A(i).w = 0
NEXT i
```

Emits `movi v28.4s, #0` before loop, then `str q28, [base, offset]` per element.

**Pattern E: Reduction across array**

```basic
sum = 0
FOR i = 0 TO n
    sum = sum + A(i).x + A(i).y + A(i).z + A(i).w
NEXT i
```

Accumulates in lanes: `add v30.4s, v30.4s, v28.4s` per element, then
`addv s30, v30.4s` at the end. One horizontal operation total.

### Phase 4: Reductions and Advanced Operations

**Estimated scope:** ~300 LOC  
**Impact:** Horizontal sums, dot products  

#### 6.4.1 Horizontal Sum

Detect `v.x + v.y + v.z + v.w` pattern in expressions:

```cpp
bool isHorizontalSum(const Expression* expr, const TypeSymbol& udt,
                     std::string& outBaseAddr);
```

Emit `neonldr` + `neonaddv`.

#### 6.4.2 Dot Product

Detect `a.x*b.x + a.y*b.y + a.z*b.z + a.w*b.w`:

```asm
ldr   q28, [addr_a]
ldr   q29, [addr_b]
mul   v28.4s, v28.4s, v29.4s   ; element-wise multiply
addv  s28, v28.4s              ; horizontal sum
fmov  w0, s28                  ; result
```

5 instructions instead of 4 loads + 4 loads + 4 multiplies + 3 adds = 15.

---

## 7. QBE IL Examples

### 7.1 Scalar (Current)

```qbe
# Copy Vec4: b = a
%t1 =w loadw %addr_a
storew %t1, %addr_b
%t2 =w loadw %addr_a_4
storew %t2, %addr_b_4
%t3 =w loadw %addr_a_8
storew %t3, %addr_b_8
%t4 =w loadw %addr_a_12
storew %t4, %addr_b_12
```

### 7.2 NEON Bulk Copy

```qbe
# NEON bulk copy Vec4: b = a
neonldr %addr_a
neonstr %addr_b
```

### 7.3 NEON Element-Wise Add

```qbe
# NEON add: c = a + b  (Vec4, .4s arrangement)
neonldr %addr_a
neonldr2 %addr_b
neonadd
neonstr %addr_c
```

### 7.4 NEON Array Loop

```qbe
# NEON array loop: C(i) = A(i) + B(i) for i = 0..n
%base_a =l call $array_get_data_ptr(l %arr_a)
%base_b =l call $array_get_data_ptr(l %arr_b)
%base_c =l call $array_get_data_ptr(l %arr_c)
%end_off =l mul %count, 16
%off =l copy 0
@Lneon_loop
    %addr_a =l add %base_a, %off
    %addr_b =l add %base_b, %off
    %addr_c =l add %base_c, %off
    neonldr %addr_a
    neonldr2 %addr_b
    neonadd
    neonstr %addr_c
    %off =l add %off, 16
    %cond =w csltl %off, %end_off
    jnz %cond, @Lneon_loop, @Lneon_done
@Lneon_done
```

---

## 8. Testing Strategy

### 8.1 Correctness Tests

Each tier gets a dedicated test file:

| Test File | Coverage |
|-----------|----------|
| `tests/neon/test_neon_copy.bas` | Bulk UDT copy, array element copy |
| `tests/neon/test_neon_arithmetic.bas` | Element-wise +, -, * on Vec2/Vec4 |
| `tests/neon/test_neon_array_loop.bas` | Vectorized FOR loops on UDT arrays |
| `tests/neon/test_neon_reduction.bas` | Horizontal sum, dot product |
| `tests/neon/test_neon_broadcast.bas` | Scalar broadcast, array init |
| `tests/neon/test_neon_edge_cases.bas` | 3-field UDTs, odd loop counts, empty arrays |
| `tests/neon/test_neon_mixed.bas` | SIMD UDTs alongside non-SIMD UDTs |

### 8.2 Correctness Verification Approach

Every test computes results both via the NEON path AND via explicit scalar
operations, then compares:

```basic
TYPE Vec4
    x AS INTEGER
    y AS INTEGER
    z AS INTEGER
    w AS INTEGER
END TYPE

DIM a AS Vec4, b AS Vec4
a.x = 10 : a.y = 20 : a.z = 30 : a.w = 40
b.x = 1  : b.y = 2  : b.z = 3  : b.w = 4

' NEON path (compiler should vectorize this)
DIM c AS Vec4
c.x = a.x + b.x
c.y = a.y + b.y
c.z = a.z + b.z
c.w = a.w + b.w

' Scalar verification
IF c.x = 11 AND c.y = 22 AND c.z = 33 AND c.w = 44 THEN
    PRINT "PASS"
ELSE
    PRINT "FAIL"
END IF
```

### 8.3 Kill-Switch Testing

Every optimization is controlled by an environment variable:

| Variable | Default | Effect |
|----------|---------|--------|
| `ENABLE_NEON_COPY` | `1` | Enable/disable NEON bulk copy |
| `ENABLE_NEON_ARITH` | `1` | Enable/disable NEON element-wise arithmetic |
| `ENABLE_NEON_LOOPS` | `1` | Enable/disable NEON loop vectorization |

Tests are run with all combinations to verify scalar fallback produces
identical results.

### 8.4 Assembly Verification

For each test, generate assembly (`-c` flag) and verify NEON instructions
are present:

```bash
# Verify NEON instructions appear
grep -c 'ldr.*q2[89]\|str.*q2[89]\|add.*v2[89]' output.s

# Verify scalar fallback generates NO NEON instructions
ENABLE_NEON_COPY=false ./fbc_qbe test.bas -c -o output_scalar.s
grep -c 'q28\|q29\|q30' output_scalar.s  # should be 0
```

### 8.5 Performance Measurement

Instruction count comparison for representative workloads:

```bash
# Count total instructions in assembly
wc -l output_neon.s output_scalar.s

# Count NEON-specific instructions
grep -cE '^\s+(ldr|str)\s+q' output_neon.s          # Q-register loads/stores
grep -cE '^\s+(add|sub|mul)\s+v[0-9]+\.' output_neon.s  # NEON arithmetic
grep -cE '^\s+addv' output_neon.s                     # Reductions
```

---

## 9. Fallback and Safety

### 9.1 Scalar Fallback

Every NEON code path has an equivalent scalar fallback. The NEON path is
selected only when:

1. The UDT is classified as SIMD-eligible.
2. The operation pattern matches a vectorizable template.
3. The target is ARM64 (not AMD64 or RV64).
4. The kill-switch environment variable is not set to `false`.

When any condition fails, the existing scalar codegen path executes.

### 9.2 ABI Safety

- NEON scratch registers V28-V30 are caller-saved on ARM64.
- Before any `call` instruction, the emitter does NOT need to save them
  (they're scratch).
- After any `call`, their contents are undefined — the codegen must reload
  from memory before resuming NEON operations.
- The NEON opcodes are never emitted around call instructions; the
  ASTEmitter ensures NEON sequences are contiguous.

### 9.3 Mixed UDTs

When a UDT contains mixed types or strings, the SIMD classification is
`NONE` and all existing scalar code paths are used unchanged. There is no
partial vectorization of individual fields.

### 9.4 Cross-Platform

- **ARM64:** Full NEON support as described.
- **AMD64:** NEON opcodes are not emitted. The semantic classification
  still runs (for diagnostics), but the codegen checks `target == arm64`
  before emitting NEON IL. Future work could map the same patterns to
  SSE/AVX.
- **RV64:** Same — scalar fallback. Future work could target RVV.

---

## 10. Impact Projections

### 10.1 Instruction Count Reduction

| Operation | Scalar Instrs | NEON Instrs | Reduction |
|-----------|:------------:|:-----------:|:---------:|
| Copy Vec4 (4×32-bit) | 8 | 2 | 4× |
| Copy Vec2D (2×64-bit) | 4 | 2 | 2× |
| Add Vec4 | 12 | 4 | 3× |
| Add Vec4 in array loop | 16/iter | 4/iter | 4× |
| Add Vec4 array ×2 unroll | 16/iter | 2.5/iter | 6.4× |
| Sum Vec4 fields | 6 | 3 | 2× |
| Dot product Vec4 | 15 | 5 | 3× |
| Initialize Vec4 array (N elems) | 4N + 3 | N + 4 | ~4× |
| Copy Vec4 array (N elems) | 8N + 3 | 2N + 3 | ~4× |

### 10.2 Expected Real-World Impact

For a typical particle system / game physics loop updating 1000 Vec4 elements:

- **Scalar:** ~16,000 data instructions + ~3,000 loop overhead = ~19,000
- **NEON ×1:** ~4,000 data + ~3,000 loop = ~7,000 (2.7× fewer)
- **NEON ×2 unroll:** ~2,500 data + ~1,500 loop = ~4,000 (4.75× fewer)

Cache behavior also improves: 128-bit loads/stores have better utilization
of the memory bus than 32-bit scalar accesses.

### 10.3 Which Types Benefit

| UDT Pattern | Common In | SIMD? |
|-------------|-----------|-------|
| `{ x, y }` INTEGER | 2D games, coordinates | ✓ V2S |
| `{ x, y, z }` INTEGER | 3D positions (padded) | ✓ V4S_PAD1 |
| `{ x, y, z, w }` INTEGER | Homogeneous coordinates | ✓ V4S |
| `{ r, g, b, a }` SINGLE | Colors, pixels | ✓ V4S |
| `{ real, imag }` DOUBLE | Complex arithmetic | ✓ V2D |
| `{ name, age }` STRING+INT | Contacts, records | ✗ mixed types |
| `{ id, value, tag }` INT+INT+STRING | Tagged data | ✗ has string |

---

## 11. Implementation Phasing and Dependencies

```
Phase 1: Foundation                     Phase 2: Arithmetic
┌──────────────────────┐               ┌────────────────────────┐
│ • Extended SIMDType   │               │ • Statement lookahead  │
│ • SIMDInfo struct     │               │ • Pattern matching     │
│ • Detection logic     │──────────────▶│ • neonadd/sub/mul ops  │
│ • Reserve V28-V30     │               │ • Float vs int paths   │
│ • NEON opcodes in QBE │               │ • Tests                │
│ • Bulk copy emission  │               └───────────┬────────────┘
│ • alloc16 alignment   │                           │
│ • Tests               │                           ▼
└──────────────────────┘               ┌────────────────────────┐
                                       │ Phase 3: Array Loops   │
                                       │                        │
                                       │ • SIMDLoopAnalyzer     │
                                       │ • array_get_data_ptr   │
                                       │ • Loop codegen         │
                                       │ • ×2 unrolling         │
                                       │ • Remainder handling   │
                                       │ • Tests                │
                                       └───────────┬────────────┘
                                                   │
                                                   ▼
                                       ┌────────────────────────┐
                                       │ Phase 4: Reductions    │
                                       │                        │
                                       │ • Horizontal sum       │
                                       │ • Dot product          │
                                       │ • Array-wide reduction │
                                       │ • Tests                │
                                       └────────────────────────┘
```

**Phase 1** is standalone and can be implemented, tested, and shipped
independently. Each subsequent phase builds on the previous.

---

## 12. Open Questions

1. **3-field UDTs:** Should we support padding to 4 lanes (wasting 25%
   register width) or require the user to add an explicit padding field?
   Recommendation: support it transparently — the padding is an internal
   compiler detail invisible to the BASIC programmer.

2. **Integer division:** NEON has no integer vector divide. Options:
   (a) Fall back to scalar for the entire operation.
   (b) Use NEON for loads, scalar for divides, NEON for store.
   Recommendation: (a) is simpler and correct.

3. **Signed vs unsigned:** NEON has signed and unsigned variants for some
   operations (e.g., `sminv` vs `uminv`). Map INTEGER→signed, UINTEGER→unsigned.

4. **Overflow behavior:** NEON integer add/sub wrap on overflow (same as
   scalar ARM64 add). NEON also offers saturating variants (`sqadd`, `uqadd`).
   Recommendation: use wrapping (matches scalar behavior).

5. **AMD64/SSE mapping:** The same SIMDInfo classification works for SSE2
   (`__m128i` / `__m128`). Phase 1-2 could be extended to emit SSE
   intrinsics via inline asm or custom opcodes for the AMD64 backend.
   This is future work and does not affect the ARM64 design.

6. **User-visible syntax:** Should we add explicit vector syntax (e.g.,
   `DIM v AS SIMD Vec4`) or keep it fully transparent? Recommendation:
   fully transparent — the compiler auto-detects eligible UDTs. A `PRINT`
   diagnostic (`[SIMD] Detected...`) already exists for user visibility.

---

## 13. File Change Summary

| File | Changes |
|------|---------|
| `fsh/.../fasterbasic_ast.h` | Extended `SIMDType` enum, `SIMDInfo` struct |
| `fsh/.../fasterbasic_semantic.h` | `SIMDInfo` on `TypeSymbol` |
| `fsh/.../fasterbasic_semantic.cpp` | Generalized classification, loop analysis |
| `fsh/.../codegen_v2/type_manager.h` | `getSIMDInfo()` method |
| `fsh/.../codegen_v2/type_manager.cpp` | SIMDInfo computation |
| `fsh/.../codegen_v2/ast_emitter.h` | NEON emission methods |
| `fsh/.../codegen_v2/ast_emitter.cpp` | Bulk copy, arithmetic, loop vectorization |
| `qbe_source/ops.h` | NEON opcodes |
| `qbe_source/arm64/targ.c` | Reserve V28-V30 |
| `qbe_source/arm64/isel.c` | Pass-through for NEON ops |
| `qbe_source/arm64/emit.c` | NEON instruction emission |
| `fsh/.../runtime_c/basic_array.c` | `array_get_data_ptr()` |
| `tests/neon/*.bas` | Test suite (7+ test files) |