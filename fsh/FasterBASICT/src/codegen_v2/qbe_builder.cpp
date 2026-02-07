#include "qbe_builder.h"
#include <iomanip>
#include <sstream>

namespace fbc {

QBEBuilder::QBEBuilder() 
    : tempCounter_(0)
    , labelCounter_(0)
    , inFunction_(false)
    , currentFunction_("")
    , stringCounter_(0)
{
}

std::string QBEBuilder::getIL() const {
    return il_.str();
}

void QBEBuilder::reset() {
    il_.str("");
    il_.clear();
    tempCounter_ = 0;
    labelCounter_ = 0;
    inFunction_ = false;
    currentFunction_ = "";
    stringPool_.clear();
    stringCounter_ = 0;
}

// === Function/Block Structure ===

void QBEBuilder::emitFunctionStart(const std::string& name, 
                                   const std::string& returnType,
                                   const std::string& params) {
    if (inFunction_) {
        emitComment("WARNING: Starting new function without ending previous one");
    }
    
    inFunction_ = true;
    currentFunction_ = name;
    tempCounter_ = 0;  // Reset temps for each function
    
    il_ << "export function ";
    if (!returnType.empty()) {
        il_ << returnType << " ";
    }
    il_ << "$" << name << "(";
    if (!params.empty()) {
        il_ << params;
    }
    il_ << ") {\n";
}

void QBEBuilder::emitFunctionEnd() {
    if (!inFunction_) {
        emitComment("WARNING: Ending function but not in a function");
        return;
    }
    
    il_ << "}\n\n";
    inFunction_ = false;
    currentFunction_ = "";
}

void QBEBuilder::emitLabel(const std::string& label) {
    if (!inFunction_) {
        emitComment("WARNING: Emitting label outside function");
    }
    il_ << "@" << label << "\n";
}

// === Temporaries ===

std::string QBEBuilder::newTemp() {
    return formatTemp(tempCounter_++);
}

std::string QBEBuilder::formatTemp(int n) {
    std::ostringstream oss;
    oss << "%t." << n;
    return oss.str();
}

// === Arithmetic & Logic ===

void QBEBuilder::emitBinary(const std::string& dest, const std::string& type,
                           const std::string& op, const std::string& lhs, 
                           const std::string& rhs) {
    std::ostringstream oss;
    oss << dest << " =" << type << " " << op << " " << lhs << ", " << rhs;
    emitInstruction(oss.str());
}

void QBEBuilder::emitCompare(const std::string& dest, const std::string& type,
                            const std::string& op, const std::string& lhs,
                            const std::string& rhs) {
    std::ostringstream oss;
    // Build the full QBE comparison mnemonic.
    //
    // Callers pass a *base* comparison name.  Accepted forms:
    //   - Already-prefixed signed-integer ops: "slt", "sle", "sgt", "sge"
    //   - Bare names that work for both int and float: "eq", "ne"
    //   - Bare names for ordering: "lt", "le", "gt", "ge"
    //
    // For integer types (w, l) we need signed prefix:  csltw, cslew …
    // For float types  (s, d) we need bare ordering:   cltd,  cled  …
    //
    // Strategy: normalise the op to its bare root (strip leading 's' when it
    // is a signed-integer prefix, i.e. one of slt/sle/sgt/sge), then
    // re-prefix according to the operand type.

    // Normalise: strip leading 's' only when the op is a well-known signed
    // integer comparison (slt, sle, sgt, sge).  This avoids accidentally
    // stripping the 's' from unrelated ops.
    std::string baseOp = op;
    if (baseOp == "slt" || baseOp == "sle" || baseOp == "sgt" || baseOp == "sge") {
        baseOp = baseOp.substr(1);  // "lt", "le", "gt", "ge"
    }

    std::string fullOp;
    if (type == "s" || type == "d") {
        // Floating-point: c<op><type>  e.g. cltd, ceqs
        fullOp = "c" + baseOp + type;
    } else {
        // Integer: cs<op><type>  e.g. csltw, cslel  (except eq/ne which are c<op><type>)
        if (baseOp == "eq" || baseOp == "ne") {
            fullOp = "c" + baseOp + type;
        } else {
            fullOp = "cs" + baseOp + type;
        }
    }

    oss << dest << " =w " << fullOp << " " << lhs << ", " << rhs;
    emitInstruction(oss.str());
}

void QBEBuilder::emitNeg(const std::string& dest, const std::string& type,
                        const std::string& operand) {
    std::ostringstream oss;
    oss << dest << " =" << type << " neg " << operand;
    emitInstruction(oss.str());
}

// === Memory Operations ===

void QBEBuilder::emitLoad(const std::string& dest, const std::string& type,
                         const std::string& addr) {
    std::ostringstream oss;
    oss << dest << " =" << type << " load" << type << " " << addr;
    emitInstruction(oss.str());
}

void QBEBuilder::emitStore(const std::string& type, const std::string& value,
                          const std::string& addr) {
    std::ostringstream oss;
    oss << "store" << type << " " << value << ", " << addr;
    emitInstruction(oss.str());
}

void QBEBuilder::emitAlloc(const std::string& dest, int size, int alignment) {
    // In QBE the suffix on alloc (4, 8, 16) specifies the *alignment* of the
    // allocation, and the operand is the number of bytes to reserve on the
    // stack.
    //
    // When the caller supplies an explicit alignment we use it directly.
    // When alignment == 0 (default / legacy) we pick from the requested size
    // using a simple heuristic that matches the most common cases.
    int align = alignment;
    if (align <= 0) {
        // Legacy heuristic: choose alignment from size
        if (size <= 4)       align = 4;
        else if (size <= 8)  align = 8;
        else                 align = 8;  // 8-byte alignment is sufficient for
                                         // most data; use 16 only when asked
    }

    // Clamp to one of the three QBE alloc variants
    int allocSuffix;
    if (align <= 4)       allocSuffix = 4;
    else if (align <= 8)  allocSuffix = 8;
    else                  allocSuffix = 16;

    std::ostringstream oss;
    oss << dest << " =l alloc" << allocSuffix << " " << size;
    emitInstruction(oss.str());
}

// === Control Flow ===

void QBEBuilder::emitJump(const std::string& target) {
    std::ostringstream oss;
    oss << "jmp @" << target;
    emitInstruction(oss.str());
}

void QBEBuilder::emitBranch(const std::string& condition,
                           const std::string& trueLabel,
                           const std::string& falseLabel) {
    std::ostringstream oss;
    oss << "jnz " << condition << ", @" << trueLabel << ", @" << falseLabel;
    emitInstruction(oss.str());
}

void QBEBuilder::emitSwitch(const std::string& type, const std::string& selector,
                           const std::string& defaultLabel,
                           const std::vector<std::string>& caseLabels) {
    // QBE doesn't have a native switch instruction with bracket syntax.
    // We need to emit a chain of comparisons and conditional jumps.
    // The selector is already 0-indexed (converted from BASIC's 1-indexed).
    //
    // Generated code pattern for ON x GOTO L1, L2, L3:
    //   if selector == 0 goto L1
    //   if selector == 1 goto L2
    //   if selector == 2 goto L3
    //   goto default
    
    if (caseLabels.empty()) {
        // No cases, just jump to default
        emitJump(defaultLabel);
        return;
    }
    
    // Generate comparison chain
    for (size_t i = 0; i < caseLabels.size(); ++i) {
        // Compare selector with case index
        std::string cmpResult = newTemp();
        std::ostringstream cmpOss;
        cmpOss << cmpResult << " =" << type << " ceq" << type << " " 
               << selector << ", " << i;
        emitInstruction(cmpOss.str());
        
        // Create labels for next comparison or default
        std::string nextLabel;
        if (i + 1 < caseLabels.size()) {
            // More cases to check - create intermediate label
            nextLabel = "switch_next_" + std::to_string(labelCounter_++);
        } else {
            // Last case - jump to default if not equal
            nextLabel = defaultLabel;
        }
        
        // Conditional jump: if equal, jump to case label; otherwise continue
        std::ostringstream jnzOss;
        jnzOss << "jnz " << cmpResult << ", @" << caseLabels[i] 
               << ", @" << nextLabel;
        emitInstruction(jnzOss.str());
        
        // Emit next label if not last case
        if (i + 1 < caseLabels.size()) {
            emitLabel(nextLabel);
        }
    }
}

void QBEBuilder::emitReturn(const std::string& value) {
    std::ostringstream oss;
    oss << "ret";
    if (!value.empty()) {
        oss << " " << value;
    }
    emitInstruction(oss.str());
}


// === Function Calls ===

void QBEBuilder::emitCall(const std::string& dest, const std::string& returnType,
                         const std::string& funcName, const std::string& args) {
    std::ostringstream oss;
    
    // If we have a destination, emit assignment
    if (!dest.empty() && !returnType.empty()) {
        oss << dest << " =" << returnType << " ";
    }
    
    oss << "call $" << funcName << "(";
    if (!args.empty()) {
        oss << args;
    }
    oss << ")";
    
    emitInstruction(oss.str());
}

// === Type Conversions ===

void QBEBuilder::emitExtend(const std::string& dest, const std::string& destType,
                           const std::string& op, const std::string& src) {
    std::ostringstream oss;
    oss << dest << " =" << destType << " " << op << " " << src;
    emitInstruction(oss.str());
}

void QBEBuilder::emitConvert(const std::string& dest, const std::string& destType,
                            const std::string& op, const std::string& src) {
    std::ostringstream oss;
    oss << dest << " =" << destType << " " << op << " " << src;
    emitInstruction(oss.str());
}

void QBEBuilder::emitTrunc(const std::string& dest, const std::string& destType,
                          const std::string& src) {
    std::ostringstream oss;
    oss << dest << " =" << destType << " copy " << src;
    emitInstruction(oss.str());
}

// === Data Section ===

void QBEBuilder::emitGlobalData(const std::string& name, const std::string& type,
                               const std::string& initializer) {
    if (inFunction_) {
        emitComment("WARNING: Emitting global data inside function");
    }
    
    // Name is already mangled with $$ prefix, don't add another $
    il_ << "data " << name << " = { " << type << " " << initializer << " }\n";
}

void QBEBuilder::emitStringConstant(const std::string& name, const std::string& value) {
    if (inFunction_) {
        emitComment("WARNING: Emitting string constant inside function");
    }
    
    std::string escaped = escapeString(value);
    il_ << "data $" << name << " = { b \"" << escaped << "\", b 0 }\n";
}

std::string QBEBuilder::escapeString(const std::string& str) {
    std::ostringstream oss;
    for (char c : str) {
        switch (c) {
            case '\n': oss << "\\n"; break;
            case '\r': oss << "\\r"; break;
            case '\t': oss << "\\t"; break;
            case '\\': oss << "\\\\"; break;
            case '"':  oss << "\\\""; break;
            default:
                if (c >= 32 && c <= 126) {
                    oss << c;
                } else {
                    // Escape non-printable characters as hex
                    oss << "\\x" << std::hex << std::setfill('0') 
                        << std::setw(2) << (int)(unsigned char)c;
                }
                break;
        }
    }
    return oss.str();
}

// === String Constant Pool ===

std::string QBEBuilder::registerString(const std::string& value) {
    // Check if string already in pool
    auto it = stringPool_.find(value);
    if (it != stringPool_.end()) {
        return it->second;
    }
    
    // Generate new label
    std::ostringstream oss;
    oss << "str_" << stringCounter_++;
    std::string label = oss.str();
    
    // Add to pool
    stringPool_[value] = label;
    
    return label;
}

bool QBEBuilder::hasString(const std::string& value) const {
    return stringPool_.find(value) != stringPool_.end();
}

std::string QBEBuilder::getStringLabel(const std::string& value) const {
    auto it = stringPool_.find(value);
    if (it != stringPool_.end()) {
        return it->second;
    }
    return "";
}

void QBEBuilder::emitStringPool() {
    if (stringPool_.empty()) {
        return;
    }
    
    emitComment("=== String Constant Pool ===");
    emitBlankLine();
    
    for (const auto& [value, label] : stringPool_) {
        std::string escaped = escapeString(value);
        il_ << "data $" << label << " = { b \"" << escaped << "\", b 0 }\n";
        emittedStrings_.insert(label);
    }
    
    emitBlankLine();
}

void QBEBuilder::emitLateStringPool() {
    // Emit any strings that were registered after the initial emitStringPool() call.
    // This catches strings registered during code generation (e.g. null-check error messages).
    bool emittedAny = false;
    for (const auto& [value, label] : stringPool_) {
        if (emittedStrings_.find(label) == emittedStrings_.end()) {
            if (!emittedAny) {
                emitBlankLine();
                emitComment("=== Late-Registered String Constants ===");
                emittedAny = true;
            }
            std::string escaped = escapeString(value);
            il_ << "data $" << label << " = { b \"" << escaped << "\", b 0 }\n";
            emittedStrings_.insert(label);
        }
    }
    if (emittedAny) {
        emitBlankLine();
    }
}

void QBEBuilder::clearStringPool() {
    stringPool_.clear();
    stringCounter_ = 0;
}

// === Comments & Debugging ===

void QBEBuilder::emitComment(const std::string& comment) {
    il_ << "# " << comment << "\n";
}

void QBEBuilder::emitBlankLine() {
    il_ << "\n";
}

// === Raw Emission ===

void QBEBuilder::emitRaw(const std::string& line) {
    il_ << line << "\n";
}

// === Private Helpers ===

void QBEBuilder::emitInstruction(const std::string& instr) {
    if (!inFunction_) {
        emitComment("WARNING: Emitting instruction outside function: " + instr);
    }
    il_ << "    " << instr << "\n";
}

} // namespace fbc