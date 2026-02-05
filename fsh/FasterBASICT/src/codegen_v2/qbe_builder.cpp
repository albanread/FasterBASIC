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
    // For floating point types (s, d), use 'clt' not 'cslt'
    // For integer types (w, l), use 'cslt'
    std::string fullOp;
    if (type == "s" || type == "d") {
        // Floating point: remove 's' prefix if present
        if (op.length() > 0 && op[0] == 's') {
            fullOp = "c" + op.substr(1) + type;
        } else {
            fullOp = "c" + op + type;
        }
    } else {
        // Integer: keep as is
        fullOp = "c" + op + type;
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

void QBEBuilder::emitAlloc(const std::string& dest, int size) {
    std::ostringstream oss;
    oss << dest << " =l alloc";
    
    // Choose alloc4, alloc8, or alloc16 based on size
    if (size <= 4) {
        oss << "4 " << size;
    } else if (size <= 8) {
        oss << "8 " << size;
    } else {
        oss << "16 " << size;
    }
    
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
    }
    
    emitBlankLine();
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