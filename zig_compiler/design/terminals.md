# Terminal I/O Keyword Mapping for FasterBASIC

This document defines the BASIC keyword mapping for the terminal I/O library, providing friendly, intuitive commands that follow classic BASIC conventions while supporting modern terminal capabilities.

## Design Principles

1. **Classic BASIC Compatibility**: Use traditional keywords (LOCATE, CLS, COLOR) where applicable
2. **VDU Prefix for Output**: Low-level display operations use `VDU` prefix (Video Display Unit)
3. **KB Prefix for Input**: Keyboard/input operations use `KB` prefix
4. **Intuitive Names**: Commands should be self-documenting and easy to remember
5. **Consistency**: Related operations follow similar naming patterns

---

## Output Commands (Display/VDU)

### Screen Control

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `CLS` | `basic_cls()` | Clear screen and home cursor |
| `GCLS` | `basic_gcls()` | Graphics clear screen (alias for CLS in text mode) |
| `VDUCLS` | `basic_cls()` | Alternative VDU-style clear screen |
| `VDUEOL` | `basic_clear_eol()` | Clear from cursor to end of line |
| `VDUEOS` | `basic_clear_eos()` | Clear from cursor to end of screen |

### Cursor Positioning

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `LOCATE row, col` | `basic_locate(row, col)` | Move cursor to row, column (1-based) |
| `TAB(col)` | `basic_locate(current_row, col)` | Move to column (stays on current row) |
| `VDUPOS row, col` | `basic_locate(row, col)` | Alternative positioning command |

### Cursor Control

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `CURSOR ON` | `showCursor()` | Show cursor |
| `CURSOR OFF` | `hideCursor()` | Hide cursor |
| `CURSOR HIDE` | `hideCursor()` | Hide cursor (alternative syntax) |
| `CURSOR SHOW` | `showCursor()` | Show cursor (alternative syntax) |
| `CURSOR SAVE` | `saveCursor()` | Save current cursor position |
| `CURSOR RESTORE` | `restoreCursor()` | Restore saved cursor position |
| `VDUCURSOR state` | `hideCursor()` or `showCursor()` | VDU-style cursor control (state: 0=off, 1=on) |

### Cursor Movement (Relative)

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `VDUUP n` | `cursorUp(n)` | Move cursor up n rows |
| `VDUDOWN n` | `cursorDown(n)` | Move cursor down n rows |
| `VDULEFT n` | `cursorLeft(n)` | Move cursor left n columns |
| `VDURIGHT n` | `cursorRight(n)` | Move cursor right n columns |
| `VDUMOVE dx, dy` | `cursorRight(dx); cursorDown(dy)` | Relative move (delta x, delta y) |

### Color Control (16-Color Mode)

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `COLOR fg` | `basic_color(fg)` | Set foreground color (0-15) |
| `COLOR fg, bg` | `basic_color_bg(fg, bg)` | Set foreground and background color |
| `COLOUR fg` | `basic_color(fg)` | British spelling (alias) |
| `COLOUR fg, bg` | `basic_color_bg(fg, bg)` | British spelling (alias) |
| `VDUCOLOR fg` | `basic_color(fg)` | VDU-style color command |
| `VDUCOLOUR fg, bg` | `basic_color_bg(fg, bg)` | VDU-style with background |

### Color Control (RGB/True Color)

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `RGB(r, g, b)` | `basic_color_rgb(r, g, b)` | Set RGB foreground color (0-255 each) |
| `RGB(r, g, b, br, bg, bb)` | `basic_color_rgb(r,g,b); basic_color_rgb_bg(br,bg,bb)` | Set RGB foreground and background |
| `RGBFG r, g, b` | `basic_color_rgb(r, g, b)` | Set RGB foreground explicitly |
| `RGBBG r, g, b` | `basic_color_rgb_bg(r, g, b)` | Set RGB background explicitly |
| `VDURGB r, g, b` | `basic_color_rgb(r, g, b)` | VDU-style RGB command |

### Reset/Default

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `COLOR RESET` | `basic_color_reset()` | Reset all colors and styles to defaults |
| `COLOUR RESET` | `basic_color_reset()` | British spelling |
| `VDURESET` | `basic_color_reset()` | VDU-style reset |
| `NORMAL` | `basic_color_reset()` | Return to normal display mode |

### Text Styles

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `BOLD` | `basic_style_bold()` | Enable bold text |
| `DIM` * | `basic_style_dim()` | Enable dim/faint text |
| `ITALIC` | `basic_style_italic()` | Enable italic text |
| `UNDERLINE` | `basic_style_underline()` | Enable underlined text |
| `BLINK` | `basic_style_blink()` | Enable blinking text |
| `REVERSE` | `basic_style_reverse()` | Enable reverse video (swap fg/bg) |
| `INVERSE` | `basic_style_reverse()` | Alternative name for reverse |
| `STYLE RESET` | `basic_style_reset()` | Disable all text styles |
| `VDUSTYLE code` | (style functions) | VDU-style (code: 1=bold, 2=dim, 3=italic, 4=underline, 5=blink, 7=reverse, 0=reset) |

\* Note: `DIM` for styling must be parsed in context to avoid conflict with `DIM` for array declarations

### Screen Modes

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `SCREEN ALTERNATE` | `basic_screen_alternate()` | Switch to alternate screen buffer |
| `SCREEN MAIN` | `basic_screen_main()` | Switch to main screen buffer |
| `VDUSCREEN mode` | (screen functions) | VDU-style screen control (mode: 0=main, 1=alternate) |

---

## Input Commands (Keyboard/KB)

### Basic Input

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `INPUT prompt$; var` | `basic_input()` | Standard line input with prompt |
| `INPUT var` | `basic_input()` | Line input without prompt |
| `LINE INPUT prompt$; var$` | `basic_line_input()` | Line input (allows commas in input) |
| `KBINPUT var$` | `basic_line_input()` | Keyboard line input |

### Character Input

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `KBGET()` | `basic_kb_get()` | Get single character (wait for keypress) |
| `KBHIT()` | `basic_kb_hit()` | Check if key is available (returns 1/0) |
| `KBPEEK()` | `basic_kb_peek()` | Peek at next character without consuming |
| `INKEY$` | `basic_inkey()` | Get key without waiting (returns "" if none) |
| `INKEY$(timeout)` | `basic_inkey_timeout(ms)` | Get key with timeout in milliseconds |

### Special Key Detection

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `KBCODE()` | `basic_kb_code()` | Get raw key code (including special keys) |
| `KBSPECIAL()` | `basic_kb_special()` | Returns special key code (arrows, F-keys, etc.) |
| `KBMOD()` | `basic_kb_modifiers()` | Returns modifier state (Ctrl/Alt/Shift bitmask) |

### Raw/Cooked Mode

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `KBRAW ON` | `basic_kb_raw_mode(1)` | Enable raw keyboard mode (no echo, no buffer) |
| `KBRAW OFF` | `basic_kb_raw_mode(0)` | Disable raw mode (return to cooked/line mode) |
| `KBECHO ON` | `basic_kb_echo(1)` | Enable keyboard echo |
| `KBECHO OFF` | `basic_kb_echo(0)` | Disable keyboard echo |

### Input Buffer Control

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `KBFLUSH` | `basic_kb_flush()` | Clear/flush keyboard input buffer |
| `KBCLEAR` | `basic_kb_flush()` | Alternative name for flush |
| `KBCOUNT()` | `basic_kb_count()` | Return number of characters in buffer |

---

## Query Functions (Read State)

### Position Queries

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `POS(0)` | `basic_get_cursor_col()` | Get current cursor column (1-based) |
| `ROW(0)` | `basic_get_cursor_row()` | Get current cursor row (1-based) |
| `CSRLIN` | `basic_get_cursor_row()` | Get cursor line (row) - GW-BASIC style |
| `VDUPOSX()` | `basic_get_cursor_col()` | VDU-style column query |
| `VDUPOSY()` | `basic_get_cursor_row()` | VDU-style row query |

### Terminal Size

| BASIC Keyword | Runtime Function | Description |
|--------------|------------------|-------------|
| `VDUWIDTH()` | `basic_term_width()` | Get terminal width in columns |
| `VDUHEIGHT()` | `basic_term_height()` | Get terminal height in rows |
| `VDUSIZE()` | `basic_term_size()` | Returns width in upper 16 bits, height in lower 16 bits |
| `SCREEN WIDTH()` | `basic_term_width()` | Alternative terminal width query |
| `SCREEN HEIGHT()` | `basic_term_height()` | Alternative terminal height query |

---

## Color Constants

Predefined constants for 16-color mode (0-15):

```basic
' Standard 16-color palette
CONST BLACK = 0
CONST BLUE = 1
CONST GREEN = 2
CONST CYAN = 3
CONST RED = 4
CONST MAGENTA = 5
CONST BROWN = 6       ' or YELLOW
CONST LIGHTGRAY = 7   ' or WHITE
CONST DARKGRAY = 8
CONST LIGHTBLUE = 9
CONST LIGHTGREEN = 10
CONST LIGHTCYAN = 11
CONST LIGHTRED = 12
CONST LIGHTMAGENTA = 13
CONST YELLOW = 14
CONST WHITE = 15
```

---

## Special Key Code Constants

For use with `KBCODE()` and `KBSPECIAL()`:

```basic
' Cursor movement keys
CONST KB_UP = 256
CONST KB_DOWN = 257
CONST KB_LEFT = 258
CONST KB_RIGHT = 259
CONST KB_HOME = 260
CONST KB_END = 261
CONST KB_PAGEUP = 262
CONST KB_PAGEDOWN = 263

' Function keys
CONST KB_F1 = 270
CONST KB_F2 = 271
CONST KB_F3 = 272
CONST KB_F4 = 273
CONST KB_F5 = 274
CONST KB_F6 = 275
CONST KB_F7 = 276
CONST KB_F8 = 277
CONST KB_F9 = 278
CONST KB_F10 = 279
CONST KB_F11 = 280
CONST KB_F12 = 281

' Editing keys
CONST KB_INSERT = 290
CONST KB_DELETE = 291
CONST KB_BACKSPACE = 8
CONST KB_TAB = 9
CONST KB_ENTER = 13
CONST KB_ESCAPE = 27

' Modifier bitmask (for KBMOD)
CONST MOD_SHIFT = 1
CONST MOD_CTRL = 2
CONST MOD_ALT = 4
```

---

## Usage Examples

### Basic Screen Control

```basic
CLS                      ' Clear screen
LOCATE 10, 20            ' Move to row 10, column 20
PRINT "Hello, World!"

COLOR 14                 ' Yellow text
PRINT "This is yellow"
COLOR 14, 1              ' Yellow on blue
PRINT "Yellow on blue background"
COLOR RESET              ' Back to defaults
```

### VDU-Style Commands

```basic
VDUCLS                   ' Clear screen
VDUPOS 5, 10             ' Position cursor
VDUCOLOR 12              ' Light red
VDURIGHT 5               ' Move 5 columns right
VDUDOWN 2                ' Move 2 rows down
VDURESET                 ' Reset all attributes
```

### RGB True Color

```basic
RGBFG 255, 100, 50       ' Orange foreground
RGBBG 0, 0, 50           ' Dark blue background
PRINT "True color text"
COLOR RESET
```

### Text Styling

```basic
BOLD
PRINT "Bold text"
UNDERLINE
PRINT "Bold and underlined"
STYLE RESET
PRINT "Normal again"
```

### Cursor Control

```basic
CURSOR OFF               ' Hide cursor
PRINT "Cursor hidden"
CURSOR SAVE              ' Save position
LOCATE 1, 1
PRINT "Top corner"
CURSOR RESTORE           ' Back to saved position
CURSOR ON                ' Show cursor
```

### Keyboard Input

```basic
' Standard input
INPUT "Enter name: "; name$

' Single character input
PRINT "Press any key..."
k$ = INKEY$              ' Non-blocking
IF k$ = "" THEN
    k$ = CHR$(KBGET())   ' Blocking - wait for key
END IF

' Check for specific keys
IF KBHIT() THEN
    code = KBCODE()
    IF code = KB_UP THEN
        PRINT "Up arrow pressed"
    ELSEIF code = KB_F1 THEN
        PRINT "F1 pressed"
    END IF
END IF
```

### Raw Mode Input

```basic
KBRAW ON                 ' Enable raw mode
KBECHO OFF               ' Disable echo
CURSOR OFF               ' Hide cursor

' Game loop
DO
    IF KBHIT() THEN
        k = KBCODE()
        IF k = KB_UP THEN y = y - 1
        IF k = KB_DOWN THEN y = y + 1
        IF k = KB_LEFT THEN x = x - 1
        IF k = KB_RIGHT THEN x = x + 1
        IF k = KB_ESCAPE THEN EXIT DO
    END IF
    ' Update game display...
LOOP

KBRAW OFF                ' Restore normal mode
KBECHO ON
CURSOR ON
```

### Alternate Screen Buffer

```basic
SCREEN ALTERNATE         ' Switch to alternate buffer (clean slate)
CLS
PRINT "This is in the alternate screen"
PRINT "Press any key to return..."
WHILE NOT KBHIT(): WEND
SCREEN MAIN              ' Return to main buffer (original content restored)
```

### Position Queries

```basic
LOCATE 10, 20
PRINT "Current position: "; ROW(0); ", "; POS(0)
' Outputs: Current position: 10, 20

width = VDUWIDTH()
height = VDUHEIGHT()
PRINT "Terminal size: "; width; " x "; height
```

---

## Implementation Priority

### Phase 1: Core Commands (Already in Runtime)
- ✅ `CLS`, `GCLS`
- ✅ `LOCATE`
- ✅ `COLOR` (fg), `COLOR` (fg, bg)
- ✅ Cursor show/hide/save/restore
- ✅ Relative cursor movement
- ✅ RGB colors
- ✅ Text styles
- ✅ Screen buffer switching

### Phase 2: Parser & Codegen Integration (Next Step)
- [ ] Add all keywords to lexer/token definitions
- [ ] Implement parser rules for each command syntax
- [ ] Create codegen emission methods in `BlockEmitter`
- [ ] Add runtime function declarations in `RuntimeLibrary`
- [ ] Wire up `terminal_init()` / `terminal_cleanup()` in main

### Phase 3: Input Functions (Future)
- [ ] Implement `KBGET`, `KBHIT`, `INKEY$`
- [ ] Raw mode support
- [ ] Special key detection
- [ ] Input buffer control

### Phase 4: Query Functions (Future)
- [ ] Position queries (`POS`, `ROW`, `CSRLIN`)
- [ ] Terminal size detection

---

## Parser Considerations

### Context-Sensitive Keywords

Some keywords may conflict with existing BASIC keywords:

- **`DIM`**: Already used for array declarations. `DIM` as a style command should be avoided or require explicit context (e.g., `STYLE DIM` or `VDUSTYLE 2`)
- **`TAB`**: May conflict with existing TAB function in PRINT statements
- **`SCREEN`**: Consider if SCREEN is used for other purposes (graphics modes, etc.)

### Multi-Word Commands

Commands like `CURSOR ON`, `COLOR RESET`, `SCREEN ALTERNATE` require special parsing:
- Treat as single statement with sub-keyword
- Example: `CURSOR` is the primary keyword, `ON`/`OFF`/`SHOW`/`HIDE`/`SAVE`/`RESTORE` are sub-commands

### Function vs Statement

Some operations make sense as both statements and functions:
- `LOCATE row, col` (statement)
- `POS(0)` (function)
- `INKEY$` (function)
- `KBHIT()` (function returning boolean/integer)

---

## Recommendations

1. **Start Simple**: Implement the most common commands first (CLS, LOCATE, COLOR, basic INPUT)
2. **Use Traditional Names**: Stick to classic BASIC keywords for familiarity (LOCATE, COLOR, INKEY$)
3. **VDU for Advanced**: Use VDU prefix for lower-level or less common operations
4. **KB for Input**: Use KB prefix consistently for all keyboard input operations
5. **Aliases**: Provide both American (COLOR) and British (COLOUR) spellings
6. **Constants**: Define color and key constants in a standard include file or built-in
7. **Documentation**: Provide clear examples for common use cases

---

## Next Steps

1. Add keywords to lexer (`src/lexer.zig` or token definitions)
2. Implement parser methods for each command category
3. Create `BlockEmitter` methods for codegen
4. Test with sample programs
5. Document in user manual

This mapping provides a comprehensive, BASIC-friendly interface to modern terminal capabilities while maintaining backward compatibility with classic BASIC conventions.