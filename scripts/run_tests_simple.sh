#!/bin/bash
#
# Simple test runner for FasterBASIC
# Compiles and runs tests, checking for ERROR messages in output
#

# Don't exit on error - we want to run all tests
# set -e

COMPILER="./qbe_basic_integrated/fbc_qbe"
RUNTIME_DIR="./qbe_basic_integrated/runtime"
TEST_DIR="./tests"
TEMP_DIR="./test_output"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Create temp directory
mkdir -p "$TEMP_DIR"

# Statistics
TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0
TIMEOUT_TESTS=0

# Arrays to store results
declare -a FAILED_TEST_NAMES
declare -a TIMEOUT_TEST_NAMES

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FasterBASIC Test Runner"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Function to run a single test
run_test() {
    local test_file="$1"
    local test_name=$(basename "$test_file" .bas)

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    echo -n "Testing: ${test_name} ... "

    # Compile (fbc_qbe does compilation and linking)
    if ! $COMPILER "$test_file" -o "$TEMP_DIR/${test_name}" >"$TEMP_DIR/${test_name}_compile.out" 2>&1; then
        echo -e "${RED}COMPILE FAIL${NC}"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TEST_NAMES+=("$test_name (compile error)")
        return 1
    fi

    # Run with timeout
    if ! timeout 5s "$TEMP_DIR/${test_name}" > "$TEMP_DIR/${test_name}.out" 2>&1; then
        if [ $? -eq 124 ]; then
            echo -e "${YELLOW}TIMEOUT${NC}"
            TIMEOUT_TESTS=$((TIMEOUT_TESTS + 1))
            TIMEOUT_TEST_NAMES+=("$test_name")
            return 1
        else
            echo -e "${RED}CRASH${NC}"
            FAILED_TESTS=$((FAILED_TESTS + 1))
            FAILED_TEST_NAMES+=("$test_name (crash)")
            return 1
        fi
    fi

    # Check output for ERROR
    if grep -qi "^ERROR:" "$TEMP_DIR/${test_name}.out"; then
        echo -e "${RED}FAIL${NC} (found ERROR in output)"
        FAILED_TESTS=$((FAILED_TESTS + 1))
        FAILED_TEST_NAMES+=("$test_name")
        # Show first ERROR line
        echo "    $(grep -i "^ERROR:" "$TEMP_DIR/${test_name}.out" | head -1)"
        return 1
    fi

    # Success
    echo -e "${GREEN}PASS${NC}"
    PASSED_TESTS=$((PASSED_TESTS + 1))
    return 0
}

# Find and run all tests
echo "Searching for tests..."
echo ""

# Test categories
categories=(
    "tests/arithmetic"
    "tests/array_expr"
    "tests/arrays"
    "tests/comparisons"
    "tests/conditionals"
    "tests/data"
    "tests/exceptions"
    "tests/functions"
    "tests/hashmap"
    "tests/io"
    "tests/loops"
    "tests/neon"
    "tests/qbe_madd"
    "tests/rosetta"
    "tests/strings"
    "tests/types"
)

for category in "${categories[@]}"; do
    if [ -d "$category" ]; then
        echo -e "${BLUE}═══ $(basename $category | tr '[:lower:]' '[:upper:]') TESTS ═══${NC}"
        for test_file in "$category"/*.bas; do
            if [ -f "$test_file" ]; then
                run_test "$test_file"
            fi
        done
        echo ""
    fi
done

# Also check for tests in root tests directory
if [ -d "$TEST_DIR" ]; then
    for test_file in "$TEST_DIR"/*.bas; do
        if [ -f "$test_file" ]; then
            run_test "$test_file"
        fi
    done
fi

# Print summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  TEST SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Total Tests:   $TOTAL_TESTS"
echo -e "Passed:        ${GREEN}${PASSED_TESTS}${NC}"
echo -e "Failed:        ${RED}${FAILED_TESTS}${NC}"
echo -e "Timeout:       ${YELLOW}${TIMEOUT_TESTS}${NC}"
echo ""

# Show failed tests
if [ ${#FAILED_TEST_NAMES[@]} -gt 0 ]; then
    echo -e "${RED}Failed Tests:${NC}"
    for test_name in "${FAILED_TEST_NAMES[@]}"; do
        echo "  ✗ $test_name"
    done
    echo ""
fi

# Show timeout tests
if [ ${#TIMEOUT_TEST_NAMES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Timeout Tests:${NC}"
    for test_name in "${TIMEOUT_TEST_NAMES[@]}"; do
        echo "  ⏱ $test_name"
    done
    echo ""
fi

# Final result
if [ $FAILED_TESTS -eq 0 ] && [ $TIMEOUT_TESTS -eq 0 ]; then
    echo -e "${GREEN}✓ ALL TESTS PASSED!${NC}"
    exit 0
else
    echo -e "${RED}✗ SOME TESTS FAILED${NC}"
    exit 1
fi
