# BASED - BASIC Editor Design Document

## Overview

BASED is a full-screen terminal editor for FasterBASIC source files, inspired by the classic QuickBASIC IDE. It serves as both a practical tool and a comprehensive test of FasterBASIC's terminal I/O capabilities.

## Goals

1. **Functional Editor**: Create a usable editor for writing BASIC programs
2. **Terminal I/O Test**: Exercise all terminal features (CLS, LOCATE, COLOR, cursor control, keyboard input)
3. **Self-Hosting Capability**: Demonstrate FasterBASIC can build complete applications
4. **Classic Feel**: Capture the spirit of retro BASIC IDEs

## Features

### Core Editing
- Multi-line text buffer with line-based storage
- Cursor movement (arrow keys, Home/End, PgUp/PgDn)
- Text insertion and deletion
- Line operations (insert, delete, duplicate)
- Scroll viewport for files larger than screen

### Keyboard Commands

#### File Operations
- `Ctrl+S` - Save file
- `Ctrl+L` - Load file (prompt for filename)
- `Ctrl+N` - New file (clear buffer, prompt to save if modified)
- `Ctrl+Q` - Quit (prompt to save if modified)

#### Editing Operations
- `Ctrl+K` - Kill (delete) current line
- `Ctrl+D` - Duplicate current line
- `Ctrl+X` - Cut line to clipboard
- `Ctrl+C` - Copy line to clipboard
- `Ctrl+V` - Paste from clipboard
- `Ctrl+Z` - Undo (stretch goal)

#### Build & Run
- `Ctrl+R` - Build and Run (compile with fbc, run if successful)
- `Ctrl+B` - Build only (compile without running)

#### Code Tools
- `Ctrl+F` - Format BASIC code (auto-indent, keyword capitalization)
- `Ctrl+G` - Go to line number

#### Navigation
- Arrow keys - Move cursor
- `Home` - Start of line
- `End` - End of line
- `PgUp` - Page up
- `PgDn` - Page down
- `Ctrl+Home` - Start of file
- `Ctrl+End` - End of file

### Display

#### Screen Layout
```
╔════════════════════════════════════════════════════════════════════════════╗
║ BASED - FasterBASIC Editor                    [modified]   untitled.bas    ║
╠════════════════════════════════════════════════════════════════════════════╣
║     1: REM Example program                                                 ║
║     2: PRINT "Hello, World!"                                               ║
║     3: FOR i = 1 TO 10                                                     ║
║     4:     PRINT i                                                         ║
║     5: NEXT i                                                              ║
║     6: █                                                                   ║
║    ...                                                                     ║
║                                                                            ║
╠════════════════════════════════════════════════════════════════════════════╣
║ F1=Help  ^S=Save  ^L=Load  ^R=Run  ^F=Format  ^K=Kill  ^D=Dup  ^Q=Quit    ║
╚════════════════════════════════════════════════════════════════════════════╝
```

#### Color Scheme (16-color mode)
- **Title Bar**: White on Blue (color 15, 1)
- **Line Numbers**: Cyan on Black (color 11, 0)
- **Code Area**: White on Black (color 7, 0)
- **Keywords**: Bright White/Bold (color 15)
- **Comments**: Green (color 10)
- **Strings**: Yellow (color 14)
- **Status Bar**: Black on Gray (color 0, 7)
- **Modified Indicator**: Red on Blue (color 12, 1)

### Data Structures

#### EditorState
- `lines$()` - Array of strings (line buffer)
- `line_count` - Number of lines
- `cursor_x` - Column position (0-based)
- `cursor_y` - Row position in file (0-based)
- `view_top` - First visible line (scrolling)
- `modified` - Boolean flag
- `filename$` - Current file name
- `clipboard$` - Single-line clipboard
- `screen_width` - Terminal width
- `screen_height` - Terminal height

#### Constants
```basic
CONST MAX_LINES = 10000
CONST MAX_LINE_LEN = 255
CONST HEADER_LINES = 2
CONST FOOTER_LINES = 2
```

## Architecture

### Module Structure

```
based.bas (main program)
├── Editor Core
│   ├── init_editor() - Initialize state
│   ├── main_loop() - Main event loop
│   └── cleanup() - Shutdown
├── Display
│   ├── draw_header() - Title bar
│   ├── draw_editor() - Code area with line numbers
│   ├── draw_status() - Status/help bar
│   └── refresh_screen() - Full redraw
├── Input
│   ├── handle_key() - Process keyboard input
│   ├── handle_printable() - Insert character
│   └── handle_special() - Special keys (arrows, etc.)
├── File Operations
│   ├── load_file() - Read from disk
│   ├── save_file() - Write to disk
│   └── prompt_filename() - UI for filename input
├── Edit Operations
│   ├── insert_char() - Insert at cursor
│   ├── delete_char() - Backspace/Delete
│   ├── insert_line() - New line
│   ├── delete_line() - Remove line
│   └── duplicate_line() - Copy line below
├── Navigation
│   ├── move_cursor() - Update cursor position
│   ├── scroll_view() - Adjust viewport
│   └── clamp_cursor() - Keep cursor in bounds
├── Build & Run
│   ├── build_program() - Invoke fbc compiler
│   ├── run_program() - Execute compiled binary
│   └── show_output() - Display compile errors/output
└── Code Tools
    ├── format_line() - Auto-indent, capitalize keywords
    └── format_buffer() - Format all lines
```

### Main Loop Pseudocode

```
INIT editor state
CALL draw_screen()

DO
    key = KBGET()
    
    IF is_ctrl_key(key) THEN
        CALL handle_command(key)
    ELSEIF is_special_key(key) THEN
        CALL handle_navigation(key)
    ELSEIF is_printable(key) THEN
        CALL insert_char(key)
        modified = TRUE
    END IF
    
    CALL refresh_screen()
LOOP UNTIL quit_flag

CALL cleanup()
```

## Implementation Phases

### Phase 1: Basic Framework ✓ (to be implemented)
- Initialize terminal (CLS, KBRAW 1)
- Draw static header and footer
- Main event loop with quit command
- Clean shutdown

### Phase 2: Display & Buffer ✓ (to be implemented)
- Line buffer storage (dynamic array)
- Display lines with line numbers
- Cursor positioning
- Viewport scrolling

### Phase 3: Basic Editing ✓ (to be implemented)
- Character insertion/deletion
- Arrow key navigation
- Enter (new line)
- Backspace/Delete

### Phase 4: Line Operations ✓ (to be implemented)
- Ctrl+K (kill line)
- Ctrl+D (duplicate line)
- Clipboard (cut/copy/paste)

### Phase 5: File I/O ✓ (to be implemented)
- Save file (Ctrl+S)
- Load file (Ctrl+L)
- Filename prompt dialog
- Modified flag tracking

### Phase 6: Build & Run ✓ (to be implemented)
- Invoke FBC compiler (Ctrl+B)
- Build and run (Ctrl+R)
- Display compilation output
- Handle errors

### Phase 7: Code Tools (stretch goal)
- Format code (Ctrl+F)
- Keyword recognition and capitalization
- Auto-indentation
- Syntax highlighting (if feasible)

### Phase 8: Polish (stretch goal)
- Go to line (Ctrl+G)
- Undo/Redo
- Find/Replace
- Help screen (F1)

## Technical Considerations

### Terminal I/O Usage
- **CLS**: Clear screen for initial draw and refresh
- **LOCATE**: Position cursor for drawing text and user cursor
- **COLOR**: Set foreground/background for different UI elements
- **KBRAW**: Enable raw mode for character-by-character input
- **KBGET**: Blocking keyboard read in main loop
- **KBHIT**: Check for input (if implementing async features)
- **Special Keys**: Handle arrow keys (256+), function keys, Home/End, etc.

### File I/O
- Use BASIC file operations: OPEN, INPUT, LINE INPUT, PRINT#, CLOSE
- Handle file not found, permission errors
- Create backup on save (optional)

### Performance
- Redraw only changed portions (optimize later)
- Limit buffer size (MAX_LINES constant)
- Handle large files gracefully (lazy loading - stretch goal)

### Error Handling
- Validate file operations
- Catch keyboard errors
- Handle terminal resize (if detectable)
- Graceful degradation on unsupported features

### Build Integration
- Save temp file before compilation
- Capture compiler output (redirect to file, then read)
- Check exit code for success/failure
- Handle running compiled program (may need to exit raw mode temporarily)

## Testing Strategy

### Manual Testing Scenarios
1. **Empty Buffer**: Start editor, type text, verify display
2. **File Operations**: Load existing .bas file, edit, save, reload
3. **Navigation**: Test all cursor movements, scrolling
4. **Line Operations**: Kill, duplicate, cut/copy/paste lines
5. **Build & Run**: Write simple program, compile, run, verify output
6. **Edge Cases**: 
   - Empty file
   - Single character file
   - File with very long lines (>255 chars)
   - Scrolling at top/bottom boundaries
   - Saving to invalid path

### Test Files
- `test_hello.bas` - Simple "Hello World" program
- `test_syntax.bas` - Program with syntax errors
- `test_large.bas` - File with many lines (100+)
- `test_edge.bas` - Edge cases (empty lines, long lines)

## Future Enhancements

- **Multiple Buffers**: Edit multiple files, switch between them
- **Split View**: View two parts of same file
- **Integrated Debugger**: Breakpoints, step through code
- **Project Management**: Multi-file projects, build configurations
- **Themes**: Customizable color schemes
- **Mouse Support**: Click to position cursor, select text
- **UTF-8**: Support for non-ASCII characters
- **Configuration File**: Save preferences (.basedrc)

## Success Criteria

BASED is successful if:
1. ✅ It compiles without errors using FasterBASIC
2. ✅ Basic editing works (insert, delete, navigate)
3. ✅ Files can be loaded and saved
4. ✅ Programs can be built and run from within the editor
5. ✅ The editor is usable for writing small to medium BASIC programs
6. ✅ It demonstrates FasterBASIC's terminal I/O capabilities
7. ✅ Code is readable and maintainable (serves as example)

## Files

- `DESIGN.md` - This document
- `based.bas` - Main editor program
- `README.md` - User documentation
- `examples/` - Example BASIC files for testing
- `screenshots/` - Terminal screenshots (optional)

## Notes

- Keep code simple and readable (it's a teaching example)
- Comment thoroughly
- Use meaningful variable names
- Avoid premature optimization
- Focus on core features first, add polish later
- Document any FasterBASIC limitations discovered

---

**Version**: 1.0  
**Author**: FasterBASIC Project  
**Date**: 2024  
**Status**: Design Complete - Ready for Implementation