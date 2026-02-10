#!/bin/bash

# Configuration
COMPILER="./zig_compiler/zig-out/bin/fbc"
RUNTIME_DIR="./zig_compiler/runtime"
TEST_DIR="performance_tests"
TEMP_DIR="test_output"

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check requirements
if [ ! -f "$COMPILER" ]; then
    echo -e "${RED}Error: Compiler not found at $COMPILER${NC}"
    echo "Please build it first: cd zig_compiler && zig build"
    exit 1
fi

if [ ! -d "$TEST_DIR" ]; then
    echo -e "${RED}Error: Benchmark directory $TEST_DIR not found${NC}"
    exit 1
fi

mkdir -p "$TEMP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  FasterBASIC Performance Benchmarks"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Compiler: $COMPILER"
echo "Runtime:  $RUNTIME_DIR"
echo ""
printf "%-35s %-15s %-15s %-10s\n" "BENCHMARK" "COMPILE TIME" "RUN TIME" "STATUS"
echo "──────────────────────────────────────────────────────────────────"

# Helper for timing
get_time() {
    perl -MTime::HiRes=time -e 'printf "%.4f", time'
}

for test_file in "$TEST_DIR"/*.bas; do
    if [ ! -f "$test_file" ]; then continue; fi

    test_name=$(basename "$test_file" .bas)
    output_bin="$TEMP_DIR/${test_name}"

    printf "%-35s " "${test_name}"

    # 1. Measure Compilation Time
    comp_start=$(get_time)

    if ! "$COMPILER" "$test_file" --runtime-dir "$RUNTIME_DIR" -o "$output_bin" > "$TEMP_DIR/${test_name}_compile.log" 2>&1; then
        comp_end=$(get_time)
        comp_duration=$(perl -e "printf \"%.3fs\", $comp_end - $comp_start")

        printf "%-15s %-15s ${RED}COMPILE FAIL${NC}\n" "${comp_duration}" "-"
        # cat "$TEMP_DIR/${test_name}_compile.log" # Uncomment to debug
        continue
    fi

    comp_end=$(get_time)
    comp_duration=$(perl -e "printf \"%.3fs\", $comp_end - $comp_start")
    printf "%-15s " "${comp_duration}"

    # 2. Measure Execution Time
    run_start=$(get_time)

    "$output_bin" > "$TEMP_DIR/${test_name}.out" 2>&1
    ret_code=$?

    run_end=$(get_time)
    run_duration=$(perl -e "printf \"%.3fs\", $run_end - $run_start")

    # Analyze result
    if [ $ret_code -ne 0 ]; then
        printf "%-15s ${RED}CRASH${NC} (Exit: %d)\n" "${run_duration}" $ret_code
    else
        printf "%-15s ${GREEN}PASS${NC}\n" "${run_duration}"
    fi
done

echo ""
echo "Benchmarks completed."
