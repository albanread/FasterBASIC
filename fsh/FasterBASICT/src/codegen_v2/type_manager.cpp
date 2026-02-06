#include "type_manager.h"
#include "../fasterbasic_semantic.h"

namespace fbc {

// === Type Mapping ===

std::string TypeManager::getQBEType(BasicType basicType) const {
    // Map BaseType enum from fasterbasic_semantic.h to QBE types
    switch (basicType) {
        case BasicType::BYTE:
        case BasicType::UBYTE:
        case BasicType::SHORT:
        case BasicType::USHORT:
        case BasicType::INTEGER:
        case BasicType::UINTEGER:
            return "w";  // 32-bit word
            
        case BasicType::LONG:
        case BasicType::ULONG:
            return "l";  // 64-bit long (also used for pointers)
            
        case BasicType::SINGLE:
            return "s";  // Single precision float
            
        case BasicType::DOUBLE:
            return "d";  // Double precision float
            
        case BasicType::STRING:
        case BasicType::UNICODE:
            return "l";  // String is a pointer (descriptor pointer)
            
        case BasicType::VOID:
            return "";   // No return type
            
        case BasicType::USER_DEFINED:
            return "l";  // UDT is a pointer to struct
            
        case BasicType::OBJECT:
            return "l";  // Object is a pointer to runtime object
            
        case BasicType::UNKNOWN:
        default:
            return "w";  // Default to word for unknown types
    }
}

std::string TypeManager::getQBETypeForVariable(BasicType varType) const {
    // For variables, we use the same mapping as getQBEType
    return getQBEType(varType);
}

std::string TypeManager::getQBEReturnType(BasicType returnType) const {
    // For return types, VOID returns empty string
    if (returnType == BasicType::VOID) {
        return "";
    }
    return getQBEType(returnType);
}

int TypeManager::getTypeSize(BasicType basicType) const {
    switch (basicType) {
        case BasicType::BYTE:
        case BasicType::UBYTE:
            return 1;
            
        case BasicType::SHORT:
        case BasicType::USHORT:
            return 2;
            
        case BasicType::INTEGER:
        case BasicType::UINTEGER:
        case BasicType::SINGLE:
            return 4;
            
        case BasicType::LONG:
        case BasicType::ULONG:
        case BasicType::DOUBLE:
        case BasicType::STRING:
        case BasicType::UNICODE:
        case BasicType::USER_DEFINED:
        case BasicType::OBJECT:
            return 8;  // Pointers and 64-bit types
            
        case BasicType::VOID:
            return 0;
            
        case BasicType::UNKNOWN:
        default:
            return 4;  // Default to 4 bytes
    }
}

int TypeManager::getTypeAlignment(BasicType basicType) const {
    switch (basicType) {
        case BasicType::BYTE:
        case BasicType::UBYTE:
            return 1;

        case BasicType::SHORT:
        case BasicType::USHORT:
            return 2;

        case BasicType::INTEGER:
        case BasicType::UINTEGER:
        case BasicType::SINGLE:
            return 4;

        case BasicType::LONG:
        case BasicType::ULONG:
        case BasicType::DOUBLE:
        case BasicType::STRING:
        case BasicType::UNICODE:
        case BasicType::USER_DEFINED:
        case BasicType::OBJECT:
            return 8;

        case BasicType::VOID:
        case BasicType::UNKNOWN:
        default:
            return 4;
    }
}

int TypeManager::getUDTSize(const FasterBASIC::TypeSymbol& udtDef) const {
    int totalSize = 0;
    int maxAlignment = 1;
    for (const auto& field : udtDef.fields) {
        int fieldAlign = getTypeAlignment(field.typeDesc.baseType);
        int fieldSize  = getTypeSize(field.typeDesc.baseType);
        // Track the largest field alignment for trailing padding
        if (fieldAlign > maxAlignment) maxAlignment = fieldAlign;
        // Pad current offset to the field's natural alignment
        int padding = (fieldAlign - (totalSize % fieldAlign)) % fieldAlign;
        totalSize += padding + fieldSize;
    }
    // Add trailing padding so the struct size is a multiple of the
    // largest field alignment (required for arrays of this UDT)
    int trailingPad = (maxAlignment - (totalSize % maxAlignment)) % maxAlignment;
    totalSize += trailingPad;
    return totalSize;
}

int TypeManager::getUDTSizeRecursive(const FasterBASIC::TypeSymbol& udtDef, 
                                     const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap) const {
    int totalSize = 0;
    for (const auto& field : udtDef.fields) {
        if (field.typeDesc.baseType == FasterBASIC::BaseType::USER_DEFINED) {
            // Nested UDT - recursively calculate size
            auto nestedIt = udtMap.find(field.typeDesc.udtName);
            if (nestedIt != udtMap.end()) {
                totalSize += getUDTSizeRecursive(nestedIt->second, udtMap);
            } else {
                // UDT not found, treat as 0 size (error should be caught elsewhere)
                return 0;
            }
        } else {
            totalSize += getTypeSize(field.typeDesc.baseType);
        }
    }
    return totalSize;
}

bool TypeManager::isNumeric(BasicType basicType) const {
    switch (basicType) {
        case BasicType::BYTE:
        case BasicType::UBYTE:
        case BasicType::SHORT:
        case BasicType::USHORT:
        case BasicType::INTEGER:
        case BasicType::UINTEGER:
        case BasicType::LONG:
        case BasicType::ULONG:
        case BasicType::SINGLE:
        case BasicType::DOUBLE:
            return true;
        default:
            return false;
    }
}

bool TypeManager::isFloatingPoint(BasicType basicType) const {
    return basicType == BasicType::SINGLE || basicType == BasicType::DOUBLE;
}

bool TypeManager::isIntegral(BasicType basicType) const {
    switch (basicType) {
        case BasicType::BYTE:
        case BasicType::UBYTE:
        case BasicType::SHORT:
        case BasicType::USHORT:
        case BasicType::INTEGER:
        case BasicType::UINTEGER:
        case BasicType::LONG:
        case BasicType::ULONG:
            return true;
        default:
            return false;
    }
}

bool TypeManager::isString(BasicType basicType) const {
    return basicType == BasicType::STRING || basicType == BasicType::UNICODE;
}

// === Type Conversion Names ===

std::string TypeManager::getConversionOp(BasicType fromType, BasicType toType) const {
    if (fromType == toType) {
        return "";  // No conversion needed
    }
    
    // Get QBE type characters
    char fromQBE = getQBETypeChar(fromType);
    char toQBE = getQBETypeChar(toType);
    
    if (fromQBE == toQBE) {
        return "";  // Same QBE type, no conversion
    }
    
    return mapConversion(fromQBE, toQBE);
}

bool TypeManager::needsConversion(BasicType fromType, BasicType toType) const {
    if (fromType == toType) {
        return false;
    }
    
    char fromQBE = getQBETypeChar(fromType);
    char toQBE = getQBETypeChar(toType);
    
    return fromQBE != toQBE;
}

BasicType TypeManager::getPromotedType(BasicType type1, BasicType type2) const {
    // Type promotion rules (similar to C):
    // 1. STRING stays STRING (no promotion with other types)
    // 2. DOUBLE beats everything (numeric)
    // 3. SINGLE beats integers
    // 4. LONG beats smaller integers
    // 5. INTEGER beats smaller integers
    
    // If both are STRING, stay STRING
    if (type1 == BasicType::STRING && type2 == BasicType::STRING) {
        return BasicType::STRING;
    }
    
    // If one is STRING and the other isn't, keep STRING
    // (this handles IIF with string branches)
    if (type1 == BasicType::STRING || type2 == BasicType::STRING) {
        return BasicType::STRING;
    }
    
    // If either is DOUBLE, promote to DOUBLE
    if (type1 == BasicType::DOUBLE || type2 == BasicType::DOUBLE) {
        return BasicType::DOUBLE;
    }
    
    // If either is SINGLE, promote to SINGLE
    if (type1 == BasicType::SINGLE || type2 == BasicType::SINGLE) {
        return BasicType::SINGLE;
    }
    
    // If either is LONG, promote to LONG
    if (type1 == BasicType::LONG || type2 == BasicType::LONG ||
        type1 == BasicType::ULONG || type2 == BasicType::ULONG) {
        return BasicType::LONG;
    }
    
    // If either is INTEGER, promote to INTEGER
    if (type1 == BasicType::INTEGER || type2 == BasicType::INTEGER ||
        type1 == BasicType::UINTEGER || type2 == BasicType::UINTEGER) {
        return BasicType::INTEGER;
    }
    
    // If either is SHORT, promote to INTEGER
    if (type1 == BasicType::SHORT || type2 == BasicType::SHORT ||
        type1 == BasicType::USHORT || type2 == BasicType::USHORT) {
        return BasicType::INTEGER;
    }
    
    // Default to INTEGER for BYTE operations
    return BasicType::INTEGER;
}

// === Type Names ===

std::string TypeManager::getTypeName(BasicType basicType) const {
    switch (basicType) {
        case BasicType::BYTE:           return "BYTE";
        case BasicType::UBYTE:          return "UBYTE";
        case BasicType::SHORT:          return "SHORT";
        case BasicType::USHORT:         return "USHORT";
        case BasicType::INTEGER:        return "INTEGER";
        case BasicType::UINTEGER:       return "UINTEGER";
        case BasicType::LONG:           return "LONG";
        case BasicType::ULONG:          return "ULONG";
        case BasicType::SINGLE:         return "SINGLE";
        case BasicType::DOUBLE:         return "DOUBLE";
        case BasicType::STRING:         return "STRING";
        case BasicType::UNICODE:        return "UNICODE";
        case BasicType::VOID:           return "VOID";
        case BasicType::USER_DEFINED:   return "USER_DEFINED";
        case BasicType::UNKNOWN:        return "UNKNOWN";
        default:                        return "UNKNOWN";
    }
}

std::string TypeManager::getQBETypeName(const std::string& qbeType) const {
    if (qbeType == "w") return "w (32-bit int)";
    if (qbeType == "l") return "l (64-bit int/ptr)";
    if (qbeType == "s") return "s (float)";
    if (qbeType == "d") return "d (double)";
    if (qbeType == "b") return "b (byte)";
    if (qbeType == "h") return "h (half-word)";
    return qbeType + " (unknown)";
}

// === Return Variable Name Helpers ===

std::string TypeManager::getReturnVariableSuffix(BasicType returnType) const {
    switch (returnType) {
        case BasicType::BYTE:       return "_BYTE";
        case BasicType::UBYTE:      return "_BYTE";
        case BasicType::SHORT:      return "_SHORT";
        case BasicType::USHORT:     return "_SHORT";
        case BasicType::INTEGER:    return "_INT";
        case BasicType::UINTEGER:   return "_INT";
        case BasicType::LONG:       return "_LONG";
        case BasicType::ULONG:      return "_LONG";
        case BasicType::SINGLE:     return "_FLOAT";
        case BasicType::DOUBLE:     return "_DOUBLE";
        case BasicType::STRING:
        case BasicType::UNICODE:    return "_STRING";
        default:                    return "";
    }
}

std::string TypeManager::getReturnVariableName(const std::string& funcName,
                                               BasicType returnType) const {
    std::string suffix = getReturnVariableSuffix(returnType);
    if (suffix.empty()) {
        return funcName;  // VOID / UNKNOWN – bare name
    }
    return funcName + suffix;
}

std::string TypeManager::getDefaultValue(BasicType basicType) const {
    if (isFloatingPoint(basicType)) {
        if (basicType == BasicType::SINGLE) {
            return "s_0.0";  // QBE single float zero
        } else {
            return "d_0.0";  // QBE double float zero
        }
    } else if (isIntegral(basicType)) {
        return "0";
    } else if (isString(basicType)) {
        return "0";  // Null pointer
    } else {
        return "0";  // Default to zero
    }
}

// === Private Helpers ===

char TypeManager::getQBETypeChar(BasicType basicType) const {
    std::string qbeType = getQBEType(basicType);
    if (qbeType.empty()) return 'v';  // void
    return qbeType[0];
}

std::string TypeManager::mapConversion(char fromQBE, char toQBE) const {
    // QBE conversion operations reference:
    // https://c9x.me/compile/doc/il.html#Conversions
    
    // From integer (w) conversions
    if (fromQBE == 'w') {
        if (toQBE == 'l') return "extsw";     // Sign extend word to long
        if (toQBE == 's') return "swtof";     // Signed word to float
        if (toQBE == 'd') return "INT_TO_DOUBLE_W";  // Special: needs two-step conversion
    }
    
    // From long (l) conversions
    if (fromQBE == 'l') {
        if (toQBE == 'w') return "copy";      // Truncate long to word
        if (toQBE == 's') return "sltof";     // Signed long to float
        if (toQBE == 'd') return "INT_TO_DOUBLE_L";  // Special: needs two-step conversion
    }
    
    // From float (s) conversions
    if (fromQBE == 's') {
        if (toQBE == 'w') return "stosi";     // Float to signed int
        if (toQBE == 'l') return "FLOAT_TO_LONG";  // Special: needs two-step conversion (stosi + extsw)
        if (toQBE == 'd') return "exts";      // Extend float to double
    }
    
    // From double (d) conversions
    if (fromQBE == 'd') {
        if (toQBE == 'w') return "dtosi";     // Double to signed int
        if (toQBE == 'l') return "DOUBLE_TO_LONG";  // Special: needs two-step conversion (dtosi + extsw)
        if (toQBE == 's') return "truncd";    // Truncate double to float
    }
    
    // No known conversion or void
    return "copy";  // Default to copy (may not be valid for all types)
}

} // namespace fbc