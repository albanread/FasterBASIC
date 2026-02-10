#!/bin/sh
# Build script for zbased - Zig text editor using FasterBASIC runtime

echo "Building zbased..."
echo

# Paths
RUNTIME_DIR="../zig_compiler/zig-out/lib"
RUNTIME_INCLUDE="../zig_compiler/runtime"

# Check if runtime libraries exist
if [ ! -d "$RUNTIME_DIR" ]; then
    echo "Error: Runtime libraries not found at $RUNTIME_DIR"
    echo "Please build FasterBASIC first: cd ../zig_compiler && zig build"
    exit 1
fi

# Compile zbased.zig to object file
echo "Compiling zbased.zig..."
zig build-obj zbased.zig \
    -O ReleaseFast \
    -target native \
    -fno-strip

if [ $? -ne 0 ]; then
    echo "Failed to compile zbased.zig"
    exit 1
fi

# Link with runtime libraries
echo "Linking with runtime libraries..."
cc -o zbased zbased.o \
    "$RUNTIME_DIR/libterminal_io.a" \
    "$RUNTIME_DIR/libio_ops.a" \
    "$RUNTIME_DIR/libstring_utf32.a" \
    "$RUNTIME_DIR/libstring_ops.a" \
    "$RUNTIME_DIR/libmemory_mgmt.a" \
    -lc -lm

if [ $? -ne 0 ]; then
    echo "Failed to link zbased"
    exit 1
fi

# Clean up object file
rm -f zbased.o

echo
echo "✓ Build successful!"
echo
echo "Run the editor:"
echo "  ./zbased"
echo "  ./zbased myfile.txt"
echo
