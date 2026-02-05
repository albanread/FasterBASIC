#include "runtime_objects.h"
#include "fasterbasic_semantic.h"
#include <algorithm>
#include <cctype>

namespace FasterBASIC {

// =============================================================================
// RuntimeObjectRegistry Implementation
// =============================================================================

void RuntimeObjectRegistry::initialize() {
    // Clear any existing registrations (for re-initialization)
    clear();
    
    // Register all known runtime object types
    registerHashmapType();
    
    // Future object types can be registered here:
    // registerFileType();
    // registerSpriteType();
    // registerTimerType();
}

void RuntimeObjectRegistry::registerObjectType(const ObjectTypeDescriptor& objType) {
    // Store by type name (uppercase for case-insensitive lookup)
    std::string upperName = objType.typeName;
    std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
    objectTypes_[upperName] = objType;
}

const ObjectTypeDescriptor* RuntimeObjectRegistry::getObjectType(const std::string& typeName) const {
    std::string upperName = typeName;
    std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
    
    auto it = objectTypes_.find(upperName);
    if (it != objectTypes_.end()) {
        return &it->second;
    }
    return nullptr;
}

bool RuntimeObjectRegistry::isObjectType(const TypeDescriptor& typeDesc) const {
    if (typeDesc.baseType != BaseType::OBJECT) {
        return false;
    }
    return getObjectType(typeDesc.objectTypeName) != nullptr;
}

std::vector<const ObjectTypeDescriptor*> RuntimeObjectRegistry::getAllObjectTypes() const {
    std::vector<const ObjectTypeDescriptor*> result;
    for (const auto& pair : objectTypes_) {
        result.push_back(&pair.second);
    }
    return result;
}

void RuntimeObjectRegistry::clear() {
    objectTypes_.clear();
}

// =============================================================================
// Object Type Registration Functions
// =============================================================================

void RuntimeObjectRegistry::registerHashmapType() {
    ObjectTypeDescriptor hashmap;
    hashmap.typeName = "HASHMAP";
    hashmap.description = "Hash table / dictionary for key-value storage with string keys";
    
    // Set constructor: hashmap_new(capacity) with default capacity of 128
    // NOTE: Smaller capacities (16, 31, 32) trigger a bug when multiple hashmaps are used
    // TODO: Investigate why BASIC code hangs with small capacities while C code works fine
    hashmap.setConstructor("hashmap_new", {"w 128"});
    
    // Enable subscript operator: dict("key") = value and value = dict("key")
    hashmap.enableSubscript(
        TypeDescriptor(BaseType::STRING),   // Keys must be strings
        TypeDescriptor(BaseType::STRING),   // Values are strings (for now)
        "hashmap_lookup",                    // Runtime function for dict("key")
        "hashmap_insert"                     // Runtime function for dict("key") = value
    );
    
    // HASKEY(key$) -> INTEGER (returns 1 if key exists, 0 otherwise)
    MethodSignature haskey("HASKEY", BaseType::INTEGER, "hashmap_has_key");
    haskey.addParam("key", BaseType::STRING)
          .withDescription("Check if a key exists in the hashmap");
    hashmap.addMethod(haskey);
    
    // SIZE() -> INTEGER (returns number of entries)
    MethodSignature size("SIZE", BaseType::INTEGER, "hashmap_size");
    size.withDescription("Get the number of entries in the hashmap");
    hashmap.addMethod(size);
    
    // REMOVE(key$) -> INTEGER (returns 1 if removed, 0 if not found)
    MethodSignature remove("REMOVE", BaseType::INTEGER, "hashmap_remove");
    remove.addParam("key", BaseType::STRING)
          .withDescription("Remove a key-value pair from the hashmap");
    hashmap.addMethod(remove);
    
    // CLEAR() -> void (removes all entries)
    MethodSignature clear("CLEAR", BaseType::UNKNOWN, "hashmap_clear");
    clear.withDescription("Remove all entries from the hashmap");
    hashmap.addMethod(clear);
    
    // KEYS() -> pointer to char** (NULL-terminated array of keys)
    // Note: In the future, this should return a BASIC string array
    MethodSignature keys("KEYS", BaseType::STRING, "hashmap_keys");
    keys.withDescription("Get an array of all keys in the hashmap");
    hashmap.addMethod(keys);
    
    // Register the hashmap type
    registerObjectType(hashmap);
}

// =============================================================================
// Future Object Type Registrations (Placeholders)
// =============================================================================

/*
void RuntimeObjectRegistry::registerFileType() {
    ObjectTypeDescriptor file;
    file.typeName = "FILE";
    file.baseType = BaseType::FILE;
    file.description = "File handle for binary or text file I/O";
    
    // Methods:
    // - CLOSE() -> void
    // - EOF() -> INTEGER
    // - READ(bytes%) -> STRING
    // - WRITE(data$) -> INTEGER
    // - SEEK(pos&) -> void
    // - TELL() -> LONG
    
    registerObjectType(file);
}

void RuntimeObjectRegistry::registerSpriteType() {
    ObjectTypeDescriptor sprite;
    sprite.typeName = "SPRITE";
    sprite.baseType = BaseType::SPRITE;
    sprite.description = "2D sprite object for graphics rendering";
    
    // Methods:
    // - SHOW() -> void
    // - HIDE() -> void
    // - MOVE(x%, y%) -> void
    // - ROTATE(angle!) -> void
    // - SCALE(factor!) -> void
    // - SETTINT(color&) -> void
    
    registerObjectType(sprite);
}

void RuntimeObjectRegistry::registerTimerType() {
    ObjectTypeDescriptor timer;
    timer.typeName = "TIMER";
    timer.baseType = BaseType::TIMER;
    timer.description = "Timer object for scheduling events";
    
    // Methods:
    // - START() -> void
    // - STOP() -> void
    // - RESET() -> void
    // - ELAPSED() -> DOUBLE
    // - SETINTERVAL(ms&) -> void
    
    registerObjectType(timer);
}
*/

} // namespace FasterBASIC