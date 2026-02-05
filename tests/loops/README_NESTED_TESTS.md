# Nested Control Flow Tests

## Overview

This directory contains comprehensive tests for nested control flow structures to verify the CFG (Control Flow Graph) builder handles complex nesting correctly.

**Created:** February 1, 2025  
**Purpose:** Identify and fix fragile CFG builder issues with nested control structures  
**Status:** Active test suite for CFG validation

---

## Background

The CFG builder has historically been fragile with nested control flow structures. Previous issues included:

- WHILE loops inside IF statements executing only once (FIXED - Jan 2025)
- FOR loops inside IF statements not iterating properly (FIXED - Jan 2025)
- Missing loop header blocks and back-edges in nested structures

These tests systematically verify all combinations of nested control structures to catch CFG building errors.

---

## Test Files

### 1. `test_nested_while_if.bas`
**Tests:** WHILE loops nested with IF statements  
**Covers:**
- WHILE in IF THEN
- WHILE in IF ELSE
- WHILE in multiple IF branches
- IF inside WHILE
- Deep nesting (WHILE in IF in WHILE)
- Multiple WHILEs in same IF block

**Key Patterns:**
```basic
' Pattern 1: WHILE in IF
IF condition THEN
    WHILE inner <= 5
        ' Should iterate 5 times
    WEND
END IF

' Pattern 2: IF in WHILE
WHILE outer <= 3
    IF condition THEN
        ' Should evaluate each iteration
    END IF
WEND
```

### 2. `test_nested_if_while.bas`
**Tests:** IF statements nested inside WHILE loops  
**Covers:**
- Simple IF in WHILE
- IF-ELSE in WHILE
- Multiple IFs in WHILE
- Nested IF in WHILE
- Complex conditions in WHILE
- IF affecting WHILE control flow

**Key Patterns:**
```basic
WHILE i <= 5
    IF i MOD 2 = 0 THEN
        ' Even number processing
    ELSE
        ' Odd number processing
    END IF
    i = i + 1
WEND
```

### 3. `test_nested_repeat_if.bas`
**Tests:** REPEAT UNTIL loops nested with IF statements  
**Covers:**
- REPEAT in IF THEN
- REPEAT in IF ELSE
- IF inside REPEAT
- Multiple REPEATs in IF branches
- Complex exit conditions
- Deep nesting (REPEAT in IF in REPEAT)
- Early termination with IF

**Key Patterns:**
```basic
' Post-test loop with IF
REPEAT
    IF condition THEN
        ' Conditional processing
    END IF
    i = i + 1
UNTIL i > 5
```

### 4. `test_nested_do_if.bas`
**Tests:** DO LOOP variants nested with IF statements  
**Covers:**
- DO WHILE in IF
- DO UNTIL in IF
- DO...LOOP WHILE in IF (post-test)
- DO...LOOP UNTIL in IF (post-test)
- IF inside all DO variants
- Multiple DOs in same IF
- Mixed pre-test and post-test loops
- Deep nesting (DO in IF in DO)

**Key Patterns:**
```basic
' Pre-test DO WHILE
DO WHILE condition
    IF nested_condition THEN
        ' Processing
    END IF
LOOP

' Post-test DO...LOOP WHILE
DO
    IF condition THEN
        ' Processing
    END IF
LOOP WHILE condition
```

### 5. `test_nested_for_if.bas`
**Tests:** FOR NEXT loops nested with IF statements  
**Covers:**
- FOR in IF THEN/ELSE
- FOR with STEP in IF
- Negative STEP FOR in IF
- IF inside FOR
- Multiple IFs in FOR
- Multiple FORs in same IF
- Deep nesting (FOR in IF in FOR)
- EXIT FOR with IF
- Complex range expressions
- Triple nesting

**Key Patterns:**
```basic
' FOR with STEP in IF
IF condition THEN
    FOR i = 1 TO 10 STEP 2
        ' Should iterate 5 times
    NEXT i
END IF

' Negative STEP
FOR i = 10 TO 1 STEP -1
    IF i = 5 THEN
        ' Midpoint processing
    END IF
NEXT i
```

### 6. `test_nested_mixed_controls.bas`
**Tests:** Complex combinations of different control structures  
**Covers:**
- WHILE inside FOR inside IF
- FOR inside WHILE inside IF
- DO inside REPEAT inside IF
- All loop types in one IF block
- Triple nesting with mixed types
- Quadruple nesting
- Alternating IF and loops
- Mixed pre-test and post-test loops

**Key Patterns:**
```basic
' Complex mixed nesting
FOR outer = 1 TO 5
    IF outer > 2 THEN
        WHILE mid <= 3
            REPEAT
                DO WHILE inner <= 2
                    ' Quadruple nesting
                LOOP
            UNTIL done
        WEND
    END IF
NEXT outer
```

---

## Test Methodology

### What Each Test Verifies

1. **Loop Iteration Count**: Nested loops execute the correct number of times
2. **Back-Edge Creation**: CFG has proper loop back-edges
3. **Loop Header Blocks**: Each loop gets a proper loop header block
4. **Branch Handling**: IF branches properly contain nested loops
5. **Exit Conditions**: Loop exit conditions work correctly when nested
6. **Variable Updates**: Loop counters update correctly in nested context
7. **Deep Nesting**: Multiple levels of nesting work (3-4 levels deep)

### Expected Behavior

✅ **Correct:**
- Nested loops iterate fully (not just once)
- All IF branches execute when reached
- Loop counters update properly
- Exit conditions evaluate correctly
- No premature loop termination

❌ **Incorrect (CFG bug):**
- Inner loop executes only once
- Missing loop header blocks
- No back-edges from loop body to header
- Branches bypass nested loops
- Loops terminate after single iteration

---

## Running the Tests

### Run All Nested Tests

```bash
cd tests/loops
for file in test_nested_*.bas; do
    echo "Testing: $file"
    ../../qbe_basic -o /tmp/test "$file" && /tmp/test
    echo "---"
done
```

### Run Individual Test

```bash
./qbe_basic -o /tmp/test tests/loops/test_nested_while_if.bas
/tmp/test
```

### Inspect CFG Structure

Use the `-G` flag to generate CFG trace:

```bash
./qbe_basic -G tests/loops/test_nested_while_if.bas
```

Look for:
- Loop header blocks marked `[LOOP HEADER]`
- Back-edges from loop body to header
- Proper successor relationships
- No missing blocks

### Example CFG Output (Correct)

```
Block 5 (WHILE Loop Header) [LOOP HEADER]
  [10] WHILE - creates loop
  Successors: 6, 8

Block 6 (WHILE Loop Body)
  [11] PRINT
  [12] LET/ASSIGNMENT
  [13] WEND
  Successors: 5  ← Back-edge to header
```

### Example CFG Output (Bug)

```
Block 5 (IF Body)
  [10] IF - then:6 else:0
  [11] WHILE ← No loop header!
  [12] PRINT
  [13] WEND
  Successors: 7  ← No back-edge!
```

---

## Debugging Failed Tests

### Step 1: Identify the Failure

Run the test and look for:
- Incorrect iteration counts
- Missing output
- Premature termination
- Loops that execute only once

### Step 2: Inspect CFG

```bash
./qbe_basic -G tests/loops/failing_test.bas > cfg_trace.txt
```

Look for:
- Missing loop header blocks
- Missing back-edges
- Improper successor chains
- Blocks not processed

### Step 3: Check QBE IL

```bash
./qbe_basic -i -o test.qbe failing_test.bas
cat test.qbe
```

Look for:
- Missing jump instructions
- Incorrect label references
- Missing loop labels

### Step 4: Trace Execution

Add debug PRINT statements:

```basic
WHILE outer <= 3
    PRINT "DEBUG: outer="; outer  ' Add this
    IF condition THEN
        inner = 1
        WHILE inner <= 5
            PRINT "DEBUG: inner="; inner  ' Add this
            inner = inner + 1
        WEND
    END IF
    outer = outer + 1
WEND
```

---

## Common CFG Builder Issues

### Issue 1: Missing Recursive Processing

**Symptom:** Nested loops in IF statements execute only once

**Cause:** CFG builder doesn't recursively process IF statement bodies

**Fix:** Implement `processNestedStatements()` to recursively process all control structures inside IF branches

### Issue 2: Missing Loop Headers

**Symptom:** Loop body directly follows parent block without header

**Cause:** Loop header block not created for nested loops

**Fix:** Ensure `processWhileStatement()`, `processForStatement()`, etc. are called for nested loops

### Issue 3: Incorrect Back-Edges

**Symptom:** Loop doesn't iterate, falls through

**Cause:** WEND/NEXT/LOOP statement doesn't create back-edge to header

**Fix:** Ensure loop end statements properly connect to loop header block

### Issue 4: Branch Bypass

**Symptom:** IF branch seems to skip nested control structures

**Cause:** Nested statements not added to proper branch blocks

**Fix:** Ensure nested statements go into correct IF branch block, not parent block

---

## Test Results Interpretation

### All Tests Pass ✅

CFG builder correctly handles:
- All nesting combinations
- Proper loop iteration
- Correct branching
- Deep nesting (3-4 levels)

### Specific Test Fails ❌

Identify pattern:
- Does it affect all WHILE loops? → WHILE processing issue
- Only in IF THEN? → THEN branch processing issue
- Only deep nesting? → Recursion depth issue
- All loops in IF? → IF nesting issue

### Intermittent Failures ⚠️

May indicate:
- Uninitialized variables
- State carried between tests
- Order-dependent issues
- Memory corruption

---

## Test Statistics

### Coverage

- **6 test files**
- **~85 individual test cases**
- **~1,100 lines of test code**

### Nesting Depth Tested

- Level 2: All files (loop in IF)
- Level 3: Tests 5-9 (loop in IF in loop)
- Level 4: test_nested_mixed_controls.bas

### Loop Types Covered

- WHILE...WEND
- FOR...NEXT (with STEP, negative STEP)
- REPEAT...UNTIL
- DO WHILE...LOOP
- DO UNTIL...LOOP
- DO...LOOP WHILE
- DO...LOOP UNTIL

### Control Structures Covered

- IF THEN END IF
- IF THEN ELSE END IF
- Nested IF statements
- Multiple IFs in sequence
- Complex boolean conditions

---

## Adding New Tests

### When to Add Tests

1. New control structure added (SELECT CASE, TRY/CATCH, etc.)
2. CFG bug found with specific nesting pattern
3. Edge case discovered
4. Optimization changes CFG building

### Test Template

```basic
REM Test: [Description of what's being tested]
REM Purpose: [Why this test is needed]
REM Expected: [Expected behavior]
REM Covers: [Specific patterns covered]

PRINT "=== Test 1: [Test name] ==="
DIM outer%
DIM inner%

' Test code here

PRINT "Test 1 complete"
PRINT ""

' More tests...

PRINT "=== All tests passed ==="
END
```

### Naming Convention

- `test_nested_[primary]_[secondary].bas`
- Example: `test_nested_while_if.bas` - WHILE nested with IF
- Example: `test_nested_select_loops.bas` - SELECT CASE with loops

---

## Related Documentation

- `docs/session_notes/CFG_FIX_SESSION_COMPLETE.md` - Original nested WHILE/IF bug fix
- `docs/session_notes/NESTED_WHILE_IF_FIX_SUMMARY.md` - Fix implementation details
- `fsh/FasterBASICT/src/fasterbasic_cfg.{h,cpp}` - CFG builder source code
- `docs/design/ControlFlowGraph.md` - CFG design documentation

---

## Known Issues

### Fixed Issues ✅

1. **WHILE in IF executing once** - Fixed Jan 2025
2. **FOR in IF not iterating** - Fixed Jan 2025
3. **Missing loop headers** - Fixed Jan 2025

### Current Issues ⚠️

1. **SELECT CASE nesting** - Not yet tested comprehensively
2. **TRY/CATCH nesting** - Not yet tested with loops
3. **GOSUB in nested structures** - May need additional tests

### Future Testing Needs 📋

1. SELECT CASE with nested loops
2. TRY/CATCH with nested control flow
3. GOSUB/RETURN in nested structures
4. ON GOTO/GOSUB with nesting
5. EXIT WHILE/FOR/DO in deeply nested contexts
6. Five or more levels of nesting (stress test)

---

## Performance Notes

These tests focus on **correctness**, not performance:

- Tests are designed to be **obvious** when they fail
- Iteration counts are **small** (2-5 typically)
- Output is **verbose** to aid debugging
- Tests are **self-contained** (no external dependencies)

For performance testing, see:
- `tests/benchmarks/` (if it exists)
- `tests/rosetta/` (real-world algorithms)

---

## Maintenance

### Regular Checks

1. Run tests after any CFG builder changes
2. Add tests for new control structures
3. Update this README when adding new tests
4. Keep test files clean and well-commented

### Test Hygiene

- Keep tests focused (one pattern per test section)
- Use clear variable names
- Print descriptive messages
- Mark expected vs actual behavior
- Keep iteration counts small

---

**Last Updated:** February 1, 2025  
**Maintained By:** FasterBASIC Project  
**Test Suite Version:** 1.0