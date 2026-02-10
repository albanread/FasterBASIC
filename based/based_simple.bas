REM BASED - BASIC Editor for FasterBASIC (Simplified Version)
REM A full-screen terminal editor - without file I/O for initial testing
REM Version 0.9

REM ============================================================================
REM CONSTANTS
REM ============================================================================

CONSTANT MAX_LINES = 1000
CONSTANT MAX_LINE_LEN = 255
CONSTANT HEADER_LINES = 2
CONSTANT FOOTER_LINES = 2
CONSTANT TAB_SIZE = 4

REM Special key codes (returned by KBGET for non-ASCII keys)
CONSTANT KEY_UP = 256
CONSTANT KEY_DOWN = 257
CONSTANT KEY_LEFT = 258
CONSTANT KEY_RIGHT = 259
CONSTANT KEY_HOME = 260
CONSTANT KEY_END = 261
CONSTANT KEY_PGUP = 262
CONSTANT KEY_PGDN = 263
CONSTANT KEY_DELETE = 264

REM Control key codes
CONSTANT CTRL_D = 4
CONSTANT CTRL_K = 11
CONSTANT CTRL_Q = 17

REM ASCII codes
CONSTANT KEY_ENTER = 13
CONSTANT KEY_BACKSPACE = 8
CONSTANT KEY_TAB = 9
CONSTANT KEY_ESC = 27

REM ============================================================================
REM GLOBAL VARIABLES
REM ============================================================================

DIM lines$(MAX_LINES)
DIM line_count AS INTEGER
DIM cursor_x AS INTEGER
DIM cursor_y AS INTEGER
DIM view_top AS INTEGER
DIM quit_flag AS INTEGER
DIM screen_width AS INTEGER
DIM screen_height AS INTEGER
DIM edit_height AS INTEGER

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
    quit_flag = 0

    REM Get terminal size (assume 80x24)
    screen_width = 80
    screen_height = 24
    edit_height = screen_height - HEADER_LINES - FOOTER_LINES

    REM Enable raw keyboard mode
    KBRAW 1

    REM Clear screen and hide cursor during setup
    CLS
    CURSOR_HIDE
END SUB

SUB cleanup()
    REM Restore terminal state
    KBRAW 0
    CURSOR_SHOW
    CLS
    LOCATE 0, 0
    PRINT "Thanks for using BASED!"
END SUB

REM ============================================================================
REM DISPLAY FUNCTIONS
REM ============================================================================

SUB draw_header()
    REM Draw title bar
    LOCATE 0, 0
    COLOR 15, 1

    DIM title$ AS STRING
    title$ = " BASED - FasterBASIC Editor (Simple Version) "

    PRINT title$;

    DIM i AS INTEGER
    FOR i = LEN(title$) TO screen_width - 1
        PRINT " ";
    NEXT i

    REM Draw separator line
    LOCATE 0, 1
    FOR i = 0 TO screen_width - 1
        PRINT "-";
    NEXT i

    COLOR 7, 0
END SUB

SUB draw_line(line_num AS INTEGER, screen_row AS INTEGER)
    REM Draw a single line of code with line number
    LOCATE 0, screen_row

    REM Clear line first
    DIM i AS INTEGER
    FOR i = 0 TO screen_width - 1
        PRINT " ";
    NEXT i

    LOCATE 0, screen_row

    REM Line number (5 chars, cyan)
    COLOR 11, 0
    PRINT "    ";
    PRINT line_num + 1;
    PRINT ": ";

    REM Code text (white)
    COLOR 7, 0
    IF line_num < line_count THEN
        PRINT lines$(line_num);
    END IF
END SUB

SUB draw_editor()
    REM Draw all visible lines in the edit area
    DIM i AS INTEGER
    DIM screen_row AS INTEGER

    FOR i = 0 TO edit_height - 1
        screen_row = HEADER_LINES + i
        IF view_top + i < MAX_LINES THEN
            CALL draw_line(view_top + i, screen_row)
        END IF
    NEXT i
END SUB

SUB draw_status()
    REM Draw status/help bar at bottom
    DIM status_row AS INTEGER
    status_row = screen_height - 2

    LOCATE 0, status_row
    COLOR 0, 7

    REM Draw separator
    DIM i AS INTEGER
    FOR i = 0 TO screen_width - 1
        PRINT "-";
    NEXT i

    REM Draw help line
    LOCATE 0, status_row + 1
    DIM help$ AS STRING
    help$ = " Arrow keys=Navigate  ^K=Kill line  ^D=Dup line  ^Q=Quit "
    PRINT help$;
    FOR i = LEN(help$) TO screen_width - 1
        PRINT " ";
    NEXT i

    COLOR 7, 0
END SUB

SUB refresh_screen()
    REM Redraw entire screen
    CALL draw_header()
    CALL draw_editor()
    CALL draw_status()
    CALL position_cursor()
END SUB

SUB position_cursor()
    REM Position terminal cursor at editor cursor location
    DIM screen_row AS INTEGER
    DIM screen_col AS INTEGER

    screen_row = HEADER_LINES + (cursor_y - view_top)
    screen_col = 8 + cursor_x

    REM Clamp to visible area
    IF screen_row < HEADER_LINES THEN
        screen_row = HEADER_LINES
    END IF
    IF screen_row >= screen_height - FOOTER_LINES THEN
        screen_row = screen_height - FOOTER_LINES - 1
    END IF

    IF screen_col < 8 THEN
        screen_col = 8
    END IF
    IF screen_col >= screen_width THEN
        screen_col = screen_width - 1
    END IF

    CURSOR_SHOW
    LOCATE screen_col, screen_row
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
    DIM i AS INTEGER
    FOR i = 1 TO edit_height
        IF cursor_y > 0 THEN
            cursor_y = cursor_y - 1
            CALL clamp_cursor_x()
            CALL adjust_viewport()
        END IF
    NEXT i
END SUB

SUB move_page_down()
    DIM i AS INTEGER
    FOR i = 1 TO edit_height
        IF cursor_y < line_count - 1 THEN
            cursor_y = cursor_y + 1
            CALL clamp_cursor_x()
            CALL adjust_viewport()
        END IF
    NEXT i
END SUB

SUB clamp_cursor_x()
    DIM line_len AS INTEGER
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
        lines$(cursor_y) = CHR$(ch) + line$
    ELSEIF cursor_x >= LEN(line$) THEN
        lines$(cursor_y) = line$ + CHR$(ch)
    ELSE
        left$ = LEFT$(line$, cursor_x)
        right$ = MID$(line$, cursor_x + 1)
        lines$(cursor_y) = left$ + CHR$(ch) + right$
    END IF

    cursor_x = cursor_x + 1
END SUB

SUB delete_char_backspace()
    REM Delete character before cursor (backspace)
    IF cursor_x > 0 THEN
        DIM line$ AS STRING
        DIM left$ AS STRING
        DIM right$ AS STRING

        line$ = lines$(cursor_y)
        left$ = LEFT$(line$, cursor_x - 1)

        IF cursor_x < LEN(line$) THEN
            right$ = MID$(line$, cursor_x + 1)
            lines$(cursor_y) = left$ + right$
        ELSE
            lines$(cursor_y) = left$
        END IF

        cursor_x = cursor_x - 1
    ELSEIF cursor_y > 0 THEN
        REM Join with previous line
        DIM prev_len AS INTEGER
        prev_len = LEN(lines$(cursor_y - 1))
        lines$(cursor_y - 1) = lines$(cursor_y - 1) + lines$(cursor_y)
        CALL delete_current_line()
        cursor_y = cursor_y - 1
        cursor_x = prev_len
        CALL adjust_viewport()
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

        IF cursor_x + 1 < LEN(line$) THEN
            right$ = MID$(line$, cursor_x + 2)
            lines$(cursor_y) = left$ + right$
        ELSE
            lines$(cursor_y) = left$
        END IF
    ELSEIF cursor_y < line_count - 1 THEN
        REM Join with next line
        lines$(cursor_y) = lines$(cursor_y) + lines$(cursor_y + 1)

        REM Shift lines up
        DIM i AS INTEGER
        FOR i = cursor_y + 1 TO line_count - 2
            lines$(i) = lines$(i + 1)
        NEXT i

        line_count = line_count - 1
    END IF
END SUB

SUB insert_new_line()
    REM Split line at cursor (Enter key)
    IF line_count >= MAX_LINES THEN
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
    DIM i AS INTEGER
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    lines$(cursor_y) = left$
    lines$(cursor_y + 1) = right$

    line_count = line_count + 1
    cursor_y = cursor_y + 1
    cursor_x = 0

    CALL adjust_viewport()
END SUB

SUB delete_current_line()
    REM Delete the current line (Ctrl+K)
    IF line_count = 1 THEN
        REM Do not delete the last line, just clear it
        lines$(0) = ""
        cursor_x = 0
    ELSE
        REM Shift lines up
        DIM i AS INTEGER
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
END SUB

SUB duplicate_current_line()
    REM Duplicate the current line (Ctrl+D)
    IF line_count >= MAX_LINES THEN
        RETURN
    END IF

    REM Shift lines down
    DIM i AS INTEGER
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    REM Copy current line
    lines$(cursor_y + 1) = lines$(cursor_y)

    line_count = line_count + 1
    cursor_y = cursor_y + 1

    CALL adjust_viewport()
END SUB

REM ============================================================================
REM INPUT HANDLING
REM ============================================================================

SUB handle_key(key AS INTEGER)
    REM Main keyboard input handler

    REM Control keys
    IF key = CTRL_Q THEN
        quit_flag = 1
    ELSEIF key = CTRL_K THEN
        CALL delete_current_line()
    ELSEIF key = CTRL_D THEN
        CALL duplicate_current_line()

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
        DIM i AS INTEGER
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

    REM Draw initial screen
    CALL refresh_screen()

    REM Main event loop
    DIM key AS INTEGER

    DO
        CALL position_cursor()
        key = KBGET()
        CALL handle_key(key)

        REM Redraw editor area and status
        CALL draw_editor()
        CALL draw_status()
    LOOP UNTIL quit_flag <> 0

    CALL cleanup()
END SUB

REM Start the editor
CALL main()
