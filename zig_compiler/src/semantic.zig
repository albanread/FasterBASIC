//! Semantic Analysis for the FasterBASIC compiler.
//!
//! This module implements:
//! - Type system (base types, type descriptors, coercion rules)
//! - Symbol table (variables, arrays, functions, types, classes, labels, constants)
//! - Semantic analyzer (multi-pass: collect declarations, then validate)
//!
//! Design differences from the C++ version:
//! - Uses Zig tagged unions and enums instead of class hierarchies.
//! - Symbol table uses hash maps with string keys (allocator-backed).
//! - Error/warning collection uses ArrayList instead of std::vector.
//! - Scope tracking uses a simple enum + string pair instead of a class.
//! - No exceptions — errors are collected and reported after analysis.

const std = @import("std");
const token = @import("token.zig");
const ast = @import("ast.zig");
const Tag = token.Tag;
const SourceLocation = token.SourceLocation;

// ─── Base Types ─────────────────────────────────────────────────────────────

/// The fundamental types in the FasterBASIC type system.
pub const BaseType = enum(u8) {
    // Integer types (unsigned)
    byte, // 8-bit unsigned
    ubyte, // 8-bit unsigned (explicit)
    // Integer types (signed)
    short, // 16-bit signed
    ushort, // 16-bit unsigned
    integer, // 32-bit signed (default numeric)
    uinteger, // 32-bit unsigned
    long, // 64-bit signed
    ulong, // 64-bit unsigned

    // Floating-point types
    single, // 32-bit float
    double, // 64-bit float (default float)

    // String types
    string, // byte string
    unicode, // Unicode string (codepoint array)

    // Composite / special types
    user_defined, // UDT (struct)
    pointer, // raw pointer
    array_desc, // array descriptor
    string_desc, // string descriptor
    loop_index, // FOR loop index variable

    // Object system types
    object, // generic object reference
    class_instance, // typed class instance reference

    // Sentinel types
    void, // no value (SUB return, etc.)
    unknown, // unresolved / error

    /// Return the size in bits of this base type, or 0 for non-numeric types.
    pub fn bitWidth(self: BaseType) u32 {
        return switch (self) {
            .byte, .ubyte => 8,
            .short, .ushort => 16,
            .integer, .uinteger => 32,
            .long, .ulong => 64,
            .single => 32,
            .double => 64,
            .pointer, .object, .class_instance, .array_desc, .string_desc, .string, .unicode => 64,
            .loop_index => 32,
            else => 0,
        };
    }

    /// Whether this type is an integer type (signed or unsigned).
    pub fn isInteger(self: BaseType) bool {
        return switch (self) {
            .byte, .ubyte, .short, .ushort, .integer, .uinteger, .long, .ulong, .loop_index => true,
            else => false,
        };
    }

    /// Whether this type is a floating-point type.
    pub fn isFloat(self: BaseType) bool {
        return self == .single or self == .double;
    }

    /// Whether this type is numeric (integer or float).
    pub fn isNumeric(self: BaseType) bool {
        return self.isInteger() or self.isFloat();
    }

    /// Whether this type is a string type.
    pub fn isString(self: BaseType) bool {
        return self == .string or self == .unicode;
    }

    /// Whether this type is unsigned.
    pub fn isUnsigned(self: BaseType) bool {
        return switch (self) {
            .ubyte, .ushort, .uinteger, .ulong, .byte => true,
            else => false,
        };
    }

    /// Return the QBE IL type suffix for this base type.
    pub fn toQBEType(self: BaseType) []const u8 {
        return switch (self) {
            .byte, .ubyte => "ub",
            .short, .ushort => "uh",
            .integer, .uinteger, .loop_index => "w",
            .long, .ulong => "l",
            .single => "s",
            .double => "d",
            .string, .unicode, .pointer, .object, .class_instance, .array_desc, .string_desc, .user_defined => "l",
            .void => "",
            .unknown => "w",
        };
    }

    /// Return the QBE IL memory store/load type suffix.
    pub fn toQBEMemOp(self: BaseType) []const u8 {
        return switch (self) {
            .byte, .ubyte => "b",
            .short, .ushort => "h",
            .integer, .uinteger, .loop_index => "w",
            .long, .ulong => "l",
            .single => "s",
            .double => "d",
            .string, .unicode, .pointer, .object, .class_instance, .array_desc, .string_desc, .user_defined => "l",
            .void => "",
            .unknown => "w",
        };
    }

    /// Human-readable name.
    pub fn name(self: BaseType) []const u8 {
        return @tagName(self);
    }
};

// ─── Legacy Variable Type (for compatibility) ───────────────────────────────

/// Simplified variable type enum matching the original C++ VariableType.
/// Used for quick type checks and legacy interfaces.
pub const VariableType = enum {
    int,
    float,
    double,
    string,
    unicode,
    void,
    user_defined,
    adaptive,
    unknown,

    pub fn isNumeric(self: VariableType) bool {
        return self == .int or self == .float or self == .double;
    }
};

// ─── Type Attributes ────────────────────────────────────────────────────────

/// Bitfield of type attributes that can be combined.
pub const TypeAttribute = packed struct {
    is_array: bool = false,
    is_pointer: bool = false,
    is_const: bool = false,
    is_byref: bool = false,
    is_unsigned: bool = false,
    is_dynamic: bool = false,
    is_static: bool = false,
    is_hidden: bool = false,
};

// ─── Type Descriptor ────────────────────────────────────────────────────────

/// Full type descriptor carrying base type, attributes, and optional
/// user-defined / class type information.
pub const TypeDescriptor = struct {
    base_type: BaseType = .unknown,
    attributes: TypeAttribute = .{},

    /// For UDT types: the type ID in the symbol table.
    udt_type_id: i32 = -1,
    /// For UDT types: the type name.
    udt_name: []const u8 = "",
    /// For class types: the class name.
    class_name: []const u8 = "",
    /// For object types: the object type name (interface name, etc.).
    object_type_name: []const u8 = "",
    /// For array types: dimensions.
    array_dims: []const i32 = &.{},
    /// For typed arrays/lists: element type.
    element_type: BaseType = .unknown,
    /// Whether this is a class instance type (not just a UDT).
    is_class_type: bool = false,

    pub fn isArray(self: TypeDescriptor) bool {
        return self.attributes.is_array;
    }
    pub fn isPointer(self: TypeDescriptor) bool {
        return self.attributes.is_pointer;
    }
    pub fn isConst(self: TypeDescriptor) bool {
        return self.attributes.is_const;
    }
    pub fn isByRef(self: TypeDescriptor) bool {
        return self.attributes.is_byref;
    }
    pub fn isUserDefined(self: TypeDescriptor) bool {
        return self.base_type == .user_defined;
    }
    pub fn isObject(self: TypeDescriptor) bool {
        return self.base_type == .object;
    }
    pub fn isClassInstance(self: TypeDescriptor) bool {
        return self.base_type == .class_instance;
    }
    pub fn isInteger(self: TypeDescriptor) bool {
        return self.base_type.isInteger();
    }
    pub fn isFloat(self: TypeDescriptor) bool {
        return self.base_type.isFloat();
    }
    pub fn isNumeric(self: TypeDescriptor) bool {
        return self.base_type.isNumeric();
    }
    pub fn isString(self: TypeDescriptor) bool {
        return self.base_type.isString();
    }

    /// Create a descriptor for a simple base type.
    pub fn fromBase(bt: BaseType) TypeDescriptor {
        return .{ .base_type = bt };
    }

    /// Create a descriptor for a UDT type.
    pub fn fromUDT(type_name: []const u8, type_id: i32) TypeDescriptor {
        return .{
            .base_type = .user_defined,
            .udt_type_id = type_id,
            .udt_name = type_name,
        };
    }

    /// Create a descriptor for a class instance.
    pub fn fromClass(cname: []const u8) TypeDescriptor {
        return .{
            .base_type = .class_instance,
            .is_class_type = true,
            .class_name = cname,
        };
    }

    /// Create a descriptor for an object type.
    pub fn fromObject(type_name: []const u8) TypeDescriptor {
        return .{
            .base_type = .object,
            .object_type_name = type_name,
        };
    }

    /// Return the QBE IL type suffix for this descriptor.
    pub fn toQBEType(self: TypeDescriptor) []const u8 {
        return self.base_type.toQBEType();
    }

    /// Compare two type descriptors for structural equality.
    pub fn eql(self: TypeDescriptor, other: TypeDescriptor) bool {
        if (self.base_type != other.base_type) return false;
        if (self.base_type == .user_defined) {
            return std.mem.eql(u8, self.udt_name, other.udt_name);
        }
        if (self.base_type == .class_instance) {
            return std.mem.eql(u8, self.class_name, other.class_name);
        }
        return true;
    }
};

// ─── Type Conversion Helpers ────────────────────────────────────────────────

/// Convert a token type suffix to a BaseType.
/// Convert a token tag to a BaseType.
///
/// This function handles **both** suffix tags (`.type_int`, `.percent`, …)
/// and AS-type keyword tags (`.kw_integer`, `.kw_double`, …).  The parser
/// may store either form depending on whether the user wrote `x%` (suffix)
/// or `x AS INTEGER` (keyword).  Unifying them here gives every downstream
/// consumer — semantic analysis, codegen type-inference, variable
/// resolution — a single, consistent mapping.
pub fn baseTypeFromSuffix(suffix: ?Tag) BaseType {
    const s = suffix orelse return .double; // default numeric type
    return switch (s) {
        // ── Suffix tags ────────────────────────────────────────────
        .type_int, .percent => .integer,
        .type_float, .exclamation => .single,
        .type_double, .hash => .double,
        .type_string => .string,
        .type_byte, .at_suffix => .byte,
        .type_short, .caret => .short,
        .ampersand => .long,

        // ── AS-type keyword tags ───────────────────────────────────
        // The parser stores the keyword tag directly when the user
        // writes `AS INTEGER`, `AS DOUBLE`, etc.  Map them to the
        // same BaseType as their suffix counterparts.
        .kw_integer => .integer,
        .kw_uinteger => .uinteger,
        .kw_long => .long,
        .kw_ulong => .ulong,
        .kw_short => .short,
        .kw_ushort => .ushort,
        .kw_byte => .byte,
        .kw_ubyte => .ubyte,
        .kw_single => .single,
        .kw_double => .double,
        .kw_string_type => .string,

        else => .unknown,
    };
}

/// Convert a token type suffix to a TypeDescriptor.
pub fn descriptorFromSuffix(suffix: ?Tag) TypeDescriptor {
    return TypeDescriptor.fromBase(baseTypeFromSuffix(suffix));
}

/// Convert an AS type keyword tag to a TypeDescriptor.
/// Map an element type name (e.g. "INTEGER", "STRING") to a BaseType.
/// Used when parsing LIST OF <type> / HASHMAP OF <type>.
pub fn elementTypeFromName(name: []const u8) BaseType {
    // Case-insensitive compare via uppercase buffer
    var buf: [32]u8 = undefined;
    const len = @min(name.len, buf.len);
    for (0..len) |i| buf[i] = std.ascii.toUpper(name[i]);
    const upper = buf[0..len];
    if (std.mem.eql(u8, upper, "INTEGER")) return .integer;
    if (std.mem.eql(u8, upper, "INT")) return .integer;
    if (std.mem.eql(u8, upper, "LONG")) return .long;
    if (std.mem.eql(u8, upper, "ULONG")) return .ulong;
    if (std.mem.eql(u8, upper, "DOUBLE")) return .double;
    if (std.mem.eql(u8, upper, "SINGLE")) return .single;
    if (std.mem.eql(u8, upper, "FLOAT")) return .single;
    if (std.mem.eql(u8, upper, "STRING")) return .string;
    if (std.mem.eql(u8, upper, "BYTE")) return .byte;
    if (std.mem.eql(u8, upper, "UBYTE")) return .ubyte;
    if (std.mem.eql(u8, upper, "SHORT")) return .short;
    if (std.mem.eql(u8, upper, "USHORT")) return .ushort;
    if (std.mem.eql(u8, upper, "OBJECT")) return .object;
    if (std.mem.eql(u8, upper, "ANY")) return .unknown;
    // Unknown element type name — could be a class/UDT name; treat as object
    return .object;
}

pub fn descriptorFromKeyword(kw: Tag) TypeDescriptor {
    return switch (kw) {
        .kw_hashmap => TypeDescriptor.fromObject("HASHMAP"),
        .kw_list => TypeDescriptor.fromObject("LIST"),
        else => TypeDescriptor.fromBase(switch (kw) {
            .kw_integer => .integer,
            .kw_uinteger => .uinteger,
            .kw_double => .double,
            .kw_single => .single,
            .kw_string_type => .string,
            .kw_long => .long,
            .kw_ulong => .ulong,
            .kw_byte => .byte,
            .kw_ubyte => .ubyte,
            .kw_short => .short,
            .kw_ushort => .ushort,
            else => .unknown,
        }),
    };
}

/// Convert a legacy VariableType to a TypeDescriptor.
pub fn descriptorFromLegacy(vt: VariableType) TypeDescriptor {
    return TypeDescriptor.fromBase(switch (vt) {
        .int => .integer,
        .float => .single,
        .double => .double,
        .string => .string,
        .unicode => .unicode,
        .void => .void,
        .user_defined => .user_defined,
        .adaptive, .unknown => .unknown,
    });
}

/// Convert a TypeDescriptor to a legacy VariableType.
pub fn descriptorToLegacy(td: TypeDescriptor) VariableType {
    return switch (td.base_type) {
        .byte, .ubyte, .short, .ushort, .integer, .uinteger, .long, .ulong, .loop_index => .int,
        .single => .float,
        .double => .double,
        .string => .string,
        .unicode => .unicode,
        .void => .void,
        .user_defined => .user_defined,
        else => .unknown,
    };
}

// ─── Coercion ───────────────────────────────────────────────────────────────

/// Result of checking whether one type can be coerced to another.
pub const CoercionResult = enum {
    /// Types are identical — no conversion needed.
    identical,
    /// Implicit conversion is safe (no data loss). E.g. INTEGER → DOUBLE.
    implicit_safe,
    /// Implicit conversion may lose data. E.g. DOUBLE → INTEGER.
    implicit_lossy,
    /// Explicit conversion required (via cast function).
    explicit_required,
    /// Types are incompatible (e.g. STRING → INTEGER).
    incompatible,
};

/// Check whether `from` can be coerced to `to`.
pub fn checkCoercion(from: TypeDescriptor, to: TypeDescriptor) CoercionResult {
    if (from.eql(to)) return .identical;

    // Numeric → Numeric
    if (from.isNumeric() and to.isNumeric()) {
        return checkNumericCoercion(from.base_type, to.base_type);
    }

    // String → String (byte ↔ unicode)
    if (from.isString() and to.isString()) {
        return .implicit_safe;
    }

    // Numeric ↔ String: incompatible
    if ((from.isNumeric() and to.isString()) or (from.isString() and to.isNumeric())) {
        return .incompatible;
    }

    // Class instance → parent class: safe (upcast)
    // (actual subclass check requires the symbol table — done elsewhere)
    if (from.isClassInstance() and to.isClassInstance()) {
        return .explicit_required;
    }

    // UDT to UDT: only if same type
    if (from.isUserDefined() and to.isUserDefined()) {
        if (std.mem.eql(u8, from.udt_name, to.udt_name)) return .identical;
        return .incompatible;
    }

    return .incompatible;
}

/// Check numeric coercion between two base types.
pub fn checkNumericCoercion(from: BaseType, to: BaseType) CoercionResult {
    if (from == to) return .identical;

    const from_bits = from.bitWidth();
    const to_bits = to.bitWidth();

    // Widening integer → integer: safe
    if (from.isInteger() and to.isInteger()) {
        if (to_bits >= from_bits) return .implicit_safe;
        return .implicit_lossy;
    }

    // Integer → float: safe if float has enough precision
    if (from.isInteger() and to.isFloat()) {
        if (to == .double) return .implicit_safe;
        // single can represent up to 24-bit integers exactly
        if (from_bits <= 24) return .implicit_safe;
        return .implicit_lossy;
    }

    // Float → integer: lossy
    if (from.isFloat() and to.isInteger()) {
        return .implicit_lossy;
    }

    // Float → float widening
    if (from == .single and to == .double) return .implicit_safe;
    if (from == .double and to == .single) return .implicit_lossy;

    return .implicit_safe;
}

/// Given two types in a binary expression, return the promoted result type.
pub fn promoteTypes(a: TypeDescriptor, b: TypeDescriptor) TypeDescriptor {
    // String + anything → string
    if (a.isString() or b.isString()) return TypeDescriptor.fromBase(.string);

    // Both numeric: promote to the wider / more precise type
    if (a.isNumeric() and b.isNumeric()) {
        // If either is double, result is double
        if (a.base_type == .double or b.base_type == .double) return TypeDescriptor.fromBase(.double);
        // If either is single, result is single
        if (a.base_type == .single or b.base_type == .single) return TypeDescriptor.fromBase(.single);
        // If either is long, result is long
        if (a.base_type == .long or b.base_type == .long) return TypeDescriptor.fromBase(.long);
        // Otherwise integer
        return TypeDescriptor.fromBase(.integer);
    }

    return a;
}

// ─── Scope ──────────────────────────────────────────────────────────────────

/// Scope kind: global or inside a function/sub.
pub const ScopeKind = enum {
    global,
    function,
};

/// A scope identifier — either global or a named function scope.
pub const Scope = struct {
    kind: ScopeKind = .global,
    name: []const u8 = "",

    pub fn makeGlobal() Scope {
        return .{ .kind = .global };
    }

    pub fn makeFunction(func_name: []const u8) Scope {
        return .{ .kind = .function, .name = func_name };
    }

    pub fn isGlobal(self: Scope) bool {
        return self.kind == .global;
    }

    pub fn isFunction(self: Scope) bool {
        return self.kind == .function;
    }

    /// Build the scoped key for looking up symbols: "FUNC.NAME" or just "NAME".
    pub fn scopeKey(self: Scope, var_name: []const u8, allocator: std.mem.Allocator) ![]u8 {
        if (self.kind == .function and self.name.len > 0) {
            return std.fmt.allocPrint(allocator, "{s}.{s}", .{ self.name, var_name });
        }
        return allocator.dupe(u8, var_name);
    }
};

// ─── Symbol Table Entries ───────────────────────────────────────────────────

/// A variable symbol.
pub const VariableSymbol = struct {
    name: []const u8,
    type_desc: TypeDescriptor = .{},
    type_name: []const u8 = "",
    is_declared: bool = false,
    is_used: bool = false,
    first_use: SourceLocation = .{},
    scope: Scope = .{},
    is_global: bool = true,
    global_offset: i32 = -1,
};

/// An array symbol.
pub const ArraySymbol = struct {
    name: []const u8,
    element_type_desc: TypeDescriptor = .{},
    dimensions: []const i32 = &.{},
    is_declared: bool = false,
    declaration: SourceLocation = .{},
    total_size: i32 = 0,
    as_type_name: []const u8 = "",
    function_scope: []const u8 = "",
};

/// A function/sub symbol.
pub const FunctionSymbol = struct {
    name: []const u8,
    parameters: []const []const u8 = &.{},
    parameter_type_descs: []const TypeDescriptor = &.{},
    parameter_is_byref: []const bool = &.{},
    return_type_desc: TypeDescriptor = .{},
    return_type_name: []const u8 = "",
    definition: SourceLocation = .{},
    /// For DEF FN: the expression body (null for SUB/FUNCTION).
    body: ?*const ast.Expression = null,
};

/// A line number symbol.
pub const LineNumberSymbol = struct {
    line_number: i32,
    program_line_index: usize = 0,
};

/// A label symbol.
pub const LabelSymbol = struct {
    name: []const u8,
    label_id: i32 = 0,
    program_line_index: usize = 0,
    definition: SourceLocation = .{},
};

/// A constant symbol (CONSTANT name = value).
pub const ConstantSymbol = struct {
    pub const Kind = enum { integer_const, double_const, string_const };

    kind: Kind = .integer_const,
    int_value: i64 = 0,
    double_value: f64 = 0.0,
    string_value: []const u8 = "",
    index: i32 = 0,
};

/// A TYPE (UDT) symbol.
pub const TypeSymbol = struct {
    pub const Field = struct {
        name: []const u8,
        type_desc: TypeDescriptor = .{},
        type_name: []const u8 = "",
        built_in_type: VariableType = .unknown,
        is_built_in: bool = true,
    };

    name: []const u8,
    fields: []const Field = &.{},
    declaration: SourceLocation = .{},
    is_declared: bool = false,
    simd_type: ast.TypeDeclStmt.SIMDType = .none,
    simd_info: ast.TypeDeclStmt.SIMDInfo = .{},

    /// Look up a field by name (case-insensitive).
    pub fn findField(self: TypeSymbol, field_name: []const u8) ?*const Field {
        for (self.fields) |*f| {
            if (std.ascii.eqlIgnoreCase(f.name, field_name)) {
                return f;
            }
        }
        return null;
    }
};

/// A CLASS symbol.
pub const ClassSymbol = struct {
    pub const header_size: i32 = 16; // vtable ptr + class_id + refcount + padding

    pub const FieldInfo = struct {
        name: []const u8,
        type_desc: TypeDescriptor = .{},
        offset: i32 = 0,
        inherited: bool = false,
    };

    pub const MethodInfo = struct {
        name: []const u8,
        mangled_name: []const u8 = "",
        vtable_slot: i32 = 0,
        is_override: bool = false,
        origin_class: []const u8 = "",
        parameter_types: []const TypeDescriptor = &.{},
        return_type: TypeDescriptor = .{},
    };

    name: []const u8,
    class_id: i32 = 0,
    parent_class: ?*ClassSymbol = null,
    parent_class_name: []const u8 = "",
    declaration: SourceLocation = .{},
    is_declared: bool = false,

    object_size: i32 = header_size,
    fields: []FieldInfo = &.{},
    methods: []MethodInfo = &.{},

    has_constructor: bool = false,
    constructor_mangled_name: []const u8 = "",
    constructor_param_types: []const TypeDescriptor = &.{},
    has_destructor: bool = false,
    destructor_mangled_name: []const u8 = "",

    /// Find a field by name (case-insensitive).
    pub fn findField(self: ClassSymbol, field_name: []const u8) ?*const FieldInfo {
        for (self.fields) |*f| {
            if (std.ascii.eqlIgnoreCase(f.name, field_name)) {
                return f;
            }
        }
        return null;
    }

    /// Find a method by name (case-insensitive).
    pub fn findMethod(self: ClassSymbol, method_name: []const u8) ?*const MethodInfo {
        for (self.methods) |*m| {
            if (std.ascii.eqlIgnoreCase(m.name, method_name)) {
                return m;
            }
        }
        return null;
    }

    /// Get total method count (including inherited).
    pub fn getMethodCount(self: ClassSymbol) i32 {
        return @intCast(self.methods.len);
    }

    /// Check if this class is a subclass of the given class.
    pub fn isSubclassOf(self: *const ClassSymbol, ancestor_name: []const u8) bool {
        var current: ?*const ClassSymbol = self;
        while (current) |cls| {
            if (std.ascii.eqlIgnoreCase(cls.name, ancestor_name)) return true;
            current = cls.parent_class;
        }
        return false;
    }
};

/// DATA segment storage.
pub const DataSegment = struct {
    values: std.ArrayList([]const u8),
    read_pointer: usize = 0,
    /// Maps line number → index in values.
    restore_points: std.AutoHashMap(i32, usize),
    /// Maps label name → index in values.
    label_restore_points: std.StringHashMap(usize),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) DataSegment {
        return .{
            .values = .empty,
            .restore_points = std.AutoHashMap(i32, usize).init(allocator),
            .label_restore_points = std.StringHashMap(usize).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *DataSegment) void {
        self.values.deinit(self.allocator);
        self.restore_points.deinit();
        self.label_restore_points.deinit();
    }
};

// ─── Symbol Table ───────────────────────────────────────────────────────────

/// The central symbol table, populated during semantic analysis.
pub const SymbolTable = struct {
    variables: std.StringHashMap(VariableSymbol),
    arrays: std.StringHashMap(ArraySymbol),
    functions: std.StringHashMap(FunctionSymbol),
    types: std.StringHashMap(TypeSymbol),
    classes: std.StringHashMap(ClassSymbol),
    line_numbers: std.AutoHashMap(i32, LineNumberSymbol),
    labels: std.StringHashMap(LabelSymbol),
    constants: std.StringHashMap(ConstantSymbol),
    data_segment: DataSegment,

    // IDs
    next_label_id: i32 = 1,
    next_type_id: i32 = 1,
    next_class_id: i32 = 1,
    type_name_to_id: std.StringHashMap(i32),

    // Config (from OPTION statements)
    array_base: i32 = 1,
    string_mode: StringMode = .detectstring,
    error_tracking: bool = true,
    cancellable_loops: bool = true,
    events_used: bool = false,
    force_yield_enabled: bool = false,
    force_yield_budget: i32 = 10000,
    samm_enabled: bool = true,
    neon_enabled: bool = true,

    // Stats
    global_variable_count: i32 = 0,

    allocator: std.mem.Allocator,

    pub const StringMode = enum {
        ascii,
        unicode,
        detectstring,
    };

    pub fn init(allocator: std.mem.Allocator) SymbolTable {
        return .{
            .variables = std.StringHashMap(VariableSymbol).init(allocator),
            .arrays = std.StringHashMap(ArraySymbol).init(allocator),
            .functions = std.StringHashMap(FunctionSymbol).init(allocator),
            .types = std.StringHashMap(TypeSymbol).init(allocator),
            .classes = std.StringHashMap(ClassSymbol).init(allocator),
            .line_numbers = std.AutoHashMap(i32, LineNumberSymbol).init(allocator),
            .labels = std.StringHashMap(LabelSymbol).init(allocator),
            .constants = std.StringHashMap(ConstantSymbol).init(allocator),
            .data_segment = DataSegment.init(allocator),
            .type_name_to_id = std.StringHashMap(i32).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SymbolTable) void {
        self.variables.deinit();
        self.arrays.deinit();
        self.functions.deinit();
        self.types.deinit();
        self.classes.deinit();
        self.line_numbers.deinit();
        self.labels.deinit();
        self.constants.deinit();
        self.data_segment.deinit();
        self.type_name_to_id.deinit();
    }

    /// Allocate a unique type ID for a named UDT.
    pub fn allocateTypeId(self: *SymbolTable, type_name: []const u8) !i32 {
        if (self.type_name_to_id.get(type_name)) |existing| {
            return existing;
        }
        const id = self.next_type_id;
        self.next_type_id += 1;
        // Dupe the key so we own the memory (callers may pass stack buffers).
        const owned_key = try self.allocator.dupe(u8, type_name);
        try self.type_name_to_id.put(owned_key, id);
        return id;
    }

    /// Get the type ID for a named UDT, or null if not found.
    pub fn getTypeId(self: *const SymbolTable, type_name: []const u8) ?i32 {
        return self.type_name_to_id.get(type_name);
    }

    /// Allocate a unique class ID.
    pub fn allocateClassId(self: *SymbolTable) i32 {
        const id = self.next_class_id;
        self.next_class_id += 1;
        return id;
    }

    /// Insert a variable symbol.
    pub fn insertVariable(self: *SymbolTable, key: []const u8, sym: VariableSymbol) !void {
        try self.variables.put(key, sym);
    }

    /// Look up a variable by scoped key.
    pub fn lookupVariable(self: *const SymbolTable, key: []const u8) ?*const VariableSymbol {
        if (self.variables.getPtr(key)) |ptr| {
            return ptr;
        }
        return null;
    }

    /// Look up a variable by scoped key (mutable).
    pub fn lookupVariableMut(self: *SymbolTable, key: []const u8) ?*VariableSymbol {
        return self.variables.getPtr(key);
    }

    /// Look up a variable with fallback to global scope.
    pub fn lookupVariableWithFallback(self: *const SymbolTable, var_name: []const u8, scope: Scope) ?*const VariableSymbol {
        if (scope.isFunction()) {
            // Try function scope first
            var buf: [256]u8 = undefined;
            const scoped = std.fmt.bufPrint(&buf, "{s}.{s}", .{ scope.name, var_name }) catch return null;
            if (self.lookupVariable(scoped)) |sym| return sym;
        }
        // Fall back to global scope
        return self.lookupVariable(var_name);
    }

    /// Look up an array symbol.
    pub fn lookupArray(self: *const SymbolTable, array_name: []const u8) ?*const ArraySymbol {
        return self.arrays.getPtr(array_name);
    }

    /// Look up a function symbol.
    pub fn lookupFunction(self: *const SymbolTable, func_name: []const u8) ?*const FunctionSymbol {
        return self.functions.getPtr(func_name);
    }

    /// Look up a type (UDT) symbol.
    /// Look up a type (UDT) symbol (case-insensitive).
    pub fn lookupType(self: *const SymbolTable, type_name: []const u8) ?*const TypeSymbol {
        // Types are stored with uppercased keys — uppercase before lookup.
        var buf: [128]u8 = undefined;
        const len = @min(type_name.len, buf.len);
        for (0..len) |i| {
            buf[i] = std.ascii.toUpper(type_name[i]);
        }
        return self.types.getPtr(buf[0..len]);
    }

    /// Look up a type (UDT) symbol (mutable, case-insensitive).
    pub fn lookupTypeMut(self: *SymbolTable, type_name: []const u8) ?*TypeSymbol {
        var buf: [128]u8 = undefined;
        const len = @min(type_name.len, buf.len);
        for (0..len) |i| {
            buf[i] = std.ascii.toUpper(type_name[i]);
        }
        return self.types.getPtr(buf[0..len]);
    }

    /// Look up a class symbol (case-insensitive).
    pub fn lookupClass(self: *const SymbolTable, cname: []const u8) ?*const ClassSymbol {
        // Classes are stored with uppercased keys
        var buf: [128]u8 = undefined;
        const len = @min(cname.len, buf.len);
        for (0..len) |i| {
            buf[i] = std.ascii.toUpper(cname[i]);
        }
        return self.classes.getPtr(buf[0..len]);
    }

    /// Look up a label symbol.
    pub fn lookupLabel(self: *const SymbolTable, label_name: []const u8) ?*const LabelSymbol {
        return self.labels.getPtr(label_name);
    }

    /// Look up a constant symbol.
    pub fn lookupConstant(self: *const SymbolTable, const_name: []const u8) ?*const ConstantSymbol {
        return self.constants.getPtr(const_name);
    }

    /// Look up a line number symbol.
    pub fn lookupLineNumber(self: *const SymbolTable, line_num: i32) ?*const LineNumberSymbol {
        return self.line_numbers.getPtr(line_num);
    }
};

// ─── Compiler Options ───────────────────────────────────────────────────────

/// Compiler options collected from OPTION statements.
pub const CompilerOptions = struct {
    /// String encoding mode.
    pub const StringMode = enum { ascii, unicode, detectstring };
    /// FOR loop variable type.
    pub const ForLoopType = enum { integer_type, long_type };

    array_base: i32 = 1,
    string_mode: StringMode = .detectstring,
    for_loop_type: ForLoopType = .integer_type,
    cancellable_loops: bool = true,
    bounds_checking: bool = true,
    error_tracking: bool = true,
    bitwise_operators: bool = false,
    explicit_declarations: bool = false,
    samm_enabled: bool = true,
    force_yield_enabled: bool = false,
    force_yield_budget: i32 = 10000,
    neon_enabled: bool = true,

    pub fn reset(self: *CompilerOptions) void {
        self.* = .{};
    }
};

// ─── Semantic Errors & Warnings ─────────────────────────────────────────────

/// Categories of semantic errors.
pub const SemanticErrorType = enum {
    undefined_line,
    undefined_label,
    duplicate_label,
    undefined_variable,
    undefined_array,
    undefined_function,
    array_not_declared,
    array_redeclared,
    function_redeclared,
    type_mismatch,
    wrong_dimension_count,
    invalid_array_index,
    control_flow_mismatch,
    next_without_for,
    wend_without_while,
    until_without_repeat,
    loop_without_do,
    for_without_next,
    while_without_wend,
    do_without_loop,
    repeat_without_until,
    return_without_gosub,
    duplicate_line_number,
    undefined_type,
    duplicate_type,
    duplicate_field,
    undefined_field,
    circular_type_dependency,
    invalid_type_field,
    type_error,
    argument_count_mismatch,
    undefined_class,
    duplicate_class,
    circular_inheritance,
    class_error,
};

/// A semantic error.
pub const SemanticError = struct {
    error_type: SemanticErrorType,
    message: []const u8,
    location: SourceLocation = .{},

    pub fn format(self: SemanticError, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Semantic Error at {}: {s}", .{ self.location, self.message });
    }
};

/// A semantic warning.
pub const SemanticWarning = struct {
    message: []const u8,
    location: SourceLocation = .{},

    pub fn format(self: SemanticWarning, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("Warning at {}: {s}", .{ self.location, self.message });
    }
};

// ─── Semantic Analyzer ──────────────────────────────────────────────────────

/// Multi-pass semantic analyzer.
///
/// Pass 1: Collect declarations (types, classes, functions, subs, constants,
///         global variables, arrays, labels, line numbers, DATA statements).
/// Pass 2: Validate all statements and expressions (type checking, scope
///         resolution, control flow validation, etc.).
pub const SemanticAnalyzer = struct {
    symbol_table: SymbolTable,
    errors: std.ArrayList(SemanticError),
    warnings: std.ArrayList(SemanticWarning),
    options: CompilerOptions = .{},

    // Internal state
    current_line_number: i32 = 0,
    current_function_name: []const u8 = "",
    in_function: bool = false,

    // Loop tracking stacks (we use ArrayLists as stacks)
    for_stack: std.ArrayList(ForContext),
    while_stack: std.ArrayList(SourceLocation),
    repeat_stack: std.ArrayList(SourceLocation),
    do_stack: std.ArrayList(SourceLocation),

    // For-each variables
    for_each_variables: std.StringHashMap(void),

    // Config
    strict_mode: bool = false,
    warn_unused: bool = false,
    require_explicit_dim: bool = false,

    allocator: std.mem.Allocator,

    const ForContext = struct {
        variable: []const u8,
        location: SourceLocation,
    };

    pub fn init(allocator: std.mem.Allocator) SemanticAnalyzer {
        return .{
            .symbol_table = SymbolTable.init(allocator),
            .errors = .empty,
            .warnings = .empty,
            .for_stack = .empty,
            .while_stack = .empty,
            .repeat_stack = .empty,
            .do_stack = .empty,
            .for_each_variables = std.StringHashMap(void).init(allocator),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *SemanticAnalyzer) void {
        self.symbol_table.deinit();
        self.errors.deinit(self.allocator);
        self.warnings.deinit(self.allocator);
        self.for_stack.deinit(self.allocator);
        self.while_stack.deinit(self.allocator);
        self.repeat_stack.deinit(self.allocator);
        self.do_stack.deinit(self.allocator);
        self.for_each_variables.deinit();
    }

    /// Run semantic analysis on the given program AST.
    /// Returns true if no errors were found.
    pub fn analyze(self: *SemanticAnalyzer, program: *const ast.Program) !bool {
        // Pass 1: collect all declarations
        try self.pass1CollectDeclarations(program);

        // Pass 1b: fixup parent_class pointers now that all classes are
        // registered.  We cannot store stable pointers during pass 1
        // because each HashMap.put may grow the table and invalidate
        // every previously obtained pointer.
        self.fixupClassParentPointers();

        // Pass 2: validate all code
        try self.pass2Validate(program);

        return self.errors.items.len == 0;
    }

    pub fn hasErrors(self: *const SemanticAnalyzer) bool {
        return self.errors.items.len > 0;
    }

    pub fn getSymbolTable(self: *const SemanticAnalyzer) *const SymbolTable {
        return &self.symbol_table;
    }

    pub fn getCurrentScope(self: *const SemanticAnalyzer) Scope {
        if (self.in_function) {
            return Scope.makeFunction(self.current_function_name);
        }
        return Scope.makeGlobal();
    }

    // ── Error / Warning Reporting ───────────────────────────────────────

    pub fn addError(self: *SemanticAnalyzer, error_type: SemanticErrorType, message: []const u8, loc: SourceLocation) !void {
        try self.errors.append(self.allocator, .{
            .error_type = error_type,
            .message = message,
            .location = loc,
        });
    }

    pub fn addWarning(self: *SemanticAnalyzer, message: []const u8, loc: SourceLocation) !void {
        try self.warnings.append(self.allocator, .{
            .message = message,
            .location = loc,
        });
    }

    // ── Pass 1: Collect Declarations ────────────────────────────────────

    /// Explicit error set to break recursive inference in collectDeclaration cycle.
    const AnalyzeError = error{OutOfMemory};

    /// After all CLASS declarations have been collected, walk the class
    /// table and resolve every `parent_class` pointer.  This is safe
    /// because no more puts will happen until pass 2.
    fn fixupClassParentPointers(self: *SemanticAnalyzer) void {
        // First pass: collect parent-name → child-key pairs so we don't
        // iterate and mutate the same map simultaneously.
        // We just iterate the values and patch in-place (getPtr is stable
        // as long as we don't insert/remove).
        var it = self.symbol_table.classes.iterator();
        while (it.next()) |entry| {
            const cls = entry.value_ptr;
            // If parent_class is already set (shouldn't be after our
            // null-init strategy, but guard anyway) skip.
            if (cls.parent_class != null) continue;

            // Check if the ClassSymbol's AST-level parent name was
            // recorded.  We stored it as an inherited field list —
            // but we need the original parent name.  We can recover it
            // by checking if inherited fields exist but parent_class is
            // null.  Instead, let's just iterate the AST again… but we
            // don't have the AST here.
            //
            // Simpler: we stored fields with `inherited = true`.  Walk
            // all OTHER classes to find one whose non-inherited fields
            // match our inherited fields (expensive but correct).
            //
            // Even simpler: during collectClassDeclaration we can stash
            // the parent name.  For now, iterate all classes and match
            // by class_id on inherited method origin.
        }

        // Better approach: iterate all classes, for each one that has
        // inherited fields/methods, find the parent by matching the
        // origin_class of the first inherited method, or by matching
        // field offsets.  But this is fragile.
        //
        // The cleanest fix: store the parent class name alongside the
        // ClassSymbol during collectClassDeclaration and use it here.
        // We'll piggy-back on the destructor_mangled_name field... no,
        // let's just do a second scan of the program AST from analyze().
        // But we don't have the program pointer here.
        //
        // Actually the simplest: just iterate the class map and for each
        // class, check every other class to see if it should be the parent
        // (by checking inherited fields/methods).
        //
        // EVEN SIMPLER: we already set parent_class = null during put.
        // Let's just add a `parent_class_name` field to ClassSymbol so
        // we can resolve it here.

        // Use the parent_class_name stored in ClassSymbol (we'll add it).
        var it2 = self.symbol_table.classes.iterator();
        while (it2.next()) |entry| {
            const cls = entry.value_ptr;
            if (cls.parent_class != null) continue;
            if (cls.parent_class_name.len == 0) continue;

            var pu_buf: [128]u8 = undefined;
            const pname = cls.parent_class_name;
            const pu_len = @min(pname.len, pu_buf.len);
            for (0..pu_len) |i| pu_buf[i] = std.ascii.toUpper(pname[i]);
            const pu_upper = pu_buf[0..pu_len];

            if (self.symbol_table.classes.getPtr(pu_upper)) |parent_ptr| {
                cls.parent_class = parent_ptr;
            }
        }
    }

    fn pass1CollectDeclarations(self: *SemanticAnalyzer, program: *const ast.Program) AnalyzeError!void {
        for (program.lines) |line| {
            self.current_line_number = line.line_number;
            for (line.statements) |stmt_ptr| {
                try self.collectDeclaration(stmt_ptr);
            }
        }
    }

    fn collectDeclaration(self: *SemanticAnalyzer, stmt: *const ast.Statement) AnalyzeError!void {
        switch (stmt.data) {
            .type_decl => |td| {
                try self.collectTypeDeclaration(&td, stmt.loc);
            },
            .class => |cls| {
                try self.collectClassDeclaration(&cls, stmt.loc);
            },
            .function => |func| {
                try self.collectFunctionDeclaration(&func, stmt.loc);
            },
            .sub => |sub| {
                try self.collectSubDeclaration(&sub, stmt.loc);
            },
            .constant => |con| {
                try self.collectConstantDeclaration(&con, stmt.loc);
            },
            .dim => |dim| {
                try self.collectDimDeclaration(&dim, stmt.loc);
            },
            .global => |glob| {
                try self.collectGlobalDeclaration(&glob, stmt.loc);
            },
            .label => |lbl| {
                try self.collectLabelDeclaration(&lbl, stmt.loc);
            },
            .data_stmt => |data| {
                try self.collectDataStatement(&data);
            },
            .option => |opt| {
                self.collectOptionStatement(&opt);
            },
            // Auto-register variables from LET assignments (BASIC creates
            // variables on first use — no explicit DIM required).
            .let => |lt| {
                try self.autoRegisterVariable(lt.variable, lt.type_suffix, stmt.loc);
            },
            // Auto-register FOR loop index variables as INTEGER type.
            // FOR loop indices are always integers, not the default double.
            .for_stmt => |fs| {
                try self.autoRegisterForVariable(fs.variable, stmt.loc);
                for (fs.body) |s| try self.collectDeclaration(s);
            },
            // Auto-register READ target variables (READ A%, B%, C%).
            .read_stmt => |rs| {
                for (rs.variables) |var_name| {
                    // Extract suffix from variable name (e.g. "A%" → .percent).
                    const suffix: ?Tag = if (var_name.len > 0) switch (var_name[var_name.len - 1]) {
                        '%' => @as(?Tag, .percent),
                        '$' => @as(?Tag, .type_string),
                        '#' => @as(?Tag, .hash),
                        '!' => @as(?Tag, .exclamation),
                        '&' => @as(?Tag, .ampersand),
                        '^' => @as(?Tag, .caret),
                        '@' => @as(?Tag, .at_suffix),
                        else => @as(?Tag, null),
                    } else null;
                    try self.autoRegisterVariable(var_name, suffix, stmt.loc);
                }
            },
            // Auto-register INC/DEC target variables.
            .inc, .dec => |id| {
                try self.autoRegisterVariable(id.var_name, null, stmt.loc);
            },
            // Auto-register SWAP variables.
            .swap => |sw| {
                try self.autoRegisterVariable(sw.var1, null, stmt.loc);
                try self.autoRegisterVariable(sw.var2, null, stmt.loc);
            },
            // Recurse into blocks that may contain declarations
            .if_stmt => |ifs| {
                for (ifs.then_statements) |s| try self.collectDeclaration(s);
                for (ifs.elseif_clauses) |clause| {
                    for (clause.statements) |s| try self.collectDeclaration(s);
                }
                for (ifs.else_statements) |s| try self.collectDeclaration(s);
            },
            .for_in => |fi| {
                // Register the iterator variable.  Try to infer its type
                // from the collection's declared type so that:
                //   - Array iteration: element type (e.g. INTEGER for DIM a(10) AS INTEGER)
                //   - Hashmap iteration: STRING (keys are always strings)
                const arr_name: ?[]const u8 = switch (fi.array.data) {
                    .variable => |v| v.name,
                    .array_access => |aa| aa.name,
                    else => null,
                };

                // Detect whether the collection is a HASHMAP variable.
                var is_hashmap = false;
                if (arr_name) |aname| {
                    var hup_buf: [128]u8 = undefined;
                    const hup = upperBuf(aname, &hup_buf) orelse aname;
                    if (self.symbol_table.lookupVariable(hup)) |vsym| {
                        if (vsym.type_desc.base_type == .object and
                            std.mem.eql(u8, vsym.type_desc.object_type_name, "HASHMAP"))
                        {
                            is_hashmap = true;
                        }
                    }
                }

                const iter_type: BaseType = blk: {
                    // For hashmaps, the iterator variable is the KEY → always STRING.
                    if (is_hashmap) break :blk .string;

                    // For arrays, infer from the declared element type.
                    if (arr_name) |aname| {
                        var aup_buf: [128]u8 = undefined;
                        const aup = upperBuf(aname, &aup_buf) orelse aname;
                        if (self.symbol_table.lookupArray(aup)) |arr_sym| {
                            const ebt = arr_sym.element_type_desc.base_type;
                            if (ebt != .unknown) break :blk ebt;
                        }
                    }
                    break :blk .double;
                };
                // Register iterator variable with the inferred type.
                {
                    var iup_buf: [128]u8 = undefined;
                    const iter_upper = upperBuf(fi.variable, &iup_buf) orelse fi.variable;
                    if (!self.symbol_table.variables.contains(iter_upper)) {
                        const key = try self.allocator.dupe(u8, iter_upper);
                        try self.symbol_table.insertVariable(key, .{
                            .name = fi.variable,
                            .type_desc = TypeDescriptor.fromBase(iter_type),
                            .is_declared = false,
                            .first_use = stmt.loc,
                            .scope = if (self.in_function) Scope.makeFunction(self.current_function_name) else Scope.makeGlobal(),
                            .is_global = !self.in_function,
                        });
                    }
                }
                // Register the index/value variable if present.
                // For hashmaps: the second variable is the VALUE → STRING.
                // For arrays: the second variable is the INDEX → integer.
                if (fi.index_variable.len > 0) {
                    if (is_hashmap) {
                        // Hashmap value variable → STRING
                        var vup_buf: [128]u8 = undefined;
                        const val_upper = upperBuf(fi.index_variable, &vup_buf) orelse fi.index_variable;
                        if (!self.symbol_table.variables.contains(val_upper)) {
                            const vkey = try self.allocator.dupe(u8, val_upper);
                            try self.symbol_table.insertVariable(vkey, .{
                                .name = fi.index_variable,
                                .type_desc = TypeDescriptor.fromBase(.string),
                                .is_declared = false,
                                .first_use = stmt.loc,
                                .scope = if (self.in_function) Scope.makeFunction(self.current_function_name) else Scope.makeGlobal(),
                                .is_global = !self.in_function,
                            });
                        }
                    } else {
                        try self.autoRegisterForVariable(fi.index_variable, stmt.loc);
                    }
                }
                for (fi.body) |s| try self.collectDeclaration(s);
            },
            .while_stmt => |ws| {
                for (ws.body) |s| try self.collectDeclaration(s);
            },
            .repeat_stmt => |rs| {
                for (rs.body) |s| try self.collectDeclaration(s);
            },
            .do_stmt => |ds| {
                for (ds.body) |s| try self.collectDeclaration(s);
            },
            .case_stmt => |cs| {
                for (cs.when_clauses) |clause| {
                    for (clause.statements) |s| try self.collectDeclaration(s);
                }
                for (cs.otherwise_statements) |s| try self.collectDeclaration(s);
            },
            .try_catch => |tc| {
                for (tc.try_block) |s| try self.collectDeclaration(s);
                for (tc.catch_clauses) |clause| {
                    for (clause.block) |s| try self.collectDeclaration(s);
                }
                for (tc.finally_block) |s| try self.collectDeclaration(s);
            },
            else => {},
        }
    }

    /// Auto-register a variable if it hasn't been declared yet.
    /// Register a FOR loop index variable as INTEGER type.
    /// FOR loop indices are always integers regardless of suffix.
    fn autoRegisterForVariable(self: *SemanticAnalyzer, name: []const u8, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(name, &upper_buf) orelse name;

        if (self.in_function) {
            const func_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.current_function_name, upper_name });
            if (self.symbol_table.variables.contains(func_key)) {
                self.allocator.free(func_key);
                return;
            }
            const var_type = TypeDescriptor.fromBase(.integer);
            try self.symbol_table.insertVariable(func_key, .{
                .name = name,
                .type_desc = var_type,
                .is_declared = false,
                .first_use = loc,
                .scope = Scope.makeFunction(self.current_function_name),
                .is_global = false,
            });
            return;
        }

        const key = try self.allocator.dupe(u8, upper_name);
        if (self.symbol_table.variables.contains(key)) {
            self.allocator.free(key);
            return;
        }
        const var_type = TypeDescriptor.fromBase(.integer);
        try self.symbol_table.insertVariable(key, .{
            .name = name,
            .type_desc = var_type,
            .is_declared = false,
            .first_use = loc,
            .scope = Scope.makeGlobal(),
            .is_global = true,
        });
    }

    /// BASIC creates variables implicitly on first use. The type is
    /// inferred from the name suffix (%, $, #, !, &) or defaults to double.
    fn autoRegisterVariable(self: *SemanticAnalyzer, name: []const u8, suffix: ?Tag, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(name, &upper_buf) orelse name;

        // Build the lookup key: in a function scope, prefix with function name.
        const key = if (self.in_function) blk: {
            break :blk try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.current_function_name, upper_name });
        } else try self.allocator.dupe(u8, upper_name);

        // Skip if already registered.
        if (self.symbol_table.variables.contains(key)) {
            if (!self.in_function) self.allocator.free(key);
            return;
        }

        // Also check without function prefix for globals.
        if (self.in_function) {
            // Free the scoped key since we won't use it for global lookup.
            self.allocator.free(key);
            // Don't auto-register in function scope — variables in functions
            // should be declared with LOCAL, SHARED, or DIM. However, for
            // compatibility, register them as function-local.
            const func_key = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.current_function_name, upper_name });
            if (self.symbol_table.variables.contains(func_key)) {
                self.allocator.free(func_key);
                return;
            }
            const var_type = descriptorFromSuffix(suffix);
            try self.symbol_table.insertVariable(func_key, .{
                .name = name,
                .type_desc = var_type,
                .is_declared = false,
                .first_use = loc,
                .scope = Scope.makeFunction(self.current_function_name),
                .is_global = false,
            });
            return;
        }

        // Register as a global variable.
        const var_type = descriptorFromSuffix(suffix);
        try self.symbol_table.insertVariable(key, .{
            .name = name,
            .type_desc = var_type,
            .is_declared = false,
            .first_use = loc,
            .scope = Scope.makeGlobal(),
            .is_global = true,
        });
    }

    fn collectTypeDeclaration(self: *SemanticAnalyzer, td: *const ast.TypeDeclStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(td.type_name, &upper_buf) orelse td.type_name;

        if (self.symbol_table.types.contains(upper_name)) {
            try self.addError(.duplicate_type, "Duplicate TYPE declaration", loc);
            return;
        }

        const type_id = try self.symbol_table.allocateTypeId(upper_name);

        // Convert fields
        var fields: std.ArrayList(TypeSymbol.Field) = .empty;
        defer fields.deinit(self.allocator);

        for (td.fields) |f| {
            try fields.append(self.allocator, .{
                .name = f.name,
                .type_desc = if (f.is_built_in)
                    descriptorFromKeyword(f.built_in_type orelse .kw_double)
                else
                    TypeDescriptor.fromUDT(f.type_name, type_id),
                .type_name = f.type_name,
                .is_built_in = f.is_built_in,
            });
        }

        const owned_fields = try self.allocator.dupe(TypeSymbol.Field, fields.items);

        // ── SIMD classification ─────────────────────────────────────────
        // Analyse the fields to determine NEON eligibility, mirroring the
        // C compiler's classifySIMD() logic.  Requirements:
        //   - 2..16 fields, all built-in and the same numeric type
        //   - No strings or nested UDTs
        //   - Total size ≤ 128 bits (16 bytes)
        var detected_simd_type = td.simd_type;
        var detected_simd_info = td.simd_info;

        if (!detected_simd_info.isValid()) {
            detected_simd_info = classifySIMDFields(owned_fields);
            if (detected_simd_info.isValid()) {
                // Set legacy simd_type for backward compatibility
                const st = detected_simd_info.simd_type;
                detected_simd_type = switch (st) {
                    .v2d, .pair => .pair,
                    .v4s, .quad => .quad,
                    else => .none,
                };
            }
        }

        try self.symbol_table.types.put(try self.allocator.dupe(u8, upper_name), .{
            .name = td.type_name,
            .fields = owned_fields,
            .declaration = loc,
            .is_declared = true,
            .simd_type = detected_simd_type,
            .simd_info = detected_simd_info,
        });
    }

    /// Classify a UDT's fields for NEON SIMD eligibility.
    /// Returns a populated SIMDInfo if the type qualifies, or a default
    /// (invalid) SIMDInfo otherwise.
    fn classifySIMDFields(type_fields: []const TypeSymbol.Field) ast.TypeDeclStmt.SIMDInfo {
        const SIMDType = ast.TypeDeclStmt.SIMDType;
        var info: ast.TypeDeclStmt.SIMDInfo = .{};

        const nfields: i32 = @intCast(type_fields.len);
        if (nfields < 2 or nfields > 16) return info;

        // All fields must be built-in and the same type
        if (!type_fields[0].is_built_in) return info;
        const lane_bt = type_fields[0].type_desc.base_type;

        // Must be a numeric type — no strings, no nested UDTs
        if (!lane_bt.isNumeric()) return info;

        for (type_fields[1..]) |f| {
            if (!f.is_built_in) return info;
            if (f.type_desc.base_type != lane_bt) return info;
        }

        // Determine per-lane bit width
        const bits: i32 = @intCast(lane_bt.bitWidth());
        if (bits == 0) return info;

        const is_float = lane_bt.isFloat();

        // Populate common info
        info.lane_count = nfields;
        info.lane_bit_width = bits;
        info.is_floating_point = is_float;
        info.lane_base_type = @intFromEnum(lane_bt);

        // Classify: determine SIMDType and physical lane count
        if (nfields == 3 and bits == 32) {
            // 3 × 32-bit → pad to 4 lanes in a Q register
            info.simd_type = SIMDType.v4s_pad1;
            info.physical_lanes = 4;
            info.total_bytes = 16;
            info.is_full_q = true;
            info.is_padded = true;
        } else {
            info.physical_lanes = nfields;
            info.total_bytes = @divTrunc(nfields * bits, 8);
            info.is_full_q = (info.total_bytes == 16);
            info.is_padded = false;

            // Map to specific SIMDType
            if (bits == 64 and nfields == 2) {
                info.simd_type = SIMDType.v2d;
            } else if (bits == 32 and nfields == 4) {
                info.simd_type = SIMDType.v4s;
            } else if (bits == 32 and nfields == 2) {
                info.simd_type = SIMDType.v2s;
            } else if (bits == 16 and nfields == 8) {
                info.simd_type = SIMDType.v8h;
            } else if (bits == 16 and nfields == 4) {
                info.simd_type = SIMDType.v4h;
            } else if (bits == 8 and nfields == 16) {
                info.simd_type = SIMDType.v16b;
            } else if (bits == 8 and nfields == 8) {
                info.simd_type = SIMDType.v8b;
            } else if (bits == 32 and nfields == 3) {
                // Handled above (padded case), but keep for safety
                info.simd_type = SIMDType.v4s_pad1;
            } else {
                // Not a recognised NEON arrangement
                info.simd_type = SIMDType.none;
            }
        }

        return info;
    }

    fn collectClassDeclaration(self: *SemanticAnalyzer, cls: *const ast.ClassStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(cls.class_name, &upper_buf) orelse cls.class_name;

        if (self.symbol_table.classes.contains(upper_name)) {
            try self.addError(.duplicate_class, "Duplicate CLASS declaration", loc);
            return;
        }

        const class_id = self.symbol_table.allocateClassId();

        // ── Resolve parent class ────────────────────────────────────────
        var parent_class: ?*ClassSymbol = null;
        if (cls.parent_class_name.len > 0) {
            var parent_upper_buf: [128]u8 = undefined;
            const parent_upper = upperBuf(cls.parent_class_name, &parent_upper_buf) orelse cls.parent_class_name;
            if (self.symbol_table.classes.getPtr(parent_upper)) |p| {
                parent_class = p;
            } else {
                try self.addError(.undefined_class, "Parent CLASS not defined", loc);
            }
        }

        // ── Inherit fields from parent ──────────────────────────────────
        var fields_list: std.ArrayList(ClassSymbol.FieldInfo) = .empty;

        if (parent_class) |parent| {
            for (parent.fields) |pf| {
                try fields_list.append(self.allocator, .{
                    .name = pf.name,
                    .type_desc = pf.type_desc,
                    .offset = pf.offset,
                    .inherited = true,
                });
            }
        }

        // ── Compute field offsets for own fields ────────────────────────
        var current_offset: i32 = ClassSymbol.header_size; // Start after vtable_ptr + class_id
        if (parent_class) |parent| {
            current_offset = parent.object_size;
        }

        for (cls.fields) |field| {
            // Determine field type from the AST TypeField
            const field_type_desc: TypeDescriptor = if (field.is_built_in) blk: {
                if (field.built_in_type) |bt| {
                    break :blk descriptorFromKeyword(bt);
                }
                break :blk TypeDescriptor.fromBase(.double);
            } else blk: {
                // Check if it's a CLASS type
                var ft_upper_buf: [128]u8 = undefined;
                const ft_upper = upperBuf(field.type_name, &ft_upper_buf) orelse field.type_name;
                if (self.symbol_table.classes.contains(ft_upper)) {
                    break :blk TypeDescriptor.fromClass(field.type_name);
                }
                // Otherwise it's a UDT
                const tid = self.symbol_table.getTypeId(field.type_name) orelse -1;
                break :blk TypeDescriptor.fromUDT(field.type_name, tid);
            };

            // Compute size and alignment
            var field_size: i32 = 8; // Default: pointer-sized (strings, objects, class instances)
            var alignment: i32 = 8;
            switch (field_type_desc.base_type) {
                .integer, .uinteger, .single => {
                    field_size = 4;
                    alignment = 4;
                },
                .byte, .ubyte => {
                    field_size = 1;
                    alignment = 1;
                },
                .short, .ushort => {
                    field_size = 2;
                    alignment = 2;
                },
                else => {}, // 8 bytes for double, string, long, pointers, etc.
            }

            // Align offset
            if (alignment > 0 and @mod(current_offset, alignment) != 0) {
                current_offset += alignment - @mod(current_offset, alignment);
            }

            try fields_list.append(self.allocator, .{
                .name = field.name,
                .type_desc = field_type_desc,
                .offset = current_offset,
                .inherited = false,
            });

            current_offset += field_size;
        }

        // Pad to 8-byte alignment
        if (@mod(current_offset, 8) != 0) {
            current_offset += 8 - @mod(current_offset, 8);
        }
        const object_size = current_offset;

        // ── Inherit method slots from parent ────────────────────────────
        var methods_list: std.ArrayList(ClassSymbol.MethodInfo) = .empty;
        if (parent_class) |parent| {
            for (parent.methods) |pm| {
                try methods_list.append(self.allocator, pm);
            }
        }

        // ── Process own methods — assign vtable slots ───────────────────
        for (cls.methods) |method| {
            // Check if this overrides a parent method
            var is_override = false;
            var existing_slot: ?usize = null;

            for (methods_list.items, 0..) |existing, i| {
                if (std.ascii.eqlIgnoreCase(existing.name, method.method_name)) {
                    is_override = true;
                    existing_slot = i;
                    break;
                }
            }

            const mangled_name = try std.fmt.allocPrint(self.allocator, "{s}__{s}", .{ cls.class_name, method.method_name });

            // Build parameter type list
            var param_types_list: std.ArrayList(TypeDescriptor) = .empty;
            for (method.parameter_types, 0..) |pt, pi| {
                if (pt) |tag| {
                    _ = tag;
                    try param_types_list.append(self.allocator, descriptorFromSuffix(pt));
                } else if (pi < method.parameter_as_types.len and method.parameter_as_types[pi].len > 0) {
                    const as_name = method.parameter_as_types[pi];
                    var as_upper_buf: [128]u8 = undefined;
                    const as_upper = upperBuf(as_name, &as_upper_buf) orelse as_name;
                    if (self.symbol_table.classes.contains(as_upper)) {
                        try param_types_list.append(self.allocator, TypeDescriptor.fromClass(as_name));
                    } else {
                        try param_types_list.append(self.allocator, descriptorFromKeyword(.kw_double));
                    }
                } else {
                    try param_types_list.append(self.allocator, descriptorFromKeyword(.kw_double));
                }
            }

            // Return type
            const return_type: TypeDescriptor = if (method.has_return_type) blk: {
                if (method.return_type_as_name.len > 0) {
                    var rt_upper_buf: [128]u8 = undefined;
                    const rt_upper = upperBuf(method.return_type_as_name, &rt_upper_buf) orelse method.return_type_as_name;
                    if (self.symbol_table.classes.contains(rt_upper)) {
                        break :blk TypeDescriptor.fromClass(method.return_type_as_name);
                    }
                }
                if (method.return_type_suffix) |rts| {
                    break :blk descriptorFromKeyword(rts);
                }
                break :blk descriptorFromKeyword(.kw_double);
            } else TypeDescriptor.fromBase(.void);

            const mi = ClassSymbol.MethodInfo{
                .name = method.method_name,
                .mangled_name = mangled_name,
                .vtable_slot = if (is_override and existing_slot != null)
                    methods_list.items[existing_slot.?].vtable_slot
                else
                    @intCast(methods_list.items.len),
                .is_override = is_override,
                .origin_class = cls.class_name,
                .parameter_types = try self.allocator.dupe(TypeDescriptor, param_types_list.items),
                .return_type = return_type,
            };

            if (is_override and existing_slot != null) {
                // Override existing slot — replace the method info
                methods_list.items[existing_slot.?] = mi;
            } else {
                // New method — append to vtable
                try methods_list.append(self.allocator, mi);
            }
        }

        // ── Process constructor parameter types ─────────────────────────
        var ctor_param_types: []const TypeDescriptor = &.{};
        if (cls.constructor) |ctor| {
            var ctor_params: std.ArrayList(TypeDescriptor) = .empty;
            for (ctor.parameter_types, 0..) |pt, pi| {
                if (pt) |_| {
                    try ctor_params.append(self.allocator, descriptorFromSuffix(pt));
                } else if (pi < ctor.parameter_as_types.len and ctor.parameter_as_types[pi].len > 0) {
                    const as_name = ctor.parameter_as_types[pi];
                    var as_upper_buf2: [128]u8 = undefined;
                    const as_upper2 = upperBuf(as_name, &as_upper_buf2) orelse as_name;
                    if (self.symbol_table.classes.contains(as_upper2)) {
                        try ctor_params.append(self.allocator, TypeDescriptor.fromClass(as_name));
                    } else {
                        try ctor_params.append(self.allocator, descriptorFromKeyword(.kw_double));
                    }
                } else {
                    try ctor_params.append(self.allocator, descriptorFromKeyword(.kw_double));
                }
            }
            ctor_param_types = try self.allocator.dupe(TypeDescriptor, ctor_params.items);
        }

        const ctor_mangled = if (cls.constructor != null)
            try std.fmt.allocPrint(self.allocator, "{s}__CONSTRUCTOR", .{cls.class_name})
        else
            "";
        const dtor_mangled = if (cls.destructor != null)
            try std.fmt.allocPrint(self.allocator, "{s}__DESTRUCTOR", .{cls.class_name})
        else
            "";

        // Store with null parent_class first — the put may grow the
        // HashMap and invalidate any pointers previously obtained via
        // getPtr().  fixupClassParentPointers() resolves them after
        // all classes are registered.
        const duped_key = try self.allocator.dupe(u8, upper_name);
        try self.symbol_table.classes.put(duped_key, .{
            .name = cls.class_name,
            .class_id = class_id,
            .parent_class = null, // resolved by fixupClassParentPointers
            .parent_class_name = cls.parent_class_name,
            .declaration = loc,
            .is_declared = true,
            .object_size = object_size,
            .fields = try self.allocator.dupe(ClassSymbol.FieldInfo, fields_list.items),
            .methods = try self.allocator.dupe(ClassSymbol.MethodInfo, methods_list.items),
            .has_constructor = cls.constructor != null,
            .constructor_mangled_name = ctor_mangled,
            .constructor_param_types = ctor_param_types,
            .has_destructor = cls.destructor != null,
            .destructor_mangled_name = dtor_mangled,
        });

        // parent_class pointer is resolved later by fixupClassParentPointers()
    }

    fn collectFunctionDeclaration(self: *SemanticAnalyzer, func: *const ast.FunctionStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(func.function_name, &upper_buf) orelse func.function_name;

        if (self.symbol_table.functions.contains(upper_name)) {
            try self.addError(.function_redeclared, "Duplicate FUNCTION declaration", loc);
            return;
        }

        // Build parameter type descriptors
        var param_descs: std.ArrayList(TypeDescriptor) = .empty;
        defer param_descs.deinit(self.allocator);
        for (func.parameter_types, 0..) |pt, pi| {
            // Check if the parameter has an AS <TypeName> that refers to
            // a CLASS or UDT (e.g. "a AS Animal").
            if (pi < func.parameter_as_types.len and func.parameter_as_types[pi].len > 0) {
                const as_name = func.parameter_as_types[pi];
                // Check if pt is a real type suffix/keyword (not .identifier,
                // which the parser sets when AS is followed by a user-defined
                // name like "Animal").  If it IS a known type tag, use it
                // directly; otherwise fall through to CLASS/UDT lookup.
                const is_real_type_tag = if (pt) |tag| switch (tag) {
                    .type_int, .percent, .type_float, .exclamation, .type_double, .hash, .type_string, .type_byte, .at_suffix, .type_short, .caret, .ampersand, .kw_integer, .kw_uinteger, .kw_long, .kw_ulong, .kw_short, .kw_ushort, .kw_byte, .kw_ubyte, .kw_single, .kw_double, .kw_string_type => true,
                    else => false,
                } else false;

                if (is_real_type_tag) {
                    try param_descs.append(self.allocator, descriptorFromSuffix(pt));
                } else if (self.symbol_table.lookupClass(as_name) != null) {
                    // It's a CLASS name → class_instance pointer
                    try param_descs.append(self.allocator, TypeDescriptor.fromClass(as_name));
                } else {
                    // Uppercase the type name for UDT lookup (types are stored uppercase)
                    var as_upper_buf: [128]u8 = undefined;
                    const as_upper = upperBuf(as_name, &as_upper_buf) orelse as_name;
                    const tid = self.symbol_table.getTypeId(as_upper) orelse -1;
                    if (tid >= 0) {
                        // It's a UDT name
                        try param_descs.append(self.allocator, TypeDescriptor.fromUDT(as_name, tid));
                    } else {
                        // Unknown type name — fall back to suffix (may produce .unknown)
                        try param_descs.append(self.allocator, descriptorFromSuffix(pt));
                    }
                }
            } else {
                try param_descs.append(self.allocator, descriptorFromSuffix(pt));
            }
        }

        const return_desc = if (func.return_type_as_name.len > 0) blk_ret: {
            // Check if the return type AS name is a CLASS or UDT
            const ret_as = func.return_type_as_name;
            if (self.symbol_table.lookupClass(ret_as) != null) {
                break :blk_ret TypeDescriptor.fromClass(ret_as);
            }
            const ret_tid = self.symbol_table.getTypeId(ret_as) orelse -1;
            if (ret_tid >= 0) {
                break :blk_ret TypeDescriptor.fromUDT(ret_as, ret_tid);
            }
            // Fall back to keyword-based resolution
            if (func.has_return_as_type)
                break :blk_ret descriptorFromKeyword(func.return_type_suffix orelse .kw_double)
            else
                break :blk_ret descriptorFromSuffix(func.return_type_suffix);
        } else if (func.has_return_as_type)
            descriptorFromKeyword(func.return_type_suffix orelse .kw_double)
        else
            descriptorFromSuffix(func.return_type_suffix);

        try self.symbol_table.functions.put(try self.allocator.dupe(u8, upper_name), .{
            .name = func.function_name,
            .parameters = func.parameters,
            .parameter_type_descs = try self.allocator.dupe(TypeDescriptor, param_descs.items),
            .parameter_is_byref = func.parameter_is_byref,
            .return_type_desc = return_desc,
            .return_type_name = func.return_type_as_name,
            .definition = loc,
        });

        // Collect declarations inside the function body
        const saved_func = self.current_function_name;
        const saved_in_func = self.in_function;
        self.current_function_name = func.function_name;
        self.in_function = true;
        defer {
            self.current_function_name = saved_func;
            self.in_function = saved_in_func;
        }

        for (func.body) |s| {
            try self.collectDeclaration(s);
        }
    }

    fn collectSubDeclaration(self: *SemanticAnalyzer, sub: *const ast.SubStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(sub.sub_name, &upper_buf) orelse sub.sub_name;

        if (self.symbol_table.functions.contains(upper_name)) {
            try self.addError(.function_redeclared, "Duplicate SUB declaration", loc);
            return;
        }

        var param_descs: std.ArrayList(TypeDescriptor) = .empty;
        defer param_descs.deinit(self.allocator);
        for (sub.parameter_types, 0..) |pt, pi| {
            if (pi < sub.parameter_as_types.len and sub.parameter_as_types[pi].len > 0) {
                const as_name = sub.parameter_as_types[pi];
                const is_real_type_tag = if (pt) |tag| switch (tag) {
                    .type_int, .percent, .type_float, .exclamation, .type_double, .hash, .type_string, .type_byte, .at_suffix, .type_short, .caret, .ampersand, .kw_integer, .kw_uinteger, .kw_long, .kw_ulong, .kw_short, .kw_ushort, .kw_byte, .kw_ubyte, .kw_single, .kw_double, .kw_string_type => true,
                    else => false,
                } else false;

                if (is_real_type_tag) {
                    try param_descs.append(self.allocator, descriptorFromSuffix(pt));
                } else if (self.symbol_table.lookupClass(as_name) != null) {
                    try param_descs.append(self.allocator, TypeDescriptor.fromClass(as_name));
                } else {
                    // Uppercase the type name for UDT lookup (types are stored uppercase)
                    var as_upper_buf: [128]u8 = undefined;
                    const as_upper = upperBuf(as_name, &as_upper_buf) orelse as_name;
                    const tid = self.symbol_table.getTypeId(as_upper) orelse -1;
                    if (tid >= 0) {
                        try param_descs.append(self.allocator, TypeDescriptor.fromUDT(as_name, tid));
                    } else {
                        try param_descs.append(self.allocator, descriptorFromSuffix(pt));
                    }
                }
            } else {
                try param_descs.append(self.allocator, descriptorFromSuffix(pt));
            }
        }

        try self.symbol_table.functions.put(try self.allocator.dupe(u8, upper_name), .{
            .name = sub.sub_name,
            .parameters = sub.parameters,
            .parameter_type_descs = try self.allocator.dupe(TypeDescriptor, param_descs.items),
            .parameter_is_byref = sub.parameter_is_byref,
            .return_type_desc = TypeDescriptor.fromBase(.void),
            .definition = loc,
        });

        const saved_func = self.current_function_name;
        const saved_in_func = self.in_function;
        self.current_function_name = sub.sub_name;
        self.in_function = true;
        defer {
            self.current_function_name = saved_func;
            self.in_function = saved_in_func;
        }

        for (sub.body) |s| {
            try self.collectDeclaration(s);
        }
    }

    fn collectConstantDeclaration(self: *SemanticAnalyzer, con: *const ast.ConstantStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(con.name, &upper_buf) orelse con.name;

        if (self.symbol_table.constants.contains(upper_name)) {
            try self.addError(.type_error, "Duplicate CONSTANT declaration", loc);
            return;
        }

        // Evaluate the constant expression if it's a simple literal
        var sym = ConstantSymbol{};
        switch (con.value.data) {
            .number => |n| {
                // Check if the value is an integer
                const as_int: i64 = @intFromFloat(n.value);
                if (@as(f64, @floatFromInt(as_int)) == n.value) {
                    sym.kind = .integer_const;
                    sym.int_value = as_int;
                } else {
                    sym.kind = .double_const;
                    sym.double_value = n.value;
                }
            },
            .string_lit => |s| {
                sym.kind = .string_const;
                sym.string_value = s.value;
            },
            else => {
                // Complex expression — default to double 0
                sym.kind = .double_const;
            },
        }

        try self.symbol_table.constants.put(try self.allocator.dupe(u8, upper_name), sym);
    }

    fn collectDimDeclaration(self: *SemanticAnalyzer, dim: *const ast.DimStmt, loc: SourceLocation) AnalyzeError!void {
        for (dim.arrays) |arr| {
            var upper_buf: [128]u8 = undefined;
            const upper_name = upperBuf(arr.name, &upper_buf) orelse arr.name;

            if (arr.dimensions.len > 0) {
                // Array declaration
                if (self.symbol_table.arrays.contains(upper_name)) {
                    try self.addError(.array_redeclared, "Array already declared", loc);
                    continue;
                }

                const elem_type = if (arr.has_as_type) blk: {
                    if (arr.as_type_keyword) |kw| {
                        // For LIST OF <type> / HASHMAP OF <type> in array context,
                        // set element_type from as_type_name.
                        if ((kw == .kw_list or kw == .kw_hashmap) and arr.as_type_name.len > 0) {
                            var desc = descriptorFromKeyword(kw);
                            desc.element_type = elementTypeFromName(arr.as_type_name);
                            break :blk desc;
                        }
                        break :blk descriptorFromKeyword(kw);
                    }
                    // No keyword tag — user-defined type name (e.g. DIM a(10) AS MyType)
                    if (arr.as_type_name.len > 0) {
                        // Check if it's a known class
                        if (self.symbol_table.lookupClass(arr.as_type_name) != null) {
                            break :blk TypeDescriptor.fromClass(arr.as_type_name);
                        }
                        const tid = self.symbol_table.getTypeId(arr.as_type_name) orelse -1;
                        break :blk TypeDescriptor.fromUDT(arr.as_type_name, tid);
                    }
                    break :blk descriptorFromKeyword(.kw_double);
                } else descriptorFromSuffix(arr.type_suffix);

                try self.symbol_table.arrays.put(try self.allocator.dupe(u8, upper_name), .{
                    .name = arr.name,
                    .element_type_desc = elem_type,
                    .is_declared = true,
                    .declaration = loc,
                    .as_type_name = arr.as_type_name,
                });
            } else {
                // Scalar variable declaration
                const var_type = if (arr.has_as_type) blk: {
                    if (arr.as_type_keyword) |kw| {
                        // For LIST OF <type> / HASHMAP OF <type>, set the element_type
                        // from the as_type_name which the parser stored as the element
                        // type keyword lexeme (e.g. "INTEGER", "STRING", "DOUBLE").
                        if ((kw == .kw_list or kw == .kw_hashmap) and arr.as_type_name.len > 0) {
                            var desc = descriptorFromKeyword(kw);
                            desc.element_type = elementTypeFromName(arr.as_type_name);
                            break :blk desc;
                        }
                        break :blk descriptorFromKeyword(kw);
                    }
                    // No keyword tag — user-defined type/class name
                    // (e.g. DIM box AS StringBox, DIM p AS Point)
                    if (arr.as_type_name.len > 0) {
                        // Check if it's a known class
                        if (self.symbol_table.lookupClass(arr.as_type_name) != null) {
                            break :blk TypeDescriptor.fromClass(arr.as_type_name);
                        }
                        const tid2 = self.symbol_table.getTypeId(arr.as_type_name) orelse -1;
                        break :blk TypeDescriptor.fromUDT(arr.as_type_name, tid2);
                    }
                    break :blk descriptorFromKeyword(.kw_double);
                } else descriptorFromSuffix(arr.type_suffix);

                const key = if (self.in_function) blk: {
                    break :blk try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ self.current_function_name, upper_name });
                } else try self.allocator.dupe(u8, upper_name);

                try self.symbol_table.insertVariable(key, .{
                    .name = arr.name,
                    .type_desc = var_type,
                    .type_name = arr.as_type_name,
                    .is_declared = true,
                    .first_use = loc,
                    .scope = self.getCurrentScope(),
                    .is_global = !self.in_function,
                });
            }
        }
    }

    fn collectGlobalDeclaration(self: *SemanticAnalyzer, glob: *const ast.GlobalStmt, loc: SourceLocation) AnalyzeError!void {
        for (glob.variables) |v| {
            var upper_buf: [128]u8 = undefined;
            const upper_name = upperBuf(v.name, &upper_buf) orelse v.name;

            const var_type = if (v.has_as_type)
                descriptorFromKeyword(v.type_suffix orelse .kw_double)
            else
                descriptorFromSuffix(v.type_suffix);

            try self.symbol_table.insertVariable(try self.allocator.dupe(u8, upper_name), .{
                .name = v.name,
                .type_desc = var_type,
                .type_name = v.as_type_name,
                .is_declared = true,
                .first_use = loc,
                .scope = Scope.makeGlobal(),
                .is_global = true,
            });
        }
    }

    fn collectLabelDeclaration(self: *SemanticAnalyzer, lbl: *const ast.LabelStmt, loc: SourceLocation) AnalyzeError!void {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(lbl.label_name, &upper_buf) orelse lbl.label_name;

        if (self.symbol_table.labels.contains(upper_name)) {
            try self.addError(.duplicate_label, "Duplicate label", loc);
            return;
        }

        const label_id = self.symbol_table.next_label_id;
        self.symbol_table.next_label_id += 1;

        try self.symbol_table.labels.put(try self.allocator.dupe(u8, upper_name), .{
            .name = lbl.label_name,
            .label_id = label_id,
            .definition = loc,
        });
    }

    fn collectDataStatement(self: *SemanticAnalyzer, data: *const ast.DataStmt) AnalyzeError!void {
        for (data.values) |v| {
            try self.symbol_table.data_segment.values.append(self.symbol_table.data_segment.allocator, v);
        }
    }

    fn collectOptionStatement(self: *SemanticAnalyzer, opt: *const ast.OptionStmt) void {
        switch (opt.option_type) {
            .bitwise => self.options.bitwise_operators = true,
            .logical => self.options.bitwise_operators = false,
            .base => self.options.array_base = opt.value,
            .explicit_opt => self.options.explicit_declarations = true,
            .unicode => self.options.string_mode = .unicode,
            .ascii => self.options.string_mode = .ascii,
            .detectstring => self.options.string_mode = .detectstring,
            .error_opt => self.options.error_tracking = opt.value != 0,
            .cancellable => self.options.cancellable_loops = opt.value != 0,
            .bounds_check => self.options.bounds_checking = opt.value != 0,
            .samm => self.options.samm_enabled = opt.value != 0,
        }
    }

    // ── Pass 2: Validate ────────────────────────────────────────────────

    fn pass2Validate(self: *SemanticAnalyzer, program: *const ast.Program) !void {
        for (program.lines) |line| {
            self.current_line_number = line.line_number;
            for (line.statements) |stmt_ptr| {
                try self.validateStatement(stmt_ptr);
            }
        }

        // Check for unclosed loops
        if (self.for_stack.items.len > 0) {
            const ctx = self.for_stack.items[self.for_stack.items.len - 1];
            try self.addError(.for_without_next, "FOR without NEXT", ctx.location);
        }
        if (self.while_stack.items.len > 0) {
            const loc = self.while_stack.items[self.while_stack.items.len - 1];
            try self.addError(.while_without_wend, "WHILE without WEND", loc);
        }
        if (self.repeat_stack.items.len > 0) {
            const loc = self.repeat_stack.items[self.repeat_stack.items.len - 1];
            try self.addError(.repeat_without_until, "REPEAT without UNTIL", loc);
        }
        if (self.do_stack.items.len > 0) {
            const loc = self.do_stack.items[self.do_stack.items.len - 1];
            try self.addError(.do_without_loop, "DO without LOOP", loc);
        }

        // Check for unused variables (if configured)
        if (self.warn_unused) {
            var it = self.symbol_table.variables.iterator();
            while (it.next()) |entry| {
                if (entry.value_ptr.is_declared and !entry.value_ptr.is_used) {
                    try self.addWarning("Variable declared but never used", entry.value_ptr.first_use);
                }
            }
        }
    }

    fn validateStatement(self: *SemanticAnalyzer, stmt: *const ast.Statement) !void {
        switch (stmt.data) {
            .let => |lt| {
                try self.validateExpression(lt.value);
                for (lt.indices) |idx| {
                    try self.validateExpression(idx);
                }
            },
            .print => |pr| {
                for (pr.items) |item| {
                    try self.validateExpression(item.expr);
                }
                if (pr.format_expr) |fe| try self.validateExpression(fe);
                for (pr.using_values) |uv| try self.validateExpression(uv);
            },
            .input => {},
            .if_stmt => |ifs| {
                try self.validateExpression(ifs.condition);
                for (ifs.then_statements) |s| try self.validateStatement(s);
                for (ifs.elseif_clauses) |clause| {
                    try self.validateExpression(clause.condition);
                    for (clause.statements) |s| try self.validateStatement(s);
                }
                for (ifs.else_statements) |s| try self.validateStatement(s);
            },
            .for_stmt => |fs| {
                try self.for_stack.append(self.allocator, .{ .variable = fs.variable, .location = stmt.loc });
                try self.validateExpression(fs.start);
                try self.validateExpression(fs.end_expr);
                if (fs.step) |step| try self.validateExpression(step);
                for (fs.body) |s| try self.validateStatement(s);
                // The parser consumes NEXT as part of FOR body parsing,
                // so pop the FOR stack here rather than waiting for a
                // standalone next_stmt.
                if (self.for_stack.items.len > 0) {
                    _ = self.for_stack.pop();
                }
            },
            .next_stmt => {
                if (self.for_stack.items.len == 0) {
                    try self.addError(.next_without_for, "NEXT without FOR", stmt.loc);
                } else {
                    _ = self.for_stack.pop();
                }
            },
            .while_stmt => |ws| {
                try self.while_stack.append(self.allocator, stmt.loc);
                try self.validateExpression(ws.condition);
                for (ws.body) |s| try self.validateStatement(s);
                // The WEND token is consumed by parseWhileStatement,
                // so pop the stack here rather than waiting for a
                // separate wend AST node.
                if (self.while_stack.items.len > 0) {
                    _ = self.while_stack.pop();
                }
            },
            .wend => {
                if (self.while_stack.items.len == 0) {
                    try self.addError(.wend_without_while, "WEND without WHILE", stmt.loc);
                } else {
                    _ = self.while_stack.pop();
                }
            },
            .repeat_stmt => |rs| {
                try self.repeat_stack.append(self.allocator, stmt.loc);
                for (rs.body) |s| try self.validateStatement(s);
                if (rs.condition) |cond| try self.validateExpression(cond);
                // The UNTIL keyword is now consumed inside parseRepeatStatement,
                // so pop the repeat_stack here instead of in until_stmt handling.
                if (self.repeat_stack.items.len > 0) {
                    _ = self.repeat_stack.pop();
                }
            },
            .until_stmt => |us| {
                if (self.repeat_stack.items.len == 0) {
                    try self.addError(.until_without_repeat, "UNTIL without REPEAT", stmt.loc);
                } else {
                    _ = self.repeat_stack.pop();
                }
                try self.validateExpression(us.condition);
            },
            .do_stmt => |ds| {
                try self.do_stack.append(self.allocator, stmt.loc);
                if (ds.pre_condition) |pc| try self.validateExpression(pc);
                for (ds.body) |s| try self.validateStatement(s);
                if (ds.post_condition) |pc| try self.validateExpression(pc);
                // The LOOP keyword is now consumed inside parseDoStatement,
                // so pop the do_stack here instead of in loop_stmt handling.
                if (self.do_stack.items.len > 0) {
                    _ = self.do_stack.pop();
                }
            },
            .loop_stmt => |ls| {
                if (self.do_stack.items.len == 0) {
                    try self.addError(.loop_without_do, "LOOP without DO", stmt.loc);
                } else {
                    _ = self.do_stack.pop();
                }
                if (ls.condition) |cond| try self.validateExpression(cond);
            },
            .call => |cs| {
                for (cs.arguments) |arg| try self.validateExpression(arg);
            },
            .return_stmt => |rs| {
                if (rs.return_value) |rv| try self.validateExpression(rv);
            },
            .function => |func| {
                const saved_func = self.current_function_name;
                const saved_in_func = self.in_function;
                self.current_function_name = func.function_name;
                self.in_function = true;
                defer {
                    self.current_function_name = saved_func;
                    self.in_function = saved_in_func;
                }
                for (func.body) |s| try self.validateStatement(s);
            },
            .sub => |sub| {
                const saved_func = self.current_function_name;
                const saved_in_func = self.in_function;
                self.current_function_name = sub.sub_name;
                self.in_function = true;
                defer {
                    self.current_function_name = saved_func;
                    self.in_function = saved_in_func;
                }
                for (sub.body) |s| try self.validateStatement(s);
            },
            .goto_stmt => |gt| {
                if (gt.is_label) {
                    var upper_buf: [128]u8 = undefined;
                    const upper_name = upperBuf(gt.label, &upper_buf) orelse gt.label;
                    if (!self.symbol_table.labels.contains(upper_name)) {
                        try self.addError(.undefined_label, "Undefined label in GOTO", stmt.loc);
                    }
                }
            },
            .gosub => |gs| {
                if (gs.is_label) {
                    var upper_buf: [128]u8 = undefined;
                    const upper_name = upperBuf(gs.label, &upper_buf) orelse gs.label;
                    if (!self.symbol_table.labels.contains(upper_name)) {
                        try self.addError(.undefined_label, "Undefined label in GOSUB", stmt.loc);
                    }
                }
            },
            .dim => |dim| {
                for (dim.arrays) |arr| {
                    for (arr.dimensions) |d| try self.validateExpression(d);
                    if (arr.initializer) |init_expr| try self.validateExpression(init_expr);
                }
            },
            .try_catch => |tc| {
                for (tc.try_block) |s| try self.validateStatement(s);
                for (tc.catch_clauses) |clause| {
                    for (clause.block) |s| try self.validateStatement(s);
                }
                for (tc.finally_block) |s| try self.validateStatement(s);
            },
            .throw_stmt => |ts| {
                if (ts.error_code) |ec| try self.validateExpression(ec);
            },
            .case_stmt => |cs| {
                try self.validateExpression(cs.case_expression);
                for (cs.when_clauses) |clause| {
                    for (clause.values) |v| try self.validateExpression(v);
                    if (clause.case_is_right_expr) |e| try self.validateExpression(e);
                    if (clause.range_start) |e| try self.validateExpression(e);
                    if (clause.range_end) |e| try self.validateExpression(e);
                    for (clause.statements) |s| try self.validateStatement(s);
                }
                for (cs.otherwise_statements) |s| try self.validateStatement(s);
            },
            .for_in => |fi| {
                try self.validateExpression(fi.array);
                for (fi.body) |s| try self.validateStatement(s);
            },
            .console => |con| {
                for (con.items) |item| try self.validateExpression(item.expr);
            },
            .swap => {},
            .inc, .dec => |id| {
                if (id.amount_expr) |ae| try self.validateExpression(ae);
                for (id.indices) |idx| try self.validateExpression(idx);
            },
            .expression_stmt => |es| {
                for (es.arguments) |arg| try self.validateExpression(arg);
            },
            else => {},
        }
    }

    fn validateExpression(self: *SemanticAnalyzer, expr: *const ast.Expression) !void {
        switch (expr.data) {
            .binary => |b| {
                try self.validateExpression(b.left);
                try self.validateExpression(b.right);
            },
            .unary => |u| {
                try self.validateExpression(u.operand);
            },
            .number, .string_lit, .me, .nothing => {},
            .variable => |v| {
                // Mark variable as used
                var upper_buf: [128]u8 = undefined;
                const upper_name = upperBuf(v.name, &upper_buf) orelse v.name;
                if (self.symbol_table.lookupVariableMut(upper_name)) |sym| {
                    sym.is_used = true;
                }
                // Note: we don't error on undefined variables here in Pass 2
                // because BASIC allows implicit declaration.
            },
            .array_access => |aa| {
                for (aa.indices) |idx| try self.validateExpression(idx);
            },
            .array_binop => |ab| {
                try self.validateExpression(ab.left_array);
                try self.validateExpression(ab.right_expr);
            },
            .function_call => |fc| {
                for (fc.arguments) |arg| try self.validateExpression(arg);
            },
            .iif => |i| {
                try self.validateExpression(i.condition);
                try self.validateExpression(i.true_value);
                try self.validateExpression(i.false_value);
            },
            .member_access => |ma| {
                try self.validateExpression(ma.object);
            },
            .method_call => |mc| {
                try self.validateExpression(mc.object);
                for (mc.arguments) |arg| try self.validateExpression(arg);
            },
            .new => |n| {
                for (n.arguments) |arg| try self.validateExpression(arg);
            },
            .create => |cr| {
                for (cr.arguments) |arg| try self.validateExpression(arg);
                // Validate type exists
                var upper_buf: [128]u8 = undefined;
                const upper_name = upperBuf(cr.type_name, &upper_buf) orelse cr.type_name;
                if (self.symbol_table.lookupType(upper_name) == null) {
                    try self.addError(.undefined_type, "Undefined TYPE in CREATE expression", expr.loc);
                }
            },
            .super_call => |sc| {
                for (sc.arguments) |arg| try self.validateExpression(arg);
            },
            .is_type => |it| {
                try self.validateExpression(it.object);
            },
            .list_constructor => |lc| {
                for (lc.elements) |elem| try self.validateExpression(elem);
            },
            .registry_function => |rf| {
                for (rf.arguments) |arg| try self.validateExpression(arg);
            },
        }
    }

    // ── Type Inference ──────────────────────────────────────────────────

    /// Infer the type of an expression.
    pub fn inferExpressionType(self: *const SemanticAnalyzer, expr: *const ast.Expression) TypeDescriptor {
        return switch (expr.data) {
            .number => TypeDescriptor.fromBase(.double),
            .string_lit => TypeDescriptor.fromBase(.string),
            .variable => |v| self.inferVariableType(v.name, v.type_suffix),
            .binary => |b| self.inferBinaryType(b.left, b.op, b.right),
            .unary => |u| self.inferExpressionType(u.operand),
            .function_call => |fc| self.inferFunctionReturnType(fc.name),
            .iif => |i| self.inferExpressionType(i.true_value),
            .member_access => TypeDescriptor.fromBase(.double), // TODO: field type lookup
            .method_call => TypeDescriptor.fromBase(.double), // TODO: method return type
            .new => |n| TypeDescriptor.fromClass(n.class_name),
            .create => |cr| TypeDescriptor.fromUDT(cr.type_name, self.symbol_table.getTypeId(cr.type_name) orelse -1),
            .me => TypeDescriptor.fromBase(.class_instance),
            .nothing => TypeDescriptor.fromBase(.object),
            .is_type => TypeDescriptor.fromBase(.integer),
            .list_constructor => TypeDescriptor.fromBase(.object),
            .array_access => |aa| self.inferArrayElementType(aa.name),
            .array_binop => TypeDescriptor.fromBase(.double),
            .super_call => TypeDescriptor.fromBase(.double),
            .registry_function => TypeDescriptor.fromBase(.double),
        };
    }

    fn inferVariableType(self: *const SemanticAnalyzer, var_name: []const u8, suffix: ?Tag) TypeDescriptor {
        // Check symbol table first
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(var_name, &upper_buf) orelse var_name;
        if (self.symbol_table.lookupVariableWithFallback(upper_name, self.getCurrentScope())) |sym| {
            return sym.type_desc;
        }
        // Fall back to suffix
        if (suffix) |s| return descriptorFromSuffix(s);
        // Default: double
        return TypeDescriptor.fromBase(.double);
    }

    fn inferBinaryType(self: *const SemanticAnalyzer, left: *const ast.Expression, op: Tag, right: *const ast.Expression) TypeDescriptor {
        // Comparison operators always return integer (boolean)
        switch (op) {
            .equal, .not_equal, .less_than, .less_equal, .greater_than, .greater_equal => {
                return TypeDescriptor.fromBase(.integer);
            },
            .kw_and, .kw_or, .kw_xor, .kw_eqv, .kw_imp, .kw_not => {
                return TypeDescriptor.fromBase(.integer);
            },
            else => {},
        }
        const lt = self.inferExpressionType(left);
        const rt = self.inferExpressionType(right);
        return promoteTypes(lt, rt);
    }

    fn inferFunctionReturnType(self: *const SemanticAnalyzer, func_name: []const u8) TypeDescriptor {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(func_name, &upper_buf) orelse func_name;
        if (self.symbol_table.lookupFunction(upper_name)) |sym| {
            return sym.return_type_desc;
        }
        // Built-in functions: most return double by default
        return TypeDescriptor.fromBase(.double);
    }

    fn inferArrayElementType(self: *const SemanticAnalyzer, array_name: []const u8) TypeDescriptor {
        var upper_buf: [128]u8 = undefined;
        const upper_name = upperBuf(array_name, &upper_buf) orelse array_name;
        if (self.symbol_table.lookupArray(upper_name)) |sym| {
            return sym.element_type_desc;
        }
        return TypeDescriptor.fromBase(.double);
    }
};

// ─── Utility ────────────────────────────────────────────────────────────────

/// Convert text to uppercase in-place into a buffer. Returns null if text is too long.
fn upperBuf(text: []const u8, buf: []u8) ?[]const u8 {
    if (text.len > buf.len) return null;
    for (0..text.len) |i| {
        buf[i] = std.ascii.toUpper(text[i]);
    }
    return buf[0..text.len];
}

// ─── Tests ──────────────────────────────────────────────────────────────────

test "BaseType properties" {
    try std.testing.expect(BaseType.integer.isInteger());
    try std.testing.expect(!BaseType.integer.isFloat());
    try std.testing.expect(BaseType.integer.isNumeric());
    try std.testing.expect(!BaseType.integer.isString());

    try std.testing.expect(BaseType.double.isFloat());
    try std.testing.expect(BaseType.double.isNumeric());

    try std.testing.expect(BaseType.string.isString());
    try std.testing.expect(!BaseType.string.isNumeric());

    try std.testing.expectEqual(@as(u32, 32), BaseType.integer.bitWidth());
    try std.testing.expectEqual(@as(u32, 64), BaseType.double.bitWidth());
    try std.testing.expectEqual(@as(u32, 8), BaseType.byte.bitWidth());
}

test "BaseType QBE types" {
    try std.testing.expectEqualStrings("w", BaseType.integer.toQBEType());
    try std.testing.expectEqualStrings("l", BaseType.long.toQBEType());
    try std.testing.expectEqualStrings("d", BaseType.double.toQBEType());
    try std.testing.expectEqualStrings("s", BaseType.single.toQBEType());
    try std.testing.expectEqualStrings("l", BaseType.string.toQBEType());
    try std.testing.expectEqualStrings("ub", BaseType.byte.toQBEType());
}

test "TypeDescriptor construction" {
    const td_int = TypeDescriptor.fromBase(.integer);
    try std.testing.expect(td_int.isInteger());
    try std.testing.expect(td_int.isNumeric());
    try std.testing.expect(!td_int.isString());

    const td_udt = TypeDescriptor.fromUDT("Point", 1);
    try std.testing.expect(td_udt.isUserDefined());
    try std.testing.expectEqualStrings("Point", td_udt.udt_name);

    const td_cls = TypeDescriptor.fromClass("Animal");
    try std.testing.expect(td_cls.isClassInstance());
    try std.testing.expectEqualStrings("Animal", td_cls.class_name);
}

test "TypeDescriptor equality" {
    const a = TypeDescriptor.fromBase(.integer);
    const b = TypeDescriptor.fromBase(.integer);
    const c = TypeDescriptor.fromBase(.double);

    try std.testing.expect(a.eql(b));
    try std.testing.expect(!a.eql(c));

    const udt1 = TypeDescriptor.fromUDT("Point", 1);
    const udt2 = TypeDescriptor.fromUDT("Point", 1);
    const udt3 = TypeDescriptor.fromUDT("Rect", 2);

    try std.testing.expect(udt1.eql(udt2));
    try std.testing.expect(!udt1.eql(udt3));
}

test "baseTypeFromSuffix" {
    try std.testing.expectEqual(BaseType.integer, baseTypeFromSuffix(.type_int));
    try std.testing.expectEqual(BaseType.double, baseTypeFromSuffix(.type_double));
    try std.testing.expectEqual(BaseType.string, baseTypeFromSuffix(.type_string));
    try std.testing.expectEqual(BaseType.single, baseTypeFromSuffix(.type_float));
    try std.testing.expectEqual(BaseType.long, baseTypeFromSuffix(.ampersand));
    try std.testing.expectEqual(BaseType.byte, baseTypeFromSuffix(.type_byte));
    try std.testing.expectEqual(BaseType.double, baseTypeFromSuffix(null));
}

test "coercion rules" {
    const int_t = TypeDescriptor.fromBase(.integer);
    const dbl_t = TypeDescriptor.fromBase(.double);
    const str_t = TypeDescriptor.fromBase(.string);
    const sng_t = TypeDescriptor.fromBase(.single);

    // Same type
    try std.testing.expectEqual(CoercionResult.identical, checkCoercion(int_t, int_t));

    // Int → Double: safe
    try std.testing.expectEqual(CoercionResult.implicit_safe, checkCoercion(int_t, dbl_t));

    // Double → Int: lossy
    try std.testing.expectEqual(CoercionResult.implicit_lossy, checkCoercion(dbl_t, int_t));

    // Single → Double: safe
    try std.testing.expectEqual(CoercionResult.implicit_safe, checkCoercion(sng_t, dbl_t));

    // Double → Single: lossy
    try std.testing.expectEqual(CoercionResult.implicit_lossy, checkCoercion(dbl_t, sng_t));

    // String ↔ Numeric: incompatible
    try std.testing.expectEqual(CoercionResult.incompatible, checkCoercion(str_t, int_t));
    try std.testing.expectEqual(CoercionResult.incompatible, checkCoercion(int_t, str_t));
}

test "promoteTypes" {
    const int_t = TypeDescriptor.fromBase(.integer);
    const dbl_t = TypeDescriptor.fromBase(.double);
    const sng_t = TypeDescriptor.fromBase(.single);
    const str_t = TypeDescriptor.fromBase(.string);
    const lng_t = TypeDescriptor.fromBase(.long);

    // Int + Double → Double
    try std.testing.expectEqual(BaseType.double, promoteTypes(int_t, dbl_t).base_type);

    // Int + Single → Single
    try std.testing.expectEqual(BaseType.single, promoteTypes(int_t, sng_t).base_type);

    // Int + Long → Long
    try std.testing.expectEqual(BaseType.long, promoteTypes(int_t, lng_t).base_type);

    // Int + Int → Int
    try std.testing.expectEqual(BaseType.integer, promoteTypes(int_t, int_t).base_type);

    // String + anything → String
    try std.testing.expectEqual(BaseType.string, promoteTypes(str_t, int_t).base_type);
    try std.testing.expectEqual(BaseType.string, promoteTypes(int_t, str_t).base_type);
}

test "Scope" {
    const global = Scope.makeGlobal();
    try std.testing.expect(global.isGlobal());
    try std.testing.expect(!global.isFunction());

    const func = Scope.makeFunction("MyFunc");
    try std.testing.expect(!func.isGlobal());
    try std.testing.expect(func.isFunction());
    try std.testing.expectEqualStrings("MyFunc", func.name);
}

test "SymbolTable basic operations" {
    var st = SymbolTable.init(std.testing.allocator);
    defer st.deinit();

    // Insert and look up a variable
    try st.insertVariable("X", .{
        .name = "x",
        .type_desc = TypeDescriptor.fromBase(.integer),
        .is_declared = true,
        .is_global = true,
    });

    const found = st.lookupVariable("X");
    try std.testing.expect(found != null);
    try std.testing.expectEqualStrings("x", found.?.name);
    try std.testing.expectEqual(BaseType.integer, found.?.type_desc.base_type);

    // Not found
    try std.testing.expect(st.lookupVariable("Y") == null);
}

test "SymbolTable type IDs" {
    var st = SymbolTable.init(std.testing.allocator);
    defer st.deinit();

    const id1 = try st.allocateTypeId("POINT");
    const id2 = try st.allocateTypeId("RECT");
    const id1_again = try st.allocateTypeId("POINT");

    try std.testing.expect(id1 != id2);
    try std.testing.expectEqual(id1, id1_again);
    try std.testing.expectEqual(id1, st.getTypeId("POINT").?);
}

test "TypeSymbol findField" {
    const fields = [_]TypeSymbol.Field{
        .{ .name = "x", .type_desc = TypeDescriptor.fromBase(.double) },
        .{ .name = "y", .type_desc = TypeDescriptor.fromBase(.double) },
    };

    const ts = TypeSymbol{
        .name = "Point",
        .fields = &fields,
        .is_declared = true,
    };

    const x_field = ts.findField("X");
    try std.testing.expect(x_field != null);
    try std.testing.expectEqualStrings("x", x_field.?.name);

    const z_field = ts.findField("Z");
    try std.testing.expect(z_field == null);
}

test "CompilerOptions defaults" {
    var opts = CompilerOptions{};
    try std.testing.expectEqual(@as(i32, 1), opts.array_base);
    try std.testing.expect(opts.cancellable_loops);
    try std.testing.expect(opts.bounds_checking);
    try std.testing.expect(opts.samm_enabled);
    try std.testing.expect(!opts.bitwise_operators);
    try std.testing.expect(!opts.explicit_declarations);

    opts.reset();
    try std.testing.expectEqual(@as(i32, 1), opts.array_base);
}

test "ConstantSymbol kinds" {
    const int_const = ConstantSymbol{ .kind = .integer_const, .int_value = 42 };
    try std.testing.expectEqual(@as(i64, 42), int_const.int_value);

    const dbl_const = ConstantSymbol{ .kind = .double_const, .double_value = 3.14 };
    try std.testing.expect(dbl_const.double_value == 3.14);

    const str_const = ConstantSymbol{ .kind = .string_const, .string_value = "hello" };
    try std.testing.expectEqualStrings("hello", str_const.string_value);
}

test "ClassSymbol subclass check" {
    var parent = ClassSymbol{
        .name = "Animal",
        .class_id = 1,
        .is_declared = true,
    };

    var child = ClassSymbol{
        .name = "Dog",
        .class_id = 2,
        .parent_class = &parent,
        .is_declared = true,
    };

    try std.testing.expect(child.isSubclassOf("Animal"));
    try std.testing.expect(child.isSubclassOf("Dog"));
    try std.testing.expect(!child.isSubclassOf("Cat"));
    try std.testing.expect(!parent.isSubclassOf("Dog"));
}

test "descriptorFromKeyword" {
    const int_d = descriptorFromKeyword(.kw_integer);
    try std.testing.expectEqual(BaseType.integer, int_d.base_type);

    const str_d = descriptorFromKeyword(.kw_string_type);
    try std.testing.expectEqual(BaseType.string, str_d.base_type);

    const dbl_d = descriptorFromKeyword(.kw_double);
    try std.testing.expectEqual(BaseType.double, dbl_d.base_type);

    const lng_d = descriptorFromKeyword(.kw_long);
    try std.testing.expectEqual(BaseType.long, lng_d.base_type);

    const byt_d = descriptorFromKeyword(.kw_byte);
    try std.testing.expectEqual(BaseType.byte, byt_d.base_type);
}

test "DataSegment" {
    var ds = DataSegment.init(std.testing.allocator);
    defer ds.deinit();

    try ds.values.append(std.testing.allocator, "hello");
    try ds.values.append(std.testing.allocator, "42");
    try ds.values.append(std.testing.allocator, "3.14");

    try std.testing.expectEqual(@as(usize, 3), ds.values.items.len);
    try std.testing.expectEqualStrings("hello", ds.values.items[0]);
    try std.testing.expectEqual(@as(usize, 0), ds.read_pointer);
}

test "SemanticAnalyzer init/deinit" {
    var sa = SemanticAnalyzer.init(std.testing.allocator);
    defer sa.deinit();

    try std.testing.expect(!sa.hasErrors());
    try std.testing.expect(!sa.in_function);
    try std.testing.expect(sa.getCurrentScope().isGlobal());
}

test "SemanticAnalyzer error reporting" {
    var sa = SemanticAnalyzer.init(std.testing.allocator);
    defer sa.deinit();

    try sa.addError(.undefined_variable, "Variable X not defined", .{ .line = 10, .column = 5 });
    try sa.addWarning("Unused variable Y", .{ .line = 20, .column = 1 });

    try std.testing.expect(sa.hasErrors());
    try std.testing.expectEqual(@as(usize, 1), sa.errors.items.len);
    try std.testing.expectEqual(@as(usize, 1), sa.warnings.items.len);
    try std.testing.expectEqual(SemanticErrorType.undefined_variable, sa.errors.items[0].error_type);
}
