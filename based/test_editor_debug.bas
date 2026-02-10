REM BASED Editor - Debug Version with Logging
REM This version logs all operations to debug.log for troubleshooting

REM ============================================================================
REM CONSTANTS
REM ============================================================================

CONST MAX_LINES = 1000
CONST MAX_LINE_LEN = 255
CONST HEADER_LINES = 2
CONST FOOTER_LINES = 2
CONST TAB_SIZE = 4

REM Key codes
CONST KEY_UP = 328
CONST KEY_DOWN = 336
CONST KEY_LEFT = 331
CONST KEY_RIGHT = 333
CONST KEY_HOME = 327
CONST KEY_END = 335
CONST KEY_PGUP = 329
CONST KEY_PGDN = 337
CONST KEY_DELETE = 339
CONST KEY_BACKSPACE = 8
CONST KEY_ENTER = 13
CONST KEY_TAB = 9
CONST KEY_ESC = 27

REM Control keys (Ctrl+letter)
CONST CTRL_Q = 17
CONST CTRL_S = 19
CONST CTRL_L = 12
CONST CTRL_K = 11
CONST CTRL_D = 4

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
DIM screen_width AS INTEGER
DIM screen_height AS INTEGER
DIM edit_height AS INTEGER
DIM quit_flag AS INTEGER

REM Debug log file handle
DIM log_handle AS INTEGER

REM ============================================================================
REM DEBUG LOGGING
REM ============================================================================

SUB log_open()
    OPEN "debug.log" FOR OUTPUT AS #1
    log_handle = 1
    PRINT #log_handle, "=== BASED Debug Log Started ==="
END SUB

SUB log_msg(msg$ AS STRING)
    PRINT #log_handle, msg$
END SUB

SUB log_state()
    PRINT #log_handle, "STATE: cursor_y="; cursor_y; " cursor_x="; cursor_x; " view_top="; view_top; " line_count="; line_count
END SUB

SUB log_close()
    PRINT #log_handle, "=== Debug Log Ended ==="
    CLOSE #log_handle
END SUB

REM ============================================================================
REM INITIALIZATION
REM ============================================================================

SUB init_editor()
    log_open()
    log_msg("init_editor: Starting...")

    screen_width = 80
    screen_height = 24
    edit_height = screen_height - HEADER_LINES - FOOTER_LINES

    log_msg("init_editor: screen_width=" + STR$(screen_width))
    log_msg("init_editor: screen_height=" + STR$(screen_height))
    log_msg("init_editor: edit_height=" + STR$(edit_height))

    REM Initialize with one empty line
    line_count = 1
    lines$(0) = ""
    cursor_x = 0
    cursor_y = 0
    view_top = 0
    modified = 0
    quit_flag = 0

    REM Check for command-line filename
    IF COMMANDCOUNT() >= 1 THEN
        filename$ = COMMAND(1)
        log_msg("init_editor: Loading file from command line: " + filename$)
        CALL load_file(filename$)
    ELSE
        filename$ = "untitled.bas"
        log_msg("init_editor: No file specified, using: " + filename$)
    END IF

    REM Enter raw mode and setup screen
    log_msg("init_editor: Entering raw mode...")
    KBRAW 1

    CLS
    CURSOR_HIDE

    log_msg("init_editor: Complete. Drawing initial screen...")
    log_state()
END SUB

SUB cleanup()
    log_msg("cleanup: Starting...")
    KBRAW 0
    CURSOR_SHOW
    CLS
    LOCATE 0, 0
    PRINT "Thanks for using BASED! (Debug log saved to debug.log)"
    log_close()
END SUB

REM ============================================================================
REM DISPLAY
REM ============================================================================

SUB draw_header()
    log_msg("draw_header: Drawing title bar")

    LOCATE 0, 0
    COLOR 15, 1

    DIM title$ AS STRING
    DIM mod$ AS STRING
    DIM spaces$ AS STRING
    DIM i%

    title$ = " BASED - " + filename$
    IF modified = 1 THEN
        mod$ = " [modified]"
    ELSE
        mod$ = ""
    END IF

    PRINT title$ + mod$;

    REM Pad rest of line
    FOR i = LEN(title$ + mod$) TO screen_width - 1
        PRINT " ";
    NEXT i

    REM Draw separator
    LOCATE 0, 1
    COLOR 7, 0
    FOR i = 0 TO screen_width - 1
        PRINT "-";
    NEXT i
END SUB

SUB draw_line(line_num AS INTEGER, screen_row AS INTEGER)
    DIM line_text$ AS STRING
    DIM i%

    REM Build line number (5 chars)
    line_text$ = STR$(line_num + 1)
    DIM padding%
    padding = 5 - LEN(line_text$)
    FOR i = 0 TO padding - 1
        line_text$ = " " + line_text$
    NEXT i
    line_text$ = line_text$ + ": "

    REM Add content
    IF line_num < line_count THEN
        line_text$ = line_text$ + lines$(line_num)
    END IF

    REM Pad to screen width
    FOR i = LEN(line_text$) TO screen_width - 1
        line_text$ = line_text$ + " "
    NEXT i

    REM Draw the line
    LOCATE 0, screen_row
    COLOR 6, 0
    PRINT LEFT$(line_text$, 7);
    COLOR 7, 0
    PRINT MID$(line_text$, 8, screen_width - 7)
END SUB

SUB draw_editor()
    DIM i%
    DIM screen_row%

    FOR i = 0 TO edit_height - 1
        screen_row = HEADER_LINES + i
        IF view_top + i < line_count THEN
            CALL draw_line(view_top + i, screen_row)
        ELSE
            REM Draw empty line
            LOCATE 0, screen_row
            COLOR 7, 0
            DIM j%
            FOR j = 0 TO screen_width - 1
                PRINT " ";
            NEXT j
        END IF
    NEXT i
END SUB

SUB draw_status()
    DIM status_row%
    DIM i%

    status_row = screen_height - 2

    REM Separator
    LOCATE 0, status_row
    COLOR 7, 0
    FOR i = 0 TO screen_width - 1
        PRINT "=";
    NEXT i

    REM Help line
    LOCATE 0, status_row + 1
    COLOR 0, 7
    DIM help$ AS STRING
    help$ = " Arrow=Move ^S=Save ^Q=Quit ^K=Kill ^D=Dup "
    PRINT help$;
    FOR i = LEN(help$) TO screen_width - 1
        PRINT " ";
    NEXT i
END SUB

SUB refresh_screen()
    CALL draw_header()
    CALL draw_editor()
    CALL draw_status()
    CALL position_cursor()
END SUB

SUB position_cursor()
    DIM screen_row%
    DIM screen_col%

    screen_row = HEADER_LINES + (cursor_y - view_top)
    screen_col = 8 + cursor_x

    log_msg("position_cursor: screen_row=" + STR$(screen_row) + " screen_col=" + STR$(screen_col))

    CURSOR_SHOW
    LOCATE screen_col, screen_row
END SUB

REM ============================================================================
REM CURSOR MOVEMENT
REM ============================================================================

SUB move_cursor_up()
    log_msg("move_cursor_up: Before - cursor_y=" + STR$(cursor_y) + " view_top=" + STR$(view_top))

    IF cursor_y > 0 THEN
        cursor_y = cursor_y - 1
        CALL adjust_viewport()
    END IF

    log_msg("move_cursor_up: After - cursor_y=" + STR$(cursor_y) + " view_top=" + STR$(view_top))
END SUB

SUB move_cursor_down()
    log_msg("move_cursor_down: Before - cursor_y=" + STR$(cursor_y) + " view_top=" + STR$(view_top))

    IF cursor_y < line_count - 1 THEN
        cursor_y = cursor_y + 1
        CALL adjust_viewport()
    END IF

    log_msg("move_cursor_down: After - cursor_y=" + STR$(cursor_y) + " view_top=" + STR$(view_top))
END SUB

SUB move_cursor_left()
    IF cursor_x > 0 THEN
        cursor_x = cursor_x - 1
    END IF
END SUB

SUB move_cursor_right()
    IF cursor_x < LEN(lines$(cursor_y)) THEN
        cursor_x = cursor_x + 1
    END IF
END SUB

SUB move_cursor_home()
    cursor_x = 0
END SUB

SUB move_cursor_end()
    cursor_x = LEN(lines$(cursor_y))
END SUB

SUB adjust_viewport()
    log_msg("adjust_viewport: Before - view_top=" + STR$(view_top) + " cursor_y=" + STR$(cursor_y) + " edit_height=" + STR$(edit_height))

    IF cursor_y < view_top THEN
        view_top = cursor_y
        log_msg("adjust_viewport: Scrolled up, new view_top=" + STR$(view_top))
    END IF

    IF cursor_y >= view_top + edit_height THEN
        view_top = cursor_y - edit_height + 1
        log_msg("adjust_viewport: Scrolled down, new view_top=" + STR$(view_top))
    END IF

    IF view_top < 0 THEN
        view_top = 0
    END IF

    log_msg("adjust_viewport: After - view_top=" + STR$(view_top))
END SUB

REM ============================================================================
REM EDITING
REM ============================================================================

SUB insert_char(ch AS INTEGER)
    DIM line$ AS STRING
    DIM left$ AS STRING
    DIM right$ AS STRING

    log_msg("insert_char: ch=" + STR$(ch) + " cursor_x=" + STR$(cursor_x))

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

    log_msg("insert_char: New line: " + lines$(cursor_y))
END SUB

SUB delete_char_backspace()
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
    END IF
END SUB

SUB delete_current_line()
    log_msg("delete_current_line: Deleting line " + STR$(cursor_y))

    IF line_count = 1 THEN
        lines$(0) = ""
        cursor_x = 0
        modified = 1
        RETURN
    END IF

    DIM i%
    FOR i = cursor_y TO line_count - 2
        lines$(i) = lines$(i + 1)
    NEXT i

    line_count = line_count - 1

    IF cursor_y >= line_count THEN
        cursor_y = line_count - 1
    END IF

    cursor_x = 0
    modified = 1
END SUB

SUB duplicate_current_line()
    log_msg("duplicate_current_line: Duplicating line " + STR$(cursor_y))

    IF line_count >= MAX_LINES THEN
        RETURN
    END IF

    DIM i%
    FOR i = line_count TO cursor_y + 2 STEP -1
        lines$(i) = lines$(i - 1)
    NEXT i

    lines$(cursor_y + 1) = lines$(cursor_y)
    line_count = line_count + 1
    cursor_y = cursor_y + 1
    modified = 1
END SUB

REM ============================================================================
REM FILE OPERATIONS
REM ============================================================================

SUB load_file(fname$ AS STRING)
    log_msg("load_file: Loading " + fname$)

    DIM content$ AS STRING
    content$ = SLURP(fname$)

    IF LEN(content$) = 0 THEN
        log_msg("load_file: File empty or not found")
        RETURN
    END IF

    REM Parse into lines
    line_count = 0
    DIM pos%
    DIM line_start%
    line_start = 1

    FOR pos = 1 TO LEN(content$)
        IF MID$(content$, pos, 1) = CHR$(10) OR MID$(content$, pos, 1) = CHR$(13) THEN
            IF pos > line_start THEN
                lines$(line_count) = MID$(content$, line_start, pos - line_start)
            ELSE
                lines$(line_count) = ""
            END IF
            line_count = line_count + 1

            REM Skip CR+LF
            IF MID$(content$, pos, 1) = CHR$(13) AND pos < LEN(content$) THEN
                IF MID$(content$, pos + 1, 1) = CHR$(10) THEN
                    pos = pos + 1
                END IF
            END IF

            line_start = pos + 1
        END IF
    NEXT pos

    REM Handle last line
    IF line_start <= LEN(content$) THEN
        lines$(line_count) = MID$(content$, line_start)
        line_count = line_count + 1
    END IF

    IF line_count = 0 THEN
        line_count = 1
        lines$(0) = ""
    END IF

    cursor_x = 0
    cursor_y = 0
    view_top = 0
    modified = 0

    log_msg("load_file: Loaded " + STR$(line_count) + " lines")
END SUB

SUB save_file(fname$ AS STRING)
    log_msg("save_file: Saving to " + fname$)

    DIM content$ AS STRING
    DIM i%

    content$ = ""
    FOR i = 0 TO line_count - 1
        content$ = content$ + lines$(i) + CHR$(10)
    NEXT i

    SPIT fname$, content$
    modified = 0

    log_msg("save_file: Saved " + STR$(line_count) + " lines")
END SUB

REM ============================================================================
REM INPUT HANDLING
REM ============================================================================

SUB handle_key(key AS INTEGER)
    log_msg("handle_key: key=" + STR$(key))

    IF key = CTRL_Q THEN
        log_msg("handle_key: CTRL_Q - Quit")
        quit_flag = 1
    ELSEIF key = CTRL_S THEN
        log_msg("handle_key: CTRL_S - Save")
        CALL save_file(filename$)
    ELSEIF key = CTRL_K THEN
        log_msg("handle_key: CTRL_K - Kill line")
        CALL delete_current_line()
    ELSEIF key = CTRL_D THEN
        log_msg("handle_key: CTRL_D - Duplicate line")
        CALL duplicate_current_line()
    ELSEIF key = KEY_UP THEN
        log_msg("handle_key: KEY_UP")
        CALL move_cursor_up()
    ELSEIF key = KEY_DOWN THEN
        log_msg("handle_key: KEY_DOWN")
        CALL move_cursor_down()
    ELSEIF key = KEY_LEFT THEN
        CALL move_cursor_left()
    ELSEIF key = KEY_RIGHT THEN
        CALL move_cursor_right()
    ELSEIF key = KEY_HOME THEN
        CALL move_cursor_home()
    ELSEIF key = KEY_END THEN
        CALL move_cursor_end()
    ELSEIF key = KEY_BACKSPACE THEN
        CALL delete_char_backspace()
    ELSEIF key >= 32 AND key < 127 THEN
        CALL insert_char(key)
    END IF
END SUB

REM ============================================================================
REM MAIN
REM ============================================================================

SUB main()
    CALL init_editor()
    CALL refresh_screen()

    DIM key%
    DIM loop_count%
    loop_count = 0

    DO
        key = KBGET
        loop_count = loop_count + 1

        log_msg("=== LOOP " + STR$(loop_count) + " ===")
        log_state()

        CALL handle_key(key)

        log_msg("After handle_key:")
        log_state()

        log_msg("Redrawing editor content...")
        CALL draw_editor()
        CALL draw_status()
        CALL position_cursor()

    LOOP UNTIL quit_flag

    CALL cleanup()
END SUB

CALL main()
