#!/bin/bash
#
# verify_implementation.sh
# Verification script for exception handling and array descriptor implementation
#
# This script checks for common implementation errors:
# 1. setjmp called through wrapper (should be direct call)
# 2. Wrong ArrayDescriptor field offsets
# 3. Missing string cleanup in REDIM
# 4. Missing descriptor field restoration after erase
#

# Don't exit on error - we want to report all issues
# set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODEGEN_DIR="$SCRIPT_DIR/fsh/FasterBASICT/src/codegen"
CODEGEN_FILES=(
    "$CODEGEN_DIR/qbe_codegen_main.cpp"
    "$CODEGEN_DIR/qbe_codegen_statements.cpp"
    "$CODEGEN_DIR/qbe_codegen_expressions.cpp"
    "$CODEGEN_DIR/qbe_codegen_helpers.cpp"
    "$CODEGEN_DIR/qbe_codegen_runtime.cpp"
)

echo "=================================================="
echo "FasterBASIC Implementation Verification"
echo "=================================================="
echo ""

# Check counter
ISSUES_FOUND=0
CHECKS_PASSED=0

# Function to print check result
print_check() {
    local status=$1
    local message=$2
    if [ "$status" = "PASS" ]; then
        echo -e "${GREEN}✓${NC} $message"
        ((CHECKS_PASSED++))
    elif [ "$status" = "FAIL" ]; then
        echo -e "${RED}✗${NC} $message"
        ((ISSUES_FOUND++))
    elif [ "$status" = "WARN" ]; then
        echo -e "${YELLOW}⚠${NC} $message"
    else
        echo -e "${BLUE}ℹ${NC} $message"
    fi
}

echo "Checking codegen files in: $CODEGEN_DIR"
echo ""

# Check 1: Verify elementSize is loaded from offset 40, not 24
echo "=== Checking ArrayDescriptor Field Offsets ==="
found_40=false
found_24=false

for file in "${CODEGEN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "add.*40.*element\|elementSize.*40" "$file"; then
            found_40=true
        fi
        if grep -q "add.*24.*element" "$file" 2>/dev/null; then
            found_24=true
        fi
    fi
done

if [ "$found_40" = true ]; then
    print_check "PASS" "elementSize loaded from offset 40 (correct)"
else
    print_check "WARN" "Could not verify elementSize offset 40 - manual inspection recommended"
fi

if [ "$found_24" = true ]; then
    print_check "FAIL" "Found elementSize loaded from offset 24 (WRONG - that's lowerBound2!)"
fi

# Check 2: Verify array_descriptor_erase is called before REDIM
echo ""
echo "=== Checking String Array Cleanup ==="
found_erase=false

for file in "${CODEGEN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "array_descriptor_erase" "$file"; then
            found_erase=true
            break
        fi
    fi
done

if [ "$found_erase" = true ]; then
    print_check "PASS" "array_descriptor_erase called (correct for string cleanup)"
else
    print_check "FAIL" "array_descriptor_erase not found - strings may leak on REDIM"
fi

# Check 3: Verify dimensions field is restored after erase (offset 48)
echo ""
echo "=== Checking Descriptor Field Restoration ==="
found_dims=false

for file in "${CODEGEN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "48.*dimension\|dimension.*48" "$file"; then
            found_dims=true
            break
        fi
    fi
done

if [ "$found_dims" = true ]; then
    print_check "PASS" "dimensions field (offset 48) restoration found"
else
    print_check "WARN" "Could not verify dimensions field restoration - manual check recommended"
fi

# Check 4: Verify setjmp is called directly (not through wrapper)
echo ""
echo "=== Checking Exception Handling setjmp Call ==="
found_setjmp=false
found_wrapper=false

for file in "${CODEGEN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "call.*setjmp" "$file"; then
            found_setjmp=true
        fi
        if grep -q "basic_exception_setup_wrapper" "$file"; then
            found_wrapper=true
        fi
    fi
done

if [ "$found_setjmp" = true ]; then
    print_check "PASS" "Direct setjmp call found in codegen"

    if [ "$found_wrapper" = true ]; then
        print_check "FAIL" "Found call to basic_exception_setup_wrapper - should call setjmp directly!"
    fi
else
    print_check "WARN" "Could not verify setjmp call - manual inspection recommended"
fi

# Check 5: Verify ERR and ERL return type classification
echo ""
echo "=== Checking ERR/ERL Builtin Return Types ==="
found_err_erl=false

for file in "${CODEGEN_FILES[@]}"; do
    if [ -f "$file" ]; then
        if grep -q "ERR.*w\|ERL.*w\|\"w\".*ERR\|\"w\".*ERL" "$file"; then
            found_err_erl=true
            break
        fi
    fi
done

if [ "$found_err_erl" = true ]; then
    print_check "PASS" "ERR/ERL classified as returning 'w' type (32-bit int)"
else
    print_check "WARN" "Could not verify ERR/ERL return type - should return 'w' not 'l'"
fi

# Check 6: Verify test files exist
echo ""
echo "=== Checking Test Coverage ==="
EXCEPTION_TESTS=(
    "tests/exceptions/test_try_catch_basic.bas"
    "tests/exceptions/test_catch_all.bas"
    "tests/exceptions/test_finally.bas"
    "tests/exceptions/test_err_erl.bas"
)

ARRAY_TESTS=(
    "tests/arrays/test_erase.bas"
    "tests/arrays/test_redim.bas"
    "tests/arrays/test_redim_preserve.bas"
)

for test in "${EXCEPTION_TESTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$test" ]; then
        print_check "PASS" "Exception test exists: $(basename $test)"
    else
        print_check "FAIL" "Missing exception test: $test"
    fi
done

for test in "${ARRAY_TESTS[@]}"; do
    if [ -f "$SCRIPT_DIR/$test" ]; then
        print_check "PASS" "Array test exists: $(basename $test)"
    else
        print_check "FAIL" "Missing array test: $test"
    fi
done

# Check 7: Verify runtime files in test harness
echo ""
echo "=== Checking Test Harness Runtime Files ==="
if [ -f "$SCRIPT_DIR/test_basic_suite.sh" ]; then
    if grep -q "array_descriptor_runtime.c" "$SCRIPT_DIR/test_basic_suite.sh"; then
        print_check "PASS" "array_descriptor_runtime.c linked in test harness"
    else
        print_check "FAIL" "array_descriptor_runtime.c missing from test harness"
    fi

    if grep -q "string_pool.c" "$SCRIPT_DIR/test_basic_suite.sh"; then
        print_check "PASS" "string_pool.c linked in test harness"
    else
        print_check "FAIL" "string_pool.c missing from test harness"
    fi
else
    print_check "WARN" "test_basic_suite.sh not found"
fi

# Check 8: Verify documentation exists
echo ""
echo "=== Checking Documentation ==="
if [ -f "$SCRIPT_DIR/docs/CRITICAL_IMPLEMENTATION_NOTES.md" ]; then
    print_check "PASS" "Critical implementation notes documented"
else
    print_check "FAIL" "Missing CRITICAL_IMPLEMENTATION_NOTES.md"
fi

# Check 9: Verify CI integration
echo ""
echo "=== Checking CI Integration ==="
if [ -f "$SCRIPT_DIR/.github/workflows/build.yml" ]; then
    if grep -q "test_basic_suite.sh" "$SCRIPT_DIR/.github/workflows/build.yml"; then
        print_check "PASS" "Test suite integrated in CI"
    else
        print_check "WARN" "Test suite may not run in CI"
    fi
else
    print_check "WARN" "CI workflow file not found"
fi

# Summary
echo ""
echo "=================================================="
echo "Verification Summary"
echo "=================================================="
echo -e "Checks passed: ${GREEN}$CHECKS_PASSED${NC}"
echo -e "Issues found:  ${RED}$ISSUES_FOUND${NC}"
echo ""

if [ $ISSUES_FOUND -eq 0 ]; then
    echo -e "${GREEN}✓ All critical checks passed!${NC}"
    echo ""
    echo "Recommended next steps:"
    echo "  1. Run full test suite: ./test_basic_suite.sh"
    echo "  2. Test on multiple platforms if available"
    echo "  3. Review docs/CRITICAL_IMPLEMENTATION_NOTES.md"
    exit 0
else
    echo -e "${RED}✗ Issues found - review implementation${NC}"
    echo ""
    echo "Fix steps:"
    echo "  1. Review docs/CRITICAL_IMPLEMENTATION_NOTES.md"
    echo "  2. Check ArrayDescriptor field offsets (offset 40 for elementSize)"
    echo "  3. Ensure setjmp called directly, not through wrapper"
    echo "  4. Verify array_descriptor_erase called before REDIM"
    echo "  5. Restore descriptor fields after erase (dimensions = 1)"
    exit 1
fi
