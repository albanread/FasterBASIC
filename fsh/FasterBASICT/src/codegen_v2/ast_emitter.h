#ifndef AST_EMITTER_H
#define AST_EMITTER_H

#include <string>
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
    
    // === Helper: normalize FOR loop variable names ===
    // If varName references a FOR loop variable, returns it with the correct integer suffix
    // Otherwise returns varName unchanged
    std::string normalizeForLoopVarName(const std::string& varName) const;
    
    // Normalize a variable name to include proper type suffix based on semantic analyzer's type inference
    // This ensures codegen uses the same normalized names as the symbol table
    std::string normalizeVariableName(const std::string& varName) const;
};

} // namespace fbc

#endif // AST_EMITTER_H