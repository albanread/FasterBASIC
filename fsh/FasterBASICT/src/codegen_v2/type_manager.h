#ifndef TYPE_MANAGER_H
#define TYPE_MANAGER_H

#include <string>
#include <cstdint>
#include "../fasterbasic_semantic.h"

namespace fbc {

// Type alias for BaseType from FasterBASIC semantic analyzer
using BasicType = FasterBASIC::BaseType;

// =============================================================================
// Named Constants (previously magic numbers scattered across codegen)
// =============================================================================

/** Maximum depth for GOSUB return stack (number of nested GOSUBs supported) */
constexpr int GOSUB_STACK_DEPTH = 16;

/** Size of each GOSUB return stack entry in bytes (stores a block ID as w/int32) */
constexpr int GOSUB_ENTRY_BYTES = 4;

/** Sentinel length value for MID$() when no length is specified ("to end of string") */
constexpr int MID_TO_END_SENTINEL = INT32_MAX;

/** Default maximum number of QBE local variables per function */
constexpr int MAX_LOCAL_VARIABLES = 200;

/**
 * TypeManager - BASIC to QBE type mapping and conversions
 * 
 * Responsible for:
 * - Mapping BASIC types to QBE types (INTEGER -> w, SINGLE -> s, etc.)
 * - Type coercion and conversion
 * - Array descriptor types
 * - Function return types
 * 
 * QBE Type Reference:
 * - w: word (32-bit integer)
 * - l: long (64-bit integer / pointer)
 * - s: single precision float
 * - d: double precision float
 * - b: byte (used in data sections)
 */
class TypeManager {
public:
    TypeManager() = default;
    ~TypeManager() = default;

    // === Type Mapping ===
    
    /**
     * Get the QBE type for a BASIC type
     * @param basicType BASIC type (BaseType::INTEGER, BaseType::SINGLE, etc.)
     * @return QBE type string ("w", "l", "s", "d")
     */
    std::string getQBEType(BasicType basicType) const;
    
    /**
     * Get the QBE type for a variable symbol
     * @param varType Variable type
     * @return QBE type string
     */
    std::string getQBETypeForVariable(BasicType varType) const;
    
    /**
     * Get the QBE type for a function return
     * @param returnType Return type
     * @return QBE type string (empty for SUB/void)
     */
    std::string getQBEReturnType(BasicType returnType) const;
    
    /**
     * Get the size in bytes for a BASIC type
     * @param basicType BASIC type
     * @return Size in bytes (4 for INTEGER/SINGLE, 8 for DOUBLE/LONG/STRING)
     */
    int getTypeSize(BasicType basicType) const;
    
    /**
     * Get the natural alignment in bytes for a BASIC type.
     * Used to select the correct QBE alloc variant (alloc4, alloc8, alloc16)
     * and to compute padded UDT field offsets.
     * @param basicType BASIC type
     * @return Alignment in bytes (1, 2, 4, or 8)
     */
    int getTypeAlignment(BasicType basicType) const;
    
    /**
     * Get the size in bytes for a UDT (User-Defined Type)
     * @param udtDef The UDT type symbol definition
     * @return Total size in bytes (sum of all field sizes)
     */
    int getUDTSize(const FasterBASIC::TypeSymbol& udtDef) const;
    
    /**
     * Get the size in bytes for a UDT with nested UDT support
     * @param udtDef The UDT type symbol definition
     * @param udtMap Map of all UDT definitions for nested lookup
     * @return Total size in bytes (recursively calculated)
     */
    int getUDTSizeRecursive(const FasterBASIC::TypeSymbol& udtDef, 
                           const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap) const;
    
    /**
     * Check if a type is numeric (INTEGER, SINGLE, DOUBLE, LONG)
     * @param basicType Type to check
     * @return true if numeric
     */
    bool isNumeric(BasicType basicType) const;
    
    /**
     * Check if a type is floating point (SINGLE, DOUBLE)
     * @param basicType Type to check
     * @return true if floating point
     */
    bool isFloatingPoint(BasicType basicType) const;
    
    /**
     * Check if a type is integral (INTEGER, LONG, BYTE)
     * @param basicType Type to check
     * @return true if integral
     */
    bool isIntegral(BasicType basicType) const;
    
    /**
     * Check if a type is a string type
     * @param basicType Type to check
     * @return true if STRING
     */
    bool isString(BasicType basicType) const;

    // === Type Conversion Names ===
    
    /**
     * Get the QBE conversion operation for type coercion
     * @param fromType Source BASIC type
     * @param toType Destination BASIC type
     * @return QBE conversion operation name (e.g., "swtof", "dtosi", "stod")
     *         Returns empty string if no conversion needed
     */
    std::string getConversionOp(BasicType fromType, BasicType toType) const;
    
    /**
     * Check if conversion is needed between two types
     * @param fromType Source type
     * @param toType Destination type
     * @return true if conversion required
     */
    bool needsConversion(BasicType fromType, BasicType toType) const;
    
    /**
     * Get the intermediate type for arithmetic promotion
     * (e.g., INTEGER + SINGLE promotes to SINGLE)
     * @param type1 First operand type
     * @param type2 Second operand type
     * @return Promoted type
     */
    BasicType getPromotedType(BasicType type1, BasicType type2) const;

    // === Type Names (for debugging/comments) ===
    
    /**
     * Get a human-readable name for a BASIC type
     * @param basicType Type
     * @return Type name (e.g., "INTEGER", "SINGLE", "STRING")
     */
    std::string getTypeName(BasicType basicType) const;
    
    /**
     * Get a human-readable name for a QBE type
     * @param qbeType QBE type string
     * @return Type description (e.g., "w (32-bit int)", "s (float)")
     */
    std::string getQBETypeName(const std::string& qbeType) const;

    // === Special Types ===
    
    /**
     * Get the QBE type for array descriptors
     * Array descriptors are structs containing base pointer, dimensions, etc.
     * @return QBE type for array descriptor pointer (always "l")
     */
    std::string getArrayDescriptorType() const { return "l"; }
    
    /**
     * Get the QBE type for string descriptors
     * String descriptors contain data pointer and length
     * @return QBE type for string descriptor pointer (always "l")
     */
    std::string getStringDescriptorType() const { return "l"; }
    
    /**
     * Get the default zero value for a type
     * @param basicType Type
     * @return Default value string (e.g., "0" for INTEGER, "s_0.0" for SINGLE)
     */
    std::string getDefaultValue(BasicType basicType) const;

    // === Return Variable Name Helpers ===
    
    /**
     * Get the normalized suffix for a function return variable, based on its
     * return type. Used by FUNCTION codegen to build the implicit return
     * variable name (e.g., "MyFunc" + "_DOUBLE" -> "MyFunc_DOUBLE").
     *
     * @param returnType The BASIC return type of the function
     * @return Suffix string (e.g., "_INT", "_DOUBLE", "_STRING"), or "" for
     *         types that have no conventional suffix (VOID, UNKNOWN, etc.)
     */
    std::string getReturnVariableSuffix(BasicType returnType) const;
    
    /**
     * Build the full normalized return variable name for a FUNCTION.
     * Convenience wrapper: returns funcName + getReturnVariableSuffix(returnType).
     *
     * @param funcName  The BASIC function name (e.g., "Add")
     * @param returnType The function's return type
     * @return Full return variable name (e.g., "Add_INT")
     */
    std::string getReturnVariableName(const std::string& funcName,
                                      BasicType returnType) const;

private:
    // Internal helper: get QBE type character
    char getQBETypeChar(BasicType basicType) const;
    
    // Internal helper: map QBE conversion operation
    std::string mapConversion(char fromQBE, char toQBE) const;
};

} // namespace fbc

#endif // TYPE_MANAGER_H