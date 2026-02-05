//
// fasterbasic_qbe_codegen.h
// FasterBASIC QBE Code Generator
//
// Generates QBE IL (Intermediate Language) from FasterBASIC CFG/AST.
// The generated QBE IL calls the C runtime library (libbasic_runtime.a)
// for high-level operations like strings, arrays, I/O, etc.
//
// This is a modular implementation split across multiple files:
// - qbe_codegen_main.cpp        - Main orchestration, block emission
// - qbe_codegen_expressions.cpp - Expression emission
// - qbe_codegen_statements.cpp  - Statement emission
// - qbe_codegen_runtime.cpp     - Runtime library call wrappers
// - qbe_codegen_helpers.cpp     - Helper functions
//

#ifndef FASTERBASIC_QBE_CODEGEN_H
#define FASTERBASIC_QBE_CODEGEN_H

#include "fasterbasic_cfg.h"
#include "fasterbasic_semantic.h"
#include "fasterbasic_ast.h"
#include "fasterbasic_options.h"
#include "fasterbasic_data_preprocessor.h"
#include <string>
#include <sstream>
#include <vector>
#include <unordered_map>
#include <unordered_set>
#include <map>
#include <memory>

namespace FasterBASIC {

// =============================================================================
// QBE Code Generation Configuration
// =============================================================================

struct QBECodeGenConfig {
    bool emitComments = true;        // Include source line comments
    bool emitDebugInfo = false;      // Generate debug metadata
    bool optimizeLocals = true;      // Use locals where possible
    int maxLocalVariables = 200;     // Max local variables (QBE limit)
    
    QBECodeGenConfig() = default;
};

// =============================================================================
// QBE Code Generation Statistics
// =============================================================================

struct QBECodeGenStats {
    size_t instructionsGenerated = 0;
    size_t labelsGenerated = 0;
    size_t variablesUsed = 0;
    size_t arraysUsed = 0;
    size_t functionsGenerated = 0;
    double generationTimeMs = 0.0;
    
    void print() const;
};

// =============================================================================
// QBE Code Generator
// =============================================================================

class QBECodeGenerator {
public:
    QBECodeGenerator();
    explicit QBECodeGenerator(const QBECodeGenConfig& config);
    ~QBECodeGenerator();
    
    // Main API: Generate QBE IL from ProgramCFG (main + functions)
    std::string generate(const ProgramCFG& programCFG, 
                        const SymbolTable& symbols,
                        const CompilerOptions& options);
    
    // Set DATA values from preprocessor
    void setDataValues(const DataPreprocessorResult& dataResult);
    
    // Get generation statistics
    const QBECodeGenStats& getStats() const { return m_stats; }
    
    // Configuration
    void setConfig(const QBECodeGenConfig& config) { m_config = config; }
    const QBECodeGenConfig& getConfig() const { return m_config; }

private:
    // Code generation state
    std::ostringstream m_output;
    QBECodeGenConfig m_config;
    QBECodeGenStats m_stats;
    const ProgramCFG* m_programCFG;
    const ControlFlowGraph* m_cfg;  // Points to current CFG being generated
    const SymbolTable* m_symbols;
    CompilerOptions m_options;
    
    // Symbol tables and tracking
    std::unordered_map<std::string, int> m_variables;      // varName -> slot
    std::unordered_map<std::string, std::string> m_varTypes; // varName -> QBE type
    std::unordered_map<std::string, int> m_arrays;         // arrayName -> id
    std::unordered_map<std::string, std::string> m_arrayElementTypes; // arrayName -> typeName (for UDT arrays)
    std::unordered_map<int, std::string> m_labels;         // blockId/lineNum -> label
    std::unordered_map<std::string, int> m_stringLiterals; // literal -> id</parameter>
    
    // Temporary variable counter
    int m_tempCounter = 0;
    int m_labelCounter = 0;
    int m_stringCounter = 0;
    
    // Track QBE types of temporaries (for type-aware operations)
    std::unordered_map<std::string, std::string> m_tempTypes;
    
    // Current function context
    std::string m_currentFunction;
    bool m_inFunction = false;
    std::unordered_set<std::string> m_localVariables;  // Local variables in current function
    std::unordered_map<std::string, VariableType> m_localVariableTypes;  // Types of LOCAL variables
    std::unordered_set<std::string> m_sharedVariables; // Shared (global) variables accessed in function
    std::unordered_set<std::string> m_forLoopVariables; // FOR loop indices (always INTEGER)
    std::unordered_map<std::string, std::string> m_defFnParams; // DEF FN parameter name -> QBE temp mapping
    
    // Cached global base pointer (for efficient global variable access)
    std::string m_cachedGlobalBase;  // Cached %global_base temp (empty if not yet cached)
    
    // Current block being emitted (for statement handlers)
    const BasicBlock* m_currentBlock = nullptr;
    
    // Last evaluated condition (for conditional branches)
    std::string m_lastCondition;
    
    // SELECT CASE context (for emitting test blocks)
    // Use map keyed by CaseStatement pointer to handle multiple SELECT CASEs
    std::map<const CaseStatement*, std::string> m_selectCaseValues;
    std::map<const CaseStatement*, std::string> m_selectCaseTypes;
    std::map<const CaseStatement*, std::vector<std::vector<std::string>>> m_selectCaseClauseValues;
    std::map<const CaseStatement*, std::vector<std::vector<const Expression*>>> m_selectCaseClauseExpressions;
    std::map<const CaseStatement*, std::vector<bool>> m_selectCaseClauseIsCaseIs;
    std::map<const CaseStatement*, std::vector<TokenType>> m_selectCaseClauseIsOperators;
    std::map<const CaseStatement*, std::vector<bool>> m_selectCaseClauseIsRange;
    std::map<const CaseStatement*, std::vector<const Expression*>> m_selectCaseClauseRangeStart;
    std::map<const CaseStatement*, std::vector<const Expression*>> m_selectCaseClauseRangeEnd;
    std::map<const CaseStatement*, size_t> m_selectCaseClauseIndex;
    const CaseStatement* m_currentSelectCase = nullptr;  // Track which SELECT CASE we're processing
    
    // Flag: did last statement emit a terminator (jump/return)?
    bool m_lastStatementWasTerminator = false;
    
    // Loop context stack (for EXIT statements)
    struct LoopContext {
        std::string exitLabel;      // Label to jump to on EXIT
        std::string continueLabel;  // Label to jump to on CONTINUE
        std::string type;           // "FOR", "WHILE", "DO", etc.
        std::string forVariable;    // FOR loop variable name (for NEXT without variable)
        bool isForEach;             // true for FOR EACH...IN, false for traditional FOR
        
        // FOR EACH specific context (when isForEach = true)
        std::string forEachArrayDesc;  // Array descriptor variable
        std::string forEachIndex;      // Index variable
        VariableType forEachElemType;  // Element type
    };
    std::vector<LoopContext> m_loopStack;
    
    // Track variables declared in FOR EACH loops (to skip in initial declarations)
    std::set<std::string> m_forEachDeclaredVars;
    
    // GOSUB return stack (for RETURN statements)
    std::vector<std::string> m_gosubReturnLabels;
    
    // Data section strings
    std::vector<std::string> m_dataStrings;
    
    // DATA/READ/RESTORE support
    std::vector<DataValue> m_dataValues;
    std::map<int, size_t> m_lineRestorePoints;
    std::map<std::string, size_t> m_labelRestorePoints;
    
    // User-Defined Types (UDT) support
    std::unordered_map<std::string, size_t> m_typeSizes;        // typeName -> size in bytes
    std::unordered_map<std::string, std::unordered_map<std::string, size_t>> m_fieldOffsets;  // typeName -> (fieldName -> offset)
    std::unordered_map<std::string, std::string> m_varTypeNames; // varName -> typeName (for USER_DEFINED types)
    
    // Function context for local array cleanup
    struct FunctionContext {
        std::string name;
        std::vector<std::string> localArrays;  // Heap-allocated arrays to free on exit
        std::string tidyExitLabel;             // Label for cleanup block
        VariableType returnType;
        bool isSub;                            // SUB vs FUNCTION
        
        FunctionContext(const std::string& n, VariableType ret, bool sub)
            : name(n), returnType(ret), isSub(sub), tidyExitLabel("") {}
    };
    std::stack<FunctionContext> m_functionStack;
    
    // =============================================================================
    // Main Generation Functions (qbe_codegen_main.cpp)
    // =============================================================================
    
    void emitHeader();
    void emitDataSection();
    void emitMainFunction();
    void emitFunction(const std::string& functionName);
    void emitBlock(const BasicBlock* block);
    
    // Pre-pass to collect FOR loop variables for type inference
    void collectForLoopVariables();
    
    // Helper for entering/exiting function context
    void enterFunctionContext(const std::string& functionName);
    void exitFunctionContext();
    
    // =============================================================================
    // Statement Emission (qbe_codegen_statements.cpp)
    // =============================================================================
    
    void emitStatement(const Statement* stmt);
    void emitPrint(const PrintStatement* stmt);
    void emitInput(const InputStatement* stmt);
    void emitLet(const LetStatement* stmt);
    void emitMidAssign(const MidAssignStatement* stmt);
    void emitSliceAssign(const SliceAssignStatement* stmt);
    void emitIf(const IfStatement* stmt);
    void emitFor(const ForStatement* stmt);
    void emitForIn(const ForInStatement* stmt);
    void emitNext(const NextStatement* stmt);
    void emitWhile(const WhileStatement* stmt);
    void emitWend(const WendStatement* stmt);
    void emitGoto(const GotoStatement* stmt);
    void emitGosub(const GosubStatement* stmt);
    void emitOnGoto(const OnGotoStatement* stmt);
    void emitOnGosub(const OnGosubStatement* stmt);
    void emitReturn(const ReturnStatement* stmt);
    void emitDim(const DimStatement* stmt);
    void emitEnd(const EndStatement* stmt);
    void emitRem(const RemStatement* stmt);
    void emitCall(const CallStatement* stmt);
    void emitRead(const ReadStatement* stmt);
    void emitRestore(const RestoreStatement* stmt);
    void emitErase(const EraseStatement* stmt);
    void emitRedim(const RedimStatement* stmt);
    void emitExit(const ExitStatement* stmt);
    void emitRepeat(const RepeatStatement* stmt);
    void emitUntil(const UntilStatement* stmt);
    void emitDo(const DoStatement* stmt);
    void emitLoop(const LoopStatement* stmt);
    void emitCase(const CaseStatement* stmt);
    void emitLocal(const LocalStatement* stmt);
    void emitShared(const SharedStatement* stmt);
    void emitTryCatch(const TryCatchStatement* stmt);
    void emitThrow(const ThrowStatement* stmt);
    
    // Terminal I/O
    void emitCls(const SimpleStatement* stmt);
    void emitColor(const ExpressionStatement* stmt);
    void emitLocate(const ExpressionStatement* stmt);
    void emitWidth(const ExpressionStatement* stmt);
    
    // =============================================================================
    // Expression Emission (qbe_codegen_expressions.cpp)
    // =============================================================================
    
    std::string emitExpression(const Expression* expr);
    std::string emitNumberLiteral(const NumberExpression* expr);
    std::string emitStringLiteral(const StringExpression* expr);
    std::string emitVariableRef(const VariableExpression* expr);
    std::string emitBinaryOp(const BinaryExpression* expr);
    std::string emitUnaryOp(const UnaryExpression* expr);
    std::string emitFunctionCall(const FunctionCallExpression* expr);
    std::string emitArrayAccessExpr(const ArrayAccessExpression* expr);
    std::string emitArrayElementPtr(const std::string& arrayName, const std::vector<std::unique_ptr<Expression>>& indices);
    std::string emitMemberAccessExpr(const MemberAccessExpression* expr);
    std::string emitIIF(const IIFExpression* expr);
    
    // Constant folding helpers
    bool isNumberLiteral(const Expression* expr, double& value);
    bool areNumberLiterals(const Expression* expr1, const Expression* expr2, double& val1, double& val2);
    std::string emitIntConstant(int64_t value);
    int getPowerOf2ShiftAmount(const Expression* expr);
    
    // Helper for function mapping
    std::string mapToRuntimeFunction(const std::string& basicFunc);
    
    // =============================================================================
    // Runtime Library Calls (qbe_codegen_runtime.cpp)
    // =============================================================================
    
    // I/O operations
    void emitPrintValue(const std::string& value, VariableType type);
    void emitPrintNewline();
    void emitPrintTab();
    std::string emitInputString();
    std::string emitInputInt();
    std::string emitInputDouble();
    
    // String operations
    std::string emitStringConstant(const std::string& str);
    std::string emitStringConcat(const std::string& left, const std::string& right);
    std::string emitStringCompare(const std::string& left, const std::string& right);
    std::string emitStringLength(const std::string& str);
    std::string emitStringSubstr(const std::string& str, const std::string& start, const std::string& length);
    
    // Array operations
    std::string emitArrayCreate(const std::string& arrayName, const std::vector<std::string>& bounds);
    std::string emitArrayGet(const std::string& arrayName, const std::vector<std::string>& indices);
    void emitArrayStore(const std::string& arrayName, const std::vector<std::string>& indices, const std::string& value);
    
    // Type conversions
    std::string emitIntToString(const std::string& value);
    std::string emitDoubleToString(const std::string& value);
    std::string emitStringToInt(const std::string& value);
    std::string emitStringToDouble(const std::string& value);
    std::string emitIntToDouble(const std::string& value, const std::string& valueQBEType = "l");
    std::string emitDoubleToInt(const std::string& value);
    
    // Math operations
    std::string emitMathFunction(const std::string& funcName, const std::vector<std::string>& args);
    std::string emitAbs(const std::string& value);
    std::string emitSqrt(const std::string& value);
    std::string emitSin(const std::string& value);
    std::string emitCos(const std::string& value);
    std::string emitTan(const std::string& value);
    std::string emitPow(const std::string& base, const std::string& exp);
    std::string emitRnd();
    
    // File I/O operations
    void emitFileOpen(const std::string& filename, const std::string& mode, const std::string& fileNum);
    void emitFileClose(const std::string& fileNum);
    std::string emitFileRead(const std::string& fileNum);
    void emitFileWrite(const std::string& fileNum, const std::string& data);
    std::string emitFileEof(const std::string& fileNum);
    
    // =============================================================================
    // Helper Functions (qbe_codegen_helpers.cpp)
    // =============================================================================
    
    // Emit raw QBE IL
    void emit(const std::string& code);
    void emitLine(const std::string& code);
    void emitComment(const std::string& comment);
    void emitLabel(const std::string& label);
    
    // Temporary variable management
    std::string allocTemp(const std::string& qbeType = "w");
    std::string allocLabel();
    void freeTemp(const std::string& temp);
    
    // Label generation
    std::string makeLabel(const std::string& prefix);
    std::string getBlockLabel(int blockId);
    std::string getLineLabel(int lineNumber);
    std::string getFunctionExitLabel();  // Returns tidy_exit for functions, exit for main
    int getFallthroughBlock(const Statement* stmt) const;
    
    // Type mapping
    std::string getQBEType(VariableType type);
    std::string getActualQBEType(const Expression* expr);  // Get actual QBE type (w for comparisons, l for ints)
    std::string getQBETypeFromSuffix(char suffix);
    char getTypeSuffix(const std::string& varName);
    VariableType getVariableType(const std::string& varName);
    
    // TypeDescriptor-based type system (new)
    std::string getQBETypeD(const TypeDescriptor& typeDesc);
    std::string getQBEMemOpD(const TypeDescriptor& typeDesc);  // For store operations
    std::string getQBELoadOpD(const TypeDescriptor& typeDesc); // For load operations
    TypeDescriptor getVariableTypeD(const std::string& varName);
    TokenType getTokenTypeFromSuffix(char suffix);
    
    // Variable management
    std::string sanitizeQBEVariableName(const std::string& varName);
    std::string getVariableRef(const std::string& varName);
    std::string getArrayRef(const std::string& arrayName);
    void declareVariable(const std::string& varName, VariableType type);
    std::string stripTypeSuffix(const std::string& varName);
    void declareArray(const std::string& arrayName, VariableType type);
    
    // String escaping
    std::string escapeString(const std::string& str);
    
    // Get runtime function name
    std::string getRuntimeFunction(const std::string& operation, VariableType type);
    
    // Check if expression is constant
    bool isConstantExpression(const Expression* expr);
    int evaluateConstantInt(const Expression* expr);
    
    // Comparison operations
    std::string getComparisonOp(TokenType op);
    std::string getComparisonOpDouble(TokenType op);
    double evaluateConstantDouble(const Expression* expr);
    
    // Loop management
    LoopContext* pushLoop(const std::string& exitLabel, const std::string& continueLabel, const std::string& type, const std::string& forVariable = "", bool isForEach = false);
    void popLoop();
    LoopContext* getCurrentLoop();
    
    // GOSUB return stack
    void pushGosubReturn(const std::string& returnLabel);
    void popGosubReturn();
    std::string getCurrentGosubReturn();
    
    // Type inference and promotion
    VariableType inferExpressionType(const Expression* expr);
    std::string promoteToType(const std::string& value, VariableType fromType, VariableType toType, const std::string& actualQBEType = "");
    
    // Utility functions
    std::string toUpper(const std::string& str);
    std::string toLower(const std::string& str);
    bool isNumericType(VariableType type);
    bool isIntegerType(VariableType type);
    bool isFloatingType(VariableType type);
    bool isStringType(VariableType type);
    
    // User-Defined Type helpers
    size_t calculateTypeSize(const std::string& typeName);
    size_t calculateFieldOffset(const std::string& typeName, const std::string& fieldName);
    size_t getFieldOffset(const std::string& typeName, const std::vector<std::string>& memberChain);
    std::string inferMemberAccessType(const Expression* expr);
    std::string getVariableTypeName(const std::string& varName);
    const TypeSymbol* getTypeSymbol(const std::string& typeName);
};

// =============================================================================
// Utility Functions
// =============================================================================

// Quick helper to generate QBE IL from CFG
inline std::string generateQBECode(const ProgramCFG& programCFG, 
                                  const SymbolTable& symbols,
                                  const CompilerOptions& options) {
    QBECodeGenerator gen;
    return gen.generate(programCFG, symbols, options);
}

// Generate with custom configuration
inline std::string generateQBECode(const ProgramCFG& programCFG, 
                                  const SymbolTable& symbols,
                                  const CompilerOptions& options,
                                  const QBECodeGenConfig& config) {
    QBECodeGenerator gen(config);
    return gen.generate(programCFG, symbols, options);
}

} // namespace FasterBASIC

#endif // FASTERBASIC_QBE_CODEGEN_H