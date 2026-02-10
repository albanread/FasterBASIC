# Terminal I/O Raw Mode Issues on macOS - Technical Review

## Date
February 10, 2025

## Executive Summary

The terminal I/O library (`zig_compiler/runtime/terminal_io.zig`) has several critical issues with raw mode handling on macOS that cause the screen control to be ineffective. The primary issue is **blocking escape sequence parsing** that causes the program to hang when ESC is pressed alone, and improper timeout handling for distinguishing between ESC key presses and escape sequences (arrow keys, function keys).

## Critical Issues Identified

### 1. ❌ Blocking Escape Sequence Parser (CRITICAL)

**Location**: `terminal_io.zig` lines ~800-850, function `parseEscapeSequence()`

**Problem**: The escape sequence parser reads characters one-by-one with **blocking reads**. With `VMIN=1` and `VTIME=0` set in raw mode, each `read()` call blocks indefinitely until a character arrives.

**Code**:
```zig
while (len < buf.len) {
    var ch: [1]u8 = undefined;
    
    // This read() BLOCKS indefinitely with VMIN=1, VTIME=0
    const n = std.posix.read(stdin, &ch) catch break;
    if (n == 0) break;
    
    buf[len] = ch[0];
    len += 1;
    // ...
}
```

**Impact**:
- Pressing ESC alone freezes the program (waits forever for next character)
- Arrow keys work but have latency due to character-by-character blocking
- Users must press 3+ characters to break out of the loop
- Makes the editor/terminal programs unusable

**Example Scenario**:
1. User presses ESC key (single byte: 0x1B)
2. Parser receives ESC and enters `parseEscapeSequence()`
3. Parser tries to read next character with blocking read
4. **Program hangs** because no more characters are coming (ESC was pressed alone, not as part of arrow key sequence)
5. User must press additional keys to unblock

### 2. ❌ No Real Timeout Mechanism

**Location**: `terminal_io.zig` lines ~847-850

**Problem**: The code has a comment about timeout but doesn't implement one:

```zig
// Timeout to avoid blocking forever
if (len >= 3) break;
```

This only limits the sequence length, but **does not prevent blocking** on each individual `read()` call. With `VMIN=1`, the read will block until a character arrives, regardless of this check.

**What's Needed**:
- Set `VMIN=0` and `VTIME=1` (or similar) for subsequent reads after ESC
- This creates a 0.1 second timeout per read
- Allows detection of when the escape sequence is complete

### 3. ❌ Incorrect tcsetattr Option

**Location**: `terminal_io.zig` lines 685-686, 688

**Problem**: Uses `.FLUSH` (TCSAFLUSH) option:

```zig
try std.posix.tcsetattr(std.posix.STDIN_FILENO, .FLUSH, raw);
```

**Issue**: On macOS, `TCSAFLUSH` can cause input loss, especially when switching terminal modes frequently (entering/exiting raw mode, handling escape sequences). This is particularly problematic in interactive editors.

**Recommendation**: Use `.NOW` (TCSANOW) for immediate effect without flushing input buffer:

```zig
try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw);
```

### 4. ❌ Missing Dynamic VMIN/VTIME Adjustment

**Problem**: The code sets `VMIN=1, VTIME=0` globally in raw mode and never changes it. This is correct for blocking reads of the first character but **wrong for escape sequence parsing**.

**Current Approach** (problematic):
```zig
raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;   // Block until 1 char
raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;  // No timeout
```

**Correct Approach** for escape sequences:
1. **First character**: `VMIN=1, VTIME=0` (block for initial ESC)
2. **Subsequent characters**: `VMIN=0, VTIME=1` (non-blocking with 0.1s timeout)
3. When timeout occurs (read returns 0), sequence is complete

This allows:
- ESC alone: Returns after 0.1 second timeout
- ESC + arrow key sequence: Reads complete sequence quickly
- Proper detection of sequence end

### 5. ⚠️ No Restoration of Blocking Mode

**Problem**: Even if we temporarily switch to non-blocking mode for escape parsing, the code doesn't restore the original blocking mode settings afterward.

**Impact**: Terminal state can become inconsistent between different operations.

## Technical Background

### How Escape Sequences Work

When you press an arrow key in a terminal, it sends multiple bytes:
- **Up Arrow**: ESC [ A (3 bytes: 0x1B 0x5B 0x41)
- **Down Arrow**: ESC [ B (3 bytes: 0x1B 0x5B 0x42)
- **F1 Key**: ESC [ 1 1 ~ (5 bytes)

When you press ESC alone:
- **ESC Key**: 0x1B (1 byte only)

The challenge: After receiving 0x1B, how do we know if more bytes are coming?

### Standard Unix Terminal Solution

The standard approach on Unix systems:

```c
// For first character (blocking)
struct termios tio;
tio.c_cc[VMIN] = 1;   // Wait for at least 1 character
tio.c_cc[VTIME] = 0;  // No timeout
tcsetattr(STDIN_FILENO, TCSANOW, &tio);

// After receiving ESC, switch to non-blocking with timeout
tio.c_cc[VMIN] = 0;   // Don't require any characters
tio.c_cc[VTIME] = 1;  // 0.1 second timeout
tcsetattr(STDIN_FILENO, TCSANOW, &tio);

// Now read() returns 0 after 0.1 seconds if no more data
```

This allows the program to distinguish:
- ESC alone: Second read() times out (returns 0)
- Arrow key: Second read() gets '[', third gets 'A', etc.

### Alternative: poll() or select()

Another approach is using `poll()` with a timeout between reads:

```c
// After reading ESC
struct pollfd fds[1];
fds[0].fd = STDIN_FILENO;
fds[0].events = POLLIN;

// Wait up to 100ms for more data
int result = poll(fds, 1, 100);
if (result == 0) {
    // Timeout - ESC was pressed alone
} else {
    // More data available - read next character
}
```

This approach keeps `VMIN=1, VTIME=0` but uses external timeout mechanism.

## Recommended Fixes

### Fix #1: Implement Proper Escape Sequence Timeout (CRITICAL)

**Location**: `parseEscapeSequence()` function

**Change**:
```zig
fn parseEscapeSequence() i32 {
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    
    const stdin = if (builtin.os.tag == .windows)
        std.os.windows.GetStdHandle(std.os.windows.STD_INPUT_HANDLE) catch return 0x1B
    else
        std.posix.STDIN_FILENO;
    
    // On Unix, temporarily set non-blocking mode with timeout
    // This prevents hanging when ESC is pressed alone
    if (builtin.os.tag != .windows) {
        var temp_termios = std.posix.tcgetattr(std.posix.STDIN_FILENO) catch return 0x1B;
        temp_termios.cc[@intFromEnum(std.posix.V.MIN)] = 0;  // Don't block
        temp_termios.cc[@intFromEnum(std.posix.V.TIME)] = 1; // 0.1 second timeout
        std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, temp_termios) catch {};
    }
    
    // Read up to 16 bytes for the escape sequence with timeout
    while (len < buf.len) {
        var ch: [1]u8 = undefined;
        
        if (builtin.os.tag == .windows) {
            var read: std.os.windows.DWORD = 0;
            if (std.os.windows.kernel32.ReadFile(stdin, &ch, 1, &read, null) == 0) break;
            if (read == 0) break;
        } else {
            const n = std.posix.read(stdin, &ch) catch break;
            if (n == 0) break; // Timeout or no more data - sequence is complete
        }
        
        buf[len] = ch[0];
        len += 1;
        
        // Check if we have a complete sequence
        if (len >= 2) {
            if (buf[0] == '[') {
                // Mouse event: ESC [ < Cb ; Cx ; Cy M/m
                if (len >= 2 and buf[1] == '<') {
                    const result = parseMouseEvent(buf[0..len]);
                    // Restore blocking mode
                    if (builtin.os.tag != .windows) {
                        setUnixRawMode(true) catch {};
                    }
                    return result;
                }
                
                // Arrow keys and other sequences
                if (len >= 2) {
                    const last = buf[len - 1];
                    
                    // Single char sequences (complete when letter or ~ is found)
                    if (last >= 'A' and last <= 'Z' or last >= 'a' and last <= 'z' or last == '~') {
                        const result = parseCSISequence(buf[0..len]);
                        // Restore blocking mode
                        if (builtin.os.tag != .windows) {
                            setUnixRawMode(true) catch {};
                        }
                        return result;
                    }
                }
            }
            // SS3 sequences: ESC O ...
            else if (buf[0] == 'O' and len >= 2) {
                const result = parseSS3Sequence(buf[0..len]);
                // Restore blocking mode
                if (builtin.os.tag != .windows) {
                    setUnixRawMode(true) catch {};
                }
                return result;
            }
        }
        
        // Safety limit to avoid reading too much
        if (len >= 8) break;
    }
    
    // Restore blocking mode before returning
    if (builtin.os.tag != .windows) {
        setUnixRawMode(true) catch {};
    }
    
    // If we only got ESC or couldn't parse, return ESC
    // This happens when ESC is pressed alone (len == 0 after timeout)
    return 0x1B;
}
```

### Fix #2: Change tcsetattr to use .NOW

**Location**: `setUnixRawMode()` and `setUnixEcho()` functions

**Change**:
```zig
fn setUnixRawMode(enable: bool) !void {
    if (builtin.os.tag == .windows) return;
    
    if (enable) {
        var raw = original_termios;
        
        // Disable canonical mode, echo, signals
        raw.lflag.ICANON = false;
        raw.lflag.ECHO = false;
        raw.lflag.ISIG = false;
        raw.lflag.IEXTEN = false;
        
        // Disable input processing
        raw.iflag.IXON = false;
        raw.iflag.ICRNL = false;
        raw.iflag.BRKINT = false;
        raw.iflag.INPCK = false;
        raw.iflag.ISTRIP = false;
        
        // Keep output processing enabled so ANSI escape codes work
        raw.oflag.OPOST = true;
        raw.oflag.ONLCR = true;
        
        // Set character size to 8 bits
        raw.cflag.CSIZE = .CS8;
        
        // Minimum characters for non-canonical read
        raw.cc[@intFromEnum(std.posix.V.MIN)] = 1;
        raw.cc[@intFromEnum(std.posix.V.TIME)] = 0;
        
        // Use TCSANOW for immediate effect (better for macOS than FLUSH)
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, raw);
    } else {
        try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, original_termios);
    }
}

fn setUnixEcho(enable: bool) !void {
    if (builtin.os.tag == .windows) return;
    
    var current = try std.posix.tcgetattr(std.posix.STDIN_FILENO);
    current.lflag.ECHO = enable;
    try std.posix.tcsetattr(std.posix.STDIN_FILENO, .NOW, current);
}
```

### Fix #3: Alternative poll()-based Approach

If the VMIN/VTIME approach doesn't work well on macOS, use `poll()`:

```zig
fn parseEscapeSequence() i32 {
    var buf: [16]u8 = undefined;
    var len: usize = 0;
    
    const stdin = std.posix.STDIN_FILENO;
    
    // Read up to 16 bytes for the escape sequence
    while (len < buf.len) {
        // Use poll to check if data is available with timeout
        var fds: [1]std.posix.pollfd = [_]std.posix.pollfd{
            .{
                .fd = stdin,
                .events = std.posix.POLL.IN,
                .revents = 0,
            },
        };
        
        // 100ms timeout (in milliseconds)
        const result = std.posix.poll(&fds, 100) catch break;
        
        // Timeout or no data available
        if (result == 0 or (fds[0].revents & std.posix.POLL.IN) == 0) {
            break; // Sequence is complete
        }
        
        // Data is available, read it
        var ch: [1]u8 = undefined;
        const n = std.posix.read(stdin, &ch) catch break;
        if (n == 0) break;
        
        buf[len] = ch[0];
        len += 1;
        
        // [rest of parsing logic...]
    }
    
    return 0x1B;
}
```

## Testing Strategy

### Test 1: ESC Key Alone
```bash
# Run editor
./based_editor test.bas

# Press ESC key
# Expected: Returns ESC character (0x1B) after ~0.1 second
# Current: Program hangs indefinitely
```

### Test 2: Arrow Keys
```bash
# Run editor
./based_editor test.bas

# Press Up Arrow
# Expected: Cursor moves up immediately
# Current: May work but with latency
```

### Test 3: Rapid Key Input
```bash
# Type quickly: ESC, Up, Down, Left, Right, ESC
# Expected: All keys processed correctly
# Current: May hang on ESC keys
```

### Test 4: Terminal State Restoration
```bash
# Run editor and quit with Ctrl+Q
# Expected: Terminal returns to normal mode
# Current: May leave terminal in inconsistent state
```

## Implementation Status

✅ **COMPLETED**: Fixes have been applied to `terminal_io.zig`:
- Changed `.FLUSH` to `.NOW` in all `tcsetattr()` calls
- Added timeout mechanism using `VMIN=0, VTIME=1` in escape sequence parser
- Added proper restoration of blocking mode after parsing
- Increased safety limit from 3 to 8 characters for longer sequences

❌ **PENDING**: Needs rebuild and testing
- Requires `zig build` to compile changes
- Needs interactive testing on macOS with actual editor
- Should verify arrow keys, ESC key, function keys all work properly

## Additional Observations

### Output Processing (Already Fixed)
The previous terminal I/O issue with mixed output streams (C stdio vs raw file descriptors) has been correctly fixed by using `fprintf()` for all output. This fix is working well.

### Input Processing (Current Focus)
The input side (keyboard handling) has the blocking issues described above. The fixes focus on:
1. Non-blocking reads with timeout for escape sequences
2. Proper terminal attribute handling for macOS
3. Consistent state restoration

## References

- **termios(3)** man page - Terminal I/O settings
- **tcsetattr(3)** man page - TCSANOW vs TCSAFLUSH behavior
- **VMIN and VTIME** - Character-oriented input settings
- **ANSI Escape Sequences** - CSI and SS3 sequence formats

## Conclusion

The terminal I/O library has critical issues with escape sequence handling that make it unusable on macOS. The blocking reads without proper timeout cause the program to hang when ESC is pressed alone. The fixes provided above implement proper timeout mechanisms using either VMIN/VTIME adjustment or poll()-based approach.

**Priority**: HIGH - This breaks basic editor functionality
**Complexity**: MEDIUM - Well-understood Unix terminal programming patterns
**Risk**: LOW - Changes are isolated to input handling, well-tested patterns

Once rebuilt with `zig build`, these fixes should make the terminal control effective on macOS.