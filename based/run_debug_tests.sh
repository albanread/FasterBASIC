#!/bin/sh
echo "=== Compiling debug tests ==="
../zig_compiler/zig-out/bin/fbc test_debug.bas -o test_debug
../zig_compiler/zig-out/bin/fbc test_grid.bas -o test_grid
../zig_compiler/zig-out/bin/fbc test_editor_debug.bas -o test_editor_debug 2>&1 | grep -E '(Compiled|error)'

echo ""
echo "=== Run these tests ==="
echo "1. ./test_debug      - Simple positioning test"
echo "2. ./test_grid       - Visual grid showing coordinates"
echo "3. ./test_editor_debug test_file.bas   - Editor with logging to debug.log"
echo ""
echo "For the debug editor:"
echo "  - Use arrow keys, type, etc"
echo "  - Quit with Ctrl+Q"
echo "  - Check 'debug.log' to see what happened"
echo ""
echo "To record terminal session:"
echo "  script -q terminal_session.txt"
echo "  ./test_grid"
echo "  exit"
echo "  cat terminal_session.txt  # Review what happened"
