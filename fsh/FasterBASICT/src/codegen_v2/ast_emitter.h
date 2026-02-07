#ifndef AST_EMITTER_H
#define AST_EMITTER_H

#include <string>
#include <vector>
#include <unordered_map>
#include <unordered_set>
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

    /**
     * Check if SAMM (Scope-Aware Memory Management) is enabled.
     * Returns false when the program contains OPTION SAMM OFF.
     */
    bool isSAMMEnabled() const;

    // === Expression Emission ===
    
    /**
     * Emit code for an expression
     * @param expr Expression to emit
     * @return Temporary holding the result value
     */
    std::string emitExpression(const FasterBASIC::Expression* expr);
    
    /**
     * Set the current CLASS context for METHOD/CONSTRUCTOR/DESTRUCTOR emission.
     * This allows ME references to resolve to the correct class.
     * Pass nullptr to clear the context.
     * @param cls The ClassSymbol for the current class, or nullptr
     */
    void setCurrentClassContext(const FasterBASIC::ClassSymbol* cls) { currentClassContext_ = cls; }
    
    /**
     * Get the current CLASS context (may be nullptr if not inside a method)
     */
    const FasterBASIC::ClassSymbol* getCurrentClassContext() const { return currentClassContext_; }

    /**
     * Set/get the current FOR EACH statement whose body is being emitted.
     * Used by MATCH TYPE to resolve which loop's slots to consult.
     */
    void setCurrentForEachStmt(const FasterBASIC::ForInStatement* stmt) { currentForEachStmt_ = stmt; }
    const FasterBASIC::ForInStatement* getCurrentForEachStmt() const { return currentForEachStmt_; }
    
    /**
     * Set the return type for the current METHOD being emitted.
     * When non-VOID, emitReturnStatement will emit a direct `ret <value>`
     * instead of looking up a FUNCTION return variable.
     * Pass BaseType::VOID to clear (e.g. after method emission).
     * @param type The METHOD's return BaseType
     */
    void setMethodReturnType(FasterBASIC::BaseType type) { methodReturnType_ = type; }
    
    /**
     * Get the current METHOD return type (VOID if not inside a method).
     */
    FasterBASIC::BaseType getMethodReturnType() const { return methodReturnType_; }

    /**
     * Set the current METHOD name being emitted.
     * Used to detect return-via-assignment (e.g., `Hello = "Hi"` inside
     * METHOD Hello() AS STRING).  The name is compared case-insensitively
     * against LET assignment targets.
     * Pass an empty string to clear after method emission.
     * @param name The METHOD name (e.g. "Hello", "GetName$")
     */
    void setMethodName(const std::string& name) { methodName_ = name; }

    /**
     * Get the current METHOD name (empty if not inside a method).
     */
    const std::string& getMethodName() const { return methodName_; }

    /**
     * Set the QBE stack-slot name for the method return variable.
     * Allocated by emitClassMethod when the method has a non-void return type.
     * @param slot QBE address (e.g. "%method_ret")
     */
    void setMethodReturnSlot(const std::string& slot) { methodReturnSlot_ = slot; }

    /**
     * Get the QBE stack-slot name for the method return variable.
     */
    const std::string& getMethodReturnSlot() const { return methodReturnSlot_; }
    
    /**
     * Emit a sequence of statements (used for METHOD/CONSTRUCTOR/DESTRUCTOR bodies).
     * Iterates through the statement list and emits each one via emitStatement().
     * @param body Vector of statements to emit
     */
    void emitMethodBody(const std::vector<FasterBASIC::StatementPtr>& body);
    
    /**
     * Register a METHOD/CONSTRUCTOR parameter so that loadVariable/getVariableAddress
     * can resolve it during method body emission.
     * Parameters are stored in a separate map (methodParamAddresses_ / methodParamTypes_)
     * and take priority over normal symbol table lookups.
     * @param name   Raw parameter name (e.g. "n")
     * @param addr   QBE address of the parameter's stack slot (e.g. "%var_n")
     * @param type   BaseType of the parameter
     */
    void registerMethodParam(const std::string& name, const std::string& addr, FasterBASIC::BaseType type);
    
    /**
     * Clear all registered method parameters (call after emitting a method body).
     */
    void clearMethodParams();
    
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
     * Emit FOR EACH / FOR...IN loop initialization
     * Sets up internal index variable (= LBOUND), stores UBOUND limit.
     * @param stmt ForInStatement
     */
    void emitForEachInit(const FasterBASIC::ForInStatement* stmt);

    /**
     * Pre-allocate stack slots for FOR EACH loop temporaries in the entry block.
     * Must be called during entry block emission so that alloc instructions
     * are in the start block (QBE requirement). The init method will then
     * only emit stores into the pre-allocated slots.
     * @param stmt ForInStatement
     */
    void preAllocateForEachSlots(const FasterBASIC::ForInStatement* stmt);

    /**
     * Pre-allocate stack slots for regular FOR loop temporaries (limit, step)
     * in the entry block. Must be called during entry block emission.
     * @param stmt ForStatement
     */
    void preAllocateForSlots(const FasterBASIC::ForStatement* stmt);

    /**
     * Pre-allocate shared scratch buffers (bounds array for DIM, indices
     * array for array access) in the entry block.  Must be called once
     * during entry block emission so that the resulting alloc instructions
     * are in QBE's start block.
     */
    void preAllocateSharedBuffers();
    
    /**
     * Emit FOR EACH / FOR...IN loop condition check
     * @param stmt ForInStatement
     * @return Temporary holding condition result (index <= ubound)
     */
    std::string emitForEachCondition(const FasterBASIC::ForInStatement* stmt);
    
    /**
     * Emit FOR EACH / FOR...IN loop increment (index += 1)
     * @param stmt ForInStatement
     */
    void emitForEachIncrement(const FasterBASIC::ForInStatement* stmt);
    
    /**
     * Emit FOR EACH / FOR...IN body preamble
     * Loads arr(index) into the element variable, and optionally sets
     * the user-visible index variable.
     * @param stmt ForInStatement
     */
    void emitForEachBodyPreamble(const FasterBASIC::ForInStatement* stmt);

    /**
     * Emit FOR EACH / FOR...IN exit cleanup
     * For hashmap iteration, frees the keys array allocated during init.
     * No-op for array iteration.
     * @param stmt ForInStatement
     */
    void emitForEachCleanup(const FasterBASIC::ForInStatement* stmt);
    
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
     * Emit MATCH TYPE statement (safe type dispatch for LIST OF ANY)
     * @param stmt MATCH TYPE statement
     */
    void emitMatchTypeStatement(const FasterBASIC::MatchTypeStatement* stmt);
    
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
    
    // FOR EACH variable element types — maps raw variable name (e.g. "n")
    // to the BaseType of the array element so that loadVariable /
    // storeVariable / getVariableAddress can resolve FOR EACH iteration
    // variables that are intentionally kept out of the symbol table.
    std::unordered_map<std::string, FasterBASIC::BaseType> forEachVarTypes_;

    // FOR EACH hashmap tracking — set of primary loop variable names
    // whose FOR EACH loop iterates over a HASHMAP rather than an array.
    // Used by emitForEachCondition / BodyPreamble / Increment to choose
    // the correct lowering (keys-array iteration vs array element access).
    std::unordered_set<std::string> forEachIsHashmap_;

    // FOR EACH list tracking — set of primary loop variable names
    // whose FOR EACH loop iterates over a LIST rather than an array.
    // Used by emitForEachCondition / BodyPreamble / Increment to choose
    // cursor-based linked list traversal.
    std::unordered_set<std::string> forEachIsList_;

    // FOR EACH list element type — maps loop variable name to the
    // list's element BaseType (e.g. INTEGER for LIST OF INTEGER,
    // UNKNOWN for LIST OF ANY). Used by body preamble to select
    // the correct list_iter_value_* function.
    std::unordered_map<std::string, FasterBASIC::BaseType> forEachListElemType_;

    // Shared bounds buffer for DIM/REDIM array statements.
    // Pre-allocated in the entry block so that alloc instructions
    // are never emitted in non-start blocks (QBE requirement).
    // Sized for 8 dimensions × 2 bounds × 4 bytes = 64 bytes.
    std::string sharedBoundsBuffer_;

    // Shared indices buffer for array element access (array_get_address).
    // Pre-allocated in the entry block.
    // Sized for 8 dimensions × 4 bytes = 32 bytes.
    std::string sharedIndicesBuffer_;

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

    // === CLASS context ===
    // Tracks the current CLASS being emitted (for METHOD/CONSTRUCTOR/DESTRUCTOR bodies).
    // Used to resolve ME.Field accesses and ME.Method() calls to the correct class.
    const FasterBASIC::ClassSymbol* currentClassContext_ = nullptr;

    // When true, IF/FOR/WHILE statements use direct inline emission instead of
    // being delegated to CFG edges.  Set inside MATCH TYPE arm bodies where the
    // CFG builder does not recurse into nested control flow.
    bool inDirectEmitContext_ = false;

    // Tracks the current FOR EACH statement whose body is being emitted.
    // Set by the CFG emitter when entering a ForIn_Body block so that
    // MATCH TYPE can determine which loop's slots to use (avoids
    // confusion when multiple loops share the same variable name).
    const FasterBASIC::ForInStatement* currentForEachStmt_ = nullptr;
    
    // === METHOD return type context ===
    // When emitting a METHOD body that has a return value, this is set to the
    // method's return BaseType so that emitReturnStatement can emit a direct
    // `ret <value>` instead of the FUNCTION-style store-and-jump pattern.
    // Set to VOID (default) when not inside a method body.
    FasterBASIC::BaseType methodReturnType_ = FasterBASIC::BaseType::VOID;

    // === METHOD name context ===
    // When emitting a METHOD body, this holds the method's name so that
    // assignment-to-method-name (e.g., `Hello = "Hi"`) can be detected and
    // routed to the method return slot instead of a regular variable store.
    std::string methodName_;

    // === METHOD return-value stack slot ===
    // QBE address of the stack slot allocated for method return-via-assignment.
    // Allocated in emitClassMethod; loaded in the fallback-return path.
    // Empty when not inside a method or when the method is void.
    std::string methodReturnSlot_;
    
    // === METHOD/CONSTRUCTOR parameter maps ===
    // Registered before emitting a method body so that getVariableAddress / loadVariable
    // can resolve parameters that are NOT in the semantic symbol table.
    // Key: raw parameter name (e.g. "n"), Value: QBE stack slot address (e.g. "%var_n")
    std::unordered_map<std::string, std::string> methodParamAddresses_;
    // Key: raw parameter name, Value: BaseType of the parameter
    std::unordered_map<std::string, FasterBASIC::BaseType> methodParamTypes_;
    // Key: raw variable name, Value: CLASS name (e.g. "Item")
    // Only populated for CLASS_INSTANCE variables DIM'd inside METHOD bodies.
    // Used by emitMethodCall to resolve the correct ClassSymbol for virtual dispatch.
    std::unordered_map<std::string, std::string> methodParamClassNames_;
    
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
    std::string emitListConstructor(const FasterBASIC::ListConstructorExpression* expr);
    
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

    // Strip text-form type suffixes (_INT, _LONG, _DOUBLE, _STRING, _FLOAT, _BYTE, _SHORT)
    // from a variable name, returning the base name.  Used to reconcile parser-mangled
    // names (e.g. "m_INT") with method-param registration keys (e.g. "m").
    static std::string stripTextTypeSuffix(const std::string& name);

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

    // === Direct control-flow emission for METHOD bodies ===
    // Method bodies are emitted via emitMethodBody() without CFG infrastructure,
    // so compound statements (IF/FOR/WHILE) need direct inline emission.
    
    /**
     * Emit an IF/ELSEIF/ELSE block directly (without CFG).
     * Used inside METHOD/CONSTRUCTOR/DESTRUCTOR bodies.
     */
    void emitIfDirect(const FasterBASIC::IfStatement* stmt);
    
    /**
     * Emit a FOR..NEXT loop directly (without CFG).
     * Used inside METHOD/CONSTRUCTOR/DESTRUCTOR bodies.
     */
    void emitForDirect(const FasterBASIC::ForStatement* stmt);
    
    /**
     * Check whether a statement list contains any DIM statement (recursively).
     * Used to decide whether SAMM loop-iteration scopes are needed — we only
     * emit samm_enter_scope/samm_exit_scope around loop bodies that actually
     * allocate variables, avoiding overhead on simple loops.
     */
    static bool bodyContainsDim(const std::vector<FasterBASIC::StatementPtr>& body);

    /**
     * Emit a WHILE..WEND loop directly (without CFG).
     * Used inside METHOD/CONSTRUCTOR/DESTRUCTOR bodies.
     */
    void emitWhileDirect(const FasterBASIC::WhileStatement* stmt);

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