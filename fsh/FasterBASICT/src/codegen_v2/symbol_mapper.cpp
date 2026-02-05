#include "symbol_mapper.h"
#include <cctype>
#include <sstream>

namespace fbc {

SymbolMapper::SymbolMapper()
    : currentFunction_("")
    , labelCounter_(0)
    , stringCounter_(0)
{
    initializeReservedWords();
}

// === Variable Name Mangling ===

std::string SymbolMapper::mangleVariableName(const std::string& basicName, bool isGlobal) {
    // Check cache first
    std::string cacheKey = (isGlobal ? "G:" : "L:") + basicName;
    auto it = symbolCache_.find(cacheKey);
    if (it != symbolCache_.end()) {
        return it->second;
    }
    
    // Strip type suffix and get type string
    std::string baseName = basicName;
    std::string typeSuffix;
    
    if (!baseName.empty()) {
        char lastChar = baseName.back();
        if (lastChar == '%' || lastChar == '$' || lastChar == '#' || 
            lastChar == '!' || lastChar == '&') {
            typeSuffix = getTypeSuffixString(lastChar);
            baseName = baseName.substr(0, baseName.length() - 1);
        }
    }
    
    // Sanitize the base name
    std::string sanitized = sanitizeName(baseName);
    
    // Build mangled name
    std::ostringstream oss;
    if (isGlobal) {
        // Use $ prefix for global symbols in QBE
        oss << "$var_" << sanitized;
    } else {
        oss << "%var_" << sanitized;
    }
    
    if (!typeSuffix.empty()) {
        oss << "_" << typeSuffix;
    }
    
    std::string mangled = oss.str();
    
    // Escape if reserved
    mangled = escapeReserved(mangled);
    
    // Cache and return
    symbolCache_[cacheKey] = mangled;
    return mangled;
}

std::string SymbolMapper::mangleArrayName(const std::string& basicName, bool isGlobal) {
    std::string baseName = stripTypeSuffix(basicName);
    std::string sanitized = sanitizeName(baseName);
    
    std::ostringstream oss;
    if (isGlobal) {
        // Use $ prefix for global symbols in QBE
        oss << "$arr_" << sanitized;
    } else {
        oss << "%arr_" << sanitized;
    }
    
    return escapeReserved(oss.str());
}

std::string SymbolMapper::getArrayDescriptorName(const std::string& basicName) {
    std::string baseName = stripTypeSuffix(basicName);
    std::string sanitized = sanitizeName(baseName);
    // Use $ prefix for global symbols in QBE
    return "$arr_desc_" + sanitized;
}

// === Function/Subroutine Names ===

std::string SymbolMapper::mangleSubName(const std::string& subName) {
    std::string sanitized = sanitizeName(subName);
    return escapeReserved("$sub_" + sanitized);
}

std::string SymbolMapper::mangleFunctionName(const std::string& funcName) {
    std::string baseName = stripTypeSuffix(funcName);
    std::string sanitized = sanitizeName(baseName);
    return escapeReserved("$func_" + sanitized);
}

std::string SymbolMapper::mangleDefFnName(const std::string& defName) {
    std::string sanitized = sanitizeName(defName);
    return escapeReserved("$deffn_" + sanitized);
}

// === Label Names ===

std::string SymbolMapper::mangleLabelName(const std::string& label) {
    // Check if it's a numeric label (line number)
    bool isNumeric = true;
    for (char c : label) {
        if (!std::isdigit(c)) {
            isNumeric = false;
            break;
        }
    }
    
    if (isNumeric) {
        return "line_" + label;
    } else {
        std::string sanitized = sanitizeName(label);
        return "label_" + sanitized;
    }
}

std::string SymbolMapper::getBlockLabel(int blockId) {
    return "block_" + std::to_string(blockId);
}

std::string SymbolMapper::getUniqueLabel(const std::string& prefix) {
    std::string sanitized = sanitizeName(prefix);
    return sanitized + "_" + std::to_string(labelCounter_++);
}

// === String Constant Names ===

std::string SymbolMapper::getStringConstantName() {
    return "$str_" + std::to_string(stringCounter_++);
}

// === Scope Management ===

void SymbolMapper::enterFunctionScope(const std::string& functionName,
                                      const std::vector<std::string>& parameters) {
    currentFunction_ = functionName;
    sharedVariables_.clear();
    currentFunctionParameters_ = parameters;
}

void SymbolMapper::exitFunctionScope() {
    currentFunction_ = "";
    sharedVariables_.clear();
    currentFunctionParameters_.clear();
}

void SymbolMapper::addSharedVariable(const std::string& varName) {
    sharedVariables_.insert(varName);
}

bool SymbolMapper::isSharedVariable(const std::string& varName) const {
    return sharedVariables_.count(varName) > 0;
}

void SymbolMapper::clearSharedVariables() {
    sharedVariables_.clear();
}

bool SymbolMapper::inFunctionScope() const {
    return !currentFunction_.empty();
}

std::string SymbolMapper::getCurrentFunction() const {
    return currentFunction_;
}

// === Reserved Word Checking ===

bool SymbolMapper::isQBEReserved(const std::string& name) const {
    return qbeReserved_.find(name) != qbeReserved_.end();
}

std::string SymbolMapper::escapeReserved(const std::string& name) const {
    if (isQBEReserved(name)) {
        return "_" + name;
    }
    return name;
}

// === Reset ===

void SymbolMapper::reset() {
    currentFunction_ = "";
    sharedVariables_.clear();
    currentFunctionParameters_.clear();
    labelCounter_ = 0;
    stringCounter_ = 0;
    symbolCache_.clear();
}

bool SymbolMapper::isParameter(const std::string& varName) const {
    for (const auto& param : currentFunctionParameters_) {
        if (param == varName) {
            return true;
        }
    }
    return false;
}

// === Private Helpers ===

std::string SymbolMapper::stripTypeSuffix(const std::string& name) const {
    if (name.empty()) return name;
    
    char lastChar = name.back();
    if (lastChar == '%' || lastChar == '$' || lastChar == '#' || 
        lastChar == '!' || lastChar == '&') {
        return name.substr(0, name.length() - 1);
    }
    
    return name;
}

std::string SymbolMapper::getTypeSuffixString(char suffix) const {
    switch (suffix) {
        case '%': return "int";
        case '&': return "lng";
        case '!': return "sng";
        case '#': return "dbl";
        case '$': return "str";
        default:  return "";
    }
}

std::string SymbolMapper::sanitizeName(const std::string& name) const {
    std::ostringstream oss;
    
    for (char c : name) {
        if (std::isalnum(c) || c == '_') {
            oss << c;
        } else {
            oss << '_';
        }
    }
    
    std::string result = oss.str();
    
    // Ensure name doesn't start with a digit
    if (!result.empty() && std::isdigit(result[0])) {
        result = "_" + result;
    }
    
    // Handle empty result
    if (result.empty()) {
        result = "_unnamed";
    }
    
    return result;
}

void SymbolMapper::initializeReservedWords() {
    // QBE instruction names
    qbeReserved_.insert("add");
    qbeReserved_.insert("sub");
    qbeReserved_.insert("mul");
    qbeReserved_.insert("div");
    qbeReserved_.insert("rem");
    qbeReserved_.insert("udiv");
    qbeReserved_.insert("urem");
    qbeReserved_.insert("or");
    qbeReserved_.insert("xor");
    qbeReserved_.insert("and");
    qbeReserved_.insert("sar");
    qbeReserved_.insert("shr");
    qbeReserved_.insert("shl");
    qbeReserved_.insert("stored");
    qbeReserved_.insert("stores");
    qbeReserved_.insert("storel");
    qbeReserved_.insert("storew");
    qbeReserved_.insert("storeh");
    qbeReserved_.insert("storeb");
    qbeReserved_.insert("loadd");
    qbeReserved_.insert("loads");
    qbeReserved_.insert("loadl");
    qbeReserved_.insert("loadsw");
    qbeReserved_.insert("loaduw");
    qbeReserved_.insert("loadsh");
    qbeReserved_.insert("loaduh");
    qbeReserved_.insert("loadsb");
    qbeReserved_.insert("loadub");
    qbeReserved_.insert("alloc4");
    qbeReserved_.insert("alloc8");
    qbeReserved_.insert("alloc16");
    qbeReserved_.insert("extsw");
    qbeReserved_.insert("extuw");
    qbeReserved_.insert("extsh");
    qbeReserved_.insert("extuh");
    qbeReserved_.insert("extsb");
    qbeReserved_.insert("extub");
    qbeReserved_.insert("exts");
    qbeReserved_.insert("truncd");
    qbeReserved_.insert("stosi");
    qbeReserved_.insert("stoui");
    qbeReserved_.insert("dtosi");
    qbeReserved_.insert("dtoui");
    qbeReserved_.insert("swtof");
    qbeReserved_.insert("uwtof");
    qbeReserved_.insert("sltof");
    qbeReserved_.insert("ultof");
    qbeReserved_.insert("cast");
    qbeReserved_.insert("copy");
    qbeReserved_.insert("ceqw");
    qbeReserved_.insert("ceql");
    qbeReserved_.insert("ceqs");
    qbeReserved_.insert("ceqd");
    qbeReserved_.insert("cnew");
    qbeReserved_.insert("cnel");
    qbeReserved_.insert("cnes");
    qbeReserved_.insert("cned");
    qbeReserved_.insert("cslew");
    qbeReserved_.insert("cslel");
    qbeReserved_.insert("csles");
    qbeReserved_.insert("csled");
    qbeReserved_.insert("csltw");
    qbeReserved_.insert("csltl");
    qbeReserved_.insert("cslts");
    qbeReserved_.insert("csltd");
    qbeReserved_.insert("csgew");
    qbeReserved_.insert("csgel");
    qbeReserved_.insert("csges");
    qbeReserved_.insert("csged");
    qbeReserved_.insert("csgtw");
    qbeReserved_.insert("csgtl");
    qbeReserved_.insert("csgts");
    qbeReserved_.insert("csgtd");
    qbeReserved_.insert("culew");
    qbeReserved_.insert("culel");
    qbeReserved_.insert("cultw");
    qbeReserved_.insert("cultl");
    qbeReserved_.insert("cugew");
    qbeReserved_.insert("cugel");
    qbeReserved_.insert("cugtw");
    qbeReserved_.insert("cugtl");
    qbeReserved_.insert("couw");
    qbeReserved_.insert("cuow");
    qbeReserved_.insert("coul");
    qbeReserved_.insert("cuol");
    qbeReserved_.insert("cos");
    qbeReserved_.insert("cuo");
    qbeReserved_.insert("cod");
    qbeReserved_.insert("call");
    qbeReserved_.insert("vastart");
    qbeReserved_.insert("vaarg");
    qbeReserved_.insert("ret");
    qbeReserved_.insert("jmp");
    qbeReserved_.insert("jnz");
    qbeReserved_.insert("hlt");
    
    // QBE type names
    qbeReserved_.insert("w");
    qbeReserved_.insert("l");
    qbeReserved_.insert("s");
    qbeReserved_.insert("d");
    qbeReserved_.insert("b");
    qbeReserved_.insert("h");
    
    // QBE keywords
    qbeReserved_.insert("function");
    qbeReserved_.insert("export");
    qbeReserved_.insert("section");
    qbeReserved_.insert("data");
    qbeReserved_.insert("align");
    qbeReserved_.insert("type");
}

} // namespace fbc