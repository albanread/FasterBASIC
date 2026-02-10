# Terminal I/O for FasterBASIC

This document describes the terminal I/O capabilities available in FasterBASIC, providing classic BASIC-style screen control commands with modern ANSI terminal support.

---

## Quick Start

```basic
' Clear screen and draw something
CLS
LOCATE 10, 20
COLOR 14
PRINT "Hello, World!"
COLOR 15, 4
PRINT "White text on red background"
```

---

## Available Commands

### Screen Control

#### `CLS`
Clear the entire screen and move cursor to home position (1,1).

```basic
CLS
```

#### `GCLS`
Graphics clear screen (alias for CLS in text mode).

```basic
GCLS
```

---

### Cursor Positioning

#### `LOCATE row, col`
Move the cursor to the specified row and column (1-based coordinates).

**Syntax:**
```basic
LOCATE row, col
```

**Example:**
```basic
LOCATE 10, 20        ' Move to row 10, column 20
PRINT "Text here"
LOCATE 5, 5          ' Move to row 5, column 5
PRINT "More text"
```

**Notes:**
- Row and column are 1-based (top-left is 1,1)
- Most terminals support at least 24 rows × 80 columns
- Modern terminals often support larger sizes
- Out-of-bounds coordinates may wrap or be clamped depending on terminal

---

### Colors

#### `COLOR foreground`
Set the text foreground color.

**Syntax:**
```basic
COLOR fg
```

**Example:**
```basic
COLOR 14             ' Yellow text
PRINT "Yellow!"
COLOR 12             ' Light red text
PRINT "Red!"
```

#### `COLOR foreground, background`
Set both foreground and background colors.

**Syntax:**
```basic
COLOR fg, bg
```

**Example:**
```basic
COLOR 15, 4          ' White on red
PRINT "Alert!"
COLOR 0, 14          ' Black on yellow
PRINT "Warning"
```

### Standard 16-Color Palette

| Code | Color        | Bright | Code | Color             |
|------|-------------|--------|------|-------------------|
| 0    | Black       | 8      | Dark Gray         |
| 1    | Blue        | 9      | Light Blue        |
| 2    | Green       | 10     | Light Green       |
| 3    | Cyan        | 11     | Light Cyan        |
| 4    | Red         | 12     | Light Red         |
| 5    | Magenta     | 13     | Light Magenta     |
| 6    | Brown       | 14     | Yellow            |
| 7    | Light Gray  | 15     | White             |

**Example - Show all colors:**
```basic
DIM i AS INTEGER
FOR i = 0 TO 15
    COLOR i
    PRINT "Color "; i; " sample text"
NEXT i
```

---

## Complete Examples

### Example 1: Simple Menu

```basic
CLS
LOCATE 5, 30
COLOR 15, 1
PRINT " MAIN MENU "
COLOR 7, 0

LOCATE 8, 25
PRINT "1. Start Game"
LOCATE 9, 25
PRINT "2. Options"
LOCATE 10, 25
PRINT "3. Exit"

LOCATE 12, 25
INPUT "Choose option: "; choice
```

### Example 2: Color Palette Display

```basic
CLS
LOCATE 2, 25
COLOR 14
PRINT "Color Palette Demo"

DIM c AS INTEGER
FOR c = 0 TO 15
    LOCATE 4 + c, 10
    COLOR c
    PRINT "■■■ Color "; c; " - The quick brown fox"
NEXT c

' Background colors
LOCATE 22, 10
COLOR 0, 7
PRINT " Gray BG "
COLOR 15, 1
PRINT " Blue BG "
COLOR 15, 2
PRINT " Green BG "
COLOR 0, 14
PRINT " Yellow BG "
COLOR 15, 4
PRINT " Red BG "

' Reset
COLOR 7, 0
```

### Example 3: Box Drawing

```basic
CLS
COLOR 11

' Draw a box using box-drawing characters
LOCATE 5, 20
PRINT "┌────────────────────────┐"
LOCATE 6, 20
PRINT "│  Welcome to FasterBASIC │"
LOCATE 7, 20
PRINT "│                        │"
LOCATE 8, 20
PRINT "│  Box drawing works!    │"
LOCATE 9, 20
PRINT "└────────────────────────┘"

COLOR 7
```

### Example 4: Animated Bar

```basic
CLS
LOCATE 10, 10
PRINT "Loading..."

DIM i AS INTEGER
FOR i = 1 TO 50
    LOCATE 12, 10 + i
    COLOR 10
    PRINT "█"
    ' Small delay (if SLEEP or WAIT_MS available)
NEXT i

LOCATE 14, 10
COLOR 7
PRINT "Complete!"
```

### Example 5: Status Display

```basic
CLS
COLOR 15, 4
LOCATE 1, 1
PRINT "╔══════════════════════════════════════════════════════════════════════════╗"
LOCATE 2, 1
PRINT "║                          SYSTEM STATUS                                   ║"
LOCATE 3, 1
PRINT "╚══════════════════════════════════════════════════════════════════════════╝"

COLOR 7, 0
LOCATE 5, 5
PRINT "CPU: "
COLOR 10
PRINT "OK"

COLOR 7
LOCATE 6, 5
PRINT "Memory: "
COLOR 10
PRINT "512 MB"

COLOR 7
LOCATE 7, 5
PRINT "Disk: "
COLOR 12
PRINT "85% Full"

COLOR 7
LOCATE 9, 5
PRINT "Status: "
COLOR 10
PRINT "RUNNING"

COLOR 7, 0
```

---

## Technical Details

### Platform Support

**Windows 10+:**
- Automatically enables VT100 escape sequence support
- Uses `SetConsoleMode` with `ENABLE_VIRTUAL_TERMINAL_PROCESSING`
- Works in cmd.exe, PowerShell, and Windows Terminal

**macOS/Linux:**
- Direct ANSI escape sequence output
- Works with any VT100-compatible terminal
- Tested on: Terminal.app, iTerm2, xterm, gnome-terminal, konsole

### ANSI Implementation

The terminal I/O system uses standard ANSI/VT100 escape sequences:

- **Clear screen:** `ESC[2J ESC[H`
- **Cursor positioning:** `ESC[row;colH`
- **Foreground colors:** `ESC[30-37m` (normal), `ESC[90-97m` (bright)
- **Background colors:** `ESC[40-47m` (normal), `ESC[100-107m` (bright)
- **Reset:** `ESC[0m`

### Type Conversions

Color and position parameters can be any numeric expression:

```basic
' Variables
DIM row AS INTEGER, col AS INTEGER
row = 10
col = 20
LOCATE row, col

' Expressions
LOCATE 5 + 3, 10 * 2
COLOR 14, 1 + 1

' Function results
LOCATE GetRow(), GetColumn()
```

The compiler automatically converts floating-point expressions to integers.

---

## Coming Soon (Not Yet Implemented)

The following features are planned for future releases:

### Text Styles
- `BOLD` - Bold text
- `ITALIC` - Italic text
- `UNDERLINE` - Underlined text
- `BLINK` - Blinking text
- `INVERSE` - Reverse video (swap fg/bg)
- `NORMAL` - Reset to normal

### RGB True Colors
- `RGBFG r, g, b` - Set RGB foreground (0-255 each)
- `RGBBG r, g, b` - Set RGB background

### Cursor Control
- `CURSOR ON/OFF` - Show/hide cursor
- `CURSOR SAVE/RESTORE` - Save/restore cursor position

### VDU Commands
- `VDUUP n`, `VDUDOWN n` - Move cursor relatively
- `VDULEFT n`, `VDURIGHT n` - Move cursor relatively
- `VDUEOL` - Clear to end of line
- `VDUEOS` - Clear to end of screen

### Keyboard Input
- `KBGET()` - Get single character (blocking)
- `KBHIT()` - Check if key available
- `INKEY$` - Get key without waiting
- `KBCODE()` - Get special key codes (arrows, F-keys)

### Query Functions
- `POS(0)` - Get cursor column
- `ROW(0)` - Get cursor row
- `VDUWIDTH()` - Get terminal width
- `VDUHEIGHT()` - Get terminal height

---

## Tips and Best Practices

### 1. Always Reset Colors
Reset colors at program exit to avoid messing up the user's terminal:

```basic
' At program end
COLOR 7, 0
CLS
```

### 2. Clear Before Drawing
Clear the screen before drawing complex layouts:

```basic
CLS
' Now draw your UI
```

### 3. Use Constants for Colors
Define color constants for readability:

```basic
CONST BLACK = 0
CONST RED = 4
CONST YELLOW = 14
CONST WHITE = 15

COLOR YELLOW
PRINT "Warning!"
COLOR WHITE, RED
PRINT "Error!"
```

### 4. Box Drawing Characters
Unicode box drawing works in most modern terminals:

```
Single line:  ─ │ ┌ ┐ └ ┘ ├ ┤ ┬ ┴ ┼
Double line:  ═ ║ ╔ ╗ ╚ ╝ ╠ ╣ ╦ ╩ ╬
Blocks:       █ ▄ ▀ ▌ ▐
Arrows:       ← → ↑ ↓
Symbols:      ● ○ ◆ ◇ ★ ☆
```

### 5. Test Your Layout
Different terminals have different sizes. Test with common dimensions:
- 80×24 (classic)
- 80×25 (DOS/Windows)
- 132×43 (wide)

### 6. Consider Terminal Background
Be careful with color 0 (black) on terminals with black backgrounds - it will be invisible! Always provide good contrast.

---

## Limitations

1. **No position tracking yet:** BASIC programs cannot query cursor position (POS/ROW functions not yet implemented)
2. **No size detection:** Programs cannot query terminal dimensions yet
3. **Fixed color palette:** Only 16-color mode supported; RGB/true-color commands parsed but not yet usable
4. **No input control:** Keyboard raw mode and special key detection not yet available
5. **No validation:** Invalid coordinates or color codes are passed to the terminal without checking

---

## Troubleshooting

### Colors don't appear
- **Windows:** Ensure you're using Windows 10+ or Windows Terminal
- **Old cmd.exe:** May not support ANSI colors; use Windows Terminal instead
- Check that your terminal emulator supports ANSI/VT100 escape sequences

### Cursor positioning is off
- Make sure your terminal window is large enough for the coordinates you're using
- Remember that LOCATE uses 1-based coordinates (1,1 is top-left)
- Some terminals may handle out-of-bounds coordinates differently

### Box characters appear as ???
- Your terminal may not support Unicode
- Try using ASCII alternatives: `+` `|` `-` for boxes
- Ensure your terminal is set to UTF-8 encoding

---

## Related Documentation

- [Terminal Keyword Mapping Design](terminals.md) - Complete keyword design
- [Implementation Status](terminals_implementation_status.md) - Current implementation status
- Runtime source: `zig_compiler/runtime/terminal_io.zig`
- Parser source: `zig_compiler/src/parser.zig` (parseLocateStatement, parseColorStatement)
- Codegen source: `zig_compiler/src/codegen.zig` (emitCLS, emitLocate, emitColor)

---

## License

Part of the FasterBASIC compiler project.

---

**Last Updated:** February 10, 2024  
**Version:** Phase 1 - Basic Terminal Control