# BASED Test Plan

## Overview

This document outlines the testing strategy for BASED (BASIC Editor). Since BASED is an interactive terminal application, most testing will be manual, but we'll document specific test scenarios to ensure comprehensive coverage.

## Test Environment

- **Terminal**: Unix/Linux terminal with ANSI escape sequence support
- **Terminal Size**: Minimum 80x24 characters
- **Compiler**: FasterBASIC compiler (fbc) in PATH
- **Test Files**: Located in `examples/` directory

## Build Test

### BT-001: Compile BASED
**Objective**: Verify that BASED compiles without errors

**Steps**:
1. Run `./build.sh` or `fbc based.bas -o based`
2. Check for compilation errors
3. Verify executable `based` is created

**Expected Result**: 
- Clean compilation with no errors
- Executable file `based` exists and is runnable

**Status**: ⏳ Pending

---

## Startup Tests

### ST-001: Launch Editor
**Objective**: Verify editor starts successfully

**Steps**:
1. Run `./based`
2. Observe initial screen

**Expected Result**:
- Screen clears
- Title bar displays "BASED - FasterBASIC Editor"
- Filename shows "untitled.bas"
- Line 1 is visible with line number
- Status bar shows keyboard shortcuts
- Cursor is visible at position 1:1

**Status**: ⏳ Pending

---

### ST-002: Initial State
**Objective**: Verify initial editor state

**Steps**:
1. Launch BASED
2. Check display elements

**Expected Result**:
- Modified flag NOT shown (no "[modified]")
- Single empty line (line 1)
- Cursor at column 0, row 0
- No clipboard content

**Status**: ⏳ Pending

---

## Navigation Tests

### NT-001: Arrow Key Navigation
**Objective**: Test basic cursor movement

**Steps**:
1. Launch BASED
2. Type "Hello World"
3. Press LEFT arrow 5 times
4. Press RIGHT arrow 2 times
5. Press UP arrow (should stay on line 1)
6. Press DOWN arrow (should stay on line 1)

**Expected Result**:
- Cursor moves correctly left/right within text
- Cursor does not move beyond text boundaries
- UP/DOWN have no effect on single line

**Status**: ⏳ Pending

---

### NT-002: Home/End Keys
**Objective**: Test Home and End key navigation

**Steps**:
1. Launch BASED
2. Type "This is a test line"
3. Press HOME key
4. Verify cursor at start of line
5. Press END key
6. Verify cursor at end of line

**Expected Result**:
- HOME moves cursor to column 0
- END moves cursor to end of text

**Status**: ⏳ Pending

---

### NT-003: Multi-line Navigation
**Objective**: Test navigation across multiple lines

**Steps**:
1. Launch BASED
2. Type "Line 1" and press ENTER
3. Type "Line 2" and press ENTER
4. Type "Line 3"
5. Press UP arrow twice (should be on line 1)
6. Press DOWN arrow once (should be on line 2)
7. Press HOME, then DOWN (should be at start of line 3)

**Expected Result**:
- UP/DOWN move between lines correctly
- Cursor X position is preserved when possible
- Cursor X is clamped to line length when moving to shorter lines

**Status**: ⏳ Pending

---

### NT-004: Page Up/Down
**Objective**: Test page scrolling

**Steps**:
1. Load or create a file with 50+ lines
2. Press PAGE DOWN several times
3. Observe viewport scrolling
4. Press PAGE UP to return
5. Verify cursor and viewport positions

**Expected Result**:
- Viewport scrolls by approximately edit_height lines
- Cursor moves with viewport
- No crash at top/bottom boundaries

**Status**: ⏳ Pending

---

## Editing Tests

### ET-001: Text Insertion
**Objective**: Test character insertion

**Steps**:
1. Launch BASED
2. Type "Hello"
3. Press LEFT 3 times (cursor after "He")
4. Type "y" (should insert, making "Heyllo")

**Expected Result**:
- Characters insert at cursor position
- Existing text shifts right
- Modified flag appears

**Status**: ⏳ Pending

---

### ET-002: Backspace Delete
**Objective**: Test backspace deletion

**Steps**:
1. Launch BASED
2. Type "Hello World"
3. Press BACKSPACE 5 times
4. Verify text is now "Hello "

**Expected Result**:
- Backspace deletes character before cursor
- Cursor moves left
- Modified flag appears

**Status**: ⏳ Pending

---

### ET-003: Forward Delete
**Objective**: Test DELETE key

**Steps**:
1. Launch BASED
2. Type "Hello World"
3. Press HOME
4. Press DELETE 6 times
5. Verify text is now "World"

**Expected Result**:
- DELETE removes character at cursor
- Cursor stays in place
- Modified flag appears

**Status**: ⏳ Pending

---

### ET-004: Enter Key (New Line)
**Objective**: Test line splitting with Enter

**Steps**:
1. Launch BASED
2. Type "Hello World"
3. Move cursor to after "Hello"
4. Press ENTER

**Expected Result**:
- Line splits into two lines
- Line 1: "Hello"
- Line 2: " World"
- Cursor moves to start of line 2
- Line count increases

**Status**: ⏳ Pending

---

### ET-005: Backspace at Line Start
**Objective**: Test line joining with backspace

**Steps**:
1. Create two lines: "Hello" and "World"
2. Position cursor at start of line 2
3. Press BACKSPACE

**Expected Result**:
- Lines join: "HelloWorld"
- Cursor positioned between "Hello" and "World"
- Line count decreases

**Status**: ⏳ Pending

---

### ET-006: Tab Key
**Objective**: Test tab insertion

**Steps**:
1. Launch BASED
2. Press TAB
3. Verify 4 spaces inserted

**Expected Result**:
- 4 spaces appear
- Cursor advances 4 positions

**Status**: ⏳ Pending

---

## Line Operation Tests

### LO-001: Kill Line (Ctrl+K)
**Objective**: Test line deletion

**Steps**:
1. Create 3 lines: "Line1", "Line2", "Line3"
2. Position cursor on line 2
3. Press Ctrl+K

**Expected Result**:
- Line 2 deleted
- Lines renumber: Line1, Line3
- Cursor on line 2 (former line 3)
- Modified flag set

**Status**: ⏳ Pending

---

### LO-002: Duplicate Line (Ctrl+D)
**Objective**: Test line duplication

**Steps**:
1. Type "Test Line"
2. Press Ctrl+D

**Expected Result**:
- New line inserted below
- New line contains "Test Line"
- Cursor moves to duplicated line
- Modified flag set

**Status**: ⏳ Pending

---

### LO-003: Cut Line (Ctrl+X)
**Objective**: Test cut to clipboard

**Steps**:
1. Create 2 lines: "Line1", "Line2"
2. Position on line 1
3. Press Ctrl+X

**Expected Result**:
- Line 1 deleted
- Clipboard contains "Line1"
- Status message: "Line cut to clipboard"
- Modified flag set

**Status**: ⏳ Pending

---

### LO-004: Copy Line (Ctrl+C)
**Objective**: Test copy to clipboard

**Steps**:
1. Type "Copy Me"
2. Press Ctrl+C

**Expected Result**:
- Line remains in buffer
- Clipboard contains "Copy Me"
- Status message: "Line copied to clipboard"
- No modified flag (no change made)

**Status**: ⏳ Pending

---

### LO-005: Paste Line (Ctrl+V)
**Objective**: Test paste from clipboard

**Steps**:
1. Type "Original"
2. Press Ctrl+C (copy)
3. Press ENTER (new line)
4. Press Ctrl+V (paste)

**Expected Result**:
- New line inserted with "Original"
- Cursor moves to pasted line
- Status message: "Line pasted from clipboard"
- Modified flag set

**Status**: ⏳ Pending

---

### LO-006: Paste Empty Clipboard
**Objective**: Test paste with empty clipboard

**Steps**:
1. Launch BASED (fresh, no clipboard)
2. Press Ctrl+V

**Expected Result**:
- Status message: "Clipboard is empty"
- No change to buffer

**Status**: ⏳ Pending

---

## File Operation Tests

### FO-001: Save File (Ctrl+S)
**Objective**: Test saving a file

**Steps**:
1. Launch BASED
2. Type some text
3. Press Ctrl+S
4. Exit editor
5. Check filesystem for "untitled.bas"

**Expected Result**:
- File "untitled.bas" created
- File contains typed text
- Status message: "Saved: untitled.bas"
- Modified flag cleared

**Status**: ⏳ Pending

---

### FO-002: Load File (Ctrl+L)
**Objective**: Test loading a file

**Steps**:
1. Launch BASED
2. Press Ctrl+L
3. Type "examples/hello.bas"
4. Press ENTER

**Expected Result**:
- File loads into buffer
- Content displayed with line numbers
- Filename updates to "examples/hello.bas"
- Status message: "Loaded: examples/hello.bas"
- Modified flag clear

**Status**: ⏳ Pending

---

### FO-003: Load Non-existent File
**Objective**: Test error handling for missing files

**Steps**:
1. Launch BASED
2. Press Ctrl+L
3. Type "nonexistent.bas"
4. Press ENTER

**Expected Result**:
- Error message or status indication
- Editor remains functional
- Original buffer unchanged

**Status**: ⏳ Pending

---

### FO-004: Quit Without Save (Ctrl+Q)
**Objective**: Test quit with unsaved changes

**Steps**:
1. Launch BASED
2. Type some text
3. Press Ctrl+Q
4. When prompted, press 'N'

**Expected Result**:
- Prompt: "Save changes? (Y/N)"
- On 'N', editor exits without saving
- Terminal restored to normal mode

**Status**: ⏳ Pending

---

### FO-005: Quit With Save (Ctrl+Q)
**Objective**: Test quit with save prompt

**Steps**:
1. Launch BASED
2. Type some text
3. Press Ctrl+Q
4. When prompted, press 'Y'

**Expected Result**:
- Prompt: "Save changes? (Y/N)"
- On 'Y', file saves then editor exits
- File exists on filesystem

**Status**: ⏳ Pending

---

## Build & Run Tests

### BR-001: Build and Run (Ctrl+R)
**Objective**: Test compilation integration

**Steps**:
1. Load or create a simple program
2. Press Ctrl+R

**Expected Result**:
- Editor saves file
- Switches to normal terminal mode
- Displays compilation message
- (When implemented) Compiles and runs program
- Returns to editor on keypress

**Status**: ⏳ Pending (compilation not yet wired up)

---

### BR-002: Build Only (Ctrl+B)
**Objective**: Test compile without run

**Steps**:
1. Load a program
2. Press Ctrl+B

**Expected Result**:
- File saves
- Status message indicates build
- (When implemented) Compilation occurs
- No program execution

**Status**: ⏳ Pending (compilation not yet wired up)

---

## Formatting Tests

### FM-001: Format Buffer (Ctrl+F)
**Objective**: Test code formatting

**Steps**:
1. Type "  PRINT 'Hello'  " (with extra spaces)
2. Press Ctrl+F

**Expected Result**:
- Leading/trailing spaces removed
- Status message: "Code formatted"
- Modified flag set

**Status**: ⏳ Pending

---

## Edge Case Tests

### EC-001: Empty File Operations
**Objective**: Test operations on empty buffer

**Steps**:
1. Launch BASED
2. Press Ctrl+K (delete empty line)
3. Press Ctrl+D (duplicate empty line)
4. Type text, verify still works

**Expected Result**:
- No crash on empty line operations
- Buffer maintains at least one line
- Editor remains functional

**Status**: ⏳ Pending

---

### EC-002: Maximum Line Length
**Objective**: Test behavior at MAX_LINE_LEN

**Steps**:
1. Type 255 characters on one line
2. Try to type more

**Expected Result**:
- Line accepts up to 255 characters
- Additional characters either ignored or line scrolls
- No crash or corruption

**Status**: ⏳ Pending

---

### EC-003: Maximum Lines
**Objective**: Test MAX_LINES limit

**Steps**:
1. Create script to generate file with 10,000 lines
2. Load file
3. Try to insert additional lines

**Expected Result**:
- File loads (may be slow)
- Status message: "Maximum lines reached"
- Editor remains stable

**Status**: ⏳ Pending

---

### EC-004: Long File Scrolling
**Objective**: Test scrolling in large files

**Steps**:
1. Load file with 100+ lines
2. Hold PAGE DOWN to scroll to end
3. Hold PAGE UP to scroll to start
4. Use arrow keys at boundaries

**Expected Result**:
- Smooth scrolling
- No crashes at boundaries
- Cursor and viewport sync correctly

**Status**: ⏳ Pending

---

### EC-005: Rapid Key Input
**Objective**: Test handling of fast typing

**Steps**:
1. Launch BASED
2. Type very quickly (paste long text if possible)
3. Navigate while typing

**Expected Result**:
- All characters captured
- No dropped input
- Display updates correctly
- No crashes

**Status**: ⏳ Pending

---

## Display Tests

### DT-001: Color Rendering
**Objective**: Verify color display

**Steps**:
1. Launch BASED
2. Observe title bar (blue background)
3. Observe line numbers (cyan)
4. Observe status bar (gray background)

**Expected Result**:
- Colors display as intended
- Text is readable
- No display corruption

**Status**: ⏳ Pending

---

### DT-002: Screen Refresh
**Objective**: Test full screen redraw

**Steps**:
1. Edit several lines
2. Observe screen updates
3. Scroll and verify display

**Expected Result**:
- Display updates correctly
- No artifacts or corruption
- Line numbers align with content

**Status**: ⏳ Pending

---

### DT-003: Modified Flag Display
**Objective**: Test modified indicator

**Steps**:
1. Launch BASED (no modified flag)
2. Type a character (modified flag appears)
3. Press Ctrl+S (modified flag clears)
4. Type again (modified flag reappears)

**Expected Result**:
- "[modified]" appears in title bar when changed
- Disappears after save
- Reappears on next edit

**Status**: ⏳ Pending

---

## Keyboard Mode Tests

### KM-001: Raw Mode Enable
**Objective**: Verify raw mode activation

**Steps**:
1. Launch BASED
2. Type characters
3. Press Ctrl+C (should NOT exit immediately)

**Expected Result**:
- Characters appear immediately (no line buffering)
- Control keys processed by editor
- Terminal in raw mode

**Status**: ⏳ Pending

---

### KM-002: Raw Mode Restore
**Objective**: Verify terminal restoration on exit

**Steps**:
1. Launch BASED
2. Press Ctrl+Q (or Ctrl+R for build)
3. Exit editor
4. Type in shell

**Expected Result**:
- Terminal returns to normal mode
- Shell input works normally
- Cursor visible and functional

**Status**: ⏳ Pending

---

## Integration Tests

### IT-001: Edit-Save-Load Cycle
**Objective**: Test complete workflow

**Steps**:
1. Launch BASED
2. Type a program with multiple lines
3. Press Ctrl+S to save as "test.bas"
4. Press Ctrl+Q to quit
5. Launch BASED again
6. Press Ctrl+L and load "test.bas"
7. Verify content

**Expected Result**:
- File saves correctly
- File loads back with exact content
- Line numbers correct
- No data loss

**Status**: ⏳ Pending

---

### IT-002: Complex Editing Session
**Objective**: Test real-world usage

**Steps**:
1. Load examples/subroutines.bas
2. Navigate to function definition
3. Duplicate a function (Ctrl+D multiple times)
4. Modify the duplicated function
5. Delete old function (Ctrl+K repeatedly)
6. Use cut/copy/paste
7. Save file (Ctrl+S)

**Expected Result**:
- All operations work smoothly
- File saves with changes
- No crashes or corruption
- Modified flag tracks correctly

**Status**: ⏳ Pending

---

## Performance Tests

### PT-001: Large File Load Time
**Objective**: Measure load time for large files

**Steps**:
1. Create file with 1000 lines
2. Time loading with Ctrl+L

**Expected Result**:
- File loads in reasonable time (<2 seconds)
- Editor responsive after load

**Status**: ⏳ Pending

---

### PT-002: Scrolling Performance
**Objective**: Test scrolling smoothness

**Steps**:
1. Load 500+ line file
2. Hold PAGE DOWN key
3. Observe screen updates

**Expected Result**:
- Scrolling is smooth
- No visible lag or tearing
- Screen updates quickly

**Status**: ⏳ Pending

---

## Regression Tests

After any code changes, re-run these critical tests:

1. **Smoke Test**: Launch, type text, save, quit
2. **Navigation**: Arrow keys, Home/End work
3. **Edit Operations**: Insert, delete, backspace
4. **File I/O**: Save and load
5. **Display**: Colors and layout correct

---

## Test Results Summary

| Category | Total | Passed | Failed | Pending |
|----------|-------|--------|--------|---------|
| Build | 1 | 0 | 0 | 1 |
| Startup | 2 | 0 | 0 | 2 |
| Navigation | 4 | 0 | 0 | 4 |
| Editing | 6 | 0 | 0 | 6 |
| Line Ops | 6 | 0 | 0 | 6 |
| File Ops | 5 | 0 | 0 | 5 |
| Build/Run | 2 | 0 | 0 | 2 |
| Formatting | 1 | 0 | 0 | 1 |
| Edge Cases | 5 | 0 | 0 | 5 |
| Display | 3 | 0 | 0 | 3 |
| Keyboard | 2 | 0 | 0 | 2 |
| Integration | 2 | 0 | 0 | 2 |
| Performance | 2 | 0 | 0 | 2 |
| **TOTAL** | **41** | **0** | **0** | **41** |

---

## Known Issues

*To be filled in during testing*

---

## Future Test Additions

- Undo/Redo functionality (when implemented)
- Find/Replace (when implemented)
- Go to Line (when implemented)
- Help screen (F1) (when implemented)
- Syntax highlighting (when implemented)
- Mouse support (when implemented)
- UTF-8 character handling
- Terminal resize handling
- Multi-file buffers (when implemented)

---

**Version**: 1.0  
**Last Updated**: 2024  
**Maintainer**: FasterBASIC Project