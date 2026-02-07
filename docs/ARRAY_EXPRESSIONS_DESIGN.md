# Array Expressions — Technical Design Note

**Status:** Design / Pre-Implementation  
**Author:** FasterBASIC Compiler Team  
**Date:** February 2025  
**Depends on:** NEON SIMD Phase 3 (array loop vectorization), SIMDLoopInfo infrastructure

---

## 1. Overview

This document describes the design for **whole-array expressions** in FasterBASIC — a syntax that allows element-wise arithmetic, copy, fill, and scalar broadcast operations on entire arrays without explicit FOR loops.

The user writes:

```basic
C() = A() + B()
```

The compiler generates the same NEON-vectorized pointer loop that Phase 3 already emits for the equivalent FOR loop pattern. The key insight is that **all the codegen infrastructure already exists** — what's needed is a front-end syntax path that constructs a `SIMDLoopInfo` from array metadata and feeds it into the existing `emitSIMDLoop()`.

### Motivation

Currently, the compiler detects and vectorizes FOR loops that match patterns like:

```basic
FOR i = 0 TO N
  C(i) = A(i) + B(i)
NEXT i
```

This works, but forces the programmer to write boilerplate. Array expressions:

1. Eliminate the FOR/NEXT scaffolding
2. Communicate intent more directly
3. Give the compiler an unambiguous vectorization target (no loop-carried dependency analysis needed)
4. Align with Fortran, MATLAB, and NumPy idioms that programmers expect

---

## 2. Syntax

### 2.1 Whole-Array References

An array name followed by empty parentheses denotes a whole-array operand:

```
<array-ref> ::= <identifier> "()"
```

The parser already partially recognizes this in `parseLetStatement()`:

```cpp
// fasterbasic_parser.cpp, line ~1312
if (match(TokenType::LPAREN)) {
    // Support whole-array syntax: A() = ...
    // Empty parentheses means operate on entire array
    if (current().type != TokenType::RPAREN) {
        do {
            stmt->addIndex(parseExpression());
        } while (match(TokenType::COMMA));
    }
    consume(TokenType::RPAREN, "Expected ')' after array indices");
}
```

When `indices` is empty after parsing, the `LetStatement` represents a whole-array operation. This detection path already exists on the LHS — it needs to be extended to the RHS expression parser.

### 2.2 Supported Forms

```
<array-expr> ::= <array-ref> <binop> <array-ref>       (* element-wise *)
               | <array-ref> <binop> <scalar-expr>      (* broadcast right *)
               | <scalar-expr> <binop> <array-ref>      (* broadcast left *)
               | <array-ref>                             (* copy *)
               | <scalar-expr>                           (* fill *)
               | "-" <array-ref>                         (* negate *)

<array-assignment> ::= <array-ref> "=" <array-expr>

<binop> ::= "+" | "-" | "*" | "/"
```

Examples:

```basic
C() = A() + B()       ' element-wise add
C() = A() * 2.0       ' scalar broadcast multiply
C() = A()             ' whole-array copy
A() = 0               ' fill
B() = -A()            ' negate
```

### 2.3 Flag on LetStatement

A whole-array LHS is identified by:
- `stmt->indices` is **empty** (no index expressions)
- `stmt->variable` resolves to a known array in `symbolTable.arrays`
- `stmt->memberChain` is empty

No new AST node type is needed. The existing `LetStatement` with empty `indices` already represents this case.

---

## 3. Expression Parser Changes

### 3.1 Problem

Currently, `parsePrimary()` handles `A()` on the RHS as an `ArrayAccessExpression` with no indices. However, the expression parser doesn't explicitly flag this as a whole-array reference, and the binary expression tree built from `A() + B()` treats the `()` sub-expressions as zero-argument array accesses.

### 3.2 Required Change

In `parsePrimary()` (around line 6232 of `fasterbasic_parser.cpp`), when an identifier is followed by `()` with no index expressions inside, mark the resulting `ArrayAccessExpression` with a flag indicating it's a whole-array reference:

```cpp
// In parsePrimary(), after consuming LPAREN:
auto arrayAccess = std::make_unique<ArrayAccessExpression>(name, suffix);

if (current().type != TokenType::RPAREN) {
    do {
        arrayAccess->addIndex(parseExpression());
    } while (match(TokenType::COMMA));
}
// If indices is empty, this is a whole-array reference: A()
// The flag is implicit: arrayAccess->indices.size() == 0

consume(TokenType::RPAREN, "Expected ')' after array indices");
return arrayAccess;
```

This already works syntactically. The `ArrayAccessExpression` with `indices.size() == 0` is the whole-array reference. No parser change may be needed at all — just codegen detection.

### 3.3 AST Representation

Given `C() = A() + B()`, the AST is:

```
LetStatement
  variable: "C"
  indices: []                    ← empty = whole-array LHS
  value: BinaryExpression(PLUS)
    left:  ArrayAccessExpression("A", indices=[])  ← whole-array ref
    right: ArrayAccessExpression("B", indices=[])  ← whole-array ref
```

Given `B() = A() * 2.0`, the AST is:

```
LetStatement
  variable: "B"
  indices: []
  value: BinaryExpression(MULTIPLY)
    left:  ArrayAccessExpression("A", indices=[])
    right: NumberExpression(2.0)
```

Given `A() = 0`, the AST is:

```
LetStatement
  variable: "A"
  indices: []
  value: NumberExpression(0)
```

The codegen layer inspects these shapes to determine the operation class.

---

## 4. Semantic Validation

### 4.1 Type Checking

The semantic analyzer (or the codegen detection path) must verify:

1. **LHS is a declared array.** `stmt->variable` must exist in `symbolTable.arrays`.

2. **Element type is numeric.** String arrays are not supported (no SIMD path, reference counting makes element-wise ops meaningless).

3. **RHS array operands exist and have matching element types.** For `C() = A() + B()`, all three arrays must have the same `elementTypeDesc.baseType` (or the same `asTypeName` for UDT arrays).

4. **Scalar operands are type-compatible.** For `B() = A() * 2.0`, the scalar `2.0` must be convertible to the array's element type.

5. **Division constraints.** Integer division is not supported via NEON hardware — it falls back to scalar. Float division uses `neondiv`.

### 4.2 Bounds Handling

Array expressions operate over the **full declared range** of the destination array. At runtime:

- The destination array's bounds (lowerBound, upperBound) define the iteration range.
- Source arrays are bounds-checked against this range via `array_check_range()`.
- If source arrays are smaller than the destination, a runtime error is raised.

This reuses the existing bounds-checking infrastructure from `emitSIMDLoop()`.

### 4.3 Error Messages

| Condition | Error |
|---|---|
| LHS is not a declared array | `Array 'X' not declared` |
| RHS array has different element type | `Type mismatch in array expression: 'A' is SINGLE but 'B' is DOUBLE` |
| String array used in expression | `Array expressions not supported for STRING arrays` |
| Scalar type incompatible | `Cannot apply DOUBLE scalar to INTEGER array` |

---

## 5. Code Generation

### 5.1 Detection in emitLetStatement

Add a new detection block early in `emitLetStatement()`, before the existing scalar/UDT paths:

```cpp
void ASTEmitter::emitLetStatement(const LetStatement* stmt) {
    clearArrayElementCache();

    // ── NEW: Whole-array expression detection ──
    if (stmt->indices.empty() && stmt->memberChain.empty()) {
        const auto& symbolTable = semantic_.getSymbolTable();
        auto arrIt = symbolTable.arrays.find(stmt->variable);
        if (arrIt != symbolTable.arrays.end()) {
            if (tryEmitWholeArrayExpression(stmt, arrIt->second)) {
                return;
            }
            // Fall through to error or scalar handling
        }
    }

    // ... existing code paths ...
}
```

### 5.2 tryEmitWholeArrayExpression

This function inspects the RHS to classify the operation and build a `SIMDLoopInfo`:

```cpp
bool ASTEmitter::tryEmitWholeArrayExpression(
        const LetStatement* stmt,
        const ArraySymbol& destArray) {

    const auto& symbolTable = semantic_.getSymbolTable();
    const auto& value = stmt->value;

    // --- Case 1: Fill — A() = <scalar> ---
    if (!isWholeArrayRef(value.get())) {
        // RHS is a scalar expression (not an array reference)
        return emitArrayFill(stmt, destArray);
    }

    // --- Case 2: Copy — B() = A() ---
    if (value->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        auto* srcRef = static_cast<const ArrayAccessExpression*>(value.get());
        if (srcRef->indices.empty()) {
            return emitArrayCopy(stmt, destArray, srcRef);
        }
    }

    // --- Case 3: Unary negate — B() = -A() ---
    if (value->getType() == ASTNodeType::EXPR_UNARY) {
        auto* unary = static_cast<const UnaryExpression*>(value.get());
        if (unary->op == TokenType::MINUS && isWholeArrayRef(unary->operand.get())) {
            return emitArrayNegate(stmt, destArray, unary);
        }
    }

    // --- Case 4: Binary — C() = A() op B(), or B() = A() op scalar ---
    if (value->getType() == ASTNodeType::EXPR_BINARY) {
        auto* binExpr = static_cast<const BinaryExpression*>(value.get());
        return emitArrayBinaryOp(stmt, destArray, binExpr);
    }

    return false; // Not a recognized array expression
}
```

### 5.3 Operation Classification

`emitArrayBinaryOp` determines whether the expression is array-array or array-scalar:

```cpp
bool ASTEmitter::emitArrayBinaryOp(
        const LetStatement* stmt,
        const ArraySymbol& destArray,
        const BinaryExpression* binExpr) {

    bool leftIsArray  = isWholeArrayRef(binExpr->left.get());
    bool rightIsArray = isWholeArrayRef(binExpr->right.get());

    if (leftIsArray && rightIsArray) {
        // C() = A() + B() → element-wise
        return emitArrayArrayOp(stmt, destArray, binExpr);
    }
    if (leftIsArray && !rightIsArray) {
        // B() = A() + 5 → broadcast scalar right
        return emitArrayScalarOp(stmt, destArray, binExpr, /*scalarOnLeft=*/false);
    }
    if (!leftIsArray && rightIsArray) {
        // B() = 5 - A() → broadcast scalar left
        return emitArrayScalarOp(stmt, destArray, binExpr, /*scalarOnLeft=*/true);
    }

    return false; // Both scalars — not an array expression
}
```

### 5.4 Helper: isWholeArrayRef

```cpp
bool ASTEmitter::isWholeArrayRef(const Expression* expr) {
    if (!expr) return false;
    if (expr->getType() != ASTNodeType::EXPR_ARRAY_ACCESS) return false;
    auto* arr = static_cast<const ArrayAccessExpression*>(expr);
    if (!arr->indices.empty()) return false;
    // Verify it's a declared array
    const auto& symbolTable = semantic_.getSymbolTable();
    return symbolTable.arrays.count(arr->name) > 0;
}
```

---

## 6. Reusing emitSIMDLoop

### 6.1 Element-Wise Operations (Array-Array)

For `C() = A() + B()`, build a `SIMDLoopInfo` and call `emitSIMDLoop`:

```cpp
bool ASTEmitter::emitArrayArrayOp(
        const LetStatement* stmt,
        const ArraySymbol& destArray,
        const BinaryExpression* binExpr) {

    auto* leftArr  = static_cast<const ArrayAccessExpression*>(binExpr->left.get());
    auto* rightArr = static_cast<const ArrayAccessExpression*>(binExpr->right.get());

    // Look up source arrays
    const auto& symbolTable = semantic_.getSymbolTable();
    auto srcAIt = symbolTable.arrays.find(leftArr->name);
    auto srcBIt = symbolTable.arrays.find(rightArr->name);
    if (srcAIt == symbolTable.arrays.end() || srcBIt == symbolTable.arrays.end())
        return false;

    // Verify element types match
    if (destArray.elementTypeDesc.baseType != srcAIt->second.elementTypeDesc.baseType)
        return false;
    if (destArray.elementTypeDesc.baseType != srcBIt->second.elementTypeDesc.baseType)
        return false;

    // Determine element size and SIMD info
    int elemSize = getElementSizeBytes(destArray);
    auto simdInfo = getSIMDInfoForArrayElement(destArray);

    // Map operator to operation name
    std::string opName;
    switch (binExpr->op) {
        case TokenType::PLUS:     opName = "add"; break;
        case TokenType::MINUS:    opName = "sub"; break;
        case TokenType::MULTIPLY: opName = "mul"; break;
        case TokenType::DIVIDE:   opName = "div"; break;
        default: return false;
    }

    // Build SIMDLoopInfo
    SIMDLoopInfo info;
    info.isVectorizable = true;
    info.operation = opName;
    info.elemSizeBytes = elemSize;
    info.arrangementCode = simdArrangementCode(simdInfo);

    // Add operands (reuses existing SIMDLoopInfo::ArrayOperand)
    SIMDLoopInfo::ArrayOperand srcAOp;
    srcAOp.arrayName = leftArr->name;
    srcAOp.simdInfo = simdInfo;
    srcAOp.isReadOnly = true;

    SIMDLoopInfo::ArrayOperand srcBOp;
    srcBOp.arrayName = rightArr->name;
    srcBOp.simdInfo = simdInfo;
    srcBOp.isReadOnly = true;

    SIMDLoopInfo::ArrayOperand destOp;
    destOp.arrayName = stmt->variable;
    destOp.simdInfo = simdInfo;
    destOp.isReadOnly = false;

    info.operands = { srcAOp, srcBOp, destOp };
    info.srcAArrayIndex = 0;
    info.srcBArrayIndex = 1;
    info.destArrayIndex = 2;

    // Use array descriptor bounds instead of FOR loop bounds
    info.startIsConstant = false;  // read from descriptor at runtime
    info.endIsConstant = false;

    builder_.emitComment("Array expression: " + stmt->variable
        + "() = " + leftArr->name + "() " + opName + " " + rightArr->name + "()");

    emitWholeArraySIMDLoop(info);
    return true;
}
```

### 6.2 emitWholeArraySIMDLoop

This is a variant of `emitSIMDLoop` that reads bounds from array descriptors instead of FOR loop start/end expressions. The core NEON loop body is identical.

```cpp
void ASTEmitter::emitWholeArraySIMDLoop(const SIMDLoopInfo& info) {
    builder_.emitComment("=== Array expression: NEON vectorized loop ===");

    // 1. Get destination array bounds from descriptor
    std::string destDesc = getArrayDescriptorPtr(info.operands[info.destArrayIndex].arrayName);
    std::string lowerBound = builder_.newTemp();
    std::string upperBound = builder_.newTemp();
    builder_.emitCall(lowerBound, "w", "array_get_lower_bound", "l " + destDesc);
    builder_.emitCall(upperBound, "w", "array_get_upper_bound", "l " + destDesc);

    // 2. Bounds-check source arrays
    for (size_t i = 0; i < info.operands.size(); ++i) {
        if ((int)i == info.destArrayIndex) continue;
        std::string srcDesc = getArrayDescriptorPtr(info.operands[i].arrayName);
        std::string srcPtr = builder_.newTemp();
        builder_.emitLoad(srcPtr, "l", srcDesc);
        builder_.emitCall("", "", "array_check_range",
                         "l " + srcPtr + ", w " + lowerBound + ", w " + upperBound);
    }

    // 3. Get data pointers
    std::vector<std::string> basePtrs;
    for (const auto& op : info.operands) {
        std::string descPtr = getArrayDescriptorPtr(op.arrayName);
        std::string arrPtr = builder_.newTemp();
        builder_.emitLoad(arrPtr, "l", descPtr);
        std::string dataPtr = builder_.newTemp();
        builder_.emitCall(dataPtr, "l", "array_get_data_ptr", "l " + arrPtr);
        basePtrs.push_back(dataPtr);
    }

    // 4. Compute byte range
    //    (identical to emitSIMDLoop steps 4–7, using lowerBound/upperBound
    //     instead of FOR start/end)

    // ... pointer loop with neonldr/neonldr2/neonop/neonstr ...
    // ... scalar remainder for non-aligned tail ...

    builder_.emitComment("=== End array expression loop ===");
}
```

The inner loop body is byte-identical to what `emitSIMDLoop` already generates. The only difference is where the iteration bounds come from (array descriptor vs. FOR loop variables).

### 6.3 Refactoring Opportunity

To avoid code duplication, extract the core NEON loop from `emitSIMDLoop` into a shared helper:

```cpp
// Shared: emit the pointer-based NEON loop body
void ASTEmitter::emitNEONPointerLoop(
    const std::vector<std::string>& basePtrs,
    const std::string& startOffset,
    const std::string& totalBytes,
    const SIMDLoopInfo& info);
```

Both `emitSIMDLoop` (FOR loop path) and `emitWholeArraySIMDLoop` (array expression path) call this shared helper. The difference is only in how `startOffset` and `totalBytes` are computed.

---

## 7. Scalar Broadcast

### 7.1 Problem

For `B() = A() * 2.0`, one operand is a scalar. The existing NEON loop uses `neonldr` + `neonldr2` to load two 128-bit values. For broadcast, one of those loads must be replaced with a scalar-to-vector duplication.

### 7.2 Approach: Pre-Broadcast to Stack

The simplest approach that requires **no new QBE opcodes**:

1. Evaluate the scalar expression to a QBE temporary.
2. Allocate a 16-byte aligned stack slot.
3. Store the scalar value to all lanes of the stack slot (4 stores for 32-bit, 2 for 64-bit).
4. Use `neonldr2` to load from this slot into q29.
5. Hoist this load above the loop — q29 stays constant.
6. The loop body uses `neonldr` (source array) + `neonop` + `neonstr` (dest).

```
; Pre-broadcast: fill 16-byte slot with scalar value
    %bcast =l alloc16 16
    stores %scalar, %bcast
    %off4 =l add %bcast, 4
    stores %scalar, %off4
    %off8 =l add %bcast, 8
    stores %scalar, %off8
    %off12 =l add %bcast, 12
    stores %scalar, %off12

    neonldr2 %bcast          ; q29 = [scalar, scalar, scalar, scalar]

; Loop body (q29 is invariant):
loop:
    neonldr  %srcAddr         ; q28 = A(i..i+3)
    neonmul  2                ; q28 = q28 * q29  (.4s float)
    neonstr  %dstAddr         ; B(i..i+3) = result
    ; advance pointers ...
```

### 7.3 Alternative: neondup Opcode

A cleaner approach adds a new QBE pseudo-opcode:

```
neondup <arrangement> <value>
```

which emits ARM64 `dup v29.4s, w0` (or `dup v29.2d, x0` for 64-bit). This populates q29 with the scalar and is hoisted before the loop.

This is a single new case in the QBE ARM64 emitter alongside the existing `neonldr`, `neonldr2`, etc. handlers.

### 7.4 Recommendation

Start with the pre-broadcast-to-stack approach (7.2). It works today with zero QBE changes. Add `neondup` later as a performance refinement — it saves 3–7 stores and a load per array expression invocation (negligible for large arrays).

---

## 8. Array Fill

### 8.1 Pattern

```basic
A() = 0
A() = 3.14
```

### 8.2 Implementation

Array fill is a special case of scalar broadcast with no source array:

1. Broadcast the scalar to a 16-byte stack slot (or use `neondup`).
2. Load into q28 via `neonldr`.
3. Loop: `neonstr` to consecutive addresses.

For the common case `A() = 0`, emit `movi v28.4s, #0` (ARM64 immediate zero) — even cheaper. This could be a future optimization; the generic broadcast path handles it correctly if less efficiently.

### 8.3 Code Path

```cpp
bool ASTEmitter::emitArrayFill(
        const LetStatement* stmt,
        const ArraySymbol& destArray) {

    // Evaluate the fill value
    BaseType elemType = destArray.elementTypeDesc.baseType;
    std::string fillValue = emitExpressionAs(stmt->value.get(), elemType);

    // Get array descriptor and bounds
    std::string descPtr = getArrayDescriptorPtr(stmt->variable);
    // ... get data pointer, lower/upper bounds ...

    // Broadcast fill value to 16-byte aligned slot
    // ... (same as scalar broadcast pre-loop setup) ...

    // neonldr from broadcast slot → q28
    // Loop: neonstr to consecutive dest addresses
    // ... pointer advance, termination check ...

    return true;
}
```

---

## 9. Array Negate

### 9.1 Pattern

```basic
B() = -A()
```

### 9.2 Implementation

Negate can be expressed as `0 - A()`:

1. Zero q29 (or use `movi v29.4s, #0`).
2. Loop: `neonldr` source into q28, `neonsub` (q28 = q29 - q28 — note: need reversed operand order), `neonstr` to dest.

### 9.3 Operand Order Problem

The existing `neonsub` computes `q28 = q28 - q29`. For negate, we need `q28 = 0 - q28`, which is `q28 = q29 - q28` (reversed).

Options:

1. **New opcode `neonneg`**: emits `fneg v28.4s, v28.4s` (for float) or `neg v28.4s, v28.4s` (for int). Simplest and most efficient.
2. **Reverse-subtract opcode `neonrsub`**: emits `sub v28.4s, v29.4s, v28.4s`. More general.
3. **Load zero, swap, subtract**: Load 0 into q28 via broadcast, load source into q29 via `neonldr2`, then `neonsub`. Works with existing opcodes but wastes a register.

Recommendation: Option 3 for initial implementation (zero QBE changes). Add `neonneg` later.

---

## 10. Numeric Array SIMD

### 10.1 Current State

The existing SIMD infrastructure focuses on **UDT arrays** — types like `Vec4` that pack into a single 128-bit register. Plain numeric arrays (`DIM A(100) AS SINGLE`) are not currently SIMD-accelerated in the array loop vectorizer.

### 10.2 Extension

Plain numeric arrays are actually the **best** SIMD candidates because multiple consecutive elements naturally pack into a NEON register:

| Element Type | QBE Suffix | Bytes | Per Q Register | Arrangement |
|---|---|---|---|---|
| `BYTE` | `b` | 1 | 16 | `.16b` |
| `SHORT` | `h` | 2 | 8 | `.8h` |
| `INTEGER` | `w` | 4 | 4 | `.4s` |
| `SINGLE` | `s` | 4 | 4 | `.4s` |
| `LONG` | `l` | 8 | 2 | `.2d` |
| `DOUBLE` | `d` | 8 | 2 | `.2d` |

### 10.3 getSIMDInfoForArrayElement

A new helper that constructs a `SIMDInfo` from an array's element type (rather than from a UDT definition):

```cpp
TypeDeclarationStatement::SIMDInfo ASTEmitter::getSIMDInfoForArrayElement(
        const ArraySymbol& arr) {
    TypeDeclarationStatement::SIMDInfo info;
    info.type = TypeDeclarationStatement::SIMDType::NONE;

    BaseType elemType = arr.elementTypeDesc.baseType;
    switch (elemType) {
        case BaseType::INTEGER:
            info.type = TypeDeclarationStatement::SIMDType::V4S;
            info.laneCount = 4;
            info.physicalLanes = 4;
            info.laneBitWidth = 32;
            info.totalBytes = 16;
            info.isFullQ = true;
            info.isFloatingPoint = false;
            info.laneType = BaseType::INTEGER;
            break;
        case BaseType::FLOAT:  // SINGLE
            info.type = TypeDeclarationStatement::SIMDType::V4S;
            info.laneCount = 4;
            info.physicalLanes = 4;
            info.laneBitWidth = 32;
            info.totalBytes = 16;
            info.isFullQ = true;
            info.isFloatingPoint = true;
            info.laneType = BaseType::FLOAT;
            break;
        case BaseType::DOUBLE:
            info.type = TypeDeclarationStatement::SIMDType::V2D;
            info.laneCount = 2;
            info.physicalLanes = 2;
            info.laneBitWidth = 64;
            info.totalBytes = 16;
            info.isFullQ = true;
            info.isFloatingPoint = true;
            info.laneType = BaseType::DOUBLE;
            break;
        // ... LONG, SHORT, BYTE ...
        default:
            break;  // Not SIMD-eligible
    }
    return info;
}
```

### 10.4 Element Size vs. Register Size

For numeric arrays, the element size (4 bytes for INTEGER) differs from the NEON register width (16 bytes). The loop processes `registerWidth / elementSize` elements per iteration.

This contrasts with UDT arrays where each element is exactly 16 bytes (one Q register). The `elemSizeBytes` field in `SIMDLoopInfo` must be set to the **register width** (16), not the element width (4), since the pointer advances by 16 bytes per iteration.

The remainder loop handles the tail when `arrayLength % lanesPerRegister != 0`.

---

## 11. Scalar Fallback

### 11.1 Non-NEON Platforms

On x86_64 and RISC-V (or when NEON is disabled), array expressions must still work. The codegen emits a simple scalar loop:

```
; Scalar fallback for C() = A() + B()
    ; get bounds and data pointers (same as NEON path)
    ; for each element:
    ;   load A(i), load B(i), add, store C(i)
```

### 11.2 Kill-Switch

Reuse the existing `ENABLE_NEON_LOOP` environment variable. When disabled, `tryEmitWholeArrayExpression` either:

1. Falls through to a scalar loop emitter, or
2. Synthesizes a FOR loop AST and lets the existing scalar FOR codegen handle it.

Option 2 is simpler — construct a synthetic `ForStatement` with the array bounds and a body of `C(i) = A(i) + B(i)`, then call the normal `emitForStatement`.

---

## 12. Remainder Handling

### 12.1 Problem

If an array has 102 `SINGLE` elements and NEON processes 4 per iteration, the main loop handles 100 elements (25 iterations). The remaining 2 elements need a scalar epilogue.

### 12.2 Implementation

After the main NEON loop exits:

```
; Main loop processed: 0..99 (25 NEON iterations × 4 elements)
; Remainder: 100, 101

remainder_loop:
    ; if offset >= totalBytes, goto done
    ; load single element from A, load single element from B
    ; scalar add
    ; store to C
    ; advance offset by elementSize (4 bytes)
    ; goto remainder_loop
done:
```

The existing `emitSIMDLoop` doesn't currently handle remainders (it relies on array lengths being multiples of the lane count because UDTs are exactly 128 bits). **Array expressions on numeric arrays require adding this remainder loop.**

### 12.3 Alternative: Over-Allocate Arrays

A simpler strategy: ensure array allocations are rounded up to the nearest 16-byte boundary. The NEON loop can then safely read/write past the logical end of the array (the memory is allocated but the values are ignored). This avoids the remainder loop entirely.

This requires a change in `array_descriptor_alloc()` to align allocation sizes.

Recommendation: implement the remainder loop first (correctness), then consider over-allocation as an optimization.

---

## 13. Implementation Phases

### Phase A: Core Array Expressions (Tier 1)

**Scope:** Element-wise arithmetic and copy for UDT arrays only (leveraging existing SIMD infrastructure completely).

1. Add `isWholeArrayRef()` helper
2. Add `tryEmitWholeArrayExpression()` detection in `emitLetStatement()`
3. Add `emitArrayArrayOp()` — builds `SIMDLoopInfo`, calls `emitSIMDLoop` variant
4. Add `emitArrayCopy()` — builds `SIMDLoopInfo` with copy operation
5. Refactor `emitSIMDLoop` to accept bounds from array descriptors

**Files changed:** `ast_emitter.cpp`, `ast_emitter.h`  
**Estimated effort:** ~200 lines of new code  
**Test:** `C() = A() + B()` for `Vec4` arrays produces same output as FOR loop version

### Phase B: Numeric Array Support

**Scope:** Extend SIMD support from UDT arrays to plain numeric arrays.

1. Add `getSIMDInfoForArrayElement()` for primitive types
2. Handle element size != register size in loop pointer arithmetic
3. Add remainder loop for non-aligned array lengths
4. Test with INTEGER, SINGLE, DOUBLE, LONG arrays

**Files changed:** `ast_emitter.cpp`, `type_manager.cpp`  
**Estimated effort:** ~150 lines  
**Test:** `C() = A() + B()` for `SINGLE` arrays, length not multiple of 4

### Phase C: Scalar Broadcast and Fill

**Scope:** `B() = A() * 2.0` and `A() = 0`.

1. Add pre-broadcast-to-stack helper
2. Add `emitArrayScalarOp()` with hoisted broadcast load
3. Add `emitArrayFill()` as special case
4. Test broadcast from both sides: `B() = A() * 2` and `B() = 2 * A()`

**Files changed:** `ast_emitter.cpp`  
**Estimated effort:** ~100 lines  
**Test:** `B() = A() * 2.0`, `A() = 0`, `B() = 10.0 - A()`

### Phase D: Negate and Scalar Fallback

**Scope:** `B() = -A()`, plus non-NEON platform support.

1. Add `emitArrayNegate()` using zero-subtract pattern
2. Add scalar fallback loop for non-ARM64 targets
3. Verify kill-switch works correctly

**Files changed:** `ast_emitter.cpp`  
**Estimated effort:** ~80 lines

### Phase E: Future — Reductions, Compound Expressions

**Scope:** `SUM(A())`, `DOT(A(), B())`, `D() = A() + B() * C()`.

Deferred to a later design cycle. Requires new runtime functions for horizontal reductions and potentially fused multiply-add opcode support.

---

## 14. File Change Summary

| File | Changes |
|---|---|
| `fsh/FasterBASICT/src/fasterbasic_parser.cpp` | Verify `A()` parsing in expressions (may already work) |
| `fsh/FasterBASICT/src/codegen_v2/ast_emitter.h` | Declare new methods: `tryEmitWholeArrayExpression`, `emitArrayArrayOp`, `emitArrayCopy`, `emitArrayFill`, `emitArrayScalarOp`, `emitArrayNegate`, `isWholeArrayRef`, `getSIMDInfoForArrayElement`, `emitWholeArraySIMDLoop` |
| `fsh/FasterBASICT/src/codegen_v2/ast_emitter.cpp` | Implement all new methods; add detection in `emitLetStatement` |
| `fsh/FasterBASICT/src/codegen_v2/type_manager.cpp` | Possibly extend `getSIMDInfo` for primitive element types |
| `fsh/FasterBASICT/runtime_c/basic_runtime.c` | Add `array_get_lower_bound()`, `array_get_upper_bound()` if not already exposed |

---

## 15. Testing Strategy

### 15.1 Correctness Tests

Each operation class needs a test that:
1. Initializes source arrays with known values
2. Performs the array expression
3. Verifies each result element matches the expected scalar computation

```basic
' test_array_expr_add.bas
DIM A(10) AS SINGLE
DIM B(10) AS SINGLE
DIM C(10) AS SINGLE

FOR i = 0 TO 10
  A(i) = i * 1.5
  B(i) = i * 0.5
NEXT i

C() = A() + B()

FOR i = 0 TO 10
  IF C(i) <> A(i) + B(i) THEN
    PRINT "FAIL at index "; i
    END
  ENDIF
NEXT i
PRINT "PASS: array add"
```

### 15.2 Edge Cases

- Arrays of length 1
- Arrays of length 0 (empty after ERASE)
- Arrays where length is not a multiple of NEON lane count (remainder handling)
- In-place operation: `A() = A() + B()`
- Same array on both sides: `A() = A() + A()` (effectively `A() = A() * 2`)
- Fill with zero, fill with negative, fill with large value
- Scalar broadcast with integer and float types
- Division by zero in array (runtime error or IEEE behavior)

### 15.3 Verification Against FOR Loop

For every array expression test, also run the equivalent FOR loop version and verify identical results. This ensures the array expression path produces the same output as the already-validated loop vectorizer.

### 15.4 Kill-Switch Test

Run each test with `ENABLE_NEON_LOOP=0` to verify the scalar fallback produces correct results.

---

## 16. Open Questions

1. **Multi-dimensional arrays.** Should `C(,) = A(,) + B(,)` work for 2D arrays? The underlying storage is contiguous, so the SIMD loop would work identically. The question is whether to support the syntax now or defer.

2. **Mixed-precision broadcast.** Should `B() = A() + 1` work when `A` is `SINGLE` and `1` is parsed as `INTEGER`? Implicit conversion is natural but adds complexity.

3. **REDIM interaction.** If `A` is REDIMed after `DIM`, the array bounds change at runtime. The expression must use runtime bounds (from the descriptor), not compile-time bounds. This is already handled by reading from the descriptor.

4. **OPTION BASE.** Array expressions must respect `OPTION BASE 0` vs `OPTION BASE 1`. The descriptor's `lowerBound` field handles this transparently.

5. **Compound expressions.** Should `D() = A() + B() * C()` be a single expression, or require a temporary? Supporting it directly enables FMLA on ARM64, but adds expression tree complexity. Deferred to Phase E.

6. **Assignment operators.** Should `A() += B()` sugar be supported? Not a BASIC tradition, but convenient. Probably not — `A() = A() + B()` is clear enough and the in-place case is already handled.