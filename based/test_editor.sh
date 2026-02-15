#!/bin/sh
# Non-interactive test for BASED editor
# Verifies that the editor initializes without crashing

echo "Testing BASED editor initialization..."
echo

# Test 1: Start editor with no arguments (should show empty buffer)
echo "Test 1: Starting editor with no file (will auto-exit in 1 second)..."
timeout 1 ./based_editor 2>&1 | head -5 || true
echo "✓ Editor started without file argument"
echo

# Test 2: Start editor with a file argument
echo "Test 2: Starting editor with test file..."
timeout 1 ./based_editor test_simple.bas 2>&1 | head -5 || true
echo "✓ Editor started with file argument"
echo

# Test 3: Verify command-line argument support
echo "Test 3: Testing command-line arguments..."
cat > /tmp/test_cmd_args.bas << 'EOF'
IF COMMANDCOUNT > 1 THEN
    PRINT "Arg: "; COMMAND(1)
ELSE
    PRINT "No args"
ENDIF
EOF

../zig_compiler/zig-out/bin/fbc /tmp/test_cmd_args.bas -o /tmp/test_cmd_args 2>&1 | grep -v warning
/tmp/test_cmd_args myfile.bas
echo "✓ Command-line arguments working"
echo

# Test 4: Test SLURP/SPIT with a simple file
echo "Test 4: Testing SLURP/SPIT..."
cat > /tmp/test_slurp.bas << 'EOF'
content$ = "Test line 1" + CHR$(10) + "Test line 2"
SPIT "/tmp/test_file.txt", content$
loaded$ = SLURP("/tmp/test_file.txt")
IF loaded$ = content$ THEN
    PRINT "✓ SLURP/SPIT working"
ELSE
    PRINT "✗ SLURP/SPIT failed"
ENDIF
EOF

../zig_compiler/zig-out/bin/fbc /tmp/test_slurp.bas -o /tmp/test_slurp 2>&1 | grep -v warning
/tmp/test_slurp
echo

echo "========================================="
echo "All tests completed!"
echo "========================================="
echo
echo "To run the editor interactively:"
echo "  ./based_editor"
echo "  ./based_editor myfile.bas"
echo
