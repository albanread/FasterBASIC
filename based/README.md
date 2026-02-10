# BASED - BASIC Editor for FasterBASIC

A full-screen terminal editor for FasterBASIC, inspired by the classic QuickBASIC IDE.

## Overview

BASED is a lightweight, terminal-based code editor designed specifically for writing FasterBASIC programs. It provides a familiar editing experience reminiscent of classic BASIC development environments while demonstrating the terminal I/O and file handling capabilities of FasterBASIC.

## Features

### Core Editing
- Multi-line text buffer with line numbers
- Full cursor navigation (arrow keys, Home/End, Page Up/Down)
- Text insertion and deletion
- Line operations (insert, delete, duplicate)
- Clipboard support (cut/copy/paste lines)
- Automatic viewport scrolling
- Command-line file loading
- Efficient whole-file I/O using SLURP and SPIT

### Keyboard Commands

#### File Operations
- **Ctrl+S** - Save file
- **Ctrl+L** - Load file (prompts for filename)
- **Ctrl+Q** - Quit (prompts to save if modified)

#### Editing Operations
- **Ctrl+K** - Kill (delete) current line
- **Ctrl+D** - Duplicate current line
- **Ctrl+X** - Cut line to clipboard
- **Ctrl+C** - Copy line to clipboard
- **Ctrl+V** - Paste from clipboard

#### Build & Run
- **Ctrl+R** - Build and Run (compile with fbc, then execute)
- **Ctrl+B** - Build only (compile without running)

#### Code Tools
- **Ctrl+F** - Format BASIC code (trim whitespace)

#### Navigation
- **Arrow Keys** - Move cursor
- **Home** - Start of line
- **End** - End of line
- **Page Up** - Scroll up one page
- **Page Down** - Scroll down one page
- **Enter** - Insert new line
- **Backspace** - Delete character before cursor
- **Delete** - Delete character at cursor
- **Tab** - Insert 4 spaces

## Building BASED

### Using the Build Script (Recommended)

```bash
cd based
./build.sh
```

The build script automatically finds the FasterBASIC compiler and builds the editor.

### Manual Build

To compile BASED manually, use the FasterBASIC compiler:

```bash
fbc based.bas -o based
```

This will create an executable named `based` that you can run from your terminal.

## Running BASED

### Start with Empty Buffer

```bash
./based
```

By default, BASED starts with an empty buffer named `untitled.bas`.

### Load File from Command Line

```bash
./based myprogram.bas
```

BASED will automatically load the specified file if it exists.

### Load File from Within Editor

Press **Ctrl+L** and enter the filename when prompted.

## Screen Layout

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
║ ^S=Save ^L=Load ^R=Run ^F=Format ^K=Kill ^D=Dup ^Q=Quit                   ║
╚════════════════════════════════════════════════════════════════════════════╝
```

### Components

1. **Title Bar** (top) - Shows editor name, modified flag, and current filename
2. **Edit Area** (middle) - Line numbers and code with cursor
3. **Status Bar** (bottom) - Quick reference for keyboard commands

## Color Scheme

- **Title Bar**: White text on blue background
- **Line Numbers**: Cyan text on black background
- **Code Area**: White text on black background
- **Status Bar**: Black text on gray background
- **Modified Indicator**: Shows `[modified]` in red when file has unsaved changes

## Limitations

- Maximum 10,000 lines per file
- Maximum 255 characters per line
- Single file editing (no multiple buffers)
- No syntax highlighting (colored keywords not yet implemented)
- Basic clipboard (single line only)
- No undo/redo (planned for future)
- Terminal must support ANSI escape sequences
- Assumes 80x24 terminal size (dynamic sizing not yet implemented)

## File Format

BASED works with plain text files, typically with `.bas` extension. Files are saved with Unix line endings (LF).

### Efficient File I/O

BASED uses the new `SLURP` and `SPIT` functions for efficient whole-file operations:
- **SLURP(filename$)** - Reads entire file into memory in one operation
- **SPIT filename$, content$** - Writes entire file in one operation

This is much faster than traditional line-by-line I/O, especially for larger files.

## Tips

1. **Save Often**: Press Ctrl+S frequently to save your work
2. **Test Your Code**: Use Ctrl+R to quickly compile and run your program
3. **Line Operations**: Ctrl+D is handy for duplicating similar code lines
4. **Clipboard**: Use Ctrl+X/C/V to move lines around in your code
5. **Command Line**: Open files quickly with `./based filename.bas`

## Examples

The `examples/` directory contains sample BASIC programs you can load and edit:

- `hello.bas` - Simple "Hello World" program
- `loops.bas` - Examples of FOR and WHILE loops
- `subroutines.bas` - SUB and FUNCTION definitions

Load an example:
1. Press **Ctrl+L**
2. Type `examples/hello.bas`
3. Press **Enter**

## Technical Details

BASED is written entirely in FasterBASIC and uses the following features:

### Terminal I/O
- **CLS** - Clear screen
- **LOCATE** - Position cursor
- **COLOR** - Set text colors
- **KBRAW** - Enable raw keyboard mode
- **KBGET** - Read keyboard input
- **CURSOR_SHOW/CURSOR_HIDE** - Control cursor visibility

### File Operations
- **SLURP(filename$)** - Read entire file efficiently
- **SPIT filename$, content$** - Write entire file efficiently

### Command-Line Arguments
- **COMMANDCOUNT** - Get number of arguments
- **COMMAND(n)** - Access individual arguments

The editor demonstrates that FasterBASIC is capable of building complete, interactive terminal applications with efficient file handling.

## Troubleshooting

### Terminal Issues

If the editor display looks corrupted:
- Make sure your terminal supports ANSI escape sequences
- Try resizing your terminal to at least 80x24
- Some terminal emulators may not support all features

If keyboard input doesn't work:
- Press Ctrl+C to exit if stuck
- The terminal will be restored to normal mode on exit

### Compilation Issues

If you get errors about missing keywords:
- Make sure you're using the latest version of FasterBASIC
- Check that terminal I/O support is compiled into your runtime

### File Loading Issues

If files don't load:
- Check that the file path is correct
- Verify file permissions
- Large files (>10,000 lines) will be truncated

## Development Status

BASED is currently in version 1.0 and includes:

- ✅ Core editing (insert, delete, navigate)
- ✅ File I/O (load, save with SLURP/SPIT)
- ✅ Command-line file loading
- ✅ Line operations (kill, duplicate, clipboard)
- ✅ Basic formatting
- ✅ Build & run integration (framework in place)
- ⏳ Advanced formatting (keyword capitalization, auto-indent)
- ⏳ Syntax highlighting
- ⏳ Undo/Redo
- ⏳ Find/Replace
- ⏳ Go to line
- ⏳ Help screen (F1)
- ⏳ Multiple file buffers

## Contributing

BASED is part of the FasterBASIC project. Contributions are welcome!

Areas for improvement:
- Implement actual compiler invocation for Ctrl+R
- Add syntax highlighting using COLOR for keywords
- Implement undo/redo stack
- Add find/replace functionality
- Improve formatting (auto-indentation, keyword capitalization)
- Dynamic terminal size detection
- UTF-8 support
- Mouse support (click to position cursor)

## License

BASED is part of the FasterBASIC project and uses the same license.

## Credits

Inspired by:
- QuickBASIC IDE (Microsoft, 1985-2000)
- Turbo Pascal IDE (Borland)
- Classic BASIC development environments

Built with FasterBASIC to demonstrate the language's capabilities.

---

**Version**: 1.0  
**Author**: FasterBASIC Project  
**Date**: 2024

For more information about FasterBASIC, see the main project documentation.