#ifndef AST_EMITTER_H
#define AST_EMITTER_H

#include <string>
#include <vector>
#include <unordered_map>
#include "../fasterbasic_ast.h"
#include "../fasterbasic_semantic.h"
#include "qbe_builder.h"
#include "type_manager.h"
#include "symbol_mapper.h"
#include "runtime_library.h"

namespace fbc {

/**
 * ASTEmitter - Statement and expression code emission
 * 
 * Responsible for:
 * - Emitting code for expressions (binary ops, function calls, literals, etc.)
 * - Emitting code for statements (LET, PRINT, IF, FOR, etc.)
 * - Type checking and conversion
 * - Variable and array access
 * 
 * Works with QBEBuilder for low-level IL emission and RuntimeLibrary
 * for runtime function calls.
 */
// =========================================================================
// SIMDLoopInfo — describes a FOR loop that can be vectorized with NEON
// =========================================================================
struct SIMDLoopInfo {
    bool isVectorizable = false;

    // Loop bounds (evaluated once, integer)
    std::string indexVar;            // e.g. "i"

    // Whether start/end are compile-time constants
    bool startIsConstant = false;
    bool endIsConstant   = false;
    int  startVal = 0;               // only valid when startIsConstant
    int  endVal   = 0;               // only valid when endIsConstant
    int  stepVal  = 1;               // must be 1 for vectorization

    // Array operands participating in the loop
    struct ArrayOperand {
        std::string arrayName;       // e.g. "positions"
        std::string udtTypeName;     // e.g. "Vec4"
        FasterBASIC::TypeDeclarationStatement::SIMDInfo simdInfo;
        bool isReadOnly = true;      // true if only loaded, never stored
    };
    std::vector<ArrayOperand> operands;

    // Operation description
    // "add", "sub", "mul", "div" for element-wise binary ops
    // "copy" for array-to-array copy
    std::string operation;
    int destArrayIndex  = -1;        // index into operands for destination
    int srcAArrayIndex  = -1;        // index into operands for source A
    int srcBArrayIndex  = -1;        // index into operands for source B (-1 for copy)

    // NEON arrangement code (0=.4s-int, 1=.2d-int, 2=.4s-float, 3=.2d-float)
    int arrangementCode = 0;

    // Element size in bytes (16 for Q-register UDTs)
    int elemSizeBytes = 0;
};

class ASTEmitter {
public:
    ASTEmitter(QBEBuilder& builder, TypeManager& typeManager, 
               SymbolMapper& symbolMapper, RuntimeLibrary& runtime,
               FasterBASIC::SemanticAnalyzer& semantic);
    ~ASTEmitter() = default;

    // === Expression Emission ===
    
    /**
     * Emit code for an expression
     * @param expr Expression to emit
     * @return Temporary holding the result value
     */
    std::string emitExpression(const FasterBASIC::Expression* expr);
    
    /**
     * Emit code for an expression with expected type (auto-converts)
     * @param expr Expression to emit
     * @param expectedType Expected result type
     * @return Temporary holding the result (converted to expectedType)
     */
    std::string emitExpressionAs(const FasterBASIC::Expression* expr, 
                                  FasterBASIC::BaseType expectedType);

    // === Statement Emission ===
    
    /**
     * Emit code for a statement
     * @param stmt Statement to emit
     */
    void emitStatement(const FasterBASIC::Statement* stmt);
    
    /**
     * Emit LET assignment
     * @param stmt LET statement
     */
    void emitLetStatement(const FasterBASIC::LetStatement* stmt);
    
    /**
     * Emit PRINT statement
     * @param stmt PRINT statement
     */
    void emitPrintStatement(const FasterBASIC::PrintStatement* stmt);
    
    /**
     * Emit INPUT statement
     * @param stmt INPUT statement
     */
    void emitInputStatement(const FasterBASIC::InputStatement* stmt);
    
    /**
     * Emit READ statement
     * @param stmt READ statement
     */
    void emitReadStatement(const FasterBASIC::ReadStatement* stmt);
    
    /**
     * Emit RESTORE statement
     * @param stmt RESTORE statement
     */
    void emitRestoreStatement(const FasterBASIC::RestoreStatement* stmt);
    
    /**
     * Emit slice assignment statement (text$(start TO end) = value)
     * @param stmt Slice assignment statement
     */
    void emitSliceAssignStatement(const FasterBASIC::SliceAssignStatement* stmt);
    
    /**
     * Emit IF statement (handled by CFGEmitter for control flow)
     * This just emits the condition evaluation
     * @param stmt IF statement
     * @return Temporary holding condition result
     */
    std::string emitIfCondition(const FasterBASIC::IfStatement* stmt);
    
    /**
     * Emit WHILE loop condition check
     * @param stmt WHILE statement
     * @return Temporary holding condition result
     */
    std::string emitWhileCondition(const FasterBASIC::WhileStatement* stmt);
    
    /**
     * Emit DO loop pre-condition check (DO WHILE/UNTIL)
     * @param stmt DO statement
     * @return Temporary holding condition result (empty if no pre-condition)
     */
    std::string emitDoPreCondition(const FasterBASIC::DoStatement* stmt);
    
    /**
     * Emit LOOP post-condition check (LOOP WHILE/UNTIL)
     * @param stmt LOOP statement
     * @return Temporary holding condition result (empty if no post-condition)
     */
    std::string emitLoopPostCondition(const FasterBASIC::LoopStatement* stmt);
    
    /**
     * Emit FOR loop initialization
     * @param stmt FOR statement
     */
    void emitForInit(const FasterBASIC::ForStatement* stmt);
    
    /**
     * Emit FOR loop condition check
     * @param stmt FOR statement
     * @return Temporary holding condition result (loop variable <= end value)
     */
    std::string emitForCondition(const FasterBASIC::ForStatement* stmt);
    
    /**
     * Emit FOR loop increment
     * @param stmt FOR statement
     */
    void emitForIncrement(const FasterBASIC::ForStatement* stmt);
    
    /**
     * Emit END statement
     * @param stmt END statement
     */
    void emitEndStatement(const FasterBASIC::EndStatement* stmt);
    
    /**
     * Emit RETURN statement
     * @param stmt RETURN statement
     */
    void emitReturnStatement(const FasterBASIC::ReturnStatement* stmt);
    
    /**
     * Emit DIM statement (array declaration)
     * @param stmt DIM statement
     */
    void emitDimStatement(const FasterBASIC::DimStatement* stmt);
    
    /**
     * Emit REDIM statement (array redimensioning)
     * @param stmt REDIM statement
     */
    void emitRedimStatement(const FasterBASIC::RedimStatement* stmt);
    
    /**
     * Emit ERASE statement (array deallocation)
     * @param stmt ERASE statement
     */
    void emitEraseStatement(const FasterBASIC::EraseStatement* stmt);
    
    /**
     * Emit LOCAL statement (local variable declaration in SUB/FUNCTION)
     * @param stmt LOCAL statement
     */
    void emitLocalStatement(const FasterBASIC::LocalStatement* stmt);
    
    /**
     * Emit CALL statement (SUB call)
     * @param stmt CALL statement
     */
    void emitCallStatement(const FasterBASIC::CallStatement* stmt);

    // === Variable Access ===
    
    /**
     * Get the address of a variable (for assignments)
     * @param varName Variable name
     * @return Temporary holding variable address
     */
    std::string getVariableAddress(const std::string& varName);
    
    /**
     * Load a variable value
     * @param varName Variable name
     * @return Temporary holding variable value
     */
    std::string loadVariable(const std::string& varName);
    
    /**
     * Store a value to a variable
     * @param varName Variable name
     * @param value Value to store (temporary)
     */
    void storeVariable(const std::string& varName, const std::string& value);

    // === Array Access ===
    
    /**
     * Emit array element access
     * @param arrayName Array name
     * @param indices Index expressions
     * @return Temporary holding element address
     */
    std::string emitArrayAccess(const std::string& arrayName,
                                const std::vector<FasterBASIC::ExpressionPtr>& indices);
    
    /**
     * Load array element value
     * @param arrayName Array name
     * @param indices Index expressions
     * @return Temporary holding element value
     */
    std::string loadArrayElement(const std::string& arrayName,
                                 const std::vector<FasterBASIC::ExpressionPtr>& indices);
    
    /**
     * Store value to array element
     * @param arrayName Array name
     * @param indices Index expressions
     * @param value Value to store
     */
    void storeArrayElement(const std::string& arrayName,
                          const std::vector<FasterBASIC::ExpressionPtr>& indices,
                          const std::string& value);

    // === Type Inference ===
    
    /**
     * Get the type of an expression
     * @param expr Expression
     * @return Type of the expression result
     */
    FasterBASIC::BaseType getExpressionType(const FasterBASIC::Expression* expr);
    
    /**
     * Get the type of a variable
     * @param varName Variable name
     * @return Variable type
     */
    FasterBASIC::BaseType getVariableType(const std::string& varName);
    
    /**
     * Get the symbol table from semantic analyzer
     * @return Reference to symbol table
     */
    const FasterBASIC::SymbolTable& getSymbolTable() const { return semantic_.getSymbolTable(); }
    
private:
    QBEBuilder& builder_;
    TypeManager& typeManager_;
    SymbolMapper& symbolMapper_;
    RuntimeLibrary& runtime_;
    FasterBASIC::SemanticAnalyzer& semantic_;
    
    // Global variable addresses cache
    std::unordered_map<std::string, std::string> globalVarAddresses_;
    
    // FOR loop temporary variable addresses (limit, step, comparison flag)
    std::unordered_map<std::string, std::string> forLoopTempAddresses_;
    
    // === Array element base address cache ===
    // Workaround for QBE ARM64 miscompilation: when the same array element is
    // accessed multiple times (e.g., Contacts(Idx).Name then Contacts(Idx).Phone),
    // the QBE backend can incorrectly drop the index*element_size multiplication
    // in the second and subsequent accesses. By caching the computed element base
    // address in a stack slot and reloading it, we avoid re-emitting the mul+add
    // pattern that triggers the bug.
    //
    // Key: "arrayName:serializedIndexExpr", Value: QBE stack alloc name holding the address
    std::unordered_map<std::string, std::string> arrayElemBaseCache_;
    
    // === Expression Emitters (by type) ===
    
    std::string emitBinaryExpression(const FasterBASIC::BinaryExpression* expr);
    std::string emitUnaryExpression(const FasterBASIC::UnaryExpression* expr);
    std::string emitNumberLiteral(const FasterBASIC::NumberExpression* expr, FasterBASIC::BaseType expectedType = FasterBASIC::BaseType::UNKNOWN);
    std::string emitStringLiteral(const FasterBASIC::StringExpression* expr);
    std::string emitVariableExpression(const FasterBASIC::VariableExpression* expr);
    std::string emitArrayAccessExpression(const FasterBASIC::ArrayAccessExpression* expr);
    std::string emitMemberAccessExpression(const FasterBASIC::MemberAccessExpression* expr);
    std::string emitFunctionCall(const FasterBASIC::FunctionCallExpression* expr);
    std::string emitIIFExpression(const FasterBASIC::IIFExpression* expr);
    std::string emitMethodCall(const FasterBASIC::MethodCallExpression* expr);
    
    // === Binary Operation Helpers ===
    
    std::string emitArithmeticOp(const std::string& left, const std::string& right,
                                 FasterBASIC::TokenType op, FasterBASIC::BaseType type);
    std::string emitComparisonOp(const std::string& left, const std::string& right,
                                 FasterBASIC::TokenType op, FasterBASIC::BaseType type);
    std::string emitLogicalOp(const std::string& left, const std::string& right,
                             FasterBASIC::TokenType op);
    std::string emitStringOp(const std::string& left, const std::string& right,
                            FasterBASIC::TokenType op);
    
    // === Type Conversion Helpers ===
    
    std::string emitTypeConversion(const std::string& value, 
                                   FasterBASIC::BaseType fromType,
                                   FasterBASIC::BaseType toType);
    
    // === Helper: get QBE operator name ===
    
    std::string getQBEArithmeticOp(FasterBASIC::TokenType op);
    
    // === Helper: get type suffix character ===
    
    char getTypeSuffixChar(FasterBASIC::TokenType suffix);
    char getTypeSuffixChar(FasterBASIC::BaseType type);
    std::string getQBEComparisonOp(FasterBASIC::TokenType op);
    
    // === Helper: get array element address (for UDT arrays) ===
    
    std::string emitArrayElementAddress(const std::string& arrayName, 
                                        const std::vector<FasterBASIC::ExpressionPtr>& indices);
    
    // === Array element base address cache helpers ===
    
    // Serialize an index expression to a string key for cache lookup.
    // Returns empty string for complex expressions that shouldn't be cached.
    std::string serializeIndexExpression(const FasterBASIC::Expression* expr) const;
    
    // Invalidate the array element base address cache.
    // Called at the start of each statement and after any assignment that could
    // change array contents or index variable values.
    void clearArrayElementCache();
    
    // === Helper: recursive UDT field-by-field copy with proper string refcounting ===
    // Copies all fields from sourceAddr to targetAddr for the given UDT definition.
    // Handles string fields with retain/release and nested UDTs recursively.
    void emitUDTCopyFieldByField(const std::string& sourceAddr,
                                 const std::string& targetAddr,
                                 const FasterBASIC::TypeSymbol& udtDef,
                                 const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap);
    
    // === NEON Phase 2: Element-wise UDT arithmetic ===
    // Detects patterns like C = A + B where A, B, C are the same SIMD-eligible
    // UDT type and emits NEON vector arithmetic (neonldr/neonldr2/neonadd/neonstr)
    // instead of scalar field-by-field operations.
    // Returns true if NEON arithmetic was emitted, false to fall through to scalar path.
    bool tryEmitNEONArithmetic(const FasterBASIC::LetStatement* stmt,
                               const std::string& targetAddr,
                               const FasterBASIC::TypeSymbol& udtDef,
                               const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap);

    // === Scalar fallback for UDT arithmetic ===
    // When NEON arithmetic is disabled or not applicable, performs field-by-field
    // scalar arithmetic (C.field = A.field op B.field) for +, -, *, /.
    // Returns true if scalar arithmetic was emitted, false if not applicable.
    bool emitScalarUDTArithmetic(const FasterBASIC::LetStatement* stmt,
                                 const std::string& targetAddr,
                                 const FasterBASIC::TypeSymbol& udtDef,
                                 const std::unordered_map<std::string, FasterBASIC::TypeSymbol>& udtMap);
    
    // Helper: get the memory address of a UDT expression (variable, array element,
    // or member access). Returns empty string if the expression is not a UDT address.
    std::string getUDTAddressForExpr(const FasterBASIC::Expression* expr);
    
    // Helper: resolve the UDT type name from an expression that yields a UDT value.
    // Returns empty string if the expression does not resolve to a known UDT.
    std::string getUDTTypeNameForExpr(const FasterBASIC::Expression* expr);
    
    // Helper: map a SIMDInfo arrangement to the integer constant used in NEON IL
    // opcodes (0=Kw/.4s-int, 1=Kl/.2d-int, 2=Ks/.4s-float, 3=Kd/.2d-float).
    int simdArrangementCode(const FasterBASIC::TypeDeclarationStatement::SIMDInfo& info);
    
    // === Helper: normalize FOR loop variable names ===
    // If varName references a FOR loop variable, returns it with the correct integer suffix
    // Otherwise returns varName unchanged
    std::string normalizeForLoopVarName(const std::string& varName) const;
    
    // Normalize a variable name to include proper type suffix based on semantic analyzer's type inference
    // This ensures codegen uses the same normalized names as the symbol table
    std::string normalizeVariableName(const std::string& varName) const;

public:
    // === NEON Phase 3: Array Loop Vectorization (public for CFGEmitter) ===

    /**
     * Analyze a FOR loop to determine if it can be vectorized with NEON.
     * Checks the loop structure, body pattern, array operands, and UDT
     * SIMD eligibility.
     *
     * @param forStmt The FOR statement to analyze
     * @return SIMDLoopInfo with isVectorizable == true if the loop qualifies
     */
    SIMDLoopInfo analyzeSIMDLoop(const FasterBASIC::ForStatement* forStmt);

    /**
     * Emit a NEON-vectorized loop that replaces a scalar FOR loop.
     * Emits: bounds checks, data-pointer extraction, byte-offset loop
     * with NEON load/op/store, and post-loop variable fixup.
     *
     * @param forStmt  The original FOR statement (for start/end expressions)
     * @param info     The analysis result from analyzeSIMDLoop()
     * @param exitLabel QBE label to jump to when the loop is finished
     */
    void emitSIMDLoop(const FasterBASIC::ForStatement* forStmt,
                      const SIMDLoopInfo& info,
                      const std::string& exitLabel);

private:
    // === NEON Phase 3 helpers ===

    // Check whether a LetStatement body is a whole-UDT binary op on array
    // elements indexed by the loop variable: C(i) = A(i) OP B(i)
    bool matchWholeUDTBinaryOp(const FasterBASIC::LetStatement* stmt,
                                const std::string& indexVar,
                                SIMDLoopInfo& info);

    // Check whether a LetStatement body is a whole-UDT array copy
    // indexed by the loop variable: B(i) = A(i)
    bool matchWholeUDTCopy(const FasterBASIC::LetStatement* stmt,
                            const std::string& indexVar,
                            SIMDLoopInfo& info);

    // Check whether a set of LetStatements covers all fields of a
    // SIMD-eligible UDT with the same binary op: C(i).f = A(i).f OP B(i).f
    bool matchFieldByFieldOp(const std::vector<FasterBASIC::StatementPtr>& body,
                              const std::string& indexVar,
                              SIMDLoopInfo& info);

    // Helper: get the array descriptor QBE name for an array
    std::string getArrayDescriptorPtr(const std::string& arrayName);

    // Helper: check if an expression is a simple variable reference
    // to the loop index variable
    bool isLoopIndexVar(const FasterBASIC::Expression* expr,
                        const std::string& indexVar) const;

    // Helper: try to evaluate an expression as a compile-time integer constant
    bool tryEvalConstantInt(const FasterBASIC::Expression* expr, int& outVal) const;
};

} // namespace fbc

#endif // AST_EMITTER_H