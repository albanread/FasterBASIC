#!/bin/bash
# ============================================================
# NEON SIMD Test Runner for FasterBASIC
# ============================================================
# Compiles and runs all NEON test files, collects results,
# performs assembly verification, and prints a summary.
#
# Usage:
#   ./scripts/run_neon_tests.sh              # Run all tests
#   ./scripts/run_neon_tests.sh --asm        # Also verify assembly output
#   ./scripts/run_neon_tests.sh --killswitch # Also test NEON kill-switch
#   ./scripts/run_neon_tests.sh --all        # Run everything
# ============================================================

set -euo pipefail

cd "$(dirname "$0")/.."
PROJECT_ROOT="$(pwd)"
COMPILER="$PROJECT_ROOT/qbe_basic_integrated/fbc_qbe"
TEST_DIR="$PROJECT_ROOT/tests/neon"
OUTPUT_DIR="$PROJECT_ROOT/test_output"

# Colors (if terminal supports them)
if [ -t 1 ]; then
    GREEN='\033[0;32m'
    RED='\033[0;31m'
    YELLOW='\033[0;33m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    RESET='\033[0m'
else
    GREEN='' RED='' YELLOW='' CYAN='' BOLD='' RESET=''
fi

DO_ASM=0
DO_KILLSWITCH=0

for arg in "$@"; do
    case "$arg" in
        --asm) DO_ASM=1 ;;
        --killswitch) DO_KILLSWITCH=1 ;;
        --all) DO_ASM=1; DO_KILLSWITCH=1 ;;
        --help|-h)
            echo "Usage: $0 [--asm] [--killswitch] [--all]"
            echo "  --asm         Verify NEON instructions in generated assembly"
            echo "  --killswitch  Test NEON kill-switch (compile with NEON disabled)"
            echo "  --all         Run all tests including asm and killswitch"
            exit 0
            ;;
    esac
done

# Check compiler exists
if [ ! -x "$COMPILER" ]; then
    echo -e "${RED}ERROR: Compiler not found at $COMPILER${RESET}"
    echo "Run: cd qbe_basic_integrated && ./build_qbe_basic.sh"
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

# ============================================================
# Phase 1: Compile and run all NEON test files
# ============================================================

echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  NEON SIMD Test Suite${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""

TOTAL_FILES=0
PASSED_FILES=0
FAILED_FILES=0
COMPILE_FAILURES=0
TOTAL_PASS=0
TOTAL_FAIL=0

declare -a FAILED_NAMES=()

for test_file in "$TEST_DIR"/*.bas; do
    [ -f "$test_file" ] || continue
    TOTAL_FILES=$((TOTAL_FILES + 1))

    name=$(basename "$test_file" .bas)
    binary="$OUTPUT_DIR/$name"

    echo -e "${CYAN}--- $name ---${RESET}"

    # Compile
    compile_out=$("$COMPILER" "$test_file" -o "$binary" 2>&1)
    if [ $? -ne 0 ]; then
        echo -e "  ${RED}COMPILE FAILED${RESET}"
        echo "$compile_out" | head -5
        COMPILE_FAILURES=$((COMPILE_FAILURES + 1))
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$name (compile error)")
        echo ""
        continue
    fi

    # Show SIMD detection messages
    echo "$compile_out" | grep '\[SIMD\]' | sed 's/^/  /' || true

    # Run with a timeout
    run_out=$(timeout 10 "$binary" 2>&1) || true

    # Count PASS and FAIL in output
    file_pass=$(echo "$run_out" | grep -c ' PASS' || true)
    file_fail=$(echo "$run_out" | grep -c ' FAIL' || true)

    TOTAL_PASS=$((TOTAL_PASS + file_pass))
    TOTAL_FAIL=$((TOTAL_FAIL + file_fail))

    if [ "$file_fail" -eq 0 ] && [ "$file_pass" -gt 0 ]; then
        echo -e "  ${GREEN}ALL PASS${RESET} ($file_pass assertions)"
        PASSED_FILES=$((PASSED_FILES + 1))
    elif [ "$file_fail" -gt 0 ]; then
        echo -e "  ${RED}FAILURES${RESET}: $file_fail failed, $file_pass passed"
        # Show the failing lines
        echo "$run_out" | grep ' FAIL' | sed 's/^/    /'
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$name ($file_fail failures)")
    else
        echo -e "  ${YELLOW}NO ASSERTIONS${RESET} (no PASS/FAIL found in output)"
        FAILED_FILES=$((FAILED_FILES + 1))
        FAILED_NAMES+=("$name (no assertions)")
    fi
    echo ""
done

# ============================================================
# Phase 2: Assembly verification (optional)
# ============================================================

ASM_OK=0
ASM_TOTAL=0

if [ "$DO_ASM" -eq 1 ]; then
    echo -e "${BOLD}============================================================${RESET}"
    echo -e "${BOLD}  Assembly Verification${RESET}"
    echo -e "${BOLD}============================================================${RESET}"
    echo ""

    ASM_FILE="/tmp/fbasic_neon_asm_verify.s"
    ASM_TEST="$TEST_DIR/test_neon_asm_verify.bas"

    if [ -f "$ASM_TEST" ]; then
        "$COMPILER" "$ASM_TEST" -c -o "$ASM_FILE" 2>/dev/null

        check_asm() {
            local pattern="$1"
            local label="$2"
            local count
            ASM_TOTAL=$((ASM_TOTAL + 1))
            count=$(grep -c "$pattern" "$ASM_FILE" 2>/dev/null || true)
            if [ "$count" -gt 0 ]; then
                echo -e "  ${GREEN}FOUND${RESET}  $label ($count occurrences)"
                ASM_OK=$((ASM_OK + 1))
            else
                echo -e "  ${RED}MISSING${RESET} $label"
            fi
        }

        echo "Checking for NEON instructions in generated assembly..."
        echo ""
        check_asm 'ldr.*q28'            "ldr q28  (NEON 128-bit load)"
        check_asm 'str.*q28'            "str q28  (NEON 128-bit store)"
        check_asm 'ldr.*q29'            "ldr q29  (NEON 128-bit load2)"
        check_asm 'add.*v28\.4s'        "add v28.4s  (integer vector add)"
        check_asm 'sub.*v28\.4s'        "sub v28.4s  (integer vector sub)"
        check_asm 'mul.*v28\.4s'        "mul v28.4s  (integer vector mul)"
        check_asm 'fadd.*v28\.4s'       "fadd v28.4s (float vector add)"
        check_asm 'fsub.*v28\.4s'       "fsub v28.4s (float vector sub)"
        check_asm 'fmul.*v28\.4s'       "fmul v28.4s (float vector mul)"
        check_asm 'fdiv.*v28\.4s'       "fdiv v28.4s (float vector div)"
        check_asm 'fadd.*v28\.2d'       "fadd v28.2d (double vector add)"
        check_asm 'fsub.*v28\.2d'       "fsub v28.2d (double vector sub)"
        check_asm 'fmul.*v28\.2d'       "fmul v28.2d (double vector mul)"
        check_asm 'fdiv.*v28\.2d'       "fdiv v28.2d (double vector div)"

        echo ""
        echo -e "Assembly verification: ${ASM_OK}/${ASM_TOTAL} instruction types found"

        rm -f "$ASM_FILE"
    else
        echo -e "  ${YELLOW}SKIPPED${RESET}: $ASM_TEST not found"
    fi
    echo ""
fi

# ============================================================
# Phase 3: Kill-switch testing (optional)
# ============================================================

KS_PASS=0
KS_TOTAL=0

if [ "$DO_KILLSWITCH" -eq 1 ]; then
    echo -e "${BOLD}============================================================${RESET}"
    echo -e "${BOLD}  Kill-Switch Testing (NEON disabled at compile time)${RESET}"
    echo -e "${BOLD}============================================================${RESET}"
    echo ""

    KS_TEST="$TEST_DIR/test_neon_killswitch.bas"

    if [ -f "$KS_TEST" ]; then
        # Compile with NEON enabled (default)
        KS_ON_BIN="$OUTPUT_DIR/test_neon_killswitch_on"
        "$COMPILER" "$KS_TEST" -o "$KS_ON_BIN" 2>/dev/null
        ks_on_out=$("$KS_ON_BIN" 2>&1) || true
        ks_on_pass=$(echo "$ks_on_out" | grep -c ' PASS' || true)
        ks_on_fail=$(echo "$ks_on_out" | grep -c ' FAIL' || true)

        echo "NEON enabled  (default): $ks_on_pass PASS, $ks_on_fail FAIL"

        # Compile with NEON disabled
        KS_OFF_BIN="$OUTPUT_DIR/test_neon_killswitch_off"
        ENABLE_NEON_COPY=0 ENABLE_NEON_ARITH=0 ENABLE_NEON_LOOP=0 \
            "$COMPILER" "$KS_TEST" -o "$KS_OFF_BIN" 2>/dev/null
        ks_off_out=$("$KS_OFF_BIN" 2>&1) || true
        ks_off_pass=$(echo "$ks_off_out" | grep -c ' PASS' || true)
        ks_off_fail=$(echo "$ks_off_out" | grep -c ' FAIL' || true)

        echo "NEON disabled (env=0):   $ks_off_pass PASS, $ks_off_fail FAIL"

        KS_TOTAL=$((ks_on_pass + ks_on_fail + ks_off_pass + ks_off_fail))
        KS_PASS=$((ks_on_pass + ks_off_pass))

        echo ""
        if [ "$ks_on_fail" -eq 0 ] && [ "$ks_off_fail" -eq 0 ]; then
            echo -e "  ${GREEN}Kill-switch: BOTH PATHS PASS${RESET}"
        elif [ "$ks_on_fail" -eq 0 ]; then
            echo -e "  ${GREEN}NEON path: ALL PASS${RESET}"
            echo -e "  ${RED}Scalar fallback: $ks_off_fail FAILURES${RESET}"
            echo "  (No scalar fallback for UDT arithmetic — known limitation)"
            echo ""
            echo "  Failing tests with NEON disabled:"
            echo "$ks_off_out" | grep ' FAIL' | sed 's/^/    /'
        else
            echo -e "  ${RED}NEON path: $ks_on_fail FAILURES${RESET}"
            echo "  Failing tests:"
            echo "$ks_on_out" | grep ' FAIL' | sed 's/^/    /'
        fi
    else
        echo -e "  ${YELLOW}SKIPPED${RESET}: $KS_TEST not found"
    fi
    echo ""
fi

# ============================================================
# Summary
# ============================================================

echo -e "${BOLD}============================================================${RESET}"
echo -e "${BOLD}  Summary${RESET}"
echo -e "${BOLD}============================================================${RESET}"
echo ""
echo "Test files:          $TOTAL_FILES"
echo -e "  Fully passing:     ${GREEN}$PASSED_FILES${RESET}"
if [ "$FAILED_FILES" -gt 0 ]; then
    echo -e "  With failures:     ${RED}$FAILED_FILES${RESET}"
fi
if [ "$COMPILE_FAILURES" -gt 0 ]; then
    echo -e "  Compile failures:  ${RED}$COMPILE_FAILURES${RESET}"
fi
echo ""
echo "Assertions:          $((TOTAL_PASS + TOTAL_FAIL))"
echo -e "  PASS:              ${GREEN}$TOTAL_PASS${RESET}"
if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo -e "  FAIL:              ${RED}$TOTAL_FAIL${RESET}"
else
    echo -e "  FAIL:              ${GREEN}0${RESET}"
fi

if [ "$DO_ASM" -eq 1 ]; then
    echo ""
    echo -e "Assembly checks:     ${ASM_OK}/${ASM_TOTAL} instruction types verified"
fi

if [ "$DO_KILLSWITCH" -eq 1 ]; then
    echo ""
    echo "Kill-switch:         $KS_PASS pass / $KS_TOTAL total assertions"
fi

echo ""

if [ ${#FAILED_NAMES[@]} -gt 0 ]; then
    echo -e "${RED}Failed test files:${RESET}"
    for fn in "${FAILED_NAMES[@]}"; do
        echo -e "  ${RED}*${RESET} $fn"
    done
    echo ""
fi

# Known issues summary
if [ "$TOTAL_FAIL" -gt 0 ]; then
    echo -e "${YELLOW}Known Issues:${RESET}"
    echo "  1. Array element UDT copy (Arr(i) = Scalar, Arr(i) = Arr(j))"
    echo "     stores pointer instead of data — codegen bug in emitLetStatement"
    echo "  2. Chained copy (D=C after C=A+B) fails for some paths"
    echo "  3. Float literal comparison (SINGLE vs DOUBLE precision mismatch)"
    echo "     e.g., 3.14 as SINGLE != 3.14 as DOUBLE — not a NEON bug"
    echo "  4. Loop verification with float <> comparison fails even when"
    echo "     individual element checks pass — float comparison precision issue"
    echo "  5. No scalar fallback for UDT arithmetic (C=A+B) when NEON disabled"
    echo ""
fi

if [ "$TOTAL_FAIL" -eq 0 ] && [ "$COMPILE_FAILURES" -eq 0 ]; then
    echo -e "${GREEN}${BOLD}ALL NEON TESTS PASSED!${RESET}"
    exit 0
else
    echo -e "${YELLOW}${BOLD}Some tests have failures — see details above.${RESET}"
    exit 1
fi
