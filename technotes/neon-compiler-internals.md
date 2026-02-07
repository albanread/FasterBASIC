# NEON SIMD Compiler Internals

**Audience:** Compiler engineers working on FasterBASIC, QBE backend modifications, or similar SIMD-via-custom-opcode strategies.

**Prerequisite reading:** Familiarity with QBE's IL, register allocation pipeline, and ARM64 NEON ISA.

---

## Table of Contents

1. [Architecture Decision: Custom Opcodes vs. Alternatives](#1-architecture-decision-custom-opcodes-vs-alternatives)
2. [Pipeline Overview](#2-pipeline-overview)
3. [SIMD Classification Subsystem](#3-simd-classification-subsystem)
4. [QBE Opcode Definitions](#4-qbe-opcode-definitions)
5. [Register Reservation Strategy](#5-register-reservation-strategy)
6. [Frontend Pattern Detection and IL Emission](#6-frontend-pattern-detection-and-il-emission)
7. [Instruction Selection Pass-Through](#7-instruction-selection-pass-through)
8. [Backend Code Emission](#8-backend-code-emission)
9. [Interaction with QBE Optimization Passes](#9-interaction-with-qbe-optimization-passes)
10. [The MADD Fusion Safety Problem](#10-the-madd-fusion-safety-problem)
11. [UDT Array Element Copy Semantics](#11-udt-array-element-copy-semantics)
12. [Scalar Fallback and Kill-Switch Mechanism](#12-scalar-fallback-and-kill-switch-mechanism)
13. [Arrangement Encoding Scheme](#13-arrangement-encoding-scheme)
14. [Testing Infrastructure](#14-testing-infrastructure)
15. [Known Limitations and Future Work](#15-known-limitations-and-future-work)
16. [File Map](#16-file-map)

---

## 1. Architecture Decision: Custom Opcodes vs. Alternatives

Three strategies were evaluated for introducing NEON code generation into the
FasterBASIC + QBE pipeline. Understanding why custom opcodes were chosen is
essential context for anyone modifying this code.

### Option A: Inline Assembly Strings

QBE has no inline assembly facility. Adding one would require threading
arbitrary strings through the register allocator, instruction scheduler, and
emitter — an invasive change that would break the IR's well-formedness
invariants.

**Rejected.**

### Option B: Post-Regalloc Pattern Matching in the Emitter

Detect that four consecutive scalar adds on adjacent stack slots should become
a single vector add. This is fragile after register allocation has reordered
and interleaved instructions, and type information (is this a Vec4? are all
fields the same type?) is no longer available at that point.

**Rejected.**

### Option C: Custom QBE Opcodes (Chosen)

Add NEON operations to `ops.h` as target-specific opcodes. The frontend emits
them with full type knowledge; they flow through the QBE pipeline as pinned,
side-effecting instructions; the ARM64 emitter converts them to NEON mnemonics.

**Advantages:**
- IL remains well-formed — labels, branches, block layout, debug info all work normally.
- Address operands (base pointers, loop indices) participate in standard register allocation.
- Vector registers are reserved and side-step regalloc entirely.
- Decision point is in the frontend where UDT structure is known.
- Kill-switch is trivial: the frontend simply doesn't emit the opcodes.

---

## 2. Pipeline Overview

```
┌─────────────────────────────────────────────────────────────────┐
│  FasterBASIC Frontend                                           │
│                                                                 │
│  1. Parser → AST                                                │
│  2. Semantic Analyzer                                           │
│     └─ classifySIMDType() on every TYPE..END TYPE               │
│        └─ Attaches SIMDInfo to TypeSymbol in symbol table       │
│  3. ASTEmitter (CodeGen V2)                                     │
│     ├─ emitLetStatement() detects UDT assignment patterns       │
│     ├─ tryEmitNEONArithmetic() → emits neonldr/neonadd/neonstr │
│     ├─ emitUDTCopyFieldByField() → emits neonldr/neonstr       │
│     ├─ emitScalarUDTArithmetic() → scalar fallback              │
│     └─ emitSIMDLoop() → vectorized FOR loop                    │
│                                                                 │
│  Output: QBE IL with NEON custom opcodes                        │
└──────────────────────┬──────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────────┐
│  QBE Backend                                                    │
│                                                                 │
│  1. Parser (parse.c)                                            │
│     └─ Recognizes neonldr, neonstr, neonadd, etc. via          │
│        perfect-hash lexer (K=320942661, M=23)                   │
│  2. SSA Construction, GVN, GCM, Load Elimination, Alias...     │
│     └─ NEON stores recognized as memory-writers                 │
│        (isneonstore() macro in all.h)                           │
│  3. Instruction Selection (arm64/isel.c)                        │
│     └─ NEON opcodes pass through unchanged                      │
│        GPR address args get fixarg() for slot materialization   │
│  4. Register Allocation (rega.c / spill.c)                      │
│     └─ V28-V30 excluded from rsave[], never assigned            │
│  5. Post-Regalloc Liveness (filllive called twice)              │
│     └─ Second filllive() after regalloc populates b->out        │
│        with physical register IDs for MADD fusion safety        │
│  6. Code Emission (arm64/emit.c)                                │
│     └─ case Oneonldr..Oneondup: emit NEON ARM64 mnemonics      │
│     └─ MADD/MSUB fusion with safety checks                     │
│                                                                 │
│  Output: ARM64 assembly with NEON instructions                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. SIMD Classification Subsystem

### When Classification Happens

During semantic analysis, every `TYPE...END TYPE` declaration is inspected.
The classifier runs in `processTypeDeclarationStatement()` and produces a
`SIMDInfo` struct that is stored on the `TypeSymbol`.

### Eligibility Rules

A UDT is SIMD-eligible when ALL of the following hold:

| Rule | Rationale |
|------|-----------|
| All fields are the same numeric base type | NEON lanes must be homogeneous |
| No STRING, UNICODE, USER_DEFINED, or OBJECT fields | Pointers — arithmetic is meaningless |
| Total packed size ≤ 128 bits (16 bytes) | Must fit in a single Q register |
| Field count is 2, 3, 4, 8, or 16 | NEON operates on fixed lane widths |

3-field types are transparently padded to 4 lanes (zero-filled padding lane).

### The SIMDInfo Descriptor

```cpp
struct SIMDInfo {
    SIMDType  type;           // V2D, V4S, V8H, V16B, V2S, V4H, V8B, V4S_PAD1, or NONE
    int       laneCount;      // Active lanes: 2, 3, 4, 8, 16
    int       physicalLanes;  // Lanes in register (may differ for padded: 4 when laneCount=3)
    int       laneBitWidth;   // 8, 16, 32, or 64
    int       totalBytes;     // 8 (D register) or 16 (Q register)
    bool      isFullQ;        // true → 128-bit Q register; false → 64-bit D register
    bool      isPadded;       // true when laneCount < physicalLanes
    bool      isFloatingPoint; // true for SINGLE/DOUBLE lanes
    BaseType  laneType;       // The uniform base type of each lane

    const char* arrangement() const;  // Returns "4s", "2d", "8h", etc.
    const char* regPrefix() const;    // "q" for 128-bit, "d" for 64-bit
};
```

### Lane Configuration Table

| Fields | Base Type | Total Bits | SIMDType | Arrangement | Register |
|--------|-----------|:----------:|----------|:-----------:|:--------:|
| 2 | DOUBLE | 128 | V2D | `.2d` | Q |
| 2 | LONG/ULONG | 128 | V2D | `.2d` | Q |
| 4 | INTEGER | 128 | V4S | `.4s` | Q |
| 4 | SINGLE | 128 | V4S | `.4s` | Q |
| 8 | SHORT | 128 | V8H | `.8h` | Q |
| 16 | BYTE | 128 | V16B | `.16b` | Q |
| 2 | INTEGER/SINGLE | 64 | V2S | `.2s` | D |
| 4 | SHORT | 64 | V4H | `.4h` | D |
| 8 | BYTE | 64 | V8B | `.8b` | D |
| 3 | INTEGER/SINGLE | 96→128 | V4S_PAD1 | `.4s` | Q (padded) |

The classification is computed once at semantic analysis time and cached on the
`TypeSymbol`. All downstream code (emitter, codegen) queries `typeSymbol.simdInfo.type`
to check eligibility.

---

## 4. QBE Opcode Definitions

All NEON opcodes are defined in `qbe_source/ops.h` using the standard `O()` macro.
They are placed in the **public operations** section so the parser can recognize
them by name.

### Opcode Table

```c
/* ops.h — NEON vector operations */

O(neonldr,   T(m,m,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 ← [addr]
O(neonstr,   T(m,m,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // [addr] ← V28
O(neonldr2,  T(m,m,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V29 ← [addr]
O(neonstr2,  T(m,m,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // [addr] ← V29
O(neonadd,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = V28 + V29
O(neonsub,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = V28 - V29
O(neonmul,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = V28 * V29
O(neondiv,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = V28 / V29 (float only)
O(neonneg,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = -V28
O(neonabs,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = |V28|
O(neonfma,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 += V29 * V30
O(neonmin,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = min(V28, V29)
O(neonmax,   T(w,w,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = max(V28, V29)
O(neondup,   T(w,w,e,e, w,w,e,e), F(0,0,0,0,0,0,0,0,0,1))  // V28 = broadcast(GPR)
O(neonaddv,  T(w,l,e,e, x,x,e,e), F(0,0,0,0,0,0,0,0,0,1))  // scalar = horiz_sum(V28)
```

### Key Properties

Every NEON opcode has:

- **Pinned = 1** (rightmost `F()` flag): prevents GCM/GVN from moving or
  eliminating them. NEON operations have implicit register dependencies (V28/V29)
  that the optimizer cannot see, so they must stay in emission order.
- **No result register for most ops**: arithmetic ops (neonadd, neonsub, etc.)
  are resultless — they modify V28 implicitly. The `to` field is `R` (void).
  Only `neonaddv` produces a scalar GPR result.
- **Type signature `T(m,m,e,e, x,x,e,e)` for loads/stores**: `arg[0]` is a
  memory address (`m` class), which allows the address to participate in
  register allocation normally.
- **Type signature `T(w,w,e,e, x,x,e,e)` for arithmetic**: `arg[0]` carries
  the arrangement encoding as an integer constant, not a register. The `w,w`
  in slot 0 keeps the parser happy; the actual arrangement is decoded at
  emission time.

### Parser Perfect-Hash

Adding 15 new opcode names required recomputing the lexer perfect-hash
parameters. The current constants are:

```
K = 320942661
M = 23
```

Computed via `tools/lexh_neon.c`. If you add more opcodes, you must recompute
these values or the parser will fail to recognize the new names.

---

## 5. Register Reservation Strategy

### The Problem

QBE's register allocator assigns ARM64 V0–V30 as scalar floating-point
registers. NEON operations need dedicated vector registers that won't be
clobbered between a `neonldr` and a `neonstr`.

### The Solution

Remove V28, V29, and V30 from `arm64_rsave[]` in `arm64/targ.c`:

```c
int arm64_rsave[] = {
    R0,  R1,  R2,  R3,  R4,  R5,  R6,  R7,
    R8,  R9,  R10, R11, R12, R13, R14, R15,
    IP0, IP1, R18, LR,
    V0,  V1,  V2,  V3,  V4,  V5,  V6,  V7,
    V16, V17, V18, V19, V20, V21, V22, V23,
    V24, V25, V26, V27,
    /* V28, V29, V30 reserved for NEON scratch */
    -1
};
```

The register allocator never assigns V28–V30 to any SSA temporary. The NEON
opcodes reference these registers implicitly (hardcoded in the emitter), so
there is no conflict.

### Register Roles

| Register | Role | Used By |
|----------|------|---------|
| V28 (q28) | Primary operand / result | `neonldr`, `neonstr`, all arithmetic |
| V29 (q29) | Secondary operand | `neonldr2`, `neonstr2`, binary arithmetic ops |
| V30 (q30) | Tertiary / accumulator | `neonfma` (multiply-add), loop accumulators |

### ABI Safety

V28–V30 are caller-saved in the ARM64 calling convention. The emitter does not
need to save/restore them around function calls. After any `call` instruction,
their contents are undefined — the codegen must reload from memory before
issuing further NEON operations. The ASTEmitter ensures NEON sequences never
straddle function calls.

### Trade-off

Reserving 3 of 31 vector registers reduces the floating-point register file
available to scalar code from 31 to 28. In practice this has negligible
spill pressure impact because:

1. FasterBASIC programs rarely have more than ~10 live FP values simultaneously.
2. The NEON benefit (4× fewer instructions for hot loops) vastly outweighs
   occasional extra spills.

If loop unrolling requires 4 NEON scratch registers, V27 can be added to the
reserved pool (reducing scalar FP registers to 27).

---

## 6. Frontend Pattern Detection and IL Emission

### Entry Point: `emitLetStatement()`

All NEON emission is triggered from `ASTEmitter::emitLetStatement()` in
`codegen_v2/ast_emitter.cpp`. The method follows a priority chain:

```
emitLetStatement(stmt):
    resolve target variable/array element
    if target is a UDT:
        look up UDT definition from symbol table
        get target address

        1. tryEmitNEONArithmetic(stmt, targetAddr, udtDef, udtMap)
           → if returns true: done (NEON arithmetic emitted)

        2. emitScalarUDTArithmetic(stmt, targetAddr, udtDef, udtMap)
           → if returns true: done (scalar field-by-field arithmetic)

        3. emitUDTCopyFieldByField(sourceAddr, targetAddr, udtDef, udtMap)
           → handles plain copy (may use NEON bulk copy or scalar)
```

The same priority chain applies to both simple UDT variables and array element
targets (`Arr(i) = A + B`).

### Pattern: Whole-UDT Binary Arithmetic

`tryEmitNEONArithmetic()` checks:

1. **Kill-switch**: `ENABLE_NEON_ARITH` environment variable. If `"0"` or
   `"false"`, returns false immediately.
2. **Value expression type**: Must be a `BinaryExpression` with operator
   `+`, `-`, `*`, or `/`.
3. **Operand UDT types**: Both operands must resolve to the same UDT type
   as the target (via `getUDTTypeNameForExpr()`).
4. **SIMD eligibility**: `udtDef.simdInfo.type != SIMDType::NONE`.
5. **Division constraint**: For `/`, the arrangement must be floating-point
   (NEON has no integer vector divide).

If all checks pass, the emitter outputs four IL instructions:

```
neonldr  %addr_left      ; q28 ← left operand
neonldr2 %addr_right     ; q29 ← right operand
neonadd  <arrCode>        ; v28 = v28 + v29 (arrangement-specific)
neonstr  %addr_target    ; target ← q28
```

The addresses `%addr_left`, `%addr_right`, `%addr_target` are normal GPR
temporaries produced by `getUDTAddressForExpr()`. They flow through
register allocation normally.

The `<arrCode>` is an integer constant encoding the arrangement (see
[Section 13: Arrangement Encoding](#13-arrangement-encoding-scheme)).

### Pattern: Bulk UDT Copy

Inside `emitUDTCopyFieldByField()`, if the UDT is SIMD-eligible and the
`ENABLE_NEON_COPY` kill-switch is not set to false, the method emits:

```
neonldr %addr_source
neonstr %addr_target
```

Two instructions instead of 4–8 scalar load/store pairs.

### Pattern: Array Loop Vectorization

The `SIMDLoopInfo analyzeSIMDLoop()` method examines a FOR loop's AST to
determine if the body consists entirely of vectorizable UDT array operations.

Requirements for vectorization:

| Constraint | Reason |
|------------|--------|
| Integer loop index, step = 1 or -1 | Predictable stride |
| All array accesses use the loop index | No cross-iteration dependencies |
| No function calls in body | Would clobber V28–V30 |
| No string operations | Strings are pointers, not vectorizable |
| Same SIMD-eligible UDT type for all arrays | Lane configurations must match |
| No early exit (`EXIT FOR`) | Loop count must be known/computable |
| Body is pure element-wise | No cross-field operations |

When detected, `emitSIMDLoop()` replaces the entire FOR/NEXT with a
byte-offset-based loop:

```
%base_a    =l call $array_get_data_ptr(l %arr_a)
%base_b    =l call $array_get_data_ptr(l %arr_b)
%base_c    =l call $array_get_data_ptr(l %arr_c)
%end_off   =l mul %count, 16
%off       =l copy 0
@Lneon_loop
    %addr_a =l add %base_a, %off
    %addr_b =l add %base_b, %off
    %addr_c =l add %base_c, %off
    neonldr  %addr_a
    neonldr2 %addr_b
    neonadd  0              ; arrangement code for .4s-int
    neonstr  %addr_c
    %off    =l add %off, 16
    %cond   =w csltl %off, %end_off
    jnz %cond, @Lneon_loop, @Lneon_done
@Lneon_done
```

The `array_get_data_ptr()` runtime function returns a direct pointer to the
contiguous data buffer, bypassing per-element bounds checking. A single bounds
check is performed before the loop.

---

## 7. Instruction Selection Pass-Through

In `arm64/isel.c`, the `sel()` function contains an early-exit path for NEON
opcodes:

```c
static int
isneon(int op)
{
    return INRANGE(op, Oneonldr, Oneondup);
}

/* In sel(): */
if (isneon(i.op)) {
    emiti(i);
    iarg = curi->arg;
    if (INRANGE(i.op, Oneonldr, Oneonstr2)) {
        /* Load/store ops: arg[0] is a memory address → fixarg for slot materialization */
        fixarg(&iarg[0], Kl, 0, fn);
    } else if (i.op == Oneondup) {
        /* dup: arg[0] is arrangement constant (skip), arg[1] is GPR → fixarg */
        if (rtype(i.arg[1]) != -1 && !req(i.arg[1], R))
            fixarg(&iarg[1], Kl, 0, fn);
    }
    /* neonadd..neonmax, neonaddv: arg[0] is integer arrangement constant — no fixarg */
    return;
}
```

### Why `fixarg()` Is Needed

Even though NEON opcodes don't go through register allocation for the vector
registers, their **address operands** are normal SSA temporaries. If a
temporary was spilled to a stack slot, `fixarg()` inserts the reload
instruction to materialize it into a GPR before the NEON instruction executes.

### Why Arithmetic Args Are Skipped

For `neonadd`, `neonsub`, etc., `arg[0]` is an integer constant encoding the
arrangement (0–3). Calling `fixarg()` on it would try to treat it as a
register reference, which would corrupt the encoding. The arrangement constant
is decoded at emission time by `neon_arr_from_arg()`.

---

## 8. Backend Code Emission

### Arrangement Decoding

The emitter in `arm64/emit.c` uses two helper functions:

```c
/* Map arrangement code to ARM64 arrangement suffix string */
static char *
neon_arrangement(int cls)
{
    switch (cls) {
    case Kw: return "4s";   // 0: 4×32-bit integer
    case Ks: return "4s";   // 2: 4×32-bit float (same encoding, different instructions)
    case Kl: return "2d";   // 1: 2×64-bit integer
    case Kd: return "2d";   // 3: 2×64-bit float
    default: return "4s";
    }
}

/* Determine if arrangement uses float instructions (fadd vs add) */
static int
neon_is_float(int cls)
{
    return cls == Ks || cls == Kd;
}
```

The `neon_arr_from_arg()` function extracts the arrangement code from `arg[0]`,
handling both `RInt` (inline small integer) and `RCon` (constant table entry)
forms, since the parser may produce either depending on context.

### Emission Examples

**neonldr (vector load):**
```c
case Oneonldr:
    fprintf(e->f, "\tldr\tq28, [%s]\n", rname(i->arg[0].val, Kl));
    break;
```

**neonadd (vector add):**
```c
case Oneonadd: {
    int ac = neon_arr_from_arg(i, e);
    char *arr = neon_arrangement(ac);
    if (neon_is_float(ac))
        fprintf(e->f, "\tfadd\tv28.%s, v28.%s, v29.%s\n", arr, arr, arr);
    else
        fprintf(e->f, "\tadd\tv28.%s, v28.%s, v29.%s\n", arr, arr, arr);
    break;
}
```

**neonaddv (horizontal sum):**
```c
case Oneonaddv:
    fprintf(e->f, "\taddv\ts28, v28.4s\n");
    fprintf(e->f, "\tfmov\t%s, s28\n", rname(i->to.val, Kw));
    break;
```

Note that `neonaddv` is the only NEON opcode with a result register (`i->to`).
The horizontal sum produces a scalar value that goes into a GPR, which the
register allocator manages normally.

**neondup (scalar broadcast):**
```c
case Oneondup: {
    int ac = neon_arr_from_arg(i, e);
    char *arr = neon_arrangement(ac);
    char *gpr_pfx = neon_dup_gpr_prefix(ac);  // "w" for 32-bit, "x" for 64-bit
    fprintf(e->f, "\tdup\tv28.%s, %s%d\n", arr, gpr_pfx, i->arg[1].val - R0);
    break;
}
```

### Kill-Switch Guards in Emitter

Every NEON emission case checks the corresponding kill-switch environment
variable. If the kill-switch is active but a NEON opcode was somehow emitted
(indicating a frontend bug), the emitter calls `die()` rather than
silently generating wrong code:

```c
case Oneonldr:
    if (!is_neon_copy_enabled()) {
        die("neonldr emitted but NEON copy disabled");
    }
    // ... emit ...
```

This is a defense-in-depth measure. The frontend should never emit NEON
opcodes when the corresponding kill-switch is active.

---

## 9. Interaction with QBE Optimization Passes

NEON opcodes are invisible to most QBE optimization passes (they don't produce
SSA values, and their implicit register usage is opaque to the optimizer). However,
NEON **stores** write to memory, which affects several passes that track memory
state.

### The `isneonstore()` Macro

Defined in `all.h`:

```c
#define isneonstore(o) ((o) == Oneonstr || (o) == Oneonstr2)
```

This macro is checked in four places:

#### 1. Load Elimination (`load.c`)

The load eliminator's `def()` function must recognize NEON stores as killing
scalar loads from the same address. Without this, a scalar load could be
forwarded across a NEON store that overwrites the same memory:

```c
/* load.c — def() */
if (killsl(i->to, sl)
|| (i->op == Ocall && escapes(sl.ref, curf))
|| isneonstore(i->op))    // ← NEON store kills loads
    ...
```

#### 2. Alias Analysis (`alias.c`)

NEON store addresses must be marked as escaped so the alias analysis doesn't
assume the memory is unmodified:

```c
/* alias.c — fillalias() */
if (!isstore(i->op) && !isneonstore(i->op))
    if (i->op != Oargc)
        esc(i->arg[1], fn);

if (isneonstore(i->op))
    esc(i->arg[0], fn);   // ← mark NEON store target as escaped
```

#### 3. Global Code Motion (`gcm.c`)

GCM must sink NEON store address operands correctly. NEON stores use `arg[0]`
for the address (unlike scalar stores which use `arg[1]`):

```c
/* gcm.c — sink() */
else if (isstore(i->op))
    sinkref(fn, b, &i->arg[1]);
else if (isneonstore(i->op))
    sinkref(fn, b, &i->arg[0]);  // ← address is in arg[0], not arg[1]
```

#### 4. Memory Coalescing (`mem.c`)

The memory coalescer must recognize NEON stores as 16-byte writes:

```c
/* mem.c — coalesce() */
if (isneonstore(i->op)) {
    x = NBit >= 16 ? BIT(16) - 1 : (bits)-1;
    // ... mark 16 bytes as written ...
}
```

### Why This Matters

If any of these four integration points is missing, the optimizer will make
incorrect assumptions about memory state around NEON stores:

- **Missing in load.c**: A scalar load from address X could be forwarded
  past a NEON store to address X, reading stale data.
- **Missing in alias.c**: The alias analysis could conclude that a NEON
  store doesn't alias with a subsequent scalar load, enabling incorrect
  reordering.
- **Missing in gcm.c**: GCM could move a NEON store to a different block
  where its address operand isn't computed yet.
- **Missing in mem.c**: Memory coalescing could merge writes incorrectly,
  not accounting for the 16-byte NEON write width.

---

## 10. The MADD Fusion Safety Problem

This section documents a subtle correctness bug that was discovered during
NEON testing but is **not specific to NEON** — it affects all ARM64 code
generation through QBE. It is documented here because the NEON test suite
was what exposed it.

### Background: MADD Peephole

The ARM64 emitter fuses consecutive MUL + ADD instructions into a single
MADD instruction:

```
MUL  x1, x2, x3      →   MADD x0, x2, x3, x4
ADD  x0, x4, x1           (dest = addend + (mul_op1 * mul_op2))
```

This saves one instruction and one cycle on most ARM64 microarchitectures.

### The Bug

After register allocation, CSE (Common Subexpression Elimination) and GVN
(Global Value Numbering) may have arranged for the MUL result register to be
read by instructions in **other basic blocks**. The original MADD fusion check
only scanned for uses of the MUL result within the **same basic block**.

When the MUL was fused into MADD and never emitted, successor blocks that
expected to read the MUL result register got a stale (undefined) value,
typically whatever happened to be in that register from a prior computation.

This manifested as incorrect array element field values in NEON test cases,
where the MUL was computing an array element address offset that was consumed
by loads in a different block.

### The Fix: Post-Regalloc Liveness + Cross-Block Check

The fix has two parts:

**Part 1: Re-run `filllive()` after register allocation.**

In `main.c`, a second call to `filllive()` was added after `spill()`:

```c
/* main.c — func() */
spill(fn);
simpljmp(fn);
fillcfg(fn);
filllive(fn);  /* re-run after regalloc so b->out has physical regs for emitter */
```

Before this change, `b->out` (the live-out set for each block) contained
SSA temporary IDs. After register allocation, those IDs are meaningless
because physical registers have been assigned. The second `filllive()` call
recomputes `b->out` with physical register IDs.

**Part 2: Check `b->out` in `prev_result_used_later()`.**

The function `prev_result_used_later()` in `arm64/emit.c` checks whether
the MUL result register is used after the ADD instruction. The enhanced
version adds a live-out check:

```c
static int
prev_result_used_later(Ins *i, Blk *b, Ref prev_to)
{
    /* If the consumer overwrites the same register, safe. */
    if (req(i->to, prev_to))
        return 0;

    /* Scan instructions after 'i' in this block. */
    for (j = i + 1; j != end; j++) {
        if (req(j->arg[0], prev_to) || req(j->arg[1], prev_to))
            return 1;  /* Used later in same block — unsafe */
        if (req(j->to, prev_to))
            return 0;  /* Overwritten — stop scanning */
    }

    /* Check branch argument. */
    if (req(b->jmp.arg, prev_to))
        return 1;

    /* NEW: Check if register is live-out from this block.
     * If it is, a successor block reads the MUL result. */
    if (rtype(prev_to) == RTmp && bshas(b->out, prev_to.val))
        return 1;  /* Live-out — fusion unsafe */

    return 0;
}
```

The same check is applied in `try_msub_fusion()` for MUL + SUB → MSUB.

### Verification

The NEON test suite includes test cases that exercise cross-block MUL result
sharing (specifically, array element address computations consumed by loads
in a different block). These tests pass with the fix and fail without it.

### Performance Note

The second `filllive()` call adds a small compile-time cost (one extra pass
over the CFG). This is negligible compared to register allocation itself.
No runtime performance impact — MADD fusion still fires when safe, and
the live-out check prevents it only when it would produce wrong code.

---

## 11. UDT Array Element Copy Semantics

### The Bug

When assigning a UDT value to an array element:

```basic
DIM Arr(10) AS Vec4
DIM Temp AS Vec4
Temp.X = 1 : Temp.Y = 2 : Temp.Z = 3 : Temp.W = 4
Arr(3) = Temp
```

The emitter was incorrectly emitting a single 8-byte store of the source
UDT's **address** (a pointer) to the array element slot, instead of copying
the full UDT payload. For UDTs > 8 bytes, this resulted in partial/corrupt
data in the array element.

### Root Cause

The `emitLetStatement()` array-element path was computing the target element
address correctly but then falling through to a generic store path that
treated the source as a scalar value (pointer-sized) rather than a
multi-byte aggregate.

### The Fix

For array element UDT assignments, the emitter now:

1. Computes the target element address via `emitArrayElementAddress()`.
2. Resolves the source UDT address via `getUDTAddressForExpr()`.
3. Calls `emitUDTCopyFieldByField()` with both addresses.
4. `emitUDTCopyFieldByField()` checks SIMD eligibility:
   - If eligible and NEON copy enabled → `neonldr`/`neonstr` (2 instructions)
   - Otherwise → field-by-field scalar loads/stores

This correctly handles all assignment patterns:
- `Arr(i) = Temp` (scalar → array element)
- `Arr(i) = Arr(j)` (array element → array element)
- `Temp = Arr(i)` (array element → scalar)
- `Arr(i) = Arr(j) + Arr(k)` (arithmetic result → array element)

---

## 12. Scalar Fallback and Kill-Switch Mechanism

### Design Principle

Every NEON code path has an equivalent scalar fallback. The NEON path is
selected only when all four conditions hold:

1. The UDT is classified as SIMD-eligible (`simdInfo.type != NONE`).
2. The operation pattern matches a vectorizable template.
3. The target architecture is ARM64.
4. The kill-switch environment variable is not set to `"0"` or `"false"`.

### Kill-Switch Environment Variables

| Variable | Default | Controls |
|----------|---------|----------|
| `ENABLE_NEON_COPY` | `1` | `neonldr`/`neonstr` emission for bulk copy |
| `ENABLE_NEON_ARITH` | `1` | `neonadd`/`neonsub`/`neonmul`/`neondiv` emission |
| `ENABLE_NEON_LOOP` | `1` | Vectorized loop generation |
| `ENABLE_MADD_FUSION` | `1` | MADD/MSUB peephole fusion |
| `ENABLE_SHIFT_FUSION` | `1` | Shifted-operand fusion |
| `ENABLE_LDP_STP_FUSION` | `1` | Load/store pair fusion |

Kill-switches are checked via lazy-initialized static variables:

```c
static int
is_neon_copy_enabled(void)
{
    static int checked = 0;
    static int enabled = 1;
    if (!checked) {
        const char *env = getenv("ENABLE_NEON_COPY");
        if (env) {
            enabled = (strcmp(env, "1") == 0 || strcmp(env, "true") == 0);
        }
        checked = 1;
    }
    return enabled;
}
```

The same pattern is used in both the frontend (`tryEmitNEONArithmetic()`)
and the backend (`emitins()`). The frontend checks are the primary gate —
if the frontend doesn't emit NEON opcodes, the backend never sees them.
The backend checks are defense-in-depth.

### Scalar Fallback Implementation

`emitScalarUDTArithmetic()` performs field-by-field arithmetic when
NEON is disabled or the UDT is not SIMD-eligible:

```
For each field F in UDT:
    %left_F  = load from left_addr + offset(F)
    %right_F = load from right_addr + offset(F)
    %result_F = %left_F op %right_F
    store %result_F to target_addr + offset(F)
```

This generates 3N instructions for N fields (vs. 4 for NEON). The scalar
path always produces correct results, making it the safe default.

### Int→Double Precision Fix

During kill-switch testing, a precision bug was discovered: some integer-to-
double conversions were being routed through SINGLE (float32) as an
intermediate step:

```
int → swtof → SINGLE → exts → DOUBLE   (LOSSY for large integers)
```

For integers > 2²⁴ (16,777,216), the SINGLE intermediate loses precision.
The fix routes int→double conversions directly:

```
int → swtof → DOUBLE   (via cls=Kd)
```

This uses `swtof` or `sltof` targeting the `d` (double) class directly,
bypassing the lossy single-precision intermediate.

---

## 13. Arrangement Encoding Scheme

### The Problem

NEON arithmetic opcodes (`neonadd`, `neonsub`, etc.) are resultless — the
parser assigns them `cls = Kw` by default. But the ARM64 emitter needs to
know the arrangement (`.4s`, `.2d`) and whether to use integer or float
instructions (`add` vs. `fadd`).

### The Solution

The arrangement is encoded as an integer constant in `arg[0]`:

| Code | QBE Class | Arrangement | Instruction Type | Example |
|:----:|:---------:|:-----------:|:----------------:|---------|
| 0 | Kw | `.4s` | Integer | `add v28.4s, v28.4s, v29.4s` |
| 1 | Kl | `.2d` | Integer | `add v28.2d, v28.2d, v29.2d` |
| 2 | Ks | `.4s` | Float | `fadd v28.4s, v28.4s, v29.4s` |
| 3 | Kd | `.2d` | Float | `fadd v28.2d, v28.2d, v29.2d` |

### Frontend Encoding

```cpp
int ASTEmitter::simdArrangementCode(const SIMDInfo& info) {
    if (info.isFloatingPoint) {
        return (info.laneBitWidth == 64) ? 3 : 2;  // Kd or Ks
    } else {
        return (info.laneBitWidth == 64) ? 1 : 0;  // Kl or Kw
    }
}
```

The frontend emits the arrangement code via `getcon()`:

```cpp
builder_.emitRaw("    neonadd " + std::to_string(arrCode));
```

### Backend Decoding

`neon_arr_from_arg()` handles both `RInt` (parser-inlined small integer) and
`RCon` (constant table entry) representations:

```c
static int
neon_arr_from_arg(Ins *i, E *e)
{
    int v;

    if (rtype(i->arg[0]) == RInt) {
        v = rsval(i->arg[0]);
        if (v >= 0 && v <= 3)
            return v;
    }
    if (rtype(i->arg[0]) == RCon) {
        Con *c = &e->fn->con[i->arg[0].val];
        if (c->type == CBits) {
            v = (int)c->bits.i;
            if (v >= 0 && v <= 3)
                return v;
        }
    }
    return i->cls;  /* fallback to instruction class */
}
```

The fallback to `i->cls` handles edge cases where the arrangement constant
might not be present (e.g., `neonldr` which doesn't use an arrangement).

---

## 14. Testing Infrastructure

### Test Runner

`scripts/run_neon_tests.sh` is the primary test harness:

```bash
./scripts/run_neon_tests.sh              # Basic tests
./scripts/run_neon_tests.sh --asm        # + assembly verification
./scripts/run_neon_tests.sh --killswitch # + scalar fallback verification
./scripts/run_neon_tests.sh --all        # everything
```

### Test Files

19 test files in `tests/neon/`, totaling 244 assertions:

| File | Coverage |
|------|----------|
| `test_neon_vec4_copy.bas` | Vec4 bulk copy (4×INTEGER) |
| `test_neon_vec4f_copy.bas` | Vec4F bulk copy (4×SINGLE) |
| `test_neon_vec2d_copy.bas` | Vec2D bulk copy (2×DOUBLE) |
| `test_neon_vec4_arith.bas` | Vec4 +, -, * arithmetic |
| `test_neon_vec4f_arith.bas` | Vec4F +, -, *, / float arithmetic |
| `test_neon_vec2d_arith.bas` | Vec2D +, -, *, / double arithmetic |
| `test_neon_loop_vec4_add.bas` | Array loop vectorization (add/sub/mul) |
| `test_neon_loop_vec4f.bas` | Array loop vectorization (float) |
| `test_neon_loop_vec2d.bas` | Array loop vectorization (double) |
| `test_neon_loop_copy.bas` | Array loop bulk copy |
| `test_neon_array_copy.bas` | Array element ↔ scalar copy |
| `test_neon_edge_cases.bas` | Boundary conditions, special values |
| `test_neon_combined.bas` | Mixed operations in sequence |
| `test_neon_fallback.bas` | Non-eligible UDTs (scalar fallback) |
| `test_neon_killswitch.bas` | All operations with NEON disabled |
| `test_neon_asm_verify.bas` | Assembly output verification |
| `test_neon_loop_debug.bas` | Loop edge cases and debugging |
| `test_neon_loop_edge.bas` | Loop boundary conditions |
| `test_neon_array_debug.bas` | Array debugging scenarios |

### Test Pattern

Every test computes results via the NEON path AND verifies against known
scalar values:

```basic
A.X = 10 : A.Y = 20 : A.Z = 30 : A.W = 40
B.X = 1  : B.Y = 2  : B.Z = 3  : B.W = 4
C = A + B
IF C.X = 11 AND C.Y = 22 AND C.Z = 33 AND C.W = 44 THEN
    PRINT "PASS"
ELSE
    PRINT "FAIL"
END IF
```

### Kill-Switch Testing

The kill-switch test (`test_neon_killswitch.bas`) is compiled twice:

```bash
# With NEON (default)
./fbc_qbe tests/neon/test_neon_killswitch.bas -o ks_on

# Without NEON
ENABLE_NEON_COPY=0 ENABLE_NEON_ARITH=0 ENABLE_NEON_LOOP=0 \
    ./fbc_qbe tests/neon/test_neon_killswitch.bas -o ks_off
```

Both binaries must produce identical output. The test covers all operation
types: copy, addition, subtraction, multiplication, division, self-assignment,
copy-after-arithmetic, array loops, and array copies (17 assertions, run
in both modes = 34 total).

### Assembly Verification

The `--asm` mode generates assembly output and searches for expected NEON
instruction patterns:

```bash
grep -cE 'ldr\s+q2[89]' output.s          # NEON loads
grep -cE 'str\s+q2[89]' output.s          # NEON stores
grep -cE 'add\s+v2[89]\.' output.s        # NEON integer add
grep -cE 'fadd\s+v2[89]\.' output.s       # NEON float add
grep -cE 'fmul\s+v2[89]\.' output.s       # NEON float multiply
grep -cE 'fdiv\s+v2[89]\.' output.s       # NEON float divide
```

14 instruction categories are checked. All must be present for the
assembly verification to pass.

---

## 15. Known Limitations and Future Work

### Current Limitations

1. **Integer vector division**: NEON has no integer `sdiv` for vectors.
   Integer division falls back to scalar. This is an ARM64 ISA limitation.

2. **3-field UDTs**: Supported via padding to 4 lanes, but the padding lane
   wastes 25% of register width and requires zeroing on load.

3. **No partial vectorization**: If a UDT has mixed types (e.g., 3 integers
   and 1 string), the entire UDT is treated as non-SIMD. There is no attempt
   to vectorize just the integer fields.

4. **Cross-field operations**: Operations like `a.x + a.y` (horizontal) are
   only handled in the dedicated reduction path (Tier 4), not in the
   general arithmetic path.

5. **No loop unrolling in vectorized loops**: The current implementation
   processes one UDT element per iteration. LDP/STP-based ×2 unrolling
   (processing two elements per iteration) is designed but not yet implemented.

6. **Single target architecture**: Only ARM64 NEON is supported. x86_64
   SSE/AVX and RISC-V RVV use scalar fallback.

### Recommended Future Work

**High priority:**

- CI integration: run `scripts/run_neon_tests.sh --all` on push and PRs.
- Regression test for the MADD fusion cross-block bug (minimal reproducer).
- Tests for int→double precision edge cases.

**Medium priority:**

- ×2 loop unrolling with LDP/STP on Q registers (estimated 6.4× speedup).
- SSE/AVX mapping for x86_64 backend (same SIMDInfo classification, different
  opcode emission).
- IL-level assertions that UDT array element assignments never emit a
  single pointer-sized store.

**Lower priority:**

- Saturating arithmetic variants (`sqadd`, `uqadd`) via a BASIC keyword or
  type modifier.
- Fused multiply-add at the BASIC level (`C = A + B * D` → `neonldr` ×3 +
  `neonfma` + `neonstr`).
- Horizontal reduction optimizations for array-wide sums (accumulate in
  lanes, single `addv` at the end).

---

## 16. File Map

### Frontend (FasterBASIC)

| File | NEON-Related Content |
|------|---------------------|
| `fsh/FasterBASICT/src/codegen_v2/ast_emitter.h` | `SIMDLoopInfo` struct, NEON method declarations (`tryEmitNEONArithmetic`, `emitScalarUDTArithmetic`, `emitSIMDLoop`, `analyzeSIMDLoop`, `matchWholeUDTBinaryOp`, `matchWholeUDTCopy`, `simdArrangementCode`, `getUDTAddressForExpr`, `getUDTTypeNameForExpr`) |
| `fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp` | Pattern detection logic, NEON IL emission, scalar fallback implementation, array loop vectorization |
| `fsh/FasterBASICT/src/fasterbasic_ast.h` | `SIMDType` enum, `SIMDInfo` struct |
| `fsh/FasterBASICT/src/fasterbasic_semantic.h` | `SIMDInfo` on `TypeSymbol` |
| `fsh/FasterBASICT/src/fasterbasic_semantic.cpp` | `classifySIMDType()`, UDT SIMD eligibility detection |
| `fsh/FasterBASICT/src/codegen_v2/type_manager.h` | `getSIMDInfo()` method |

### QBE Backend

| File | NEON-Related Content |
|------|---------------------|
| `qbe_source/ops.h` | 15 NEON opcode definitions (`neonldr` through `neondup`) |
| `qbe_source/all.h` | `isneonstore()` macro |
| `qbe_source/arm64/targ.c` | V28–V30 removed from `arm64_rsave[]` |
| `qbe_source/arm64/isel.c` | `isneon()` check, pass-through with selective `fixarg()` |
| `qbe_source/arm64/emit.c` | `neon_arrangement()`, `neon_is_float()`, `neon_arr_from_arg()`, `neon_dup_gpr_prefix()`, all `case Oneon*` emission blocks, `prev_result_used_later()`, `try_madd_fusion()`, `try_msub_fusion()`, NEON kill-switch checks |
| `qbe_source/main.c` | Second `filllive()` call after register allocation |
| `qbe_source/load.c` | `isneonstore()` check in `def()` for load elimination |
| `qbe_source/alias.c` | `isneonstore()` check in `fillalias()` for alias analysis |
| `qbe_source/gcm.c` | `isneonstore()` check in `sink()` for global code motion |
| `qbe_source/mem.c` | `isneonstore()` check in `coalesce()` for memory coalescing |

### Tests and Scripts

| File | Content |
|------|---------|
| `tests/neon/*.bas` | 19 NEON test programs (244 assertions) |
| `scripts/run_neon_tests.sh` | Test runner with `--asm` and `--killswitch` modes |

### Documentation

| File | Content |
|------|---------|
| `FasterBasicNeon.md` | Full design document (1411 lines) |
| `articles/neon-simd-support.md` | User-facing guide with examples |
| `technotes/neon-compiler-internals.md` | This document |

---

*Last updated after commit f717eb6 — "Fix NEON testing failures: all 244 assertions + 36 kill-switch tests pass"*