#!/bin/bash
# run_tests.sh
# Test runner for FasterBASIC hashmap tests

set -e

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Find the compiler - we need to run from qbe_modules directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILE_DIR="$SCRIPT_DIR/../../qbe_basic_integrated/qbe_modules"
COMPILER="../fbc_qbe"

if [ ! -d "$COMPILE_DIR" ]; then
    echo -e "${RED}Error: Compile directory not found at $COMPILE_DIR${NC}"
    exit 1
fi

# List of working tests
WORKING_TESTS=(
    "test_hashmap_basic.bas"
    "test_hashmap_multiple.bas"
    "test_hashmap_update.bas"
    "test_hashmap_with_arrays.bas"
    "test_hashmap_two_maps_multiple_inserts.bas"
    "test_hashmap_comprehensive_verified.bas"
    "test_contacts_list_arrays.bas"
)

# Counters
PASSED=0
FAILED=0
TOTAL=0

echo "=========================================="
echo "FasterBASIC Hashmap Test Suite"
echo "=========================================="
echo ""

# Change to compile directory
cd "$COMPILE_DIR"

# Run each test
for test in "${WORKING_TESTS[@]}"; do
    TEST_PATH="$SCRIPT_DIR/$test"

    if [ ! -f "$TEST_PATH" ]; then
        echo -e "${YELLOW}SKIP: $test (file not found)${NC}"
        continue
    fi

    TOTAL=$((TOTAL + 1))
    echo -n "Running $test ... "

    # Compile the test
    TEST_NAME=$(basename "$test" .bas)
    if ! $COMPILER "$TEST_PATH" -o "$TEST_NAME" > /tmp/compile_$$.log 2>&1; then
        echo -e "${RED}COMPILE FAILED${NC}"
        cat /tmp/compile_$$.log
        FAILED=$((FAILED + 1))
        rm -f /tmp/compile_$$.log
        continue
    fi

    # Run the test with timeout
    if timeout 10s ./"$TEST_NAME" > /tmp/run_$$.log 2>&1; then
        # Check if output contains PASS or ERROR
        if grep -q "PASS" /tmp/run_$$.log && ! grep -q "ERROR" /tmp/run_$$.log; then
            echo -e "${GREEN}PASS${NC}"
            PASSED=$((PASSED + 1))
        else
            echo -e "${RED}FAIL${NC}"
            echo "Output:"
            cat /tmp/run_$$.log
            FAILED=$((FAILED + 1))
        fi
    else
        EXIT_CODE=$?
        if [ $EXIT_CODE -eq 124 ]; then
            echo -e "${RED}TIMEOUT${NC}"
        else
            echo -e "${RED}CRASH (exit code $EXIT_CODE)${NC}"
        fi
        echo "Output (if any):"
        cat /tmp/run_$$.log 2>/dev/null || true
        FAILED=$((FAILED + 1))
    fi

    # Cleanup
    rm -f "$TEST_NAME" /tmp/compile_$$.log /tmp/run_$$.log
done

echo ""
echo "=========================================="
echo "Test Results"
echo "=========================================="
echo "Total:  $TOTAL"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}✗ Some tests failed${NC}"
    exit 1
fi
