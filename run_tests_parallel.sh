#!/bin/bash
# Parallel end-to-end test runner for the Zig FasterBASIC compiler
# Uses xargs -P8 to compile/run tests across 8 CPUs
#
# Usage:
#   bash run_tests_parallel.sh [--jit] [filter]
#
# Examples:
#   bash run_tests_parallel.sh              # Run all tests (AOT mode)
#   bash run_tests_parallel.sh --jit        # Run all tests (JIT mode)
#   bash run_tests_parallel.sh gosub        # Run tests matching "gosub" (AOT)
#   bash run_tests_parallel.sh --jit gosub  # Run tests matching "gosub" (JIT)
set -o pipefail

FBC="./zig_compiler/zig-out/bin/fbc"
TIMEOUT_SEC=10
JIT_MODE=0

# Parse flags
FILTER=""
for arg in "$@"; do
    case "$arg" in
        --jit|-J)
            JIT_MODE=1
            ;;
        *)
            FILTER="$arg"
            ;;
    esac
done

if [ "$JIT_MODE" -eq 1 ]; then
    RESULTS_DIR="test_output/jit_results"
    MODE_LABEL="JIT"
else
    RESULTS_DIR="test_output/e2e_results"
    MODE_LABEL="AOT"
fi

mkdir -p "$RESULTS_DIR"

if [ ! -x "$FBC" ]; then
    echo "Error: Compiler not found at $FBC"
    echo "Run 'cd zig_compiler && zig build' first."
    exit 1
fi

# Collect all .bas test files
find tests -name '*.bas' -type f | sort > /tmp/fbc_test_list.txt

# Also include zig_compiler/tests/jit_*.bas when in JIT mode
if [ "$JIT_MODE" -eq 1 ]; then
    find zig_compiler/tests -name 'jit_*.bas' -type f | sort >> /tmp/fbc_test_list.txt
fi

if [ -n "$FILTER" ]; then
    grep "$FILTER" /tmp/fbc_test_list.txt > /tmp/fbc_test_list_filtered.txt
    mv /tmp/fbc_test_list_filtered.txt /tmp/fbc_test_list.txt
fi

TOTAL=$(wc -l < /tmp/fbc_test_list.txt | tr -d ' ')

echo "=============================================="
echo " FasterBASIC Zig Compiler - Parallel ${MODE_LABEL} Tests"
echo "=============================================="
echo ""
echo "Compiler: $FBC"
echo "Mode:     $MODE_LABEL"
echo "Workers:  8"
echo "Tests:    $TOTAL"
echo "Filter:   ${FILTER:-<all>}"
echo ""

export FBC RESULTS_DIR TIMEOUT_SEC JIT_MODE

# The worker function: compile and run a single .bas file
# Writes a one-line result to stdout: STATUS|test_name|detail
run_one_test() {
    local bas_file="$1"
    local test_name
    test_name=$(echo "$bas_file" | sed 's|^tests/||; s|^zig_compiler/tests/||; s|\.bas$||; s|/|__|g')
    local log_file="$RESULTS_DIR/${test_name}.log"

    if [ "$JIT_MODE" -eq 1 ]; then
        # ── JIT mode: single step — fbc --jit executes in-process ──
        local run_output
        run_output=$(timeout "$TIMEOUT_SEC" $FBC "$bas_file" --jit 2>"$log_file")
        local rc=$?

        # Save output
        echo "$run_output" > "$RESULTS_DIR/${test_name}.output"

        if [ $rc -eq 124 ]; then
            echo "RUN_FAIL|${test_name}|(timeout ${TIMEOUT_SEC}s)"
        elif [ $rc -gt 128 ]; then
            local sig=$((rc - 128))
            echo "RUN_FAIL|${test_name}|(signal $sig)"
        elif [ $rc -ne 0 ]; then
            # Check if it's a compile/link error vs runtime error
            local hint
            hint=$(grep -i "error\|Error" "$log_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
            if grep -qi "Parse error\|parse errors\|IL generation\|Syntax error" "$log_file" 2>/dev/null; then
                echo "IL_FAIL|${test_name}|${hint}"
            elif grep -qi "JIT compilation failed\|QBE\|invalid.*operand" "$log_file" 2>/dev/null; then
                echo "QBE_FAIL|${test_name}|${hint}"
            elif grep -qi "JIT session.*failed\|linking error\|unresolved\|undefined" "$log_file" 2>/dev/null; then
                echo "LINK_FAIL|${test_name}|${hint}"
            elif grep -qi "JIT execution did not complete" "$log_file" 2>/dev/null; then
                echo "RUN_FAIL|${test_name}|${hint}"
            else
                echo "BUILD_FAIL|${test_name}|${hint}"
            fi
        else
            echo "PASS|${test_name}|exit=$rc"
        fi
    else
        # ── AOT mode: IL gen → compile → run ──
        local out_exe="/tmp/fbc_test_$$_${test_name}"

        # Step 1: IL generation
        $FBC "$bas_file" -i >/dev/null 2>"$log_file"
        if [ $? -ne 0 ]; then
            local hint
            hint=$(grep -i "error" "$log_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
            echo "IL_FAIL|${test_name}|${hint}"
            return
        fi

        # Step 2: Full compile
        $FBC "$bas_file" -o "$out_exe" 2>"$log_file"
        if [ $? -ne 0 ]; then
            local hint
            hint=$(grep -i "error\|undefined\|ld:" "$log_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
            if grep -qi "QBE compilation failed" "$log_file" 2>/dev/null; then
                echo "QBE_FAIL|${test_name}|${hint}"
            elif grep -qi "linking failed\|undefined.*symbol\|unresolved\|ld:" "$log_file" 2>/dev/null; then
                echo "LINK_FAIL|${test_name}|${hint}"
            else
                echo "BUILD_FAIL|${test_name}|${hint}"
            fi
            rm -f "$out_exe"
            return
        fi

        # Step 3: Run
        if [ ! -x "$out_exe" ]; then
            echo "LINK_FAIL|${test_name}|(no executable)"
            return
        fi

        local run_output
        run_output=$(timeout "$TIMEOUT_SEC" "$out_exe" 2>&1)
        local rc=$?
        rm -f "$out_exe"

        # Save output
        echo "$run_output" > "$RESULTS_DIR/${test_name}.output"

        if [ $rc -eq 124 ]; then
            echo "RUN_FAIL|${test_name}|(timeout ${TIMEOUT_SEC}s)"
        elif [ $rc -gt 128 ]; then
            local sig=$((rc - 128))
            echo "RUN_FAIL|${test_name}|(signal $sig)"
        else
            echo "PASS|${test_name}|exit=$rc"
        fi
    fi
}
export -f run_one_test

# Run all tests in parallel across 8 CPUs, collect results
RESULTS_FILE="/tmp/fbc_parallel_results_$$.txt"
cat /tmp/fbc_test_list.txt | xargs -P8 -I{} bash -c 'run_one_test "$@"' _ {} > "$RESULTS_FILE"

# Parse and display results
PASS=0; FAIL_IL=0; FAIL_QBE=0; FAIL_LINK=0; FAIL_BUILD=0; FAIL_RUN=0

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

declare -a IL_FAILURES QBE_FAILURES LINK_FAILURES BUILD_FAILURES RUN_FAILURES

while IFS='|' read -r status name detail; do
    case "$status" in
        PASS)
            PASS=$((PASS + 1))
            printf "${GREEN}PASS${NC}          %-50s\n" "$name"
            ;;
        IL_FAIL)
            FAIL_IL=$((FAIL_IL + 1))
            IL_FAILURES+=("$name")
            printf "${RED}FAIL${NC} [IL gen] %-50s %s\n" "$name" "$detail"
            ;;
        QBE_FAIL)
            FAIL_QBE=$((FAIL_QBE + 1))
            QBE_FAILURES+=("$name")
            printf "${YELLOW}FAIL${NC} [qbe   ] %-50s %s\n" "$name" "$detail"
            ;;
        LINK_FAIL)
            FAIL_LINK=$((FAIL_LINK + 1))
            LINK_FAILURES+=("$name")
            printf "${YELLOW}FAIL${NC} [link  ] %-50s %s\n" "$name" "$detail"
            ;;
        BUILD_FAIL)
            FAIL_BUILD=$((FAIL_BUILD + 1))
            BUILD_FAILURES+=("$name")
            printf "${RED}FAIL${NC} [build ] %-50s %s\n" "$name" "$detail"
            ;;
        RUN_FAIL)
            FAIL_RUN=$((FAIL_RUN + 1))
            RUN_FAILURES+=("$name")
            printf "${RED}FAIL${NC} [run   ] %-50s %s\n" "$name" "$detail"
            ;;
    esac
done < <(sort "$RESULTS_FILE")

ACTUAL_TOTAL=$((PASS + FAIL_IL + FAIL_QBE + FAIL_LINK + FAIL_BUILD + FAIL_RUN))

echo ""
echo "=============================================="
echo " Summary ($MODE_LABEL mode)"
echo "=============================================="
echo ""
printf "  Total:          %d\n" "$ACTUAL_TOTAL"
printf "  ${GREEN}Passed:${NC}         %d\n" "$PASS"
printf "  ${RED}IL gen fail:${NC}    %d\n" "$FAIL_IL"
printf "  ${RED}Build fail:${NC}     %d\n" "$FAIL_BUILD"
printf "  ${YELLOW}QBE fail:${NC}       %d\n" "$FAIL_QBE"
printf "  ${YELLOW}Link fail:${NC}      %d\n" "$FAIL_LINK"
printf "  ${RED}Run fail:${NC}       %d\n" "$FAIL_RUN"
echo ""

print_failure_list() {
    local label="$1"
    shift
    local items=("$@")
    if [ ${#items[@]} -gt 0 ]; then
        echo -e "${label}"
        for f in "${items[@]}"; do
            echo "  - $f"
        done
        echo ""
    fi
}

print_failure_list "${RED}IL generation failures:${NC}" "${IL_FAILURES[@]}"
print_failure_list "${RED}Build failures:${NC}" "${BUILD_FAILURES[@]}"
print_failure_list "${YELLOW}QBE failures:${NC}" "${QBE_FAILURES[@]}"
print_failure_list "${YELLOW}Link failures:${NC}" "${LINK_FAILURES[@]}"
print_failure_list "${RED}Run failures:${NC}" "${RUN_FAILURES[@]}"

if [ "$ACTUAL_TOTAL" -gt 0 ]; then
    PASS_RATE=$((PASS * 100 / ACTUAL_TOTAL))
    echo "Pass rate: ${PASS}/${ACTUAL_TOTAL} (${PASS_RATE}%)"
else
    echo "No tests found."
fi
echo ""
echo "Detailed logs: $RESULTS_DIR/"

# Cleanup
rm -f /tmp/fbc_test_list.txt "$RESULTS_FILE"

if [ "$PASS" -eq "$ACTUAL_TOTAL" ]; then
    exit 0
else
    exit 1
fi
