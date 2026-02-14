#!/bin/bash
# tools/jit_instruction_dump.sh
#
# Generates ARM64 machine code bytes for a given assembly instruction.
# Useful for verifying JIT encoder output against system tools.
#
# Usage: ./tools/jit_instruction_dump.sh "instruction string"
# Example: ./tools/jit_instruction_dump.sh "add x0, x1, #42"

INSTRUCTION="$1"

if [ -z "$INSTRUCTION" ]; then
    echo "Usage: $0 \"instruction string\""
    echo "Example: $0 \"add x0, x1, #42\""
    exit 1
fi

# Try to find llvm-mc either in path or common locations
LLVM_MC="llvm-mc"
if ! command -v $LLVM_MC &> /dev/null; then
    # Check if Homebrew llvm is installed
    if [ -f "/opt/homebrew/opt/llvm/bin/llvm-mc" ]; then
        LLVM_MC="/opt/homebrew/opt/llvm/bin/llvm-mc"
    elif [ -f "/usr/local/opt/llvm/bin/llvm-mc" ]; then
        LLVM_MC="/usr/local/opt/llvm/bin/llvm-mc"
    fi
fi

if command -v $LLVM_MC &> /dev/null; then
    # Method 1: Use llvm-mc (Direct and cleanest)
    echo "Using: $LLVM_MC"
    echo ".text" | $LLVM_MC -arch=arm64 -show-encoding --defsym "$INSTRUCTION" 2>/dev/null || \
    echo "$INSTRUCTION" | $LLVM_MC -arch=arm64 -show-encoding
else
    # Method 2: Use system clang and objdump (Universal)
    echo "Using: clang (system assembler)"
    TMP_SRC=$(mktemp /tmp/jit_test.XXXXXX.s)
    TMP_OBJ="${TMP_SRC}.o"

    # Create assembly source
    echo ".text" > "$TMP_SRC"
    echo ".align 2" >> "$TMP_SRC"
    echo "    $INSTRUCTION" >> "$TMP_SRC"

    # Assemble
    clang -c "$TMP_SRC" -o "$TMP_OBJ" -arch arm64

    if [ $? -eq 0 ]; then
        # Disassemble to show instruction
        echo "Disassembly:"
        objdump -d "$TMP_OBJ" | grep -v "$TMP_OBJ" | grep -v "file format" | tail -n +2
        
        # Get raw hex from otool (Text Section)
        # otool output format:
        # address   hex_word1 hex_word2 ...
        # We use awk to skip the first field (address) and print the rest
        HEX_WORDS=$(otool -t -X "$TMP_OBJ" | awk '{for (i=2; i<=NF; i++) print $i}')
        
        echo "Text Section Hex (32-bit words):"
        echo "$HEX_WORDS"

        # Format as byte array (little-endian for ARM64)
        echo "C/Zig Byte Array (Little Endian):"
        echo -n "{ "
        for word in $HEX_WORDS; do
            # word is like "9100a820"
            # little endian: 20, a8, 00, 91
            # Note: otool output is hex string.
            b3=${word:0:2}
            b2=${word:2:2}
            b1=${word:4:2}
            b0=${word:6:2}
            # ARM64 instructions are 32-bit (4 bytes).
            # otool -t -X dumps in host byte order (little endian on M1/M2/M3)
            # but usually displays as 32-bit integer hex.
            # 0x9100a820 stored as 20 a8 00 91.
            # So the least significant byte is 0x20.
            echo -n "0x$b0, 0x$b1, 0x$b2, 0x$b3, "
        done
        echo "}"
    else
        echo "Assembly failed."
    fi

    # Cleanup
    rm -f "$TMP_SRC" "$TMP_OBJ"
fi
