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
    }

    // ── Arithmetic & Logic ──────────────────────────────────────────────

    /// Emit a binary arithmetic instruction.
    /// `dest`: e.g. "%t.0". `qbe_type`: "w","l","s","d". `op`: "add","sub", etc.
    pub fn emitBinary(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, op: []const u8, lhs: []const u8, rhs: []const u8) !void {
        try self.emit("    {s} ={s} {s} {s}, {s}\n", .{ dest, qbe_type, op, lhs, rhs });
    }

    /// Emit a comparison instruction.
    pub fn emitCompare(self: *QBEBuilder, dest: []const u8, qbe_type: []const u8, op: []const u8, lhs: []const u8, rhs: []const u8) !void {
        try self.emit("    {s} =w c{s}{s} {s}, {s}\n", .{ dest, op, qbe_type, lhs, rhs });
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

    /// Mangle an array descriptor name: arr → "arr_ARR_desc".
    pub fn arrayDescName(self: *const SymbolMapper, name: []const u8) ![]const u8 {
        var buf: [128]u8 = undefined;
        const upper = toUpperBuf(name, &buf);
        return std.fmt.allocPrint(self.allocator, "arr_{s}_desc", .{upper});
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

        // I/O
        try self.declare("print_int", "w %val");
        try self.declare("print_double", "d %val");
        try self.declare("print_string", "l %str");
        try self.declare("print_newline", "");
        try self.declare("print_tab", "");
        try self.declare("input_string", "l %prompt");
        try self.declare("input_number", "l %prompt");

        // String operations
        try self.declare("string_create", "l %data, w %len");
        try self.declare("string_concat", "l %a, l %b");
        try self.declare("string_compare", "l %a, l %b");
        try self.declare("string_length", "l %str");
        try self.declare("string_mid", "l %str, w %start, w %len");
        try self.declare("string_left", "l %str, w %len");
        try self.declare("string_right", "l %str, w %len");
        try self.declare("string_retain", "l %str");
        try self.declare("string_release", "l %str");
        try self.declare("string_from_int", "w %val");
        try self.declare("string_from_double", "d %val");
        try self.declare("string_slice", "l %str, w %start, w %end");

        // Math
        try self.declare("math_power", "d %base, d %exp");
        try self.declare("math_sqr", "d %val");
        try self.declare("math_abs_int", "w %val");
        try self.declare("math_abs_double", "d %val");

        // Memory
        try self.declare("basic_alloc", "l %size");
        try self.declare("basic_free", "l %ptr");

        // Array operations
        try self.declare("array_create", "w %ndims, l %desc, w %upper, w %elemsize");
        try self.declare("array_bounds_check", "l %desc, w %index");
        try self.declare("array_element_addr", "l %desc, w %index");
        try self.declare("array_erase", "l %desc");

        // SAMM (Scope-Aware Memory Management)
        try self.declare("samm_init", "");
        try self.declare("samm_shutdown", "");
        try self.declare("samm_enter_scope", "");
        try self.declare("samm_exit_scope", "");
        try self.declare("samm_register", "l %ptr, l %dtor");

        // Error handling
        try self.declare("basic_error", "w %code, l %msg");
        try self.declare("set_error_line", "w %line");

        // Object system
        try self.declare("object_alloc", "w %size, l %vtable");
        try self.declare("object_release", "l %obj");
        try self.declare("object_retain", "l %obj");

        // Conversion
        try self.declare("val_to_int", "l %str");
        try self.declare("val_to_double", "l %str");
        try self.declare("chr_func", "w %code");
        try self.declare("asc_func", "l %str");

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

    /// When non-null, we are inside a FUNCTION/SUB and should resolve
    /// variables against this context before falling back to globals.
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
                .double => "print_double",
                .integer => "print_int",
                .string => "print_string",
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
                // Otherwise consult the symbol table for the actual type
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
            .member_access => .double,
            .array_access => |aa| typeFromSuffix(aa.type_suffix),
            .iif => |i| self.inferExprType(i.true_value),
            .new, .create => .string,
            .method_call => .double,
            .me, .nothing, .super_call => .double,
            .is_type => .integer,
            .list_constructor => .double,
            .array_binop => .double,
            .registry_function => .double,
        };
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
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ dest, label });
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
                    return dest;
                }
            }

            if (fctx.resolve(upper_base)) |rv| {
                const dest = try self.builder.newTemp();
                try self.builder.emitLoad(dest, rv.qbe_type, rv.addr);
                return dest;
            }
        }

        // ── Fall back to global variable ────────────────────────────────
        const dest = try self.builder.newTemp();
        const var_name = try self.symbol_mapper.globalVarName(name, suffix);

        // When the suffix is null (unsuffixed variable), consult the symbol
        // table for the actual registered type instead of defaulting to
        // double.  This is important for FOR loop index variables which are
        // registered as integer.
        var bt = semantic.baseTypeFromSuffix(suffix);
        if (suffix == null) {
            var sym_upper_buf: [128]u8 = undefined;
            const sym_base = SymbolMapper.stripSuffix(name);
            const slen = @min(sym_base.len, sym_upper_buf.len);
            for (0..slen) |si| sym_upper_buf[si] = std.ascii.toUpper(sym_base[si]);
            const sym_upper = sym_upper_buf[0..slen];
            if (self.symbol_table.lookupVariable(sym_upper)) |vsym| {
                bt = vsym.type_desc.base_type;
            }
        }
        const qbe_t = bt.toQBEType();
        const load_t = bt.toQBEMemOp();

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

        // Choose the QBE type for arithmetic: if both sides are integer, use "w".
        const is_int_op = (left_type == .integer and right_type == .integer);
        const arith_type: []const u8 = if (is_int_op) "w" else "d";

        // If mixing types (one int, one double), promote the int to double.
        const eff_lhs = if (!is_int_op and left_type == .integer)
            try self.emitIntToDouble(lhs)
        else
            lhs;
        const eff_rhs = if (!is_int_op and right_type == .integer)
            try self.emitIntToDouble(rhs)
        else
            rhs;

        switch (op) {
            // Arithmetic
            .plus => try self.builder.emitBinary(dest, arith_type, "add", eff_lhs, eff_rhs),
            .minus => try self.builder.emitBinary(dest, arith_type, "sub", eff_lhs, eff_rhs),
            .multiply => try self.builder.emitBinary(dest, arith_type, "mul", eff_lhs, eff_rhs),
            .divide => {
                if (is_int_op) {
                    // Integer division: result stays integer
                    try self.builder.emitBinary(dest, "w", "div", eff_lhs, eff_rhs);
                } else {
                    try self.builder.emitBinary(dest, "d", "div", eff_lhs, eff_rhs);
                }
            },
            .kw_mod => {
                if (is_int_op) {
                    try self.builder.emitBinary(dest, "w", "rem", eff_lhs, eff_rhs);
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
                try self.builder.emitCall(dest, "d", "math_power", args);
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

    /// Convert a numeric value to a string via runtime call.
    fn emitNumericToString(self: *ExprEmitter, temp: []const u8, et: ExprType) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        switch (et) {
            .integer => {
                const args = try std.fmt.allocPrint(self.allocator, "w {s}", .{temp});
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

    fn emitFunctionCall(self: *ExprEmitter, name: []const u8, arguments: []const ast.ExprPtr, is_fn: bool) EmitError![]const u8 {
        _ = is_fn;

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        for (arguments, 0..) |arg, i| {
            if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.emitExpression(arg);
            const arg_type = self.inferExprType(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "{s} {s}", .{ arg_type.argLetter(), arg_val });
        }

        const dest = try self.builder.newTemp();
        const mangled = try self.symbol_mapper.functionName(name);
        // Determine return type: string functions (name ends with $) return l,
        // otherwise default to d (double). Look up in symbol table if possible.
        const ret_type: []const u8 = blk: {
            if (name.len > 0 and name[name.len - 1] == '$') break :blk "l";
            // Check symbol table for declared return type.
            // The semantic analyzer stores names in uppercase, so
            // uppercase the name before lookup.
            var fn_upper_buf: [128]u8 = undefined;
            const fn_base = SymbolMapper.stripSuffix(name);
            const fn_ulen = @min(fn_base.len, fn_upper_buf.len);
            for (0..fn_ulen) |ui| fn_upper_buf[ui] = std.ascii.toUpper(fn_base[ui]);
            const fn_upper = fn_upper_buf[0..fn_ulen];
            if (self.symbol_table.lookupFunction(fn_upper)) |fsym| {
                break :blk fsym.return_type_desc.toQBEType();
            }
            // Also try the original name (in case it's already uppercase)
            if (self.symbol_table.lookupFunction(name)) |fsym| {
                break :blk fsym.return_type_desc.toQBEType();
            }
            break :blk "d";
        };
        try self.builder.emitCall(dest, ret_type, mangled, args_buf.items);
        return dest;
    }

    fn emitIIF(self: *ExprEmitter, condition: *const ast.Expression, true_val: *const ast.Expression, false_val: *const ast.Expression) EmitError![]const u8 {
        // IIF is a self-contained inline conditional expression.
        // It creates its own micro-CFG within the block.
        const cond = try self.emitExpression(condition);
        const id = self.builder.nextLabelId();
        const true_label = try std.fmt.allocPrint(self.allocator, "iif_true_{d}", .{id});
        const false_label = try std.fmt.allocPrint(self.allocator, "iif_false_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "iif_done_{d}", .{id});

        const cond_int = try self.builder.newTemp();
        try self.builder.emitConvert(cond_int, "w", "dtosi", cond);

        try self.builder.emitBranch(cond_int, true_label, false_label);

        try self.builder.emitLabel(true_label);
        const tv = try self.emitExpression(true_val);
        try self.builder.emitJump(done_label);

        try self.builder.emitLabel(false_label);
        const fv = try self.emitExpression(false_val);
        try self.builder.emitJump(done_label);

        try self.builder.emitLabel(done_label);
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =d phi @{s} {s}, @{s} {s}\n", .{ dest, true_label, tv, false_label, fv });

        return dest;
    }

    fn emitMemberAccess(self: *ExprEmitter, object: *const ast.Expression, member_name: []const u8) EmitError![]const u8 {
        const obj_addr = try self.emitExpression(object);

        // Try to determine the UDT type from the object expression and
        // look up the field offset.
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
                        const dest = try self.builder.newTemp();
                        const load_type = field.type_desc.base_type.toQBEType();
                        try self.builder.emitLoad(dest, load_type, field_addr);
                        return dest;
                    }
                    offset += self.type_manager.sizeOf(field.type_desc.base_type);
                }
            }
        }

        // Fallback: unknown member, load as double from base address.
        try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "WARN: unresolved member .{s}", .{member_name}));
        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, "d", obj_addr);
        return dest;
    }

    /// Try to infer the UDT type name from an expression (for member access).
    fn inferUDTName(self: *ExprEmitter, expr: *const ast.Expression) ?[]const u8 {
        switch (expr.data) {
            .variable => |v| {
                // Look up in symbol table
                if (self.symbol_table.lookupVariable(v.name)) |vsym| {
                    if (vsym.type_desc.base_type == .user_defined) {
                        return vsym.type_desc.udt_name;
                    }
                }
            },
            .create => |cr| return cr.type_name,
            else => {},
        }
        return null;
    }

    fn emitMethodCall(self: *ExprEmitter, object: *const ast.Expression, method_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        const obj_val = try self.emitExpression(object);

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        try std.fmt.format(args_buf.writer(self.allocator), "l {s}", .{obj_val});

        for (arguments) |arg| {
            try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.emitExpression(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "d {s}", .{arg_val});
        }

        const dest = try self.builder.newTemp();
        _ = method_name;
        // TODO: vtable dispatch
        try self.builder.emitComment("TODO: method call via vtable");
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }

    fn emitArrayAccess(self: *ExprEmitter, name: []const u8, indices: []const ast.ExprPtr, suffix: ?Tag) EmitError![]const u8 {
        if (indices.len == 0) {
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
            return dest;
        }

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
        try self.builder.emitCall("", "", "array_bounds_check", bc_args);

        const elem_addr = try self.builder.newTemp();
        const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
        try self.builder.emitCall(elem_addr, "l", "array_element_addr", ea_args);

        // Determine element type from suffix
        const bt = semantic.baseTypeFromSuffix(suffix);
        const load_type = bt.toQBEType();

        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, load_type, elem_addr);
        return dest;
    }

    fn emitCreate(self: *ExprEmitter, type_name: []const u8, arguments: []const ast.ExprPtr, is_named: bool, field_names: []const []const u8) EmitError![]const u8 {
        _ = is_named;
        _ = field_names;
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

                if (i < arguments.len) {
                    const val = try self.emitExpression(arguments[i]);
                    const store_type = field.type_desc.base_type.toQBEMemOp();
                    try self.builder.emitStore(store_type, val, field_addr);
                } else {
                    const store_type = field.type_desc.base_type.toQBEMemOp();
                    try self.builder.emitStore(store_type, "0", field_addr);
                }

                offset += self.type_manager.sizeOf(field.type_desc.base_type);
            }
        } else {
            try self.builder.emitComment("WARNING: unknown type in CREATE, zero-filling");
        }

        return addr;
    }

    fn emitNew(self: *ExprEmitter, class_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = arguments;
        const vtable_label = try self.symbol_mapper.vtableName(class_name);
        const vtable_addr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ vtable_addr, vtable_label });

        const cls = self.symbol_table.lookupClass(class_name);
        const obj_size: i32 = if (cls) |c| c.object_size else semantic.ClassSymbol.header_size;

        const obj = try self.builder.newTemp();
        const args = try std.fmt.allocPrint(self.allocator, "w {d}, l {s}", .{ obj_size, vtable_addr });
        try self.builder.emitCall(obj, "l", "object_alloc", args);

        return obj;
    }

    fn emitMe(self: *ExprEmitter) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy %me\n", .{dest});
        return dest;
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
            _ = class_name;
            try self.builder.emitComment("TODO: IS type check");
            try self.builder.emit("    {s} =w copy 0\n", .{dest});
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
        _ = elements;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: list constructor");
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
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

/// Context saved when a SELECT CASE is emitted so that case_test blocks
/// can compare against the selector.
const CaseContext = struct {
    selector_temp: []const u8,
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

    /// When non-null, we are inside a FUNCTION/SUB.
    func_ctx: ?*const FunctionContext = null,

    /// FOR loop contexts, keyed by the loop header block index.
    for_contexts: std.AutoHashMap(u32, ForLoopContext),

    /// CASE selector contexts, keyed by the case entry block index.
    case_contexts: std.AutoHashMap(u32, CaseContext),

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
            .case_contexts = std.AutoHashMap(u32, CaseContext).init(allocator),
        };
    }

    pub fn deinit(self: *BlockEmitter) void {
        self.for_contexts.deinit();
        self.case_contexts.deinit();
    }

    /// Reset per-function state.
    pub fn resetContexts(self: *BlockEmitter) void {
        self.for_contexts.clearRetainingCapacity();
        self.case_contexts.clearRetainingCapacity();
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
        // When suffix is null, consult the symbol table for the actual
        // registered type (e.g. FOR loop variables are integer, not double).
        var bt = semantic.baseTypeFromSuffix(suffix);
        if (suffix == null) {
            var sym_upper_buf: [128]u8 = undefined;
            const sym_base = SymbolMapper.stripSuffix(name);
            const slen = @min(sym_base.len, sym_upper_buf.len);
            for (0..slen) |si| sym_upper_buf[si] = std.ascii.toUpper(sym_base[si]);
            const sym_upper = sym_upper_buf[0..slen];
            if (self.symbol_table.lookupVariable(sym_upper)) |vsym| {
                bt = vsym.type_desc.base_type;
            }
        }
        const var_name = try self.symbol_mapper.globalVarName(name, suffix);
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
                .end_stmt => {
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
                        return;
                    }
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

    /// Emit the FOR loop initialisation: set loop variable to start value,
    /// evaluate and store end value. Register the ForLoopContext so the
    /// header and increment blocks can use it.
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

        // 2. Evaluate end (limit) expression, convert to integer, store in temp slot.
        const end_raw = try self.expr_emitter.emitExpression(fs.end_expr);
        const end_type = self.expr_emitter.inferExprType(fs.end_expr);
        const end_val = if (end_type == .double) blk: {
            const t = try self.builder.newTemp();
            try self.builder.emitConvert(t, "w", "dtosi", end_raw);
            break :blk t;
        } else end_raw;
        const end_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(end_addr, 4, 4);
        try self.builder.emitStore("w", end_val, end_addr);

        // 3. Evaluate step expression (default 1), convert to integer, store in temp slot.
        const step_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(step_addr, 4, 4);
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
            try self.builder.emitComment("WARN: FOR increment context not found");
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
        const sel_val = try self.expr_emitter.emitExpression(cs.case_expression);
        try self.case_contexts.put(block.index, .{ .selector_temp = sel_val });
    }

    /// Emit the comparison for a case_test block. Compares the selector
    /// against the test value and branches accordingly.
    fn emitCaseTest(self: *BlockEmitter, block: *const cfg_mod.BasicBlock, match_target: u32, next_target: u32) EmitError!void {
        // Find the selector from the case entry block.
        // Walk predecessors back to find the case entry (or the previous case_test).
        var sel_temp: ?[]const u8 = null;

        // Search the case_contexts for any predecessor chain.
        // The selector was stored in the block that contained the case_stmt.
        var ctx_it = self.case_contexts.iterator();
        while (ctx_it.next()) |entry| {
            sel_temp = entry.value_ptr.selector_temp;
            break; // Use the first (and typically only) case context in scope
        }

        if (sel_temp == null) {
            try self.builder.emitComment("WARN: CASE selector not found");
            try self.builder.emitJump(try blockLabel(self.cfg, next_target, self.allocator));
            return;
        }

        if (block.branch_condition) |test_val_expr| {
            const test_val = try self.expr_emitter.emitExpression(test_val_expr);
            const cmp = try self.builder.newTemp();
            try self.builder.emitCompare(cmp, "d", "eq", sel_temp.?, test_val);
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

    // ── Leaf Statement Emitters ─────────────────────────────────────────

    fn emitPrintStatement(self: *BlockEmitter, pr: *const ast.PrintStmt) EmitError!void {
        for (pr.items) |item| {
            const val = try self.expr_emitter.emitExpression(item.expr);
            const et = self.expr_emitter.inferExprType(item.expr);
            const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.argLetter(), val });
            try self.runtime.callVoid(et.printFn(), args);

            if (item.comma) {
                try self.runtime.callVoid("print_tab", "");
            }
            if (item.semicolon) {
                // Semicolon: no space between items (already handled by not
                // emitting tab/newline). Nothing to do.
            }
        }

        if (pr.trailing_newline) {
            try self.runtime.callVoid("print_newline", "");
        }
    }

    fn emitConsoleStatement(self: *BlockEmitter, con: *const ast.ConsoleStmt) EmitError!void {
        for (con.items) |item| {
            const val = try self.expr_emitter.emitExpression(item.expr);
            const et = self.expr_emitter.inferExprType(item.expr);
            const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.argLetter(), val });
            try self.runtime.callVoid(et.printFn(), args);
        }
        if (con.trailing_newline) {
            try self.runtime.callVoid("print_newline", "");
        }
    }

    fn emitLetStatement(self: *BlockEmitter, lt: *const ast.LetStmt) EmitError!void {
        const val = try self.expr_emitter.emitExpression(lt.value);
        const bt = semantic.baseTypeFromSuffix(lt.type_suffix);
        const store_type = bt.toQBEMemOp();

        // ── Simple variable assignment ──────────────────────────────────
        if (lt.member_chain.len == 0 and lt.indices.len == 0) {
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

            // Convert value to target type if needed.
            const expr_type = self.expr_emitter.inferExprType(lt.value);
            const effective_val = try self.emitTypeConversion(val, expr_type, resolved.base_type);
            try self.builder.emitStore(resolved.store_type, effective_val, var_addr);
            return;
        }

        // ── Array element store: a%(i) = value ─────────────────────────
        if (lt.indices.len > 0) {
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
            try self.builder.emitCall("", "", "array_bounds_check", bc_args);

            // Get element address
            const elem_addr = try self.builder.newTemp();
            const ea_args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
            try self.builder.emitCall(elem_addr, "l", "array_element_addr", ea_args);

            // Convert value and store
            const expr_type = self.expr_emitter.inferExprType(lt.value);
            const effective_val = try self.emitTypeConversion(val, expr_type, bt);
            try self.builder.emitStore(store_type, effective_val, elem_addr);
            return;
        }

        // ── Member chain store: point.x = value ────────────────────────
        if (lt.member_chain.len > 0) {
            // Load the base object address.
            const var_name = try self.symbol_mapper.globalVarName(lt.variable, lt.type_suffix);
            const base_addr = try self.builder.newTemp();
            try self.builder.emitLoad(base_addr, "l", try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));

            // Walk the member chain to compute the final field address.
            var current_addr = base_addr;
            var current_type_name: ?[]const u8 = blk: {
                if (self.symbol_table.lookupVariable(lt.variable)) |vsym| {
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
                                    // Store the value at this field.
                                    const field_store_type = field.type_desc.base_type.toQBEMemOp();
                                    const expr_type = self.expr_emitter.inferExprType(lt.value);
                                    const effective_val = try self.emitTypeConversion(val, expr_type, field.type_desc.base_type);
                                    try self.builder.emitStore(field_store_type, effective_val, field_addr);
                                } else {
                                    // Intermediate: load pointer to nested UDT.
                                    const next_addr = try self.builder.newTemp();
                                    try self.builder.emitLoad(next_addr, "l", field_addr);
                                    current_addr = next_addr;
                                    current_type_name = field.type_desc.udt_name;
                                }
                                break;
                            }
                            offset += self.type_manager.sizeOf(field.type_desc.base_type);
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
        // Double → Integer
        if (from == .double and to_bt.isInteger()) {
            const dest = try self.builder.newTemp();
            try self.builder.emitConvert(dest, "w", "dtosi", val);
            return dest;
        }
        // Integer → Double
        if (from == .integer and to_bt.isFloat()) {
            const dest = try self.builder.newTemp();
            try self.builder.emitConvert(dest, "d", "swtof", val);
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
                const bt = if (arr.has_as_type)
                    semantic.baseTypeFromSuffix(if (arr.as_type_keyword) |kw| kw.asTypeToSuffix() else null)
                else
                    semantic.baseTypeFromSuffix(arr.type_suffix);
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
                try self.builder.emitCall("", "", "array_create", create_args);
            } else if (arr.initializer) |init_expr| {
                // ── Scalar DIM with initializer ─────────────────────────
                const val = try self.expr_emitter.emitExpression(init_expr);
                const var_name = try self.symbol_mapper.globalVarName(arr.name, arr.type_suffix);
                const bt = if (arr.has_as_type)
                    semantic.baseTypeFromSuffix(if (arr.as_type_keyword) |kw| kw.asTypeToSuffix() else null)
                else
                    semantic.baseTypeFromSuffix(arr.type_suffix);
                const store_type = bt.toQBEMemOp();
                const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});

                // Convert value to target type if needed.
                const expr_type = self.expr_emitter.inferExprType(init_expr);
                const effective_val = try self.emitTypeConversion(val, expr_type, bt);
                try self.builder.emitStore(store_type, effective_val, var_addr);
            } else {
                // ── Scalar DIM without initializer (declare only) ───────
                // The global data section already zero-initialized it.
                // If this is a DIM x AS type (non-array), just ensure the
                // global variable exists — emitGlobalVariables handles it.
            }
        }
    }

    fn emitCallStatement(self: *BlockEmitter, cs: *const ast.CallStmt) EmitError!void {
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
            const val = try self.expr_emitter.emitExpression(rv);
            try self.builder.emitReturn(val);
        } else {
            try self.builder.emitReturn("");
        }
    }

    fn emitIncDec(self: *BlockEmitter, id: *const ast.IncDecStmt, is_inc: bool) EmitError!void {
        const resolved = try self.resolveVarAddr(id.var_name, null);
        const var_addr = resolved.addr;

        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "d", var_addr);

        const amount = if (id.amount_expr) |ae|
            try self.expr_emitter.emitExpression(ae)
        else blk: {
            const one = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_1.0\n", .{one});
            break :blk one;
        };

        const result = try self.builder.newTemp();
        if (is_inc) {
            try self.builder.emitBinary(result, "d", "add", cur, amount);
        } else {
            try self.builder.emitBinary(result, "d", "sub", cur, amount);
        }
        try self.builder.emitStore("d", result, var_addr);
    }

    fn emitSwapStatement(self: *BlockEmitter, sw: *const ast.SwapStmt) EmitError!void {
        const resolved1 = try self.resolveVarAddr(sw.var1, null);
        const resolved2 = try self.resolveVarAddr(sw.var2, null);

        const tmp1 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp1, "d", resolved1.addr);
        const tmp2 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp2, "d", resolved2.addr);
        try self.builder.emitStore("d", tmp2, resolved1.addr);
        try self.builder.emitStore("d", tmp1, resolved2.addr);
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
            const bt = semantic.baseTypeFromSuffix(lv.type_suffix);
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
        }

        // Special: increment block for FOR loops.
        if (block.kind == .loop_increment) {
            try be.emitForIncrement(block);
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

    fn emitGlobalVariables(self: *CFGCodeGenerator) !void {
        const st = self.semantic.getSymbolTable();
        var it = st.variables.iterator();

        try self.builder.emitComment("=== Global Variables ===");

        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            if (sym.is_global) {
                // Use the variable's type suffix from its name for mangling.
                const suffix = if (sym.name.len > 0) blk: {
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

    try builder.emitCall("%ret", "w", "print_int", "w 42");
    try builder.emitCall("", "", "print_newline", "");

    const il = builder.getIL();
    try std.testing.expect(std.mem.indexOf(u8, il, "%ret =w call $print_int(w 42)") != null);
    try std.testing.expect(std.mem.indexOf(u8, il, "call $print_newline()") != null);
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
