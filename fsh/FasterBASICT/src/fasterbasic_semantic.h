//
// fasterbasic_semantic.h
// FasterBASIC - Semantic Analyzer
//
// Validates AST, builds symbol tables, performs type checking, and prepares
// the program for execution. This is Phase 3 of the compilation pipeline.
//

#ifndef FASTERBASIC_SEMANTIC_H
#define FASTERBASIC_SEMANTIC_H

#include "fasterbasic_ast.h"
#include "fasterbasic_token.h"
#include "fasterbasic_options.h"
#include "../runtime/ConstantsManager.h"
#include "modular_commands.h"
#include <string>
#include <vector>
#include <map>
#include <unordered_map>
#include <set>
#include <unordered_set>
#include <stack>
#include <memory>
#include <sstream>

#include <algorithm>

namespace FasterBASIC {

// =============================================================================
// Type System
// =============================================================================

enum class VariableType {
    INT,        // Integer (%)
    FLOAT,      // Single precision (! or default)
    DOUBLE,     // Double precision (#)
    STRING,     // String ($) - byte-based
    UNICODE,    // Unicode string ($) - codepoint array (OPTION UNICODE mode)
    VOID,       // No return value (for SUB)
    USER_DEFINED, // User-defined type (TYPE...END TYPE)
    ADAPTIVE,   // Adaptive type - inferred from context (FOR EACH loop variables)
    UNKNOWN     // Not yet determined
};

inline const char* typeToString(VariableType type) {
    switch (type) {
        case VariableType::INT: return "INTEGER";
        case VariableType::FLOAT: return "FLOAT";
        case VariableType::DOUBLE: return "DOUBLE";
        case VariableType::STRING: return "STRING";
        case VariableType::USER_DEFINED: return "USER_DEFINED";
        case VariableType::UNICODE: return "UNICODE";
        case VariableType::VOID: return "VOID";
        case VariableType::ADAPTIVE: return "ADAPTIVE";
        case VariableType::UNKNOWN: return "UNKNOWN";
    }
    return "UNKNOWN";
}

// =============================================================================
// QBE-Aligned Type System (New)
// =============================================================================

// Base type categories aligned with QBE type system
enum class BaseType {
    // Numeric types (map to QBE w, l, s, d)
    BYTE,           // 8-bit signed integer (memory ops: sb)
    UBYTE,          // 8-bit unsigned integer (memory ops: ub)
    SHORT,          // 16-bit signed integer (memory ops: sh)
    USHORT,         // 16-bit unsigned integer (memory ops: uh)
    INTEGER,        // 32-bit signed integer (QBE: w)
    UINTEGER,       // 32-bit unsigned integer (QBE: w)
    LONG,           // 64-bit signed integer (QBE: l)
    ULONG,          // 64-bit unsigned integer (QBE: l)
    SINGLE,         // 32-bit float (QBE: s)
    DOUBLE,         // 64-bit float (QBE: d)
    
    // String types
    STRING,         // Byte-based string (descriptor with byte array)
    UNICODE,        // Unicode string (descriptor with codepoint array)
    
    // Composite types
    USER_DEFINED,   // User-defined TYPE (aggregate)
    POINTER,        // Pointer type (QBE: l on 64-bit)
    
    // Hidden/internal types (not directly user-visible)
    ARRAY_DESC,     // Array descriptor structure
    STRING_DESC,    // String descriptor structure
    LOOP_INDEX,     // Internal loop index (always LONG)
    
    // Runtime object types (registered in RuntimeObjectRegistry)
    OBJECT,         // Runtime object (HASHMAP, FILE, etc.) - use objectTypeName to identify
    
    // CLASS instance type
    CLASS_INSTANCE, // User-defined CLASS instance (heap-allocated, pointer semantics)
    
    // Special types
    VOID,           // No value (for SUB)
    UNKNOWN         // Not yet determined
};

// Type attributes (bitfield flags)
enum TypeAttribute : uint32_t {
    TYPE_ATTR_NONE          = 0,
    TYPE_ATTR_ARRAY         = 1 << 0,   // Is an array
    TYPE_ATTR_POINTER       = 1 << 1,   // Is a pointer
    TYPE_ATTR_CONST         = 1 << 2,   // Constant/read-only
    TYPE_ATTR_BYREF         = 1 << 3,   // Pass by reference
    TYPE_ATTR_UNSIGNED      = 1 << 4,   // Unsigned integer
    TYPE_ATTR_DYNAMIC       = 1 << 5,   // Dynamic array (REDIM)
    TYPE_ATTR_STATIC        = 1 << 6,   // Static array (fixed)
    TYPE_ATTR_HIDDEN        = 1 << 7,   // Hidden/internal type
};

// Complete type descriptor
struct TypeDescriptor {
    BaseType baseType;              // Base type
    uint32_t attributes;            // Type attribute flags
    int udtTypeId;                  // Unique ID for USER_DEFINED types (-1 if not UDT)
    std::string udtName;            // Name of UDT (empty if not USER_DEFINED)
    std::string objectTypeName;     // Name of runtime object type (empty if not OBJECT)
    std::vector<int> arrayDims;     // Array dimensions (empty if not array)
    BaseType elementType;           // For arrays/pointers: type of element
    
    // CLASS instance support
    bool isClassType = false;       // true = CLASS (heap pointer), false = TYPE (value)
    std::string className;          // Name of CLASS (populated when isClassType == true)
    
    // Constructors
    TypeDescriptor()
        : baseType(BaseType::UNKNOWN), attributes(TYPE_ATTR_NONE), udtTypeId(-1), elementType(BaseType::UNKNOWN), isClassType(false) {}
    
    explicit TypeDescriptor(BaseType bt)
        : baseType(bt), attributes(TYPE_ATTR_NONE), udtTypeId(-1), elementType(BaseType::UNKNOWN), isClassType(false) {}
    
    TypeDescriptor(BaseType bt, uint32_t attrs)
        : baseType(bt), attributes(attrs), udtTypeId(-1), elementType(BaseType::UNKNOWN), isClassType(false) {}
    
    // Static factory method for creating object types
    static TypeDescriptor makeObject(const std::string& typeName) {
        TypeDescriptor desc(BaseType::OBJECT);
        desc.objectTypeName = typeName;
        return desc;
    }
    
    // Factory: create a LIST type descriptor with optional element type
    // LIST OF INTEGER  → makeList(BaseType::INTEGER)
    // LIST OF STRING   → makeList(BaseType::STRING)
    // LIST OF ANY      → makeList()  or  makeList(BaseType::UNKNOWN)
    static TypeDescriptor makeList(BaseType elemType = BaseType::UNKNOWN) {
        TypeDescriptor desc = makeObject("LIST");
        desc.elementType = elemType;
        return desc;
    }
    
    // Factory: create a CLASS instance type descriptor
    static TypeDescriptor makeClassInstance(const std::string& clsName) {
        TypeDescriptor desc(BaseType::CLASS_INSTANCE);
        desc.isClassType = true;
        desc.className = clsName;
        return desc;
    }
    
    // Type predicates
    bool isArray() const { return (attributes & TYPE_ATTR_ARRAY) != 0; }
    bool isPointer() const { return (attributes & TYPE_ATTR_POINTER) != 0; }
    bool isConst() const { return (attributes & TYPE_ATTR_CONST) != 0; }
    bool isByRef() const { return (attributes & TYPE_ATTR_BYREF) != 0; }
    bool isUnsigned() const { return (attributes & TYPE_ATTR_UNSIGNED) != 0; }
    bool isDynamic() const { return (attributes & TYPE_ATTR_DYNAMIC) != 0; }
    bool isStatic() const { return (attributes & TYPE_ATTR_STATIC) != 0; }
    bool isHidden() const { return (attributes & TYPE_ATTR_HIDDEN) != 0; }
    bool isUserDefined() const { return baseType == BaseType::USER_DEFINED; }
    bool isObject() const { return baseType == BaseType::OBJECT; }
    bool isClassInstance() const { return baseType == BaseType::CLASS_INSTANCE || isClassType; }
    
    // LIST type predicates
    bool isList() const {
        return baseType == BaseType::OBJECT && objectTypeName == "LIST";
    }
    bool isTypedList() const {
        return isList() && elementType != BaseType::UNKNOWN;
    }
    bool isHeterogeneousList() const {
        return isList() && elementType == BaseType::UNKNOWN;
    }
    BaseType listElementType() const {
        return isList() ? elementType : BaseType::UNKNOWN;
    }
    
    bool isInteger() const {
        return baseType == BaseType::BYTE || baseType == BaseType::UBYTE ||
               baseType == BaseType::SHORT || baseType == BaseType::USHORT ||
               baseType == BaseType::INTEGER || baseType == BaseType::UINTEGER ||
               baseType == BaseType::LONG || baseType == BaseType::ULONG;
    }
    
    bool isFloat() const {
        return baseType == BaseType::SINGLE || baseType == BaseType::DOUBLE;
    }
    
    bool isNumeric() const {
        return isInteger() || isFloat();
    }
    
    bool isString() const {
        return baseType == BaseType::STRING || baseType == BaseType::UNICODE;
    }
    
    // Get bit width for numeric types
    int getBitWidth() const {
        switch (baseType) {
            case BaseType::BYTE:
            case BaseType::UBYTE:
                return 8;
            case BaseType::SHORT:
            case BaseType::USHORT:
                return 16;
            case BaseType::INTEGER:
            case BaseType::UINTEGER:
            case BaseType::SINGLE:
                return 32;
            case BaseType::LONG:
            case BaseType::ULONG:
            case BaseType::DOUBLE:
            case BaseType::POINTER:
                return 64;
            default:
                return 0;
        }
    }
    
    // Map to QBE type
    std::string toQBEType() const {
        if (isArray() || isPointer() || baseType == BaseType::ARRAY_DESC || 
            baseType == BaseType::STRING_DESC || baseType == BaseType::STRING || 
            baseType == BaseType::UNICODE) {
            return "l";  // Arrays, pointers, and strings are pointers (64-bit)
        }
        
        switch (baseType) {
            case BaseType::BYTE:
            case BaseType::UBYTE:
            case BaseType::SHORT:
            case BaseType::USHORT:
            case BaseType::INTEGER:
            case BaseType::UINTEGER:
                return "w";  // 32-bit integer
            case BaseType::LONG:
            case BaseType::ULONG:
            case BaseType::LOOP_INDEX:
            case BaseType::POINTER:
                return "l";  // 64-bit integer
            case BaseType::SINGLE:
                return "s";  // 32-bit float
            case BaseType::DOUBLE:
                return "d";  // 64-bit float
            default:
                return "l";  // Default to 64-bit pointer
        }
    }
    
    // Map to QBE memory operation suffix
    std::string toQBEMemOp() const {
        switch (baseType) {
            case BaseType::BYTE:
            case BaseType::UBYTE:
                return "b";   // Byte (for store)
            case BaseType::SHORT:
            case BaseType::USHORT:
                return "h";   // Halfword (for store)
            case BaseType::INTEGER:
            case BaseType::UINTEGER:
                return "w";   // Word
            case BaseType::LONG:
            case BaseType::ULONG:
            case BaseType::LOOP_INDEX:
                return "l";   // Long
            case BaseType::SINGLE:
                return "s";   // Single
            case BaseType::DOUBLE:
                return "d";   // Double
            default:
                return "l";   // Default
        }
    }
    
    // Map to QBE load operation suffix (handles sign/zero extension)
    std::string toQBELoadOp() const {
        switch (baseType) {
            case BaseType::BYTE:
                return "sb";  // Sign-extend byte
            case BaseType::UBYTE:
                return "ub";  // Zero-extend byte
            case BaseType::SHORT:
                return "sh";  // Sign-extend halfword
            case BaseType::USHORT:
                return "uh";  // Zero-extend halfword
            case BaseType::INTEGER:
            case BaseType::UINTEGER:
                return "w";   // Word
            case BaseType::LONG:
            case BaseType::ULONG:
            case BaseType::LOOP_INDEX:
                return "l";   // Long
            case BaseType::SINGLE:
                return "s";   // Single
            case BaseType::DOUBLE:
                return "d";   // Double
            default:
                return "l";   // Default
        }
    }
    
    // Convert to string for debugging
    std::string toString() const {
        std::ostringstream oss;
        
        // Base type
        switch (baseType) {
            case BaseType::BYTE: oss << "BYTE"; break;
            case BaseType::UBYTE: oss << "UBYTE"; break;
            case BaseType::SHORT: oss << "SHORT"; break;
            case BaseType::USHORT: oss << "USHORT"; break;
            case BaseType::INTEGER: oss << "INTEGER"; break;
            case BaseType::UINTEGER: oss << "UINTEGER"; break;
            case BaseType::LONG: oss << "LONG"; break;
            case BaseType::ULONG: oss << "ULONG"; break;
            case BaseType::SINGLE: oss << "SINGLE"; break;
            case BaseType::DOUBLE: oss << "DOUBLE"; break;
            case BaseType::STRING: oss << "STRING"; break;
            case BaseType::UNICODE: oss << "UNICODE"; break;
            case BaseType::USER_DEFINED: oss << "UDT:" << udtName; break;
            case BaseType::POINTER: oss << "POINTER"; break;
            case BaseType::ARRAY_DESC: oss << "ARRAY_DESC"; break;
            case BaseType::STRING_DESC: oss << "STRING_DESC"; break;
            case BaseType::OBJECT: oss << "OBJECT:" << objectTypeName; break;
            case BaseType::LOOP_INDEX: oss << "LOOP_INDEX"; break;
            case BaseType::CLASS_INSTANCE: oss << "CLASS:" << className; break;
            case BaseType::VOID: oss << "VOID"; break;
            case BaseType::UNKNOWN: oss << "UNKNOWN"; break;
        }
        
        // Attributes
        if (isArray()) {
            oss << "[";
            for (size_t i = 0; i < arrayDims.size(); ++i) {
                if (i > 0) oss << ",";
                oss << arrayDims[i];
            }
            oss << "]";
        }
        if (isPointer()) oss << "*";
        if (isConst()) oss << " CONST";
        if (isByRef()) oss << " BYREF";
        
        return oss.str();
    }
    
    // Equality comparison
    bool operator==(const TypeDescriptor& other) const {
        if (baseType != other.baseType) return false;
        if (isUserDefined() && udtTypeId != other.udtTypeId) return false;
        if (isObject() && objectTypeName != other.objectTypeName) return false;
        if (isArray() != other.isArray()) return false;
        if (isArray() && arrayDims != other.arrayDims) return false;
        return true;
    }
    
    bool operator!=(const TypeDescriptor& other) const {
        return !(*this == other);
    }
};

// Conversion helpers between old and new type systems
inline TypeDescriptor legacyTypeToDescriptor(VariableType legacyType) {
    switch (legacyType) {
        case VariableType::INT:
            return TypeDescriptor(BaseType::INTEGER);
        case VariableType::FLOAT:
            return TypeDescriptor(BaseType::SINGLE);
        case VariableType::DOUBLE:
            return TypeDescriptor(BaseType::DOUBLE);
        case VariableType::STRING:
            return TypeDescriptor(BaseType::STRING);
        case VariableType::UNICODE:
            return TypeDescriptor(BaseType::UNICODE);
        case VariableType::VOID:
            return TypeDescriptor(BaseType::VOID);
        case VariableType::USER_DEFINED:
            return TypeDescriptor(BaseType::USER_DEFINED);
        case VariableType::UNKNOWN:
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

inline VariableType descriptorToLegacyType(const TypeDescriptor& desc) {
    switch (desc.baseType) {
        case BaseType::BYTE:
        case BaseType::UBYTE:
        case BaseType::SHORT:
        case BaseType::USHORT:
        case BaseType::INTEGER:
        case BaseType::UINTEGER:
        case BaseType::LONG:
        case BaseType::ULONG:
        case BaseType::LOOP_INDEX:
            return VariableType::INT;
        case BaseType::SINGLE:
            return VariableType::FLOAT;
        case BaseType::DOUBLE:
            return VariableType::DOUBLE;
        case BaseType::STRING:
        case BaseType::STRING_DESC:
            return VariableType::STRING;
        case BaseType::UNICODE:
            return VariableType::UNICODE;
        case BaseType::USER_DEFINED:
            return VariableType::USER_DEFINED;
        case BaseType::VOID:
            return VariableType::VOID;
        default:
            return VariableType::UNKNOWN;
    }
}

// Convert TokenType suffix to TypeDescriptor
inline TypeDescriptor tokenSuffixToDescriptor(TokenType suffix, bool isUnsigned = false) {
    switch (suffix) {
        case TokenType::TYPE_INT:
            return TypeDescriptor(isUnsigned ? BaseType::UINTEGER : BaseType::INTEGER);
        case TokenType::TYPE_FLOAT:
            return TypeDescriptor(BaseType::SINGLE);
        case TokenType::TYPE_DOUBLE:
            return TypeDescriptor(BaseType::DOUBLE);
        case TokenType::TYPE_STRING:
            return TypeDescriptor(BaseType::STRING);
        case TokenType::TYPE_BYTE:
            return TypeDescriptor(isUnsigned ? BaseType::UBYTE : BaseType::BYTE);
        case TokenType::TYPE_SHORT:
            return TypeDescriptor(isUnsigned ? BaseType::USHORT : BaseType::SHORT);
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

// Convert AS type keyword to TypeDescriptor
inline TypeDescriptor keywordToDescriptor(TokenType keyword) {
    switch (keyword) {
        case TokenType::KEYWORD_INTEGER:
            return TypeDescriptor(BaseType::INTEGER);
        case TokenType::KEYWORD_LONG:
            return TypeDescriptor(BaseType::LONG);
        case TokenType::KEYWORD_SINGLE:
            return TypeDescriptor(BaseType::SINGLE);
        case TokenType::KEYWORD_DOUBLE:
            return TypeDescriptor(BaseType::DOUBLE);
        case TokenType::KEYWORD_STRING:
            return TypeDescriptor(BaseType::STRING);
        case TokenType::KEYWORD_BYTE:
            return TypeDescriptor(BaseType::BYTE);
        case TokenType::KEYWORD_SHORT:
            return TypeDescriptor(BaseType::SHORT);
        case TokenType::KEYWORD_UBYTE:
            return TypeDescriptor(BaseType::UBYTE);
        case TokenType::KEYWORD_USHORT:
            return TypeDescriptor(BaseType::USHORT);
        case TokenType::KEYWORD_UINTEGER:
            return TypeDescriptor(BaseType::UINTEGER);
        case TokenType::KEYWORD_ULONG:
            return TypeDescriptor(BaseType::ULONG);
        case TokenType::KEYWORD_HASHMAP:
            return TypeDescriptor::makeObject("HASHMAP");
        case TokenType::KEYWORD_LIST:
            return TypeDescriptor::makeList();  // LIST OF ANY by default
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

// Type suffix mapping
inline char getTypeSuffix(BaseType type) {
    switch (type) {
        case BaseType::INTEGER: return '%';
        case BaseType::LONG: return '&';
        case BaseType::SINGLE: return '!';
        case BaseType::DOUBLE: return '#';
        case BaseType::STRING:
        case BaseType::UNICODE: return '$';
        case BaseType::BYTE: return '@';
        case BaseType::SHORT: return '^';
        default: return '\0';
    }
}

inline BaseType baseTypeFromSuffix(char suffix) {
    switch (suffix) {
        case '%': return BaseType::INTEGER;
        case '&': return BaseType::LONG;
        case '!': return BaseType::SINGLE;
        case '#': return BaseType::DOUBLE;
        case '$': return BaseType::STRING;  // Will be STRING or UNICODE based on mode
        case '@': return BaseType::BYTE;
        case '^': return BaseType::SHORT;
        default: return BaseType::UNKNOWN;
    }
}

// =============================================================================
// Symbol Tables
// =============================================================================

// Variable symbol
// Scope information for clear scope hierarchy
struct Scope {
    enum class Type {
        GLOBAL,      // Top-level/main program scope
        FUNCTION     // Inside a SUB or FUNCTION
    };
    
    Type type;
    std::string name;        // Empty for global, function name for function scope
    int blockNumber;         // Block number within this scope (for nested blocks)
    
    Scope() : type(Type::GLOBAL), name(""), blockNumber(0) {}
    
    Scope(Type t, const std::string& n = "", int block = 0)
        : type(t), name(n), blockNumber(block) {}
    
    // Helper to create global scope
    static Scope makeGlobal(int block = 0) {
        return Scope(Type::GLOBAL, "", block);
    }
    
    // Helper to create function scope
    static Scope makeFunction(const std::string& funcName, int block = 0) {
        return Scope(Type::FUNCTION, funcName, block);
    }
    
    // Check if this is global scope
    bool isGlobal() const { return type == Type::GLOBAL; }
    
    // Check if this is function scope
    bool isFunction() const { return type == Type::FUNCTION; }
    
    // Get a string representation for debugging/lookup keys
    std::string toString() const {
        if (type == Type::GLOBAL) {
            return "global";
        } else {
            return "function:" + name;
        }
    }
    
    // Compare scopes for equality
    bool operator==(const Scope& other) const {
        return type == other.type && name == other.name && blockNumber == other.blockNumber;
    }
};

struct VariableSymbol {
    std::string name;
    TypeDescriptor typeDesc;                         // Full type descriptor with attributes
    std::string typeName;                            // For USER_DEFINED types, the type name
    bool isDeclared;                                 // Explicit declaration vs implicit
    bool isUsed;
    SourceLocation firstUse;
    Scope scope;                                     // Explicit scope tracking (global or function)
    bool isGlobal;                                   // true if declared with GLOBAL statement
    int globalOffset;                                // Slot number in global vector (only valid if isGlobal == true)

    VariableSymbol()
        : typeDesc(BaseType::UNKNOWN), isDeclared(false), isUsed(false), scope(Scope::makeGlobal()), isGlobal(false), globalOffset(-1) {}

    // Constructor from TypeDescriptor
    VariableSymbol(const std::string& n, const TypeDescriptor& td, bool decl = false)
        : name(n), typeDesc(td), isDeclared(decl), isUsed(false), scope(Scope::makeGlobal()), isGlobal(false), globalOffset(-1) {
        if (td.isUserDefined()) {
            typeName = td.udtName;
        }
    }

    // Constructor with explicit scope
    VariableSymbol(const std::string& n, const TypeDescriptor& td, const Scope& s, bool decl = false)
        : name(n), typeDesc(td), isDeclared(decl), isUsed(false), scope(s), isGlobal(false), globalOffset(-1) {
        if (td.isUserDefined()) {
            typeName = td.udtName;
        }
    }

    std::string toString() const {
        std::ostringstream oss;
        oss << name << ": " << typeDesc.toString();
        oss << " [" << scope.toString() << "]";
        if (!isDeclared) oss << " [implicit]";
        return oss.str();
    }
    
    // Legacy compatibility helpers
    std::string functionScope() const {
        return scope.isFunction() ? scope.name : "";
    }
    
    bool isInFunctionScope() const {
        return scope.isFunction();
    }

};

// Array symbol
struct ArraySymbol {
    std::string name;
    TypeDescriptor elementTypeDesc;                  // Element type descriptor
    std::vector<int> dimensions;
    bool isDeclared;
    SourceLocation declaration;
    int totalSize;                                   // Product of all dimensions
    std::string asTypeName;                          // For USER_DEFINED element types
    std::string functionScope;                       // Empty string = global, otherwise function name

    ArraySymbol()
        : elementTypeDesc(BaseType::UNKNOWN), isDeclared(false), totalSize(0), functionScope("") {}

    // Constructor from TypeDescriptor
    ArraySymbol(const std::string& n, const TypeDescriptor& elemType, const std::vector<int>& dims, bool decl = false)
        : name(n), elementTypeDesc(elemType),
          dimensions(dims), isDeclared(decl), totalSize(1), functionScope("") {
        if (elemType.isUserDefined()) {
            asTypeName = elemType.udtName;
        }
        // Calculate total size
        for (int dim : dimensions) {
            totalSize *= dim;
        }
    }

    std::string toString() const {
        std::ostringstream oss;
        oss << name << "(";
        for (size_t i = 0; i < dimensions.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << dimensions[i];
        }
        oss << ") : " << elementTypeDesc.toString();
        oss << " [" << totalSize << " elements]";
        return oss.str();
    }
    
    // Legacy compatibility method
    std::string toLegacyString() const {
        std::ostringstream oss;
        oss << name << "(";
        for (size_t i = 0; i < dimensions.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << dimensions[i];
        }
        oss << ") : " << elementTypeDesc.toString();
        oss << " [" << totalSize << " elements]";
        return oss.str();
    }
};

// Function symbol (DEF FN)
struct FunctionSymbol {
    std::string name;
    std::vector<std::string> parameters;
    std::vector<TypeDescriptor> parameterTypeDescs;  // Parameter type descriptors
    std::vector<bool> parameterIsByRef;              // BYREF flag for each parameter
    TypeDescriptor returnTypeDesc;                   // Return type descriptor
    std::string returnTypeName;                      // For USER_DEFINED return types
    SourceLocation definition;
    const Expression* body;                          // Pointer to AST node (not owned)

    FunctionSymbol()
        : returnTypeDesc(BaseType::UNKNOWN), body(nullptr) {}
    
    // Constructor from TypeDescriptors
    FunctionSymbol(const std::string& n, const std::vector<std::string>& params,
                   const std::vector<TypeDescriptor>& paramTypes, const TypeDescriptor& retType)
        : name(n), parameters(params), parameterTypeDescs(paramTypes), 
          returnTypeDesc(retType), body(nullptr) {
        // Fill byref flags
        for (const auto& td : paramTypes) {
            parameterIsByRef.push_back(td.isByRef());
        }
        if (retType.isUserDefined()) {
            returnTypeName = retType.udtName;
        }
    }

    std::string toString() const {
        std::ostringstream oss;
        oss << "FN " << name << "(";
        for (size_t i = 0; i < parameters.size(); ++i) {
            if (i > 0) oss << ", ";
            oss << parameters[i];
            if (i < parameterTypeDescs.size()) {
                oss << " : " << parameterTypeDescs[i].toString();
                if (parameterIsByRef[i]) oss << " BYREF";
            }
        }
        oss << ") : " << returnTypeDesc.toString();
        return oss.str();
    }

};

// Line number symbol
struct LineNumberSymbol {
    int lineNumber;
    size_t programLineIndex;    // Index in Program::lines
    std::vector<SourceLocation> references;  // Where referenced (GOTO, GOSUB, etc.)

    LineNumberSymbol() : lineNumber(0), programLineIndex(0) {}

    std::string toString() const {
        std::ostringstream oss;
        oss << "Line " << lineNumber << " (index " << programLineIndex << ")";
        if (!references.empty()) {
            oss << " - referenced " << references.size() << " time(s)";
        }
        return oss.str();
    }
};

// Label symbol (for :label)
struct LabelSymbol {
    std::string name;
    int labelId;                // Unique numeric ID for code generation
    size_t programLineIndex;    // Line number where defined
    SourceLocation definition;
    std::vector<SourceLocation> references;  // Where referenced (GOTO, GOSUB)

    LabelSymbol() : labelId(0), programLineIndex(0) {}

    std::string toString() const {
        std::ostringstream oss;
        oss << "Label :" << name << " (ID " << labelId << ", index " << programLineIndex << ")";
        if (!references.empty()) {
            oss << " - referenced " << references.size() << " time(s)";
        }
        return oss.str();
    }
};

// Data segment (for DATA/READ/RESTORE)
struct DataSegment {
    std::vector<std::string> values;
    size_t readPointer;
    std::unordered_map<int, size_t> restorePoints;  // Line number -> position
    std::unordered_map<std::string, size_t> labelRestorePoints;  // Label name -> position

    DataSegment() : readPointer(0) {}

    std::string toString() const {
        std::ostringstream oss;
        oss << "DATA segment: " << values.size() << " values";
        if (!restorePoints.empty()) {
            oss << ", " << restorePoints.size() << " line RESTORE points";
        }
        if (!labelRestorePoints.empty()) {
            oss << ", " << labelRestorePoints.size() << " label RESTORE points";
        }
        return oss.str();
    }
};

// Constant value (compile-time evaluated)
struct ConstantSymbol {
    enum class Type { INTEGER, DOUBLE, STRING } type;
    union {
        int64_t intValue;
        double doubleValue;
    };
    std::string stringValue;
    int index;  // Index in C++ ConstantsManager for efficient lookup

    ConstantSymbol() : type(Type::INTEGER), intValue(0), index(-1) {}
    explicit ConstantSymbol(int64_t val) : type(Type::INTEGER), intValue(val), index(-1) {}
    explicit ConstantSymbol(double val) : type(Type::DOUBLE), doubleValue(val), index(-1) {}
    explicit ConstantSymbol(const std::string& val) : type(Type::STRING), stringValue(val), index(-1) {}
};

// User-defined type symbol (TYPE/END TYPE)
struct TypeSymbol {
    struct Field {
        std::string name;
        TypeDescriptor typeDesc;                     // New: Field type descriptor
        std::string typeName;                        // Legacy: Type name (deprecated)
        VariableType builtInType;                    // Legacy: If built-in type (deprecated)
        bool isBuiltIn;                              // Legacy: true if built-in (deprecated)
        
        // New constructor from TypeDescriptor
        Field(const std::string& n, const TypeDescriptor& td)
            : name(n), typeDesc(td), typeName(td.isUserDefined() ? td.udtName : ""),
              builtInType(descriptorToLegacyType(td)), isBuiltIn(!td.isUserDefined()) {}
        
        // Legacy constructor for compatibility
        Field(const std::string& n, const std::string& tname, VariableType btype, bool builtin)
            : name(n), typeDesc(builtin ? legacyTypeToDescriptor(btype) : TypeDescriptor(BaseType::USER_DEFINED)),
              typeName(tname), builtInType(btype), isBuiltIn(builtin) {
            if (!builtin) {
                typeDesc.udtName = tname;
            }
        }
    };
    
    std::string name;
    std::vector<Field> fields;
    SourceLocation declaration;
    bool isDeclared;
    TypeDeclarationStatement::SIMDType simdType;  // SIMD type classification for ARM NEON acceleration
    TypeDeclarationStatement::SIMDInfo simdInfo;   // Full SIMD descriptor for NEON vectorization
    
    TypeSymbol() : isDeclared(false), simdType(TypeDeclarationStatement::SIMDType::NONE), simdInfo() {}
    explicit TypeSymbol(const std::string& n) : name(n), isDeclared(true), simdType(TypeDeclarationStatement::SIMDType::NONE), simdInfo() {}
    
    std::string toString() const {
        std::ostringstream oss;
        oss << "TYPE " << name << "\n";
        for (const auto& field : fields) {
            oss << "  " << field.name << " AS " << field.typeName << "\n";
        }
        oss << "END TYPE";
        return oss.str();
    }
    
    // Check if a field exists
    const Field* findField(const std::string& fieldName) const {
        for (const auto& field : fields) {
            if (field.name == fieldName) {
                return &field;
            }
        }
        return nullptr;
    }
};

// =============================================================================
// ClassSymbol — describes a CLASS declaration (fields, methods, vtable layout)
// =============================================================================

struct ClassSymbol {
    std::string name;
    int classId;                        // unique, assigned at registration time
    ClassSymbol* parentClass;           // nullptr for root classes
    SourceLocation declaration;
    bool isDeclared;

    // Object layout
    int objectSize;                     // total bytes including header + padding
    static constexpr int headerSize = 16; // 16 (vtable ptr + class_id)

    // Fields (includes inherited)
    struct FieldInfo {
        std::string name;
        TypeDescriptor typeDesc;
        int offset;                     // byte offset from object start
        bool inherited;                 // true if from parent class
    };
    std::vector<FieldInfo> fields;

    // Methods (includes inherited)
    struct MethodInfo {
        std::string name;
        std::string mangledName;        // "ClassName__MethodName"
        int vtableSlot;                 // index in method portion of vtable
        bool isOverride;                // true if overriding parent method
        std::string originClass;        // class where method was first defined
        // Signature info for validation
        std::vector<TypeDescriptor> parameterTypes;
        TypeDescriptor returnType;
    };
    std::vector<MethodInfo> methods;

    // Constructor & destructor
    bool hasConstructor;
    std::string constructorMangledName; // "ClassName__CONSTRUCTOR"
    std::vector<TypeDescriptor> constructorParamTypes;
    bool hasDestructor;
    std::string destructorMangledName;  // "ClassName__DESTRUCTOR"

    ClassSymbol()
        : classId(0), parentClass(nullptr), isDeclared(false),
          objectSize(headerSize), hasConstructor(false), hasDestructor(false) {}
    
    ClassSymbol(const std::string& n, int id)
        : name(n), classId(id), parentClass(nullptr), isDeclared(true),
          objectSize(headerSize), hasConstructor(false), hasDestructor(false),
          constructorMangledName(n + "__CONSTRUCTOR"),
          destructorMangledName(n + "__DESTRUCTOR") {}

    // Find a field by name (case-insensitive)
    const FieldInfo* findField(const std::string& fieldName) const {
        std::string upperName = fieldName;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        for (const auto& f : fields) {
            std::string upperField = f.name;
            std::transform(upperField.begin(), upperField.end(), upperField.begin(), ::toupper);
            if (upperField == upperName) return &f;
        }
        return nullptr;
    }

    // Find a method by name (case-insensitive)
    const MethodInfo* findMethod(const std::string& methodName) const {
        std::string upperName = methodName;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        for (const auto& m : methods) {
            std::string upperMethod = m.name;
            std::transform(upperMethod.begin(), upperMethod.end(), upperMethod.begin(), ::toupper);
            if (upperMethod == upperName) return &m;
        }
        return nullptr;
    }

    // Total number of method slots (for vtable sizing)
    int getMethodCount() const { return static_cast<int>(methods.size()); }

    // Check if this class is a subclass of another
    bool isSubclassOf(const ClassSymbol* other) const {
        if (!other) return false;
        const ClassSymbol* current = this;
        while (current) {
            if (current->classId == other->classId) return true;
            current = current->parentClass;
        }
        return false;
    }
};

// Complete symbol table
struct SymbolTable {
    std::unordered_map<std::string, VariableSymbol> variables;
    std::unordered_map<std::string, ArraySymbol> arrays;
    std::unordered_map<std::string, FunctionSymbol> functions;
    std::unordered_map<std::string, TypeSymbol> types;  // User-defined types (TYPE/END TYPE)
    std::unordered_map<std::string, ClassSymbol> classes;  // CLASS declarations
    std::unordered_map<int, LineNumberSymbol> lineNumbers;
    std::unordered_map<std::string, LabelSymbol> labels;  // Symbolic labels
    std::unordered_map<std::string, ConstantSymbol> constants;  // Compile-time constants
    DataSegment dataSegment;
    int nextLabelId = 10000;  // Start label IDs at 10000 to avoid conflicts with line numbers
    int arrayBase = 1;  // OPTION BASE: 0 or 1 (default 1 to match Lua arrays)
    int globalVariableCount = 0;  // Number of GLOBAL variables (for runtime vector allocation)
    CompilerOptions::StringMode stringMode = CompilerOptions::StringMode::DETECTSTRING;  // OPTION ASCII/UNICODE/DETECTSTRING
    bool errorTracking = true;  // OPTION ERROR: if true, emit _LINE tracking for error messages
    bool cancellableLoops = true;  // OPTION CANCELLABLE: if true, inject script cancellation checks in loops
    bool eventsUsed = false;  // EVENT DETECTION: if true, program uses ON EVENT statements and needs event processing code
    bool forceYieldEnabled = false;  // OPTION FORCE_YIELD: if true, enable quasi-preemptive handler yielding
    int forceYieldBudget = 10000;  // OPTION FORCE_YIELD budget: instructions before forced yield
    bool sammEnabled = true;  // OPTION SAMM: if true, emit SAMM scope enter/exit calls for automatic memory management
    
    // Type registry for UDT type IDs (new type system)
    std::unordered_map<std::string, int> typeNameToId;  // UDT name -> unique type ID
    int nextTypeId = 1;  // Next available UDT type ID
    
    // Class ID allocation for CLASS system
    int nextClassId = 1;  // 0 is reserved for NOTHING
    
    // Allocate a new type ID for a UDT
    int allocateTypeId(const std::string& typeName) {
        auto it = typeNameToId.find(typeName);
        if (it != typeNameToId.end()) {
            return it->second;  // Already allocated
        }
        int id = nextTypeId++;
        typeNameToId[typeName] = id;
        return id;
    }
    
    // Get type ID for a UDT (returns -1 if not found)
    int getTypeId(const std::string& typeName) const {
        auto it = typeNameToId.find(typeName);
        return (it != typeNameToId.end()) ? it->second : -1;
    }

    // Allocate a new class ID
    int allocateClassId(const std::string& className) {
        int id = nextClassId++;
        return id;
    }
    
    // Look up a class by name (case-insensitive)
    ClassSymbol* lookupClass(const std::string& name) {
        std::string upperName = name;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        auto it = classes.find(upperName);
        if (it != classes.end()) return &it->second;
        return nullptr;
    }
    
    const ClassSymbol* lookupClass(const std::string& name) const {
        std::string upperName = name;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        auto it = classes.find(upperName);
        if (it != classes.end()) return &it->second;
        return nullptr;
    }
    
    std::string toString() const;
    
    // Helper: Generate a scope-qualified key for symbol table lookup
    // Format: "global::varName" or "function:funcName::varName"
    static std::string makeScopeKey(const std::string& varName, const Scope& scope) {
        if (scope.isGlobal()) {
            return "global::" + varName;
        } else {
            return "function:" + scope.name + "::" + varName;
        }
    }
    
    // Helper: Insert a variable with scope-qualified key
    void insertVariable(const std::string& varName, const VariableSymbol& symbol) {
        std::string key = makeScopeKey(varName, symbol.scope);
        variables[key] = symbol;
    }
    
    // Helper: Lookup a variable in a specific scope
    VariableSymbol* lookupVariable(const std::string& varName, const Scope& scope) {
        std::string key = makeScopeKey(varName, scope);
        auto it = variables.find(key);
        return (it != variables.end()) ? &it->second : nullptr;
    }
    
    const VariableSymbol* lookupVariable(const std::string& varName, const Scope& scope) const {
        std::string key = makeScopeKey(varName, scope);
        auto it = variables.find(key);
        return (it != variables.end()) ? &it->second : nullptr;
    }
    
    // Helper: Lookup a variable with fallback to global scope
    // First tries the given scope, then tries global if not found
    VariableSymbol* lookupVariableWithFallback(const std::string& varName, const Scope& scope) {
        // Try function scope first
        if (scope.isFunction()) {
            VariableSymbol* result = lookupVariable(varName, scope);
            if (result) return result;
        }
        // Fall back to global scope
        return lookupVariable(varName, Scope::makeGlobal());
    }
    
    const VariableSymbol* lookupVariableWithFallback(const std::string& varName, const Scope& scope) const {
        // Try function scope first
        if (scope.isFunction()) {
            const VariableSymbol* result = lookupVariable(varName, scope);
            if (result) return result;
        }
        // Fall back to global scope
        return lookupVariable(varName, Scope::makeGlobal());
    }
    
    // Legacy compatibility: lookup variable by name only (tries scoped keys first, then flat key)
    // This allows gradual migration from flat keys to scoped keys
    VariableSymbol* lookupVariableLegacy(const std::string& varName, const std::string& functionScope = "") {
        // Try new scoped lookup first
        if (!functionScope.empty()) {
            // Try function scope
            Scope funcScope = Scope::makeFunction(functionScope);
            VariableSymbol* result = lookupVariable(varName, funcScope);
            if (result) return result;
        }
        // Try global scope
        VariableSymbol* result = lookupVariable(varName, Scope::makeGlobal());
        if (result) return result;
        
        // Fall back to old flat key lookup (for backward compatibility)
        auto it = variables.find(varName);
        return (it != variables.end()) ? &it->second : nullptr;
    }
    
    const VariableSymbol* lookupVariableLegacy(const std::string& varName, const std::string& functionScope = "") const {
        // Try new scoped lookup first
        if (!functionScope.empty()) {
            // Try function scope
            Scope funcScope = Scope::makeFunction(functionScope);
            const VariableSymbol* result = lookupVariable(varName, funcScope);
            if (result) return result;
        }
        // Try global scope
        const VariableSymbol* result = lookupVariable(varName, Scope::makeGlobal());
        if (result) return result;
        
        // Fall back to old flat key lookup (for backward compatibility)
        auto it = variables.find(varName);
        return (it != variables.end()) ? &it->second : nullptr;
    }
    
    // Helper: Determine string type based on stringMode and literal content
    // Returns STRING for ASCII, UNICODE for non-ASCII (in DETECTSTRING mode)
    BaseType getStringTypeForLiteral(bool hasNonASCII) const {
        switch (stringMode) {
            case CompilerOptions::StringMode::ASCII:
                // ASCII mode: all strings are STRING (non-ASCII is error, caught by parser)
                return BaseType::STRING;
            case CompilerOptions::StringMode::UNICODE:
                // Unicode mode: all strings are UNICODE
                return BaseType::UNICODE;
            case CompilerOptions::StringMode::DETECTSTRING:
                // Detect mode: ASCII if all bytes < 128, else UNICODE
                return hasNonASCII ? BaseType::UNICODE : BaseType::STRING;
            default:
                return BaseType::STRING;
        }
    }
};

// =============================================================================
// Errors and Warnings
// =============================================================================

enum class SemanticErrorType {
    UNDEFINED_LINE,
    UNDEFINED_LABEL,
    DUPLICATE_LABEL,
    UNDEFINED_VARIABLE,
    UNDEFINED_ARRAY,
    UNDEFINED_FUNCTION,
    ARRAY_NOT_DECLARED,
    ARRAY_REDECLARED,
    FUNCTION_REDECLARED,
    TYPE_MISMATCH,
    WRONG_DIMENSION_COUNT,
    INVALID_ARRAY_INDEX,
    CONTROL_FLOW_MISMATCH,
    NEXT_WITHOUT_FOR,
    WEND_WITHOUT_WHILE,
    UNTIL_WITHOUT_REPEAT,
    LOOP_WITHOUT_DO,
    FOR_WITHOUT_NEXT,
    WHILE_WITHOUT_WEND,
    DO_WITHOUT_LOOP,
    REPEAT_WITHOUT_UNTIL,
    RETURN_WITHOUT_GOSUB,
    DUPLICATE_LINE_NUMBER,
    // Type-related errors
    UNDEFINED_TYPE,
    DUPLICATE_TYPE,
    DUPLICATE_FIELD,
    UNDEFINED_FIELD,
    CIRCULAR_TYPE_DEPENDENCY,
    INVALID_TYPE_FIELD,
    TYPE_ERROR,
    ARGUMENT_COUNT_MISMATCH,
    // CLASS-related errors
    UNDEFINED_CLASS,
    DUPLICATE_CLASS,
    CIRCULAR_INHERITANCE,
    CLASS_ERROR
};

struct SemanticError {
    SemanticErrorType type;
    std::string message;
    SourceLocation location;

    SemanticError(SemanticErrorType t, const std::string& msg, const SourceLocation& loc)
        : type(t), message(msg), location(loc) {}

    std::string toString() const {
        return "Semantic Error at " + location.toString() + ": " + message;
    }
};

struct SemanticWarning {
    std::string message;
    SourceLocation location;

    SemanticWarning(const std::string& msg, const SourceLocation& loc)
        : message(msg), location(loc) {}

    std::string toString() const {
        return "Warning at " + location.toString() + ": " + message;
    }
};

// =============================================================================
// Semantic Analyzer
// =============================================================================

class SemanticAnalyzer {
public:
    SemanticAnalyzer();
    explicit SemanticAnalyzer(const ModularCommands::CommandRegistry* registry);
    ~SemanticAnalyzer();

    // Main analysis entry point
    // Takes compiler options from OPTION statements (already collected by parser)
    bool analyze(Program& program, const CompilerOptions& options);

    // Get results
    const SymbolTable& getSymbolTable() const { return m_symbolTable; }
    const std::vector<SemanticError>& getErrors() const { return m_errors; }
    const std::vector<SemanticWarning>& getWarnings() const { return m_warnings; }
    bool hasErrors() const { return !m_errors.empty(); }
    ConstantsManager& getConstantsManager() { return m_constantsManager; }
    
    // Scoped variable lookup helper for codegen
    // Returns nullptr if variable not found
    // Searches local scope first (if functionScope provided), then global scope
    const VariableSymbol* lookupVariableScoped(const std::string& varName, 
                                                const std::string& functionScope = "") const;
    
    // Check if a variable is a FOR loop variable (suffix-agnostic)
    // FOR loop variables are tracked in the symbol table with normalized names
    bool isForLoopVariable(const std::string& varName) const {
        // Strip suffix to get base name
        std::string baseName = stripTypeSuffix(varName);
        
        // Check if this variable exists in the symbol table as an integer type
        // (FOR variables are always integers based on OPTION FOR setting)
        auto it = m_symbolTable.variables.find(baseName + "_INT");
        if (it != m_symbolTable.variables.end()) {
            return it->second.typeDesc.baseType == BaseType::INTEGER;
        }
        
        it = m_symbolTable.variables.find(baseName + "_LONG");
        if (it != m_symbolTable.variables.end()) {
            return it->second.typeDesc.baseType == BaseType::LONG;
        }
        
        return false;
    }

    // Helper to get the correct integer suffix based on OPTION FOR setting
    // Returns text suffix used by parser mangling (_INT or _LONG)
    std::string getForLoopIntegerSuffix() const;

    // Ensure predefined constants are loaded (safe to call multiple times)
    void ensureConstantsLoaded();

    // Load functions from command registry
    void loadFromCommandRegistry(const ModularCommands::CommandRegistry& registry);
    const ConstantsManager& getConstantsManager() const { return m_constantsManager; }

    // Configuration
    void setStrictMode(bool strict) { m_strictMode = strict; }
    void setWarnUnused(bool warn) { m_warnUnused = warn; }
    void setRequireExplicitDim(bool require) { m_requireExplicitDim = require; }

    // Register DATA labels (from preprocessor) so RESTORE can find them
    void registerDataLabels(const std::map<std::string, int>& dataLabels);

    // Inject runtime constants (from host environment like FBRunner3)
    // These appear as if they were CONSTANT statements in the source
    void injectRuntimeConstant(const std::string& name, int64_t value);
    void injectRuntimeConstant(const std::string& name, double value);
    void injectRuntimeConstant(const std::string& name, const std::string& value);

    // Report generation
    std::string generateReport() const;

    // Constant expression evaluation (compile-time)
    // Uses FasterBASIC::ConstantValue from ConstantsManager.h
    FasterBASIC::ConstantValue evaluateConstantExpression(const Expression& expr);

private:
    // Two-pass analysis
    void pass1_collectDeclarations(Program& program);
    void pass2_validate(Program& program);

    // Pass 1: Declaration collection
    void collectLineNumbers(Program& program);
    void collectLabels(Program& program);
    void collectLabelsRecursive(const std::vector<StatementPtr>& statements, int fallbackLineNumber);
    void collectOptionStatements(Program& program);
    void collectGlobalStatements(Program& program);
    void collectDimStatements(Program& program);
    void collectDefStatements(Program& program);
    void collectFunctionAndSubStatements(Program& program);
    void collectDataStatements(Program& program);
    void collectForEachVariables(Program& program);
    void collectConstantStatements(Program& program);
    void collectTypeDeclarations(Program& program);  // Collect TYPE/END TYPE declarations
    void collectClassDeclarations(Program& program);  // Collect CLASS/END CLASS declarations
    void collectTimerHandlers(Program& program);  // Collect AFTER/EVERY handlers in pass1

    // Recursively walk a statement list and process any DIM statements found,
    // including those nested inside FOR/IF/WHILE/DO bodies.
    void collectDimStatementsRecursive(const std::vector<StatementPtr>& stmts);

    void processDimStatement(const DimStatement& stmt);
    void processFunctionStatement(const FunctionStatement& stmt);
    void processSubStatement(const SubStatement& stmt);
    void processDefStatement(const DefStatement& stmt);
    void processDataStatement(const DataStatement& stmt, int lineNumber,
                             const std::string& dataLabel);
    void processConstantStatement(const ConstantStatement& stmt);
    void processClassStatement(const ClassStatement& stmt);
    void processTypeDeclarationStatement(const TypeDeclarationStatement* stmt);

    // Pass 2: Validation
    void validateProgramLine(const ProgramLine& line);
    void validateStatement(const Statement& stmt);
    void validateExpression(const Expression& expr);
    
    // Array operation analysis
    void analyzeArrayExpression(const Expression* expr, TypeDeclarationStatement::SIMDType targetSIMDType);

    // Statement validation
    void validatePrintStatement(const PrintStatement& stmt);
    void validateConsoleStatement(const ConsoleStatement& stmt);
    void validateInputStatement(const InputStatement& stmt);
    void validateLetStatement(const LetStatement& stmt);
    void validateSliceAssignStatement(const SliceAssignStatement& stmt);
    void validateGotoStatement(const GotoStatement& stmt);
    void validateGosubStatement(const GosubStatement& stmt);
    void validateOnGotoStatement(const OnGotoStatement& stmt);
    void validateOnGosubStatement(const OnGosubStatement& stmt);
    void validateIfStatement(const IfStatement& stmt);
    void validateForStatement(const ForStatement& stmt);
    void validateForInStatement(ForInStatement& stmt);
    void validateNextStatement(const NextStatement& stmt);
    void validateWhileStatement(const WhileStatement& stmt);
    void validateWendStatement(const WendStatement& stmt);
    void validateRepeatStatement(const RepeatStatement& stmt);
    void validateUntilStatement(const UntilStatement& stmt);
    void validateDoStatement(const DoStatement& stmt);
    void validateLoopStatement(const LoopStatement& stmt);
    void validateReadStatement(const ReadStatement& stmt);
    void validateRestoreStatement(const RestoreStatement& stmt);
    void validateExpressionStatement(const ExpressionStatement& stmt);
    void validateOnEventStatement(const OnEventStatement& stmt);
    
    // Timer event statement validation
    void validateAfterStatement(const AfterStatement& stmt);
    void validateEveryStatement(const EveryStatement& stmt);
    void validateAfterFramesStatement(const AfterFramesStatement& stmt);
    void validateEveryFrameStatement(const EveryFrameStatement& stmt);
    void validateRunStatement(const RunStatement& stmt);
    void validateTimerStopStatement(const TimerStopStatement& stmt);
    void validateTimerIntervalStatement(const TimerIntervalStatement& stmt);

    // Exception handling statement validation
    void validateTryCatchStatement(const TryCatchStatement& stmt);
    void validateThrowStatement(const ThrowStatement& stmt);

    // Expression validation and type inference
    VariableType inferExpressionType(const Expression& expr);
    VariableType inferBinaryExpressionType(const BinaryExpression& expr);
    VariableType inferUnaryExpressionType(const UnaryExpression& expr);
    VariableType inferVariableType(const VariableExpression& expr);
    VariableType inferArrayAccessType(const ArrayAccessExpression& expr);
    VariableType inferFunctionCallType(const FunctionCallExpression& expr);
    VariableType inferRegistryFunctionType(const RegistryFunctionExpression& expr);
    VariableType inferMemberAccessType(const MemberAccessExpression& expr);

    // Type checking
    void checkTypeCompatibility(VariableType expected, VariableType actual,
                               const SourceLocation& loc, const std::string& context);
    VariableType promoteTypes(VariableType left, VariableType right);
    bool isNumericType(VariableType type);

    // New TypeDescriptor-based type inference (Phase 2)
    TypeDescriptor inferExpressionTypeD(const Expression& expr);
    TypeDescriptor inferBinaryExpressionTypeD(const BinaryExpression& expr);
    TypeDescriptor inferUnaryExpressionTypeD(const UnaryExpression& expr);
    TypeDescriptor inferVariableTypeD(const VariableExpression& expr);
    TypeDescriptor inferArrayAccessTypeD(const ArrayAccessExpression& expr);
    TypeDescriptor inferFunctionCallTypeD(const FunctionCallExpression& expr);
    TypeDescriptor inferRegistryFunctionTypeD(const RegistryFunctionExpression& expr);
    TypeDescriptor inferMemberAccessTypeD(const MemberAccessExpression& expr);

    // Coercion and type checking with TypeDescriptor
    enum class CoercionResult {
        IDENTICAL,          // Types are identical, no conversion needed
        IMPLICIT_SAFE,      // Implicit widening conversion (e.g., INT -> LONG)
        IMPLICIT_LOSSY,     // Implicit narrowing with potential loss (warn)
        EXPLICIT_REQUIRED,  // Explicit conversion required (e.g., DOUBLE -> INT)
        INCOMPATIBLE        // Types cannot be converted
    };
    
    CoercionResult checkCoercion(const TypeDescriptor& from, const TypeDescriptor& to) const;
    CoercionResult checkNumericCoercion(const TypeDescriptor& from, const TypeDescriptor& to) const;
    bool validateAssignment(const TypeDescriptor& lhs, const TypeDescriptor& rhs, const SourceLocation& loc);
    TypeDescriptor promoteTypesD(const TypeDescriptor& left, const TypeDescriptor& right) const;
    
    // Type inference helpers
    TypeDescriptor inferTypeFromSuffixD(TokenType suffix) const;
    TypeDescriptor inferTypeFromSuffixD(char suffix) const;
    TypeDescriptor inferTypeFromNameD(const std::string& name) const;

    // Symbol table management (new TypeDescriptor-based)
    VariableSymbol* declareVariableD(const std::string& name, const TypeDescriptor& type,
                                     const SourceLocation& loc, bool isDeclared = false);
    ArraySymbol* declareArrayD(const std::string& name, const TypeDescriptor& elementType,
                              const std::vector<int>& dimensions,
                              const SourceLocation& loc);
    FunctionSymbol* declareFunctionD(const std::string& name,
                                     const std::vector<std::string>& params,
                                     const std::vector<TypeDescriptor>& paramTypes,
                                     const TypeDescriptor& returnType,
                                     const Expression* body,
                                     const SourceLocation& loc);

    // Symbol table management (legacy - maintained for compatibility)
    VariableSymbol* declareVariable(const std::string& name, VariableType type,
                                   const SourceLocation& loc, bool isDeclared = false);
    ArraySymbol* declareArray(const std::string& name, VariableType type,
                            const std::vector<int>& dimensions,
                            const SourceLocation& loc);
    FunctionSymbol* declareFunction(const std::string& name,
                                   const std::vector<std::string>& params,
                                   const Expression* body,
                                   const SourceLocation& loc);

    VariableSymbol* lookupVariable(const std::string& name);
    ArraySymbol* lookupArray(const std::string& name);
    FunctionSymbol* lookupFunction(const std::string& name);
    LineNumberSymbol* lookupLine(int lineNumber);
    LabelSymbol* lookupLabel(const std::string& name);
    TypeSymbol* lookupType(const std::string& name);
    TypeSymbol* declareType(const std::string& name, const SourceLocation& loc);

    // Label management
    LabelSymbol* declareLabel(const std::string& name, size_t programLineIndex,
                             const SourceLocation& loc);
    int resolveLabelToId(const std::string& name, const SourceLocation& loc);

    // Variable/array usage tracking
    void useVariable(const std::string& name, const SourceLocation& loc);
    void useArray(const std::string& name, size_t dimensionCount, const SourceLocation& loc);

    // Type suffix handling
    VariableType inferTypeFromSuffix(TokenType suffix);
    VariableType inferTypeFromName(const std::string& name);
    std::string mangleNameWithSuffix(const std::string& name, TokenType suffix);

    // Variable name normalization - ensures all variable names have proper type suffixes
    // This is the canonical function to normalize variable names throughout the system
    std::string normalizeVariableName(const std::string& name, const TypeDescriptor& typeDesc) const;
    std::string normalizeVariableName(const std::string& name, TokenType suffix, const std::string& asTypeName = "") const;

    // FOR loop variable normalization
    // If varName references a FOR loop variable (by base name), returns the normalized name
    // with the correct integer suffix based on OPTION FOR. Otherwise returns varName unchanged.
    std::string normalizeForLoopVariable(const std::string& varName) const;
    
    // Helper to strip type suffix from variable name
    static std::string stripTypeSuffix(const std::string& name);

    // Built-in function support
    bool isBuiltinFunction(const std::string& name) const;
    VariableType getBuiltinReturnType(const std::string& name) const;
    int getBuiltinArgCount(const std::string& name) const;

    // Control flow validation
    void validateControlFlow(Program& program);
    void checkUnusedVariables();

    // Error reporting
    void error(SemanticErrorType type, const std::string& message,
              const SourceLocation& loc);
    void warning(const std::string& message, const SourceLocation& loc);

    // Constant expression evaluation helpers
    FasterBASIC::ConstantValue evalConstantBinary(const BinaryExpression& expr);
    FasterBASIC::ConstantValue evalConstantUnary(const UnaryExpression& expr);
    FasterBASIC::ConstantValue evalConstantFunction(const FunctionCallExpression& expr);
    FasterBASIC::ConstantValue evalConstantVariable(const VariableExpression& expr);

    // Check if expression can be evaluated at compile time
    bool isConstantExpression(const Expression& expr);

    // Type promotion for constant operations
    bool isConstantNumeric(const FasterBASIC::ConstantValue& val);
    double getConstantAsDouble(const FasterBASIC::ConstantValue& val);
    int64_t getConstantAsInt(const FasterBASIC::ConstantValue& val);

    // Data
    SymbolTable m_symbolTable;
    std::vector<SemanticError> m_errors;
    std::vector<SemanticWarning> m_warnings;
    
    // Track FOR EACH variables (they should NOT be in symbol table)
    std::set<std::string> m_forEachVariables;
    
    // Track FOR loop variables (base names without suffixes)
    // These variables ignore type suffixes - I, I%, I& all refer to the same variable
    std::unordered_set<std::string> m_forLoopVariables;
    
    ConstantsManager m_constantsManager;

    // Configuration
    CompilerOptions m_options;  // Store compiler options (including FOR loop type)
    bool m_strictMode;
    bool m_warnUnused;
    bool m_requireExplicitDim;
    bool m_cancellableLoops;

    // Control flow stacks (for validation)
    struct ForContext {
        std::string variable;
        SourceLocation location;
    };
    std::stack<ForContext> m_forStack;
    std::stack<SourceLocation> m_whileStack;
    std::stack<SourceLocation> m_repeatStack;
    std::stack<SourceLocation> m_doStack;

    // Current analysis context
    const Program* m_program;
    int m_currentLineNumber;

    // Built-in function registry
    std::unordered_map<std::string, int> m_builtinFunctions;  // name -> arg count
    void initializeBuiltinFunctions();

    // Timer handler tracking
    std::unordered_set<std::string> m_registeredHandlers;  // Handlers registered via AFTER/EVERY
    bool m_inTimerHandler;  // True when analyzing a timer handler function
    std::string m_currentFunctionName;  // Name of function currently being analyzed

    // Function scope variable tracking (for LOCAL/SHARED validation)
    struct FunctionScope {
        std::string functionName;
        std::unordered_set<std::string> parameters;      // Function parameters (implicitly local)
        std::unordered_set<std::string> localVariables;  // LOCAL declarations
        std::unordered_set<std::string> sharedVariables; // SHARED declarations
        bool inFunction;                                  // Are we inside a function/sub?
        TypeDescriptor expectedReturnType;               // Expected return type for FUNCTION
        std::string expectedReturnTypeName;              // User-defined return type name (if any)
        bool isSub;                                      // true if SUB (no return value), false if FUNCTION
        
        FunctionScope() : inFunction(false), expectedReturnType(BaseType::UNKNOWN), isSub(false) {}
    };
    
    FunctionScope m_currentFunctionScope;
    
    // Get current scope (global or function)
    Scope getCurrentScope() const {
        if (m_currentFunctionScope.inFunction) {
            return Scope::makeFunction(m_currentFunctionScope.functionName);
        } else {
            return Scope::makeGlobal();
        }
    }
    
    // Validation helper for variables in functions
    void validateVariableInFunction(const std::string& varName, const SourceLocation& loc);
    void validateReturnStatement(const ReturnStatement& stmt);
    
    // Symbol table fix pass - ensure all variables have correct type suffixes
    void fixSymbolTableMangling();
};

} // namespace FasterBASIC

#endif // FASTERBASIC_SEMANTIC_H
