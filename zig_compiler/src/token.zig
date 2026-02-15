//! Token types and token structure for the FasterBASIC compiler.
//!
//! This module defines the complete set of token types recognized by the lexer,
//! mirroring the original C++ TokenType enum but using Zig's tagged unions and
//! enums for type safety.

const std = @import("std");

/// Source location for error reporting.
pub const SourceLocation = struct {
    line: u32 = 1,
    column: u32 = 1,

    pub fn format(self: SourceLocation, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{}:{}", .{ self.line, self.column });
    }
};

/// A single token produced by the lexer.
pub const Token = struct {
    tag: Tag,
    /// The raw source text of this token (slice into source buffer).
    lexeme: []const u8 = "",
    /// For NUMBER tokens, the parsed numeric value.
    number_value: f64 = 0.0,
    /// Whether a string literal contains non-ASCII bytes.
    has_non_ascii: bool = false,
    /// Source location where this token starts.
    location: SourceLocation = .{},

    pub fn is(self: Token, tag: Tag) bool {
        return self.tag == tag;
    }

    pub fn isNot(self: Token, tag: Tag) bool {
        return self.tag != tag;
    }

    pub fn isKeyword(self: Token) bool {
        return @intFromEnum(self.tag) >= @intFromEnum(Tag.kw_print) and
            @intFromEnum(self.tag) <= @intFromEnum(Tag.kw_typeof);
    }

    pub fn isOperator(self: Token) bool {
        return @intFromEnum(self.tag) >= @intFromEnum(Tag.plus) and
            @intFromEnum(self.tag) <= @intFromEnum(Tag.kw_imp);
    }

    pub fn isComparison(self: Token) bool {
        return switch (self.tag) {
            .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal => true,
            else => false,
        };
    }

    pub fn isArithmetic(self: Token) bool {
        return switch (self.tag) {
            .plus, .minus, .multiply, .divide, .int_divide, .power, .kw_mod => true,
            else => false,
        };
    }

    pub fn isTypeSuffix(self: Token) bool {
        return switch (self.tag) {
            .type_int, .type_float, .type_double, .type_string, .type_byte, .type_short, .ampersand => true,
            else => false,
        };
    }

    pub fn isTypeKeyword(self: Token) bool {
        return switch (self.tag) {
            .kw_integer, .kw_double, .kw_single, .kw_string_type, .kw_long, .kw_byte, .kw_short, .kw_ubyte, .kw_ushort, .kw_uinteger, .kw_ulong, .kw_marshalled, .kw_hashmap, .kw_list => true,
            else => false,
        };
    }

    pub fn isEndOfStatement(self: Token) bool {
        return switch (self.tag) {
            .end_of_line, .end_of_file, .colon => true,
            else => false,
        };
    }

    pub fn format(self: Token, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}", .{@tagName(self.tag)});
        if (self.lexeme.len > 0) {
            try writer.print("(\"{s}\")", .{self.lexeme});
        }
    }
};

/// Token tag — the kind of token.
///
/// The ordering of variants matters: keywords are grouped together, operators
/// are grouped together, etc., to allow range checks in `isKeyword()` etc.
pub const Tag = enum(u16) {
    // ── End markers ──────────────────────────────────────────────────────
    end_of_file,
    end_of_line,

    // ── Literals ─────────────────────────────────────────────────────────
    number, // 123, 3.14, 1.5e10
    string, // "Hello World"

    // ── Identifiers ──────────────────────────────────────────────────────
    identifier,

    // ── Keywords (control flow) ──────────────────────────────────────────
    // NOTE: kw_print must be the first keyword for isKeyword() range check.
    kw_print,
    kw_console,
    kw_input,
    kw_let,
    kw_goto,
    kw_gosub,
    kw_return,
    kw_if,
    kw_then,
    kw_else,
    kw_elseif,
    kw_endif,
    kw_for,
    kw_each,
    kw_to,
    kw_step,
    kw_in,
    kw_next,
    kw_while,
    kw_wend,
    kw_repeat,
    kw_until,
    kw_do,
    kw_loop,
    kw_done,
    kw_end,
    kw_exit,
    kw_case,
    kw_select,
    kw_of,
    kw_when,
    kw_is,
    kw_otherwise,
    kw_endcase,
    kw_match,
    kw_endmatch,

    // ── Keywords (exception handling) ────────────────────────────────────
    kw_try,
    kw_catch,
    kw_finally,
    kw_throw,
    kw_err,
    kw_erl,

    // ── Keywords (compiler directives) ───────────────────────────────────
    kw_option,
    kw_bitwise,
    kw_logical,
    kw_base,
    kw_explicit,
    kw_unicode,
    kw_ascii,
    kw_detectstring,
    kw_error,
    kw_include,
    kw_once,
    kw_cancellable,
    kw_bounds_check,
    kw_force_yield,
    kw_samm,
    kw_neon,

    // ── Keywords (functions & procedures) ────────────────────────────────
    kw_sub,
    kw_function,
    kw_endsub,
    kw_endfunction,

    // ── Keywords (concurrency — workers) ─────────────────────────────────
    kw_worker,
    kw_endworker,
    kw_spawn,
    kw_await,
    kw_ready,
    kw_future,
    kw_marshall,
    kw_unmarshall,
    // ── Keywords (worker messaging) ──────────────────────────────────────
    kw_send,
    kw_receive,
    kw_hasmessage,
    kw_parent,
    kw_cancel,
    kw_cancelled,
    kw_call,
    kw_local,
    kw_global,
    kw_shared,
    kw_byref,
    kw_byval,
    kw_as,
    kw_def,
    kw_fn,
    kw_iif,
    kw_mid,
    kw_left,
    kw_right,
    kw_on,
    kw_onevent,
    kw_off,

    // ── Keywords (type names for AS declarations) ────────────────────────
    kw_integer,
    kw_double,
    kw_single,
    kw_string_type,
    kw_long,
    kw_byte,
    kw_short,
    kw_ubyte,
    kw_ushort,
    kw_uinteger,
    kw_ulong,
    kw_marshalled,
    kw_hashmap,
    kw_list,

    // ── Keywords (data) ──────────────────────────────────────────────────
    kw_dim,
    kw_redim,
    kw_erase,
    kw_preserve,
    kw_swap,
    kw_inc,
    kw_dec,
    kw_data,
    kw_read,
    kw_restore,
    kw_constant,
    kw_type,
    kw_endtype,

    // ── Keywords (CLASS & object system) ─────────────────────────────────
    kw_class,
    kw_extends,
    kw_constructor,
    kw_destructor,
    kw_method,
    kw_me,
    kw_super,
    kw_new,
    kw_create,
    kw_delete,
    kw_nothing,

    // ── Keywords (file I/O) ──────────────────────────────────────────────
    kw_open,
    kw_close,
    kw_print_stream,
    kw_input_stream,
    kw_line_input_stream,
    kw_line_input,
    kw_write_stream,
    kw_slurp,
    kw_spit,
    kw_field,
    kw_lset,
    kw_rset,
    kw_put,
    kw_seek,
    kw_loc,
    kw_lof,

    // ── Keywords (misc) ──────────────────────────────────────────────────
    kw_rem,
    kw_cls,
    kw_color,
    kw_wrch,
    kw_wrstr,
    kw_wait,
    kw_wait_ms,
    kw_shell,
    kw_system,
    kw_command,
    kw_commandcount,

    // ── Keywords (graphics) ──────────────────────────────────────────────
    kw_pset,
    kw_rect,
    kw_circle,
    kw_circlef,
    kw_gcls,
    kw_clg,
    kw_hline,
    kw_vline,

    // ── Keywords (text layer) ────────────────────────────────────────────
    kw_at,
    kw_locate,
    kw_textput,
    kw_print_at,
    kw_input_at,
    kw_tchar,
    kw_tgrid,
    kw_tscroll,
    kw_tclear,

    // ── Keywords (terminal I/O - VDU output) ─────────────────────────────
    kw_vducls,
    kw_vdueol,
    kw_vdueos,
    kw_vdupos,
    kw_vducursor,
    kw_vduup,
    kw_vdudown,
    kw_vduleft,
    kw_vduright,
    kw_vdumove,
    kw_vducolor,
    kw_vducolour,
    kw_vdurgb,
    kw_vdureset,
    kw_vdustyle,
    kw_vduscreen,
    kw_vduposx,
    kw_vduposy,
    kw_vduwidth,
    kw_vduheight,
    kw_vdusize,

    // ── Keywords (terminal I/O - cursor control) ─────────────────────────
    kw_cursor_on,
    kw_cursor_off,
    kw_cursor_hide,
    kw_cursor_show,
    kw_cursor_save,
    kw_cursor_restore,

    // ── Keywords (terminal I/O - color & style) ──────────────────────────
    kw_colour,
    kw_color_reset,
    kw_rgb,
    kw_rgbfg,
    kw_rgbbg,
    kw_bold,
    kw_italic,
    kw_underline,
    kw_blink,
    kw_inverse,
    kw_style_reset,
    kw_normal,

    // ── Keywords (terminal I/O - screen modes) ───────────────────────────
    kw_screen_alternate,
    kw_screen_main,

    // ── Keywords (terminal I/O - KB input) ───────────────────────────────
    kw_kbget,
    kw_kbhit,
    kw_kbpeek,
    kw_kbcode,
    kw_kbspecial,
    kw_kbmod,
    kw_kbraw,
    kw_kbecho,
    kw_kbflush,
    kw_kbclear,
    kw_kbcount,
    kw_flush,
    kw_beginpaint,
    kw_endpaint,
    kw_screenwidth,
    kw_screenheight,
    kw_kbinput,
    kw_inkey,

    // ── Keywords (terminal I/O - position queries) ───────────────────────
    kw_pos,
    kw_row,
    kw_csrlin,

    // ── Keywords (sprites) ───────────────────────────────────────────────
    kw_sprload,
    kw_sprfree,
    kw_sprshow,
    kw_sprhide,
    kw_sprmove,
    kw_sprpos,
    kw_sprtint,
    kw_sprscale,
    kw_sprrot,
    kw_sprexplode,

    // ── Keywords (audio) ─────────────────────────────────────────────────
    kw_play,
    kw_play_sound,

    // ── Keywords (timing) ────────────────────────────────────────────────
    kw_sleep,
    kw_vsync,
    kw_after,
    kw_every,
    kw_afterframes,
    kw_everyframe,
    kw_timer,
    kw_stop,
    kw_run,

    // ── Keywords (time units) ────────────────────────────────────────────
    kw_ms,
    kw_secs,
    kw_minutes,
    kw_frames,

    // ── Keywords (hashmap methods) ───────────────────────────────────────
    kw_haskey,
    kw_keys,
    kw_size,
    kw_clear,
    kw_remove,

    // ── Keywords (list methods) ──────────────────────────────────────────
    kw_append,
    kw_prepend,
    kw_head,
    kw_tail,
    kw_rest,
    kw_length,
    kw_empty,
    kw_contains,
    kw_indexof,
    kw_join,
    kw_copy,
    kw_reverse,
    kw_shift,
    kw_pop,
    kw_extend,
    kw_insert,
    kw_get,
    // NOTE: kw_typeof must be the last keyword for isKeyword() range check.
    kw_typeof,

    // ── Keywords (special) ───────────────────────────────────────────────
    kw_using,

    // ── Registry-based modular commands ──────────────────────────────────
    registry_command,
    registry_function,

    // ── Operators (arithmetic) ───────────────────────────────────────────
    // NOTE: plus must be the first operator for isOperator() range check.
    plus, // +
    minus, // -
    multiply, // *
    divide, // /
    int_divide, // backslash
    power, // ^
    kw_mod, // MOD

    // ── Operators (comparison) ───────────────────────────────────────────
    equal, // =
    not_equal, // <> or !=
    less_than, // <
    less_equal, // <=
    greater_than, // >
    greater_equal, // >=

    // ── Operators (logical) ──────────────────────────────────────────────
    kw_and,
    kw_or,
    kw_not,
    kw_xor,
    kw_eqv,
    // NOTE: kw_imp must be the last operator for isOperator() range check.
    kw_imp,

    // ── Delimiters ───────────────────────────────────────────────────────
    lparen, // (
    rparen, // )
    comma, // ,
    semicolon, // ;
    colon, // :
    question, // ?
    dot, // .

    // ── Type suffixes ────────────────────────────────────────────────────
    type_int, // %
    type_float, // !
    type_double, // #
    type_string, // $
    type_byte, // @
    type_short, // ^ (when used as suffix)
    hash, // # (file stream indicator)
    percent, // % (integer suffix alternative name)
    ampersand, // & (long suffix)
    exclamation, // ! (single suffix alternative name)
    caret, // ^ (short suffix alternative name)
    at_suffix, // @ (byte suffix alternative name)

    // ── Error / Unknown ──────────────────────────────────────────────────
    unknown,

    /// Look up a keyword from its text representation (case-insensitive).
    /// Returns null if the text is not a keyword.
    /// Uses a general-purpose allocator (typically arena) for initialization.
    pub fn fromKeyword(text: []const u8, allocator: std.mem.Allocator) ?Tag {
        var buf: [32]u8 = undefined;
        if (text.len > buf.len) return null;
        const upper = toUpperBuf(text, &buf);

        const map = getKeywordMap(allocator) catch return null;
        return map.get(upper);
    }

    /// Return a human-readable name for this tag.
    pub fn name(self: Tag) []const u8 {
        return @tagName(self);
    }

    /// Convert a type-keyword tag to its corresponding suffix tag.
    /// e.g. kw_integer → type_int, kw_string_type → type_string, etc.
    pub fn asTypeToSuffix(self: Tag) ?Tag {
        return switch (self) {
            .kw_integer, .kw_uinteger => .type_int,
            .kw_double => .type_double,
            .kw_single => .type_float,
            .kw_string_type => .type_string,
            .kw_long, .kw_ulong => .ampersand,
            .kw_byte, .kw_ubyte => .type_byte,
            .kw_short, .kw_ushort => .type_short,
            .kw_marshalled => null,
            else => null,
        };
    }
};

// ─── Keyword map built at runtime (once) ────────────────────────────────────

const KeywordMap = std.StringHashMap(Tag);

var keyword_map_initialized = false;
var keyword_map: KeywordMap = undefined;
var keyword_map_mutex = std.Thread.Mutex{};

fn toUpperBuf(text: []const u8, buf: []u8) []const u8 {
    const len = @min(text.len, buf.len);
    for (0..len) |i| {
        buf[i] = std.ascii.toUpper(text[i]);
    }
    return buf[0..len];
}

fn initKeywordMap(_: std.mem.Allocator) !void {
    @setEvalBranchQuota(100000);
    // Use page_allocator for this process-lifetime singleton so it doesn't
    // appear as a leak when callers pass std.testing.allocator (GPA).
    keyword_map = KeywordMap.init(std.heap.page_allocator);
    const keywords = [_]struct { []const u8, Tag }{
        .{ "PRINT", .kw_print },
        .{ "CONSOLE", .kw_console },
        .{ "INPUT", .kw_input },
        .{ "LET", .kw_let },
        .{ "GOTO", .kw_goto },
        .{ "GOSUB", .kw_gosub },
        .{ "RETURN", .kw_return },
        .{ "IF", .kw_if },
        .{ "THEN", .kw_then },
        .{ "ELSE", .kw_else },
        .{ "ELSEIF", .kw_elseif },
        .{ "ENDIF", .kw_endif },
        .{ "FOR", .kw_for },
        .{ "EACH", .kw_each },
        .{ "TO", .kw_to },
        .{ "STEP", .kw_step },
        .{ "IN", .kw_in },
        .{ "NEXT", .kw_next },
        .{ "WHILE", .kw_while },
        .{ "WEND", .kw_wend },
        .{ "REPEAT", .kw_repeat },
        .{ "UNTIL", .kw_until },
        .{ "DO", .kw_do },
        .{ "LOOP", .kw_loop },
        .{ "DONE", .kw_done },
        .{ "END", .kw_end },
        .{ "EXIT", .kw_exit },
        .{ "CASE", .kw_case },
        .{ "SELECT", .kw_select },
        .{ "OF", .kw_of },
        .{ "WHEN", .kw_when },
        .{ "IS", .kw_is },
        .{ "OTHERWISE", .kw_otherwise },
        .{ "ENDCASE", .kw_endcase },
        .{ "MATCH", .kw_match },
        .{ "ENDMATCH", .kw_endmatch },
        .{ "TRY", .kw_try },
        .{ "CATCH", .kw_catch },
        .{ "FINALLY", .kw_finally },
        .{ "THROW", .kw_throw },
        .{ "ERR", .kw_err },
        .{ "ERL", .kw_erl },
        .{ "OPTION", .kw_option },
        .{ "BITWISE", .kw_bitwise },
        .{ "LOGICAL", .kw_logical },
        .{ "BASE", .kw_base },
        .{ "EXPLICIT", .kw_explicit },
        .{ "UNICODE", .kw_unicode },
        .{ "ASCII", .kw_ascii },
        .{ "DETECTSTRING", .kw_detectstring },
        .{ "ERROR", .kw_error },
        .{ "INCLUDE", .kw_include },
        .{ "ONCE", .kw_once },
        .{ "CANCELLABLE", .kw_cancellable },
        .{ "BOUNDS_CHECK", .kw_bounds_check },
        .{ "FORCE_YIELD", .kw_force_yield },
        .{ "SAMM", .kw_samm },
        .{ "NEON", .kw_neon },
        .{ "SUB", .kw_sub },
        .{ "FUNCTION", .kw_function },
        .{ "ENDSUB", .kw_endsub },
        .{ "ENDFUNCTION", .kw_endfunction },
        .{ "WORKER", .kw_worker },
        .{ "ENDWORKER", .kw_endworker },
        .{ "SPAWN", .kw_spawn },
        .{ "AWAIT", .kw_await },
        .{ "READY", .kw_ready },
        .{ "FUTURE", .kw_future },
        .{ "MARSHALL", .kw_marshall },
        .{ "UNMARSHALL", .kw_unmarshall },
        .{ "SEND", .kw_send },
        .{ "RECEIVE", .kw_receive },
        .{ "HASMESSAGE", .kw_hasmessage },
        .{ "PARENT", .kw_parent },
        .{ "CANCEL", .kw_cancel },
        .{ "CANCELLED", .kw_cancelled },
        .{ "CALL", .kw_call },
        .{ "LOCAL", .kw_local },
        .{ "GLOBAL", .kw_global },
        .{ "SHARED", .kw_shared },
        .{ "BYREF", .kw_byref },
        .{ "BYVAL", .kw_byval },
        .{ "AS", .kw_as },
        .{ "DEF", .kw_def },
        .{ "FN", .kw_fn },
        .{ "IIF", .kw_iif },
        .{ "MID", .kw_mid },
        .{ "MID$", .kw_mid },
        .{ "LEFT", .kw_left },
        .{ "LEFT$", .kw_left },
        .{ "RIGHT", .kw_right },
        .{ "RIGHT$", .kw_right },
        .{ "ON", .kw_on },
        .{ "ONEVENT", .kw_onevent },
        .{ "OFF", .kw_off },
        .{ "INTEGER", .kw_integer },
        .{ "DOUBLE", .kw_double },
        .{ "SINGLE", .kw_single },
        .{ "STRING", .kw_string_type },
        .{ "LONG", .kw_long },
        .{ "BYTE", .kw_byte },
        .{ "SHORT", .kw_short },
        .{ "UBYTE", .kw_ubyte },
        .{ "USHORT", .kw_ushort },
        .{ "UINTEGER", .kw_uinteger },
        .{ "ULONG", .kw_ulong },
        .{ "MARSHALLED", .kw_marshalled },
        .{ "HASHMAP", .kw_hashmap },
        .{ "LIST", .kw_list },
        .{ "DIM", .kw_dim },
        .{ "REDIM", .kw_redim },
        .{ "ERASE", .kw_erase },
        .{ "PRESERVE", .kw_preserve },
        .{ "SWAP", .kw_swap },
        .{ "INC", .kw_inc },
        .{ "DEC", .kw_dec },
        .{ "DATA", .kw_data },
        .{ "READ", .kw_read },
        .{ "RESTORE", .kw_restore },
        .{ "CONSTANT", .kw_constant },
        .{ "TYPE", .kw_type },
        .{ "ENDTYPE", .kw_endtype },
        .{ "CLASS", .kw_class },
        .{ "EXTENDS", .kw_extends },
        .{ "CONSTRUCTOR", .kw_constructor },
        .{ "DESTRUCTOR", .kw_destructor },
        .{ "METHOD", .kw_method },
        .{ "ME", .kw_me },
        .{ "SUPER", .kw_super },
        .{ "NEW", .kw_new },
        .{ "CREATE", .kw_create },
        .{ "DELETE", .kw_delete },
        .{ "NOTHING", .kw_nothing },
        .{ "OPEN", .kw_open },
        .{ "CLOSE", .kw_close },
        .{ "SLURP", .kw_slurp },
        .{ "SPIT", .kw_spit },
        .{ "FIELD", .kw_field },
        .{ "LSET", .kw_lset },
        .{ "RSET", .kw_rset },
        .{ "PUT", .kw_put },
        .{ "SEEK", .kw_seek },
        .{ "LOC", .kw_loc },
        .{ "LOF", .kw_lof },
        .{ "REM", .kw_rem },
        .{ "CLS", .kw_cls },
        .{ "COLOR", .kw_color },
        .{ "WRCH", .kw_wrch },
        .{ "WRSTR", .kw_wrstr },
        .{ "COMMAND", .kw_command },
        .{ "COMMANDCOUNT", .kw_commandcount },
        .{ "WAIT", .kw_wait },
        .{ "WAIT_MS", .kw_wait_ms },
        .{ "SHELL", .kw_shell },
        .{ "SYSTEM", .kw_system },
        .{ "PSET", .kw_pset },
        .{ "RECT", .kw_rect },
        .{ "CIRCLE", .kw_circle },
        .{ "CIRCLEF", .kw_circlef },
        .{ "GCLS", .kw_gcls },
        .{ "CLG", .kw_clg },
        .{ "HLINE", .kw_hline },
        .{ "VLINE", .kw_vline },
        .{ "AT", .kw_at },
        .{ "LOCATE", .kw_locate },
        .{ "VDUCLS", .kw_vducls },
        .{ "VDUEOL", .kw_vdueol },
        .{ "VDUEOS", .kw_vdueos },
        .{ "VDUPOS", .kw_vdupos },
        .{ "VDUCURSOR", .kw_vducursor },
        .{ "VDUUP", .kw_vduup },
        .{ "VDUDOWN", .kw_vdudown },
        .{ "VDULEFT", .kw_vduleft },
        .{ "VDURIGHT", .kw_vduright },
        .{ "VDUMOVE", .kw_vdumove },
        .{ "VDUCOLOR", .kw_vducolor },
        .{ "VDUCOLOUR", .kw_vducolour },
        .{ "VDURGB", .kw_vdurgb },
        .{ "VDURESET", .kw_vdureset },
        .{ "VDUSTYLE", .kw_vdustyle },
        .{ "VDUSCREEN", .kw_vduscreen },
        .{ "VDUPOSX", .kw_vduposx },
        .{ "VDUPOSY", .kw_vduposy },
        .{ "VDUWIDTH", .kw_vduwidth },
        .{ "VDUHEIGHT", .kw_vduheight },
        .{ "VDUSIZE", .kw_vdusize },
        .{ "CURSOR_ON", .kw_cursor_on },
        .{ "CURSOR_OFF", .kw_cursor_off },
        .{ "CURSOR_HIDE", .kw_cursor_hide },
        .{ "CURSOR_SHOW", .kw_cursor_show },
        .{ "CURSOR_SAVE", .kw_cursor_save },
        .{ "CURSOR_RESTORE", .kw_cursor_restore },
        .{ "COLOUR", .kw_colour },
        .{ "COLOR_RESET", .kw_color_reset },
        .{ "RGB", .kw_rgb },
        .{ "RGBFG", .kw_rgbfg },
        .{ "RGBBG", .kw_rgbbg },
        .{ "BOLD", .kw_bold },
        .{ "ITALIC", .kw_italic },
        .{ "UNDERLINE", .kw_underline },
        .{ "BLINK", .kw_blink },
        .{ "INVERSE", .kw_inverse },
        .{ "STYLE_RESET", .kw_style_reset },
        .{ "NORMAL", .kw_normal },
        .{ "SCREEN_ALTERNATE", .kw_screen_alternate },
        .{ "SCREEN_MAIN", .kw_screen_main },
        // Keyboard input - commented out to reduce keyword map size
        .{ "KBGET", .kw_kbget },
        .{ "KBHIT", .kw_kbhit },
        .{ "KBPEEK", .kw_kbpeek },
        .{ "KBCODE", .kw_kbcode },
        .{ "KBSPECIAL", .kw_kbspecial },
        .{ "KBMOD", .kw_kbmod },
        .{ "KBRAW", .kw_kbraw },
        .{ "KBECHO", .kw_kbecho },
        .{ "KBFLUSH", .kw_kbflush },
        .{ "KBCLEAR", .kw_kbclear },
        .{ "KBCOUNT", .kw_kbcount },
        .{ "FLUSH", .kw_flush },
        .{ "BEGINPAINT", .kw_beginpaint },
        .{ "ENDPAINT", .kw_endpaint },
        .{ "SCREENWIDTH", .kw_screenwidth },
        .{ "SCREENHEIGHT", .kw_screenheight },
        .{ "KBINPUT", .kw_kbinput },
        .{ "INKEY", .kw_inkey },
        .{ "POS", .kw_pos },
        .{ "ROW", .kw_row },
        .{ "CSRLIN", .kw_csrlin },
        // Text layer - commented out to reduce keyword map size
        // .{ "TEXTPUT", .kw_textput },
        // .{ "PRINT_AT", .kw_print_at },
        // .{ "INPUT_AT", .kw_input_at },
        // .{ "TCHAR", .kw_tchar },
        // .{ "TGRID", .kw_tgrid },
        // .{ "TSCROLL", .kw_tscroll },
        // .{ "TCLEAR", .kw_tclear },
        // Sprites - commented out to reduce keyword map size
        // .{ "SPRLOAD", .kw_sprload },
        // .{ "SPRFREE", .kw_sprfree },
        // .{ "SPRSHOW", .kw_sprshow },
        // .{ "SPRHIDE", .kw_sprhide },
        // .{ "SPRMOVE", .kw_sprmove },
        // .{ "SPRPOS", .kw_sprpos },
        // .{ "SPRTINT", .kw_sprtint },
        // .{ "SPRSCALE", .kw_sprscale },
        // .{ "SPRROT", .kw_sprrot },
        // .{ "SPREXPLODE", .kw_sprexplode },
        // Audio - commented out to reduce keyword map size
        // .{ "PLAY", .kw_play },
        // .{ "PLAY_SOUND", .kw_play_sound },
        .{ "SLEEP", .kw_sleep },
        // Timing
        // .{ "VSYNC", .kw_vsync },
        .{ "AFTER", .kw_after },
        .{ "EVERY", .kw_every },
        // .{ "AFTERFRAMES", .kw_afterframes },
        // .{ "EVERYFRAME", .kw_everyframe },
        .{ "TIMER", .kw_timer },
        .{ "STOP", .kw_stop },
        // .{ "RUN", .kw_run },
        .{ "MS", .kw_ms },
        .{ "SECS", .kw_secs },
        .{ "MINUTES", .kw_minutes },
        // .{ "FRAMES", .kw_frames },
        .{ "AND", .kw_and },
        .{ "OR", .kw_or },
        .{ "NOT", .kw_not },
        .{ "XOR", .kw_xor },
        .{ "EQV", .kw_eqv },
        .{ "IMP", .kw_imp },
        .{ "MOD", .kw_mod },
        .{ "HASKEY", .kw_haskey },
        .{ "KEYS", .kw_keys },
        .{ "SIZE", .kw_size },
        .{ "CLEAR", .kw_clear },
        .{ "REMOVE", .kw_remove },
        .{ "APPEND", .kw_append },
        .{ "PREPEND", .kw_prepend },
        .{ "HEAD", .kw_head },
        .{ "TAIL", .kw_tail },
        .{ "REST", .kw_rest },
        .{ "LENGTH", .kw_length },
        .{ "EMPTY", .kw_empty },
        .{ "CONTAINS", .kw_contains },
        .{ "INDEXOF", .kw_indexof },
        .{ "JOIN", .kw_join },
        .{ "COPY", .kw_copy },
        .{ "REVERSE", .kw_reverse },
        .{ "SHIFT", .kw_shift },
        .{ "POP", .kw_pop },
        .{ "EXTEND", .kw_extend },
        .{ "INSERT", .kw_insert },
        .{ "GET", .kw_get },
        .{ "TYPEOF", .kw_typeof },
        .{ "USING", .kw_using },
    };

    for (keywords) |kw| {
        try keyword_map.put(kw[0], kw[1]);
    }
    keyword_map_initialized = true;
}

fn getKeywordMap(allocator: std.mem.Allocator) !*KeywordMap {
    keyword_map_mutex.lock();
    defer keyword_map_mutex.unlock();

    if (!keyword_map_initialized) {
        try initKeywordMap(allocator);
    }
    return &keyword_map;
}

fn deinitKeywordMap() void {
    keyword_map_mutex.lock();
    defer keyword_map_mutex.unlock();

    if (keyword_map_initialized) {
        keyword_map.deinit();
        keyword_map_initialized = false;
    }
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "keyword lookup - basic" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(Tag.kw_print, Tag.fromKeyword("PRINT", allocator).?);
    try std.testing.expectEqual(Tag.kw_print, Tag.fromKeyword("print", allocator).?);
    try std.testing.expectEqual(Tag.kw_print, Tag.fromKeyword("Print", allocator).?);
    try std.testing.expectEqual(Tag.kw_if, Tag.fromKeyword("IF", allocator).?);
    try std.testing.expectEqual(Tag.kw_end, Tag.fromKeyword("END", allocator).?);
    try std.testing.expect(Tag.fromKeyword("NOTAKEYWORD", allocator) == null);
}

test "keyword lookup - type keywords" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(Tag.kw_integer, Tag.fromKeyword("INTEGER", allocator).?);
    try std.testing.expectEqual(Tag.kw_string_type, Tag.fromKeyword("STRING", allocator).?);
    try std.testing.expectEqual(Tag.kw_double, Tag.fromKeyword("DOUBLE", allocator).?);
}

test "keyword lookup - operators" {
    const allocator = std.testing.allocator;
    try std.testing.expectEqual(Tag.kw_and, Tag.fromKeyword("AND", allocator).?);
    try std.testing.expectEqual(Tag.kw_or, Tag.fromKeyword("OR", allocator).?);
    try std.testing.expectEqual(Tag.kw_mod, Tag.fromKeyword("MOD", allocator).?);
}

test "token predicates" {
    const tok_plus = Token{ .tag = .plus, .lexeme = "+" };
    try std.testing.expect(tok_plus.isArithmetic());
    try std.testing.expect(tok_plus.isOperator());
    try std.testing.expect(!tok_plus.isComparison());
    try std.testing.expect(!tok_plus.isKeyword());

    const tok_eq = Token{ .tag = .equal, .lexeme = "=" };
    try std.testing.expect(tok_eq.isComparison());
    try std.testing.expect(tok_eq.isOperator());

    const tok_if = Token{ .tag = .kw_if, .lexeme = "IF" };
    try std.testing.expect(tok_if.isKeyword());
    try std.testing.expect(!tok_if.isOperator());

    const tok_pct = Token{ .tag = .type_int, .lexeme = "%" };
    try std.testing.expect(tok_pct.isTypeSuffix());
}

test "asTypeToSuffix" {
    try std.testing.expectEqual(Tag.type_int, Tag.kw_integer.asTypeToSuffix().?);
    try std.testing.expectEqual(Tag.type_double, Tag.kw_double.asTypeToSuffix().?);
    try std.testing.expectEqual(Tag.type_float, Tag.kw_single.asTypeToSuffix().?);
    try std.testing.expectEqual(Tag.type_string, Tag.kw_string_type.asTypeToSuffix().?);
    try std.testing.expectEqual(Tag.ampersand, Tag.kw_long.asTypeToSuffix().?);
    try std.testing.expectEqual(Tag.type_byte, Tag.kw_byte.asTypeToSuffix().?);
    try std.testing.expect(Tag.kw_print.asTypeToSuffix() == null);
}

test "isEndOfStatement" {
    const eol = Token{ .tag = .end_of_line };
    try std.testing.expect(eol.isEndOfStatement());
    const eof = Token{ .tag = .end_of_file };
    try std.testing.expect(eof.isEndOfStatement());
    const col = Token{ .tag = .colon, .lexeme = ":" };
    try std.testing.expect(col.isEndOfStatement());
    const id = Token{ .tag = .identifier, .lexeme = "x" };
    try std.testing.expect(!id.isEndOfStatement());
}
