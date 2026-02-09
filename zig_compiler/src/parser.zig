//! Recursive descent parser for the FasterBASIC compiler.
//!
//! Converts a token stream (from the Lexer) into an Abstract Syntax Tree.
//! Implements operator precedence via the classic precedence-climbing method:
//!
//!   Expression → LogicalImp
//!   LogicalImp → LogicalEqv (IMP LogicalEqv)*
//!   LogicalEqv → LogicalOr (EQV LogicalOr)*
//!   LogicalOr  → LogicalXor (OR LogicalXor)*
//!   LogicalXor → LogicalAnd (XOR LogicalAnd)*
//!   LogicalAnd → LogicalNot (AND LogicalNot)*
//!   LogicalNot → NOT? Comparison
//!   Comparison → Additive (CompOp Additive)*
//!   Additive   → Multiplicative ((+|-) Multiplicative)*
//!   Multiplicative → Unary ((*|/|\|MOD) Unary)*
//!   Unary      → (-|NOT)? Power
//!   Power      → Postfix (^ Postfix)*
//!   Postfix    → Primary (.member | .method(args) | (indices))*
//!   Primary    → NUMBER | STRING | IDENTIFIER | (Expr) | FuncCall | IIF | NEW | CREATE | ME | NOTHING
//!
//! Design differences from the C++ version:
//! - Error recovery uses Zig error unions instead of C++ exceptions.
//! - Token stream is a simple slice with an index (no iterator class).
//! - AST nodes are allocated through `ast.Builder`.
//! - All parse methods return `!` (may fail on OOM or unrecoverable error).
//! - Forward-reference scanning (prescan) is done in a separate pass.

const std = @import("std");
const token_mod = @import("token.zig");
const ast = @import("ast.zig");
const lexer_mod = @import("lexer.zig");
const Token = token_mod.Token;
const Tag = token_mod.Tag;
const SourceLocation = token_mod.SourceLocation;

// ─── Parser Error ───────────────────────────────────────────────────────────

pub const ParserError = struct {
    message: []const u8,
    location: SourceLocation,

    pub fn format(self: ParserError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Parser Error at {}: {s}", .{ self.location, self.message });
    }
};

// ─── Parser ─────────────────────────────────────────────────────────────────

pub const Parser = struct {
    /// The token stream to parse.
    tokens: []const Token,
    /// Current position in the token stream.
    pos: usize,
    /// AST node builder (handles allocation).
    builder: ast.Builder,
    /// Collected parse errors.
    errors: std.ArrayList(ParserError),
    /// Allocator for dynamic data.
    allocator: std.mem.Allocator,

    // ── Configuration ───────────────────────────────────────────────────
    /// Allow implicit LET (e.g. `X = 5` without the LET keyword).
    allow_implicit_let: bool = true,
    /// Strict syntax checking mode.
    strict_mode: bool = false,

    // ── Pre-scan results ────────────────────────────────────────────────
    /// Names of user-defined FUNCTIONs (collected in prescan).
    user_functions: std.StringHashMap(void),
    /// Names of user-defined SUBs (collected in prescan).
    user_subs: std.StringHashMap(void),

    // ── Internal counters ───────────────────────────────────────────────
    /// Auto-assigned line number for lines without explicit numbers.
    auto_line_number: i32 = 1000,

    /// Initialize a parser over the given token stream.
    pub fn init(tokens: []const Token, allocator: std.mem.Allocator) Parser {
        return .{
            .tokens = tokens,
            .pos = 0,
            .builder = ast.Builder.init(allocator),
            .errors = .empty,
            .allocator = allocator,
            .user_functions = std.StringHashMap(void).init(allocator),
            .user_subs = std.StringHashMap(void).init(allocator),
        };
    }

    /// Release all memory owned by the parser.
    pub fn deinit(self: *Parser) void {
        self.errors.deinit(self.allocator);
        self.user_functions.deinit();
        self.user_subs.deinit();
    }

    /// Whether parsing produced any errors.
    pub fn hasErrors(self: *const Parser) bool {
        return self.errors.items.len > 0;
    }

    // ═════════════════════════════════════════════════════════════════════
    // Top-level parsing
    // ═════════════════════════════════════════════════════════════════════

    /// Parse the entire token stream and produce a Program AST.
    pub fn parse(self: *Parser) !ast.Program {
        // Pre-scan for forward references (function/sub names).
        self.prescanForFunctions();

        // Parse all program lines.
        var lines: std.ArrayList(ast.ProgramLine) = .empty;
        defer lines.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.isAtEnd()) break;

            const line = try self.parseProgramLine();
            try lines.append(self.allocator, line);
        }

        return .{
            .lines = try self.allocator.dupe(ast.ProgramLine, lines.items),
        };
    }

    /// Pre-scan the token stream for FUNCTION and SUB declarations so that
    /// forward references can be resolved during the main parse.
    fn prescanForFunctions(self: *Parser) void {
        var i: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const tok = self.tokens[i];
            if (tok.tag == .kw_function or tok.tag == .kw_sub) {
                const is_func = tok.tag == .kw_function;
                // Next token should be the name.
                if (i + 1 < self.tokens.len and self.tokens[i + 1].tag == .identifier) {
                    const name = self.tokens[i + 1].lexeme;
                    if (is_func) {
                        self.user_functions.put(name, {}) catch {};
                    } else {
                        self.user_subs.put(name, {}) catch {};
                    }
                }
            }
        }
    }

    /// Parse a single program line (possibly containing multiple colon-separated
    /// statements).
    fn parseProgramLine(self: *Parser) ExprError!ast.ProgramLine {
        const loc = self.currentLocation();
        var stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer stmts.deinit(self.allocator);

        // Check for an optional leading line number.
        var line_number: i32 = 0;
        if (self.check(.number)) {
            const num_tok = self.current();
            line_number = @intFromFloat(num_tok.number_value);
            _ = self.advance();
        } else {
            line_number = self.auto_line_number;
            self.auto_line_number += 10;
        }

        // Parse statements on this line (separated by colons).
        while (!self.isAtEnd() and !self.check(.end_of_line) and !self.check(.end_of_file)) {
            // If we see a line number here, a multi-line construct (like
            // IF/END IF or FOR/NEXT) already consumed past this line.
            // Break so the outer parse loop handles the new line.
            if (self.check(.number) and stmts.items.len > 0) break;

            // After a multi-line construct, we may land on an END keyword
            // that belongs to an outer scope (END METHOD, END CONSTRUCTOR,
            // END CLASS, END SUB, END FUNCTION, etc.).  Don't consume it
            // here — let the outer parser handle it.
            if (self.check(.kw_end) and stmts.items.len > 0) break;

            // Tokens that belong to an enclosing multi-line construct
            // (ELSE, ELSEIF for IF blocks; WEND for WHILE; LOOP for DO;
            // UNTIL for REPEAT; NEXT for FOR).  After parsing a nested
            // multi-line construct, parseProgramLine may land on one of
            // these.  They must not be consumed here — leave them for the
            // enclosing construct's parser.
            if (stmts.items.len > 0) {
                const tag = self.current().tag;
                if (tag == .kw_else or tag == .kw_elseif or
                    tag == .kw_wend or tag == .kw_loop or
                    tag == .kw_until or tag == .kw_next)
                {
                    break;
                }
            }

            // Compound END tokens (produced by the lexer for "END SUB",
            // "END FUNCTION", "END IF", etc.) also signal a scope boundary.
            // Don't try to parse them as statements — leave them for the
            // enclosing construct's parser to consume.
            if (self.isScopeClosingToken()) {
                if (stmts.items.len == 0) {
                    // Orphaned scope-closing token at top level (e.g. ENDIF
                    // without a matching IF).  Skip past it so the outer
                    // parse loop doesn't spin forever on the same token.
                    _ = self.advance();
                }
                break;
            }
            const stmt = self.parseStatement() catch |err| {
                // Error recovery: skip to end of line.
                switch (err) {
                    error.ParseError => {
                        self.skipToEndOfLine();
                        break;
                    },
                    else => return err,
                }
            };
            try stmts.append(self.allocator, stmt);

            // Consume optional colon separator.
            if (self.check(.colon)) {
                _ = self.advance();
            }
        }

        // Consume the end-of-line token.
        if (self.check(.end_of_line)) {
            _ = self.advance();
        }

        return .{
            .line_number = line_number,
            .statements = try self.allocator.dupe(ast.StmtPtr, stmts.items),
            .loc = loc,
        };
    }

    // ═════════════════════════════════════════════════════════════════════
    // Statement parsing
    // ═════════════════════════════════════════════════════════════════════

    fn parseStatement(self: *Parser) ExprError!ast.StmtPtr {
        const tok = self.current();

        return switch (tok.tag) {
            .kw_print => self.parsePrintStatement(),
            .kw_console => self.parseConsoleStatement(),
            .kw_input => self.parseInputStatement(),
            .kw_let => self.parseLetStatement(),
            .kw_goto => self.parseGotoStatement(),
            .kw_gosub => self.parseGosubStatement(),
            .kw_return => self.parseReturnStatement(),
            .kw_if => self.parseIfStatement(),
            .kw_for => self.parseForStatement(),
            .kw_next => self.parseNextStatement(),
            .kw_while => self.parseWhileStatement(),
            .kw_wend => self.parseWendStatement(),
            .kw_repeat => self.parseRepeatStatement(),
            .kw_until => self.parseUntilStatement(),
            .kw_do => self.parseDoStatement(),
            .kw_loop => self.parseLoopStatement(),
            .kw_end => self.parseEndStatement(),
            .kw_exit => self.parseExitStatement(),
            .kw_select => self.parseSelectCaseStatement(),
            .kw_dim => self.parseDimStatement(),
            .kw_redim => self.parseRedimStatement(),
            .kw_erase => self.parseEraseStatement(),
            .kw_swap => self.parseSwapStatement(),
            .kw_inc => self.parseIncStatement(),
            .kw_dec => self.parseDecStatement(),
            .kw_local => self.parseLocalStatement(),
            .kw_global => self.parseGlobalStatement(),
            .kw_shared => self.parseSharedStatement(),
            .kw_constant => self.parseConstantStatement(),
            .kw_type => self.parseTypeDeclaration(),
            .kw_data => self.parseDataStatement(),
            .kw_read => self.parseReadStatement(),
            .kw_restore => self.parseRestoreStatement(),
            .kw_rem => self.parseRemStatement(),
            .kw_option => self.parseOptionStatement(),
            .kw_function => self.parseFunctionStatement(),
            .kw_sub => self.parseSubStatement(),
            .kw_call => self.parseCallStatement(),
            .kw_def => self.parseDefStatement(),
            .kw_class => self.parseClassDeclaration(),
            .kw_delete => self.parseDeleteStatement(),
            .kw_open => self.parseOpenStatement(),
            .kw_close => self.parseCloseStatement(),
            .kw_cls => self.parseSimpleStatement(.cls),
            .kw_gcls, .kw_clg => self.parseSimpleStatement(.gcls),
            .kw_vsync => self.parseSimpleStatement(.vsync),
            .kw_color => self.parseColorStatement(),
            .kw_wait => self.parseWaitStatement(),
            .kw_wait_ms => self.parseWaitMsStatement(),
            .kw_sleep => self.parseSleepStatement(),
            .kw_try => self.parseTryCatchStatement(),
            .kw_throw => self.parseThrowStatement(),
            .kw_on => self.parseOnStatement(),
            .kw_after => self.parseAfterStatement(),
            .kw_every => self.parseEveryStatement(),
            .kw_run => self.parseRunStatement(),
            .kw_match => self.parseMatchTypeStatement(),

            // Identifier at start of line: could be LET (implicit) or CALL or LABEL.
            .identifier => self.parseIdentifierStatement(),

            // ME.field = value  (assignment to class member via ME reference)
            .kw_me => self.parseMeStatement(),

            // SUPER.Method() call inside a class method
            .kw_super => self.parseSuperStatement(),

            // Keywords that can also be used as variable names or method
            // call targets when they appear at the start of a statement
            // (e.g. `left = 7`, `empty$ = ""`, `data.field = x`).
            .kw_mid, .kw_left, .kw_right => self.parseKeywordAsIdentifierStatement(),

            else => {
                // ── General keyword-as-identifier fallback at statement start ──
                // When allow_implicit_let is true and a keyword appears that is
                // not otherwise handled, treat it as an identifier-started
                // statement (variable assignment, method call, etc.).
                // Examples: `Append = ME.Value + suffix`, `local.Method()`,
                //           `color$ = "red"`, `circle.Draw()`.
                if (tok.isKeyword() and self.allow_implicit_let) {
                    return self.parseKeywordAsIdentifierStatement();
                }
                try self.addError("Unexpected token at start of statement");
                return error.ParseError;
            },
        };
    }

    // ── Individual statement parsers ─────────────────────────────────────

    fn parsePrintStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume PRINT

        var items: std.ArrayList(ast.PrintItem) = .empty;
        defer items.deinit(self.allocator);

        var trailing_newline = true;

        while (!self.isAtEndOfStatement()) {
            const expr = try self.parseExpression();
            var semicolon = false;
            var comma = false;

            if (self.check(.semicolon)) {
                _ = self.advance();
                semicolon = true;
                trailing_newline = false;
            } else if (self.check(.comma)) {
                _ = self.advance();
                comma = true;
                trailing_newline = false;
            } else {
                trailing_newline = true;
            }

            try items.append(self.allocator, .{
                .expr = expr,
                .semicolon = semicolon,
                .comma = comma,
            });

            // If we hit end of statement after the expression (no separator),
            // that's fine — trailing newline is implied.
            if (self.isAtEndOfStatement()) break;
            // If we consumed a separator, continue parsing more items.
            if (!semicolon and !comma) break;
        }

        return self.builder.stmt(loc, .{ .print = .{
            .items = try self.allocator.dupe(ast.PrintItem, items.items),
            .trailing_newline = trailing_newline,
        } });
    }

    fn parseConsoleStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume CONSOLE

        var items: std.ArrayList(ast.PrintItem) = .empty;
        defer items.deinit(self.allocator);

        var trailing_newline = true;

        while (!self.isAtEndOfStatement()) {
            const expr = try self.parseExpression();
            var semicolon = false;
            var comma = false;

            if (self.check(.semicolon)) {
                _ = self.advance();
                semicolon = true;
                trailing_newline = false;
            } else if (self.check(.comma)) {
                _ = self.advance();
                comma = true;
                trailing_newline = false;
            } else {
                trailing_newline = true;
            }

            try items.append(self.allocator, .{
                .expr = expr,
                .semicolon = semicolon,
                .comma = comma,
            });

            if (self.isAtEndOfStatement()) break;
            if (!semicolon and !comma) break;
        }

        return self.builder.stmt(loc, .{ .console = .{
            .items = try self.allocator.dupe(ast.PrintItem, items.items),
            .trailing_newline = trailing_newline,
        } });
    }

    fn parseInputStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume INPUT

        var prompt: []const u8 = "";
        var variables: std.ArrayList([]const u8) = .empty;
        defer variables.deinit(self.allocator);

        // Optional prompt string.
        if (self.check(.string)) {
            prompt = lexer_mod.Lexer.stringValue(self.current());
            _ = self.advance();
            // Consume ; or , after prompt.
            if (self.check(.semicolon) or self.check(.comma)) {
                _ = self.advance();
            }
        }

        // Variable list.
        while (!self.isAtEndOfStatement()) {
            if (self.check(.identifier)) {
                try variables.append(self.allocator, self.current().lexeme);
                _ = self.advance();
                // Consume optional type suffix.
                self.skipTypeSuffix();
            } else {
                break;
            }
            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .input = .{
            .prompt = prompt,
            .variables = try self.allocator.dupe([]const u8, variables.items),
        } });
    }

    fn parseLetStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume LET

        return self.parseAssignment(loc);
    }

    fn parseGotoStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume GOTO

        if (self.check(.identifier)) {
            const label = self.current().lexeme;
            _ = self.advance();
            return self.builder.stmt(loc, .{ .goto_stmt = .{ .label = label, .is_label = true } });
        } else if (self.check(.number)) {
            const line_num: i32 = @intFromFloat(self.current().number_value);
            _ = self.advance();
            return self.builder.stmt(loc, .{ .goto_stmt = .{ .line_number = line_num } });
        } else {
            try self.addError("Expected label or line number after GOTO");
            return error.ParseError;
        }
    }

    fn parseGosubStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume GOSUB

        if (self.check(.identifier)) {
            const label = self.current().lexeme;
            _ = self.advance();
            return self.builder.stmt(loc, .{ .gosub = .{ .label = label, .is_label = true } });
        } else if (self.check(.number)) {
            const line_num: i32 = @intFromFloat(self.current().number_value);
            _ = self.advance();
            return self.builder.stmt(loc, .{ .gosub = .{ .line_number = line_num } });
        } else {
            try self.addError("Expected label or line number after GOSUB");
            return error.ParseError;
        }
    }

    fn parseReturnStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume RETURN

        var return_value: ?ast.ExprPtr = null;
        if (!self.isAtEndOfStatement()) {
            return_value = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .return_stmt = .{ .return_value = return_value } });
    }

    fn parseIfStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume IF

        const condition = try self.parseExpression();
        _ = try self.consume(.kw_then, "Expected THEN after IF condition");

        // Check if it's a single-line IF or a multi-line IF.
        if (self.isAtEndOfStatement()) {
            // Multi-line IF
            return self.parseMultiLineIf(loc, condition);
        } else {
            // Single-line IF
            return self.parseSingleLineIf(loc, condition);
        }
    }

    fn parseSingleLineIf(self: *Parser, loc: SourceLocation, condition: ast.ExprPtr) ExprError!ast.StmtPtr {
        var then_stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer then_stmts.deinit(self.allocator);

        // Check for GOTO shorthand: IF cond THEN 100
        if (self.check(.number)) {
            const line_num: i32 = @intFromFloat(self.current().number_value);
            _ = self.advance();
            return self.builder.stmt(loc, .{ .if_stmt = .{
                .condition = condition,
                .then_statements = &.{},
                .goto_line = line_num,
                .has_goto = true,
            } });
        }

        // Parse then-clause statements (colon-separated, until ELSE/ELSEIF/EOL).
        while (!self.isAtEnd() and !self.check(.end_of_line) and !self.check(.end_of_file) and
            !self.check(.kw_else) and !self.check(.kw_elseif))
        {
            const stmt = try self.parseStatement();
            try then_stmts.append(self.allocator, stmt);

            // If there's a colon, continue parsing more THEN statements.
            if (self.check(.colon)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        // Optional ELSE clause (also supports multiple colon-separated statements).
        var else_stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer else_stmts.deinit(self.allocator);

        if (self.check(.kw_else)) {
            _ = self.advance();
            while (!self.isAtEnd() and !self.check(.end_of_line) and !self.check(.end_of_file)) {
                const else_stmt = try self.parseStatement();
                try else_stmts.append(self.allocator, else_stmt);

                if (self.check(.colon)) {
                    _ = self.advance();
                } else {
                    break;
                }
            }
        }

        return self.builder.stmt(loc, .{ .if_stmt = .{
            .condition = condition,
            .then_statements = try self.allocator.dupe(ast.StmtPtr, then_stmts.items),
            .else_statements = try self.allocator.dupe(ast.StmtPtr, else_stmts.items),
        } });
    }

    fn parseMultiLineIf(self: *Parser, loc: SourceLocation, condition: ast.ExprPtr) ExprError!ast.StmtPtr {
        // Consume trailing EOL.
        if (self.check(.end_of_line)) _ = self.advance();

        var then_stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer then_stmts.deinit(self.allocator);

        var elseif_clauses: std.ArrayList(ast.IfStmt.ElseIfClause) = .empty;
        defer elseif_clauses.deinit(self.allocator);

        var else_stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer else_stmts.deinit(self.allocator);

        // Parse THEN block until ELSE, ELSEIF, ENDIF, or END IF.
        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.isIfTerminator(true)) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try then_stmts.append(self.allocator, s);
            }
        }

        // Parse ELSEIF clauses.
        // In line-numbered BASIC, the line number before ELSEIF must be
        // consumed so that the keyword check sees the actual ELSEIF token.
        self.skipLineNumberBefore(.kw_elseif);
        while (self.check(.kw_elseif)) {
            _ = self.advance(); // consume ELSEIF
            const elseif_cond = try self.parseExpression();
            _ = try self.consume(.kw_then, "Expected THEN after ELSEIF condition");
            if (self.check(.end_of_line)) _ = self.advance();

            var elseif_stmts: std.ArrayList(ast.StmtPtr) = .empty;
            defer elseif_stmts.deinit(self.allocator);

            while (!self.isAtEnd()) {
                self.skipBlankLines();
                if (self.isIfTerminator(true)) break;

                const line = try self.parseProgramLine();
                for (line.statements) |s| {
                    try elseif_stmts.append(self.allocator, s);
                }
            }

            try elseif_clauses.append(self.allocator, .{
                .condition = elseif_cond,
                .statements = try self.allocator.dupe(ast.StmtPtr, elseif_stmts.items),
            });

            self.skipLineNumberBefore(.kw_elseif);
        }

        // Parse optional ELSE block.
        self.skipLineNumberBefore(.kw_else);
        if (self.check(.kw_else)) {
            _ = self.advance();
            if (self.check(.end_of_line)) _ = self.advance();

            while (!self.isAtEnd()) {
                self.skipBlankLines();
                if (self.isIfTerminator(false)) break;

                const line = try self.parseProgramLine();
                for (line.statements) |s| {
                    try else_stmts.append(self.allocator, s);
                }
            }
        }

        // Consume ENDIF or END IF (skip line number in line-numbered BASIC).
        self.skipLineNumberBefore(.kw_endif);
        if (self.check(.kw_endif)) {
            _ = self.advance();
        } else if (self.check(.kw_end)) {
            _ = self.advance();
            if (self.check(.kw_if)) {
                _ = self.advance();
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .if_stmt = .{
            .condition = condition,
            .then_statements = try self.allocator.dupe(ast.StmtPtr, then_stmts.items),
            .elseif_clauses = try self.allocator.dupe(ast.IfStmt.ElseIfClause, elseif_clauses.items),
            .else_statements = try self.allocator.dupe(ast.StmtPtr, else_stmts.items),
            .is_multi_line = true,
        } });
    }

    /// In line-numbered BASIC, peek past an optional leading line number
    /// to check whether the next meaningful token is one of the IF-block
    /// terminators (ELSE, ELSEIF, ENDIF, END IF, or bare END).
    /// `include_else` controls whether ELSE and ELSEIF count as terminators
    /// (true in THEN/ELSEIF bodies, false in the ELSE body).
    fn isIfTerminator(self: *Parser, include_else: bool) bool {
        const tag = self.peekPastLineNumber();
        if (tag == .kw_endif) return true;
        if (include_else and (tag == .kw_else or tag == .kw_elseif)) return true;
        // Bare END is only a terminator if followed by IF (i.e. "END IF").
        // A standalone END (program termination) inside an IF body is NOT
        // a terminator — it's a valid statement.
        if (tag == .kw_end) {
            const effective_pos = if (self.check(.number) and self.pos + 1 < self.tokens.len)
                self.pos + 1
            else
                self.pos;
            if (effective_pos + 1 < self.tokens.len and self.tokens[effective_pos + 1].tag == .kw_if) return true;
            return false;
        }
        return false;
    }

    /// Return the tag of the current token, or if the current token is a
    /// line number (.number) and the next token exists, return the next
    /// token's tag instead.  This lets break-checks see past line numbers
    /// in line-numbered BASIC without consuming them.
    fn peekPastLineNumber(self: *Parser) Tag {
        if (self.check(.number) and self.pos + 1 < self.tokens.len) {
            return self.tokens[self.pos + 1].tag;
        }
        return self.current().tag;
    }

    /// Check whether the current position (possibly preceded by a line
    /// number) is an "END TRY" sequence.  Returns true only when the
    /// effective END keyword is followed by TRY.  A bare END (program
    /// termination) returns false.
    fn isEndTry(self: *Parser) bool {
        // Find the position of the END token, skipping an optional leading
        // line number.
        const end_pos = if (self.check(.number) and self.pos + 1 < self.tokens.len and
            self.tokens[self.pos + 1].tag == .kw_end)
            self.pos + 1
        else if (self.check(.kw_end))
            self.pos
        else
            return false;

        // Check if the token after END is TRY.
        if (end_pos + 1 < self.tokens.len and self.tokens[end_pos + 1].tag == .kw_try) {
            return true;
        }
        return false;
    }

    /// If the current token is a line number and the token after it
    /// matches `expected_tag`, consume the line number so that the
    /// caller can directly check/consume the keyword.
    fn skipLineNumberBefore(self: *Parser, expected_tag: Tag) void {
        if (self.check(.number) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == expected_tag) {
            _ = self.advance(); // consume the line number
        }
    }

    fn parseForStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume FOR

        // Check for FOR EACH ... IN
        if (self.check(.kw_each)) {
            return self.parseForEachStatement(loc);
        }

        // Regular FOR loop.
        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after FOR");
            return error.ParseError;
        }
        const variable = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        // Check for FOR var IN array  or  FOR var, idx IN array
        // (FOR...IN without the EACH keyword).
        if (self.check(.kw_in) or self.check(.comma)) {
            return self.parseForInStatement(loc, variable);
        }

        _ = try self.consume(.equal, "Expected '=' after FOR variable");
        const start = try self.parseExpression();
        _ = try self.consume(.kw_to, "Expected TO in FOR statement");
        const end_expr = try self.parseExpression();

        var step: ?ast.ExprPtr = null;
        if (self.check(.kw_step)) {
            _ = self.advance();
            step = try self.parseExpression();
        }

        // Parse body until NEXT.
        if (self.check(.end_of_line)) _ = self.advance();

        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_next)) break;
            // In line-numbered BASIC, the current token is the line number
            // before NEXT. Peek past it to detect NEXT on the next line.
            if (self.check(.number) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_next) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }

        // Consume the NEXT statement that terminates this FOR loop.
        // We must consume it here (including line number in line-numbered
        // BASIC) so that parseProgramLine does not try to parse subsequent
        // lines as part of the FOR's original line.
        // IMPORTANT: Do NOT consume the trailing EOL after NEXT — leave it
        // so that parseProgramLine's loop sees EOL and breaks out cleanly.
        if (self.check(.number) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_next) {
            _ = self.advance(); // consume line number before NEXT
        }
        if (self.check(.kw_next)) {
            _ = self.advance(); // consume NEXT
            // Consume optional variable name after NEXT.
            if (self.check(.identifier)) _ = self.advance();
            self.skipTypeSuffix();
            // Do NOT consume trailing EOL — parseProgramLine needs to see
            // it to know this line is finished.
        }

        return self.builder.stmt(loc, .{ .for_stmt = .{
            .variable = variable,
            .start = start,
            .end_expr = end_expr,
            .step = step,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseForEachStatement(self: *Parser, loc: SourceLocation) ExprError!ast.StmtPtr {
        _ = self.advance(); // consume EACH

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after FOR EACH");
            return error.ParseError;
        }
        const variable = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        // Check for FOR EACH var, idx IN array
        var index_variable: []const u8 = "";
        if (self.check(.comma)) {
            _ = self.advance(); // consume comma
            if (self.check(.identifier)) {
                index_variable = self.current().lexeme;
                _ = self.advance();
                self.skipTypeSuffix();
            }
        }

        _ = try self.consume(.kw_in, "Expected IN after FOR EACH variable");
        const array_expr = try self.parseExpression();

        return self.finishForInBody(loc, variable, index_variable, array_expr);
    }

    /// Parse `FOR var IN array` or `FOR var, idx IN array` (without EACH).
    /// Called after the loop variable has already been consumed.
    fn parseForInStatement(self: *Parser, loc: SourceLocation, variable: []const u8) ExprError!ast.StmtPtr {
        var index_variable: []const u8 = "";

        // Check for optional index variable: FOR var, idx IN ...
        if (self.check(.comma)) {
            _ = self.advance(); // consume comma
            if (self.check(.identifier)) {
                index_variable = self.current().lexeme;
                _ = self.advance();
                self.skipTypeSuffix();
            }
        }

        _ = try self.consume(.kw_in, "Expected IN after FOR variable");
        const array_expr = try self.parseExpression();

        return self.finishForInBody(loc, variable, index_variable, array_expr);
    }

    /// Shared tail for FOR EACH and FOR...IN: parse body until NEXT,
    /// consume NEXT, and return a for_in statement.
    fn finishForInBody(self: *Parser, loc: SourceLocation, variable: []const u8, index_variable: []const u8, array_expr: ast.ExprPtr) ExprError!ast.StmtPtr {
        if (self.check(.end_of_line)) _ = self.advance();

        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_next)) break;
            // In line-numbered BASIC, peek past the line number to detect NEXT.
            if (self.check(.number) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_next) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }

        // Consume the NEXT statement (same logic as regular FOR).
        // Do NOT consume the trailing EOL.
        if (self.check(.number) and self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_next) {
            _ = self.advance(); // consume line number before NEXT
        }
        if (self.check(.kw_next)) {
            _ = self.advance(); // consume NEXT
            if (self.check(.identifier)) _ = self.advance();
            self.skipTypeSuffix();
        }

        return self.builder.stmt(loc, .{ .for_in = .{
            .variable = variable,
            .index_variable = index_variable,
            .array = array_expr,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseNextStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume NEXT

        var variable: []const u8 = "";
        if (self.check(.identifier)) {
            variable = self.current().lexeme;
            _ = self.advance();
            self.skipTypeSuffix();
        }

        return self.builder.stmt(loc, .{ .next_stmt = .{ .variable = variable } });
    }

    fn parseWhileStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume WHILE

        const condition = try self.parseExpression();
        if (self.check(.end_of_line)) _ = self.advance();

        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_wend)) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }

        // Consume the WEND token so nested WHILEs don't cause the
        // outer WHILE to exit prematurely (the inner WEND would
        // otherwise still be the current token when control returns
        // to the outer parseWhileStatement's body loop).
        if (self.check(.kw_wend)) {
            _ = self.advance();
            if (self.check(.end_of_line)) _ = self.advance();
        }

        return self.builder.stmt(loc, .{ .while_stmt = .{
            .condition = condition,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseWendStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume WEND
        return self.builder.stmt(loc, .{ .wend = {} });
    }

    fn parseRepeatStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume REPEAT
        if (self.check(.end_of_line)) _ = self.advance();

        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_until)) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }

        return self.builder.stmt(loc, .{ .repeat_stmt = .{
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseUntilStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume UNTIL

        const condition = try self.parseExpression();

        return self.builder.stmt(loc, .{ .until_stmt = .{
            .condition = condition,
        } });
    }

    fn parseDoStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DO

        var pre_cond_type: ast.DoStmt.ConditionType = .none;
        var pre_cond: ?ast.ExprPtr = null;

        // Optional pre-condition: DO WHILE expr or DO UNTIL expr.
        if (self.check(.kw_while)) {
            _ = self.advance();
            pre_cond_type = .while_cond;
            pre_cond = try self.parseExpression();
        } else if (self.check(.kw_until)) {
            _ = self.advance();
            pre_cond_type = .until_cond;
            pre_cond = try self.parseExpression();
        }

        if (self.check(.end_of_line)) _ = self.advance();

        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_loop)) break;

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }

        return self.builder.stmt(loc, .{ .do_stmt = .{
            .pre_condition_type = pre_cond_type,
            .pre_condition = pre_cond,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseLoopStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume LOOP

        var cond_type: ast.LoopStmt.ConditionType = .none;
        var cond: ?ast.ExprPtr = null;

        if (self.check(.kw_while)) {
            _ = self.advance();
            cond_type = .while_cond;
            cond = try self.parseExpression();
        } else if (self.check(.kw_until)) {
            _ = self.advance();
            cond_type = .until_cond;
            cond = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .loop_stmt = .{
            .condition_type = cond_type,
            .condition = cond,
        } });
    }

    fn parseEndStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume END
        return self.builder.stmt(loc, .{ .end_stmt = {} });
    }

    fn parseExitStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume EXIT

        const exit_type: ast.ExitStmt.ExitType = if (self.check(.kw_for)) blk: {
            _ = self.advance();
            break :blk .for_loop;
        } else if (self.check(.kw_do)) blk: {
            _ = self.advance();
            break :blk .do_loop;
        } else if (self.check(.kw_while)) blk: {
            _ = self.advance();
            break :blk .while_loop;
        } else if (self.check(.kw_repeat)) blk: {
            _ = self.advance();
            break :blk .repeat_loop;
        } else if (self.check(.kw_function)) blk: {
            _ = self.advance();
            break :blk .function;
        } else if (self.check(.kw_sub)) blk: {
            _ = self.advance();
            break :blk .sub;
        } else .for_loop; // default: EXIT FOR

        return self.builder.stmt(loc, .{ .exit_stmt = .{ .exit_type = exit_type } });
    }

    fn parseSelectCaseStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume SELECT
        _ = try self.consume(.kw_case, "Expected CASE after SELECT");

        const case_expr = try self.parseExpression();
        if (self.check(.end_of_line)) _ = self.advance();

        var when_clauses: std.ArrayList(ast.CaseStmt.WhenClause) = .empty;
        defer when_clauses.deinit(self.allocator);

        var otherwise_stmts: std.ArrayList(ast.StmtPtr) = .empty;
        defer otherwise_stmts.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();

            // In line-numbered BASIC, peek past optional line number
            // to find the actual keyword (CASE, END SELECT, etc.).
            const effective_tag = self.peekPastLineNumber();

            if (effective_tag == .kw_endcase) {
                self.skipLineNumberBefore(.kw_endcase);
                _ = self.advance();
                break;
            }
            // END SELECT: the lexer may not always collapse it to
            // kw_endcase — handle bare END followed by SELECT too.
            if (effective_tag == .kw_end) {
                self.skipLineNumberBefore(.kw_end);
                // Check if it's END SELECT (two tokens).
                if (self.pos + 1 < self.tokens.len and
                    (self.tokens[self.pos + 1].tag == .kw_select or self.tokens[self.pos + 1].tag == .kw_case))
                {
                    _ = self.advance(); // consume END
                    _ = self.advance(); // consume SELECT/CASE
                    break;
                }
                break;
            }

            if (effective_tag == .kw_case or effective_tag == .kw_when) {
                self.skipLineNumberBefore(.kw_case);
                self.skipLineNumberBefore(.kw_when);
                _ = self.advance(); // consume CASE / WHEN

                // Check for CASE ELSE / OTHERWISE.
                if (self.check(.kw_else) or self.check(.kw_otherwise)) {
                    _ = self.advance();
                    if (self.check(.end_of_line)) _ = self.advance();

                    while (!self.isAtEnd()) {
                        self.skipBlankLines();
                        const inner_tag = self.peekPastLineNumber();
                        if (inner_tag == .kw_case or inner_tag == .kw_when or inner_tag == .kw_endcase or inner_tag == .kw_end) break;
                        const line = try self.parseProgramLine();
                        for (line.statements) |s| {
                            try otherwise_stmts.append(self.allocator, s);
                        }
                    }
                    continue;
                }

                // Parse case values.
                var values: std.ArrayList(ast.ExprPtr) = .empty;
                defer values.deinit(self.allocator);

                // ── CASE IS <op> <expr> ──────────────────────────
                var is_case_is = false;
                var case_is_op: Tag = .equal;
                var case_is_right: ?ast.ExprPtr = null;

                if (self.check(.kw_is)) {
                    _ = self.advance(); // consume IS
                    // Expect a comparison operator.
                    const op_tag = self.current().tag;
                    if (op_tag == .equal or op_tag == .not_equal or
                        op_tag == .less_than or op_tag == .less_equal or
                        op_tag == .greater_than or op_tag == .greater_equal)
                    {
                        case_is_op = op_tag;
                        _ = self.advance(); // consume the operator
                        case_is_right = try self.parseExpression();
                        is_case_is = true;
                    }
                }

                // ── CASE <expr> [TO <expr>] [, <expr> [TO <expr>] ...] ──
                var is_range = false;
                var range_start: ?ast.ExprPtr = null;
                var range_end: ?ast.ExprPtr = null;

                if (!is_case_is) {
                    const val = try self.parseExpression();
                    try values.append(self.allocator, val);

                    // Check for CASE val TO val (range).
                    if (self.check(.kw_to)) {
                        _ = self.advance(); // consume TO
                        is_range = true;
                        range_start = val;
                        range_end = try self.parseExpression();
                        // Clear values — range uses range_start/range_end.
                        values.clearRetainingCapacity();
                    }

                    // Comma-separated additional values (only for non-range).
                    if (!is_range) {
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try values.append(self.allocator, try self.parseExpression());
                        }
                    }
                }

                if (self.check(.end_of_line)) _ = self.advance();

                // Parse case body.
                var case_body: std.ArrayList(ast.StmtPtr) = .empty;
                defer case_body.deinit(self.allocator);

                while (!self.isAtEnd()) {
                    self.skipBlankLines();
                    const body_tag = self.peekPastLineNumber();
                    if (body_tag == .kw_case or body_tag == .kw_when or body_tag == .kw_otherwise or body_tag == .kw_endcase or body_tag == .kw_end) break;
                    const line = try self.parseProgramLine();
                    for (line.statements) |s| {
                        try case_body.append(self.allocator, s);
                    }
                }

                try when_clauses.append(self.allocator, .{
                    .values = try self.allocator.dupe(ast.ExprPtr, values.items),
                    .is_case_is = is_case_is,
                    .case_is_operator = case_is_op,
                    .case_is_right_expr = case_is_right,
                    .is_range = is_range,
                    .range_start = range_start,
                    .range_end = range_end,
                    .statements = try self.allocator.dupe(ast.StmtPtr, case_body.items),
                });
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .case_stmt = .{
            .case_expression = case_expr,
            .when_clauses = try self.allocator.dupe(ast.CaseStmt.WhenClause, when_clauses.items),
            .otherwise_statements = try self.allocator.dupe(ast.StmtPtr, otherwise_stmts.items),
        } });
    }

    fn parseDimStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DIM

        var arrays: std.ArrayList(ast.DimStmt.ArrayDim) = .empty;
        defer arrays.deinit(self.allocator);

        while (true) {
            // Accept identifiers AND keywords as variable names, because
            // BASIC variable names like "local", "item", "error" etc. may
            // collide with keyword tags in the lexer.
            if (!self.check(.identifier) and !self.current().isKeyword()) {
                try self.addError("Expected variable name after DIM");
                return error.ParseError;
            }

            const name = self.current().lexeme;
            _ = self.advance();

            var type_suffix: ?Tag = null;
            if (self.isTypeSuffix()) {
                type_suffix = self.current().tag;
                _ = self.advance();
            }

            var dimensions: std.ArrayList(ast.ExprPtr) = .empty;
            defer dimensions.deinit(self.allocator);

            // Optional dimensions: DIM arr(10) or DIM arr(10, 20).
            if (self.check(.lparen)) {
                _ = self.advance();
                if (!self.check(.rparen)) {
                    try dimensions.append(self.allocator, try self.parseExpression());
                    while (self.check(.comma)) {
                        _ = self.advance();
                        try dimensions.append(self.allocator, try self.parseExpression());
                    }
                }
                _ = try self.consume(.rparen, "Expected ')' after dimensions");
            }

            // Optional AS type.
            var as_type_name: []const u8 = "";
            var as_type_keyword: ?Tag = null;
            var has_as_type = false;

            if (self.check(.kw_as)) {
                _ = self.advance();
                has_as_type = true;
                if (self.isTypeKeyword()) {
                    as_type_keyword = self.current().tag;
                    _ = self.advance();
                    // Handle LIST OF <type> / HASHMAP OF <type>
                    if ((as_type_keyword == .kw_list or as_type_keyword == .kw_hashmap) and self.check(.kw_of)) {
                        _ = self.advance(); // consume OF
                        // Consume the element type (keyword or identifier).
                        // For full generality we accept LIST OF ANY etc.
                        if (self.isTypeKeyword()) {
                            // e.g. LIST OF INTEGER — store the container type
                            // as the main type; element type info is in as_type_name.
                            as_type_name = self.current().lexeme;
                            _ = self.advance();
                        } else if (self.check(.identifier) or self.current().isKeyword()) {
                            // Accept identifiers and keywords as element types
                            // (e.g. LIST OF ANY, LIST OF Item)
                            as_type_name = self.current().lexeme;
                            _ = self.advance();
                        } else if (self.check(.kw_of)) {
                            // nested OF — skip for now
                            _ = self.advance();
                        }
                        // Accept optional key type for HASHMAP: HASHMAP OF STRING TO INTEGER
                        // (simplified: just skip TO <type> if present)
                    }
                } else if (self.check(.identifier) or self.current().isKeyword()) {
                    // Accept identifiers AND keywords as type names
                    // (e.g. DIM circ AS Circle — "Circle" is .kw_circle).
                    as_type_name = self.current().lexeme;
                    _ = self.advance();
                } else {
                    try self.addError("Expected type name after AS");
                    return error.ParseError;
                }
            }

            // Optional initializer: = expression.
            var initializer: ?ast.ExprPtr = null;
            if (self.check(.equal)) {
                _ = self.advance();
                initializer = try self.parseExpression();
            }

            try arrays.append(self.allocator, .{
                .name = name,
                .type_suffix = type_suffix,
                .dimensions = try self.allocator.dupe(ast.ExprPtr, dimensions.items),
                .as_type_name = as_type_name,
                .as_type_keyword = as_type_keyword,
                .has_as_type = has_as_type,
                .initializer = initializer,
            });

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .dim = .{
            .arrays = try self.allocator.dupe(ast.DimStmt.ArrayDim, arrays.items),
        } });
    }

    fn parseRedimStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume REDIM

        var preserve = false;
        if (self.check(.kw_preserve)) {
            _ = self.advance();
            preserve = true;
        }

        var arrays: std.ArrayList(ast.RedimStmt.ArrayRedim) = .empty;
        defer arrays.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) {
                try self.addError("Expected array name after REDIM");
                return error.ParseError;
            }
            const name = self.current().lexeme;
            _ = self.advance();
            self.skipTypeSuffix();

            _ = try self.consume(.lparen, "Expected '(' after array name in REDIM");
            var dims: std.ArrayList(ast.ExprPtr) = .empty;
            defer dims.deinit(self.allocator);

            try dims.append(self.allocator, try self.parseExpression());
            while (self.check(.comma)) {
                _ = self.advance();
                try dims.append(self.allocator, try self.parseExpression());
            }
            _ = try self.consume(.rparen, "Expected ')' after REDIM dimensions");

            try arrays.append(self.allocator, .{
                .name = name,
                .dimensions = try self.allocator.dupe(ast.ExprPtr, dims.items),
            });

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .redim = .{
            .arrays = try self.allocator.dupe(ast.RedimStmt.ArrayRedim, arrays.items),
            .preserve = preserve,
        } });
    }

    fn parseEraseStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume ERASE

        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) {
                try self.addError("Expected array name after ERASE");
                return error.ParseError;
            }
            try names.append(self.allocator, self.current().lexeme);
            _ = self.advance();
            self.skipTypeSuffix();

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .erase = .{
            .array_names = try self.allocator.dupe([]const u8, names.items),
        } });
    }

    fn parseSwapStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume SWAP

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after SWAP");
            return error.ParseError;
        }
        const var1 = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        _ = try self.consume(.comma, "Expected ',' between SWAP variables");

        if (!self.check(.identifier)) {
            try self.addError("Expected second variable name in SWAP");
            return error.ParseError;
        }
        const var2 = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        return self.builder.stmt(loc, .{ .swap = .{ .var1 = var1, .var2 = var2 } });
    }

    fn parseIncStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume INC

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after INC");
            return error.ParseError;
        }
        const var_name = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        var amount: ?ast.ExprPtr = null;
        if (self.check(.comma)) {
            _ = self.advance();
            amount = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .inc = .{
            .var_name = var_name,
            .amount_expr = amount,
        } });
    }

    fn parseDecStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DEC

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after DEC");
            return error.ParseError;
        }
        const var_name = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        var amount: ?ast.ExprPtr = null;
        if (self.check(.comma)) {
            _ = self.advance();
            amount = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .dec = .{
            .var_name = var_name,
            .amount_expr = amount,
        } });
    }

    fn parseLocalStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume LOCAL

        var vars: std.ArrayList(ast.LocalStmt.LocalVar) = .empty;
        defer vars.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) break;

            const name = self.current().lexeme;
            _ = self.advance();

            var type_suffix: ?Tag = null;
            if (self.isTypeSuffix()) {
                type_suffix = self.current().tag;
                _ = self.advance();
            }

            var as_type_name: []const u8 = "";
            var has_as_type = false;
            if (self.check(.kw_as)) {
                _ = self.advance();
                has_as_type = true;
                if (self.isTypeKeyword() or self.check(.identifier)) {
                    as_type_name = self.current().lexeme;
                    _ = self.advance();
                }
            }

            var initial_value: ?ast.ExprPtr = null;
            if (self.check(.equal)) {
                _ = self.advance();
                initial_value = try self.parseExpression();
            }

            try vars.append(self.allocator, .{
                .name = name,
                .type_suffix = type_suffix,
                .initial_value = initial_value,
                .as_type_name = as_type_name,
                .has_as_type = has_as_type,
            });

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .local = .{
            .variables = try self.allocator.dupe(ast.LocalStmt.LocalVar, vars.items),
        } });
    }

    fn parseGlobalStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume GLOBAL

        var vars: std.ArrayList(ast.GlobalStmt.GlobalVar) = .empty;
        defer vars.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) break;

            const name = self.current().lexeme;
            _ = self.advance();

            var type_suffix: ?Tag = null;
            if (self.isTypeSuffix()) {
                type_suffix = self.current().tag;
                _ = self.advance();
            }

            var as_type_name: []const u8 = "";
            var has_as_type = false;
            if (self.check(.kw_as)) {
                _ = self.advance();
                has_as_type = true;
                if (self.isTypeKeyword() or self.check(.identifier)) {
                    as_type_name = self.current().lexeme;
                    _ = self.advance();
                }
            }

            var initial_value: ?ast.ExprPtr = null;
            if (self.check(.equal)) {
                _ = self.advance();
                initial_value = try self.parseExpression();
            }

            try vars.append(self.allocator, .{
                .name = name,
                .type_suffix = type_suffix,
                .initial_value = initial_value,
                .as_type_name = as_type_name,
                .has_as_type = has_as_type,
            });

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .global = .{
            .variables = try self.allocator.dupe(ast.GlobalStmt.GlobalVar, vars.items),
        } });
    }

    fn parseSharedStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume SHARED

        var vars: std.ArrayList(ast.SharedStmt.SharedVariable) = .empty;
        defer vars.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) break;

            const name = self.current().lexeme;
            _ = self.advance();

            var type_suffix: ?Tag = null;
            if (self.isTypeSuffix()) {
                type_suffix = self.current().tag;
                _ = self.advance();
            }

            var as_type_name: []const u8 = "";
            var has_as_type = false;
            if (self.check(.kw_as)) {
                _ = self.advance();
                has_as_type = true;
                if (self.isTypeKeyword() or self.check(.identifier)) {
                    as_type_name = self.current().lexeme;
                    _ = self.advance();
                }
            }

            try vars.append(self.allocator, .{
                .name = name,
                .type_suffix = type_suffix,
                .as_type_name = as_type_name,
                .has_as_type = has_as_type,
            });

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .shared = .{
            .variables = try self.allocator.dupe(ast.SharedStmt.SharedVariable, vars.items),
        } });
    }

    fn parseConstantStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume CONSTANT

        if (!self.check(.identifier)) {
            try self.addError("Expected constant name after CONSTANT");
            return error.ParseError;
        }
        const name = self.current().lexeme;
        _ = self.advance();

        _ = try self.consume(.equal, "Expected '=' after constant name");
        const value = try self.parseExpression();

        return self.builder.stmt(loc, .{ .constant = .{ .name = name, .value = value } });
    }

    fn parseTypeDeclaration(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume TYPE

        if (!self.check(.identifier)) {
            try self.addError("Expected type name after TYPE");
            return error.ParseError;
        }
        const type_name = self.current().lexeme;
        _ = self.advance();
        if (self.check(.end_of_line)) _ = self.advance();

        var fields: std.ArrayList(ast.TypeDeclStmt.TypeField) = .empty;
        defer fields.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_endtype)) {
                _ = self.advance();
                break;
            }
            if (self.check(.kw_end)) {
                _ = self.advance();
                // Consume optional TYPE after END.
                if (self.check(.kw_type)) _ = self.advance();
                break;
            }

            // Parse field: name AS Type
            // Accept identifiers and keywords as field names, because
            // BASIC field names like "Data", "Size", "Error" etc. may
            // collide with keyword tags in the lexer.
            if (self.check(.identifier) or self.current().isKeyword()) {
                const field_name = self.current().lexeme;
                _ = self.advance();
                self.skipTypeSuffix();

                _ = try self.consume(.kw_as, "Expected AS after field name in TYPE declaration");

                var field_type_name: []const u8 = "";
                var built_in_type: ?Tag = null;
                var is_built_in = true;

                if (self.isTypeKeyword()) {
                    built_in_type = self.current().tag;
                    _ = self.advance();
                } else if (self.check(.identifier)) {
                    field_type_name = self.current().lexeme;
                    is_built_in = false;
                    _ = self.advance();
                } else {
                    try self.addError("Expected type name after AS in field declaration");
                    return error.ParseError;
                }

                try fields.append(self.allocator, .{
                    .name = field_name,
                    .type_name = field_type_name,
                    .built_in_type = built_in_type,
                    .is_built_in = is_built_in,
                });

                if (self.check(.end_of_line)) _ = self.advance();
            } else {
                // Skip unexpected content.
                _ = self.advance();
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .type_decl = .{
            .type_name = type_name,
            .fields = try self.allocator.dupe(ast.TypeDeclStmt.TypeField, fields.items),
        } });
    }

    fn parseDataStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DATA

        var values: std.ArrayList([]const u8) = .empty;
        defer values.deinit(self.allocator);

        while (!self.isAtEndOfStatement()) {
            if (self.check(.string)) {
                try values.append(self.allocator, lexer_mod.Lexer.stringValue(self.current()));
                _ = self.advance();
            } else if (self.check(.number)) {
                try values.append(self.allocator, self.current().lexeme);
                _ = self.advance();
            } else if (self.check(.minus)) {
                _ = self.advance();
                if (self.check(.number)) {
                    // Negative number. We store the lexeme with minus prefix.
                    const num_lex = self.current().lexeme;
                    const neg = try std.fmt.allocPrint(self.allocator, "-{s}", .{num_lex});
                    try values.append(self.allocator, neg);
                    _ = self.advance();
                }
            } else if (self.check(.identifier)) {
                try values.append(self.allocator, self.current().lexeme);
                _ = self.advance();
            } else {
                break;
            }

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .data_stmt = .{
            .values = try self.allocator.dupe([]const u8, values.items),
        } });
    }

    fn parseReadStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume READ

        var vars: std.ArrayList([]const u8) = .empty;
        defer vars.deinit(self.allocator);

        while (true) {
            if (!self.check(.identifier)) break;
            try vars.append(self.allocator, self.current().lexeme);
            _ = self.advance();
            self.skipTypeSuffix();

            if (self.check(.comma)) {
                _ = self.advance();
            } else {
                break;
            }
        }

        return self.builder.stmt(loc, .{ .read_stmt = .{
            .variables = try self.allocator.dupe([]const u8, vars.items),
        } });
    }

    fn parseRestoreStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume RESTORE

        var label: []const u8 = "";
        var line_number: i32 = 0;
        var is_label = false;

        if (self.check(.identifier)) {
            label = self.current().lexeme;
            is_label = true;
            _ = self.advance();
        } else if (self.check(.number)) {
            line_number = @intFromFloat(self.current().number_value);
            _ = self.advance();
        }

        return self.builder.stmt(loc, .{ .restore = .{
            .line_number = line_number,
            .label = label,
            .is_label = is_label,
        } });
    }

    fn parseRemStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume REM
        // The lexer already skips the rest of the comment line.
        return self.builder.stmt(loc, .{ .rem = .{ .comment = "" } });
    }

    fn parseOptionStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume OPTION

        const option_type: ast.OptionStmt.OptionType = if (self.check(.kw_bitwise)) blk: {
            _ = self.advance();
            break :blk .bitwise;
        } else if (self.check(.kw_logical)) blk: {
            _ = self.advance();
            break :blk .logical;
        } else if (self.check(.kw_base)) blk: {
            _ = self.advance();
            break :blk .base;
        } else if (self.check(.kw_explicit)) blk: {
            _ = self.advance();
            break :blk .explicit_opt;
        } else if (self.check(.kw_unicode)) blk: {
            _ = self.advance();
            break :blk .unicode;
        } else if (self.check(.kw_ascii)) blk: {
            _ = self.advance();
            break :blk .ascii;
        } else if (self.check(.kw_detectstring)) blk: {
            _ = self.advance();
            break :blk .detectstring;
        } else if (self.check(.kw_error)) blk: {
            _ = self.advance();
            break :blk .error_opt;
        } else if (self.check(.kw_cancellable)) blk: {
            _ = self.advance();
            break :blk .cancellable;
        } else if (self.check(.kw_bounds_check)) blk: {
            _ = self.advance();
            break :blk .bounds_check;
        } else if (self.check(.kw_samm)) blk: {
            _ = self.advance();
            break :blk .samm;
        } else blk: {
            try self.addError("Unknown OPTION directive");
            _ = self.advance();
            break :blk .bitwise;
        };

        var value: i32 = 1;
        if (self.check(.number)) {
            value = @intFromFloat(self.current().number_value);
            _ = self.advance();
        } else if (self.check(.kw_on)) {
            value = 1;
            _ = self.advance();
        } else if (self.check(.kw_off)) {
            value = 0;
            _ = self.advance();
        }

        return self.builder.stmt(loc, .{ .option = .{
            .option_type = option_type,
            .value = value,
        } });
    }

    fn parseFunctionStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume FUNCTION

        if (!self.check(.identifier)) {
            try self.addError("Expected function name after FUNCTION");
            return error.ParseError;
        }
        const func_name = self.current().lexeme;
        _ = self.advance();

        var return_suffix: ?Tag = null;
        if (self.isTypeSuffix()) {
            return_suffix = self.current().tag;
            _ = self.advance();
        }

        // Parameters.
        const params = try self.parseParameterList();

        // Optional AS return type.
        var return_as_name: []const u8 = "";
        var has_return_as_type = false;
        if (self.check(.kw_as)) {
            _ = self.advance();
            has_return_as_type = true;
            if (self.isTypeKeyword() or self.check(.identifier)) {
                return_as_name = self.current().lexeme;
                return_suffix = self.current().tag;
                _ = self.advance();
            }
        }

        if (self.check(.end_of_line)) _ = self.advance();

        // Parse body until END FUNCTION.
        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_endfunction)) {
                _ = self.advance();
                break;
            }
            if (self.check(.kw_end)) {
                // Check for "END FUNCTION".
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_function) {
                    _ = self.advance();
                    _ = self.advance();
                    break;
                }
                break;
            }

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .function = .{
            .function_name = func_name,
            .return_type_suffix = return_suffix,
            .return_type_as_name = return_as_name,
            .has_return_as_type = has_return_as_type,
            .parameters = params.names,
            .parameter_types = params.types,
            .parameter_as_types = params.as_types,
            .parameter_is_byref = params.is_byref,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseSubStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume SUB

        if (!self.check(.identifier)) {
            try self.addError("Expected sub name after SUB");
            return error.ParseError;
        }
        const sub_name = self.current().lexeme;
        _ = self.advance();

        const params = try self.parseParameterList();

        if (self.check(.end_of_line)) _ = self.advance();

        // Parse body until END SUB.
        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_endsub)) {
                _ = self.advance();
                break;
            }
            if (self.check(.kw_end)) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_sub) {
                    _ = self.advance();
                    _ = self.advance();
                    break;
                }
                break;
            }

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .sub = .{
            .sub_name = sub_name,
            .parameters = params.names,
            .parameter_types = params.types,
            .parameter_as_types = params.as_types,
            .parameter_is_byref = params.is_byref,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        } });
    }

    fn parseCallStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();

        // Only consume CALL keyword if present — this function is also
        // invoked from parseIdentifierStatement where the current token
        // is the sub name itself (implicit call without CALL keyword).
        if (self.check(.kw_call)) {
            _ = self.advance(); // consume CALL
        }

        if (!self.check(.identifier) and !self.current().isKeyword()) {
            try self.addError("Expected sub name after CALL");
            return error.ParseError;
        }
        const sub_name = self.current().lexeme;
        _ = self.advance();

        var args: std.ArrayList(ast.ExprPtr) = .empty;
        defer args.deinit(self.allocator);

        // Optional argument list with or without parentheses.
        if (self.check(.lparen)) {
            _ = self.advance();
            if (!self.check(.rparen)) {
                try args.append(self.allocator, try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try args.append(self.allocator, try self.parseExpression());
                }
            }
            _ = try self.consume(.rparen, "Expected ')' after CALL arguments");
        } else {
            // Arguments without parens (space-separated until EOL/colon).
            while (!self.isAtEndOfStatement()) {
                try args.append(self.allocator, try self.parseExpression());
                if (self.check(.comma)) {
                    _ = self.advance();
                } else {
                    break;
                }
            }
        }

        return self.builder.stmt(loc, .{ .call = .{
            .sub_name = sub_name,
            .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
        } });
    }

    fn parseDefStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DEF

        // Consume optional FN prefix.
        if (self.check(.kw_fn)) _ = self.advance();

        if (!self.check(.identifier)) {
            try self.addError("Expected function name after DEF");
            return error.ParseError;
        }
        const func_name = self.current().lexeme;
        _ = self.advance();
        self.skipTypeSuffix();

        // Parameter list.
        var param_names: std.ArrayList([]const u8) = .empty;
        defer param_names.deinit(self.allocator);
        var param_suffixes: std.ArrayList(?Tag) = .empty;
        defer param_suffixes.deinit(self.allocator);

        if (self.check(.lparen)) {
            _ = self.advance();
            while (!self.check(.rparen) and !self.isAtEnd()) {
                if (self.check(.identifier)) {
                    try param_names.append(self.allocator, self.current().lexeme);
                    _ = self.advance();
                    if (self.isTypeSuffix()) {
                        try param_suffixes.append(self.allocator, self.current().tag);
                        _ = self.advance();
                    } else {
                        try param_suffixes.append(self.allocator, null);
                    }
                }
                if (self.check(.comma)) _ = self.advance();
            }
            _ = try self.consume(.rparen, "Expected ')' after DEF parameters");
        }

        _ = try self.consume(.equal, "Expected '=' after DEF parameter list");
        const body_expr = try self.parseExpression();

        return self.builder.stmt(loc, .{ .def = .{
            .function_name = func_name,
            .parameters = try self.allocator.dupe([]const u8, param_names.items),
            .parameter_suffixes = try self.allocator.dupe(?Tag, param_suffixes.items),
            .body = body_expr,
        } });
    }

    fn parseClassDeclaration(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume CLASS

        // Accept identifiers and keywords as class names (e.g. Base, Empty).
        if (!self.check(.identifier) and !self.current().isKeyword()) {
            try self.addError("Expected class name after CLASS");
            return error.ParseError;
        }
        const class_name = self.current().lexeme;
        _ = self.advance();

        var parent_name: []const u8 = "";
        if (self.check(.kw_extends)) {
            _ = self.advance();
            if (self.check(.identifier) or self.current().isKeyword()) {
                parent_name = self.current().lexeme;
                _ = self.advance();
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        // Parse class body (fields, constructor, destructor, methods) until END CLASS.
        var fields: std.ArrayList(ast.TypeDeclStmt.TypeField) = .empty;
        defer fields.deinit(self.allocator);

        var methods: std.ArrayList(*ast.MethodStmt) = .empty;
        defer methods.deinit(self.allocator);

        var constructor: ?*ast.ConstructorStmt = null;
        var destructor: ?*ast.DestructorStmt = null;

        while (!self.isAtEnd()) {
            self.skipBlankLines();

            // Skip REM / comments inside class body.
            if (self.check(.kw_rem)) {
                self.skipToEndOfLine();
                if (self.check(.end_of_line)) _ = self.advance();
                continue;
            }

            // Check for END CLASS.
            if (self.check(.kw_end)) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_class) {
                    _ = self.advance(); // consume END
                    _ = self.advance(); // consume CLASS
                    break;
                }
                // Bare END without CLASS — break to avoid infinite loop.
                _ = self.advance();
                break;
            }

            // CONSTRUCTOR
            if (self.check(.kw_constructor)) {
                constructor = try self.parseConstructorDeclaration();
                continue;
            }

            // DESTRUCTOR
            if (self.check(.kw_destructor)) {
                destructor = try self.parseDestructorDeclaration();
                continue;
            }

            // METHOD
            if (self.check(.kw_method)) {
                const method = try self.parseMethodDeclaration();
                try methods.append(self.allocator, method);
                continue;
            }

            // Field declaration: FieldName AS Type
            // Accept keywords as field names (e.g. Error, Data, Value).
            if (self.check(.identifier) or self.current().isKeyword()) {
                const field_name = self.current().lexeme;
                _ = self.advance();
                self.skipTypeSuffix();

                if (self.check(.kw_as)) {
                    _ = self.advance();
                    var built_in_type: ?Tag = null;
                    var field_type_name: []const u8 = "";
                    var is_built_in = true;

                    if (self.isTypeKeyword()) {
                        built_in_type = self.current().tag;
                        _ = self.advance();
                    } else if (self.check(.identifier) or self.current().isKeyword()) {
                        field_type_name = self.current().lexeme;
                        is_built_in = false;
                        _ = self.advance();
                    }

                    try fields.append(self.allocator, .{
                        .name = field_name,
                        .type_name = field_type_name,
                        .built_in_type = built_in_type,
                        .is_built_in = is_built_in,
                    });
                }
                if (self.check(.end_of_line)) _ = self.advance();
                continue;
            }

            // Unknown token inside class — skip line to recover.
            self.skipToEndOfLine();
            if (self.check(.end_of_line)) _ = self.advance();
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .class = .{
            .class_name = class_name,
            .parent_class_name = parent_name,
            .fields = try self.allocator.dupe(ast.TypeDeclStmt.TypeField, fields.items),
            .constructor = constructor,
            .destructor = destructor,
            .methods = try self.allocator.dupe(*ast.MethodStmt, methods.items),
        } });
    }

    /// Parse a METHOD declaration inside a CLASS body.
    fn parseMethodDeclaration(self: *Parser) ExprError!*ast.MethodStmt {
        _ = self.advance(); // consume METHOD

        if (!self.check(.identifier) and !self.current().isKeyword()) {
            try self.addError("Expected method name after METHOD");
            return error.ParseError;
        }
        const method_name = self.current().lexeme;
        _ = self.advance();

        const params = try self.parseParameterList();

        // Optional return type: AS ReturnType
        var return_type_suffix: ?Tag = null;
        var return_type_as_name: []const u8 = "";
        var has_return_type = false;
        if (self.check(.kw_as)) {
            _ = self.advance();
            has_return_type = true;
            if (self.isTypeKeyword()) {
                return_type_suffix = self.current().tag;
                return_type_as_name = self.current().lexeme;
                _ = self.advance();
            } else if (self.check(.identifier) or self.current().isKeyword()) {
                return_type_as_name = self.current().lexeme;
                _ = self.advance();
            }
        }

        if (self.check(.end_of_line)) _ = self.advance();

        // Parse method body until END METHOD.
        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_end)) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_method) {
                    _ = self.advance(); // consume END
                    _ = self.advance(); // consume METHOD
                    break;
                }
                // Bare END inside method body is a valid END statement — parse it.
                const stmt = try self.parseStatement();
                try body.append(self.allocator, stmt);
                continue;
            }
            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        const method = try self.allocator.create(ast.MethodStmt);
        method.* = .{
            .method_name = method_name,
            .parameters = params.names,
            .parameter_types = params.types,
            .parameter_as_types = params.as_types,
            .parameter_is_byref = params.is_byref,
            .return_type_suffix = return_type_suffix,
            .return_type_as_name = return_type_as_name,
            .has_return_type = has_return_type,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        };
        return method;
    }

    /// Parse a CONSTRUCTOR declaration inside a CLASS body.
    fn parseConstructorDeclaration(self: *Parser) ExprError!*ast.ConstructorStmt {
        _ = self.advance(); // consume CONSTRUCTOR

        const params = try self.parseParameterList();

        if (self.check(.end_of_line)) _ = self.advance();

        // Parse constructor body until END CONSTRUCTOR.
        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        var has_super_call = false;
        var super_args_list: std.ArrayList(ast.ExprPtr) = .empty;
        defer super_args_list.deinit(self.allocator);

        var first_statement = true;

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_end)) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_constructor) {
                    _ = self.advance(); // consume END
                    _ = self.advance(); // consume CONSTRUCTOR
                    break;
                }
                const stmt = try self.parseStatement();
                try body.append(self.allocator, stmt);
                first_statement = false;
                continue;
            }

            // Check for SUPER() call (should be first statement).
            if (self.check(.kw_super) and first_statement) {
                _ = self.advance(); // consume SUPER
                if (self.check(.lparen)) {
                    _ = self.advance();
                    has_super_call = true;
                    while (!self.check(.rparen) and !self.isAtEnd()) {
                        try super_args_list.append(self.allocator, try self.parseExpression());
                        if (self.check(.comma)) _ = self.advance();
                    }
                    if (self.check(.rparen)) _ = self.advance();
                }
                if (self.check(.end_of_line)) _ = self.advance();
                first_statement = false;
                continue;
            }

            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
            first_statement = false;
        }
        if (self.check(.end_of_line)) _ = self.advance();

        const ctor = try self.allocator.create(ast.ConstructorStmt);
        ctor.* = .{
            .parameters = params.names,
            .parameter_types = params.types,
            .parameter_as_types = params.as_types,
            .parameter_is_byref = params.is_byref,
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
            .has_super_call = has_super_call,
            .super_args = try self.allocator.dupe(ast.ExprPtr, super_args_list.items),
        };
        return ctor;
    }

    /// Parse a DESTRUCTOR declaration inside a CLASS body.
    fn parseDestructorDeclaration(self: *Parser) ExprError!*ast.DestructorStmt {
        _ = self.advance(); // consume DESTRUCTOR

        // Optional empty parens.
        if (self.check(.lparen)) {
            _ = self.advance();
            if (self.check(.rparen)) _ = self.advance();
        }

        if (self.check(.end_of_line)) _ = self.advance();

        // Parse destructor body until END DESTRUCTOR.
        var body: std.ArrayList(ast.StmtPtr) = .empty;
        defer body.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            if (self.check(.kw_end)) {
                if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .kw_destructor) {
                    _ = self.advance(); // consume END
                    _ = self.advance(); // consume DESTRUCTOR
                    break;
                }
                const stmt = try self.parseStatement();
                try body.append(self.allocator, stmt);
                continue;
            }
            const line = try self.parseProgramLine();
            for (line.statements) |s| {
                try body.append(self.allocator, s);
            }
        }
        if (self.check(.end_of_line)) _ = self.advance();

        const dtor = try self.allocator.create(ast.DestructorStmt);
        dtor.* = .{
            .body = try self.allocator.dupe(ast.StmtPtr, body.items),
        };
        return dtor;
    }

    fn parseDeleteStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume DELETE

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name after DELETE");
            return error.ParseError;
        }
        const var_name = self.current().lexeme;
        _ = self.advance();

        return self.builder.stmt(loc, .{ .delete = .{ .variable_name = var_name } });
    }

    fn parseOpenStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume OPEN
        // Simplified: OPEN "filename" FOR INPUT/OUTPUT AS #n
        // Skip parsing details for now.
        self.skipToEndOfLine();
        return self.builder.stmt(loc, .{ .open = .{ .filename = "" } });
    }

    fn parseCloseStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume CLOSE

        var file_number: i32 = 0;
        var close_all = false;

        if (self.check(.number)) {
            file_number = @intFromFloat(self.current().number_value);
            _ = self.advance();
        } else if (self.check(.hash)) {
            _ = self.advance();
            if (self.check(.number)) {
                file_number = @intFromFloat(self.current().number_value);
                _ = self.advance();
            }
        } else {
            close_all = true;
        }

        return self.builder.stmt(loc, .{ .close = .{
            .file_number = file_number,
            .close_all = close_all,
        } });
    }

    fn parseSimpleStatement(self: *Parser, comptime kind: std.meta.FieldEnum(ast.StmtData)) !ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance();
        return self.builder.stmt(loc, @unionInit(ast.StmtData, @tagName(kind), {}));
    }

    fn parseColorStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume COLOR

        const fg = try self.parseExpression();
        var bg: ?ast.ExprPtr = null;
        if (self.check(.comma)) {
            _ = self.advance();
            bg = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .color = .{ .fg = fg, .bg = bg } });
    }

    fn parseWaitStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume WAIT
        const dur = try self.parseExpression();
        return self.builder.stmt(loc, .{ .wait_stmt = .{ .duration = dur } });
    }

    fn parseWaitMsStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume WAIT_MS
        const duration = try self.parseExpression();
        return self.builder.stmt(loc, .{ .wait_ms = .{ .duration = duration } });
    }

    fn parseSleepStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume SLEEP
        // SLEEP takes an optional duration in seconds (double).
        // If no argument, default to 0 (sleep indefinitely or no-op).
        if (self.isAtEndOfStatement()) {
            return self.builder.stmt(loc, .{ .wait_stmt = .{
                .duration = try self.builder.numberExpr(loc, 0),
            } });
        }
        const duration = try self.parseExpression();
        return self.builder.stmt(loc, .{ .wait_stmt = .{ .duration = duration } });
    }

    fn parseTryCatchStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume TRY
        if (self.check(.end_of_line)) _ = self.advance();

        var try_block: std.ArrayList(ast.StmtPtr) = .empty;
        defer try_block.deinit(self.allocator);

        while (!self.isAtEnd()) {
            self.skipBlankLines();
            const try_tag = self.peekPastLineNumber();
            if (try_tag == .kw_catch or try_tag == .kw_finally) break;
            // Only break on END if it is followed by TRY (i.e. "END TRY").
            // A bare END is a valid statement (program termination) inside
            // TRY/CATCH blocks.
            if (try_tag == .kw_end and self.isEndTry()) break;
            const line = try self.parseProgramLine();
            for (line.statements) |s| try try_block.append(self.allocator, s);
        }

        var catch_clauses: std.ArrayList(ast.TryCatchStmt.CatchClause) = .empty;
        defer catch_clauses.deinit(self.allocator);

        while (self.peekPastLineNumber() == .kw_catch) {
            self.skipLineNumberBefore(.kw_catch);
            _ = self.advance(); // consume CATCH

            // Parse optional error code(s) after CATCH (e.g. CATCH 100).
            var error_codes: std.ArrayList(i32) = .empty;
            defer error_codes.deinit(self.allocator);
            while (self.check(.number)) {
                const code: i32 = @intFromFloat(self.current().number_value);
                try error_codes.append(self.allocator, code);
                _ = self.advance();
                if (self.check(.comma)) {
                    _ = self.advance();
                } else {
                    break;
                }
            }

            if (self.check(.end_of_line)) _ = self.advance();

            var block: std.ArrayList(ast.StmtPtr) = .empty;
            defer block.deinit(self.allocator);

            while (!self.isAtEnd()) {
                self.skipBlankLines();
                const catch_inner_tag = self.peekPastLineNumber();
                if (catch_inner_tag == .kw_catch or catch_inner_tag == .kw_finally) break;
                if (catch_inner_tag == .kw_end and self.isEndTry()) break;
                const line = try self.parseProgramLine();
                for (line.statements) |s| try block.append(self.allocator, s);
            }

            try catch_clauses.append(self.allocator, .{
                .block = try self.allocator.dupe(ast.StmtPtr, block.items),
            });
        }

        var finally_block: std.ArrayList(ast.StmtPtr) = .empty;
        defer finally_block.deinit(self.allocator);
        var has_finally = false;

        if (self.peekPastLineNumber() == .kw_finally) {
            has_finally = true;
            self.skipLineNumberBefore(.kw_finally);
            _ = self.advance();
            if (self.check(.end_of_line)) _ = self.advance();

            while (!self.isAtEnd()) {
                self.skipBlankLines();
                if (self.peekPastLineNumber() == .kw_end and self.isEndTry()) break;
                const line = try self.parseProgramLine();
                for (line.statements) |s| try finally_block.append(self.allocator, s);
            }
        }

        // Consume END TRY.
        self.skipLineNumberBefore(.kw_end);
        if (self.check(.kw_end)) {
            _ = self.advance();
            if (self.check(.kw_try)) _ = self.advance();
        }
        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .try_catch = .{
            .try_block = try self.allocator.dupe(ast.StmtPtr, try_block.items),
            .catch_clauses = try self.allocator.dupe(ast.TryCatchStmt.CatchClause, catch_clauses.items),
            .finally_block = try self.allocator.dupe(ast.StmtPtr, finally_block.items),
            .has_finally = has_finally,
        } });
    }

    fn parseThrowStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume THROW

        var error_code: ?ast.ExprPtr = null;
        if (!self.isAtEndOfStatement()) {
            error_code = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .throw_stmt = .{ .error_code = error_code } });
    }

    fn parseOnStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume ON

        // Simplified: ON expr GOTO/GOSUB label1, label2, ...
        const selector = try self.parseExpression();

        if (self.check(.kw_goto)) {
            _ = self.advance();
            var labels: std.ArrayList([]const u8) = .empty;
            defer labels.deinit(self.allocator);

            while (!self.isAtEndOfStatement()) {
                if (self.check(.identifier)) {
                    try labels.append(self.allocator, self.current().lexeme);
                    _ = self.advance();
                } else if (self.check(.number)) {
                    try labels.append(self.allocator, self.current().lexeme);
                    _ = self.advance();
                } else break;
                if (self.check(.comma)) _ = self.advance() else break;
            }

            return self.builder.stmt(loc, .{ .on_goto = .{
                .selector = selector,
                .labels = try self.allocator.dupe([]const u8, labels.items),
                .line_numbers = &.{},
                .is_label_list = &.{},
            } });
        } else if (self.check(.kw_gosub)) {
            _ = self.advance();
            var labels: std.ArrayList([]const u8) = .empty;
            defer labels.deinit(self.allocator);

            while (!self.isAtEndOfStatement()) {
                if (self.check(.identifier)) {
                    try labels.append(self.allocator, self.current().lexeme);
                    _ = self.advance();
                } else if (self.check(.number)) {
                    try labels.append(self.allocator, self.current().lexeme);
                    _ = self.advance();
                } else break;
                if (self.check(.comma)) _ = self.advance() else break;
            }

            return self.builder.stmt(loc, .{ .on_gosub = .{
                .selector = selector,
                .labels = try self.allocator.dupe([]const u8, labels.items),
                .line_numbers = &.{},
                .is_label_list = &.{},
            } });
        }

        try self.addError("Expected GOTO or GOSUB after ON expression");
        return error.ParseError;
    }

    fn parseAfterStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume AFTER
        const dur = try self.parseExpression();

        var unit: ast.TimeUnit = .milliseconds;
        if (self.check(.kw_ms)) {
            _ = self.advance();
            unit = .milliseconds;
        } else if (self.check(.kw_secs)) {
            _ = self.advance();
            unit = .seconds;
        } else if (self.check(.kw_frames)) {
            _ = self.advance();
            unit = .frames;
        }

        var handler_name: []const u8 = "";
        if (self.check(.kw_call) or self.check(.kw_goto) or self.check(.kw_gosub)) {
            _ = self.advance();
        }
        if (self.check(.identifier)) {
            handler_name = self.current().lexeme;
            _ = self.advance();
        }

        return self.builder.stmt(loc, .{ .after = .{
            .duration = dur,
            .unit = unit,
            .handler_name = handler_name,
        } });
    }

    fn parseEveryStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume EVERY
        const dur = try self.parseExpression();

        var unit: ast.TimeUnit = .milliseconds;
        if (self.check(.kw_ms)) {
            _ = self.advance();
            unit = .milliseconds;
        } else if (self.check(.kw_secs)) {
            _ = self.advance();
            unit = .seconds;
        } else if (self.check(.kw_frames)) {
            _ = self.advance();
            unit = .frames;
        }

        var handler_name: []const u8 = "";
        if (self.check(.kw_call) or self.check(.kw_goto) or self.check(.kw_gosub)) {
            _ = self.advance();
        }
        if (self.check(.identifier)) {
            handler_name = self.current().lexeme;
            _ = self.advance();
        }

        return self.builder.stmt(loc, .{ .every = .{
            .duration = dur,
            .unit = unit,
            .handler_name = handler_name,
        } });
    }

    fn parseRunStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume RUN

        var until_cond: ?ast.ExprPtr = null;
        if (self.check(.kw_until)) {
            _ = self.advance();
            until_cond = try self.parseExpression();
        }

        return self.builder.stmt(loc, .{ .run = .{ .until_condition = until_cond } });
    }

    fn parseMatchTypeStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume MATCH

        // Consume optional TYPE keyword after MATCH.
        if (self.check(.kw_type)) {
            _ = self.advance();
        }

        // Parse the expression being matched.
        const match_expr = try self.parseExpression();
        if (self.check(.end_of_line)) _ = self.advance();

        var case_arms: std.ArrayList(ast.MatchTypeStmt.CaseArm) = .empty;
        defer case_arms.deinit(self.allocator);

        var case_else_body: []ast.StmtPtr = @constCast(&.{});

        while (!self.isAtEnd()) {
            self.skipBlankLines();

            // Check for END MATCH / ENDMATCH
            if (self.check(.kw_endmatch)) {
                _ = self.advance();
                break;
            }
            if (self.check(.kw_end)) {
                // Peek: END MATCH
                if (self.pos + 1 < self.tokens.len) {
                    const next = self.tokens[self.pos + 1];
                    if (next.tag == .kw_match) {
                        _ = self.advance(); // consume END
                        _ = self.advance(); // consume MATCH
                        break;
                    }
                }
                // Bare END — might be end of program
                break;
            }

            // Parse CASE arm
            if (self.check(.kw_case)) {
                _ = self.advance(); // consume CASE

                // CASE ELSE
                if (self.check(.kw_else)) {
                    _ = self.advance();
                    if (self.check(.end_of_line)) _ = self.advance();

                    var else_stmts: std.ArrayList(ast.StmtPtr) = .empty;
                    defer else_stmts.deinit(self.allocator);

                    while (!self.isAtEnd()) {
                        self.skipBlankLines();
                        if (self.check(.kw_case) or self.check(.kw_endmatch) or self.check(.kw_end)) break;
                        try else_stmts.append(self.allocator, try self.parseStatement());
                        if (self.check(.end_of_line)) _ = self.advance();
                    }
                    case_else_body = try self.allocator.dupe(ast.StmtPtr, else_stmts.items);
                    continue;
                }

                // CASE <type> [binding_var]
                var type_keyword: []const u8 = "";
                var atom_type_tag: i32 = 0;
                var binding_variable: []const u8 = "";
                var binding_suffix: ?Tag = null;
                var is_class_match = false;
                var match_class_name: []const u8 = "";
                var is_udt_match = false;
                var udt_type_name: []const u8 = "";

                if (self.isTypeKeyword()) {
                    type_keyword = self.current().lexeme;
                    atom_type_tag = @intFromEnum(self.current().tag);
                    _ = self.advance();
                } else if (self.check(.identifier)) {
                    // Could be a class name or UDT name
                    const type_name = self.current().lexeme;
                    _ = self.advance();

                    // Determine if it's a class or UDT match
                    is_class_match = true;
                    match_class_name = type_name;
                    is_udt_match = false;
                    udt_type_name = type_name;
                } else {
                    try self.addError("Expected type name after CASE in MATCH TYPE");
                    return error.ParseError;
                }

                // Optional binding variable name
                if (self.check(.identifier)) {
                    binding_variable = self.current().lexeme;
                    _ = self.advance();
                    if (self.isTypeSuffix()) {
                        binding_suffix = self.current().tag;
                        _ = self.advance();
                    }
                } else if (self.current().isKeyword() and !self.check(.end_of_line) and !self.check(.kw_case) and !self.check(.kw_end)) {
                    // Accept keywords as binding variable names
                    binding_variable = self.current().lexeme;
                    _ = self.advance();
                    if (self.isTypeSuffix()) {
                        binding_suffix = self.current().tag;
                        _ = self.advance();
                    }
                }

                if (self.check(.end_of_line)) _ = self.advance();

                // Parse body statements for this CASE arm.
                var body: std.ArrayList(ast.StmtPtr) = .empty;
                defer body.deinit(self.allocator);

                while (!self.isAtEnd()) {
                    self.skipBlankLines();
                    if (self.check(.kw_case) or self.check(.kw_endmatch) or self.check(.kw_end)) break;
                    try body.append(self.allocator, try self.parseStatement());
                    if (self.check(.end_of_line)) _ = self.advance();
                }

                try case_arms.append(self.allocator, .{
                    .type_keyword = type_keyword,
                    .atom_type_tag = atom_type_tag,
                    .binding_variable = binding_variable,
                    .binding_suffix = binding_suffix,
                    .body = try self.allocator.dupe(ast.StmtPtr, body.items),
                    .is_class_match = is_class_match,
                    .match_class_name = match_class_name,
                    .is_udt_match = is_udt_match,
                    .udt_type_name = udt_type_name,
                });
            } else {
                // Skip unexpected content
                _ = self.advance();
            }
        }

        if (self.check(.end_of_line)) _ = self.advance();

        return self.builder.stmt(loc, .{ .match_type = .{
            .match_expression = match_expr,
            .case_arms = try self.allocator.dupe(ast.MatchTypeStmt.CaseArm, case_arms.items),
            .case_else_body = case_else_body,
        } });
    }

    /// Parse a statement starting with ME (e.g., ME.Name = value).
    fn parseMeStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();

        // Check if this is a method call: ME.method(args)
        if (self.isMethodCallStatement()) {
            const expr = try self.parseExpression();
            return self.builder.stmt(loc, .{ .call = .{
                .sub_name = "ME",
                .arguments = &.{},
                .method_call_expr = expr,
            } });
        }

        // Otherwise it's an assignment: ME.field = value
        // Consume ME and treat it as the variable name for assignment.
        _ = self.advance(); // consume ME

        var member_chain: std.ArrayList([]const u8) = .empty;
        defer member_chain.deinit(self.allocator);

        // Parse member chain: ME.field1.field2 ...
        while (self.check(.dot)) {
            _ = self.advance();
            if (self.check(.identifier) or self.current().isKeyword()) {
                try member_chain.append(self.allocator, self.current().lexeme);
                _ = self.advance();
                self.skipTypeSuffix();
            } else {
                try self.addError("Expected member name after '.'");
                return error.ParseError;
            }
        }

        _ = try self.consume(.equal, "Expected '=' in ME assignment");
        const value = try self.parseExpression();

        return self.builder.stmt(loc, .{ .let = .{
            .variable = "ME",
            .member_chain = try self.allocator.dupe([]const u8, member_chain.items),
            .value = value,
        } });
    }

    /// Handle SUPER.Method() calls at statement start.
    fn parseSuperStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();

        // SUPER should always be followed by .Method() in statement context.
        // Parse the full expression (parsePrimary emits a variable "SUPER",
        // parsePostfix handles the .Method(args) chain).
        const expr = try self.parseExpression();
        return self.builder.stmt(loc, .{ .call = .{
            .sub_name = "SUPER",
            .arguments = &.{},
            .method_call_expr = expr,
        } });
    }

    /// Handle keywords that can appear as variable names or method-call
    /// targets at the start of a statement (e.g. `left = 7`, `left$ = "x"`).
    /// The keyword token is re-interpreted as an identifier and delegated
    /// to the same logic as parseIdentifierStatement / parseAssignment.
    fn parseKeywordAsIdentifierStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();

        if (!self.allow_implicit_let) {
            try self.addError("Unexpected token at start of statement");
            return error.ParseError;
        }

        // Detect method-call pattern: keyword[suffix].name(
        // We peek ahead past the keyword and optional suffix to check for dot.
        var peek_offset: usize = 1;
        if (self.pos + peek_offset < self.tokens.len and
            self.tokens[self.pos + peek_offset].isTypeSuffix())
        {
            peek_offset += 1;
        }
        const has_dot = (self.pos + peek_offset < self.tokens.len and
            self.tokens[self.pos + peek_offset].tag == .dot);

        if (has_dot) {
            // Could be method call (keyword.method(args)) or member assignment.
            // Check further: dot + name + lparen → method call statement.
            const has_method_call = (self.pos + peek_offset + 2 < self.tokens.len and
                (self.tokens[self.pos + peek_offset + 1].tag == .identifier or
                    self.tokens[self.pos + peek_offset + 1].isKeyword()) and
                self.tokens[self.pos + peek_offset + 2].tag == .lparen);

            if (has_method_call) {
                const name = self.current().lexeme;
                const expr = try self.parseExpression();
                return self.builder.stmt(loc, .{ .call = .{
                    .sub_name = name,
                    .arguments = &.{},
                    .method_call_expr = expr,
                } });
            }
        }

        // Otherwise treat as implicit LET assignment.
        return self.parseKeywordAssignment(loc);
    }

    /// Parse an assignment where the variable name is a keyword token
    /// (e.g. `left$ = "hello"`, `mid = 5`).  Mirrors parseAssignment
    /// but reads the variable name from a keyword token.
    fn parseKeywordAssignment(self: *Parser, loc: SourceLocation) ExprError!ast.StmtPtr {
        const name = self.current().lexeme;
        _ = self.advance(); // consume keyword token

        var type_suffix: ?Tag = null;
        if (self.isTypeSuffix()) {
            type_suffix = self.current().tag;
            _ = self.advance();
        }

        // Parse optional array indices.
        var indices: std.ArrayList(ast.ExprPtr) = .empty;
        defer indices.deinit(self.allocator);

        if (self.check(.lparen)) {
            _ = self.advance();
            if (!self.check(.rparen)) {
                try indices.append(self.allocator, try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try indices.append(self.allocator, try self.parseExpression());
                }
            }
            _ = try self.consume(.rparen, "Expected ')' after indices");
        }

        // Parse optional member chain: .field1.field2 ...
        var member_chain: std.ArrayList([]const u8) = .empty;
        defer member_chain.deinit(self.allocator);

        while (self.check(.dot)) {
            _ = self.advance();
            if (self.check(.identifier) or self.current().isKeyword()) {
                try member_chain.append(self.allocator, self.current().lexeme);
                _ = self.advance();
                self.skipTypeSuffix();
            } else {
                try self.addError("Expected member name after '.'");
                return error.ParseError;
            }
        }

        _ = try self.consume(.equal, "Expected '=' in assignment");
        const value = try self.parseExpression();

        return self.builder.stmt(loc, .{ .let = .{
            .variable = name,
            .type_suffix = type_suffix,
            .indices = try self.allocator.dupe(ast.ExprPtr, indices.items),
            .member_chain = try self.allocator.dupe([]const u8, member_chain.items),
            .value = value,
        } });
    }

    fn parseIdentifierStatement(self: *Parser) ExprError!ast.StmtPtr {
        const loc = self.currentLocation();

        // Check if this is a label definition: "labelName:"
        if (self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .colon) {
            const label_name = self.current().lexeme;
            _ = self.advance(); // consume identifier
            _ = self.advance(); // consume colon
            return self.builder.stmt(loc, .{ .label = .{ .label_name = label_name } });
        }

        // Check if this is a known SUB call (without CALL keyword).
        const name = self.current().lexeme;
        var buf: [128]u8 = undefined;
        const len = @min(name.len, buf.len);
        for (0..len) |i| buf[i] = std.ascii.toUpper(name[i]);
        const upper_name = buf[0..len];

        if (self.user_subs.contains(upper_name) or self.user_subs.contains(name)) {
            return self.parseCallStatement();
        }

        // Check for method-call statement: identifier.method(args)
        // or identifier(index).method(args)
        // These are void calls like d.CLEAR(), list.APPEND(x), etc.
        if (self.allow_implicit_let and self.isMethodCallStatement()) {
            // Parse as expression statement — the expression parser handles
            // member access, method calls, and postfix chains naturally.
            const expr = try self.parseExpression();
            return self.builder.stmt(loc, .{ .call = .{
                .sub_name = name,
                .arguments = &.{},
                .method_call_expr = expr,
            } });
        }

        // Otherwise, treat as implicit LET assignment.
        if (self.allow_implicit_let) {
            return self.parseAssignment(loc);
        }

        try self.addError("Unexpected identifier at start of statement");
        return error.ParseError;
    }

    /// Parse an assignment: variable = expression (with optional member chain
    /// and array indices).
    fn parseAssignment(self: *Parser, loc: SourceLocation) ExprError!ast.StmtPtr {
        // Slice assignment detection: name$(expr TO expr) = value
        // Check ahead for the pattern: identifier [suffix] ( expr TO expr )
        if (self.check(.identifier)) {
            // Peek for TO inside parens to detect slice pattern
            var peek_pos = self.pos + 1;
            // Skip optional suffix
            if (peek_pos < self.tokens.len and self.tokens[peek_pos].isTypeSuffix()) {
                peek_pos += 1;
            }
            // Check for lparen
            if (peek_pos < self.tokens.len and self.tokens[peek_pos].tag == .lparen) {
                // Scan forward to find TO at depth 1 before rparen
                var scan = peek_pos + 1;
                var depth: u32 = 1;
                var found_to = false;
                while (scan < self.tokens.len and depth > 0) {
                    if (self.tokens[scan].tag == .lparen) depth += 1;
                    if (self.tokens[scan].tag == .rparen) {
                        depth -= 1;
                        if (depth == 0) break;
                    }
                    if (self.tokens[scan].tag == .kw_to and depth == 1) {
                        found_to = true;
                        break;
                    }
                    scan += 1;
                }
                if (found_to) {
                    const saved_name = self.current().lexeme;
                    _ = self.advance(); // consume identifier
                    // Skip optional suffix
                    if (self.isTypeSuffix()) _ = self.advance();
                    _ = self.advance(); // consume '('
                    const start_expr = try self.parseExpression();
                    _ = try self.consume(.kw_to, "Expected TO in slice");
                    const end_expr = try self.parseExpression();
                    _ = try self.consume(.rparen, "Expected ')' after slice range");
                    _ = try self.consume(.equal, "Expected '=' in slice assignment");
                    const replacement = try self.parseExpression();
                    return self.builder.stmt(loc, .{ .slice_assign = .{
                        .variable = saved_name,
                        .start = start_expr,
                        .end_expr = end_expr,
                        .replacement = replacement,
                    } });
                }
            }
        }

        if (!self.check(.identifier)) {
            try self.addError("Expected variable name in assignment");
            return error.ParseError;
        }

        const variable = self.current().lexeme;
        _ = self.advance();

        var type_suffix: ?Tag = null;
        if (self.isTypeSuffix()) {
            type_suffix = self.current().tag;
            _ = self.advance();
        }

        var indices: std.ArrayList(ast.ExprPtr) = .empty;
        defer indices.deinit(self.allocator);

        var member_chain: std.ArrayList([]const u8) = .empty;
        defer member_chain.deinit(self.allocator);

        // Array indices: variable(expr, expr, ...)
        if (self.check(.lparen)) {
            _ = self.advance();
            if (!self.check(.rparen)) {
                try indices.append(self.allocator, try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try indices.append(self.allocator, try self.parseExpression());
                }
            }
            _ = try self.consume(.rparen, "Expected ')' after array indices");
        }

        // Member chain: variable.field1.field2
        // Accept keywords as member names (SIZE, CLEAR, KEYS, etc.).
        while (self.check(.dot)) {
            _ = self.advance();
            if (self.check(.identifier) or self.current().isKeyword()) {
                try member_chain.append(self.allocator, self.current().lexeme);
                _ = self.advance();
                self.skipTypeSuffix();
            } else {
                try self.addError("Expected member name after '.'");
                return error.ParseError;
            }
        }

        _ = try self.consume(.equal, "Expected '=' in assignment");
        const value = try self.parseExpression();

        return self.builder.stmt(loc, .{ .let = .{
            .variable = variable,
            .type_suffix = type_suffix,
            .indices = try self.allocator.dupe(ast.ExprPtr, indices.items),
            .member_chain = try self.allocator.dupe([]const u8, member_chain.items),
            .value = value,
        } });
    }

    // ═════════════════════════════════════════════════════════════════════
    // Expression parsing (operator precedence climbing)
    // ═════════════════════════════════════════════════════════════════════

    /// Parse an expression (entry point for the precedence hierarchy).
    /// Explicit error set to break recursive error set inference in Zig 0.15.
    pub const ExprError = error{ ParseError, OutOfMemory };
    pub fn parseExpression(self: *Parser) ExprError!ast.ExprPtr {
        return self.parseLogicalImp();
    }

    fn parseLogicalImp(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseLogicalEqv();
        while (self.check(.kw_imp)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parseLogicalEqv();
            expr = try self.builder.binaryExpr(loc, expr, .kw_imp, right);
        }
        return expr;
    }

    fn parseLogicalEqv(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseLogicalOr();
        while (self.check(.kw_eqv)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parseLogicalOr();
            expr = try self.builder.binaryExpr(loc, expr, .kw_eqv, right);
        }
        return expr;
    }

    fn parseLogicalOr(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseLogicalXor();
        while (self.check(.kw_or)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parseLogicalXor();
            expr = try self.builder.binaryExpr(loc, expr, .kw_or, right);
        }
        return expr;
    }

    fn parseLogicalXor(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseLogicalAnd();
        while (self.check(.kw_xor)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parseLogicalAnd();
            expr = try self.builder.binaryExpr(loc, expr, .kw_xor, right);
        }
        return expr;
    }

    fn parseLogicalAnd(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseLogicalNot();
        while (self.check(.kw_and)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parseLogicalNot();
            expr = try self.builder.binaryExpr(loc, expr, .kw_and, right);
        }
        return expr;
    }

    fn parseLogicalNot(self: *Parser) ExprError!ast.ExprPtr {
        if (self.check(.kw_not)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const operand = try self.parseComparison();
            return self.builder.expr(loc, .{ .unary = .{ .op = .kw_not, .operand = operand } });
        }
        return self.parseComparison();
    }

    fn parseComparison(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseAdditive();
        while (self.current().isComparison() or self.check(.kw_is)) {
            const loc = self.currentLocation();
            if (self.check(.kw_is)) {
                _ = self.advance(); // consume IS

                // IS NOTHING — null check
                if (self.check(.kw_nothing)) {
                    _ = self.advance();
                    expr = try self.builder.expr(loc, .{ .is_type = .{
                        .object = expr,
                        .class_name = "",
                        .is_nothing_check = true,
                    } });
                } else {
                    // IS ClassName — type check
                    // Accept identifier or keyword as class/type name.
                    if (!self.check(.identifier) and !self.current().isKeyword()) {
                        try self.addError("Expected type name or NOTHING after IS");
                        return error.ParseError;
                    }
                    const class_name = self.current().lexeme;
                    _ = self.advance();
                    expr = try self.builder.expr(loc, .{ .is_type = .{
                        .object = expr,
                        .class_name = class_name,
                        .is_nothing_check = false,
                    } });
                }
            } else {
                const op = self.current().tag;
                _ = self.advance();
                const right = try self.parseAdditive();
                expr = try self.builder.binaryExpr(loc, expr, op, right);
            }
        }
        return expr;
    }

    fn parseAdditive(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseMultiplicative();
        while (self.check(.plus) or self.check(.minus)) {
            const loc = self.currentLocation();
            const op = self.current().tag;
            _ = self.advance();
            const right = try self.parseMultiplicative();
            expr = try self.builder.binaryExpr(loc, expr, op, right);
        }
        return expr;
    }

    fn parseMultiplicative(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parseUnary();
        while (self.check(.multiply) or self.check(.divide) or self.check(.int_divide) or self.check(.kw_mod)) {
            const loc = self.currentLocation();
            const op = self.current().tag;
            _ = self.advance();
            const right = try self.parseUnary();
            expr = try self.builder.binaryExpr(loc, expr, op, right);
        }
        return expr;
    }

    fn parseUnary(self: *Parser) ExprError!ast.ExprPtr {
        if (self.check(.minus)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const operand = try self.parsePower();
            return self.builder.expr(loc, .{ .unary = .{ .op = .minus, .operand = operand } });
        }
        if (self.check(.plus)) {
            _ = self.advance();
            return self.parsePower();
        }
        return self.parsePower();
    }

    fn parsePower(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parsePostfix();
        while (self.check(.power)) {
            const loc = self.currentLocation();
            _ = self.advance();
            const right = try self.parsePostfix();
            expr = try self.builder.binaryExpr(loc, expr, .power, right);
        }
        return expr;
    }

    fn parsePostfix(self: *Parser) ExprError!ast.ExprPtr {
        var expr = try self.parsePrimary();

        // Member access and method calls: expr.member or expr.method(args)
        while (self.check(.dot)) {
            const loc = self.currentLocation();
            _ = self.advance(); // consume '.'

            // After '.', accept identifiers AND keywords as member/method
            // names. Many BASIC built-in method names collide with keywords:
            // SIZE, CLEAR, REMOVE, KEYS, LENGTH, EMPTY, APPEND, HEAD, TAIL,
            // REST, CONTAINS, INDEXOF, JOIN, COPY, REVERSE, SHIFT, POP,
            // EXTEND, INSERT, GET, HASKEY, PREPEND, etc.
            if (!self.check(.identifier) and !self.current().isKeyword()) {
                try self.addError("Expected member name after '.'");
                return error.ParseError;
            }
            const member_name = self.current().lexeme;
            _ = self.advance();
            self.skipTypeSuffix();

            // Check if it's a method call.
            if (self.check(.lparen)) {
                _ = self.advance();
                var args: std.ArrayList(ast.ExprPtr) = .empty;
                defer args.deinit(self.allocator);

                if (!self.check(.rparen)) {
                    try args.append(self.allocator, try self.parseExpression());
                    while (self.check(.comma)) {
                        _ = self.advance();
                        try args.append(self.allocator, try self.parseExpression());
                    }
                }
                _ = try self.consume(.rparen, "Expected ')' after method arguments");

                expr = try self.builder.expr(loc, .{ .method_call = .{
                    .object = expr,
                    .method_name = member_name,
                    .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                } });
            } else {
                expr = try self.builder.expr(loc, .{ .member_access = .{
                    .object = expr,
                    .member_name = member_name,
                } });
            }
        }

        return expr;
    }

    fn parsePrimary(self: *Parser) ExprError!ast.ExprPtr {
        const tok = self.current();
        const loc = self.currentLocation();

        switch (tok.tag) {
            .number => {
                _ = self.advance();
                // Skip optional type suffix after number literal (e.g. 42%, 3.14#)
                self.skipTypeSuffix();
                return self.builder.numberExpr(loc, tok.number_value);
            },
            .string => {
                _ = self.advance();
                const value = lexer_mod.Lexer.stringValue(tok);
                return self.builder.stringExpr(loc, value);
            },
            .identifier => {
                const name = tok.lexeme;
                _ = self.advance();

                var type_suffix: ?Tag = null;
                if (self.isTypeSuffix()) {
                    type_suffix = self.current().tag;
                    _ = self.advance();
                }

                // Function call, array access, or string slice: name(args...)
                if (self.check(.lparen)) {
                    // ── String slice detection ──────────────────────────
                    // Check for the pattern name$(start TO end) which is a
                    // string slice expression.  Peek ahead for TO at depth 1.
                    {
                        var scan_pos = self.pos + 1; // past '('
                        var scan_depth: u32 = 1;
                        var found_to = false;
                        while (scan_pos < self.tokens.len and scan_depth > 0) {
                            if (self.tokens[scan_pos].tag == .lparen) scan_depth += 1;
                            if (self.tokens[scan_pos].tag == .rparen) {
                                scan_depth -= 1;
                                if (scan_depth == 0) break;
                            }
                            if (self.tokens[scan_pos].tag == .kw_to and scan_depth == 1) {
                                found_to = true;
                                break;
                            }
                            scan_pos += 1;
                        }
                        if (found_to) {
                            // Parse as string slice: name$(start TO end)
                            // Also handles: name$(TO end)  — start defaults to 1
                            //               name$(start TO) — end defaults to LEN
                            _ = self.advance(); // consume '('

                            // Check for (TO end) form — no start expression
                            var start_expr: ast.ExprPtr = undefined;
                            if (self.check(.kw_to)) {
                                // No start expression — default to 1
                                start_expr = try self.builder.numberExpr(loc, 1.0);
                            } else {
                                start_expr = try self.parseExpression();
                            }

                            _ = try self.consume(.kw_to, "Expected TO in slice expression");

                            // Check for (start TO) form — no end expression
                            var end_expr: ast.ExprPtr = undefined;
                            if (self.check(.rparen)) {
                                // No end expression — default to -1 (meaning
                                // LEN; the codegen/runtime interprets -1 as end).
                                end_expr = try self.builder.numberExpr(loc, -1.0);
                            } else {
                                end_expr = try self.parseExpression();
                            }

                            _ = try self.consume(.rparen, "Expected ')' after slice range");
                            // Emit as a function call to MID$ with the variable
                            // as first argument and start/end as 2nd/3rd.
                            // The codegen maps this to the runtime slice function.
                            const var_expr = try self.builder.variableExpr(loc, name, type_suffix);
                            return self.builder.expr(loc, .{ .function_call = .{
                                .name = "MID",
                                .arguments = try self.allocator.dupe(ast.ExprPtr, &.{ var_expr, start_expr, end_expr }),
                            } });
                        }
                    }

                    // Determine if this is a function call or array access.
                    // If the name is a known function, treat as function call.
                    var is_function = self.isBuiltinFunction(name);
                    if (!is_function) {
                        var buf2: [128]u8 = undefined;
                        const ulen = @min(name.len, buf2.len);
                        for (0..ulen) |i| buf2[i] = std.ascii.toUpper(name[i]);
                        is_function = self.user_functions.contains(buf2[0..ulen]) or
                            self.user_functions.contains(name);
                    }

                    _ = self.advance(); // consume '('
                    var args: std.ArrayList(ast.ExprPtr) = .empty;
                    defer args.deinit(self.allocator);

                    if (!self.check(.rparen)) {
                        try args.append(self.allocator, try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try args.append(self.allocator, try self.parseExpression());
                        }
                    }
                    _ = try self.consume(.rparen, "Expected ')' after arguments");

                    if (is_function) {
                        return self.builder.expr(loc, .{ .function_call = .{
                            .name = name,
                            .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                        } });
                    } else {
                        // Treat as array access.
                        return self.builder.expr(loc, .{ .array_access = .{
                            .name = name,
                            .type_suffix = type_suffix,
                            .indices = try self.allocator.dupe(ast.ExprPtr, args.items),
                        } });
                    }
                }

                return self.builder.variableExpr(loc, name, type_suffix);
            },
            .lparen => {
                _ = self.advance(); // consume '('
                const expr = try self.parseExpression();
                _ = try self.consume(.rparen, "Expected ')' after expression");
                return expr;
            },
            .kw_iif => {
                _ = self.advance(); // consume IIF
                _ = try self.consume(.lparen, "Expected '(' after IIF");
                const cond = try self.parseExpression();
                _ = try self.consume(.comma, "Expected ',' after IIF condition");
                const true_val = try self.parseExpression();
                _ = try self.consume(.comma, "Expected ',' after IIF true value");
                const false_val = try self.parseExpression();
                _ = try self.consume(.rparen, "Expected ')' after IIF");
                return self.builder.expr(loc, .{ .iif = .{
                    .condition = cond,
                    .true_value = true_val,
                    .false_value = false_val,
                } });
            },
            .kw_new => {
                _ = self.advance(); // consume NEW
                if (!self.check(.identifier) and !self.current().isKeyword()) {
                    try self.addError("Expected class name after NEW");
                    return error.ParseError;
                }
                const class_name = self.current().lexeme;
                _ = self.advance();

                var args: std.ArrayList(ast.ExprPtr) = .empty;
                defer args.deinit(self.allocator);

                if (self.check(.lparen)) {
                    _ = self.advance();
                    if (!self.check(.rparen)) {
                        try args.append(self.allocator, try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try args.append(self.allocator, try self.parseExpression());
                        }
                    }
                    _ = try self.consume(.rparen, "Expected ')' after NEW arguments");
                }

                return self.builder.expr(loc, .{ .new = .{
                    .class_name = class_name,
                    .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                } });
            },
            .kw_create => {
                return self.parseCreateExpression();
            },
            .kw_me => {
                _ = self.advance();
                return self.builder.expr(loc, .{ .me = {} });
            },
            .kw_nothing => {
                _ = self.advance();
                return self.builder.expr(loc, .{ .nothing = {} });
            },
            .kw_not => {
                _ = self.advance();
                const operand = try self.parsePrimary();
                return self.builder.expr(loc, .{ .unary = .{ .op = .kw_not, .operand = operand } });
            },
            .minus => {
                _ = self.advance();
                const operand = try self.parsePrimary();
                return self.builder.expr(loc, .{ .unary = .{ .op = .minus, .operand = operand } });
            },
            // Built-in functions that are also keywords: MID, LEFT, RIGHT.
            // When followed by '(' they are function calls; otherwise they
            // are treated as plain variables (e.g. `left = 7`).
            .kw_mid, .kw_left, .kw_right => {
                const fname = tok.lexeme;
                _ = self.advance();

                // Consume optional type suffix (shouldn't normally appear
                // after the bare keyword, but handle gracefully).
                var type_suffix: ?Tag = null;
                if (self.isTypeSuffix()) {
                    type_suffix = self.current().tag;
                    _ = self.advance();
                }

                if (self.check(.lparen)) {
                    _ = self.advance(); // consume '('
                    var args: std.ArrayList(ast.ExprPtr) = .empty;
                    defer args.deinit(self.allocator);

                    if (!self.check(.rparen)) {
                        try args.append(self.allocator, try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try args.append(self.allocator, try self.parseExpression());
                        }
                    }
                    _ = try self.consume(.rparen, "Expected ')' after built-in function arguments");
                    return self.builder.expr(loc, .{ .function_call = .{
                        .name = fname,
                        .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                    } });
                }

                // No '(' follows — treat as a variable reference.
                return self.builder.variableExpr(loc, fname, type_suffix);
            },
            .kw_err => {
                _ = self.advance();
                // Consume optional trailing () — ERR and ERR() are equivalent.
                if (self.check(.lparen)) {
                    _ = self.advance();
                    if (self.check(.rparen)) _ = self.advance();
                }
                return self.builder.expr(loc, .{ .function_call = .{
                    .name = "ERR",
                    .arguments = &.{},
                } });
            },
            .kw_erl => {
                _ = self.advance();
                // Consume optional trailing () — ERL and ERL() are equivalent.
                if (self.check(.lparen)) {
                    _ = self.advance();
                    if (self.check(.rparen)) _ = self.advance();
                }
                return self.builder.expr(loc, .{ .function_call = .{
                    .name = "ERL",
                    .arguments = &.{},
                } });
            },
            .kw_super => {
                // SUPER in expression context — typically SUPER.Method().
                // Emit as a variable so parsePostfix can handle the dot chain.
                _ = self.advance();
                return self.builder.variableExpr(loc, "SUPER", null);
            },
            .kw_list => {
                // LIST(expr, expr, ...) — list constructor expression.
                _ = self.advance(); // consume LIST
                if (self.check(.lparen)) {
                    _ = self.advance(); // consume '('
                    var elements: std.ArrayList(ast.ExprPtr) = .empty;
                    defer elements.deinit(self.allocator);

                    if (!self.check(.rparen)) {
                        try elements.append(self.allocator, try self.parseExpression());
                        while (self.check(.comma)) {
                            _ = self.advance();
                            try elements.append(self.allocator, try self.parseExpression());
                        }
                    }
                    _ = try self.consume(.rparen, "Expected ')' after LIST elements");
                    return self.builder.expr(loc, .{ .list_constructor = .{
                        .elements = try self.allocator.dupe(ast.ExprPtr, elements.items),
                    } });
                }
                // Bare LIST without parens — treat as variable.
                return self.builder.variableExpr(loc, "LIST", null);
            },
            .kw_fn => {
                // FN user-defined function call: FN MyFunc(args)
                _ = self.advance();
                if (!self.check(.identifier)) {
                    try self.addError("Expected function name after FN");
                    return error.ParseError;
                }
                const fname = self.current().lexeme;
                _ = self.advance();

                _ = try self.consume(.lparen, "Expected '(' after FN function name");
                var args: std.ArrayList(ast.ExprPtr) = .empty;
                defer args.deinit(self.allocator);

                if (!self.check(.rparen)) {
                    try args.append(self.allocator, try self.parseExpression());
                    while (self.check(.comma)) {
                        _ = self.advance();
                        try args.append(self.allocator, try self.parseExpression());
                    }
                }
                _ = try self.consume(.rparen, "Expected ')' after FN arguments");

                return self.builder.expr(loc, .{ .function_call = .{
                    .name = fname,
                    .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                    .is_fn = true,
                } });
            },

            else => {
                // ── General keyword-as-identifier fallback ──────────
                // Many BASIC programs use variable names that collide
                // with keywords (e.g. `local`, `append`, `error`, `item`,
                // `color`, `circle`, `stop`, `timer`, etc.).  When a
                // keyword appears in expression context and is not one of
                // the specifically handled keywords above, treat it as
                // an identifier so that `local.GetID()`, `Append = expr`,
                // `circle.Area()`, etc. work.
                if (tok.isKeyword()) {
                    const kw_name = tok.lexeme;
                    _ = self.advance();

                    var type_suffix: ?Tag = null;
                    if (self.isTypeSuffix()) {
                        type_suffix = self.current().tag;
                        _ = self.advance();
                    }

                    // Function/array call: keyword(args...)
                    if (self.check(.lparen)) {
                        var is_function = self.isBuiltinFunction(kw_name);
                        if (!is_function) {
                            var buf3: [128]u8 = undefined;
                            const ulen3 = @min(kw_name.len, buf3.len);
                            for (0..ulen3) |i| buf3[i] = std.ascii.toUpper(kw_name[i]);
                            is_function = self.user_functions.contains(buf3[0..ulen3]) or
                                self.user_functions.contains(kw_name);
                        }

                        _ = self.advance(); // consume '('
                        var args: std.ArrayList(ast.ExprPtr) = .empty;
                        defer args.deinit(self.allocator);

                        if (!self.check(.rparen)) {
                            try args.append(self.allocator, try self.parseExpression());
                            while (self.check(.comma)) {
                                _ = self.advance();
                                try args.append(self.allocator, try self.parseExpression());
                            }
                        }
                        _ = try self.consume(.rparen, "Expected ')' after arguments");

                        if (is_function) {
                            return self.builder.expr(loc, .{ .function_call = .{
                                .name = kw_name,
                                .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
                            } });
                        } else {
                            return self.builder.expr(loc, .{ .array_access = .{
                                .name = kw_name,
                                .type_suffix = type_suffix,
                                .indices = try self.allocator.dupe(ast.ExprPtr, args.items),
                            } });
                        }
                    }

                    // Plain variable reference (e.g. `local`, `local.GetID()`)
                    return self.builder.variableExpr(loc, kw_name, type_suffix);
                }

                try self.addError("Unexpected token in expression");
                return error.ParseError;
            },
        }
    }

    /// Parse a CREATE expression: CREATE TypeName(args...) or CREATE TypeName(Field := value, ...)
    fn parseCreateExpression(self: *Parser) ExprError!ast.ExprPtr {
        const loc = self.currentLocation();
        _ = self.advance(); // consume CREATE

        if (!self.check(.identifier)) {
            try self.addError("Expected type name after CREATE");
            return error.ParseError;
        }
        const type_name = self.current().lexeme;
        _ = self.advance();

        _ = try self.consume(.lparen, "Expected '(' after CREATE type name");

        var args: std.ArrayList(ast.ExprPtr) = .empty;
        defer args.deinit(self.allocator);

        var field_names: std.ArrayList([]const u8) = .empty;
        defer field_names.deinit(self.allocator);

        var is_named = false;

        if (!self.check(.rparen)) {
            // Check for named-field syntax: Identifier := Expression
            // Lookahead: if current is IDENTIFIER and next is COLON and after that EQUAL,
            // then this is named syntax.
            if (self.check(.identifier) and
                self.pos + 1 < self.tokens.len and self.tokens[self.pos + 1].tag == .colon and
                self.pos + 2 < self.tokens.len and self.tokens[self.pos + 2].tag == .equal)
            {
                is_named = true;
            }

            if (is_named) {
                // Parse named fields: Field := value, ...
                while (!self.check(.rparen) and !self.isAtEnd()) {
                    if (!self.check(.identifier)) {
                        try self.addError("Expected field name in named CREATE");
                        return error.ParseError;
                    }
                    try field_names.append(self.allocator, self.current().lexeme);
                    _ = self.advance();

                    // Consume :=
                    _ = try self.consume(.colon, "Expected ':' in ':=' assignment");
                    _ = try self.consume(.equal, "Expected '=' in ':=' assignment");

                    try args.append(self.allocator, try self.parseExpression());

                    if (self.check(.comma)) {
                        _ = self.advance();
                    } else {
                        break;
                    }
                }
            } else {
                // Positional arguments.
                try args.append(self.allocator, try self.parseExpression());
                while (self.check(.comma)) {
                    _ = self.advance();
                    try args.append(self.allocator, try self.parseExpression());
                }
            }
        }

        _ = try self.consume(.rparen, "Expected ')' after CREATE arguments");

        return self.builder.expr(loc, .{ .create = .{
            .type_name = type_name,
            .arguments = try self.allocator.dupe(ast.ExprPtr, args.items),
            .is_named = is_named,
            .field_names = try self.allocator.dupe([]const u8, field_names.items),
        } });
    }

    // ═════════════════════════════════════════════════════════════════════
    // Helper: parameter list parsing
    // ═════════════════════════════════════════════════════════════════════

    const ParamResult = struct {
        names: []const []const u8,
        types: []const ?Tag,
        as_types: []const []const u8,
        is_byref: []bool,
    };

    fn parseParameterList(self: *Parser) ExprError!ParamResult {
        var names: std.ArrayList([]const u8) = .empty;
        defer names.deinit(self.allocator);
        var types: std.ArrayList(?Tag) = .empty;
        defer types.deinit(self.allocator);
        var as_types: std.ArrayList([]const u8) = .empty;
        defer as_types.deinit(self.allocator);
        var is_byref: std.ArrayList(bool) = .empty;
        defer is_byref.deinit(self.allocator);

        if (self.check(.lparen)) {
            _ = self.advance();

            while (!self.check(.rparen) and !self.isAtEnd()) {
                var byref = false;
                if (self.check(.kw_byref)) {
                    _ = self.advance();
                    byref = true;
                } else if (self.check(.kw_byval)) {
                    _ = self.advance();
                }

                if (!self.check(.identifier)) break;
                try names.append(self.allocator, self.current().lexeme);
                _ = self.advance();

                var type_suffix: ?Tag = null;
                if (self.isTypeSuffix()) {
                    type_suffix = self.current().tag;
                    _ = self.advance();
                }

                var as_type: []const u8 = "";
                if (self.check(.kw_as)) {
                    _ = self.advance();
                    if (self.isTypeKeyword() or self.check(.identifier)) {
                        as_type = self.current().lexeme;
                        if (type_suffix == null) {
                            type_suffix = self.current().tag;
                        }
                        _ = self.advance();
                    }
                }

                try types.append(self.allocator, type_suffix);
                try as_types.append(self.allocator, as_type);
                try is_byref.append(self.allocator, byref);

                if (self.check(.comma)) {
                    _ = self.advance();
                } else {
                    break;
                }
            }

            if (self.check(.rparen)) _ = self.advance();
        }

        return .{
            .names = try self.allocator.dupe([]const u8, names.items),
            .types = try self.allocator.dupe(?Tag, types.items),
            .as_types = try self.allocator.dupe([]const u8, as_types.items),
            .is_byref = try self.allocator.dupe(bool, is_byref.items),
        };
    }

    // ═════════════════════════════════════════════════════════════════════
    // Token stream helpers
    // ═════════════════════════════════════════════════════════════════════

    fn current(self: *const Parser) Token {
        if (self.pos >= self.tokens.len) {
            return .{ .tag = .end_of_file };
        }
        return self.tokens[self.pos];
    }

    fn currentLocation(self: *const Parser) SourceLocation {
        return self.current().location;
    }

    fn peek(self: *const Parser, offset: usize) Token {
        const idx = self.pos + offset;
        if (idx >= self.tokens.len) return .{ .tag = .end_of_file };
        return self.tokens[idx];
    }

    fn isAtEnd(self: *const Parser) bool {
        return self.pos >= self.tokens.len or self.current().tag == .end_of_file;
    }

    fn advance(self: *Parser) Token {
        const tok = self.current();
        if (self.pos < self.tokens.len) {
            self.pos += 1;
        }
        return tok;
    }

    fn check(self: *const Parser, tag: Tag) bool {
        return self.current().tag == tag;
    }

    fn consume(self: *Parser, tag: Tag, error_msg: []const u8) ExprError!Token {
        if (self.check(tag)) {
            return self.advance();
        }
        try self.addError(error_msg);
        return error.ParseError;
    }

    fn isAtEndOfStatement(self: *const Parser) bool {
        return self.current().isEndOfStatement() or self.isAtEnd();
    }

    fn skipToEndOfLine(self: *Parser) void {
        while (!self.isAtEnd() and !self.check(.end_of_line) and !self.check(.end_of_file)) {
            _ = self.advance();
        }
        if (self.check(.end_of_line)) _ = self.advance();
    }

    fn skipBlankLines(self: *Parser) void {
        while (self.check(.end_of_line)) {
            _ = self.advance();
        }
    }

    /// Returns true if the current token is a compound END token that closes
    /// a scope (e.g. .kw_endsub, .kw_endfunction, .kw_endif, .kw_endcase,
    /// .kw_endtype, .kw_endmatch).  These should never be consumed by
    /// parseProgramLine — they belong to the enclosing construct's parser.
    fn isScopeClosingToken(self: *Parser) bool {
        const tag = self.current().tag;
        return tag == .kw_endsub or
            tag == .kw_endfunction or
            tag == .kw_endif or
            tag == .kw_endcase or
            tag == .kw_endtype or
            tag == .kw_endmatch;
    }

    /// Returns true if the current identifier-starting token is followed by
    /// `.` and then something that looks like a method call (keyword or
    /// identifier, possibly followed by `(`).  Used to distinguish
    /// `d.CLEAR()` (method call statement) from `d = expr` (assignment).
    fn isMethodCallStatement(self: *Parser) bool {
        // Walk ahead from current position, scanning through ALL chained
        // dot-members (e.g. obj.inner.field or obj.inner.method()) to
        // reach the FINAL token after the last dotted name.  Only then
        // decide: if '(' follows → method call; if '=' follows → assignment.
        //
        // This prevents multi-dot member assignments like O.I.V = 99 from
        // being misclassified as method calls (the old code only looked one
        // dot deep and treated the second dot as "end of statement").
        var p = self.pos;
        if (p >= self.tokens.len) return false;

        // Skip past the leading identifier or ME keyword.
        if (self.tokens[p].tag != .identifier and self.tokens[p].tag != .kw_me) return false;
        p += 1;

        // Skip optional type suffix.
        if (p < self.tokens.len and self.tokens[p].isTypeSuffix()) p += 1;

        // Skip optional parenthesized index (e.g., arr(0).method()).
        if (p < self.tokens.len and self.tokens[p].tag == .lparen) {
            var depth: u32 = 1;
            p += 1;
            while (p < self.tokens.len and depth > 0) {
                if (self.tokens[p].tag == .lparen) depth += 1;
                if (self.tokens[p].tag == .rparen) depth -= 1;
                p += 1;
            }
        }

        // Now walk through ALL chained dot-members:
        //   .name [suffix] [(...)] .name [suffix] [(...)] ...
        // After this loop, p points to the token AFTER the final member name.
        while (true) {
            // Expect '.'
            if (p >= self.tokens.len or self.tokens[p].tag != .dot) return false;
            p += 1;

            // After '.', expect identifier or keyword (member/method name).
            if (p >= self.tokens.len) return false;
            if (self.tokens[p].tag != .identifier and !self.tokens[p].isKeyword()) return false;
            p += 1;

            // Skip optional type suffix after member name.
            if (p < self.tokens.len and self.tokens[p].isTypeSuffix()) p += 1;

            // Skip optional parenthesized arguments (e.g., .method(args)).
            if (p < self.tokens.len and self.tokens[p].tag == .lparen) {
                var depth: u32 = 1;
                p += 1;
                while (p < self.tokens.len and depth > 0) {
                    if (self.tokens[p].tag == .lparen) depth += 1;
                    if (self.tokens[p].tag == .rparen) depth -= 1;
                    p += 1;
                }
            }

            // If the next token is another '.', continue scanning the chain.
            // Otherwise break out and inspect what follows the final member.
            if (p < self.tokens.len and self.tokens[p].tag == .dot) {
                continue;
            }
            break;
        }

        // p is now past the final member name (and any suffix / parens).
        // If '(' follows → it's a method call (the final member has args).
        // Note: we already consumed parens above when they were present, so
        // if we reach here the final member did NOT have parens.  Check if
        // the token at the saved position (before any paren skip) was '('.
        // Actually, if the final member already had parens we consumed them,
        // so by definition it was a method call.  But the loop consumed them
        // and advanced p past them — let's check what's at p now.

        // If '(' is here, it means there's a call at the end we didn't
        // consume (shouldn't happen given the loop above, but be safe).
        if (p < self.tokens.len and self.tokens[p].tag == .lparen) return true;

        // If '=' follows → this is an assignment (e.g. O.I.V = 99), NOT a
        // method call.
        if (p < self.tokens.len and self.tokens[p].tag == .equal) return false;

        // Check: did the final member in the chain have parenthesized args?
        // If so, it was a method call like obj.method() — we already consumed
        // the parens in the loop.  Detect this by checking whether the token
        // just before p is ')'.
        if (p >= 2 and self.tokens[p - 1].tag == .rparen) return true;

        // At end of statement (newline/colon/eof) with no parens and no '='
        // — could be a void method call without parens.  Only treat as method
        // call if there was exactly one dot-member (no nested chain), since
        // multi-level chains without parens are field accesses, not calls.
        // However, being conservative: return false to let the caller parse
        // it as an assignment/expression, which is safer.
        return false;
    }

    fn isTypeSuffix(self: *Parser) bool {
        return self.current().isTypeSuffix();
    }

    fn skipTypeSuffix(self: *Parser) void {
        if (self.isTypeSuffix()) {
            _ = self.advance();
        }
    }

    fn isTypeKeyword(self: *const Parser) bool {
        return self.current().isTypeKeyword();
    }

    fn isBuiltinFunction(self: *const Parser, name: []const u8) bool {
        _ = self;
        // A subset of known built-in functions (case-insensitive comparison).
        const builtins = [_][]const u8{
            "ABS",  "SGN",   "SQR",    "INT",   "FIX",   "CINT",
            "CLNG", "CDBL",  "CSNG",   "SIN",   "COS",   "TAN",
            "ATN",  "LOG",   "EXP",    "RND",   "VAL",   "STR",
            "CHR",  "ASC",   "LEN",    "INSTR", "UCASE", "LCASE",
            "TRIM", "LTRIM", "RTRIM",  "SPACE", "TAB",   "HEX",
            "OCT",  "BIN",   "MID",    "LEFT",  "RIGHT", "TIMER",
            "PEEK", "POKE",  "STRING", "INKEY", "POINT",
        };

        // Strip trailing type suffix ($, %, !, #, &, @, ^) before
        // comparison so that e.g. "LEFT$" matches builtin "LEFT".
        var base_name = name;
        if (base_name.len > 0) {
            const last = base_name[base_name.len - 1];
            if (last == '$' or last == '%' or last == '!' or last == '#' or
                last == '&' or last == '@' or last == '^')
            {
                base_name = base_name[0 .. base_name.len - 1];
            }
        }

        for (builtins) |builtin| {
            if (std.ascii.eqlIgnoreCase(base_name, builtin)) return true;
        }
        return false;
    }

    // ── Error reporting ─────────────────────────────────────────────────

    fn addError(self: *Parser, message: []const u8) ExprError!void {
        try self.errors.append(self.allocator, .{
            .message = message,
            .location = self.currentLocation(),
        });
    }
};

// ═════════════════════════════════════════════════════════════════════════════
// Tests
// ═════════════════════════════════════════════════════════════════════════════

fn tokenize(source: []const u8, allocator: std.mem.Allocator) ![]const Token {
    var lex = lexer_mod.Lexer.init(source, allocator);
    defer lex.deinit();
    try lex.tokenize();
    return allocator.dupe(Token, lex.tokens.items);
}

test "parse empty program" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();
    _ = program;
    try std.testing.expect(!parser.hasErrors());
}

test "parse PRINT statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT \"Hello\"", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    try std.testing.expect(program.lines.len >= 1);
    try std.testing.expect(program.lines[0].statements.len >= 1);

    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .print);
}

test "parse END statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("END", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    try std.testing.expect(program.lines.len >= 1);
    try std.testing.expect(program.lines[0].statements.len >= 1);

    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .end_stmt);
}

test "parse multi-line program" {
    const source =
        \\PRINT "Hello"
        \\DIM x AS INTEGER
        \\x = 42
        \\END
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    try std.testing.expect(program.lines.len >= 4);
}

test "parse arithmetic expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT 1 + 2 * 3", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .print);

    // The expression should have proper precedence: 1 + (2 * 3)
    const print_data = stmt.data.print;
    try std.testing.expectEqual(@as(usize, 1), print_data.items.len);
    const expr = print_data.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .binary);
    try std.testing.expectEqual(Tag.plus, expr.data.binary.op);
}

test "parse FOR loop" {
    const source =
        \\FOR i = 1 TO 10
        \\  PRINT i
        \\NEXT i
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    // The FOR loop should be in the first line's statements.
    const first_stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(first_stmt.data), .for_stmt);
    try std.testing.expectEqualStrings("i", first_stmt.data.for_stmt.variable);
}

test "parse IF statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("IF x > 10 THEN PRINT x", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .if_stmt);
}

test "parse DIM statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("DIM x AS INTEGER", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .dim);
    try std.testing.expectEqual(@as(usize, 1), stmt.data.dim.arrays.len);
    try std.testing.expectEqualStrings("x", stmt.data.dim.arrays[0].name);
    try std.testing.expect(stmt.data.dim.arrays[0].has_as_type);
}

test "parse TYPE declaration" {
    const source =
        \\TYPE Point
        \\  x AS DOUBLE
        \\  y AS DOUBLE
        \\END TYPE
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .type_decl);
    try std.testing.expectEqualStrings("Point", stmt.data.type_decl.type_name);
    try std.testing.expectEqual(@as(usize, 2), stmt.data.type_decl.fields.len);
}

test "parse FUNCTION definition" {
    const source =
        \\FUNCTION Add(a AS INTEGER, b AS INTEGER) AS INTEGER
        \\  RETURN a + b
        \\END FUNCTION
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    // Find the FUNCTION statement.
    var found_func = false;
    for (program.lines) |line| {
        for (line.statements) |stmt| {
            if (std.meta.activeTag(stmt.data) == .function) {
                found_func = true;
                try std.testing.expectEqualStrings("Add", stmt.data.function.function_name);
                try std.testing.expectEqual(@as(usize, 2), stmt.data.function.parameters.len);
            }
        }
    }
    try std.testing.expect(found_func);
}

test "parse CREATE expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT CREATE Point(1.0, 2.0)", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    const expr = stmt.data.print.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .create);
    try std.testing.expectEqualStrings("Point", expr.data.create.type_name);
    try std.testing.expect(!expr.data.create.is_named);
    try std.testing.expectEqual(@as(usize, 2), expr.data.create.arguments.len);
}

test "parse named CREATE expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT CREATE Point(x := 1.0, y := 2.0)", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    const expr = stmt.data.print.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .create);
    try std.testing.expect(expr.data.create.is_named);
    try std.testing.expectEqual(@as(usize, 2), expr.data.create.field_names.len);
    try std.testing.expectEqualStrings("x", expr.data.create.field_names[0]);
    try std.testing.expectEqualStrings("y", expr.data.create.field_names[1]);
}

test "parse WHILE loop" {
    const source =
        \\WHILE x > 0
        \\  DEC x
        \\WEND
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .while_stmt);
    try std.testing.expect(stmt.data.while_stmt.body.len > 0);
}

test "parse CONSTANT" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("CONSTANT PI = 3.14159", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .constant);
    try std.testing.expectEqualStrings("PI", stmt.data.constant.name);
}

test "parse implicit assignment" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("x = 42", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .let);
    try std.testing.expectEqualStrings("x", stmt.data.let.variable);
}

test "parse label definition" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("myLabel:\nPRINT \"at label\"", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .label);
    try std.testing.expectEqualStrings("myLabel", stmt.data.label.label_name);
}

test "parse OPTION statement" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("OPTION BASE 0", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .option);
    try std.testing.expectEqual(ast.OptionStmt.OptionType.base, stmt.data.option.option_type);
    try std.testing.expectEqual(@as(i32, 0), stmt.data.option.value);
}

test "parse operator precedence" {
    // 2 + 3 * 4 should be parsed as 2 + (3 * 4)
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT 2 + 3 * 4", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const expr = program.lines[0].statements[0].data.print.items[0].expr;

    // Top level should be +
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .binary);
    try std.testing.expectEqual(Tag.plus, expr.data.binary.op);

    // Right side should be *
    const right = expr.data.binary.right;
    try std.testing.expectEqual(std.meta.activeTag(right.data), .binary);
    try std.testing.expectEqual(Tag.multiply, right.data.binary.op);
}

test "parse parenthesized expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT (2 + 3) * 4", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const expr = program.lines[0].statements[0].data.print.items[0].expr;

    // Top level should be *
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .binary);
    try std.testing.expectEqual(Tag.multiply, expr.data.binary.op);

    // Left side should be +
    const left = expr.data.binary.left;
    try std.testing.expectEqual(std.meta.activeTag(left.data), .binary);
    try std.testing.expectEqual(Tag.plus, left.data.binary.op);
}

test "parse unary minus" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT -42", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const expr = program.lines[0].statements[0].data.print.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .unary);
    try std.testing.expectEqual(Tag.minus, expr.data.unary.op);
}

test "parse IIF expression" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT IIF(x > 0, 1, 0)", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const expr = program.lines[0].statements[0].data.print.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .iif);
}

test "parse DO WHILE loop" {
    const source =
        \\DO WHILE x > 0
        \\  DEC x
        \\LOOP
    ;
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize(source, alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const stmt = program.lines[0].statements[0];
    try std.testing.expectEqual(std.meta.activeTag(stmt.data), .do_stmt);
    try std.testing.expectEqual(ast.DoStmt.ConditionType.while_cond, stmt.data.do_stmt.pre_condition_type);
    try std.testing.expect(stmt.data.do_stmt.pre_condition != null);
}

test "error recovery" {
    // Missing THEN — should produce error but continue.
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("IF x > 10\nPRINT x\nENDIF", alloc);
    var parser = Parser.init(tokens, alloc);
    _ = parser.parse() catch {};

    try std.testing.expect(parser.hasErrors());
}

test "parse member access" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();
    const tokens = try tokenize("PRINT point.x", alloc);
    var parser = Parser.init(tokens, alloc);
    const program = try parser.parse();

    try std.testing.expect(!parser.hasErrors());
    const expr = program.lines[0].statements[0].data.print.items[0].expr;
    try std.testing.expectEqual(std.meta.activeTag(expr.data), .member_access);
    try std.testing.expectEqualStrings("x", expr.data.member_access.member_name);
}
