REM Minimal Editor Test - Shows what's happening
REM Displays cursor/viewport state on screen so you can see the problem

CONST MAX_LINES = 100
CONST HEADER_LINES = 2
CONST FOOTER_LINES = 4
CONST KEY_UP = 328
CONST KEY_DOWN = 336
CONST KEY_LEFT = 331
CONST KEY_RIGHT = 333
CONST CTRL_Q = 17

DIM lines$(MAX_LINES)
DIM line_count AS INTEGER
DIM cursor_x AS INTEGER
DIM cursor_y AS INTEGER
DIM view_top AS INTEGER
DIM screen_height AS INTEGER
DIM edit_height AS INTEGER
DIM quit_flag AS INTEGER

REM Initialize
screen_height = 24
edit_height = screen_height - HEADER_LINES - FOOTER_LINES
line_count = 10
DIM i%
FOR i = 0 TO 9
    lines$(i) = "Line " + STR$(i) + " - This is test content"
NEXT i
cursor_x = 0
cursor_y = 0
view_top = 0
quit_flag = 0

KBRAW 1
CLS
CURSOR_HIDE

REM Main loop
DO
    REM Draw header
    LOCATE 0, 0
    COLOR 15, 1
    PRINT "Minimal Editor Test - Press Ctrl+Q to quit";
    DIM j%
    FOR j = 41 TO 79
        PRINT " ";
    NEXT j

    LOCATE 0, 1
    COLOR 7, 0
    FOR j = 0 TO 79
        PRINT "-";
    NEXT j

    REM Draw content
    FOR i = 0 TO edit_height - 1
        DIM screen_row%
        screen_row = HEADER_LINES + i
        LOCATE 0, screen_row
        COLOR 7, 0

        IF view_top + i < line_count THEN
            REM Show line number and content
            DIM line_text$ AS STRING
            line_text$ = STR$(view_top + i) + ": " + lines$(view_top + i)
            PRINT line_text$;
            FOR j = LEN(line_text$) TO 79
                PRINT " ";
            NEXT j
        ELSE
            REM Empty line
            FOR j = 0 TO 79
                PRINT " ";
            NEXT j
        END IF
    NEXT i

    REM Draw debug status (4 lines)
    DIM status_row%
    status_row = screen_height - 4

    LOCATE 0, status_row
    COLOR 0, 7
    DIM info1$ AS STRING
    info1$ = " cursor_y=" + STR$(cursor_y) + " cursor_x=" + STR$(cursor_x)
    PRINT info1$;
    FOR j = LEN(info1$) TO 79
        PRINT " ";
    NEXT j

    LOCATE 0, status_row + 1
    DIM info2$ AS STRING
    info2$ = " view_top=" + STR$(view_top) + " edit_height=" + STR$(edit_height)
    PRINT info2$;
    FOR j = LEN(info2$) TO 79
        PRINT " ";
    NEXT j

    LOCATE 0, status_row + 2
    DIM info3$ AS STRING
    DIM screen_cursor_row%
    screen_cursor_row = HEADER_LINES + (cursor_y - view_top)
    info3$ = " screen_cursor_row=" + STR$(screen_cursor_row) + " line_count=" + STR$(line_count)
    PRINT info3$;
    FOR j = LEN(info3$) TO 79
        PRINT " ";
    NEXT j

    LOCATE 0, status_row + 3
    COLOR 7, 0
    DIM help$ AS STRING
    help$ = " UP/DOWN to move | Watch the values change | Ctrl+Q=Quit "
    PRINT help$;
    FOR j = LEN(help$) TO 79
        PRINT " ";
    NEXT j

    REM Position cursor
    screen_cursor_row = HEADER_LINES + (cursor_y - view_top)
    LOCATE cursor_x + 3, screen_cursor_row
    CURSOR_SHOW

    REM Wait for key
    DIM key%
    key = KBGET

    REM Handle key
    IF key = KEY_UP THEN
        IF cursor_y > 0 THEN
            cursor_y = cursor_y - 1
            REM Adjust viewport
            IF cursor_y < view_top THEN
                view_top = cursor_y
            END IF
        END IF
    ELSEIF key = KEY_DOWN THEN
        IF cursor_y < line_count - 1 THEN
            cursor_y = cursor_y + 1
            REM Adjust viewport
            IF cursor_y >= view_top + edit_height THEN
                view_top = cursor_y - edit_height + 1
            END IF
        END IF
    ELSEIF key = KEY_LEFT THEN
        IF cursor_x > 0 THEN
            cursor_x = cursor_x - 1
        END IF
    ELSEIF key = KEY_RIGHT THEN
        IF cursor_x < 20 THEN
            cursor_x = cursor_x + 1
        END IF
    ELSEIF key = CTRL_Q THEN
        quit_flag = 1
    END IF

LOOP UNTIL quit_flag

REM Cleanup
KBRAW 0
CURSOR_SHOW
CLS
LOCATE 0, 0
PRINT "Test complete!"
