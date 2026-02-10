REM BASED - BASIC Editor for FasterBASIC
REM A full-screen terminal editor inspired by QuickBASIC
REM Version 1.0

REM ============================================================================
REM CONSTANTS
REM ============================================================================

MAX_LINES = 10000
MAX_LINE_LEN = 255
HEADER_LINES = 2
FOOTER_LINES = 2
TAB_SIZE = 4

REM Special key codes (must match terminal_io.zig runtime values)
KEY_UP = 328
KEY_DOWN = 336
KEY_LEFT = 331
KEY_RIGHT = 333
KEY_HOME = 327
KEY_END = 335
KEY_PGUP = 329
KEY_PGDN = 337
KEY_DELETE = 339
KEY_INSERT = 338
CONSTANT KEY_F1 = 315

REM Control key codes
CTRL_B = 2
CTRL_C = 3
CTRL_D = 4
CTRL_F = 6
CTRL_G = 7
CTRL_K = 11
CTRL_L = 12
CTRL_N = 14
CTRL_Q = 17
CTRL_R = 18
CTRL_S = 19
CTRL_V = 22
CTRL_X = 24
CTRL_Z = 26

REM ASCII codes
KEY_ENTER = 13
KEY_BACKSPACE = 8
KEY_TAB = 9
KEY_ESC = 27

REM ============================================================================
REM GLOBAL VARIABLES
REM ============================================================================

DIM lines$(MAX_LINES)
DIM line_count AS INTEGER
DIM cursor_x AS INTEGER
DIM cursor_y AS INTEGER
DIM view_top AS INTEGER
DIM modified AS INTEGER
DIM filename$ AS STRING
DIM clipboard$ AS STRING
DIM screen_width AS INTEGER
DIM screen_height AS INTEGER
DIM edit_height AS INTEGER
DIM quit_flag AS INTEGER
DIM status_msg$ AS STRING
DIM insert_mode AS INTEGER
DIM initialized AS INTEGER

REM ============================================================================
REM INITIALIZATION
REM ============================================================================

SUB init_editor()
    REM Initialize editor state
    line_count = 1
    lines$(0) = ""
    cursor_x = 0
    cursor_y = 0
    view_top = 0
    modified = 0
    filename$ = "untitled.bas"
    clipboard$ = ""
    quit_flag = 0
    insert_mode = 1
    initialized = 0
    status_msg$ = "Welcome to BASED! Press F1 for help"

    REM Detect terminal size dynamically (falls back to 80x24)
    screen_width = SCREENWIDTH
    screen_height = SCREENHEIGHT
    edit_height = screen_height - HEADER_LINES - FOOTER_LINES

    REM Check for command-line filename argument BEFORE entering raw mode
    IF COMMANDCOUNT > 1 THEN
        filename$ = COMMAND(1)
        CALL load_file(filename$)
    END IF

    REM Enable raw keyboard mode AFTER file loading
    KBRAW 1

    REM Switch to alternate screen buffer (like vim/nano) so quitting
    REM restores the user's original terminal content
    SCREEN_ALTERNATE

    REM Clear screen and hide cursor during initial draw
    CLS
    CURSOR_HIDE

    REM Mark as initialized
    initialized = 1
END SUB

SUB cleanup()
    REM Restore terminal state
    KBRAW 0
    CURSOR_SHOW
    COLOR 7, 0

    REM Switch back to main screen buffer — restores original terminal content
    SCREEN_MAIN

    PRINT "Thanks for using BASED!"
END SUB

REM ============================================================================
REM DISPLAY FUNCTIONS
REM ============================================================================

SUB draw_header()
    REM Draw title bar on row 0
    LOCATE 0, 0
    COLOR 15, 1

    DIM title$ AS STRING
    DIM mod_indicator$ AS STRING
    DIM right_text$ AS STRING
    DIM line_text$ AS STRING

    IF modified THEN
        mod_indicator$ = "[modified]"
    ELSE
        mod_indicator$ = "          "
    END IF

    title$ = " BASED - FasterBASIC Editor "
    right_text$ = mod_indicator$ + " " + filename$ + " "

    REM Build complete line with padding
    line_text$ = title$
    DIM i%
    FOR i = LEN(title$) TO screen_width - LEN(right_text$) - 1
        line_text$ = line_text$ + " "
    NEXT i
    line_text$ = line_text$ + right_text$

    WRSTR line_text$

    REM Draw separator line on row 1
    LOCATE 0, 1
    COLOR 7, 0
    line_text$ = ""
    FOR i = 0 TO screen_width - 1
        line_text$ = line_text$ + "="
    NEXT i
    WRSTR line_text$

    COLOR 7, 0
END SUB

SUB draw_line(line_num AS INTEGER, screen_row AS INTEGER)
    REM Draw a single line of code with line number
    DIM line_text$ AS STRING
    DIM line_str$ AS STRING
    DIM i%

    REM Build line number (5 chars + ": ")
    line_str$ = STR$(line_num + 1)
    DIM padding%
    padding = 5 - LEN(line_str$)
    line_text$ = ""
    FOR i = 0 TO padding - 1
        line_text$ = line_text$ + " "
    NEXT i
    line_text$ = line_text$ + line_str$ + ": "

    REM Add code content
    IF line_num < line_count THEN
        DIM visible_len%
        visible_len = screen_width - 8
        IF LEN(lines$(line_num)) > visible_len THEN
            line_text$ = line_text$ + LEFT$(lines$(line_num), visible_len)
        ELSE
            line_text$ = line_text$ + lines$(line_num)
        END IF
    END IF

    REM Pad to screen width
    FOR i = LEN(line_text$) TO screen_width - 1
        line_text$ = line_text$ + " "
    NEXT i

    REM Position and print the complete line
    LOCATE 0, screen_row
    COLOR 6, 0
    WRSTR LEFT$(line_text$, 7)
    COLOR 7, 0
    WRSTR MID$(line_text$, 8, screen_width - 7)
END SUB

SUB draw_editor()
    REM Draw all visible lines in the edit area
    DIM i%
    DIM screen_row%

    FOR i = 0 TO edit_height - 1
        screen_row = HEADER_LINES + i
        IF view_top + i < MAX_LINES THEN
            CALL draw_line(view_top + i, screen_row)
        END IF
    NEXT i
END SUB

SUB draw_status()
    REM Draw status/help bar at bottom
    DIM status_row%
    status_row = screen_height - 2
    DIM line_text$ AS STRING
    DIM i%

    REM Draw separator on status_row
    LOCATE 0, status_row
    COLOR 7, 0
    line_text$ = ""
    FOR i = 0 TO screen_width - 1
        line_text$ = line_text$ + "="
    NEXT i
    WRSTR line_text$

    REM Draw help line on status_row + 1
    LOCATE 0, status_row + 1
    COLOR 0, 7
    DIM help$ AS STRING
    help$ = " ^S=Save ^L=Load ^R=Run ^F=Format ^K=Kill ^D=Dup ^Q=Quit "
    line_text$ = help$
    FOR i = LEN(help$) TO screen_width - 1
        line_text$ = line_text$ + " "
    NEXT i
    WRSTR line_text$

    COLOR 7, 0
END SUB

SUB show_status_message(msg$ AS STRING)
    REM Display a temporary status message
    REM Skip if not initialized yet
    IF initialized = 0 THEN
        RETURN
    END IF

    status_msg$ = msg$

    DIM status_row%
    status_row = screen_height - 2
    DIM line_text$ AS STRING
    DIM i%

    BEGINPAINT
    LOCATE 0, status_row
    COLOR 0, 7

    line_text$ = " " + msg$
    FOR i = LEN(line_text$) TO screen_width - 1
        line_text$ = line_text$ + " "
    NEXT i
    WRSTR line_text$

    COLOR 7, 0
    ENDPAINT
END SUB

SUB refresh_screen()
    REM Redraw entire screen (batched for performance)
    BEGINPAINT
    CALL draw_header()
    CALL draw_editor()
    CALL draw_status()
    CALL position_cursor()
    ENDPAINT
END SUB

SUB position_cursor()
    REM Position terminal cursor at editor cursor location
    DIM screen_row%
    DIM screen_col%

    screen_row = HEADER_LINES + (cursor_y - view_top)
    screen_col = 8 + cursor_x

    REM Clamp to visible area
    IF screen_row < HEADER_LINES THEN screen_row = HEADER_LINES
    IF screen_row >= screen_height - FOOTER_LINES THEN
        screen_row = screen_height - FOOTER_LINES - 1
    END IF

    IF screen_col < 8 THEN screen_col = 8
    IF screen_col >= screen_width THEN screen_col = screen_width - 1

    CURSOR_SHOW
    LOCATE screen_col, screen_row
    FLUSH
END SUB

REM ============================================================================
REM NAVIGATION
REM ============================================================================

SUB move_cursor_left()
    IF cursor_x > 0 THEN
        cursor_x = cursor_x - 1
    ELSEIF cursor_y > 0 THEN
        cursor_y = cursor_y - 1
        cursor_x = LEN(lines$(cursor_y))
        CALL adjust_viewport()
    END IF
END SUB

SUB move_cursor_right()
    IF cursor_x < LEN(lines$(cursor_y)) THEN
        cursor_x = cursor_x + 1
    ELSEIF cursor_y < line_count - 1 THEN
        cursor_y = cursor_y + 1
        cursor_x = 0
        CALL adjust_viewport()
    END IF
END SUB

SUB move_cursor_up()
    IF cursor_y > 0 THEN
        cursor_y = cursor_y - 1
        CALL clamp_cursor_x()
        CALL adjust_viewport()
    END IF
END SUB

SUB move_cursor_down()
    IF cursor_y < line_count - 1 THEN
        cursor_y = cursor_y + 1
        CALL clamp_cursor_x()
        CALL adjust_viewport()
    END IF
END SUB

SUB move_cursor_home()
    cursor_x = 0
END SUB

SUB move_cursor_end()
    cursor_x = LEN(lines$(cursor_y))
END SUB

SUB move_page_up()
    DIM i%
    FOR i = 1 TO edit_height
        CALL move_cursor_up()
    NEXT i
END SUB

SUB move_page_down()
    DIM i%
    FOR i = 1 TO edit_height
        CALL move_cursor_down()
    NEXT i
END SUB

SUB clamp_cursor_x()
    DIM line_len%
    line_len = LEN(lines$(cursor_y))
    IF cursor_x > line_len THEN
        cursor_x = line_len
    END IF
END SUB

SUB adjust_viewport()
    REM Scroll viewport to keep cursor visible
    IF cursor_y < view_top THEN
        view_top = cursor_y
    END IF

    IF cursor_y >= view_top + edit_height THEN
        view_top = cursor_y - edit_height + 1
    END IF

    IF view_top < 0 THEN
        view_top = 0
    END IF
END SUB

REM ============================================================================
REM EDITING OPERATIONS
REM ============================================================================

SUB insert_char(ch AS INTEGER)
    REM Insert a character at cursor position
    DIM line$ AS STRING
    DIM left$ AS STRING
    DIM right$ AS STRING

    line$ = lines$(cursor_y)

    IF cursor_x = 0 THEN
        left$ = ""
        right$ = line$
    ELSEIF cursor_x >= LEN(line$) THEN
        left$ = line$
        right$ = ""
    ELSE
        left$ = LEFT$(line$, cursor_x)
        right$ = MID$(line$, cursor_x + 1)
    END IF

    lines$(cursor_y) = left$ + CHR$(ch) + right$
    cursor_x = cursor_x + 1
    modified = 1
END SUB

SUB delete_char_backspace()
    REM Delete character before cursor (backspace)
    IF cursor_x > 0 THEN
        DIM line$ AS STRING
        DIM left$ AS STRING
        DIM right$ AS STRING

        line$ = lines$(cursor_y)
        left$ = LEFT$(line$, cursor_x - 1)
        right$ = MID$(line$, cursor_x + 1)

        lines$(cursor_y) = left$ + right$
        cursor_x = cursor_x - 1
        modified = 1
    ELSEIF cursor_y > 0 THEN
        REM Join with previous line
        DIM prev_len%
        prev_len = LEN(lines$(cursor_y - 1))
        lines$(cursor_y - 1) = lines$(cursor_y - 1) + lines$(cursor_y)
        CALL delete_current_line()
        cursor_y = cursor_y - 1
        cursor_x = prev_len
        CALL adjust_viewport()
        modified = 1
    END IF
END SUB

SUB delete_char_forward()
    REM Delete character at cursor (delete key)
    DIM line$ AS STRING
    line$ = lines$(cursor_y)

    IF cursor_x < LEN(line$) THEN
        DIM left$ AS STRING
        DIM right$ AS STRING

        left$ = LEFT$(line$, cursor_x)
        right$ = MID$(line$, cursor_x + 2)

        lines$(cursor_y) = left$ + right$
        modified = 1
    ELSEIF cursor_y < line_count - 1 THEN
        REM Join with next line
        lines$(cursor_y) = lines$(cursor_y) + lines$(cursor_y + 1)

        REM Shift lines up
        DIM i%
        FOR i = cursor_y + 1 TO line_count - 2
            lines$(i) = lines$(i + 1)
        NEXT i

        line_count = line_count - 1
        modified = 1
    END IF
END SUB

SUB insert_new_line()
    REM Split line at cursor (Enter key)
    IF line_count >= MAX_LINES THEN
        CALL show_status_message("Error: Maximum lines reached")
        RETURN
    END IF

    DIM line$ AS STRING
    DIM left$ AS STRING
    DIM right$ AS STRING

    line$ = lines$(cursor_y)

    IF cursor_x = 0 THEN
        left$ = ""
        right$ = line$
    ELSEIF cursor_x >= LEN(line$) THEN
        left$ = line$
        right$ = ""
    ELSE
        left$ = LEFT$(line$, cursor_x)
        right$ = MID$(line$, cursor_x + 1)
    END IF

    REM Shift lines down
    DIM i%
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    lines$(cursor_y) = left$
    lines$(cursor_y + 1) = right$

    line_count = line_count + 1
    cursor_y = cursor_y + 1
    cursor_x = 0

    CALL adjust_viewport()
    modified = 1
END SUB

SUB delete_current_line()
    REM Delete the current line (Ctrl+K)
    IF line_count = 1 THEN
        REM Don't delete the last line, just clear it
        lines$(0) = ""
        cursor_x = 0
    ELSE
        REM Shift lines up
        DIM i%
        FOR i = cursor_y TO line_count - 2
            lines$(i) = lines$(i + 1)
        NEXT i

        line_count = line_count - 1

        REM Adjust cursor if at end
        IF cursor_y >= line_count THEN
            cursor_y = line_count - 1
        END IF
    END IF

    cursor_x = 0
    CALL clamp_cursor_x()
    modified = 1
END SUB

SUB duplicate_current_line()
    REM Duplicate the current line (Ctrl+D)
    IF line_count >= MAX_LINES THEN
        CALL show_status_message("Error: Maximum lines reached")
        RETURN
    END IF

    REM Shift lines down
    DIM i%
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    REM Copy current line
    lines$(cursor_y + 1) = lines$(cursor_y)

    line_count = line_count + 1
    cursor_y = cursor_y + 1

    CALL adjust_viewport()
    modified = 1
END SUB

SUB cut_line()
    REM Cut current line to clipboard (Ctrl+X)
    clipboard$ = lines$(cursor_y)
    CALL delete_current_line()
    CALL show_status_message("Line cut to clipboard")
END SUB

SUB copy_line()
    REM Copy current line to clipboard (Ctrl+C)
    clipboard$ = lines$(cursor_y)
    CALL show_status_message("Line copied to clipboard")
END SUB

SUB paste_line()
    REM Paste clipboard as new line (Ctrl+V)
    IF clipboard$ = "" THEN
        CALL show_status_message("Clipboard is empty")
        RETURN
    END IF

    IF line_count >= MAX_LINES THEN
        CALL show_status_message("Error: Maximum lines reached")
        RETURN
    END IF

    REM Shift lines down
    DIM i%
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    lines$(cursor_y + 1) = clipboard$
    line_count = line_count + 1
    cursor_y = cursor_y + 1

    CALL adjust_viewport()
    modified = 1
    CALL show_status_message("Line pasted from clipboard")
END SUB

REM ============================================================================
REM FILE OPERATIONS
REM ============================================================================

SUB load_file(fname$ AS STRING)
    REM Load a file from disk using SLURP for efficient whole-file reading
    DIM content$ AS STRING
    DIM line_start%, char_pos%, content_len%

    REM Read entire file into memory
    content$ = SLURP(fname$)

    REM Parse content into lines array
    line_count = 0
    line_start% = 1
    content_len% = LEN(content$)

    FOR char_pos% = 1 TO content_len%
        IF line_count >= MAX_LINES THEN
            CALL show_status_message("Warning: File truncated at max lines")
            EXIT FOR
        END IF

        REM Check for newline (CHR$(10) or CHR$(13))
        IF MID$(content$, char_pos%, 1) = CHR$(10) OR MID$(content$, char_pos%, 1) = CHR$(13) THEN
            REM Extract line from line_start to char_pos-1
            IF char_pos% > line_start% THEN
                lines$(line_count) = MID$(content$, line_start%, char_pos% - line_start%)
            ELSE
                lines$(line_count) = ""
            END IF
            line_count = line_count + 1

            REM Handle CR+LF (skip LF if we just read CR)
            IF MID$(content$, char_pos%, 1) = CHR$(13) AND char_pos% < content_len% THEN
                IF MID$(content$, char_pos% + 1, 1) = CHR$(10) THEN
                    char_pos% = char_pos% + 1
                END IF
            END IF

            line_start% = char_pos% + 1
        END IF
    NEXT char_pos%

    REM Handle last line if no trailing newline
    IF line_start% <= content_len% AND line_count < MAX_LINES THEN
        lines$(line_count) = MID$(content$, line_start%, content_len% - line_start% + 1)
        line_count = line_count + 1
    END IF

    REM Ensure at least one empty line
    IF line_count = 0 THEN
        line_count = 1
        lines$(0) = ""
    END IF

    filename$ = fname$
    cursor_x = 0
    cursor_y = 0
    view_top = 0
    modified = 0

    CALL show_status_message("Loaded: " + fname$)
END SUB

SUB save_file(fname$ AS STRING)
    REM Save buffer to disk using SPIT for efficient whole-file writing
    DIM content$ AS STRING
    DIM i%

    REM Build content string from lines array
    content$ = ""
    FOR i% = 0 TO line_count - 1
        content$ = content$ + lines$(i%)
        IF i% < line_count - 1 THEN
            content$ = content$ + CHR$(10)
        END IF
    NEXT i%

    REM Write entire file at once
    SPIT fname$, content$

    filename$ = fname$
    modified = 0

    CALL show_status_message("Saved: " + fname$)
END SUB

SUB prompt_save()
    REM Prompt to save before quit/new
    IF NOT modified THEN
        RETURN
    END IF

    CALL show_status_message("Save changes? (Y/N)")
    CALL position_cursor()

    DIM response%
    response% = KBGET

    IF response% = 89 OR response% = 121 THEN
        REM 'Y' or 'y'
        CALL save_file(filename$)
    END IF
END SUB

SUB prompt_filename_load()
    REM Simple filename input for load
    REM For now, we'll just load the default filename
    REM A full implementation would use a text input dialog

    CALL show_status_message("Enter filename (or ESC to cancel): ")

    DIM fname$ AS STRING
    DIM ch%
    fname$ = ""

    DO
        CALL position_cursor()
        ch% = KBGET

        IF ch% = KEY_ESC THEN
            CALL show_status_message("Load cancelled")
            RETURN
        ELSEIF ch% = KEY_ENTER THEN
            EXIT DO
        ELSEIF ch% = KEY_BACKSPACE THEN
            IF LEN(fname$) > 0 THEN
                fname$ = LEFT$(fname$, LEN(fname$) - 1)
            END IF
        ELSEIF ch% >= 32 AND ch% <= 126 THEN
            fname$ = fname$ + CHR$(ch%)
        END IF

        CALL show_status_message("Enter filename: " + fname$ + "_")
    LOOP

    IF fname$ <> "" THEN
        CALL load_file(fname$)
    ELSE
        CALL show_status_message("No filename entered")
    END IF
END SUB

REM ============================================================================
REM BUILD & RUN
REM ============================================================================

SUB build_and_run()
    REM Save current file and build with FBC
    CALL show_status_message("Building and running...")

    REM Save first
    CALL save_file(filename$)

    REM Switch to normal terminal mode temporarily
    KBRAW 0
    CURSOR_SHOW
    CLS

    REM Build command
    PRINT "Compiling "; filename$; "..."
    PRINT

    REM TODO: Actually invoke the compiler
    REM For now, just display a message
    PRINT "Note: Actual compilation not yet implemented"
    PRINT "You would run: fbc "; filename$
    PRINT
    PRINT "Press any key to return to editor..."

    DIM dummy%
    dummy% = KBGET

    REM Return to raw mode and redraw
    KBRAW 1
    CURSOR_HIDE
    CALL refresh_screen()
END SUB

SUB build_only()
    REM Build without running
    CALL show_status_message("Building...")

    REM Save first
    CALL save_file(filename$)

    REM Similar to build_and_run but without execution
    CALL show_status_message("Build complete (not implemented yet)")
END SUB

REM ============================================================================
REM CODE FORMATTING
REM ============================================================================

SUB format_buffer()
    REM Format all lines in buffer (Ctrl+F)
    DIM i%

    FOR i = 0 TO line_count - 1
        CALL format_line(i)
    NEXT i

    modified = 1
    CALL show_status_message("Code formatted")
END SUB

SUB format_line(line_num AS INTEGER)
    REM Format a single line (basic implementation)
    DIM line$ AS STRING
    DIM formatted$ AS STRING

    line$ = lines$(line_num)

    REM Trim leading/trailing spaces
    formatted$ = LTRIM$(RTRIM$(line$))

    REM TODO: Add keyword capitalization
    REM TODO: Add auto-indentation based on block structure

    lines$(line_num) = formatted$
END SUB

REM ============================================================================
REM INPUT HANDLING
REM ============================================================================

SUB handle_key(key AS INTEGER)
    REM Main keyboard input handler

    REM Control keys
    IF key = CTRL_Q THEN
        CALL prompt_save()
        quit_flag = 1
    ELSEIF key = CTRL_S THEN
        CALL save_file(filename$)
    ELSEIF key = CTRL_L THEN
        CALL prompt_filename_load()
    ELSEIF key = CTRL_K THEN
        CALL delete_current_line()
    ELSEIF key = CTRL_D THEN
        CALL duplicate_current_line()
    ELSEIF key = CTRL_X THEN
        CALL cut_line()
    ELSEIF key = CTRL_C THEN
        CALL copy_line()
    ELSEIF key = CTRL_V THEN
        CALL paste_line()
    ELSEIF key = CTRL_R THEN
        CALL build_and_run()
    ELSEIF key = CTRL_B THEN
        CALL build_only()
    ELSEIF key = CTRL_F THEN
        CALL format_buffer()

    REM Special keys
    ELSEIF key = KEY_UP THEN
        CALL move_cursor_up()
    ELSEIF key = KEY_DOWN THEN
        CALL move_cursor_down()
    ELSEIF key = KEY_LEFT THEN
        CALL move_cursor_left()
    ELSEIF key = KEY_RIGHT THEN
        CALL move_cursor_right()
    ELSEIF key = KEY_HOME THEN
        CALL move_cursor_home()
    ELSEIF key = KEY_END THEN
        CALL move_cursor_end()
    ELSEIF key = KEY_PGUP THEN
        CALL move_page_up()
    ELSEIF key = KEY_PGDN THEN
        CALL move_page_down()
    ELSEIF key = KEY_DELETE THEN
        CALL delete_char_forward()

    REM Editing keys
    ELSEIF key = KEY_ENTER THEN
        CALL insert_new_line()
    ELSEIF key = KEY_BACKSPACE THEN
        CALL delete_char_backspace()
    ELSEIF key = KEY_TAB THEN
        REM Insert spaces for tab
        DIM i%
        FOR i = 1 TO TAB_SIZE
            CALL insert_char(32)
        NEXT i

    REM Printable characters
    ELSEIF key >= 32 AND key < 127 THEN
        CALL insert_char(key)
    END IF
END SUB

REM ============================================================================
REM MAIN PROGRAM
REM ============================================================================

SUB main()
    CALL init_editor()

    REM Draw initial screen once
    CALL refresh_screen()

    REM Main event loop - KBGET blocks until key is pressed
    DIM key%
    DIM needs_full_redraw AS INTEGER
    DIM needs_content_redraw AS INTEGER

    DO
        REM Wait for keypress (blocks, doesn't spin)
        key% = KBGET

        REM Determine what kind of update we need
        needs_full_redraw = 0
        needs_content_redraw = 0

        REM Navigation keys - just move cursor, no redraw
        IF key% = KEY_UP OR key% = KEY_DOWN OR key% = KEY_LEFT OR key% = KEY_RIGHT OR key% = KEY_HOME OR key% = KEY_END THEN
            CALL handle_key(key%)
            REM Only redraw if modified flag changed or viewport scrolled
            REM For now, just reposition cursor
        REM File operations need full redraw
        ELSEIF key% = CTRL_S OR key% = CTRL_L THEN
            CALL handle_key(key%)
            needs_full_redraw = 1
        REM Editing operations need content redraw
        ELSEIF key% = CTRL_K OR key% = CTRL_D OR key% = KEY_ENTER OR key% = KEY_BACKSPACE OR key% = KEY_DELETE OR (key% >= 32 AND key% < 127) THEN
            CALL handle_key(key%)
            needs_content_redraw = 1
        REM Other keys
        ELSE
            CALL handle_key(key%)
            needs_full_redraw = 1
        END IF

        REM Redraw based on what changed
        IF needs_full_redraw = 1 THEN
            CALL refresh_screen()
        ELSEIF needs_content_redraw = 1 THEN
            BEGINPAINT
            CALL draw_editor()
            CALL draw_status()
            CALL position_cursor()
            ENDPAINT
        ELSE
            REM Just move cursor for navigation
            CALL position_cursor()
        END IF
    LOOP UNTIL quit_flag

    CALL cleanup()
END SUB

REM Start the editor
CALL main()
