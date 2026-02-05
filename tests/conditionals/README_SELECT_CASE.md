# SELECT CASE Test Suite

This directory contains comprehensive tests for the SELECT CASE statement, including type handling and automatic type conversion.

## Test Files

### test_select_case.bas
**Primary comprehensive test** - Tests all SELECT CASE variants with both integer and double types.

**Tests covered:**
1. Integer SELECT with integer CASE values
2. Integer SELECT with range (CASE x TO y)
3. Integer SELECT with multiple values (CASE 1, 2, 3)
4. CASE ELSE clause
5. CASE IS conditional tests (integer)
6. Double SELECT with double CASE values
7. Double SELECT with range
8. CASE IS conditional tests (double)
9. Integer SELECT with automatic type conversion
10. Double SELECT with multiple values

**Expected behavior:** All tests should output "PASS" messages, no "ERROR" messages.

### test_select_advanced.bas
**Advanced features demonstration** - Showcases SELECT CASE features that C/Java/C++ switch statements CANNOT do.

**Tests covered:**
1. Range comparisons (switch: IMPOSSIBLE)
2. Floating-point values (switch: COMPILE ERROR)
3. Relational operators CASE IS (switch: IMPOSSIBLE)
4. Negative ranges (switch: IMPOSSIBLE)
5. Multiple values without fallthrough (switch: error-prone)
6. Mixed ranges and discrete values (switch: IMPOSSIBLE)
7. Double precision ranges (switch: COMPILE ERROR)
8. Zero boundary ranges (switch: IMPOSSIBLE)
9. Percentage classification with ranges (switch: needs 101 case labels!)
10. Scientific notation ranges (switch: COMPILE ERROR)
11. No fallthrough bugs (switch: COMMON BUG)
12. Complex business logic ranges (switch: must use if-else)

**Expected behavior:** All tests should output "PASS" messages demonstrating SELECT CASE superiority over switch.

**Purpose:** This test serves as both regression testing and documentation of why SELECT CASE is more powerful than switch.

### test_select_types.bas
**Type handling edge cases** - Focuses on type conversions and boundary conditions.

**Tests covered:**
1. Integer/Integer matching (no conversion)
2. Double/Double matching (no conversion)
3. Integer SELECT with ranges
4. Double SELECT with ranges
5. Multiple values with integers
6. Multiple values with doubles
7. CASE IS with integers
8. CASE IS with doubles
9. Integer boundary test (zero)
10. Double boundary test (0.0)
11. Negative integer ranges
12. Negative double ranges

**Expected behavior:** All tests should output "PASS" messages, no "ERROR" messages.

### test_select_demo.bas
**Real-world demonstration** - Shows practical usage of SELECT CASE with different types.

**Demonstrates:**
- Grade classification (integer ranges)
- Pi approximation matching (double ranges)
- Day of week selection
- All CASE syntax variants
- Temperature classification (real-world double ranges)

**Expected behavior:** Should demonstrate all features working correctly with descriptive output.

## Key Features Tested

### Automatic Type Matching
The compiler automatically handles type conversions between SELECT expressions and CASE values:

```basic
' Integer SELECT - CASE values auto-converted to integer
DIM i%
i% = 42
SELECT CASE i%
    CASE 42        ' Compared as integer (no conversion)
    CASE 3.14      ' 3.14 converted to 3, then compared
END SELECT

' Double SELECT - CASE values auto-converted to double
DIM d#
d# = 3.14
SELECT CASE d#
    CASE 3.14      ' Compared as double (no conversion)
    CASE 3         ' 3 converted to 3.0, then compared
END SELECT
```

### Supported CASE Variants

1. **Single value:** `CASE 42`
2. **Multiple values:** `CASE 1, 2, 3`
3. **Range:** `CASE 10 TO 20`
4. **Conditional:** `CASE IS > 50`
5. **Else clause:** `CASE ELSE`

All variants work with both INTEGER and DOUBLE types.

### Why SELECT CASE is Superior to C-style switch

SELECT CASE can do many things that switch statements in C, C++, Java, and JavaScript cannot:

1. **Range comparisons:** `CASE 10 TO 20` (switch requires listing all values or using if-else)
2. **Floating-point values:** Works with doubles (switch gives compile error in C/C++)
3. **Relational operators:** `CASE IS > 100` (switch cannot do this)
4. **No fallthrough bugs:** Each case auto-completes (switch requires manual break statements)
5. **Mixed conditions:** Can combine ranges, discrete values, and relational tests

See `test_select_advanced.bas` for demonstrations of all these features.

## Running the Tests

### Run all SELECT CASE tests:
```bash
# From project root
for test in tests/conditionals/test_select*.bas; do
    ./qbe_basic -o /tmp/test_temp "$test" && /tmp/test_temp
done
```

### Run individual test:
```bash
./qbe_basic -o test_select tests/conditionals/test_select_case.bas
./test_select
```

### Expected output format:
All tests follow the pattern:
```
=== Test Name ===

Test 1: Description
PASS: Success message

Test 2: Description
PASS: Success message

=== All Tests PASSED ===
```

Any line starting with "ERROR:" indicates a test failure.

## Type Conversion Rules

### When SELECT is INTEGER:
- Integer CASE values: Direct comparison (optimal)
- Double CASE values: Converted to integer using `dtosi` (truncation)

### When SELECT is DOUBLE:
- Double CASE values: Direct comparison (optimal)
- Integer CASE values: Converted to double using `sltof`

### Code Generation Quality:
The compiler generates minimal conversions:
- Same types: Zero conversions
- Mixed types: One conversion (CASE value to SELECT type)

## Regression Testing

These tests protect against:
1. **Type confusion** - SELECT DOUBLE tried to convert already-double values
2. **Missing type inference** - Not checking actual CASE value types
3. **Inverted conversion logic** - Converting the wrong operand
4. **Range handling bugs** - Incorrect range endpoint conversions
5. **Multiple value bugs** - Not handling OR-chains of different types
6. **CASE IS bugs** - Conditional comparisons with wrong types

## Historical Context

Prior to the fix (see `docs/SELECT_CASE_TYPE_GLYPH_ANALYSIS.md`):
- SELECT CASE with DOUBLE variables failed with QBE IL errors
- Type conversion logic was inverted
- Compiler assumed all CASE values were doubles

After the fix:
- Full type inference for both SELECT and CASE expressions
- Automatic type matching with minimal conversions
- All CASE variants work with all numeric types

## Adding New Tests

When adding SELECT CASE tests:

1. **Use descriptive test names** that indicate what's being tested
2. **Use PASS/ERROR pattern** for easy automated validation
3. **Test both INTEGER and DOUBLE** for complete coverage
4. **Include edge cases** like zero, negatives, boundaries
5. **Create .expected files** for automated comparison

Example test structure:
```basic
10 PRINT "Test X: Description"
20 DIM var%
30 var% = value
40 SELECT CASE var%
50   CASE expected
60     PRINT "PASS: Correct match"
70   CASE ELSE
80     PRINT "ERROR: Should have matched"
90 END SELECT
```

## See Also

- `docs/SELECT_CASE_VS_SWITCH.md` - Why SELECT CASE is superior to switch statements
- `docs/SELECT_CASE_TYPE_GLYPH_ANALYSIS.md` - Comprehensive type handling analysis
- `SELECT_CASE_FIX_SUMMARY.md` - Quick fix summary
- `VERIFICATION_COMPLETE.md` - Final verification report
- `START_HERE.md` - Type system documentation
- `TEST_SUITE_UPDATE.md` - Test suite addition summary