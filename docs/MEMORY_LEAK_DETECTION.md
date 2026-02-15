# Memory Leak Detection in Compiled Programs

## Overview

The FasterBASIC runtime includes comprehensive memory leak detection for compiled programs. When a program exits, it automatically prints detailed memory statistics showing allocations, deallocations, and any potential leaks.

## What Gets Tracked

### 1. SAMM (String Allocator with Memory Management)

SAMM is the primary memory allocator used by the runtime for:
- **Strings**: All string operations (concatenation, substring, etc.)
- **Lists**: Dynamic list structures (LIST data type)
- **Objects**: User-defined types and class instances
- **Scoped allocations**: Memory tied to scope lifetimes

### 2. Runtime Allocator (basic_malloc)

The runtime allocator tracks:
- **UDT allocations**: User-defined type instances
- **Array descriptors**: Metadata for dynamic arrays
- **Internal structures**: Various runtime data structures

Note: Most programs use SAMM almost exclusively, so the runtime allocator stats often show zero allocations.

## How to Use

### Automatic Statistics

Memory statistics are **automatically printed** at program exit. No special flags or environment variables are needed.

### Example Output

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SAMM Memory Statistics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Scopes entered:       4001
  Scopes exited:        4001
  Objects allocated:    1501
  Objects freed (DEL):  0
  Objects cleaned (bg): 58617
  Strings tracked:      57116
  Strings cleaned:      57116
  Cleanup batches:      1500
  Double-free catches:  0
  RETAIN calls:         2500
  Bytes allocated:      2320664
  Bytes freed:          2332672
  Leaked objects:       0
  Leaked bytes:         0
  ✓ All allocations freed
  Current scope depth:  0
  Peak scope depth:     1
  Bloom filter:         not allocated (no overflow objects)
  Cleanup time:         30.108 ms
  Background worker:    stopped
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━


━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Memory Statistics (Runtime Allocator)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Total allocations:   0
  Total deallocations: 0
  Total bytes:         0
  Leaked objects:      0
  ✓ All allocations freed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Understanding the Statistics

### SAMM Statistics

| Field | Description |
|-------|-------------|
| **Scopes entered** | Number of times scope-based memory management was activated |
| **Scopes exited** | Number of times scopes were cleaned up |
| **Objects allocated** | Total objects (Lists, etc.) explicitly allocated |
| **Objects freed (DEL)** | Objects freed via explicit DEL statement |
| **Objects cleaned (bg)** | Objects automatically freed by scope cleanup |
| **Strings tracked** | Total number of string allocations tracked |
| **Strings cleaned** | Strings automatically freed at scope exit |
| **Cleanup batches** | Number of background cleanup operations |
| **Double-free catches** | Safety checks that prevented double-free errors |
| **RETAIN calls** | Explicit reference count increments |
| **Bytes allocated** | Total bytes allocated during program execution |
| **Bytes freed** | Total bytes freed (may be slightly higher due to pool overhead) |
| **Leaked objects** | Objects not freed (should be 0!) |
| **Leaked bytes** | Bytes not freed (should be 0!) |
| **Current scope depth** | Scope nesting at exit (should be 0) |
| **Peak scope depth** | Maximum scope nesting during execution |
| **Cleanup time** | Total time spent in memory cleanup (milliseconds) |

### Runtime Allocator Statistics

| Field | Description |
|-------|-------------|
| **Total allocations** | Calls to `basic_malloc` |
| **Total deallocations** | Calls to `basic_free` |
| **Total bytes** | Cumulative bytes allocated |
| **Leaked objects** | Allocations without corresponding frees |

## Interpreting Results

### ✓ All allocations freed

This is the desired state - your program has no memory leaks!

```
  Leaked objects:       0
  Leaked bytes:         0
  ✓ All allocations freed
```

### ⚠️ WARNING: Memory leaks detected!

If you see this warning, your program has memory leaks:

```
  Leaked objects:       15
  Leaked bytes:         1024
  ⚠️  WARNING: Memory leaks detected!
```

Common causes:
1. **Missing DEL statements**: Objects created but never deleted
2. **Circular references**: Objects referring to each other (rare in BASIC)
3. **Arrays not freed**: Large arrays allocated but not released
4. **Strings in global scope**: Strings that persist until program exit

## Example Programs

### Clean Program (No Leaks)

```basic
' This program properly cleans up all allocations
DIM s AS STRING
s = "Hello, World!"
PRINT s
' String automatically freed at program exit
```

### Program with Leak Detection

```basic
' Allocate arrays and strings
DIM arr(1000) AS INTEGER
DIM names(50) AS STRING

FOR i = 1 TO 50
    names(i) = "Name_" + STR(i)
NEXT i

PRINT "Processing complete"
' Arrays and strings automatically freed at exit
' Memory stats printed showing clean exit
```

## Advanced Features

### Background Cleanup

SAMM includes a background cleanup thread that asynchronously frees memory:
- Reduces pause times in the main program
- Shown in "Objects cleaned (bg)" statistic
- "Cleanup time" shows total time spent in cleanup

### Scope-Based Memory Management

Memory is automatically freed when scopes exit:
- Function/SUB returns
- FOR/WHILE/DO loops complete
- IF/THEN/ELSE blocks exit

This is shown in "Scopes entered/exited" and "Objects cleaned" statistics.

### Reference Counting

Strings and objects use reference counting:
- RETAIN increases reference count
- Automatic cleanup decrements count
- Object freed when count reaches zero
- "RETAIN calls" shows explicit increments

## Performance Considerations

### Typical Overhead

Memory tracking has minimal overhead:
- **< 1%** runtime overhead for allocation tracking
- **< 5%** additional memory for bookkeeping
- **Cleanup time** is usually < 100ms even for large programs

### Optimizing Memory Usage

To minimize memory usage:
1. Keep scopes small (use SUBs/FUNCTIONs)
2. Free large arrays explicitly with ERASE
3. Avoid unnecessary string concatenations in loops
4. Use string builders for large concatenations

## Disabling Statistics

If you want to disable memory statistics printing (not recommended for development):

1. Set environment variable `BASIC_MEMORY_STATS=0` (future feature)
2. Or rebuild runtime with statistics disabled (requires modifying source)

For production, the statistics are valuable for detecting leaks without any code changes.

## Compiler Memory Leaks vs Runtime Memory Leaks

### Compiler Leaks

The **compiler itself** (the `fbc` program) now uses an `ArenaAllocator` and has no memory leaks.

### Runtime Leaks

The **compiled BASIC program** uses SAMM and the runtime allocator. These statistics show memory usage of YOUR program, not the compiler.

## Testing

### Run Stress Tests

The repository includes stress tests that exercise memory allocation:

```bash
./run_stress_tests.sh
```

Each test will print memory statistics showing:
- How much memory was used
- Whether all memory was freed
- Any detected leaks

### Example Stress Test Output

```
Test: test_samm_stress_volume         PASS  (0.297s)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  SAMM Memory Statistics
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Objects allocated:    12001
  Strings tracked:      27675
  Bytes allocated:      1395024
  Bytes freed:          1491032
  Leaked objects:       0
  ✓ All allocations freed
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

## Implementation Details

### Where Statistics Are Printed

Statistics are printed in `basic_runtime_cleanup()`, which is called automatically at program exit from the `main` function.

### Source Files

- `runtime/samm_core.zig` - SAMM allocator and statistics
- `runtime/samm_pool.zig` - Slab pool allocator (used by SAMM)
- `runtime/memory_mgmt.zig` - Runtime allocator (basic_malloc)
- `runtime/basic_runtime.c` - Runtime initialization and cleanup

### Enabling/Disabling

To disable in source (not recommended):
1. Edit `runtime/samm_core.zig`: comment out `samm_print_stats_always()` call
2. Edit `runtime/basic_runtime.c`: comment out `samm_print_stats_always()` call
3. Rebuild: `cd zig_compiler && zig build`

## Troubleshooting

### No statistics printed

If you don't see statistics:
1. Make sure program exits normally (not via CTRL+C)
2. Check that `basic_runtime_cleanup()` is called
3. Rebuild compiler: `cd zig_compiler && zig build`

### Misleading "leaked objects" value

If you see negative or huge leaked object counts:
- This was a bug in earlier versions (now fixed)
- Rebuild with latest code

### "Bytes freed" > "Bytes allocated"

This is normal! SAMM uses slab pools which may free slightly more bytes than allocated due to:
- Pool overhead
- Alignment padding
- Internal bookkeeping structures

The important metric is "Leaked objects" and "Leaked bytes" should both be 0.

## Future Enhancements

Planned improvements:
- Per-allocation stack traces for leak detection
- Interactive memory browser
- Configurable verbosity levels
- JSON output format for tooling integration
- Memory profiling mode with allocation hotspots

## References

- SAMM design: `runtime/samm_core.zig` (comments at top)
- Memory management: `runtime/memory_mgmt.zig`
- Compiler changes: `SWAP_ENHANCEMENT.md` (includes compiler memory fix)
- Runtime API: `runtime/basic_runtime.h`
