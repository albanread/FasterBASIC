#ifndef QBE_CODEGEN_V2_H
#define QBE_CODEGEN_V2_H

#include <string>
#include <memory>
#include <vector>
#include "../fasterbasic_ast.h"
#include "../fasterbasic_cfg.h"
#include "../fasterbasic_semantic.h"
#include "../fasterbasic_data_preprocessor.h"
#include "qbe_builder.h"
#include "type_manager.h"
#include "symbol_mapper.h"
#include "runtime_library.h"
#include "ast_emitter.h"
#include "cfg_emitter.h"

namespace fbc {

/**
 * QBECodeGeneratorV2 - Main code generation orchestrator
 * 
 * This is the top-level component that coordinates all code generation.
 * It replaces the old code generator with a CFG-v2-aware implementation.
 * 
 * Responsibilities:
 * - Overall code generation flow
 * - Global declarations (variables, functions, arrays)
 * - Function/subroutine generation
 * - Integration with compiler pipeline
 * - IL output management
 * 
 * Architecture:
 * - Uses QBEBuilder for low-level IL emission
 * - Uses TypeManager for type mapping
 * - Uses SymbolMapper for name mangling
 * - Uses RuntimeLibrary for runtime calls
 * - Uses ASTEmitter for statement/expression code
 * - Uses CFGEmitter for control flow
 */
class QBECodeGeneratorV2 {
public:
    /**
     * Constructor
     * @param semantic Semantic analyzer with symbol table
     */
    explicit QBECodeGeneratorV2(FasterBASIC::SemanticAnalyzer& semantic);
    
    ~QBECodeGeneratorV2();

    // === Main Generation Entry Points ===
    
    /**
     * Generate QBE IL for an entire program
     * @param program Program AST root
     * @param programCFG Complete program CFG (main + all functions/subs)
     * @return Generated QBE IL as string
     */
    std::string generateProgram(const FasterBASIC::Program* program,
                                const FasterBASIC::ProgramCFG* programCFG);
    
    /**
     * Generate QBE IL for a function
     * @param funcSymbol Function symbol table entry
     * @param cfg Function CFG
     * @return Generated QBE IL as string
     */
    std::string generateFunction(const FasterBASIC::FunctionSymbol* funcSymbol,
                                 const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Generate QBE IL for a SUB
     * @param subSymbol SUB symbol table entry
     * @param cfg SUB CFG
     * @return Generated QBE IL as string
     */
    std::string generateSub(const FasterBASIC::FunctionSymbol* subSymbol,
                           const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Set DATA values from preprocessor
     * @param dataResult Preprocessed DATA values, restore points, and labels
     */
    void setDataValues(const FasterBASIC::DataPreprocessorResult& dataResult);

    // === Global Declarations ===
    
    /**
     * Emit DATA segment as global read-only data
     */
    void emitDataSegment();
    
    /**
     * Emit global variable declarations
     */
    void emitGlobalVariables();
    
    /**
     * Emit global array declarations
     */
    void emitGlobalArrays();
    
    /**
     * Emit string constant pool
     */
    void emitStringConstants();
    
    /**
     * Emit runtime function declarations (external)
     */
    void emitRuntimeDeclarations();
    
    /**
     * Emit GOSUB return stack (global data for GOSUB/RETURN)
     */
    void emitGosubReturnStack();

    // === Main Program Generation ===
    
    /**
     * Generate the main function
     * @param cfg Main program CFG
     */
    void generateMainFunction(const FasterBASIC::ControlFlowGraph* cfg);

    // === Output Management ===
    
    /**
     * Get the complete generated IL
     * @return QBE IL as string
     */
    std::string getIL() const;
    
    /**
     * Clear generated IL (useful for testing)
     */
    void reset();
    
    /**
     * Enable/disable verbose comments in generated IL
     * @param verbose True to enable verbose comments
     */
    void setVerbose(bool verbose);
    
    /**
     * Enable/disable optimization
     * @param optimize True to enable optimization
     */
    void setOptimize(bool optimize);

    // === Component Access (for testing/debugging) ===
    
    QBEBuilder& getBuilder() { return *builder_; }
    TypeManager& getTypeManager() { return *typeManager_; }
    SymbolMapper& getSymbolMapper() { return *symbolMapper_; }
    RuntimeLibrary& getRuntimeLibrary() { return *runtime_; }
    ASTEmitter& getASTEmitter() { return *astEmitter_; }
    CFGEmitter& getCFGEmitter() { return *cfgEmitter_; }

private:
    // Semantic analyzer reference
    FasterBASIC::SemanticAnalyzer& semantic_;
    
    // Core components (owned)
    // Components
    std::unique_ptr<QBEBuilder> builder_;
    std::unique_ptr<TypeManager> typeManager_;
    std::unique_ptr<SymbolMapper> symbolMapper_;
    std::unique_ptr<RuntimeLibrary> runtime_;
    std::unique_ptr<ASTEmitter> astEmitter_;
    std::unique_ptr<CFGEmitter> cfgEmitter_;
    
    // Configuration
    bool verbose_;
    bool optimize_;
    
    // DATA segment
    FasterBASIC::DataPreprocessorResult dataValues_;
    
    // === Helper Methods ===
    
    /**
     * Initialize all components
     */
    void initializeComponents();
    
    /**
     * Emit file header comment
     */
    void emitFileHeader();
    
    /**
     * Emit a global variable
     * @param varSymbol Variable symbol
     */
    void emitGlobalVariable(const FasterBASIC::VariableSymbol* varSymbol);
    
    /**
     * Emit a global array
     * @param arraySymbol Array symbol
     */
    void emitGlobalArray(const FasterBASIC::ArraySymbol* arraySymbol);
    
    /**
     * Get all global variables from semantic analyzer
     * @return List of global variable symbols
     */
    std::vector<FasterBASIC::VariableSymbol*> getGlobalVariables();
    
    /**
     * Get all global arrays from semantic analyzer
     * @return List of global array symbols
     */
    std::vector<FasterBASIC::ArraySymbol*> getGlobalArrays();
    
    /**
     * Get all functions from semantic analyzer
     * @return List of function symbols
     */
    std::vector<FasterBASIC::FunctionSymbol*> getFunctions();
    
    // === String Collection (Phase 1) ===
    
    /**
     * Collect all string literals from the program and all SUBs/FUNCTIONs
     * @param program Program AST
     * @param programCFG Program CFG containing all function/sub CFGs
     */
    void collectStringLiterals(const FasterBASIC::Program* program,
                              const FasterBASIC::ProgramCFG* programCFG);
    
    /**
     * Recursively collect strings from a statement
     * @param stmt Statement to scan
     */
    void collectStringsFromStatement(const FasterBASIC::Statement* stmt);
    
    /**
     * Recursively collect strings from an expression
     * @param expr Expression to scan
     */
    void collectStringsFromExpression(const FasterBASIC::Expression* expr);
    
    /**
     * Register SHARED variables from a function/SUB CFG
     * Scans the CFG for SHARED statements and registers them with the symbol mapper
     * @param cfg Function CFG to scan
     * @param symbolMapper Symbol mapper to register variables with
     */
    static void registerSharedVariables(const FasterBASIC::ControlFlowGraph* cfg,
                                       SymbolMapper* symbolMapper);
};

} // namespace fbc

#endif // QBE_CODEGEN_V2_H