//
// string_pool.zig
// FasterBASIC Runtime — String Descriptor Pool (legacy stub)
//
// The string descriptor pool was migrated to the generic SammSlabPool
// infrastructure.  This file provides the legacy g_string_pool symbol
// for backward link compatibility.
//

/// Legacy placeholder — matches C `typedef struct { int _unused; } StringDescriptorPool`
const StringDescriptorPool = extern struct {
    _unused: c_int,
};

/// Legacy global — kept for link compatibility.
/// No longer functional; all operations go through g_string_desc_pool.
export var g_string_pool: StringDescriptorPool = .{ ._unused = 0 };
