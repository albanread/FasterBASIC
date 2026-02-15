#!/bin/sh
# Terminal I/O Test Script
# Tests the fixes to terminal_io.zig

set -e

echo "=========================================="
echo "Terminal I/O Test Suite"
echo "=========================================="
echo ""

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
COMPILER="$SCRIPT_DIR/../zig_compiler/zig-out/bin/fbc"

# Check if compiler exists
if [ ! -f "$COMPILER" ]; then
    echo "ERROR: Compiler not found at $COMPILER"
    echo "Please run 'cd ../zig_compiler && zig build' first"
    exit 1
fi

echo "Using compiler: $COMPILER"
echo ""

# Test 1: Compile test_locate_auto.bas
echo "Test 1: Compiling test_locate_auto.bas..."
cd "$SCRIPT_DIR"
if $COMPILER test_locate_auto.bas -o test_locate_auto 2>&1 | grep -q "Compiled:"; then
    echo "  ✓ Compilation successful"
else
    echo "  ✗ Compilation failed"
    exit 1
fi

# Test 2: Run test_locate_auto (non-interactive)
echo ""
echo "Test 2: Running test_locate_auto (non-interactive test)..."
echo "  This should display text at various screen positions."
echo "  Press ENTER when prompted to continue..."
echo ""
echo "--- OUTPUT START ---"
./test_locate_auto
echo "--- OUTPUT END ---"
echo ""

# Test 3: Compile the editor
echo "Test 3: Compiling based.bas (the editor)..."
if $COMPILER based.bas -o based_editor 2>&1 | grep -q "Compiled:"; then
    echo "  ✓ Editor compilation successful"
else
    echo "  ✗ Editor compilation failed"
    exit 1
fi

# Test 4: Verify editor binary exists
echo ""
echo "Test 4: Verifying editor binary..."
if [ -f "$SCRIPT_DIR/based_editor" ]; then
    echo "  ✓ Editor binary created: based_editor"
else
    echo "  ✗ Editor binary not found"
    exit 1
fi

# Summary
echo ""
echo "=========================================="
echo "Test Summary"
echo "=========================================="
echo ""
echo "✓ All compilation tests passed"
echo "✓ Non-interactive test completed"
echo "✓ Editor binary ready"
echo ""
echo "To test the editor interactively, run:"
echo "  cd $SCRIPT_DIR"
echo "  ./based_editor test_file.bas"
echo ""
echo "Expected behavior:"
echo "  - Title bar at top (white on blue)"
echo "  - File content in the middle with line numbers"
echo "  - Status/help line at bottom (black on white)"
echo "  - No overlapping or garbled text"
echo "  - Arrow keys should move cursor"
echo "  - Ctrl+Q to quit"
echo ""
