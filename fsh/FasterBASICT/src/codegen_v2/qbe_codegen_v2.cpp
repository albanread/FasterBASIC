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
    
    // Emit CFG
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
    
    // Emit CFG
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
    
    // Emit CFG (local variable allocations will be inserted at entry block)
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
            
            // Emit UDT as a zeroed byte array of the appropriate size
            builder_->emitComment("Global UDT: " + varSymbol->name + " (type: " + varSymbol->typeName + ", size: " + std::to_string(udtSize) + " bytes)");
            builder_->emitRaw("export data " + mangledName + " = { z " + std::to_string(udtSize) + " }");
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

} // namespace fbc