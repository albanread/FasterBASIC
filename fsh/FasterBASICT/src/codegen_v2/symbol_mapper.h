#ifndef SYMBOL_MAPPER_H
#define SYMBOL_MAPPER_H

#include <string>
#include <unordered_map>
#include <unordered_set>

namespace fbc {

/**
 * SymbolMapper - Name mangling and symbol mapping
 * 
 * Responsible for:
 * - Variable name mangling (avoid QBE reserved words, handle BASIC special chars)
 * - Label generation (blocks, functions, subroutines)
 * - Scope tracking (global vs. local variables)
 * - Unique temporary naming
 * 
 * BASIC allows characters in names that QBE doesn't (%, $, #, !, etc.)
 * We need to mangle these names to valid QBE identifiers.
 */
class SymbolMapper {
public:
    SymbolMapper();
    ~SymbolMapper() = default;

    // === Variable Name Mangling ===
    
    /**
     * Mangle a BASIC variable name to a valid QBE identifier
     * @param basicName BASIC variable name (e.g., "MyVar%", "name$", "x")
     * @param isGlobal True if this is a global variable
     * @return Mangled QBE name (e.g., "$var_MyVar_int", "$var_name_str", "%x")
     * 
     * Rules:
     * - Global variables start with $
     * - Local variables start with %
     * - Type suffixes are converted: % -> _int, $ -> _str, # -> _dbl, ! -> _sng
     * - Dots and other special chars are replaced with underscores
     */
    std::string mangleVariableName(const std::string& basicName, bool isGlobal = false);
    
    /**
     * Mangle an array name
     * @param basicName BASIC array name
     * @param isGlobal True if global array
     * @return Mangled array name (e.g., "$arr_MyArray")
     */
    std::string mangleArrayName(const std::string& basicName, bool isGlobal = false);
    
    /**
     * Get the array descriptor name for an array
     * Array descriptors store metadata (dimensions, bounds, etc.)
     * @param basicName BASIC array name
     * @return Descriptor name (e.g., "$arr_desc_MyArray")
     */
    std::string getArrayDescriptorName(const std::string& basicName);

    // === Function/Subroutine Names ===
    
    /**
     * Mangle a SUB name
     * @param subName BASIC SUB name
     * @return Mangled name (e.g., "$sub_MySub")
     */
    std::string mangleSubName(const std::string& subName);
    
    /**
     * Mangle a FUNCTION name
     * @param funcName BASIC FUNCTION name
     * @return Mangled name (e.g., "$func_MyFunc")
     */
    std::string mangleFunctionName(const std::string& funcName);
    
    /**
     * Mangle a DEF FN name
     * @param defName BASIC DEF FN name (e.g., "FNDouble")
     * @return Mangled name (e.g., "$deffn_FNDouble")
     */
    std::string mangleDefFnName(const std::string& defName);

    // === Label Names ===
    
    /**
     * Mangle a BASIC label/line number
     * @param label BASIC label (string or number)
     * @return Mangled label name (e.g., "label_MyLabel", "line_100")
     */
    std::string mangleLabelName(const std::string& label);
    
    /**
     * Get a block label name for CFG blocks
     * @param blockId CFG block ID
     * @return Block label (e.g., "block_0", "block_5")
     */
    std::string getBlockLabel(int blockId);
    
    /**
     * Get a unique label for control flow structures
     * @param prefix Label prefix (e.g., "if_then", "loop_body")
     * @return Unique label (e.g., "if_then_0", "loop_body_3")
     */
    std::string getUniqueLabel(const std::string& prefix);

    // === String Constant Names ===
    
    /**
     * Get a unique string constant name
     * @return String constant name (e.g., "$str_0", "$str_1")
     */
    std::string getStringConstantName();

    // === Scope Management ===
    
    /**
     * Enter a function scope (for LOCAL variable handling)
     * @param functionName Function or SUB name
     * @param parameters List of parameter names for this function
     */
    void enterFunctionScope(const std::string& functionName,
                           const std::vector<std::string>& parameters = {});
    
    /**
     * Exit current function scope
     */
    void exitFunctionScope();
    
    /**
     * Mark a variable as SHARED in the current function scope
     * @param varName Variable name (as it appears in BASIC code)
     */
    void addSharedVariable(const std::string& varName);
    
    /**
     * Check if a variable is SHARED in the current function
     * @param varName Variable name
     * @return True if SHARED
     */
    bool isSharedVariable(const std::string& varName) const;
    
    /**
     * Check if a variable is a parameter of the current function
     * @param varName Variable name
     * @return True if it's a parameter
     */
    bool isParameter(const std::string& varName) const;
    
    /**
     * Clear shared variables (called when exiting function scope)
     */
    void clearSharedVariables();
    
    /**
     * Check if we're in a function scope
     * @return True if in function, false if at global scope
     */
    bool inFunctionScope() const;
    
    /**
     * Get current function name (or empty if at global scope)
     * @return Current function name
     */
    std::string getCurrentFunction() const;

    // === Reserved Word Checking ===
    
    /**
     * Check if a name is a QBE reserved word
     * @param name Name to check
     * @return True if reserved
     */
    bool isQBEReserved(const std::string& name) const;
    
    /**
     * Escape a name if it's reserved
     * @param name Name to escape
     * @return Escaped name (with _ prefix if reserved)
     */
    std::string escapeReserved(const std::string& name) const;

    // === Reset (for testing) ===
    
    /**
     * Reset all counters and scope (useful for testing)
     */
    void reset();

private:
    // Current function scope (empty if global)
    std::string currentFunction_;
    
    // Shared variables in current function scope
    std::unordered_set<std::string> sharedVariables_;
    
    // Parameters in current function scope
    std::vector<std::string> currentFunctionParameters_;
    
    // Counters for unique name generation
    int labelCounter_;
    int stringCounter_;
    
    // QBE reserved words (instructions, types, etc.)
    std::unordered_set<std::string> qbeReserved_;
    
    // Symbol cache (to ensure consistent mangling)
    std::unordered_map<std::string, std::string> symbolCache_;
    
    // Helper: strip type suffix from BASIC name
    std::string stripTypeSuffix(const std::string& name) const;
    
    // Helper: get type suffix string
    std::string getTypeSuffixString(char suffix) const;
    
    // Helper: sanitize name (replace invalid chars with underscores)
    std::string sanitizeName(const std::string& name) const;
    
    // Helper: initialize QBE reserved words
    void initializeReservedWords();
};

} // namespace fbc

#endif // SYMBOL_MAPPER_H