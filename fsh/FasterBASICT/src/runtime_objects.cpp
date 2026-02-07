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
    registerListType();
    
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

void RuntimeObjectRegistry::registerListType() {
    ObjectTypeDescriptor list;
    list.typeName = "LIST";
    list.description = "Ordered, dynamically-sized collection (typed or heterogeneous)";

    // Constructor: list_create() — no arguments
    list.setConstructor("list_create", {});

    // --- Mutating methods ---

    // APPEND(value) — append element to end
    // NOTE: actual runtime function is selected by codegen based on
    //       argument type and list element type:
    //       list_append_int / list_append_float / list_append_string / list_append_list
    MethodSignature append("APPEND", BaseType::UNKNOWN, "list_append_int");
    append.addParam("value", BaseType::LONG)
          .withDescription("Append an element to the end of the list");
    list.addMethod(append);

    // PREPEND(value) — prepend element to beginning
    MethodSignature prepend("PREPEND", BaseType::UNKNOWN, "list_prepend_int");
    prepend.addParam("value", BaseType::LONG)
           .withDescription("Prepend an element to the beginning of the list");
    list.addMethod(prepend);

    // INSERT(pos, value) — insert at 1-based position
    MethodSignature insert("INSERT", BaseType::UNKNOWN, "list_insert_int");
    insert.addParam("pos", BaseType::INTEGER)
          .addParam("value", BaseType::LONG)
          .withDescription("Insert an element at a 1-based position");
    list.addMethod(insert);

    // REMOVE(pos) — remove element at 1-based position
    MethodSignature remove("REMOVE", BaseType::UNKNOWN, "list_remove");
    remove.addParam("pos", BaseType::INTEGER)
          .withDescription("Remove element at 1-based position");
    list.addMethod(remove);

    // CLEAR() — remove all elements
    MethodSignature clear("CLEAR", BaseType::UNKNOWN, "list_clear");
    clear.withDescription("Remove all elements");
    list.addMethod(clear);

    // EXTEND(other) — append all elements from another list
    MethodSignature extend("EXTEND", BaseType::UNKNOWN, "list_extend");
    extend.addParam("other", BaseType::OBJECT)
          .withDescription("Append all elements from another list");
    list.addMethod(extend);

    // --- Accessor methods ---
    // Return types shown here are defaults for LIST OF INTEGER.
    // The codegen overrides based on the list's actual element type.

    // HEAD() — get the first element's value
    MethodSignature head("HEAD", BaseType::LONG, "list_head_int");
    head.withDescription("Get the value of the first element");
    list.addMethod(head);

    // REST() — new list with all elements except the first
    MethodSignature rest("REST", BaseType::OBJECT, "list_rest");
    rest.withDescription("New list containing all elements except the first");
    list.addMethod(rest);

    // GET(pos) — get element value at 1-based position
    MethodSignature get("GET", BaseType::LONG, "list_get_int");
    get.addParam("pos", BaseType::INTEGER)
       .withDescription("Get element value at 1-based position");
    list.addMethod(get);

    // LENGTH() — number of elements (O(1))
    MethodSignature length("LENGTH", BaseType::LONG, "list_length");
    length.withDescription("Number of elements (O(1))");
    list.addMethod(length);

    // EMPTY() — check if list is empty (1=yes, 0=no)
    MethodSignature empty("EMPTY", BaseType::INTEGER, "list_empty");
    empty.withDescription("Check if the list is empty (1=yes, 0=no)");
    list.addMethod(empty);

    // CONTAINS(value) — check if list contains value
    MethodSignature contains("CONTAINS", BaseType::INTEGER, "list_contains_int");
    contains.addParam("value", BaseType::LONG)
            .withDescription("Check if the list contains a value");
    list.addMethod(contains);

    // INDEXOF(value) — find 1-based position (0=not found)
    MethodSignature indexof("INDEXOF", BaseType::LONG, "list_indexof_int");
    indexof.addParam("value", BaseType::LONG)
           .withDescription("Find 1-based position of value (0=not found)");
    list.addMethod(indexof);

    // JOIN(separator) — join elements into a string
    MethodSignature join("JOIN", BaseType::STRING, "list_join");
    join.addParam("separator", BaseType::STRING)
        .withDescription("Join elements into a string with separator");
    list.addMethod(join);

    // --- Methods returning new lists ---

    // COPY() — deep copy of the list
    MethodSignature copy("COPY", BaseType::OBJECT, "list_copy");
    copy.withDescription("Create a deep copy of the list");
    list.addMethod(copy);

    // REVERSE() — new list in reversed order
    MethodSignature reverse("REVERSE", BaseType::OBJECT, "list_reverse");
    reverse.withDescription("Create a new list in reversed order");
    list.addMethod(reverse);

    // --- Stack/Queue methods ---

    // SHIFT() — remove and return the first element
    MethodSignature shift("SHIFT", BaseType::LONG, "list_shift_int");
    shift.withDescription("Remove and return the first element");
    list.addMethod(shift);

    // POP() — remove and return the last element
    MethodSignature pop("POP", BaseType::LONG, "list_pop_int");
    pop.withDescription("Remove and return the last element");
    list.addMethod(pop);

    // Enable subscript operator: myList(n) for read access (sugar for .GET(n))
    // The actual codegen selects list_get_int/list_get_float/list_get_ptr based on
    // the list's element type — these defaults are just for the semantic analyzer.
    list.enableSubscript(
        TypeDescriptor(BaseType::INTEGER),  // Key is 1-based integer index
        TypeDescriptor(BaseType::LONG),     // Default return type (overridden by codegen)
        "list_get_int",                     // Default get function (overridden by codegen)
        "list_insert_int"                   // Default set function (not yet used)
    );

    registerObjectType(list);
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