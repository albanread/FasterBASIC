//! Control Flow Graph (CFG) for the FasterBASIC compiler.
//!
//! This module constructs and analyzes a control flow graph from the AST,
//! providing a modern IR-level representation that can drive code generation,
//! optimization passes, and static analysis.
//!
//! Architecture:
//! - `BasicBlock`: A maximal sequence of statements with single entry, single exit.
//! - `Edge`: A typed directed edge between basic blocks.
//! - `CFG`: The complete control flow graph for a function or program body.
//! - `CFGBuilder`: Constructs a CFG from a slice of AST statements.
//! - Analysis: Reachability, loop detection, dead-code identification.
//! - Dump: Human-readable CFG output for `--trace-cfg`.
//!
//! Design principles:
//! - Basic blocks hold *references* to AST statements (zero-copy).
//! - Edges carry semantic type information (fallthrough, branch, jump, etc.).
//! - Two-pass construction handles forward GOTO/GOSUB targets.
//! - Structured control flow (IF, FOR, WHILE, DO, CASE, TRY) maps cleanly
//!   to diamond/loop patterns in the graph.
//! - Unstructured control flow (GOTO, GOSUB, ON GOTO) is supported via
//!   label/line-number resolution with fixup.
//! - Each function/sub body gets its own CFG; the main program body gets one too.
//! - The CFG is the ideal input for a code generator: iterate blocks in
//!   reverse-postorder, emit instructions, and wire up branches.

const std = @import("std");
const ast = @import("ast.zig");
const token = @import("token.zig");
const SourceLocation = token.SourceLocation;

// ═══════════════════════════════════════════════════════════════════════════
// Edge — Typed directed edge between basic blocks
// ═══════════════════════════════════════════════════════════════════════════

/// The semantic kind of a control-flow edge.
pub const EdgeKind = enum {
    /// Sequential fall-through to the next block.
    fallthrough,
    /// Conditional branch taken when condition is true.
    branch_true,
    /// Conditional branch taken when condition is false.
    branch_false,
    /// Unconditional jump (GOTO, end of loop body, etc.).
    jump,
    /// Back-edge to a loop header (FOR, WHILE, DO, REPEAT).
    back_edge,
    /// Edge to a loop exit block (EXIT FOR, EXIT WHILE, etc.).
    loop_exit,
    /// Edge from CASE/WHEN match to body.
    case_match,
    /// Edge from CASE/WHEN mismatch to next case.
    case_next,
    /// Edge to exception handler (TRY → CATCH).
    exception,
    /// Edge from TRY/CATCH/FINALLY to the block after the handler.
    finally,
    /// GOSUB call edge (saves return address).
    gosub_call,
    /// RETURN from GOSUB.
    gosub_return,
    /// Edge to function exit / program END.
    exit,
    /// ON GOTO / ON GOSUB computed branch.
    computed_branch,
};

/// A directed edge from one basic block to another.
pub const Edge = struct {
    /// Source block index.
    from: u32,
    /// Destination block index.
    to: u32,
    /// Semantic kind of this edge.
    kind: EdgeKind,
    /// Optional label for debugging/printing (e.g., "i <= 10", "CASE 1").
    label: []const u8 = "",
};

// ═══════════════════════════════════════════════════════════════════════════
// BasicBlock — A maximal straight-line sequence of statements
// ═══════════════════════════════════════════════════════════════════════════

/// The kind of a basic block, indicating its structural role.
pub const BlockKind = enum {
    /// Program/function entry point.
    entry,
    /// Program/function exit point (may be synthetic/empty).
    exit_block,
    /// Normal code block.
    normal,
    /// Loop header (condition check for FOR, WHILE, DO-pre).
    loop_header,
    /// Loop body entry.
    loop_body,
    /// Loop increment (FOR step).
    loop_increment,
    /// Loop exit (block after the loop).
    loop_exit,
    /// IF-THEN block.
    if_then,
    /// ELSEIF block.
    if_elseif,
    /// ELSE block.
    if_else,
    /// Merge point after IF/ELSE or CASE.
    merge,
    /// CASE/WHEN test block.
    case_test,
    /// CASE/WHEN body block.
    case_body,
    /// CASE OTHERWISE/ELSE body.
    case_otherwise,
    /// TRY body.
    try_body,
    /// CATCH handler.
    catch_handler,
    /// FINALLY handler.
    finally_handler,
    /// GOSUB target (label block that can be returned from).
    gosub_target,
    /// Label target (for GOTO).
    label_target,
    /// Synthetic/empty block used for graph structure.
    synthetic,
};

/// A basic block in the control flow graph.
pub const BasicBlock = struct {
    /// Unique index of this block within its CFG.
    index: u32,
    /// Semantic kind of this block.
    kind: BlockKind,
    /// Human-readable name for debugging (e.g., "entry", "for_cond_0").
    name: []const u8 = "",
    /// Statements in this block (references into the AST — not owned).
    statements: std.ArrayList(*const ast.Statement) = .empty,
    /// Indices of predecessor blocks.
    predecessors: std.ArrayList(u32) = .empty,
    /// Indices of successor blocks.
    successors: std.ArrayList(u32) = .empty,
    /// Source location of the first statement (for diagnostics).
    loc: SourceLocation = .{},

    /// If this block is a loop header, the index of the corresponding exit block.
    loop_exit_block: ?u32 = null,
    /// If this block is inside a loop, the index of the loop header.
    loop_header_block: ?u32 = null,
    /// If this block is a conditional branch, the condition expression.
    branch_condition: ?*const ast.Expression = null,
    /// GOTO/label name associated with this block (if any).
    label_name: []const u8 = "",
    /// Line number associated with this block (for line-number GOTOs).
    line_number: i32 = 0,

    /// Whether this block has been visited during analysis.
    visited: bool = false,
    /// Whether this block is reachable from the entry.
    reachable: bool = false,
    /// Reverse-postorder number (set during RPO traversal).
    rpo_number: i32 = -1,
    /// Depth in the dominator tree (set during dominance analysis).
    dom_depth: i32 = -1,
    /// Immediate dominator block index.
    idom: ?u32 = null,

    pub fn deinit(self: *BasicBlock, allocator: std.mem.Allocator) void {
        self.statements.deinit(allocator);
        self.predecessors.deinit(allocator);
        self.successors.deinit(allocator);
    }

    /// Add a statement to this block.
    pub fn addStatement(self: *BasicBlock, allocator: std.mem.Allocator, stmt: *const ast.Statement) !void {
        try self.statements.append(allocator, stmt);
        if (self.statements.items.len == 1) {
            self.loc = stmt.loc;
        }
    }

    /// Whether this block is empty (no statements).
    pub fn isEmpty(self: *const BasicBlock) bool {
        return self.statements.items.len == 0;
    }

    /// Whether this block ends with a terminator (return, goto, end, exit).
    pub fn hasTerminator(self: *const BasicBlock) bool {
        if (self.statements.items.len == 0) return false;
        const last = self.statements.items[self.statements.items.len - 1];
        return switch (last.data) {
            .goto_stmt, .return_stmt, .end_stmt, .exit_stmt => true,
            else => false,
        };
    }

    /// Whether this block is a loop header.
    pub fn isLoopHeader(self: *const BasicBlock) bool {
        return self.kind == .loop_header;
    }

    /// Whether this block is the entry block.
    pub fn isEntry(self: *const BasicBlock) bool {
        return self.kind == .entry;
    }

    /// Whether this block is the exit block.
    pub fn isExit(self: *const BasicBlock) bool {
        return self.kind == .exit_block;
    }

    /// Number of successors.
    pub fn numSuccessors(self: *const BasicBlock) usize {
        return self.successors.items.len;
    }

    /// Number of predecessors.
    pub fn numPredecessors(self: *const BasicBlock) usize {
        return self.predecessors.items.len;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// LoopInfo — Information about a loop in the CFG
// ═══════════════════════════════════════════════════════════════════════════

/// Describes a natural loop found in the CFG.
pub const LoopInfo = struct {
    /// The loop header block (dominates all other blocks in the loop).
    header: u32,
    /// The loop exit block (first block after the loop).
    exit_block: u32,
    /// All blocks that are part of this loop body.
    body_blocks: std.ArrayList(u32) = .empty,
    /// Back-edge sources (blocks that jump back to the header).
    back_edge_sources: std.ArrayList(u32) = .empty,
    /// Nesting depth (0 = outermost loop).
    depth: u32 = 0,
    /// Parent loop header index (for nested loops).
    parent: ?u32 = null,

    pub fn deinit(self: *LoopInfo, allocator: std.mem.Allocator) void {
        self.body_blocks.deinit(allocator);
        self.back_edge_sources.deinit(allocator);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// CFG — The complete Control Flow Graph
// ═══════════════════════════════════════════════════════════════════════════

/// A control flow graph for a function body or the main program.
pub const CFG = struct {
    /// All basic blocks, indexed by their `index` field.
    blocks: std.ArrayList(BasicBlock) = .empty,
    /// All edges in the graph.
    edges: std.ArrayList(Edge) = .empty,
    /// Index of the entry block (always 0).
    entry: u32 = 0,
    /// Index of the exit block.
    exit: u32 = 0,
    /// Detected loops.
    loops: std.ArrayList(LoopInfo) = .empty,
    /// Name of the function/sub this CFG belongs to ("main" for program body).
    function_name: []const u8 = "main",
    /// Blocks in reverse-postorder (computed by analysis).
    rpo_order: std.ArrayList(u32) = .empty,
    /// Whether analysis has been run.
    analyzed: bool = false,
    /// Number of unreachable blocks found.
    unreachable_count: u32 = 0,

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) CFG {
        return .{
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *CFG) void {
        for (self.blocks.items) |*block| {
            block.deinit(self.allocator);
        }
        self.blocks.deinit(self.allocator);
        self.edges.deinit(self.allocator);
        for (self.loops.items) |*loop_info| {
            loop_info.deinit(self.allocator);
        }
        self.loops.deinit(self.allocator);
        self.rpo_order.deinit(self.allocator);
    }

    /// Create a new basic block and return its index.
    pub fn newBlock(self: *CFG, kind: BlockKind) !u32 {
        const index: u32 = @intCast(self.blocks.items.len);
        const block = BasicBlock{
            .index = index,
            .kind = kind,
            .name = "",
        };
        try self.blocks.append(self.allocator, block);
        return index;
    }

    /// Create a new basic block with a specific name.
    pub fn newNamedBlock(self: *CFG, kind: BlockKind, name: []const u8) !u32 {
        const index: u32 = @intCast(self.blocks.items.len);
        const block = BasicBlock{
            .index = index,
            .kind = kind,
            .name = name,
        };
        try self.blocks.append(self.allocator, block);
        return index;
    }

    /// Get a block by index.
    pub fn getBlock(self: *CFG, index: u32) *BasicBlock {
        return &self.blocks.items[index];
    }

    /// Get a block by index (const).
    pub fn getBlockConst(self: *const CFG, index: u32) *const BasicBlock {
        return &self.blocks.items[index];
    }

    /// Add a directed edge between two blocks.
    pub fn addEdge(self: *CFG, from: u32, to: u32, kind: EdgeKind) !void {
        // Avoid duplicate edges
        for (self.edges.items) |e| {
            if (e.from == from and e.to == to and e.kind == kind) return;
        }
        try self.edges.append(self.allocator, .{ .from = from, .to = to, .kind = kind });
        try self.blocks.items[from].successors.append(self.allocator, to);
        try self.blocks.items[to].predecessors.append(self.allocator, from);
    }

    /// Add a directed edge with a label.
    pub fn addLabeledEdge(self: *CFG, from: u32, to: u32, kind: EdgeKind, label: []const u8) !void {
        for (self.edges.items) |e| {
            if (e.from == from and e.to == to and e.kind == kind) return;
        }
        try self.edges.append(self.allocator, .{ .from = from, .to = to, .kind = kind, .label = label });
        try self.blocks.items[from].successors.append(self.allocator, to);
        try self.blocks.items[to].predecessors.append(self.allocator, from);
    }

    /// Get all edges from a specific block.
    pub fn edgesFrom(self: *const CFG, block_index: u32) []const Edge {
        // Return slice of matching edges (caller must iterate)
        _ = block_index;
        return self.edges.items;
    }

    /// Find the edge between two specific blocks.
    pub fn findEdge(self: *const CFG, from: u32, to: u32) ?*const Edge {
        for (self.edges.items) |*e| {
            if (e.from == from and e.to == to) return e;
        }
        return null;
    }

    /// Number of blocks.
    pub fn numBlocks(self: *const CFG) usize {
        return self.blocks.items.len;
    }

    /// Number of edges.
    pub fn numEdges(self: *const CFG) usize {
        return self.edges.items.len;
    }

    // ── Analysis ────────────────────────────────────────────────────────

    /// Run all analysis passes: reachability, RPO, loop detection.
    pub fn analyze(self: *CFG) !void {
        try self.computeReachability();
        try self.computeReversePostorder();
        try self.detectLoops();
        self.analyzed = true;
    }

    /// Mark all blocks reachable from the entry via DFS.
    pub fn computeReachability(self: *CFG) !void {
        // Reset
        for (self.blocks.items) |*block| {
            block.reachable = false;
            block.visited = false;
        }
        self.unreachable_count = 0;

        // DFS from entry
        var stack: std.ArrayList(u32) = .empty;
        defer stack.deinit(self.allocator);
        try stack.append(self.allocator, self.entry);

        while (stack.items.len > 0) {
            const idx = stack.pop().?;
            if (self.blocks.items[idx].visited) continue;
            self.blocks.items[idx].visited = true;
            self.blocks.items[idx].reachable = true;

            for (self.blocks.items[idx].successors.items) |succ| {
                if (!self.blocks.items[succ].visited) {
                    try stack.append(self.allocator, succ);
                }
            }
        }

        // Count unreachable
        for (self.blocks.items) |block| {
            if (!block.reachable) self.unreachable_count += 1;
        }
    }

    /// Compute reverse-postorder numbering via iterative DFS.
    pub fn computeReversePostorder(self: *CFG) !void {
        self.rpo_order.clearRetainingCapacity();

        const num_blocks = self.blocks.items.len;
        if (num_blocks == 0) return;

        // Reset visited flags
        for (self.blocks.items) |*block| {
            block.visited = false;
            block.rpo_number = -1;
        }

        // Iterative post-order DFS using an explicit stack.
        // Each stack frame is (block_index, child_cursor).
        const Frame = struct { block: u32, cursor: usize };
        var stack: std.ArrayList(Frame) = .empty;
        defer stack.deinit(self.allocator);

        var postorder: std.ArrayList(u32) = .empty;
        defer postorder.deinit(self.allocator);

        self.blocks.items[self.entry].visited = true;
        try stack.append(self.allocator, .{ .block = self.entry, .cursor = 0 });

        while (stack.items.len > 0) {
            const frame = &stack.items[stack.items.len - 1];
            const succs = self.blocks.items[frame.block].successors.items;

            if (frame.cursor < succs.len) {
                const succ = succs[frame.cursor];
                frame.cursor += 1;
                if (!self.blocks.items[succ].visited) {
                    self.blocks.items[succ].visited = true;
                    try stack.append(self.allocator, .{ .block = succ, .cursor = 0 });
                }
            } else {
                // All children processed — this is the post-order visit.
                try postorder.append(self.allocator, frame.block);
                _ = stack.pop();
            }
        }

        // Reverse the postorder to get reverse-postorder.
        var rpo_num: i32 = 0;
        var i: usize = postorder.items.len;
        while (i > 0) {
            i -= 1;
            const idx = postorder.items[i];
            self.blocks.items[idx].rpo_number = rpo_num;
            try self.rpo_order.append(self.allocator, idx);
            rpo_num += 1;
        }
    }

    /// Detect natural loops by finding back-edges.
    /// A back-edge is an edge from a block to a block with a lower or equal RPO number.
    pub fn detectLoops(self: *CFG) !void {
        // Clear existing loop info
        for (self.loops.items) |*li| {
            li.deinit(self.allocator);
        }
        self.loops.clearRetainingCapacity();

        for (self.edges.items) |edge| {
            const from_block = self.blocks.items[edge.from];
            const to_block = self.blocks.items[edge.to];

            // A back-edge: target has RPO number <= source (or is explicitly a back_edge kind).
            const is_back = (edge.kind == .back_edge) or
                (from_block.rpo_number >= 0 and to_block.rpo_number >= 0 and
                    to_block.rpo_number <= from_block.rpo_number);

            if (is_back) {
                // The target of the back-edge is the loop header.
                const header = edge.to;

                // Check if we already have a loop for this header.
                var existing_loop: ?*LoopInfo = null;
                for (self.loops.items) |*li| {
                    if (li.header == header) {
                        existing_loop = li;
                        break;
                    }
                }

                if (existing_loop) |li| {
                    try li.back_edge_sources.append(self.allocator, edge.from);
                } else {
                    // Find the exit block for this loop header.
                    const exit_blk = self.blocks.items[header].loop_exit_block orelse self.exit;
                    var li = LoopInfo{
                        .header = header,
                        .exit_block = exit_blk,
                    };
                    try li.back_edge_sources.append(self.allocator, edge.from);

                    // Collect all blocks in the loop body via reverse DFS from back-edge source.
                    try self.collectLoopBody(&li);
                    try self.loops.append(self.allocator, li);
                }
            }
        }

        // Compute nesting depth
        for (self.loops.items, 0..) |*outer, oi| {
            for (self.loops.items, 0..) |*inner, ii| {
                if (oi == ii) continue;
                if (self.loopContainsBlock(outer, inner.header) and !self.loopContainsBlock(inner, outer.header)) {
                    inner.parent = @intCast(oi);
                    inner.depth = outer.depth + 1;
                }
            }
        }
    }

    fn collectLoopBody(self: *CFG, li: *LoopInfo) error{OutOfMemory}!void {
        // Start from back-edge sources and walk backwards to the header.
        var worklist: std.ArrayList(u32) = .empty;
        defer worklist.deinit(self.allocator);

        var in_loop = std.AutoHashMap(u32, void).init(self.allocator);
        defer in_loop.deinit();

        try in_loop.put(li.header, {});
        try li.body_blocks.append(self.allocator, li.header);

        for (li.back_edge_sources.items) |src| {
            if (!in_loop.contains(src)) {
                try in_loop.put(src, {});
                try worklist.append(self.allocator, src);
                try li.body_blocks.append(self.allocator, src);
            }
        }

        while (worklist.items.len > 0) {
            const block_idx = worklist.pop().?;
            for (self.blocks.items[block_idx].predecessors.items) |pred| {
                if (!in_loop.contains(pred)) {
                    try in_loop.put(pred, {});
                    try worklist.append(self.allocator, pred);
                    try li.body_blocks.append(self.allocator, pred);
                }
            }
        }
    }

    fn loopContainsBlock(self: *const CFG, li: *const LoopInfo, block_idx: u32) bool {
        _ = self;
        for (li.body_blocks.items) |b| {
            if (b == block_idx) return true;
        }
        return false;
    }

    // ── Queries ─────────────────────────────────────────────────────────

    /// Get all unreachable blocks. Caller must pass the allocator that owns `out`.
    pub fn getUnreachableBlocks(self: *const CFG, out: *std.ArrayList(u32), allocator: std.mem.Allocator) !void {
        for (self.blocks.items) |block| {
            if (!block.reachable and block.index != self.exit) {
                try out.append(allocator, block.index);
            }
        }
    }

    /// Check if a block is inside any loop.
    pub fn isInLoop(self: *const CFG, block_idx: u32) bool {
        for (self.loops.items) |li| {
            if (self.loopContainsBlock(&li, block_idx)) return true;
        }
        return false;
    }

    /// Get the loop that contains a block (innermost if nested).
    pub fn getInnermostLoop(self: *const CFG, block_idx: u32) ?*const LoopInfo {
        var best: ?*const LoopInfo = null;
        var best_depth: u32 = 0;
        for (self.loops.items) |*li| {
            if (self.loopContainsBlock(li, block_idx)) {
                if (best == null or li.depth > best_depth) {
                    best = li;
                    best_depth = li.depth;
                }
            }
        }
        return best;
    }

    /// Iterate blocks in reverse-postorder (ideal for forward dataflow).
    pub fn iterRPO(self: *const CFG) []const u32 {
        return self.rpo_order.items;
    }

    // ── Dump / Pretty-print ─────────────────────────────────────────────

    /// Dump the CFG in a human-readable format.
    pub fn dump(self: *const CFG, writer: anytype) void {
        writer.print("\n╔══════════════════════════════════════════════════════════════╗\n", .{}) catch {};
        writer.print("║  CFG: {s} ({d} blocks, {d} edges", .{
            self.function_name,
            self.numBlocks(),
            self.numEdges(),
        }) catch {};
        if (self.analyzed) {
            writer.print(", {d} loops, {d} unreachable", .{
                self.loops.items.len,
                self.unreachable_count,
            }) catch {};
        }
        writer.print(")\n", .{}) catch {};
        writer.print("╚══════════════════════════════════════════════════════════════╝\n\n", .{}) catch {};

        // Blocks
        for (self.blocks.items) |block| {
            self.dumpBlock(&block, writer);
        }

        // Edges summary
        writer.print("── Edges ──────────────────────────────────────────────────────\n", .{}) catch {};
        for (self.edges.items) |edge| {
            const from_name = if (edge.from < self.blocks.items.len) blk: {
                const b = self.blocks.items[edge.from];
                break :blk if (b.name.len > 0) b.name else kindToStaticName(b.kind);
            } else "?";
            const to_name = if (edge.to < self.blocks.items.len) blk: {
                const b = self.blocks.items[edge.to];
                break :blk if (b.name.len > 0) b.name else kindToStaticName(b.kind);
            } else "?";
            writer.print("  BB{d}({s}) ──[{s}]──▸ BB{d}({s})", .{
                edge.from,           from_name,
                @tagName(edge.kind), edge.to,
                to_name,
            }) catch {};
            if (edge.label.len > 0) {
                writer.print("  \"{s}\"", .{edge.label}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }

        // Loops
        if (self.loops.items.len > 0) {
            writer.print("\n── Loops ──────────────────────────────────────────────────────\n", .{}) catch {};
            for (self.loops.items, 0..) |li, i| {
                writer.print("  Loop {d}: header=BB{d} exit=BB{d} depth={d} blocks=[", .{
                    i, li.header, li.exit_block, li.depth,
                }) catch {};
                for (li.body_blocks.items, 0..) |b, j| {
                    if (j > 0) writer.print(",", .{}) catch {};
                    writer.print("{d}", .{b}) catch {};
                }
                writer.print("] back_edges=[", .{}) catch {};
                for (li.back_edge_sources.items, 0..) |b, j| {
                    if (j > 0) writer.print(",", .{}) catch {};
                    writer.print("{d}", .{b}) catch {};
                }
                writer.print("]\n", .{}) catch {};
            }
        }

        // RPO
        if (self.rpo_order.items.len > 0) {
            writer.print("\n── Reverse Postorder ──────────────────────────────────────────\n", .{}) catch {};
            writer.print("  [", .{}) catch {};
            for (self.rpo_order.items, 0..) |idx, i| {
                if (i > 0) writer.print(", ", .{}) catch {};
                writer.print("BB{d}", .{idx}) catch {};
            }
            writer.print("]\n", .{}) catch {};
        }

        writer.print("\n", .{}) catch {};
    }

    fn dumpBlock(self: *const CFG, block: *const BasicBlock, writer: anytype) void {
        _ = self;
        const reachable_str: []const u8 = if (block.reachable) "" else " [UNREACHABLE]";
        const display_name = if (block.name.len > 0) block.name else kindToStaticName(block.kind);
        writer.print("┌─ BB{d}: {s} ({s}){s}", .{
            block.index,
            display_name,
            @tagName(block.kind),
            reachable_str,
        }) catch {};
        if (block.rpo_number >= 0) {
            writer.print("  RPO={d}", .{block.rpo_number}) catch {};
        }
        writer.print("\n", .{}) catch {};

        // Predecessors
        if (block.predecessors.items.len > 0) {
            writer.print("│  preds: ", .{}) catch {};
            for (block.predecessors.items, 0..) |p, i| {
                if (i > 0) writer.print(", ", .{}) catch {};
                writer.print("BB{d}", .{p}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }

        // Statements
        for (block.statements.items, 0..) |stmt, i| {
            writer.print("│  [{d}] {s}", .{ i, @tagName(std.meta.activeTag(stmt.data)) }) catch {};
            dumpStmtBrief(stmt, writer);
            writer.print("  ({d}:{d})\n", .{ stmt.loc.line, stmt.loc.column }) catch {};
        }
        if (block.statements.items.len == 0) {
            writer.print("│  (empty)\n", .{}) catch {};
        }

        // Branch condition
        if (block.branch_condition != null) {
            writer.print("│  branch: <condition expr>\n", .{}) catch {};
        }

        // Successors
        if (block.successors.items.len > 0) {
            writer.print("│  succs: ", .{}) catch {};
            for (block.successors.items, 0..) |s, i| {
                if (i > 0) writer.print(", ", .{}) catch {};
                writer.print("BB{d}", .{s}) catch {};
            }
            writer.print("\n", .{}) catch {};
        }

        writer.print("└──────────────────────────────────────────────────────────────\n", .{}) catch {};
    }

    /// Emit a Graphviz DOT representation for visualization.
    pub fn dumpDot(self: *const CFG, writer: anytype) void {
        writer.print("digraph CFG_{s} {{\n", .{self.function_name}) catch {};
        writer.print("  rankdir=TB;\n", .{}) catch {};
        writer.print("  node [shape=record, fontname=\"Courier\"];\n\n", .{}) catch {};

        for (self.blocks.items) |block| {
            const color: []const u8 = if (block.kind == .entry)
                "lightblue"
            else if (block.kind == .exit_block)
                "lightyellow"
            else if (block.isLoopHeader())
                "lightgreen"
            else if (!block.reachable)
                "lightgray"
            else
                "white";

            const dot_name = if (block.name.len > 0) block.name else kindToStaticName(block.kind);
            writer.print("  BB{d} [label=\"BB{d}: {s}\\n{s}\\n{d} stmts\", style=filled, fillcolor={s}];\n", .{
                block.index,
                block.index,
                dot_name,
                @tagName(block.kind),
                block.statements.items.len,
                color,
            }) catch {};
        }

        writer.print("\n", .{}) catch {};

        for (self.edges.items) |edge| {
            const style: []const u8 = switch (edge.kind) {
                .back_edge => "style=dashed, color=red",
                .branch_true => "color=green",
                .branch_false => "color=red",
                .exception => "style=dotted, color=purple",
                .exit => "color=gray",
                else => "",
            };
            writer.print("  BB{d} -> BB{d} [label=\"{s}\", {s}];\n", .{
                edge.from, edge.to, @tagName(edge.kind), style,
            }) catch {};
        }

        writer.print("}}\n", .{}) catch {};
    }
};

fn dumpStmtBrief(stmt: *const ast.Statement, writer: anytype) void {
    switch (stmt.data) {
        .print => |pr| writer.print(" PRINT ({d} items)", .{pr.items.len}) catch {},
        .let => |lt| {
            writer.print(" LET {s}", .{lt.variable}) catch {};
        },
        .if_stmt => writer.print(" IF", .{}) catch {},
        .for_stmt => |fs| writer.print(" FOR {s}", .{fs.variable}) catch {},
        .while_stmt => writer.print(" WHILE", .{}) catch {},
        .do_stmt => writer.print(" DO", .{}) catch {},
        .repeat_stmt => writer.print(" REPEAT", .{}) catch {},
        .case_stmt => writer.print(" SELECT CASE", .{}) catch {},
        .goto_stmt => |gt| {
            if (gt.is_label) {
                writer.print(" GOTO {s}", .{gt.label}) catch {};
            } else {
                writer.print(" GOTO {d}", .{gt.line_number}) catch {};
            }
        },
        .gosub => |gs| {
            if (gs.is_label) {
                writer.print(" GOSUB {s}", .{gs.label}) catch {};
            } else {
                writer.print(" GOSUB {d}", .{gs.line_number}) catch {};
            }
        },
        .return_stmt => writer.print(" RETURN", .{}) catch {},
        .end_stmt => writer.print(" END", .{}) catch {},
        .exit_stmt => |es| writer.print(" EXIT {s}", .{@tagName(es.exit_type)}) catch {},
        .label => |lbl| writer.print(" LABEL {s}", .{lbl.label_name}) catch {},
        .call => |cs| writer.print(" CALL {s}", .{cs.sub_name}) catch {},
        .function => |f| writer.print(" FUNCTION {s}", .{f.function_name}) catch {},
        .sub => |s| writer.print(" SUB {s}", .{s.sub_name}) catch {},
        .dim => writer.print(" DIM", .{}) catch {},
        .try_catch => writer.print(" TRY", .{}) catch {},
        .throw_stmt => writer.print(" THROW", .{}) catch {},
        .rem => writer.print(" REM", .{}) catch {},
        else => {},
    }
}

/// Return a static string name for a block kind (no allocation needed).
/// The block index is available separately via `block.index`.
fn kindToStaticName(kind: BlockKind) []const u8 {
    return switch (kind) {
        .entry => "entry",
        .exit_block => "exit",
        .normal => "bb",
        .loop_header => "loop_hdr",
        .loop_body => "loop_body",
        .loop_increment => "loop_inc",
        .loop_exit => "loop_exit",
        .if_then => "if_then",
        .if_elseif => "if_elseif",
        .if_else => "if_else",
        .merge => "merge",
        .case_test => "case_test",
        .case_body => "case_body",
        .case_otherwise => "case_else",
        .try_body => "try",
        .catch_handler => "catch",
        .finally_handler => "finally",
        .gosub_target => "gosub",
        .label_target => "label",
        .synthetic => "syn",
    };
}

// ═══════════════════════════════════════════════════════════════════════════
// CFGBuilder — Constructs a CFG from AST statements
// ═══════════════════════════════════════════════════════════════════════════

/// Pending GOTO/GOSUB fixup: an edge that references a label or line number
/// not yet resolved to a block.
const PendingJump = struct {
    from_block: u32,
    target_label: []const u8,
    target_line: i32,
    is_label: bool,
    edge_kind: EdgeKind,
};

/// Context for tracking the current loop (for EXIT statements).
const LoopContext = struct {
    header_block: u32,
    exit_block: u32,
    increment_block: ?u32,
};

/// Builds a CFG from a slice of AST statements.
pub const CFGBuilder = struct {
    cfg: CFG,
    allocator: std.mem.Allocator,

    /// Current block being populated.
    current_block: u32 = 0,

    /// Map from label name → block index.
    label_map: std.StringHashMap(u32),
    /// Map from line number → block index.
    line_map: std.AutoHashMap(i32, u32),
    /// Pending jumps that need fixup after all labels are collected.
    pending_jumps: std.ArrayList(PendingJump) = .empty,

    /// Stack of active loop contexts (for EXIT).
    loop_stack: std.ArrayList(LoopContext) = .empty,

    /// Sub-CFGs for function/sub bodies.
    function_cfgs: std.StringHashMap(CFG),

    pub fn init(allocator: std.mem.Allocator) CFGBuilder {
        return .{
            .cfg = CFG.init(allocator),
            .allocator = allocator,
            .label_map = std.StringHashMap(u32).init(allocator),
            .line_map = std.AutoHashMap(i32, u32).init(allocator),
            .function_cfgs = std.StringHashMap(CFG).init(allocator),
        };
    }

    pub fn deinit(self: *CFGBuilder) void {
        self.cfg.deinit();
        self.label_map.deinit();
        self.line_map.deinit();
        self.pending_jumps.deinit(self.allocator);
        self.loop_stack.deinit(self.allocator);
        var it = self.function_cfgs.iterator();
        while (it.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.function_cfgs.deinit();
    }

    /// Build a CFG from the top-level program.
    pub fn buildFromProgram(self: *CFGBuilder, program: *const ast.Program) !*CFG {
        self.cfg.function_name = "main";

        // Create entry and exit blocks.
        const entry_blk = try self.cfg.newNamedBlock(.entry, "entry");
        self.cfg.entry = entry_blk;
        const exit_blk = try self.cfg.newNamedBlock(.exit_block, "exit");
        self.cfg.exit = exit_blk;

        self.current_block = entry_blk;

        // First pass: collect all labels and line numbers.
        for (program.lines) |line| {
            for (line.statements) |stmt| {
                switch (stmt.data) {
                    .label => |lbl| {
                        // Pre-register label so forward GOTOs can find it.
                        if (!self.label_map.contains(lbl.label_name)) {
                            const lbl_block = try self.cfg.newNamedBlock(.label_target, try std.fmt.allocPrint(self.allocator, "label_{s}", .{lbl.label_name}));
                            self.cfg.getBlock(lbl_block).label_name = lbl.label_name;
                            try self.label_map.put(lbl.label_name, lbl_block);
                        }
                    },
                    else => {},
                }
            }
        }

        // Second pass: build the CFG.
        for (program.lines) |line| {
            // Register line number mapping to current block.
            if (line.line_number > 0) {
                if (!self.line_map.contains(line.line_number)) {
                    try self.line_map.put(line.line_number, self.current_block);
                }
            }

            for (line.statements) |stmt| {
                try self.processStatement(stmt);
            }
        }

        // Ensure the last block connects to exit.
        if (self.current_block != exit_blk) {
            const last_block = self.cfg.getBlock(self.current_block);
            if (!last_block.hasTerminator()) {
                try self.cfg.addEdge(self.current_block, exit_blk, .fallthrough);
            }
        }

        // Fixup phase: resolve pending GOTO/GOSUB targets.
        try self.resolvePendingJumps();

        // Run analysis.
        try self.cfg.analyze();

        return &self.cfg;
    }

    /// Build a CFG from a function or sub body.
    pub fn buildFromBody(self: *CFGBuilder, statements: []const ast.StmtPtr, func_name: []const u8) !*CFG {
        self.cfg.function_name = func_name;

        const entry_blk = try self.cfg.newNamedBlock(.entry, try std.fmt.allocPrint(self.allocator, "{s}_entry", .{func_name}));
        self.cfg.entry = entry_blk;
        const exit_blk = try self.cfg.newNamedBlock(.exit_block, try std.fmt.allocPrint(self.allocator, "{s}_exit", .{func_name}));
        self.cfg.exit = exit_blk;

        self.current_block = entry_blk;

        // First pass: collect labels.
        for (statements) |stmt| {
            switch (stmt.data) {
                .label => |lbl| {
                    if (!self.label_map.contains(lbl.label_name)) {
                        const lbl_block = try self.cfg.newNamedBlock(.label_target, try std.fmt.allocPrint(self.allocator, "label_{s}", .{lbl.label_name}));
                        self.cfg.getBlock(lbl_block).label_name = lbl.label_name;
                        try self.label_map.put(lbl.label_name, lbl_block);
                    }
                },
                else => {},
            }
        }

        // Second pass: build.
        for (statements) |stmt| {
            try self.processStatement(stmt);
        }

        // Connect last block to exit.
        if (self.current_block != exit_blk) {
            const last_block = self.cfg.getBlock(self.current_block);
            if (!last_block.hasTerminator()) {
                try self.cfg.addEdge(self.current_block, exit_blk, .fallthrough);
            }
        }

        try self.resolvePendingJumps();
        try self.cfg.analyze();

        return &self.cfg;
    }

    // ── Statement Processing ────────────────────────────────────────────

    fn processStatement(self: *CFGBuilder, stmt: *const ast.Statement) error{OutOfMemory}!void {
        switch (stmt.data) {
            // ── Structured control flow ─────────────────────────────────
            .if_stmt => |ifs| try self.processIfStatement(stmt, &ifs),
            .for_stmt => |fs| try self.processForStatement(stmt, &fs),
            .while_stmt => |ws| try self.processWhileStatement(stmt, &ws),
            .do_stmt => |ds| try self.processDoStatement(stmt, &ds),
            .repeat_stmt => |rs| try self.processRepeatStatement(stmt, &rs),
            .case_stmt => |cs| try self.processCaseStatement(stmt, &cs),
            .try_catch => |tc| try self.processTryCatchStatement(stmt, &tc),

            // ── Unstructured control flow ───────────────────────────────
            .goto_stmt => |gt| try self.processGotoStatement(stmt, &gt),
            .gosub => |gs| try self.processGosubStatement(stmt, &gs),
            .on_goto => |og| try self.processOnGoto(stmt, &og),
            .on_gosub => |ogs| try self.processOnGosub(stmt, &ogs),
            .return_stmt => |rs| try self.processReturnStatement(stmt, &rs),
            .exit_stmt => |es| try self.processExitStatement(stmt, &es),
            .end_stmt => try self.processEndStatement(stmt),

            // ── Labels ─────────────────────────────────────────────────
            .label => |lbl| try self.processLabelStatement(stmt, &lbl),

            // ── Function/Sub definitions ───────────────────────────────
            .function => |func| try self.processFunctionDef(stmt, &func),
            .sub => |sub_def| try self.processSubDef(stmt, &sub_def),

            // ── Normal statements (no control flow) ────────────────────
            else => {
                try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
            },
        }
    }

    // ── IF / ELSEIF / ELSE ──────────────────────────────────────────────

    fn processIfStatement(self: *CFGBuilder, stmt: *const ast.Statement, ifs: *const ast.IfStmt) !void {
        // The IF condition is evaluated in the current block.
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
        self.cfg.getBlock(self.current_block).branch_condition = ifs.condition;

        const cond_block = self.current_block;
        const merge_block = try self.cfg.newBlock(.merge);

        // THEN block
        const then_block = try self.cfg.newBlock(.if_then);
        try self.cfg.addEdge(cond_block, then_block, .branch_true);

        self.current_block = then_block;
        for (ifs.then_statements) |s| {
            try self.processStatement(s);
        }
        if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
            try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
        }

        // ELSEIF chains
        var last_false_source = cond_block;
        for (ifs.elseif_clauses) |clause| {
            const elseif_cond_block = try self.cfg.newBlock(.if_elseif);
            try self.cfg.addEdge(last_false_source, elseif_cond_block, .branch_false);
            self.cfg.getBlock(elseif_cond_block).branch_condition = clause.condition;

            const elseif_body = try self.cfg.newBlock(.if_then);
            try self.cfg.addEdge(elseif_cond_block, elseif_body, .branch_true);

            self.current_block = elseif_body;
            for (clause.statements) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
            }

            last_false_source = elseif_cond_block;
        }

        // ELSE block
        if (ifs.else_statements.len > 0) {
            const else_block = try self.cfg.newBlock(.if_else);
            try self.cfg.addEdge(last_false_source, else_block, .branch_false);

            self.current_block = else_block;
            for (ifs.else_statements) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
            }
        } else {
            // No ELSE: false branch goes directly to merge.
            try self.cfg.addEdge(last_false_source, merge_block, .branch_false);
        }

        self.current_block = merge_block;
    }

    // ── FOR loop ────────────────────────────────────────────────────────

    fn processForStatement(self: *CFGBuilder, stmt: *const ast.Statement, fs: *const ast.ForStmt) !void {
        // Init block: initialize loop variable (stays in current block).
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        // Create loop structure blocks.
        const header = try self.cfg.newBlock(.loop_header);
        const body = try self.cfg.newBlock(.loop_body);
        const increment = try self.cfg.newBlock(.loop_increment);
        const exit_blk = try self.cfg.newBlock(.loop_exit);

        self.cfg.getBlock(header).branch_condition = fs.end_expr;
        self.cfg.getBlock(header).loop_exit_block = exit_blk;

        // Init → header
        try self.cfg.addEdge(self.current_block, header, .fallthrough);

        // Header → body (condition true) or exit (condition false)
        try self.cfg.addEdge(header, body, .branch_true);
        try self.cfg.addEdge(header, exit_blk, .branch_false);

        // Push loop context for EXIT FOR.
        try self.loop_stack.append(self.allocator, .{
            .header_block = header,
            .exit_block = exit_blk,
            .increment_block = increment,
        });

        // Process body statements.
        self.current_block = body;
        for (fs.body) |s| {
            try self.processStatement(s);
        }

        // Body → increment
        if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
            try self.cfg.addEdge(self.current_block, increment, .fallthrough);
        }

        // Increment → header (back edge)
        try self.cfg.addEdge(increment, header, .back_edge);

        // Pop loop context.
        _ = self.loop_stack.pop();

        self.current_block = exit_blk;
    }

    // ── WHILE loop ──────────────────────────────────────────────────────

    fn processWhileStatement(self: *CFGBuilder, stmt: *const ast.Statement, ws: *const ast.WhileStmt) !void {
        _ = stmt;

        const header = try self.cfg.newBlock(.loop_header);
        const body = try self.cfg.newBlock(.loop_body);
        const exit_blk = try self.cfg.newBlock(.loop_exit);

        self.cfg.getBlock(header).branch_condition = ws.condition;
        self.cfg.getBlock(header).loop_exit_block = exit_blk;

        // Current → header
        try self.cfg.addEdge(self.current_block, header, .fallthrough);

        // Header → body (true) or exit (false)
        try self.cfg.addEdge(header, body, .branch_true);
        try self.cfg.addEdge(header, exit_blk, .branch_false);

        try self.loop_stack.append(self.allocator, .{
            .header_block = header,
            .exit_block = exit_blk,
            .increment_block = null,
        });

        self.current_block = body;
        for (ws.body) |s| {
            try self.processStatement(s);
        }

        // Body end → header (back edge)
        if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
            try self.cfg.addEdge(self.current_block, header, .back_edge);
        }

        _ = self.loop_stack.pop();
        self.current_block = exit_blk;
    }

    // ── DO loop ─────────────────────────────────────────────────────────

    fn processDoStatement(self: *CFGBuilder, stmt: *const ast.Statement, ds: *const ast.DoStmt) !void {
        _ = stmt;

        const exit_blk = try self.cfg.newBlock(.loop_exit);

        if (ds.pre_condition) |pre_cond| {
            // DO WHILE/UNTIL ... LOOP
            const header = try self.cfg.newBlock(.loop_header);
            const body = try self.cfg.newBlock(.loop_body);

            self.cfg.getBlock(header).branch_condition = pre_cond;
            self.cfg.getBlock(header).loop_exit_block = exit_blk;

            try self.cfg.addEdge(self.current_block, header, .fallthrough);

            if (ds.pre_condition_type == .until_cond) {
                // UNTIL: enter body when condition is false
                try self.cfg.addEdge(header, body, .branch_false);
                try self.cfg.addEdge(header, exit_blk, .branch_true);
            } else {
                // WHILE: enter body when condition is true
                try self.cfg.addEdge(header, body, .branch_true);
                try self.cfg.addEdge(header, exit_blk, .branch_false);
            }

            try self.loop_stack.append(self.allocator, .{
                .header_block = header,
                .exit_block = exit_blk,
                .increment_block = null,
            });

            self.current_block = body;
            for (ds.body) |s| {
                try self.processStatement(s);
            }

            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, header, .back_edge);
            }

            _ = self.loop_stack.pop();
        } else if (ds.post_condition) |post_cond| {
            // DO ... LOOP WHILE/UNTIL
            const body = try self.cfg.newBlock(.loop_body);
            const cond_block = try self.cfg.newBlock(.loop_header);

            self.cfg.getBlock(cond_block).branch_condition = post_cond;
            self.cfg.getBlock(body).loop_exit_block = exit_blk;

            try self.cfg.addEdge(self.current_block, body, .fallthrough);

            try self.loop_stack.append(self.allocator, .{
                .header_block = body,
                .exit_block = exit_blk,
                .increment_block = null,
            });

            self.current_block = body;
            for (ds.body) |s| {
                try self.processStatement(s);
            }

            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, cond_block, .fallthrough);
            }

            if (ds.post_condition_type == .until_cond) {
                try self.cfg.addEdge(cond_block, exit_blk, .branch_true);
                try self.cfg.addEdge(cond_block, body, .back_edge);
            } else {
                try self.cfg.addEdge(cond_block, body, .back_edge);
                try self.cfg.addEdge(cond_block, exit_blk, .branch_false);
            }

            _ = self.loop_stack.pop();
        } else {
            // DO ... LOOP (infinite, needs EXIT DO)
            const body = try self.cfg.newBlock(.loop_body);

            self.cfg.getBlock(body).loop_exit_block = exit_blk;

            try self.cfg.addEdge(self.current_block, body, .fallthrough);

            try self.loop_stack.append(self.allocator, .{
                .header_block = body,
                .exit_block = exit_blk,
                .increment_block = null,
            });

            self.current_block = body;
            for (ds.body) |s| {
                try self.processStatement(s);
            }

            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, body, .back_edge);
            }

            _ = self.loop_stack.pop();
        }

        self.current_block = exit_blk;
    }

    // ── REPEAT / UNTIL ──────────────────────────────────────────────────

    fn processRepeatStatement(self: *CFGBuilder, stmt: *const ast.Statement, rs: *const ast.RepeatStmt) !void {
        _ = stmt;

        const body = try self.cfg.newBlock(.loop_body);
        const exit_blk = try self.cfg.newBlock(.loop_exit);

        self.cfg.getBlock(body).loop_exit_block = exit_blk;

        try self.cfg.addEdge(self.current_block, body, .fallthrough);

        try self.loop_stack.append(self.allocator, .{
            .header_block = body,
            .exit_block = exit_blk,
            .increment_block = null,
        });

        self.current_block = body;
        for (rs.body) |s| {
            try self.processStatement(s);
        }

        if (rs.condition) |cond| {
            // UNTIL condition: exit when true
            const cond_block = try self.cfg.newBlock(.loop_header);
            self.cfg.getBlock(cond_block).branch_condition = cond;

            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, cond_block, .fallthrough);
            }

            try self.cfg.addEdge(cond_block, exit_blk, .branch_true);
            try self.cfg.addEdge(cond_block, body, .back_edge);
        } else {
            // Infinite REPEAT (needs EXIT)
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, body, .back_edge);
            }
        }

        _ = self.loop_stack.pop();
        self.current_block = exit_blk;
    }

    // ── SELECT CASE ─────────────────────────────────────────────────────

    fn processCaseStatement(self: *CFGBuilder, stmt: *const ast.Statement, cs: *const ast.CaseStmt) !void {
        // The SELECT CASE expression is evaluated in the current block.
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
        const case_entry = self.current_block;
        const merge_block = try self.cfg.newBlock(.merge);

        var prev_test_block = case_entry;

        for (cs.when_clauses) |clause| {
            // Test block: compare selector with WHEN value(s)
            const test_block = try self.cfg.newBlock(.case_test);
            try self.cfg.addEdge(prev_test_block, test_block, if (prev_test_block == case_entry) .fallthrough else .case_next);

            if (clause.values.len > 0) {
                // The test block gets the comparison expression.
                self.cfg.getBlock(test_block).branch_condition = clause.values[0];
            }

            // Body block: statements for this WHEN
            const body_block = try self.cfg.newBlock(.case_body);
            try self.cfg.addEdge(test_block, body_block, .case_match);

            self.current_block = body_block;
            for (clause.statements) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
            }

            prev_test_block = test_block;
        }

        // OTHERWISE (CASE ELSE)
        if (cs.otherwise_statements.len > 0) {
            const otherwise_block = try self.cfg.newBlock(.case_otherwise);
            try self.cfg.addEdge(prev_test_block, otherwise_block, .case_next);

            self.current_block = otherwise_block;
            for (cs.otherwise_statements) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
            }
        } else {
            // No OTHERWISE: fall through from last test to merge.
            try self.cfg.addEdge(prev_test_block, merge_block, .case_next);
        }

        self.current_block = merge_block;
    }

    // ── TRY / CATCH / FINALLY ───────────────────────────────────────────

    fn processTryCatchStatement(self: *CFGBuilder, stmt: *const ast.Statement, tc: *const ast.TryCatchStmt) !void {
        _ = stmt;

        const merge_block = try self.cfg.newBlock(.merge);

        // TRY body
        const try_block = try self.cfg.newBlock(.try_body);
        try self.cfg.addEdge(self.current_block, try_block, .fallthrough);

        self.current_block = try_block;
        for (tc.try_block) |s| {
            try self.processStatement(s);
        }

        // Connect TRY end to FINALLY or merge.
        const try_end_block = self.current_block;

        // CATCH clauses
        for (tc.catch_clauses) |clause| {
            const catch_block = try self.cfg.newBlock(.catch_handler);
            // Exception edge from TRY body to CATCH
            try self.cfg.addEdge(try_block, catch_block, .exception);

            self.current_block = catch_block;
            for (clause.block) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                if (tc.has_finally) {
                    // Will be connected to FINALLY below.
                } else {
                    try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
                }
            }
        }

        // FINALLY block
        if (tc.has_finally) {
            const finally_block = try self.cfg.newBlock(.finally_handler);

            // TRY end → FINALLY
            if (!self.cfg.getBlock(try_end_block).hasTerminator()) {
                try self.cfg.addEdge(try_end_block, finally_block, .finally);
            }

            // Each CATCH end → FINALLY (walk back and find catch blocks)
            for (self.cfg.blocks.items) |block| {
                if (block.kind == .catch_handler and block.successors.items.len == 0) {
                    try self.cfg.addEdge(block.index, finally_block, .finally);
                }
            }

            self.current_block = finally_block;
            for (tc.finally_block) |s| {
                try self.processStatement(s);
            }
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, merge_block, .fallthrough);
            }
        } else {
            // No FINALLY: TRY end goes to merge.
            if (!self.cfg.getBlock(try_end_block).hasTerminator()) {
                try self.cfg.addEdge(try_end_block, merge_block, .fallthrough);
            }
        }

        self.current_block = merge_block;
    }

    // ── GOTO ────────────────────────────────────────────────────────────

    fn processGotoStatement(self: *CFGBuilder, stmt: *const ast.Statement, gt: *const ast.GotoStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        if (gt.is_label) {
            // Try to resolve immediately.
            if (self.label_map.get(gt.label)) |target_block| {
                try self.cfg.addEdge(self.current_block, target_block, .jump);
            } else {
                // Forward reference — defer to fixup.
                try self.pending_jumps.append(self.allocator, .{
                    .from_block = self.current_block,
                    .target_label = gt.label,
                    .target_line = 0,
                    .is_label = true,
                    .edge_kind = .jump,
                });
            }
        } else {
            // Line number GOTO.
            if (self.line_map.get(gt.line_number)) |target_block| {
                try self.cfg.addEdge(self.current_block, target_block, .jump);
            } else {
                try self.pending_jumps.append(self.allocator, .{
                    .from_block = self.current_block,
                    .target_label = "",
                    .target_line = gt.line_number,
                    .is_label = false,
                    .edge_kind = .jump,
                });
            }
        }

        // Start a new block after the GOTO (it's unreachable unless targeted).
        const next = try self.cfg.newBlock(.normal);
        self.current_block = next;
    }

    // ── GOSUB ───────────────────────────────────────────────────────────

    fn processGosubStatement(self: *CFGBuilder, stmt: *const ast.Statement, gs: *const ast.GosubStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        const return_block = try self.cfg.newBlock(.normal);

        if (gs.is_label) {
            if (self.label_map.get(gs.label)) |target_block| {
                try self.cfg.addEdge(self.current_block, target_block, .gosub_call);
                // The RETURN from the gosub will need to come back here.
                try self.cfg.addEdge(self.current_block, return_block, .gosub_return);
            } else {
                try self.pending_jumps.append(self.allocator, .{
                    .from_block = self.current_block,
                    .target_label = gs.label,
                    .target_line = 0,
                    .is_label = true,
                    .edge_kind = .gosub_call,
                });
                // Return edge.
                try self.cfg.addEdge(self.current_block, return_block, .gosub_return);
            }
        } else {
            if (self.line_map.get(gs.line_number)) |target_block| {
                try self.cfg.addEdge(self.current_block, target_block, .gosub_call);
                try self.cfg.addEdge(self.current_block, return_block, .gosub_return);
            } else {
                try self.pending_jumps.append(self.allocator, .{
                    .from_block = self.current_block,
                    .target_label = "",
                    .target_line = gs.line_number,
                    .is_label = false,
                    .edge_kind = .gosub_call,
                });
                try self.cfg.addEdge(self.current_block, return_block, .gosub_return);
            }
        }

        self.current_block = return_block;
    }

    // ── ON GOTO / ON GOSUB ──────────────────────────────────────────────

    fn processOnGoto(self: *CFGBuilder, stmt: *const ast.Statement, og: *const ast.OnGotoStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
        const from = self.current_block;

        for (og.labels, 0..) |label_str, i| {
            const is_label = if (i < og.is_label_list.len) og.is_label_list[i] else false;
            if (is_label) {
                if (self.label_map.get(label_str)) |target| {
                    try self.cfg.addEdge(from, target, .computed_branch);
                } else {
                    try self.pending_jumps.append(self.allocator, .{
                        .from_block = from,
                        .target_label = label_str,
                        .target_line = 0,
                        .is_label = true,
                        .edge_kind = .computed_branch,
                    });
                }
            } else {
                const line_num = if (i < og.line_numbers.len) og.line_numbers[i] else 0;
                if (self.line_map.get(line_num)) |target| {
                    try self.cfg.addEdge(from, target, .computed_branch);
                } else if (line_num != 0) {
                    try self.pending_jumps.append(self.allocator, .{
                        .from_block = from,
                        .target_label = "",
                        .target_line = line_num,
                        .is_label = false,
                        .edge_kind = .computed_branch,
                    });
                }
            }
        }

        // Fall-through if selector is out of range.
        const next = try self.cfg.newBlock(.normal);
        try self.cfg.addEdge(from, next, .fallthrough);
        self.current_block = next;
    }

    fn processOnGosub(self: *CFGBuilder, stmt: *const ast.Statement, ogs: *const ast.OnGosubStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
        const from = self.current_block;

        for (ogs.labels, 0..) |label_str, i| {
            const is_label = if (i < ogs.is_label_list.len) ogs.is_label_list[i] else false;
            if (is_label) {
                if (self.label_map.get(label_str)) |target| {
                    try self.cfg.addEdge(from, target, .gosub_call);
                } else {
                    try self.pending_jumps.append(self.allocator, .{
                        .from_block = from,
                        .target_label = label_str,
                        .target_line = 0,
                        .is_label = true,
                        .edge_kind = .gosub_call,
                    });
                }
            } else {
                const line_num = if (i < ogs.line_numbers.len) ogs.line_numbers[i] else 0;
                if (self.line_map.get(line_num)) |target| {
                    try self.cfg.addEdge(from, target, .gosub_call);
                } else if (line_num != 0) {
                    try self.pending_jumps.append(self.allocator, .{
                        .from_block = from,
                        .target_label = "",
                        .target_line = line_num,
                        .is_label = false,
                        .edge_kind = .gosub_call,
                    });
                }
            }
        }

        const next = try self.cfg.newBlock(.normal);
        try self.cfg.addEdge(from, next, .gosub_return);
        self.current_block = next;
    }

    // ── RETURN ──────────────────────────────────────────────────────────

    fn processReturnStatement(self: *CFGBuilder, stmt: *const ast.Statement, rs: *const ast.ReturnStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        if (rs.return_value != null) {
            // RETURN <value> — exits the function.
            try self.cfg.addEdge(self.current_block, self.cfg.exit, .exit);
        } else {
            // RETURN without value — could be GOSUB return or function return.
            try self.cfg.addEdge(self.current_block, self.cfg.exit, .exit);
        }

        // New block after RETURN (unreachable unless targeted).
        const next = try self.cfg.newBlock(.normal);
        self.current_block = next;
    }

    // ── EXIT ────────────────────────────────────────────────────────────

    fn processExitStatement(self: *CFGBuilder, stmt: *const ast.Statement, es: *const ast.ExitStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        switch (es.exit_type) {
            .for_loop, .do_loop, .while_loop, .repeat_loop => {
                // Jump to the exit block of the innermost matching loop.
                if (self.loop_stack.items.len > 0) {
                    const ctx = self.loop_stack.items[self.loop_stack.items.len - 1];
                    try self.cfg.addEdge(self.current_block, ctx.exit_block, .loop_exit);
                }
            },
            .function, .sub => {
                // Exit the function/sub entirely.
                try self.cfg.addEdge(self.current_block, self.cfg.exit, .exit);
            },
        }

        const next = try self.cfg.newBlock(.normal);
        self.current_block = next;
    }

    // ── END ─────────────────────────────────────────────────────────────

    fn processEndStatement(self: *CFGBuilder, stmt: *const ast.Statement) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
        try self.cfg.addEdge(self.current_block, self.cfg.exit, .exit);

        const next = try self.cfg.newBlock(.normal);
        self.current_block = next;
    }

    // ── LABEL ───────────────────────────────────────────────────────────

    fn processLabelStatement(self: *CFGBuilder, stmt: *const ast.Statement, lbl: *const ast.LabelStmt) !void {
        // A label starts a new basic block (it's a potential branch target).
        if (self.label_map.get(lbl.label_name)) |target_block| {
            // Connect current block to the label block (fallthrough).
            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, target_block, .fallthrough);
            }
            self.current_block = target_block;
        } else {
            // Label wasn't pre-registered (shouldn't happen, but handle gracefully).
            const lbl_block = try self.cfg.newNamedBlock(.label_target, try std.fmt.allocPrint(self.allocator, "label_{s}", .{lbl.label_name}));
            self.cfg.getBlock(lbl_block).label_name = lbl.label_name;
            try self.label_map.put(lbl.label_name, lbl_block);

            if (!self.cfg.getBlock(self.current_block).hasTerminator()) {
                try self.cfg.addEdge(self.current_block, lbl_block, .fallthrough);
            }
            self.current_block = lbl_block;
        }

        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);
    }

    // ── FUNCTION / SUB definitions ──────────────────────────────────────

    fn processFunctionDef(self: *CFGBuilder, stmt: *const ast.Statement, func: *const ast.FunctionStmt) !void {
        // Function definitions create separate CFGs — they're not part of
        // the main program's control flow.
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        var sub_builder = CFGBuilder.init(self.allocator);

        const sub_cfg = try sub_builder.buildFromBody(func.body, func.function_name);
        _ = sub_cfg;

        // Transfer ownership of the sub-CFG.
        try self.function_cfgs.put(func.function_name, sub_builder.cfg);
        // Prevent double-free: re-init the builder's cfg so deinit is safe.
        sub_builder.cfg = CFG.init(self.allocator);
        sub_builder.deinit();
    }

    fn processSubDef(self: *CFGBuilder, stmt: *const ast.Statement, sub_def: *const ast.SubStmt) !void {
        try self.cfg.getBlock(self.current_block).addStatement(self.allocator, stmt);

        var sub_builder = CFGBuilder.init(self.allocator);

        const sub_cfg = try sub_builder.buildFromBody(sub_def.body, sub_def.sub_name);
        _ = sub_cfg;

        try self.function_cfgs.put(sub_def.sub_name, sub_builder.cfg);
        sub_builder.cfg = CFG.init(self.allocator);
        sub_builder.deinit();
    }

    // ── Fixup phase ─────────────────────────────────────────────────────

    fn resolvePendingJumps(self: *CFGBuilder) !void {
        for (self.pending_jumps.items) |pj| {
            var target: ?u32 = null;

            if (pj.is_label) {
                target = self.label_map.get(pj.target_label);
            } else {
                target = self.line_map.get(pj.target_line);
            }

            if (target) |t| {
                try self.cfg.addEdge(pj.from_block, t, pj.edge_kind);
            } else {
                // Unresolved target — create a synthetic error block.
                const err_block = try self.cfg.newNamedBlock(.synthetic, "unresolved_target");
                try self.cfg.addEdge(pj.from_block, err_block, pj.edge_kind);
                try self.cfg.addEdge(err_block, self.cfg.exit, .exit);
            }
        }
        self.pending_jumps.clearRetainingCapacity();
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Convenience: build a CFG from a program in one call
// ═══════════════════════════════════════════════════════════════════════════

/// Build a CFG for the main program body. Caller owns the returned CFGBuilder.
pub fn buildProgramCFG(program: *const ast.Program, allocator: std.mem.Allocator) !CFGBuilder {
    var builder = CFGBuilder.init(allocator);
    _ = try builder.buildFromProgram(program);
    return builder;
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test "CFG - empty program" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, exit_blk, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 2), cfg.numBlocks());
    try std.testing.expectEqual(@as(usize, 1), cfg.numEdges());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);
    try std.testing.expect(cfg.getBlock(entry_blk).reachable);
    try std.testing.expect(cfg.getBlock(exit_blk).reachable);
}

test "CFG - linear sequence" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const b0 = try cfg.newBlock(.entry);
    const b1 = try cfg.newBlock(.normal);
    const b2 = try cfg.newBlock(.normal);
    const b3 = try cfg.newBlock(.exit_block);
    cfg.entry = b0;
    cfg.exit = b3;

    try cfg.addEdge(b0, b1, .fallthrough);
    try cfg.addEdge(b1, b2, .fallthrough);
    try cfg.addEdge(b2, b3, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 4), cfg.numBlocks());
    try std.testing.expectEqual(@as(usize, 3), cfg.numEdges());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);

    // RPO should visit all 4 blocks.
    try std.testing.expectEqual(@as(usize, 4), cfg.rpo_order.items.len);
}

test "CFG - diamond (if/else)" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const then_blk = try cfg.newBlock(.if_then);
    const else_blk = try cfg.newBlock(.if_else);
    const merge = try cfg.newBlock(.merge);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, then_blk, .branch_true);
    try cfg.addEdge(entry_blk, else_blk, .branch_false);
    try cfg.addEdge(then_blk, merge, .fallthrough);
    try cfg.addEdge(else_blk, merge, .fallthrough);
    try cfg.addEdge(merge, exit_blk, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 5), cfg.numBlocks());
    try std.testing.expectEqual(@as(usize, 5), cfg.numEdges());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);
    try std.testing.expectEqual(@as(usize, 0), cfg.loops.items.len);
}

test "CFG - simple loop" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const header = try cfg.newBlock(.loop_header);
    const body = try cfg.newBlock(.loop_body);
    const exit_blk = try cfg.newBlock(.loop_exit);
    const prog_exit = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = prog_exit;
    cfg.getBlock(header).loop_exit_block = exit_blk;

    try cfg.addEdge(entry_blk, header, .fallthrough);
    try cfg.addEdge(header, body, .branch_true);
    try cfg.addEdge(header, exit_blk, .branch_false);
    try cfg.addEdge(body, header, .back_edge);
    try cfg.addEdge(exit_blk, prog_exit, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 5), cfg.numBlocks());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);

    // Should detect one loop.
    try std.testing.expectEqual(@as(usize, 1), cfg.loops.items.len);
    try std.testing.expectEqual(header, cfg.loops.items[0].header);
}

test "CFG - unreachable block" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const reachable_blk = try cfg.newBlock(.normal);
    const dead_blk = try cfg.newBlock(.normal);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, reachable_blk, .fallthrough);
    try cfg.addEdge(reachable_blk, exit_blk, .fallthrough);
    // `dead_blk` has no incoming edges from entry.
    try cfg.analyze();

    try std.testing.expect(cfg.getBlock(entry_blk).reachable);
    try std.testing.expect(cfg.getBlock(reachable_blk).reachable);
    try std.testing.expect(!cfg.getBlock(dead_blk).reachable);
    try std.testing.expect(cfg.getBlock(exit_blk).reachable);
    try std.testing.expectEqual(@as(u32, 1), cfg.unreachable_count);
}

test "CFG - nested loops" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const outer_hdr = try cfg.newBlock(.loop_header);
    const outer_body = try cfg.newBlock(.loop_body);
    const inner_hdr = try cfg.newBlock(.loop_header);
    const inner_body = try cfg.newBlock(.loop_body);
    const inner_exit = try cfg.newBlock(.loop_exit);
    const outer_exit = try cfg.newBlock(.loop_exit);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;
    cfg.getBlock(outer_hdr).loop_exit_block = outer_exit;
    cfg.getBlock(inner_hdr).loop_exit_block = inner_exit;

    try cfg.addEdge(entry_blk, outer_hdr, .fallthrough);
    try cfg.addEdge(outer_hdr, outer_body, .branch_true);
    try cfg.addEdge(outer_hdr, outer_exit, .branch_false);
    try cfg.addEdge(outer_body, inner_hdr, .fallthrough);
    try cfg.addEdge(inner_hdr, inner_body, .branch_true);
    try cfg.addEdge(inner_hdr, inner_exit, .branch_false);
    try cfg.addEdge(inner_body, inner_hdr, .back_edge);
    try cfg.addEdge(inner_exit, outer_hdr, .back_edge);
    try cfg.addEdge(outer_exit, exit_blk, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);
    // Should detect two loops.
    try std.testing.expectEqual(@as(usize, 2), cfg.loops.items.len);
}

test "CFG - duplicate edge prevention" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const b0 = try cfg.newBlock(.entry);
    const b1 = try cfg.newBlock(.exit_block);
    cfg.entry = b0;
    cfg.exit = b1;

    try cfg.addEdge(b0, b1, .fallthrough);
    try cfg.addEdge(b0, b1, .fallthrough); // duplicate
    try cfg.addEdge(b0, b1, .fallthrough); // duplicate

    // Should have exactly one edge.
    try std.testing.expectEqual(@as(usize, 1), cfg.numEdges());
}

test "CFG - RPO ordering" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    // Diamond:  0 → {1,2} → 3
    const b0 = try cfg.newBlock(.entry);
    const b1 = try cfg.newBlock(.if_then);
    const b2 = try cfg.newBlock(.if_else);
    const b3 = try cfg.newBlock(.exit_block);
    cfg.entry = b0;
    cfg.exit = b3;

    try cfg.addEdge(b0, b1, .branch_true);
    try cfg.addEdge(b0, b2, .branch_false);
    try cfg.addEdge(b1, b3, .fallthrough);
    try cfg.addEdge(b2, b3, .fallthrough);
    try cfg.analyze();

    // RPO should have 4 entries.
    try std.testing.expectEqual(@as(usize, 4), cfg.rpo_order.items.len);
    // Entry should be first in RPO.
    try std.testing.expectEqual(b0, cfg.rpo_order.items[0]);
    // Exit should be last in RPO.
    try std.testing.expectEqual(b3, cfg.rpo_order.items[3]);
}

test "CFG - block properties" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const hdr = try cfg.newBlock(.loop_header);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try std.testing.expect(cfg.getBlock(entry_blk).isEntry());
    try std.testing.expect(!cfg.getBlock(entry_blk).isExit());
    try std.testing.expect(cfg.getBlock(exit_blk).isExit());
    try std.testing.expect(cfg.getBlock(hdr).isLoopHeader());
    try std.testing.expect(cfg.getBlock(entry_blk).isEmpty());
}

test "CFG - isInLoop query" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const header = try cfg.newBlock(.loop_header);
    const body = try cfg.newBlock(.loop_body);
    const exit_blk = try cfg.newBlock(.loop_exit);
    const prog_exit = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = prog_exit;
    cfg.getBlock(header).loop_exit_block = exit_blk;

    try cfg.addEdge(entry_blk, header, .fallthrough);
    try cfg.addEdge(header, body, .branch_true);
    try cfg.addEdge(header, exit_blk, .branch_false);
    try cfg.addEdge(body, header, .back_edge);
    try cfg.addEdge(exit_blk, prog_exit, .fallthrough);
    try cfg.analyze();

    try std.testing.expect(cfg.isInLoop(header));
    try std.testing.expect(cfg.isInLoop(body));
    try std.testing.expect(!cfg.isInLoop(entry_blk));
    try std.testing.expect(!cfg.isInLoop(exit_blk));
}

test "CFG - case/select structure" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const test1 = try cfg.newBlock(.case_test);
    const body1 = try cfg.newBlock(.case_body);
    const test2 = try cfg.newBlock(.case_test);
    const body2 = try cfg.newBlock(.case_body);
    const otherwise = try cfg.newBlock(.case_otherwise);
    const merge = try cfg.newBlock(.merge);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, test1, .fallthrough);
    try cfg.addEdge(test1, body1, .case_match);
    try cfg.addEdge(test1, test2, .case_next);
    try cfg.addEdge(body1, merge, .fallthrough);
    try cfg.addEdge(test2, body2, .case_match);
    try cfg.addEdge(test2, otherwise, .case_next);
    try cfg.addEdge(body2, merge, .fallthrough);
    try cfg.addEdge(otherwise, merge, .fallthrough);
    try cfg.addEdge(merge, exit_blk, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 8), cfg.numBlocks());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);
}

test "CFGBuilder - minimal program via AST" {
    // Build a minimal AST: just an END statement.
    const allocator = std.testing.allocator;
    const b = ast.Builder.init(allocator);

    const end_stmt = try b.stmt(.{ .line = 1, .column = 1 }, .{ .end_stmt = {} });
    defer allocator.destroy(end_stmt);

    const stmts = try allocator.alloc(ast.StmtPtr, 1);
    defer allocator.free(stmts);
    stmts[0] = end_stmt;

    var lines_storage: [1]ast.ProgramLine = .{
        .{
            .line_number = 0,
            .statements = stmts,
            .loc = .{ .line = 1, .column = 1 },
        },
    };

    const program = ast.Program{
        .lines = &lines_storage,
    };

    var builder = CFGBuilder.init(allocator);
    defer builder.deinit();

    const cfg = try builder.buildFromProgram(&program);

    // Should have at least entry, exit, and possibly intermediate blocks.
    try std.testing.expect(cfg.numBlocks() >= 2);
    try std.testing.expect(cfg.analyzed);
    try std.testing.expect(cfg.getBlock(cfg.entry).reachable);
    try std.testing.expect(cfg.getBlock(cfg.exit).reachable);
}

test "CFG - DOT output does not crash" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;
    try cfg.addEdge(entry_blk, exit_blk, .fallthrough);
    try cfg.analyze();

    // Just verify it doesn't crash — write to a fixed buffer.
    var buf: [4096]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    cfg.dumpDot(fbs.writer());
    // Should have produced some output.
    try std.testing.expect(fbs.pos > 0);
}

test "CFG - dump output does not crash" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const body = try cfg.newBlock(.normal);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;
    try cfg.addEdge(entry_blk, body, .fallthrough);
    try cfg.addEdge(body, exit_blk, .fallthrough);
    try cfg.analyze();

    var buf: [8192]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    cfg.dump(fbs.writer());
    try std.testing.expect(fbs.pos > 0);
}

test "CFG - getUnreachableBlocks" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    _ = try cfg.newBlock(.normal); // dead block 1
    _ = try cfg.newBlock(.normal); // dead block 2
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, exit_blk, .fallthrough);
    try cfg.analyze();

    var dead_blocks: std.ArrayList(u32) = .empty;
    defer dead_blocks.deinit(allocator);
    try cfg.getUnreachableBlocks(&dead_blocks, allocator);
    try std.testing.expectEqual(@as(usize, 2), dead_blocks.items.len);
}

test "CFG - try/catch structure" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const entry_blk = try cfg.newBlock(.entry);
    const try_blk = try cfg.newBlock(.try_body);
    const catch_blk = try cfg.newBlock(.catch_handler);
    const finally_blk = try cfg.newBlock(.finally_handler);
    const merge = try cfg.newBlock(.merge);
    const exit_blk = try cfg.newBlock(.exit_block);
    cfg.entry = entry_blk;
    cfg.exit = exit_blk;

    try cfg.addEdge(entry_blk, try_blk, .fallthrough);
    try cfg.addEdge(try_blk, catch_blk, .exception);
    try cfg.addEdge(try_blk, finally_blk, .finally);
    try cfg.addEdge(catch_blk, finally_blk, .finally);
    try cfg.addEdge(finally_blk, merge, .fallthrough);
    try cfg.addEdge(merge, exit_blk, .fallthrough);
    try cfg.analyze();

    try std.testing.expectEqual(@as(usize, 6), cfg.numBlocks());
    try std.testing.expectEqual(@as(u32, 0), cfg.unreachable_count);
}

test "CFG - edge find" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const b0 = try cfg.newBlock(.entry);
    const b1 = try cfg.newBlock(.if_then);
    const b2 = try cfg.newBlock(.if_else);
    cfg.entry = b0;

    try cfg.addEdge(b0, b1, .branch_true);
    try cfg.addEdge(b0, b2, .branch_false);

    const e1 = cfg.findEdge(b0, b1);
    try std.testing.expect(e1 != null);
    try std.testing.expectEqual(EdgeKind.branch_true, e1.?.kind);

    const e2 = cfg.findEdge(b0, b2);
    try std.testing.expect(e2 != null);
    try std.testing.expectEqual(EdgeKind.branch_false, e2.?.kind);

    const e3 = cfg.findEdge(b1, b2);
    try std.testing.expect(e3 == null);
}

test "CFG - predecessor and successor counts" {
    const allocator = std.testing.allocator;
    var cfg = CFG.init(allocator);
    defer cfg.deinit();

    const b0 = try cfg.newBlock(.entry);
    const b1 = try cfg.newBlock(.normal);
    const b2 = try cfg.newBlock(.normal);
    const b3 = try cfg.newBlock(.exit_block);
    cfg.entry = b0;
    cfg.exit = b3;

    try cfg.addEdge(b0, b1, .branch_true);
    try cfg.addEdge(b0, b2, .branch_false);
    try cfg.addEdge(b1, b3, .fallthrough);
    try cfg.addEdge(b2, b3, .fallthrough);

    try std.testing.expectEqual(@as(usize, 0), cfg.getBlock(b0).numPredecessors());
    try std.testing.expectEqual(@as(usize, 2), cfg.getBlock(b0).numSuccessors());
    try std.testing.expectEqual(@as(usize, 1), cfg.getBlock(b1).numPredecessors());
    try std.testing.expectEqual(@as(usize, 2), cfg.getBlock(b3).numPredecessors());
}
