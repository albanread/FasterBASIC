# Nested Control Flow Tests - Quick Start Guide

**Created:** February 1, 2025  
**Purpose:** Quick reference for running and understanding nested control flow tests

---

## TL;DR - Run All Tests Now

```bash
./scripts/test_nested_control_flow.sh
```

Expected output: All 6 tests pass ✓

---

## What Are These Tests?

These tests verify that the CFG (Control Flow Graph) builder correctly handles **nested control flow structures** like:

- WHILE loops inside IF statements
- FOR loops inside IF statements
- IF statements inside WHILE loops
- REPEAT, DO LOOP with IF nesting
- Deep nesting (3-4 levels)
- Mixed control structures

### Why Do We Need These?

The CFG builder has been fragile with nested control flows. Previous bugs:
- ❌ WHILE inside IF executed only once (FIXED Jan 2025)
- ❌ FOR inside IF didn't iterate properly (FIXED Jan 2025)
- ⚠️ Need to verify REPEAT, DO, and mixed nesting work correctly

---

## Test Files

| File | What It Tests | # Tests |
|------|---------------|---------|
| `test_nested_while_if.bas` | WHILE with IF | 6 |
| `test_nested_if_while.bas` | IF with WHILE | 6 |
| `test_nested_for_if.bas` | FOR with IF | 15 |
| `test_nested_repeat_if.bas` | REPEAT with IF | 8 |
| `test_nested_do_if.bas` | DO LOOP with IF | 12 |
| `test_nested_mixed_controls.bas` | Mixed nesting | 15 |

**Total:** 6 files, 85+ test cases, ~1,100 lines of code

---

## Running Tests

### Run All Tests (Recommended)

```bash
./scripts/test_nested_control_flow.sh
```

Output shows:
- ✓ PASS (green) - Test succeeded
- ✗ FAIL (red) - Test failed
- ⚠ WARNING (yellow) - No clear pass/fail marker

### Run Single Test

```bash
./qbe_basic -o /tmp/test tests/loops/test_nested_while_if.bas
/tmp/test
```

Look for "All ... tests passed" at the end.

### Inspect CFG Structure

```bash
./qbe_basic -G tests/loops/test_nested_while_if.bas
```

Look for:
- `[LOOP HEADER]` blocks
- Back-edges (loop body → header)
- Proper successor chains

---

## What "Correct" Looks Like

### Correct CFG (Loop in IF)

```
Block 5 (WHILE Loop Header) [LOOP HEADER]
  [9] WHILE - creates loop
  Successors: 6, 8

Block 6 (WHILE Loop Body)
  [10] PRINT
  [11] LET/ASSIGNMENT
  [12] WEND
  Successors: 5  ← Back-edge!
```

✅ Separate header block  
✅ Back-edge to header  
✅ Nested loop iterates fully

### Incorrect CFG (Bug)

```
Block 4 (IF Body)
  [8] IF - then:5 else:0
  [9] WHILE  ← No header!
  [10] PRINT
  [11] WEND
  Successors: 7  ← No back-edge!
```

❌ No header block  
❌ No back-edge  
❌ Loop executes only once

---

## Quick Debugging

### Test Fails - What To Do?

1. **Check output:** What's missing? Wrong iteration count?

2. **Inspect CFG:**
   ```bash
   ./qbe_basic -G failing_test.bas > cfg.txt
   ```

3. **Look for:**
   - Missing `[LOOP HEADER]` blocks
   - Missing back-edges (Successors should include header)
   - Blocks not connected properly

4. **Check QBE IL:**
   ```bash
   ./qbe_basic -i -o test.qbe failing_test.bas
   ```
   Look for missing jumps or labels

5. **Add debug output:**
   ```basic
   WHILE outer <= 3
       PRINT "DEBUG: outer="; outer  ' Add this
       ' ... rest of code ...
   WEND
   ```

---

## Common Patterns

### Pattern 1: Loop in IF

```basic
IF condition THEN
    FOR i = 1 TO 5
        PRINT i  ' Should print 1,2,3,4,5
    NEXT i
END IF
```

**Expected:** Loop runs 5 times  
**Bug symptom:** Loop runs 1 time or not at all

### Pattern 2: IF in Loop

```basic
FOR i = 1 TO 5
    IF i MOD 2 = 0 THEN
        PRINT "Even: "; i
    END IF
NEXT i
```

**Expected:** IF evaluated 5 times, prints 3 times  
**Bug symptom:** IF never evaluates or evaluates wrong

### Pattern 3: Deep Nesting

```basic
FOR outer = 1 TO 2
    IF outer = 1 THEN
        FOR mid = 1 TO 2
            WHILE inner <= 3
                PRINT inner
                inner = inner + 1
            WEND
        NEXT mid
    END IF
NEXT outer
```

**Expected:** WHILE runs 3 times for each mid iteration  
**Bug symptom:** WHILE doesn't run or runs once

---

## Test Results Interpretation

### All Pass ✅
```
Total Tests:  6
Passed:       6
Failed:       0
```
CFG builder is working correctly!

### Some Fail ❌
```
Total Tests:  6
Passed:       4
Failed:       2
```

**Next steps:**
1. Identify which tests failed
2. Look for patterns (all REPEAT? all deep nesting?)
3. Inspect CFG traces (auto-generated in `/tmp/`)
4. Check `docs/session_notes/CFG_FIX_SESSION_COMPLETE.md` for similar issues

---

## Expected Output Examples

### test_nested_while_if.bas

```
=== Test 1: WHILE in IF THEN ===
  Inner loop: 1
  Inner loop: 2
  Inner loop: 3
  Inner loop: 4
  Inner loop completed
Outer: 1
Outer: 2
Outer: 3
Test 1 complete

...

=== All nested WHILE-IF tests passed ===
```

### test_nested_for_if.bas

```
=== Test 1: FOR in IF THEN ===
  Inner: 1
  Inner: 2
  Inner: 3
  Inner: 4
  Inner loop ran 4 times
Outer: 1
Outer: 2
Outer: 3
Test 1 complete

...

=== All nested FOR-IF tests passed ===
```

---

## When To Run These Tests

✅ **Always:** After CFG builder changes  
✅ **Often:** After parser/semantic changes  
✅ **Sometimes:** After optimization changes  
✅ **Before:** Merging CFG-related PRs  
✅ **After:** Fixing any control flow bugs

---

## File Locations

```
tests/loops/
├── test_nested_while_if.bas       ← WHILE + IF tests
├── test_nested_if_while.bas       ← IF + WHILE tests
├── test_nested_for_if.bas         ← FOR + IF tests
├── test_nested_repeat_if.bas      ← REPEAT + IF tests
├── test_nested_do_if.bas          ← DO LOOP + IF tests
├── test_nested_mixed_controls.bas ← Mixed tests
├── README_NESTED_TESTS.md         ← Full documentation
└── NESTED_TESTS_QUICKSTART.md     ← This file

scripts/
└── test_nested_control_flow.sh    ← Test runner

docs/session_notes/
├── CFG_FIX_SESSION_COMPLETE.md    ← Original bug fix
└── NESTED_CONTROL_FLOW_TEST_SUITE.md ← Test suite summary
```

---

## Key Terminology

**CFG:** Control Flow Graph - internal representation of program flow  
**Loop Header:** Entry block for a loop with condition check  
**Back-edge:** Jump from loop end back to loop header  
**Successor:** Block that executes after current block  
**Nesting:** Control structures inside other control structures

---

## Getting Help

1. **Full documentation:** `tests/loops/README_NESTED_TESTS.md`
2. **Test suite summary:** `docs/session_notes/NESTED_CONTROL_FLOW_TEST_SUITE.md`
3. **Original bug fix:** `docs/session_notes/CFG_FIX_SESSION_COMPLETE.md`
4. **CFG design:** `docs/design/ControlFlowGraph.md`

---

## Quick Commands Reference

```bash
# Run all nested tests
./scripts/test_nested_control_flow.sh

# Run one test
./qbe_basic -o /tmp/test tests/loops/test_nested_while_if.bas && /tmp/test

# Show CFG structure
./qbe_basic -G tests/loops/test_nested_while_if.bas

# Generate QBE IL
./qbe_basic -i -o test.qbe tests/loops/test_nested_while_if.bas

# Generate assembly
./qbe_basic -c -o test.s tests/loops/test_nested_while_if.bas
```

---

**Happy Testing!** 🧪

If all tests pass, your CFG builder is handling nested control flow correctly. If any fail, you've found a bug - check the CFG traces and fix the issue before it reaches production.