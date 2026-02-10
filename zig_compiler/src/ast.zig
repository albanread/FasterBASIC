//! Abstract Syntax Tree for the FasterBASIC compiler.
//!
//! This module defines all AST node types using Zig's tagged unions, replacing
//! the C++ class hierarchy with a flat, cache-friendly representation.
//!
//! Design principles:
//! - Statements and Expressions are separate tagged unions.
//! - Child nodes are heap-allocated via the provided allocator.
//! - Slices (`[]...`) are used instead of `std::vector`.
//! - Source locations are attached to every node for error reporting.
//! - No virtual dispatch — pattern matching via `switch` on the tag.

const std = @import("std");
const token = @import("token.zig");
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

// ─── Pointer types ──────────────────────────────────────────────────────────

/// A heap-allocated expression node.
pub const ExprPtr = *Expression;
/// A heap-allocated statement node.
pub const StmtPtr = *Statement;

// ─── Expressions ────────────────────────────────────────────────────────────

/// An expression node in the AST.
pub const Expression = struct {
    loc: SourceLocation = .{},
    data: ExprData,
};

/// Tagged union of all expression kinds.
pub const ExprData = union(enum) {
    /// Binary operation: left op right
    binary: BinaryExpr,
    /// Unary operation: op expr
    unary: UnaryExpr,
    /// Numeric literal
    number: NumberExpr,
    /// String literal
    string_lit: StringExpr,
    /// Variable reference
    variable: VariableExpr,
    /// Array element access: name(index, ...)
    array_access: ArrayAccessExpr,
    /// Whole-array binary operation: arr + arr, arr * scalar, etc.
    array_binop: ArrayBinopExpr,
    /// Function/built-in call: FuncName(args...)
    function_call: FunctionCallExpr,
    /// Inline conditional: IIF(cond, true_val, false_val)
    iif: IIFExpr,
    /// Member access: object.field
    member_access: MemberAccessExpr,
    /// Method call: object.method(args...)
    method_call: MethodCallExpr,
    /// NEW ClassName(args...) — heap-allocated class instance
    new: NewExpr,
    /// CREATE TypeName(args...) — stack-allocated UDT value
    create: CreateExpr,
    /// ME — current object reference inside a method/constructor
    me: void,
    /// NOTHING — null object reference
    nothing: void,
    /// SUPER.Method(args...) or SUPER(args...) for constructor chain
    super_call: SuperCallExpr,
    /// expr IS ClassName / expr IS NOTHING
    is_type: IsTypeExpr,
    /// List constructor: {elem1, elem2, ...}
    list_constructor: ListConstructorExpr,
    /// Registry-based modular function expression
    registry_function: RegistryFunctionExpr,
    /// SPAWN WorkerName(args...) — starts a worker on a background thread
    spawn: SpawnExpr,
    /// AWAIT future — blocks until worker finishes, returns result
    await_expr: AwaitExpr,
    /// READY(future) — non-blocking check if worker is done
    ready: ReadyExpr,
    /// MARSHALL(variable) — deep-copy array/UDT for worker transfer
    marshall: MarshallExpr,
};

pub const BinaryExpr = struct {
    left: ExprPtr,
    op: Tag,
    right: ExprPtr,
};

pub const UnaryExpr = struct {
    op: Tag,
    operand: ExprPtr,
};

pub const NumberExpr = struct {
    value: f64,
};

pub const StringExpr = struct {
    value: []const u8,
    has_non_ascii: bool = false,
};

pub const VariableExpr = struct {
    name: []const u8,
    type_suffix: ?Tag = null,
};

pub const ArrayAccessExpr = struct {
    name: []const u8,
    type_suffix: ?Tag = null,
    indices: []ExprPtr,
};

pub const ArrayBinopExpr = struct {
    pub const OpType = enum {
        add,
        subtract,
        multiply,
        add_scalar,
        sub_scalar,
        mul_scalar,
    };

    operation: OpType,
    left_array: ExprPtr,
    right_expr: ExprPtr,
    is_scalar_op: bool = false,
};

pub const FunctionCallExpr = struct {
    name: []const u8,
    arguments: []ExprPtr,
    is_fn: bool = false,
};

pub const IIFExpr = struct {
    condition: ExprPtr,
    true_value: ExprPtr,
    false_value: ExprPtr,
};

pub const MemberAccessExpr = struct {
    object: ExprPtr,
    member_name: []const u8,
};

pub const MethodCallExpr = struct {
    object: ExprPtr,
    method_name: []const u8,
    arguments: []ExprPtr,
};

pub const NewExpr = struct {
    class_name: []const u8,
    arguments: []ExprPtr,
};

pub const CreateExpr = struct {
    type_name: []const u8,
    arguments: []ExprPtr,
    /// Whether arguments use named-field syntax (Field := value).
    is_named: bool = false,
    /// Field names for named-field CREATE (parallel to arguments).
    field_names: []const []const u8 = &.{},
};

pub const SuperCallExpr = struct {
    method_name: []const u8,
    arguments: []ExprPtr,
    is_constructor_call: bool = false,
};

pub const IsTypeExpr = struct {
    object: ExprPtr,
    class_name: []const u8,
    is_nothing_check: bool = false,
};

pub const ListConstructorExpr = struct {
    elements: []ExprPtr,
};

pub const RegistryFunctionExpr = struct {
    name: []const u8,
    arguments: []ExprPtr,
    return_type: u8 = 0, // opaque tag, interpreted by codegen
};

// ─── Statements ─────────────────────────────────────────────────────────────

/// A statement node in the AST.
pub const Statement = struct {
    loc: SourceLocation = .{},
    data: StmtData,
};

/// Tagged union of all statement kinds.
pub const StmtData = union(enum) {
    // ── Output / Input ──────────────────────────────────────────────────
    print: PrintStmt,
    console: ConsoleStmt,
    input: InputStmt,
    input_at: InputAtStmt,
    print_at: PrintAtStmt,

    // ── Assignment ──────────────────────────────────────────────────────
    let: LetStmt,
    mid_assign: MidAssignStmt,
    slice_assign: SliceAssignStmt,

    // ── Control flow ────────────────────────────────────────────────────
    goto_stmt: GotoStmt,
    gosub: GosubStmt,
    on_goto: OnGotoStmt,
    on_gosub: OnGosubStmt,
    on_call: OnCallStmt,
    on_event: OnEventStmt,
    return_stmt: ReturnStmt,
    exit_stmt: ExitStmt,
    end_stmt: void,

    // ── Conditionals ────────────────────────────────────────────────────
    if_stmt: IfStmt,
    case_stmt: CaseStmt,
    match_type: MatchTypeStmt,

    // ── Loops ───────────────────────────────────────────────────────────
    for_stmt: ForStmt,
    for_in: ForInStmt,
    next_stmt: NextStmt,
    while_stmt: WhileStmt,
    wend: void,
    repeat_stmt: RepeatStmt,
    until_stmt: UntilStmt,
    do_stmt: DoStmt,
    loop_stmt: LoopStmt,

    // ── Exception handling ──────────────────────────────────────────────
    try_catch: TryCatchStmt,
    throw_stmt: ThrowStmt,

    // ── Declarations ────────────────────────────────────────────────────
    dim: DimStmt,
    redim: RedimStmt,
    erase: EraseStmt,
    swap: SwapStmt,
    inc: IncDecStmt,
    dec: IncDecStmt,
    local: LocalStmt,
    global: GlobalStmt,
    shared: SharedStmt,
    constant: ConstantStmt,
    type_decl: TypeDeclStmt,
    data_stmt: DataStmt,
    read_stmt: ReadStmt,
    restore: RestoreStmt,
    option: OptionStmt,

    // ── Functions / Subs ────────────────────────────────────────────────
    function: FunctionStmt,
    sub: SubStmt,
    def: DefStmt,
    call: CallStmt,
    label: LabelStmt,

    // ── Workers (concurrency) ───────────────────────────────────────────
    worker: WorkerStmt,
    unmarshall: UnmarshallStmt,

    // ── CLASS / Object system ───────────────────────────────────────────
    class: ClassStmt,
    delete: DeleteStmt,

    // ── File I/O ────────────────────────────────────────────────────────
    open: OpenStmt,
    close: CloseStmt,

    // ── Process Execution ───────────────────────────────────────────────
    shell: ShellStmt,
    spit: SpitStmt,

    // ── Graphics / Sound / Timing ───────────────────────────────────────
    cls: void,
    gcls: void,
    vsync: void,
    color: ColorStmt,
    wait_stmt: WaitStmt,
    wait_ms: WaitStmt,

    // ── Terminal I/O (simple commands) ───────────────────────────────────
    cursor_on: void,
    cursor_off: void,
    cursor_hide: void,
    cursor_show: void,
    cursor_save: void,
    cursor_restore: void,
    color_reset: void,
    bold: void,
    italic: void,
    underline: void,
    blink: void,
    inverse: void,
    style_reset: void,
    normal: void,
    screen_alternate: void,
    screen_main: void,

    // ── Keyboard input ──────────────────────────────────────────────────
    kbraw: KbRawStmt,
    kbecho: KbEchoStmt,
    kbflush: void,

    pset: PsetStmt,
    line_stmt: LineStmt,
    rect: RectStmt,
    circle: CircleStmt,
    hline: HVLineStmt,
    vline: HVLineStmt,

    // ── Text layer ──────────────────────────────────────────────────────
    at_stmt: AtStmt,
    textput: TextputStmt,
    tchar: TcharStmt,
    tgrid: TgridStmt,
    tscroll: TscrollStmt,
    tclear: TclearStmt,
    locate: LocateStmt,

    // ── Sprites ─────────────────────────────────────────────────────────
    sprload: SpriteStmt,
    sprfree: SpriteStmt,
    sprshow: SpriteStmt,
    sprhide: SpriteStmt,
    sprmove: SprmoveStmt,
    sprpos: SprposStmt,
    sprtint: SprtintStmt,
    sprscale: SprscaleStmt,
    sprrot: SprrotStmt,
    sprexplode: SpriteStmt,

    // ── Audio ───────────────────────────────────────────────────────────
    play: PlayStmt,
    play_sound: PlaySoundStmt,

    // ── Timer events ────────────────────────────────────────────────────
    after: TimerEventStmt,
    every: TimerEventStmt,
    afterframes: TimerEventStmt,
    everyframe: TimerEventStmt,
    run: RunStmt,
    timer_stop: TimerStopStmt,
    timer_interval: TimerIntervalStmt,

    // ── Miscellaneous ───────────────────────────────────────────────────
    rem: RemStmt,
    expression_stmt: ExpressionStmtData,
    registry_command: RegistryCommandStmt,
};

// ─── Statement payloads ─────────────────────────────────────────────────────

/// A single item in a PRINT/CONSOLE statement.
pub const PrintItem = struct {
    expr: ExprPtr,
    semicolon: bool = false,
    comma: bool = false,
};

pub const PrintStmt = struct {
    file_number: ?ExprPtr = null, // Expression for file number (null for console)
    items: []PrintItem,
    trailing_newline: bool = true,
    /// PRINT USING support.
    has_using: bool = false,
    format_expr: ?ExprPtr = null,
    using_values: []ExprPtr = &.{},
};

pub const ConsoleStmt = struct {
    items: []PrintItem,
    trailing_newline: bool = true,
};

pub const InputStmt = struct {
    prompt: []const u8 = "",
    variables: []const []const u8,
    file_number: ?ExprPtr = null, // Expression for file number (null for console)
    is_line_input: bool = false,
};

pub const InputAtStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    prompt: []const u8 = "",
    variable: []const u8,
    fg_color: ?ExprPtr = null,
    bg_color: ?ExprPtr = null,
};

pub const PrintAtStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    items: []PrintItem,
    fg: ?ExprPtr = null,
    bg: ?ExprPtr = null,
    has_explicit_colors: bool = false,
    has_using: bool = false,
    format_expr: ?ExprPtr = null,
    using_values: []ExprPtr = &.{},
};

pub const LetStmt = struct {
    variable: []const u8,
    type_suffix: ?Tag = null,
    indices: []ExprPtr = &.{},
    member_chain: []const []const u8 = &.{},
    value: ExprPtr,
};

pub const MidAssignStmt = struct {
    variable: []const u8,
    position: ExprPtr,
    length: ?ExprPtr = null,
    replacement: ExprPtr,
};

pub const SliceAssignStmt = struct {
    variable: []const u8,
    start: ExprPtr,
    end_expr: ExprPtr,
    replacement: ExprPtr,
};

pub const GotoStmt = struct {
    line_number: i32 = 0,
    label: []const u8 = "",
    is_label: bool = false,
};

pub const GosubStmt = struct {
    line_number: i32 = 0,
    label: []const u8 = "",
    is_label: bool = false,
};

pub const OnGotoStmt = struct {
    selector: ExprPtr,
    labels: []const []const u8,
    line_numbers: []i32,
    is_label_list: []bool,
};

pub const OnGosubStmt = struct {
    selector: ExprPtr,
    labels: []const []const u8,
    line_numbers: []i32,
    is_label_list: []bool,
};

pub const OnCallStmt = struct {
    selector: ExprPtr,
    function_names: []const []const u8,
};

pub const EventHandlerType = enum {
    call,
    goto_handler,
    gosub_handler,
};

pub const OnEventStmt = struct {
    event_name: []const u8,
    handler_type: EventHandlerType = .call,
    target: []const u8 = "",
    is_line_number: bool = false,
};

pub const ReturnStmt = struct {
    return_value: ?ExprPtr = null,
};

pub const ExitStmt = struct {
    pub const ExitType = enum {
        for_loop,
        do_loop,
        while_loop,
        repeat_loop,
        function,
        sub,
    };
    exit_type: ExitType,
};

pub const IfStmt = struct {
    pub const ElseIfClause = struct {
        condition: ExprPtr,
        statements: []StmtPtr,
    };

    condition: ExprPtr,
    then_statements: []StmtPtr,
    elseif_clauses: []ElseIfClause = &.{},
    else_statements: []StmtPtr = &.{},
    goto_line: i32 = 0,
    has_goto: bool = false,
    is_multi_line: bool = false,
};

pub const CaseStmt = struct {
    pub const WhenClause = struct {
        values: []ExprPtr = &.{},
        is_case_is: bool = false,
        case_is_operator: Tag = .equal,
        case_is_right_expr: ?ExprPtr = null,
        is_range: bool = false,
        range_start: ?ExprPtr = null,
        range_end: ?ExprPtr = null,
        statements: []StmtPtr = &.{},
    };

    case_expression: ExprPtr,
    when_clauses: []WhenClause,
    otherwise_statements: []StmtPtr = &.{},
};

pub const MatchTypeStmt = struct {
    pub const CaseArm = struct {
        type_keyword: []const u8 = "",
        atom_type_tag: i32 = 0,
        binding_variable: []const u8 = "",
        binding_suffix: ?Tag = null,
        body: []StmtPtr = &.{},
        is_class_match: bool = false,
        match_class_name: []const u8 = "",
        is_udt_match: bool = false,
        udt_type_name: []const u8 = "",
    };

    match_expression: ExprPtr,
    case_arms: []CaseArm,
    case_else_body: []StmtPtr = &.{},
};

pub const ForStmt = struct {
    variable: []const u8,
    start: ExprPtr,
    end_expr: ExprPtr,
    step: ?ExprPtr = null,
    body: []StmtPtr = &.{},
};

pub const ForInStmt = struct {
    variable: []const u8,
    index_variable: []const u8 = "",
    array: ExprPtr,
    inferred_type: i32 = 0,
    body: []StmtPtr = &.{},
};

pub const NextStmt = struct {
    variable: []const u8 = "",
};

pub const WhileStmt = struct {
    condition: ExprPtr,
    body: []StmtPtr = &.{},
};

pub const RepeatStmt = struct {
    body: []StmtPtr = &.{},
    condition: ?ExprPtr = null,
};

pub const UntilStmt = struct {
    condition: ExprPtr,
};

pub const DoStmt = struct {
    pub const ConditionType = enum { none, while_cond, until_cond };

    pre_condition_type: ConditionType = .none,
    pre_condition: ?ExprPtr = null,
    post_condition_type: ConditionType = .none,
    post_condition: ?ExprPtr = null,
    body: []StmtPtr = &.{},
};

pub const LoopStmt = struct {
    pub const ConditionType = enum { none, while_cond, until_cond };

    condition_type: ConditionType = .none,
    condition: ?ExprPtr = null,
};

pub const TryCatchStmt = struct {
    pub const CatchClause = struct {
        error_codes: []i32 = &.{},
        block: []StmtPtr = &.{},
    };

    try_block: []StmtPtr,
    catch_clauses: []CatchClause = &.{},
    finally_block: []StmtPtr = &.{},
    has_finally: bool = false,
};

pub const ThrowStmt = struct {
    error_code: ?ExprPtr = null,
};

pub const DimStmt = struct {
    pub const ArrayDim = struct {
        name: []const u8,
        type_suffix: ?Tag = null,
        dimensions: []ExprPtr = &.{},
        as_type_name: []const u8 = "",
        as_type_keyword: ?Tag = null,
        has_as_type: bool = false,
        initializer: ?ExprPtr = null,
    };

    arrays: []ArrayDim,
};

pub const RedimStmt = struct {
    pub const ArrayRedim = struct {
        name: []const u8,
        dimensions: []ExprPtr,
    };

    arrays: []ArrayRedim,
    preserve: bool = false,
};

pub const EraseStmt = struct {
    array_names: []const []const u8,
};

pub const SwapStmt = struct {
    var1: []const u8,
    var1_indices: []ExprPtr = &.{},
    var1_member_chain: []const []const u8 = &.{},
    var2: []const u8,
    var2_indices: []ExprPtr = &.{},
    var2_member_chain: []const []const u8 = &.{},
};

pub const IncDecStmt = struct {
    var_name: []const u8,
    indices: []ExprPtr = &.{},
    member_chain: []const []const u8 = &.{},
    amount_expr: ?ExprPtr = null,
};

pub const LocalStmt = struct {
    pub const LocalVar = struct {
        name: []const u8,
        type_suffix: ?Tag = null,
        initial_value: ?ExprPtr = null,
        as_type_name: []const u8 = "",
        has_as_type: bool = false,
    };

    variables: []LocalVar,
};

pub const GlobalStmt = struct {
    pub const GlobalVar = struct {
        name: []const u8,
        type_suffix: ?Tag = null,
        initial_value: ?ExprPtr = null,
        as_type_name: []const u8 = "",
        has_as_type: bool = false,
    };

    variables: []GlobalVar,
};

pub const SharedStmt = struct {
    pub const SharedVariable = struct {
        name: []const u8,
        type_suffix: ?Tag = null,
        as_type_name: []const u8 = "",
        has_as_type: bool = false,
    };

    variables: []SharedVariable,
};

pub const ConstantStmt = struct {
    name: []const u8,
    value: ExprPtr,
};

pub const TypeDeclStmt = struct {
    pub const SIMDType = enum {
        none,
        pair,
        quad,
        v2d,
        v4s,
        v8h,
        v16b,
        v2s,
        v4h,
        v8b,
        v4s_pad1,
    };

    pub const SIMDInfo = struct {
        simd_type: SIMDType = .none,
        lane_count: i32 = 0,
        physical_lanes: i32 = 0,
        lane_bit_width: i32 = 0,
        total_bytes: i32 = 0,
        is_full_q: bool = false,
        is_padded: bool = false,
        is_floating_point: bool = false,
        lane_base_type: i32 = 0,

        pub fn isValid(self: SIMDInfo) bool {
            return self.simd_type != .none;
        }
    };

    pub const TypeField = struct {
        name: []const u8,
        type_name: []const u8 = "",
        built_in_type: ?Tag = null,
        is_built_in: bool = true,
    };

    type_name: []const u8,
    fields: []TypeField,
    simd_type: SIMDType = .none,
    simd_info: SIMDInfo = .{},
};

pub const DataStmt = struct {
    values: []const []const u8,
};

pub const ReadStmt = struct {
    variables: []const []const u8,
};

pub const RestoreStmt = struct {
    line_number: i32 = 0,
    label: []const u8 = "",
    is_label: bool = false,
};

pub const OptionStmt = struct {
    pub const OptionType = enum {
        bitwise,
        logical,
        base,
        explicit_opt,
        unicode,
        ascii,
        detectstring,
        error_opt,
        cancellable,
        bounds_check,
        samm,
    };

    option_type: OptionType,
    value: i32 = 0,
};

pub const FunctionStmt = struct {
    function_name: []const u8,
    return_type_suffix: ?Tag = null,
    return_type_as_name: []const u8 = "",
    has_return_as_type: bool = false,
    parameters: []const []const u8,
    parameter_types: []const ?Tag,
    parameter_as_types: []const []const u8,
    parameter_is_byref: []bool,
    body: []StmtPtr,
};

pub const SubStmt = struct {
    sub_name: []const u8,
    parameters: []const []const u8,
    parameter_types: []const ?Tag,
    parameter_as_types: []const []const u8,
    parameter_is_byref: []bool,
    body: []StmtPtr,
};

pub const DefStmt = struct {
    function_name: []const u8,
    parameters: []const []const u8,
    parameter_suffixes: []const ?Tag,
    body: ExprPtr,
};

pub const CallStmt = struct {
    sub_name: []const u8,
    arguments: []ExprPtr,
    /// If set, this is a method call expression wrapped as a statement.
    method_call_expr: ?ExprPtr = null,
};

pub const LabelStmt = struct {
    label_name: []const u8,
};

// ── Workers (concurrency) ───────────────────────────────────────────────

/// WORKER declaration — an isolated function that runs on a background thread.
pub const WorkerStmt = struct {
    worker_name: []const u8,
    return_type_suffix: ?Tag = null,
    return_type_as_name: []const u8 = "",
    has_return_as_type: bool = false,
    parameters: []const []const u8,
    parameter_types: []const ?Tag,
    parameter_as_types: []const []const u8,
    body: []StmtPtr,
};

/// UNMARSHALL target, source — reconstruct an array or UDT from a marshalled blob.
pub const UnmarshallStmt = struct {
    target_variable: []const u8,
    source_expr: ExprPtr,
};

/// SPAWN WorkerName(args...) — starts a worker, returns a FUTURE handle.
pub const SpawnExpr = struct {
    worker_name: []const u8,
    arguments: []ExprPtr,
};

/// AWAIT future — blocks until worker finishes, returns its result.
pub const AwaitExpr = struct {
    future: ExprPtr,
};

/// READY(future) — non-blocking check, returns 1 (true) or 0 (false).
pub const ReadyExpr = struct {
    future: ExprPtr,
};

/// MARSHALL(variable) — deep-copy an array or UDT into a portable blob.
/// Returns an opaque pointer (stored as DOUBLE) for passing to workers.
pub const MarshallExpr = struct {
    variable_name: []const u8,
};

// ── CLASS / Object system ───────────────────────────────────────────────

pub const MethodStmt = struct {
    method_name: []const u8,
    parameters: []const []const u8 = &.{},
    parameter_types: []const ?Tag = &.{},
    parameter_as_types: []const []const u8 = &.{},
    parameter_is_byref: []bool = &.{},
    return_type_suffix: ?Tag = null,
    return_type_as_name: []const u8 = "",
    has_return_type: bool = false,
    body: []StmtPtr = &.{},
};

pub const ConstructorStmt = struct {
    parameters: []const []const u8 = &.{},
    parameter_types: []const ?Tag = &.{},
    parameter_as_types: []const []const u8 = &.{},
    parameter_is_byref: []bool = &.{},
    body: []StmtPtr = &.{},
    has_super_call: bool = false,
    super_args: []ExprPtr = &.{},
};

pub const DestructorStmt = struct {
    body: []StmtPtr = &.{},
};

pub const ClassStmt = struct {
    class_name: []const u8,
    parent_class_name: []const u8 = "",
    fields: []TypeDeclStmt.TypeField = &.{},
    constructor: ?*ConstructorStmt = null,
    destructor: ?*DestructorStmt = null,
    methods: []*MethodStmt = &.{},
};

pub const DeleteStmt = struct {
    variable_name: []const u8,
};

// ── File I/O ────────────────────────────────────────────────────────────

pub const OpenStmt = struct {
    filename: ExprPtr, // Expression for filename (string)
    mode: []const u8 = "", // "INPUT", "OUTPUT", "APPEND"
    file_number: ExprPtr, // Expression for file number (integer)
    record_length: i32 = 0,
};

pub const CloseStmt = struct {
    file_number: ?ExprPtr = null, // Expression for file number (null if close_all)
    close_all: bool = false,
};

// ── Process Execution ───────────────────────────────────────────────────

pub const ShellStmt = struct {
    command: ExprPtr, // Command expression (string)
};

pub const SpitStmt = struct {
    filename: ExprPtr, // Filename expression (string)
    content: ExprPtr, // Content expression (string)
};

// ── Graphics ────────────────────────────────────────────────────────────

pub const ColorStmt = struct {
    fg: ExprPtr,
    bg: ?ExprPtr = null,
};

pub const WaitStmt = struct {
    duration: ExprPtr,
};

pub const PsetStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    color: ?ExprPtr = null,
};

pub const LineStmt = struct {
    x1: ExprPtr,
    y1: ExprPtr,
    x2: ExprPtr,
    y2: ExprPtr,
    color: ?ExprPtr = null,
};

pub const RectStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    w: ExprPtr,
    h: ExprPtr,
    color: ?ExprPtr = null,
    filled: bool = false,
};

pub const CircleStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    radius: ExprPtr,
    color: ?ExprPtr = null,
    filled: bool = false,
};

pub const HVLineStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    length: ExprPtr,
    color: ?ExprPtr = null,
};

// ── Text layer ──────────────────────────────────────────────────────────

pub const AtStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
};

pub const TextputStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    text: ExprPtr,
    fg: ?ExprPtr = null,
    bg: ?ExprPtr = null,
};

pub const TcharStmt = struct {
    x: ExprPtr,
    y: ExprPtr,
    char_expr: ExprPtr,
    fg: ?ExprPtr = null,
    bg: ?ExprPtr = null,
};

pub const TgridStmt = struct {
    cols: ExprPtr,
    rows: ExprPtr,
};

pub const TscrollStmt = struct {
    dx: ExprPtr,
    dy: ExprPtr,
};

pub const TclearStmt = struct {
    x: ?ExprPtr = null,
    y: ?ExprPtr = null,
    w: ?ExprPtr = null,
    h: ?ExprPtr = null,
};

pub const LocateStmt = struct {
    row: ExprPtr,
    col: ?ExprPtr = null,
};

// ── Sprites ─────────────────────────────────────────────────────────────

pub const SpriteStmt = struct {
    sprite_id: ExprPtr,
};

pub const SprmoveStmt = struct {
    sprite_id: ExprPtr,
    x: ExprPtr,
    y: ExprPtr,
};

pub const SprposStmt = struct {
    sprite_id: ExprPtr,
    x: ExprPtr,
    y: ExprPtr,
    scale_x: ?ExprPtr = null,
    scale_y: ?ExprPtr = null,
    rotation: ?ExprPtr = null,
};

pub const SprtintStmt = struct {
    sprite_id: ExprPtr,
    color: ExprPtr,
};

pub const SprscaleStmt = struct {
    sprite_id: ExprPtr,
    scale_x: ExprPtr,
    scale_y: ?ExprPtr = null,
};

pub const SprrotStmt = struct {
    sprite_id: ExprPtr,
    angle: ExprPtr,
};

// ── Audio ───────────────────────────────────────────────────────────────

pub const PlayStmt = struct {
    filename: ExprPtr,
    format: []const u8 = "",
    has_format: bool = false,
    wav_output: ?ExprPtr = null,
    has_wav_output: bool = false,
    slot_number: ?ExprPtr = null,
    has_slot: bool = false,
    fast_render: bool = false,
};

pub const PlaySoundStmt = struct {
    sound_id: ExprPtr,
    volume: ?ExprPtr = null,
    cap_duration: ?ExprPtr = null,
    has_cap_duration: bool = false,
};

// ── Timer events ────────────────────────────────────────────────────────

pub const TimeUnit = enum {
    milliseconds,
    seconds,
    frames,
};

pub const TimerEventStmt = struct {
    duration: ExprPtr,
    unit: TimeUnit = .milliseconds,
    handler_name: []const u8 = "",
    inline_body: []StmtPtr = &.{},
    is_inline_handler: bool = false,
};

pub const RunStmt = struct {
    until_condition: ?ExprPtr = null,
};

pub const TimerStopStmt = struct {
    pub const StopTarget = enum { handler, timer_id, all };

    target_type: StopTarget = .all,
    handler_name: []const u8 = "",
    timer_id: ?ExprPtr = null,
};

pub const TimerIntervalStmt = struct {
    interval: ExprPtr,
};

// ── Miscellaneous ───────────────────────────────────────────────────────

pub const RemStmt = struct {
    comment: []const u8,
};

pub const ExpressionStmtData = struct {
    name: []const u8,
    arguments: []ExprPtr = &.{},
};

pub const KbRawStmt = struct {
    enable: ExprPtr,
};

pub const KbEchoStmt = struct {
    enable: ExprPtr,
};

pub const RegistryCommandStmt = struct {
    name: []const u8,
    arguments: []ExprPtr = &.{},
};

// ─── Program / Program Line ─────────────────────────────────────────────────

pub const ProgramLine = struct {
    line_number: i32 = 0,
    statements: []StmtPtr,
    loc: SourceLocation = .{},
};

pub const Program = struct {
    lines: []ProgramLine,
};

// ─── AST Allocator Helpers ──────────────────────────────────────────────────

/// Convenience functions for building AST nodes with an allocator.
pub const Builder = struct {
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Builder {
        return .{ .allocator = allocator };
    }

    /// Allocate and initialize an Expression on the heap.
    pub fn expr(self: Builder, loc: SourceLocation, data: ExprData) !ExprPtr {
        const node = try self.allocator.create(Expression);
        node.* = .{ .loc = loc, .data = data };
        return node;
    }

    /// Allocate and initialize a Statement on the heap.
    pub fn stmt(self: Builder, loc: SourceLocation, data: StmtData) !StmtPtr {
        const node = try self.allocator.create(Statement);
        node.* = .{ .loc = loc, .data = data };
        return node;
    }

    /// Allocate a slice and copy items into it.
    pub fn dupeSlice(self: Builder, comptime T: type, items: []const T) ![]T {
        return self.allocator.dupe(T, items);
    }

    /// Allocate a slice from an ArrayList.
    pub fn dupeList(self: Builder, comptime T: type, list: std.ArrayList(T)) ![]T {
        return self.allocator.dupe(T, list.items);
    }

    /// Create a number expression.
    pub fn numberExpr(self: Builder, loc: SourceLocation, value: f64) !ExprPtr {
        return self.expr(loc, .{ .number = .{ .value = value } });
    }

    /// Create a string literal expression.
    pub fn stringExpr(self: Builder, loc: SourceLocation, value: []const u8) !ExprPtr {
        return self.expr(loc, .{ .string_lit = .{ .value = value } });
    }

    /// Create a variable expression.
    pub fn variableExpr(self: Builder, loc: SourceLocation, name: []const u8, suffix: ?Tag) !ExprPtr {
        return self.expr(loc, .{ .variable = .{ .name = name, .type_suffix = suffix } });
    }

    /// Create a binary expression.
    pub fn binaryExpr(self: Builder, loc: SourceLocation, left: ExprPtr, op: Tag, right: ExprPtr) !ExprPtr {
        return self.expr(loc, .{ .binary = .{ .left = left, .op = op, .right = right } });
    }

    /// Create an END statement.
    pub fn endStmt(self: Builder, loc: SourceLocation) !StmtPtr {
        return self.stmt(loc, .{ .end_stmt = {} });
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "build simple expression" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{ .line = 1, .column = 1 };

    const left = try b.numberExpr(loc, 1.0);
    defer allocator.destroy(left);
    const right = try b.numberExpr(loc, 2.0);
    defer allocator.destroy(right);
    const bin = try b.binaryExpr(loc, left, .plus, right);
    defer allocator.destroy(bin);

    try std.testing.expectEqual(ExprData.binary, std.meta.activeTag(bin.data));
    try std.testing.expectEqual(Tag.plus, bin.data.binary.op);
    try std.testing.expect(bin.data.binary.left.data.number.value == 1.0);
    try std.testing.expect(bin.data.binary.right.data.number.value == 2.0);
}

test "build variable expression with suffix" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const v = try b.variableExpr(loc, "myVar", .type_string);
    defer allocator.destroy(v);

    try std.testing.expectEqual(ExprData.variable, std.meta.activeTag(v.data));
    try std.testing.expectEqualStrings("myVar", v.data.variable.name);
    try std.testing.expectEqual(Tag.type_string, v.data.variable.type_suffix.?);
}

test "build end statement" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{ .line = 10, .column = 1 };
    const s = try b.endStmt(loc);
    defer allocator.destroy(s);

    try std.testing.expectEqual(StmtData.end_stmt, std.meta.activeTag(s.data));
    try std.testing.expectEqual(@as(u32, 10), s.loc.line);
}

test "create expression with named fields" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const val = try b.numberExpr(loc, 3.14);
    defer allocator.destroy(val);

    const args = try allocator.alloc(ExprPtr, 1);
    defer allocator.free(args);
    args[0] = val;

    const names: []const []const u8 = &.{"x"};

    const create = try b.expr(loc, .{ .create = .{
        .type_name = "Point",
        .arguments = args,
        .is_named = true,
        .field_names = names,
    } });
    defer allocator.destroy(create);

    try std.testing.expectEqual(ExprData.create, std.meta.activeTag(create.data));
    try std.testing.expect(create.data.create.is_named);
    try std.testing.expectEqualStrings("Point", create.data.create.type_name);
    try std.testing.expectEqualStrings("x", create.data.create.field_names[0]);
}

test "if statement structure" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{ .line = 5, .column = 1 };
    const cond = try b.numberExpr(loc, 1.0);
    defer allocator.destroy(cond);

    const body_stmt = try b.endStmt(loc);
    defer allocator.destroy(body_stmt);

    const then_stmts = try allocator.alloc(StmtPtr, 1);
    defer allocator.free(then_stmts);
    then_stmts[0] = body_stmt;

    const if_s = try b.stmt(loc, .{ .if_stmt = .{
        .condition = cond,
        .then_statements = then_stmts,
        .is_multi_line = true,
    } });
    defer allocator.destroy(if_s);

    try std.testing.expectEqual(StmtData.if_stmt, std.meta.activeTag(if_s.data));
    try std.testing.expect(if_s.data.if_stmt.is_multi_line);
    try std.testing.expectEqual(@as(usize, 1), if_s.data.if_stmt.then_statements.len);
}

test "print statement with items" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const str = try b.stringExpr(loc, "hello");
    defer allocator.destroy(str);

    const items = try allocator.alloc(PrintItem, 1);
    defer allocator.free(items);
    items[0] = .{ .expr = str, .semicolon = true };

    const print = try b.stmt(loc, .{ .print = .{
        .items = items,
        .trailing_newline = false,
    } });
    defer allocator.destroy(print);

    try std.testing.expectEqual(StmtData.print, std.meta.activeTag(print.data));
    try std.testing.expectEqual(@as(usize, 1), print.data.print.items.len);
    try std.testing.expect(!print.data.print.trailing_newline);
}

test "for statement" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const start = try b.numberExpr(loc, 1.0);
    defer allocator.destroy(start);
    const end_e = try b.numberExpr(loc, 10.0);
    defer allocator.destroy(end_e);
    const step = try b.numberExpr(loc, 2.0);
    defer allocator.destroy(step);

    const for_s = try b.stmt(loc, .{ .for_stmt = .{
        .variable = "i",
        .start = start,
        .end_expr = end_e,
        .step = step,
    } });
    defer allocator.destroy(for_s);

    try std.testing.expectEqual(StmtData.for_stmt, std.meta.activeTag(for_s.data));
    try std.testing.expectEqualStrings("i", for_s.data.for_stmt.variable);
    try std.testing.expect(for_s.data.for_stmt.step != null);
}

test "type declaration statement" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const fields = try allocator.alloc(TypeDeclStmt.TypeField, 2);
    defer allocator.free(fields);
    fields[0] = .{ .name = "x", .built_in_type = .kw_double };
    fields[1] = .{ .name = "y", .built_in_type = .kw_double };

    const type_s = try b.stmt(loc, .{ .type_decl = .{
        .type_name = "Point",
        .fields = fields,
    } });
    defer allocator.destroy(type_s);

    try std.testing.expectEqual(StmtData.type_decl, std.meta.activeTag(type_s.data));
    try std.testing.expectEqualStrings("Point", type_s.data.type_decl.type_name);
    try std.testing.expectEqual(@as(usize, 2), type_s.data.type_decl.fields.len);
}

test "class statement" {
    const allocator = std.testing.allocator;
    const b = Builder.init(allocator);

    const loc = SourceLocation{};
    const cls = try b.stmt(loc, .{ .class = .{
        .class_name = "Animal",
        .parent_class_name = "Object",
    } });
    defer allocator.destroy(cls);

    try std.testing.expectEqual(StmtData.class, std.meta.activeTag(cls.data));
    try std.testing.expectEqualStrings("Animal", cls.data.class.class_name);
    try std.testing.expectEqualStrings("Object", cls.data.class.parent_class_name);
}

test "all expression variants can be constructed" {
    // Smoke test: ensure every ExprData variant is a valid union tag
    const variants = comptime std.meta.fields(ExprData);
    try std.testing.expect(variants.len > 0);
    // Just verify we have the expected count of expression types
    try std.testing.expectEqual(@as(usize, 23), variants.len);
}

test "all statement variants can be constructed" {
    // Smoke test: ensure every StmtData variant is a valid union tag
    const variants = comptime std.meta.fields(StmtData);
    try std.testing.expect(variants.len > 0);
    // Verify we have a substantial number of statement types
    try std.testing.expect(variants.len >= 60);
}
