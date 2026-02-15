#!/bin/bash
# End-to-end test runner for the Zig FasterBASIC compiler
# Compiles each .bas test file, runs the resulting executable, and reports results.
#
# Usage:
#   bash run_e2e_tests.sh [--jit] [filter]
#
# Examples:
#   bash run_e2e_tests.sh              # Run all tests (AOT mode)
#   bash run_e2e_tests.sh --jit        # Run all tests (JIT mode)
#   bash run_e2e_tests.sh gosub        # Run tests matching "gosub" (AOT)
#   bash run_e2e_tests.sh --jit gosub  # Run tests matching "gosub" (JIT)

set -o pipefail

FBC="./zig_compiler/zig-out/bin/fbc"
TEST_DIR="tests"
TIMEOUT_SEC=5

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Parse arguments
JIT_MODE=0
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

# Counters
PASS=0
FAIL_COMPILE=0
FAIL_LINK=0
FAIL_RUN=0
FAIL_QBE=0
FAIL_IL=0
SKIP=0
TOTAL=0

# Arrays to track failures
declare -a IL_FAILURES
declare -a COMPILE_FAILURES
declare -a LINK_FAILURES
declare -a QBE_FAILURES
declare -a RUN_FAILURES
declare -a PASSES

mkdir -p "$RESULTS_DIR"

# Check that the compiler exists
if [ ! -x "$FBC" ]; then
    echo -e "${RED}Error: Compiler not found at $FBC${NC}"
    echo "Run 'cd zig_compiler && zig build' first."
    exit 1
fi

echo "=============================================="
echo " FasterBASIC Zig Compiler - ${MODE_LABEL} E2E Tests"
echo "=============================================="
echo ""
echo "Compiler: $FBC"
echo "Mode:     $MODE_LABEL"
echo "Test dir: $TEST_DIR"
echo "Filter:   ${FILTER:-<all>}"
echo ""

# Collect test files: tests/ dir, plus jit_* tests when in JIT mode
test_files=()
for bas_file in "$TEST_DIR"/*.bas "$TEST_DIR"/**/*.bas; do
    [ -f "$bas_file" ] && test_files+=("$bas_file")
done
if [ "$JIT_MODE" -eq 1 ]; then
    for bas_file in zig_compiler/tests/jit_*.bas; do
        [ -f "$bas_file" ] && test_files+=("$bas_file")
    done
fi

for bas_file in "${test_files[@]}"; do
    # Apply filter if given
    if [ -n "$FILTER" ]; then
        case "$bas_file" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
    fi

    TOTAL=$((TOTAL + 1))
    test_name=$(basename "$bas_file" .bas)
    log_file="$RESULTS_DIR/${test_name}.log"
    run_log="$RESULTS_DIR/${test_name}.run.log"

    # Clean previous outputs
    rm -f "$log_file" "$run_log"

    if [ "$JIT_MODE" -eq 1 ]; then
        # ── JIT mode: single step — fbc --jit ──
        run_output=$(timeout "$TIMEOUT_SEC" "$FBC" "$bas_file" --jit 2>"$log_file")
        run_exit=$?

        # Save output
        echo "$run_output" > "$RESULTS_DIR/${test_name}.output"

        if [ $run_exit -eq 124 ]; then
            FAIL_RUN=$((FAIL_RUN + 1))
            RUN_FAILURES+=("$test_name (timeout)")
            printf "${RED}FAIL${NC} [run   ] %-45s %s\n" "$test_name" "(timeout after ${TIMEOUT_SEC}s)"
        elif [ $run_exit -gt 128 ]; then
            sig=$((run_exit - 128))
            FAIL_RUN=$((FAIL_RUN + 1))
            RUN_FAILURES+=("$test_name (signal $sig)")
            printf "${RED}FAIL${NC} [run   ] %-45s %s\n" "$test_name" "(crashed, signal $sig)"
        elif [ $run_exit -ne 0 ]; then
            error_hint=$(grep -i "error\|Error" "$log_file" 2>/dev/null | head -1 | sed 's/^[[:space:]]*//')
            if grep -qi "Parse error\|parse errors\|Syntax error" "$log_file" 2>/dev/null; then
                FAIL_IL=$((FAIL_IL + 1))
                IL_FAILURES+=("$test_name")
                printf "${RED}FAIL${NC} [IL gen] %-45s %s\n" "$test_name" "$error_hint"
            elif grep -qi "JIT compilation failed\|QBE\|invalid.*operand" "$log_file" 2>/dev/null; then
                FAIL_QBE=$((FAIL_QBE + 1))
                QBE_FAILURES+=("$test_name")
                printf "${YELLOW}FAIL${NC} [qbe   ] %-45s %s\n" "$test_name" "$error_hint"
            elif grep -qi "JIT session.*failed\|linking error\|unresolved\|undefined" "$log_file" 2>/dev/null; then
                FAIL_LINK=$((FAIL_LINK + 1))
                LINK_FAILURES+=("$test_name")
                printf "${YELLOW}FAIL${NC} [link  ] %-45s %s\n" "$test_name" "$error_hint"
            elif grep -qi "JIT execution did not complete" "$log_file" 2>/dev/null; then
                FAIL_RUN=$((FAIL_RUN + 1))
                RUN_FAILURES+=("$test_name")
                printf "${RED}FAIL${NC} [run   ] %-45s %s\n" "$test_name" "$error_hint"
            else
                FAIL_COMPILE=$((FAIL_COMPILE + 1))
                COMPILE_FAILURES+=("$test_name")
                printf "${RED}FAIL${NC} [build ] %-45s %s\n" "$test_name" "$error_hint"
            fi
        else
            PASS=$((PASS + 1))
            PASSES+=("$test_name")
            printf "${GREEN}PASS${NC}          %-45s\n" "$test_name"
        fi
    else
        # ── AOT mode: IL gen → compile → run ──
        out_exe="/tmp/fbc_test_${test_name}"
        il_file="$RESULTS_DIR/${test_name}.qbe"

        rm -f "$out_exe" "$il_file"

        # Step 1: Try IL generation only first
        il_output=$("$FBC" "$bas_file" -i 2>"$log_file")
        il_exit=$?

        if [ $il_exit -ne 0 ]; then
            FAIL_IL=$((FAIL_IL + 1))
            IL_FAILURES+=("$test_name")
            error_hint=$(grep -i "error" "$log_file" | head -1 | sed 's/^[[:space:]]*//')
            printf "${RED}FAIL${NC} [IL gen] %-45s %s\n" "$test_name" "$error_hint"
            continue
        fi

        echo "$il_output" > "$il_file"

        # Step 2: Full compilation to executable
        compile_output=$("$FBC" "$bas_file" -o "$out_exe" 2>"$log_file")
        compile_exit=$?

        if [ $compile_exit -ne 0 ]; then
            if grep -qi "QBE compilation failed\|qbe.*error\|invalid.*operand\|invalid.*type\|undefined.*instruction" "$log_file" 2>/dev/null; then
                FAIL_QBE=$((FAIL_QBE + 1))
                QBE_FAILURES+=("$test_name")
                error_hint=$(grep -i "error" "$log_file" | head -1 | sed 's/^[[:space:]]*//')
                printf "${YELLOW}FAIL${NC} [qbe   ] %-45s %s\n" "$test_name" "$error_hint"
            elif grep -qi "linking failed\|undefined.*symbol\|unresolved\|ld:" "$log_file" 2>/dev/null; then
                FAIL_LINK=$((FAIL_LINK + 1))
                LINK_FAILURES+=("$test_name")
                error_hint=$(grep -i "error\|undefined\|unresolved\|ld:" "$log_file" | head -1 | sed 's/^[[:space:]]*//')
                printf "${YELLOW}FAIL${NC} [link  ] %-45s %s\n" "$test_name" "$error_hint"
            else
                FAIL_COMPILE=$((FAIL_COMPILE + 1))
                COMPILE_FAILURES+=("$test_name")
                error_hint=$(grep -i "error" "$log_file" | head -1 | sed 's/^[[:space:]]*//')
                printf "${RED}FAIL${NC} [build ] %-45s %s\n" "$test_name" "$error_hint"
            fi
            continue
        fi

        # Step 3: Run the executable
        if [ ! -x "$out_exe" ]; then
            FAIL_LINK=$((FAIL_LINK + 1))
            LINK_FAILURES+=("$test_name")
            printf "${YELLOW}FAIL${NC} [link  ] %-45s %s\n" "$test_name" "(executable not created)"
            continue
        fi

        run_output=$(timeout "$TIMEOUT_SEC" "$out_exe" 2>"$run_log")
        run_exit=$?

        if [ $run_exit -eq 124 ]; then
            FAIL_RUN=$((FAIL_RUN + 1))
            RUN_FAILURES+=("$test_name (timeout)")
            printf "${RED}FAIL${NC} [run   ] %-45s %s\n" "$test_name" "(timeout after ${TIMEOUT_SEC}s)"
        elif [ $run_exit -gt 128 ]; then
            sig=$((run_exit - 128))
            FAIL_RUN=$((FAIL_RUN + 1))
            RUN_FAILURES+=("$test_name (signal $sig)")
            printf "${RED}FAIL${NC} [run   ] %-45s %s\n" "$test_name" "(crashed, signal $sig)"
        else
            PASS=$((PASS + 1))
            PASSES+=("$test_name")
            if [ $run_exit -ne 0 ]; then
                printf "${GREEN}PASS${NC}          %-45s %s\n" "$test_name" "(exit=$run_exit)"
            else
                printf "${GREEN}PASS${NC}          %-45s\n" "$test_name"
            fi
        fi

        echo "$run_output" > "$RESULTS_DIR/${test_name}.output"
        rm -f "$out_exe"
    fi
done

echo ""
echo "=============================================="
echo " Summary ($MODE_LABEL mode)"
echo "=============================================="
echo ""
printf "  Total:          %d\n" "$TOTAL"
printf "  ${GREEN}Passed:${NC}         %d\n" "$PASS"
printf "  ${RED}IL gen fail:${NC}    %d\n" "$FAIL_IL"
printf "  ${RED}Build fail:${NC}     %d\n" "$FAIL_COMPILE"
printf "  ${YELLOW}QBE fail:${NC}       %d\n" "$FAIL_QBE"
printf "  ${YELLOW}Link fail:${NC}      %d\n" "$FAIL_LINK"
printf "  ${RED}Run fail:${NC}       %d\n" "$FAIL_RUN"
echo ""

if [ ${#IL_FAILURES[@]} -gt 0 ]; then
    echo -e "${RED}IL generation failures:${NC}"
    for f in "${IL_FAILURES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

if [ ${#COMPILE_FAILURES[@]} -gt 0 ]; then
    echo -e "${RED}Build failures:${NC}"
    for f in "${COMPILE_FAILURES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

if [ ${#QBE_FAILURES[@]} -gt 0 ]; then
    echo -e "${YELLOW}QBE failures:${NC}"
    for f in "${QBE_FAILURES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

if [ ${#LINK_FAILURES[@]} -gt 0 ]; then
    echo -e "${YELLOW}Link failures:${NC}"
    for f in "${LINK_FAILURES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

if [ ${#RUN_FAILURES[@]} -gt 0 ]; then
    echo -e "${RED}Run failures:${NC}"
    for f in "${RUN_FAILURES[@]}"; do
        echo "  - $f"
    done
    echo ""
fi

# Calculate pass rate
if [ "$TOTAL" -gt 0 ]; then
    PASS_RATE=$((PASS * 100 / TOTAL))
    echo "Pass rate: ${PASS}/${TOTAL} (${PASS_RATE}%)"
else
    echo "No tests found."
fi

echo ""
echo "Detailed logs saved to: $RESULTS_DIR/"
echo ""

# Exit with failure if any tests failed
if [ "$PASS" -eq "$TOTAL" ]; then
    exit 0
else
    exit 1
fi
