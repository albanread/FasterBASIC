#!/bin/sh
#
# run_all_tests.sh — Run all .bas tests in both JIT and AOT modes
# POSIX-compatible (no bash 4+ features)
#
# Usage: ./run_all_tests.sh [--jit-only | --aot-only] [--timeout N] [--filter PATTERN] [--verbose]
#

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FBC="$SCRIPT_DIR/zig_compiler/zig-out/bin/fbc"
TEST_DIR="$SCRIPT_DIR/tests"
TIMEOUT=10
MODE="both"
FILTER=""
TMPDIR_BASE="${TMPDIR:-/tmp}/fbc_test_$$"
VERBOSE=0

while [ $# -gt 0 ]; do
    case "$1" in
        --jit-only)  MODE="jit"; shift ;;
        --aot-only)  MODE="aot"; shift ;;
        --timeout)   TIMEOUT="$2"; shift 2 ;;
        --filter)    FILTER="$2"; shift 2 ;;
        --verbose|-v) VERBOSE=1; shift ;;
        --help|-h)
            echo "Usage: $0 [--jit-only | --aot-only] [--timeout N] [--filter PATTERN] [--verbose]"
            exit 0
            ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

if [ ! -x "$FBC" ]; then
    echo "ERROR: Compiler not found at $FBC"
    echo "Run 'cd zig_compiler && zig build' first."
    exit 1
fi

mkdir -p "$TMPDIR_BASE"

# Check for gtimeout (brew install coreutils) or timeout
if command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
elif command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
else
    echo "WARNING: No timeout command found. Tests that hang will block forever."
    echo "  Install coreutils: brew install coreutils"
    TIMEOUT_CMD=""
fi

run_with_timeout() {
    local secs="$1"
    shift
    if [ -n "$TIMEOUT_CMD" ]; then
        "$TIMEOUT_CMD" "${secs}s" "$@"
    else
        "$@"
    fi
}

# Counters
JIT_PASS=0; JIT_FAIL=0; JIT_TIMEOUT=0
AOT_PASS=0; AOT_FAIL=0; AOT_TIMEOUT=0

# Failure lists stored in temp files
JIT_FAIL_LIST="$TMPDIR_BASE/_jit_failures.txt"
AOT_FAIL_LIST="$TMPDIR_BASE/_aot_failures.txt"
CAT_STATS="$TMPDIR_BASE/_cat_stats.txt"
: > "$JIT_FAIL_LIST"
: > "$AOT_FAIL_LIST"
: > "$CAT_STATS"

# Collect test files
TEST_LIST="$TMPDIR_BASE/_test_list.txt"
find "$TEST_DIR" -name '*.bas' -type f | sort > "$TEST_LIST"
TOTAL=$(wc -l < "$TEST_LIST" | tr -d ' ')

echo "============================================================"
echo "  FasterBASIC Test Runner"
echo "============================================================"
echo "  Compiler : $FBC"
echo "  Test dir : $TEST_DIR"
echo "  Tests    : $TOTAL"
echo "  Timeout  : ${TIMEOUT}s per test"
echo "  Mode     : $MODE"
[ -n "$FILTER" ] && echo "  Filter   : $FILTER"
echo "============================================================"
echo ""

current_category=""

while IFS= read -r bas_file; do
    # Apply filter
    if [ -n "$FILTER" ]; then
        case "$bas_file" in
            *"$FILTER"*) ;;
            *) continue ;;
        esac
    fi

    rel_path="${bas_file#$TEST_DIR/}"
    category=$(dirname "$rel_path")
    [ "$category" = "." ] && category="(root)"
    test_name=$(basename "$rel_path")

    # Print category header on change
    if [ "$category" != "$current_category" ]; then
        [ -n "$current_category" ] && echo ""
        echo "── $category ──"
        current_category="$category"
    fi

    printf "  %-55s" "$test_name"

    # ── JIT test ──
    if [ "$MODE" = "both" ] || [ "$MODE" = "jit" ]; then
        jit_output=$(run_with_timeout "$TIMEOUT" "$FBC" --jit "$bas_file" 2>&1)
        jit_rc=$?
        if [ $jit_rc -eq 124 ]; then
            printf " JIT:⏱"
            JIT_TIMEOUT=$((JIT_TIMEOUT + 1))
            echo "$rel_path (timeout)" >> "$JIT_FAIL_LIST"
            echo "JIT_TIMEOUT $category" >> "$CAT_STATS"
        elif [ $jit_rc -ne 0 ]; then
            printf " JIT:✗"
            JIT_FAIL=$((JIT_FAIL + 1))
            echo "$rel_path" >> "$JIT_FAIL_LIST"
            echo "JIT_FAIL $category" >> "$CAT_STATS"
            if [ "$VERBOSE" = "1" ]; then
                printf "\n    OUTPUT: %s" "$(echo "$jit_output" | tail -1)"
            fi
        else
            printf " JIT:✓"
            JIT_PASS=$((JIT_PASS + 1))
            echo "JIT_PASS $category" >> "$CAT_STATS"
        fi
    fi

    # ── AOT test ──
    if [ "$MODE" = "both" ] || [ "$MODE" = "aot" ]; then
        bin_name="$TMPDIR_BASE/$(echo "$rel_path" | sed 's|/|__|g' | sed 's|\.bas$||')"

        # Compile
        aot_compile=$(run_with_timeout "$TIMEOUT" "$FBC" "$bas_file" -o "$bin_name" 2>&1)
        aot_rc=$?
        if [ $aot_rc -eq 124 ]; then
            printf " AOT:⏱"
            AOT_TIMEOUT=$((AOT_TIMEOUT + 1))
            echo "$rel_path (compile timeout)" >> "$AOT_FAIL_LIST"
            echo "AOT_TIMEOUT $category" >> "$CAT_STATS"
        elif [ $aot_rc -ne 0 ]; then
            printf " AOT:✗"
            AOT_FAIL=$((AOT_FAIL + 1))
            echo "$rel_path" >> "$AOT_FAIL_LIST"
            echo "AOT_FAIL $category" >> "$CAT_STATS"
            if [ "$VERBOSE" = "1" ]; then
                errmsg=$(echo "$aot_compile" | grep -v '^ld: warning' | tail -1)
                printf "\n    COMPILE: %s" "$errmsg"
            fi
        else
            # Run
            aot_output=$(run_with_timeout "$TIMEOUT" "$bin_name" 2>&1)
            run_rc=$?
            rm -f "$bin_name"
            if [ $run_rc -eq 124 ]; then
                printf " AOT:⏱"
                AOT_TIMEOUT=$((AOT_TIMEOUT + 1))
                echo "$rel_path (run timeout)" >> "$AOT_FAIL_LIST"
                echo "AOT_TIMEOUT $category" >> "$CAT_STATS"
            elif [ $run_rc -ne 0 ]; then
                printf " AOT:✗"
                AOT_FAIL=$((AOT_FAIL + 1))
                echo "$rel_path" >> "$AOT_FAIL_LIST"
                echo "AOT_FAIL $category" >> "$CAT_STATS"
                if [ "$VERBOSE" = "1" ]; then
                    printf "\n    RUN: %s" "$(echo "$aot_output" | tail -1)"
                fi
            else
                printf " AOT:✓"
                AOT_PASS=$((AOT_PASS + 1))
                echo "AOT_PASS $category" >> "$CAT_STATS"
            fi
        fi
    fi

    echo ""
done < "$TEST_LIST"

# ── Summary ──
echo ""
echo "============================================================"
echo "  SUMMARY"
echo "============================================================"

if [ "$MODE" = "both" ] || [ "$MODE" = "jit" ]; then
    JIT_TOTAL=$((JIT_PASS + JIT_FAIL + JIT_TIMEOUT))
    if [ $JIT_TOTAL -gt 0 ]; then
        JIT_PCT=$((JIT_PASS * 100 / JIT_TOTAL))
    else
        JIT_PCT=0
    fi
    echo ""
    echo "  JIT Mode:"
    echo "    Pass:    $JIT_PASS / $JIT_TOTAL"
    echo "    Fail:    $JIT_FAIL"
    echo "    Timeout: $JIT_TIMEOUT"
    echo "    Rate:    ${JIT_PCT}%"
fi

if [ "$MODE" = "both" ] || [ "$MODE" = "aot" ]; then
    AOT_TOTAL=$((AOT_PASS + AOT_FAIL + AOT_TIMEOUT))
    if [ $AOT_TOTAL -gt 0 ]; then
        AOT_PCT=$((AOT_PASS * 100 / AOT_TOTAL))
    else
        AOT_PCT=0
    fi
    echo ""
    echo "  AOT Mode:"
    echo "    Pass:    $AOT_PASS / $AOT_TOTAL"
    echo "    Fail:    $AOT_FAIL"
    echo "    Timeout: $AOT_TIMEOUT"
    echo "    Rate:    ${AOT_PCT}%"
fi

# ── Category breakdown ──
echo ""
echo "============================================================"
echo "  BY CATEGORY"
echo "============================================================"

# Extract unique categories from stats
if [ -s "$CAT_STATS" ]; then
    cats=$(awk '{print $2}' "$CAT_STATS" | sort -u)
    for cat in $cats; do
        jp=$(grep -c "^JIT_PASS $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)
        jf=$(grep -c "^JIT_FAIL $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)
        jt=$(grep -c "^JIT_TIMEOUT $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)
        ap=$(grep -c "^AOT_PASS $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)
        af=$(grep -c "^AOT_FAIL $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)
        at=$(grep -c "^AOT_TIMEOUT $cat\$" "$CAT_STATS" 2>/dev/null || echo 0)

        line=$(printf "  %-28s" "$cat")

        if [ "$MODE" = "both" ] || [ "$MODE" = "jit" ]; then
            jtotal=$((jp + jf + jt))
            line="$line JIT: ${jp}/${jtotal}"
            [ "$jf" -gt 0 ] && line="$line (${jf} fail)"
            [ "$jt" -gt 0 ] && line="$line (${jt} tmout)"
        fi
        if [ "$MODE" = "both" ] || [ "$MODE" = "aot" ]; then
            atotal=$((ap + af + at))
            line="$line  AOT: ${ap}/${atotal}"
            [ "$af" -gt 0 ] && line="$line (${af} fail)"
            [ "$at" -gt 0 ] && line="$line (${at} tmout)"
        fi
        echo "$line"
    done
fi

# ── List failures ──
if [ "$MODE" = "both" ] || [ "$MODE" = "jit" ]; then
    if [ -s "$JIT_FAIL_LIST" ]; then
        echo ""
        echo "============================================================"
        echo "  JIT FAILURES ($((JIT_FAIL + JIT_TIMEOUT)))"
        echo "============================================================"
        while IFS= read -r line; do
            echo "    $line"
        done < "$JIT_FAIL_LIST"
    fi
fi

if [ "$MODE" = "both" ] || [ "$MODE" = "aot" ]; then
    if [ -s "$AOT_FAIL_LIST" ]; then
        echo ""
        echo "============================================================"
        echo "  AOT FAILURES ($((AOT_FAIL + AOT_TIMEOUT)))"
        echo "============================================================"
        while IFS= read -r line; do
            echo "    $line"
        done < "$AOT_FAIL_LIST"
    fi
fi

# Cleanup
rm -rf "$TMPDIR_BASE"

echo ""
echo "============================================================"
echo "  Done."
echo "============================================================"

# Exit code: 0 if all passed, 1 if any failed/timed out
if [ "$MODE" = "both" ]; then
    [ $JIT_FAIL -eq 0 ] && [ $AOT_FAIL -eq 0 ] && [ $JIT_TIMEOUT -eq 0 ] && [ $AOT_TIMEOUT -eq 0 ]
elif [ "$MODE" = "jit" ]; then
    [ $JIT_FAIL -eq 0 ] && [ $JIT_TIMEOUT -eq 0 ]
else
    [ $AOT_FAIL -eq 0 ] && [ $AOT_TIMEOUT -eq 0 ]
fi
