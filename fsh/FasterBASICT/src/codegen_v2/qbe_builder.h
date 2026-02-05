#ifndef QBE_BUILDER_H
#define QBE_BUILDER_H

#include <string>
#include <sstream>
#include <vector>
#include <unordered_set>
#include <map>

namespace fbc {

/**
 * QBEBuilder - Low-level QBE IL emission
 * 
 * Responsible for:
 * - Emitting QBE instructions (add, sub, mul, div, call, ret, etc.)
 * - Managing temporary variables (%t.0, %t.1, etc.)
 * - Emitting labels and jumps
 * - Building the raw QBE IL text
 * 
 * This is the foundation of the code generator - all other components
 * use QBEBuilder to emit actual IL instructions.
 */
class QBEBuilder {
public:
    QBEBuilder();
    ~QBEBuilder() = default;

    // === Output Management ===
    
    /**
     * Get the complete generated IL as a string
     */
    std::string getIL() const;
    
    /**
     * Clear all generated IL (useful for testing)
     */
    void reset();

    // === Function/Block Structure ===
    
    /**
     * Begin a function definition
     * @param name Function name (e.g., "main", "sub_mysub")
     * @param returnType QBE return type ("w" for int, "l" for ptr, etc.)
     * @param params Parameter list (e.g., "w %arg0, l %arg1")
     */
    void emitFunctionStart(const std::string& name, 
                          const std::string& returnType,
                          const std::string& params = "");
    
    /**
     * End a function definition
     */
    void emitFunctionEnd();
    
    /**
     * Emit a basic block label
     * @param label Label name (e.g., "start", "loop_body", "if_then")
     */
    void emitLabel(const std::string& label);

    // === Temporaries ===
    
    /**
     * Allocate a new temporary variable
     * @return Temporary name (e.g., "%t.0", "%t.1")
     */
    std::string newTemp();
    
    /**
     * Get current temporary counter (for debugging/testing)
     */
    int getTempCounter() const { return tempCounter_; }

    // === Arithmetic & Logic ===
    
    /**
     * Emit a binary arithmetic operation
     * @param dest Destination temporary (e.g., "%t.0")
     * @param type QBE type ("w", "l", "s", "d")
     * @param op Operation ("add", "sub", "mul", "div", "rem")
     * @param lhs Left operand
     * @param rhs Right operand
     */
    void emitBinary(const std::string& dest, const std::string& type,
                   const std::string& op, const std::string& lhs, 
                   const std::string& rhs);
    
    /**
     * Emit a comparison operation
     * @param dest Destination temporary (must be 'w' type)
     * @param type Type of operands being compared
     * @param op Comparison ("eq", "ne", "slt", "sle", "sgt", "sge")
     * @param lhs Left operand
     * @param rhs Right operand
     */
    void emitCompare(const std::string& dest, const std::string& type,
                    const std::string& op, const std::string& lhs,
                    const std::string& rhs);
    
    /**
     * Emit a unary negation
     * @param dest Destination temporary
     * @param type QBE type
     * @param operand Operand to negate
     */
    void emitNeg(const std::string& dest, const std::string& type,
                const std::string& operand);

    // === Memory Operations ===
    
    /**
     * Emit a load operation
     * @param dest Destination temporary
     * @param type Type to load ("w", "l", "s", "d")
     * @param addr Address to load from
     */
    void emitLoad(const std::string& dest, const std::string& type,
                 const std::string& addr);
    
    /**
     * Emit a store operation
     * @param type Type to store
     * @param value Value to store
     * @param addr Address to store to
     */
    void emitStore(const std::string& type, const std::string& value,
                  const std::string& addr);
    
    /**
     * Emit an alloc4/alloc8/alloc16 instruction
     * @param dest Destination (receives pointer)
     * @param size Size in bytes
     */
    void emitAlloc(const std::string& dest, int size);

    // === Control Flow ===
    
    /**
     * Emit an unconditional jump
     * @param target Target label
     */
    void emitJump(const std::string& target);
    
    /**
     * Emit a conditional jump
     * @param condition Condition temporary (must be 'w')
     * @param trueLabel Label to jump to if non-zero
     * @param falseLabel Label to jump to if zero
     */
    void emitBranch(const std::string& condition,
                   const std::string& trueLabel,
                   const std::string& falseLabel);
    
    /**
     * Emit a switch/jump table instruction
     * @param type Type of selector ("w" or "l")
     * @param selector Selector temporary/value
     * @param defaultLabel Label for default case
     * @param caseLabels Vector of case labels (0-indexed)
     */
    void emitSwitch(const std::string& type, const std::string& selector,
                   const std::string& defaultLabel,
                   const std::vector<std::string>& caseLabels);
    
    /**
     * Emit a return instruction
     * @param value Value to return (empty for void functions)
     */
    void emitReturn(const std::string& value = "");

    // === Function Calls ===
    
    /**
     * Emit a function call
     * @param dest Destination temporary (empty for void calls)
     * @param returnType Return type ("w", "l", "s", "d", "" for void)
     * @param funcName Function name
     * @param args Argument list (e.g., "w 42, l %str")
     */
    void emitCall(const std::string& dest, const std::string& returnType,
                 const std::string& funcName, const std::string& args = "");

    // === Type Conversions ===
    
    /**
     * Emit a type extension (sign or zero extend)
     * @param dest Destination temporary
     * @param destType Destination type
     * @param op Extension operation ("extsw", "extuw", "extsh", etc.)
     * @param src Source operand
     */
    void emitExtend(const std::string& dest, const std::string& destType,
                   const std::string& op, const std::string& src);
    
    /**
     * Emit a floating point conversion
     * @param dest Destination temporary
     * @param destType Destination type ("s" or "d")
     * @param op Conversion op ("swtof", "dtosi", "stod", etc.)
     * @param src Source operand
     */
    void emitConvert(const std::string& dest, const std::string& destType,
                    const std::string& op, const std::string& src);
    
    /**
     * Emit a truncation
     * @param dest Destination temporary
     * @param destType Destination type
     * @param src Source operand
     */
    void emitTrunc(const std::string& dest, const std::string& destType,
                  const std::string& src);

    // === Data Section ===
    
    /**
     * Emit a global data declaration
     * @param name Global name (e.g., "$var_x")
     * @param type Type specifier ("w", "l", etc.)
     * @param initializer Initial value (e.g., "4", "z 8" for zero bytes)
     */
    void emitGlobalData(const std::string& name, const std::string& type,
                       const std::string& initializer);
    
    /**
     * Emit a string constant
     * @param name Constant name (e.g., "$str_0")
     * @param value String value (will be escaped and null-terminated)
     */
    void emitStringConstant(const std::string& name, const std::string& value);

    // === String Constant Pool ===
    
    /**
     * Register a string literal in the constant pool
     * @param value String literal text
     * @return Label name for the string (e.g., "$str_0")
     */
    std::string registerString(const std::string& value);
    
    /**
     * Check if a string is already in the pool
     * @param value String literal text
     * @return true if already registered
     */
    bool hasString(const std::string& value) const;
    
    /**
     * Get the label for a registered string
     * @param value String literal text
     * @return Label name, or empty string if not registered
     */
    std::string getStringLabel(const std::string& value) const;
    
    /**
     * Emit all registered string constants as global data section
     * Should be called before emitting any functions
     */
    void emitStringPool();
    
    /**
     * Clear the string pool (for testing)
     */
    void clearStringPool();

    // === Comments & Debugging ===
    
    /**
     * Emit a comment line
     * @param comment Comment text
     */
    void emitComment(const std::string& comment);
    
    /**
     * Emit a blank line (for readability)
     */
    void emitBlankLine();

    // === Raw Emission (escape hatch) ===
    
    /**
     * Emit a raw line of IL (use sparingly)
     * @param line Raw IL line
     */
    void emitRaw(const std::string& line);

    // === Helper Methods ===
    
    /**
     * Get next unique label ID
     * @return Unique label ID
     */
    int getNextLabelId() { return labelCounter_++; }
    
    /**
     * Get next temporary register name
     * @return Temporary name (e.g., "%t.42")
     */
    std::string getNextTemp() { return newTemp(); }

private:
    std::ostringstream il_;          // Accumulated IL output
    int tempCounter_;                // Counter for temporary variables
    int labelCounter_;               // Counter for unique labels
    bool inFunction_;                // Are we inside a function?
    std::string currentFunction_;    // Current function name
    
    // String constant pool
    std::map<std::string, std::string> stringPool_;  // value -> label
    int stringCounter_;              // Counter for string labels
    
    // Helper: format a temporary name
    static std::string formatTemp(int n);
    
    // Helper: escape string for QBE
    static std::string escapeString(const std::string& str);

public:
    // === Low-level Instruction Emission ===
    
    /**
     * Emit a raw instruction (for special cases)
     * @param instr Instruction text
     */
    void emitInstruction(const std::string& instr);

private:
};

} // namespace fbc

#endif // QBE_BUILDER_H