# Makefile for QBE Hashmap Module
# Builds and tests the hand-coded QBE hashmap implementation

.PHONY: all clean test hashmap.o test_hashmap qbe

# Compiler and tools
CC = cc
FBC_QBE = ../fbc_qbe
CFLAGS = -std=c99 -O2 -Wall -Wextra
LDFLAGS =

# Default target
all: test_hashmap

# Compile QBE source to object file using fbc_qbe
hashmap.o: hashmap.qbe
	@echo "Compiling QBE hashmap module to object file..."
	$(FBC_QBE) hashmap.qbe -o hashmap.o

# Build test program
test_hashmap: test_hashmap.c hashmap.o
	@echo "Building test program..."
	$(CC) $(CFLAGS) -o $@ test_hashmap.c hashmap.o $(LDFLAGS)

# Run tests
test: test_hashmap
	@echo ""
	@echo "Running hashmap tests..."
	@echo ""
	./test_hashmap

# Clean build artifacts
clean:
	@echo "Cleaning build artifacts..."
	rm -f hashmap.o test_hashmap
	@echo "Clean complete."

# Help target
help:
	@echo "QBE Hashmap Module Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  all          - Build everything (default)"
	@echo "  test         - Build and run tests"
	@echo "  clean        - Remove build artifacts"
	@echo "  hashmap.o    - Build hashmap object file only"
	@echo "  help         - Show this help message"
	@echo ""
	@echo "Files:"
	@echo "  hashmap.qbe  - QBE IL source for hashmap"
	@echo "  hashmap.h    - C header interface"
	@echo "  test_hashmap.c - Test program"
