# Scripts

This directory contains utility scripts for building, testing, and maintaining the FasterBASIC QBE compiler.

---

## ⚠️ IMPORTANT: TEST RUNNER LOCATION

**THE MAIN TEST RUNNER IS AT PROJECT ROOT:**

```bash
cd /path/to/FBCQBE
./run_tests.sh
```

**DO NOT** look for test runners in this scripts directory. The primary test script has been moved to the project root for visibility.

---

## Available Scripts

### Build Scripts

- **See [../qbe_basic_integrated/build_qbe_basic.sh](../qbe_basic_integrated/build_qbe_basic.sh)** - Main build script
  - This is the ONLY build script you should use
  - Builds the QBE compiler with FasterBASIC integration
  - Run from `qbe_basic_integrated/` directory

### Test Scripts

**⚠️ PRIMARY TEST RUNNER:** Use `./run_tests.sh` from the project root (not in this directory)

- **run_tests_simple.sh** - Source for main test runner
  - This file is copied to `../run_tests.sh` at project root
  - DO NOT run from this scripts directory
  - Always use `./run_tests.sh` from project root

- **verify_implementation.sh** - Comprehensive verification
  - Alternative verification script
  - Less commonly used
  - Use `./run_tests.sh` instead for standard testing

### Utility Scripts

- **generate_tests.sh** - Generate test cases
  - Creates test programs programmatically
  - Useful for regression testing

- **organize.sh** - Directory organization
  - One-time script used to reorganize project structure
  - Kept for reference

## Usage

**CORRECT WAY TO RUN TESTS:**

```bash
# From project root - THIS IS THE ONLY CORRECT COMMAND
./run_tests.sh
```

**DO NOT** run test scripts from the scripts directory. The main test runner is at the project root for easy access.

If you need to run other utility scripts:

```bash
# Run from project root
./scripts/generate_tests.sh
```

## Building the Compiler

**Important:** Do NOT use any build scripts in this directory. Always use:

```bash
cd qbe_basic_integrated
./build_qbe_basic.sh
```

See [../BUILD.md](../BUILD.md) for detailed build instructions.

## Test Organization

- **Test programs**: [../test_programs/](../test_programs/)
  - `examples/` - Example BASIC programs
  - `scratch/` - Temporary test files (gitignored)
  
- **Test suite**: [../tests/](../tests/)
  - Organized test cases by feature
  - Used by verification scripts

## Adding New Scripts

When adding new scripts:

1. Make them executable: `chmod +x scriptname.sh`
2. Add a header comment explaining the script's purpose
3. Document usage in this README
4. Follow bash best practices (set -e, proper error handling)
5. Test from project root to ensure paths work correctly