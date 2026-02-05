# Logical Operators Fix Summary

## Problem

Logical operators (AND, OR, NOT) were failing when used with string comparisons or mixed string/integer comparisons.

### Symptoms

```basic
' These worked:
IF A = 10 AND B = 20 THEN PRINT "PASS"           ' ✅ Integer AND Integer

' These failed:
IF S$ = "Hello" AND C = 5 THEN PRINT "PASS"      ' ❌ String AND Integer
IF S1$ = "A" AND S2$ = "B" THEN PRINT "PASS"     ' ❌ String AND String
```

The bug affected all logical operators when any operand involved a string comparison.

## Root Cause

The bug was in `getExpressionType()` in `ast_emitter.cpp`. The function determines the result type of an expression, which is used to decide how to emit code.

**Original (buggy) logic:**
```cpp
case ASTNodeType::EXPR_BINARY: {
    BaseType leftType = getExpressionType(binExpr->left.get());
    BaseType rightType = getExpressionType(binExpr->right.get());
    
    // String operations always return string
    if (typeManager_.isString(leftType) || typeManager_.isString(rightType)) {
        return BaseType::STRING;  // ❌ WRONG for comparisons!
    }
    
    // Comparison operations return INTEGER (boolean)
    if (binExpr->op >= TokenType::EQUAL && binExpr->op <= TokenType::GREATER_EQUAL) {
        return BaseType::INTEGER;
    }
    // ...
}
```

### The Problem

When evaluating `S$ = "Hello" AND C = 5`:
1. The AND operator has two operands: `(S$ = "Hello")` and `(C = 5)`
2. For the left operand `(S$ = "Hello")`, `getExpressionType()` was called
3. It checked the operand types (STRING and STRING)
4. **BUG**: It returned `BaseType::STRING` before checking if this was a comparison
5. The comparison check never executed
6. The AND operator saw operand type STRING and called `emitStringOp()`
7. `emitStringOp()` doesn't support AND, so it returned `"0"` with an error
8. The generated code had `jnz 0, @then, @else` - always taking the false branch

## The Fix

**Move the comparison check BEFORE the string type check:**

```cpp
case ASTNodeType::EXPR_BINARY: {
    const auto* binExpr = static_cast<const BinaryExpression*>(expr);
    
    // Comparison operations ALWAYS return INTEGER (boolean), regardless of operand types
    if (binExpr->op >= TokenType::EQUAL && binExpr->op <= TokenType::GREATER_EQUAL) {
        return BaseType::INTEGER;  // ✅ Check this FIRST
    }
    
    BaseType leftType = getExpressionType(binExpr->left.get());
    BaseType rightType = getExpressionType(binExpr->right.get());
    
    // String concatenation returns string
    if (typeManager_.isString(leftType) || typeManager_.isString(rightType)) {
        return BaseType::STRING;
    }
    
    // Arithmetic operations promote to common type
    return typeManager_.getPromotedType(leftType, rightType);
}
```

### Why This Works

1. **Comparison check first**: Before looking at operand types, check if this is a comparison operator
2. **Comparisons always return boolean**: `S$ = "Hello"` returns an INTEGER (0 or 1), not a STRING
3. **Then check for strings**: Only after ruling out comparisons, check if operands are strings (for concatenation)
4. **Result**: The AND operator now sees INTEGER operands and correctly emits bitwise AND

## Secondary Bug: LONG Literal Typing

While fixing the AND operator, we discovered a related issue with large integer literals.

### Problem

```basic
Big = 9999999999
IF Big = 9999999999 THEN PRINT "PASS"  ' ❌ Failed
```

Large integers like `9999999999` (which fit in INT64 but not INT32) were being typed as DOUBLE instead of LONG.

### Root Cause

In `getExpressionType()` for number literals:

```cpp
// Original (buggy)
if (numExpr->value == std::floor(numExpr->value) && 
    numExpr->value >= INT32_MIN && numExpr->value <= INT32_MAX) {
    return BaseType::INTEGER;
} else {
    return BaseType::DOUBLE;  // ❌ Wrong for large integers!
}
```

### The Fix

```cpp
// Fixed
if (numExpr->value == std::floor(numExpr->value)) {
    // Integer literal - check range
    if (numExpr->value >= INT32_MIN && numExpr->value <= INT32_MAX) {
        return BaseType::INTEGER;
    } else if (numExpr->value >= INT64_MIN && numExpr->value <= INT64_MAX) {
        return BaseType::LONG;  // ✅ Proper LONG typing
    } else {
        return BaseType::DOUBLE;  // Only for truly huge values
    }
} else {
    return BaseType::DOUBLE;  // Has fractional part
}
```

### Impact

- Large integer literals now typed as LONG instead of DOUBLE
- Comparisons with large integers are exact (no floating-point precision loss)
- Better type promotion: LONG + INTEGER = LONG, not DOUBLE

## Test Results

### Before Fix
```
Test 1: Integer comparisons          ✅ PASS
Test 2: String and integer            ❌ FAIL
Test 3: Two string comparisons        ❌ FAIL
```

### After Fix
```
Test 1: Integer comparisons          ✅ PASS
Test 2: String and integer            ✅ PASS
Test 3: Two string comparisons        ✅ PASS
```

### Comprehensive Test
```basic
REM All of these now work correctly:
IF A = 10 AND B = 20 THEN PRINT "PASS"                    ' ✅
IF S$ = "Hello" AND C = 5 THEN PRINT "PASS"               ' ✅
IF S1$ = "A" AND S2$ = "B" THEN PRINT "PASS"              ' ✅
IF C$ = "Wrong" OR D = 5 THEN PRINT "PASS"                ' ✅
IF NOT (E$ = "Wrong") THEN PRINT "PASS"                   ' ✅
IF (F$ = "A" AND G = 1) OR (H$ = "B" AND I = 2) THEN ...  ' ✅
IF Big = 9999999999 AND Count = 123456789 THEN ...        ' ✅
```

## Impact on UDT Tests

This fix unblocked UDT tests that were failing due to the AND operator bug:

- `test_udt_string.bas` - Now ✅ PASS (was FAIL)
- `test_udt_long.bas` - Now ✅ PASS (was FAIL)

All UDT tests now pass successfully.

## Files Modified

1. **`codegen_v2/ast_emitter.cpp`**
   - `getExpressionType()` - Moved comparison check before string check
   - `getExpressionType()` - Added LONG typing for large integer literals

## Lessons Learned

1. **Order matters**: When checking expression types, order of checks is critical
2. **Type semantics**: Comparison operations return boolean (INTEGER), not the type of their operands
3. **Integer ranges**: Need to handle INT32, INT64, and DOUBLE ranges separately
4. **Test coverage**: String comparisons in logical expressions were not adequately tested
5. **Cascading bugs**: One bug (AND operator) masked another (LONG literal typing)

## Future Improvements

1. Add regression tests for logical operators with all type combinations
2. Document type promotion rules more clearly
3. Consider adding explicit boolean type (instead of using INTEGER for booleans)
4. Add more comprehensive numeric literal tests (edge cases around INT32_MAX, INT64_MAX)