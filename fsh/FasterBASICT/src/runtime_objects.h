#ifndef RUNTIME_OBJECTS_H
#define RUNTIME_OBJECTS_H

#include <string>
#include <vector>
#include <unordered_map>
#include <memory>
#include <algorithm>
#include "fasterbasic_token.h"
#include "fasterbasic_semantic.h"

namespace FasterBASIC {

// =============================================================================
// Method Signature
// =============================================================================

/**
 * Describes a method parameter
 */
struct MethodParameter {
    std::string name;           // Parameter name (for documentation/error messages)
    BaseType type;              // Expected parameter type
    bool isOptional;            // Can this parameter be omitted?
    std::string defaultValue;   // Default value if optional (empty if N/A)
    
    MethodParameter(const std::string& n, BaseType t, bool optional = false, 
                   const std::string& defaultVal = "")
        : name(n), type(t), isOptional(optional), defaultValue(defaultVal) {}
};

/**
 * Describes a method signature (name, parameters, return type)
 */
struct MethodSignature {
    std::string name;                       // Method name (case-insensitive in BASIC)
    std::vector<MethodParameter> parameters; // Method parameters
    BaseType returnType;                    // Return type (UNKNOWN for void methods)
    std::string runtimeFunctionName;        // C runtime function to call (e.g., "hashmap_has_key")
    std::string description;                // Human-readable description
    
    MethodSignature() : returnType(BaseType::UNKNOWN) {}
    
    MethodSignature(const std::string& n, BaseType retType, const std::string& runtimeFunc)
        : name(n), returnType(retType), runtimeFunctionName(runtimeFunc) {}
    
    // Add a required parameter
    MethodSignature& addParam(const std::string& name, BaseType type) {
        parameters.emplace_back(name, type, false);
        return *this;
    }
    
    // Add an optional parameter
    MethodSignature& addOptionalParam(const std::string& name, BaseType type, 
                                     const std::string& defaultValue = "") {
        parameters.emplace_back(name, type, true, defaultValue);
        return *this;
    }
    
    // Set description
    MethodSignature& withDescription(const std::string& desc) {
        description = desc;
        return *this;
    }
    
    // Get number of required parameters
    size_t requiredParamCount() const {
        size_t count = 0;
        for (const auto& param : parameters) {
            if (!param.isOptional) count++;
        }
        return count;
    }
    
    // Get total parameter count
    size_t totalParamCount() const {
        return parameters.size();
    }
};

// =============================================================================
// Object Type Descriptor
// =============================================================================

/**
 * Describes a runtime object type (like HASHMAP, FILE, SPRITE)
 * 
 * Runtime objects are opaque handles (pointers) created by runtime functions.
 * They have methods that can be called, and optionally support subscript operators.
 */
struct ObjectTypeDescriptor {
    std::string typeName;           // Type name (e.g., "HASHMAP", "FILE")
    
    // Constructor support
    std::string constructorFunction;  // Runtime function to create new instance (e.g., "hashmap_new")
    std::vector<std::string> constructorDefaultArgs;  // Default constructor arguments in QBE format (e.g., "w 16")
    
    // Subscript operator support (e.g., dict("key") for hashmap access)
    bool hasSubscriptOperator;      // Does this object support obj(key)?
    TypeDescriptor subscriptKeyType;      // Type of key (e.g., STRING for hashmap)
    TypeDescriptor subscriptReturnType;   // Type returned by subscript access
    std::string subscriptGetFunction; // Runtime function for get: obj(key)
    std::string subscriptSetFunction; // Runtime function for set: obj(key) = value
    
    // Methods supported by this object type
    std::vector<MethodSignature> methods;
    
    // Documentation
    std::string description;
    
    ObjectTypeDescriptor()
        : hasSubscriptOperator(false)
        , subscriptKeyType(BaseType::UNKNOWN)
        , subscriptReturnType(BaseType::UNKNOWN) {}
    
    // Find a method by name (case-insensitive)
    const MethodSignature* findMethod(const std::string& methodName) const {
        std::string upperName = methodName;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        
        for (const auto& method : methods) {
            std::string upperMethodName = method.name;
            std::transform(upperMethodName.begin(), upperMethodName.end(), 
                          upperMethodName.begin(), ::toupper);
            if (upperMethodName == upperName) {
                return &method;
            }
        }
        return nullptr;
    }
    
    // Check if method exists
    bool hasMethod(const std::string& methodName) const {
        return findMethod(methodName) != nullptr;
    }
    
    // Add a method to this object type
    ObjectTypeDescriptor& addMethod(const MethodSignature& method) {
        methods.push_back(method);
        return *this;
    }
    
    // Set constructor information
    ObjectTypeDescriptor& setConstructor(const std::string& constructorFunc,
                                        const std::vector<std::string>& defaultArgs = {}) {
        constructorFunction = constructorFunc;
        constructorDefaultArgs = defaultArgs;
        return *this;
    }
    
    // Enable subscript operator
    ObjectTypeDescriptor& enableSubscript(const TypeDescriptor& keyType, const TypeDescriptor& returnType,
                                         const std::string& getFunc,
                                         const std::string& setFunc) {
        hasSubscriptOperator = true;
        subscriptKeyType = keyType;
        subscriptReturnType = returnType;
        subscriptGetFunction = getFunc;
        subscriptSetFunction = setFunc;
        return *this;
    }
    
    // Set description
    ObjectTypeDescriptor& withDescription(const std::string& desc) {
        description = desc;
        return *this;
    }
};

// =============================================================================
// Runtime Object Registry
// =============================================================================

/**
 * Global registry of runtime object types
 * 
 * This registry is populated at compiler initialization with all runtime
 * object types that the compiler knows about (HASHMAP, FILE, SPRITE, etc.)
 * 
 * The semantic analyzer queries this registry to:
 * - Check if a type is an object type
 * - Validate method calls on objects
 * - Check subscript operator usage
 * 
 * The code generator queries this registry to:
 * - Look up runtime function names for methods
 * - Generate correct call signatures
 */
class RuntimeObjectRegistry {
public:
    static RuntimeObjectRegistry& getInstance() {
        static RuntimeObjectRegistry instance;
        return instance;
    }
    
    // Initialize registry with all known runtime object types
    void initialize();
    
    // Register a new object type
    void registerObjectType(const ObjectTypeDescriptor& objType);
    
    // Look up object type by name (case-insensitive)
    const ObjectTypeDescriptor* getObjectType(const std::string& typeName) const;
    
    // Check if a TypeDescriptor is an object type
    bool isObjectType(const TypeDescriptor& typeDesc) const;
    
    // Get all registered object types (for debugging/documentation)
    std::vector<const ObjectTypeDescriptor*> getAllObjectTypes() const;
    
    // Clear registry (for testing)
    void clear();
    
private:
    RuntimeObjectRegistry() {}
    
    // Map from type name (uppercase) to ObjectTypeDescriptor
    std::unordered_map<std::string, ObjectTypeDescriptor> objectTypes_;
    
    // Registration functions for specific object types
    void registerHashmapType();
    // Future object types:
    // void registerFileType();
    // void registerSpriteType();
    // void registerTimerType();
};

// =============================================================================
// Helper Functions
// =============================================================================

/**
 * Initialize the global runtime object registry
 * Should be called once at compiler startup
 */
inline void initializeRuntimeObjectRegistry() {
    RuntimeObjectRegistry::getInstance().initialize();
}

/**
 * Get the global runtime object registry
 */
inline RuntimeObjectRegistry& getRuntimeObjectRegistry() {
    return RuntimeObjectRegistry::getInstance();
}

} // namespace FasterBASIC

#endif // RUNTIME_OBJECTS_H