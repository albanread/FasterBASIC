//! CFG-Driven Code Generation for the FasterBASIC compiler.
//!
//! This module generates QBE Intermediate Language (IL) from the CFG and
//! semantic analysis results. Unlike codegen_v1 which walked the AST directly,
//! this version uses the Control Flow Graph to drive code generation:
//!
//!   1. Walk basic blocks in reverse-postorder (RPO).
//!   2. For each block, emit a QBE label, then emit code for each statement.
//!   3. Emit the block terminator (branch/jump/ret) based on CFG edges.
//!
//! Architecture:
//! - `QBEBuilder`: Low-level IL text emission (instructions, labels, temps).
//! - `TypeManager`: Maps FasterBASIC types to QBE types.
//! - `SymbolMapper`: Generates mangled names for variables, functions, etc.
//! - `RuntimeLibrary`: Declarations and call helpers for the C runtime.
//! - `ExprEmitter`: Expression → QBE IL translation (pure data-flow).
//! - `BlockEmitter`: Emits statements within a basic block + terminators.
//! - `CFGCodeGenerator`: Top-level orchestrator, walks CFG in RPO order.
//!
//! The control-flow structure (IF diamonds, loop headers/back-edges, CASE
//! dispatch, TRY/CATCH) is encoded entirely in the CFG edges and block kinds.
//! The codegen never re-derives control flow from the AST.

const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const cfg_mod = @import("cfg.zig");
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

// ═══════════════════════════════════════════════════════════════════════════
// FunctionContext — Tracks parameters, locals, and return value for the
//                   currently-emitting function/sub.
// ═══════════════════════════════════════════════════════════════════════════

pub const FunctionContext = struct {
    /// Original function/sub name (as written in source).
    func_name: []const u8,
    /// Uppercased function name (for matching assignments like `FuncName = val`).
    upper_name: []const u8,
    /// True for FUNCTION (has return value), false for SUB.
    is_function: bool,
    /// QBE return type string ("d", "w", "l", or "" for void/SUB).
    return_type: []const u8,
    /// The semantic base type of the return value.
    return_base_type: semantic.BaseType,
    /// Stack address where the return value is accumulated (for FUNCTION).
    return_addr: ?[]const u8,

    /// Maps parameter base name (uppercase) → info about its stack slot.
    param_addrs: std.StringHashMap(ParamInfo),
    /// Maps local variable base name (uppercase) → its stack address.
    local_addrs: std.StringHashMap(LocalInfo),

    allocator: std.mem.Allocator,

    pub const ParamInfo = struct {
        /// Stack-allocated address for the parameter.
        addr: []const u8,
        /// QBE type letter ("w", "d", "l", etc.)
        qbe_type: []const u8,
        /// The semantic base type.
        base_type: semantic.BaseType,
        /// The type suffix tag (if any).
        suffix: ?Tag,
    };

    pub const LocalInfo = struct {
        /// Stack-allocated address for the local variable.
        addr: []const u8,
        /// QBE type letter.
        qbe_type: []const u8,
        /// The semantic base type.
        base_type: semantic.BaseType,
        /// The type suffix tag (if any).
        suffix: ?Tag,
    };

    pub fn init(allocator: std.mem.Allocator, func_name: []const u8, upper_name: []const u8, is_function: bool, return_type: []const u8, return_base_type: semantic.BaseType) FunctionContext {
        return .{
            .func_name = func_name,
            .upper_name = upper_name,
            .is_function = is_function,
            .return_type = return_type,
            .return_base_type = return_base_type,
            .return_addr = null,
            .param_addrs = std.StringHashMap(ParamInfo).init(allocator),
            .local_addrs = std.StringHashMap(LocalInfo).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FunctionContext) void {
        self.param_addrs.deinit();
        self.local_addrs.deinit();
    }

    /// Look up a variable by (uppercase) base name.  Returns the stack
    /// address and QBE type if the name is a parameter or local in this
    /// function context.  Returns null if not found (caller should fall
    /// back to global lookup).
    pub const ResolvedVar = struct {
        addr: []const u8,
        qbe_type: []const u8,
        base_type: semantic.BaseType,
        suffix: ?Tag,
    };

    pub fn resolve(self: *const FunctionContext, upper_base_name: []const u8) ?ResolvedVar {
        if (self.param_addrs.get(upper_base_name)) |pi| {
            return .{ .addr = pi.addr, .qbe_type = pi.qbe_type, .base_type = pi.base_type, .suffix = pi.suffix };
        }
        if (self.local_addrs.get(upper_base_name)) |li| {
            return .{ .addr = li.addr, .qbe_type = li.qbe_type, .base_type = li.base_type, .suffix = li.suffix };
        }
        return null;
    }

    /// Check whether an uppercase name matches the function name (for
    /// `FunctionName = expr` return-value assignment).
    pub fn isReturnAssignment(self: *const FunctionContext, upper_base_name: []const u8) bool {
        return self.is_function and std.mem.eql(u8, upper_base_name, self.upper_name);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// QBEBuilder — Low-level QBE IL emission
// ═══════════════════════════════════════════════════════════════════════════

/// Builds QBE IL text by appending instructions to an internal buffer.
/// Manages temporary variable allocation, label generation, and string
/// constant pooling.
pub const QBEBuilder = struct {
    /// The accumulated IL output.
    output: std.ArrayList(u8),
    /// Counter for temporary variables (%t.0, %t.1, ...).
    temp_counter: u32 = 0,
    /// Counter for unique labels.
    label_counter: u32 = 0,
    /// Counter for string constant labels ($str_0, $str_1, ...).
    string_counter: u32 = 0,
    /// Whether we are currently inside a function body.
    in_function: bool = false,
    /// Name of the current function (for debugging).
    current_function: []const u8 = "",
    /// Whether the current block has been terminated (jmp/ret/jnz).
    /// When true, further instructions are unreachable until a new label.
    terminated: bool = false,
    /// The most recently emitted block label (without '@' prefix).
    /// Used by IIF phi nodes to reference the correct predecessor block
    /// when nested IIFs create intermediate blocks.
    current_label: []const u8 = "",

    /// String constant pool: value → label name.
    string_pool: std.StringHashMap([]const u8),
    /// Set of string labels already emitted by `emitStringPool()`.
    emitted_strings: std.StringHashMap(void),

    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) QBEBuilder {
        return .{
            .output = .empty,
            .string_pool = std.StringHashMap([]const u8).init(allocator),
            .emitted_strings = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *QBEBuilder) void {
        self.output.deinit(self.allocator);
        // Free allocated keys and values in the string pool.
        var it = self.string_pool.iterator();
        while (it.next()) |entry| {
            self.allocator.free(entry.key_ptr.*);
            self.allocator.free(entry.value_ptr.*);
        }
        self.string_pool.deinit();
        self.emitted_strings.deinit();
    }

    /// Get the complete generated IL as a string slice.
    pub fn getIL(self: *const QBEBuilder) []const u8 {
        return self.output.items;
    }

    /// Clear all generated IL and reset counters.
    pub fn reset(self: *QBEBuilder) void {
        self.output.clearRetainingCapacity();
        self.temp_counter = 0;
        self.label_counter = 0;
        self.string_counter = 0;
        self.in_function = false;
        self.current_function = "";
        self.terminated = false;
        self.string_pool.clearRetainingCapacity();
        self.emitted_strings.clearRetainingCapacity();
    }

    // ── Temporaries ─────────────────────────────────────────────────────

    /// Allocate a new temporary variable name: %t.0, %t.1, ...
    pub fn newTemp(self: *QBEBuilder) ![]const u8 {
        const n = self.temp_counter;
        self.temp_counter += 1;
        return std.fmt.allocPrint(self.allocator, "%t.{d}", .{n});
    }

    /// Get next unique label ID.
    pub fn nextLabelId(self: *QBEBuilder) u32 {
        const id = self.label_counter;
        self.label_counter += 1;
        return id;
    }

    // ── Function / Block Structure ──────────────────────────────────────

    /// Begin a function definition.
    /// `name`: function name (e.g. "main", "sub_mysub").
    /// `return_type`: QBE return type ("w", "l", "s", "d", or "" for void).
    /// `params`: parameter list (e.g. "w %arg0, l %arg1").
    pub fn emitFunctionStart(self: *QBEBuilder, name: []const u8, return_type: []const u8, params: []const u8) !void {
        if (return_type.len > 0) {
            try self.emit("export function {s} ${s}({s}) {{\n", .{ return_type, name, params });
        } else {
            try self.emit("export function ${s}({s}) {{\n", .{ name, params });
        }
        self.in_function = true;
        self.current_function = name;
    }

    /// End a function definition.
    pub fn emitFunctionEnd(self: *QBEBuilder) !void {
        try self.raw("}\n\n");
        self.in_function = false;
        self.current_function = "";
    }

    /// Emit a basic block label.
    /// Clears the terminated flag — a new label starts a new reachable block.
    pub fn emitLabel(self: *QBEBuilder, label: []const u8) !void {
        try self.emit("@{s}\n", .{label});
        self.terminated = false;
        self.current_label = label;
    }

    // ── Arithmetic & Logic ──────────────────────────────────────────────

    /// Emit a binary arithmetic instruction.
    /// `dest`: e.g. "%t.0". `qbe_type`: "w","l","s","d". `op`: "add","sub", etc.
    pub fn emitBinary(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, op: []const u8, lhs: []const u8, rhs: []const u8) !void {
        try self.emit("    {s} ={s} {s} {s}, {s}\n", .{ dest, qbe_type, op, lhs, rhs });
    }

    /// Emit a comparison instruction.
    /// For integer types (w, l) ordered comparisons get a signed prefix (s),
    /// producing e.g. csgtw, csltw.  Equality (eq, ne) has no sign prefix.
    /// For float types (d, s) no prefix is needed.
    pub fn emitCompare(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, op: []const u8, lhs: []const u8, rhs: []const u8) !void {
        const is_int_type = std.mem.eql(u8, qbe_type, "w") or std.mem.eql(u8, qbe_type, "l");
        const is_ordered = std.mem.eql(u8, op, "lt") or std.mem.eql(u8, op, "le") or
            std.mem.eql(u8, op, "gt") or std.mem.eql(u8, op, "ge");
        if (is_int_type and is_ordered) {
            // Signed integer comparison: csltw, cslew, csgtw, csgew, etc.
            try self.emit("    {s} =w cs{s}{s} {s}, {s}\n", .{ dest, op, qbe_type, lhs, rhs });
        } else {
            // Equality/inequality (ceqw, cnew, ceqd, cned) or
            // float ordered comparisons (cltd, cled, cgtd, cged)
            try self.emit("    {s} =w c{s}{s} {s}, {s}\n", .{ dest, op, qbe_type, lhs, rhs });
        }
    }

    /// Emit a unary negation: dest =type sub 0, operand.
    pub fn emitNeg(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, operand: []const u8) !void {
        const zero: []const u8 = if (std.mem.eql(u8, qbe_type, "d"))
            "d_0.0"
        else if (std.mem.eql(u8, qbe_type, "s"))
            "s_0.0"
        else
            "0";
        try self.emitBinary(dest, qbe_type, "sub", zero, operand);
    }

    // ── Memory Operations ───────────────────────────────────────────────

    /// Emit a load instruction.
    pub fn emitLoad(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, addr: []const u8) !void {
        try self.emit("    {s} ={s} load{s} {s}\n", .{ dest, qbe_type, qbe_type, addr });
    }

    /// Emit a store instruction.
    pub fn emitStore(self: *QBEBuilder, qbe_type: []const u8, value: []const u8, addr: []const u8) !void {
        try self.emit("    store{s} {s}, {s}\n", .{ qbe_type, value, addr });
    }

    /// Emit a stack allocation.
    /// `dest`: receives the pointer (always type 'l').
    /// `size`: number of bytes.
    /// `alignment`: required alignment (4, 8, or 16).
    pub fn emitAlloc(self: *QBEBuilder, dest: []const u8, size: u32, alignment: u32) !void {
        const align_val: u32 = if (alignment == 0) blk: {
            if (size <= 4) break :blk 4;
            if (size <= 8) break :blk 8;
            break :blk 16;
        } else alignment;

        try self.emit("    {s} =l alloc{d} {d}\n", .{ dest, align_val, size });
    }

    // ── Control Flow ────────────────────────────────────────────────────

    /// Emit an unconditional jump.
    pub fn emitJump(self: *QBEBuilder, target: []const u8) !void {
        if (self.terminated) return; // block already ended
        try self.emit("    jmp @{s}\n", .{target});
        self.terminated = true;
    }

    /// Emit a conditional branch.
    pub fn emitBranch(self: *QBEBuilder, condition: []const u8, true_label: []const u8, false_label: []const u8) !void {
        if (self.terminated) return;
        try self.emit("    jnz {s}, @{s}, @{s}\n", .{ condition, true_label, false_label });
        self.terminated = true;
    }

    /// Emit a return instruction.
    pub fn emitReturn(self: *QBEBuilder, value: []const u8) !void {
        if (self.terminated) return;
        if (value.len > 0) {
            try self.emit("    ret {s}\n", .{value});
        } else {
            try self.emit("    ret\n", .{});
        }
        self.terminated = true;
    }

    // ── Function Calls ──────────────────────────────────────────────────

    /// Emit a function call.
    /// `dest`: empty for void calls.
    /// `return_type`: "w","l","s","d" or "" for void.
    pub fn emitCall(self: *QBEBuilder, dest: []const u8, return_type: []const u8, func_name: []const u8, args: []const u8) !void {
        if (dest.len > 0 and return_type.len > 0) {
            try self.emit("    {s} ={s} call ${s}({s})\n", .{ dest, return_type, func_name, args });
        } else {
            try self.emit("    call ${s}({s})\n", .{ func_name, args });
        }
    }

    // ── Type Conversions ────────────────────────────────────────────────

    /// Emit a sign/zero extension: extsw, extuw, extsh, etc.
    pub fn emitExtend(self: *QBEBuilder, dest: []const u8, dest_type: []const u8, op: []const u8, src: []const u8) !void {
        try self.emit("    {s} ={s} {s} {s}\n", .{ dest, dest_type, op, src });
    }

    /// Emit a floating-point conversion: swtof, dtosi, stod, etc.
    pub fn emitConvert(self: *QBEBuilder, dest: []const u8, dest_type: []const u8, op: []const u8, src: []const u8) !void {
        try self.emit("    {s} ={s} {s} {s}\n", .{ dest, dest_type, op, src });
    }

    /// Emit a truncation.
    pub fn emitTrunc(self: *QBEBuilder, dest: []const u8, dest_type: []const u8, src: []const u8) !void {
        try self.emit("    {s} ={s} copy {s}\n", .{ dest, dest_type, src });
    }

    // ── Data Section ────────────────────────────────────────────────────

    /// Emit a global data declaration.
    pub fn emitGlobalData(self: *QBEBuilder, name: []const u8, qbe_type: []const u8, initializer: []const u8) !void {
        try self.emit("data ${s} = {{ {s} {s} }}\n", .{ name, qbe_type, initializer });
    }

    /// Emit a string constant as global data.
    pub fn emitStringConstant(self: *QBEBuilder, name: []const u8, value: []const u8) !void {
        // Emit: data $name = { b "escaped_value", b 0 }
        try self.emit("data ${s} = {{ b \"", .{name});
        try self.writeEscapedString(value);
        try self.raw("\", b 0 }\n");
    }

    // ── String Constant Pool ────────────────────────────────────────────

    /// Register a string literal and return its label. If already registered,
    /// returns the existing label.
    pub fn registerString(self: *QBEBuilder, value: []const u8) ![]const u8 {
        if (self.string_pool.get(value)) |existing| {
            return existing;
        }
        const n = self.string_counter;
        self.string_counter += 1;
        const label = try std.fmt.allocPrint(self.allocator, "str_{d}", .{n});
        const owned_value = try self.allocator.dupe(u8, value);
        try self.string_pool.put(owned_value, label);
        return label;
    }

    /// Check if a string is already in the pool.
    pub fn hasString(self: *const QBEBuilder, value: []const u8) bool {
        return self.string_pool.contains(value);
    }

    /// Get the label for a registered string.
    pub fn getStringLabel(self: *const QBEBuilder, value: []const u8) ?[]const u8 {
        return self.string_pool.get(value);
    }

    /// Emit all registered string constants as global data.
    pub fn emitStringPool(self: *QBEBuilder) !void {
        var it = self.string_pool.iterator();
        while (it.next()) |entry| {
            const value = entry.key_ptr.*;
            const label = entry.value_ptr.*;
            if (!self.emitted_strings.contains(label)) {
                try self.emitStringConstant(label, value);
                try self.emitted_strings.put(label, {});
            }
        }
        try self.raw("\n");
    }

    /// Emit string constants registered after the initial pool emission.
    pub fn emitLateStringPool(self: *QBEBuilder) !void {
        var it = self.string_pool.iterator();
        while (it.next()) |entry| {
            const label = entry.value_ptr.*;
            if (!self.emitted_strings.contains(label)) {
                try self.emitStringConstant(label, entry.key_ptr.*);
                try self.emitted_strings.put(label, {});
            }
        }
    }

    // ── Comments & Raw Emission ─────────────────────────────────────────

    /// Emit a comment line.
    pub fn emitComment(self: *QBEBuilder, comment: []const u8) !void {
        try self.emit("# {s}\n", .{comment});
    }

    /// Emit a blank line.
    pub fn emitBlankLine(self: *QBEBuilder) !void {
        try self.raw("\n");
    }

    /// Emit a raw line of IL.
    /// Emit a QBE `blit` instruction to copy `n` bytes from `src` to `dst`.
    /// Both `src` and `dst` must be pointer-typed (`l`) temporaries.
    pub fn emitBlit(self: *QBEBuilder, src: []const u8, dst: []const u8, n: u32) !void {
        try self.emit("    blit {s}, {s}, {d}\n", .{ src, dst, n });
    }

    pub fn raw(self: *QBEBuilder, text: []const u8) !void {
        try self.output.appendSlice(self.allocator, text);
    }

    /// Emit a raw instruction line.
    pub fn emitInstruction(self: *QBEBuilder, instr: []const u8) !void {
        try self.emit("    {s}\n", .{instr});
    }

    // ── Internal Helpers ────────────────────────────────────────────────

    fn emit(self: *QBEBuilder, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.output.writer(self.allocator), fmt, args);
    }

    fn writeEscapedString(self: *QBEBuilder, str: []const u8) !void {
        const writer = self.output.writer(self.allocator);
        for (str) |c| {
            switch (c) {
                '\n' => try writer.writeAll("\\n"),
                '\r' => try writer.writeAll("\\r"),
                '\t' => try writer.writeAll("\\t"),
                '\\' => try writer.writeAll("\\\\"),
                '"' => try writer.writeAll("\\\""),
                0 => try writer.writeAll("\\0"),
                else => {
                    if (c < 0x20 or c >= 0x7f) {
                        try std.fmt.format(writer, "\\x{x:0>2}", .{c});
                    } else {
                        try writer.writeByte(c);
                    }
                },
            }
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// TypeManager — Maps FasterBASIC types to QBE types
// ═══════════════════════════════════════════════════════════════════════════

/// Maps FasterBASIC types and type descriptors to QBE IL type strings,
/// sizes, and alignment requirements.
pub const TypeManager = struct {
    symbol_table: *const semantic.SymbolTable,

    pub fn init(sym_table: *const semantic.SymbolTable) TypeManager {
        return .{ .symbol_table = sym_table };
    }

    /// Get the QBE IL type suffix for a BaseType.
    pub fn qbeType(self: *const TypeManager, bt: semantic.BaseType) []const u8 {
        _ = self;
        return bt.toQBEType();
    }

    /// Get the QBE IL type suffix for a TypeDescriptor.
    pub fn qbeTypeDesc(self: *const TypeManager, td: semantic.TypeDescriptor) []const u8 {
        _ = self;
        return td.toQBEType();
    }

    /// Get the size in bytes for a BaseType.
    pub fn sizeOf(self: *const TypeManager, bt: semantic.BaseType) u32 {
        _ = self;
        return switch (bt) {
            .byte, .ubyte => 1,
            .short, .ushort => 2,
            .integer, .uinteger, .single, .loop_index => 4,
            .long, .ulong, .double => 8,
            .string, .unicode, .pointer, .object, .class_instance, .array_desc, .string_desc => 8,
            .user_defined => 0, // must look up UDT
            .void, .unknown => 0,
        };
    }

    /// Get the size of a UDT type by summing its field sizes.
    pub fn sizeOfUDT(self: *const TypeManager, type_name: []const u8) u32 {
        const ts = self.symbol_table.lookupType(type_name) orelse return 0;
        var total: u32 = 0;
        for (ts.fields) |field| {
            if (field.is_built_in) {
                total += self.sizeOf(field.type_desc.base_type);
            } else {
                // Nested UDT
                total += self.sizeOfUDT(field.type_name);
            }
        }
        return total;
    }

    /// Get alignment requirement for a BaseType.
    pub fn alignOf(self: *const TypeManager, bt: semantic.BaseType) u32 {
        const size = self.sizeOf(bt);
        if (size == 0) return 4;
        if (size <= 4) return 4;
        return 8;
    }

    /// Get the QBE store type suffix: "b" for byte, "h" for short, etc.
    pub fn qbeStoreType(self: *const TypeManager, bt: semantic.BaseType) []const u8 {
        _ = self;
        return bt.toQBEMemOp();
    }

    /// Get the appropriate QBE load instruction suffix.
    /// For signed small types, use sign-extending loads.
    pub fn qbeLoadType(self: *const TypeManager, bt: semantic.BaseType) []const u8 {
        _ = self;
        return switch (bt) {
            .byte => "ub",
            .ubyte => "ub",
            .short => "sh",
            .ushort => "uh",
            .integer, .uinteger, .loop_index => "w",
            .long, .ulong => "l",
            .single => "s",
            .double => "d",
            .string, .unicode, .pointer, .object, .class_instance, .array_desc, .string_desc, .user_defined => "l",
            .void => "",
            .unknown => "w",
        };
    }

    /// Get the QBE type for a function parameter.
    pub fn qbeParamType(self: *const TypeManager, td: semantic.TypeDescriptor) []const u8 {
        // Small integer types get widened to w (word) for function parameters
        return switch (td.base_type) {
            .byte, .ubyte, .short, .ushort, .integer, .uinteger, .loop_index => "w",
            else => self.qbeTypeDesc(td),
        };
    }

    /// Convert an AS-type name string (e.g. "INTEGER", "STRING", "DOUBLE")
    /// to a semantic BaseType.  This is used when the parser stores the
    /// type keyword lexeme as a string rather than a Tag.
    pub fn baseTypeFromTypeName(name: []const u8) semantic.BaseType {
        // Compare case-insensitively by checking uppercase forms.
        if (std.ascii.eqlIgnoreCase(name, "INTEGER")) return .integer;
        if (std.ascii.eqlIgnoreCase(name, "UINTEGER")) return .uinteger;
        if (std.ascii.eqlIgnoreCase(name, "LONG")) return .long;
        if (std.ascii.eqlIgnoreCase(name, "ULONG")) return .ulong;
        if (std.ascii.eqlIgnoreCase(name, "SHORT")) return .short;
        if (std.ascii.eqlIgnoreCase(name, "USHORT")) return .ushort;
        if (std.ascii.eqlIgnoreCase(name, "BYTE")) return .byte;
        if (std.ascii.eqlIgnoreCase(name, "UBYTE")) return .ubyte;
        if (std.ascii.eqlIgnoreCase(name, "SINGLE")) return .single;
        if (std.ascii.eqlIgnoreCase(name, "DOUBLE")) return .double;
        if (std.ascii.eqlIgnoreCase(name, "STRING")) return .string;
        if (std.ascii.eqlIgnoreCase(name, "BOOLEAN")) return .integer;
        if (std.ascii.eqlIgnoreCase(name, "LIST")) return .object;
        if (std.ascii.eqlIgnoreCase(name, "HASHMAP")) return .object;
        // Unknown / UDT name — treat as user-defined (pointer-sized, no conversion).
        return .user_defined;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// SymbolMapper — Name mangling for QBE symbols
// ═══════════════════════════════════════════════════════════════════════════

/// Generates mangled QBE symbol names from FasterBASIC identifiers.
/// Handles variable names, function names, array names, class names, etc.
pub const SymbolMapper = struct {
    /// Variables marked as SHARED in the current function scope.
    shared_vars: std.StringHashMap(void),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) SymbolMapper {
        return .{
            .shared_vars = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolMapper) void {
        self.shared_vars.deinit();
    }

    /// Mangle a global variable name: x% → "var_x_int", name$ → "var_name_str".
    pub fn globalVarName(self: *const SymbolMapper, name: []const u8, suffix: ?Tag) ![]const u8 {
        const base = stripSuffix(name);
        const type_tag = suffixString(suffix);
        return std.fmt.allocPrint(self.allocator, "var_{s}{s}", .{ base, type_tag });
    }

    /// Mangle a local variable name: %name or %name_type.
    pub fn localVarName(self: *const SymbolMapper, name: []const u8, suffix: ?Tag) ![]const u8 {
        const base = stripSuffix(name);
        const type_tag = suffixString(suffix);
        return std.fmt.allocPrint(self.allocator, "%{s}{s}", .{ base, type_tag });
    }

    /// Mangle a function name: MyFunc → "func_MYFUNC".
    pub fn functionName(self: *const SymbolMapper, name: []const u8) ![]const u8 {
        var buf: [128]u8 = undefined;
        const upper = toUpperBuf(name, &buf);
        return std.fmt.allocPrint(self.allocator, "func_{s}", .{upper});
    }

    /// Mangle a SUB name: MySub → "sub_MYSUB".
    pub fn subName(self: *const SymbolMapper, name: []const u8) ![]const u8 {
        var buf: [128]u8 = undefined;
        const upper = toUpperBuf(name, &buf);
        return std.fmt.allocPrint(self.allocator, "sub_{s}", .{upper});
    }

    /// Mangle an array descriptor name: arr$ → "arr_ARR_str_desc".
    /// Strips type-suffix characters ($, %, #, !, &, ^, @) that are
    /// invalid inside QBE identifiers and appends a type tag instead.
    pub fn arrayDescName(self: *const SymbolMapper, name: []const u8) ![]const u8 {
        // Detect suffix before stripping
        const type_tag: []const u8 = if (name.len > 0) switch (name[name.len - 1]) {
            '$' => "_str",
            '%' => "_int",
            '#' => "_dbl",
            '!' => "_sng",
            '&' => "_lng",
            '^' => "_sht",
            '@' => "_byt",
            else => "",
        } else "";
        const base = stripSuffix(name);
        var buf: [128]u8 = undefined;
        const upper = toUpperBuf(base, &buf);
        return std.fmt.allocPrint(self.allocator, "arr_{s}{s}_desc", .{ upper, type_tag });
    }

    /// Mangle a class method name: ClassName.MethodName → "ClassName__MethodName".
    pub fn classMethodName(self: *const SymbolMapper, class_name: []const u8, method_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}__{s}", .{ class_name, method_name });
    }

    /// Mangle a class constructor name.
    pub fn classConstructorName(self: *const SymbolMapper, class_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}__CONSTRUCTOR", .{class_name});
    }

    /// Mangle a class destructor name.
    pub fn classDestructorName(self: *const SymbolMapper, class_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "{s}__DESTRUCTOR", .{class_name});
    }

    /// Mangle a vtable data name.
    pub fn vtableName(self: *const SymbolMapper, class_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "vtable_{s}", .{class_name});
    }

    /// Mangle a class name string constant name.
    pub fn classNameStringLabel(self: *const SymbolMapper, class_name: []const u8) ![]const u8 {
        return std.fmt.allocPrint(self.allocator, "classname_{s}", .{class_name});
    }

    /// Register a variable as SHARED.
    pub fn registerShared(self: *SymbolMapper, var_name: []const u8) !void {
        try self.shared_vars.put(var_name, {});
    }

    /// Check if a variable is SHARED.
    pub fn isShared(self: *const SymbolMapper, var_name: []const u8) bool {
        return self.shared_vars.contains(var_name);
    }

    /// Clear SHARED variable registrations (between function scopes).
    pub fn clearShared(self: *SymbolMapper) void {
        self.shared_vars.clearRetainingCapacity();
    }

    // ── Helpers ─────────────────────────────────────────────────────────

    pub fn stripSuffix(name: []const u8) []const u8 {
        if (name.len == 0) return name;
        const last = name[name.len - 1];
        if (last == '%' or last == '!' or last == '#' or last == '$' or last == '@' or last == '&' or last == '^') {
            return name[0 .. name.len - 1];
        }
        return name;
    }

    fn suffixString(suffix: ?Tag) []const u8 {
        const s = suffix orelse return "";
        return switch (s) {
            .type_int, .percent => "_int",
            .type_float, .exclamation => "_sng",
            .type_double, .hash => "_dbl",
            .type_string => "_str",
            .type_byte, .at_suffix => "_byt",
            .type_short, .caret => "_sht",
            .ampersand => "_lng",
            else => "",
        };
    }

    fn toUpperBuf(text: []const u8, buf: []u8) []const u8 {
        const len = @min(text.len, buf.len);
        for (0..len) |i| {
            buf[i] = std.ascii.toUpper(text[i]);
        }
        return buf[0..len];
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// RuntimeLibrary — C runtime function declarations and call helpers
// ═══════════════════════════════════════════════════════════════════════════

/// Provides helpers for calling the FasterBASIC C runtime library functions.
/// Each function knows the QBE signature and provides a convenient call method.
pub const RuntimeLibrary = struct {
    builder: *QBEBuilder,

    pub fn init(builder: *QBEBuilder) RuntimeLibrary {
        return .{ .builder = builder };
    }

    /// Emit declarations for all runtime functions used by the compiler.
    pub fn emitDeclarations(self: *RuntimeLibrary) !void {
        try self.builder.emitComment("=== Runtime Library Declarations ===");

        // I/O  (runtime: io_ops.c)
        try self.declare("basic_print_int", "l %val");
        try self.declare("basic_print_double", "d %val");
        try self.declare("basic_print_string_desc", "l %str");
        try self.declare("basic_print_newline", "");
        try self.declare("basic_print_tab", "");
        try self.declare("basic_input_string", "l %prompt");
        try self.declare("basic_input_int", "l %prompt");
        try self.declare("basic_input_double", "l %prompt");

        // StringDescriptor operations  (runtime: string_utf32.c, string_descriptor.h)
        try self.declare("string_new_utf8", "l %cstr");
        try self.declare("string_concat", "l %a, l %b");
        try self.declare("string_compare", "l %a, l %b");
        try self.declare("string_length", "l %str");
        try self.declare("basic_mid", "l %str, w %start, w %len");
        try self.declare("basic_left", "l %str, w %len");
        try self.declare("basic_right", "l %str, w %len");
        try self.declare("string_retain", "l %str");
        try self.declare("string_release", "l %str");
        try self.declare("string_from_int", "l %val");
        try self.declare("string_from_double", "d %val");
        try self.declare("string_slice", "l %str, l %start, l %end");
        try self.declare("string_to_int", "l %str");
        try self.declare("string_to_double", "l %str");
        try self.declare("basic_chr", "w %code");
        try self.declare("basic_asc", "l %str");
        try self.declare("string_upper", "l %str");
        try self.declare("string_lower", "l %str");
        try self.declare("string_instr", "l %haystack, l %needle, l %start");
        try self.declare("basic_string_repeat", "l %count, w %codepoint");
        try self.declare("basic_space", "l %count");
        try self.declare("basic_val", "l %str");
        try self.declare("basic_len", "l %str");
        try self.declare("string_ltrim", "l %str");
        try self.declare("string_rtrim", "l %str");
        try self.declare("string_trim", "l %str");
        try self.declare("string_clone", "l %str");

        // Math  (runtime: libm + math_ops.c)
        try self.declare("pow", "d %base, d %exp");
        try self.declare("sqrt", "d %val");
        try self.declare("fabs", "d %val");
        try self.declare("basic_abs_int", "w %val");
        try self.declare("basic_sgn", "d %val");
        try self.declare("basic_rnd", "d %val");
        try self.declare("sin", "d %val");
        try self.declare("cos", "d %val");
        try self.declare("tan", "d %val");
        try self.declare("atan", "d %val");
        try self.declare("atan2", "d %y, d %x");
        try self.declare("log", "d %val");
        try self.declare("log10", "d %val");
        try self.declare("exp", "d %val");
        try self.declare("ceil", "d %val");
        try self.declare("floor", "d %val");
        try self.declare("round", "d %val");
        try self.declare("trunc", "d %val");
        try self.declare("math_cint", "d %val");
        try self.declare("acos", "d %val");
        try self.declare("asin", "d %val");
        try self.declare("sinh", "d %val");
        try self.declare("cosh", "d %val");
        try self.declare("tanh", "d %val");
        try self.declare("hypot", "d %a, d %b");
        try self.declare("cbrt", "d %val");

        // Hex/Oct/Bin string conversions  (runtime: string_utf32.c)
        try self.declare("HEX_STRING", "l %val, l %digits");
        try self.declare("OCT_STRING", "l %val, l %digits");
        try self.declare("BIN_STRING", "l %val, l %digits");

        // Memory  (runtime: memory_mgmt.c)
        try self.declare("basic_malloc", "l %size");
        try self.declare("basic_free", "l %ptr");

        // Array operations  (runtime: fbc_bridge.c)
        try self.declare("fbc_array_create", "w %ndims, l %desc, w %upper, w %elemsize");
        try self.declare("fbc_array_bounds_check", "l %desc, w %index");
        try self.declare("fbc_array_element_addr", "l %desc, w %index");
        try self.declare("array_descriptor_erase", "l %desc");

        // SAMM (Scope-Aware Memory Management)  (runtime: samm_core.c)
        try self.declare("samm_init", "");
        try self.declare("samm_shutdown", "");
        try self.declare("samm_enter_scope", "");
        try self.declare("samm_exit_scope", "");
        try self.declare("samm_register_cleanup", "l %ptr, l %dtor");

        // Error handling  (runtime: basic_runtime.c)
        try self.declare("basic_error", "w %code, l %msg");
        try self.declare("basic_set_line", "w %line");
        try self.declare("basic_runtime_init", "");
        try self.declare("basic_runtime_cleanup", "");

        // Object system  (runtime: class_runtime.c)
        try self.declare("class_object_new", "l %size, l %vtable, l %classid");
        try self.declare("class_object_delete", "l %objref");
        try self.declare("class_is_instance", "l %obj, l %classid");

        // Data statements  (runtime: basic_runtime.c)
        try self.declare("basic_data_init", "l %data, w %count");
        try self.declare("basic_read_data_string", "");
        try self.declare("basic_read_data_int", "");
        try self.declare("basic_read_data_double", "");
        try self.declare("basic_restore_data", "");

        // String conversion  (runtime: string_utf32.c)
        try self.declare("string_to_utf8", "l %str");

        // Timer / Sleep  (runtime: basic_runtime.c)
        try self.declare("basic_timer", "");
        try self.declare("basic_timer_ms", "");
        try self.declare("basic_sleep_ms", "w %ms");

        // Hashmap  (runtime: hashmap.qbe — appended to IL when needed)
        try self.declare("hashmap_new", "w %capacity");
        try self.declare("hashmap_insert", "l %map, l %key, l %value");
        try self.declare("hashmap_lookup", "l %map, l %key");
        try self.declare("hashmap_has_key", "l %map, l %key");
        try self.declare("hashmap_remove", "l %map, l %key");
        try self.declare("hashmap_size", "l %map");
        try self.declare("hashmap_clear", "l %map");
        try self.declare("hashmap_keys", "l %map");
        try self.declare("hashmap_free", "l %map");

        // List operations  (runtime: list_ops.c)
        try self.declare("list_create", "");
        try self.declare("list_create_typed", "w %elem_type_flag");
        try self.declare("list_free", "l %list");
        // Append (value is int64_t for int, double for float, ptr for string/object)
        try self.declare("list_append_int", "l %list, l %val");
        try self.declare("list_append_float", "l %list, d %val");
        try self.declare("list_append_string", "l %list, l %str");
        try self.declare("list_append_object", "l %list, l %obj");
        // Prepend
        try self.declare("list_prepend_int", "l %list, l %val");
        try self.declare("list_prepend_float", "l %list, d %val");
        try self.declare("list_prepend_string", "l %list, l %str");
        // Insert (pos is int64_t)
        try self.declare("list_insert_int", "l %list, l %pos, l %val");
        try self.declare("list_insert_float", "l %list, l %pos, d %val");
        try self.declare("list_insert_string", "l %list, l %pos, l %str");
        // Length / Empty
        try self.declare("list_length", "l %list");
        try self.declare("list_empty", "l %list");
        // Positional access (pos is int64_t)
        try self.declare("list_get_type", "l %list, l %pos");
        try self.declare("list_get_int", "l %list, l %pos");
        try self.declare("list_get_float", "l %list, l %pos");
        try self.declare("list_get_ptr", "l %list, l %pos");
        // Head access
        try self.declare("list_head_int", "l %list");
        try self.declare("list_head_float", "l %list");
        try self.declare("list_head_ptr", "l %list");
        try self.declare("list_head_type", "l %list");
        // Shift (remove first, return value)
        try self.declare("list_shift_int", "l %list");
        try self.declare("list_shift_float", "l %list");
        try self.declare("list_shift_ptr", "l %list");
        try self.declare("list_shift_type", "l %list");
        // Pop (remove last, return value)
        try self.declare("list_pop_int", "l %list");
        try self.declare("list_pop_float", "l %list");
        try self.declare("list_pop_ptr", "l %list");
        // Remove / Clear
        try self.declare("list_remove", "l %list, l %pos");
        try self.declare("list_clear", "l %list");
        try self.declare("list_erase", "l %list, l %pos");
        // Search
        try self.declare("list_contains_int", "l %list, l %val");
        try self.declare("list_contains_float", "l %list, d %val");
        try self.declare("list_contains_string", "l %list, l %str");
        try self.declare("list_indexof_int", "l %list, l %val");
        try self.declare("list_indexof_float", "l %list, d %val");
        try self.declare("list_indexof_string", "l %list, l %str");
        // Join
        try self.declare("list_join", "l %list, l %sep");
        // Copy / Reverse
        try self.declare("list_copy", "l %list");
        try self.declare("list_reverse", "l %list");
        // Iteration
        try self.declare("list_iter_begin", "l %list");
        try self.declare("list_iter_next", "l %cursor");
        try self.declare("list_iter_type", "l %cursor");
        try self.declare("list_iter_value_int", "l %cursor");
        try self.declare("list_iter_value_float", "l %cursor");
        try self.declare("list_iter_value_ptr", "l %cursor");

        try self.builder.emitBlankLine();
    }

    /// Call a void runtime function (no return value).
    pub fn callVoid(self: *RuntimeLibrary, func_name: []const u8, args: []const u8) !void {
        try self.builder.emitCall("", "", func_name, args);
    }

    /// Call a runtime function that returns a value.
    pub fn callRet(self: *RuntimeLibrary, dest: []const u8, ret_type: []const u8, func_name: []const u8, args: []const u8) !void {
        try self.builder.emitCall(dest, ret_type, func_name, args);
    }

    fn declare(self: *RuntimeLibrary, name: []const u8, params: []const u8) !void {
        _ = params;
        // QBE doesn't require forward declarations for external functions,
        // but we emit comments for documentation.
        try self.builder.emitComment(name);
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// ExprEmitter — Expression to QBE IL translation
// ═══════════════════════════════════════════════════════════════════════════

/// Translates AST expression nodes to QBE IL instructions.
/// This is pure data-flow: no control-flow manipulation (except IIF which
/// is a self-contained inline conditional).
pub const ExprEmitter = struct {
    builder: *QBEBuilder,
    type_manager: *const TypeManager,
    symbol_mapper: *SymbolMapper,
    runtime: *RuntimeLibrary,
    symbol_table: *const semantic.SymbolTable,
    allocator: std.mem.Allocator,

    // CLASS body context: set when emitting inside a method/constructor/destructor
    class_ctx: ?*const semantic.ClassSymbol = null,
    method_ret_slot: []const u8 = "",
    method_name: []const u8 = "",

    func_ctx: ?*const FunctionContext = null,

    pub fn init(
        builder: *QBEBuilder,
        type_manager: *const TypeManager,
        symbol_mapper: *SymbolMapper,
        runtime: *RuntimeLibrary,
        symbol_table: *const semantic.SymbolTable,
        allocator: std.mem.Allocator,
    ) ExprEmitter {
        return .{
            .builder = builder,
            .type_manager = type_manager,
            .symbol_mapper = symbol_mapper,
            .runtime = runtime,
            .symbol_table = symbol_table,
            .allocator = allocator,
            .func_ctx = null,
        };
    }

    // ── Runtime Object Helpers ──────────────────────────────────────────

    /// Check if a variable name refers to a HASHMAP runtime object.
    fn isHashmapVariable(self: *ExprEmitter, name: []const u8) bool {
        var up_buf: [128]u8 = undefined;
        const base = SymbolMapper.stripSuffix(name);
        const ulen = @min(base.len, up_buf.len);
        for (0..ulen) |i| up_buf[i] = std.ascii.toUpper(base[i]);
        const upper = up_buf[0..ulen];
        if (self.symbol_table.lookupVariable(upper)) |vsym| {
            return vsym.type_desc.base_type == .object and
                std.mem.eql(u8, vsym.type_desc.object_type_name, "HASHMAP");
        }
        return false;
    }

    /// Check if a variable name refers to a LIST runtime object.
    fn isListVariable(self: *ExprEmitter, name: []const u8) bool {
        var up_buf: [128]u8 = undefined;
        const base = SymbolMapper.stripSuffix(name);
        const ulen = @min(base.len, up_buf.len);
        for (0..ulen) |i| up_buf[i] = std.ascii.toUpper(base[i]);
        const upper = up_buf[0..ulen];
        if (self.symbol_table.lookupVariable(upper)) |vsym| {
            return vsym.type_desc.base_type == .object and
                std.mem.eql(u8, vsym.type_desc.object_type_name, "LIST");
        }
        return false;
    }

    /// Return the declared element BaseType for a LIST variable.
    /// Returns .unknown if the variable is not a list or has no declared element type.
    fn listElementType(self: *ExprEmitter, name: []const u8) semantic.BaseType {
        var up_buf: [128]u8 = undefined;
        const base = SymbolMapper.stripSuffix(name);
        const ulen = @min(base.len, up_buf.len);
        for (0..ulen) |i| up_buf[i] = std.ascii.toUpper(base[i]);
        const upper = up_buf[0..ulen];
        if (self.symbol_table.lookupVariable(upper)) |vsym| {
            if (vsym.type_desc.base_type == .object and
                std.mem.eql(u8, vsym.type_desc.object_type_name, "LIST"))
            {
                return vsym.type_desc.element_type;
            }
        }
        return .unknown;
    }

    // ── Expression Type Inference ───────────────────────────────────────

    /// QBE-level type classification for expression results.
    pub const ExprType = enum {
        /// 64-bit float (QBE `d`) — the BASIC default numeric type.
        double,
        /// 32-bit integer (QBE `w`) — INTEGER / LONG variables.
        integer,
        /// Pointer to string descriptor (QBE `l`) — STRING$ variables.
        string,

        /// Return the QBE type letter for argument passing.
        pub fn argLetter(self: ExprType) []const u8 {
            return switch (self) {
                .double => "d",
                .integer => "w",
                .string => "l",
            };
        }

        /// Return the runtime print function name for this type.
        pub fn printFn(self: ExprType) []const u8 {
            return switch (self) {
                .double => "basic_print_double",
                .integer => "basic_print_int",
                .string => "basic_print_string_desc",
            };
        }

        /// Return the QBE argument type letter (l for int since runtime uses int64_t).
        pub fn printArgLetter(self: ExprType) []const u8 {
            return switch (self) {
                .double => "d",
                .integer => "l",
                .string => "l",
            };
        }
    };

    /// Infer the QBE-level type of an expression from the AST.
    pub fn inferExprType(self: *ExprEmitter, expr: *const ast.Expression) ExprType {
        return switch (expr.data) {
            .string_lit => .string,
            .number => |n| {
                // If the number is a whole number that fits in i32, treat as integer.
                const as_int: i64 = @intFromFloat(n.value);
                if (@as(f64, @floatFromInt(as_int)) == n.value and n.value >= -2147483648.0 and n.value <= 2147483647.0) {
                    return .integer;
                }
                return .double;
            },
            .variable => |v| {
                // If the variable has an explicit suffix, use that.
                if (v.type_suffix != null) return typeFromSuffix(v.type_suffix);

                // ── Check function context first (params / locals) ──────
                // This ensures parameters and locals declared as integer
                // inside a FUNCTION/SUB are inferred correctly rather than
                // falling through to the global symbol table (which may
                // not have them or may have a different type).
                if (self.func_ctx) |fctx| {
                    var fup_buf: [128]u8 = undefined;
                    const fbase = SymbolMapper.stripSuffix(v.name);
                    const flen = @min(fbase.len, fup_buf.len);
                    for (0..flen) |fi| fup_buf[fi] = std.ascii.toUpper(fbase[fi]);
                    const fupper = fup_buf[0..flen];

                    if (fctx.resolve(fupper)) |rv| {
                        if (rv.base_type.isInteger()) return .integer;
                        if (rv.base_type.isString()) return .string;
                        if (rv.base_type.isFloat()) return .double;
                        return .double;
                    }

                    // Also check return-value assignment variable
                    // (e.g. FuncName used as a variable inside the function).
                    if (fctx.isReturnAssignment(fupper)) {
                        if (fctx.return_base_type.isInteger()) return .integer;
                        if (fctx.return_base_type.isString()) return .string;
                        return .double;
                    }
                }

                // ── Fall back to global symbol table ────────────────────
                // Consult the symbol table for the actual type
                // (e.g. FOR loop index variables are registered as integer).
                var vup_buf: [128]u8 = undefined;
                const vbase = SymbolMapper.stripSuffix(v.name);
                const vlen = @min(vbase.len, vup_buf.len);
                for (0..vlen) |vi| vup_buf[vi] = std.ascii.toUpper(vbase[vi]);
                const vupper = vup_buf[0..vlen];
                if (self.symbol_table.lookupVariable(vupper)) |vsym| {
                    if (vsym.type_desc.base_type.isInteger()) return .integer;
                    if (vsym.type_desc.base_type.isString()) return .string;
                }
                return .double;
            },
            .binary => |b| {
                const lt = self.inferExprType(b.left);
                const rt = self.inferExprType(b.right);

                // String concatenation yields string
                if (lt == .string or rt == .string) {
                    return switch (b.op) {
                        .plus, .ampersand => .string,
                        // String comparisons yield integer (boolean)
                        .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal => .integer,
                        else => .double,
                    };
                }

                // Comparison and logical operators always return integer (w)
                return switch (b.op) {
                    .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal, .kw_and, .kw_or, .kw_xor => .integer,
                    // Integer division always returns integer
                    .int_divide => .integer,
                    // If both operands are integer, arithmetic stays integer
                    .plus, .minus, .multiply, .divide, .kw_mod => {
                        if (lt == .integer and rt == .integer) return .integer;
                        return .double;
                    },
                    // Power always returns double
                    .power => .double,
                    else => .double,
                };
            },
            .unary => |u| {
                // NOT always returns integer; negation preserves type
                if (u.op == .kw_not) return .integer;
                return self.inferExprType(u.operand);
            },
            .function_call => |fc| blk: {
                if (fc.name.len > 0 and fc.name[fc.name.len - 1] == '$') break :blk ExprType.string;
                // Check symbol table for declared return type.
                // The semantic analyzer stores names in uppercase, so
                // uppercase the name before lookup.
                var fc_upper_buf: [128]u8 = undefined;
                const fc_base = SymbolMapper.stripSuffix(fc.name);
                const fc_ulen = @min(fc_base.len, fc_upper_buf.len);
                for (0..fc_ulen) |ui| fc_upper_buf[ui] = std.ascii.toUpper(fc_base[ui]);
                const fc_upper = fc_upper_buf[0..fc_ulen];

                // SGN always returns integer (-1, 0, or 1) regardless of input type.
                if (std.mem.eql(u8, fc_upper, "SGN")) {
                    break :blk ExprType.integer;
                }

                // ABS is context-dependent: integer arg → integer result,
                // double arg → double result.
                if (std.mem.eql(u8, fc_upper, "ABS")) {
                    if (fc.arguments.len > 0) {
                        const arg_et = self.inferExprType(fc.arguments[0]);
                        if (arg_et == .integer) break :blk ExprType.integer;
                    }
                    break :blk ExprType.double;
                }

                // Check builtin function mapping first (LEN, ASC, STR$, etc.)
                if (mapBuiltinFunction(fc_upper)) |bi| {
                    if (std.mem.eql(u8, bi.ret_type, "w")) break :blk ExprType.integer;
                    if (std.mem.eql(u8, bi.ret_type, "l")) break :blk ExprType.string;
                    if (std.mem.eql(u8, bi.ret_type, "d")) break :blk ExprType.double;
                }
                // Check symbol table for user-defined functions
                if (self.symbol_table.lookupFunction(fc_upper)) |fsym| {
                    const bt = fsym.return_type_desc.base_type;
                    if (bt.isInteger()) break :blk ExprType.integer;
                    if (bt.isString()) break :blk ExprType.string;
                }
                // Also try the original name as fallback
                if (self.symbol_table.lookupFunction(fc.name)) |fsym| {
                    const bt = fsym.return_type_desc.base_type;
                    if (bt.isInteger()) break :blk ExprType.integer;
                    if (bt.isString()) break :blk ExprType.string;
                }
                break :blk ExprType.double;
            },
            .member_access => |ma| blk_ma: {
                // Check if this is a CLASS field access — infer type from the field descriptor
                if (ma.object.data == .me) {
                    if (self.class_ctx) |cls| {
                        if (cls.findField(ma.member_name)) |fi| {
                            if (fi.type_desc.base_type.isInteger()) break :blk_ma ExprType.integer;
                            if (fi.type_desc.base_type.isString()) break :blk_ma ExprType.string;
                            break :blk_ma ExprType.double;
                        }
                    }
                }
                const ma_cname = self.inferClassName(ma.object);
                if (ma_cname) |cname| {
                    var mcu_buf: [128]u8 = undefined;
                    const mcu_len = @min(cname.len, mcu_buf.len);
                    for (0..mcu_len) |mi2| mcu_buf[mi2] = std.ascii.toUpper(cname[mi2]);
                    if (self.symbol_table.lookupClass(mcu_buf[0..mcu_len])) |cls| {
                        if (cls.findField(ma.member_name)) |fi| {
                            if (fi.type_desc.base_type.isInteger()) break :blk_ma ExprType.integer;
                            if (fi.type_desc.base_type.isString()) break :blk_ma ExprType.string;
                            if (fi.type_desc.base_type == .class_instance) break :blk_ma ExprType.double;
                            break :blk_ma ExprType.double;
                        }
                    }
                }
                // ── UDT field type inference ────────────────────────────
                // Resolve the UDT type of the object expression and look up
                // the field to determine the correct ExprType.  This handles
                // both simple (P.X) and nested (O.I.V) member access.
                const ma_udt_type = self.inferUDTNameForExpr(ma.object);
                if (ma_udt_type) |uname| {
                    if (self.symbol_table.lookupType(uname)) |tsym| {
                        for (tsym.fields) |field| {
                            if (std.mem.eql(u8, field.name, ma.member_name)) {
                                if (field.type_desc.base_type.isInteger()) break :blk_ma ExprType.integer;
                                if (field.type_desc.base_type.isString()) break :blk_ma ExprType.string;
                                if (field.type_desc.base_type.isFloat()) break :blk_ma ExprType.double;
                                break :blk_ma ExprType.double;
                            }
                        }
                    }
                }
                break :blk_ma ExprType.double;
            },
            .array_access => |aa| blk_aa: {
                // Hashmap subscript returns string (values are StringDescriptor*)
                if (self.isHashmapVariable(aa.name)) break :blk_aa ExprType.string;

                // Check symbol table for the actual array element type.
                // This is essential for typed arrays (DIM a(10) AS MyClass).
                var aau_buf: [128]u8 = undefined;
                const aau_len = @min(aa.name.len, aau_buf.len);
                for (0..aau_len) |aai| aau_buf[aai] = std.ascii.toUpper(aa.name[aai]);
                if (self.symbol_table.lookupArray(aau_buf[0..aau_len])) |arr_sym| {
                    const elt = arr_sym.element_type_desc.base_type;
                    if (elt.isInteger()) break :blk_aa ExprType.integer;
                    if (elt.isString()) break :blk_aa ExprType.string;
                    if (elt.isFloat()) break :blk_aa ExprType.double;
                    // class_instance, user_defined, pointer, object → double
                    // (these are pointer-sized values; ExprType doesn't have
                    //  a dedicated variant but callers use inferClassName for
                    //  class-specific dispatch)
                }
                break :blk_aa typeFromSuffix(aa.type_suffix);
            },
            .iif => |i| self.inferExprType(i.true_value),
            .new => .double, // NEW returns an object pointer (l)
            .create => .double, // CREATE returns a UDT pointer (l)
            .method_call => |mc| blk_mc: {
                // Check if this is a hashmap method call
                if (mc.object.data == .variable) {
                    const obj_name = mc.object.data.variable.name;
                    if (self.isHashmapVariable(obj_name)) {
                        var mup_buf: [64]u8 = undefined;
                        const mlen = @min(mc.method_name.len, mup_buf.len);
                        for (0..mlen) |mi| mup_buf[mi] = std.ascii.toUpper(mc.method_name[mi]);
                        const mupper = mup_buf[0..mlen];
                        if (std.mem.eql(u8, mupper, "HASKEY") or
                            std.mem.eql(u8, mupper, "SIZE") or
                            std.mem.eql(u8, mupper, "REMOVE"))
                            break :blk_mc ExprType.integer;
                        if (std.mem.eql(u8, mupper, "KEYS"))
                            break :blk_mc ExprType.string;
                    }
                    // ── List method return type inference ────────────────
                    if (self.isListVariable(obj_name)) {
                        var lmup_buf: [64]u8 = undefined;
                        const lmlen = @min(mc.method_name.len, lmup_buf.len);
                        for (0..lmlen) |li| lmup_buf[li] = std.ascii.toUpper(mc.method_name[li]);
                        const lmupper = lmup_buf[0..lmlen];
                        // Methods that always return integer
                        if (std.mem.eql(u8, lmupper, "LENGTH") or
                            std.mem.eql(u8, lmupper, "EMPTY") or
                            std.mem.eql(u8, lmupper, "CONTAINS") or
                            std.mem.eql(u8, lmupper, "INDEXOF"))
                            break :blk_mc ExprType.integer;
                        // JOIN always returns string
                        if (std.mem.eql(u8, lmupper, "JOIN"))
                            break :blk_mc ExprType.string;
                        // Element-returning methods: type depends on LIST OF <type>
                        if (std.mem.eql(u8, lmupper, "HEAD") or
                            std.mem.eql(u8, lmupper, "GET") or
                            std.mem.eql(u8, lmupper, "SHIFT") or
                            std.mem.eql(u8, lmupper, "POP"))
                        {
                            const elt = self.listElementType(obj_name);
                            if (elt.isInteger()) break :blk_mc ExprType.integer;
                            if (elt.isString()) break :blk_mc ExprType.string;
                            break :blk_mc ExprType.double;
                        }
                        // Void methods (APPEND, PREPEND, REMOVE, CLEAR) → integer (dummy 0)
                        break :blk_mc ExprType.integer;
                    }
                }
                // Check CLASS method return type
                if (mc.object.data == .me) {
                    if (self.class_ctx) |cls| {
                        if (cls.findMethod(mc.method_name)) |mi_info| {
                            if (mi_info.return_type.base_type.isInteger()) break :blk_mc ExprType.integer;
                            if (mi_info.return_type.base_type.isString()) break :blk_mc ExprType.string;
                        }
                    }
                }
                const mc_cname = self.inferClassName(mc.object);
                if (mc_cname) |cname| {
                    var mccu_buf: [128]u8 = undefined;
                    const mccu_len = @min(cname.len, mccu_buf.len);
                    for (0..mccu_len) |mci| mccu_buf[mci] = std.ascii.toUpper(cname[mci]);
                    if (self.symbol_table.lookupClass(mccu_buf[0..mccu_len])) |cls| {
                        if (cls.findMethod(mc.method_name)) |mi_info| {
                            if (mi_info.return_type.base_type.isInteger()) break :blk_mc ExprType.integer;
                            if (mi_info.return_type.base_type.isString()) break :blk_mc ExprType.string;
                        }
                    }
                }
                break :blk_mc ExprType.double;
            },
            .me, .nothing, .super_call => .double,
            .is_type => .integer,
            .list_constructor => .double,
            .array_binop => .double,
            .registry_function => .double,
        };
    }

    /// Check whether an expression resolves to a LONG (64-bit integer)
    /// base type.  This is needed because `inferExprType` collapses both
    /// INTEGER (32-bit) and LONG (64-bit) into `.integer`.  When emitting
    /// binary arithmetic we must use QBE `l` ops for LONG operands.
    fn isLongExpr(self: *ExprEmitter, expr: *const ast.Expression) bool {
        switch (expr.data) {
            .variable => |v| {
                // Check function context first (params / locals)
                if (self.func_ctx) |fctx| {
                    var fup_buf: [128]u8 = undefined;
                    const fbase = SymbolMapper.stripSuffix(v.name);
                    const flen = @min(fbase.len, fup_buf.len);
                    for (0..flen) |fi| fup_buf[fi] = std.ascii.toUpper(v.name[fi]);
                    const fupper = fup_buf[0..flen];
                    if (fctx.resolve(fupper)) |rv| {
                        return rv.base_type == .long or rv.base_type == .ulong;
                    }
                }
                // Fall back to global symbol table
                var vup_buf: [128]u8 = undefined;
                const vbase = SymbolMapper.stripSuffix(v.name);
                const vlen = @min(vbase.len, vup_buf.len);
                for (0..vlen) |vi| vup_buf[vi] = std.ascii.toUpper(vbase[vi]);
                const vupper = vup_buf[0..vlen];
                if (self.symbol_table.lookupVariable(vupper)) |vsym| {
                    return vsym.type_desc.base_type == .long or vsym.type_desc.base_type == .ulong;
                }
                // Check suffix
                if (v.type_suffix) |s| {
                    return s == .ampersand;
                }
                return false;
            },
            .binary => |b| {
                return self.isLongExpr(b.left) or self.isLongExpr(b.right);
            },
            .unary => |u| {
                return self.isLongExpr(u.operand);
            },
            .function_call => |fc| {
                var fc_upper_buf: [128]u8 = undefined;
                const fc_base = SymbolMapper.stripSuffix(fc.name);
                const fc_ulen = @min(fc_base.len, fc_upper_buf.len);
                for (0..fc_ulen) |ui| fc_upper_buf[ui] = std.ascii.toUpper(fc_base[ui]);
                const fc_upper = fc_upper_buf[0..fc_ulen];
                if (self.symbol_table.lookupFunction(fc_upper)) |fsym| {
                    return fsym.return_type_desc.base_type == .long or fsym.return_type_desc.base_type == .ulong;
                }
                return false;
            },
            else => return false,
        }
    }

    fn typeFromSuffix(suffix: ?Tag) ExprType {
        if (suffix) |s| {
            return switch (s) {
                .type_string => .string,
                .type_int => .integer,
                .type_double => .double,
                .type_float => .double,
                .type_byte => .integer,
                .type_short => .integer,
                .ampersand => .integer,
                .hash => .double,
                .percent => .integer,
                .exclamation => .double,
                else => .double,
            };
        }
        return .double;
    }

    // ── Expression Emission ─────────────────────────────────────────────

    /// Explicit error set to break recursive inference in emitExpression cycle.
    const EmitError = error{OutOfMemory};

    /// Emit code for an expression and return the temporary holding the result.
    pub fn emitExpression(self: *ExprEmitter, expr: *const ast.Expression) EmitError![]const u8 {
        return switch (expr.data) {
            .number => |n| self.emitNumberLiteral(n.value),
            .string_lit => |s| self.emitStringLiteral(s.value),
            .variable => |v| self.emitVariableLoad(v.name, v.type_suffix),
            .binary => |b| self.emitBinaryExpr(b.left, b.op, b.right),
            .unary => |u| self.emitUnaryExpr(u.op, u.operand),
            .function_call => |fc| self.emitFunctionCall(fc.name, fc.arguments, fc.is_fn),
            .iif => |i| self.emitIIF(i.condition, i.true_value, i.false_value),
            .member_access => |ma| self.emitMemberAccess(ma.object, ma.member_name),
            .method_call => |mc| self.emitMethodCall(mc.object, mc.method_name, mc.arguments),
            .array_access => |aa| self.emitArrayAccess(aa.name, aa.indices, aa.type_suffix),
            .create => |cr| self.emitCreate(cr.type_name, cr.arguments, cr.is_named, cr.field_names),
            .new => |n| self.emitNew(n.class_name, n.arguments),
            .me => self.emitMe(),
            .nothing => self.emitNothing(),
            .is_type => |it| self.emitIsType(it.object, it.class_name, it.is_nothing_check),
            .super_call => |sc| self.emitSuperCall(sc.method_name, sc.arguments),
            .list_constructor => |lc| self.emitListConstructor(lc.elements),
            .array_binop => |ab| self.emitArrayBinop(ab.left_array, ab.operation, ab.right_expr),
            .registry_function => |rf| self.emitRegistryFunction(rf.name, rf.arguments),
        };
    }

    fn emitNumberLiteral(self: *ExprEmitter, value: f64) EmitError![]const u8 {
        const as_int: i64 = @intFromFloat(value);
        if (@as(f64, @floatFromInt(as_int)) == value and value >= -2147483648.0 and value <= 2147483647.0) {
            // Whole number that fits in 32-bit integer — emit as integer
            // directly. Callers that need a double will promote via
            // emitIntToDouble when they see the .integer ExprType.
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =w copy {d}\n", .{ dest, as_int });
            return dest;
        } else {
            // Fractional or out-of-range: emit as double literal.
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_{d}\n", .{ dest, value });
            return dest;
        }
    }

    fn emitStringLiteral(self: *ExprEmitter, value: []const u8) EmitError![]const u8 {
        const label = try self.builder.registerString(value);
        // Pass the raw C string pointer to string_new_utf8() which creates
        // a proper StringDescriptor* — the canonical string representation
        // used by the FasterBASIC runtime.
        const raw_ptr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ raw_ptr, label });
        const dest = try self.builder.newTemp();
        const args = try std.fmt.allocPrint(self.allocator, "l {s}", .{raw_ptr});
        try self.builder.emitCall(dest, "l", "string_new_utf8", args);
        return dest;
    }

    fn emitVariableLoad(self: *ExprEmitter, name: []const u8, suffix: ?Tag) EmitError![]const u8 {
        // ── Check function context for parameters / locals ──────────────
        if (self.func_ctx) |fctx| {
            var upper_buf: [128]u8 = undefined;
            const base = SymbolMapper.stripSuffix(name);
            const ulen = @min(base.len, upper_buf.len);
            for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
            const upper_base = upper_buf[0..ulen];

            // Check if this is the function return variable (FuncName used as variable)
            if (fctx.isReturnAssignment(upper_base)) {
                if (fctx.return_addr) |ret_addr| {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitLoad(dest, fctx.return_type, ret_addr);
                    // SINGLE values are loaded as QBE 's' but the expression
                    // system works entirely with 'd' (double). Extend to
                    // double so that comparisons and arithmetic work.
                    if (std.mem.eql(u8, fctx.return_type, "s")) {
                        const dbl = try self.builder.newTemp();
                        try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
                        return dbl;
                    }
                    return dest;
                }
            }

            if (fctx.resolve(upper_base)) |rv| {
                const dest = try self.builder.newTemp();
                // For user_defined (UDT) locals stored inline on the stack,
                // the stack slot address IS the UDT address — return it
                // directly instead of loading from it.
                if (rv.base_type == .user_defined) {
                    try self.builder.emit("    {s} =l copy {s}\n", .{ dest, rv.addr });
                } else {
                    try self.builder.emitLoad(dest, rv.qbe_type, rv.addr);
                }
                // SINGLE locals/params are loaded as 's' but the expression
                // system expects 'd'. Promote to double.
                if (rv.base_type == .single) {
                    const dbl = try self.builder.newTemp();
                    try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
                    return dbl;
                }
                return dest;
            }
        }

        // ── Fall back to global variable ────────────────────────────────
        const dest = try self.builder.newTemp();

        // When the suffix is null (unsuffixed variable), consult the symbol
        // table for the actual registered type instead of defaulting to
        // double.  This is important for FOR loop index variables which are
        // registered as integer.
        // When the suffix is null, first try to detect it from the
        // variable name itself (e.g. "I%" → .percent), then consult the
        // symbol table for the registered type.
        var effective_suffix = suffix;
        if (effective_suffix == null and name.len > 0) {
            effective_suffix = switch (name[name.len - 1]) {
                '%' => @as(?Tag, .percent),
                '$' => @as(?Tag, .type_string),
                '#' => @as(?Tag, .hash),
                '!' => @as(?Tag, .exclamation),
                '&' => @as(?Tag, .ampersand),
                '^' => @as(?Tag, .caret),
                '@' => @as(?Tag, .at_suffix),
                else => @as(?Tag, null),
            };
        }
        var bt = semantic.baseTypeFromSuffix(effective_suffix);
        if (effective_suffix == null) {
            // No suffix from caller or name — consult the symbol table.
            // Try stripped name first, then original (with suffix char) to
            // handle both "DIM x AS INTEGER" and "FOR I% = ..." patterns.
            var sym_upper_buf: [128]u8 = undefined;
            const sym_base = SymbolMapper.stripSuffix(name);
            const slen = @min(sym_base.len, sym_upper_buf.len);
            for (0..slen) |si| sym_upper_buf[si] = std.ascii.toUpper(sym_base[si]);
            const sym_upper = sym_upper_buf[0..slen];
            const vsym = self.symbol_table.lookupVariable(sym_upper) orelse blk: {
                // Stripped name not found — try the full uppercased name
                // (symbol table may store key with suffix, e.g. "I%").
                var full_upper_buf: [128]u8 = undefined;
                const flen = @min(name.len, full_upper_buf.len);
                for (0..flen) |fi| full_upper_buf[fi] = std.ascii.toUpper(name[fi]);
                const full_upper = full_upper_buf[0..flen];
                break :blk self.symbol_table.lookupVariable(full_upper);
            };
            if (vsym) |vs| {
                bt = vs.type_desc.base_type;
                // Reconstruct suffix from base type so globalVarName
                // produces the same mangled name as emitGlobalVariables.
                effective_suffix = switch (bt) {
                    .integer => @as(?Tag, .type_int),
                    .single => @as(?Tag, .type_float),
                    .double => @as(?Tag, .type_double),
                    .string => @as(?Tag, .type_string),
                    .long => @as(?Tag, .ampersand),
                    .byte => @as(?Tag, .type_byte),
                    .short => @as(?Tag, .type_short),
                    else => @as(?Tag, null),
                };
            }
        }
        const var_name = try self.symbol_mapper.globalVarName(name, effective_suffix);
        const qbe_t = bt.toQBEType();
        const load_t = bt.toQBEMemOp();

        // For user_defined (UDT) types, the global variable stores a
        // POINTER to the struct (allocated by CREATE on the stack or
        // heap).  Load the pointer from the global slot with loadl.
        if (bt == .user_defined) {
            try self.builder.emitLoad(dest, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));
            return dest;
        }

        // For small types (byte, short), the load suffix differs from the
        // result type.  E.g. loadsb gives a w result.
        if (!std.mem.eql(u8, qbe_t, load_t) and bt.isInteger()) {
            // Small integer: load with sign/zero extension into w.
            try self.builder.emit("    {s} =w load{s} {s}\n", .{
                dest,
                if (bt == .byte or bt == .ubyte) @as([]const u8, "ub") else @as([]const u8, "sh"),
                try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}),
            });
        } else {
            try self.builder.emitLoad(dest, qbe_t, try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));
        }
        // SINGLE globals are loaded as 's' but the expression system
        // expects 'd' (double). Promote to double so that comparisons
        // (ceqd, cgtd, …) and arithmetic work correctly.
        if (bt == .single) {
            const dbl = try self.builder.newTemp();
            try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
            return dbl;
        }
        return dest;
    }

    fn emitBinaryExpr(self: *ExprEmitter, left: *const ast.Expression, op: Tag, right: *const ast.Expression) EmitError![]const u8 {
        // Determine operand types for type-aware emission.
        const left_type = self.inferExprType(left);
        const right_type = self.inferExprType(right);

        // ── String concatenation ────────────────────────────────────────
        // If either operand is a string and the op is `+` or `&`, emit
        // a call to the string_concat runtime function.
        if (left_type == .string or right_type == .string) {
            switch (op) {
                .plus, .ampersand => {
                    const lhs = try self.emitExpression(left);
                    const rhs_val = try self.emitExpression(right);
                    // If one side isn't a string, convert it.
                    const lhs_str = if (left_type != .string)
                        try self.emitNumericToString(lhs, left_type)
                    else
                        lhs;
                    const rhs_str = if (right_type != .string)
                        try self.emitNumericToString(rhs_val, right_type)
                    else
                        rhs_val;
                    const dest = try self.builder.newTemp();
                    const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ lhs_str, rhs_str });
                    try self.builder.emitCall(dest, "l", "string_concat", args);
                    return dest;
                },
                // String comparison operators
                .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal => {
                    const lhs = try self.emitExpression(left);
                    const rhs_val = try self.emitExpression(right);
                    const cmp_result = try self.builder.newTemp();
                    const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ lhs, rhs_val });
                    try self.builder.emitCall(cmp_result, "w", "string_compare", args);
                    const dest = try self.builder.newTemp();
                    switch (op) {
                        .equal => try self.builder.emitCompare(dest, "w", "eq", cmp_result, "0"),
                        .not_equal => try self.builder.emitCompare(dest, "w", "ne", cmp_result, "0"),
                        .less_than => try self.builder.emitCompare(dest, "w", "lt", cmp_result, "0"),
                        .less_equal => try self.builder.emitCompare(dest, "w", "le", cmp_result, "0"),
                        .greater_than => try self.builder.emitCompare(dest, "w", "gt", cmp_result, "0"),
                        .greater_equal => try self.builder.emitCompare(dest, "w", "ge", cmp_result, "0"),
                        else => unreachable,
                    }
                    return dest;
                },
                else => {}, // Fall through for other ops (shouldn't happen with strings)
            }
        }

        const lhs = try self.emitExpression(left);
        const rhs = try self.emitExpression(right);
        const dest = try self.builder.newTemp();

        // Detect pointer-typed operands (UDT, CLASS, object variables,
        // NEW/CREATE expressions) that return 'l' values.  These must
        // use long ('l') comparison, not double ('d'), to avoid QBE
        // "invalid type for first operand" errors.
        const left_is_ptr = self.isPointerExpr(left);
        const right_is_ptr = self.isPointerExpr(right);
        const is_ptr_op = left_is_ptr or right_is_ptr;

        // Choose the QBE type for arithmetic: if both sides are integer, use "w".
        // For LONG (64-bit int) operands, use "l" instead of "w".
        const is_int_op = (left_type == .integer and right_type == .integer);
        const is_long_op = is_int_op and (self.isLongExpr(left) or self.isLongExpr(right));
        const arith_type: []const u8 = if (is_ptr_op) "l" else if (is_long_op) "l" else if (is_int_op) "w" else "d";

        // If mixing types (one int, one double), promote the int to double.
        // Skip promotion for pointer operands — they are already 'l'.
        // For LONG ops, promote 32-bit integers to 64-bit with extsw.
        const eff_lhs = if (!is_ptr_op and !is_int_op and left_type == .integer)
            try self.emitIntToDouble(lhs)
        else if (is_long_op and !self.isLongExpr(left)) blk: {
            const ext = try self.builder.newTemp();
            try self.builder.emitExtend(ext, "l", "extsw", lhs);
            break :blk ext;
        } else lhs;
        const eff_rhs = if (!is_ptr_op and !is_int_op and right_type == .integer)
            try self.emitIntToDouble(rhs)
        else if (is_long_op and !self.isLongExpr(right)) blk: {
            const ext = try self.builder.newTemp();
            try self.builder.emitExtend(ext, "l", "extsw", rhs);
            break :blk ext;
        } else rhs;

        switch (op) {
            // Arithmetic
            .plus => try self.builder.emitBinary(dest, arith_type, "add", eff_lhs, eff_rhs),
            .minus => try self.builder.emitBinary(dest, arith_type, "sub", eff_lhs, eff_rhs),
            .multiply => try self.builder.emitBinary(dest, arith_type, "mul", eff_lhs, eff_rhs),
            .divide => {
                if (is_int_op) {
                    // Integer division: result stays integer (w or l for LONG)
                    try self.builder.emitBinary(dest, if (is_long_op) "l" else "w", "div", eff_lhs, eff_rhs);
                } else {
                    try self.builder.emitBinary(dest, "d", "div", eff_lhs, eff_rhs);
                }
            },
            .kw_mod => {
                if (is_int_op) {
                    try self.builder.emitBinary(dest, if (is_long_op) "l" else "w", "rem", eff_lhs, eff_rhs);
                } else {
                    // Float MOD: a - floor(a/b) * b
                    const div_temp = try self.builder.newTemp();
                    try self.builder.emitBinary(div_temp, "d", "div", eff_lhs, eff_rhs);
                    const trunc_temp = try self.builder.newTemp();
                    try self.builder.emitConvert(trunc_temp, "w", "dtosi", div_temp);
                    const floor_temp = try self.builder.newTemp();
                    try self.builder.emitConvert(floor_temp, "d", "swtof", trunc_temp);
                    const mul_temp = try self.builder.newTemp();
                    try self.builder.emitBinary(mul_temp, "d", "mul", floor_temp, eff_rhs);
                    try self.builder.emitBinary(dest, "d", "sub", eff_lhs, mul_temp);
                }
            },
            .power => {
                // Power always uses doubles.
                const pow_lhs = if (left_type == .integer) try self.emitIntToDouble(lhs) else lhs;
                const pow_rhs = if (right_type == .integer) try self.emitIntToDouble(rhs) else rhs;
                const args = try std.fmt.allocPrint(self.allocator, "d {s}, d {s}", .{ pow_lhs, pow_rhs });
                try self.builder.emitCall(dest, "d", "pow", args);
            },
            .int_divide => {
                // Integer division always truncates.
                const li = if (left_type == .integer) lhs else blk: {
                    const t = try self.builder.newTemp();
                    try self.builder.emitConvert(t, "w", "dtosi", lhs);
                    break :blk t;
                };
                const ri = if (right_type == .integer) rhs else blk: {
                    const t = try self.builder.newTemp();
                    try self.builder.emitConvert(t, "w", "dtosi", rhs);
                    break :blk t;
                };
                try self.builder.emitBinary(dest, "w", "div", li, ri);
            },

            // Comparison operators — result is always w (int).
            .equal => try self.builder.emitCompare(dest, arith_type, "eq", eff_lhs, eff_rhs),
            .not_equal => try self.builder.emitCompare(dest, arith_type, "ne", eff_lhs, eff_rhs),
            .less_than => try self.builder.emitCompare(dest, arith_type, "lt", eff_lhs, eff_rhs),
            .less_equal => try self.builder.emitCompare(dest, arith_type, "le", eff_lhs, eff_rhs),
            .greater_than => try self.builder.emitCompare(dest, arith_type, "gt", eff_lhs, eff_rhs),
            .greater_equal => try self.builder.emitCompare(dest, arith_type, "ge", eff_lhs, eff_rhs),

            // Logical operators — always w.
            .kw_and => try self.builder.emitBinary(dest, "w", "and", eff_lhs, eff_rhs),
            .kw_or => try self.builder.emitBinary(dest, "w", "or", eff_lhs, eff_rhs),
            .kw_xor => try self.builder.emitBinary(dest, "w", "xor", eff_lhs, eff_rhs),

            else => {
                try self.builder.emitComment("WARN: unhandled binary op, treating as add");
                try self.builder.emitBinary(dest, arith_type, "add", eff_lhs, eff_rhs);
            },
        }

        return dest;
    }

    /// Convert an integer temporary to double.
    fn emitIntToDouble(self: *ExprEmitter, int_temp: []const u8) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emitConvert(dest, "d", "swtof", int_temp);
        return dest;
    }

    /// Convert a double temporary to integer (truncate).
    fn emitDoubleToInt(self: *ExprEmitter, dbl_temp: []const u8) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emitConvert(dest, "w", "dtosi", dbl_temp);
        return dest;
    }

    /// Convert a numeric value to a StringDescriptor* via runtime call.
    fn emitNumericToString(self: *ExprEmitter, temp: []const u8, et: ExprType) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        switch (et) {
            .integer => {
                // string_from_int expects int64_t (l), sign-extend w → l
                const long_val = try self.builder.newTemp();
                try self.builder.emitExtend(long_val, "l", "extsw", temp);
                const args = try std.fmt.allocPrint(self.allocator, "l {s}", .{long_val});
                try self.builder.emitCall(dest, "l", "string_from_int", args);
            },
            .double => {
                const args = try std.fmt.allocPrint(self.allocator, "d {s}", .{temp});
                try self.builder.emitCall(dest, "l", "string_from_double", args);
            },
            .string => return temp, // already a string
        }
        return dest;
    }

    /// Check whether an expression produces a pointer-typed (l) value
    /// rather than a numeric (w/d) value.  Used to select the correct
    /// QBE comparison type (ceql vs ceqd) for UDT/CLASS/object variables.
    fn isPointerExpr(self: *ExprEmitter, expr: *const ast.Expression) bool {
        return switch (expr.data) {
            .new, .create, .nothing, .list_constructor => true,
            .variable => |v| {
                var vu_buf: [128]u8 = undefined;
                const vbase = SymbolMapper.stripSuffix(v.name);
                const vlen = @min(vbase.len, vu_buf.len);
                for (0..vlen) |vi| vu_buf[vi] = std.ascii.toUpper(vbase[vi]);
                if (self.symbol_table.lookupVariable(vu_buf[0..vlen])) |vsym| {
                    return switch (vsym.type_desc.base_type) {
                        .class_instance, .object, .user_defined, .pointer => true,
                        else => false,
                    };
                }
                return false;
            },
            .member_access => |ma| {
                // If the member resolves to a class/UDT field, it's a pointer
                const cname = self.inferClassName(ma.object);
                if (cname) |cn| {
                    var cu_buf: [128]u8 = undefined;
                    const cu_len = @min(cn.len, cu_buf.len);
                    for (0..cu_len) |ci| cu_buf[ci] = std.ascii.toUpper(cn[ci]);
                    if (self.symbol_table.lookupClass(cu_buf[0..cu_len])) |cls| {
                        if (cls.findField(ma.member_name)) |fi| {
                            return switch (fi.type_desc.base_type) {
                                .class_instance, .object, .user_defined, .pointer => true,
                                else => false,
                            };
                        }
                    }
                }
                return false;
            },
            else => false,
        };
    }

    fn emitUnaryExpr(self: *ExprEmitter, op: Tag, operand: *const ast.Expression) EmitError![]const u8 {
        const val = try self.emitExpression(operand);
        const dest = try self.builder.newTemp();
        const operand_type = self.inferExprType(operand);
        const qbe_t: []const u8 = if (operand_type == .integer) "w" else "d";

        switch (op) {
            .minus => try self.builder.emitNeg(dest, qbe_t, val),
            .kw_not => {
                try self.builder.emitCompare(dest, "w", "eq", val, "0");
            },
            else => {
                try self.builder.emit("    {s} ={s} copy {s}\n", .{ dest, qbe_t, val });
            },
        }

        return dest;
    }

    /// Map a BASIC builtin function name to the actual C runtime symbol.
    /// Returns null if the name is not a builtin (i.e. it's a user function).
    const BuiltinMapping = struct { rt_name: []const u8, ret_type: []const u8 };

    fn mapBuiltinFunction(name_upper: []const u8) ?BuiltinMapping {
        // String functions — all use StringDescriptor* (l) for string args/returns
        if (std.mem.eql(u8, name_upper, "STR$") or std.mem.eql(u8, name_upper, "STR")) return .{ .rt_name = "string_from_int", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "CHR$") or std.mem.eql(u8, name_upper, "CHR")) return .{ .rt_name = "basic_chr", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "ASC")) return .{ .rt_name = "basic_asc", .ret_type = "w" };
        if (std.mem.eql(u8, name_upper, "LEN")) return .{ .rt_name = "basic_len", .ret_type = "w" };
        if (std.mem.eql(u8, name_upper, "VAL")) return .{ .rt_name = "basic_val", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "MID$") or std.mem.eql(u8, name_upper, "MID")) return .{ .rt_name = "basic_mid", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "LEFT$") or std.mem.eql(u8, name_upper, "LEFT")) return .{ .rt_name = "basic_left", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "RIGHT$") or std.mem.eql(u8, name_upper, "RIGHT")) return .{ .rt_name = "basic_right", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "UCASE$") or std.mem.eql(u8, name_upper, "UCASE")) return .{ .rt_name = "string_upper", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "LCASE$") or std.mem.eql(u8, name_upper, "LCASE")) return .{ .rt_name = "string_lower", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "INSTR")) return .{ .rt_name = "string_instr", .ret_type = "w" };
        if (std.mem.eql(u8, name_upper, "STRING$") or std.mem.eql(u8, name_upper, "STRING")) return .{ .rt_name = "basic_string_repeat", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "SPACE$") or std.mem.eql(u8, name_upper, "SPACE")) return .{ .rt_name = "basic_space", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "LTRIM$") or std.mem.eql(u8, name_upper, "LTRIM")) return .{ .rt_name = "string_ltrim", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "RTRIM$") or std.mem.eql(u8, name_upper, "RTRIM")) return .{ .rt_name = "string_rtrim", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "TRIM$") or std.mem.eql(u8, name_upper, "TRIM")) return .{ .rt_name = "string_trim", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "HEX$") or std.mem.eql(u8, name_upper, "HEX")) return .{ .rt_name = "HEX_STRING", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "OCT$") or std.mem.eql(u8, name_upper, "OCT")) return .{ .rt_name = "OCT_STRING", .ret_type = "l" };
        if (std.mem.eql(u8, name_upper, "BIN$") or std.mem.eql(u8, name_upper, "BIN")) return .{ .rt_name = "BIN_STRING", .ret_type = "l" };
        // Math functions
        if (std.mem.eql(u8, name_upper, "ABS")) return .{ .rt_name = "fabs", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "SGN")) return .{ .rt_name = "basic_sgn", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "SQR")) return .{ .rt_name = "sqrt", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "INT")) return .{ .rt_name = "floor", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "FIX")) return .{ .rt_name = "trunc", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "CINT")) return .{ .rt_name = "math_cint", .ret_type = "w" };
        if (std.mem.eql(u8, name_upper, "SIN")) return .{ .rt_name = "sin", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "COS")) return .{ .rt_name = "cos", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "TAN")) return .{ .rt_name = "tan", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "ATN") or std.mem.eql(u8, name_upper, "ATAN")) return .{ .rt_name = "atan", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "ATAN2")) return .{ .rt_name = "atan2", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "LOG")) return .{ .rt_name = "log", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "LOG10")) return .{ .rt_name = "log10", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "EXP")) return .{ .rt_name = "exp", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "RND")) return .{ .rt_name = "basic_rnd", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "CEIL")) return .{ .rt_name = "ceil", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "FLOOR")) return .{ .rt_name = "floor", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "ROUND")) return .{ .rt_name = "round", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "ACOS")) return .{ .rt_name = "acos", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "ASIN")) return .{ .rt_name = "asin", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "SINH")) return .{ .rt_name = "sinh", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "COSH")) return .{ .rt_name = "cosh", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "TANH")) return .{ .rt_name = "tanh", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "HYPOT")) return .{ .rt_name = "hypot", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "CBRT")) return .{ .rt_name = "cbrt", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "POW")) return .{ .rt_name = "pow", .ret_type = "d" };
        // Error functions
        if (std.mem.eql(u8, name_upper, "ERR")) return .{ .rt_name = "basic_err", .ret_type = "w" };
        if (std.mem.eql(u8, name_upper, "ERL")) return .{ .rt_name = "basic_erl", .ret_type = "w" };
        // Timer
        if (std.mem.eql(u8, name_upper, "TIMER")) return .{ .rt_name = "basic_timer", .ret_type = "d" };
        if (std.mem.eql(u8, name_upper, "TIMER_MS")) return .{ .rt_name = "basic_timer_ms", .ret_type = "l" };
        // Not a builtin
        return null;
    }

    fn emitFunctionCall(self: *ExprEmitter, name: []const u8, arguments: []const ast.ExprPtr, is_fn: bool) EmitError![]const u8 {
        _ = is_fn;

        // ── Check for builtin function mapping ─────────────────────────
        // Uppercase the name for lookup.
        var name_upper_buf: [128]u8 = undefined;
        const name_len = @min(name.len, name_upper_buf.len);
        for (0..name_len) |i| name_upper_buf[i] = std.ascii.toUpper(name[i]);
        const name_upper = name_upper_buf[0..name_len];

        // ── LEN intrinsic ──────────────────────────────────────────────
        // LEN(s$) is just descriptor->length at offset 8.  Emit an inline
        // field load instead of a function call.
        //
        // StringDescriptor layout (from string_descriptor.h):
        //   Offset 0:  void*   data
        //   Offset 8:  int64_t length   <── this is what we want
        //
        // We emit a NULL-safe branch so LEN("") on an uninitialised
        // variable returns 0 rather than crashing.
        if (std.mem.eql(u8, name_upper, "LEN")) {
            if (arguments.len >= 1) {
                const str_ptr = try self.emitExpression(arguments[0]);
                const id = self.builder.nextLabelId();
                const load_lbl = try std.fmt.allocPrint(self.allocator, "len_load_{d}", .{id});
                const null_lbl = try std.fmt.allocPrint(self.allocator, "len_null_{d}", .{id});
                const done_lbl = try std.fmt.allocPrint(self.allocator, "len_done_{d}", .{id});

                // NULL check
                const is_null = try self.builder.newTemp();
                try self.builder.emitCompare(is_null, "l", "eq", str_ptr, "0");
                try self.builder.emitBranch(is_null, null_lbl, load_lbl);

                // Non-NULL path: load length from offset 8
                try self.builder.emitLabel(load_lbl);
                const off_ptr = try self.builder.newTemp();
                try self.builder.emitBinary(off_ptr, "l", "add", str_ptr, "8");
                const loaded = try self.builder.newTemp();
                try self.builder.emitLoad(loaded, "l", off_ptr);
                try self.builder.emitJump(done_lbl);

                // NULL path: length is 0
                try self.builder.emitLabel(null_lbl);
                const zero = try self.builder.newTemp();
                try self.builder.emitInstruction(try std.fmt.allocPrint(
                    self.allocator,
                    "{s} =l copy 0",
                    .{zero},
                ));
                try self.builder.emitJump(done_lbl);

                // Merge
                try self.builder.emitLabel(done_lbl);
                const result = try self.builder.newTemp();
                try self.builder.emitInstruction(try std.fmt.allocPrint(
                    self.allocator,
                    "{s} =l phi @{s} {s}, @{s} {s}",
                    .{ result, load_lbl, loaded, null_lbl, zero },
                ));

                // Truncate int64 -> int32 (w) since BASIC LEN returns an integer
                const trunc = try self.builder.newTemp();
                try self.builder.emitTrunc(trunc, "w", result);
                return trunc;
            }
        }

        // ── SGN intrinsic ──────────────────────────────────────────────
        // SGN(x) = -1 if x < 0, 0 if x == 0, 1 if x > 0
        // Branchless: result = (x > 0) - (x < 0)
        if (std.mem.eql(u8, name_upper, "SGN")) {
            if (arguments.len >= 1) {
                const arg_val = try self.emitExpression(arguments[0]);
                const arg_type = self.inferExprType(arguments[0]);
                const neg = try self.builder.newTemp();
                const pos = try self.builder.newTemp();
                const result = try self.builder.newTemp();
                if (arg_type == .integer) {
                    // Integer path: csltw / csgtw
                    try self.builder.emitCompare(neg, "w", "slt", arg_val, "0");
                    try self.builder.emitCompare(pos, "w", "sgt", arg_val, "0");
                    try self.builder.emitBinary(result, "w", "sub", pos, neg);
                } else {
                    // Double path: cltd / cgtd
                    const dval = if (arg_type == .integer) try self.emitIntToDouble(arg_val) else arg_val;
                    try self.builder.emitCompare(neg, "d", "lt", dval, "d_0.0");
                    try self.builder.emitCompare(pos, "d", "gt", dval, "d_0.0");
                    try self.builder.emitBinary(result, "w", "sub", pos, neg);
                }
                return result;
            }
        }

        // ── ABS intrinsic ──────────────────────────────────────────────
        // Integer: branchless  (x ^ (x >> 31)) - (x >> 31)
        //   or simply:  if x < 0 then -x else x  via select
        // Double: call fabs
        if (std.mem.eql(u8, name_upper, "ABS")) {
            if (arguments.len >= 1) {
                const arg_val = try self.emitExpression(arguments[0]);
                const arg_type = self.inferExprType(arguments[0]);
                if (arg_type == .integer) {
                    // Integer ABS: arithmetic shift right 31 to get sign mask,
                    // then XOR and subtract.
                    // mask = x >> 31  (arithmetic: all 1s if negative, 0 if positive)
                    // abs  = (x ^ mask) - mask
                    const mask = try self.builder.newTemp();
                    try self.builder.emitBinary(mask, "w", "sar", arg_val, "31");
                    const xored = try self.builder.newTemp();
                    try self.builder.emitBinary(xored, "w", "xor", arg_val, mask);
                    const result = try self.builder.newTemp();
                    try self.builder.emitBinary(result, "w", "sub", xored, mask);
                    return result;
                } else {
                    // Double ABS: call fabs
                    const dval = if (arg_type == .integer) try self.emitIntToDouble(arg_val) else arg_val;
                    const result = try self.builder.newTemp();
                    try self.builder.emitCall(result, "d", "fabs", try std.fmt.allocPrint(self.allocator, "d {s}", .{dval}));
                    return result;
                }
            }
        }

        // Special case: STR$ with a double argument should call basic_str_double
        // instead of basic_str_int. We detect this after building args.
        const builtin = mapBuiltinFunction(name_upper);

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        // Track first argument type for STR$ dispatch
        var first_arg_type: ExprType = .double;

        for (arguments, 0..) |arg, i| {
            if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
            var arg_val = try self.emitExpression(arg);
            const arg_type = self.inferExprType(arg);
            if (i == 0) first_arg_type = arg_type;
            // For builtin math functions that return double (sin, cos,
            // sqrt, …), all arguments are expected to be double.
            // Promote integer arguments to double so QBE sees the
            // correct type (e.g. `$sin(d …)` instead of `$sin(w …)`).
            var effective_type = arg_type;
            if (builtin != null and arg_type == .integer and
                std.mem.eql(u8, builtin.?.ret_type, "d"))
            {
                arg_val = try self.emitIntToDouble(arg_val);
                effective_type = .double;
            }
            try std.fmt.format(args_buf.writer(self.allocator), "{s} {s}", .{ effective_type.argLetter(), arg_val });
        }

        const dest = try self.builder.newTemp();

        if (builtin) |bi| {
            // Special dispatch: STR$ needs different runtime functions for int vs double
            var rt_name = bi.rt_name;
            var ret_type = bi.ret_type;
            if (std.mem.eql(u8, name_upper, "STR$") or std.mem.eql(u8, name_upper, "STR")) {
                if (first_arg_type == .double) {
                    rt_name = "string_from_double";
                } else {
                    rt_name = "string_from_int";
                }
            }
            // ABS: dispatch to int vs double variant
            if (std.mem.eql(u8, name_upper, "ABS")) {
                if (first_arg_type == .integer) {
                    rt_name = "basic_abs_int";
                    ret_type = "w";
                } else {
                    rt_name = "fabs";
                    ret_type = "d";
                }
            }
            // SQR: dispatch float vs double
            if (std.mem.eql(u8, name_upper, "SQR")) {
                rt_name = "sqrt";
                ret_type = "d";
            }
            try self.builder.emitCall(dest, ret_type, rt_name, args_buf.items);
            return dest;
        }

        // ── User-defined function ──────────────────────────────────────
        const mangled = try self.symbol_mapper.functionName(name);
        // Look up the function in the symbol table for return type and
        // declared parameter types.  When declared parameter types are
        // available we rebuild the argument list so that class-instance
        // parameters use "l" (pointer) instead of "d" (double), which
        // the naive inferExprType path would produce.
        var fn_upper_buf: [128]u8 = undefined;
        const fn_base = SymbolMapper.stripSuffix(name);
        const fn_ulen = @min(fn_base.len, fn_upper_buf.len);
        for (0..fn_ulen) |ui| fn_upper_buf[ui] = std.ascii.toUpper(fn_base[ui]);
        const fn_upper = fn_upper_buf[0..fn_ulen];
        const fn_sym = self.symbol_table.lookupFunction(fn_upper) orelse
            self.symbol_table.lookupFunction(name);

        const ret_type: []const u8 = blk: {
            if (name.len > 0 and name[name.len - 1] == '$') break :blk "l";
            if (fn_sym) |fsym| break :blk fsym.return_type_desc.toQBEType();
            break :blk "d";
        };

        // Rebuild argument list using declared parameter types when the
        // function is known.  This fixes class-instance and UDT params
        // that would otherwise be emitted as "d" (double).
        if (fn_sym) |fsym| {
            if (fsym.parameter_type_descs.len > 0) {
                var typed_args: std.ArrayList(u8) = .empty;
                defer typed_args.deinit(self.allocator);
                for (arguments, 0..) |arg, ai| {
                    if (ai > 0) try typed_args.appendSlice(self.allocator, ", ");
                    const arg_val = try self.emitExpression(arg);
                    const declared_type: []const u8 = if (ai < fsym.parameter_type_descs.len)
                        fsym.parameter_type_descs[ai].toQBEType()
                    else
                        self.inferExprType(arg).argLetter();

                    // Convert if needed: inferred double but declared int, etc.
                    const expr_et = self.inferExprType(arg);
                    var effective_arg = arg_val;
                    if (std.mem.eql(u8, declared_type, "w") and expr_et == .double) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "w", "dtosi", arg_val);
                        effective_arg = cvt;
                    } else if (std.mem.eql(u8, declared_type, "d") and expr_et == .integer) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                        effective_arg = cvt;
                    } else if (std.mem.eql(u8, declared_type, "l") and expr_et == .integer) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                        effective_arg = cvt;
                    } else if (std.mem.eql(u8, declared_type, "s") and expr_et == .double) {
                        // double → single: truncate
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "s", "truncd", arg_val);
                        effective_arg = cvt;
                    } else if (std.mem.eql(u8, declared_type, "s") and expr_et == .integer) {
                        // integer → single: convert w → s
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "s", "swtof", arg_val);
                        effective_arg = cvt;
                    }
                    try std.fmt.format(typed_args.writer(self.allocator), "{s} {s}", .{ declared_type, effective_arg });
                }
                try self.builder.emitCall(dest, ret_type, mangled, typed_args.items);
                // If the function returns SINGLE (s), promote to double (d)
                // so the rest of the compiler can use it uniformly as 'd'.
                if (std.mem.eql(u8, ret_type, "s")) {
                    const promoted = try self.builder.newTemp();
                    try self.builder.emitConvert(promoted, "d", "exts", dest);
                    return promoted;
                }
                return dest;
            }
        }

        // Fallback: no symbol table info, use inferred argument types.
        try self.builder.emitCall(dest, ret_type, mangled, args_buf.items);
        // If the function returns SINGLE (s), promote to double (d)
        // so the rest of the compiler can use it uniformly as 'd'.
        if (std.mem.eql(u8, ret_type, "s")) {
            const promoted = try self.builder.newTemp();
            try self.builder.emitConvert(promoted, "d", "exts", dest);
            return promoted;
        }
        return dest;
    }

    fn emitIIF(self: *ExprEmitter, condition: *const ast.Expression, true_val: *const ast.Expression, false_val: *const ast.Expression) EmitError![]const u8 {
        // IIF is a self-contained inline conditional expression.
        // It creates its own micro-CFG within the block.
        const cond = try self.emitExpression(condition);
        const cond_type = self.inferExprType(condition);
        const id = self.builder.nextLabelId();
        const true_label = try std.fmt.allocPrint(self.allocator, "iif_true_{d}", .{id});
        const false_label = try std.fmt.allocPrint(self.allocator, "iif_false_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "iif_done_{d}", .{id});

        // Only convert to integer if condition is a double; if already
        // integer (e.g. from a comparison) use it directly.
        const cond_int = if (cond_type == .double) blk: {
            const t = try self.builder.newTemp();
            try self.builder.emitConvert(t, "w", "dtosi", cond);
            break :blk t;
        } else cond;

        try self.builder.emitBranch(cond_int, true_label, false_label);

        try self.builder.emitLabel(true_label);
        const tv = try self.emitExpression(true_val);
        // Capture the actual predecessor block for the true branch.
        // If true_val is a nested IIF, current_label will be the inner
        // IIF's done label, not true_label.
        const true_pred = self.builder.current_label;
        try self.builder.emitJump(done_label);

        try self.builder.emitLabel(false_label);
        const fv = try self.emitExpression(false_val);
        // Same for the false branch — capture the actual predecessor.
        const false_pred = self.builder.current_label;
        try self.builder.emitJump(done_label);

        // Determine the QBE type for the phi node from the result type.
        const result_type = self.inferExprType(true_val);
        const phi_qbe_type: []const u8 = switch (result_type) {
            .double => "d",
            .integer => "w",
            .string => "l",
        };

        try self.builder.emitLabel(done_label);
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} ={s} phi @{s} {s}, @{s} {s}\n", .{ dest, phi_qbe_type, true_pred, tv, false_pred, fv });

        return dest;
    }

    fn emitMemberAccess(self: *ExprEmitter, object: *const ast.Expression, member_name: []const u8) EmitError![]const u8 {
        // ── CLASS instance member access (fast path) ────────────────────
        // If expression is ME, use class_ctx directly
        if (object.data == .me) {
            if (self.class_ctx) |cls| {
                if (cls.findField(member_name)) |field_info| {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "CLASS field access: {s}.{s} (offset {d})", .{ cls.name, member_name, field_info.offset }));
                    const field_addr = try self.builder.newTemp();
                    if (field_info.offset > 0) {
                        try self.builder.emitBinary(field_addr, "l", "add", "%me", try std.fmt.allocPrint(self.allocator, "{d}", .{field_info.offset}));
                    } else {
                        try self.builder.emit("    {s} =l copy %me\n", .{field_addr});
                    }
                    const dest = try self.builder.newTemp();
                    const load_type = field_info.type_desc.base_type.toQBEType();
                    try self.builder.emitLoad(dest, load_type, field_addr);
                    return dest;
                }
            }
        }

        const obj_addr = try self.emitExpression(object);

        // ── CLASS instance member access via variable ───────────────────
        const class_name = self.inferClassName(object);
        if (class_name) |cname| {
            var cu_buf: [128]u8 = undefined;
            const cu_len = @min(cname.len, cu_buf.len);
            for (0..cu_len) |i| cu_buf[i] = std.ascii.toUpper(cname[i]);
            const cu_name = cu_buf[0..cu_len];

            if (self.symbol_table.lookupClass(cu_name)) |cls| {
                if (cls.findField(member_name)) |field_info| {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "CLASS field access: {s}.{s} (offset {d})", .{ cls.name, member_name, field_info.offset }));
                    const field_addr = try self.builder.newTemp();
                    if (field_info.offset > 0) {
                        try self.builder.emitBinary(field_addr, "l", "add", obj_addr, try std.fmt.allocPrint(self.allocator, "{d}", .{field_info.offset}));
                    } else {
                        try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, obj_addr });
                    }
                    const dest = try self.builder.newTemp();
                    const load_type = field_info.type_desc.base_type.toQBEType();
                    try self.builder.emitLoad(dest, load_type, field_addr);
                    // SINGLE fields are loaded as 's' but the expression
                    // system works with 'd' (double).  Extend to double so
                    // that comparisons (ceqd) and arithmetic work correctly.
                    if (field_info.type_desc.base_type == .single) {
                        const dbl = try self.builder.newTemp();
                        try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
                        return dbl;
                    }
                    return dest;
                }
            }
        }

        // ── UDT member access ───────────────────────────────────────────
        const udt_name = self.inferUDTName(object);
        if (udt_name) |type_name| {
            if (self.symbol_table.lookupType(type_name)) |type_sym| {
                var offset: u32 = 0;
                for (type_sym.fields) |field| {
                    if (std.mem.eql(u8, field.name, member_name)) {
                        const field_addr = try self.builder.newTemp();
                        if (offset > 0) {
                            try self.builder.emitBinary(field_addr, "l", "add", obj_addr, try std.fmt.allocPrint(self.allocator, "{d}", .{offset}));
                        } else {
                            try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, obj_addr });
                        }
                        // If the field is itself a nested UDT stored inline,
                        // return the field address directly (don't load from it).
                        if (field.type_desc.base_type == .user_defined) {
                            return field_addr;
                        }
                        const dest = try self.builder.newTemp();
                        const load_type = field.type_desc.base_type.toQBEType();
                        try self.builder.emitLoad(dest, load_type, field_addr);
                        // SINGLE fields are loaded as 's' but the expression
                        // system works with 'd' (double).  Extend to double.
                        if (field.type_desc.base_type == .single) {
                            const dbl = try self.builder.newTemp();
                            try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
                            return dbl;
                        }
                        return dest;
                    }
                    // For nested UDTs, use the actual UDT size instead of 0
                    const field_size = if (field.type_desc.base_type == .user_defined)
                        self.type_manager.sizeOfUDT(field.type_name)
                    else
                        self.type_manager.sizeOf(field.type_desc.base_type);
                    offset += if (field_size == 0) 8 else field_size;
                }
            }
        }

        // Fallback: unknown member, load as double from base address.
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unresolved member .{s}", .{member_name}));
        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, "d", obj_addr);
        return dest;
    }

    /// Try to infer the CLASS name from an expression (for member/method access).
    fn inferClassName(self: *ExprEmitter, expr: *const ast.Expression) ?[]const u8 {
        switch (expr.data) {
            .variable => |v| {
                if (self.symbol_table.lookupVariable(v.name)) |vsym| {
                    if (vsym.type_desc.base_type == .class_instance and vsym.type_desc.is_class_type) {
                        return vsym.type_desc.class_name;
                    }
                }
                // Also try with uppercase key
                var vu_buf: [128]u8 = undefined;
                const vu_len = @min(v.name.len, vu_buf.len);
                for (0..vu_len) |i| vu_buf[i] = std.ascii.toUpper(v.name[i]);
                const vu_upper = vu_buf[0..vu_len];
                if (self.symbol_table.lookupVariable(vu_upper)) |vsym| {
                    if (vsym.type_desc.base_type == .class_instance and vsym.type_desc.is_class_type) {
                        return vsym.type_desc.class_name;
                    }
                }
                // Try function-scoped key: FUNCNAME.VARNAME
                // Local class instance variables inside METHOD/FUNCTION
                // bodies are registered with a scoped key in the symbol
                // table (e.g. "MAKEWRAPPER.W" for DIM w AS Wrapper
                // inside METHOD MakeWrapper).
                if (self.func_ctx) |fctx| {
                    var scoped_buf: [256]u8 = undefined;
                    const scoped = std.fmt.bufPrint(&scoped_buf, "{s}.{s}", .{ fctx.upper_name, vu_upper }) catch null;
                    if (scoped) |sk| {
                        if (self.symbol_table.lookupVariable(sk)) |vsym| {
                            if (vsym.type_desc.base_type == .class_instance and vsym.type_desc.is_class_type) {
                                return vsym.type_desc.class_name;
                            }
                        }
                    }
                }
                // Also try with the class_ctx method name as scope
                // (for locals inside CLASS METHOD bodies)
                if (self.method_name.len > 0) {
                    const mname = self.method_name;
                    var mu_buf: [128]u8 = undefined;
                    const mu_len = @min(mname.len, mu_buf.len);
                    for (0..mu_len) |mi| mu_buf[mi] = std.ascii.toUpper(mname[mi]);
                    var scoped_buf2: [256]u8 = undefined;
                    const scoped2 = std.fmt.bufPrint(&scoped_buf2, "{s}.{s}", .{ mu_buf[0..mu_len], vu_upper }) catch null;
                    if (scoped2) |sk2| {
                        if (self.symbol_table.lookupVariable(sk2)) |vsym| {
                            if (vsym.type_desc.base_type == .class_instance and vsym.type_desc.is_class_type) {
                                return vsym.type_desc.class_name;
                            }
                        }
                    }
                }
            },
            .array_access => |aa| {
                // Look up the array in the symbol table; if its element type
                // is class_instance, return the class name so that member
                // access and method dispatch work on array elements.
                var au_buf: [128]u8 = undefined;
                const au_len = @min(aa.name.len, au_buf.len);
                for (0..au_len) |i| au_buf[i] = std.ascii.toUpper(aa.name[i]);
                if (self.symbol_table.lookupArray(au_buf[0..au_len])) |arr_sym| {
                    if (arr_sym.element_type_desc.base_type == .class_instance and arr_sym.element_type_desc.is_class_type) {
                        return arr_sym.element_type_desc.class_name;
                    }
                }
            },
            .me => {
                if (self.class_ctx) |cls| return cls.name;
            },
            .new => |n| return n.class_name,
            else => {},
        }
        return null;
    }

    /// Infer the UDT type name for an expression that may be a variable,
    /// array_access, create, or a member_access that resolves to a nested
    /// UDT field.  This is used by inferExprType to determine the correct
    /// type for chained member accesses like O.I.V.
    fn inferUDTNameForExpr(self: *ExprEmitter, expr: *const ast.Expression) ?[]const u8 {
        // First try the basic inferUDTName
        const base = self.inferUDTName(expr);
        if (base != null) return base;

        // For member_access expressions, walk the chain to find the
        // nested UDT type name.  E.g. for O.I where I is of type Inner,
        // return "Inner".
        if (expr.data == .member_access) {
            const ma = expr.data.member_access;
            const obj_udt = self.inferUDTNameForExpr(ma.object);
            if (obj_udt) |parent_type| {
                if (self.symbol_table.lookupType(parent_type)) |tsym| {
                    for (tsym.fields) |field| {
                        if (std.mem.eql(u8, field.name, ma.member_name)) {
                            if (field.type_desc.base_type == .user_defined) {
                                return if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                            }
                            return null; // field is not a UDT
                        }
                    }
                }
            }
        }
        return null;
    }

    /// Try to infer the UDT type name from an expression (for member access).
    fn inferUDTName(self: *ExprEmitter, expr: *const ast.Expression) ?[]const u8 {
        switch (expr.data) {
            .variable => |v| {
                // Look up in symbol table (try original name first)
                if (self.symbol_table.lookupVariable(v.name)) |vsym| {
                    if (vsym.type_desc.base_type == .user_defined) {
                        return vsym.type_desc.udt_name;
                    }
                }
                // Also try with uppercase key
                var vu_buf: [128]u8 = undefined;
                const vu_len = @min(v.name.len, vu_buf.len);
                for (0..vu_len) |i| vu_buf[i] = std.ascii.toUpper(v.name[i]);
                const vu_upper = vu_buf[0..vu_len];
                if (self.symbol_table.lookupVariable(vu_upper)) |vsym| {
                    if (vsym.type_desc.base_type == .user_defined) {
                        return vsym.type_desc.udt_name;
                    }
                }
                // Try function-scoped key: FUNCNAME.VARNAME
                if (self.func_ctx) |fctx| {
                    var scoped_buf: [256]u8 = undefined;
                    const scoped = std.fmt.bufPrint(&scoped_buf, "{s}.{s}", .{ fctx.upper_name, vu_upper }) catch null;
                    if (scoped) |sk| {
                        if (self.symbol_table.lookupVariable(sk)) |vsym| {
                            if (vsym.type_desc.base_type == .user_defined) {
                                return vsym.type_desc.udt_name;
                            }
                        }
                    }
                }
            },
            .array_access => |aa| {
                // Look up the array; if its element type is user_defined,
                // return the UDT name so member access works on array elements.
                var au_buf: [128]u8 = undefined;
                const au_len = @min(aa.name.len, au_buf.len);
                for (0..au_len) |i| au_buf[i] = std.ascii.toUpper(aa.name[i]);
                if (self.symbol_table.lookupArray(au_buf[0..au_len])) |arr_sym| {
                    if (arr_sym.element_type_desc.base_type == .user_defined) {
                        return arr_sym.element_type_desc.udt_name;
                    }
                }
            },
            .member_access => |ma| {
                // For chained member access (e.g. O.I where I is a UDT field),
                // infer the parent UDT and then find the field's UDT type.
                const parent_udt = self.inferUDTName(ma.object);
                if (parent_udt) |parent_type_name| {
                    if (self.symbol_table.lookupType(parent_type_name)) |type_sym| {
                        for (type_sym.fields) |field| {
                            if (std.mem.eql(u8, field.name, ma.member_name)) {
                                if (field.type_desc.base_type == .user_defined) {
                                    return field.type_desc.udt_name;
                                }
                                break;
                            }
                        }
                    }
                }
            },
            .create => |cr| return cr.type_name,
            else => {},
        }
        return null;
    }

    fn emitMethodCall(self: *ExprEmitter, object: *const ast.Expression, method_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        // ── ME.Method() calls inside class body ─────────────────────────
        if (object.data == .me) {
            if (self.class_ctx) |cls| {
                if (cls.findMethod(method_name)) |method_info| {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "ME.{s}() - direct call", .{method_name}));

                    var call_args: std.ArrayList(u8) = .empty;
                    defer call_args.deinit(self.allocator);
                    try call_args.appendSlice(self.allocator, "l %me");

                    for (arguments, 0..) |arg, ai| {
                        try call_args.appendSlice(self.allocator, ", ");
                        var arg_val = try self.emitExpression(arg);
                        const arg_type = if (ai < method_info.parameter_types.len)
                            method_info.parameter_types[ai].toQBEType()
                        else
                            "l";
                        // Convert argument to match declared parameter type
                        const expr_et = self.inferExprType(arg);
                        if (std.mem.eql(u8, arg_type, "d") and expr_et == .integer) {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                            arg_val = cvt;
                        } else if (std.mem.eql(u8, arg_type, "w") and expr_et == .double) {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "w", "dtosi", arg_val);
                            arg_val = cvt;
                        }
                        try std.fmt.format(call_args.writer(self.allocator), "{s} {s}", .{ arg_type, arg_val });
                    }

                    const ret_type = if (method_info.return_type.base_type != .void)
                        method_info.return_type.toQBEType()
                    else
                        "";

                    if (ret_type.len > 0) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, ret_type, method_info.mangled_name, call_args.items);
                        return dest;
                    } else {
                        try self.builder.emitCall("", "", method_info.mangled_name, call_args.items);
                        const dest = try self.builder.newTemp();
                        try self.builder.emit("    {s} =w copy 0\n", .{dest});
                        return dest;
                    }
                }
            }
        }

        const obj_val = try self.emitExpression(object);

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        // ── Hashmap method calls ────────────────────────────────────────
        if (object.data == .variable) {
            const var_name = object.data.variable.name;
            if (self.isHashmapVariable(var_name)) {
                var mup_buf: [64]u8 = undefined;
                const mlen = @min(method_name.len, mup_buf.len);
                for (0..mlen) |mi| mup_buf[mi] = std.ascii.toUpper(method_name[mi]);
                const mupper = mup_buf[0..mlen];

                if (std.mem.eql(u8, mupper, "HASKEY")) {
                    if (arguments.len >= 1) {
                        const key_val = try self.emitExpression(arguments[0]);
                        const cstr = try self.builder.newTemp();
                        try self.builder.emitCall(cstr, "l", "string_to_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{key_val}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "w", "hashmap_has_key", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, cstr }));
                        return dest;
                    }
                } else if (std.mem.eql(u8, mupper, "SIZE")) {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitCall(dest, "l", "hashmap_size", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    const dest_w = try self.builder.newTemp();
                    try self.builder.emitTrunc(dest_w, "w", dest);
                    return dest_w;
                } else if (std.mem.eql(u8, mupper, "REMOVE")) {
                    if (arguments.len >= 1) {
                        const key_val = try self.emitExpression(arguments[0]);
                        const cstr = try self.builder.newTemp();
                        try self.builder.emitCall(cstr, "l", "string_to_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{key_val}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "w", "hashmap_remove", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, cstr }));
                        return dest;
                    }
                } else if (std.mem.eql(u8, mupper, "CLEAR")) {
                    try self.builder.emitCall("", "", "hashmap_clear", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    const dest = try self.builder.newTemp();
                    try self.builder.emit("    {s} =w copy 0\n", .{dest});
                    return dest;
                } else if (std.mem.eql(u8, mupper, "KEYS")) {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitCall(dest, "l", "hashmap_keys", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    return dest;
                } else {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unknown HASHMAP method .{s}", .{method_name}));
                }
            }
        }

        // ── List method calls ───────────────────────────────────────────
        if (object.data == .variable) {
            const lv_name = object.data.variable.name;
            if (self.isListVariable(lv_name)) {
                var lmup_buf: [64]u8 = undefined;
                const lmlen = @min(method_name.len, lmup_buf.len);
                for (0..lmlen) |lmi| lmup_buf[lmi] = std.ascii.toUpper(method_name[lmi]);
                const lmupper = lmup_buf[0..lmlen];
                const elt = self.listElementType(lv_name);

                if (std.mem.eql(u8, lmupper, "APPEND")) {
                    if (arguments.len >= 1) {
                        const arg_val = try self.emitExpression(arguments[0]);
                        if (elt.isString()) {
                            try self.builder.emitCall("", "", "list_append_string", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, arg_val }));
                        } else if (elt.isFloat() or elt == .single) {
                            // Ensure value is double for list_append_float
                            const arg_et = self.inferExprType(arguments[0]);
                            const fval = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            try self.builder.emitCall("", "", "list_append_float", try std.fmt.allocPrint(self.allocator, "l {s}, d {s}", .{ obj_val, fval }));
                        } else {
                            // integer or unknown → list_append_int (int64_t)
                            const arg_et = self.inferExprType(arguments[0]);
                            const ival = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                                break :blk cvt;
                            } else if (arg_et == .double) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "l", "dtosi", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            try self.builder.emitCall("", "", "list_append_int", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, ival }));
                        }
                    }
                    const dest = try self.builder.newTemp();
                    try self.builder.emit("    {s} =w copy 0\n", .{dest});
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "PREPEND")) {
                    if (arguments.len >= 1) {
                        const arg_val = try self.emitExpression(arguments[0]);
                        if (elt.isString()) {
                            try self.builder.emitCall("", "", "list_prepend_string", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, arg_val }));
                        } else if (elt.isFloat() or elt == .single) {
                            const arg_et = self.inferExprType(arguments[0]);
                            const fval = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            try self.builder.emitCall("", "", "list_prepend_float", try std.fmt.allocPrint(self.allocator, "l {s}, d {s}", .{ obj_val, fval }));
                        } else {
                            const arg_et = self.inferExprType(arguments[0]);
                            const ival = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                                break :blk cvt;
                            } else if (arg_et == .double) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "l", "dtosi", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            try self.builder.emitCall("", "", "list_prepend_int", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, ival }));
                        }
                    }
                    const dest = try self.builder.newTemp();
                    try self.builder.emit("    {s} =w copy 0\n", .{dest});
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "LENGTH")) {
                    const raw = try self.builder.newTemp();
                    try self.builder.emitCall(raw, "l", "list_length", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    // Truncate int64_t → w for ExprType.integer
                    const dest = try self.builder.newTemp();
                    try self.builder.emitTrunc(dest, "w", raw);
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "EMPTY")) {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitCall(dest, "w", "list_empty", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "HEAD")) {
                    if (elt.isString()) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "l", "list_head_ptr", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else if (elt.isFloat() or elt == .single) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "d", "list_head_float", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else {
                        const raw = try self.builder.newTemp();
                        try self.builder.emitCall(raw, "l", "list_head_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitTrunc(dest, "w", raw);
                        return dest;
                    }
                } else if (std.mem.eql(u8, lmupper, "GET")) {
                    if (arguments.len >= 1) {
                        const idx_val = try self.emitExpression(arguments[0]);
                        const idx_et = self.inferExprType(arguments[0]);
                        // Position argument is int64_t (l)
                        const idx_l = if (idx_et == .integer) blk: {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitExtend(cvt, "l", "extsw", idx_val);
                            break :blk cvt;
                        } else if (idx_et == .double) blk: {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "l", "dtosi", idx_val);
                            break :blk cvt;
                        } else idx_val;
                        if (elt.isString()) {
                            const dest = try self.builder.newTemp();
                            try self.builder.emitCall(dest, "l", "list_get_ptr", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, idx_l }));
                            return dest;
                        } else if (elt.isFloat() or elt == .single) {
                            const dest = try self.builder.newTemp();
                            try self.builder.emitCall(dest, "d", "list_get_float", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, idx_l }));
                            return dest;
                        } else {
                            const raw = try self.builder.newTemp();
                            try self.builder.emitCall(raw, "l", "list_get_int", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, idx_l }));
                            const dest = try self.builder.newTemp();
                            try self.builder.emitTrunc(dest, "w", raw);
                            return dest;
                        }
                    }
                } else if (std.mem.eql(u8, lmupper, "CONTAINS")) {
                    if (arguments.len >= 1) {
                        const arg_val = try self.emitExpression(arguments[0]);
                        if (elt.isString()) {
                            const dest = try self.builder.newTemp();
                            try self.builder.emitCall(dest, "w", "list_contains_string", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, arg_val }));
                            return dest;
                        } else if (elt.isFloat() or elt == .single) {
                            const arg_et = self.inferExprType(arguments[0]);
                            const fval = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            const dest = try self.builder.newTemp();
                            try self.builder.emitCall(dest, "w", "list_contains_float", try std.fmt.allocPrint(self.allocator, "l {s}, d {s}", .{ obj_val, fval }));
                            return dest;
                        } else {
                            const arg_et = self.inferExprType(arguments[0]);
                            const ival = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                                break :blk cvt;
                            } else if (arg_et == .double) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "l", "dtosi", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            const dest = try self.builder.newTemp();
                            try self.builder.emitCall(dest, "w", "list_contains_int", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, ival }));
                            return dest;
                        }
                    }
                } else if (std.mem.eql(u8, lmupper, "INDEXOF")) {
                    if (arguments.len >= 1) {
                        const arg_val = try self.emitExpression(arguments[0]);
                        if (elt.isString()) {
                            const raw = try self.builder.newTemp();
                            try self.builder.emitCall(raw, "l", "list_indexof_string", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, arg_val }));
                            const dest = try self.builder.newTemp();
                            try self.builder.emitTrunc(dest, "w", raw);
                            return dest;
                        } else if (elt.isFloat() or elt == .single) {
                            const arg_et = self.inferExprType(arguments[0]);
                            const fval = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            const raw = try self.builder.newTemp();
                            try self.builder.emitCall(raw, "l", "list_indexof_float", try std.fmt.allocPrint(self.allocator, "l {s}, d {s}", .{ obj_val, fval }));
                            const dest = try self.builder.newTemp();
                            try self.builder.emitTrunc(dest, "w", raw);
                            return dest;
                        } else {
                            const arg_et = self.inferExprType(arguments[0]);
                            const ival = if (arg_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                                break :blk cvt;
                            } else if (arg_et == .double) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "l", "dtosi", arg_val);
                                break :blk cvt;
                            } else arg_val;
                            const raw = try self.builder.newTemp();
                            try self.builder.emitCall(raw, "l", "list_indexof_int", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, ival }));
                            const dest = try self.builder.newTemp();
                            try self.builder.emitTrunc(dest, "w", raw);
                            return dest;
                        }
                    }
                } else if (std.mem.eql(u8, lmupper, "SHIFT")) {
                    if (elt.isString()) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "l", "list_shift_ptr", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else if (elt.isFloat() or elt == .single) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "d", "list_shift_float", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else {
                        const raw = try self.builder.newTemp();
                        try self.builder.emitCall(raw, "l", "list_shift_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitTrunc(dest, "w", raw);
                        return dest;
                    }
                } else if (std.mem.eql(u8, lmupper, "POP")) {
                    if (elt.isString()) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "l", "list_pop_ptr", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else if (elt.isFloat() or elt == .single) {
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "d", "list_pop_float", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        return dest;
                    } else {
                        const raw = try self.builder.newTemp();
                        try self.builder.emitCall(raw, "l", "list_pop_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitTrunc(dest, "w", raw);
                        return dest;
                    }
                } else if (std.mem.eql(u8, lmupper, "JOIN")) {
                    if (arguments.len >= 1) {
                        const sep_val = try self.emitExpression(arguments[0]);
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "l", "list_join", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, sep_val }));
                        return dest;
                    } else {
                        // No separator — use empty string
                        const empty_label = try self.builder.registerString("");
                        const empty_tmp = try self.builder.newTemp();
                        try self.builder.emit("    {s} =l copy ${s}\n", .{ empty_tmp, empty_label });
                        const empty_sd = try self.builder.newTemp();
                        try self.builder.emitCall(empty_sd, "l", "string_new_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{empty_tmp}));
                        const dest = try self.builder.newTemp();
                        try self.builder.emitCall(dest, "l", "list_join", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, empty_sd }));
                        return dest;
                    }
                } else if (std.mem.eql(u8, lmupper, "REMOVE")) {
                    if (arguments.len >= 1) {
                        const idx_val = try self.emitExpression(arguments[0]);
                        const idx_et = self.inferExprType(arguments[0]);
                        const idx_l = if (idx_et == .integer) blk: {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitExtend(cvt, "l", "extsw", idx_val);
                            break :blk cvt;
                        } else if (idx_et == .double) blk: {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "l", "dtosi", idx_val);
                            break :blk cvt;
                        } else idx_val;
                        try self.builder.emitCall("", "", "list_remove", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ obj_val, idx_l }));
                    }
                    const dest = try self.builder.newTemp();
                    try self.builder.emit("    {s} =w copy 0\n", .{dest});
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "CLEAR")) {
                    try self.builder.emitCall("", "", "list_clear", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    const dest = try self.builder.newTemp();
                    try self.builder.emit("    {s} =w copy 0\n", .{dest});
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "COPY")) {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitCall(dest, "l", "list_copy", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    return dest;
                } else if (std.mem.eql(u8, lmupper, "REVERSE")) {
                    const dest = try self.builder.newTemp();
                    try self.builder.emitCall(dest, "l", "list_reverse", try std.fmt.allocPrint(self.allocator, "l {s}", .{obj_val}));
                    return dest;
                } else {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unknown LIST method .{s}", .{method_name}));
                }
            }
        }

        // ── CLASS vtable dispatch ───────────────────────────────────────
        const class_name = self.inferClassName(object);
        if (class_name) |cname| {
            var cu_buf: [128]u8 = undefined;
            const cu_len = @min(cname.len, cu_buf.len);
            for (0..cu_len) |i| cu_buf[i] = std.ascii.toUpper(cname[i]);
            const cu_name = cu_buf[0..cu_len];

            if (self.symbol_table.lookupClass(cu_name)) |cls| {
                if (cls.findMethod(method_name)) |method_info| {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "vtable dispatch: {s}.{s}() slot={d}", .{ cls.name, method_name, method_info.vtable_slot }));

                    // Load vtable pointer from object[0]
                    const vtable_ptr = try self.builder.newTemp();
                    try self.builder.emitLoad(vtable_ptr, "l", obj_val);

                    // Compute method slot address: vtable + 32 + slot * 8
                    const slot_offset = 32 + method_info.vtable_slot * 8;
                    const slot_addr = try self.builder.newTemp();
                    try self.builder.emitBinary(slot_addr, "l", "add", vtable_ptr, try std.fmt.allocPrint(self.allocator, "{d}", .{slot_offset}));

                    // Load method function pointer
                    const method_ptr = try self.builder.newTemp();
                    try self.builder.emitLoad(method_ptr, "l", slot_addr);

                    // Build argument list: obj as first arg (ME), then user args
                    var call_args: std.ArrayList(u8) = .empty;
                    defer call_args.deinit(self.allocator);
                    try std.fmt.format(call_args.writer(self.allocator), "l {s}", .{obj_val});

                    for (arguments, 0..) |arg, ai| {
                        try call_args.appendSlice(self.allocator, ", ");
                        var arg_val = try self.emitExpression(arg);
                        const arg_type = if (ai < method_info.parameter_types.len)
                            method_info.parameter_types[ai].toQBEType()
                        else
                            "l";
                        // Convert argument to match declared parameter type
                        const expr_et = self.inferExprType(arg);
                        if (std.mem.eql(u8, arg_type, "d") and expr_et == .integer) {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                            arg_val = cvt;
                        } else if (std.mem.eql(u8, arg_type, "w") and expr_et == .double) {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitConvert(cvt, "w", "dtosi", arg_val);
                            arg_val = cvt;
                        } else if (std.mem.eql(u8, arg_type, "l") and expr_et == .integer) {
                            const cvt = try self.builder.newTemp();
                            try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                            arg_val = cvt;
                        }
                        try std.fmt.format(call_args.writer(self.allocator), "{s} {s}", .{ arg_type, arg_val });
                    }

                    const ret_type = if (method_info.return_type.base_type != .void)
                        method_info.return_type.toQBEType()
                    else
                        "";

                    // Indirect call through function pointer
                    if (ret_type.len > 0) {
                        const dest = try self.builder.newTemp();
                        // QBE indirect call syntax: %dest =<type> call %fn_ptr(args)
                        try self.builder.emit("    {s} ={s} call {s}({s})\n", .{ dest, ret_type, method_ptr, call_args.items });
                        return dest;
                    } else {
                        try self.builder.emit("    call {s}({s})\n", .{ method_ptr, call_args.items });
                        const dest = try self.builder.newTemp();
                        try self.builder.emit("    {s} =w copy 0\n", .{dest});
                        return dest;
                    }
                }
            }
        }

        // ── Fallback: direct call with mangled name ─────────────────────
        try std.fmt.format(args_buf.writer(self.allocator), "l {s}", .{obj_val});
        for (arguments) |arg| {
            try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.emitExpression(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "d {s}", .{arg_val});
        }

        const dest = try self.builder.newTemp();
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unresolved method call .{s}", .{method_name}));
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }

    fn emitArrayAccess(self: *ExprEmitter, name: []const u8, indices: []const ast.ExprPtr, suffix: ?Tag) EmitError![]const u8 {
        if (indices.len == 0) {
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
            return dest;
        }

        // ── Hashmap subscript: dict("key") → hashmap_lookup ─────────
        if (self.isHashmapVariable(name)) {
            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "HASHMAP lookup: {s}(...)", .{name}));

            // Load the hashmap pointer from the global variable
            const var_name = try self.symbol_mapper.globalVarName(name, null);
            const map_ptr = try self.builder.newTemp();
            try self.builder.emitLoad(map_ptr, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));

            // Evaluate the key expression (must be a string descriptor)
            const key_val = try self.emitExpression(indices[0]);

            // Convert StringDescriptor* → C string (char*) for hashmap API
            const key_cstr = try self.builder.newTemp();
            try self.builder.emitCall(key_cstr, "l", "string_to_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{key_val}));

            // Call hashmap_lookup(map, key_cstr) → returns value pointer (l)
            const result = try self.builder.newTemp();
            try self.builder.emitCall(result, "l", "hashmap_lookup", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ map_ptr, key_cstr }));

            // The returned value is a StringDescriptor* (for string hashmaps)
            return result;
        }

        // ── Regular array access ────────────────────────────────────────
        const index_val = try self.emitExpression(indices[0]);
        // Convert index to integer if needed
        const idx_type = self.inferExprType(indices[0]);
        const index_int = if (idx_type == .integer) index_val else blk: {
            const t = try self.builder.newTemp();
            try self.builder.emitConvert(t, "w", "dtosi", index_val);
            break :blk t;
        };

        const desc_name = try self.symbol_mapper.arrayDescName(name);
        const desc_addr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr, desc_name });

        // Bounds check
        const bc_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
        try self.builder.emitCall("", "", "fbc_array_bounds_check", bc_args);

        const elem_addr = try self.builder.newTemp();
        const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
        try self.builder.emitCall(elem_addr, "l", "fbc_array_element_addr", ea_args);

        // Determine element type: prefer the declared array element type
        // from the symbol table over the suffix.  This is critical for
        // typed arrays such as DIM a(10) AS Animal (class_instance → "l")
        // which would otherwise fall back to double/"d" from a null suffix.
        var load_type: []const u8 = undefined;
        {
            var ean_buf: [128]u8 = undefined;
            const ean_len = @min(name.len, ean_buf.len);
            for (0..ean_len) |ei| ean_buf[ei] = std.ascii.toUpper(name[ei]);
            if (self.symbol_table.lookupArray(ean_buf[0..ean_len])) |arr_sym| {
                if (arr_sym.element_type_desc.base_type != .unknown) {
                    // For inline UDT array elements, the element address
                    // IS the struct address — return it directly without
                    // loading (the data is stored inline, not as a pointer).
                    if (arr_sym.element_type_desc.base_type == .user_defined) {
                        return elem_addr;
                    }
                    load_type = arr_sym.element_type_desc.base_type.toQBEType();
                } else {
                    load_type = semantic.baseTypeFromSuffix(suffix).toQBEType();
                }
            } else {
                load_type = semantic.baseTypeFromSuffix(suffix).toQBEType();
            }
        }

        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, load_type, elem_addr);
        // SINGLE array elements are loaded as 's' but the expression
        // system expects 'd'. Promote to double.
        if (std.mem.eql(u8, load_type, "s")) {
            const dbl = try self.builder.newTemp();
            try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, dest });
            return dbl;
        }
        return dest;
    }

    fn emitCreate(self: *ExprEmitter, type_name: []const u8, arguments: []const ast.ExprPtr, is_named: bool, field_names: []const []const u8) EmitError![]const u8 {
        const udt_size = self.type_manager.sizeOfUDT(type_name);
        const size: u32 = if (udt_size == 0) 16 else udt_size;

        const addr = try self.builder.newTemp();
        try self.builder.emitAlloc(addr, size, 8);

        const ts = self.symbol_table.lookupType(type_name);
        if (ts) |type_sym| {
            var offset: u32 = 0;
            for (type_sym.fields, 0..) |field, i| {
                const field_addr = try self.builder.newTemp();
                try self.builder.emitBinary(field_addr, "l", "add", addr, try std.fmt.allocPrint(self.allocator, "{d}", .{offset}));

                // Determine which argument supplies this field's value.
                // For positional CREATE: argument i maps to field i.
                // For named CREATE: look up the argument by field name;
                // if the field isn't mentioned, use default zero.
                const arg_idx: ?usize = if (is_named) blk: {
                    for (field_names, 0..) |fn_name, ai| {
                        if (std.ascii.eqlIgnoreCase(fn_name, field.name)) {
                            break :blk ai;
                        }
                    }
                    break :blk null;
                } else if (i < arguments.len) i else null;

                if (arg_idx) |ai| {
                    const val = try self.emitExpression(arguments[ai]);
                    const field_bt = field.type_desc.base_type;
                    const store_type = field_bt.toQBEMemOp();

                    // Apply type coercion: the argument expression type may
                    // differ from the field type (e.g. integer literal → SINGLE
                    // field, or double literal → SINGLE field).  QBE requires
                    // the operand type to match the store type exactly.
                    const arg_et = self.inferExprType(arguments[ai]);
                    var store_val = val;

                    if (field_bt == .single) {
                        // Target is SINGLE (s): convert from double or integer
                        if (arg_et == .double) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emit("    {s} =s truncd {s}\n", .{ tmp, val });
                            store_val = tmp;
                        } else if (arg_et == .integer) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emit("    {s} =s swtof {s}\n", .{ tmp, val });
                            store_val = tmp;
                        }
                    } else if (field_bt == .double) {
                        // Target is DOUBLE (d): convert from integer or single
                        if (arg_et == .integer) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emit("    {s} =d swtof {s}\n", .{ tmp, val });
                            store_val = tmp;
                        }
                    } else if (field_bt == .integer or field_bt == .uinteger) {
                        // Target is INTEGER (w): convert from double
                        if (arg_et == .double) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emitConvert(tmp, "w", "dtosi", val);
                            store_val = tmp;
                        }
                    } else if (field_bt == .long or field_bt == .ulong) {
                        // Target is LONG (l): convert from integer or double
                        if (arg_et == .integer) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emitExtend(tmp, "l", "extsw", val);
                            store_val = tmp;
                        } else if (arg_et == .double) {
                            const tmp = try self.builder.newTemp();
                            try self.builder.emitConvert(tmp, "l", "dtosi", val);
                            store_val = tmp;
                        }
                    } else if (field_bt == .string or field_bt == .unicode) {
                        // String field: retain the new string
                        const retain_args = try std.fmt.allocPrint(self.allocator, "l {s}", .{val});
                        try self.builder.emitCall("", "", "string_retain", retain_args);
                    }

                    try self.builder.emitStore(store_type, store_val, field_addr);
                } else {
                    // Default zero-initialisation for unmentioned fields
                    const field_bt = field.type_desc.base_type;
                    const store_type = field_bt.toQBEMemOp();
                    if (field_bt == .single) {
                        try self.builder.emitStore(store_type, "s_0.0", field_addr);
                    } else if (field_bt == .double) {
                        try self.builder.emitStore(store_type, "d_0.0", field_addr);
                    } else {
                        try self.builder.emitStore(store_type, "0", field_addr);
                    }
                }

                offset += self.type_manager.sizeOf(field.type_desc.base_type);
            }
        } else {
            try self.builder.emitComment("WARNING: unknown type in CREATE, zero-filling");
        }

        return addr;
    }

    fn emitNew(self: *ExprEmitter, class_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        const vtable_label = try self.symbol_mapper.vtableName(class_name);
        const vtable_addr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ vtable_addr, vtable_label });

        // Look up class symbol (try exact name and uppercase)
        var cu_buf: [128]u8 = undefined;
        const cu_len = @min(class_name.len, cu_buf.len);
        for (0..cu_len) |i| cu_buf[i] = std.ascii.toUpper(class_name[i]);
        const cu_name = cu_buf[0..cu_len];

        const cls = self.symbol_table.lookupClass(cu_name);
        const obj_size: i32 = if (cls) |c| c.object_size else semantic.ClassSymbol.header_size;
        const class_id: i32 = if (cls) |c| c.class_id else 0;

        const obj = try self.builder.newTemp();
        const alloc_args = try std.fmt.allocPrint(self.allocator, "l {d}, l {s}, l {d}", .{ obj_size, vtable_addr, class_id });
        try self.builder.emitCall(obj, "l", "class_object_new", alloc_args);

        // Call constructor if the class has one
        if (cls) |c| {
            if (c.has_constructor and c.constructor_mangled_name.len > 0) {
                var ctor_args: std.ArrayList(u8) = .empty;
                defer ctor_args.deinit(self.allocator);
                try std.fmt.format(ctor_args.writer(self.allocator), "l {s}", .{obj});

                for (arguments, 0..) |arg, ai| {
                    try ctor_args.appendSlice(self.allocator, ", ");
                    var arg_val = try self.emitExpression(arg);
                    const arg_type = if (ai < c.constructor_param_types.len)
                        c.constructor_param_types[ai].toQBEType()
                    else
                        "l";
                    // Convert argument to match declared parameter type
                    const expr_et = self.inferExprType(arg);
                    if (std.mem.eql(u8, arg_type, "d") and expr_et == .integer) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "d", "swtof", arg_val);
                        arg_val = cvt;
                    } else if (std.mem.eql(u8, arg_type, "w") and expr_et == .double) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitConvert(cvt, "w", "dtosi", arg_val);
                        arg_val = cvt;
                    } else if (std.mem.eql(u8, arg_type, "l") and expr_et == .integer) {
                        const cvt = try self.builder.newTemp();
                        try self.builder.emitExtend(cvt, "l", "extsw", arg_val);
                        arg_val = cvt;
                    }
                    try std.fmt.format(ctor_args.writer(self.allocator), "{s} {s}", .{ arg_type, arg_val });
                }

                try self.builder.emitCall("", "", c.constructor_mangled_name, ctor_args.items);
            }
        }

        return obj;
    }

    fn emitMe(_: *ExprEmitter) EmitError![]const u8 {
        return "%me";
    }

    fn emitNothing(self: *ExprEmitter) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
    }

    fn emitIsType(self: *ExprEmitter, object: *const ast.Expression, class_name: []const u8, is_nothing_check: bool) EmitError![]const u8 {
        const obj_val = try self.emitExpression(object);
        const dest = try self.builder.newTemp();

        if (is_nothing_check) {
            try self.builder.emitCompare(dest, "l", "eq", obj_val, "0");
        } else {
            // Runtime IS type check via class_is_instance
            var cu_buf: [128]u8 = undefined;
            const cu_len = @min(class_name.len, cu_buf.len);
            for (0..cu_len) |i| cu_buf[i] = std.ascii.toUpper(class_name[i]);
            const cu_name = cu_buf[0..cu_len];

            const target_id: i32 = if (self.symbol_table.lookupClass(cu_name)) |cls| cls.class_id else 0;
            const is_args = try std.fmt.allocPrint(self.allocator, "l {s}, l {d}", .{ obj_val, target_id });
            try self.builder.emitCall(dest, "w", "class_is_instance", is_args);
        }
        return dest;
    }

    fn emitSuperCall(self: *ExprEmitter, method_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = method_name;
        _ = arguments;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: SUPER call");
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }

    fn emitListConstructor(self: *ExprEmitter, elements: []const ast.ExprPtr) EmitError![]const u8 {
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "LIST({d} elements)", .{elements.len}));

        // Create a new list via list_create()
        const header_ptr = try self.builder.newTemp();
        try self.builder.emitCall(header_ptr, "l", "list_create", "");

        // Append each element using the type-specific list_append_* function
        for (elements) |elem| {
            const elem_val = try self.emitExpression(elem);
            const elem_type = self.inferExprType(elem);

            // Check if this element is an object/class pointer rather than
            // a numeric double.  NEW expressions, CREATE expressions, and
            // class-instance variables all produce pointer-sized (l) values
            // that must use list_append_object, not list_append_float.
            const is_object = switch (elem.data) {
                .new => true,
                .create => true,
                .variable => |v| blk_var: {
                    var vu_buf: [128]u8 = undefined;
                    const vbase = SymbolMapper.stripSuffix(v.name);
                    const vlen = @min(vbase.len, vu_buf.len);
                    for (0..vlen) |vi| vu_buf[vi] = std.ascii.toUpper(vbase[vi]);
                    if (self.symbol_table.lookupVariable(vu_buf[0..vlen])) |vsym| {
                        if (vsym.type_desc.base_type == .class_instance or
                            vsym.type_desc.base_type == .object or
                            vsym.type_desc.base_type == .user_defined)
                        {
                            break :blk_var true;
                        }
                    }
                    break :blk_var false;
                },
                .list_constructor => true,
                else => false,
            };

            if (is_object) {
                // Object/class pointer → list_append_object(list, ptr)
                const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ header_ptr, elem_val });
                try self.builder.emitCall("", "", "list_append_object", args);
            } else switch (elem_type) {
                .double => {
                    // Float/double value → list_append_float(list, double)
                    const args = try std.fmt.allocPrint(self.allocator, "l {s}, d {s}", .{ header_ptr, elem_val });
                    try self.builder.emitCall("", "", "list_append_float", args);
                },
                .string => {
                    // String descriptor → list_append_string(list, str_desc)
                    const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ header_ptr, elem_val });
                    try self.builder.emitCall("", "", "list_append_string", args);
                },
                .integer => {
                    // Integer value → widen to 64-bit, then list_append_int(list, long)
                    const long_val = try self.builder.newTemp();
                    try self.builder.emitExtend(long_val, "l", "extsw", elem_val);
                    const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ header_ptr, long_val });
                    try self.builder.emitCall("", "", "list_append_int", args);
                },
            }
        }

        return header_ptr;
    }

    fn emitArrayBinop(self: *ExprEmitter, left: *const ast.Expression, operation: ast.ArrayBinopExpr.OpType, right: *const ast.Expression) EmitError![]const u8 {
        _ = operation;
        _ = left;
        _ = right;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: array binary operation");
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
    }

    fn emitRegistryFunction(self: *ExprEmitter, name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = arguments;
        _ = name;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: registry function call");
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// BlockEmitter — Emits statements and terminators for basic blocks
// ═══════════════════════════════════════════════════════════════════════════

/// Context saved when a FOR loop initialisation is emitted so that the
/// loop header and increment blocks can reference the variable, end value,
/// and step expression.
const ForLoopContext = struct {
    variable: []const u8,
    step_expr: ?*const ast.Expression,
    end_addr: []const u8,
    step_addr: []const u8,
};

/// Context for FOR EACH / FOR...IN loops.  Stores the hidden index
/// variable address, the array descriptor address, the iterator
/// variable name, and the optional index variable name.
const ForEachContext = struct {
    /// The iterator variable that receives array elements (e.g. "n").
    iter_variable: []const u8,
    /// Optional index variable (e.g. "idx" in `FOR item, idx IN arr`).
    index_variable: []const u8,
    /// Stack address of the hidden loop index (integer, w).
    index_addr: []const u8,
    /// Address of the array descriptor (l).
    array_desc_addr: []const u8,
    /// QBE load type for array elements ("w", "d", "l", etc.).
    elem_load_type: []const u8,
    /// The base type of array elements.
    elem_base_type: semantic.BaseType,
};

/// Context for FOR EACH / FOR...IN loops over HASHMAP collections.
/// Uses hashmap_keys() to get a NULL-terminated key array, then
/// iterates by index, loading each key and optionally looking up
/// the corresponding value.
const ForEachHashmapContext = struct {
    /// The iterator variable that receives hashmap keys (always string).
    key_variable: []const u8,
    /// Optional value variable (e.g. "v" in `FOR k, v IN dict`).
    value_variable: []const u8,
    /// Stack address of the hidden loop index (integer, w).
    index_addr: []const u8,
    /// Stack address holding the hashmap size (integer, w).
    size_addr: []const u8,
    /// Stack address holding the keys array pointer (l).
    keys_array_addr: []const u8,
    /// Stack address holding the hashmap pointer (l) for lookups.
    map_ptr_addr: []const u8,
};

/// Pre-allocated stack slots for FOR loop limit/step temporaries.
/// QBE requires all `alloc` instructions to appear in the function's
/// start block.  We scan the entire CFG for FOR statements before
/// emitting any blocks and emit the allocs in the prologue.
const ForPreAlloc = struct {
    limit_addr: []const u8,
    step_addr: []const u8,
};

/// Context saved when a SELECT CASE is emitted so that case_test blocks
/// can compare against the selector.
const CaseContext = struct {
    selector_temp: []const u8,
    selector_type: ExprEmitter.ExprType,
};

/// Emits code for the statements within a single basic block and emits
/// the block's terminator (branch / jump / return) based on CFG edges.
pub const BlockEmitter = struct {
    expr_emitter: *ExprEmitter,
    builder: *QBEBuilder,
    runtime: *RuntimeLibrary,
    symbol_mapper: *SymbolMapper,
    type_manager: *const TypeManager,
    symbol_table: *const semantic.SymbolTable,
    cfg: *const cfg_mod.CFG,
    allocator: std.mem.Allocator,

    // CLASS body context
    class_ctx: ?*const semantic.ClassSymbol = null,
    method_ret_slot: []const u8 = "",
    method_name: []const u8 = "",
    method_ret_type: semantic.TypeDescriptor = semantic.TypeDescriptor.fromBase(.void),

    func_ctx: ?*const FunctionContext = null,

    /// FOR loop contexts, keyed by the loop header block index.
    for_contexts: std.AutoHashMap(u32, ForLoopContext),

    /// FOR EACH loop contexts, keyed by the loop header block index.
    foreach_contexts: std.AutoHashMap(u32, ForEachContext),

    /// FOR EACH hashmap loop contexts, keyed by the loop header block index.
    foreach_hashmap_contexts: std.AutoHashMap(u32, ForEachHashmapContext),

    /// CASE selector contexts, keyed by the case entry block index.
    case_contexts: std.AutoHashMap(u32, CaseContext),

    /// Pre-allocated FOR loop slots, keyed by uppercase variable name.
    for_pre_allocs: std.StringHashMap(ForPreAlloc),

    /// Whether SAMM is enabled.
    samm_enabled: bool = true,

    const ExprType = ExprEmitter.ExprType;
    const EmitError = error{OutOfMemory};

    pub fn init(
        expr_emitter: *ExprEmitter,
        builder: *QBEBuilder,
        runtime: *RuntimeLibrary,
        symbol_mapper: *SymbolMapper,
        type_manager: *const TypeManager,
        symbol_table: *const semantic.SymbolTable,
        the_cfg: *const cfg_mod.CFG,
        allocator: std.mem.Allocator,
    ) BlockEmitter {
        return .{
            .expr_emitter = expr_emitter,
            .builder = builder,
            .runtime = runtime,
            .symbol_mapper = symbol_mapper,
            .type_manager = type_manager,
            .symbol_table = symbol_table,
            .cfg = the_cfg,
            .allocator = allocator,
            .for_contexts = std.AutoHashMap(u32, ForLoopContext).init(allocator),
            .foreach_contexts = std.AutoHashMap(u32, ForEachContext).init(allocator),
            .foreach_hashmap_contexts = std.AutoHashMap(u32, ForEachHashmapContext).init(allocator),
            .case_contexts = std.AutoHashMap(u32, CaseContext).init(allocator),
            .for_pre_allocs = std.StringHashMap(ForPreAlloc).init(allocator),
        };
    }

    pub fn deinit(self: *BlockEmitter) void {
        self.for_contexts.deinit();
        self.foreach_contexts.deinit();
        self.foreach_hashmap_contexts.deinit();
        self.case_contexts.deinit();
        self.for_pre_allocs.deinit();
    }

    /// Reset per-function state.
    pub fn resetContexts(self: *BlockEmitter) void {
        self.for_contexts.clearRetainingCapacity();
        self.foreach_contexts.clearRetainingCapacity();
        self.foreach_hashmap_contexts.clearRetainingCapacity();
        self.case_contexts.clearRetainingCapacity();
        self.for_pre_allocs.clearRetainingCapacity();
        self.func_ctx = null;
        self.expr_emitter.func_ctx = null;
    }

    /// Set the current function context on both the block emitter and its
    /// child expression emitter.
    pub fn setFunctionContext(self: *BlockEmitter, ctx: ?*const FunctionContext) void {
        self.func_ctx = ctx;
        self.expr_emitter.func_ctx = ctx;
    }

    // ── Variable address resolution ─────────────────────────────────────

    /// Resolve a variable name to its QBE address, checking function
    /// context (params/locals) first, then falling back to a global.
    /// Returns the address string (e.g. "%t.5" for locals or "$var_x" for
    /// globals) and the QBE store type.
    const ResolvedAddr = struct {
        addr: []const u8,
        store_type: []const u8,
        base_type: semantic.BaseType,
    };

    fn resolveVarAddr(self: *BlockEmitter, name: []const u8, suffix: ?Tag) EmitError!ResolvedAddr {
        if (self.func_ctx) |fctx| {
            var upper_buf: [128]u8 = undefined;
            const base = SymbolMapper.stripSuffix(name);
            const ulen = @min(base.len, upper_buf.len);
            for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
            const upper_base = upper_buf[0..ulen];

            if (fctx.resolve(upper_base)) |rv| {
                return .{
                    .addr = rv.addr,
                    .store_type = rv.base_type.toQBEMemOp(),
                    .base_type = rv.base_type,
                };
            }
        }

        // Fall back to global.
        // When suffix is null, first try to detect the suffix from the
        // variable name itself (e.g. "I%" → .percent), then consult the
        // symbol table for the registered type.
        var effective_suffix = suffix;
        if (effective_suffix == null and name.len > 0) {
            effective_suffix = switch (name[name.len - 1]) {
                '%' => @as(?Tag, .percent),
                '$' => @as(?Tag, .type_string),
                '#' => @as(?Tag, .hash),
                '!' => @as(?Tag, .exclamation),
                '&' => @as(?Tag, .ampersand),
                '^' => @as(?Tag, .caret),
                '@' => @as(?Tag, .at_suffix),
                else => @as(?Tag, null),
            };
        }
        var bt = semantic.baseTypeFromSuffix(effective_suffix);
        if (effective_suffix == null) {
            // No suffix from caller or name — consult the symbol table.
            // Try stripped name first, then original (with suffix char) to
            // handle both "DIM x AS INTEGER" and "FOR I% = ..." patterns.
            var sym_upper_buf: [128]u8 = undefined;
            const sym_base = SymbolMapper.stripSuffix(name);
            const slen = @min(sym_base.len, sym_upper_buf.len);
            for (0..slen) |si| sym_upper_buf[si] = std.ascii.toUpper(sym_base[si]);
            const sym_upper = sym_upper_buf[0..slen];
            const vsym = self.symbol_table.lookupVariable(sym_upper) orelse blk: {
                // Stripped name not found — try the full uppercased name
                // (symbol table may store key with suffix, e.g. "I%").
                var full_upper_buf: [128]u8 = undefined;
                const flen = @min(name.len, full_upper_buf.len);
                for (0..flen) |fi| full_upper_buf[fi] = std.ascii.toUpper(name[fi]);
                const full_upper = full_upper_buf[0..flen];
                break :blk self.symbol_table.lookupVariable(full_upper);
            };
            if (vsym) |vs| {
                bt = vs.type_desc.base_type;
                // Reconstruct suffix from base type so globalVarName
                // produces the same mangled name as emitGlobalVariables.
                effective_suffix = switch (bt) {
                    .integer => @as(?Tag, .type_int),
                    .single => @as(?Tag, .type_float),
                    .double => @as(?Tag, .type_double),
                    .string => @as(?Tag, .type_string),
                    .long => @as(?Tag, .ampersand),
                    .byte => @as(?Tag, .type_byte),
                    .short => @as(?Tag, .type_short),
                    else => @as(?Tag, null),
                };
            }
        }
        const var_name = try self.symbol_mapper.globalVarName(name, effective_suffix);
        return .{
            .addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}),
            .store_type = bt.toQBEMemOp(),
            .base_type = bt,
        };
    }

    /// Update the CFG pointer (used when switching between main/function CFGs).
    pub fn setCFG(self: *BlockEmitter, new_cfg: *const cfg_mod.CFG) void {
        self.cfg = new_cfg;
    }

    // ── Block Statement Emission ────────────────────────────────────────

    /// Emit all statements in a basic block. Control-flow statements that
    /// created this block's structure are handled specially (e.g. FOR init,
    /// CASE selector eval). Everything else emits normally.
    pub fn emitBlockStatements(self: *BlockEmitter, block: *const cfg_mod.BasicBlock) EmitError!void {
        for (block.statements.items) |stmt| {
            try self.emitStatement(stmt, block);
        }
    }

    /// Emit a single statement within a block context.
    fn emitStatement(self: *BlockEmitter, stmt: *const ast.Statement, block: *const cfg_mod.BasicBlock) EmitError!void {
        switch (stmt.data) {
            // ── Leaf statements: emit directly ──────────────────────────
            .print => |pr| try self.emitPrintStatement(&pr),
            .console => |con| try self.emitConsoleStatement(&con),
            .let => |lt| try self.emitLetStatement(&lt),
            .dim => |dim| try self.emitDimStatement(&dim),
            .call => |cs| try self.emitCallStatement(&cs),
            .return_stmt => |rs| try self.emitReturnStatement(&rs),
            .inc => |id| try self.emitIncDec(&id, true),
            .dec => |id| try self.emitIncDec(&id, false),
            .swap => |sw| try self.emitSwapStatement(&sw),
            .local => |loc_stmt| try self.emitLocalStatement(&loc_stmt),
            .shared => |sh_stmt| try self.emitSharedStatement(&sh_stmt),

            // ── Control-flow statements: handle structurally ────────────
            //
            // These statements created the block structure in the CFG.
            // We emit only the initialisation / setup they need; the
            // branching is handled by emitTerminator via CFG edges.

            .for_stmt => |fs| try self.emitForInit(&fs, block),
            .for_in => |fi| try self.emitForEachInit(&fi, block),
            .if_stmt => {}, // condition is in branch_condition; branching in terminator
            .while_stmt => {}, // condition is in branch_condition; branching in terminator
            .do_stmt => {}, // condition is in branch_condition; branching in terminator
            .repeat_stmt => {}, // body/condition in separate blocks
            .case_stmt => |cs| try self.emitCaseSelector(&cs, block),
            .try_catch => {}, // structure in CFG blocks

            // ── Terminators: handled by CFG edges ───────────────────────
            .goto_stmt => {}, // edge already in CFG
            .gosub => {}, // edge already in CFG
            .exit_stmt => {}, // edge already in CFG
            .end_stmt => {}, // edge already in CFG
            .on_goto => {}, // edges already in CFG
            .on_gosub => {}, // edges already in CFG

            // ── No-ops and declarations ─────────────────────────────────
            .rem => {},
            .option => {},
            .label => {}, // block labels handled by CFG
            .type_decl => {},
            .class => {},
            .data_stmt => {},
            .function => {}, // handled via function_cfgs
            .sub => {}, // handled via function_cfgs

            // ── Fallback ────────────────────────────────────────────────
            else => {
                try self.builder.emitComment("TODO: unhandled statement in block");
            },
        }
    }

    // ── Terminator Emission ─────────────────────────────────────────────

    /// Emit the block terminator based on the CFG's outgoing edges.
    pub fn emitTerminator(self: *BlockEmitter, block: *const cfg_mod.BasicBlock) EmitError!void {
        // Exit block: emit return
        if (block.kind == .exit_block) {
            // The return value (if any) should have been emitted by a
            // return_stmt in a predecessor. For the main function exit
            // block we return 0 as a default.
            return;
        }

        const edges = self.cfg.edges.items;

        // Gather outgoing edges from this block.
        var true_target: ?u32 = null;
        var false_target: ?u32 = null;
        var jump_target: ?u32 = null;
        var back_edge_target: ?u32 = null;
        var exit_target: ?u32 = null;
        var fallthrough_target: ?u32 = null;
        var loop_exit_target: ?u32 = null;
        var case_match_target: ?u32 = null;
        var case_next_target: ?u32 = null;
        var has_return_edge = false;
        var has_gosub_call = false;
        var gosub_target: ?u32 = null;

        for (edges) |edge| {
            if (edge.from != block.index) continue;
            switch (edge.kind) {
                .branch_true => true_target = edge.to,
                .branch_false => false_target = edge.to,
                .jump => jump_target = edge.to,
                .back_edge => back_edge_target = edge.to,
                .fallthrough => fallthrough_target = edge.to,
                .loop_exit => loop_exit_target = edge.to,
                .exit => exit_target = edge.to,
                .case_match => case_match_target = edge.to,
                .case_next => case_next_target = edge.to,
                .gosub_call => {
                    has_gosub_call = true;
                    gosub_target = edge.to;
                },
                .gosub_return => {}, // handled after gosub_call
                .exception => {}, // TRY/CATCH: handled below
                .finally => {}, // TRY/CATCH: handled below
                .computed_branch => {}, // ON GOTO: handled below
            }
        }

        // ── Return statements already emitted ───────────────────────────
        // If the block contains a return_stmt, it was already emitted as code.
        // Check if it has an exit edge (return semantics).
        for (block.statements.items) |stmt| {
            switch (stmt.data) {
                .return_stmt => {
                    has_return_edge = true;
                    break;
                },
                else => {},
            }
        }

        if (has_return_edge and exit_target != null) {
            // Return was already emitted by emitReturnStatement; the builder
            // is in terminated state. Nothing more to do.
            return;
        }

        // ── EXIT loop statement: jump to loop exit ──────────────────────
        for (block.statements.items) |stmt| {
            switch (stmt.data) {
                .exit_stmt => {
                    if (loop_exit_target) |t| {
                        try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
                        return;
                    } else if (exit_target) |t| {
                        try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
                        return;
                    }
                },
                else => {},
            }
        }

        // ── END statement: jump to program exit ─────────────────────────
        for (block.statements.items) |stmt| {
            switch (stmt.data) {
                .end_stmt => {
                    if (exit_target) |t| {
                        try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
                    } else {
                        // No exit edge in CFG — jump directly to @exit label
                        try self.builder.emitJump("@exit");
                    }
                    return;
                },
                else => {},
            }
        }

        // ── GOTO: unconditional jump ────────────────────────────────────
        if (jump_target) |t| {
            try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
            return;
        }

        // ── GOSUB: jump to target (return handled by runtime) ───────────
        if (has_gosub_call) {
            if (gosub_target) |t| {
                try self.builder.emitComment("GOSUB call");
                try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
                return;
            }
        }

        // ── Conditional branch ──────────────────────────────────────────
        if (true_target != null and false_target != null) {
            if (block.branch_condition) |cond| {
                // Determine if this is a FOR loop header or a regular condition.
                if (block.kind == .loop_header and self.isForLoopHeader(block.index)) {
                    // FOR loop condition: compare loop variable <= end value
                    try self.emitForCondition(block.index, true_target.?, false_target.?);
                } else if (block.kind == .loop_header and self.isForEachLoopHeader(block.index)) {
                    // FOR EACH condition: compare index < array length
                    try self.emitForEachCondition(block.index, true_target.?, false_target.?);
                } else {
                    // Regular boolean condition (IF, WHILE, DO, REPEAT UNTIL)
                    const cond_val = try self.expr_emitter.emitExpression(cond);
                    const cond_type = self.expr_emitter.inferExprType(cond);

                    // Only convert from double to int if the condition is
                    // a double expression.  Comparisons and logical ops
                    // already produce a `w` (integer) result so dtosi
                    // would reinterpret the bits incorrectly.
                    const cond_int = if (cond_type == .double) blk: {
                        const t = try self.builder.newTemp();
                        try self.builder.emitConvert(t, "w", "dtosi", cond_val);
                        break :blk t;
                    } else cond_val;

                    try self.builder.emitBranch(
                        cond_int,
                        try blockLabel(self.cfg, true_target.?, self.allocator),
                        try blockLabel(self.cfg, false_target.?, self.allocator),
                    );
                }
                return;
            }
        }

        // ── Case test block: compare selector vs value ──────────────────
        if (block.kind == .case_test) {
            if (case_match_target != null and case_next_target != null) {
                try self.emitCaseTest(block, case_match_target.?, case_next_target.?);
                return;
            }
            // Fallback: if we have match but no next, just jump to match
            if (case_match_target) |t| {
                try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
                return;
            }
        }

        // ── Back-edge: jump to loop header ──────────────────────────────
        if (back_edge_target) |t| {
            try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
            return;
        }

        // ── Fallthrough to next block ───────────────────────────────────
        if (fallthrough_target) |t| {
            try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
            return;
        }

        // ── Exit edge (END, EXIT FUNCTION, etc) ─────────────────────────
        if (exit_target) |t| {
            try self.builder.emitJump(try blockLabel(self.cfg, t, self.allocator));
            return;
        }

        // ── No successors: unreachable / end of function ────────────────
        // Insert a safety ret to keep QBE happy.
        if (block.successors.items.len == 0) {
            // Nothing to do — the block is terminal.
            return;
        }

        // ── Catch-all: jump to first successor ──────────────────────────
        if (block.successors.items.len > 0) {
            try self.builder.emitJump(try blockLabel(self.cfg, block.successors.items[0], self.allocator));
        }
    }

    // ── FOR loop helpers ────────────────────────────────────────────────

    /// Check if a loop_header block is associated with a FOR loop (has a
    /// registered ForLoopContext).
    fn isForLoopHeader(self: *const BlockEmitter, header_idx: u32) bool {
        return self.for_contexts.contains(header_idx);
    }

    /// Check if a loop_header block is associated with a FOR EACH loop.
    fn isForEachLoopHeader(self: *const BlockEmitter, header_idx: u32) bool {
        return self.foreach_contexts.contains(header_idx) or self.foreach_hashmap_contexts.contains(header_idx);
    }

    // ── FOR EACH loop helpers ───────────────────────────────────────────

    /// Emit FOR EACH initialisation: set hidden index to 0, register context.
    /// Detects whether the collection is a hashmap or an array and dispatches
    /// to the appropriate init path.
    fn emitForEachInit(self: *BlockEmitter, fi: *const ast.ForInStmt, block: *const cfg_mod.BasicBlock) EmitError!void {
        // Determine collection name from the expression.
        const coll_name = switch (fi.array.data) {
            .variable => |v| v.name,
            .array_access => |aa| aa.name,
            else => "unknown",
        };

        // Detect if the collection is a hashmap.
        if (self.expr_emitter.isHashmapVariable(coll_name)) {
            try self.emitForEachHashmapInit(fi, block, coll_name);
            return;
        }

        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "FOR EACH {s} IN ...", .{fi.variable}));

        const desc_name = try self.symbol_mapper.arrayDescName(coll_name);
        const desc_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{desc_name});

        // Look up element type from symbol table.
        var arr_upper_buf: [128]u8 = undefined;
        const arr_len = @min(coll_name.len, arr_upper_buf.len);
        for (0..arr_len) |i| arr_upper_buf[i] = std.ascii.toUpper(coll_name[i]);
        const arr_upper = arr_upper_buf[0..arr_len];

        var elem_load_type: []const u8 = "d";
        var elem_base_type: semantic.BaseType = .double;
        if (self.symbol_table.lookupArray(arr_upper)) |arr_sym| {
            elem_base_type = arr_sym.element_type_desc.base_type;
            elem_load_type = elem_base_type.toQBEType();
        }

        // Allocate a hidden index variable on the stack (integer, w).
        const index_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(index_addr, 4, 4);
        // Set index = 0
        try self.builder.emitStore("w", "0", index_addr);

        // If there's an explicit index variable, resolve and init it too.
        if (fi.index_variable.len > 0) {
            const idx_resolved = try self.resolveVarAddr(fi.index_variable, null);
            try self.builder.emitStore(idx_resolved.store_type, "0", idx_resolved.addr);
        }

        // Find the header block index (the successor of the current block).
        var header_idx: ?u32 = null;
        for (self.cfg.edges.items) |edge| {
            if (edge.from == block.index and (edge.kind == .fallthrough or edge.kind == .branch_true)) {
                header_idx = edge.to;
                break;
            }
        }

        if (header_idx) |hidx| {
            const ctx = ForEachContext{
                .iter_variable = fi.variable,
                .index_variable = fi.index_variable,
                .index_addr = index_addr,
                .array_desc_addr = desc_addr,
                .elem_load_type = elem_load_type,
                .elem_base_type = elem_base_type,
            };
            try self.foreach_contexts.put(hidx, ctx);

            // Also register on the increment block (the block with back_edge to header).
            for (self.cfg.edges.items) |edge| {
                if (edge.to == hidx and edge.kind == .back_edge) {
                    try self.foreach_contexts.put(edge.from, ctx);
                }
            }

            // Also register on the body block so we can load the element there.
            for (self.cfg.edges.items) |edge| {
                if (edge.from == hidx and edge.kind == .branch_true) {
                    try self.foreach_contexts.put(edge.to, ctx);
                }
            }
        }
    }

    /// Emit FOR EACH initialisation for HASHMAP collections.
    /// Calls hashmap_keys() and hashmap_size(), stores results on the stack,
    /// and registers a ForEachHashmapContext for use by condition/body/increment.
    fn emitForEachHashmapInit(self: *BlockEmitter, fi: *const ast.ForInStmt, block: *const cfg_mod.BasicBlock, coll_name: []const u8) EmitError!void {
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "FOR EACH {s} IN {s} (HASHMAP)", .{ fi.variable, coll_name }));

        // Load the hashmap pointer from the global variable.
        const var_name = try self.symbol_mapper.globalVarName(coll_name, null);
        const map_ptr = try self.builder.newTemp();
        try self.builder.emitLoad(map_ptr, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));

        // Call hashmap_keys(map) → returns NULL-terminated char** array.
        const keys_arr = try self.builder.newTemp();
        try self.builder.emitCall(keys_arr, "l", "hashmap_keys", try std.fmt.allocPrint(self.allocator, "l {s}", .{map_ptr}));

        // Call hashmap_size(map) → returns int64_t count.
        const size_l = try self.builder.newTemp();
        try self.builder.emitCall(size_l, "l", "hashmap_size", try std.fmt.allocPrint(self.allocator, "l {s}", .{map_ptr}));
        // Truncate to int32 for comparison with w-typed index.
        const size_w = try self.builder.newTemp();
        try self.builder.emitTrunc(size_w, "w", size_l);

        // Allocate stack slots for: hidden index, size, keys array ptr, map ptr.
        const index_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(index_addr, 4, 4);
        try self.builder.emitStore("w", "0", index_addr);

        const size_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(size_addr, 4, 4);
        try self.builder.emitStore("w", size_w, size_addr);

        const keys_array_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(keys_array_addr, 8, 8);
        try self.builder.emitStore("l", keys_arr, keys_array_addr);

        const map_ptr_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(map_ptr_addr, 8, 8);
        try self.builder.emitStore("l", map_ptr, map_ptr_addr);

        // Find the header block index (the successor of the current block).
        var header_idx: ?u32 = null;
        for (self.cfg.edges.items) |edge| {
            if (edge.from == block.index and (edge.kind == .fallthrough or edge.kind == .branch_true)) {
                header_idx = edge.to;
                break;
            }
        }

        if (header_idx) |hidx| {
            const ctx = ForEachHashmapContext{
                .key_variable = fi.variable,
                .value_variable = fi.index_variable,
                .index_addr = index_addr,
                .size_addr = size_addr,
                .keys_array_addr = keys_array_addr,
                .map_ptr_addr = map_ptr_addr,
            };
            try self.foreach_hashmap_contexts.put(hidx, ctx);

            // Also register on the increment block (the block with back_edge to header).
            for (self.cfg.edges.items) |edge| {
                if (edge.to == hidx and edge.kind == .back_edge) {
                    try self.foreach_hashmap_contexts.put(edge.from, ctx);
                }
            }

            // Also register on the body block so we can load the key/value there.
            for (self.cfg.edges.items) |edge| {
                if (edge.from == hidx and edge.kind == .branch_true) {
                    try self.foreach_hashmap_contexts.put(edge.to, ctx);
                }
            }
        }
    }

    /// Emit the FOR EACH condition: compare hidden index with array upper bound
    /// or hashmap size.
    fn emitForEachCondition(self: *BlockEmitter, header_idx: u32, true_target: u32, false_target: u32) EmitError!void {
        // Check for hashmap context first.
        if (self.foreach_hashmap_contexts.get(header_idx)) |hctx| {
            try self.emitForEachHashmapCondition(&hctx, true_target, false_target);
            return;
        }

        const ctx = self.foreach_contexts.get(header_idx) orelse {
            try self.builder.emitComment("WARN: FOR EACH context not found, jumping to body");
            try self.builder.emitJump(try blockLabel(self.cfg, true_target, self.allocator));
            return;
        };

        // Load current index (w = int32)
        const cur_idx = try self.builder.newTemp();
        try self.builder.emitLoad(cur_idx, "w", ctx.index_addr);

        // ArrayDescriptor layout (from array_descriptor.h):
        //   Offset  0: void*   data          (8 bytes, pointer)
        //   Offset  8: int64_t lowerBound1    (8 bytes)
        //   Offset 16: int64_t upperBound1    (8 bytes)
        //   ...
        // Read upperBound1 at offset 16 as int64_t (l), then truncate
        // to int32 (w) for comparison with our w-typed index.
        const ub_addr = try self.builder.newTemp();
        try self.builder.emitBinary(ub_addr, "l", "add", ctx.array_desc_addr, "16");
        const upper_bound_l = try self.builder.newTemp();
        try self.builder.emitLoad(upper_bound_l, "l", ub_addr);
        // Truncate int64 → int32
        const upper_bound = try self.builder.newTemp();
        try self.builder.emitTrunc(upper_bound, "w", upper_bound_l);

        // Condition: index <= upperBound  →  continue loop
        // Equivalent to: !(index > upperBound)
        const idx_gt = try self.builder.newTemp();
        try self.builder.emit("    {s} =w csgtw {s}, {s}\n", .{ idx_gt, cur_idx, upper_bound });
        const cond = try self.builder.newTemp();
        try self.builder.emit("    {s} =w xor {s}, 1\n", .{ cond, idx_gt });

        try self.builder.emitBranch(
            cond,
            try blockLabel(self.cfg, true_target, self.allocator),
            try blockLabel(self.cfg, false_target, self.allocator),
        );
    }

    /// Emit the FOR EACH hashmap condition: compare index < size.
    fn emitForEachHashmapCondition(self: *BlockEmitter, hctx: *const ForEachHashmapContext, true_target: u32, false_target: u32) EmitError!void {
        // Load current index
        const cur_idx = try self.builder.newTemp();
        try self.builder.emitLoad(cur_idx, "w", hctx.index_addr);

        // Load hashmap size
        const size = try self.builder.newTemp();
        try self.builder.emitLoad(size, "w", hctx.size_addr);

        // Condition: index < size  →  continue loop
        const cond = try self.builder.newTemp();
        try self.builder.emit("    {s} =w csltw {s}, {s}\n", .{ cond, cur_idx, size });

        try self.builder.emitBranch(
            cond,
            try blockLabel(self.cfg, true_target, self.allocator),
            try blockLabel(self.cfg, false_target, self.allocator),
        );
    }

    /// Emit the element load at the start of a FOR EACH body block.
    /// Loads arr(index) into the iterator variable, or for hashmaps,
    /// loads the key (and optionally value) from the keys array.
    pub fn emitForEachBodyLoad(self: *BlockEmitter, block: *const cfg_mod.BasicBlock) EmitError!void {
        // Only emit for body blocks (not header or increment).
        if (block.kind != .loop_body) return;

        // Check for hashmap context first.
        if (self.foreach_hashmap_contexts.get(block.index)) |hctx| {
            try self.emitForEachHashmapBodyLoad(&hctx);
            return;
        }

        const ctx = self.foreach_contexts.get(block.index) orelse return;

        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "FOR EACH: load {s} = arr(index)", .{ctx.iter_variable}));

        // Load current index
        const cur_idx = try self.builder.newTemp();
        try self.builder.emitLoad(cur_idx, "w", ctx.index_addr);

        // Get element address: fbc_array_element_addr(desc, index)
        const elem_addr = try self.builder.newTemp();
        const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ ctx.array_desc_addr, cur_idx });
        try self.builder.emitCall(elem_addr, "l", "fbc_array_element_addr", ea_args);

        // Load element value
        const elem_val = try self.builder.newTemp();
        try self.builder.emitLoad(elem_val, ctx.elem_load_type, elem_addr);

        // For SINGLE elements, promote to double (matching emitVariableLoad behaviour)
        var store_val = elem_val;
        if (ctx.elem_base_type == .single) {
            const dbl = try self.builder.newTemp();
            try self.builder.emit("    {s} =d exts {s}\n", .{ dbl, elem_val });
            store_val = dbl;
        }

        // Store into the iterator variable
        const resolved = try self.resolveVarAddr(ctx.iter_variable, null);
        // Convert if needed: element type may differ from variable storage type
        if (ctx.elem_base_type.isInteger() and std.mem.eql(u8, resolved.store_type, "d")) {
            // Integer element → double variable: convert
            const cvt = try self.builder.newTemp();
            try self.builder.emitConvert(cvt, "d", "swtof", elem_val);
            try self.builder.emitStore(resolved.store_type, cvt, resolved.addr);
        } else if (ctx.elem_base_type == .double and resolved.base_type.isInteger()) {
            // Double element → integer variable: convert
            const cvt = try self.builder.newTemp();
            try self.builder.emitConvert(cvt, "w", "dtosi", elem_val);
            try self.builder.emitStore(resolved.store_type, cvt, resolved.addr);
        } else {
            try self.builder.emitStore(resolved.store_type, store_val, resolved.addr);
        }

        // If there's an index variable, store the current index into it too.
        if (ctx.index_variable.len > 0) {
            const idx_resolved = try self.resolveVarAddr(ctx.index_variable, null);
            if (std.mem.eql(u8, idx_resolved.store_type, "d")) {
                // Index is integer but variable may be double
                const cvt = try self.builder.newTemp();
                try self.builder.emitConvert(cvt, "d", "swtof", cur_idx);
                try self.builder.emitStore(idx_resolved.store_type, cvt, idx_resolved.addr);
            } else {
                try self.builder.emitStore(idx_resolved.store_type, cur_idx, idx_resolved.addr);
            }
        }
    }

    /// Emit the FOR EACH increment: index += 1.
    pub fn emitForEachIncrement(self: *BlockEmitter, block: *const cfg_mod.BasicBlock) EmitError!void {
        // Check for hashmap context first.
        if (self.foreach_hashmap_contexts.get(block.index)) |hctx| {
            const cur = try self.builder.newTemp();
            try self.builder.emitLoad(cur, "w", hctx.index_addr);
            const next_val = try self.builder.newTemp();
            try self.builder.emitBinary(next_val, "w", "add", cur, "1");
            try self.builder.emitStore("w", next_val, hctx.index_addr);
            return;
        }

        const ctx = self.foreach_contexts.get(block.index) orelse return;

        // Load current index, add 1, store back
        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "w", ctx.index_addr);
        const next = try self.builder.newTemp();
        try self.builder.emitBinary(next, "w", "add", cur, "1");
        try self.builder.emitStore("w", next, ctx.index_addr);
    }

    /// Emit the body load for a FOR EACH over a HASHMAP.
    /// Loads keys[index] as a C string, converts to StringDescriptor,
    /// stores to key variable.  If a value variable is present, calls
    /// hashmap_lookup to get the value.
    fn emitForEachHashmapBodyLoad(self: *BlockEmitter, hctx: *const ForEachHashmapContext) EmitError!void {
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "FOR EACH HASHMAP: load key={s}", .{hctx.key_variable}));

        // Load current index
        const cur_idx = try self.builder.newTemp();
        try self.builder.emitLoad(cur_idx, "w", hctx.index_addr);

        // Load the keys array pointer
        const keys_ptr = try self.builder.newTemp();
        try self.builder.emitLoad(keys_ptr, "l", hctx.keys_array_addr);

        // Compute address of keys[index]: keys_ptr + index * 8 (pointer size)
        const idx_ext = try self.builder.newTemp();
        try self.builder.emitExtend(idx_ext, "l", "extsw", cur_idx);
        const offset = try self.builder.newTemp();
        try self.builder.emitBinary(offset, "l", "mul", idx_ext, "8");
        const key_slot_addr = try self.builder.newTemp();
        try self.builder.emitBinary(key_slot_addr, "l", "add", keys_ptr, offset);

        // Load the char* key from keys[index]
        const key_cstr = try self.builder.newTemp();
        try self.builder.emitLoad(key_cstr, "l", key_slot_addr);

        // Convert char* → StringDescriptor* via string_new_utf8
        const key_str_desc = try self.builder.newTemp();
        try self.builder.emitCall(key_str_desc, "l", "string_new_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{key_cstr}));

        // Store the StringDescriptor* into the key variable
        const key_resolved = try self.resolveVarAddr(hctx.key_variable, null);
        try self.builder.emitStore("l", key_str_desc, key_resolved.addr);

        // If there's a value variable, look up the value from the hashmap.
        if (hctx.value_variable.len > 0) {
            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "FOR EACH HASHMAP: load value={s}", .{hctx.value_variable}));

            // Load the hashmap pointer
            const map_ptr = try self.builder.newTemp();
            try self.builder.emitLoad(map_ptr, "l", hctx.map_ptr_addr);

            // Call hashmap_lookup(map, key_cstr) → returns value (StringDescriptor*)
            const val_ptr = try self.builder.newTemp();
            try self.builder.emitCall(val_ptr, "l", "hashmap_lookup", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ map_ptr, key_cstr }));

            // Store the value into the value variable
            const val_resolved = try self.resolveVarAddr(hctx.value_variable, null);
            try self.builder.emitStore("l", val_ptr, val_resolved.addr);
        }
    }

    /// Emit the FOR loop initialisation: set loop variable to start value,
    /// evaluate and store end value. Register the ForLoopContext so the
    /// header and increment blocks can use it.
    /// Pre-allocate stack slots for all FOR loops found in the CFG.
    /// Must be called while emitting the entry block so that QBE sees
    /// the alloc instructions in the function's start block.
    pub fn preAllocateForLoopSlots(self: *BlockEmitter, the_cfg: *const cfg_mod.CFG) EmitError!void {
        try self.builder.emitComment("Pre-alloc FOR loop slots");
        for (the_cfg.blocks.items) |block| {
            for (block.statements.items) |stmt| {
                switch (stmt.data) {
                    .for_stmt => |fs| {
                        // Build uppercase key from the variable name
                        // (stripped of BASIC suffix characters).
                        const base = SymbolMapper.stripSuffix(fs.variable);
                        var upper_buf: [128]u8 = undefined;
                        const blen = @min(base.len, upper_buf.len);
                        for (0..blen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
                        const base_key = upper_buf[0..blen];

                        // Also build the full key (with suffix) for the
                        // pre-alloc map, which uses the raw variable name.
                        var full_upper_buf: [128]u8 = undefined;
                        const vlen = @min(fs.variable.len, full_upper_buf.len);
                        for (0..vlen) |i| full_upper_buf[i] = std.ascii.toUpper(fs.variable[i]);
                        const full_key = full_upper_buf[0..vlen];

                        // Skip if already allocated (same variable reused
                        // in multiple loops).
                        if (self.for_pre_allocs.contains(full_key)) continue;

                        // ── Allocate a stack slot for the loop variable
                        //    itself when inside a function context, so it
                        //    doesn't fall through to a global reference. ──
                        if (self.func_ctx) |fctx_const| {
                            const fctx: *FunctionContext = @constCast(fctx_const);
                            // Only register if not already a param or local.
                            if (fctx.resolve(base_key) == null) {
                                const var_addr = try self.builder.newTemp();
                                try self.builder.emitAlloc(var_addr, 4, 4);
                                try self.builder.emitStore("w", "0", var_addr);

                                const local_key = try self.allocator.dupe(u8, base_key);
                                try fctx.local_addrs.put(local_key, .{
                                    .addr = var_addr,
                                    .qbe_type = "w",
                                    .base_type = .integer,
                                    .suffix = @as(?Tag, .type_int),
                                });
                            }
                        }

                        const limit_addr = try self.builder.newTemp();
                        try self.builder.emitAlloc(limit_addr, 4, 4);
                        try self.builder.emitStore("w", "0", limit_addr);

                        const step_addr = try self.builder.newTemp();
                        try self.builder.emitAlloc(step_addr, 4, 4);
                        try self.builder.emitStore("w", "0", step_addr);

                        const duped_key = try self.allocator.dupe(u8, full_key);
                        try self.for_pre_allocs.put(duped_key, .{
                            .limit_addr = limit_addr,
                            .step_addr = step_addr,
                        });
                    },
                    else => {},
                }
            }
        }
    }

    fn emitForInit(self: *BlockEmitter, fs: *const ast.ForStmt, block: *const cfg_mod.BasicBlock) EmitError!void {
        // FOR loop variables always use integer (w) arithmetic.
        // All values (start, limit, step) are evaluated once at init
        // and converted to integers, matching C++ compiler behaviour.

        // 1. Evaluate start expression, convert to integer, store to loop variable.
        const start_raw = try self.expr_emitter.emitExpression(fs.start);
        const start_type = self.expr_emitter.inferExprType(fs.start);
        const start_val = if (start_type == .double) blk: {
            const t = try self.builder.newTemp();
            try self.builder.emitConvert(t, "w", "dtosi", start_raw);
            break :blk t;
        } else start_raw;
        const resolved = try self.resolveVarAddr(fs.variable, null);
        const var_addr = resolved.addr;
        try self.builder.emitStore("w", start_val, var_addr);

        // Look up pre-allocated slots for this variable.
        var upper_buf: [128]u8 = undefined;
        const vlen = @min(fs.variable.len, upper_buf.len);
        for (0..vlen) |i| upper_buf[i] = std.ascii.toUpper(fs.variable[i]);
        const var_key = upper_buf[0..vlen];
        const pre = self.for_pre_allocs.get(var_key);

        // 2. Evaluate end (limit) expression, convert to integer, store in temp slot.
        const end_raw = try self.expr_emitter.emitExpression(fs.end_expr);
        const end_type = self.expr_emitter.inferExprType(fs.end_expr);
        const end_val = if (end_type == .double) blk: {
            const t = try self.builder.newTemp();
            try self.builder.emitConvert(t, "w", "dtosi", end_raw);
            break :blk t;
        } else end_raw;
        const end_addr = if (pre) |p| p.limit_addr else blk: {
            // Fallback: inline alloc (only safe in the entry block).
            const addr = try self.builder.newTemp();
            try self.builder.emitAlloc(addr, 4, 4);
            break :blk addr;
        };
        try self.builder.emitStore("w", end_val, end_addr);

        // 3. Evaluate step expression (default 1), convert to integer, store in temp slot.
        const step_addr = if (pre) |p| p.step_addr else blk: {
            const addr = try self.builder.newTemp();
            try self.builder.emitAlloc(addr, 4, 4);
            break :blk addr;
        };
        if (fs.step) |step| {
            const step_raw = try self.expr_emitter.emitExpression(step);
            const step_type = self.expr_emitter.inferExprType(step);
            const step_val = if (step_type == .double) blk: {
                const t = try self.builder.newTemp();
                try self.builder.emitConvert(t, "w", "dtosi", step_raw);
                break :blk t;
            } else step_raw;
            try self.builder.emitStore("w", step_val, step_addr);
        } else {
            // Default step is 1.
            const one = try self.builder.newTemp();
            try self.builder.emit("    {s} =w copy 1\n", .{one});
            try self.builder.emitStore("w", one, step_addr);
        }

        // Find the loop header block: it's the fallthrough successor
        // with kind == .loop_header.
        var header_idx: ?u32 = null;
        for (self.cfg.edges.items) |edge| {
            if (edge.from == block.index and edge.kind == .fallthrough) {
                const target_block = self.cfg.getBlockConst(edge.to);
                if (target_block.kind == .loop_header) {
                    header_idx = edge.to;
                    break;
                }
            }
        }

        if (header_idx) |hidx| {
            try self.for_contexts.put(hidx, .{
                .variable = fs.variable,
                .step_expr = fs.step,
                .end_addr = end_addr,
                .step_addr = step_addr,
            });

            // Also find the increment block for this loop and register the
            // context there too. The increment block is reachable via
            // loop_body → fallthrough → loop_increment, and has a back_edge
            // to the header.
            for (self.cfg.edges.items) |edge| {
                if (edge.to == hidx and edge.kind == .back_edge) {
                    // edge.from is the increment block (or the body end).
                    try self.for_contexts.put(edge.from, .{
                        .variable = fs.variable,
                        .step_expr = fs.step,
                        .end_addr = end_addr,
                        .step_addr = step_addr,
                    });
                }
            }
        }
    }

    /// Emit the FOR loop condition: compare loop variable against end value.
    /// Uses integer (w) arithmetic. Handles both positive and negative step
    /// directions via a runtime step-sign check, matching the C++ compiler.
    fn emitForCondition(self: *BlockEmitter, header_idx: u32, true_target: u32, false_target: u32) EmitError!void {
        const ctx = self.for_contexts.get(header_idx) orelse {
            // Fallback: treat as unconditional jump to body.
            try self.builder.emitComment("WARN: FOR context not found, jumping to body");
            try self.builder.emitJump(try blockLabel(self.cfg, true_target, self.allocator));
            return;
        };

        // Load current loop variable value (integer).
        const resolved = try self.resolveVarAddr(ctx.variable, null);
        const var_addr = resolved.addr;
        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "w", var_addr);

        // Load stored end (limit) value (integer).
        const limit_val = try self.builder.newTemp();
        try self.builder.emitLoad(limit_val, "w", ctx.end_addr);

        // Load stored step value (integer) to check sign.
        const step_val = try self.builder.newTemp();
        try self.builder.emitLoad(step_val, "w", ctx.step_addr);

        // Check if step is negative: stepIsNeg = (step < 0)
        const step_is_neg = try self.builder.newTemp();
        try self.builder.emit("    {s} =w csltw {s}, 0\n", .{ step_is_neg, step_val });

        // Positive step: continue while cur <= limit  →  !(cur > limit)
        const cur_gt_limit = try self.builder.newTemp();
        try self.builder.emit("    {s} =w csgtw {s}, {s}\n", .{ cur_gt_limit, cur, limit_val });
        const pos_cond = try self.builder.newTemp();
        try self.builder.emit("    {s} =w xor {s}, 1\n", .{ pos_cond, cur_gt_limit });

        // Negative step: continue while cur >= limit  →  !(cur < limit)
        const cur_lt_limit = try self.builder.newTemp();
        try self.builder.emit("    {s} =w csltw {s}, {s}\n", .{ cur_lt_limit, cur, limit_val });
        const neg_cond = try self.builder.newTemp();
        try self.builder.emit("    {s} =w xor {s}, 1\n", .{ neg_cond, cur_lt_limit });

        // Select: result = stepIsNeg ? negCond : posCond
        // result = (stepIsNeg AND negCond) OR ((NOT stepIsNeg) AND posCond)
        const neg_part = try self.builder.newTemp();
        try self.builder.emit("    {s} =w and {s}, {s}\n", .{ neg_part, step_is_neg, neg_cond });
        const not_step_neg = try self.builder.newTemp();
        try self.builder.emit("    {s} =w xor {s}, 1\n", .{ not_step_neg, step_is_neg });
        const pos_part = try self.builder.newTemp();
        try self.builder.emit("    {s} =w and {s}, {s}\n", .{ pos_part, not_step_neg, pos_cond });
        const result = try self.builder.newTemp();
        try self.builder.emit("    {s} =w or {s}, {s}\n", .{ result, neg_part, pos_part });

        try self.builder.emitBranch(
            result,
            try blockLabel(self.cfg, true_target, self.allocator),
            try blockLabel(self.cfg, false_target, self.allocator),
        );
    }

    // ── FOR loop increment ──────────────────────────────────────────────

    /// Emit the FOR loop increment code for a loop_increment block.
    /// Uses integer (w) arithmetic. Step was stored at init time.
    pub fn emitForIncrement(self: *BlockEmitter, block: *const cfg_mod.BasicBlock) EmitError!void {
        const ctx = self.for_contexts.get(block.index) orelse {
            // Don't warn if this is a FOR EACH block (array or hashmap) —
            // those have their own increment logic.
            if (!self.foreach_contexts.contains(block.index) and
                !self.foreach_hashmap_contexts.contains(block.index))
            {
                try self.builder.emitComment("WARN: FOR increment context not found");
            }
            return;
        };

        const resolved = try self.resolveVarAddr(ctx.variable, null);
        const var_addr = resolved.addr;

        // Load current loop variable value (integer).
        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "w", var_addr);

        // Load stored step value (integer, evaluated once at init).
        const step_val = try self.builder.newTemp();
        try self.builder.emitLoad(step_val, "w", ctx.step_addr);

        // Increment: var = var + step
        const next_val = try self.builder.newTemp();
        try self.builder.emitBinary(next_val, "w", "add", cur, step_val);
        try self.builder.emitStore("w", next_val, var_addr);
    }

    // ── CASE helpers ────────────────────────────────────────────────────

    /// Evaluate and save the SELECT CASE selector expression.
    fn emitCaseSelector(self: *BlockEmitter, cs: *const ast.CaseStmt, block: *const cfg_mod.BasicBlock) EmitError!void {
        const sel_type = self.expr_emitter.inferExprType(cs.case_expression);
        const sel_val = try self.expr_emitter.emitExpression(cs.case_expression);
        try self.case_contexts.put(block.index, .{ .selector_temp = sel_val, .selector_type = sel_type });
    }

    /// Emit the comparison for a case_test block. Compares the selector
    /// against the test value and branches accordingly.
    fn emitCaseTest(self: *BlockEmitter, block: *const cfg_mod.BasicBlock, match_target: u32, next_target: u32) EmitError!void {
        // Find the selector from the case entry block.
        // Walk predecessors back to find the case entry (or the previous case_test).
        var sel_temp: ?[]const u8 = null;
        var sel_type: ExprEmitter.ExprType = .double;

        // Search the case_contexts for any predecessor chain.
        // The selector was stored in the block that contained the case_stmt.
        var ctx_it = self.case_contexts.iterator();
        while (ctx_it.next()) |entry| {
            sel_temp = entry.value_ptr.selector_temp;
            sel_type = entry.value_ptr.selector_type;
            break; // Use the first (and typically only) case context in scope
        }

        if (sel_temp == null) {
            try self.builder.emitComment("WARN: CASE selector not found");
            try self.builder.emitJump(try blockLabel(self.cfg, next_target, self.allocator));
            return;
        }

        if (block.branch_condition) |test_val_expr| {
            const test_val = try self.expr_emitter.emitExpression(test_val_expr);
            const test_type = self.expr_emitter.inferExprType(test_val_expr);
            const cmp = try self.builder.newTemp();
            // Use the correct QBE comparison type based on the selector
            const cmp_type: []const u8 = switch (sel_type) {
                .integer => "w",
                .string => "w", // string_compare returns w
                .double => "d",
            };
            if (sel_type == .string) {
                // String SELECT CASE: call string_compare, then check == 0
                const cmp_result = try self.builder.newTemp();
                const args = try std.fmt.allocPrint(self.allocator, "l {s}, l {s}", .{ sel_temp.?, test_val });
                try self.builder.emitCall(cmp_result, "w", "string_compare", args);
                try self.builder.emitCompare(cmp, "w", "eq", cmp_result, "0");
            } else {
                // Ensure both operands have the same QBE type.
                // If the selector is double but the case value is integer (or vice versa),
                // convert the case value to match the selector type.
                var effective_test_val = test_val;
                if (sel_type == .double and test_type == .integer) {
                    // Convert integer case value to double
                    const cvt = try self.builder.newTemp();
                    try self.builder.emitConvert(cvt, "d", "swtof", test_val);
                    effective_test_val = cvt;
                } else if (sel_type == .integer and test_type == .double) {
                    // Convert double case value to integer
                    const cvt = try self.builder.newTemp();
                    try self.builder.emitConvert(cvt, "w", "dtosi", test_val);
                    effective_test_val = cvt;
                }
                try self.builder.emitCompare(cmp, cmp_type, "eq", sel_temp.?, effective_test_val);
            }
            try self.builder.emitBranch(
                cmp,
                try blockLabel(self.cfg, match_target, self.allocator),
                try blockLabel(self.cfg, next_target, self.allocator),
            );
        } else {
            // No condition: unconditional match (OTHERWISE-like)
            try self.builder.emitJump(try blockLabel(self.cfg, match_target, self.allocator));
        }
    }

    // ── UDT Arithmetic Helpers (NEON + Scalar) ──────────────────────────

    /// Map SIMDInfo to the integer arrangement code used in NEON IL opcodes:
    ///   0 = Kw  (.4s integer)
    ///   1 = Kl  (.2d integer)
    ///   2 = Ks  (.4s float)
    ///   3 = Kd  (.2d float)
    ///   4 =      .8h integer
    ///   5 =      .16b integer
    fn simdArrangementCode(info: ast.TypeDeclStmt.SIMDInfo) i32 {
        return switch (info.simd_type) {
            .v4s, .v4s_pad1, .quad => if (info.is_floating_point) @as(i32, 2) else @as(i32, 0),
            .v2d, .pair => if (info.is_floating_point) @as(i32, 3) else @as(i32, 1),
            .v8h => 4,
            .v16b => 5,
            .v2s, .v4h, .v8b => 0, // half-register fallback
            .none => 0,
        };
    }

    /// Check whether a UDT contains any string fields (at any nesting depth).
    fn hasStringFields(self: *BlockEmitter, ts: *const semantic.TypeSymbol) bool {
        for (ts.fields) |field| {
            if (field.type_desc.base_type == .string) return true;
            if (field.type_desc.base_type == .user_defined) {
                const nested_name = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                if (self.symbol_table.lookupType(nested_name)) |nested_ts| {
                    if (self.hasStringFields(nested_ts)) return true;
                }
            }
        }
        return false;
    }

    /// Emit code to obtain the memory address of a UDT expression.
    /// For variables this loads the pointer from the global slot;
    /// for locals it returns the stack slot address directly.
    fn getUDTAddressForExpr(self: *BlockEmitter, expr: *const ast.Expression) EmitError!?[]const u8 {
        switch (expr.data) {
            .variable => |v| {
                // Check function-local first
                if (self.func_ctx) |fctx| {
                    var upper_buf: [128]u8 = undefined;
                    const base = SymbolMapper.stripSuffix(v.name);
                    const ulen = @min(base.len, upper_buf.len);
                    for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
                    const upper_base = upper_buf[0..ulen];
                    if (fctx.resolve(upper_base)) |rv| {
                        if (rv.base_type == .user_defined) {
                            // For locals, the stack slot address IS the struct
                            const dest = try self.builder.newTemp();
                            try self.builder.emit("    {s} =l copy {s}\n", .{ dest, rv.addr });
                            return dest;
                        }
                    }
                }
                // Global variable: load pointer from the global slot
                const var_name = try self.symbol_mapper.globalVarName(v.name, null);
                const dest = try self.builder.newTemp();
                try self.builder.emitLoad(dest, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));
                return dest;
            },
            .array_access => |aa| {
                // Emit the array element address
                const index_val = try self.expr_emitter.emitExpression(aa.indices[0]);
                const idx_type = self.expr_emitter.inferExprType(aa.indices[0]);
                const index_int = if (idx_type == .integer) index_val else blk: {
                    const t = try self.builder.newTemp();
                    try self.builder.emitConvert(t, "w", "dtosi", index_val);
                    break :blk t;
                };
                const desc_name = try self.symbol_mapper.arrayDescName(aa.name);
                const desc_addr = try self.builder.newTemp();
                try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr, desc_name });
                const bc_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
                try self.builder.emitCall("", "", "fbc_array_bounds_check", bc_args);
                const elem_addr = try self.builder.newTemp();
                const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
                try self.builder.emitCall(elem_addr, "l", "fbc_array_element_addr", ea_args);
                return elem_addr;
            },
            else => return null,
        }
    }

    /// Try to emit UDT element-wise arithmetic for a LET statement.
    /// Handles `C = A + B` (and -, *, /) where A, B, C are the same UDT type.
    /// Returns true if the statement was handled (NEON or scalar).
    fn tryEmitUDTArithmetic(self: *BlockEmitter, lt: *const ast.LetStmt, target_addr: []const u8, udt_type_name: []const u8) EmitError!bool {
        // The value expression must be a binary expression
        const bin = switch (lt.value.data) {
            .binary => |b| b,
            else => return false,
        };

        // Only handle arithmetic operators: +, -, *, /
        const neon_op: []const u8 = switch (bin.op) {
            .plus => "neonadd",
            .minus => "neonsub",
            .multiply => "neonmul",
            .divide => "neondiv",
            else => return false,
        };
        const scalar_op: []const u8 = switch (bin.op) {
            .plus => "add",
            .minus => "sub",
            .multiply => "mul",
            .divide => "div",
            else => return false,
        };

        // Both operands must be the same UDT type as the target
        const left_udt = self.expr_emitter.inferUDTNameForExpr(bin.left) orelse return false;
        const right_udt = self.expr_emitter.inferUDTNameForExpr(bin.right) orelse return false;

        if (!std.ascii.eqlIgnoreCase(left_udt, udt_type_name)) return false;
        if (!std.ascii.eqlIgnoreCase(right_udt, udt_type_name)) return false;

        // Look up the UDT definition
        const type_sym = self.symbol_table.lookupType(udt_type_name) orelse return false;

        // UDT must not contain string fields
        if (self.hasStringFields(type_sym)) return false;

        // Get addresses of left and right operands
        const left_addr = try self.getUDTAddressForExpr(bin.left) orelse return false;
        const right_addr = try self.getUDTAddressForExpr(bin.right) orelse return false;

        // ── NEON fast path ──────────────────────────────────────────────
        const simd_info = type_sym.simd_info;
        if (simd_info.isValid() and simd_info.is_full_q and self.symbol_table.neon_enabled) {
            // Division is only supported for float arrangements
            if (std.mem.eql(u8, neon_op, "neondiv") and !simd_info.is_floating_point) {
                // Fall through to scalar
            } else {
                const arr_code = simdArrangementCode(simd_info);
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "NEON arithmetic ({s}): {s} → 4 instructions", .{ udt_type_name, neon_op }));
                try self.builder.emitInstruction(try std.fmt.allocPrint(self.allocator, "neonldr {s}", .{left_addr}));
                try self.builder.emitInstruction(try std.fmt.allocPrint(self.allocator, "neonldr2 {s}", .{right_addr}));
                try self.builder.emitInstruction(try std.fmt.allocPrint(self.allocator, "{s} {d}", .{ neon_op, arr_code }));
                try self.builder.emitInstruction(try std.fmt.allocPrint(self.allocator, "neonstr {s}", .{target_addr}));
                try self.builder.emitComment("End NEON UDT arithmetic assignment");
                return true;
            }
        }

        // ── Scalar fallback (field-by-field) ────────────────────────────
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "Scalar UDT arithmetic ({s}): field-by-field {s}", .{ udt_type_name, scalar_op }));

        var offset: u32 = 0;
        for (type_sym.fields) |field| {
            const field_bt = field.type_desc.base_type;

            // Skip non-numeric fields
            if (field_bt == .string) continue;

            if (field_bt == .user_defined) {
                // For nested UDTs, skip for now (could recurse)
                const nested_name = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                const nested_sz = self.type_manager.sizeOfUDT(nested_name);
                offset += if (nested_sz == 0) 8 else nested_sz;
                continue;
            }

            const qbe_type = field_bt.toQBEType();
            const qbe_load = field_bt.toQBEMemOp();

            // Calculate field addresses
            const left_field_addr = try self.builder.newTemp();
            const right_field_addr = try self.builder.newTemp();
            const dst_field_addr = try self.builder.newTemp();

            if (offset > 0) {
                const off_str = try std.fmt.allocPrint(self.allocator, "{d}", .{offset});
                try self.builder.emitBinary(left_field_addr, "l", "add", left_addr, off_str);
                try self.builder.emitBinary(right_field_addr, "l", "add", right_addr, off_str);
                try self.builder.emitBinary(dst_field_addr, "l", "add", target_addr, off_str);
            } else {
                try self.builder.emit("    {s} =l copy {s}\n", .{ left_field_addr, left_addr });
                try self.builder.emit("    {s} =l copy {s}\n", .{ right_field_addr, right_addr });
                try self.builder.emit("    {s} =l copy {s}\n", .{ dst_field_addr, target_addr });
            }

            // Load left and right values
            const left_val = try self.builder.newTemp();
            const right_val = try self.builder.newTemp();
            try self.builder.emitLoad(left_val, qbe_load, left_field_addr);
            try self.builder.emitLoad(right_val, qbe_load, right_field_addr);

            // Perform the arithmetic operation
            const result = try self.builder.newTemp();
            try self.builder.emitBinary(result, qbe_type, scalar_op, left_val, right_val);

            // Store result to target field
            try self.builder.emitStore(qbe_load, result, dst_field_addr);

            // Advance offset
            const field_size = self.type_manager.sizeOf(field_bt);
            offset += if (field_size == 0) 8 else field_size;
        }

        try self.builder.emitComment("End scalar UDT arithmetic assignment");
        return true;
    }

    // ── Leaf Statement Emitters ─────────────────────────────────────────

    fn emitPrintStatement(self: *BlockEmitter, pr: *const ast.PrintStmt) EmitError!void {
        for (pr.items) |item| {
            // ── Check if the expression is a UDT variable ──────────────
            // UDT variables are stored as pointers (l type) but
            // inferExprType returns .double.  Printing them with
            // basic_print_double causes a QBE type mismatch.  Instead,
            // emit field-by-field printing.
            const udt_name = self.expr_emitter.inferUDTNameForExpr(item.expr);
            if (udt_name) |uname| {
                try self.emitPrintUDT(item.expr, uname);
            } else {
                const val = try self.expr_emitter.emitExpression(item.expr);
                const et = self.expr_emitter.inferExprType(item.expr);
                // basic_print_int expects int64_t (l type).  If the expression
                // produced a 32-bit word we must sign-extend it first.
                const print_val = if (et == .integer) blk: {
                    const long_val = try self.builder.newTemp();
                    try self.builder.emitExtend(long_val, "l", "extsw", val);
                    break :blk long_val;
                } else val;
                const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.printArgLetter(), print_val });
                try self.runtime.callVoid(et.printFn(), args);
            }

            if (item.comma) {
                try self.runtime.callVoid("basic_print_tab", "");
            }
            if (item.semicolon) {
                // Semicolon: no space between items (already handled by not
                // emitting tab/newline). Nothing to do.
            }
        }

        if (pr.trailing_newline) {
            try self.runtime.callVoid("basic_print_newline", "");
        }
    }

    /// Emit field-by-field printing for a UDT expression.
    /// Prints in the format: {Field1: value1, Field2: value2, ...}
    fn emitPrintUDT(self: *BlockEmitter, expr: *const ast.Expression, udt_type_name: []const u8) EmitError!void {
        const base_ptr = try self.expr_emitter.emitExpression(expr);
        const tsym = self.symbol_table.lookupType(udt_type_name) orelse {
            // Unknown UDT — fall back to printing the pointer as an integer
            const long_val = try self.builder.newTemp();
            try self.builder.emit("    {s} =l copy {s}\n", .{ long_val, base_ptr });
            const args = try std.fmt.allocPrint(self.allocator, "l {s}", .{long_val});
            try self.runtime.callVoid("basic_print_int", args);
            return;
        };

        // Print opening brace
        const open_label = try self.builder.registerString("{");
        const open_tmp = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ open_tmp, open_label });
        const open_sd = try self.builder.newTemp();
        try self.builder.emitCall(open_sd, "l", "string_new_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{open_tmp}));
        try self.runtime.callVoid("basic_print_string_desc", try std.fmt.allocPrint(self.allocator, "l {s}", .{open_sd}));

        var offset: u32 = 0;
        for (tsym.fields, 0..) |field, fi| {
            // Print "FieldName: " prefix
            const prefix = if (fi > 0)
                try std.fmt.allocPrint(self.allocator, ", {s}: ", .{field.name})
            else
                try std.fmt.allocPrint(self.allocator, "{s}: ", .{field.name});
            const prefix_label = try self.builder.registerString(prefix);
            const prefix_tmp = try self.builder.newTemp();
            try self.builder.emit("    {s} =l copy ${s}\n", .{ prefix_tmp, prefix_label });
            const prefix_sd = try self.builder.newTemp();
            try self.builder.emitCall(prefix_sd, "l", "string_new_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{prefix_tmp}));
            try self.runtime.callVoid("basic_print_string_desc", try std.fmt.allocPrint(self.allocator, "l {s}", .{prefix_sd}));

            // Compute field address
            const field_addr = try self.builder.newTemp();
            if (offset > 0) {
                try self.builder.emitBinary(field_addr, "l", "add", base_ptr, try std.fmt.allocPrint(self.allocator, "{d}", .{offset}));
            } else {
                try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, base_ptr });
            }

            const bt = field.type_desc.base_type;
            if (bt.isInteger()) {
                // Integer field: loadw, sign-extend to l, print as int
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "w", field_addr);
                const fv_long = try self.builder.newTemp();
                try self.builder.emitExtend(fv_long, "l", "extsw", fv);
                try self.runtime.callVoid("basic_print_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv_long}));
            } else if (bt == .double) {
                // Double field: loadd, print as double
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "d", field_addr);
                try self.runtime.callVoid("basic_print_double", try std.fmt.allocPrint(self.allocator, "d {s}", .{fv}));
            } else if (bt == .single) {
                // Single field: loads, extend to double, print as double
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "s", field_addr);
                const fv_d = try self.builder.newTemp();
                try self.builder.emitExtend(fv_d, "d", "exts", fv);
                try self.runtime.callVoid("basic_print_double", try std.fmt.allocPrint(self.allocator, "d {s}", .{fv_d}));
            } else if (bt == .long or bt == .ulong) {
                // Long field: loadl, print as int
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "l", field_addr);
                try self.runtime.callVoid("basic_print_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv}));
            } else if (bt.isString()) {
                // String field: loadl (pointer to string descriptor), print
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "l", field_addr);
                try self.runtime.callVoid("basic_print_string_desc", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv}));
            } else if (bt == .user_defined) {
                // Nested UDT: get the nested type name and recurse
                const nested_name = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                if (nested_name.len > 0) {
                    // Build a synthetic expression pointing at the field address
                    // For simplicity, just print the nested UDT pointer as int
                    const fv = try self.builder.newTemp();
                    try self.builder.emitLoad(fv, "l", field_addr);
                    try self.runtime.callVoid("basic_print_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv}));
                } else {
                    const fv = try self.builder.newTemp();
                    try self.builder.emitLoad(fv, "l", field_addr);
                    try self.runtime.callVoid("basic_print_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv}));
                }
            } else {
                // Fallback: load as long, print as int
                const fv = try self.builder.newTemp();
                try self.builder.emitLoad(fv, "l", field_addr);
                try self.runtime.callVoid("basic_print_int", try std.fmt.allocPrint(self.allocator, "l {s}", .{fv}));
            }

            // Advance offset
            if (field.is_built_in) {
                offset += self.type_manager.sizeOf(bt);
            } else {
                offset += self.type_manager.sizeOfUDT(if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name);
            }
        }

        // Print closing brace
        const close_label = try self.builder.registerString("}");
        const close_tmp = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ close_tmp, close_label });
        const close_sd = try self.builder.newTemp();
        try self.builder.emitCall(close_sd, "l", "string_new_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{close_tmp}));
        try self.runtime.callVoid("basic_print_string_desc", try std.fmt.allocPrint(self.allocator, "l {s}", .{close_sd}));
    }

    fn emitConsoleStatement(self: *BlockEmitter, con: *const ast.ConsoleStmt) EmitError!void {
        for (con.items) |item| {
            // Check for UDT variables — same treatment as emitPrintStatement
            const udt_name = self.expr_emitter.inferUDTNameForExpr(item.expr);
            if (udt_name) |uname| {
                try self.emitPrintUDT(item.expr, uname);
            } else {
                const val = try self.expr_emitter.emitExpression(item.expr);
                const et = self.expr_emitter.inferExprType(item.expr);
                const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.printArgLetter(), val });
                try self.runtime.callVoid(et.printFn(), args);
            }
        }
        if (con.trailing_newline) {
            try self.runtime.callVoid("basic_print_newline", "");
        }
    }

    fn emitLetStatement(self: *BlockEmitter, lt: *const ast.LetStmt) EmitError!void {
        // ── UDT arithmetic interception ─────────────────────────────────
        // Before evaluating the RHS expression, check if this is a UDT
        // binary arithmetic assignment (C = A + B where A, B, C are UDTs).
        // If so, emit NEON or scalar field-by-field arithmetic directly.
        if (lt.member_chain.len == 0 and lt.indices.len == 0) {
            const resolved_early = try self.resolveVarAddr(lt.variable, lt.type_suffix);
            if (resolved_early.base_type == .user_defined) {
                // Look up the UDT type name
                var vlu_buf_early: [128]u8 = undefined;
                const vlu_base_early = SymbolMapper.stripSuffix(lt.variable);
                const vlu_len_early = @min(vlu_base_early.len, vlu_buf_early.len);
                for (0..vlu_len_early) |vli| vlu_buf_early[vli] = std.ascii.toUpper(vlu_base_early[vli]);
                const vlu_upper_early = vlu_buf_early[0..vlu_len_early];
                const udt_name_early: ?[]const u8 = blk: {
                    if (self.symbol_table.lookupVariable(vlu_upper_early)) |vsym| {
                        if (vsym.type_desc.udt_name.len > 0) break :blk vsym.type_desc.udt_name;
                    }
                    break :blk null;
                };
                if (udt_name_early) |utn| {
                    if (lt.value.data == .binary) {
                        // Get the target struct address
                        const dst_ptr_early = try self.builder.newTemp();
                        try self.builder.emitLoad(dst_ptr_early, "l", resolved_early.addr);
                        if (try self.tryEmitUDTArithmetic(lt, dst_ptr_early, utn)) {
                            return;
                        }
                    }
                }
            }
        }
        // Also handle array element UDT arithmetic: Arr(i) = A op B
        if (lt.indices.len > 0 and lt.member_chain.len == 0 and !self.expr_emitter.isHashmapVariable(lt.variable)) {
            if (lt.value.data == .binary) {
                // Check if the array element type is a UDT
                var alu_buf_early: [128]u8 = undefined;
                const alu_len_early = @min(lt.variable.len, alu_buf_early.len);
                for (0..alu_len_early) |ali| alu_buf_early[ali] = std.ascii.toUpper(lt.variable[ali]);
                if (self.symbol_table.lookupArray(alu_buf_early[0..alu_len_early])) |arr_sym| {
                    if (arr_sym.element_type_desc.base_type == .user_defined) {
                        const arr_udt_name = arr_sym.element_type_desc.udt_name;
                        if (arr_udt_name.len > 0) {
                            // Compute the array element address
                            const index_val_early = try self.expr_emitter.emitExpression(lt.indices[0]);
                            const idx_type_early = self.expr_emitter.inferExprType(lt.indices[0]);
                            const index_int_early = if (idx_type_early == .integer) index_val_early else blk: {
                                const t = try self.builder.newTemp();
                                try self.builder.emitConvert(t, "w", "dtosi", index_val_early);
                                break :blk t;
                            };
                            const desc_name_early = try self.symbol_mapper.arrayDescName(lt.variable);
                            const desc_addr_early = try self.builder.newTemp();
                            try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr_early, desc_name_early });
                            const bc_args_early = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr_early, index_int_early });
                            try self.builder.emitCall("", "", "fbc_array_bounds_check", bc_args_early);
                            const elem_addr_early = try self.builder.newTemp();
                            const ea_args_early = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr_early, index_int_early });
                            try self.builder.emitCall(elem_addr_early, "l", "fbc_array_element_addr", ea_args_early);

                            if (try self.tryEmitUDTArithmetic(lt, elem_addr_early, arr_udt_name)) {
                                return;
                            }
                        }
                    }
                }
            }
        }

        const val = try self.expr_emitter.emitExpression(lt.value);
        const bt = semantic.baseTypeFromSuffix(lt.type_suffix);
        const store_type = bt.toQBEMemOp();

        // ── Simple variable assignment ──────────────────────────────────
        if (lt.member_chain.len == 0 and lt.indices.len == 0) {
            // Check if this is a return-via-assignment inside a METHOD body
            // (e.g. MethodName = expr)
            if (self.method_ret_slot.len > 0 and self.method_name.len > 0) {
                if (std.ascii.eqlIgnoreCase(lt.variable, self.method_name)) {
                    const expr_type = self.expr_emitter.inferExprType(lt.value);
                    const ret_store = self.method_ret_type.base_type.toQBEMemOp();
                    const effective_val = try self.emitTypeConversion(val, expr_type, self.method_ret_type.base_type);
                    try self.builder.emitStore(ret_store, effective_val, self.method_ret_slot);
                    return;
                }
            }

            // Check if this is a return-value assignment (FuncName = expr).
            if (self.func_ctx) |fctx| {
                var upper_buf: [128]u8 = undefined;
                const base = SymbolMapper.stripSuffix(lt.variable);
                const ulen = @min(base.len, upper_buf.len);
                for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
                const upper_base = upper_buf[0..ulen];

                if (fctx.isReturnAssignment(upper_base)) {
                    if (fctx.return_addr) |ret_addr| {
                        const expr_type = self.expr_emitter.inferExprType(lt.value);
                        const ret_store = fctx.return_base_type.toQBEMemOp();
                        const effective_val = try self.emitTypeConversion(val, expr_type, fctx.return_base_type);
                        try self.builder.emitStore(ret_store, effective_val, ret_addr);
                        return;
                    }
                }
            }

            // Check function context for params/locals.
            const resolved = try self.resolveVarAddr(lt.variable, lt.type_suffix);
            const var_addr = resolved.addr;

            // UDT value copy: when assigning one UDT variable to another
            // (e.g. Cpy = Src), copy the struct bytes instead of the pointer
            // so the two variables remain independent.
            if (resolved.base_type == .user_defined) {
                // Look up the UDT type name to determine its size.
                var vlu_buf: [128]u8 = undefined;
                const vlu_base = SymbolMapper.stripSuffix(lt.variable);
                const vlu_len = @min(vlu_base.len, vlu_buf.len);
                for (0..vlu_len) |vli| vlu_buf[vli] = std.ascii.toUpper(vlu_base[vli]);
                const vlu_upper = vlu_buf[0..vlu_len];
                const udt_type_name: ?[]const u8 = blk: {
                    if (self.symbol_table.lookupVariable(vlu_upper)) |vsym| {
                        if (vsym.type_desc.udt_name.len > 0) break :blk vsym.type_desc.udt_name;
                    }
                    break :blk null;
                };
                if (udt_type_name) |utn| {
                    const udt_sz = self.type_manager.sizeOfUDT(utn);
                    if (udt_sz > 0) {
                        // val = pointer to source struct (from CREATE or variable load)
                        // var_addr = $var_Cpy (holds pointer to dest struct)
                        // Load destination struct pointer from the variable slot.
                        const dst_ptr = try self.builder.newTemp();
                        try self.builder.emitLoad(dst_ptr, "l", var_addr);
                        try self.builder.emitBlit(val, dst_ptr, udt_sz);
                        return;
                    }
                }
            }

            // Convert value to target type if needed.
            const expr_type = self.expr_emitter.inferExprType(lt.value);
            const effective_val = try self.emitTypeConversion(val, expr_type, resolved.base_type);
            try self.builder.emitStore(resolved.store_type, effective_val, var_addr);
            return;
        }

        // ── Hashmap subscript store: dict("key") = value ────────────────
        if (lt.indices.len > 0 and self.expr_emitter.isHashmapVariable(lt.variable)) {
            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "HASHMAP insert: {s}(...) = ...", .{lt.variable}));

            // Load the hashmap pointer from the global variable
            const hm_var_name = try self.symbol_mapper.globalVarName(lt.variable, null);
            const map_ptr = try self.builder.newTemp();
            try self.builder.emitLoad(map_ptr, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{hm_var_name}));

            // Evaluate the key expression (string descriptor)
            const key_val = try self.expr_emitter.emitExpression(lt.indices[0]);

            // Convert StringDescriptor* → C string (char*) for hashmap API
            const key_cstr = try self.builder.newTemp();
            try self.builder.emitCall(key_cstr, "l", "string_to_utf8", try std.fmt.allocPrint(self.allocator, "l {s}", .{key_val}));

            // The value is already emitted (val). It's a StringDescriptor* for string values.
            // Call hashmap_insert(map, key_cstr, value)
            const insert_result = try self.builder.newTemp();
            try self.builder.emitCall(insert_result, "w", "hashmap_insert", try std.fmt.allocPrint(self.allocator, "l {s}, l {s}, l {s}", .{ map_ptr, key_cstr, val }));
            return;
        }

        // ── Array element store: a%(i) = value ─────────────────────────
        // Also handles array-element-then-member-chain: arr(i).field = value
        if (lt.indices.len > 0 and !self.expr_emitter.isHashmapVariable(lt.variable)) {
            const index_val = try self.expr_emitter.emitExpression(lt.indices[0]);
            const idx_type = self.expr_emitter.inferExprType(lt.indices[0]);
            const index_int = if (idx_type == .integer) index_val else blk: {
                const t = try self.builder.newTemp();
                try self.builder.emitConvert(t, "w", "dtosi", index_val);
                break :blk t;
            };

            const desc_name = try self.symbol_mapper.arrayDescName(lt.variable);
            const desc_addr = try self.builder.newTemp();
            try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr, desc_name });

            // Bounds check
            const bc_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
            try self.builder.emitCall("", "", "fbc_array_bounds_check", bc_args);

            // Get element address
            const elem_addr = try self.builder.newTemp();
            const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
            try self.builder.emitCall(elem_addr, "l", "fbc_array_element_addr", ea_args);

            // Look up the array element type from the symbol table so we
            // use the correct store op (e.g. storel for class instances
            // instead of stored which would be wrong for pointers).
            var arr_bt = bt;
            var arr_store_type = store_type;
            {
                var alu_buf: [128]u8 = undefined;
                const alu_len = @min(lt.variable.len, alu_buf.len);
                for (0..alu_len) |ali| alu_buf[ali] = std.ascii.toUpper(lt.variable[ali]);
                if (self.symbol_table.lookupArray(alu_buf[0..alu_len])) |arr_sym| {
                    if (arr_sym.element_type_desc.base_type != .unknown) {
                        arr_bt = arr_sym.element_type_desc.base_type;
                        arr_store_type = arr_bt.toQBEMemOp();
                    }
                }
            }

            // ── arr(i).field = value  (array element + member chain) ───
            if (lt.member_chain.len > 0) {
                // Determine the class/UDT for this array element
                var arr_class_name: ?[]const u8 = null;
                var arr_udt_name: ?[]const u8 = null;
                {
                    var alu2_buf: [128]u8 = undefined;
                    const alu2_len = @min(lt.variable.len, alu2_buf.len);
                    for (0..alu2_len) |ali2| alu2_buf[ali2] = std.ascii.toUpper(lt.variable[ali2]);
                    if (self.symbol_table.lookupArray(alu2_buf[0..alu2_len])) |arr_sym| {
                        if (arr_sym.element_type_desc.base_type == .class_instance and arr_sym.element_type_desc.is_class_type) {
                            arr_class_name = arr_sym.element_type_desc.class_name;
                        } else if (arr_sym.element_type_desc.base_type == .user_defined) {
                            arr_udt_name = arr_sym.element_type_desc.udt_name;
                        }
                    }
                }

                // For class instances, the array element stores a pointer
                // that must be loaded.  For inline UDTs, elem_addr already
                // IS the struct address — use it directly.
                const obj_ptr = if (arr_udt_name != null) elem_addr else blk: {
                    const p = try self.builder.newTemp();
                    try self.builder.emitLoad(p, "l", elem_addr);
                    break :blk p;
                };

                // CLASS instance field store on array element
                if (arr_class_name) |cname| {
                    var cu_buf3: [128]u8 = undefined;
                    const cu_len3 = @min(cname.len, cu_buf3.len);
                    for (0..cu_len3) |ci3| cu_buf3[ci3] = std.ascii.toUpper(cname[ci3]);
                    if (self.symbol_table.lookupClass(cu_buf3[0..cu_len3])) |cls| {
                        var current_addr3 = obj_ptr;
                        var current_cls: *const semantic.ClassSymbol = cls;

                        for (lt.member_chain, 0..) |member_name, chain_idx| {
                            const is_last = (chain_idx == lt.member_chain.len - 1);

                            if (current_cls.findField(member_name)) |field_info| {
                                const field_addr = try self.builder.newTemp();
                                if (field_info.offset > 0) {
                                    try self.builder.emitBinary(field_addr, "l", "add", current_addr3, try std.fmt.allocPrint(self.allocator, "{d}", .{field_info.offset}));
                                } else {
                                    try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, current_addr3 });
                                }

                                if (is_last) {
                                    const field_store_type = field_info.type_desc.base_type.toQBEMemOp();
                                    const expr_type = self.expr_emitter.inferExprType(lt.value);
                                    const effective_val = try self.emitTypeConversion(val, expr_type, field_info.type_desc.base_type);
                                    try self.builder.emitStore(field_store_type, effective_val, field_addr);
                                } else {
                                    const next_addr = try self.builder.newTemp();
                                    try self.builder.emitLoad(next_addr, "l", field_addr);
                                    current_addr3 = next_addr;
                                    if (field_info.type_desc.base_type == .class_instance and field_info.type_desc.is_class_type) {
                                        var inner_buf2: [128]u8 = undefined;
                                        const inner_len2 = @min(field_info.type_desc.class_name.len, inner_buf2.len);
                                        for (0..inner_len2) |ii2| inner_buf2[ii2] = std.ascii.toUpper(field_info.type_desc.class_name[ii2]);
                                        if (self.symbol_table.lookupClass(inner_buf2[0..inner_len2])) |inner_cls| {
                                            current_cls = inner_cls;
                                        }
                                    }
                                }
                            } else {
                                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: field .{s} not found in {s}", .{ member_name, current_cls.name }));
                            }
                        }
                        return;
                    }
                }

                // UDT field store on array element
                if (arr_udt_name) |udt_tn| {
                    if (self.symbol_table.lookupType(udt_tn)) |type_sym| {
                        var current_addr4 = obj_ptr;
                        var current_type_name2: ?[]const u8 = udt_tn;

                        for (lt.member_chain, 0..) |member_name, chain_idx| {
                            const is_last = (chain_idx == lt.member_chain.len - 1);
                            if (current_type_name2) |tn2| {
                                if (self.symbol_table.lookupType(tn2)) |tsym| {
                                    var offset2: u32 = 0;
                                    for (tsym.fields) |field| {
                                        if (std.mem.eql(u8, field.name, member_name)) {
                                            const field_addr = try self.builder.newTemp();
                                            if (offset2 > 0) {
                                                try self.builder.emitBinary(field_addr, "l", "add", current_addr4, try std.fmt.allocPrint(self.allocator, "{d}", .{offset2}));
                                            } else {
                                                try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, current_addr4 });
                                            }
                                            if (is_last) {
                                                const field_store_type = field.type_desc.base_type.toQBEMemOp();
                                                const expr_type = self.expr_emitter.inferExprType(lt.value);
                                                const effective_val = try self.emitTypeConversion(val, expr_type, field.type_desc.base_type);
                                                try self.builder.emitStore(field_store_type, effective_val, field_addr);
                                            } else {
                                                // For inline UDT fields, the field address
                                                // IS the sub-struct — don't dereference it.
                                                if (field.type_desc.base_type == .user_defined) {
                                                    current_addr4 = field_addr;
                                                } else {
                                                    const next_addr = try self.builder.newTemp();
                                                    try self.builder.emitLoad(next_addr, "l", field_addr);
                                                    current_addr4 = next_addr;
                                                }
                                                current_type_name2 = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                                            }
                                            break;
                                        }
                                        // Use sizeOfUDT for user_defined fields
                                        // since sizeOf(.user_defined) returns 0.
                                        const field_size = if (field.type_desc.base_type == .user_defined)
                                            self.type_manager.sizeOfUDT(field.type_name)
                                        else
                                            self.type_manager.sizeOf(field.type_desc.base_type);
                                        offset2 += if (field_size == 0) 8 else field_size;
                                    }
                                }
                            }
                            _ = type_sym;
                        }
                        return;
                    }
                }

                // Fallback: store directly (flat field offset unknown)
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unresolved array element member store {s}(...).{s}", .{ lt.variable, lt.member_chain[0] }));
                try self.builder.emitStore(arr_store_type, val, elem_addr);
                return;
            }

            // Simple array element store (no member chain)
            // For class instances / objects, no conversion needed — both
            // source and target are pointer-sized (l).
            if (arr_bt == .class_instance or arr_bt == .object) {
                try self.builder.emitStore(arr_store_type, val, elem_addr);
            } else {
                const expr_type = self.expr_emitter.inferExprType(lt.value);
                const effective_val = try self.emitTypeConversion(val, expr_type, arr_bt);
                try self.builder.emitStore(arr_store_type, effective_val, elem_addr);
            }
            return;
        }

        // ── Member chain store: point.x = value ────────────────────────
        if (lt.member_chain.len > 0) {
            // ── ME.field = value inside CLASS body ──────────────────────
            if (std.ascii.eqlIgnoreCase(lt.variable, "ME")) {
                if (self.class_ctx) |cls| {
                    // Simple single-level ME.Field = value
                    if (lt.member_chain.len == 1) {
                        const member_name = lt.member_chain[0];
                        if (cls.findField(member_name)) |field_info| {
                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "ME.{s} = ... (offset {d})", .{ member_name, field_info.offset }));
                            const field_addr = try self.builder.newTemp();
                            if (field_info.offset > 0) {
                                try self.builder.emitBinary(field_addr, "l", "add", "%me", try std.fmt.allocPrint(self.allocator, "{d}", .{field_info.offset}));
                            } else {
                                try self.builder.emit("    {s} =l copy %me\n", .{field_addr});
                            }
                            const field_store_type = field_info.type_desc.base_type.toQBEMemOp();
                            const expr_type = self.expr_emitter.inferExprType(lt.value);
                            const effective_val = try self.emitTypeConversion(val, expr_type, field_info.type_desc.base_type);
                            try self.builder.emitStore(field_store_type, effective_val, field_addr);
                            return;
                        }
                    }
                }
            }

            // ── CLASS instance field store: obj.field = value ───────────
            const class_name_opt = self.expr_emitter.inferClassName(&ast.Expression{
                .data = .{ .variable = .{ .name = lt.variable } },
                .loc = .{},
            });

            if (class_name_opt) |cname| {
                var cu_buf2: [128]u8 = undefined;
                const cu_len2 = @min(cname.len, cu_buf2.len);
                for (0..cu_len2) |i| cu_buf2[i] = std.ascii.toUpper(cname[i]);
                const cu_name2 = cu_buf2[0..cu_len2];

                if (self.symbol_table.lookupClass(cu_name2)) |cls| {
                    // Load the object pointer
                    const resolved2 = try self.resolveVarAddr(lt.variable, lt.type_suffix);
                    const obj_ptr = try self.builder.newTemp();
                    try self.builder.emitLoad(obj_ptr, "l", resolved2.addr);

                    // Walk the member chain
                    var current_addr2 = obj_ptr;
                    var current_cls: *const semantic.ClassSymbol = cls;

                    for (lt.member_chain, 0..) |member_name, chain_idx| {
                        const is_last = (chain_idx == lt.member_chain.len - 1);

                        if (current_cls.findField(member_name)) |field_info| {
                            const field_addr = try self.builder.newTemp();
                            if (field_info.offset > 0) {
                                try self.builder.emitBinary(field_addr, "l", "add", current_addr2, try std.fmt.allocPrint(self.allocator, "{d}", .{field_info.offset}));
                            } else {
                                try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, current_addr2 });
                            }

                            if (is_last) {
                                const field_store_type = field_info.type_desc.base_type.toQBEMemOp();
                                const expr_type = self.expr_emitter.inferExprType(lt.value);
                                const effective_val = try self.emitTypeConversion(val, expr_type, field_info.type_desc.base_type);
                                try self.builder.emitStore(field_store_type, effective_val, field_addr);
                            } else {
                                // Intermediate: load pointer for nested access
                                const next_addr = try self.builder.newTemp();
                                try self.builder.emitLoad(next_addr, "l", field_addr);
                                current_addr2 = next_addr;
                                // Try to follow the class chain
                                if (field_info.type_desc.base_type == .class_instance and field_info.type_desc.is_class_type) {
                                    var inner_buf: [128]u8 = undefined;
                                    const inner_len = @min(field_info.type_desc.class_name.len, inner_buf.len);
                                    for (0..inner_len) |ii| inner_buf[ii] = std.ascii.toUpper(field_info.type_desc.class_name[ii]);
                                    if (self.symbol_table.lookupClass(inner_buf[0..inner_len])) |inner_cls| {
                                        current_cls = inner_cls;
                                    }
                                }
                            }
                        } else {
                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: field .{s} not found in {s}", .{ member_name, current_cls.name }));
                        }
                    }
                    return;
                }
            }

            // ── UDT member chain store (original behavior) ─────────────
            // For UDT variables stored inline, we need the ADDRESS of the
            // variable, not its loaded content.  Use `copy` instead of `loadl`.
            const var_name = try self.symbol_mapper.globalVarName(lt.variable, lt.type_suffix);
            const base_addr = try self.builder.newTemp();

            // UDT variables store a POINTER to the struct in their
            // global slot (allocated by CREATE).  Load the pointer
            // with loadl so we get the actual struct address for
            // field offset calculations.
            try self.builder.emitLoad(base_addr, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));

            // Walk the member chain to compute the final field address.
            var current_addr = base_addr;
            var current_type_name: ?[]const u8 = blk: {
                // Try original name
                if (self.symbol_table.lookupVariable(lt.variable)) |vsym| {
                    if (vsym.type_desc.base_type == .user_defined) {
                        break :blk vsym.type_desc.udt_name;
                    }
                }
                // Try uppercase
                var vlu2_buf: [128]u8 = undefined;
                const vlu2_base = SymbolMapper.stripSuffix(lt.variable);
                const vlu2_len = @min(vlu2_base.len, vlu2_buf.len);
                for (0..vlu2_len) |vli2| vlu2_buf[vli2] = std.ascii.toUpper(vlu2_base[vli2]);
                const vlu2_upper = vlu2_buf[0..vlu2_len];
                if (self.symbol_table.lookupVariable(vlu2_upper)) |vsym| {
                    if (vsym.type_desc.base_type == .user_defined) {
                        break :blk vsym.type_desc.udt_name;
                    }
                }
                break :blk null;
            };

            for (lt.member_chain, 0..) |member_name, chain_idx| {
                const is_last = (chain_idx == lt.member_chain.len - 1);
                if (current_type_name) |tn| {
                    if (self.symbol_table.lookupType(tn)) |type_sym| {
                        var offset: u32 = 0;
                        var found = false;
                        for (type_sym.fields) |field| {
                            if (std.mem.eql(u8, field.name, member_name)) {
                                found = true;
                                const field_addr = try self.builder.newTemp();
                                if (offset > 0) {
                                    try self.builder.emitBinary(field_addr, "l", "add", current_addr, try std.fmt.allocPrint(self.allocator, "{d}", .{offset}));
                                } else {
                                    try self.builder.emit("    {s} =l copy {s}\n", .{ field_addr, current_addr });
                                }

                                if (is_last) {
                                    // For user_defined (nested UDT) fields,
                                    // copy the struct bytes inline with blit
                                    // instead of storing a pointer.
                                    if (field.type_desc.base_type == .user_defined) {
                                        const nested_tn = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                                        const nested_sz = self.type_manager.sizeOfUDT(nested_tn);
                                        if (nested_sz > 0) {
                                            try self.builder.emitBlit(val, field_addr, nested_sz);
                                        } else {
                                            try self.builder.emitStore("l", val, field_addr);
                                        }
                                    } else {
                                        // Store the value at this field.
                                        const field_store_type = field.type_desc.base_type.toQBEMemOp();
                                        const expr_type = self.expr_emitter.inferExprType(lt.value);
                                        const effective_val = try self.emitTypeConversion(val, expr_type, field.type_desc.base_type);
                                        try self.builder.emitStore(field_store_type, effective_val, field_addr);
                                    }
                                } else {
                                    // Intermediate nested UDT field.
                                    // If the field is itself a user_defined type
                                    // stored inline, the field address IS the
                                    // nested struct — do NOT load from it.
                                    if (field.type_desc.base_type == .user_defined) {
                                        current_addr = field_addr;
                                    } else {
                                        const next_addr = try self.builder.newTemp();
                                        try self.builder.emitLoad(next_addr, "l", field_addr);
                                        current_addr = next_addr;
                                    }
                                    current_type_name = if (field.type_desc.udt_name.len > 0) field.type_desc.udt_name else field.type_name;
                                }
                                break;
                            }
                            // Use sizeOfUDT for user_defined fields
                            // since sizeOf(.user_defined) returns 0.
                            const field_size = if (field.type_desc.base_type == .user_defined)
                                self.type_manager.sizeOfUDT(field.type_name)
                            else
                                self.type_manager.sizeOf(field.type_desc.base_type);
                            offset += if (field_size == 0) 8 else field_size;
                        }
                        if (!found) {
                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: field .{s} not found in {s}", .{ member_name, tn }));
                        }
                    }
                } else {
                    try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unresolved type for .{s}", .{member_name}));
                }
            }
        }
    }

    /// Convert a value from one expression type to a target BaseType.
    fn emitTypeConversion(self: *BlockEmitter, val: []const u8, from: ExprEmitter.ExprType, to_bt: semantic.BaseType) EmitError![]const u8 {
        const target_qbe = to_bt.toQBEType();
        const is_long_target = std.mem.eql(u8, target_qbe, "l") and to_bt.isInteger();

        // Pointer types (class_instance, object, user_defined) — no conversion
        if (to_bt == .class_instance or to_bt == .object or to_bt == .pointer or to_bt == .user_defined) {
            return val;
        }

        // Double → Single (truncd)
        if (from == .double and to_bt == .single) {
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =s truncd {s}\n", .{ dest, val });
            return dest;
        }

        // Double → Integer (long or word)
        if (from == .double and to_bt.isInteger()) {
            const dest = try self.builder.newTemp();
            if (is_long_target) {
                // Double → long (64-bit integer)
                try self.builder.emitConvert(dest, "l", "dtosi", val);
            } else {
                // Double → word (32-bit integer)
                try self.builder.emitConvert(dest, "w", "dtosi", val);
            }
            return dest;
        }
        // Integer → Double
        if (from == .integer and to_bt == .double) {
            const dest = try self.builder.newTemp();
            try self.builder.emitConvert(dest, "d", "swtof", val);
            return dest;
        }
        // Integer → Single
        if (from == .integer and to_bt == .single) {
            const dest = try self.builder.newTemp();
            // swtof produces double, then truncd to single
            const tmp = try self.builder.newTemp();
            try self.builder.emitConvert(tmp, "d", "swtof", val);
            try self.builder.emit("    {s} =s truncd {s}\n", .{ dest, tmp });
            return dest;
        }
        // Integer (w) → Long (l): sign-extend
        if (from == .integer and is_long_target) {
            const dest = try self.builder.newTemp();
            try self.builder.emitExtend(dest, "l", "extsw", val);
            return dest;
        }
        // Otherwise: no conversion needed.
        return val;
    }

    fn emitDimStatement(self: *BlockEmitter, dim: *const ast.DimStmt) EmitError!void {
        for (dim.arrays) |arr| {
            if (arr.dimensions.len > 0) {
                // ── Array DIM: allocate via runtime ─────────────────────
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s}(...)", .{arr.name}));

                // Evaluate the upper bound expression for dimension 1.
                const upper_val = try self.expr_emitter.emitExpression(arr.dimensions[0]);
                const upper_type = self.expr_emitter.inferExprType(arr.dimensions[0]);
                const upper_int = if (upper_type == .integer) upper_val else blk: {
                    const t = try self.builder.newTemp();
                    try self.builder.emitConvert(t, "w", "dtosi", upper_val);
                    break :blk t;
                };

                // Determine element size from type suffix or AS type.
                const bt = if (arr.has_as_type) blk: {
                    if (arr.as_type_keyword) |kw| {
                        break :blk semantic.baseTypeFromSuffix(kw.asTypeToSuffix());
                    }
                    // No keyword tag — user-defined type/class name
                    if (arr.as_type_name.len > 0) {
                        break :blk TypeManager.baseTypeFromTypeName(arr.as_type_name);
                    }
                    break :blk semantic.baseTypeFromSuffix(null);
                } else semantic.baseTypeFromSuffix(arr.type_suffix);
                const elem_size = self.type_manager.sizeOf(bt);
                const actual_elem_size: u32 = if (elem_size == 0) 8 else elem_size;

                // Get the array descriptor global address.
                const desc_name = try self.symbol_mapper.arrayDescName(arr.name);
                const desc_addr = try self.builder.newTemp();
                try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr, desc_name });

                // Call array_create(ndims=1, desc, upper_bound, elem_size)
                const create_args = try std.fmt.allocPrint(
                    self.allocator,
                    "w 1, l {s}, w {s}, w {d}",
                    .{ desc_addr, upper_int, actual_elem_size },
                );
                try self.builder.emitCall("", "", "fbc_array_create", create_args);
            } else if (self.func_ctx != null) {
                // ── Inside a FUNCTION/SUB: DIM creates a local variable ─
                try self.emitDimAsLocal(arr);
            } else if (arr.initializer) |init_expr| {
                // ── Scalar DIM with initializer (global scope) ──────────
                const val = try self.expr_emitter.emitExpression(init_expr);

                // Compute the base type and effective suffix from AS keyword
                // so globalVarName produces the correct mangled name (e.g.
                // "var_A_int" for DIM A AS INTEGER = 5).
                var effective_dim_suffix = arr.type_suffix;
                const bt = if (arr.has_as_type) blk: {
                    if (arr.as_type_keyword) |kw| {
                        // LIST and HASHMAP are pointer (object) types — their
                        // asTypeToSuffix() returns null which would default to
                        // double.  Detect them explicitly.
                        if (kw == .kw_list or kw == .kw_hashmap) {
                            break :blk semantic.BaseType.object;
                        }
                        const kw_suffix = kw.asTypeToSuffix();
                        if (kw_suffix != null) effective_dim_suffix = kw_suffix;
                        break :blk semantic.baseTypeFromSuffix(kw_suffix);
                    }
                    // No keyword tag — check if it's a CLASS name first
                    if (arr.as_type_name.len > 0) {
                        var cls_upper_buf: [128]u8 = undefined;
                        const cls_ulen = @min(arr.as_type_name.len, cls_upper_buf.len);
                        for (0..cls_ulen) |ci| cls_upper_buf[ci] = std.ascii.toUpper(arr.as_type_name[ci]);
                        if (self.symbol_table.lookupClass(cls_upper_buf[0..cls_ulen]) != null) {
                            break :blk semantic.BaseType.class_instance;
                        }
                        break :blk TypeManager.baseTypeFromTypeName(arr.as_type_name);
                    }
                    break :blk semantic.baseTypeFromSuffix(null);
                } else semantic.baseTypeFromSuffix(arr.type_suffix);
                const var_name = try self.symbol_mapper.globalVarName(arr.name, effective_dim_suffix);
                const store_type = bt.toQBEMemOp();
                const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});

                // For class instances, objects (LIST/HASHMAP), and UDT
                // pointers, no conversion needed — source and target are
                // both pointer-sized (l).
                if (bt == .class_instance or bt == .object or bt == .user_defined) {
                    try self.builder.emitStore(store_type, val, var_addr);
                } else {
                    // Convert value to target type if needed.
                    const expr_type = self.expr_emitter.inferExprType(init_expr);
                    const effective_val = try self.emitTypeConversion(val, expr_type, bt);
                    try self.builder.emitStore(store_type, effective_val, var_addr);
                }
            } else {
                // ── Scalar DIM without initializer (declare only) ───────
                // Check for runtime object types (HASHMAP, LIST) that need
                // constructor calls even without an explicit initializer.
                if (arr.has_as_type) {
                    if (arr.as_type_keyword) |kw| {
                        if (kw == .kw_hashmap) {
                            // DIM x AS HASHMAP → hashmap_new(128)
                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s} AS HASHMAP", .{arr.name}));
                            const var_name = try self.symbol_mapper.globalVarName(arr.name, null);
                            const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});
                            const map_ptr = try self.builder.newTemp();
                            try self.builder.emitCall(map_ptr, "l", "hashmap_new", "w 128");
                            try self.builder.emitStore("l", map_ptr, var_addr);
                        } else if (kw == .kw_list) {
                            // DIM x AS LIST → list_create()
                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s} AS LIST", .{arr.name}));
                            const var_name = try self.symbol_mapper.globalVarName(arr.name, null);
                            const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});
                            const list_ptr = try self.builder.newTemp();
                            try self.builder.emitCall(list_ptr, "l", "list_create", "");
                            try self.builder.emitStore("l", list_ptr, var_addr);
                        }
                    } else if (arr.as_type_name.len > 0) {
                        // No keyword tag — check if it's a UDT that needs
                        // auto-allocation so the pointer slot isn't null.
                        var udt_check_buf: [128]u8 = undefined;
                        const udt_check_len = @min(arr.as_type_name.len, udt_check_buf.len);
                        for (0..udt_check_len) |uci| udt_check_buf[uci] = std.ascii.toUpper(arr.as_type_name[uci]);
                        const udt_check_upper = udt_check_buf[0..udt_check_len];

                        // Only auto-alloc for actual UDT types (not classes,
                        // not primitive type names like INTEGER/STRING).
                        if (self.symbol_table.lookupClass(udt_check_upper) == null and
                            TypeManager.baseTypeFromTypeName(arr.as_type_name) == .user_defined)
                        {
                            const udt_size = self.type_manager.sizeOfUDT(arr.as_type_name);
                            const alloc_size: u32 = if (udt_size == 0) 8 else udt_size;

                            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s} AS {s} (auto-alloc UDT, {d} bytes)", .{ arr.name, arr.as_type_name, alloc_size }));
                            const var_name = try self.symbol_mapper.globalVarName(arr.name, null);
                            const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});
                            const udt_ptr = try self.builder.newTemp();
                            try self.builder.emitCall(udt_ptr, "l", "basic_malloc", try std.fmt.allocPrint(self.allocator, "l {d}", .{alloc_size}));
                            try self.builder.emitStore("l", udt_ptr, var_addr);
                        }
                    }
                }
                // Otherwise the global data section already zero-initialized it.
            }
        }
    }

    /// Emit a DIM declaration as a function-local stack variable.
    /// Called when we are inside a FUNCTION/SUB and the DIM is for a
    /// scalar (non-array) variable.
    fn emitDimAsLocal(self: *BlockEmitter, arr: ast.DimStmt.ArrayDim) EmitError!void {
        const fctx_ptr = self.func_ctx orelse return;
        const fctx: *FunctionContext = @constCast(fctx_ptr);

        // Determine the base type from AS keyword, AS type name, or suffix.
        const bt: semantic.BaseType = if (arr.has_as_type) blk: {
            if (arr.as_type_keyword) |kw| {
                // LIST and HASHMAP are pointer (object) types — their
                // asTypeToSuffix() returns null which would default to
                // double.  Detect them explicitly.
                if (kw == .kw_list or kw == .kw_hashmap) {
                    break :blk semantic.BaseType.object;
                }
                break :blk semantic.baseTypeFromSuffix(kw.asTypeToSuffix());
            }
            // No keyword tag stored — check if the parser stored a type
            // name string (e.g. "INTEGER", "STRING") in as_type_name.
            if (arr.as_type_name.len > 0) {
                // Check if it's a CLASS name first — must use class_instance
                // so that initialisers (NEW ...) are not subjected to
                // spurious dtosi conversion (pointers are not doubles).
                var cls_check_buf: [128]u8 = undefined;
                const cls_check_len = @min(arr.as_type_name.len, cls_check_buf.len);
                for (0..cls_check_len) |ci| cls_check_buf[ci] = std.ascii.toUpper(arr.as_type_name[ci]);
                if (self.symbol_table.lookupClass(cls_check_buf[0..cls_check_len]) != null) {
                    break :blk semantic.BaseType.class_instance;
                }
                break :blk TypeManager.baseTypeFromTypeName(arr.as_type_name);
            }
            // AS <UDT name> — treat as pointer/object (long).
            break :blk .long;
        } else semantic.baseTypeFromSuffix(arr.type_suffix);

        const qbe_t = bt.toQBEType();
        const size = self.type_manager.sizeOf(bt);
        const actual_size: u32 = if (size == 0) 8 else size;
        const alignment: u32 = self.type_manager.alignOf(bt);

        // Allocate stack slot.
        const addr = try self.builder.newTemp();
        try self.builder.emitAlloc(addr, actual_size, alignment);

        // Zero-initialise.
        if (bt == .class_instance or bt == .object) {
            try self.builder.emitStore("l", "0", addr);
        } else if (bt.isNumeric()) {
            if (bt.isInteger()) {
                try self.builder.emitStore(bt.toQBEMemOp(), "0", addr);
            } else {
                try self.builder.emitStore(bt.toQBEMemOp(), "d_0.0", addr);
            }
        } else if (bt == .string or bt == .long) {
            try self.builder.emitStore("l", "0", addr);
        } else if (bt == .user_defined) {
            // UDT local without initialiser — allocate struct memory via
            // basic_malloc so the pointer slot isn't null.
            if (arr.as_type_name.len > 0) {
                const udt_size = self.type_manager.sizeOfUDT(arr.as_type_name);
                const alloc_size: u32 = if (udt_size == 0) 8 else udt_size;
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s} AS {s} (local auto-alloc UDT, {d} bytes)", .{ arr.name, arr.as_type_name, alloc_size }));
                const udt_ptr = try self.builder.newTemp();
                try self.builder.emitCall(udt_ptr, "l", "basic_malloc", try std.fmt.allocPrint(self.allocator, "l {d}", .{alloc_size}));
                try self.builder.emitStore("l", udt_ptr, addr);
            } else {
                try self.builder.emitStore("l", "0", addr);
            }
        }

        // If there's an initialiser, evaluate and store it.
        if (arr.initializer) |init_expr| {
            const init_val = try self.expr_emitter.emitExpression(init_expr);
            // For class instance assignments (NEW), no conversion needed —
            // both source and target are pointer-sized (l).
            if (bt == .class_instance or bt == .object or bt == .user_defined) {
                try self.builder.emitStore("l", init_val, addr);
            } else {
                const expr_type = self.expr_emitter.inferExprType(init_expr);
                const effective = try self.emitTypeConversion(init_val, expr_type, bt);
                try self.builder.emitStore(bt.toQBEMemOp(), effective, addr);
            }
        }

        // Register in function context so subsequent references resolve
        // to this stack slot.
        var upper_buf: [128]u8 = undefined;
        const base = SymbolMapper.stripSuffix(arr.name);
        const ulen = @min(base.len, upper_buf.len);
        for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
        const upper_key = try self.allocator.dupe(u8, upper_buf[0..ulen]);

        // For class instance locals, also register the variable in the
        // symbol table so that inferClassName can find it later (for
        // member access and method calls on the local variable).
        if (bt == .class_instance and arr.as_type_name.len > 0) {
            if (self.func_ctx != null) {
                // Register a VariableSymbol so inferClassName can resolve the class name.
                const var_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{
                    fctx.upper_name, upper_key,
                });
                const mut_st: *semantic.SymbolTable = @constCast(self.symbol_table);
                try mut_st.insertVariable(var_key, .{
                    .name = arr.name,
                    .type_desc = semantic.TypeDescriptor.fromClass(arr.as_type_name),
                    .type_name = arr.as_type_name,
                    .is_declared = true,
                    .first_use = .{},
                    .scope = .{ .kind = .function, .name = fctx.func_name },
                    .is_global = false,
                });
            }
        }

        try fctx.local_addrs.put(upper_key, .{
            .addr = addr,
            .qbe_type = qbe_t,
            .base_type = bt,
            .suffix = arr.type_suffix,
        });
    }

    fn emitCallStatement(self: *BlockEmitter, cs: *const ast.CallStmt) EmitError!void {
        // If this is a method-call statement (e.g. dict.CLEAR(), list.APPEND(x)),
        // evaluate the method call expression for its side effects and discard
        // the return value.
        if (cs.method_call_expr) |expr| {
            _ = try self.expr_emitter.emitExpression(expr);
            return;
        }

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        for (cs.arguments, 0..) |arg, i| {
            if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.expr_emitter.emitExpression(arg);
            const arg_type = self.expr_emitter.inferExprType(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "{s} {s}", .{ arg_type.argLetter(), arg_val });
        }

        const mangled = try self.symbol_mapper.subName(cs.sub_name);
        try self.builder.emitCall("", "", mangled, args_buf.items);
    }

    fn emitReturnStatement(self: *BlockEmitter, rs: *const ast.ReturnStmt) EmitError!void {
        if (rs.return_value) |rv| {
            var val = try self.expr_emitter.emitExpression(rv);
            // Convert the expression result to match the function's
            // declared return type.  The expression system works with
            // 'd' (double) for all floats and 'w' (word) for all ints,
            // but the function may return 's' (SINGLE) or 'l' (LONG).
            if (self.func_ctx) |fctx| {
                const ret_t = fctx.return_type;
                const expr_et = self.expr_emitter.inferExprType(rv);
                if (std.mem.eql(u8, ret_t, "s") and expr_et == .double) {
                    // double → single: truncate
                    const cvt = try self.builder.newTemp();
                    try self.builder.emitConvert(cvt, "s", "truncd", val);
                    val = cvt;
                } else if (std.mem.eql(u8, ret_t, "l") and expr_et == .integer and !self.expr_emitter.isLongExpr(rv)) {
                    // word → long: sign-extend
                    const cvt = try self.builder.newTemp();
                    try self.builder.emitExtend(cvt, "l", "extsw", val);
                    val = cvt;
                } else if (std.mem.eql(u8, ret_t, "w") and expr_et == .integer and self.expr_emitter.isLongExpr(rv)) {
                    // long → word: truncate (shouldn't normally happen, but be safe)
                    const cvt = try self.builder.newTemp();
                    try self.builder.emitInstruction(try std.fmt.allocPrint(
                        self.allocator,
                        "{s} =w copy {s}",
                        .{ cvt, val },
                    ));
                    val = cvt;
                }
            }
            try self.builder.emitReturn(val);
        } else {
            try self.builder.emitReturn("");
        }
    }

    fn emitIncDec(self: *BlockEmitter, id: *const ast.IncDecStmt, is_inc: bool) EmitError!void {
        const resolved = try self.resolveVarAddr(id.var_name, null);
        const var_addr = resolved.addr;
        const bt = resolved.base_type;
        const is_int = bt.isInteger();
        const qbe_t: []const u8 = if (is_int) "w" else "d";
        const load_t = resolved.store_type;

        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, load_t, var_addr);

        const amount = if (id.amount_expr) |ae| blk: {
            const raw = try self.expr_emitter.emitExpression(ae);
            const ae_type = self.expr_emitter.inferExprType(ae);
            // Convert amount to match variable type if needed.
            if (is_int and ae_type == .double) {
                const t = try self.builder.newTemp();
                try self.builder.emitConvert(t, "w", "dtosi", raw);
                break :blk t;
            } else if (!is_int and ae_type == .integer) {
                const t = try self.builder.newTemp();
                try self.builder.emitConvert(t, "d", "swtof", raw);
                break :blk t;
            }
            break :blk raw;
        } else blk: {
            const one = try self.builder.newTemp();
            if (is_int) {
                try self.builder.emit("    {s} =w copy 1\n", .{one});
            } else {
                try self.builder.emit("    {s} =d copy d_1.0\n", .{one});
            }
            break :blk one;
        };

        const result = try self.builder.newTemp();
        if (is_inc) {
            try self.builder.emitBinary(result, qbe_t, "add", cur, amount);
        } else {
            try self.builder.emitBinary(result, qbe_t, "sub", cur, amount);
        }
        try self.builder.emitStore(load_t, result, var_addr);
    }

    fn emitSwapStatement(self: *BlockEmitter, sw: *const ast.SwapStmt) EmitError!void {
        const resolved1 = try self.resolveVarAddr(sw.var1, null);
        const resolved2 = try self.resolveVarAddr(sw.var2, null);

        // Use the type of the first variable for the swap operation.
        // If both are the same type this is straightforward; if they
        // differ we use the wider type (double) to avoid truncation.
        const load1 = resolved1.store_type;
        const load2 = resolved2.store_type;

        const tmp1 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp1, load1, resolved1.addr);
        const tmp2 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp2, load2, resolved2.addr);
        try self.builder.emitStore(load1, tmp2, resolved1.addr);
        try self.builder.emitStore(load2, tmp1, resolved2.addr);
    }

    // ── LOCAL / SHARED statement handling ───────────────────────────────

    fn emitLocalStatement(self: *BlockEmitter, loc_stmt: *const ast.LocalStmt) EmitError!void {
        // LOCAL declarations allocate stack space for function-local
        // variables and register them in the function context.
        const fctx_ptr = if (self.func_ctx) |f| f else {
            try self.builder.emitComment("WARN: LOCAL outside function — ignored");
            return;
        };
        // We need a mutable pointer to update the context.
        const fctx: *FunctionContext = @constCast(fctx_ptr);

        for (loc_stmt.variables) |lv| {
            // Determine base type: prefer AS keyword if present, then
            // fall back to type suffix.
            const bt: semantic.BaseType = if (lv.has_as_type and lv.as_type_name.len > 0) blk: {
                // The parser stores the AS type as a string (e.g.
                // "INTEGER", "STRING").  Convert it to a BaseType.
                break :blk TypeManager.baseTypeFromTypeName(lv.as_type_name);
            } else if (lv.type_suffix) |suf| blk: {
                break :blk semantic.baseTypeFromSuffix(suf);
            } else blk: {
                break :blk semantic.baseTypeFromSuffix(null);
            };
            const qbe_t = bt.toQBEType();
            const size = self.type_manager.sizeOf(bt);
            const actual_size: u32 = if (size == 0) 8 else size;
            const alignment: u32 = self.type_manager.alignOf(bt);

            const addr = try self.builder.newTemp();
            try self.builder.emitAlloc(addr, actual_size, alignment);

            // Zero-initialise.
            if (bt.isNumeric()) {
                if (bt.isInteger()) {
                    try self.builder.emitStore(bt.toQBEMemOp(), "0", addr);
                } else {
                    try self.builder.emitStore(bt.toQBEMemOp(), "d_0.0", addr);
                }
            } else if (bt == .string) {
                try self.builder.emitStore("l", "0", addr);
            }

            // If there's an initialiser, evaluate and store it.
            if (lv.initial_value) |init_expr| {
                const init_val = try self.expr_emitter.emitExpression(init_expr);
                const expr_type = self.expr_emitter.inferExprType(init_expr);
                const effective = try self.emitTypeConversion(init_val, expr_type, bt);
                try self.builder.emitStore(bt.toQBEMemOp(), effective, addr);
            }

            // Register in function context.
            var upper_buf: [128]u8 = undefined;
            const base = SymbolMapper.stripSuffix(lv.name);
            const ulen = @min(base.len, upper_buf.len);
            for (0..ulen) |i| upper_buf[i] = std.ascii.toUpper(base[i]);
            const upper_key = try self.allocator.dupe(u8, upper_buf[0..ulen]);

            try fctx.local_addrs.put(upper_key, .{
                .addr = addr,
                .qbe_type = qbe_t,
                .base_type = bt,
                .suffix = lv.type_suffix,
            });
        }
    }

    fn emitSharedStatement(self: *BlockEmitter, sh_stmt: *const ast.SharedStmt) EmitError!void {
        // SHARED declarations make global variables accessible inside a
        // function by name.  We register them so that resolveVarAddr
        // skips the function context and falls through to the global.
        // (Currently the fallback already does this, so we just emit a
        // comment for documentation.)
        for (sh_stmt.variables) |sv| {
            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "SHARED {s}", .{sv.name}));
            try self.symbol_mapper.registerShared(sv.name);
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// CFGCodeGenerator — Top-level CFG-driven orchestrator
// ═══════════════════════════════════════════════════════════════════════════

/// Top-level code generator that walks the CFG in reverse-postorder to
/// produce QBE IL. Replaces the old AST-walking CodeGenerator.
///
/// Usage:
/// ```
/// var gen = CFGCodeGenerator.init(semantic_analyzer, program_cfg, cfg_builder, allocator);
/// defer gen.deinit();
/// const il = try gen.generate(program);
/// ```
pub const CFGCodeGenerator = struct {
    builder: QBEBuilder,
    type_manager: TypeManager,
    symbol_mapper: SymbolMapper,
    runtime: RuntimeLibrary,
    expr_emitter: ?ExprEmitter,
    block_emitter: ?BlockEmitter,

    semantic: *const semantic.SemanticAnalyzer,
    program_cfg: *const cfg_mod.CFG,
    cfg_builder: *const cfg_mod.CFGBuilder,
    allocator: std.mem.Allocator,

    /// Whether to emit verbose comments.
    verbose: bool = false,
    /// Whether SAMM is enabled.
    samm_enabled: bool = true,

    pub fn init(
        sem: *const semantic.SemanticAnalyzer,
        program_cfg: *const cfg_mod.CFG,
        the_cfg_builder: *const cfg_mod.CFGBuilder,
        allocator: std.mem.Allocator,
    ) CFGCodeGenerator {
        return .{
            .allocator = allocator,
            .semantic = sem,
            .program_cfg = program_cfg,
            .cfg_builder = the_cfg_builder,
            .verbose = false,
            .samm_enabled = true,
            .builder = QBEBuilder.init(allocator),
            .type_manager = TypeManager.init(sem.getSymbolTable()),
            .symbol_mapper = SymbolMapper.init(allocator),
            // runtime, expr_emitter, and block_emitter hold interior
            // pointers to this struct, so they must be initialised *after*
            // the struct has settled at its final address (i.e. in
            // generate(), where `self` is a stable *CFGCodeGenerator).
            .runtime = undefined,
            .expr_emitter = null,
            .block_emitter = null,
        };
    }

    pub fn deinit(self: *CFGCodeGenerator) void {
        if (self.block_emitter) |*be| be.deinit();
        self.builder.deinit();
        self.symbol_mapper.deinit();
    }

    /// Generate QBE IL for the entire program. Returns the IL as a string.
    pub fn generate(self: *CFGCodeGenerator, program: *const ast.Program) ![]const u8 {
        // Now that `self` is at its final address we can take interior
        // pointers safely.
        self.runtime = RuntimeLibrary.init(&self.builder);

        self.expr_emitter = ExprEmitter.init(
            &self.builder,
            &self.type_manager,
            &self.symbol_mapper,
            &self.runtime,
            self.semantic.getSymbolTable(),
            self.allocator,
        );

        self.block_emitter = BlockEmitter.init(
            &self.expr_emitter.?,
            &self.builder,
            &self.runtime,
            &self.symbol_mapper,
            &self.type_manager,
            self.semantic.getSymbolTable(),
            self.program_cfg,
            self.allocator,
        );
        self.block_emitter.?.samm_enabled = self.samm_enabled;

        // Phase 1: File header
        try self.emitFileHeader();

        // Phase 2: String constant pool (collect from AST, then emit)
        try self.collectStringLiterals(program);
        try self.builder.emitStringPool();

        // Phase 3: Global data declarations
        try self.emitGlobalVariables();
        try self.emitGlobalArrays();

        // Phase 3b: CLASS vtables and class name strings
        try self.emitClassDeclarations(program);

        // Phase 4: Runtime declarations
        try self.runtime.emitDeclarations();

        // Phase 5: Main function (from program CFG)
        try self.emitCFGFunction(self.program_cfg, "main", "w", "", true, null);

        // Phase 6: Function/Sub definitions (from CFGBuilder's function_cfgs)
        var func_it = self.cfg_builder.function_cfgs.iterator();
        while (func_it.next()) |entry| {
            const func_name = entry.key_ptr.*;
            const func_cfg = entry.value_ptr;

            // Look up semantic info for return type and parameters.
            // The semantic analyzer stores names in uppercase (including
            // any type suffix like "$"), so the lookup key must keep
            // the suffix.  However, the FunctionContext.upper_name used
            // for return-assignment matching (e.g. `Greet$ = expr`)
            // must have the suffix stripped so it matches the variable
            // name after SymbolMapper.stripSuffix.
            var upper_buf: [128]u8 = undefined;
            const upper_len = @min(func_name.len, upper_buf.len);
            for (0..upper_len) |i| {
                upper_buf[i] = std.ascii.toUpper(func_name[i]);
            }
            const upper_name = upper_buf[0..upper_len];

            // Build a suffix-stripped uppercase name for the context.
            const func_name_base = SymbolMapper.stripSuffix(func_name);
            var upper_base_buf: [128]u8 = undefined;
            const upper_base_len = @min(func_name_base.len, upper_base_buf.len);
            for (0..upper_base_len) |i| {
                upper_base_buf[i] = std.ascii.toUpper(func_name_base[i]);
            }
            const upper_name_stripped = upper_base_buf[0..upper_base_len];

            const st = self.semantic.getSymbolTable();
            const func_sym = st.lookupFunction(upper_name);

            if (func_sym) |fsym| {
                // Determine if it's a FUNCTION (has return value) or a SUB (void).
                const ret_type = fsym.return_type_desc.toQBEType();
                const is_func = !std.mem.eql(u8, ret_type, "") and fsym.return_type_desc.base_type != .void;
                const mangled = if (is_func)
                    try self.symbol_mapper.functionName(func_name)
                else
                    try self.symbol_mapper.subName(func_name);

                // Build parameter list.
                var params_buf: std.ArrayList(u8) = .empty;
                defer params_buf.deinit(self.allocator);
                for (fsym.parameters, 0..) |param, i| {
                    if (i > 0) try params_buf.appendSlice(self.allocator, ", ");
                    const pt = if (i < fsym.parameter_type_descs.len)
                        fsym.parameter_type_descs[i].toQBEType()
                    else
                        "d";
                    const param_stripped = SymbolMapper.stripSuffix(param);
                    try std.fmt.format(params_buf.writer(self.allocator), "{s} %{s}", .{ pt, param_stripped });
                }

                // Build function context for parameter / local tracking.
                const duped_upper = try self.allocator.dupe(u8, upper_name_stripped);
                var func_ctx = FunctionContext.init(
                    self.allocator,
                    func_name,
                    duped_upper,
                    is_func,
                    if (is_func) ret_type else "",
                    if (is_func) fsym.return_type_desc.base_type else .void,
                );

                // Pre-register parameters in the context so that the
                // function prologue (emitted in emitCFGFunction) can
                // allocate stack slots and copy param values.
                for (fsym.parameters, 0..) |param, i| {
                    const pt_desc = if (i < fsym.parameter_type_descs.len)
                        fsym.parameter_type_descs[i]
                    else
                        semantic.TypeDescriptor.fromBase(.double);

                    const pt = pt_desc.toQBEType();
                    const p_bt = pt_desc.base_type;
                    const p_suffix: ?Tag = if (i < fsym.parameter_type_descs.len) blk: {
                        // Reconstruct suffix from base type
                        break :blk switch (p_bt) {
                            .integer => @as(?Tag, .type_int),
                            .single => @as(?Tag, .type_float),
                            .double => @as(?Tag, .type_double),
                            .string => @as(?Tag, .type_string),
                            .long => @as(?Tag, .ampersand),
                            .byte => @as(?Tag, .type_byte),
                            .short => @as(?Tag, .type_short),
                            else => @as(?Tag, null),
                        };
                    } else null;

                    // Allocate a stack slot for each parameter.
                    const addr = try self.builder.newTemp();
                    const size = self.type_manager.sizeOf(p_bt);
                    const actual_size: u32 = if (size == 0) 8 else size;
                    const alignment: u32 = self.type_manager.alignOf(p_bt);

                    // We record the alloc temp; the actual alloc + copy
                    // instructions will be emitted at the top of the first
                    // block inside emitCFGFunction.

                    const param_base = SymbolMapper.stripSuffix(param);
                    var param_upper_buf: [128]u8 = undefined;
                    const plen = @min(param_base.len, param_upper_buf.len);
                    for (0..plen) |j| param_upper_buf[j] = std.ascii.toUpper(param_base[j]);
                    const param_key = try self.allocator.dupe(u8, param_upper_buf[0..plen]);

                    try func_ctx.param_addrs.put(param_key, .{
                        .addr = addr,
                        .qbe_type = pt,
                        .base_type = p_bt,
                        .suffix = p_suffix,
                    });

                    _ = actual_size;
                    _ = alignment;
                }

                try self.emitCFGFunction(func_cfg, mangled, ret_type, params_buf.items, false, &func_ctx);
                func_ctx.deinit();
            } else {
                // It might be a SUB (no return value).
                const mangled = try self.symbol_mapper.subName(func_name);

                // Build a minimal function context for SUBs too, so that
                // parameters are handled locally.
                const duped_upper = try self.allocator.dupe(u8, upper_name_stripped);
                var func_ctx = FunctionContext.init(
                    self.allocator,
                    func_name,
                    duped_upper,
                    false,
                    "",
                    .void,
                );

                // Look up the SUB in the symbol table (stored as a
                // function with void return).
                const sub_sym = st.lookupFunction(upper_name);
                if (sub_sym) |ssym| {
                    for (ssym.parameters, 0..) |param, i| {
                        const pt_desc = if (i < ssym.parameter_type_descs.len)
                            ssym.parameter_type_descs[i]
                        else
                            semantic.TypeDescriptor.fromBase(.double);

                        const pt = pt_desc.toQBEType();
                        const p_bt = pt_desc.base_type;
                        const p_suffix: ?Tag = switch (p_bt) {
                            .integer => @as(?Tag, .type_int),
                            .single => @as(?Tag, .type_float),
                            .double => @as(?Tag, .type_double),
                            .string => @as(?Tag, .type_string),
                            .long => @as(?Tag, .ampersand),
                            .byte => @as(?Tag, .type_byte),
                            .short => @as(?Tag, .type_short),
                            else => @as(?Tag, null),
                        };

                        const addr = try self.builder.newTemp();
                        const param_base = SymbolMapper.stripSuffix(param);
                        var param_upper_buf: [128]u8 = undefined;
                        const plen = @min(param_base.len, param_upper_buf.len);
                        for (0..plen) |j| param_upper_buf[j] = std.ascii.toUpper(param_base[j]);
                        const param_key = try self.allocator.dupe(u8, param_upper_buf[0..plen]);

                        try func_ctx.param_addrs.put(param_key, .{
                            .addr = addr,
                            .qbe_type = pt,
                            .base_type = p_bt,
                            .suffix = p_suffix,
                        });
                    }

                    // Build param string for the SUB signature.
                    var params_buf: std.ArrayList(u8) = .empty;
                    defer params_buf.deinit(self.allocator);
                    for (ssym.parameters, 0..) |param, i| {
                        if (i > 0) try params_buf.appendSlice(self.allocator, ", ");
                        const pt = if (i < ssym.parameter_type_descs.len)
                            ssym.parameter_type_descs[i].toQBEType()
                        else
                            "d";
                        const param_stripped = SymbolMapper.stripSuffix(param);
                        try std.fmt.format(params_buf.writer(self.allocator), "{s} %{s}", .{ pt, param_stripped });
                    }
                    try self.emitCFGFunction(func_cfg, mangled, "", params_buf.items, false, &func_ctx);
                } else {
                    try self.emitCFGFunction(func_cfg, mangled, "", "", false, &func_ctx);
                }
                func_ctx.deinit();
            }
        }

        // Phase 7: Late string pool (strings discovered during codegen)
        try self.builder.emitLateStringPool();

        // Phase 8: Append hashmap QBE module if program uses hashmaps
        {
            const st2 = self.semantic.getSymbolTable();
            var var_it = st2.variables.iterator();
            var needs_hashmap = false;
            while (var_it.next()) |entry| {
                const vsym = entry.value_ptr;
                if (vsym.type_desc.base_type == .object and
                    std.mem.eql(u8, vsym.type_desc.object_type_name, "HASHMAP"))
                {
                    needs_hashmap = true;
                    break;
                }
            }
            if (needs_hashmap) {
                try self.builder.emitBlankLine();
                try self.builder.emitComment("=== Hashmap Runtime Module (hashmap.qbe) ===");
                try self.builder.raw(@embedFile("hashmap.qbe"));
            }
        }

        return self.builder.getIL();
    }

    // ── Core: emit a single CFG as a QBE function ───────────────────────

    /// Walk a CFG in reverse-postorder and emit QBE IL for each block.
    fn emitCFGFunction(
        self: *CFGCodeGenerator,
        the_cfg: *const cfg_mod.CFG,
        func_name: []const u8,
        return_type: []const u8,
        params: []const u8,
        is_main: bool,
        func_ctx: ?*FunctionContext,
    ) !void {
        var be = &self.block_emitter.?;
        be.setCFG(the_cfg);
        be.resetContexts();

        // Set function context for parameter / local resolution.
        if (func_ctx) |fctx| {
            be.setFunctionContext(fctx);
        }

        try self.builder.emitFunctionStart(func_name, return_type, params);

        // QBE requires every instruction to be inside a labelled block.
        // Emit a prologue label so the parameter-copy / return-slot code
        // that follows lives in a valid block.
        if (!is_main) {
            try self.builder.emitLabel("prologue");
        }

        // ── Function prologue: allocate stack slots for parameters ──────
        if (func_ctx) |fctx| {
            if (fctx.param_addrs.count() > 0) {
                try self.builder.emitComment("--- function prologue: copy params to stack ---");

                // Look up the function symbol to get ordered parameter info.
                var upper_buf2: [128]u8 = undefined;
                const upper_len2 = @min(fctx.func_name.len, upper_buf2.len);
                for (0..upper_len2) |i| upper_buf2[i] = std.ascii.toUpper(fctx.func_name[i]);
                const upper_fn = upper_buf2[0..upper_len2];

                const st = self.semantic.getSymbolTable();
                if (st.lookupFunction(upper_fn)) |fsym| {
                    for (fsym.parameters, 0..) |param, i| {
                        const param_base = SymbolMapper.stripSuffix(param);
                        var param_upper_buf: [128]u8 = undefined;
                        const plen = @min(param_base.len, param_upper_buf.len);
                        for (0..plen) |j| param_upper_buf[j] = std.ascii.toUpper(param_base[j]);
                        const param_key = param_upper_buf[0..plen];

                        if (fctx.param_addrs.get(param_key)) |pi| {
                            const p_bt = pi.base_type;
                            const size = self.type_manager.sizeOf(p_bt);
                            const actual_size: u32 = if (size == 0) 8 else size;
                            const alignment: u32 = self.type_manager.alignOf(p_bt);

                            try self.builder.emitAlloc(pi.addr, actual_size, alignment);

                            // Copy parameter value to stack slot.
                            const p_stripped = SymbolMapper.stripSuffix(param);
                            const param_temp = try std.fmt.allocPrint(self.allocator, "%{s}", .{p_stripped});
                            try self.builder.emitStore(p_bt.toQBEMemOp(), param_temp, pi.addr);
                        }

                        _ = i;
                    }
                }
            }

            // Allocate return value slot for FUNCTIONs.
            if (fctx.is_function and return_type.len > 0) {
                const ret_addr = try self.builder.newTemp();
                // Determine size from return type.
                const ret_size: u32 = if (std.mem.eql(u8, return_type, "d")) 8 else if (std.mem.eql(u8, return_type, "l")) 8 else 4;
                const ret_align: u32 = if (ret_size >= 8) 8 else 4;
                try self.builder.emitAlloc(ret_addr, ret_size, ret_align);

                // Zero-initialise.
                if (std.mem.eql(u8, return_type, "d")) {
                    try self.builder.emitStore("d", "d_0.0", ret_addr);
                } else {
                    try self.builder.emitStore(return_type, "0", ret_addr);
                }

                fctx.return_addr = ret_addr;
            }
        }

        // If the CFG has RPO order available, use it. Otherwise fall back to
        // iterating blocks in index order.
        const order = the_cfg.rpo_order.items;

        if (order.len > 0) {
            for (order) |block_idx| {
                const block = the_cfg.getBlockConst(block_idx);
                if (!block.reachable) continue;
                try self.emitBlock(the_cfg, block, is_main, func_ctx);
            }
        } else {
            // Fallback: iterate all blocks in index order.
            for (the_cfg.blocks.items) |block| {
                try self.emitBlock(the_cfg, &block, is_main, func_ctx);
            }
        }

        try self.builder.emitFunctionEnd();

        // Clear function context.
        if (func_ctx != null) {
            var be2 = &self.block_emitter.?;
            be2.setFunctionContext(null);
            self.symbol_mapper.clearShared();
        }
    }

    /// Emit a single basic block: label, statements, terminator.
    fn emitBlock(
        self: *CFGCodeGenerator,
        the_cfg: *const cfg_mod.CFG,
        block: *const cfg_mod.BasicBlock,
        is_main: bool,
        func_ctx: ?*const FunctionContext,
    ) !void {
        var be = &self.block_emitter.?;
        const label = try blockLabel(the_cfg, block.index, self.allocator);

        // Emit block label.
        try self.builder.emitLabel(label);

        // Special: entry block for main function.
        if (block.kind == .entry and is_main) {
            if (self.samm_enabled) {
                try self.runtime.callVoid("samm_init", "");
            }
            // Pre-allocate FOR loop temp slots in the entry block.
            try be.preAllocateForLoopSlots(the_cfg);
        }

        // Special: entry block for a function/sub — also pre-allocate.
        if (block.kind == .entry and !is_main) {
            try be.preAllocateForLoopSlots(the_cfg);
        }

        // Special: increment block for FOR loops.
        if (block.kind == .loop_increment) {
            try be.emitForIncrement(block);
            try be.emitForEachIncrement(block);
        }

        // Special: body block for FOR EACH loops — load element before statements.
        if (block.kind == .loop_body) {
            try be.emitForEachBodyLoad(block);
        }

        // Emit statements in this block.
        try be.emitBlockStatements(block);

        // Special: exit block for main function.
        if (block.kind == .exit_block and is_main) {
            try self.builder.emitComment("Program exit");
            if (self.samm_enabled) {
                try self.runtime.callVoid("samm_shutdown", "");
            }
            try self.builder.emitReturn("0");
            return;
        }

        // Special: exit block for a function/sub.
        if (block.kind == .exit_block and !is_main) {
            if (func_ctx) |fctx| {
                if (fctx.is_function) {
                    // Load the accumulated return value and return it.
                    if (fctx.return_addr) |ret_addr| {
                        const ret_val = try self.builder.newTemp();
                        try self.builder.emitLoad(ret_val, fctx.return_type, ret_addr);
                        try self.builder.emitReturn(ret_val);
                        return;
                    }
                }
            }
            try self.builder.emitReturn("");
            return;
        }

        // Emit terminator based on CFG edges.
        try be.emitTerminator(block);
    }

    // ── Preamble / Data Emission ────────────────────────────────────────

    fn emitFileHeader(self: *CFGCodeGenerator) !void {
        try self.builder.emitComment("═══════════════════════════════════════════════════════════════");
        try self.builder.emitComment(" FasterBASIC - Generated QBE IL");
        try self.builder.emitComment(" Generated by the Zig compiler (fbc) — CFG-driven codegen");
        try self.builder.emitComment("═══════════════════════════════════════════════════════════════");
        try self.builder.emitBlankLine();
    }

    // ── CLASS System: VTables, Class Name Strings, Method/Ctor/Dtor Bodies ──

    fn emitClassDeclarations(self: *CFGCodeGenerator, program: *const ast.Program) !void {
        const st = self.semantic.getSymbolTable();
        if (st.classes.count() == 0) return;

        try self.builder.emitBlankLine();
        try self.builder.emitComment("=== CLASS System: VTables & Methods ===");
        try self.builder.emitBlankLine();

        // Phase 1: Emit class name string constants
        var cls_it = st.classes.iterator();
        while (cls_it.next()) |entry| {
            const cls = entry.value_ptr;
            const label = try self.symbol_mapper.classNameStringLabel(cls.name);
            try self.builder.emit("data ${s} = {{ b \"{s}\", b 0 }}\n", .{ label, cls.name });
        }

        try self.builder.emitBlankLine();

        // Phase 2: Emit vtable data sections
        var cls_it2 = st.classes.iterator();
        while (cls_it2.next()) |entry| {
            const cls = entry.value_ptr;
            try self.emitClassVtable(cls);
        }

        try self.builder.emitBlankLine();

        // Phase 3: Emit method/constructor/destructor function bodies
        // Find ClassStatement AST nodes from the program
        for (program.lines) |line| {
            for (line.statements) |stmt_ptr| {
                if (stmt_ptr.data == .class) {
                    const class_stmt = &stmt_ptr.data.class;
                    // Look up class symbol
                    var cu_buf: [128]u8 = undefined;
                    const cu_len = @min(class_stmt.class_name.len, cu_buf.len);
                    for (0..cu_len) |i| cu_buf[i] = std.ascii.toUpper(class_stmt.class_name[i]);
                    const cu_name = cu_buf[0..cu_len];

                    if (st.classes.getPtr(cu_name)) |cls| {
                        // Emit constructor
                        if (class_stmt.constructor) |ctor| {
                            if (cls.has_constructor) {
                                try self.emitClassConstructor(class_stmt, ctor, cls);
                            }
                        }

                        // Emit destructor
                        if (class_stmt.destructor) |dtor| {
                            if (cls.has_destructor) {
                                try self.emitClassDestructor(class_stmt, dtor, cls);
                            }
                        }

                        // Emit methods
                        for (class_stmt.methods) |method| {
                            try self.emitClassMethod(class_stmt, method, cls);
                        }
                    }
                }
            }
        }
    }

    fn emitClassVtable(self: *CFGCodeGenerator, cls: *const semantic.ClassSymbol) !void {
        // VTable layout:
        //   [0]  class_id           (l, int64)
        //   [8]  parent_vtable ptr  (l, 0 if root)
        //   [16] class_name ptr     (l, ptr to $classname_X)
        //   [24] destructor ptr     (l, 0 if none)
        //   [32+] method pointers   (l each, in vtable slot order)
        const vtable_label = try self.symbol_mapper.vtableName(cls.name);
        const classname_label = try self.symbol_mapper.classNameStringLabel(cls.name);

        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "VTable for {s} (class_id={d}, {d} methods)", .{ cls.name, cls.class_id, cls.methods.len }));

        try self.builder.emit("data ${s} = {{\n", .{vtable_label});

        // [0] class_id
        try self.builder.emit("    l {d},\n", .{cls.class_id});

        // [8] parent_vtable pointer
        if (cls.parent_class) |parent| {
            const parent_vtable = try self.symbol_mapper.vtableName(parent.name);
            try self.builder.emit("    l ${s},\n", .{parent_vtable});
        } else {
            try self.builder.raw("    l 0,\n");
        }

        // [16] class_name pointer
        try self.builder.emit("    l ${s},\n", .{classname_label});

        // [24] destructor pointer
        if (cls.has_destructor and cls.destructor_mangled_name.len > 0) {
            try self.builder.emit("    l ${s}", .{cls.destructor_mangled_name});
        } else {
            try self.builder.raw("    l 0");
        }

        // [32+] method pointers
        for (cls.methods) |method| {
            try self.builder.raw(",\n");
            try self.builder.emit("    l ${s}", .{method.mangled_name});
        }

        try self.builder.raw("\n}\n");
    }

    fn emitClassConstructor(self: *CFGCodeGenerator, _: *const ast.ClassStmt, ctor: *const ast.ConstructorStmt, cls: *const semantic.ClassSymbol) !void {
        try self.builder.emitBlankLine();
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "CONSTRUCTOR {s}", .{cls.name}));

        // Build parameter list: first param is always l %me
        var params_buf: std.ArrayList(u8) = .empty;
        defer params_buf.deinit(self.allocator);
        try params_buf.appendSlice(self.allocator, "l %me");

        for (ctor.parameters, 0..) |param, i| {
            try params_buf.appendSlice(self.allocator, ", ");
            const pt = if (i < cls.constructor_param_types.len)
                cls.constructor_param_types[i].toQBEType()
            else
                "l";
            const param_stripped = SymbolMapper.stripSuffix(param);
            try std.fmt.format(params_buf.writer(self.allocator), "{s} %param_{s}", .{ pt, param_stripped });
        }

        try self.builder.emitFunctionStart(cls.constructor_mangled_name, "", params_buf.items);
        try self.builder.emitLabel("start");

        // SAMM: Enter CONSTRUCTOR scope
        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Enter CONSTRUCTOR scope");
            try self.builder.emitCall("", "", "samm_enter_scope", "");
        }

        // Create a FunctionContext so that parameter variables resolve
        // to their stack slots (matching C++ registerMethodParam pattern).
        const ctor_upper = try std.fmt.allocPrint(self.allocator, "{s}__CONSTRUCTOR", .{cls.name});
        var func_ctx = FunctionContext.init(
            self.allocator,
            ctor_upper,
            ctor_upper,
            false, // constructor is void
            "",
            .void,
        );
        defer func_ctx.deinit();

        // Allocate local variables for parameters and register them
        for (ctor.parameters, 0..) |param, i| {
            const p_bt = if (i < cls.constructor_param_types.len)
                cls.constructor_param_types[i].base_type
            else
                .long;
            const pt = if (i < cls.constructor_param_types.len)
                cls.constructor_param_types[i].toQBEType()
            else
                "l";
            const p_suffix: ?Tag = switch (p_bt) {
                .integer => @as(?Tag, .type_int),
                .single => @as(?Tag, .type_float),
                .double => @as(?Tag, .type_double),
                .string => @as(?Tag, .type_string),
                .long => @as(?Tag, .ampersand),
                .byte => @as(?Tag, .type_byte),
                .short => @as(?Tag, .type_short),
                else => @as(?Tag, null),
            };
            const param_stripped = SymbolMapper.stripSuffix(param);
            const var_name = try std.fmt.allocPrint(self.allocator, "%var_{s}", .{param_stripped});
            const size_str: []const u8 = if (std.mem.eql(u8, pt, "w") or std.mem.eql(u8, pt, "s")) "4" else "8";
            try self.builder.emit("    {s} =l alloc8 {s}\n", .{ var_name, size_str });
            const store_op: []const u8 = if (std.mem.eql(u8, pt, "w")) "storew" else if (std.mem.eql(u8, pt, "s")) "stores" else if (std.mem.eql(u8, pt, "d")) "stored" else "storel";
            try self.builder.emit("    {s} %param_{s}, {s}\n", .{ store_op, param_stripped, var_name });

            // Register in function context so resolveVarAddr finds it
            var pu_buf: [128]u8 = undefined;
            const pu_len = @min(param_stripped.len, pu_buf.len);
            for (0..pu_len) |j| pu_buf[j] = std.ascii.toUpper(param_stripped[j]);
            const param_key = try self.allocator.dupe(u8, pu_buf[0..pu_len]);
            try func_ctx.param_addrs.put(param_key, .{
                .addr = var_name,
                .qbe_type = pt,
                .base_type = p_bt,
                .suffix = p_suffix,
            });
        }

        // Set function context on emitters
        self.block_emitter.?.setFunctionContext(&func_ctx);
        defer self.block_emitter.?.setFunctionContext(null);

        // Handle SUPER() call
        if (ctor.has_super_call) {
            if (cls.parent_class) |parent| {
                if (parent.has_constructor) {
                    try self.builder.emitComment("SUPER() call to parent constructor");
                    var super_args: std.ArrayList(u8) = .empty;
                    defer super_args.deinit(self.allocator);
                    try super_args.appendSlice(self.allocator, "l %me");
                    for (ctor.super_args, 0..) |sarg, si| {
                        try super_args.appendSlice(self.allocator, ", ");
                        const arg_val = try self.expr_emitter.?.emitExpression(sarg);
                        const arg_type = if (si < parent.constructor_param_types.len)
                            parent.constructor_param_types[si].toQBEType()
                        else
                            "l";
                        try std.fmt.format(super_args.writer(self.allocator), "{s} {s}", .{ arg_type, arg_val });
                    }
                    try self.builder.emitCall("", "", parent.constructor_mangled_name, super_args.items);
                }
            }
        } else if (cls.parent_class) |parent| {
            // Implicit SUPER() for zero-arg parent constructors
            if (parent.has_constructor and parent.constructor_param_types.len == 0) {
                try self.builder.emitComment("Implicit SUPER() call to parent zero-arg constructor");
                try self.builder.emitCall("", "", parent.constructor_mangled_name, "l %me");
            }
        }

        // Set class context for ME resolution
        self.expr_emitter.?.class_ctx = cls;
        defer {
            self.expr_emitter.?.class_ctx = null;
        }
        self.block_emitter.?.class_ctx = cls;
        defer {
            self.block_emitter.?.class_ctx = null;
        }

        // Emit constructor body statements
        for (ctor.body) |stmt| {
            try self.emitClassBodyStatement(stmt, cls);
        }

        // SAMM: Exit CONSTRUCTOR scope
        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Exit CONSTRUCTOR scope");
            try self.builder.emitCall("", "", "samm_exit_scope", "");
        }

        try self.builder.emitReturn("");
        try self.builder.emitFunctionEnd();
    }

    fn emitClassDestructor(self: *CFGCodeGenerator, class_stmt: *const ast.ClassStmt, dtor: *const ast.DestructorStmt, cls: *const semantic.ClassSymbol) !void {
        _ = class_stmt;
        try self.builder.emitBlankLine();
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DESTRUCTOR {s}", .{cls.name}));

        try self.builder.emitFunctionStart(cls.destructor_mangled_name, "", "l %me");
        try self.builder.emitLabel("start");

        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Enter DESTRUCTOR scope");
            try self.builder.emitCall("", "", "samm_enter_scope", "");
        }

        // Create a minimal FunctionContext for destructor body
        const dtor_upper = try std.fmt.allocPrint(self.allocator, "{s}__DESTRUCTOR", .{cls.name});
        var func_ctx = FunctionContext.init(self.allocator, dtor_upper, dtor_upper, false, "", .void);
        defer func_ctx.deinit();
        self.block_emitter.?.setFunctionContext(&func_ctx);
        defer self.block_emitter.?.setFunctionContext(null);

        self.expr_emitter.?.class_ctx = cls;
        defer {
            self.expr_emitter.?.class_ctx = null;
        }
        self.block_emitter.?.class_ctx = cls;
        defer {
            self.block_emitter.?.class_ctx = null;
        }
        for (dtor.body) |stmt| {
            try self.emitClassBodyStatement(stmt, cls);
        }

        // Chain to parent destructor
        if (cls.parent_class) |parent| {
            if (parent.has_destructor) {
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "Chain to parent destructor: {s}", .{parent.name}));
                try self.builder.emitCall("", "", parent.destructor_mangled_name, "l %me");
            }
        }

        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Exit DESTRUCTOR scope");
            try self.builder.emitCall("", "", "samm_exit_scope", "");
        }

        try self.builder.emitReturn("");
        try self.builder.emitFunctionEnd();
    }

    fn emitClassMethod(self: *CFGCodeGenerator, class_stmt: *const ast.ClassStmt, method: *const ast.MethodStmt, cls: *const semantic.ClassSymbol) !void {
        _ = class_stmt;

        // Find the method info from the ClassSymbol
        const method_info = cls.findMethod(method.method_name) orelse {
            try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "ERROR: method '{s}' not found in ClassSymbol '{s}'", .{ method.method_name, cls.name }));
            return;
        };

        try self.builder.emitBlankLine();
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "METHOD {s}.{s}", .{ cls.name, method.method_name }));

        // Determine return type
        const ret_type = if (method_info.return_type.base_type != .void)
            method_info.return_type.toQBEType()
        else
            "";

        const is_func = method_info.return_type.base_type != .void;

        // Build parameter list: first param is always l %me
        var params_buf: std.ArrayList(u8) = .empty;
        defer params_buf.deinit(self.allocator);
        try params_buf.appendSlice(self.allocator, "l %me");

        for (method.parameters, 0..) |param, i| {
            try params_buf.appendSlice(self.allocator, ", ");
            const pt = if (i < method_info.parameter_types.len)
                method_info.parameter_types[i].toQBEType()
            else
                "l";
            const param_stripped = SymbolMapper.stripSuffix(param);
            try std.fmt.format(params_buf.writer(self.allocator), "{s} %param_{s}", .{ pt, param_stripped });
        }

        try self.builder.emitFunctionStart(method_info.mangled_name, ret_type, params_buf.items);
        try self.builder.emitLabel("start");

        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Enter METHOD scope");
            try self.builder.emitCall("", "", "samm_enter_scope", "");
        }

        // Create a FunctionContext so that parameter variables and the
        // return-via-assignment slot resolve correctly (matching the C++
        // registerMethodParam / setMethodReturnSlot pattern).
        var mu_buf: [128]u8 = undefined;
        const mu_len = @min(method.method_name.len, mu_buf.len);
        for (0..mu_len) |mi| mu_buf[mi] = std.ascii.toUpper(method.method_name[mi]);
        const method_upper = try self.allocator.dupe(u8, mu_buf[0..mu_len]);
        var func_ctx = FunctionContext.init(
            self.allocator,
            method.method_name,
            method_upper,
            is_func,
            ret_type,
            method_info.return_type.base_type,
        );
        defer func_ctx.deinit();

        // Allocate local variables for parameters and register them
        for (method.parameters, 0..) |param, i| {
            const p_bt = if (i < method_info.parameter_types.len)
                method_info.parameter_types[i].base_type
            else
                .long;
            const pt = if (i < method_info.parameter_types.len)
                method_info.parameter_types[i].toQBEType()
            else
                "l";
            const p_suffix: ?Tag = switch (p_bt) {
                .integer => @as(?Tag, .type_int),
                .single => @as(?Tag, .type_float),
                .double => @as(?Tag, .type_double),
                .string => @as(?Tag, .type_string),
                .long => @as(?Tag, .ampersand),
                .byte => @as(?Tag, .type_byte),
                .short => @as(?Tag, .type_short),
                else => @as(?Tag, null),
            };
            const param_stripped = SymbolMapper.stripSuffix(param);
            const var_name = try std.fmt.allocPrint(self.allocator, "%var_{s}", .{param_stripped});
            const size_str: []const u8 = if (std.mem.eql(u8, pt, "w") or std.mem.eql(u8, pt, "s")) "4" else "8";
            try self.builder.emit("    {s} =l alloc8 {s}\n", .{ var_name, size_str });
            const store_op: []const u8 = if (std.mem.eql(u8, pt, "w")) "storew" else if (std.mem.eql(u8, pt, "s")) "stores" else if (std.mem.eql(u8, pt, "d")) "stored" else "storel";
            try self.builder.emit("    {s} %param_{s}, {s}\n", .{ store_op, param_stripped, var_name });

            // Register in function context
            var pu_buf: [128]u8 = undefined;
            const pu_len = @min(param_stripped.len, pu_buf.len);
            for (0..pu_len) |j| pu_buf[j] = std.ascii.toUpper(param_stripped[j]);
            const param_key = try self.allocator.dupe(u8, pu_buf[0..pu_len]);
            try func_ctx.param_addrs.put(param_key, .{
                .addr = var_name,
                .qbe_type = pt,
                .base_type = p_bt,
                .suffix = p_suffix,
            });
        }

        // Allocate return-value slot for non-void methods
        var method_ret_slot: []const u8 = "";
        if (method_info.return_type.base_type != .void) {
            method_ret_slot = "%method_ret";
            const ret_slot_size: []const u8 = if (std.mem.eql(u8, ret_type, "w") or std.mem.eql(u8, ret_type, "s")) "4" else "8";
            try self.builder.emitComment("Allocate return-value slot for return-via-assignment");
            try self.builder.emit("    {s} =l alloc8 {s}\n", .{ method_ret_slot, ret_slot_size });
            // Zero-initialize
            if (std.mem.eql(u8, ret_slot_size, "4")) {
                try self.builder.emit("    storew 0, {s}\n", .{method_ret_slot});
            } else {
                try self.builder.emit("    storel 0, {s}\n", .{method_ret_slot});
            }
            func_ctx.return_addr = method_ret_slot;

            // Also register under the method name so `MethodName = expr`
            // resolves to the return slot (matching C++ setMethodReturnSlot).
            try func_ctx.param_addrs.put(method_upper, .{
                .addr = method_ret_slot,
                .qbe_type = ret_type,
                .base_type = method_info.return_type.base_type,
                .suffix = null,
            });
        }

        // Set function context on emitters
        self.block_emitter.?.setFunctionContext(&func_ctx);
        defer self.block_emitter.?.setFunctionContext(null);

        // Set class context for ME resolution
        self.expr_emitter.?.class_ctx = cls;
        self.expr_emitter.?.method_ret_slot = method_ret_slot;
        self.expr_emitter.?.method_name = method.method_name;
        defer {
            self.expr_emitter.?.class_ctx = null;
            self.expr_emitter.?.method_ret_slot = "";
            self.expr_emitter.?.method_name = "";
        }
        self.block_emitter.?.class_ctx = cls;
        self.block_emitter.?.method_ret_slot = method_ret_slot;
        self.block_emitter.?.method_name = method.method_name;
        self.block_emitter.?.method_ret_type = method_info.return_type;
        defer {
            self.block_emitter.?.class_ctx = null;
            self.block_emitter.?.method_ret_slot = "";
            self.block_emitter.?.method_name = "";
            self.block_emitter.?.method_ret_type = semantic.TypeDescriptor.fromBase(.void);
        }

        // Emit method body statements
        for (method.body) |stmt| {
            try self.emitClassBodyStatement(stmt, cls);
        }

        // Emit fallback return
        const fallback_id = self.builder.nextLabelId();
        try self.builder.emitLabel(try std.fmt.allocPrint(self.allocator, "method_fallback_{d}", .{fallback_id}));

        if (self.samm_enabled) {
            try self.builder.emitComment("SAMM: Exit METHOD scope (fallback path)");
            try self.builder.emitCall("", "", "samm_exit_scope", "");
        }

        if (method_info.return_type.base_type == .void) {
            try self.builder.emitReturn("");
        } else {
            // Load the return value from the return-via-assignment slot
            const ret_val = try self.builder.newTemp();
            const load_op: []const u8 = if (std.mem.eql(u8, ret_type, "w"))
                "loadw"
            else if (std.mem.eql(u8, ret_type, "s"))
                "loads"
            else if (std.mem.eql(u8, ret_type, "d"))
                "loadd"
            else
                "loadl";
            try self.builder.emit("    {s} ={s} {s} {s}\n", .{ ret_val, ret_type, load_op, method_ret_slot });
            try self.builder.emitReturn(ret_val);
        }

        try self.builder.emitFunctionEnd();
    }

    /// Emit a single statement inside a CLASS method/constructor/destructor body.
    /// This handles the basic statements that appear inside class bodies.
    fn emitClassBodyStatement(self: *CFGCodeGenerator, stmt: *const ast.Statement, cls: *const semantic.ClassSymbol) !void {
        _ = cls;
        switch (stmt.data) {
            .print => |pr| try self.block_emitter.?.emitPrintStatement(&pr),
            .let => |lt| try self.block_emitter.?.emitLetStatement(&lt),
            .call => |cs| try self.block_emitter.?.emitCallStatement(&cs),
            .dim => |dim| try self.block_emitter.?.emitDimStatement(&dim),
            .return_stmt => |rs| {
                // Handle RETURN inside a method
                if (self.block_emitter.?.method_ret_slot.len > 0) {
                    // RETURN expr — store in ret slot and return
                    if (rs.return_value) |rv| {
                        const val = try self.expr_emitter.?.emitExpression(rv);
                        const ret_type = self.block_emitter.?.method_ret_type;
                        if (ret_type.base_type != .void) {
                            const store_op = ret_type.base_type.toQBEMemOp();
                            // Convert the return value to match the declared
                            // return type (e.g. integer 0 → double 0.0).
                            const expr_et = self.expr_emitter.?.inferExprType(rv);
                            const effective_val = if (std.mem.eql(u8, store_op, "d") and expr_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "d", "swtof", val);
                                break :blk cvt;
                            } else if (std.mem.eql(u8, store_op, "w") and expr_et == .double) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitConvert(cvt, "w", "dtosi", val);
                                break :blk cvt;
                            } else if (std.mem.eql(u8, store_op, "l") and expr_et == .integer) blk: {
                                const cvt = try self.builder.newTemp();
                                try self.builder.emitExtend(cvt, "l", "extsw", val);
                                break :blk cvt;
                            } else val;
                            try self.builder.emitStore(store_op, effective_val, self.block_emitter.?.method_ret_slot);
                        }
                    }
                    if (self.samm_enabled) {
                        try self.builder.emitCall("", "", "samm_exit_scope", "");
                    }
                    if (self.block_emitter.?.method_ret_slot.len > 0 and self.block_emitter.?.method_ret_type.base_type != .void) {
                        const ret_type_str = self.block_emitter.?.method_ret_type.toQBEType();
                        const ret_val = try self.builder.newTemp();
                        const load_op: []const u8 = if (std.mem.eql(u8, ret_type_str, "w"))
                            "loadw"
                        else if (std.mem.eql(u8, ret_type_str, "s"))
                            "loads"
                        else if (std.mem.eql(u8, ret_type_str, "d"))
                            "loadd"
                        else
                            "loadl";
                        try self.builder.emit("    {s} ={s} {s} {s}\n", .{ ret_val, ret_type_str, load_op, self.block_emitter.?.method_ret_slot });
                        try self.builder.emitReturn(ret_val);
                    } else {
                        try self.builder.emitReturn("");
                    }
                } else {
                    // Inside constructor/destructor — just return void
                    if (self.samm_enabled) {
                        try self.builder.emitCall("", "", "samm_exit_scope", "");
                    }
                    try self.builder.emitReturn("");
                }
                // Emit a fresh label so QBE doesn't complain about unreachable code
                const lbl_id = self.builder.nextLabelId();
                try self.builder.emitLabel(try std.fmt.allocPrint(self.allocator, "after_ret_{d}", .{lbl_id}));
            },
            .if_stmt => |ifs| {
                // Simple if/then/else inside class body
                const cond_val = try self.expr_emitter.?.emitExpression(ifs.condition);
                const then_lbl = self.builder.nextLabelId();
                const else_lbl = self.builder.nextLabelId();
                const end_lbl = self.builder.nextLabelId();

                // Convert to int if double
                const cond_type = self.expr_emitter.?.inferExprType(ifs.condition);
                const cond_int = if (cond_type == .double) blk: {
                    const t = try self.builder.newTemp();
                    try self.builder.emitConvert(t, "w", "dtosi", cond_val);
                    break :blk t;
                } else cond_val;

                try self.builder.emitBranch(cond_int, try std.fmt.allocPrint(self.allocator, "then_{d}", .{then_lbl}), try std.fmt.allocPrint(self.allocator, "else_{d}", .{else_lbl}));
                try self.builder.emitLabel(try std.fmt.allocPrint(self.allocator, "then_{d}", .{then_lbl}));
                for (ifs.then_statements) |s| {
                    try self.emitClassBodyStatement(s, self.expr_emitter.?.class_ctx.?);
                }
                try self.builder.emitJump(try std.fmt.allocPrint(self.allocator, "endif_{d}", .{end_lbl}));
                try self.builder.emitLabel(try std.fmt.allocPrint(self.allocator, "else_{d}", .{else_lbl}));
                for (ifs.else_statements) |s| {
                    try self.emitClassBodyStatement(s, self.expr_emitter.?.class_ctx.?);
                }
                try self.builder.emitJump(try std.fmt.allocPrint(self.allocator, "endif_{d}", .{end_lbl}));
                try self.builder.emitLabel(try std.fmt.allocPrint(self.allocator, "endif_{d}", .{end_lbl}));
            },
            .rem => {},
            .console => |con| try self.block_emitter.?.emitConsoleStatement(&con),
            else => {
                try self.builder.emitComment("TODO: unhandled statement in class body");
            },
        }
    }

    fn emitGlobalVariables(self: *CFGCodeGenerator) !void {
        const st = self.semantic.getSymbolTable();
        var it = st.variables.iterator();

        try self.builder.emitComment("=== Global Variables ===");

        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            if (sym.is_global) {
                // Use the variable's type suffix from its name for mangling.
                // First try to derive suffix from the last character of the name
                // (e.g. x% → _int, name$ → _str).
                var suffix: ?Tag = if (sym.name.len > 0) blk: {
                    const last = sym.name[sym.name.len - 1];
                    break :blk switch (last) {
                        '%' => @as(?Tag, .type_int),
                        '!' => @as(?Tag, .type_float),
                        '#' => @as(?Tag, .type_double),
                        '$' => @as(?Tag, .type_string),
                        '&' => @as(?Tag, .ampersand),
                        else => @as(?Tag, null),
                    };
                } else null;

                // When the name has no suffix character (e.g. DIM x AS INTEGER),
                // derive the suffix from base_type so that the global data
                // label matches what resolveVarAddr produces at load/store sites.
                if (suffix == null) {
                    suffix = switch (sym.type_desc.base_type) {
                        .integer => @as(?Tag, .type_int),
                        .single => @as(?Tag, .type_float),
                        .double => @as(?Tag, .type_double),
                        .string => @as(?Tag, .type_string),
                        .long => @as(?Tag, .ampersand),
                        .byte => @as(?Tag, .type_byte),
                        .short => @as(?Tag, .type_short),
                        else => @as(?Tag, null),
                    };
                }

                const var_name = try self.symbol_mapper.globalVarName(sym.name, suffix);
                const size = self.type_manager.sizeOf(sym.type_desc.base_type);
                const actual_size: u32 = if (size == 0) 8 else size;

                try self.builder.emitGlobalData(var_name, "z", try std.fmt.allocPrint(self.allocator, "{d}", .{actual_size}));
            }
        }

        try self.builder.emitBlankLine();
    }

    fn emitGlobalArrays(self: *CFGCodeGenerator) !void {
        const st = self.semantic.getSymbolTable();
        var it = st.arrays.iterator();

        if (st.arrays.count() > 0) {
            try self.builder.emitComment("=== Global Arrays ===");
        }

        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            const desc_name = try self.symbol_mapper.arrayDescName(sym.name);
            // ArrayDescriptor is 64 bytes (see array_descriptor.h)
            try self.builder.emitGlobalData(desc_name, "z", "64");
        }

        if (st.arrays.count() > 0) {
            try self.builder.emitBlankLine();
        }
    }

    fn collectStringLiterals(self: *CFGCodeGenerator, program: *const ast.Program) !void {
        for (program.lines) |line| {
            for (line.statements) |stmt| {
                try self.collectStringsFromStatement(stmt);
            }
        }
    }

    fn collectStringsFromStatement(self: *CFGCodeGenerator, stmt: *const ast.Statement) !void {
        switch (stmt.data) {
            .print => |pr| {
                for (pr.items) |item| {
                    try self.collectStringsFromExpression(item.expr);
                }
            },
            .console => |con| {
                for (con.items) |item| {
                    try self.collectStringsFromExpression(item.expr);
                }
            },
            .let => |lt| {
                try self.collectStringsFromExpression(lt.value);
            },
            .if_stmt => |ifs| {
                try self.collectStringsFromExpression(ifs.condition);
                for (ifs.then_statements) |s| try self.collectStringsFromStatement(s);
                for (ifs.else_statements) |s| try self.collectStringsFromStatement(s);
                for (ifs.elseif_clauses) |clause| {
                    try self.collectStringsFromExpression(clause.condition);
                    for (clause.statements) |s| try self.collectStringsFromStatement(s);
                }
            },
            .for_stmt => |fs| {
                try self.collectStringsFromExpression(fs.start);
                try self.collectStringsFromExpression(fs.end_expr);
                if (fs.step) |step| try self.collectStringsFromExpression(step);
                for (fs.body) |s| try self.collectStringsFromStatement(s);
            },
            .while_stmt => |ws| {
                try self.collectStringsFromExpression(ws.condition);
                for (ws.body) |s| try self.collectStringsFromStatement(s);
            },
            .do_stmt => |ds| {
                if (ds.pre_condition) |pc| try self.collectStringsFromExpression(pc);
                if (ds.post_condition) |pc| try self.collectStringsFromExpression(pc);
                for (ds.body) |s| try self.collectStringsFromStatement(s);
            },
            .repeat_stmt => |rs| {
                if (rs.condition) |cond| try self.collectStringsFromExpression(cond);
                for (rs.body) |s| try self.collectStringsFromStatement(s);
            },
            .case_stmt => |cs| {
                try self.collectStringsFromExpression(cs.case_expression);
                for (cs.when_clauses) |clause| {
                    for (clause.values) |val| try self.collectStringsFromExpression(val);
                    for (clause.statements) |s| try self.collectStringsFromStatement(s);
                }
                for (cs.otherwise_statements) |s| try self.collectStringsFromStatement(s);
            },
            .dim => |dim| {
                for (dim.arrays) |arr| {
                    if (arr.initializer) |init_expr| try self.collectStringsFromExpression(init_expr);
                }
            },
            .call => |cs| {
                for (cs.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .return_stmt => |rs| {
                if (rs.return_value) |rv| try self.collectStringsFromExpression(rv);
            },
            .function => |func| {
                for (func.body) |s| try self.collectStringsFromStatement(s);
            },
            .sub => |sub_def| {
                for (sub_def.body) |s| try self.collectStringsFromStatement(s);
            },
            .try_catch => |tc| {
                for (tc.try_block) |s| try self.collectStringsFromStatement(s);
                for (tc.catch_clauses) |clause| {
                    for (clause.block) |s| try self.collectStringsFromStatement(s);
                }
                for (tc.finally_block) |s| try self.collectStringsFromStatement(s);
            },
            else => {},
        }
    }

    fn collectStringsFromExpression(self: *CFGCodeGenerator, expr: *const ast.Expression) !void {
        switch (expr.data) {
            .string_lit => |s| {
                _ = try self.builder.registerString(s.value);
            },
            .binary => |b| {
                try self.collectStringsFromExpression(b.left);
                try self.collectStringsFromExpression(b.right);
            },
            .unary => |u| {
                try self.collectStringsFromExpression(u.operand);
            },
            .function_call => |fc| {
                for (fc.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .iif => |i| {
                try self.collectStringsFromExpression(i.condition);
                try self.collectStringsFromExpression(i.true_value);
                try self.collectStringsFromExpression(i.false_value);
            },
            .member_access => |ma| {
                try self.collectStringsFromExpression(ma.object);
            },
            .method_call => |mc| {
                try self.collectStringsFromExpression(mc.object);
                for (mc.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .array_access => |aa| {
                for (aa.indices) |idx| try self.collectStringsFromExpression(idx);
            },
            .create => |cr| {
                for (cr.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .new => |n| {
                for (n.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .is_type => |it| {
                try self.collectStringsFromExpression(it.object);
            },
            .super_call => |sc| {
                for (sc.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .list_constructor => |lc| {
                for (lc.elements) |elem| try self.collectStringsFromExpression(elem);
            },
            .array_binop => |ab| {
                try self.collectStringsFromExpression(ab.left_array);
                try self.collectStringsFromExpression(ab.right_expr);
            },
            .registry_function => |rf| {
                for (rf.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            else => {},
        }
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// Block Label Utility
// ═══════════════════════════════════════════════════════════════════════════

/// Derive a QBE label string for a basic block. Uses the block's name if
/// available, otherwise generates one from the block index.
fn blockLabel(the_cfg: *const cfg_mod.CFG, block_idx: u32, allocator: std.mem.Allocator) ![]const u8 {
    const block = the_cfg.getBlockConst(block_idx);
    if (block.name.len > 0) {
        return block.name;
    }
    return std.fmt.allocPrint(allocator, "block_{d}", .{block_idx});
}

// ═══════════════════════════════════════════════════════════════════════════
// Tests
// ═══════════════════════════════════════════════════════════════════════════

test "QBEBuilder basic emission" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitComment("test");
    try builder.emitBlankLine();
    try builder.emitGlobalData("var_x", "z", "8");

    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "# test") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "data $var_x") != null);
}

test "QBEBuilder temporaries" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const t0 = try builder.newTemp();
    const t1 = try builder.newTemp();
    const t2 = try builder.newTemp();

    try std.testing.expectEqualStrings("%t.0", t0);
    try std.testing.expectEqualStrings("%t.1", t1);
    try std.testing.expectEqualStrings("%t.2", t2);
    try std.testing.expectEqual(@as(u32, 3), builder.temp_counter);

    // Free the allocated strings
    std.testing.allocator.free(t0);
    std.testing.allocator.free(t1);
    std.testing.allocator.free(t2);
}

test "QBEBuilder label IDs" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const id0 = builder.nextLabelId();
    const id1 = builder.nextLabelId();

    try std.testing.expectEqual(@as(u32, 0), id0);
    try std.testing.expectEqual(@as(u32, 1), id1);
}

test "QBEBuilder string pool" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    const label1 = try builder.registerString("hello");
    const label2 = try builder.registerString("world");
    const label1_again = try builder.registerString("hello");

    try std.testing.expectEqualStrings(label1, label1_again);
    try std.testing.expect(!std.mem.eql(u8, label1, label2));
    try std.testing.expect(builder.hasString("hello"));
    try std.testing.expect(!builder.hasString("foobar"));
}

test "QBEBuilder function structure" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitFunctionStart("main", "w", "");
    try builder.emitLabel("start");
    try builder.emitReturn("0");
    try builder.emitFunctionEnd();

    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "export function") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "@start") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "ret 0") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "}") != null);
}

test "QBEBuilder arithmetic emission" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitBinary("%t.0", "d", "add", "%t.1", "%t.2");
    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "%t.0 =d add %t.1, %t.2") != null);
}

test "QBEBuilder store and load" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitStore("d", "%t.0", "$var_x");
    try builder.emitLoad("%t.1", "d", "$var_x");
    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "stored %t.0, $var_x") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "%t.1 =d loadd $var_x") != null);
}

test "QBEBuilder alloc" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitAlloc("%ptr", 16, 8);
    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "%ptr =l alloc8 16") != null);
}

test "QBEBuilder branch and jump" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitBranch("%cond", "if_true", "if_false");
    // A label starts a new block, clearing the terminated flag
    try builder.emitLabel("loop_body");
    try builder.emitJump("loop_start");
    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "jnz %cond, @if_true, @if_false") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "jmp @loop_start") != null);
}

test "QBEBuilder call" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitCall("%ret", "l", "basic_print_int", "l 42");
    try builder.emitCall("", "", "basic_print_newline", "");

    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "%ret =l call $basic_print_int(l 42)") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "call $basic_print_newline()") != null);
}

test "QBEBuilder escape string" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitStringConstant("str_0", "hello\nworld");
    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "hello\\nworld") != null);
}

test "TypeManager basic sizes" {
    var st = semantic.SymbolTable.init(std.testing.allocator);
    defer st.deinit();

    const tm = TypeManager.init(&st);
    try std.testing.expectEqual(@as(u32, 1), tm.sizeOf(.byte));
    try std.testing.expectEqual(@as(u32, 2), tm.sizeOf(.short));
    try std.testing.expectEqual(@as(u32, 4), tm.sizeOf(.integer));
    try std.testing.expectEqual(@as(u32, 8), tm.sizeOf(.long));
    try std.testing.expectEqual(@as(u32, 4), tm.sizeOf(.single));
    try std.testing.expectEqual(@as(u32, 8), tm.sizeOf(.double));
    try std.testing.expectEqual(@as(u32, 8), tm.sizeOf(.string));
}

test "TypeManager QBE types" {
    var st = semantic.SymbolTable.init(std.testing.allocator);
    defer st.deinit();

    const tm = TypeManager.init(&st);
    try std.testing.expectEqualStrings("w", tm.qbeType(.integer));
    try std.testing.expectEqualStrings("l", tm.qbeType(.long));
    try std.testing.expectEqualStrings("d", tm.qbeType(.double));
    try std.testing.expectEqualStrings("s", tm.qbeType(.single));
    try std.testing.expectEqualStrings("l", tm.qbeType(.string));
}

test "TypeManager alignment" {
    var st = semantic.SymbolTable.init(std.testing.allocator);
    defer st.deinit();

    const tm = TypeManager.init(&st);
    try std.testing.expectEqual(@as(u32, 4), tm.alignOf(.byte));
    try std.testing.expectEqual(@as(u32, 4), tm.alignOf(.integer));
    try std.testing.expectEqual(@as(u32, 8), tm.alignOf(.long));
    try std.testing.expectEqual(@as(u32, 8), tm.alignOf(.double));
}

test "SymbolMapper variable names" {
    var sm = SymbolMapper.init(std.testing.allocator);
    defer sm.deinit();

    const name1 = try sm.globalVarName("x", .type_int);
    defer std.testing.allocator.free(name1);
    try std.testing.expectEqualStrings("var_x_int", name1);

    const name2 = try sm.globalVarName("name$", .type_string);
    defer std.testing.allocator.free(name2);
    try std.testing.expectEqualStrings("var_name_str", name2);

    const name3 = try sm.globalVarName("y", null);
    defer std.testing.allocator.free(name3);
    try std.testing.expectEqualStrings("var_y", name3);
}

test "SymbolMapper function names" {
    var sm = SymbolMapper.init(std.testing.allocator);
    defer sm.deinit();

    const fname = try sm.functionName("myFunc");
    defer std.testing.allocator.free(fname);
    try std.testing.expectEqualStrings("func_MYFUNC", fname);

    const sname = try sm.subName("doThing");
    defer std.testing.allocator.free(sname);
    try std.testing.expectEqualStrings("sub_DOTHING", sname);
}

test "SymbolMapper class names" {
    var sm = SymbolMapper.init(std.testing.allocator);
    defer sm.deinit();

    const mname = try sm.classMethodName("Animal", "Speak");
    defer std.testing.allocator.free(mname);
    try std.testing.expectEqualStrings("Animal__Speak", mname);

    const cname = try sm.classConstructorName("Dog");
    defer std.testing.allocator.free(cname);
    try std.testing.expectEqualStrings("Dog__CONSTRUCTOR", cname);

    const vname = try sm.vtableName("Cat");
    defer std.testing.allocator.free(vname);
    try std.testing.expectEqualStrings("vtable_Cat", vname);
}

test "SymbolMapper shared variables" {
    var sm = SymbolMapper.init(std.testing.allocator);
    defer sm.deinit();

    try std.testing.expect(!sm.isShared("x"));
    try sm.registerShared("x");
    try std.testing.expect(sm.isShared("x"));
    sm.clearShared();
    try std.testing.expect(!sm.isShared("x"));
}

test "QBEBuilder reset clears state" {
    var builder = QBEBuilder.init(std.testing.allocator);
    defer builder.deinit();

    try builder.emitComment("something");
    const tmp = try builder.newTemp();
    defer std.testing.allocator.free(tmp);
    _ = builder.nextLabelId();

    try std.testing.expect(builder.getIL().len > 0);
    try std.testing.expectEqual(@as(u32, 1), builder.temp_counter);
    try std.testing.expectEqual(@as(u32, 1), builder.label_counter);

    builder.reset();

    try std.testing.expectEqual(@as(usize, 0), builder.getIL().len);
    try std.testing.expectEqual(@as(u32, 0), builder.temp_counter);
    try std.testing.expectEqual(@as(u32, 0), builder.label_counter);
}

test "blockLabel with named block" {
    var cfg_graph = cfg_mod.CFG.init(std.testing.allocator);
    defer cfg_graph.deinit();

    const idx = try cfg_graph.newNamedBlock(.entry, "entry");
    const label = try blockLabel(&cfg_graph, idx, std.testing.allocator);
    // Named blocks should return their name directly, which is not heap-allocated by blockLabel.
    try std.testing.expectEqualStrings("entry", label);
}

test "blockLabel with unnamed block" {
    var cfg_graph = cfg_mod.CFG.init(std.testing.allocator);
    defer cfg_graph.deinit();

    const idx = try cfg_graph.newBlock(.normal);
    const label = try blockLabel(&cfg_graph, idx, std.testing.allocator);
    defer std.testing.allocator.free(label);
    try std.testing.expectEqualStrings("block_0", label);
}
