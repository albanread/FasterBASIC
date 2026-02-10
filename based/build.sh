#!/bin/sh
# Build script for BASED - BASIC Editor

echo "Building BASED - FasterBASIC Editor..."
echo

# Path to FasterBASIC compiler
FBC="../zig_compiler/zig-out/bin/fbc"

# Check if fbc exists
if [ ! -f "$FBC" ]; then
    echo "Error: fbc not found at $FBC"
    echo "Please build FasterBASIC first: cd ../zig_compiler && zig build"
    exit 1
fi

# Compile BASED
echo "Compiling based.bas..."
"$FBC" based.bas -o based

if [ $? -eq 0 ]; then
    echo
    echo "✓ Build successful!"
    echo
    echo "Run the editor with: ./based"
    echo
    echo "Or load a file: ./based examples/hello.bas"
    echo
else
    echo
    echo "✗ Build failed!"
    exit 1
fi
