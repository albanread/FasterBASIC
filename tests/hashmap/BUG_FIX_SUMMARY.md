# Hashmap Bug Fix Summary

## Overview

Fixed a critical bug in the FasterBASIC hashmap implementation that caused memory corruption when inserting entries with large hash values (> 2^31). The bug manifested as entries being written to wrong memory locations, causing hashmaps to become corrupted and programs to hang in infinite loops.

## Bug Description

### Symptoms
- Programs with multiple hashmaps would hang during insertion operations
- Entries inserted into one hashmap would appear in a different hashmap
- Size counters would increment but entries wouldn't appear in the correct slots
- Specific keys like "Bob" and "David" would trigger the bug consistently

### Root Cause

The `hashmap_compute_index` function in `qbe_basic_integrated/qbe_modules/hashmap.qbe` used the **signed remainder** operation (`rem`) instead of **unsigned remainder** (`urem`).

When hash values exceeded 2^31 (e.g., `0xebcba174` for "Bob", `0x8aba8bfd` for "David"), they were interpreted as negative numbers in signed arithmetic. The signed remainder operation would then produce negative indices, which wrapped around to large positive values when used as unsigned array indices.

Example:
- Hash for "Bob": `0xebcba174` (3,955,949,940 unsigned, -339,017,356 signed)
- `rem 0xebcba174, 16` = `-12` (signed) = `4294967284` (unsigned 32-bit)
- This caused "Bob" to be written to an invalid or wrong memory location

## The Fix

### File Changed
`qbe_basic_integrated/qbe_modules/hashmap.qbe`, line 26

### Change Made
```diff
-    %index =w rem %hash, %capacity
+    %index =w urem %hash, %capacity
```

### Explanation
Changed from signed remainder (`rem`) to unsigned remainder (`urem`) to ensure the modulo operation treats both operands as unsigned integers, producing correct positive indices in the range `[0, capacity-1]`.

## Verification

### Test Programs Created

1. **test_hashmap_two_maps_multiple_inserts.bas** (Regression Test)
   - Specifically tests keys with large hash values ("Bob", "David")
   - Verifies two independent hashmaps with multiple insertions each
   - Tests 8 total insertions across two maps
   - Status: ✅ PASS

2. **test_hashmap_comprehensive_verified.bas** (Comprehensive Test)
   - Tests 6 independent hashmaps simultaneously
   - 40+ key-value pairs total
   - Tests updates, special characters, and resize operations
   - Status: ✅ PASS

3. **C Debug Tools Created**
   - `hashmap_debug.c` - Full state inspection and debugging tools
   - `test_bug_hunt.c` - Step-by-step trace to identify the bug
   - `test_trace_insert.c` - Low-level QBE function tracing

### Test Results

All hashmap tests now pass:
- ✅ test_hashmap_basic.bas
- ✅ test_hashmap_multiple.bas
- ✅ test_hashmap_update.bas
- ✅ test_hashmap_with_arrays.bas
- ✅ test_hashmap_two_maps_multiple_inserts.bas (NEW)
- ✅ test_hashmap_comprehensive_verified.bas (NEW)

### Before Fix
- Programs would hang indefinitely
- Memory corruption visible in debug dumps
- Size counters mismatched actual occupied slots
- Entries appeared in wrong hashmaps

### After Fix
- No hangs or timeouts
- All insertions go to correct locations
- Size counters match actual occupied slots
- All lookups return correct values
- Multiple hashmaps work independently

## Debug Methodology

The bug was found using a systematic approach:

1. **Reproduction** - Created minimal test cases that consistently triggered the hang
2. **C Testing** - Verified the bug existed in pure C, ruling out BASIC integration issues
3. **State Inspection** - Created `hashmap_debug.c` to dump complete internal state
4. **Tracing** - Used `test_trace_insert.c` to call QBE functions directly and trace exact behavior
5. **Root Cause** - Discovered negative indices in trace output, leading to the signed remainder bug

Key insight: When trace output showed `index = 4294967284` (which is `-12` in signed 32-bit), it became clear that signed arithmetic was being used where unsigned was needed.

## Impact

This fix enables:
- ✅ Multiple independent hashmaps in the same program
- ✅ Large datasets without corruption
- ✅ Reliable hash table operations for all key types
- ✅ Production-ready BASIC hashmap support

## Files Modified

1. `qbe_basic_integrated/qbe_modules/hashmap.qbe` - Core fix (1 line changed)
2. `tests/hashmap/test_hashmap_two_maps_multiple_inserts.bas` - Regression test (NEW)
3. `tests/hashmap/test_hashmap_comprehensive_verified.bas` - Comprehensive test (NEW)
4. `tests/hashmap/README.md` - Documentation updated
5. `tests/hashmap/run_tests.sh` - Test runner script (NEW)
6. `qbe_basic_integrated/qbe_modules/hashmap_debug.c` - Debug tools (NEW)

## Lessons Learned

1. **Signed vs Unsigned Matters** - In low-level code, the distinction between signed and unsigned operations is critical, especially for hash tables and array indexing.

2. **Debug Tools Are Essential** - Creating comprehensive state inspection tools (`hashmap_debug.c`) was crucial for identifying the bug.

3. **Trace at Multiple Levels** - Testing at both BASIC and C levels helped isolate whether the bug was in the runtime or code generation.

4. **Large Values Expose Bugs** - Hash functions naturally produce values across the full 32-bit range, which exposed the signed arithmetic bug that wouldn't appear with small test values.

## Date
February 5, 2025

## Contributors
Bug identified, debugged, and fixed with comprehensive testing and documentation.