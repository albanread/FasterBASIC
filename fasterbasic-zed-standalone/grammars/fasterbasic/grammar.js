// Tree-sitter grammar for FasterBASIC
// Case-insensitive BASIC dialect with classes, lists, pattern matching, and more.

// Helper: case-insensitive keyword matching
function kw(word) {
  let result = "";
  for (const c of word) {
    if (/[a-zA-Z]/.test(c)) {
      result += "[" + c.toLowerCase() + c.toUpperCase() + "]";
    } else {
      result += "\\" + c;
    }
  }
  return new RegExp(result);
}

// Helper: optional sequence
function optseq(...rules) {
  return optional(seq(...rules));
}

// Helper: comma-separated list with at least one element
function commaSep1(rule) {
  return seq(rule, repeat(seq(",", rule)));
}

// Helper: optional comma-separated list
function commaSep(rule) {
  return optional(commaSep1(rule));
}

// Helper: semicolon/comma separated print items
function printSep() {
  return choice(";", ",");
}

module.exports = grammar({
  name: "fasterbasic",

  extras: ($) => [/[ \t\r]+/],

  externals: ($) => [],

  word: ($) => $.identifier_plain,

  conflicts: ($) => [
    [$.call_expression, $.array_access],
    [$.for_each_statement, $.next_statement],
    [$.for_statement, $.next_statement],
    [$.finally_clause],
    [$.catch_clause],
    [$.else_clause],
    [$.elseif_clause],
    [$.match_type_case],
    [$.match_type_else],
    [$.otherwise_clause],
    [$.case_clause],
  ],

  rules: {
    source_file: ($) => repeat(choice($._statement_line, $._newline)),

    _newline: ($) => /\n/,

    // A line optionally starting with a line number, then a statement list
    _statement_line: ($) =>
      seq(optional($.line_number), $._statement_list, $._newline),

    line_number: ($) => /[0-9]+/,

    _statement_list: ($) =>
      prec.left(seq($._statement, repeat(seq(":", $._statement)))),

    // Label definition (higher precedence to resolve conflict with _identifier)
    label: ($) => prec(2, seq($.identifier_plain, ":")),

    // =========================================================================
    // STATEMENTS
    // =========================================================================
    _statement: ($) =>
      choice(
        $.comment,
        $.label,
        $.print_statement,
        $.console_statement,
        $.input_statement,
        $.line_input_statement,
        $.dim_statement,
        $.redim_statement,
        $.erase_statement,
        $.local_statement,
        $.global_statement,
        $.shared_statement,
        $.constant_statement,
        $.let_statement,
        $.assignment_statement,
        $.if_statement,
        $.single_line_if,
        $.select_case_statement,
        $.for_statement,
        $.for_each_statement,
        $.next_statement,
        $.while_statement,
        $.repeat_statement,
        $.do_statement,
        $.exit_statement,
        $.continue_statement,
        $.goto_statement,
        $.gosub_statement,
        $.on_statement,
        $.return_statement,
        $.sub_declaration,
        $.function_declaration,
        $.class_declaration,
        $.type_declaration,
        $.match_type_statement,
        $.try_statement,
        $.throw_statement,
        $.call_statement,
        $.def_fn_statement,
        $.swap_statement,
        $.inc_statement,
        $.dec_statement,
        $.option_statement,
        $.data_statement,
        $.read_statement,
        $.restore_statement,
        $.open_statement,
        $.close_statement,
        $.end_statement,
        $.run_statement,
        $.stop_statement,
        $.cls_statement,
        $.gcls_statement,
        $.color_statement,
        $.pset_statement,
        $.line_draw_statement,
        $.rect_statement,
        $.circle_statement,
        $.hline_statement,
        $.vline_statement,
        $.at_statement,
        $.textput_statement,
        $.sprite_statement,
        $.timer_statement,
        $.play_statement,
        $.method_call_statement,
      ),

    // =========================================================================
    // COMMENTS
    // =========================================================================
    comment: ($) => choice(seq(kw("REM"), /[^\n]*/), seq("'", /[^\n]*/)),

    // =========================================================================
    // PRINT / CONSOLE
    // =========================================================================
    print_statement: ($) =>
      seq(
        choice(kw("PRINT"), "?"),
        optional(
          choice(
            seq("#", $._expression, ",", optional($.print_list)),
            seq(kw("USING"), $._expression, ";", $.expression_list),
            $.print_list,
          ),
        ),
      ),

    console_statement: ($) => seq(kw("CONSOLE"), optional($.print_list)),

    print_list: ($) =>
      choice(
        seq(
          $.print_item,
          repeat(seq(printSep(), $.print_item)),
          optional(printSep()),
        ),
        printSep(),
      ),

    print_item: ($) => $._expression,

    // =========================================================================
    // INPUT
    // =========================================================================
    input_statement: ($) =>
      seq(
        kw("INPUT"),
        optional(seq("#", $._expression, ",")),
        optional(seq($.string_literal, ";")),
        commaSep1($._lvalue_or_identifier),
      ),

    line_input_statement: ($) =>
      seq(
        kw("LINE"),
        kw("INPUT"),
        optional(seq($.string_literal, ";")),
        $._lvalue_or_identifier,
      ),

    // =========================================================================
    // VARIABLE DECLARATIONS
    // =========================================================================
    dim_statement: ($) => seq(kw("DIM"), commaSep1($.dim_item)),

    dim_item: ($) =>
      seq(
        $._identifier,
        optional(seq("(", $.expression_list, ")")),
        optional($.type_annotation),
        optional(seq("=", $._expression)),
      ),

    redim_statement: ($) =>
      seq(kw("REDIM"), optional(kw("PRESERVE")), commaSep1($.dim_item)),

    erase_statement: ($) => seq(kw("ERASE"), commaSep1($._identifier)),

    local_statement: ($) => seq(kw("LOCAL"), commaSep1($.local_item)),

    local_item: ($) =>
      seq(
        $._identifier,
        optional($.type_annotation),
        optional(seq("=", $._expression)),
      ),

    global_statement: ($) => seq(kw("GLOBAL"), commaSep1($.local_item)),

    shared_statement: ($) => seq(kw("SHARED"), commaSep1($._identifier)),

    constant_statement: ($) =>
      seq(
        choice(kw("CONSTANT"), kw("CONST")),
        $._identifier,
        "=",
        $._expression,
      ),

    // Type annotation: AS INTEGER, AS STRING, AS LIST OF ANY, AS ClassName, etc.
    type_annotation: ($) => seq(kw("AS"), $.type_name),

    type_name: ($) =>
      choice(
        kw("INTEGER"),
        kw("INT"),
        kw("LONG"),
        kw("SINGLE"),
        kw("FLOAT"),
        kw("DOUBLE"),
        kw("STRING"),
        kw("BYTE"),
        kw("SHORT"),
        kw("UBYTE"),
        kw("USHORT"),
        kw("UINTEGER"),
        kw("UINT"),
        kw("ULONG"),
        kw("ANY"),
        $.list_type,
        $.hashmap_type,
        // User-defined type or class name
        $._identifier,
      ),

    list_type: ($) => seq(kw("LIST"), optional(seq(kw("OF"), $.type_name))),

    hashmap_type: ($) => kw("HASHMAP"),

    // =========================================================================
    // ASSIGNMENT
    // =========================================================================
    let_statement: ($) => seq(kw("LET"), $.lvalue, "=", $._expression),

    assignment_statement: ($) => prec(-1, seq($.lvalue, "=", $._expression)),

    lvalue: ($) =>
      choice(
        $._identifier,
        $.member_expression,
        $.array_access,
        $.slice_expression,
      ),

    _lvalue_or_identifier: ($) =>
      choice($._identifier, $.member_expression, $.array_access),

    // =========================================================================
    // CONTROL FLOW
    // =========================================================================
    goto_statement: ($) =>
      seq(kw("GOTO"), choice($.integer_literal, $._identifier)),

    gosub_statement: ($) =>
      seq(kw("GOSUB"), choice($.integer_literal, $._identifier)),

    return_statement: ($) => seq(kw("RETURN"), optional($._expression)),

    on_statement: ($) =>
      seq(
        choice(kw("ON"), kw("ONEVENT")),
        $._expression,
        choice(kw("GOTO"), kw("GOSUB"), kw("CALL")),
        commaSep1(choice($.integer_literal, $._identifier)),
      ),

    end_statement: ($) => prec(-2, kw("END")),

    stop_statement: ($) => kw("STOP"),

    // =========================================================================
    // IF / ELSEIF / ELSE
    // =========================================================================
    if_statement: ($) =>
      seq(
        kw("IF"),
        $._expression,
        kw("THEN"),
        $._newline,
        repeat($._block_content),
        repeat($.elseif_clause),
        optional($.else_clause),
        choice(kw("ENDIF"), seq(kw("END"), kw("IF"))),
      ),

    elseif_clause: ($) =>
      seq(
        kw("ELSEIF"),
        $._expression,
        kw("THEN"),
        $._newline,
        repeat($._block_content),
      ),

    else_clause: ($) => seq(kw("ELSE"), $._newline, repeat($._block_content)),

    single_line_if: ($) =>
      prec.right(
        1,
        seq(
          kw("IF"),
          $._expression,
          kw("THEN"),
          $._statement_list,
          optional(seq(kw("ELSE"), $._statement_list)),
        ),
      ),

    // =========================================================================
    // SELECT CASE
    // =========================================================================
    select_case_statement: ($) =>
      seq(
        kw("SELECT"),
        kw("CASE"),
        $._expression,
        $._newline,
        repeat($.case_clause),
        optional($.otherwise_clause),
        choice(kw("ENDCASE"), seq(kw("END"), kw("CASE"))),
      ),

    case_clause: ($) =>
      seq(
        kw("CASE"),
        commaSep1($.case_condition),
        $._newline,
        repeat($._block_content),
      ),

    case_condition: ($) =>
      choice(
        seq(kw("IS"), $.comparison_operator, $._expression),
        seq($._expression, kw("TO"), $._expression),
        $._expression,
      ),

    otherwise_clause: ($) =>
      seq(kw("OTHERWISE"), $._newline, repeat($._block_content)),

    // =========================================================================
    // LOOPS
    // =========================================================================
    for_statement: ($) =>
      seq(
        kw("FOR"),
        $._identifier,
        "=",
        $._expression,
        kw("TO"),
        $._expression,
        optional(seq(kw("STEP"), $._expression)),
        $._newline,
        repeat($._block_content),
        kw("NEXT"),
        optional($._identifier),
      ),

    for_each_statement: ($) =>
      seq(
        kw("FOR"),
        kw("EACH"),
        choice(
          // Two-variable form: FOR EACH T, E IN list
          seq($._identifier, ",", $._identifier),
          // Single-variable form: FOR EACH E IN list
          $._identifier,
        ),
        kw("IN"),
        $._expression,
        $._newline,
        repeat($._block_content),
        kw("NEXT"),
        optional($._identifier),
      ),

    next_statement: ($) => seq(kw("NEXT"), optional($._identifier)),

    while_statement: ($) =>
      seq(
        kw("WHILE"),
        $._expression,
        $._newline,
        repeat($._block_content),
        choice(kw("WEND"), kw("ENDWHILE")),
      ),

    repeat_statement: ($) =>
      seq(
        kw("REPEAT"),
        $._newline,
        repeat($._block_content),
        kw("UNTIL"),
        $._expression,
      ),

    do_statement: ($) =>
      seq(
        kw("DO"),
        optional(
          choice(
            seq(kw("WHILE"), $._expression),
            seq(kw("UNTIL"), $._expression),
          ),
        ),
        $._newline,
        repeat($._block_content),
        kw("LOOP"),
        optional(
          choice(
            seq(kw("WHILE"), $._expression),
            seq(kw("UNTIL"), $._expression),
          ),
        ),
      ),

    exit_statement: ($) =>
      seq(
        kw("EXIT"),
        choice(
          kw("FOR"),
          kw("DO"),
          kw("WHILE"),
          kw("REPEAT"),
          kw("FUNCTION"),
          kw("SUB"),
        ),
      ),

    continue_statement: ($) => kw("CONTINUE"),

    // =========================================================================
    // SUB / FUNCTION
    // =========================================================================
    sub_declaration: ($) =>
      seq(
        kw("SUB"),
        field("name", $._identifier),
        optional(seq("(", optional($.parameter_list), ")")),
        $._newline,
        repeat($._block_content),
        choice(seq(kw("END"), kw("SUB")), kw("ENDSUB")),
      ),

    function_declaration: ($) =>
      seq(
        kw("FUNCTION"),
        field("name", $._identifier),
        optional(seq("(", optional($.parameter_list), ")")),
        optional($.type_annotation),
        $._newline,
        repeat($._block_content),
        choice(seq(kw("END"), kw("FUNCTION")), kw("ENDFUNCTION")),
      ),

    parameter_list: ($) => commaSep1($.parameter),

    parameter: ($) =>
      seq(
        optional(choice(kw("BYVAL"), kw("BYREF"))),
        $._identifier,
        optional($.type_annotation),
      ),

    def_fn_statement: ($) =>
      seq(
        kw("DEF"),
        kw("FN"),
        field("name", $._identifier),
        optional(seq("(", optional($.parameter_list), ")")),
        "=",
        $._expression,
      ),

    call_statement: ($) =>
      prec(
        -2,
        seq(
          optional(kw("CALL")),
          $._identifier,
          optional(seq("(", optional($.expression_list), ")")),
        ),
      ),

    // =========================================================================
    // CLASS
    // =========================================================================
    class_declaration: ($) =>
      seq(
        kw("CLASS"),
        field("name", $._identifier),
        optional(seq(kw("EXTENDS"), field("superclass", $._identifier))),
        $._newline,
        repeat($.class_body_item),
        seq(kw("END"), kw("CLASS")),
      ),

    class_body_item: ($) =>
      choice(
        $.field_declaration,
        $.constructor_declaration,
        $.destructor_declaration,
        $.method_declaration,
        $.comment,
        $._newline,
      ),

    field_declaration: ($) =>
      seq($._identifier, kw("AS"), $.type_name, $._newline),

    constructor_declaration: ($) =>
      seq(
        kw("CONSTRUCTOR"),
        optional(seq("(", optional($.parameter_list), ")")),
        $._newline,
        repeat($._block_content),
        seq(kw("END"), kw("CONSTRUCTOR")),
      ),

    destructor_declaration: ($) =>
      seq(
        kw("DESTRUCTOR"),
        $._newline,
        repeat($._block_content),
        seq(kw("END"), kw("DESTRUCTOR")),
      ),

    method_declaration: ($) =>
      seq(
        kw("METHOD"),
        field("name", $._identifier),
        optional(seq("(", optional($.parameter_list), ")")),
        optional($.type_annotation),
        $._newline,
        repeat($._block_content),
        seq(kw("END"), kw("METHOD")),
      ),

    // =========================================================================
    // TYPE (UDT)
    // =========================================================================
    type_declaration: ($) =>
      seq(
        kw("TYPE"),
        field("name", $._identifier),
        $._newline,
        repeat($.type_field),
        choice(seq(kw("END"), kw("TYPE")), kw("ENDTYPE")),
      ),

    type_field: ($) => seq($._identifier, kw("AS"), $.type_name, $._newline),

    // =========================================================================
    // MATCH TYPE
    // =========================================================================
    match_type_statement: ($) =>
      seq(
        kw("MATCH"),
        kw("TYPE"),
        $._expression,
        $._newline,
        repeat($.match_type_case),
        optional($.match_type_else),
        choice(seq(kw("END"), kw("MATCH")), kw("ENDMATCH")),
      ),

    match_type_case: ($) =>
      seq(
        kw("CASE"),
        $.type_name,
        field("binding", $._identifier),
        $._newline,
        repeat($._block_content),
      ),

    match_type_else: ($) =>
      seq(kw("CASE"), kw("ELSE"), $._newline, repeat($._block_content)),

    // =========================================================================
    // TRY / CATCH / FINALLY
    // =========================================================================
    try_statement: ($) =>
      seq(
        kw("TRY"),
        $._newline,
        repeat($._block_content),
        repeat($.catch_clause),
        optional($.finally_clause),
        seq(kw("END"), kw("TRY")),
      ),

    catch_clause: ($) =>
      seq(
        kw("CATCH"),
        commaSep1($.integer_literal),
        $._newline,
        repeat($._block_content),
      ),

    finally_clause: ($) =>
      seq(kw("FINALLY"), $._newline, repeat($._block_content)),

    throw_statement: ($) => seq(kw("THROW"), $._expression),

    // =========================================================================
    // DATA / READ / RESTORE
    // =========================================================================
    data_statement: ($) =>
      seq(
        kw("DATA"),
        commaSep1(
          choice(
            $.string_literal,
            $.integer_literal,
            $.float_literal,
            $._identifier,
          ),
        ),
      ),

    read_statement: ($) => seq(kw("READ"), commaSep1($._lvalue_or_identifier)),

    restore_statement: ($) =>
      seq(kw("RESTORE"), optional(choice($.integer_literal, $._identifier))),

    // =========================================================================
    // FILE I/O
    // =========================================================================
    open_statement: ($) =>
      seq(
        kw("OPEN"),
        $._expression,
        kw("FOR"),
        choice(kw("INPUT"), kw("OUTPUT"), kw("APPEND"), kw("BINARY")),
        kw("AS"),
        "#",
        $._expression,
      ),

    close_statement: ($) => seq(kw("CLOSE"), optional(seq("#", $._expression))),

    // =========================================================================
    // UTILITY STATEMENTS
    // =========================================================================
    swap_statement: ($) =>
      seq(kw("SWAP"), $._lvalue_or_identifier, ",", $._lvalue_or_identifier),

    inc_statement: ($) =>
      seq(
        kw("INC"),
        $._lvalue_or_identifier,
        optional(seq(",", $._expression)),
      ),

    dec_statement: ($) =>
      seq(
        kw("DEC"),
        $._lvalue_or_identifier,
        optional(seq(",", $._expression)),
      ),

    // =========================================================================
    // COMPILER OPTIONS
    // =========================================================================
    option_statement: ($) =>
      seq(
        kw("OPTION"),
        choice(
          kw("BITWISE"),
          kw("LOGICAL"),
          seq(kw("BASE"), $.integer_literal),
          kw("EXPLICIT"),
          kw("UNICODE"),
          kw("ASCII"),
          kw("DETECTSTRING"),
          seq(kw("ERROR"), choice(kw("ON"), kw("OFF"))),
          seq(kw("INCLUDE"), $.string_literal),
          kw("ONCE"),
          seq(kw("CANCELLABLE"), choice(kw("ON"), kw("OFF"))),
          seq(kw("BOUNDS_CHECK"), choice(kw("ON"), kw("OFF"))),
          seq(kw("FORCE_YIELD"), choice(kw("ON"), kw("OFF"))),
          seq(kw("SAMM"), choice(kw("ON"), kw("OFF"))),
          seq(kw("STRICT"), choice(kw("ON"), kw("OFF"))),
        ),
      ),

    // =========================================================================
    // GRAPHICS
    // =========================================================================
    cls_statement: ($) => seq(kw("CLS"), optional($._expression)),

    gcls_statement: ($) =>
      seq(choice(kw("GCLS"), kw("CLG")), optional($._expression)),

    color_statement: ($) =>
      seq(kw("COLOR"), $._expression, optional(seq(",", $._expression))),

    pset_statement: ($) =>
      seq(
        kw("PSET"),
        "(",
        $._expression,
        ",",
        $._expression,
        ")",
        optional(seq(",", $._expression)),
      ),

    line_draw_statement: ($) =>
      seq(
        kw("LINE"),
        "(",
        $._expression,
        ",",
        $._expression,
        ")",
        "-",
        "(",
        $._expression,
        ",",
        $._expression,
        ")",
        optional(seq(",", $._expression)),
      ),

    rect_statement: ($) =>
      seq(
        choice(kw("RECT"), kw("RECTF")),
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        optional(seq(",", $._expression)),
      ),

    circle_statement: ($) =>
      seq(
        choice(kw("CIRCLE"), kw("CIRCLEF")),
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        optional(seq(",", $._expression)),
      ),

    hline_statement: ($) =>
      seq(
        kw("HLINE"),
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        optional(seq(",", $._expression)),
      ),

    vline_statement: ($) =>
      seq(
        kw("VLINE"),
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        optional(seq(",", $._expression)),
      ),

    // =========================================================================
    // TEXT LAYER
    // =========================================================================
    at_statement: ($) =>
      seq(choice(kw("AT"), kw("LOCATE")), $._expression, ",", $._expression),

    textput_statement: ($) =>
      seq(
        choice(kw("TEXTPUT"), kw("TEXT_PUT"), kw("TCHAR"), kw("TEXT_PUTCHAR")),
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        optional(seq(",", $._expression, ",", $._expression)),
      ),

    // =========================================================================
    // SPRITES
    // =========================================================================
    sprite_statement: ($) =>
      seq(
        choice(
          kw("SPRLOAD"),
          kw("SPRFREE"),
          kw("SPRSHOW"),
          kw("SPRHIDE"),
          kw("SPRMOVE"),
          kw("SPRPOS"),
          kw("SPRTINT"),
          kw("SPRSCALE"),
          kw("SPRROT"),
          kw("SPREXPLODE"),
        ),
        commaSep1($._expression),
      ),

    // =========================================================================
    // TIMER / EVENT
    // =========================================================================
    timer_statement: ($) =>
      choice(
        // AFTER/EVERY ... MS/SECS/FRAMES GOTO/GOSUB/CALL target
        seq(
          choice(kw("AFTER"), kw("EVERY")),
          $._expression,
          choice(kw("MS"), kw("SECS"), kw("FRAMES")),
          choice(
            seq(choice(kw("GOTO"), kw("GOSUB"), kw("CALL")), $._identifier),
            seq(kw("DO"), $._newline, repeat($._block_content), kw("DONE")),
          ),
        ),
        // AFTERFRAMES / EVERYFRAME
        seq(
          choice(kw("AFTERFRAMES"), kw("EVERYFRAME")),
          $._expression,
          choice(kw("GOTO"), kw("GOSUB"), kw("CALL")),
          $._identifier,
        ),
        // TIMER STOP
        seq(kw("TIMER"), kw("STOP"), optional($._identifier)),
        // VSYNC / WAIT / WAIT_MS
        seq(kw("VSYNC"), optional($._expression)),
        seq(kw("WAIT"), optional($._expression)),
        seq(kw("WAIT_MS"), $._expression),
      ),

    run_statement: ($) =>
      seq(kw("RUN"), optional(seq(kw("UNTIL"), $._expression))),

    // =========================================================================
    // AUDIO
    // =========================================================================
    play_statement: ($) =>
      seq(choice(kw("PLAY"), kw("PLAY_SOUND")), commaSep1($._expression)),

    // =========================================================================
    // METHOD CALL as statement (e.g., obj.Method(args))
    // =========================================================================
    method_call_statement: ($) =>
      prec(
        -1,
        seq(
          $.member_expression,
          optional(seq("(", optional($.expression_list), ")")),
        ),
      ),

    // =========================================================================
    // BLOCK CONTENT (statements within blocks)
    // =========================================================================
    _block_content: ($) =>
      choice(
        seq(optional($.line_number), $._statement_list, $._newline),
        $._newline,
      ),

    // =========================================================================
    // EXPRESSIONS
    // =========================================================================
    _expression: ($) =>
      choice(
        $.binary_expression,
        $.unary_expression,
        $.primary_expression,
        $.parenthesized_expression,
        $.call_expression,
        $.member_expression,
        $.array_access,
        $.slice_expression,
        $.iif_expression,
        $.new_expression,
        $.list_constructor,
        $.string_literal,
        $.integer_literal,
        $.float_literal,
        $.hex_literal,
        $.boolean_literal,
        $.nothing_literal,
        $.me_expression,
        $._identifier,
      ),

    // Binary expressions with precedence
    binary_expression: ($) =>
      choice(
        // Logical operators (lowest precedence)
        prec.left(1, seq($._expression, kw("IMP"), $._expression)),
        prec.left(2, seq($._expression, kw("EQV"), $._expression)),
        prec.left(3, seq($._expression, kw("OR"), $._expression)),
        prec.left(4, seq($._expression, kw("XOR"), $._expression)),
        prec.left(5, seq($._expression, kw("AND"), $._expression)),
        // Comparison
        prec.left(6, seq($._expression, $.comparison_operator, $._expression)),
        // String concatenation and arithmetic
        prec.left(7, seq($._expression, "+", $._expression)),
        prec.left(7, seq($._expression, "-", $._expression)),
        prec.left(8, seq($._expression, "*", $._expression)),
        prec.left(8, seq($._expression, "/", $._expression)),
        prec.left(8, seq($._expression, "\\", $._expression)),
        prec.left(8, seq($._expression, kw("MOD"), $._expression)),
        // Exponentiation (right-associative)
        prec.right(9, seq($._expression, "^", $._expression)),
      ),

    comparison_operator: ($) =>
      choice("=", "<>", "!=", "<", "<=", ">", ">=", kw("IS")),

    unary_expression: ($) =>
      choice(
        prec.right(10, seq("-", $._expression)),
        prec.right(10, seq("+", $._expression)),
        prec.right(7, seq(kw("NOT"), $._expression)),
      ),

    parenthesized_expression: ($) => seq("(", $._expression, ")"),

    call_expression: ($) =>
      prec(
        12,
        seq(
          choice(
            $._identifier,
            seq(kw("FN"), $._identifier),
            $.member_expression,
          ),
          "(",
          optional($.expression_list),
          ")",
        ),
      ),

    member_expression: ($) =>
      prec.left(
        13,
        seq(
          choice(
            $._identifier,
            $.call_expression,
            $.member_expression,
            $.parenthesized_expression,
          ),
          ".",
          $._identifier,
        ),
      ),

    array_access: ($) =>
      prec(12, seq($._identifier, "(", $.expression_list, ")")),

    slice_expression: ($) =>
      prec(12, seq($._identifier, "[", $._expression, ":", $._expression, "]")),

    iif_expression: ($) =>
      seq(
        kw("IIF"),
        "(",
        $._expression,
        ",",
        $._expression,
        ",",
        $._expression,
        ")",
      ),

    new_expression: ($) =>
      seq(
        kw("NEW"),
        $._identifier,
        optional(seq("(", optional($.expression_list), ")")),
      ),

    list_constructor: ($) =>
      seq(kw("LIST"), "(", optional($.expression_list), ")"),

    expression_list: ($) => commaSep1($._expression),

    primary_expression: ($) =>
      prec(
        1,
        choice(
          $.string_literal,
          $.integer_literal,
          $.float_literal,
          $.hex_literal,
          $.boolean_literal,
          $.nothing_literal,
          $.me_expression,
          $._identifier,
        ),
      ),

    // =========================================================================
    // IDENTIFIERS
    // =========================================================================
    _identifier: ($) => choice($.identifier_plain, $.typed_identifier),

    // Plain identifier without type suffix
    identifier_plain: ($) => /[a-zA-Z_][a-zA-Z0-9_]*/,

    // Identifier with type suffix: x%, name$, etc.
    typed_identifier: ($) => /[a-zA-Z_][a-zA-Z0-9_]*[%&!#$@^]/,

    // =========================================================================
    // LITERALS
    // =========================================================================
    string_literal: ($) =>
      seq('"', repeat(choice($.escape_sequence, $.string_content)), '"'),

    string_content: ($) => /[^"\\]+/,

    escape_sequence: ($) => /\\[nrt\\"'0]/,

    integer_literal: ($) => /[0-9]+/,

    float_literal: ($) =>
      choice(
        /[0-9]+\.[0-9]*([eE][+-]?[0-9]+)?/,
        /[0-9]+[eE][+-]?[0-9]+/,
        /\.[0-9]+([eE][+-]?[0-9]+)?/,
      ),

    hex_literal: ($) => choice(/&[hH][0-9a-fA-F]+/, /0[xX][0-9a-fA-F]+/),

    boolean_literal: ($) => choice(kw("TRUE"), kw("FALSE")),

    nothing_literal: ($) => kw("NOTHING"),

    me_expression: ($) => kw("ME"),

    // Super call (used inside constructors)
    super_call: ($) => seq(kw("SUPER"), "(", optional($.expression_list), ")"),
  },
});
