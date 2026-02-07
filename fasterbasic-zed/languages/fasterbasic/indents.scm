; =========================================================================
; FasterBASIC Tree-sitter Indentation Queries for Zed
; Controls automatic indentation when editing FasterBASIC source files
; =========================================================================

; -------------------------------------------------------------------------
; Block structures that increase indent
; -------------------------------------------------------------------------

; IF...THEN (multi-line)
(if_statement) @indent

; ELSEIF / ELSE clauses (dedent then re-indent)
(elseif_clause) @indent
(else_clause) @indent

; SELECT CASE
(select_case_statement) @indent
(case_clause) @indent
(otherwise_clause) @indent

; FOR / FOR EACH loops
(for_statement) @indent
(for_each_statement) @indent

; WHILE loop
(while_statement) @indent

; REPEAT...UNTIL loop
(repeat_statement) @indent

; DO...LOOP
(do_statement) @indent

; SUB / FUNCTION
(sub_declaration) @indent
(function_declaration) @indent

; CLASS
(class_declaration) @indent

; CLASS members
(constructor_declaration) @indent
(destructor_declaration) @indent
(method_declaration) @indent

; TYPE (UDT)
(type_declaration) @indent

; MATCH TYPE
(match_type_statement) @indent
(match_type_case) @indent
(match_type_else) @indent

; TRY / CATCH / FINALLY
(try_statement) @indent
(catch_clause) @indent
(finally_clause) @indent

; Timer inline DO...DONE blocks
(timer_statement) @indent

; -------------------------------------------------------------------------
; Outdent markers — closing keywords reduce indent
; -------------------------------------------------------------------------

; These are all the "END ..." / closing tokens that should outdent.
; We use @outdent on the node that ends the block.

; Note: Tree-sitter for Zed uses @outdent on the closing token/node
; of a block to signal that the line with that token should be dedented.

; Multi-line IF closers
(if_statement "ENDIF" @outdent)
(if_statement "END" @outdent)

; ELSEIF and ELSE start at same level as IF
(elseif_clause "ELSEIF" @outdent)
(else_clause "ELSE" @outdent)

; SELECT CASE closers
(select_case_statement "ENDCASE" @outdent)
(select_case_statement "END" @outdent)
(case_clause "CASE" @outdent)
(otherwise_clause "OTHERWISE" @outdent)

; FOR loop closers
(for_statement "NEXT" @outdent)
(for_each_statement "NEXT" @outdent)

; WHILE closers
(while_statement "WEND" @outdent)
(while_statement "ENDWHILE" @outdent)

; REPEAT closer
(repeat_statement "UNTIL" @outdent)

; DO...LOOP closer
(do_statement "LOOP" @outdent)

; SUB / FUNCTION closers
(sub_declaration "ENDSUB" @outdent)
(sub_declaration "END" @outdent)
(function_declaration "ENDFUNCTION" @outdent)
(function_declaration "END" @outdent)

; CLASS closer
(class_declaration "END" @outdent)

; CLASS member closers
(constructor_declaration "END" @outdent)
(destructor_declaration "END" @outdent)
(method_declaration "END" @outdent)

; TYPE closer
(type_declaration "ENDTYPE" @outdent)
(type_declaration "END" @outdent)

; MATCH TYPE closers
(match_type_statement "ENDMATCH" @outdent)
(match_type_statement "END" @outdent)
(match_type_case "CASE" @outdent)
(match_type_else "CASE" @outdent)

; TRY closers
(try_statement "END" @outdent)
(catch_clause "CATCH" @outdent)
(finally_clause "FINALLY" @outdent)

; Timer inline block closer
(timer_statement "DONE" @outdent)
