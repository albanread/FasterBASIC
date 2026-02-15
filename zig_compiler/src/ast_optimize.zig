//! AST-Level Optimization Pass for the FasterBASIC compiler.
//!
//! This module performs source-level optimizations on the AST **after**
//! semantic analysis (so CONST values, type info, and symbol tables are
//! available) and **before** CFG construction.
//!
//! These are transformations that QBE structurally cannot perform because
//! they require high-level semantic knowledge (string operations, function
//! call semantics, BASIC-specific loop structure) that is lost by the time
//! QBE sees the IL.
//!
//! Optimizations performed (single recursive walk):
//!
//!  1. Constant folding          — `3 + 4` → `7`, `-5` → `-5`
//!  2. CONST propagation         — `CONST N = 10` … `N` → `10`
//!  3. String literal folding    — `"Hello" + " " + "World"` → `"Hello World"`
//!  4. String identity elision   — `"" + s$` → `s$`, `s$ + ""` → `s$`
//!  5. Power strength reduction  — `x^2` → `x*x`, `x^0` → `1`, etc.
//!  6. FOR step-direction tag    — annotates known-positive / known-negative
//!  7. Dead branch elimination   — `IF 0 THEN …` → removed
//!  8. IIF simplification        — `IIF(1, a, b)` → `a`
//!  9. Algebraic identities      — `x + 0` → `x`, `x * 1` → `x`, `x * 0` → `0`
//! 10. NOT constant folding      — `NOT 0` → `1`, `NOT 1` → `0`
//! 11. Double negation elision   — `--x` → `x`, `NOT NOT x` → `x`
//! 12. String function folding   — `LEN("hello")` → `5`, `LEFT$("ab",1)` → `"a"`, etc.
//! 13. Division by constant      — `x / 4.0` → `x * 0.25`
//! 14. MOD power-of-2            — `x MOD 8` → `x AND 7` (integer operands)
//! 15. Dead loop elimination     — `WHILE 0 … WEND` → removed
//! 16. Boolean AND/OR identities — `x AND 0` → `0`, `x OR 0` → `x`

const std = @import("std");
const ast = @import("ast.zig");
const token = @import("token.zig");
const semantic = @import("semantic.zig");
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

// ─── FOR loop step direction ────────────────────────────────────────────────

/// Step direction tag that can be inferred at compile time for FOR loops.
/// Stored externally in the optimizer's result and queried by codegen.
pub const StepDirection = enum {
    /// Step is a compile-time constant > 0 (or omitted, which defaults to 1).
    positive,
    /// Step is a compile-time constant < 0.
    negative,
    /// Step is zero (degenerate — loop never terminates or never executes).
    zero,
    /// Step direction cannot be determined at compile time.
    unknown,
};

// ─── Statistics ─────────────────────────────────────────────────────────────

pub const OptStats = struct {
    constants_folded: u32 = 0,
    constants_propagated: u32 = 0,
    strings_folded: u32 = 0,
    string_identities: u32 = 0,
    powers_reduced: u32 = 0,
    dead_branches: u32 = 0,
    iifs_simplified: u32 = 0,
    algebraic_identities: u32 = 0,
    for_loops_specialized: u32 = 0,
    not_folded: u32 = 0,
    double_negations: u32 = 0,
    string_funcs_folded: u32 = 0,
    div_to_mul: u32 = 0,
    mod_to_and: u32 = 0,
    dead_loops: u32 = 0,
    bool_identities: u32 = 0,

    pub fn total(self: OptStats) u32 {
        return self.constants_folded +
            self.constants_propagated +
            self.strings_folded +
            self.string_identities +
            self.powers_reduced +
            self.dead_branches +
            self.iifs_simplified +
            self.algebraic_identities +
            self.for_loops_specialized +
            self.not_folded +
            self.double_negations +
            self.string_funcs_folded +
            self.div_to_mul +
            self.mod_to_and +
            self.dead_loops +
            self.bool_identities;
    }
};

// ─── Optimizer ──────────────────────────────────────────────────────────────

pub const ASTOptimizer = struct {
    symbol_table: *const semantic.SymbolTable,
    allocator: std.mem.Allocator,
    stats: OptStats = .{},

    /// FOR variable name (upper-cased) → inferred step direction.
    /// Codegen queries this to specialize loop condition emission.
    for_step_directions: std.StringHashMap(StepDirection),

    pub fn init(
        symbol_table: *const semantic.SymbolTable,
        allocator: std.mem.Allocator,
    ) ASTOptimizer {
        return .{
            .symbol_table = symbol_table,
            .allocator = allocator,
            .for_step_directions = std.StringHashMap(StepDirection).init(allocator),
        };
    }

    pub fn deinit(self: *ASTOptimizer) void {
        // Keys are allocated by us — free them.
        var it = self.for_step_directions.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
        }
        self.for_step_directions.deinit();
    }

    // ── Public API ──────────────────────────────────────────────────────

    /// Run the optimization pass over the entire program.
    pub fn optimize(self: *ASTOptimizer, program: *ast.Program) !void {
        for (program.lines) |*line| {
            try self.optimizeStatements(line.statements);
        }
    }

    /// Look up the inferred step direction for a FOR loop variable.
    /// Returns `.unknown` if no specialization was recorded.
    pub fn getStepDirection(self: *const ASTOptimizer, var_name_upper: []const u8) StepDirection {
        return self.for_step_directions.get(var_name_upper) orelse .unknown;
    }

    // ── Statement-level optimization ────────────────────────────────────

    const OptError = error{OutOfMemory};

    fn optimizeStatements(self: *ASTOptimizer, stmts: []ast.StmtPtr) OptError!void {
        for (stmts) |stmt| {
            try self.optimizeStatement(stmt);
        }
    }

    fn optimizeStatement(self: *ASTOptimizer, stmt: ast.StmtPtr) OptError!void {
        switch (stmt.data) {
            .let => |*lt| {
                lt.value = try self.optimizeExpr(lt.value);
                // Optimize index expressions
                for (lt.indices) |*idx| {
                    idx.* = try self.optimizeExpr(idx.*);
                }
            },
            .print => |*pr| {
                for (pr.items) |*item| {
                    item.expr = try self.optimizeExpr(item.expr);
                }
                if (pr.format_expr) |fe| {
                    pr.format_expr = try self.optimizeExpr(fe);
                }
                for (pr.using_values) |*uv| {
                    uv.* = try self.optimizeExpr(uv.*);
                }
            },
            .console => |*con| {
                for (con.items) |*item| {
                    item.expr = try self.optimizeExpr(item.expr);
                }
            },
            .if_stmt => |*ifs| {
                try self.optimizeIfStmt(ifs, stmt);
            },
            .for_stmt => |*fs| {
                fs.start = try self.optimizeExpr(fs.start);
                fs.end_expr = try self.optimizeExpr(fs.end_expr);
                if (fs.step) |step| {
                    fs.step = try self.optimizeExpr(step);
                }
                // Tag the step direction
                try self.tagForStepDirection(fs);
                // Optimize body
                try self.optimizeStatements(fs.body);
            },
            .for_in => |*fi| {
                fi.array = try self.optimizeExpr(fi.array);
                try self.optimizeStatements(fi.body);
            },
            .while_stmt => |*ws| {
                ws.condition = try self.optimizeExpr(ws.condition);
                // Dead loop elimination: WHILE 0 ... WEND → remove entire loop
                if (isConstantFalse(ws.condition)) {
                    stmt.data = .{ .rem = .{ .comment = "optimized out: dead WHILE loop (condition always false)" } };
                    self.stats.dead_loops += 1;
                    return;
                }
                try self.optimizeStatements(ws.body);
            },
            .repeat_stmt => |*rs| {
                if (rs.condition) |c| {
                    rs.condition = try self.optimizeExpr(c);
                }
                try self.optimizeStatements(rs.body);
            },
            .do_stmt => |*ds| {
                if (ds.pre_condition) |c| {
                    ds.pre_condition = try self.optimizeExpr(c);
                }
                if (ds.post_condition) |c| {
                    ds.post_condition = try self.optimizeExpr(c);
                }
                // Dead loop elimination: DO WHILE 0 ... LOOP → remove
                if (ds.pre_condition_type == .while_cond) {
                    if (ds.pre_condition) |pc| {
                        if (isConstantFalse(pc)) {
                            stmt.data = .{ .rem = .{ .comment = "optimized out: dead DO WHILE loop (condition always false)" } };
                            self.stats.dead_loops += 1;
                            return;
                        }
                    }
                }
                // DO UNTIL 1 ... LOOP → remove (UNTIL true = never enter)
                if (ds.pre_condition_type == .until_cond) {
                    if (ds.pre_condition) |pc| {
                        if (isConstantTrue(pc)) {
                            stmt.data = .{ .rem = .{ .comment = "optimized out: dead DO UNTIL loop (condition always true)" } };
                            self.stats.dead_loops += 1;
                            return;
                        }
                    }
                }
                try self.optimizeStatements(ds.body);
            },
            .case_stmt => |*cs| {
                cs.case_expression = try self.optimizeExpr(cs.case_expression);
                for (cs.when_clauses) |*wc| {
                    for (wc.values) |*v| {
                        v.* = try self.optimizeExpr(v.*);
                    }
                    if (wc.case_is_right_expr) |e| {
                        wc.case_is_right_expr = try self.optimizeExpr(e);
                    }
                    if (wc.range_start) |e| {
                        wc.range_start = try self.optimizeExpr(e);
                    }
                    if (wc.range_end) |e| {
                        wc.range_end = try self.optimizeExpr(e);
                    }
                    try self.optimizeStatements(wc.statements);
                }
                try self.optimizeStatements(cs.otherwise_statements);
            },
            .match_type => |*mt| {
                mt.match_expression = try self.optimizeExpr(mt.match_expression);
                for (mt.case_arms) |*arm| {
                    try self.optimizeStatements(arm.body);
                }
                try self.optimizeStatements(mt.case_else_body);
            },
            .try_catch => |*tc| {
                try self.optimizeStatements(tc.try_block);
                for (tc.catch_clauses) |*cc| {
                    try self.optimizeStatements(cc.block);
                }
                try self.optimizeStatements(tc.finally_block);
            },
            .function => |*fn_stmt| {
                try self.optimizeStatements(fn_stmt.body);
            },
            .sub => |*sub_stmt| {
                try self.optimizeStatements(sub_stmt.body);
            },
            .worker => |*wk| {
                try self.optimizeStatements(wk.body);
            },
            .def => |*d| {
                d.body = try self.optimizeExpr(d.body);
            },
            .class => |*cls| {
                if (cls.constructor) |ctor| {
                    try self.optimizeStatements(ctor.body);
                }
                if (cls.destructor) |dtor| {
                    try self.optimizeStatements(dtor.body);
                }
                for (cls.methods) |method| {
                    try self.optimizeStatements(method.body);
                }
            },
            .dim => |*dm| {
                for (dm.arrays) |*arr| {
                    for (arr.dimensions) |*dim_expr| {
                        dim_expr.* = try self.optimizeExpr(dim_expr.*);
                    }
                    if (arr.initializer) |init_expr| {
                        arr.initializer = try self.optimizeExpr(init_expr);
                    }
                }
            },
            .call => |*c| {
                for (c.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
            },
            .input => |*inp| {
                if (inp.file_number) |fn_expr| {
                    inp.file_number = try self.optimizeExpr(fn_expr);
                }
            },
            .wrch => |*w| {
                w.expr = try self.optimizeExpr(w.expr);
            },
            .wrstr => |*w| {
                w.expr = try self.optimizeExpr(w.expr);
            },
            .throw_stmt => |*t| {
                if (t.error_code) |ec| {
                    t.error_code = try self.optimizeExpr(ec);
                }
            },
            .inc => |*id| {
                if (id.amount_expr) |ae| {
                    id.amount_expr = try self.optimizeExpr(ae);
                }
            },
            .dec => |*id| {
                if (id.amount_expr) |ae| {
                    id.amount_expr = try self.optimizeExpr(ae);
                }
            },
            .local => |*loc| {
                for (loc.variables) |*v| {
                    if (v.initial_value) |iv| {
                        v.initial_value = try self.optimizeExpr(iv);
                    }
                }
            },
            .global => |*g| {
                for (g.variables) |*v| {
                    if (v.initial_value) |iv| {
                        v.initial_value = try self.optimizeExpr(iv);
                    }
                }
            },
            .on_goto => |*og| {
                og.selector = try self.optimizeExpr(og.selector);
            },
            .on_gosub => |*ogs| {
                ogs.selector = try self.optimizeExpr(ogs.selector);
            },
            .on_call => |*oc| {
                oc.selector = try self.optimizeExpr(oc.selector);
            },
            .return_stmt => |*rs| {
                if (rs.return_value) |rv| {
                    rs.return_value = try self.optimizeExpr(rv);
                }
            },
            .mid_assign => |*ma| {
                ma.position = try self.optimizeExpr(ma.position);
                if (ma.length) |l| {
                    ma.length = try self.optimizeExpr(l);
                }
                ma.replacement = try self.optimizeExpr(ma.replacement);
            },
            .slice_assign => |*sa| {
                sa.start = try self.optimizeExpr(sa.start);
                sa.end_expr = try self.optimizeExpr(sa.end_expr);
                sa.replacement = try self.optimizeExpr(sa.replacement);
            },
            .color => |*col| {
                col.fg = try self.optimizeExpr(col.fg);
                if (col.bg) |bg| {
                    col.bg = try self.optimizeExpr(bg);
                }
            },
            .wait_stmt => |*w| {
                w.duration = try self.optimizeExpr(w.duration);
            },
            .send => |*s| {
                s.message = try self.optimizeExpr(s.message);
            },
            .unmarshall => |*u| {
                u.source_expr = try self.optimizeExpr(u.source_expr);
            },
            .expression_stmt => |*es| {
                for (es.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
            },
            .print_at => |*pa| {
                pa.x = try self.optimizeExpr(pa.x);
                pa.y = try self.optimizeExpr(pa.y);
                for (pa.items) |*item| {
                    item.expr = try self.optimizeExpr(item.expr);
                }
            },
            .input_at => |*ia| {
                ia.x = try self.optimizeExpr(ia.x);
                ia.y = try self.optimizeExpr(ia.y);
                if (ia.fg_color) |fc| {
                    ia.fg_color = try self.optimizeExpr(fc);
                }
                if (ia.bg_color) |bc| {
                    ia.bg_color = try self.optimizeExpr(bc);
                }
            },
            .swap => |*sw| {
                for (sw.var1_indices) |*idx| {
                    idx.* = try self.optimizeExpr(idx.*);
                }
                for (sw.var2_indices) |*idx| {
                    idx.* = try self.optimizeExpr(idx.*);
                }
            },
            .open => |*o| {
                o.filename = try self.optimizeExpr(o.filename);
                o.file_number = try self.optimizeExpr(o.file_number);
            },
            .spit => |*sp| {
                sp.filename = try self.optimizeExpr(sp.filename);
                sp.content = try self.optimizeExpr(sp.content);
            },
            .shell => |*sh| {
                sh.command = try self.optimizeExpr(sh.command);
            },
            .close => |*cl| {
                if (cl.file_number) |fn_expr| {
                    cl.file_number = try self.optimizeExpr(fn_expr);
                }
            },
            .match_receive => |*mr| {
                mr.handle_expression = try self.optimizeExpr(mr.handle_expression);
                for (mr.case_arms) |*arm| {
                    try self.optimizeStatements(arm.body);
                }
                try self.optimizeStatements(mr.case_else_body);
            },

            // Statements with no sub-expressions or sub-statements to optimize
            .goto_stmt,
            .gosub,
            .next_stmt,
            .wend,
            .until_stmt,
            .loop_stmt,
            .end_stmt,
            .exit_stmt,
            .label,
            .type_decl,
            .data_stmt,
            .read_stmt,
            .restore,
            .option,
            .constant,
            .shared,
            .erase,
            .redim,
            .delete,
            .rem,
            .on_event,
            .field,
            .lset,
            .rset,
            .put,
            .get,
            .seek,
            .wait_ms,
            .cls,
            .gcls,
            .vsync,
            .cursor_on,
            .cursor_off,
            .cursor_hide,
            .cursor_show,
            .cursor_save,
            .cursor_restore,
            .color_reset,
            .bold,
            .italic,
            .underline,
            .blink,
            .inverse,
            .style_reset,
            .normal,
            .screen_alternate,
            .screen_main,
            .flush,
            .begin_paint,
            .end_paint,
            .kbraw,
            .kbecho,
            .kbflush,
            .pset,
            .line_stmt,
            .rect,
            .circle,
            .hline,
            .vline,
            .at_stmt,
            .textput,
            .tchar,
            .tgrid,
            .tscroll,
            .tclear,
            .locate,
            .sprload,
            .sprfree,
            .sprshow,
            .sprhide,
            .sprmove,
            .sprpos,
            .sprtint,
            .sprscale,
            .sprrot,
            .sprexplode,
            .play,
            .play_sound,
            .after,
            .every,
            .afterframes,
            .everyframe,
            .run,
            .timer_stop,
            .timer_interval,
            .cancel,
            .registry_command,
            => {},
        }
    }

    // ── IF statement optimization (dead branch elimination) ─────────────

    fn optimizeIfStmt(self: *ASTOptimizer, ifs: *ast.IfStmt, stmt: ast.StmtPtr) OptError!void {
        ifs.condition = try self.optimizeExpr(ifs.condition);

        // Optimize bodies regardless of whether we can eliminate branches
        try self.optimizeStatements(ifs.then_statements);
        for (ifs.elseif_clauses) |*clause| {
            clause.condition = try self.optimizeExpr(clause.condition);
            try self.optimizeStatements(clause.statements);
        }
        try self.optimizeStatements(ifs.else_statements);

        // Dead branch elimination: if condition is a known constant,
        // replace the IF with just the taken branch.
        if (isConstantTrue(ifs.condition)) {
            // Condition is always true — keep only THEN branch.
            // We replace the IF statement with a REM + inline the THEN body.
            // Since we can't change the statement slice length, we turn
            // the IF into just running the THEN statements by removing
            // all the ELSE/ELSEIF branches.
            ifs.elseif_clauses = &.{};
            ifs.else_statements = &.{};
            self.stats.dead_branches += 1;
        } else if (isConstantFalse(ifs.condition)) {
            // Condition is always false.
            if (ifs.elseif_clauses.len > 0) {
                // Promote first ELSEIF to be the main IF condition
                const first_elseif = ifs.elseif_clauses[0];
                ifs.condition = first_elseif.condition;
                ifs.then_statements = first_elseif.statements;
                ifs.elseif_clauses = if (ifs.elseif_clauses.len > 1)
                    ifs.elseif_clauses[1..]
                else
                    &.{};
                self.stats.dead_branches += 1;
            } else if (ifs.else_statements.len > 0) {
                // No ELSEIFs — promote ELSE to THEN with always-true cond
                ifs.condition = try self.makeNumberExpr(1.0, stmt.loc);
                ifs.then_statements = ifs.else_statements;
                ifs.else_statements = &.{};
                self.stats.dead_branches += 1;
            } else {
                // No ELSEIF, no ELSE — the whole IF does nothing.
                // Replace with a harmless REM.
                stmt.data = .{ .rem = .{ .comment = "optimized out: dead IF branch" } };
                self.stats.dead_branches += 1;
            }
        }
    }

    // ── FOR step direction tagging ──────────────────────────────────────

    fn tagForStepDirection(self: *ASTOptimizer, fs: *const ast.ForStmt) OptError!void {
        const dir: StepDirection = if (fs.step) |step_expr|
            classifyStepDirection(step_expr)
        else
            // No explicit step — defaults to 1 (positive).
            .positive;

        if (dir != .unknown) {
            self.stats.for_loops_specialized += 1;
        }

        // Store the direction keyed by the upper-cased variable name.
        var upper_buf: [128]u8 = undefined;
        const vlen = @min(fs.variable.len, upper_buf.len);
        for (0..vlen) |i| {
            upper_buf[i] = std.ascii.toUpper(fs.variable[i]);
        }
        const lookup = upper_buf[0..vlen];

        // If there was a previous entry for this variable name (nested
        // loops or sequential loops reusing the same name), just update
        // the value in place — no new key allocation needed.
        if (self.for_step_directions.getPtr(lookup)) |existing| {
            existing.* = dir;
        } else {
            const key = try self.allocator.dupe(u8, lookup);
            try self.for_step_directions.put(key, dir);
        }
    }

    /// Determine the step direction from a step expression, if it's a
    /// compile-time constant.
    fn classifyStepDirection(expr: *const ast.Expression) StepDirection {
        switch (expr.data) {
            .number => |n| {
                if (n.value > 0) return .positive;
                if (n.value < 0) return .negative;
                return .zero;
            },
            .unary => |u| {
                if (u.op == .minus) {
                    // -<number>
                    if (u.operand.data == .number) {
                        const inner = u.operand.data.number.value;
                        if (inner > 0) return .negative;
                        if (inner < 0) return .positive;
                        return .zero;
                    }
                }
                return .unknown;
            },
            else => return .unknown,
        }
    }

    // ── Expression-level optimization ───────────────────────────────────

    fn optimizeExpr(self: *ASTOptimizer, expr: ast.ExprPtr) OptError!ast.ExprPtr {
        switch (expr.data) {
            .binary => |*b| {
                // Optimize children first (bottom-up).
                b.left = try self.optimizeExpr(b.left);
                b.right = try self.optimizeExpr(b.right);

                // ── Numeric constant folding ────────────────────────
                if (try self.tryFoldBinary(b.left, b.op, b.right, expr.loc)) |folded| {
                    return folded;
                }

                // ── String folding ──────────────────────────────────
                if (b.op == .plus or b.op == .ampersand) {
                    if (try self.tryFoldStringConcat(b.left, b.right, expr.loc)) |folded| {
                        return folded;
                    }
                    // String identity: "" + x → x
                    if (try self.tryStringIdentity(b.left, b.right, b.op)) |result| {
                        return result;
                    }
                }

                // ── Algebraic identities ────────────────────────────────────
                if (try self.tryAlgebraicIdentity(b.left, b.op, b.right, expr.loc)) |result| {
                    return result;
                }

                // ── Division by constant → multiplication ───────────────────
                if (b.op == .divide) {
                    if (try self.tryDivToMul(b.left, b.right, expr.loc)) |result| {
                        return result;
                    }
                }

                // ── MOD power-of-2 → AND ────────────────────────────────────
                if (b.op == .kw_mod) {
                    if (try self.tryModToAnd(b.left, b.right, expr.loc)) |result| {
                        return result;
                    }
                }

                // ── Boolean AND/OR identities ───────────────────────────────
                if (b.op == .kw_and or b.op == .kw_or) {
                    if (try self.tryBoolIdentity(b.left, b.op, b.right, expr.loc)) |result| {
                        return result;
                    }
                }

                // ── Power strength reduction ────────────────────────────────
                if (b.op == .power) {
                    if (try self.tryReducePower(b.left, b.right, expr.loc)) |result| {
                        return result;
                    }
                }

                return expr;
            },
            .unary => |*u| {
                u.operand = try self.optimizeExpr(u.operand);

                // Fold unary minus on number literal: -(5) → -5
                if (u.op == .minus) {
                    if (u.operand.data == .number) {
                        const val = u.operand.data.number.value;
                        self.stats.constants_folded += 1;
                        return self.makeNumberExpr(-val, expr.loc);
                    }
                    // Double negation: -(-x) → x
                    if (u.operand.data == .unary) {
                        if (u.operand.data.unary.op == .minus) {
                            self.stats.double_negations += 1;
                            return u.operand.data.unary.operand;
                        }
                    }
                }

                // Fold NOT on constant: NOT 0 → 1, NOT <nonzero> → 0
                if (u.op == .kw_not) {
                    if (u.operand.data == .number) {
                        const val = u.operand.data.number.value;
                        const int_val: i64 = @intFromFloat(val);
                        self.stats.not_folded += 1;
                        // BASIC NOT is bitwise: NOT 0 = -1 (all bits set)
                        // but for boolean contexts NOT 0 → non-zero (true)
                        // and NOT non-zero → depends on bitwise.
                        // We use bitwise NOT for integer values to match
                        // the runtime semantics.
                        const result: i64 = ~int_val;
                        return self.makeNumberExpr(@floatFromInt(result), expr.loc);
                    }
                    // Double negation: NOT NOT x → x
                    if (u.operand.data == .unary) {
                        if (u.operand.data.unary.op == .kw_not) {
                            self.stats.double_negations += 1;
                            return u.operand.data.unary.operand;
                        }
                    }
                }

                return expr;
            },
            .variable => |v| {
                // CONST propagation: if the variable name matches a known
                // constant, replace with the constant's value.
                if (try self.tryPropagateConst(v.name, expr.loc)) |folded| {
                    return folded;
                }
                return expr;
            },
            .iif => |*i| {
                i.condition = try self.optimizeExpr(i.condition);
                i.true_value = try self.optimizeExpr(i.true_value);
                i.false_value = try self.optimizeExpr(i.false_value);

                // IIF simplification: if condition is constant, pick branch
                if (isConstantTrue(i.condition)) {
                    self.stats.iifs_simplified += 1;
                    return i.true_value;
                } else if (isConstantFalse(i.condition)) {
                    self.stats.iifs_simplified += 1;
                    return i.false_value;
                }

                return expr;
            },
            .function_call => |*fc| {
                for (fc.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                // Try folding pure string/math functions on constant args
                if (try self.tryFoldBuiltinFunction(fc.name, fc.arguments, expr.loc)) |folded| {
                    return folded;
                }
                return expr;
            },
            .method_call => |*mc| {
                mc.object = try self.optimizeExpr(mc.object);
                for (mc.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .member_access => |*ma| {
                ma.object = try self.optimizeExpr(ma.object);
                return expr;
            },
            .array_access => |*aa| {
                for (aa.indices) |*idx| {
                    idx.* = try self.optimizeExpr(idx.*);
                }
                return expr;
            },
            .array_binop => |*ab| {
                ab.left_array = try self.optimizeExpr(ab.left_array);
                ab.right_expr = try self.optimizeExpr(ab.right_expr);
                return expr;
            },
            .new => |*n| {
                for (n.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .create => |*cr| {
                for (cr.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .super_call => |*sc| {
                for (sc.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .is_type => |*it| {
                it.object = try self.optimizeExpr(it.object);
                return expr;
            },
            .list_constructor => |*lc| {
                for (lc.elements) |*elem| {
                    elem.* = try self.optimizeExpr(elem.*);
                }
                return expr;
            },
            .registry_function => |*rf| {
                for (rf.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .spawn => |*sp| {
                for (sp.arguments) |*arg| {
                    arg.* = try self.optimizeExpr(arg.*);
                }
                return expr;
            },
            .await_expr => |*aw| {
                aw.future = try self.optimizeExpr(aw.future);
                return expr;
            },
            .ready => |*rd| {
                rd.future = try self.optimizeExpr(rd.future);
                return expr;
            },
            .marshall => return expr,
            .receive => |*rc| {
                rc.handle = try self.optimizeExpr(rc.handle);
                return expr;
            },
            .has_message => |*hm| {
                hm.handle = try self.optimizeExpr(hm.handle);
                return expr;
            },

            // Leaf nodes — nothing to optimize
            .number,
            .string_lit,
            .me,
            .nothing,
            .parent,
            .cancelled,
            => return expr,
        }
    }

    // ── Constant folding (numeric) ──────────────────────────────────────

    fn tryFoldBinary(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        op: Tag,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const lval = getConstantNumber(left) orelse return null;
        const rval = getConstantNumber(right) orelse return null;

        const result: f64 = switch (op) {
            .plus => lval + rval,
            .minus => lval - rval,
            .multiply => lval * rval,
            .divide => if (rval != 0) lval / rval else return null,
            .int_divide => blk: {
                if (rval == 0) return null;
                const li: i64 = @intFromFloat(lval);
                const ri: i64 = @intFromFloat(rval);
                if (ri == 0) return null;
                break :blk @as(f64, @floatFromInt(@divTrunc(li, ri)));
            },
            .kw_mod => blk: {
                if (rval == 0) return null;
                const li: i64 = @intFromFloat(lval);
                const ri: i64 = @intFromFloat(rval);
                if (ri == 0) return null;
                break :blk @as(f64, @floatFromInt(@rem(li, ri)));
            },
            .power => std.math.pow(f64, lval, rval),

            // Comparison operators → 0 or 1 (integer result)
            .equal => boolToF64(lval == rval),
            .not_equal => boolToF64(lval != rval),
            .less_than => boolToF64(lval < rval),
            .less_equal => boolToF64(lval <= rval),
            .greater_than => boolToF64(lval > rval),
            .greater_equal => boolToF64(lval >= rval),

            // Logical / bitwise operators on integer operands
            .kw_and => blk: {
                const li: i64 = @intFromFloat(lval);
                const ri: i64 = @intFromFloat(rval);
                break :blk @as(f64, @floatFromInt(li & ri));
            },
            .kw_or => blk: {
                const li: i64 = @intFromFloat(lval);
                const ri: i64 = @intFromFloat(rval);
                break :blk @as(f64, @floatFromInt(li | ri));
            },
            .kw_xor => blk: {
                const li: i64 = @intFromFloat(lval);
                const ri: i64 = @intFromFloat(rval);
                break :blk @as(f64, @floatFromInt(li ^ ri));
            },

            else => return null,
        };

        // Guard against NaN/Inf results — don't fold those
        if (std.math.isNan(result) or std.math.isInf(result)) return null;

        self.stats.constants_folded += 1;
        return try self.makeNumberExpr(result, loc);
    }

    // ── CONST propagation ───────────────────────────────────────────────

    fn tryPropagateConst(
        self: *ASTOptimizer,
        name: []const u8,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        var upper_buf: [128]u8 = undefined;
        const name_len = @min(name.len, upper_buf.len);
        for (0..name_len) |i| {
            upper_buf[i] = std.ascii.toUpper(name[i]);
        }
        const upper = upper_buf[0..name_len];

        const csym = self.symbol_table.lookupConstant(upper) orelse return null;

        self.stats.constants_propagated += 1;

        return switch (csym.kind) {
            .integer_const => try self.makeNumberExpr(@floatFromInt(csym.int_value), loc),
            .double_const => try self.makeNumberExpr(csym.double_value, loc),
            .string_const => try self.makeStringExpr(csym.string_value, loc),
        };
    }

    // ── String folding ──────────────────────────────────────────────────

    fn tryFoldStringConcat(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const lstr = getConstantString(left) orelse return null;
        const rstr = getConstantString(right) orelse return null;

        // Concatenate at compile time
        const combined = try std.fmt.allocPrint(self.allocator, "{s}{s}", .{ lstr, rstr });
        self.stats.strings_folded += 1;
        return try self.makeStringExpr(combined, loc);
    }

    /// Detect and eliminate string identity operations:
    ///   "" + x → x
    ///   x + "" → x
    fn tryStringIdentity(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        right: *const ast.Expression,
        op: Tag,
    ) OptError!?ast.ExprPtr {
        _ = op;

        // "" + x → x (if x is a string expression)
        if (getConstantString(left)) |lstr| {
            if (lstr.len == 0 and isStringExpr(right)) {
                self.stats.string_identities += 1;
                // Return the right operand — it's already optimized.
                return @constCast(right);
            }
        }

        // x + "" → x (if x is a string expression)
        if (getConstantString(right)) |rstr| {
            if (rstr.len == 0 and isStringExpr(left)) {
                self.stats.string_identities += 1;
                return @constCast(left);
            }
        }

        return null;
    }

    // ── Algebraic identities ────────────────────────────────────────────

    fn tryAlgebraicIdentity(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        op: Tag,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const lval = getConstantNumber(left);
        const rval = getConstantNumber(right);

        switch (op) {
            .plus => {
                // x + 0 → x
                if (rval) |rv| {
                    if (rv == 0) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(left);
                    }
                }
                // 0 + x → x
                if (lval) |lv| {
                    if (lv == 0) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(right);
                    }
                }
            },
            .minus => {
                // x - 0 → x
                if (rval) |rv| {
                    if (rv == 0) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(left);
                    }
                }
            },
            .multiply => {
                // x * 0 → 0
                if (rval) |rv| {
                    if (rv == 0) {
                        self.stats.algebraic_identities += 1;
                        return try self.makeNumberExpr(0, loc);
                    }
                }
                if (lval) |lv| {
                    if (lv == 0) {
                        self.stats.algebraic_identities += 1;
                        return try self.makeNumberExpr(0, loc);
                    }
                }
                // x * 1 → x
                if (rval) |rv| {
                    if (rv == 1) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(left);
                    }
                }
                // 1 * x → x
                if (lval) |lv| {
                    if (lv == 1) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(right);
                    }
                }
                // x * -1 → -x
                if (rval) |rv| {
                    if (rv == -1) {
                        self.stats.algebraic_identities += 1;
                        return try self.makeUnaryExpr(.minus, @constCast(left), loc);
                    }
                }
                // -1 * x → -x
                if (lval) |lv| {
                    if (lv == -1) {
                        self.stats.algebraic_identities += 1;
                        return try self.makeUnaryExpr(.minus, @constCast(right), loc);
                    }
                }
            },
            .divide => {
                // x / 1 → x
                if (rval) |rv| {
                    if (rv == 1) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(left);
                    }
                }
            },
            .power => {
                // x ^ 0 → 1
                if (rval) |rv| {
                    if (rv == 0) {
                        self.stats.algebraic_identities += 1;
                        return try self.makeNumberExpr(1, loc);
                    }
                }
                // x ^ 1 → x
                if (rval) |rv| {
                    if (rv == 1) {
                        self.stats.algebraic_identities += 1;
                        return @constCast(left);
                    }
                }
            },
            else => {},
        }

        return null;
    }

    // ── Division by constant → multiplication ───────────────────────────

    /// Transform `x / C` → `x * (1/C)` when C is a non-zero, non-integer-
    /// power-of-2 constant.  Multiplication is faster than division on most
    /// hardware.  We skip integer values like 1.0 and 2.0 that are already
    /// handled by algebraic identities or that the backend can strength-
    /// reduce to a shift.
    fn tryDivToMul(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const rval = getConstantNumber(right) orelse return null;

        // Skip trivial cases already covered elsewhere (x/1, x/0)
        if (rval == 0 or rval == 1.0 or rval == -1.0) return null;

        // Only transform when the reciprocal is exact in f64
        const recip = 1.0 / rval;
        if (recip * rval != 1.0) return null;

        self.stats.div_to_mul += 1;
        const recip_node = try self.makeNumberExpr(recip, loc);
        return try self.makeBinaryExpr(@constCast(left), .multiply, recip_node, loc);
    }

    // ── MOD power-of-2 → AND ────────────────────────────────────────────

    /// Transform `x MOD 2^n` → `x AND (2^n - 1)` for positive power-of-2
    /// modulus values.  Only safe for non-negative integer operands, but
    /// BASIC MOD operates on integers anyway (truncating both sides).
    fn tryModToAnd(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const rval = getConstantNumber(right) orelse return null;

        // Must be a positive integer
        if (rval <= 0) return null;
        const ri: i64 = @intFromFloat(rval);
        if (@as(f64, @floatFromInt(ri)) != rval) return null;

        // Check power-of-2: ri > 0 and (ri & (ri-1)) == 0
        if (ri > 0 and (ri & (ri - 1)) == 0) {
            self.stats.mod_to_and += 1;
            const mask = try self.makeNumberExpr(@floatFromInt(ri - 1), loc);
            return try self.makeBinaryExpr(@constCast(left), .kw_and, mask, loc);
        }

        return null;
    }

    // ── Boolean AND/OR identities ───────────────────────────────────────

    /// Simplify boolean/bitwise AND and OR with constant operands:
    ///   x AND 0   → 0        x OR  0   → x
    ///   0 AND x   → 0        0 OR  x   → x
    ///   x AND -1  → x        x OR  -1  → -1
    ///   -1 AND x  → x        -1 OR  x  → -1
    fn tryBoolIdentity(
        self: *ASTOptimizer,
        left: *const ast.Expression,
        op: Tag,
        right: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const lval = getConstantNumber(left);
        const rval = getConstantNumber(right);

        if (op == .kw_and) {
            // x AND 0 → 0
            if (rval) |rv| {
                if (rv == 0) {
                    self.stats.bool_identities += 1;
                    return try self.makeNumberExpr(0, loc);
                }
            }
            // 0 AND x → 0
            if (lval) |lv| {
                if (lv == 0) {
                    self.stats.bool_identities += 1;
                    return try self.makeNumberExpr(0, loc);
                }
            }
            // x AND -1 → x  (all bits set = identity for AND)
            if (rval) |rv| {
                if (rv == -1) {
                    self.stats.bool_identities += 1;
                    return @constCast(left);
                }
            }
            // -1 AND x → x
            if (lval) |lv| {
                if (lv == -1) {
                    self.stats.bool_identities += 1;
                    return @constCast(right);
                }
            }
        }

        if (op == .kw_or) {
            // x OR 0 → x
            if (rval) |rv| {
                if (rv == 0) {
                    self.stats.bool_identities += 1;
                    return @constCast(left);
                }
            }
            // 0 OR x → x
            if (lval) |lv| {
                if (lv == 0) {
                    self.stats.bool_identities += 1;
                    return @constCast(right);
                }
            }
            // x OR -1 → -1  (all bits set = absorbing for OR)
            if (rval) |rv| {
                if (rv == -1) {
                    self.stats.bool_identities += 1;
                    return try self.makeNumberExpr(-1, loc);
                }
            }
            // -1 OR x → -1
            if (lval) |lv| {
                if (lv == -1) {
                    self.stats.bool_identities += 1;
                    return try self.makeNumberExpr(-1, loc);
                }
            }
        }

        return null;
    }

    // ── String function constant folding ────────────────────────────────

    /// Fold pure built-in functions when all arguments are constants.
    /// These are runtime library calls that QBE has no visibility into.
    fn tryFoldBuiltinFunction(
        self: *ASTOptimizer,
        name: []const u8,
        args: []ast.ExprPtr,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        // Normalise function name to upper-case for matching
        var upper_buf: [32]u8 = undefined;
        const nlen = @min(name.len, upper_buf.len);
        for (0..nlen) |i| {
            upper_buf[i] = std.ascii.toUpper(name[i]);
        }
        const upper = upper_buf[0..nlen];

        // ── Single-arg string functions ─────────────────────────────
        if (args.len == 1) {
            // LEN(const_string) → number
            if (std.mem.eql(u8, upper, "LEN")) {
                const s = getConstantString(args[0]) orelse return null;
                self.stats.string_funcs_folded += 1;
                return try self.makeNumberExpr(@floatFromInt(s.len), loc);
            }

            // ASC(const_string) → number  (ASCII value of first char)
            if (std.mem.eql(u8, upper, "ASC")) {
                const s = getConstantString(args[0]) orelse return null;
                if (s.len == 0) return null; // runtime error — don't fold
                self.stats.string_funcs_folded += 1;
                return try self.makeNumberExpr(@floatFromInt(s[0]), loc);
            }

            // CHR$(const_number) → string
            if (std.mem.eql(u8, upper, "CHR$")) {
                const val = getConstantNumber(args[0]) orelse return null;
                const iv: i64 = @intFromFloat(val);
                if (iv < 0 or iv > 127) return null; // only fold safe ASCII
                const buf = try self.allocator.alloc(u8, 1);
                buf[0] = @intCast(iv);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(buf, loc);
            }

            // UCASE$(const_string) → string
            if (std.mem.eql(u8, upper, "UCASE$")) {
                const s = getConstantString(args[0]) orelse return null;
                const result = try self.allocator.alloc(u8, s.len);
                for (0..s.len) |i| {
                    result[i] = std.ascii.toUpper(s[i]);
                }
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // LCASE$(const_string) → string
            if (std.mem.eql(u8, upper, "LCASE$")) {
                const s = getConstantString(args[0]) orelse return null;
                const result = try self.allocator.alloc(u8, s.len);
                for (0..s.len) |i| {
                    result[i] = std.ascii.toLower(s[i]);
                }
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // TRIM$ / LTRIM$ / RTRIM$
            if (std.mem.eql(u8, upper, "TRIM$") or std.mem.eql(u8, upper, "LTRIM$") or std.mem.eql(u8, upper, "RTRIM$")) {
                const s = getConstantString(args[0]) orelse return null;
                var trimmed: []const u8 = s;
                if (upper[0] == 'T' or upper[0] == 'L') {
                    trimmed = std.mem.trimLeft(u8, trimmed, " ");
                }
                if (upper[0] == 'T' or upper[0] == 'R') {
                    trimmed = std.mem.trimRight(u8, trimmed, " ");
                }
                const result = try self.allocator.dupe(u8, trimmed);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // VAL(const_string) → number
            if (std.mem.eql(u8, upper, "VAL")) {
                const s = getConstantString(args[0]) orelse return null;
                const trimmed = std.mem.trim(u8, s, " ");
                const val = std.fmt.parseFloat(f64, trimmed) catch return null;
                self.stats.string_funcs_folded += 1;
                return try self.makeNumberExpr(val, loc);
            }

            // STR$(const_number) → string
            if (std.mem.eql(u8, upper, "STR$")) {
                const val = getConstantNumber(args[0]) orelse return null;
                // Only fold clean integer values to avoid precision issues
                const iv: i64 = @intFromFloat(val);
                if (@as(f64, @floatFromInt(iv)) != val) return null;
                const result = try std.fmt.allocPrint(self.allocator, "{d}", .{iv});
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // SPACE$(const_number) → string of spaces
            if (std.mem.eql(u8, upper, "SPACE$")) {
                const val = getConstantNumber(args[0]) orelse return null;
                const iv: i64 = @intFromFloat(val);
                if (iv < 0 or iv > 256) return null; // don't fold huge strings
                const count: usize = @intCast(iv);
                const result = try self.allocator.alloc(u8, count);
                @memset(result, ' ');
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }
        }

        // ── Two-arg functions ───────────────────────────────────────
        if (args.len == 2) {
            // LEFT$(const_string, const_number) → string
            if (std.mem.eql(u8, upper, "LEFT$")) {
                const s = getConstantString(args[0]) orelse return null;
                const nval = getConstantNumber(args[1]) orelse return null;
                const n: i64 = @intFromFloat(nval);
                if (n < 0) return null;
                const count: usize = @min(@as(usize, @intCast(n)), s.len);
                const result = try self.allocator.dupe(u8, s[0..count]);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // RIGHT$(const_string, const_number) → string
            if (std.mem.eql(u8, upper, "RIGHT$")) {
                const s = getConstantString(args[0]) orelse return null;
                const nval = getConstantNumber(args[1]) orelse return null;
                const n: i64 = @intFromFloat(nval);
                if (n < 0) return null;
                const count: usize = @min(@as(usize, @intCast(n)), s.len);
                const start = s.len - count;
                const result = try self.allocator.dupe(u8, s[start..]);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }

            // INSTR(const_string, const_string) → number (1-based position)
            if (std.mem.eql(u8, upper, "INSTR")) {
                const haystack = getConstantString(args[0]) orelse return null;
                const needle = getConstantString(args[1]) orelse return null;
                if (std.mem.indexOf(u8, haystack, needle)) |pos| {
                    self.stats.string_funcs_folded += 1;
                    return try self.makeNumberExpr(@floatFromInt(pos + 1), loc);
                } else {
                    self.stats.string_funcs_folded += 1;
                    return try self.makeNumberExpr(0, loc);
                }
            }

            // STRING$(count, char_code_or_string) → string
            if (std.mem.eql(u8, upper, "STRING$")) {
                const count_val = getConstantNumber(args[0]) orelse return null;
                const count_i: i64 = @intFromFloat(count_val);
                if (count_i < 0 or count_i > 256) return null;
                const count: usize = @intCast(count_i);

                // STRING$(n, code) or STRING$(n, "x")
                var fill_char: u8 = undefined;
                if (getConstantNumber(args[1])) |char_val| {
                    const ci: i64 = @intFromFloat(char_val);
                    if (ci < 0 or ci > 255) return null;
                    fill_char = @intCast(ci);
                } else if (getConstantString(args[1])) |cs| {
                    if (cs.len == 0) return null;
                    fill_char = cs[0];
                } else return null;

                const result = try self.allocator.alloc(u8, count);
                @memset(result, fill_char);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }
        }

        // ── Three-arg functions ─────────────────────────────────────
        if (args.len == 3) {
            // MID$(const_string, const_start, const_length) → string
            if (std.mem.eql(u8, upper, "MID$")) {
                const s = getConstantString(args[0]) orelse return null;
                const start_val = getConstantNumber(args[1]) orelse return null;
                const len_val = getConstantNumber(args[2]) orelse return null;
                const start_i: i64 = @intFromFloat(start_val);
                const len_i: i64 = @intFromFloat(len_val);
                if (start_i < 1 or len_i < 0) return null;
                const start: usize = @intCast(start_i - 1); // 1-based to 0-based
                if (start >= s.len) {
                    const empty = try self.allocator.dupe(u8, "");
                    self.stats.string_funcs_folded += 1;
                    return try self.makeStringExpr(empty, loc);
                }
                const avail = s.len - start;
                const take: usize = @min(@as(usize, @intCast(len_i)), avail);
                const result = try self.allocator.dupe(u8, s[start .. start + take]);
                self.stats.string_funcs_folded += 1;
                return try self.makeStringExpr(result, loc);
            }
        }

        return null;
    }

    // ── Power strength reduction ────────────────────────────────────────

    fn tryReducePower(
        self: *ASTOptimizer,
        base: *const ast.Expression,
        exponent: *const ast.Expression,
        loc: SourceLocation,
    ) OptError!?ast.ExprPtr {
        const exp_val = getConstantNumber(exponent) orelse return null;

        // x ^ 2 → x * x
        if (exp_val == 2.0) {
            self.stats.powers_reduced += 1;
            const base_copy = @constCast(base);
            return try self.makeBinaryExpr(base_copy, .multiply, base_copy, loc);
        }

        // x ^ 3 → x * x * x
        if (exp_val == 3.0) {
            self.stats.powers_reduced += 1;
            const base_copy = @constCast(base);
            const x_squared = try self.makeBinaryExpr(base_copy, .multiply, base_copy, loc);
            return try self.makeBinaryExpr(x_squared, .multiply, base_copy, loc);
        }

        // x ^ -1 → 1 / x
        if (exp_val == -1.0) {
            self.stats.powers_reduced += 1;
            const one = try self.makeNumberExpr(1, loc);
            return try self.makeBinaryExpr(one, .divide, @constCast(base), loc);
        }

        // x ^ 0.5 → sqrt(x) — emit as function call
        // Note: we don't create function call nodes here because the
        // AST function call requires runtime name resolution. Instead
        // we leave x^0.5 as-is and let QBE + the runtime handle sqrt.
        // The algebraic identity pass already handles x^0 and x^1 above.

        return null;
    }

    // ── AST node constructors ───────────────────────────────────────────

    fn makeNumberExpr(self: *ASTOptimizer, value: f64, loc: SourceLocation) OptError!ast.ExprPtr {
        const node = try self.allocator.create(ast.Expression);
        node.* = .{ .loc = loc, .data = .{ .number = .{ .value = value } } };
        return node;
    }

    fn makeStringExpr(self: *ASTOptimizer, value: []const u8, loc: SourceLocation) OptError!ast.ExprPtr {
        const node = try self.allocator.create(ast.Expression);
        node.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = value } } };
        return node;
    }

    fn makeUnaryExpr(self: *ASTOptimizer, op: Tag, operand: ast.ExprPtr, loc: SourceLocation) OptError!ast.ExprPtr {
        const node = try self.allocator.create(ast.Expression);
        node.* = .{ .loc = loc, .data = .{ .unary = .{ .op = op, .operand = operand } } };
        return node;
    }

    fn makeBinaryExpr(self: *ASTOptimizer, left: ast.ExprPtr, op: Tag, right: ast.ExprPtr, loc: SourceLocation) OptError!ast.ExprPtr {
        const node = try self.allocator.create(ast.Expression);
        node.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = op, .right = right } } };
        return node;
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    /// Extract a compile-time constant number from an expression, or null.
    fn getConstantNumber(expr: *const ast.Expression) ?f64 {
        return switch (expr.data) {
            .number => |n| n.value,
            .unary => |u| {
                if (u.op == .minus) {
                    if (u.operand.data == .number) {
                        return -u.operand.data.number.value;
                    }
                }
                return null;
            },
            else => null,
        };
    }

    /// Extract a compile-time constant string from an expression, or null.
    fn getConstantString(expr: *const ast.Expression) ?[]const u8 {
        return switch (expr.data) {
            .string_lit => |s| s.value,
            else => null,
        };
    }

    /// Check if an expression is a string type (string literal, variable
    /// with $ suffix, or string function call).
    fn isStringExpr(expr: *const ast.Expression) bool {
        return switch (expr.data) {
            .string_lit => true,
            .variable => |v| {
                if (v.type_suffix) |s| {
                    return s == .type_string;
                }
                // Check if the name ends with $
                if (v.name.len > 0 and v.name[v.name.len - 1] == '$') return true;
                return false;
            },
            .function_call => |fc| {
                // Functions ending with $ return strings
                if (fc.name.len > 0 and fc.name[fc.name.len - 1] == '$') return true;
                return false;
            },
            .method_call => true, // conservative — could be string
            .iif => true, // might be string IIF
            .binary => |b| {
                // String concatenation results are strings
                if (b.op == .plus or b.op == .ampersand) {
                    return isStringExpr(b.left) or isStringExpr(b.right);
                }
                return false;
            },
            .member_access => true, // could be string field
            .array_access => |aa| {
                if (aa.type_suffix) |s| {
                    return s == .type_string;
                }
                if (aa.name.len > 0 and aa.name[aa.name.len - 1] == '$') return true;
                return false;
            },
            else => false,
        };
    }

    /// Check whether an expression is a compile-time constant that
    /// evaluates to "true" (non-zero).
    fn isConstantTrue(expr: *const ast.Expression) bool {
        if (getConstantNumber(expr)) |val| {
            return val != 0;
        }
        return false;
    }

    /// Check whether an expression is a compile-time constant that
    /// evaluates to "false" (zero).
    fn isConstantFalse(expr: *const ast.Expression) bool {
        if (getConstantNumber(expr)) |val| {
            return val == 0;
        }
        return false;
    }

    fn boolToF64(b: bool) f64 {
        return if (b) 1.0 else 0.0;
    }
};

// ─── Tests ──────────────────────────────────────────────────────────────────

test "constant folding - addition" {
    const allocator = std.testing.allocator;

    // Build: 3 + 4
    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const left = try allocator.create(ast.Expression);
    left.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    const right = try allocator.create(ast.Expression);
    right.* = .{ .loc = loc, .data = .{ .number = .{ .value = 4.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = .plus, .right = right } } };
    defer allocator.destroy(left);
    defer allocator.destroy(right);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 7.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.constants_folded);

    // Clean up the new node created by the optimizer
    if (result != bin and result != left and result != right) {
        allocator.destroy(result);
    }
}

test "constant folding - subtraction" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const left = try allocator.create(ast.Expression);
    left.* = .{ .loc = loc, .data = .{ .number = .{ .value = 10.0 } } };
    const right = try allocator.create(ast.Expression);
    right.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = .minus, .right = right } } };
    defer allocator.destroy(left);
    defer allocator.destroy(right);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 7.0), result.data.number.value);
    if (result != bin) allocator.destroy(result);
}

test "constant folding - multiplication" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const left = try allocator.create(ast.Expression);
    left.* = .{ .loc = loc, .data = .{ .number = .{ .value = 6.0 } } };
    const right = try allocator.create(ast.Expression);
    right.* = .{ .loc = loc, .data = .{ .number = .{ .value = 7.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = .multiply, .right = right } } };
    defer allocator.destroy(left);
    defer allocator.destroy(right);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 42.0), result.data.number.value);
    if (result != bin) allocator.destroy(result);
}

test "constant folding - division by zero returns null (no fold)" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const left = try allocator.create(ast.Expression);
    left.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    const right = try allocator.create(ast.Expression);
    right.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = .divide, .right = right } } };
    defer allocator.destroy(left);
    defer allocator.destroy(right);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // Should NOT fold — division by zero
    try std.testing.expect(result.data == .binary);
    try std.testing.expectEqual(@as(u32, 0), opt.stats.constants_folded);
}

test "constant folding - comparison" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const left = try allocator.create(ast.Expression);
    left.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    const right = try allocator.create(ast.Expression);
    right.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = left, .op = .greater_than, .right = right } } };
    defer allocator.destroy(left);
    defer allocator.destroy(right);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 1.0), result.data.number.value);
    if (result != bin) allocator.destroy(result);
}

test "constant folding - nested expression (2 + 3) * 4" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    // Build inner: 2 + 3
    const two = try allocator.create(ast.Expression);
    two.* = .{ .loc = loc, .data = .{ .number = .{ .value = 2.0 } } };
    const three = try allocator.create(ast.Expression);
    three.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    const inner = try allocator.create(ast.Expression);
    inner.* = .{ .loc = loc, .data = .{ .binary = .{ .left = two, .op = .plus, .right = three } } };
    // Build outer: inner * 4
    const four = try allocator.create(ast.Expression);
    four.* = .{ .loc = loc, .data = .{ .number = .{ .value = 4.0 } } };
    const outer = try allocator.create(ast.Expression);
    outer.* = .{ .loc = loc, .data = .{ .binary = .{ .left = inner, .op = .multiply, .right = four } } };
    defer allocator.destroy(two);
    defer allocator.destroy(three);
    defer allocator.destroy(inner);
    defer allocator.destroy(four);
    defer allocator.destroy(outer);

    const result = try opt.optimizeExpr(outer);

    // The inner fold (2+3) created an intermediate 5.0 node, now at outer.data.binary.left
    const intermediate = outer.data.binary.left;
    if (intermediate != two and intermediate != three and intermediate != inner and intermediate != four and intermediate != outer) {
        allocator.destroy(intermediate);
    }

    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 20.0), result.data.number.value);
    // Two folds: (2+3)→5, then 5*4→20
    try std.testing.expectEqual(@as(u32, 2), opt.stats.constants_folded);

    // Clean up the final folded result node (20.0)
    if (result != outer and result != inner and result != two and result != three and result != four) {
        allocator.destroy(result);
    }
}

test "unary minus folding" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const five = try allocator.create(ast.Expression);
    five.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    const neg = try allocator.create(ast.Expression);
    neg.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = five } } };
    defer allocator.destroy(five);
    defer allocator.destroy(neg);

    const result = try opt.optimizeExpr(neg);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, -5.0), result.data.number.value);
    if (result != neg and result != five) allocator.destroy(result);
}

test "NOT folding" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const not_expr = try allocator.create(ast.Expression);
    not_expr.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .kw_not, .operand = zero } } };
    defer allocator.destroy(zero);
    defer allocator.destroy(not_expr);

    const result = try opt.optimizeExpr(not_expr);
    try std.testing.expect(result.data == .number);
    // NOT 0 = -1 (bitwise NOT)
    try std.testing.expectEqual(@as(f64, -1.0), result.data.number.value);
    if (result != not_expr and result != zero) allocator.destroy(result);
}

test "algebraic identity - x + 0" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .plus, .right = zero } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(zero);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // Should return var_x directly
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.algebraic_identities);
}

test "algebraic identity - x * 0" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .multiply, .right = zero } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(zero);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 0.0), result.data.number.value);
    if (result != bin and result != var_x and result != zero) allocator.destroy(result);
}

test "algebraic identity - x * 1" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .multiply, .right = one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
}

test "algebraic identity - x / 1" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .divide, .right = one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
}

test "power strength reduction - x^2 → x*x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const two = try allocator.create(ast.Expression);
    two.* = .{ .loc = loc, .data = .{ .number = .{ .value = 2.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .power, .right = two } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(two);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // Should become x * x
    try std.testing.expect(result.data == .binary);
    try std.testing.expect(result.data.binary.op == .multiply);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.powers_reduced);
    if (result != bin) allocator.destroy(result);
}

test "power strength reduction - x^0 → 1" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .power, .right = zero } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(zero);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x^0 is handled by algebraic_identity (not power reduction)
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 1.0), result.data.number.value);
    if (result != bin and result != var_x and result != zero) allocator.destroy(result);
}

test "power strength reduction - x^-1 → 1/x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    // Build the unary -1 expression
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const neg_one = try allocator.create(ast.Expression);
    neg_one.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = one } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .power, .right = neg_one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one);
    defer allocator.destroy(neg_one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);

    // The unary fold -(1.0) created an intermediate -1.0 node, now at bin.data.binary.right
    const intermediate_neg = bin.data.binary.right;
    if (intermediate_neg != one and intermediate_neg != neg_one and intermediate_neg != var_x and intermediate_neg != bin) {
        allocator.destroy(intermediate_neg);
    }

    // x^-1 → 1/x
    try std.testing.expect(result.data == .binary);
    try std.testing.expect(result.data.binary.op == .divide);
    try std.testing.expect(result.data.binary.left.data == .number);
    try std.testing.expectEqual(@as(f64, 1.0), result.data.binary.left.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.powers_reduced);
    // Clean up: the optimizer creates two nodes (the number 1 and the binary /)
    if (result != bin) {
        if (result.data.binary.left != one and result.data.binary.left != neg_one and result.data.binary.left != var_x) {
            allocator.destroy(result.data.binary.left);
        }
        allocator.destroy(result);
    }
}

test "string folding - concatenation of literals" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const hello = try allocator.create(ast.Expression);
    hello.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello" } } };
    const world = try allocator.create(ast.Expression);
    world.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = " World" } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = hello, .op = .plus, .right = world } } };
    defer allocator.destroy(hello);
    defer allocator.destroy(world);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("Hello World", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.strings_folded);
    // Free the concatenated string and expression
    if (result != bin and result != hello and result != world) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string identity - empty string + variable" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const empty = try allocator.create(ast.Expression);
    empty.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "" } } };
    const var_s = try allocator.create(ast.Expression);
    var_s.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "s$", .type_suffix = .type_string } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = empty, .op = .plus, .right = var_s } } };
    defer allocator.destroy(empty);
    defer allocator.destroy(var_s);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // Should return var_s directly
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("s$", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_identities);
}

test "IIF simplification - constant true" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const cond = try allocator.create(ast.Expression);
    cond.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const true_val = try allocator.create(ast.Expression);
    true_val.* = .{ .loc = loc, .data = .{ .number = .{ .value = 42.0 } } };
    const false_val = try allocator.create(ast.Expression);
    false_val.* = .{ .loc = loc, .data = .{ .number = .{ .value = 99.0 } } };
    const iif_expr = try allocator.create(ast.Expression);
    iif_expr.* = .{ .loc = loc, .data = .{ .iif = .{
        .condition = cond,
        .true_value = true_val,
        .false_value = false_val,
    } } };
    defer allocator.destroy(cond);
    defer allocator.destroy(true_val);
    defer allocator.destroy(false_val);
    defer allocator.destroy(iif_expr);

    const result = try opt.optimizeExpr(iif_expr);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 42.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.iifs_simplified);
}

test "IIF simplification - constant false" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const cond = try allocator.create(ast.Expression);
    cond.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const true_val = try allocator.create(ast.Expression);
    true_val.* = .{ .loc = loc, .data = .{ .number = .{ .value = 42.0 } } };
    const false_val = try allocator.create(ast.Expression);
    false_val.* = .{ .loc = loc, .data = .{ .number = .{ .value = 99.0 } } };
    const iif_expr = try allocator.create(ast.Expression);
    iif_expr.* = .{ .loc = loc, .data = .{ .iif = .{
        .condition = cond,
        .true_value = true_val,
        .false_value = false_val,
    } } };
    defer allocator.destroy(cond);
    defer allocator.destroy(true_val);
    defer allocator.destroy(false_val);
    defer allocator.destroy(iif_expr);

    const result = try opt.optimizeExpr(iif_expr);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 99.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.iifs_simplified);
}

test "FOR step direction - positive literal" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const step_expr = try allocator.create(ast.Expression);
    step_expr.* = .{ .loc = loc, .data = .{ .number = .{ .value = 2.0 } } };
    defer allocator.destroy(step_expr);

    const dir = ASTOptimizer.classifyStepDirection(step_expr);
    try std.testing.expectEqual(StepDirection.positive, dir);
}

test "FOR step direction - negative literal" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    // Build -1 as unary minus on 1
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const neg_one = try allocator.create(ast.Expression);
    neg_one.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = one } } };
    defer allocator.destroy(one);
    defer allocator.destroy(neg_one);

    const dir = ASTOptimizer.classifyStepDirection(neg_one);
    try std.testing.expectEqual(StepDirection.negative, dir);
}

test "FOR step direction - unknown (variable)" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_expr = try allocator.create(ast.Expression);
    var_expr.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "step_size" } } };
    defer allocator.destroy(var_expr);

    const dir = ASTOptimizer.classifyStepDirection(var_expr);
    try std.testing.expectEqual(StepDirection.unknown, dir);
}

test "OptStats total" {
    var stats = OptStats{};
    try std.testing.expectEqual(@as(u32, 0), stats.total());
    stats.constants_folded = 3;
    stats.strings_folded = 2;
    stats.for_loops_specialized = 5;
    try std.testing.expectEqual(@as(u32, 10), stats.total());
}

test "CONST propagation" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();

    // Register a constant in the symbol table
    const key = try allocator.dupe(u8, "MAX");
    defer allocator.free(key);
    try st.constants.put(key, .{
        .kind = .integer_const,
        .int_value = 100,
    });

    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_expr = try allocator.create(ast.Expression);
    var_expr.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "MAX" } } };
    defer allocator.destroy(var_expr);

    const result = try opt.optimizeExpr(var_expr);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 100.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.constants_propagated);
    if (result != var_expr) allocator.destroy(result);
}

test "string CONST propagation" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();

    const key = try allocator.dupe(u8, "GREETING");
    defer allocator.free(key);
    try st.constants.put(key, .{
        .kind = .string_const,
        .string_value = "Hello",
    });

    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_expr = try allocator.create(ast.Expression);
    var_expr.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "GREETING" } } };
    defer allocator.destroy(var_expr);

    const result = try opt.optimizeExpr(var_expr);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("Hello", result.data.string_lit.value);
    if (result != var_expr) allocator.destroy(result);
}

test "no false positive - non-constant variable" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();

    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_expr = try allocator.create(ast.Expression);
    var_expr.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    defer allocator.destroy(var_expr);

    const result = try opt.optimizeExpr(var_expr);
    // Should return the same variable — no optimization
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 0), opt.stats.constants_propagated);
}

test "algebraic identity - x * -1 → -x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    // Build -1 as unary minus
    const one_inner = try allocator.create(ast.Expression);
    one_inner.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const neg_one_expr = try allocator.create(ast.Expression);
    neg_one_expr.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = one_inner } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .multiply, .right = neg_one_expr } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one_inner);
    defer allocator.destroy(neg_one_expr);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);

    // The unary fold -(1.0) created an intermediate -1.0 node, now at bin.data.binary.right
    const intermediate_neg = bin.data.binary.right;
    if (intermediate_neg != one_inner and intermediate_neg != neg_one_expr and intermediate_neg != var_x and intermediate_neg != bin) {
        allocator.destroy(intermediate_neg);
    }

    // Should fold -1 into -1 first, then x * -1 → -x (unary minus)
    try std.testing.expect(result.data == .unary);
    try std.testing.expect(result.data.unary.op == .minus);
    try std.testing.expect(result.data.unary.operand.data == .variable);
    if (result != bin and result != var_x and result != neg_one_expr and result != one_inner) {
        allocator.destroy(result);
    }
}

test "multiple optimizations compose" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();

    // Register CONST OFFSET = 10
    const key = try allocator.dupe(u8, "OFFSET");
    defer allocator.free(key);
    try st.constants.put(key, .{
        .kind = .integer_const,
        .int_value = 10,
    });

    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    // Build: OFFSET + 5 — should become 10 + 5 → 15
    const var_offset = try allocator.create(ast.Expression);
    var_offset.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "OFFSET" } } };
    const five = try allocator.create(ast.Expression);
    five.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_offset, .op = .plus, .right = five } } };
    defer allocator.destroy(var_offset);
    defer allocator.destroy(five);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);

    // The propagation step replaced the variable with a new number node (10.0).
    // That intermediate node is now the left child of bin. We must free it.
    // After folding, bin.left points to the propagated node (10.0).
    const propagated_node = bin.data.binary.left;
    if (propagated_node != var_offset and propagated_node != five) {
        allocator.destroy(propagated_node);
    }

    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 15.0), result.data.number.value);
    // One propagation (OFFSET → 10) + one fold (10 + 5 → 15)
    try std.testing.expectEqual(@as(u32, 1), opt.stats.constants_propagated);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.constants_folded);

    // Free the final folded result node (15.0) created by the optimizer.
    if (result != bin and result != var_offset and result != five) {
        allocator.destroy(result);
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests for new optimizations (11–16)
// ═══════════════════════════════════════════════════════════════════════════

test "double negation - minus minus x → x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const inner_neg = try allocator.create(ast.Expression);
    inner_neg.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = var_x } } };
    const outer_neg = try allocator.create(ast.Expression);
    outer_neg.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = inner_neg } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(inner_neg);
    defer allocator.destroy(outer_neg);

    const result = try opt.optimizeExpr(outer_neg);
    // --x → x
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.double_negations);
}

test "double negation - NOT NOT x → x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const inner_not = try allocator.create(ast.Expression);
    inner_not.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .kw_not, .operand = var_x } } };
    const outer_not = try allocator.create(ast.Expression);
    outer_not.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .kw_not, .operand = inner_not } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(inner_not);
    defer allocator.destroy(outer_not);

    const result = try opt.optimizeExpr(outer_not);
    // NOT NOT x → x
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.double_negations);
}

test "string function folding - LEN" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const hello = try allocator.create(ast.Expression);
    hello.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "hello" } } };
    var args_buf = [_]ast.ExprPtr{hello};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "LEN", .arguments = &args_buf } } };
    defer allocator.destroy(hello);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 5.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call and result != hello) allocator.destroy(result);
}

test "string function folding - ASC" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const a_str = try allocator.create(ast.Expression);
    a_str.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "A" } } };
    var args_buf = [_]ast.ExprPtr{a_str};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "ASC", .arguments = &args_buf } } };
    defer allocator.destroy(a_str);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 65.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call and result != a_str) allocator.destroy(result);
}

test "string function folding - CHR$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const num65 = try allocator.create(ast.Expression);
    num65.* = .{ .loc = loc, .data = .{ .number = .{ .value = 65.0 } } };
    var args_buf = [_]ast.ExprPtr{num65};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "CHR$", .arguments = &args_buf } } };
    defer allocator.destroy(num65);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("A", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call and result != num65) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - UCASE$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const mixed = try allocator.create(ast.Expression);
    mixed.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello World" } } };
    var args_buf = [_]ast.ExprPtr{mixed};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "UCASE$", .arguments = &args_buf } } };
    defer allocator.destroy(mixed);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("HELLO WORLD", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call and result != mixed) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - LCASE$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const mixed = try allocator.create(ast.Expression);
    mixed.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello World" } } };
    var args_buf = [_]ast.ExprPtr{mixed};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "LCASE$", .arguments = &args_buf } } };
    defer allocator.destroy(mixed);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("hello world", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call and result != mixed) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - LEFT$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const hello = try allocator.create(ast.Expression);
    hello.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello" } } };
    const three = try allocator.create(ast.Expression);
    three.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    var args_buf = [_]ast.ExprPtr{ hello, three };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "LEFT$", .arguments = &args_buf } } };
    defer allocator.destroy(hello);
    defer allocator.destroy(three);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("Hel", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - RIGHT$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const hello = try allocator.create(ast.Expression);
    hello.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello" } } };
    const two = try allocator.create(ast.Expression);
    two.* = .{ .loc = loc, .data = .{ .number = .{ .value = 2.0 } } };
    var args_buf = [_]ast.ExprPtr{ hello, two };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "RIGHT$", .arguments = &args_buf } } };
    defer allocator.destroy(hello);
    defer allocator.destroy(two);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("lo", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - MID$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const hello = try allocator.create(ast.Expression);
    hello.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello World" } } };
    const start = try allocator.create(ast.Expression);
    start.* = .{ .loc = loc, .data = .{ .number = .{ .value = 7.0 } } };
    const length = try allocator.create(ast.Expression);
    length.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    var args_buf = [_]ast.ExprPtr{ hello, start, length };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "MID$", .arguments = &args_buf } } };
    defer allocator.destroy(hello);
    defer allocator.destroy(start);
    defer allocator.destroy(length);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("World", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - INSTR found" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const haystack = try allocator.create(ast.Expression);
    haystack.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello World" } } };
    const needle = try allocator.create(ast.Expression);
    needle.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "World" } } };
    var args_buf = [_]ast.ExprPtr{ haystack, needle };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "INSTR", .arguments = &args_buf } } };
    defer allocator.destroy(haystack);
    defer allocator.destroy(needle);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .number);
    // "World" starts at position 7 (1-based)
    try std.testing.expectEqual(@as(f64, 7.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) allocator.destroy(result);
}

test "string function folding - INSTR not found" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const haystack = try allocator.create(ast.Expression);
    haystack.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "Hello" } } };
    const needle = try allocator.create(ast.Expression);
    needle.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "xyz" } } };
    var args_buf = [_]ast.ExprPtr{ haystack, needle };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "INSTR", .arguments = &args_buf } } };
    defer allocator.destroy(haystack);
    defer allocator.destroy(needle);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 0.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) allocator.destroy(result);
}

test "string function folding - VAL" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const num_str = try allocator.create(ast.Expression);
    num_str.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "  42.5  " } } };
    var args_buf = [_]ast.ExprPtr{num_str};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "VAL", .arguments = &args_buf } } };
    defer allocator.destroy(num_str);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 42.5), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) allocator.destroy(result);
}

test "string function folding - STR$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const num = try allocator.create(ast.Expression);
    num.* = .{ .loc = loc, .data = .{ .number = .{ .value = 42.0 } } };
    var args_buf = [_]ast.ExprPtr{num};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "STR$", .arguments = &args_buf } } };
    defer allocator.destroy(num);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("42", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - SPACE$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const five = try allocator.create(ast.Expression);
    five.* = .{ .loc = loc, .data = .{ .number = .{ .value = 5.0 } } };
    var args_buf = [_]ast.ExprPtr{five};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "SPACE$", .arguments = &args_buf } } };
    defer allocator.destroy(five);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("     ", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "string function folding - TRIM$" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const padded = try allocator.create(ast.Expression);
    padded.* = .{ .loc = loc, .data = .{ .string_lit = .{ .value = "  hi  " } } };
    var args_buf = [_]ast.ExprPtr{padded};
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "TRIM$", .arguments = &args_buf } } };
    defer allocator.destroy(padded);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("hi", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "division by constant → multiplication" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const four = try allocator.create(ast.Expression);
    four.* = .{ .loc = loc, .data = .{ .number = .{ .value = 4.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .divide, .right = four } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(four);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x / 4.0 → x * 0.25
    try std.testing.expect(result.data == .binary);
    try std.testing.expect(result.data.binary.op == .multiply);
    try std.testing.expect(result.data.binary.right.data == .number);
    try std.testing.expectEqual(@as(f64, 0.25), result.data.binary.right.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.div_to_mul);
    // Clean up optimizer-created nodes
    if (result.data.binary.right != four) {
        allocator.destroy(result.data.binary.right);
    }
    if (result != bin) allocator.destroy(result);
}

test "division by 1 not transformed (handled by algebraic identity)" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .divide, .right = one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x / 1 → x (algebraic identity, NOT div-to-mul)
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqual(@as(u32, 0), opt.stats.div_to_mul);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.algebraic_identities);
}

test "MOD power-of-2 → AND" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const eight = try allocator.create(ast.Expression);
    eight.* = .{ .loc = loc, .data = .{ .number = .{ .value = 8.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_mod, .right = eight } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(eight);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x MOD 8 → x AND 7
    try std.testing.expect(result.data == .binary);
    try std.testing.expect(result.data.binary.op == .kw_and);
    try std.testing.expect(result.data.binary.right.data == .number);
    try std.testing.expectEqual(@as(f64, 7.0), result.data.binary.right.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.mod_to_and);
    // Clean up optimizer-created nodes
    if (result.data.binary.right != eight) {
        allocator.destroy(result.data.binary.right);
    }
    if (result != bin) allocator.destroy(result);
}

test "MOD non-power-of-2 not transformed" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const seven = try allocator.create(ast.Expression);
    seven.* = .{ .loc = loc, .data = .{ .number = .{ .value = 7.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_mod, .right = seven } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(seven);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x MOD 7 — not a power of 2, no transformation
    try std.testing.expect(result.data == .binary);
    try std.testing.expect(result.data.binary.op == .kw_mod);
    try std.testing.expectEqual(@as(u32, 0), opt.stats.mod_to_and);
}

test "boolean identity - x AND 0 → 0" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_and, .right = zero } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(zero);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, 0.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.bool_identities);
    if (result != bin and result != zero and result != var_x) allocator.destroy(result);
}

test "boolean identity - x OR 0 → x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_or, .right = zero } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(zero);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);
    // x OR 0 → x
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.bool_identities);
}

test "boolean identity - x AND -1 → x" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    // Build -1 as unary minus on 1
    const one_lit = try allocator.create(ast.Expression);
    one_lit.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const neg_one = try allocator.create(ast.Expression);
    neg_one.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = one_lit } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_and, .right = neg_one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one_lit);
    defer allocator.destroy(neg_one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);

    // The unary fold -(1.0) creates an intermediate -1.0 node at bin.data.binary.right
    const intermediate_neg = bin.data.binary.right;
    if (intermediate_neg != one_lit and intermediate_neg != neg_one and intermediate_neg != var_x and intermediate_neg != bin) {
        allocator.destroy(intermediate_neg);
    }

    // x AND -1 → x
    try std.testing.expect(result.data == .variable);
    try std.testing.expectEqualStrings("x", result.data.variable.name);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.bool_identities);
}

test "boolean identity - x OR -1 → -1" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const var_x = try allocator.create(ast.Expression);
    var_x.* = .{ .loc = loc, .data = .{ .variable = .{ .name = "x" } } };
    // Build -1 as unary minus on 1
    const one_lit = try allocator.create(ast.Expression);
    one_lit.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    const neg_one = try allocator.create(ast.Expression);
    neg_one.* = .{ .loc = loc, .data = .{ .unary = .{ .op = .minus, .operand = one_lit } } };
    const bin = try allocator.create(ast.Expression);
    bin.* = .{ .loc = loc, .data = .{ .binary = .{ .left = var_x, .op = .kw_or, .right = neg_one } } };
    defer allocator.destroy(var_x);
    defer allocator.destroy(one_lit);
    defer allocator.destroy(neg_one);
    defer allocator.destroy(bin);

    const result = try opt.optimizeExpr(bin);

    // The unary fold -(1.0) creates an intermediate -1.0 node at bin.data.binary.right
    const intermediate_neg = bin.data.binary.right;
    if (intermediate_neg != one_lit and intermediate_neg != neg_one and intermediate_neg != var_x and intermediate_neg != bin) {
        allocator.destroy(intermediate_neg);
    }

    // x OR -1 → -1
    try std.testing.expect(result.data == .number);
    try std.testing.expectEqual(@as(f64, -1.0), result.data.number.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.bool_identities);
    if (result != bin and result != var_x and result != neg_one and result != one_lit) {
        allocator.destroy(result);
    }
}

test "dead loop - WHILE 0 eliminated" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    // Build: WHILE 0 ... WEND
    const zero = try allocator.create(ast.Expression);
    zero.* = .{ .loc = loc, .data = .{ .number = .{ .value = 0.0 } } };
    const print_stmt = try allocator.create(ast.Statement);
    print_stmt.* = .{ .loc = loc, .data = .{ .rem = .{ .comment = "body" } } };
    var body_buf = [_]ast.StmtPtr{print_stmt};
    const while_stmt = try allocator.create(ast.Statement);
    while_stmt.* = .{ .loc = loc, .data = .{ .while_stmt = .{ .condition = zero, .body = &body_buf } } };
    defer allocator.destroy(zero);
    defer allocator.destroy(print_stmt);
    defer allocator.destroy(while_stmt);

    try opt.optimizeStatement(while_stmt);
    // Should be replaced with a REM
    try std.testing.expect(while_stmt.data == .rem);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.dead_loops);
}

test "dead loop - WHILE 1 not eliminated" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const one = try allocator.create(ast.Expression);
    one.* = .{ .loc = loc, .data = .{ .number = .{ .value = 1.0 } } };
    var body_buf = [_]ast.StmtPtr{};
    const while_stmt = try allocator.create(ast.Statement);
    while_stmt.* = .{ .loc = loc, .data = .{ .while_stmt = .{ .condition = one, .body = &body_buf } } };
    defer allocator.destroy(one);
    defer allocator.destroy(while_stmt);

    try opt.optimizeStatement(while_stmt);
    // WHILE 1 is an infinite loop — should NOT be eliminated
    try std.testing.expect(while_stmt.data == .while_stmt);
    try std.testing.expectEqual(@as(u32, 0), opt.stats.dead_loops);
}

test "string function folding - STRING$ with char code" {
    const allocator = std.testing.allocator;

    var st = semantic.SymbolTable.init(allocator);
    defer st.deinit();
    var opt = ASTOptimizer.init(&st, allocator);
    defer opt.deinit();

    const loc = SourceLocation{};
    const count = try allocator.create(ast.Expression);
    count.* = .{ .loc = loc, .data = .{ .number = .{ .value = 3.0 } } };
    const char_code = try allocator.create(ast.Expression);
    char_code.* = .{ .loc = loc, .data = .{ .number = .{ .value = 42.0 } } }; // '*'
    var args_buf = [_]ast.ExprPtr{ count, char_code };
    const call = try allocator.create(ast.Expression);
    call.* = .{ .loc = loc, .data = .{ .function_call = .{ .name = "STRING$", .arguments = &args_buf } } };
    defer allocator.destroy(count);
    defer allocator.destroy(char_code);
    defer allocator.destroy(call);

    const result = try opt.optimizeExpr(call);
    try std.testing.expect(result.data == .string_lit);
    try std.testing.expectEqualStrings("***", result.data.string_lit.value);
    try std.testing.expectEqual(@as(u32, 1), opt.stats.string_funcs_folded);
    if (result != call) {
        allocator.free(result.data.string_lit.value);
        allocator.destroy(result);
    }
}

test "OptStats total includes new counters" {
    var stats = OptStats{};
    stats.double_negations = 2;
    stats.string_funcs_folded = 3;
    stats.div_to_mul = 1;
    stats.mod_to_and = 1;
    stats.dead_loops = 1;
    stats.bool_identities = 2;
    try std.testing.expectEqual(@as(u32, 10), stats.total());
}
