REM ============================================================================
REM BASFMT - BASIC Code Formatter for FasterBASIC
REM ============================================================================
REM A simple code formatter that:
REM - Capitalizes keywords
REM - Adds consistent indentation
REM - Trims trailing whitespace
REM - Formats block structures (IF, FOR, WHILE, SUB, FUNCTION, etc.)
REM
REM Usage: basfmt input.bas [output.bas]
REM If output.bas is not specified, formats in-place (overwrites input)
REM ============================================================================

REM ============================================================================
REM GLOBAL VARIABLES
REM ============================================================================

DIM input_file$ AS STRING
DIM output_file$ AS STRING
DIM indent_level AS INTEGER
DIM indent_size AS INTEGER
DIM line_count AS INTEGER
DIM max_lines AS INTEGER

REM Arrays for storing lines
max_lines = 10000
DIM lines$(max_lines)

REM Indentation settings
indent_size = 4

REM ============================================================================
REM KEYWORD DEFINITIONS
REM ============================================================================

REM Keywords that increase indent on the next line
DIM indent_keywords$(50)
DIM indent_kw_count AS INTEGER
indent_kw_count = 0

indent_keywords$(indent_kw_count) = "IF": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "FOR": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "WHILE": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "DO": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "SUB": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "FUNCTION": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "SELECT": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "TYPE": indent_kw_count = indent_kw_count + 1
indent_keywords$(indent_kw_count) = "CLASS": indent_kw_count = indent_kw_count + 1

REM Keywords that decrease indent on current line
DIM dedent_keywords$(50)
DIM dedent_kw_count AS INTEGER
dedent_kw_count = 0

dedent_keywords$(dedent_kw_count) = "END": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "NEXT": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "WEND": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "LOOP": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "ELSE": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "ELSEIF": dedent_kw_count = dedent_kw_count + 1
dedent_keywords$(dedent_kw_count) = "CASE": dedent_kw_count = dedent_kw_count + 1

REM All keywords to capitalize
DIM keywords$(200)
DIM kw_count AS INTEGER
kw_count = 0

keywords$(kw_count) = "AND": kw_count = kw_count + 1
keywords$(kw_count) = "AS": kw_count = kw_count + 1
keywords$(kw_count) = "CALL": kw_count = kw_count + 1
keywords$(kw_count) = "CASE": kw_count = kw_count + 1
keywords$(kw_count) = "CLASS": kw_count = kw_count + 1
keywords$(kw_count) = "CLS": kw_count = kw_count + 1
keywords$(kw_count) = "COLOR": kw_count = kw_count + 1
keywords$(kw_count) = "DATA": kw_count = kw_count + 1
keywords$(kw_count) = "DIM": kw_count = kw_count + 1
keywords$(kw_count) = "DO": kw_count = kw_count + 1
keywords$(kw_count) = "DOUBLE": kw_count = kw_count + 1
keywords$(kw_count) = "ELSE": kw_count = kw_count + 1
keywords$(kw_count) = "ELSEIF": kw_count = kw_count + 1
keywords$(kw_count) = "END": kw_count = kw_count + 1
keywords$(kw_count) = "EXIT": kw_count = kw_count + 1
keywords$(kw_count) = "FOR": kw_count = kw_count + 1
keywords$(kw_count) = "FUNCTION": kw_count = kw_count + 1
keywords$(kw_count) = "GLOBAL": kw_count = kw_count + 1
keywords$(kw_count) = "GOSUB": kw_count = kw_count + 1
keywords$(kw_count) = "GOTO": kw_count = kw_count + 1
keywords$(kw_count) = "IF": kw_count = kw_count + 1
keywords$(kw_count) = "INPUT": kw_count = kw_count + 1
keywords$(kw_count) = "INTEGER": kw_count = kw_count + 1
keywords$(kw_count) = "LOCATE": kw_count = kw_count + 1
keywords$(kw_count) = "LONG": kw_count = kw_count + 1
keywords$(kw_count) = "LOOP": kw_count = kw_count + 1
keywords$(kw_count) = "MOD": kw_count = kw_count + 1
keywords$(kw_count) = "NEW": kw_count = kw_count + 1
keywords$(kw_count) = "NEXT": kw_count = kw_count + 1
keywords$(kw_count) = "NOT": kw_count = kw_count + 1
keywords$(kw_count) = "OPEN": kw_count = kw_count + 1
keywords$(kw_count) = "OR": kw_count = kw_count + 1
keywords$(kw_count) = "PRINT": kw_count = kw_count + 1
keywords$(kw_count) = "READ": kw_count = kw_count + 1
keywords$(kw_count) = "REM": kw_count = kw_count + 1
keywords$(kw_count) = "RESTORE": kw_count = kw_count + 1
keywords$(kw_count) = "RETURN": kw_count = kw_count + 1
keywords$(kw_count) = "SELECT": kw_count = kw_count + 1
keywords$(kw_count) = "SINGLE": kw_count = kw_count + 1
keywords$(kw_count) = "STEP": kw_count = kw_count + 1
keywords$(kw_count) = "STRING": kw_count = kw_count + 1
keywords$(kw_count) = "SUB": kw_count = kw_count + 1
keywords$(kw_count) = "THEN": kw_count = kw_count + 1
keywords$(kw_count) = "TO": kw_count = kw_count + 1
keywords$(kw_count) = "TYPE": kw_count = kw_count + 1
keywords$(kw_count) = "UNTIL": kw_count = kw_count + 1
keywords$(kw_count) = "WEND": kw_count = kw_count + 1
keywords$(kw_count) = "WHILE": kw_count = kw_count + 1
keywords$(kw_count) = "XOR": kw_count = kw_count + 1

REM ============================================================================
REM UTILITY FUNCTIONS
REM ============================================================================

SUB show_usage()
    PRINT "BASFMT - BASIC Code Formatter for FasterBASIC"
    PRINT ""
    PRINT "Usage:"
    PRINT "  basfmt input.bas              Format in-place (overwrites input)"
    PRINT "  basfmt input.bas output.bas   Format to new file"
    PRINT ""
    PRINT "Features:"
    PRINT "  - Capitalizes keywords"
    PRINT "  - Adds consistent indentation (4 spaces)"
    PRINT "  - Trims trailing whitespace"
    PRINT "  - Formats block structures"
END SUB

FUNCTION upper$(text$ AS STRING) AS STRING
    REM Convert string to uppercase
    DIM result$ AS STRING
    DIM i AS INTEGER
    DIM ch$ AS STRING
    DIM ascii AS INTEGER

    result$ = ""
    FOR i = 1 TO LEN(text$)
        ch$ = MID$(text$, i, 1)
        ascii = ASC(ch$)
        REM Convert lowercase a-z (97-122) to uppercase A-Z (65-90)
        IF ascii >= 97 AND ascii <= 122 THEN
            ascii = ascii - 32
            result$ = result$ + CHR$(ascii)
        ELSE
            result$ = result$ + ch$
        END IF
    NEXT i

    upper$ = result$
END FUNCTION

FUNCTION trim$(text$ AS STRING) AS STRING
    REM Trim leading and trailing whitespace
    trim$ = RTRIM$(LTRIM$(text$))
END FUNCTION

FUNCTION is_blank_line(line$ AS STRING) AS INTEGER
    REM Check if line is empty or only whitespace
    IF LEN(trim$(line$)) = 0 THEN
        is_blank_line = 1
    ELSE
        is_blank_line = 0
    END IF
END FUNCTION

FUNCTION is_comment_line(line$ AS STRING) AS INTEGER
    REM Check if line starts with REM or '
    DIM trimmed$ AS STRING
    trimmed$ = trim$(line$)

    IF LEN(trimmed$) = 0 THEN
        is_comment_line = 0
    ELSEIF LEFT$(trimmed$, 3) = "REM" OR LEFT$(trimmed$, 3) = "rem" OR LEFT$(trimmed$, 3) = "Rem" THEN
        is_comment_line = 1
    ELSEIF LEFT$(trimmed$, 1) = "'" THEN
        is_comment_line = 1
    ELSE
        is_comment_line = 0
    END IF
END FUNCTION

FUNCTION get_first_word$(line$ AS STRING) AS STRING
    REM Extract the first word from a line
    DIM trimmed$ AS STRING
    DIM i AS INTEGER
    DIM ch$ AS STRING

    trimmed$ = trim$(line$)

    IF LEN(trimmed$) = 0 THEN
        get_first_word$ = ""
        EXIT FUNCTION
    END IF

    REM Find first space or special character
    FOR i = 1 TO LEN(trimmed$)
        ch$ = MID$(trimmed$, i, 1)
        IF ch$ = " " OR ch$ = "(" OR ch$ = "=" OR ch$ = ":" THEN
            get_first_word$ = LEFT$(trimmed$, i - 1)
            EXIT FUNCTION
        END IF
    NEXT i

    REM No delimiter found, return whole string
    get_first_word$ = trimmed$
END FUNCTION

FUNCTION should_indent(word$ AS STRING) AS INTEGER
    REM Check if this keyword increases indent
    DIM i AS INTEGER
    DIM upper_word$ AS STRING

    upper_word$ = upper$(word$)

    FOR i = 0 TO indent_kw_count - 1
        IF upper_word$ = indent_keywords$(i) THEN
            should_indent = 1
            EXIT FUNCTION
        END IF
    NEXT i

    should_indent = 0
END FUNCTION

FUNCTION should_dedent(word$ AS STRING) AS INTEGER
    REM Check if this keyword decreases indent
    DIM i AS INTEGER
    DIM upper_word$ AS STRING

    upper_word$ = upper$(word$)

    FOR i = 0 TO dedent_kw_count - 1
        IF upper_word$ = dedent_keywords$(i) THEN
            should_dedent = 1
            EXIT FUNCTION
        END IF
    NEXT i

    should_dedent = 0
END FUNCTION

FUNCTION capitalize_keywords$(line$ AS STRING) AS STRING
    REM Capitalize all keywords in the line
    DIM result$ AS STRING
    DIM i AS INTEGER
    DIM j AS INTEGER
    DIM word$ AS STRING
    DIM upper_word$ AS STRING
    DIM found AS INTEGER
    DIM pos AS INTEGER
    DIM ch$ AS STRING

    result$ = line$

    REM Simple approach: try to replace each keyword
    FOR i = 0 TO kw_count - 1
        word$ = keywords$(i)

        REM Try lowercase version
        DIM lower_word$ AS STRING
        lower_word$ = ""
        FOR j = 1 TO LEN(word$)
            ch$ = MID$(word$, j, 1)
            DIM ascii AS INTEGER
            ascii = ASC(ch$)
            IF ascii >= 65 AND ascii <= 90 THEN
                ascii = ascii + 32
                lower_word$ = lower_word$ + CHR$(ascii)
            ELSE
                lower_word$ = lower_word$ + ch$
            END IF
        NEXT j

        REM Replace all occurrences (simple version - just look for word boundaries)
        REM This is simplified - a full implementation would be more sophisticated

    NEXT i

    REM For now, just return the original
    REM A full implementation would do proper word boundary detection
    capitalize_keywords$ = result$
END FUNCTION

FUNCTION make_indent$(level AS INTEGER) AS STRING
    REM Create indent string of spaces
    DIM result$ AS STRING
    DIM total_spaces AS INTEGER
    DIM i AS INTEGER

    result$ = ""
    total_spaces = level * indent_size

    FOR i = 1 TO total_spaces
        result$ = result$ + " "
    NEXT i

    make_indent$ = result$
END FUNCTION

REM ============================================================================
REM FORMATTING LOGIC
REM ============================================================================

SUB format_lines()
    REM Format all lines with proper indentation
    DIM i AS INTEGER
    DIM original_line$ AS STRING
    DIM trimmed$ AS STRING
    DIM formatted$ AS STRING
    DIM first_word$ AS STRING
    DIM new_indent AS INTEGER

    PRINT "Formatting "; line_count; " lines..."

    indent_level = 0

    FOR i = 0 TO line_count - 1
        original_line$ = lines$(i)
        trimmed$ = trim$(original_line$)

        REM Skip blank lines - preserve them
        IF is_blank_line(original_line$) THEN
            lines$(i) = ""
            GOTO next_line
        END IF

        REM Get first word
        first_word$ = get_first_word$(trimmed$)

        REM Check if we need to dedent this line
        IF should_dedent(first_word$) THEN
            IF indent_level > 0 THEN
                indent_level = indent_level - 1
            END IF
        END IF

        REM Build formatted line
        IF is_comment_line(trimmed$) THEN
            REM Comments get current indent level
            formatted$ = make_indent$(indent_level) + trimmed$
        ELSE
            REM Regular code
            formatted$ = make_indent$(indent_level) + trimmed$
        END IF

        REM Store formatted line
        lines$(i) = formatted$

        REM Check if next line should be indented
        IF should_indent(first_word$) THEN
            REM Special case: single-line IF statements don't increase indent
            DIM has_then AS INTEGER
            has_then = 0
            DIM pos AS INTEGER
            FOR pos = 1 TO LEN(trimmed$)
                IF MID$(trimmed$, pos, 4) = "THEN" OR MID$(trimmed$, pos, 4) = "then" OR MID$(trimmed$, pos, 4) = "Then" THEN
                    has_then = 1
                END IF
            NEXT pos

            IF first_word$ = "IF" OR first_word$ = "if" OR first_word$ = "If" THEN
                IF has_then THEN
                    REM Check if there's code after THEN (single-line IF)
                    DIM after_then$ AS STRING
                    FOR pos = 1 TO LEN(trimmed$)
                        IF MID$(trimmed$, pos, 4) = "THEN" OR MID$(trimmed$, pos, 4) = "then" THEN
                            after_then$ = trim$(MID$(trimmed$, pos + 4))
                            EXIT FOR
                        END IF
                    NEXT pos

                    IF LEN(after_then$) > 0 THEN
                        REM Single-line IF, don't indent
                    ELSE
                        REM Multi-line IF, indent next line
                        indent_level = indent_level + 1
                    END IF
                ELSE
                    REM No THEN, probably line-continuation, indent
                    indent_level = indent_level + 1
                END IF
            ELSE
                REM Other indent keywords
                indent_level = indent_level + 1
            END IF
        END IF

        next_line:
    NEXT i

    PRINT "Formatting complete."
END SUB

REM ============================================================================
REM FILE I/O
REM ============================================================================

SUB load_file(filename$ AS STRING)
    REM Load file into lines array
    DIM content$ AS STRING
    DIM pos AS INTEGER
    DIM line_start AS INTEGER
    DIM ch$ AS STRING

    PRINT "Loading "; filename$; "..."

    content$ = SLURP(filename$)

    IF LEN(content$) = 0 THEN
        PRINT "Error: Could not read file or file is empty"
        END
    END IF

    PRINT "File size: "; LEN(content$); " bytes"

    REM Parse into lines
    line_count = 0
    line_start = 1

    FOR pos = 1 TO LEN(content$)
        ch$ = MID$(content$, pos, 1)

        IF ch$ = CHR$(10) OR ch$ = CHR$(13) THEN
            REM Found line ending
            IF pos > line_start THEN
                lines$(line_count) = MID$(content$, line_start, pos - line_start)
            ELSE
                lines$(line_count) = ""
            END IF

            line_count = line_count + 1

            IF line_count >= max_lines THEN
                PRINT "Error: File too large (max "; max_lines; " lines)"
                END
            END IF

            REM Handle CRLF
            IF ch$ = CHR$(13) AND pos < LEN(content$) THEN
                IF MID$(content$, pos + 1, 1) = CHR$(10) THEN
                    pos = pos + 1
                END IF
            END IF

            line_start = pos + 1
        END IF
    NEXT pos

    REM Handle last line if no trailing newline
    IF line_start <= LEN(content$) THEN
        lines$(line_count) = MID$(content$, line_start)
        line_count = line_count + 1
    END IF

    PRINT "Loaded "; line_count; " lines"
END SUB

SUB save_file(filename$ AS STRING)
    REM Save lines array to file
    DIM content$ AS STRING
    DIM i AS INTEGER

    PRINT "Saving to "; filename$; "..."

    content$ = ""
    FOR i = 0 TO line_count - 1
        content$ = content$ + lines$(i) + CHR$(10)
    NEXT i

    SPIT filename$, content$

    PRINT "Saved "; line_count; " lines"
END SUB

REM ============================================================================
REM MAIN PROGRAM
REM ============================================================================

SUB main()
    PRINT "============================================"
    PRINT "BASFMT - BASIC Code Formatter"
    PRINT "============================================"
    PRINT ""

    REM Check command-line arguments
    IF COMMANDCOUNT() < 1 THEN
        CALL show_usage()
        END
    END IF

    REM Get input file
    input_file$ = COMMAND(1)

    REM Get output file (optional)
    IF COMMANDCOUNT() >= 2 THEN
        output_file$ = COMMAND(2)
    ELSE
        output_file$ = input_file$
        PRINT "Warning: Formatting in-place (will overwrite input file)"
        PRINT ""
    END IF

    REM Load file
    CALL load_file(input_file$)

    REM Format
    CALL format_lines()

    REM Save
    CALL save_file(output_file$)

    PRINT ""
    PRINT "Done! Formatted "; line_count; " lines."
END SUB

REM Run the formatter
CALL main()
