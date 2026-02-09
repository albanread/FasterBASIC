//! Code Generation for the FasterBASIC compiler.
//!
//! This module generates QBE Intermediate Language (IL) from the AST and
//! semantic analysis results. It replaces the C++ codegen_v2 subsystem
//! with a clean Zig implementation.
//!
//! Architecture:
//! - `QBEBuilder`: Low-level IL text emission (instructions, labels, temps).
//! - `TypeManager`: Maps FasterBASIC types to QBE types.
//! - `SymbolMapper`: Generates mangled names for variables, functions, etc.
//! - `RuntimeLibrary`: Declarations and call helpers for the C runtime.
//! - `Emitter`: High-level AST→IL translation (expressions and statements).
//! - `CodeGenerator`: Top-level orchestrator that drives the full pipeline.
//!
//! Design differences from the C++ version:
//! - Single file with clear sections instead of 7 separate .h/.cpp pairs.
//! - Uses Zig's ArrayList(u8) as a write buffer instead of std::ostringstream.
//! - Temporary and label counters are simple integers, not class state.
//! - No virtual dispatch — direct function calls throughout.

const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");
const semantic = @import("semantic.zig");
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

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
        // QBE load syntax: %dest =type load[type] %addr
        // For w/l/s/d: loadw, loadl, loads, loadd
        // For ub/uh: loadub, loaduh
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

    fn stripSuffix(name: []const u8) []const u8 {
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

        // Math
        try self.declare("math_power", "d %base, d %exp");
        try self.declare("math_sqr", "d %val");
        try self.declare("math_abs_int", "w %val");
        try self.declare("math_abs_double", "d %val");

        // Memory
        try self.declare("basic_alloc", "l %size");
        try self.declare("basic_free", "l %ptr");

        // Array operations
        try self.declare("array_create", "w %ndims, l %dims, w %elemsize");
        try self.declare("array_bounds_check", "l %desc, w %index");
        try self.declare("array_element_addr", "l %desc, w %index");

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
// Emitter — AST to QBE IL translation
// ═══════════════════════════════════════════════════════════════════════════

/// Translates AST nodes (expressions and statements) to QBE IL instructions.
/// This is the heart of the code generator.
pub const Emitter = struct {
    builder: *QBEBuilder,
    type_manager: *const TypeManager,
    symbol_mapper: *SymbolMapper,
    runtime: *RuntimeLibrary,
    symbol_table: *const semantic.SymbolTable,
    allocator: std.mem.Allocator,

    /// Whether SAMM is enabled.
    samm_enabled: bool = true,

    /// Current class context (for METHOD/CONSTRUCTOR emission).
    current_class: ?*const semantic.ClassSymbol = null,

    pub fn init(
        builder: *QBEBuilder,
        type_manager: *const TypeManager,
        symbol_mapper: *SymbolMapper,
        runtime: *RuntimeLibrary,
        symbol_table: *const semantic.SymbolTable,
        allocator: std.mem.Allocator,
    ) Emitter {
        return .{
            .builder = builder,
            .type_manager = type_manager,
            .symbol_mapper = symbol_mapper,
            .runtime = runtime,
            .symbol_table = symbol_table,
            .allocator = allocator,
        };
    }

    // ── Expression Type Inference ───────────────────────────────────────

    /// QBE-level type classification for expression results.
    const ExprType = enum {
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
    fn inferExprType(self: *Emitter, expr: *const ast.Expression) ExprType {
        return switch (expr.data) {
            .string_lit => .string,
            .number => .double,
            .variable => |v| typeFromSuffix(v.type_suffix),
            .binary => |b| {
                // String concatenation yields string; otherwise numeric
                if (b.op == .ampersand or b.op == .plus) {
                    // If either operand is a string, result is string
                    const lt = self.inferExprType(b.left);
                    if (lt == .string) return .string;
                    const rt = self.inferExprType(b.right);
                    if (rt == .string) return .string;
                }
                return .double;
            },
            .unary => .double,
            .function_call => |fc| blk: {
                // Function names ending with $ return strings
                if (fc.name.len > 0 and fc.name[fc.name.len - 1] == '$') break :blk ExprType.string;
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

    /// Emit code for an expression and return the temporary holding the result.
    /// Explicit error set to break recursive inference in emitExpression cycle.
    const EmitError = error{OutOfMemory};
    pub fn emitExpression(self: *Emitter, expr: *const ast.Expression) EmitError![]const u8 {
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

    fn emitNumberLiteral(self: *Emitter, value: f64) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        // Check if it's an integer value
        const as_int: i64 = @intFromFloat(value);
        if (@as(f64, @floatFromInt(as_int)) == value and value >= -2147483648.0 and value <= 2147483647.0) {
            // Emit as integer constant, then convert to double
            const int_temp = try self.builder.newTemp();
            try self.builder.emit("    {s} =w copy {d}\n", .{ int_temp, as_int });
            try self.builder.emitConvert(dest, "d", "swtof", int_temp);
        } else {
            // Emit as double constant directly
            try self.builder.emit("    {s} =d copy d_{d}\n", .{ dest, value });
        }
        return dest;
    }

    fn emitStringLiteral(self: *Emitter, value: []const u8) EmitError![]const u8 {
        const label = try self.builder.registerString(value);
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ dest, label });
        return dest;
    }

    fn emitVariableLoad(self: *Emitter, name: []const u8, suffix: ?Tag) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        const var_name = try self.symbol_mapper.globalVarName(name, suffix);
        const bt = semantic.baseTypeFromSuffix(suffix);
        const qbe_t = bt.toQBEType();

        // Load from global variable address
        try self.builder.emitLoad(dest, qbe_t, try std.fmt.allocPrint(self.allocator, "${s}", .{var_name}));
        return dest;
    }

    fn emitBinaryExpr(self: *Emitter, left: *const ast.Expression, op: Tag, right: *const ast.Expression) EmitError![]const u8 {
        const lhs = try self.emitExpression(left);
        const rhs = try self.emitExpression(right);
        const dest = try self.builder.newTemp();

        switch (op) {
            // Arithmetic
            .plus => try self.builder.emitBinary(dest, "d", "add", lhs, rhs),
            .minus => try self.builder.emitBinary(dest, "d", "sub", lhs, rhs),
            .multiply => try self.builder.emitBinary(dest, "d", "mul", lhs, rhs),
            .divide => try self.builder.emitBinary(dest, "d", "div", lhs, rhs),
            .kw_mod => {
                // Modulo: a - floor(a/b) * b
                const div_temp = try self.builder.newTemp();
                try self.builder.emitBinary(div_temp, "d", "div", lhs, rhs);
                const trunc_temp = try self.builder.newTemp();
                try self.builder.emitConvert(trunc_temp, "w", "dtosi", div_temp);
                const floor_temp = try self.builder.newTemp();
                try self.builder.emitConvert(floor_temp, "d", "swtof", trunc_temp);
                const mul_temp = try self.builder.newTemp();
                try self.builder.emitBinary(mul_temp, "d", "mul", floor_temp, rhs);
                try self.builder.emitBinary(dest, "d", "sub", lhs, mul_temp);
            },
            .power => {
                // Use runtime power function
                const args = try std.fmt.allocPrint(self.allocator, "d {s}, d {s}", .{ lhs, rhs });
                try self.builder.emitCall(dest, "d", "math_power", args);
            },
            .int_divide => {
                // Integer divide: truncate both to int, divide, convert back
                const li = try self.builder.newTemp();
                try self.builder.emitConvert(li, "w", "dtosi", lhs);
                const ri = try self.builder.newTemp();
                try self.builder.emitConvert(ri, "w", "dtosi", rhs);
                const div_result = try self.builder.newTemp();
                try self.builder.emitBinary(div_result, "w", "div", li, ri);
                try self.builder.emitConvert(dest, "d", "swtof", div_result);
            },

            // Comparison operators
            .equal => try self.builder.emitCompare(dest, "d", "eq", lhs, rhs),
            .not_equal => try self.builder.emitCompare(dest, "d", "ne", lhs, rhs),
            .less_than => try self.builder.emitCompare(dest, "d", "lt", lhs, rhs),
            .less_equal => try self.builder.emitCompare(dest, "d", "le", lhs, rhs),
            .greater_than => try self.builder.emitCompare(dest, "d", "gt", lhs, rhs),
            .greater_equal => try self.builder.emitCompare(dest, "d", "ge", lhs, rhs),

            // Logical operators
            .kw_and => try self.builder.emitBinary(dest, "w", "and", lhs, rhs),
            .kw_or => try self.builder.emitBinary(dest, "w", "or", lhs, rhs),
            .kw_xor => try self.builder.emitBinary(dest, "w", "xor", lhs, rhs),

            else => {
                // Fallback: treat as add
                try self.builder.emitComment("WARN: unhandled binary op, treating as add");
                try self.builder.emitBinary(dest, "d", "add", lhs, rhs);
            },
        }

        return dest;
    }

    fn emitUnaryExpr(self: *Emitter, op: Tag, operand: *const ast.Expression) EmitError![]const u8 {
        const val = try self.emitExpression(operand);
        const dest = try self.builder.newTemp();

        switch (op) {
            .minus => try self.builder.emitNeg(dest, "d", val),
            .kw_not => {
                // Logical NOT: result = (val == 0) ? 1 : 0
                try self.builder.emitCompare(dest, "w", "eq", val, "0");
            },
            else => {
                // Identity / no-op
                try self.builder.emit("    {s} =d copy {s}\n", .{ dest, val });
            },
        }

        return dest;
    }

    fn emitFunctionCall(self: *Emitter, name: []const u8, arguments: []const ast.ExprPtr, is_fn: bool) EmitError![]const u8 {
        _ = is_fn;

        // Emit arguments
        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        for (arguments, 0..) |arg, i| {
            if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.emitExpression(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "d {s}", .{arg_val});
        }

        const dest = try self.builder.newTemp();
        const mangled = try self.symbol_mapper.functionName(name);
        try self.builder.emitCall(dest, "d", mangled, args_buf.items);
        return dest;
    }

    fn emitIIF(self: *Emitter, condition: *const ast.Expression, true_val: *const ast.Expression, false_val: *const ast.Expression) EmitError![]const u8 {
        const cond = try self.emitExpression(condition);
        const id = self.builder.nextLabelId();
        const true_label = try std.fmt.allocPrint(self.allocator, "iif_true_{d}", .{id});
        const false_label = try std.fmt.allocPrint(self.allocator, "iif_false_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "iif_done_{d}", .{id});

        // Convert double condition to integer for branch
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
        // phi to merge results
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =d phi @{s} {s}, @{s} {s}\n", .{ dest, true_label, tv, false_label, fv });

        return dest;
    }

    fn emitMemberAccess(self: *Emitter, object: *const ast.Expression, member_name: []const u8) EmitError![]const u8 {
        const obj_addr = try self.emitExpression(object);
        _ = member_name;
        // TODO: look up field offset in type symbol and emit load
        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, "d", obj_addr);
        return dest;
    }

    fn emitMethodCall(self: *Emitter, object: *const ast.Expression, method_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        const obj_val = try self.emitExpression(object);

        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        // First argument is always the object reference
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

    fn emitArrayAccess(self: *Emitter, name: []const u8, indices: []const ast.ExprPtr, suffix: ?Tag) EmitError![]const u8 {
        _ = suffix;
        // Emit index expression
        if (indices.len == 0) {
            const dest = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
            return dest;
        }

        const index_val = try self.emitExpression(indices[0]);
        const index_int = try self.builder.newTemp();
        try self.builder.emitConvert(index_int, "w", "dtosi", index_val);

        // Get array descriptor address
        const desc_name = try self.symbol_mapper.arrayDescName(name);
        const desc_addr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ desc_addr, desc_name });

        // Get element address via runtime
        const elem_addr = try self.builder.newTemp();
        const args = try std.fmt.allocPrint(self.allocator, "l {s}, w {s}", .{ desc_addr, index_int });
        try self.builder.emitCall(elem_addr, "l", "array_element_addr", args);

        // Load the element
        const dest = try self.builder.newTemp();
        try self.builder.emitLoad(dest, "d", elem_addr);
        return dest;
    }

    fn emitCreate(self: *Emitter, type_name: []const u8, arguments: []const ast.ExprPtr, is_named: bool, field_names: []const []const u8) EmitError![]const u8 {
        _ = is_named;
        _ = field_names;
        // Allocate stack space for the UDT
        const udt_size = self.type_manager.sizeOfUDT(type_name);
        const size: u32 = if (udt_size == 0) 16 else udt_size;

        const addr = try self.builder.newTemp();
        try self.builder.emitAlloc(addr, size, 8);

        // Initialize fields with provided arguments
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
                    // Zero-initialize unspecified fields
                    const store_type = field.type_desc.base_type.toQBEMemOp();
                    try self.builder.emitStore(store_type, "0", field_addr);
                }

                offset += self.type_manager.sizeOf(field.type_desc.base_type);
            }
        } else {
            // Type not found — zero-fill entirely
            try self.builder.emitComment("WARNING: unknown type in CREATE, zero-filling");
        }

        return addr;
    }

    fn emitNew(self: *Emitter, class_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = arguments;
        // Look up class to get object size and vtable
        const vtable_label = try self.symbol_mapper.vtableName(class_name);
        const vtable_addr = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy ${s}\n", .{ vtable_addr, vtable_label });

        const cls = self.symbol_table.lookupClass(class_name);
        const obj_size: i32 = if (cls) |c| c.object_size else semantic.ClassSymbol.header_size;

        const obj = try self.builder.newTemp();
        const args = try std.fmt.allocPrint(self.allocator, "w {d}, l {s}", .{ obj_size, vtable_addr });
        try self.builder.emitCall(obj, "l", "object_alloc", args);

        // TODO: call constructor if present
        return obj;
    }

    fn emitMe(self: *Emitter) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy %me\n", .{dest});
        return dest;
    }

    fn emitNothing(self: *Emitter) EmitError![]const u8 {
        const dest = try self.builder.newTemp();
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
    }

    fn emitIsType(self: *Emitter, object: *const ast.Expression, class_name: []const u8, is_nothing_check: bool) EmitError![]const u8 {
        const obj_val = try self.emitExpression(object);
        const dest = try self.builder.newTemp();

        if (is_nothing_check) {
            try self.builder.emitCompare(dest, "l", "eq", obj_val, "0");
        } else {
            // TODO: runtime type check via vtable
            _ = class_name;
            try self.builder.emitComment("TODO: IS type check");
            try self.builder.emit("    {s} =w copy 0\n", .{dest});
        }
        return dest;
    }

    fn emitSuperCall(self: *Emitter, method_name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = method_name;
        _ = arguments;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: SUPER call");
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }

    fn emitListConstructor(self: *Emitter, elements: []const ast.ExprPtr) EmitError![]const u8 {
        _ = elements;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: list constructor");
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
    }

    fn emitArrayBinop(self: *Emitter, left: *const ast.Expression, operation: ast.ArrayBinopExpr.OpType, right: *const ast.Expression) EmitError![]const u8 {
        _ = operation;
        _ = left;
        _ = right;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: array binary operation");
        try self.builder.emit("    {s} =l copy 0\n", .{dest});
        return dest;
    }

    fn emitRegistryFunction(self: *Emitter, name: []const u8, arguments: []const ast.ExprPtr) EmitError![]const u8 {
        _ = arguments;
        _ = name;
        const dest = try self.builder.newTemp();
        try self.builder.emitComment("TODO: registry function call");
        try self.builder.emit("    {s} =d copy d_0.0\n", .{dest});
        return dest;
    }

    // ── Statement Emission ──────────────────────────────────────────────

    /// Emit code for a single statement.
    pub fn emitStatement(self: *Emitter, stmt: *const ast.Statement) EmitError!void {
        switch (stmt.data) {
            .print => |pr| try self.emitPrintStatement(&pr),
            .let => |lt| try self.emitLetStatement(&lt),
            .if_stmt => |ifs| try self.emitIfStatement(&ifs, stmt.loc),
            .for_stmt => |fs| try self.emitForStatement(&fs),
            .while_stmt => |ws| try self.emitWhileStatement(&ws),
            .do_stmt => |ds| try self.emitDoStatement(&ds),
            .call => |cs| try self.emitCallStatement(&cs),
            .return_stmt => |rs| try self.emitReturnStatement(&rs),
            .end_stmt => try self.builder.emitJump("program_exit"),
            .dim => |dim| try self.emitDimStatement(&dim),
            .inc => |id| try self.emitIncDec(&id, true),
            .dec => |id| try self.emitIncDec(&id, false),
            .console => |con| try self.emitConsoleStatement(&con),
            .rem => {},
            .label => |lbl| try self.builder.emitLabel(lbl.label_name),
            .goto_stmt => |gt| {
                if (gt.is_label) {
                    try self.builder.emitJump(gt.label);
                }
            },
            .exit_stmt => try self.builder.emitComment("EXIT (TODO: jump to loop end)"),
            .swap => |sw| try self.emitSwapStatement(&sw),
            .repeat_stmt => |rs| try self.emitRepeatStatement(&rs),
            .case_stmt => |cs| try self.emitCaseStatement(&cs),
            .try_catch => |tc| try self.emitTryCatchStatement(&tc),
            .for_in => |fi| try self.emitForInStatement(&fi),
            .option => {},
            .type_decl => {},
            .class => {},
            .data_stmt => {},
            .function => |func| try self.emitFunctionDef(&func),
            .sub => |sub| try self.emitSubDef(&sub),
            else => {
                try self.builder.emitComment("TODO: unhandled statement type");
            },
        }
    }

    fn emitPrintStatement(self: *Emitter, pr: *const ast.PrintStmt) EmitError!void {
        for (pr.items) |item| {
            const val = try self.emitExpression(item.expr);
            const et = self.inferExprType(item.expr);
            const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.argLetter(), val });
            try self.runtime.callVoid(et.printFn(), args);

            if (item.comma) {
                try self.runtime.callVoid("print_tab", "");
            }
        }

        if (pr.trailing_newline) {
            try self.runtime.callVoid("print_newline", "");
        }
    }

    fn emitConsoleStatement(self: *Emitter, con: *const ast.ConsoleStmt) EmitError!void {
        for (con.items) |item| {
            const val = try self.emitExpression(item.expr);
            const et = self.inferExprType(item.expr);
            const args = try std.fmt.allocPrint(self.allocator, "{s} {s}", .{ et.argLetter(), val });
            try self.runtime.callVoid(et.printFn(), args);
        }
        if (con.trailing_newline) {
            try self.runtime.callVoid("print_newline", "");
        }
    }

    fn emitLetStatement(self: *Emitter, lt: *const ast.LetStmt) EmitError!void {
        const val = try self.emitExpression(lt.value);
        const var_name = try self.symbol_mapper.globalVarName(lt.variable, lt.type_suffix);
        const bt = semantic.baseTypeFromSuffix(lt.type_suffix);
        const store_type = bt.toQBEMemOp();
        const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});

        // For member chain assignments (e.g., point.x = value), this would need
        // to compute the field offset. For now, handle simple scalar assignment.
        if (lt.member_chain.len == 0 and lt.indices.len == 0) {
            try self.builder.emitStore(store_type, val, var_addr);
        } else if (lt.indices.len > 0) {
            // Array element assignment
            try self.builder.emitComment("TODO: array element store");
        } else {
            // Member chain assignment
            try self.builder.emitComment("TODO: member chain store");
        }
    }

    fn emitIfStatement(self: *Emitter, ifs: *const ast.IfStmt, loc: SourceLocation) EmitError!void {
        _ = loc;
        const id = self.builder.nextLabelId();
        const then_label = try std.fmt.allocPrint(self.allocator, "if_then_{d}", .{id});
        const else_label = try std.fmt.allocPrint(self.allocator, "if_else_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "if_done_{d}", .{id});

        // Emit condition
        const cond = try self.emitExpression(ifs.condition);
        const cond_int = try self.builder.newTemp();
        try self.builder.emitConvert(cond_int, "w", "dtosi", cond);

        const has_else = ifs.else_statements.len > 0 or ifs.elseif_clauses.len > 0;
        try self.builder.emitBranch(cond_int, then_label, if (has_else) else_label else done_label);

        // Then block
        try self.builder.emitLabel(then_label);
        for (ifs.then_statements) |s| {
            try self.emitStatement(s);
        }
        try self.builder.emitJump(done_label);

        // Else block (simplified — doesn't handle ELSEIF chains yet)
        if (has_else) {
            try self.builder.emitLabel(else_label);
            for (ifs.else_statements) |s| {
                try self.emitStatement(s);
            }
            // TODO: handle elseif_clauses chain
            try self.builder.emitJump(done_label);
        }

        try self.builder.emitLabel(done_label);
    }

    fn emitForStatement(self: *Emitter, fs: *const ast.ForStmt) EmitError!void {
        const id = self.builder.nextLabelId();
        const cond_label = try std.fmt.allocPrint(self.allocator, "for_cond_{d}", .{id});
        const body_label = try std.fmt.allocPrint(self.allocator, "for_body_{d}", .{id});
        const inc_label = try std.fmt.allocPrint(self.allocator, "for_inc_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "for_done_{d}", .{id});

        // Initialize loop variable
        const start_val = try self.emitExpression(fs.start);
        const var_name = try self.symbol_mapper.globalVarName(fs.variable, null);
        const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});
        try self.builder.emitStore("d", start_val, var_addr);

        // Emit end value
        const end_val = try self.emitExpression(fs.end_expr);
        // Store end value in temp for reuse
        const end_addr = try self.builder.newTemp();
        try self.builder.emitAlloc(end_addr, 8, 8);
        try self.builder.emitStore("d", end_val, end_addr);

        try self.builder.emitJump(cond_label);

        // Condition check
        try self.builder.emitLabel(cond_label);
        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "d", var_addr);
        const end_reload = try self.builder.newTemp();
        try self.builder.emitLoad(end_reload, "d", end_addr);
        const cmp = try self.builder.newTemp();
        try self.builder.emitCompare(cmp, "d", "le", cur, end_reload);
        try self.builder.emitBranch(cmp, body_label, done_label);

        // Body
        try self.builder.emitLabel(body_label);
        for (fs.body) |s| {
            try self.emitStatement(s);
        }
        try self.builder.emitJump(inc_label);

        // Increment
        try self.builder.emitLabel(inc_label);
        const cur2 = try self.builder.newTemp();
        try self.builder.emitLoad(cur2, "d", var_addr);
        const step_val = if (fs.step) |step|
            try self.emitExpression(step)
        else blk: {
            const one = try self.builder.newTemp();
            try self.builder.emit("    {s} =d copy d_1.0\n", .{one});
            break :blk one;
        };
        const next_val = try self.builder.newTemp();
        try self.builder.emitBinary(next_val, "d", "add", cur2, step_val);
        try self.builder.emitStore("d", next_val, var_addr);
        try self.builder.emitJump(cond_label);

        try self.builder.emitLabel(done_label);
    }

    fn emitWhileStatement(self: *Emitter, ws: *const ast.WhileStmt) EmitError!void {
        const id = self.builder.nextLabelId();
        const cond_label = try std.fmt.allocPrint(self.allocator, "while_cond_{d}", .{id});
        const body_label = try std.fmt.allocPrint(self.allocator, "while_body_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "while_done_{d}", .{id});

        try self.builder.emitJump(cond_label);
        try self.builder.emitLabel(cond_label);

        const cond = try self.emitExpression(ws.condition);
        const cond_int = try self.builder.newTemp();
        try self.builder.emitConvert(cond_int, "w", "dtosi", cond);
        try self.builder.emitBranch(cond_int, body_label, done_label);

        try self.builder.emitLabel(body_label);
        for (ws.body) |s| {
            try self.emitStatement(s);
        }
        try self.builder.emitJump(cond_label);

        try self.builder.emitLabel(done_label);
    }

    fn emitDoStatement(self: *Emitter, ds: *const ast.DoStmt) EmitError!void {
        const id = self.builder.nextLabelId();
        const body_label = try std.fmt.allocPrint(self.allocator, "do_body_{d}", .{id});
        const cond_label = try std.fmt.allocPrint(self.allocator, "do_cond_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "do_done_{d}", .{id});

        // Pre-condition (DO WHILE / DO UNTIL)
        if (ds.pre_condition) |pc| {
            try self.builder.emitJump(cond_label);
            try self.builder.emitLabel(cond_label);
            const cond = try self.emitExpression(pc);
            const cond_int = try self.builder.newTemp();
            try self.builder.emitConvert(cond_int, "w", "dtosi", cond);
            if (ds.pre_condition_type == .until_cond) {
                // UNTIL: loop while condition is false
                try self.builder.emitBranch(cond_int, done_label, body_label);
            } else {
                try self.builder.emitBranch(cond_int, body_label, done_label);
            }
        } else {
            try self.builder.emitJump(body_label);
        }

        try self.builder.emitLabel(body_label);
        for (ds.body) |s| {
            try self.emitStatement(s);
        }

        // Post-condition (LOOP WHILE / LOOP UNTIL)
        if (ds.post_condition) |pc| {
            const cond = try self.emitExpression(pc);
            const cond_int = try self.builder.newTemp();
            try self.builder.emitConvert(cond_int, "w", "dtosi", cond);
            if (ds.post_condition_type == .until_cond) {
                try self.builder.emitBranch(cond_int, done_label, body_label);
            } else {
                try self.builder.emitBranch(cond_int, body_label, done_label);
            }
        } else {
            // Infinite loop (needs EXIT DO to break)
            try self.builder.emitJump(body_label);
        }

        try self.builder.emitLabel(done_label);
    }

    fn emitRepeatStatement(self: *Emitter, rs: *const ast.RepeatStmt) EmitError!void {
        const id = self.builder.nextLabelId();
        const body_label = try std.fmt.allocPrint(self.allocator, "repeat_body_{d}", .{id});
        const done_label = try std.fmt.allocPrint(self.allocator, "repeat_done_{d}", .{id});

        try self.builder.emitJump(body_label);
        try self.builder.emitLabel(body_label);

        for (rs.body) |s| {
            try self.emitStatement(s);
        }

        if (rs.condition) |cond_expr| {
            const cond = try self.emitExpression(cond_expr);
            const cond_int = try self.builder.newTemp();
            try self.builder.emitConvert(cond_int, "w", "dtosi", cond);
            // REPEAT...UNTIL: loop while condition is false
            try self.builder.emitBranch(cond_int, done_label, body_label);
        } else {
            try self.builder.emitJump(body_label);
        }

        try self.builder.emitLabel(done_label);
    }

    fn emitCallStatement(self: *Emitter, cs: *const ast.CallStmt) EmitError!void {
        var args_buf: std.ArrayList(u8) = .empty;
        defer args_buf.deinit(self.allocator);

        for (cs.arguments, 0..) |arg, i| {
            if (i > 0) try args_buf.appendSlice(self.allocator, ", ");
            const arg_val = try self.emitExpression(arg);
            try std.fmt.format(args_buf.writer(self.allocator), "d {s}", .{arg_val});
        }

        const mangled = try self.symbol_mapper.subName(cs.sub_name);
        try self.builder.emitCall("", "", mangled, args_buf.items);
    }

    fn emitReturnStatement(self: *Emitter, rs: *const ast.ReturnStmt) EmitError!void {
        if (rs.return_value) |rv| {
            const val = try self.emitExpression(rv);
            try self.builder.emitReturn(val);
        } else {
            try self.builder.emitReturn("");
        }
    }

    fn emitDimStatement(self: *Emitter, dim: *const ast.DimStmt) EmitError!void {
        for (dim.arrays) |arr| {
            if (arr.dimensions.len > 0) {
                // Array allocation
                try self.builder.emitComment(try std.fmt.allocPrint(self.allocator, "DIM {s}(...)", .{arr.name}));
                // TODO: emit array_create call
            } else if (arr.initializer) |init_expr| {
                // Scalar with initializer: DIM x AS INTEGER = 42
                const val = try self.emitExpression(init_expr);
                const var_name = try self.symbol_mapper.globalVarName(arr.name, arr.type_suffix);
                const bt = if (arr.has_as_type)
                    semantic.baseTypeFromSuffix(if (arr.as_type_keyword) |kw| kw.asTypeToSuffix() else null)
                else
                    semantic.baseTypeFromSuffix(arr.type_suffix);
                const store_type = bt.toQBEMemOp();
                const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});
                try self.builder.emitStore(store_type, val, var_addr);
            }
        }
    }

    fn emitIncDec(self: *Emitter, id: *const ast.IncDecStmt, is_inc: bool) EmitError!void {
        const var_name = try self.symbol_mapper.globalVarName(id.var_name, null);
        const var_addr = try std.fmt.allocPrint(self.allocator, "${s}", .{var_name});

        const cur = try self.builder.newTemp();
        try self.builder.emitLoad(cur, "d", var_addr);

        const amount = if (id.amount_expr) |ae|
            try self.emitExpression(ae)
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

    fn emitSwapStatement(self: *Emitter, sw: *const ast.SwapStmt) EmitError!void {
        const name1 = try self.symbol_mapper.globalVarName(sw.var1, null);
        const name2 = try self.symbol_mapper.globalVarName(sw.var2, null);
        const addr1 = try std.fmt.allocPrint(self.allocator, "${s}", .{name1});
        const addr2 = try std.fmt.allocPrint(self.allocator, "${s}", .{name2});

        const tmp1 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp1, "d", addr1);
        const tmp2 = try self.builder.newTemp();
        try self.builder.emitLoad(tmp2, "d", addr2);
        try self.builder.emitStore("d", tmp2, addr1);
        try self.builder.emitStore("d", tmp1, addr2);
    }

    fn emitCaseStatement(self: *Emitter, cs: *const ast.CaseStmt) EmitError!void {
        const sel_val = try self.emitExpression(cs.case_expression);
        const id = self.builder.nextLabelId();
        const done_label = try std.fmt.allocPrint(self.allocator, "case_done_{d}", .{id});

        for (cs.when_clauses, 0..) |clause, i| {
            const when_body = try std.fmt.allocPrint(self.allocator, "when_body_{d}_{d}", .{ id, i });
            const when_next = try std.fmt.allocPrint(self.allocator, "when_next_{d}_{d}", .{ id, i });

            // Compare selector with each value
            if (clause.values.len > 0) {
                const cmp_val = try self.emitExpression(clause.values[0]);
                const cmp_result = try self.builder.newTemp();
                try self.builder.emitCompare(cmp_result, "d", "eq", sel_val, cmp_val);
                try self.builder.emitBranch(cmp_result, when_body, when_next);
            } else {
                try self.builder.emitJump(when_body);
            }

            try self.builder.emitLabel(when_body);
            for (clause.statements) |s| {
                try self.emitStatement(s);
            }
            try self.builder.emitJump(done_label);

            try self.builder.emitLabel(when_next);
        }

        // OTHERWISE
        for (cs.otherwise_statements) |s| {
            try self.emitStatement(s);
        }

        try self.builder.emitLabel(done_label);
    }

    fn emitTryCatchStatement(self: *Emitter, tc: *const ast.TryCatchStmt) EmitError!void {
        try self.builder.emitComment("TRY block");
        for (tc.try_block) |s| {
            try self.emitStatement(s);
        }
        // TODO: proper exception handling with setjmp/longjmp or runtime support
        for (tc.catch_clauses) |clause| {
            try self.builder.emitComment("CATCH block");
            for (clause.block) |s| {
                try self.emitStatement(s);
            }
        }
        if (tc.has_finally) {
            try self.builder.emitComment("FINALLY block");
            for (tc.finally_block) |s| {
                try self.emitStatement(s);
            }
        }
    }

    fn emitForInStatement(self: *Emitter, fi: *const ast.ForInStmt) EmitError!void {
        _ = fi;
        try self.builder.emitComment("TODO: FOR EACH ... IN loop");
    }

    fn emitFunctionDef(self: *Emitter, func: *const ast.FunctionStmt) EmitError!void {
        const mangled = try self.symbol_mapper.functionName(func.function_name);

        // Build parameter list
        var params_buf: std.ArrayList(u8) = .empty;
        defer params_buf.deinit(self.allocator);
        for (func.parameters, 0..) |param, i| {
            if (i > 0) try params_buf.appendSlice(self.allocator, ", ");
            const pt = if (i < func.parameter_types.len) func.parameter_types[i] else null;
            const bt = semantic.baseTypeFromSuffix(pt);
            try std.fmt.format(params_buf.writer(self.allocator), "{s} %{s}", .{ bt.toQBEType(), param });
        }

        try self.builder.emitFunctionStart(mangled, "d", params_buf.items);
        try self.builder.emitLabel("start");

        // Allocate return value slot
        const ret_slot = try self.builder.newTemp();
        try self.builder.emitAlloc(ret_slot, 8, 8);
        try self.builder.emitStore("d", "d_0.0", ret_slot);

        for (func.body) |s| {
            try self.emitStatement(s);
        }

        // Load and return the value
        const ret_val = try self.builder.newTemp();
        try self.builder.emitLoad(ret_val, "d", ret_slot);
        try self.builder.emitReturn(ret_val);
        try self.builder.emitFunctionEnd();
    }

    fn emitSubDef(self: *Emitter, sub: *const ast.SubStmt) EmitError!void {
        const mangled = try self.symbol_mapper.subName(sub.sub_name);

        var params_buf: std.ArrayList(u8) = .empty;
        defer params_buf.deinit(self.allocator);
        for (sub.parameters, 0..) |param, i| {
            if (i > 0) try params_buf.appendSlice(self.allocator, ", ");
            const pt = if (i < sub.parameter_types.len) sub.parameter_types[i] else null;
            const bt = semantic.baseTypeFromSuffix(pt);
            try std.fmt.format(params_buf.writer(self.allocator), "{s} %{s}", .{ bt.toQBEType(), param });
        }

        try self.builder.emitFunctionStart(mangled, "", params_buf.items);
        try self.builder.emitLabel("start");

        for (sub.body) |s| {
            try self.emitStatement(s);
        }

        try self.builder.emitReturn("");
        try self.builder.emitFunctionEnd();
    }
};

// ═══════════════════════════════════════════════════════════════════════════
// CodeGenerator — Top-level orchestrator
// ═══════════════════════════════════════════════════════════════════════════

/// Top-level code generator that drives the complete pipeline.
///
/// Usage:
/// ```
/// var gen = CodeGenerator.init(semantic_analyzer, allocator);
/// defer gen.deinit();
/// const il = try gen.generate(program);
/// ```
pub const CodeGenerator = struct {
    builder: QBEBuilder,
    type_manager: TypeManager,
    symbol_mapper: SymbolMapper,
    runtime: RuntimeLibrary,
    emitter: ?Emitter,

    semantic: *const semantic.SemanticAnalyzer,
    allocator: std.mem.Allocator,

    /// Whether to emit verbose comments.
    verbose: bool = false,
    /// Whether SAMM is enabled.
    samm_enabled: bool = true,

    pub fn init(sem: *const semantic.SemanticAnalyzer, allocator: std.mem.Allocator) CodeGenerator {
        return .{
            .allocator = allocator,
            .semantic = sem,
            .verbose = false,
            .samm_enabled = true,
            .builder = QBEBuilder.init(allocator),
            .type_manager = TypeManager.init(sem.getSymbolTable()),
            .symbol_mapper = SymbolMapper.init(allocator),
            // runtime and emitter hold interior pointers to this struct,
            // so they must be initialised *after* the struct has settled
            // at its final address (i.e. in generate(), where `self` is
            // a stable *CodeGenerator).
            .runtime = undefined,
            .emitter = null,
        };
    }

    pub fn deinit(self: *CodeGenerator) void {
        self.builder.deinit();
        self.symbol_mapper.deinit();
    }

    /// Generate QBE IL for the entire program. Returns the IL as a string.
    pub fn generate(self: *CodeGenerator, program: *const ast.Program) ![]const u8 {
        // Now that `self` is at its final address we can take interior
        // pointers safely.
        self.runtime = RuntimeLibrary.init(&self.builder);

        // Initialize the emitter (needs pointers to the other components)
        self.emitter = Emitter.init(
            &self.builder,
            &self.type_manager,
            &self.symbol_mapper,
            &self.runtime,
            self.semantic.getSymbolTable(),
            self.allocator,
        );

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

        // Phase 5: Main function
        try self.generateMainFunction(program);

        // Phase 6: Late string pool (any strings discovered during codegen)
        try self.builder.emitLateStringPool();

        return self.builder.getIL();
    }

    fn emitFileHeader(self: *CodeGenerator) !void {
        try self.builder.emitComment("═══════════════════════════════════════════════════════════════");
        try self.builder.emitComment(" FasterBASIC - Generated QBE IL");
        try self.builder.emitComment(" Generated by the Zig compiler (fbc)");
        try self.builder.emitComment("═══════════════════════════════════════════════════════════════");
        try self.builder.emitBlankLine();
    }

    fn emitGlobalVariables(self: *CodeGenerator) !void {
        const st = self.semantic.getSymbolTable();
        var it = st.variables.iterator();

        try self.builder.emitComment("=== Global Variables ===");

        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            if (sym.is_global) {
                const var_name = try self.symbol_mapper.globalVarName(sym.name, null);
                const size = self.type_manager.sizeOf(sym.type_desc.base_type);
                const actual_size: u32 = if (size == 0) 8 else size;

                try self.builder.emitGlobalData(var_name, "z", try std.fmt.allocPrint(self.allocator, "{d}", .{actual_size}));
            }
        }

        try self.builder.emitBlankLine();
    }

    fn emitGlobalArrays(self: *CodeGenerator) !void {
        const st = self.semantic.getSymbolTable();
        var it = st.arrays.iterator();

        if (st.arrays.count() > 0) {
            try self.builder.emitComment("=== Global Arrays ===");
        }

        while (it.next()) |entry| {
            const sym = entry.value_ptr;
            const desc_name = try self.symbol_mapper.arrayDescName(sym.name);
            // Array descriptors are 32 bytes (pointer + dims + size info)
            try self.builder.emitGlobalData(desc_name, "z", "32");
        }

        if (st.arrays.count() > 0) {
            try self.builder.emitBlankLine();
        }
    }

    fn generateMainFunction(self: *CodeGenerator, program: *const ast.Program) !void {
        try self.builder.emitFunctionStart("main", "w", "");
        try self.builder.emitLabel("start");

        // Initialize SAMM if enabled
        if (self.samm_enabled) {
            try self.runtime.callVoid("samm_init", "");
        }

        // Emit all statements
        var emitter = &self.emitter.?;
        for (program.lines) |line| {
            for (line.statements) |stmt| {
                // Skip function/sub definitions in the main body — they're
                // emitted separately.
                switch (stmt.data) {
                    .function, .sub, .type_decl, .class, .data_stmt => continue,
                    else => {},
                }
                try emitter.emitStatement(stmt);
            }
        }

        // Fall through to program_exit for normal completion
        try self.builder.emitJump("program_exit");

        // Emit function/sub definitions after the main function
        try self.builder.emitLabel("program_exit");
        try self.builder.emitComment("Program exit");
        if (self.samm_enabled) {
            try self.runtime.callVoid("samm_shutdown", "");
        }
        try self.builder.emitReturn("0");
        try self.builder.emitFunctionEnd();

        // Emit function/sub definitions
        for (program.lines) |line| {
            for (line.statements) |stmt| {
                switch (stmt.data) {
                    .function, .sub => try emitter.emitStatement(stmt),
                    else => {},
                }
            }
        }
    }

    fn collectStringLiterals(self: *CodeGenerator, program: *const ast.Program) !void {
        for (program.lines) |line| {
            for (line.statements) |stmt| {
                try self.collectStringsFromStatement(stmt);
            }
        }
    }

    fn collectStringsFromStatement(self: *CodeGenerator, stmt: *const ast.Statement) !void {
        switch (stmt.data) {
            .print => |pr| {
                for (pr.items) |item| try self.collectStringsFromExpression(item.expr);
                if (pr.format_expr) |fe| try self.collectStringsFromExpression(fe);
                for (pr.using_values) |uv| try self.collectStringsFromExpression(uv);
            },
            .let => |lt| {
                try self.collectStringsFromExpression(lt.value);
                for (lt.indices) |idx| try self.collectStringsFromExpression(idx);
            },
            .if_stmt => |ifs| {
                try self.collectStringsFromExpression(ifs.condition);
                for (ifs.then_statements) |s| try self.collectStringsFromStatement(s);
                for (ifs.elseif_clauses) |clause| {
                    try self.collectStringsFromExpression(clause.condition);
                    for (clause.statements) |s| try self.collectStringsFromStatement(s);
                }
                for (ifs.else_statements) |s| try self.collectStringsFromStatement(s);
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
                for (ds.body) |s| try self.collectStringsFromStatement(s);
                if (ds.post_condition) |pc| try self.collectStringsFromExpression(pc);
            },
            .call => |cs| {
                for (cs.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .function => |func| {
                for (func.body) |s| try self.collectStringsFromStatement(s);
            },
            .sub => |sub| {
                for (sub.body) |s| try self.collectStringsFromStatement(s);
            },
            .console => |con| {
                for (con.items) |item| try self.collectStringsFromExpression(item.expr);
            },
            .dim => |dim| {
                for (dim.arrays) |arr| {
                    if (arr.initializer) |init_expr| try self.collectStringsFromExpression(init_expr);
                }
            },
            else => {},
        }
    }

    fn collectStringsFromExpression(self: *CodeGenerator, expr: *const ast.Expression) !void {
        switch (expr.data) {
            .string_lit => |s| _ = try self.builder.registerString(s.value),
            .binary => |b| {
                try self.collectStringsFromExpression(b.left);
                try self.collectStringsFromExpression(b.right);
            },
            .unary => |u| try self.collectStringsFromExpression(u.operand),
            .function_call => |fc| {
                for (fc.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .iif => |i| {
                try self.collectStringsFromExpression(i.condition);
                try self.collectStringsFromExpression(i.true_value);
                try self.collectStringsFromExpression(i.false_value);
            },
            .method_call => |mc| {
                try self.collectStringsFromExpression(mc.object);
                for (mc.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .member_access => |ma| try self.collectStringsFromExpression(ma.object),
            .create => |cr| {
                for (cr.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .new => |n| {
                for (n.arguments) |arg| try self.collectStringsFromExpression(arg);
            },
            .array_access => |aa| {
                for (aa.indices) |idx| try self.collectStringsFromExpression(idx);
            },
            .is_type => |it| try self.collectStringsFromExpression(it.object),
            .list_constructor => |lc| {
                for (lc.elements) |elem| try self.collectStringsFromExpression(elem);
            },
            else => {},
        }
    }
};

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
