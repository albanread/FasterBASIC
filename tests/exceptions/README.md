# Exception Handling Tests

This directory contains comprehensive tests for the FasterBASIC TRY/CATCH/FINALLY/THROW exception handling system.

## Overview

The exception handling system implements structured exception handling in BASIC using:
- **TRY** blocks to guard code that may throw exceptions
- **CATCH** clauses to handle specific error codes or all errors (catch-all)
- **FINALLY** blocks for cleanup code that always executes
- **THROW** statements to raise exceptions with numeric error codes
- **ERR()** and **ERL()** intrinsic functions to query exception details

## Test Files

### test_try_catch_basic.bas
Tests fundamental TRY/CATCH behavior:
- Normal execution without exceptions
- THROW and CATCH with specific error codes
- Multiple CATCH blocks for different error codes
- ERR() intrinsic function returning the error code

**Expected Output:** All tests pass, demonstrating that:
- Normal code paths work when no exception is thrown
- THROW transfers control to the matching CATCH block
- ERR() returns the correct error code inside CATCH

### test_catch_all.bas
Tests CATCH-all behavior (CATCH without specifying an error code):
- CATCH-all catches any error code
- Specific CATCH clauses take precedence over CATCH-all
- CATCH-all as fallback for unmatched error codes

**Expected Output:** All tests pass, showing that:
- CATCH without an error code matches any thrown error
- Specific CATCH blocks are checked before CATCH-all
- ERR() works correctly in CATCH-all blocks

### test_finally.bas
Tests FINALLY block execution:
- FINALLY executes on normal exit from TRY
- FINALLY executes when an exception is caught
- FINALLY without CATCH (cleanup-only TRY blocks)
- Multiple operations in FINALLY blocks

**Expected Output:** All tests pass, demonstrating that:
- FINALLY always executes regardless of exception path
- FINALLY can access variables modified in TRY and CATCH
- FINALLY is suitable for resource cleanup patterns

**Note:** Some tests may show ERROR messages in output - this is intentional to validate that FINALLY runs even when errors occur.

### test_nested_try.bas
Tests nested TRY/CATCH/FINALLY blocks:
- Inner TRY catches exceptions without affecting outer TRY
- Exceptions propagate from inner to outer when not caught
- CATCH-all at multiple nesting levels
- Three-level nesting
- Nested FINALLY blocks execute in correct order

**Expected Output:** All tests pass, showing that:
- Each nesting level maintains its own exception context
- Exceptions bubble up until caught
- FINALLY blocks at each level execute properly

**Note:** Tests may show ERROR messages when validating that outer handlers should not execute - this is expected behavior.

### test_err_erl.bas
Tests ERR() and ERL() intrinsic functions:
- ERR() returns the thrown error code
- ERR() works with different error codes
- ERR() in CATCH-all blocks
- ERR() used in expressions and conditionals
- ERL() returns the line number where the error occurred
- Both functions work together
- ERR() in nested TRY/CATCH
- ERR() called multiple times maintains consistency

**Expected Output:** All tests pass, demonstrating that:
- ERR() correctly returns the error code in CATCH blocks
- ERR() can be used in expressions and comparisons
- ERL() returns meaningful line number information
- Both functions maintain state throughout the CATCH block

### test_comprehensive.bas
Realistic scenarios combining multiple exception features:
- Division by zero checking with cleanup
- Resource acquisition/release patterns
- Multiple operations with selective error handling
- Error propagation through call chains (simulated)
- State machine with error recovery and retry logic
- Complex FINALLY cleanup with multiple resources
- Error code dispatch table pattern

**Expected Output:** All tests pass, demonstrating real-world usage patterns including:
- Proper resource management (acquire/release)
- Transaction rollback patterns
- HTTP-style error code handling (404, 500, etc.)
- Retry logic with state machines

**Note:** Test output includes ERROR messages for validation - these are expected and part of the test design.

### test_throw_no_handler.bas
**⚠️ This test is NOT included in the main test suite!**

Tests THROW without a TRY handler (error termination):
- Program should terminate with a runtime error
- This validates that unhandled exceptions properly terminate execution

**To run manually:**
```bash
./qbe_basic_integrated/qbe_basic tests/exceptions/test_throw_no_handler.bas > /tmp/test.s
gcc /tmp/test.s fsh/FasterBASICT/runtime_c/*.c -I fsh/FasterBASICT/runtime_c -lm -o /tmp/test
/tmp/test
# Expected: Program terminates with error message
```

## Implementation Notes

### Technical Details

The exception handling system is implemented using setjmp/longjmp:

1. **TRY setup**: Pushes an exception context onto a stack and calls setjmp
2. **Normal execution**: If setjmp returns 0, execute TRY block body
3. **Exception path**: If setjmp returns non-zero (from longjmp), jump to dispatch
4. **Dispatch logic**: Compares ERR() with each CATCH clause to find a match
5. **FINALLY execution**: Always executes after TRY body or CATCH, then pops context
6. **Re-throw**: If no CATCH matches, calls basic_rethrow() to propagate up

### Critical Implementation Detail

The compiler generates a **direct call to setjmp** using the jmp_buf pointer from the exception context, rather than calling through a wrapper function. This is essential because:
- setjmp must capture the stack frame of the calling function
- A wrapper would capture its own frame, causing stack corruption on longjmp
- This was discovered through debugging a hang/crash issue

### Runtime Functions

- `basic_exception_push(jmp_buf*)` - Push exception context
- `basic_exception_pop()` - Pop exception context
- `basic_throw(int code)` - Throw exception (longjmp to handler)
- `basic_err()` - Return current error code
- `basic_erl()` - Return current error line number
- `basic_rethrow()` - Propagate exception to outer handler

### QBE Code Generation

Exception handling generates several QBE IL blocks:
- **try_setup**: Push context, call setjmp, branch based on return value
- **try_body**: Normal execution path
- **dispatch**: Check error code and route to appropriate CATCH
- **catch_N**: One block per CATCH clause
- **finally**: Cleanup code (if present)
- **exit**: Common exit point, pops exception context

## Running Tests

### Run All Exception Tests
```bash
./test_basic_suite.sh
```

The test suite includes all exception tests except `test_throw_no_handler.bas`.

### Run Individual Test
```bash
# Compile and run a single test
./qbe_basic_integrated/qbe_basic tests/exceptions/test_try_catch_basic.bas > /tmp/test.s
gcc /tmp/test.s fsh/FasterBASICT/runtime_c/*.c -I fsh/FasterBASICT/runtime_c -lm -o /tmp/test
/tmp/test
```

### Inspect Generated Code
```bash
# View QBE IL
./qbe_basic_integrated/qbe_basic -i tests/exceptions/test_try_catch_basic.bas

# View assembly
./qbe_basic_integrated/qbe_basic tests/exceptions/test_try_catch_basic.bas
```

## Test Results

As of the latest test run, **all 62 tests pass** (56 original + 6 exception tests):

- ✅ test_try_catch_basic.bas - PASS
- ✅ test_catch_all.bas - PASS
- ✅ test_finally.bas - PASS
- ✅ test_nested_try.bas - PASS
- ✅ test_err_erl.bas - PASS
- ✅ test_comprehensive.bas - PASS

## Known Limitations

1. **Error codes must be positive integers** - Enforced by semantic analyzer
2. **No exception variables** - Only numeric error codes are supported (no exception objects)
3. **No automatic cleanup** - Must explicitly use FINALLY for resource management
4. **Line numbers (ERL) are approximate** - Implementation-dependent based on THROW location
5. **No stack traces** - Only the immediate error code and line number are available

## Future Enhancements

Potential improvements (not currently implemented):
- String error messages associated with codes
- Stack trace capture and reporting
- Automatic resource cleanup (RAII-style)
- Exception filtering (WHEN clauses)
- Warning on unused exception contexts (uncaught paths)

## Debugging Tips

If exception tests fail:

1. **Inspect QBE IL**: Look at the try_setup, dispatch, and catch blocks
2. **Check assembly**: Verify setjmp is called directly (not through wrapper)
3. **Add logging**: Insert PRINT statements in TRY/CATCH/FINALLY to trace execution
4. **Test incrementally**: Start with simple TRY/CATCH before testing nested blocks
5. **Verify runtime**: Ensure basic_runtime.c is compiled and linked correctly

## References

- Parser: `fsh/FasterBASICT/src/fasterbasic_parser.cpp` (TRY/CATCH/FINALLY/THROW)
- Semantic: `fsh/FasterBASICT/src/fasterbasic_semantic.cpp` (validation rules)
- CFG: `fsh/FasterBASICT/src/fasterbasic_cfg.cpp` (block structure)
- Codegen: `fsh/FasterBASICT/src/codegen/qbe_codegen_statements.cpp` (IL generation)
- Runtime: `fsh/FasterBASICT/runtime_c/basic_runtime.c` (setjmp/longjmp implementation)

---

**Last Updated:** January 2025  
**Test Suite Version:** 1.0  
**All Tests Passing:** ✅ Yes (62/62)