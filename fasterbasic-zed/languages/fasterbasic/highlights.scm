; =========================================================================
; FasterBASIC Tree-sitter Highlight Queries
; =========================================================================

; -------------------------------------------------------------------------
; Comments
; -------------------------------------------------------------------------
(comment) @comment

; -------------------------------------------------------------------------
; Literals
; -------------------------------------------------------------------------
(string_literal) @string
(string_content) @string
(escape_sequence) @string.escape

(integer_literal) @number
(float_literal) @number
(hex_literal) @number

(boolean_literal) @constant.builtin
(nothing_literal) @constant.builtin
(me_expression) @variable.special

; -------------------------------------------------------------------------
; Identifiers
; -------------------------------------------------------------------------
(identifier_plain) @variable
(typed_identifier) @variable

; -------------------------------------------------------------------------
; Type names
; -------------------------------------------------------------------------
(type_name) @type
(type_annotation "AS" @keyword)

(list_type "LIST" @type.builtin)
(list_type "OF" @keyword)
(hashmap_type) @type.builtin

; -------------------------------------------------------------------------
; Labels and line numbers
; -------------------------------------------------------------------------
(label (identifier_plain) @label)
(line_number) @number

; -------------------------------------------------------------------------
; Function / Sub / Method declarations
; -------------------------------------------------------------------------
(sub_declaration
  name: (_) @function)

(function_declaration
  name: (_) @function)

(method_declaration
  name: (_) @function.method)

(constructor_declaration "CONSTRUCTOR" @keyword)
(destructor_declaration "DESTRUCTOR" @keyword)

(def_fn_statement
  name: (_) @function)

; -------------------------------------------------------------------------
; Class declarations
; -------------------------------------------------------------------------
(class_declaration
  name: (_) @type)
(class_declaration
  superclass: (_) @type)

(field_declaration (_) @property)

; -------------------------------------------------------------------------
; Type (UDT) declarations
; -------------------------------------------------------------------------
(type_declaration
  name: (_) @type)

(type_field (_) @property)

; -------------------------------------------------------------------------
; MATCH TYPE
; -------------------------------------------------------------------------
(match_type_case
  binding: (_) @variable)

; -------------------------------------------------------------------------
; Parameters
; -------------------------------------------------------------------------
(parameter (_) @variable.parameter)

; -------------------------------------------------------------------------
; Function calls
; -------------------------------------------------------------------------
(call_expression (identifier_plain) @function.call)
(call_expression (typed_identifier) @function.call)

; Member access
(member_expression "." @punctuation.delimiter)
(member_expression (_) @property . )

; Method call as statement
(method_call_statement (member_expression (_) @function.method.call . ))

; NEW expression
(new_expression "NEW" @keyword (_) @type)

; SUPER call
(super_call "SUPER" @keyword)

; List constructor
(list_constructor "LIST" @function.builtin)

; IIF expression
(iif_expression "IIF" @function.builtin)

; -------------------------------------------------------------------------
; Operators
; -------------------------------------------------------------------------
(binary_expression "+" @operator)
(binary_expression "-" @operator)
(binary_expression "*" @operator)
(binary_expression "/" @operator)
(binary_expression "\\" @operator)
(binary_expression "^" @operator)
(binary_expression "AND" @keyword.operator)
(binary_expression "OR" @keyword.operator)
(binary_expression "XOR" @keyword.operator)
(binary_expression "MOD" @keyword.operator)
(binary_expression "IMP" @keyword.operator)
(binary_expression "EQV" @keyword.operator)

(unary_expression "NOT" @keyword.operator)
(unary_expression "-" @operator)
(unary_expression "+" @operator)

(comparison_operator) @operator

; -------------------------------------------------------------------------
; Punctuation
; -------------------------------------------------------------------------
"(" @punctuation.bracket
")" @punctuation.bracket
"[" @punctuation.bracket
"]" @punctuation.bracket
"," @punctuation.delimiter
";" @punctuation.delimiter
":" @punctuation.delimiter
"#" @punctuation.special
"=" @operator

; -------------------------------------------------------------------------
; Control flow keywords
; -------------------------------------------------------------------------
(if_statement "IF" @keyword.control)
(if_statement "THEN" @keyword.control)
(if_statement "ENDIF" @keyword.control)
(if_statement "END" @keyword.control)

(single_line_if "IF" @keyword.control)
(single_line_if "THEN" @keyword.control)
(single_line_if "ELSE" @keyword.control)

(elseif_clause "ELSEIF" @keyword.control)
(elseif_clause "THEN" @keyword.control)

(else_clause "ELSE" @keyword.control)

(select_case_statement "SELECT" @keyword.control)
(select_case_statement "CASE" @keyword.control)
(select_case_statement "ENDCASE" @keyword.control)
(select_case_statement "END" @keyword.control)

(case_clause "CASE" @keyword.control)
(otherwise_clause "OTHERWISE" @keyword.control)

(for_statement "FOR" @keyword.control)
(for_statement "TO" @keyword.control)
(for_statement "STEP" @keyword.control)
(for_statement "NEXT" @keyword.control)

(for_each_statement "FOR" @keyword.control)
(for_each_statement "EACH" @keyword.control)
(for_each_statement "IN" @keyword.control)
(for_each_statement "NEXT" @keyword.control)

(next_statement "NEXT" @keyword.control)

(while_statement "WHILE" @keyword.control)
(while_statement "WEND" @keyword.control)
(while_statement "ENDWHILE" @keyword.control)

(repeat_statement "REPEAT" @keyword.control)
(repeat_statement "UNTIL" @keyword.control)

(do_statement "DO" @keyword.control)
(do_statement "LOOP" @keyword.control)
(do_statement "WHILE" @keyword.control)
(do_statement "UNTIL" @keyword.control)

(exit_statement "EXIT" @keyword.control)
(exit_statement "FOR" @keyword.control)
(exit_statement "DO" @keyword.control)
(exit_statement "WHILE" @keyword.control)
(exit_statement "REPEAT" @keyword.control)
(exit_statement "FUNCTION" @keyword.control)
(exit_statement "SUB" @keyword.control)

(continue_statement) @keyword.control

(goto_statement "GOTO" @keyword.control)
(gosub_statement "GOSUB" @keyword.control)
(return_statement "RETURN" @keyword.control)
(on_statement "ON" @keyword.control)
(on_statement "ONEVENT" @keyword.control)
(on_statement "GOTO" @keyword.control)
(on_statement "GOSUB" @keyword.control)
(on_statement "CALL" @keyword.control)

(match_type_statement "MATCH" @keyword.control)
(match_type_statement "TYPE" @keyword.control)
(match_type_statement "END" @keyword.control)
(match_type_statement "ENDMATCH" @keyword.control)

(match_type_case "CASE" @keyword.control)
(match_type_else "CASE" @keyword.control)
(match_type_else "ELSE" @keyword.control)

(try_statement "TRY" @keyword.control)
(try_statement "END" @keyword.control)
(catch_clause "CATCH" @keyword.control)
(finally_clause "FINALLY" @keyword.control)
(throw_statement "THROW" @keyword.control)

(end_statement) @keyword.control
(stop_statement) @keyword.control

; -------------------------------------------------------------------------
; Declaration keywords
; -------------------------------------------------------------------------
(dim_statement "DIM" @keyword)
(redim_statement "REDIM" @keyword)
(redim_statement "PRESERVE" @keyword)
(erase_statement "ERASE" @keyword)
(local_statement "LOCAL" @keyword)
(global_statement "GLOBAL" @keyword)
(shared_statement "SHARED" @keyword)
(constant_statement "CONSTANT" @keyword)
(constant_statement "CONST" @keyword)
(let_statement "LET" @keyword)
(data_statement "DATA" @keyword)
(read_statement "READ" @keyword)
(restore_statement "RESTORE" @keyword)

(sub_declaration "SUB" @keyword)
(sub_declaration "END" @keyword)
(sub_declaration "ENDSUB" @keyword)

(function_declaration "FUNCTION" @keyword)
(function_declaration "END" @keyword)
(function_declaration "ENDFUNCTION" @keyword)

(class_declaration "CLASS" @keyword)
(class_declaration "EXTENDS" @keyword)
(class_declaration "END" @keyword)

(method_declaration "METHOD" @keyword)
(method_declaration "END" @keyword)

(type_declaration "TYPE" @keyword)
(type_declaration "END" @keyword)
(type_declaration "ENDTYPE" @keyword)

(call_statement "CALL" @keyword)
(def_fn_statement "DEF" @keyword)
(def_fn_statement "FN" @keyword)

(parameter "BYVAL" @keyword)
(parameter "BYREF" @keyword)

; -------------------------------------------------------------------------
; Built-in statements
; -------------------------------------------------------------------------
(print_statement "PRINT" @function.builtin)
(print_statement "?" @function.builtin)
(print_statement "USING" @keyword)
(console_statement "CONSOLE" @function.builtin)
(input_statement "INPUT" @function.builtin)
(line_input_statement "LINE" @function.builtin)
(line_input_statement "INPUT" @function.builtin)

(swap_statement "SWAP" @function.builtin)
(inc_statement "INC" @function.builtin)
(dec_statement "DEC" @function.builtin)

(open_statement "OPEN" @function.builtin)
(open_statement "FOR" @keyword)
(open_statement "AS" @keyword)
(open_statement "INPUT" @keyword)
(open_statement "OUTPUT" @keyword)
(open_statement "APPEND" @keyword)
(open_statement "BINARY" @keyword)
(close_statement "CLOSE" @function.builtin)

(run_statement "RUN" @keyword.control)
(run_statement "UNTIL" @keyword.control)

; -------------------------------------------------------------------------
; Compiler options
; -------------------------------------------------------------------------
(option_statement "OPTION" @keyword.directive)
(option_statement "BITWISE" @keyword.directive)
(option_statement "LOGICAL" @keyword.directive)
(option_statement "BASE" @keyword.directive)
(option_statement "EXPLICIT" @keyword.directive)
(option_statement "UNICODE" @keyword.directive)
(option_statement "ASCII" @keyword.directive)
(option_statement "DETECTSTRING" @keyword.directive)
(option_statement "ERROR" @keyword.directive)
(option_statement "INCLUDE" @keyword.directive)
(option_statement "ONCE" @keyword.directive)
(option_statement "CANCELLABLE" @keyword.directive)
(option_statement "BOUNDS_CHECK" @keyword.directive)
(option_statement "FORCE_YIELD" @keyword.directive)
(option_statement "SAMM" @keyword.directive)
(option_statement "STRICT" @keyword.directive)
(option_statement "ON" @keyword.directive)
(option_statement "OFF" @keyword.directive)

; -------------------------------------------------------------------------
; Graphics keywords
; -------------------------------------------------------------------------
(cls_statement "CLS" @function.builtin)
(gcls_statement "GCLS" @function.builtin)
(gcls_statement "CLG" @function.builtin)
(color_statement "COLOR" @function.builtin)
(pset_statement "PSET" @function.builtin)
(line_draw_statement "LINE" @function.builtin)
(rect_statement "RECT" @function.builtin)
(rect_statement "RECTF" @function.builtin)
(circle_statement "CIRCLE" @function.builtin)
(circle_statement "CIRCLEF" @function.builtin)
(hline_statement "HLINE" @function.builtin)
(vline_statement "VLINE" @function.builtin)
(at_statement "AT" @function.builtin)
(at_statement "LOCATE" @function.builtin)
(textput_statement "TEXTPUT" @function.builtin)
(textput_statement "TEXT_PUT" @function.builtin)
(textput_statement "TCHAR" @function.builtin)
(textput_statement "TEXT_PUTCHAR" @function.builtin)

; -------------------------------------------------------------------------
; Sprite keywords
; -------------------------------------------------------------------------
(sprite_statement "SPRLOAD" @function.builtin)
(sprite_statement "SPRFREE" @function.builtin)
(sprite_statement "SPRSHOW" @function.builtin)
(sprite_statement "SPRHIDE" @function.builtin)
(sprite_statement "SPRMOVE" @function.builtin)
(sprite_statement "SPRPOS" @function.builtin)
(sprite_statement "SPRTINT" @function.builtin)
(sprite_statement "SPRSCALE" @function.builtin)
(sprite_statement "SPRROT" @function.builtin)
(sprite_statement "SPREXPLODE" @function.builtin)

; -------------------------------------------------------------------------
; Timer / Event keywords
; -------------------------------------------------------------------------
(timer_statement "AFTER" @keyword.control)
(timer_statement "EVERY" @keyword.control)
(timer_statement "MS" @keyword)
(timer_statement "SECS" @keyword)
(timer_statement "FRAMES" @keyword)
(timer_statement "DO" @keyword.control)
(timer_statement "DONE" @keyword.control)
(timer_statement "GOTO" @keyword.control)
(timer_statement "GOSUB" @keyword.control)
(timer_statement "CALL" @keyword.control)
(timer_statement "TIMER" @keyword.control)
(timer_statement "STOP" @keyword.control)
(timer_statement "VSYNC" @function.builtin)
(timer_statement "WAIT" @function.builtin)
(timer_statement "WAIT_MS" @function.builtin)
(timer_statement "AFTERFRAMES" @keyword.control)
(timer_statement "EVERYFRAME" @keyword.control)

; -------------------------------------------------------------------------
; Audio keywords
; -------------------------------------------------------------------------
(play_statement "PLAY" @function.builtin)
(play_statement "PLAY_SOUND" @function.builtin)
