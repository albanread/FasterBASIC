#include "qbe_codegen_v2.h"
#include <cstdint>

namespace fbc {

using namespace FasterBASIC;

QBECodeGeneratorV2::QBECodeGeneratorV2(SemanticAnalyzer& semantic)
    : semantic_(semantic)
    , verbose_(false)
    , optimize_(false)
{
    initializeComponents();
}

QBECodeGeneratorV2::~QBECodeGeneratorV2() = default;

bool QBECodeGeneratorV2::isSAMMEnabled() const {
    return semantic_.getSymbolTable().sammEnabled;
}

void QBECodeGeneratorV2::initializeComponents() {
    // Create all components in correct dependency order
    builder_ = std::make_unique<QBEBuilder>();
    typeManager_ = std::make_unique<TypeManager>();
    symbolMapper_ = std::make_unique<SymbolMapper>();
    runtime_ = std::make_unique<RuntimeLibrary>(*builder_, *typeManager_);
    astEmitter_ = std::make_unique<ASTEmitter>(*builder_, *typeManager_, 
                                               *symbolMapper_, *runtime_, semantic_);
    cfgEmitter_ = std::make_unique<CFGEmitter>(*builder_, *typeManager_,
                                               *symbolMapper_, *astEmitter_);
}

// === Main Generation Entry Points ===

std::string QBECodeGeneratorV2::generateProgram(const Program* program,
                                                const ProgramCFG* programCFG) {
    if (!program || !programCFG) {
        builder_->emitComment("ERROR: null program or ProgramCFG");
        return builder_->getIL();
    }
    
    // Store program pointer for CLASS emission
    program_ = program;
    
    // Reset state
    builder_->reset();
    symbolMapper_->reset();
    
    // PHASE 1: Collect all string literals from the entire program
    collectStringLiterals(program, programCFG);
    
    // Emit file header
    emitFileHeader();
    
    // Emit runtime declarations
    emitRuntimeDeclarations();
    
    // PHASE 2: Emit string constant pool (global data section)
    builder_->emitStringPool();
    
    // Emit GOSUB return stack (global data for GOSUB/RETURN)
    emitGosubReturnStack();
    
    // Emit DATA segment
    emitDataSegment();
    
    // Emit global declarations
    emitGlobalVariables();
    emitGlobalArrays();
    
    // Emit CLASS vtables and class name strings (data sections, before functions)
    emitClassDeclarations(program);
    
    builder_->emitBlankLine();
    builder_->emitComment("=== Main Program ===");
    builder_->emitBlankLine();
    
    // PHASE 3: Generate code (strings already in pool)
    generateMainFunction(programCFG->mainCFG.get());
    
    // Generate all user-defined functions and SUBs from ProgramCFG
    for (const auto& [name, cfg] : programCFG->functionCFGs) {
        builder_->emitBlankLine();
        builder_->emitComment("=== Function/Sub: " + name + " ===");
        builder_->emitBlankLine();
        
        // Look up the function symbol from semantic analyzer
        const auto& symbolTable = semantic_.getSymbolTable();
        auto it = symbolTable.functions.find(name);
        const FunctionSymbol* funcSymbol = (it != symbolTable.functions.end()) ? &it->second : nullptr;
        
        if (!funcSymbol) {
            builder_->emitComment("WARNING: Function symbol not found for: " + name);
            continue;
        }
        
        // Determine if it's a SUB or FUNCTION based on return type
        if (cfg->returnType == VariableType::VOID || cfg->returnType == VariableType::UNKNOWN) {
            // It's a SUB
            generateSub(funcSymbol, cfg.get());
        } else {
            // It's a FUNCTION
            generateFunction(funcSymbol, cfg.get());
        }
    }
    
    // Emit any strings that were registered during code generation
    // (e.g. null-check error messages, class method/field names)
    builder_->emitLateStringPool();
    
    return builder_->getIL();
}

std::string QBECodeGeneratorV2::generateFunction(const FunctionSymbol* funcSymbol,
                                                 const ControlFlowGraph* cfg) {
    if (!funcSymbol || !cfg) {
        builder_->emitComment("ERROR: null function symbol or CFG");
        return "";
    }
    
    // Mangle function name
    std::string mangledName = symbolMapper_->mangleFunctionName(funcSymbol->name);
    
    // Get return type
    std::string returnType = typeManager_->getQBEReturnType(funcSymbol->returnTypeDesc.baseType);
    
    // Build parameter list using actual parameter names
    std::string params;
    for (size_t i = 0; i < funcSymbol->parameters.size(); ++i) {
        if (i > 0) params += ", ";
        
        BaseType paramType = funcSymbol->parameterTypeDescs[i].baseType;
        std::string qbeType = typeManager_->getQBEType(paramType);
        
        // Use actual parameter name from CFG (e.g., "a", "b", "msg$")
        std::string paramName = (i < cfg->parameters.size()) ? cfg->parameters[i] : ("arg" + std::to_string(i));
        
        params += qbeType + " %" + paramName;
    }
    
    // Start function
    builder_->emitFunctionStart(mangledName.substr(1), returnType, params);
    builder_->emitComment("TRACE: Started FUNCTION " + funcSymbol->name + " with " + std::to_string(cfg->parameters.size()) + " parameters");
    
    // Enter function scope with RAII guard (ensures exitFunctionScope on any exit path)
    for (size_t i = 0; i < cfg->parameters.size(); ++i) {
        builder_->emitComment("  FUNCTION param[" + std::to_string(i) + "]: " + cfg->parameters[i]);
    }
    FunctionScopeGuard scopeGuard(*symbolMapper_, funcSymbol->name, cfg->parameters);
    
    // Register SHARED variables from this function
    registerSharedVariables(cfg, symbolMapper_.get());
    
    // SAMM: Tell the CFG emitter to emit samm_enter_scope() inside block 0
    // (after the @block_0 label). QBE requires all instructions to be
    // inside a labeled block. samm_exit_scope() is emitted by
    // emitExitBlockTerminator() before each exit `ret`.
    if (isSAMMEnabled()) {
        cfgEmitter_->setSAMMPreamble(CFGEmitter::SAMMPreamble::SCOPE_ENTER, "FUNCTION");
    }
    cfgEmitter_->emitCFG(cfg, funcSymbol->name);
    
    // End function
    builder_->emitFunctionEnd();
    
    return builder_->getIL();
}

std::string QBECodeGeneratorV2::generateSub(const FunctionSymbol* subSymbol,
                                            const ControlFlowGraph* cfg) {
    if (!subSymbol || !cfg) {
        builder_->emitComment("ERROR: null SUB symbol or CFG");
        return "";
    }
    
    // Mangle SUB name
    std::string mangledName = symbolMapper_->mangleSubName(subSymbol->name);
    
    // SUBs have no return type
    std::string returnType = "";
    
    // Build parameter list using actual parameter names
    std::string params;
    for (size_t i = 0; i < subSymbol->parameters.size(); ++i) {
        if (i > 0) params += ", ";
        
        BaseType paramType = subSymbol->parameterTypeDescs[i].baseType;
        std::string qbeType = typeManager_->getQBEType(paramType);
        
        // Use actual parameter name from CFG (e.g., "a%", "b%", "msg$")
        std::string paramName = (i < cfg->parameters.size()) ? cfg->parameters[i] : ("arg" + std::to_string(i));
        
        params += qbeType + " %" + paramName;
    }
    
    // Start function
    builder_->emitFunctionStart(mangledName.substr(1), returnType, params);
    builder_->emitComment("TRACE: Started SUB " + subSymbol->name + " with " + std::to_string(cfg->parameters.size()) + " parameters");
    
    // Enter function scope with RAII guard (ensures exitFunctionScope on any exit path)
    for (size_t i = 0; i < cfg->parameters.size(); ++i) {
        builder_->emitComment("  SUB param[" + std::to_string(i) + "]: " + cfg->parameters[i]);
    }
    FunctionScopeGuard scopeGuard(*symbolMapper_, subSymbol->name, cfg->parameters);
    
    // Register SHARED variables from this SUB
    registerSharedVariables(cfg, symbolMapper_.get());
    
    // SAMM: Tell the CFG emitter to emit samm_enter_scope() inside block 0
    // (after the @block_0 label). QBE requires all instructions to be
    // inside a labeled block. samm_exit_scope() is emitted by
    // emitExitBlockTerminator() before each exit `ret`.
    if (isSAMMEnabled()) {
        cfgEmitter_->setSAMMPreamble(CFGEmitter::SAMMPreamble::SCOPE_ENTER, "SUB");
    }
    cfgEmitter_->emitCFG(cfg, subSymbol->name);
    
    // End function
    builder_->emitFunctionEnd();
    
    return builder_->getIL();
}

// === Global Declarations ===

void QBECodeGeneratorV2::emitGlobalVariables() {
    std::vector<VariableSymbol*> globals = getGlobalVariables();
    
    if (globals.empty()) {
        return;
    }
    
    builder_->emitComment("=== Global Variables ===");
    builder_->emitBlankLine();
    
    for (VariableSymbol* varSymbol : globals) {
        emitGlobalVariable(varSymbol);
    }
    
    builder_->emitBlankLine();
}

void QBECodeGeneratorV2::emitGlobalArrays() {
    std::vector<ArraySymbol*> arrays = getGlobalArrays();
    
    if (arrays.empty()) {
        return;
    }
    
    builder_->emitComment("=== Global Arrays ===");
    builder_->emitBlankLine();
    
    for (ArraySymbol* arraySymbol : arrays) {
        emitGlobalArray(arraySymbol);
    }
    
    builder_->emitBlankLine();
}

void QBECodeGeneratorV2::emitStringConstants() {
    // String constants are emitted on-demand by ASTEmitter
    // This method is here for completeness
}

void QBECodeGeneratorV2::emitRuntimeDeclarations() {
    builder_->emitComment("=== Runtime Library Declarations ===");
    builder_->emitComment("Runtime functions are linked from runtime_c library");
    builder_->emitBlankLine();
}

void QBECodeGeneratorV2::emitGosubReturnStack() {
    builder_->emitBlankLine();
    builder_->emitComment("=== GOSUB Return Stack ===");
    builder_->emitComment("Stack for GOSUB/RETURN statements (" +
                          std::to_string(GOSUB_STACK_DEPTH) + " levels deep)");
    builder_->emitBlankLine();
    
    // Emit return stack: GOSUB_STACK_DEPTH-word array to hold return block IDs
    builder_->emitRaw("export data $gosub_return_stack = { ");
    for (int i = 0; i < GOSUB_STACK_DEPTH; i++) {
        builder_->emitRaw("w 0");
        if (i < GOSUB_STACK_DEPTH - 1) {
            builder_->emitRaw(", ");
        }
    }
    builder_->emitRaw(" }\n");
    
    // Emit stack pointer: current depth (0 = empty)
    builder_->emitRaw("export data $gosub_return_sp = { w 0 }\n");
    builder_->emitBlankLine();
}

// === Main Program Generation ===

void QBECodeGeneratorV2::generateMainFunction(const ControlFlowGraph* cfg) {
    if (!cfg) {
        builder_->emitComment("ERROR: null CFG for main");
        return;
    }
    
    // Start main function
    builder_->emitFunctionStart("main", "w", "");
    
    // Enter global scope with RAII guard
    FunctionScopeGuard scopeGuard(*symbolMapper_, "main");
    
    // SAMM: Tell the CFG emitter to emit samm_init() inside block 0
    // (after the @block_0 label). QBE requires all instructions to be
    // inside a labeled block, so we cannot emit calls before the first label.
    // samm_shutdown() is emitted by emitExitBlockTerminator() and
    // emitEndStatement() before each exit point.
    if (isSAMMEnabled()) {
        cfgEmitter_->setSAMMPreamble(CFGEmitter::SAMMPreamble::MAIN_INIT, "main");
    }
    cfgEmitter_->emitCFG(cfg, "main");
    
    // End main function (scope guard exits function scope automatically)
    builder_->emitFunctionEnd();
}

// === Output Management ===

std::string QBECodeGeneratorV2::getIL() const {
    return builder_->getIL();
}

void QBECodeGeneratorV2::reset() {
    builder_->reset();
    symbolMapper_->reset();
    cfgEmitter_->reset();
}

void QBECodeGeneratorV2::setVerbose(bool verbose) {
    verbose_ = verbose;
}

void QBECodeGeneratorV2::setOptimize(bool optimize) {
    optimize_ = optimize;
}

// === Helper Methods ===

void QBECodeGeneratorV2::emitFileHeader() {
    builder_->emitComment("=======================================================");
    builder_->emitComment("  QBE IL Generated by FasterBASIC Compiler");
    builder_->emitComment("  Code Generator: V2 (CFG-aware)");
    builder_->emitComment("=======================================================");
    builder_->emitBlankLine();
}

void QBECodeGeneratorV2::emitGlobalVariable(const VariableSymbol* varSymbol) {
    if (!varSymbol) {
        return;
    }
    
    // Mangle variable name
    std::string mangledName = symbolMapper_->mangleVariableName(varSymbol->name, true);
    
    BaseType varType = varSymbol->typeDesc.baseType;
    
    // Handle UDT types specially - allocate space for the entire struct
    if (varType == BaseType::USER_DEFINED) {
        const auto& symbolTable = semantic_.getSymbolTable();
        auto udtIt = symbolTable.types.find(varSymbol->typeName);
        if (udtIt != symbolTable.types.end()) {
            const auto& udtDef = udtIt->second;
            int udtSize = typeManager_->getUDTSizeRecursive(udtDef, symbolTable.types);
            
            // Check if SIMD-eligible for 16-byte alignment
            auto simdInfo = typeManager_->getSIMDInfo(udtDef);
            bool needsAlign16 = simdInfo.isValid() && simdInfo.isFullQ;
            
            if (needsAlign16) {
                // Pad to 16 bytes and request alignment
                int alignedSize = (udtSize + 15) & ~15;
                builder_->emitComment("Global UDT (NEON-aligned): " + varSymbol->name + " (type: " + varSymbol->typeName + ", size: " + std::to_string(alignedSize) + " bytes)");
                builder_->emitRaw("export data " + mangledName + " = align 16 { z " + std::to_string(alignedSize) + " }");
            } else {
                // Emit UDT as a zeroed byte array of the appropriate size
                builder_->emitComment("Global UDT: " + varSymbol->name + " (type: " + varSymbol->typeName + ", size: " + std::to_string(udtSize) + " bytes)");
                builder_->emitRaw("export data " + mangledName + " = { z " + std::to_string(udtSize) + " }");
            }
            return;
        }
    }
    
    // Get QBE type for non-UDT types
    std::string qbeType = typeManager_->getQBEType(varType);
    
    // Get default value
    std::string defaultValue = typeManager_->getDefaultValue(varType);
    
    // Emit global data declaration
    builder_->emitGlobalData(mangledName, qbeType, defaultValue);
}

void QBECodeGeneratorV2::emitGlobalArray(const ArraySymbol* arraySymbol) {
    if (!arraySymbol) {
        return;
    }
    
    // Get array descriptor name
    std::string descName = symbolMapper_->getArrayDescriptorName(arraySymbol->name);
    
    // Arrays are allocated and initialized by DIM statements at runtime
    // Here we just emit the descriptor storage (64 bytes = 8 longs, zero-initialized)
    builder_->emitComment("Array descriptor: " + arraySymbol->name);
    builder_->emitGlobalData(descName, "l", "0, l 0, l 0, l 0, l 0, l 0, l 0, l 0");
}

std::vector<VariableSymbol*> QBECodeGeneratorV2::getGlobalVariables() {
    std::vector<VariableSymbol*> globals;
    
    // Get all variables from semantic analyzer
    const auto& symbolTable = semantic_.getSymbolTable();
    for (const auto& entry : symbolTable.variables) {
        VariableSymbol* varSymbol = const_cast<VariableSymbol*>(&entry.second);
        // Include explicitly GLOBAL variables
        if (varSymbol && varSymbol->isGlobal) {
            globals.push_back(varSymbol);
        }
        // Also include OBJECT types in main's global scope (hashmaps, etc.)
        // These need to be globals to avoid stack addressing issues
        else if (varSymbol && varSymbol->typeDesc.baseType == BaseType::OBJECT && 
                 varSymbol->scope.isGlobal()) {
            globals.push_back(varSymbol);
        }
        // Also include UDT (User-Defined Type) variables in main's global scope
        // UDTs should be emitted as global data to ensure proper addressing
        else if (varSymbol && varSymbol->typeDesc.baseType == BaseType::USER_DEFINED && 
                 varSymbol->scope.isGlobal()) {
            globals.push_back(varSymbol);
        }
    }
    
    return globals;
}

std::vector<ArraySymbol*> QBECodeGeneratorV2::getGlobalArrays() {
    std::vector<ArraySymbol*> arrays;
    
    // Get all arrays from semantic analyzer
    const auto& symbolTable = semantic_.getSymbolTable();
    for (const auto& entry : symbolTable.arrays) {
        ArraySymbol* arraySymbol = const_cast<ArraySymbol*>(&entry.second);
        if (arraySymbol) {
            // Check if array is global (not in a function scope)
            if (arraySymbol->functionScope.empty()) {
                arrays.push_back(arraySymbol);
            }
        }
    }
    
    return arrays;
}

std::vector<FunctionSymbol*> QBECodeGeneratorV2::getFunctions() {
    std::vector<FunctionSymbol*> functions;
    
    // Get all functions from semantic analyzer
    const auto& symbolTable = semantic_.getSymbolTable();
    for (const auto& entry : symbolTable.functions) {
        FunctionSymbol* funcSymbol = const_cast<FunctionSymbol*>(&entry.second);
        if (funcSymbol) {
            functions.push_back(funcSymbol);
        }
    }
    
    return functions;
}

// === String Collection ===

void QBECodeGeneratorV2::collectStringLiterals(const Program* program, const ProgramCFG* programCFG) {
    if (!program) return;
    
    // Scan all main program lines for string literals
    for (const auto& line : program->lines) {
        if (!line) continue;
        
        for (const auto& stmt : line->statements) {
            if (stmt) {
                collectStringsFromStatement(stmt.get());
            }
        }
    }
    
    // Scan main program CFG blocks (for strings in control flow structures like SELECT CASE)
    if (programCFG && programCFG->mainCFG) {
        for (const auto& block : programCFG->mainCFG->blocks) {
            if (!block) continue;
            
            // Scan all statements in this block
            for (const Statement* stmt : block->statements) {
                if (stmt) {
                    collectStringsFromStatement(stmt);
                }
            }
        }
    }
    
    // Scan all SUBs/FUNCTIONs for string literals
    if (programCFG) {
        for (const auto& [name, cfg] : programCFG->functionCFGs) {
            if (!cfg) continue;
            
            // Scan all blocks in this function/sub CFG
            for (const auto& block : cfg->blocks) {
                if (!block) continue;
                
                // Scan all statements in this block
                for (const Statement* stmt : block->statements) {
                    if (stmt) {
                        collectStringsFromStatement(stmt);
                    }
                }
            }
        }
    }
    
    // Collect string literals from DATA values
    for (const auto& value : dataValues_.values) {
        if (std::holds_alternative<std::string>(value)) {
            const std::string& strValue = std::get<std::string>(value);
            builder_->registerString(strValue);
        }
    }
}

void QBECodeGeneratorV2::collectStringsFromStatement(const Statement* stmt) {
    if (!stmt) return;
    
    switch (stmt->getType()) {
        case ASTNodeType::STMT_PRINT: {
            const auto* printStmt = static_cast<const PrintStatement*>(stmt);
            for (const auto& item : printStmt->items) {
                if (item.expr) {
                    collectStringsFromExpression(item.expr.get());
                }
            }
            break;
        }
        
        case ASTNodeType::STMT_LET: {
            const auto* letStmt = static_cast<const LetStatement*>(stmt);
            // Collect from indices (array/hashmap subscripts)
            for (const auto& idx : letStmt->indices) {
                if (idx) {
                    collectStringsFromExpression(idx.get());
                }
            }
            // Collect from value (right-hand side)
            if (letStmt->value) {
                collectStringsFromExpression(letStmt->value.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_IF: {
            const auto* ifStmt = static_cast<const IfStatement*>(stmt);
            if (ifStmt->condition) {
                collectStringsFromExpression(ifStmt->condition.get());
            }
            for (const auto& s : ifStmt->thenStatements) {
                if (s) collectStringsFromStatement(s.get());
            }
            for (const auto& s : ifStmt->elseStatements) {
                if (s) collectStringsFromStatement(s.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_FOR: {
            const auto* forStmt = static_cast<const ForStatement*>(stmt);
            if (forStmt->start) {
                collectStringsFromExpression(forStmt->start.get());
            }
            if (forStmt->end) {
                collectStringsFromExpression(forStmt->end.get());
            }
            if (forStmt->step) {
                collectStringsFromExpression(forStmt->step.get());
            }
            for (const auto& s : forStmt->body) {
                if (s) collectStringsFromStatement(s.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_WHILE: {
            const auto* whileStmt = static_cast<const WhileStatement*>(stmt);
            if (whileStmt->condition) {
                collectStringsFromExpression(whileStmt->condition.get());
            }
            for (const auto& s : whileStmt->body) {
                if (s) collectStringsFromStatement(s.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_CALL: {
            const auto* callStmt = static_cast<const CallStatement*>(stmt);
            // Scan arguments of the CALL statement
            for (const auto& arg : callStmt->arguments) {
                if (arg) {
                    collectStringsFromExpression(arg.get());
                }
            }
            // Also scan method call expression if this is a method call statement
            if (callStmt->methodCallExpr) {
                collectStringsFromExpression(callStmt->methodCallExpr.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_SLICE_ASSIGN: {
            const auto* sliceStmt = static_cast<const SliceAssignStatement*>(stmt);
            // Collect strings from start, end, and replacement expressions
            if (sliceStmt->start) {
                collectStringsFromExpression(sliceStmt->start.get());
            }
            if (sliceStmt->end) {
                collectStringsFromExpression(sliceStmt->end.get());
            }
            if (sliceStmt->replacement) {
                collectStringsFromExpression(sliceStmt->replacement.get());
            }
            break;
        }
        
        case ASTNodeType::STMT_CASE: {
            const auto* caseStmt = static_cast<const CaseStatement*>(stmt);
            // Collect strings from the case expression
            if (caseStmt->caseExpression) {
                collectStringsFromExpression(caseStmt->caseExpression.get());
            }
            // Collect strings from each WHEN clause
            for (const auto& whenClause : caseStmt->whenClauses) {
                // Collect from case values
                for (const auto& value : whenClause.values) {
                    if (value) {
                        collectStringsFromExpression(value.get());
                    }
                }
                // Collect from CASE IS right expression
                if (whenClause.caseIsRightExpr) {
                    collectStringsFromExpression(whenClause.caseIsRightExpr.get());
                }
                // Collect from range expressions
                if (whenClause.rangeStart) {
                    collectStringsFromExpression(whenClause.rangeStart.get());
                }
                if (whenClause.rangeEnd) {
                    collectStringsFromExpression(whenClause.rangeEnd.get());
                }
                // Collect from statements in the WHEN clause
                for (const auto& s : whenClause.statements) {
                    if (s) {
                        collectStringsFromStatement(s.get());
                    }
                }
            }
            // Collect strings from OTHERWISE/CASE ELSE statements
            for (const auto& s : caseStmt->otherwiseStatements) {
                if (s) {
                    collectStringsFromStatement(s.get());
                }
            }
            break;
        }
        
        case ASTNodeType::STMT_CLASS: {
            const auto* classStmt = static_cast<const ClassStatement*>(stmt);
            // Collect strings from constructor body and arguments
            if (classStmt->constructor) {
                for (const auto& s : classStmt->constructor->body) {
                    if (s) collectStringsFromStatement(s.get());
                }
                // Collect from SUPER() arguments
                for (const auto& arg : classStmt->constructor->superArgs) {
                    if (arg) collectStringsFromExpression(arg.get());
                }
            }
            // Collect strings from destructor body
            if (classStmt->destructor) {
                for (const auto& s : classStmt->destructor->body) {
                    if (s) collectStringsFromStatement(s.get());
                }
            }
            // Collect strings from method bodies
            for (const auto& method : classStmt->methods) {
                if (method) {
                    for (const auto& s : method->body) {
                        if (s) collectStringsFromStatement(s.get());
                    }
                }
            }
            break;
        }
        
        case ASTNodeType::STMT_DIM: {
            const auto* dimStmt = static_cast<const DimStatement*>(stmt);
            for (const auto& arr : dimStmt->arrays) {
                for (const auto& dim : arr.dimensions) {
                    if (dim) collectStringsFromExpression(dim.get());
                }
                if (arr.initializer) {
                    collectStringsFromExpression(arr.initializer.get());
                }
            }
            break;
        }
        
        case ASTNodeType::STMT_DELETE: {
            // DELETE has no expressions to collect from
            break;
        }
        
        case ASTNodeType::STMT_LOCAL: {
            const auto* localStmt = static_cast<const LocalStatement*>(stmt);
            for (const auto& var : localStmt->variables) {
                if (var.initialValue) {
                    collectStringsFromExpression(var.initialValue.get());
                }
            }
            break;
        }
        
        case ASTNodeType::STMT_RETURN: {
            const auto* retStmt = static_cast<const ReturnStatement*>(stmt);
            if (retStmt->returnValue) {
                collectStringsFromExpression(retStmt->returnValue.get());
            }
            break;
        }
        
        // Add more statement types as needed
        default:
            break;
    }
}

void QBECodeGeneratorV2::collectStringsFromExpression(const Expression* expr) {
    if (!expr) return;
    
    switch (expr->getType()) {
        case ASTNodeType::EXPR_STRING: {
            const auto* strLit = static_cast<const StringExpression*>(expr);
            // Register this string in the pool
            builder_->registerString(strLit->value);
            break;
        }
        
        case ASTNodeType::EXPR_BINARY: {
            const auto* binExpr = static_cast<const BinaryExpression*>(expr);
            collectStringsFromExpression(binExpr->left.get());
            collectStringsFromExpression(binExpr->right.get());
            break;
        }
        
        case ASTNodeType::EXPR_UNARY: {
            const auto* unaryExpr = static_cast<const UnaryExpression*>(expr);
            collectStringsFromExpression(unaryExpr->expr.get());
            break;
        }
        
        case ASTNodeType::EXPR_FUNCTION_CALL: {
            const auto* callExpr = static_cast<const FunctionCallExpression*>(expr);
            for (const auto& arg : callExpr->arguments) {
                if (arg) collectStringsFromExpression(arg.get());
            }
            break;
        }
        
        case ASTNodeType::EXPR_ARRAY_ACCESS: {
            const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr);
            for (const auto& idx : arrExpr->indices) {
                if (idx) collectStringsFromExpression(idx.get());
            }
            break;
        }
        
        case ASTNodeType::EXPR_IIF: {
            const auto* iifExpr = static_cast<const IIFExpression*>(expr);
            if (iifExpr->condition) collectStringsFromExpression(iifExpr->condition.get());
            if (iifExpr->trueValue) collectStringsFromExpression(iifExpr->trueValue.get());
            if (iifExpr->falseValue) collectStringsFromExpression(iifExpr->falseValue.get());
            break;
        }
        
        case ASTNodeType::EXPR_MEMBER_ACCESS: {
            const auto* memberExpr = static_cast<const MemberAccessExpression*>(expr);
            if (memberExpr->object) collectStringsFromExpression(memberExpr->object.get());
            break;
        }
        
        case ASTNodeType::EXPR_ARRAY_BINOP: {
            const auto* arrBinOp = static_cast<const ArrayBinaryOpExpression*>(expr);
            if (arrBinOp->leftArray) collectStringsFromExpression(arrBinOp->leftArray.get());
            if (arrBinOp->rightExpr) collectStringsFromExpression(arrBinOp->rightExpr.get());
            break;
        }
        
        case ASTNodeType::EXPR_METHOD_CALL: {
            const auto* methodCall = static_cast<const MethodCallExpression*>(expr);
            if (methodCall->object) collectStringsFromExpression(methodCall->object.get());
            for (const auto& arg : methodCall->arguments) {
                if (arg) collectStringsFromExpression(arg.get());
            }
            break;
        }
        
        case ASTNodeType::EXPR_NEW: {
            const auto* newExpr = static_cast<const NewExpression*>(expr);
            for (const auto& arg : newExpr->arguments) {
                if (arg) collectStringsFromExpression(arg.get());
            }
            break;
        }
        
        case ASTNodeType::EXPR_SUPER_CALL: {
            const auto* superCall = static_cast<const SuperCallExpression*>(expr);
            for (const auto& arg : superCall->arguments) {
                if (arg) collectStringsFromExpression(arg.get());
            }
            break;
        }
        
        case ASTNodeType::EXPR_IS_TYPE: {
            const auto* isExpr = static_cast<const IsTypeExpression*>(expr);
            if (isExpr->object) collectStringsFromExpression(isExpr->object.get());
            break;
        }
        
        // Add more expression types as needed
        default:
            break;
    }
}

void QBECodeGeneratorV2::setDataValues(const DataPreprocessorResult& dataResult) {
    dataValues_ = dataResult;
}

void QBECodeGeneratorV2::emitDataSegment() {
    if (dataValues_.values.empty()) {
        return;
    }
    
    builder_->emitBlankLine();
    builder_->emitComment("=== DATA Segment ===");
    builder_->emitBlankLine();
    
    // Emit start sentinel
    builder_->emitComment("DATA segment start marker");
    builder_->emitGlobalData("$data_begins", "l", "0");
    builder_->emitBlankLine();
    
    // Emit type tags array (0=int, 1=double, 2=string)
    builder_->emitComment("DATA type tags (0=int, 1=double, 2=string)");
    for (size_t i = 0; i < dataValues_.values.size(); ++i) {
        std::string tagLabel = "$data_type_" + std::to_string(i);
        int typeTag = 0;
        if (std::holds_alternative<int>(dataValues_.values[i])) {
            typeTag = 0;
        } else if (std::holds_alternative<double>(dataValues_.values[i])) {
            typeTag = 1;
        } else if (std::holds_alternative<std::string>(dataValues_.values[i])) {
            typeTag = 2;
        }
        builder_->emitGlobalData(tagLabel, "w", std::to_string(typeTag));
    }
    builder_->emitBlankLine();
    
    // Emit each DATA value as a 64-bit (long) element for uniform access
    builder_->emitComment("DATA values (all as 64-bit for uniform access)");
    for (size_t i = 0; i < dataValues_.values.size(); ++i) {
        std::string dataLabel = "$data_" + std::to_string(i);
        
        if (std::holds_alternative<int>(dataValues_.values[i])) {
            int value = std::get<int>(dataValues_.values[i]);
            // Store as long (64-bit) for uniform access
            builder_->emitGlobalData(dataLabel, "l", std::to_string(value));
        } else if (std::holds_alternative<double>(dataValues_.values[i])) {
            double value = std::get<double>(dataValues_.values[i]);
            // Store double as bit pattern in long for uniform access
            // Use union to get bit representation
            union { double d; uint64_t bits; } u;
            u.d = value;
            builder_->emitGlobalData(dataLabel, "l", std::to_string(u.bits));
        } else if (std::holds_alternative<std::string>(dataValues_.values[i])) {
            const std::string& value = std::get<std::string>(dataValues_.values[i]);
            // Get the label (already registered during collection phase)
            std::string strLabel = builder_->getStringLabel(value);
            // Store pointer to string constant (64-bit pointer) - add $ prefix
            builder_->emitGlobalData(dataLabel, "l", "$" + strLabel);
        }
    }
    
    builder_->emitBlankLine();
    
    // Emit label restore points
    if (!dataValues_.labelRestorePoints.empty()) {
        builder_->emitComment("Label restore points");
        for (const auto& [label, index] : dataValues_.labelRestorePoints) {
            std::string labelName = "$data_label_" + label;
            std::string targetLabel = "$data_" + std::to_string(index);
            builder_->emitGlobalData(labelName, "l", targetLabel);
        }
        builder_->emitBlankLine();
    }
    
    // Emit line number restore points
    if (!dataValues_.lineRestorePoints.empty()) {
        builder_->emitComment("Line number restore points");
        for (const auto& [lineNum, index] : dataValues_.lineRestorePoints) {
            std::string lineName = "$data_line_" + std::to_string(lineNum);
            std::string targetLabel = "$data_" + std::to_string(index);
            builder_->emitGlobalData(lineName, "l", targetLabel);
        }
        builder_->emitBlankLine();
    }
    
    // Emit end sentinel
    builder_->emitComment("DATA segment end marker");
    builder_->emitGlobalData("$data_end", "l", "0");
    builder_->emitBlankLine();
    
    // Emit runtime state: data pointer and constants
    builder_->emitComment("DATA runtime state");
    builder_->emitGlobalData("$__data_pointer", "l", "$data_0");  // Initially points to first element
    builder_->emitGlobalData("$__data_start", "l", "$data_0");    // Constant: first element
    builder_->emitGlobalData("$__data_end_const", "l", "$data_end");  // Constant: end marker
    
    builder_->emitBlankLine();
}

// === SHARED Variable Registration ===

void QBECodeGeneratorV2::registerSharedVariables(const ControlFlowGraph* cfg, 
                                                 SymbolMapper* symbolMapper) {
    if (!cfg || !symbolMapper) {
        return;
    }
    
    // Scan all blocks in the CFG for SHARED statements
    for (const auto& block : cfg->blocks) {
        if (!block) continue;
        
        for (const auto& stmt : block->statements) {
            if (!stmt) continue;
            
            // Check if this is a SHARED statement
            if (stmt->getType() == ASTNodeType::STMT_SHARED) {
                const SharedStatement* sharedStmt = static_cast<const SharedStatement*>(stmt);
                
                // Register all shared variables with the symbol mapper
                for (const auto& var : sharedStmt->variables) {
                    symbolMapper->addSharedVariable(var.name);
                }
            }
        }
    }
}

// ==========================================================================
// CLASS System Emission
// ==========================================================================

std::string QBECodeGeneratorV2::getQBETypeForDescriptor(const TypeDescriptor& td) {
    switch (td.baseType) {
        case BaseType::INTEGER:
        case BaseType::UINTEGER:
        case BaseType::BYTE:
        case BaseType::UBYTE:
        case BaseType::SHORT:
        case BaseType::USHORT:
            return "w";
        case BaseType::SINGLE:
            return "s";
        case BaseType::DOUBLE:
            return "d";
        default:
            return "l";  // pointers, strings, long, class instances
    }
}

std::string QBECodeGeneratorV2::getQBEParamType(const TypeDescriptor& td) {
    return getQBETypeForDescriptor(td);
}

void QBECodeGeneratorV2::emitClassDeclarations(const Program* program) {
    if (!program) return;
    
    const auto& symbolTable = semantic_.getSymbolTable();
    if (symbolTable.classes.empty()) return;
    
    builder_->emitBlankLine();
    builder_->emitComment("=== CLASS System: VTables & Methods ===");
    builder_->emitBlankLine();
    
    // Collect all ClassStatement AST nodes from the program
    // We need these for method bodies
    std::vector<const ClassStatement*> classStmts;
    for (const auto& line : program->lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_CLASS) {
                classStmts.push_back(static_cast<const ClassStatement*>(stmt.get()));
            }
        }
    }
    
    // Phase 1: Emit class name string constants
    for (const auto& [upperName, cls] : symbolTable.classes) {
        emitClassNameString(cls);
    }
    
    builder_->emitBlankLine();
    
    // Phase 2: Emit vtable data sections
    for (const auto& [upperName, cls] : symbolTable.classes) {
        emitClassVtable(cls);
    }
    
    builder_->emitBlankLine();
    
    // Phase 3: Emit method/constructor/destructor functions
    // We need to match ClassSymbols to ClassStatement AST nodes by name
    for (const auto& classStmt : classStmts) {
        std::string upperName = classStmt->className;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);
        
        const ClassSymbol* cls = symbolTable.lookupClass(upperName);
        if (!cls) continue;
        
        // Emit constructor
        if (classStmt->constructor && cls->hasConstructor) {
            emitClassConstructor(*classStmt, *classStmt->constructor, *cls);
        }
        
        // Emit destructor
        if (classStmt->destructor && cls->hasDestructor) {
            emitClassDestructor(*classStmt, *classStmt->destructor, *cls);
        }
        
        // Emit methods
        for (const auto& method : classStmt->methods) {
            if (method) {
                emitClassMethod(*classStmt, *method, *cls);
            }
        }
    }
}

void QBECodeGeneratorV2::emitClassNameString(const ClassSymbol& cls) {
    // data $classname_Foo = { b "Foo", b 0 }
    builder_->emitComment("Class name: " + cls.name);
    std::string label = "$classname_" + cls.name;
    
    // Build the data content manually since emitStringConstant may escape differently
    std::ostringstream oss;
    oss << "data " << label << " = { b \"" << cls.name << "\", b 0 }\n";
    builder_->emitRaw(oss.str());
}

void QBECodeGeneratorV2::emitClassVtable(const ClassSymbol& cls) {
    // VTable layout:
    //   [0]  class_id           (l, int64)
    //   [8]  parent_vtable ptr  (l, 0 if root)
    //   [16] class_name ptr     (l, ptr to $classname_X)
    //   [24] destructor ptr     (l, 0 if none)
    //   [32+] method pointers   (l each, in vtable slot order)
    
    builder_->emitComment("VTable for " + cls.name + " (class_id=" + std::to_string(cls.classId) + ", " + std::to_string(cls.methods.size()) + " methods)");
    
    std::ostringstream oss;
    oss << "data $vtable_" << cls.name << " = {\n";
    
    // [0] class_id
    oss << "    l " << cls.classId << ",    # class_id\n";
    
    // [8] parent_vtable pointer
    if (cls.parentClass) {
        oss << "    l $vtable_" << cls.parentClass->name << ",    # parent_vtable\n";
    } else {
        oss << "    l 0,    # parent_vtable (root class)\n";
    }
    
    // [16] class_name pointer
    oss << "    l $classname_" << cls.name << ",    # class_name\n";
    
    // [24] destructor pointer
    if (cls.hasDestructor) {
        oss << "    l $" << cls.destructorMangledName << ",    # destructor\n";
    } else {
        oss << "    l 0,    # destructor (none)\n";
    }
    
    // [32+] method pointers in vtable slot order
    // Methods are already stored in slot order in cls.methods
    for (size_t i = 0; i < cls.methods.size(); i++) {
        const auto& mi = cls.methods[i];
        oss << "    l $" << mi.mangledName;
        if (i + 1 < cls.methods.size()) oss << ",";
        oss << "    # slot " << mi.vtableSlot << ": " << mi.name;
        if (mi.isOverride) oss << " (override)";
        if (mi.originClass != cls.name) oss << " [from " << mi.originClass << "]";
        oss << "\n";
    }
    
    oss << "}\n";
    builder_->emitRaw(oss.str());
}

void QBECodeGeneratorV2::emitClassMethod(const ClassStatement& classStmt,
                                          const MethodStatement& method,
                                          const ClassSymbol& cls) {
    // Find the method info from the ClassSymbol
    const auto* methodInfo = cls.findMethod(method.methodName);
    if (!methodInfo) {
        builder_->emitComment("ERROR: method '" + method.methodName + "' not found in ClassSymbol '" + cls.name + "'");
        return;
    }
    
    builder_->emitBlankLine();
    builder_->emitComment("METHOD " + cls.name + "." + method.methodName);
    
    // Determine return type
    std::string returnType = "";
    if (methodInfo->returnType.baseType != BaseType::VOID) {
        returnType = getQBETypeForDescriptor(methodInfo->returnType);
    }
    
    // Build parameter list: first param is always l %me
    std::string params = "l %me";
    for (size_t i = 0; i < method.parameters.size(); i++) {
        std::string paramType = "l";
        if (i < methodInfo->parameterTypes.size()) {
            paramType = getQBEParamType(methodInfo->parameterTypes[i]);
        }
        std::string paramName = "%param_" + method.parameters[i];
        params += ", " + paramType + " " + paramName;
    }
    
    // Emit function header
    builder_->emitFunctionStart(methodInfo->mangledName, returnType, params);
    builder_->emitLabel("start");
    
    // SAMM: Enter METHOD scope — local allocations (DIM inside method)
    // are tracked and cleaned up when the method returns.
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Enter METHOD scope");
        builder_->emitCall("", "", "samm_enter_scope", "");
    }
    
    // Allocate local variables for parameters so they can be addressed
    for (size_t i = 0; i < method.parameters.size(); i++) {
        std::string paramType = "l";
        BaseType paramBaseType = BaseType::LONG;
        if (i < methodInfo->parameterTypes.size()) {
            paramType = getQBEParamType(methodInfo->parameterTypes[i]);
            paramBaseType = methodInfo->parameterTypes[i].baseType;
        }
        std::string varName = "%var_" + method.parameters[i];
        int size = (paramType == "w" || paramType == "s") ? 4 : 8;
        builder_->emitRaw("    " + varName + " =l alloc8 " + std::to_string(size) + "\n");
        std::string storeOp = (paramType == "w") ? "storew" : 
                              (paramType == "s") ? "stores" : 
                              (paramType == "d") ? "stored" : "storel";
        builder_->emitRaw("    " + storeOp + " %param_" + method.parameters[i] + ", " + varName + "\n");
        
        // Register parameter so loadVariable/getVariableAddress can resolve it
        astEmitter_->registerMethodParam(method.parameters[i], varName, paramBaseType);
    }
    
    // Set current class context for ME resolution
    astEmitter_->setCurrentClassContext(&cls);
    
    // Set method return type so RETURN statements emit direct `ret`
    astEmitter_->setMethodReturnType(methodInfo->returnType.baseType);

    // Set method name so that return-via-assignment (e.g., `Hello = "Hi"`)
    // is detected and routed to the return slot in emitLetStatement.
    astEmitter_->setMethodName(method.methodName);

    // Allocate a return-value stack slot for non-void methods.
    // This enables the BASIC convention of assigning to the method name
    // to set the return value (e.g., `GetName = ME.Name`).
    // The slot is registered as a method "param" under the method name
    // so that storeVariable / loadVariable can resolve it.
    std::string methodRetSlot;
    if (methodInfo->returnType.baseType != BaseType::VOID) {
        std::string retQbeType = getQBETypeForDescriptor(methodInfo->returnType);
        int retSlotSize = (retQbeType == "w" || retQbeType == "s") ? 4 : 8;
        methodRetSlot = "%method_ret";
        builder_->emitComment("Allocate return-value slot for return-via-assignment");
        builder_->emitRaw("    " + methodRetSlot + " =l alloc8 " + std::to_string(retSlotSize) + "\n");
        // Zero-initialize the return slot (default return value)
        if (retSlotSize == 4) {
            builder_->emitRaw("    storew 0, " + methodRetSlot + "\n");
        } else {
            builder_->emitRaw("    storel 0, " + methodRetSlot + "\n");
        }
        // Register under the method name so `MethodName = expr` resolves here
        astEmitter_->registerMethodParam(method.methodName, methodRetSlot, methodInfo->returnType.baseType);
        astEmitter_->setMethodReturnSlot(methodRetSlot);
    }

    // Emit method body statements
    astEmitter_->emitMethodBody(method.body);
    
    // Clear class context, method return type, method name, return slot, and method params
    astEmitter_->setMethodReturnType(FasterBASIC::BaseType::VOID);
    astEmitter_->setMethodName("");
    astEmitter_->setMethodReturnSlot("");
    astEmitter_->setCurrentClassContext(nullptr);
    astEmitter_->clearMethodParams();
    
    // Emit default return in a separate fallback label so that if the body
    // already emitted a `ret`, QBE won't see two `ret` in the same block.
    // Note: the old samm_exit_scope() call that was here between the body
    // and the fallback label was dead code — the method body's last RETURN
    // already emitted a `ret`, making anything after it unreachable.
    int fallbackId = builder_->getNextLabelId();
    builder_->emitLabel("method_fallback_" + std::to_string(fallbackId));
    
    // SAMM: Exit METHOD scope on the fallback (no explicit RETURN) path.
    // Explicit RETURN paths emit their own samm_exit_scope() in
    // ASTEmitter::emitReturnStatement().
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Exit METHOD scope (fallback path)");
        builder_->emitCall("", "", "samm_exit_scope", "");
    }
    
    if (methodInfo->returnType.baseType == BaseType::VOID) {
        builder_->emitReturn();
    } else {
        // Load the return value from the return-via-assignment slot.
        // If the method body assigned to the method name (e.g., `GetName = ME.Name`),
        // the value will be in this slot.  Otherwise it returns the zero-initialized default.
        std::string retType = getQBETypeForDescriptor(methodInfo->returnType);
        std::string retVal = "%method_ret_val_" + std::to_string(fallbackId);
        std::string loadOp;
        if (retType == "w")      loadOp = "loadw";
        else if (retType == "s") loadOp = "loads";
        else if (retType == "d") loadOp = "loadd";
        else                     loadOp = "loadl";
        builder_->emitRaw("    " + retVal + " =" + retType + " " + loadOp + " " + methodRetSlot + "\n");

        // SAMM: If returning a CLASS instance, RETAIN to parent scope
        if (methodInfo->returnType.baseType == BaseType::CLASS_INSTANCE) {
            builder_->emitComment("SAMM: RETAIN returned CLASS instance to parent scope (fallback)");
            builder_->emitCall("", "", "samm_retain_parent", "l " + retVal);
        }

        builder_->emitReturn(retVal);
    }
    
    builder_->emitFunctionEnd();
}

void QBECodeGeneratorV2::emitClassConstructor(const ClassStatement& classStmt,
                                               const ConstructorStatement& ctor,
                                               const ClassSymbol& cls) {
    builder_->emitBlankLine();
    builder_->emitComment("CONSTRUCTOR " + cls.name);
    
    // Build parameter list: first param is always l %me
    std::string params = "l %me";
    for (size_t i = 0; i < ctor.parameters.size(); i++) {
        std::string paramType = "l";
        if (i < cls.constructorParamTypes.size()) {
            paramType = getQBEParamType(cls.constructorParamTypes[i]);
        }
        std::string paramName = "%param_" + ctor.parameters[i];
        params += ", " + paramType + " " + paramName;
    }
    
    // Emit function header (constructor returns void)
    builder_->emitFunctionStart(cls.constructorMangledName, "", params);
    builder_->emitLabel("start");
    
    // SAMM: Enter CONSTRUCTOR scope — local allocations within the
    // constructor body are tracked and cleaned up when it returns.
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Enter CONSTRUCTOR scope");
        builder_->emitCall("", "", "samm_enter_scope", "");
    }
    
    // Allocate local variables for parameters
    for (size_t i = 0; i < ctor.parameters.size(); i++) {
        std::string paramType = "l";
        BaseType paramBaseType = BaseType::LONG;
        if (i < cls.constructorParamTypes.size()) {
            paramType = getQBEParamType(cls.constructorParamTypes[i]);
            paramBaseType = cls.constructorParamTypes[i].baseType;
        }
        std::string varName = "%var_" + ctor.parameters[i];
        int size = (paramType == "w" || paramType == "s") ? 4 : 8;
        builder_->emitRaw("    " + varName + " =l alloc8 " + std::to_string(size) + "\n");
        std::string storeOp = (paramType == "w") ? "storew" : 
                              (paramType == "s") ? "stores" : 
                              (paramType == "d") ? "stored" : "storel";
        builder_->emitRaw("    " + storeOp + " %param_" + ctor.parameters[i] + ", " + varName + "\n");
        
        // Register parameter so loadVariable/getVariableAddress can resolve it
        astEmitter_->registerMethodParam(ctor.parameters[i], varName, paramBaseType);
    }
    
    // If there's an explicit SUPER() call, emit it first
    if (ctor.hasSuperCall && cls.parentClass && cls.parentClass->hasConstructor) {
        builder_->emitComment("SUPER() call to parent constructor");
        std::string superArgs = "l %me";
        for (size_t i = 0; i < ctor.superArgs.size(); i++) {
            std::string argTemp = astEmitter_->emitExpression(ctor.superArgs[i].get());
            std::string argType = "l";
            if (i < cls.parentClass->constructorParamTypes.size()) {
                argType = getQBEParamType(cls.parentClass->constructorParamTypes[i]);
            }
            superArgs += ", " + argType + " " + argTemp;
        }
        builder_->emitRaw("    call $" + cls.parentClass->constructorMangledName + "(" + superArgs + ")\n");
    } else if (!ctor.hasSuperCall && cls.parentClass && cls.parentClass->hasConstructor
               && cls.parentClass->constructorParamTypes.empty()) {
        // Implicit SUPER() call: parent has a zero-arg constructor and child
        // did not write an explicit SUPER(...) — chain automatically.
        builder_->emitComment("Implicit SUPER() call to parent zero-arg constructor");
        builder_->emitRaw("    call $" + cls.parentClass->constructorMangledName + "(l %me)\n");
    }
    
    // Set current class context for ME resolution
    astEmitter_->setCurrentClassContext(&cls);
    
    // Emit constructor body statements
    astEmitter_->emitMethodBody(ctor.body);
    
    // Clear class context and method params
    astEmitter_->setCurrentClassContext(nullptr);
    astEmitter_->clearMethodParams();
    
    // SAMM: Exit CONSTRUCTOR scope before return.
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Exit CONSTRUCTOR scope");
        builder_->emitCall("", "", "samm_exit_scope", "");
    }
    
    // Constructor always returns void
    builder_->emitReturn();
    builder_->emitFunctionEnd();
}

void QBECodeGeneratorV2::emitClassDestructor(const ClassStatement& classStmt,
                                              const DestructorStatement& dtor,
                                              const ClassSymbol& cls) {
    builder_->emitBlankLine();
    builder_->emitComment("DESTRUCTOR " + cls.name);
    
    // Destructor signature: takes only l %me, returns void
    builder_->emitFunctionStart(cls.destructorMangledName, "", "l %me");
    builder_->emitLabel("start");
    
    // SAMM: Enter DESTRUCTOR scope so that any temporary allocations made
    // during destructor body execution (e.g. string concatenations, helper
    // objects) are tracked and automatically cleaned up when the destructor
    // returns.  This is especially important when destructors are invoked
    // on the SAMM background cleanup worker thread, which has no ambient
    // scope of its own.
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Enter DESTRUCTOR scope");
        builder_->emitCall("", "", "samm_enter_scope", "");
    }
    
    // Set current class context for ME resolution
    astEmitter_->setCurrentClassContext(&cls);
    
    // Emit destructor body statements
    astEmitter_->emitMethodBody(dtor.body);
    
    // Clear class context and method params
    astEmitter_->setCurrentClassContext(nullptr);
    astEmitter_->clearMethodParams();
    
    // Chain to parent destructor if parent has one
    if (cls.parentClass && cls.parentClass->hasDestructor) {
        builder_->emitComment("Chain to parent destructor: " + cls.parentClass->name);
        builder_->emitRaw("    call $" + cls.parentClass->destructorMangledName + "(l %me)\n");
    }
    
    // SAMM: Exit DESTRUCTOR scope — any temporaries allocated during
    // the destructor body are queued for cleanup.
    if (isSAMMEnabled()) {
        builder_->emitComment("SAMM: Exit DESTRUCTOR scope");
        builder_->emitCall("", "", "samm_exit_scope", "");
    }
    
    builder_->emitReturn();
    builder_->emitFunctionEnd();
}

} // namespace fbc