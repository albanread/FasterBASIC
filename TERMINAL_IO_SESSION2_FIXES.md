# Terminal I/O Fixes — Session 2

## Date
February 10, 2025 (continued)

## Overview
Continued terminal I/O improvements building on the Session 1 fixes. This session focused on **performance**, **robustness**, **missing features**, and **bug fixes** across the runtime, compiler, and editor.

---

## Changes Summary

### 1. Fixed `writeStdout` Buffer Truncation Bug
**File**: `zig_compiler/runtime/terminal_io.zig`

**Problem**: `writeStdout()` used a fixed 512-byte stack buffer with `fprintf("%s", ...)`. Strings longer than 511 bytes were **silently truncated**. This affected long lines, full-width screen painting, and any output exceeding 511 characters.

**Fix**: Replaced `fprintf` with `fwrite(ptr, 1, len, stdout)` which:
- Handles arbitrary-length output with no buffer limit
- Doesn't require null-termination
- Doesn't interpret format specifiers (no `%s` injection risk)
- Is more efficient (single call vs format string parsing)

**Before**:
```zig
var buf: [512]u8 = undefined;
if (bytes.len >= buf.len) {
    @memcpy(buf[0 .. buf.len - 1], bytes[0 .. buf.len - 1]);
    buf[buf.len - 1] = 0;
    _ = fprintf(__stdoutp, "%s", @ptrCast(&buf));
} else {
    @memcpy(buf[0..bytes.len], bytes);
    buf[bytes.len] = 0;
    _ = fprintf(__stdoutp, "%s", @ptrCast(&buf));
}
_ = fflush(__stdoutp);
```

**After**:
```zig
if (bytes.len == 0) return;
_ = fwrite(bytes.ptr, 1, bytes.len, __stdoutp);
if (!paint_mode) {
    _ = fflush(__stdoutp);
}
```

---

### 2. Output Batching (BEGINPAINT / ENDPAINT / FLUSH)
**Files**: `terminal_io.zig`, `token.zig`, `ast.zig`, `parser.zig`, `codegen.zig`

**Problem**: Every single `WRSTR`, `WRCH`, `LOCATE`, `COLOR`, and `PRINT` call triggered an immediate `fflush(stdout)` syscall. For the BASED editor, a full screen redraw involved **hundreds** of individual flush syscalls, causing visible flicker and poor performance.

**Solution**: Added a "paint mode" that suppresses per-call `fflush`, allowing all output to accumulate in C stdio's buffer and flush once at the end of a redraw.

#### New BASIC Keywords:
| Keyword | Description |
|---------|-------------|
| `BEGINPAINT` | Enter paint mode — suppresses per-call fflush |
| `ENDPAINT` | Exit paint mode and flush all accumulated output |
| `FLUSH` | Explicitly flush stdout (works in and outside paint mode) |

#### Runtime Functions Added:
- `basic_begin_draw()` — sets `paint_mode = true`
- `basic_end_draw()` — clears `paint_mode` and calls `fflush`
- `basic_flush()` — unconditional `fflush(stdout)`
- `basic_is_paint_mode()` — returns 1 if in paint mode (used by io_ops)

#### Paint Mode Integration:
Both `terminal_io.zig` and `io_ops.zig` (PRINT functions) respect paint mode. The `io_ops.zig` and `io_ops_format.zig` modules now call `flushIfNeeded()` instead of unconditional `fflush`, checking paint mode via the exported `basic_is_paint_mode()` function. This means **PRINT statements inside BEGINPAINT blocks are also batched**.

#### Usage in the Editor:
```basic
SUB refresh_screen()
    BEGINPAINT
    CALL draw_header()
    CALL draw_editor()
    CALL draw_status()
    CALL position_cursor()
    ENDPAINT
END SUB
```

---

### 3. Fixed KBFLUSH Parser Bug
**File**: `zig_compiler/src/parser.zig`

**Problem**: `KBFLUSH` and `KBCLEAR` were routed through `parseSimpleStatement(.kw_kbflush)`, but the switch inside `parseSimpleStatement` did not have a `.kw_kbflush` case — it hit `else => unreachable`. Any BASIC program using `KBFLUSH` would crash the compiler at runtime.

**Fix**: Created a dedicated `parseKbFlushStatement()` function that correctly produces a `.kbflush` AST node.

**Before**:
```zig
.kw_kbflush, .kw_kbclear => self.parseSimpleStatement(.kw_kbflush),
```

**After**:
```zig
.kw_kbflush, .kw_kbclear => self.parseKbFlushStatement(),
```

---

### 4. Terminal Size Detection (SCREENWIDTH / SCREENHEIGHT)
**Files**: `terminal_io.zig`, `token.zig`, `parser.zig`, `codegen.zig`

**Problem**: The BASED editor hardcoded `screen_width = 80` and `screen_height = 24`, which is wrong for most modern terminals.

**Solution**: Added runtime functions that query the terminal size via `ioctl(TIOCGWINSZ)` and exposed them as BASIC built-in functions.

#### Runtime Functions:
- `terminal_get_width()` — returns column count (fallback: 80)
- `terminal_get_height()` — returns row count (fallback: 24)

#### Platform Support:
- **macOS**: `TIOCGWINSZ = 0x40087468`
- **Linux**: `TIOCGWINSZ = 0x5413`
- **Windows**: Returns fallback values (80×24)

#### BASIC Usage:
```basic
screen_width = SCREENWIDTH
screen_height = SCREENHEIGHT
```

The BASED editor now dynamically detects terminal size at startup.

---

### 5. Alternate Screen Buffer for Editor
**File**: `based/based.bas`

**Problem**: When the editor exited, it left screen painting artifacts in the terminal. The user's previous terminal content was lost.

**Fix**: The editor now uses the alternate screen buffer (`SCREEN_ALTERNATE` / `SCREEN_MAIN`), like vim and nano do. When the editor exits, the user's original terminal content is fully restored.

**Init**:
```basic
KBRAW 1
SCREEN_ALTERNATE
CLS
CURSOR_HIDE
```

**Cleanup**:
```basic
KBRAW 0
CURSOR_SHOW
COLOR 7, 0
SCREEN_MAIN
PRINT "Thanks for using BASED!"
```

---

### 6. atexit Handler for Terminal Restoration
**File**: `zig_compiler/runtime/terminal_io.zig`

**Problem**: If a BASIC program crashed, called `exit()`, or was killed, the terminal could be left in raw mode with the cursor hidden. The user would have to manually run `reset` or `stty sane`.

**Fix**: `terminal_init()` now registers an `atexit` callback that calls `terminal_cleanup()`. This ensures the terminal is **always** restored to a sane state on program exit, regardless of how the program terminates.

```zig
pub export fn terminal_init() void {
    // ... existing init code ...
    _ = atexit(&atexit_cleanup);
}

fn atexit_cleanup() callconv(.c) void {
    terminal_cleanup();
}
```

---

## Files Changed

### Runtime (`zig_compiler/runtime/`)
| File | Changes |
|------|---------|
| `terminal_io.zig` | Fixed writeStdout buffer limit; added paint mode; added basic_begin_draw/basic_end_draw/basic_flush/basic_is_paint_mode; added terminal_get_width/terminal_get_height via ioctl; added atexit handler |
| `io_ops.zig` | All PRINT functions now call `flushIfNeeded()` instead of unconditional fflush; respects paint mode |
| `io_ops_format.zig` | PRINT USING now calls `flushIfNeeded()`; respects paint mode |

### Compiler (`zig_compiler/src/`)
| File | Changes |
|------|---------|
| `token.zig` | Added `kw_flush`, `kw_beginpaint`, `kw_endpaint`, `kw_screenwidth`, `kw_screenheight` |
| `ast.zig` | Added `flush`, `begin_paint`, `end_paint` void statement types |
| `parser.zig` | Added dispatch for new keywords; added `parseKbFlushStatement()`; added SCREENWIDTH/SCREENHEIGHT expression handling; fixed KBFLUSH unreachable bug |
| `codegen.zig` | Declared `basic_flush`, `basic_begin_draw`, `basic_end_draw`, `terminal_get_width`, `terminal_get_height`; added emitter functions; added SCREENWIDTH/SCREENHEIGHT to built-in function table |

### Editor (`based/`)
| File | Changes |
|------|---------|
| `based.bas` | Uses SCREENWIDTH/SCREENHEIGHT for dynamic sizing; uses SCREEN_ALTERNATE/SCREEN_MAIN; wraps redraws in BEGINPAINT/ENDPAINT; adds FLUSH after cursor positioning |

### Tests Added (`based/`)
| File | Purpose |
|------|---------|
| `test_paint.bas` | Tests FLUSH, BEGINPAINT, ENDPAINT batching |
| `test_wrstr.bas` | Tests WRSTR with various string operations |
| `test_screensize.bas` | Tests SCREENWIDTH/SCREENHEIGHT detection |

---

## Build & Test Commands

```bash
# Build compiler
cd zig_compiler && zig build

# Build editor and tests
cd based
../zig_compiler/zig-out/bin/fbc based.bas -o based_editor
../zig_compiler/zig-out/bin/fbc test_rawmode_auto.bas -o test_rawmode_auto
../zig_compiler/zig-out/bin/fbc test_wrch.bas -o test_wrch
../zig_compiler/zig-out/bin/fbc test_wrstr.bas -o test_wrstr
../zig_compiler/zig-out/bin/fbc test_paint.bas -o test_paint
../zig_compiler/zig-out/bin/fbc test_screensize.bas -o test_screensize

# Run automated tests
./test_rawmode_auto
./test_wrch
./test_wrstr
./test_paint
./test_screensize

# Run editor (interactive)
./based_editor test_file.bas
```

---

## Test Results (Automated)

| Test | Status | Notes |
|------|--------|-------|
| `test_rawmode_auto` | ✅ PASS | All 4 test groups pass |
| `test_wrch` | ✅ PASS | Character output correct |
| `test_wrstr` | ✅ PASS | All 10 string output tests pass |
| `test_paint` | ✅ PASS | All 6 batching tests pass |
| `test_screensize` | ✅ PASS | Detects real terminal dimensions |
| `based_editor` | ✅ COMPILES | Requires interactive testing |

---

## Remaining Action Items

1. **Interactive testing**: Run the editor in a real terminal and verify:
   - Arrow keys, typing, backspace, enter work
   - Screen redraws are flicker-free (BEGINPAINT/ENDPAINT)
   - ESC key doesn't hang (Session 1 fix)
   - Terminal restores cleanly on exit (SCREEN_MAIN + atexit)

2. **Restore hashmap.qbe**: The `@embedFile("hashmap.qbe")` is still commented out in codegen.zig because the file doesn't exist. Create the QBE IL module for hashmap runtime operations.

3. **Window resize handling**: Consider adding SIGWINCH signal handling to re-query terminal size and trigger a redraw when the terminal is resized.

4. **Cross-platform validation**: The `__stdoutp` extern is macOS-specific. Linux uses `stdout`. Windows needs separate console API handling.

5. **Performance profiling**: With BEGINPAINT/ENDPAINT, measure actual redraw time improvement. Consider adding write buffering within `writeStdout` itself for even fewer fwrite calls.