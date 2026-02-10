#!/bin/bash

# Configuration
COMPILER="./zig_compiler/zig-out/bin/fbc"
RUNTIME_DIR="./zig_compiler/runtime"
TEST_DIR="tests/stress"
TEMP_DIR="test_output"
SHOW_MEMORY=0

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --show-memory)
            SHOW_MEMORY=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--show-memory]"
            exit 1
            ;;
    esac
done

# Check requirements
if [ ! -f "$COMPILER" ]; then
    echo -e "${RED}Error: Compiler not found at $COMPILER${NC}"
    echo "Please build it first: cd zig_compiler && zig build"
    exit 1
fi

if [ ! -d "$TEST_DIR" ]; then
    echo -e "${RED}Error: Test directory $TEST_DIR not found${NC}"
    exit 1
fi

mkdir -p "$TEMP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FasterBASIC Stress Tests (Zig Compiler)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Compiler: $COMPILER"
echo "Runtime:  $RUNTIME_DIR"
if [ $SHOW_MEMORY -eq 1 ]; then
    echo "Memory stats: enabled"
fi
echo ""

# Helper for timing
get_time() {
    perl -MTime::HiRes=time -e 'printf "%.4f", time'
}

for test_file in "$TEST_DIR"/*.bas; do
    if [ ! -f "$test_file" ]; then continue; fi

    test_name=$(basename "$test_file" .bas)
    output_bin="$TEMP_DIR/${test_name}"

    printf "Test: %-35s " "${test_name}"

    # Compile
    if ! "$COMPILER" "$test_file" --runtime-dir "$RUNTIME_DIR" -o "$output_bin" > "$TEMP_DIR/${test_name}_compile.log" 2>&1; then
        echo -e "${RED}COMPILE FAIL${NC}"
        # cat "$TEMP_DIR/${test_name}_compile.log" # Uncomment to debug
        continue
    fi

    # Run with timing
    start_time=$(get_time)

    if [ $SHOW_MEMORY -eq 1 ]; then
        BASIC_MEMORY_STATS=1 "$output_bin" > "$TEMP_DIR/${test_name}.out" 2>&1
    else
        "$output_bin" > "$TEMP_DIR/${test_name}.out" 2>&1
    fi
    ret_code=$?

    end_time=$(get_time)
    duration=$(perl -e "printf \"%.3f\", $end_time - $start_time")

    # Analyze result
    if [ $ret_code -ne 0 ]; then
        echo -e "${RED}CRASH${NC} (${duration}s)"
        echo "  Exit code: $ret_code"
    elif grep -qi "^ERROR:" "$TEMP_DIR/${test_name}.out"; then
        echo -e "${RED}FAIL${NC}  (${duration}s)"
        grep -i "^ERROR:" "$TEMP_DIR/${test_name}.out" | head -n 1 | sed 's/^/  /'
    else
        echo -e "${GREEN}PASS${NC}  (${duration}s)"
    fi
done

echo ""
echo "Done."
