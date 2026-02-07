//
// fasterbasic_semantic.cpp
// FasterBASIC - Semantic Analyzer Implementation
//
// Implements two-pass semantic analysis:
// Pass 1: Collect all declarations (line numbers, DIM, DEF FN, DATA)
// Pass 2: Validate usage, type check, control flow validation
//

#include "fasterbasic_semantic.h"
#include "runtime_objects.h"

#include <algorithm>
#include <sstream>
#include <cmath>
#include <iostream>
#include <fstream>

#ifdef FBRUNNER3_BUILD
#include "../../FBRunner3/register_voice.h"
#endif

namespace FasterBASIC {

// =============================================================================
// SymbolTable toString
// =============================================================================

std::string SymbolTable::toString() const {
    std::ostringstream oss;
    
    oss << "=== SYMBOL TABLE ===\n\n";
    
    // Line numbers
    if (!lineNumbers.empty()) {
        oss << "Line Numbers (" << lineNumbers.size() << "):\n";
        std::vector<int> sortedLines;
        for (const auto& pair : lineNumbers) {
            sortedLines.push_back(pair.first);
        }
        std::sort(sortedLines.begin(), sortedLines.end());
        for (int line : sortedLines) {
            const auto& sym = lineNumbers.at(line);
            oss << "  " << sym.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Labels
    if (!labels.empty()) {
        oss << "Labels (" << labels.size() << "):\n";
        std::vector<std::string> sortedLabels;
        for (const auto& pair : labels) {
            sortedLabels.push_back(pair.first);
        }
        std::sort(sortedLabels.begin(), sortedLabels.end());
        for (const auto& name : sortedLabels) {
            const auto& sym = labels.at(name);
            oss << "  " << sym.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Variables
    if (!variables.empty()) {
        oss << "Variables (" << variables.size() << "):\n";
        std::vector<std::string> sortedVars;
        for (const auto& pair : variables) {
            sortedVars.push_back(pair.first);
        }
        std::sort(sortedVars.begin(), sortedVars.end());
        for (const auto& name : sortedVars) {
            const auto& sym = variables.at(name);
            oss << "  " << sym.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Arrays
    if (!arrays.empty()) {
        oss << "Arrays (" << arrays.size() << "):\n";
        std::vector<std::string> sortedArrays;
        for (const auto& pair : arrays) {
            sortedArrays.push_back(pair.first);
        }
        std::sort(sortedArrays.begin(), sortedArrays.end());
        for (const auto& name : sortedArrays) {
            const auto& sym = arrays.at(name);
            oss << "  " << sym.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Functions
    if (!functions.empty()) {
        oss << "Functions (" << functions.size() << "):\n";
        std::vector<std::string> sortedFuncs;
        for (const auto& pair : functions) {
            sortedFuncs.push_back(pair.first);
        }
        std::sort(sortedFuncs.begin(), sortedFuncs.end());
        for (const auto& name : sortedFuncs) {
            const auto& sym = functions.at(name);
            oss << "  " << sym.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Data segment
    if (!dataSegment.values.empty()) {
        oss << "Data Segment:\n";
        oss << "  " << dataSegment.toString() << "\n";
        oss << "  Values: ";
        for (size_t i = 0; i < std::min(dataSegment.values.size(), size_t(10)); ++i) {
            if (i > 0) oss << ", ";
            oss << "\"" << dataSegment.values[i] << "\"";
        }
        if (dataSegment.values.size() > 10) {
            oss << ", ... (" << (dataSegment.values.size() - 10) << " more)";
        }
        oss << "\n\n";
    }
    
    oss << "=== END SYMBOL TABLE ===\n";
    
    return oss.str();
}

// =============================================================================
// Constructor/Destructor
// =============================================================================

SemanticAnalyzer::SemanticAnalyzer()
    : m_strictMode(false)
    , m_warnUnused(true)
    , m_requireExplicitDim(true)
    , m_cancellableLoops(true)
    , m_program(nullptr)
    , m_currentLineNumber(0)
    , m_inTimerHandler(false)
    , m_currentFunctionName("")
{
    // Ensure runtime object registry is initialized
    getRuntimeObjectRegistry().initialize();
    
    initializeBuiltinFunctions();
    
    // Load additional functions from the global command registry
    loadFromCommandRegistry(ModularCommands::getGlobalCommandRegistry());
    
    m_constantsManager.addPredefinedConstants();
    
    // Register voice waveform constants (WAVE_SINE, WAVE_SQUARE, etc.)
#ifdef FBRUNNER3_BUILD
    FBRunner3::VoiceRegistration::registerVoiceConstants(m_constantsManager);
#endif
    
    // Register ALL predefined constants from ConstantsManager into symbol table
    // This allows them to be resolved like user-defined constants during compilation
    // Dynamically loads all constants - no hardcoded list needed!
    // Constants are stored in lowercase and the formatter will NOT uppercase them
    std::vector<std::string> predefinedNames = m_constantsManager.getAllConstantNames();
    
    for (const auto& name : predefinedNames) {
        int index = m_constantsManager.getConstantIndex(name);
        if (index >= 0) {
            ConstantValue val = m_constantsManager.getConstant(index);
            ConstantSymbol sym;
            if (std::holds_alternative<int64_t>(val)) {
                sym = ConstantSymbol(std::get<int64_t>(val));
            } else if (std::holds_alternative<double>(val)) {
                sym = ConstantSymbol(std::get<double>(val));
            } else if (std::holds_alternative<std::string>(val)) {
                sym = ConstantSymbol(std::get<std::string>(val));
            }
            sym.index = index;
            
            // Store with lowercase key (as returned from manager)
            m_symbolTable.constants[name] = sym;
        }
    }
}

SemanticAnalyzer::~SemanticAnalyzer() = default;

// =============================================================================
// Constants Management
// =============================================================================

void SemanticAnalyzer::ensureConstantsLoaded() {
    // Check if constants are already loaded
    if (m_constantsManager.getConstantCount() > 0) {
        return; // Already loaded
    }
    
    // Clear and reload predefined constants
    m_constantsManager.clear();
    m_constantsManager.addPredefinedConstants();
    
    // Register LIST type tag constants (match ATOM_* values in list_ops.h)
    // These are used with FOR EACH T, E IN over LIST OF ANY
    m_constantsManager.addConstant("LIST_TYPE_INT",    (int64_t)1);
    m_constantsManager.addConstant("LIST_TYPE_FLOAT",  (int64_t)2);
    m_constantsManager.addConstant("LIST_TYPE_STRING", (int64_t)3);
    m_constantsManager.addConstant("LIST_TYPE_LIST",   (int64_t)4);
    m_constantsManager.addConstant("LIST_TYPE_OBJECT", (int64_t)5);
    
    // Register voice waveform constants (WAVE_SINE, WAVE_SQUARE, etc.)
#ifdef FBRUNNER3_BUILD
    FBRunner3::VoiceRegistration::registerVoiceConstants(m_constantsManager);
#endif
    
    // Register ALL predefined constants from ConstantsManager into symbol table
    // Constants are stored in lowercase and the formatter will NOT uppercase them
    std::vector<std::string> predefinedNames = m_constantsManager.getAllConstantNames();
    
    for (const auto& name : predefinedNames) {
        int index = m_constantsManager.getConstantIndex(name);
        if (index >= 0) {
            ConstantValue val = m_constantsManager.getConstant(index);
            ConstantSymbol sym;
            if (std::holds_alternative<int64_t>(val)) {
                sym = ConstantSymbol(std::get<int64_t>(val));
            } else if (std::holds_alternative<double>(val)) {
                sym = ConstantSymbol(std::get<double>(val));
            } else if (std::holds_alternative<std::string>(val)) {
                sym = ConstantSymbol(std::get<std::string>(val));
            }
            sym.index = index;
            
            // Store with lowercase key (as returned from manager)
            m_symbolTable.constants[name] = sym;
        }
    }
}

// =============================================================================
// Runtime Constant Injection
// =============================================================================

void SemanticAnalyzer::injectRuntimeConstant(const std::string& name, int64_t value) {
    // Add to ConstantsManager and get index (manager will normalize to lowercase)
    int index = m_constantsManager.addConstant(name, value);
    
    // Create symbol and add to symbol table (use lowercase key)
    std::string lowerName = name;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
    ConstantSymbol sym(value);
    sym.index = index;
    m_symbolTable.constants[lowerName] = sym;
}

void SemanticAnalyzer::injectRuntimeConstant(const std::string& name, double value) {
    // Add to ConstantsManager and get index (manager will normalize to lowercase)
    int index = m_constantsManager.addConstant(name, value);
    
    // Create symbol and add to symbol table (use lowercase key)
    std::string lowerName = name;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
    ConstantSymbol sym(value);
    sym.index = index;
    m_symbolTable.constants[lowerName] = sym;
}

void SemanticAnalyzer::injectRuntimeConstant(const std::string& name, const std::string& value) {
    // Add to ConstantsManager and get index (manager will normalize to lowercase)
    int index = m_constantsManager.addConstant(name, value);
    
    // Create symbol and add to symbol table (use lowercase key)
    std::string lowerName = name;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
    ConstantSymbol sym(value);
    sym.index = index;
    m_symbolTable.constants[lowerName] = sym;
}

// =============================================================================
// DATA Label Registration
// =============================================================================

void SemanticAnalyzer::registerDataLabels(const std::map<std::string, int>& dataLabels) {
    // Register labels from DATA preprocessing so RESTORE can find them
    for (const auto& [labelName, lineNumber] : dataLabels) {
        // Create a label symbol for this DATA label
        LabelSymbol sym;
        sym.name = labelName;
        sym.labelId = m_symbolTable.nextLabelId++;
        sym.programLineIndex = 0; // DATA labels don't have a program line index
        sym.definition.line = lineNumber;
        sym.definition.column = 0;
        
        m_symbolTable.labels[labelName] = sym;
    }
}

// =============================================================================
// Main Analysis Entry Point
// =============================================================================

bool SemanticAnalyzer::analyze(Program& program, const CompilerOptions& options) {
    m_program = &program;
    m_errors.clear();
    m_warnings.clear();
    
    // Store compiler options
    m_options = options;
    
    // Preserve predefined constants before resetting symbol table
    auto savedConstants = m_symbolTable.constants;
    
    m_symbolTable = SymbolTable();
    
    // Restore predefined constants
    m_symbolTable.constants = savedConstants;
    
    // Apply compiler options to symbol table
    m_symbolTable.arrayBase = options.arrayBase;
    m_symbolTable.stringMode = options.stringMode;
    m_symbolTable.errorTracking = options.errorTracking;
    m_symbolTable.cancellableLoops = options.cancellableLoops;
    m_symbolTable.forceYieldEnabled = options.forceYieldEnabled;
    m_symbolTable.forceYieldBudget = options.forceYieldBudget;
    m_symbolTable.sammEnabled = options.sammEnabled;
    m_cancellableLoops = options.cancellableLoops;
    
    // Clear control flow stacks
    while (!m_forStack.empty()) m_forStack.pop();
    while (!m_whileStack.empty()) m_whileStack.pop();
    while (!m_repeatStack.empty()) m_repeatStack.pop();
    
    // Two-pass analysis
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] Starting pass1_collectDeclarations" << std::endl;
    }
    pass1_collectDeclarations(program);
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] Starting pass2_validate" << std::endl;
    }
    pass2_validate(program);
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] Finished pass2_validate" << std::endl;
    }
    
    // Variable names are now normalized during declaration, so no post-processing needed
    
    // Final validation
    validateControlFlow(program);
    
    if (m_warnUnused) {
        checkUnusedVariables();
    }
    
    return m_errors.empty();
}

// =============================================================================
// Pass 1: Declaration Collection
// =============================================================================

void SemanticAnalyzer::pass1_collectDeclarations(Program& program) {
    collectForEachVariables(program);  // Prescan FOR EACH to mark variables as ADAPTIVE - MUST BE FIRST!
    collectLineNumbers(program);
    collectLabels(program);
    // NOTE: collectOptionStatements removed - options are now collected by parser
    collectTypeDeclarations(program);  // Collect TYPE/END TYPE declarations first
    collectClassDeclarations(program);  // Collect CLASS/END CLASS declarations (after TYPE, before constants)
    collectConstantStatements(program);  // Collect constants BEFORE DIM statements (they may use constants)
    collectGlobalStatements(program);  // Collect GLOBAL variable declarations
    collectDimStatements(program);
    collectDefStatements(program);
    collectFunctionAndSubStatements(program);
    collectDataStatements(program);
    collectTimerHandlers(program);  // Collect AFTER/EVERY handlers before validation
}

void SemanticAnalyzer::collectLineNumbers(Program& program) {
    for (size_t i = 0; i < program.lines.size(); ++i) {
        const auto& line = program.lines[i];
        if (line->lineNumber > 0) {
            // Check for duplicate line numbers
            if (m_symbolTable.lineNumbers.find(line->lineNumber) != m_symbolTable.lineNumbers.end()) {
                error(SemanticErrorType::DUPLICATE_LINE_NUMBER,
                      "Duplicate line number: " + std::to_string(line->lineNumber),
                      line->location);
                continue;
            }
            
            LineNumberSymbol sym;
            sym.lineNumber = line->lineNumber;
            sym.programLineIndex = i;
            m_symbolTable.lineNumbers[line->lineNumber] = sym;
        }
    }
}

void SemanticAnalyzer::collectLabelsRecursive(const std::vector<StatementPtr>& statements, int fallbackLineNumber) {
    for (const auto& stmt : statements) {
        if (!stmt) continue;

        if (stmt->getType() == ASTNodeType::STMT_LABEL) {
            const auto& labelStmt = static_cast<const LabelStatement&>(*stmt);
            declareLabel(labelStmt.labelName, fallbackLineNumber, stmt->location);
            continue;
        }

        // Recurse into compound statement bodies
        switch (stmt->getType()) {
            case ASTNodeType::STMT_WHILE: {
                const auto& whileStmt = static_cast<const WhileStatement&>(*stmt);
                collectLabelsRecursive(whileStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_FOR: {
                const auto& forStmt = static_cast<const ForStatement&>(*stmt);
                collectLabelsRecursive(forStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_FOR_IN: {
                const auto& forInStmt = static_cast<const ForInStatement&>(*stmt);
                collectLabelsRecursive(forInStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_DO: {
                const auto& doStmt = static_cast<const DoStatement&>(*stmt);
                collectLabelsRecursive(doStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_REPEAT: {
                const auto& repeatStmt = static_cast<const RepeatStatement&>(*stmt);
                collectLabelsRecursive(repeatStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_IF: {
                const auto& ifStmt = static_cast<const IfStatement&>(*stmt);
                collectLabelsRecursive(ifStmt.thenStatements, fallbackLineNumber);
                for (const auto& elseIfClause : ifStmt.elseIfClauses) {
                    collectLabelsRecursive(elseIfClause.statements, fallbackLineNumber);
                }
                collectLabelsRecursive(ifStmt.elseStatements, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_CASE: {
                const auto& caseStmt = static_cast<const CaseStatement&>(*stmt);
                for (const auto& whenClause : caseStmt.whenClauses) {
                    collectLabelsRecursive(whenClause.statements, fallbackLineNumber);
                }
                collectLabelsRecursive(caseStmt.otherwiseStatements, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_MATCH_TYPE: {
                const auto& matchStmt = static_cast<const MatchTypeStatement&>(*stmt);
                for (const auto& arm : matchStmt.caseArms) {
                    collectLabelsRecursive(arm.body, fallbackLineNumber);
                }
                if (!matchStmt.caseElseBody.empty()) {
                    collectLabelsRecursive(matchStmt.caseElseBody, fallbackLineNumber);
                }
                break;
            }
            case ASTNodeType::STMT_TRY_CATCH: {
                const auto& tryStmt = static_cast<const TryCatchStatement&>(*stmt);
                collectLabelsRecursive(tryStmt.tryBlock, fallbackLineNumber);
                for (const auto& clause : tryStmt.catchClauses) {
                    collectLabelsRecursive(clause.block, fallbackLineNumber);
                }
                if (tryStmt.hasFinally) {
                    collectLabelsRecursive(tryStmt.finallyBlock, fallbackLineNumber);
                }
                break;
            }
            case ASTNodeType::STMT_FUNCTION: {
                const auto& funcStmt = static_cast<const FunctionStatement&>(*stmt);
                collectLabelsRecursive(funcStmt.body, fallbackLineNumber);
                break;
            }
            case ASTNodeType::STMT_SUB: {
                const auto& subStmt = static_cast<const SubStatement&>(*stmt);
                collectLabelsRecursive(subStmt.body, fallbackLineNumber);
                break;
            }
            default:
                break;
        }
    }
}

void SemanticAnalyzer::collectLabels(Program& program) {
    for (size_t i = 0; i < program.lines.size(); ++i) {
        const auto& line = program.lines[i];
        // Determine fallback line number for labels on their own line
        int fallbackLineNumber = line->lineNumber;
        if (i + 1 < program.lines.size()) {
            fallbackLineNumber = program.lines[i + 1]->lineNumber;
        }
        collectLabelsRecursive(line->statements, fallbackLineNumber);
    }
}

void SemanticAnalyzer::collectOptionStatements(Program& program) {
    // NOTE: This function is now deprecated. OPTION statements are collected
    // by the parser before AST generation and passed as CompilerOptions.
    // This function is kept for backward compatibility but does nothing.
    // OPTION statements should not appear in the AST anymore.
}

void SemanticAnalyzer::collectGlobalStatements(Program& program) {
    int nextOffset = 0;  // Track next available global slot
    
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_GLOBAL) {
                const GlobalStatement& globalStmt = static_cast<const GlobalStatement&>(*stmt);
                
                // Register global variables in symbol table
                for (const auto& var : globalStmt.variables) {
                    // Determine variable type descriptor
                    TypeDescriptor typeDesc;
                    
                    if (var.hasAsType && !var.asTypeName.empty()) {
                        // Map AS type name to TypeDescriptor
                        std::string typeName = var.asTypeName;
                        std::transform(typeName.begin(), typeName.end(), typeName.begin(), ::toupper);
                        
                        if (typeName == "INTEGER" || typeName == "INT") {
                            typeDesc = TypeDescriptor(BaseType::INTEGER);
                        } else if (typeName == "DOUBLE") {
                            typeDesc = TypeDescriptor(BaseType::DOUBLE);
                        } else if (typeName == "SINGLE" || typeName == "FLOAT") {
                            typeDesc = TypeDescriptor(BaseType::SINGLE);
                        } else if (typeName == "STRING") {
                            typeDesc = TypeDescriptor(BaseType::STRING);
                        } else if (typeName == "LONG") {
                            typeDesc = TypeDescriptor(BaseType::LONG);
                        } else if (typeName == "BYTE") {
                            typeDesc = TypeDescriptor(BaseType::BYTE);
                        } else if (typeName == "SHORT") {
                            typeDesc = TypeDescriptor(BaseType::SHORT);
                        } else {
                            // Default to DOUBLE
                            typeDesc = TypeDescriptor(BaseType::DOUBLE);
                        }
                    } else if (var.typeSuffix != TokenType::UNKNOWN) {
                        typeDesc = legacyTypeToDescriptor(inferTypeFromSuffix(var.typeSuffix));
                    } else {
                        typeDesc = legacyTypeToDescriptor(inferTypeFromName(var.name));
                    }
                    
                    // Normalize the variable name to include proper type suffix
                    std::string normalizedName = normalizeVariableName(var.name, typeDesc);
                    
                    // Check if already declared (using normalized name)
                    if (m_symbolTable.variables.count(normalizedName)) {
                        error(SemanticErrorType::ARRAY_REDECLARED,
                              "Variable '" + normalizedName + "' already declared",
                              stmt->location);
                        continue;
                    }
                    
                    // Create variable symbol and mark it as global with explicit scope
                    VariableSymbol varSym(normalizedName, typeDesc, Scope::makeGlobal(), true);
                    varSym.firstUse = stmt->location;
                    varSym.isGlobal = true;  // Mark as GLOBAL variable
                    varSym.globalOffset = nextOffset++;  // Assign slot number and increment
                    
                    m_symbolTable.insertVariable(normalizedName, varSym);
                }
            }
        }
    }
    
    // Update global count in symbol table
    m_symbolTable.globalVariableCount = nextOffset;
}

// Recursively walk a statement list and process any DIM statements found,
// including those nested inside FOR/IF/WHILE/DO bodies.  The current
// function scope (m_currentFunctionScope / m_currentFunctionName) must
// already be set correctly by the caller.
void SemanticAnalyzer::collectDimStatementsRecursive(const std::vector<StatementPtr>& stmts) {
    for (const auto& stmt : stmts) {
        if (!stmt) continue;
        switch (stmt->getType()) {
            case ASTNodeType::STMT_DIM:
                processDimStatement(static_cast<const DimStatement&>(*stmt));
                break;

            case ASTNodeType::STMT_FOR: {
                const auto* forStmt = static_cast<const ForStatement*>(stmt.get());
                collectDimStatementsRecursive(forStmt->body);
                break;
            }
            case ASTNodeType::STMT_FOR_IN: {
                const auto* forInStmt = static_cast<const ForInStatement*>(stmt.get());
                collectDimStatementsRecursive(forInStmt->body);
                break;
            }
            case ASTNodeType::STMT_IF: {
                const auto* ifStmt = static_cast<const IfStatement*>(stmt.get());
                collectDimStatementsRecursive(ifStmt->thenStatements);
                for (const auto& clause : ifStmt->elseIfClauses) {
                    collectDimStatementsRecursive(clause.statements);
                }
                collectDimStatementsRecursive(ifStmt->elseStatements);
                break;
            }
            case ASTNodeType::STMT_WHILE: {
                const auto* whileStmt = static_cast<const WhileStatement*>(stmt.get());
                collectDimStatementsRecursive(whileStmt->body);
                break;
            }
            case ASTNodeType::STMT_DO: {
                const auto* doStmt = static_cast<const DoStatement*>(stmt.get());
                collectDimStatementsRecursive(doStmt->body);
                break;
            }
            case ASTNodeType::STMT_MATCH_TYPE: {
                const auto* matchStmt = static_cast<const MatchTypeStatement*>(stmt.get());
                for (const auto& arm : matchStmt->caseArms) {
                    collectDimStatementsRecursive(arm.body);
                }
                collectDimStatementsRecursive(matchStmt->caseElseBody);
                break;
            }
            default:
                break;
        }
    }
}

void SemanticAnalyzer::collectDimStatements(Program& program) {
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_DIM) {
                processDimStatement(static_cast<const DimStatement&>(*stmt));
            }
            // Also process DIM statements inside FUNCTION bodies (recursively)
            else if (stmt->getType() == ASTNodeType::STMT_FUNCTION) {
                const FunctionStatement* funcStmt = static_cast<const FunctionStatement*>(stmt.get());
                
                // Temporarily enter function scope so DIM variables are
                // registered with the correct function scope (not global)
                FunctionScope prevScope = m_currentFunctionScope;
                std::string prevFuncName = m_currentFunctionName;
                m_currentFunctionScope = FunctionScope();
                m_currentFunctionScope.inFunction = true;
                m_currentFunctionScope.functionName = funcStmt->functionName;
                m_currentFunctionScope.isSub = false;
                m_currentFunctionName = funcStmt->functionName;
                
                collectDimStatementsRecursive(funcStmt->body);
                
                // Restore previous scope
                m_currentFunctionScope = prevScope;
                m_currentFunctionName = prevFuncName;
            }
            // Also process DIM statements inside SUB bodies (recursively)
            else if (stmt->getType() == ASTNodeType::STMT_SUB) {
                const SubStatement* subStmt = static_cast<const SubStatement*>(stmt.get());
                
                // Temporarily enter SUB scope so DIM variables are
                // registered with the correct function scope (not global)
                FunctionScope prevScope = m_currentFunctionScope;
                std::string prevFuncName = m_currentFunctionName;
                m_currentFunctionScope = FunctionScope();
                m_currentFunctionScope.inFunction = true;
                m_currentFunctionScope.functionName = subStmt->subName;
                m_currentFunctionScope.isSub = true;
                m_currentFunctionName = subStmt->subName;
                
                collectDimStatementsRecursive(subStmt->body);
                
                // Restore previous scope
                m_currentFunctionScope = prevScope;
                m_currentFunctionName = prevFuncName;
            }
            // Also walk top-level FOR/IF/WHILE/DO bodies for nested DIMs
            else if (stmt->getType() == ASTNodeType::STMT_FOR) {
                const auto* forStmt = static_cast<const ForStatement*>(stmt.get());
                collectDimStatementsRecursive(forStmt->body);
            }
            else if (stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                const auto* forInStmt = static_cast<const ForInStatement*>(stmt.get());
                collectDimStatementsRecursive(forInStmt->body);
            }
            else if (stmt->getType() == ASTNodeType::STMT_IF) {
                const auto* ifStmt = static_cast<const IfStatement*>(stmt.get());
                collectDimStatementsRecursive(ifStmt->thenStatements);
                for (const auto& clause : ifStmt->elseIfClauses) {
                    collectDimStatementsRecursive(clause.statements);
                }
                collectDimStatementsRecursive(ifStmt->elseStatements);
            }
            else if (stmt->getType() == ASTNodeType::STMT_WHILE) {
                const auto* whileStmt = static_cast<const WhileStatement*>(stmt.get());
                collectDimStatementsRecursive(whileStmt->body);
            }
            else if (stmt->getType() == ASTNodeType::STMT_DO) {
                const auto* doStmt = static_cast<const DoStatement*>(stmt.get());
                collectDimStatementsRecursive(doStmt->body);
            }
        }
    }
}

void SemanticAnalyzer::collectDefStatements(Program& program) {
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_DEF) {
                processDefStatement(static_cast<const DefStatement&>(*stmt));
            }
        }
    }
}

void SemanticAnalyzer::collectConstantStatements(Program& program) {
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_CONSTANT) {
                processConstantStatement(static_cast<const ConstantStatement&>(*stmt));
            }
        }
    }
}

void SemanticAnalyzer::collectTypeDeclarations(Program& program) {
    // Collect all TYPE declarations in pass 1
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_TYPE) {
                processTypeDeclarationStatement(static_cast<const TypeDeclarationStatement*>(stmt.get()));
            }
        }
    }
}

// =============================================================================
// CLASS Declaration Collection
// =============================================================================

void SemanticAnalyzer::collectClassDeclarations(Program& program) {
    // Collect all CLASS declarations in pass 1
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_CLASS) {
                processClassStatement(static_cast<const ClassStatement&>(*stmt));
            }
        }
    }
}

void SemanticAnalyzer::processClassStatement(const ClassStatement& stmt) {
    std::string upperName = stmt.className;
    std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);

    // Check for duplicate class names
    if (m_symbolTable.lookupClass(upperName)) {
        error(SemanticErrorType::DUPLICATE_CLASS,
              "CLASS '" + stmt.className + "' is already defined",
              stmt.location);
        return;
    }

    // Allocate a unique class ID
    int classId = m_symbolTable.allocateClassId(upperName);

    ClassSymbol cls(stmt.className, classId);
    cls.declaration = stmt.location;

    // Resolve parent class (if EXTENDS)
    if (!stmt.parentClassName.empty()) {
        ClassSymbol* parent = m_symbolTable.lookupClass(stmt.parentClassName);
        if (!parent) {
            error(SemanticErrorType::UNDEFINED_CLASS,
                  "CLASS '" + stmt.parentClassName + "' is not defined (used as parent of '" + stmt.className + "')",
                  stmt.location);
            return;
        }

        // Check for circular inheritance (simple check: parent must not be self)
        if (parent->classId == classId) {
            error(SemanticErrorType::CIRCULAR_INHERITANCE,
                  "Circular inheritance detected: " + stmt.className + " extends itself",
                  stmt.location);
            return;
        }

        cls.parentClass = parent;

        // Inherit fields from parent
        for (const auto& pf : parent->fields) {
            ClassSymbol::FieldInfo inherited = pf;
            inherited.inherited = true;
            cls.fields.push_back(inherited);
        }

        // Inherit method slots from parent
        for (const auto& pm : parent->methods) {
            cls.methods.push_back(pm);
        }
    }

    // Compute field offsets for own fields
    int currentOffset = ClassSymbol::headerSize;  // Start after vtable_ptr + class_id

    // Account for inherited fields
    if (cls.parentClass) {
        currentOffset = cls.parentClass->objectSize;
    }

    // Add own fields
    for (const auto& field : stmt.fields) {
        ClassSymbol::FieldInfo fi;
        fi.name = field.name;
        fi.inherited = false;

        // Determine field type descriptor
        if (field.isBuiltIn) {
            fi.typeDesc = keywordToDescriptor(field.builtInType);
        } else {
            // Check if it's a CLASS type or a TYPE
            ClassSymbol* fieldClass = m_symbolTable.lookupClass(field.typeName);
            if (fieldClass) {
                fi.typeDesc = TypeDescriptor::makeClassInstance(field.typeName);
            } else {
                fi.typeDesc = TypeDescriptor(BaseType::USER_DEFINED);
                fi.typeDesc.udtName = field.typeName;
            }
        }

        // Compute alignment and offset
        int fieldSize = 8;  // Default: pointer-sized (strings, objects)
        int alignment = 8;
        if (fi.typeDesc.baseType == BaseType::INTEGER || fi.typeDesc.baseType == BaseType::UINTEGER ||
            fi.typeDesc.baseType == BaseType::SINGLE) {
            fieldSize = 4;
            alignment = 4;
        } else if (fi.typeDesc.baseType == BaseType::BYTE || fi.typeDesc.baseType == BaseType::UBYTE) {
            fieldSize = 1;
            alignment = 1;
        } else if (fi.typeDesc.baseType == BaseType::SHORT || fi.typeDesc.baseType == BaseType::USHORT) {
            fieldSize = 2;
            alignment = 2;
        }

        // Align offset
        if (currentOffset % alignment != 0) {
            currentOffset += alignment - (currentOffset % alignment);
        }

        fi.offset = currentOffset;
        currentOffset += fieldSize;

        cls.fields.push_back(fi);
    }

    // Pad to 8-byte alignment
    if (currentOffset % 8 != 0) {
        currentOffset += 8 - (currentOffset % 8);
    }
    cls.objectSize = currentOffset;

    // Process methods — assign vtable slots
    for (const auto& method : stmt.methods) {
        // Check if this overrides a parent method
        bool isOverride = false;
        int existingSlot = -1;

        for (size_t i = 0; i < cls.methods.size(); i++) {
            std::string existUpper = cls.methods[i].name;
            std::transform(existUpper.begin(), existUpper.end(), existUpper.begin(), ::toupper);
            std::string newUpper = method->methodName;
            std::transform(newUpper.begin(), newUpper.end(), newUpper.begin(), ::toupper);

            if (existUpper == newUpper) {
                isOverride = true;
                existingSlot = static_cast<int>(i);
                break;
            }
        }

        ClassSymbol::MethodInfo mi;
        mi.name = method->methodName;
        mi.mangledName = stmt.className + "__" + method->methodName;
        mi.isOverride = isOverride;
        mi.originClass = stmt.className;

        // Build parameter type list
        for (size_t p = 0; p < method->parameterTypes.size(); p++) {
            if (method->parameterTypes[p] != TokenType::UNKNOWN && method->parameterTypes[p] != TokenType::IDENTIFIER) {
                mi.parameterTypes.push_back(keywordToDescriptor(method->parameterTypes[p]));
            } else if (method->parameterTypes[p] == TokenType::IDENTIFIER) {
                // Could be a CLASS type or UDT
                ClassSymbol* pClass = m_symbolTable.lookupClass(method->parameterAsTypes[p]);
                if (pClass) {
                    mi.parameterTypes.push_back(TypeDescriptor::makeClassInstance(method->parameterAsTypes[p]));
                } else {
                    TypeDescriptor td(BaseType::USER_DEFINED);
                    td.udtName = method->parameterAsTypes[p];
                    mi.parameterTypes.push_back(td);
                }
            } else {
                mi.parameterTypes.push_back(TypeDescriptor(BaseType::UNKNOWN));
            }
        }

        // Return type
        if (method->hasReturnType) {
            if (method->returnTypeSuffix != TokenType::UNKNOWN && method->returnTypeSuffix != TokenType::IDENTIFIER) {
                mi.returnType = keywordToDescriptor(method->returnTypeSuffix);
            } else if (method->returnTypeSuffix == TokenType::IDENTIFIER) {
                ClassSymbol* rClass = m_symbolTable.lookupClass(method->returnTypeAsName);
                if (rClass) {
                    mi.returnType = TypeDescriptor::makeClassInstance(method->returnTypeAsName);
                } else {
                    mi.returnType = TypeDescriptor(BaseType::USER_DEFINED);
                    mi.returnType.udtName = method->returnTypeAsName;
                }
            }
        } else {
            mi.returnType = TypeDescriptor(BaseType::VOID);
        }

        if (isOverride) {
            // Validate override signature: parameter count, types, and return type must match
            const auto& parentMethod = cls.methods[existingSlot];

            // Check parameter count
            if (mi.parameterTypes.size() != parentMethod.parameterTypes.size()) {
                error(SemanticErrorType::CLASS_ERROR,
                      "METHOD '" + mi.name + "' override in CLASS '" + stmt.className +
                      "' has " + std::to_string(mi.parameterTypes.size()) +
                      " parameter(s), but parent '" + parentMethod.originClass +
                      "' declares " + std::to_string(parentMethod.parameterTypes.size()),
                      method->location);
            } else {
                // Check each parameter type
                for (size_t p = 0; p < mi.parameterTypes.size(); p++) {
                    if (mi.parameterTypes[p].baseType != BaseType::UNKNOWN &&
                        parentMethod.parameterTypes[p].baseType != BaseType::UNKNOWN &&
                        mi.parameterTypes[p] != parentMethod.parameterTypes[p]) {
                        error(SemanticErrorType::CLASS_ERROR,
                              "METHOD '" + mi.name + "' override in CLASS '" + stmt.className +
                              "': parameter " + std::to_string(p + 1) + " type mismatch (" +
                              mi.parameterTypes[p].toString() + " vs parent " +
                              parentMethod.parameterTypes[p].toString() + ")",
                              method->location);
                        break;
                    }
                }
            }

            // Check return type
            if (mi.returnType.baseType != BaseType::UNKNOWN &&
                parentMethod.returnType.baseType != BaseType::UNKNOWN &&
                mi.returnType != parentMethod.returnType) {
                error(SemanticErrorType::CLASS_ERROR,
                      "METHOD '" + mi.name + "' override in CLASS '" + stmt.className +
                      "': return type mismatch (" + mi.returnType.toString() +
                      " vs parent " + parentMethod.returnType.toString() + ")",
                      method->location);
            }

            // Override existing slot — replace the method info
            mi.vtableSlot = cls.methods[existingSlot].vtableSlot;
            cls.methods[existingSlot] = mi;
        } else {
            // New method — append to vtable
            mi.vtableSlot = cls.getMethodCount();
            cls.methods.push_back(mi);
        }
    }

    // Process constructor
    if (stmt.constructor) {
        cls.hasConstructor = true;
        cls.constructorMangledName = stmt.className + "__CONSTRUCTOR";

        for (size_t p = 0; p < stmt.constructor->parameterTypes.size(); p++) {
            if (stmt.constructor->parameterTypes[p] != TokenType::UNKNOWN &&
                stmt.constructor->parameterTypes[p] != TokenType::IDENTIFIER) {
                cls.constructorParamTypes.push_back(keywordToDescriptor(stmt.constructor->parameterTypes[p]));
            } else if (stmt.constructor->parameterTypes[p] == TokenType::IDENTIFIER) {
                ClassSymbol* pClass = m_symbolTable.lookupClass(stmt.constructor->parameterAsTypes[p]);
                if (pClass) {
                    cls.constructorParamTypes.push_back(TypeDescriptor::makeClassInstance(stmt.constructor->parameterAsTypes[p]));
                } else {
                    TypeDescriptor td(BaseType::USER_DEFINED);
                    td.udtName = stmt.constructor->parameterAsTypes[p];
                    cls.constructorParamTypes.push_back(td);
                }
            } else {
                cls.constructorParamTypes.push_back(TypeDescriptor(BaseType::UNKNOWN));
            }
        }
    }

    // Process destructor
    if (stmt.destructor) {
        cls.hasDestructor = true;
        cls.destructorMangledName = stmt.className + "__DESTRUCTOR";
    }

    // Register the class in the symbol table
    m_symbolTable.classes[upperName] = cls;
}

void SemanticAnalyzer::processTypeDeclarationStatement(const TypeDeclarationStatement* stmt) {
    if (!stmt) return;
    
    // Check for duplicate type name
    if (lookupType(stmt->typeName) != nullptr) {
        error(SemanticErrorType::DUPLICATE_TYPE,
              "Type '" + stmt->typeName + "' is already defined",
              stmt->location);
        return;
    }
    
    // Allocate a unique type ID for this UDT
    int udtTypeId = m_symbolTable.allocateTypeId(stmt->typeName);
    
    // Create the type symbol
    TypeSymbol typeSymbol(stmt->typeName);
    typeSymbol.declaration = stmt->location;
    
    // Track field names to detect duplicates
    std::unordered_set<std::string> fieldNames;
    
    // ── Generalized SIMD type classification ──
    // Detect all NEON-eligible UDT patterns: all fields must be the same
    // built-in numeric type, no strings or nested UDTs, total ≤ 128 bits,
    // lane count in {2, 3, 4, 8, 16}.
    TypeDeclarationStatement::SIMDType detectedSIMDType = TypeDeclarationStatement::SIMDType::NONE;
    TypeDeclarationStatement::SIMDInfo detectedSIMDInfo;
    
    auto classifySIMD = [&]() -> TypeDeclarationStatement::SIMDInfo {
        using SIMDType = TypeDeclarationStatement::SIMDType;
        TypeDeclarationStatement::SIMDInfo info;
        info.type = SIMDType::NONE;
        
        int nfields = (int)stmt->fields.size();
        if (nfields < 2 || nfields > 16) return info;
        
        // All fields must be built-in and the same type
        if (!stmt->fields[0].isBuiltIn) return info;
        TokenType laneToken = stmt->fields[0].builtInType;
        for (int fi = 1; fi < nfields; ++fi) {
            if (!stmt->fields[fi].isBuiltIn) return info;
            if (stmt->fields[fi].builtInType != laneToken) return info;
        }
        
        // Determine lane bit width and base type
        int bits = 0;
        BaseType laneBase = BaseType::UNKNOWN;
        bool isFloat = false;
        switch (laneToken) {
            case TokenType::KEYWORD_INTEGER:
                bits = 32; laneBase = BaseType::INTEGER; break;
            case TokenType::KEYWORD_SINGLE:
                bits = 32; laneBase = BaseType::SINGLE; isFloat = true; break;
            case TokenType::KEYWORD_DOUBLE:
                bits = 64; laneBase = BaseType::DOUBLE; isFloat = true; break;
            case TokenType::KEYWORD_LONG:
                bits = 64; laneBase = BaseType::LONG; break;
            default:
                return info; // STRING, BYTE, SHORT etc. — not yet supported
        }
        
        int totalBits = nfields * bits;
        if (totalBits > 128) return info;
        
        // Populate info
        info.laneCount = nfields;
        info.laneBitWidth = bits;
        info.laneBaseType = static_cast<int>(laneBase);
        info.isFloatingPoint = isFloat;
        
        // Classify: determine SIMDType and physical lane count
        if (nfields == 3 && bits == 32) {
            // 3 × 32-bit → pad to 4 lanes in a Q register
            info.type = SIMDType::V4S_PAD1;
            info.physicalLanes = 4;
            info.totalBytes = 16;
            info.isFullQ = true;
            info.isPadded = true;
        } else {
            info.physicalLanes = nfields;
            info.totalBytes = (nfields * bits) / 8;
            info.isFullQ = (info.totalBytes == 16);
            info.isPadded = false;
            
            // Map to specific SIMDType
            if (bits == 64 && nfields == 2) {
                info.type = SIMDType::V2D;
            } else if (bits == 32 && nfields == 4) {
                info.type = SIMDType::V4S;
            } else if (bits == 32 && nfields == 2) {
                info.type = SIMDType::V2S;
            } else {
                // Other valid but uncommon configs: V8H, V16B, V4H, V8B
                // Leave as NONE for now; add as needed
                return info;
            }
        }
        
        return info;
    };
    
    detectedSIMDInfo = classifySIMD();
    
    // Set legacy SIMDType for backward compatibility
    if (detectedSIMDInfo.type == TypeDeclarationStatement::SIMDType::V2D ||
        detectedSIMDInfo.type == TypeDeclarationStatement::SIMDType::PAIR) {
        detectedSIMDType = TypeDeclarationStatement::SIMDType::PAIR;
    } else if (detectedSIMDInfo.type == TypeDeclarationStatement::SIMDType::V4S ||
               detectedSIMDInfo.type == TypeDeclarationStatement::SIMDType::QUAD) {
        detectedSIMDType = TypeDeclarationStatement::SIMDType::QUAD;
    } else if (detectedSIMDInfo.isValid()) {
        // For new types (V2S, V4S_PAD1, etc.) set legacy to NONE but keep simdInfo
        detectedSIMDType = TypeDeclarationStatement::SIMDType::NONE;
    }
    
    // Store SIMD info in the statement (mutable cast for metadata)
    const_cast<TypeDeclarationStatement*>(stmt)->simdType = detectedSIMDType;
    const_cast<TypeDeclarationStatement*>(stmt)->simdInfo = detectedSIMDInfo;
    
    // Debug output for SIMD detection
    if (detectedSIMDInfo.isValid()) {
        std::cout << "[SIMD] Detected NEON-eligible type: " << stmt->typeName
                  << " [" << detectedSIMDInfo.arrangement() << "]"
                  << " (" << detectedSIMDInfo.laneCount << "×" << detectedSIMDInfo.laneBitWidth << "b"
                  << (detectedSIMDInfo.isFullQ ? ", Q-reg" : ", D-reg")
                  << (detectedSIMDInfo.isPadded ? ", padded" : "")
                  << (detectedSIMDInfo.isFloatingPoint ? ", float" : ", int")
                  << ")" << std::endl;
    }
    
    // Process each field
    for (const auto& field : stmt->fields) {
        // Check for duplicate field name
        if (fieldNames.find(field.name) != fieldNames.end()) {
            error(SemanticErrorType::DUPLICATE_FIELD,
                  "Duplicate field '" + field.name + "' in type '" + stmt->typeName + "'",
                  stmt->location);
            continue;
        }
        fieldNames.insert(field.name);
        
        // Create TypeDescriptor for the field
        TypeDescriptor fieldTypeDesc;
        
        if (field.isBuiltIn) {
            // Built-in type - convert TokenType to TypeDescriptor
            switch (field.builtInType) {
                case TokenType::KEYWORD_INTEGER:
                    fieldTypeDesc = TypeDescriptor(BaseType::INTEGER);
                    break;
                case TokenType::KEYWORD_SINGLE:
                    fieldTypeDesc = TypeDescriptor(BaseType::SINGLE);
                    break;
                case TokenType::KEYWORD_DOUBLE:
                    fieldTypeDesc = TypeDescriptor(BaseType::DOUBLE);
                    break;
                case TokenType::KEYWORD_STRING:
                    // For STRING type in TYPE definition, use global mode (not per-literal detection)
                    fieldTypeDesc = (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                        TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
                    break;
                case TokenType::KEYWORD_LONG:
                    fieldTypeDesc = TypeDescriptor(BaseType::LONG);
                    break;
                default:
                    error(SemanticErrorType::INVALID_TYPE_FIELD,
                          "Invalid field type in type '" + stmt->typeName + "'",
                          stmt->location);
                    continue;
            }
        } else {
            // User-defined type - will be validated in second pass
            fieldTypeDesc = TypeDescriptor(BaseType::USER_DEFINED);
            fieldTypeDesc.udtName = field.typeName;
            // Type ID will be resolved later when all types are registered
        }
        
        // Add field using new TypeDescriptor constructor
        TypeSymbol::Field typeField(field.name, fieldTypeDesc);
        typeSymbol.fields.push_back(typeField);
    }
    
    // Store SIMD type and info in the TypeSymbol for later use
    typeSymbol.simdType = detectedSIMDType;
    typeSymbol.simdInfo = detectedSIMDInfo;
    
    // Register the type
    m_symbolTable.types[stmt->typeName] = typeSymbol;
}

void SemanticAnalyzer::collectTimerHandlers(Program& program) {
    // Collect all handlers registered via AFTER/EVERY/AFTERFRAMES/EVERYFRAME statements
    // This must be done in pass1 so that validation in pass2 knows which functions are handlers
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_AFTER) {
                const AfterStatement& afterStmt = static_cast<const AfterStatement&>(*stmt);
                if (!afterStmt.handlerName.empty()) {
                    m_registeredHandlers.insert(afterStmt.handlerName);
                }
            } else if (stmt->getType() == ASTNodeType::STMT_EVERY) {
                const EveryStatement& everyStmt = static_cast<const EveryStatement&>(*stmt);
                if (!everyStmt.handlerName.empty()) {
                    m_registeredHandlers.insert(everyStmt.handlerName);
                }
            } else if (stmt->getType() == ASTNodeType::STMT_AFTERFRAMES) {
                const AfterFramesStatement& afterFramesStmt = static_cast<const AfterFramesStatement&>(*stmt);
                if (!afterFramesStmt.handlerName.empty()) {
                    m_registeredHandlers.insert(afterFramesStmt.handlerName);
                }
            } else if (stmt->getType() == ASTNodeType::STMT_EVERYFRAME) {
                const EveryFrameStatement& everyFrameStmt = static_cast<const EveryFrameStatement&>(*stmt);
                if (!everyFrameStmt.handlerName.empty()) {
                    m_registeredHandlers.insert(everyFrameStmt.handlerName);
                }
            }
        }
    }
}

void SemanticAnalyzer::collectFunctionAndSubStatements(Program& program) {
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_FUNCTION) {
                processFunctionStatement(static_cast<const FunctionStatement&>(*stmt));
            } else if (stmt->getType() == ASTNodeType::STMT_SUB) {
                processSubStatement(static_cast<const SubStatement&>(*stmt));
            }
        }
    }
}

void SemanticAnalyzer::processFunctionStatement(const FunctionStatement& stmt) {
    // Check if already declared
    if (m_symbolTable.functions.find(stmt.functionName) != m_symbolTable.functions.end()) {
        error(SemanticErrorType::FUNCTION_REDECLARED,
              "Function " + stmt.functionName + " already declared",
              stmt.location);
        return;
    }
    
    // Set current function scope for tracking local symbols
    m_currentFunctionName = stmt.functionName;
    
    FunctionSymbol sym;
    sym.name = stmt.functionName;
    sym.parameters = stmt.parameters;
    sym.parameterIsByRef = stmt.parameterIsByRef;
    
    // Process parameter types
    for (size_t i = 0; i < stmt.parameters.size(); ++i) {
        VariableType paramType = VariableType::UNKNOWN;
        std::string paramTypeName = "";
        
        if (i < stmt.parameterAsTypes.size() && !stmt.parameterAsTypes[i].empty()) {
            // Has AS TypeName
            paramTypeName = stmt.parameterAsTypes[i];
            
            // Convert to uppercase for case-insensitive comparison
            std::string upperTypeName = paramTypeName;
            std::transform(upperTypeName.begin(), upperTypeName.end(), upperTypeName.begin(), ::toupper);
            
            // Check if it's a built-in type keyword or user-defined type
            if (upperTypeName == "INTEGER" || upperTypeName == "INT") {
                paramType = VariableType::INT;
                paramTypeName = "";  // It's built-in, don't store name
            } else if (upperTypeName == "DOUBLE") {
                paramType = VariableType::DOUBLE;
                paramTypeName = "";
            } else if (upperTypeName == "SINGLE" || upperTypeName == "FLOAT") {
                paramType = VariableType::FLOAT;
                paramTypeName = "";
            } else if (upperTypeName == "STRING") {
                paramType = VariableType::STRING;
                paramTypeName = "";
            } else if (upperTypeName == "LONG") {
                paramType = VariableType::INT;  // legacy enum (lossy)
                paramTypeName = "LONG";  // preserve for direct TypeDescriptor below
            } else {
                // User-defined type - validate it exists (check both TYPEs and CLASSes)
                if (m_symbolTable.types.find(paramTypeName) != m_symbolTable.types.end()) {
                    paramType = VariableType::USER_DEFINED;
                } else if (m_symbolTable.classes.find(upperTypeName) != m_symbolTable.classes.end()) {
                    // CLASS instance parameter — will be handled as CLASS_INSTANCE
                    // in the TypeDescriptor below
                    paramType = VariableType::USER_DEFINED;  // legacy enum; overridden below
                } else {
                    error(SemanticErrorType::TYPE_ERROR,
                          "Unknown type '" + paramTypeName + "' in parameter " + stmt.parameters[i],
                          stmt.location);
                    paramType = VariableType::USER_DEFINED;
                }
            }
        } else if (i < stmt.parameterTypes.size()) {
            // Has type suffix
            paramType = inferTypeFromSuffix(stmt.parameterTypes[i]);
        } else {
            paramType = VariableType::DOUBLE;  // Default type (DOUBLE, not FLOAT)
        }
        
        // Build TypeDescriptor for this parameter
        // Types that the legacy VariableType enum can't represent (LONG, SHORT,
        // BYTE, etc.) are built directly to avoid losing precision.
        TypeDescriptor paramTypeDesc;
        if (paramTypeName == "LONG") {
            paramTypeDesc = TypeDescriptor(BaseType::LONG);
        } else if (paramTypeName == "SHORT") {
            paramTypeDesc = TypeDescriptor(BaseType::SHORT);
        } else if (paramTypeName == "BYTE") {
            paramTypeDesc = TypeDescriptor(BaseType::BYTE);
        } else if (paramTypeName == "ULONG") {
            paramTypeDesc = TypeDescriptor(BaseType::ULONG);
        } else if (paramTypeName == "UBYTE") {
            paramTypeDesc = TypeDescriptor(BaseType::UBYTE);
        } else if (paramTypeName == "USHORT") {
            paramTypeDesc = TypeDescriptor(BaseType::USHORT);
        } else if (paramTypeName == "UINTEGER" || paramTypeName == "UINT") {
            paramTypeDesc = TypeDescriptor(BaseType::UINTEGER);
        } else if (paramType == VariableType::USER_DEFINED && !paramTypeName.empty()) {
            // Check if this is a CLASS type
            std::string upperParamTypeName = paramTypeName;
            std::transform(upperParamTypeName.begin(), upperParamTypeName.end(), upperParamTypeName.begin(), ::toupper);
            if (m_symbolTable.classes.find(upperParamTypeName) != m_symbolTable.classes.end()) {
                // CLASS instance parameter — pointer semantics
                paramTypeDesc = TypeDescriptor::makeClassInstance(upperParamTypeName);
            } else {
                // Regular UDT parameter
                paramTypeDesc = legacyTypeToDescriptor(paramType);
                paramTypeDesc.udtName = paramTypeName;
                paramTypeDesc.udtTypeId = m_symbolTable.allocateTypeId(paramTypeName);
            }
        } else {
            paramTypeDesc = legacyTypeToDescriptor(paramType);
        }
        sym.parameterTypeDescs.push_back(paramTypeDesc);
    }
    
    // Process return type
    if (stmt.hasReturnAsType && !stmt.returnTypeAsName.empty()) {
        sym.returnTypeName = stmt.returnTypeAsName;
        
        // Convert to uppercase for case-insensitive comparison
        std::string upperReturnType = sym.returnTypeName;
        std::transform(upperReturnType.begin(), upperReturnType.end(), upperReturnType.begin(), ::toupper);
        
        // Check if it's a built-in type keyword or user-defined type
        if (upperReturnType == "INTEGER" || upperReturnType == "INT") {
            sym.returnTypeDesc = TypeDescriptor(BaseType::INTEGER);
            sym.returnTypeName = "";
        } else if (upperReturnType == "DOUBLE") {
            sym.returnTypeDesc = TypeDescriptor(BaseType::DOUBLE);
            sym.returnTypeName = "";
        } else if (upperReturnType == "SINGLE" || upperReturnType == "FLOAT") {
            sym.returnTypeDesc = TypeDescriptor(BaseType::SINGLE);
            sym.returnTypeName = "";
        } else if (upperReturnType == "STRING") {
            sym.returnTypeDesc = TypeDescriptor(BaseType::STRING);
            sym.returnTypeName = "";
        } else if (upperReturnType == "LONG") {
            sym.returnTypeDesc = TypeDescriptor(BaseType::LONG);
            sym.returnTypeName = "";
        } else {
            // User-defined type - check both TYPEs and CLASSes
            if (m_symbolTable.classes.find(upperReturnType) != m_symbolTable.classes.end()) {
                // CLASS instance return type — pointer semantics with SAMM RETAIN
                sym.returnTypeDesc = TypeDescriptor::makeClassInstance(upperReturnType);
                // Keep returnTypeName so codegen can identify the class
            } else if (m_symbolTable.types.find(sym.returnTypeName) != m_symbolTable.types.end()) {
                // Regular UDT return type
                sym.returnTypeDesc = TypeDescriptor(BaseType::USER_DEFINED);
                sym.returnTypeDesc.udtName = sym.returnTypeName;
            } else {
                error(SemanticErrorType::TYPE_ERROR,
                      "Unknown return type '" + sym.returnTypeName + "' for function " + stmt.functionName,
                      stmt.location);
                // Fallback to USER_DEFINED so compilation can continue
                sym.returnTypeDesc = TypeDescriptor(BaseType::USER_DEFINED);
                sym.returnTypeDesc.udtName = sym.returnTypeName;
            }
        }
    } else {
        sym.returnTypeDesc = legacyTypeToDescriptor(inferTypeFromSuffix(stmt.returnTypeSuffix));
    }
    
    m_symbolTable.functions[stmt.functionName] = sym;
    
    // Add function name as a variable (for return value assignment)
    // Create return variable with function scope
    Scope funcScope = Scope::makeFunction(stmt.functionName);
    
    // Normalize return variable name to include type suffix
    std::string normalizedReturnVarName = normalizeVariableName(stmt.functionName, sym.returnTypeDesc);
    
    VariableSymbol returnVar(normalizedReturnVarName, sym.returnTypeDesc, funcScope, true);
    returnVar.firstUse = stmt.location;
    // For CLASS_INSTANCE return types, set typeName so codegen can identify the class
    if (sym.returnTypeDesc.isClassInstance() && !sym.returnTypeDesc.className.empty()) {
        returnVar.typeName = sym.returnTypeDesc.className;
    }
    m_symbolTable.insertVariable(normalizedReturnVarName, returnVar);
    
    // Add parameters to symbol table as variables in function scope
    for (size_t i = 0; i < stmt.parameters.size(); ++i) {
        std::string paramName = stmt.parameters[i];
        TypeDescriptor paramTypeDesc = sym.parameterTypeDescs[i];
        
        // Normalize parameter name to include type suffix
        std::string normalizedParamName = normalizeVariableName(paramName, paramTypeDesc);
        
        VariableSymbol paramVar(normalizedParamName, paramTypeDesc, funcScope, true);
        paramVar.firstUse = stmt.location;
        // For UDT parameters, set typeName so codegen can look up the UDT definition
        if (i < stmt.parameterAsTypes.size() && !stmt.parameterAsTypes[i].empty()) {
            std::string pTypeName = stmt.parameterAsTypes[i];
            std::string upperPType = pTypeName;
            std::transform(upperPType.begin(), upperPType.end(), upperPType.begin(), ::toupper);
            // Only set typeName for user-defined types (not built-in keywords)
            if (upperPType != "INTEGER" && upperPType != "INT" && upperPType != "DOUBLE" &&
                upperPType != "SINGLE" && upperPType != "FLOAT" && upperPType != "STRING" &&
                upperPType != "LONG") {
                paramVar.typeName = pTypeName;
            }
        }
        m_symbolTable.insertVariable(normalizedParamName, paramVar);
    }
    
    // Clear current function scope
    m_currentFunctionName = "";
}

void SemanticAnalyzer::processSubStatement(const SubStatement& stmt) {
    // Check if already declared
    if (m_symbolTable.functions.find(stmt.subName) != m_symbolTable.functions.end()) {
        error(SemanticErrorType::FUNCTION_REDECLARED,
              "Subroutine " + stmt.subName + " already declared",
              stmt.location);
        return;
    }
    
    // Set current function scope for tracking local symbols
    m_currentFunctionName = stmt.subName;
    
    FunctionSymbol sym;
    sym.name = stmt.subName;
    sym.parameters = stmt.parameters;
    sym.parameterIsByRef = stmt.parameterIsByRef;
    sym.returnTypeDesc = TypeDescriptor(BaseType::VOID);
    
    // Process parameter types
    for (size_t i = 0; i < stmt.parameters.size(); ++i) {
        VariableType paramType = VariableType::UNKNOWN;
        std::string paramTypeName = "";
        
        if (i < stmt.parameterAsTypes.size() && !stmt.parameterAsTypes[i].empty()) {
            // Has AS TypeName
            paramTypeName = stmt.parameterAsTypes[i];
            
            // Convert to uppercase for case-insensitive comparison
            std::string upperTypeName = paramTypeName;
            std::transform(upperTypeName.begin(), upperTypeName.end(), upperTypeName.begin(), ::toupper);
            
            // Check if it's a built-in type keyword or user-defined type
            if (upperTypeName == "INTEGER" || upperTypeName == "INT") {
                paramType = VariableType::INT;
                paramTypeName = "";  // It's built-in, don't store name
            } else if (upperTypeName == "DOUBLE") {
                paramType = VariableType::DOUBLE;
                paramTypeName = "";
            } else if (upperTypeName == "SINGLE" || upperTypeName == "FLOAT") {
                paramType = VariableType::FLOAT;
                paramTypeName = "";
            } else if (upperTypeName == "STRING") {
                paramType = VariableType::STRING;
                paramTypeName = "";
            } else if (upperTypeName == "LONG") {
                paramType = VariableType::INT;  // legacy enum (lossy)
                paramTypeName = "LONG";  // preserve for direct TypeDescriptor below
            } else {
                // User-defined type - validate it exists
                if (m_symbolTable.types.find(paramTypeName) == m_symbolTable.types.end()) {
                    error(SemanticErrorType::TYPE_ERROR,
                          "Unknown type '" + paramTypeName + "' in parameter " + stmt.parameters[i],
                          stmt.location);
                }
                paramType = VariableType::USER_DEFINED;
            }
        } else if (i < stmt.parameterTypes.size()) {
            // Has type suffix
            paramType = inferTypeFromSuffix(stmt.parameterTypes[i]);
        } else {
            paramType = VariableType::DOUBLE;  // Default type (DOUBLE, not FLOAT)
        }
        
        // Build TypeDescriptor for this parameter
        // Types that the legacy VariableType enum can't represent (LONG, SHORT,
        // BYTE, etc.) are built directly to avoid losing precision.
        TypeDescriptor paramTypeDesc;
        if (paramTypeName == "LONG") {
            paramTypeDesc = TypeDescriptor(BaseType::LONG);
        } else if (paramTypeName == "SHORT") {
            paramTypeDesc = TypeDescriptor(BaseType::SHORT);
        } else if (paramTypeName == "BYTE") {
            paramTypeDesc = TypeDescriptor(BaseType::BYTE);
        } else if (paramTypeName == "ULONG") {
            paramTypeDesc = TypeDescriptor(BaseType::ULONG);
        } else if (paramTypeName == "UBYTE") {
            paramTypeDesc = TypeDescriptor(BaseType::UBYTE);
        } else if (paramTypeName == "USHORT") {
            paramTypeDesc = TypeDescriptor(BaseType::USHORT);
        } else if (paramTypeName == "UINTEGER" || paramTypeName == "UINT") {
            paramTypeDesc = TypeDescriptor(BaseType::UINTEGER);
        } else if (paramType == VariableType::USER_DEFINED && !paramTypeName.empty()) {
            paramTypeDesc = legacyTypeToDescriptor(paramType);
            paramTypeDesc.udtName = paramTypeName;
            paramTypeDesc.udtTypeId = m_symbolTable.allocateTypeId(paramTypeName);
        } else {
            paramTypeDesc = legacyTypeToDescriptor(paramType);
        }
        sym.parameterTypeDescs.push_back(paramTypeDesc);
        
        // Add parameter as a variable in the symbol table so it can be looked up
        // Create parameter with function scope
        Scope funcScope = Scope::makeFunction(stmt.subName);
        VariableSymbol paramVar(stmt.parameters[i], paramTypeDesc, funcScope, true);
        paramVar.firstUse = stmt.location;
        // For UDT parameters, set typeName so codegen can look up the UDT definition
        if (paramType == VariableType::USER_DEFINED && !paramTypeName.empty()) {
            paramVar.typeName = paramTypeName;
        }
        m_symbolTable.insertVariable(stmt.parameters[i], paramVar);
    }
    
    m_symbolTable.functions[stmt.subName] = sym;
    
    // Clear current function scope
    m_currentFunctionName = "";
}

void SemanticAnalyzer::collectDataStatements(Program& program) {
    // Early pass - collect ONLY DATA statements
    // Track both line numbers and labels that appear on DATA lines
    // Also track labels on preceding lines (label followed by DATA on next line)
    
    std::string pendingLabel;  // Label from previous line waiting for DATA
    
    for (const auto& line : program.lines) {
        int lineNumber = line->lineNumber;
        std::string dataLabel;  // Label on this line (if any)
        bool hasData = false;
        bool hasLabel = false;
        
        // First pass: check if this line has DATA and/or collect any label
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_LABEL) {
                // Found a label on this line
                const auto* labelStmt = static_cast<const LabelStatement*>(stmt.get());
                dataLabel = labelStmt->labelName;
                hasLabel = true;
                // DEBUG
                // fprintf(stderr, "[collectDataStatements] Found label '%s' on line %d\n", 
                //        dataLabel.c_str(), lineNumber);
            } else if (stmt->getType() == ASTNodeType::STMT_DATA) {
                hasData = true;
                // DEBUG
                // fprintf(stderr, "[collectDataStatements] Found DATA on line %d\n", lineNumber);
            }
        }
        
        // Second pass: if this line has DATA, process it with label info
        if (hasData) {
            // Use label from current line, or pending label from previous line
            std::string effectiveLabel = dataLabel.empty() ? pendingLabel : dataLabel;
            
            // DEBUG
            if (getenv("FASTERBASIC_DEBUG")) {
                fprintf(stderr, "[collectDataStatements] Processing DATA on line %d with label '%s'\n", 
                       lineNumber, effectiveLabel.c_str());
            }
            
            for (const auto& stmt : line->statements) {
                if (stmt->getType() == ASTNodeType::STMT_DATA) {
                    processDataStatement(static_cast<const DataStatement&>(*stmt), 
                                       lineNumber, effectiveLabel);
                }
            }
            
            // Clear pending label after using it
            pendingLabel.clear();
        } else if (hasLabel) {
            // Label without DATA on this line - save it for next DATA line
            pendingLabel = dataLabel;
        } else {
            // Line with neither label nor DATA - clear pending label
            pendingLabel.clear();
        }
    }
}

void SemanticAnalyzer::processDimStatement(const DimStatement& stmt) {
    for (const auto& arrayDim : stmt.arrays) {
        // Check if this is a scalar user-defined type declaration
        // DIM P AS Point (no dimensions) should create a variable, not an array
        if (arrayDim.dimensions.empty() && arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
            // Skip this UDT/CLASS path for LIST types — they are handled below
            // as built-in OBJECT types (like HASHMAP), not as user-defined types.
            if (arrayDim.asTypeKeyword == TokenType::KEYWORD_LIST) {
                // Fall through to the scalar variable declaration path below
                // which handles KEYWORD_LIST via the makeList() factory.
                goto handle_scalar_builtin;
            }
            
            // This is a scalar UDT or CLASS variable declaration (inside function or global)
            if (m_symbolTable.variables.find(arrayDim.name) != m_symbolTable.variables.end()) {
                error(SemanticErrorType::ARRAY_REDECLARED,
                      "Variable '" + arrayDim.name + "' already declared",
                      stmt.location);
                continue;
            }
            
            // Check if the type is a CLASS first, then fall back to TYPE
            const ClassSymbol* cls = m_symbolTable.lookupClass(arrayDim.asTypeName);
            if (cls) {
                // CLASS instance variable — pointer semantics, heap-allocated
                TypeDescriptor typeDesc = TypeDescriptor::makeClassInstance(arrayDim.asTypeName);
                
                VariableSymbol* sym = declareVariableD(arrayDim.name, typeDesc, stmt.location, true);
                // Scope is already set by declareVariableD() using getCurrentScope()
                continue;
            }
            
            // Check if the type exists as a TYPE declaration
            if (m_symbolTable.types.find(arrayDim.asTypeName) == m_symbolTable.types.end()) {
                error(SemanticErrorType::UNDEFINED_TYPE,
                      "Type '" + arrayDim.asTypeName + "' not defined",
                      stmt.location);
                continue;
            }
            
            // Use new TypeDescriptor system
            TypeDescriptor typeDesc(BaseType::USER_DEFINED);
            typeDesc.udtName = arrayDim.asTypeName;
            typeDesc.udtTypeId = m_symbolTable.allocateTypeId(arrayDim.asTypeName);
            
            VariableSymbol* sym = declareVariableD(arrayDim.name, typeDesc, stmt.location, true);
            // Scope is already set by declareVariableD() using getCurrentScope()
            continue;
        }
        
        // Check if this is a scalar variable of a built-in type
        // DIM x AS INTEGER or DIM x% (no dimensions) should create a variable, not an array
        handle_scalar_builtin:
        if (arrayDim.dimensions.empty()) {
            // This is a scalar variable declaration
            if (m_symbolTable.variables.find(arrayDim.name) != m_symbolTable.variables.end()) {
                error(SemanticErrorType::ARRAY_REDECLARED,
                      "Variable '" + arrayDim.name + "' already declared",
                      stmt.location);
                continue;
            }
            
            // Use new TypeDescriptor system
            TypeDescriptor typeDesc;
            
            // Infer type from suffix or explicit AS type
            // Check asTypeKeyword first (for built-in types like HASHMAP, LIST, INTEGER, etc.)
            if (arrayDim.hasAsType && arrayDim.asTypeKeyword == TokenType::KEYWORD_LIST) {
                // LIST type — parse asTypeName to determine element type
                // asTypeName is "LIST" (bare) or "LIST OF <ELEMTYPE>"
                std::string listSpec = arrayDim.asTypeName;
                std::string upperSpec = listSpec;
                std::transform(upperSpec.begin(), upperSpec.end(), upperSpec.begin(), ::toupper);
                
                if (upperSpec == "LIST" || upperSpec == "LIST OF ANY") {
                    typeDesc = TypeDescriptor::makeList(BaseType::UNKNOWN);
                } else if (upperSpec == "LIST OF INTEGER" || upperSpec == "LIST OF INT") {
                    typeDesc = TypeDescriptor::makeList(BaseType::INTEGER);
                } else if (upperSpec == "LIST OF LONG") {
                    typeDesc = TypeDescriptor::makeList(BaseType::LONG);
                } else if (upperSpec == "LIST OF DOUBLE") {
                    typeDesc = TypeDescriptor::makeList(BaseType::DOUBLE);
                } else if (upperSpec == "LIST OF SINGLE" || upperSpec == "LIST OF FLOAT") {
                    typeDesc = TypeDescriptor::makeList(BaseType::SINGLE);
                } else if (upperSpec == "LIST OF STRING") {
                    typeDesc = TypeDescriptor::makeList(BaseType::STRING);
                } else if (upperSpec == "LIST OF LIST") {
                    typeDesc = TypeDescriptor::makeList(BaseType::OBJECT);
                } else if (upperSpec == "LIST OF HASHMAP") {
                    typeDesc = TypeDescriptor::makeList(BaseType::OBJECT);
                } else if (upperSpec == "LIST OF BYTE") {
                    typeDesc = TypeDescriptor::makeList(BaseType::BYTE);
                } else if (upperSpec == "LIST OF SHORT") {
                    typeDesc = TypeDescriptor::makeList(BaseType::SHORT);
                } else {
                    // Default: LIST OF ANY
                    typeDesc = TypeDescriptor::makeList(BaseType::UNKNOWN);
                }
            } else if (arrayDim.hasAsType && arrayDim.asTypeKeyword != TokenType::UNKNOWN) {
                // Use keywordToDescriptor to get correct type from keyword token
                typeDesc = keywordToDescriptor(arrayDim.asTypeKeyword);
            } else if (arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
                // AS TypeName (for user-defined types)
                // This is only used when asTypeKeyword is UNKNOWN
                std::string typeName = arrayDim.asTypeName;
                // Convert to uppercase for case-insensitive comparison
                std::string upperTypeName = typeName;
                std::transform(upperTypeName.begin(), upperTypeName.end(), upperTypeName.begin(), ::toupper);
                
                if (upperTypeName == "INTEGER" || upperTypeName == "INT") {
                    typeDesc = TypeDescriptor(BaseType::INTEGER);
                } else if (upperTypeName == "LONG") {
                    typeDesc = TypeDescriptor(BaseType::LONG);
                } else if (upperTypeName == "SHORT") {
                    typeDesc = TypeDescriptor(BaseType::SHORT);
                } else if (upperTypeName == "BYTE") {
                    typeDesc = TypeDescriptor(BaseType::BYTE);
                } else if (upperTypeName == "DOUBLE") {
                    typeDesc = TypeDescriptor(BaseType::DOUBLE);
                } else if (typeName == "FLOAT" || typeName == "SINGLE") {
                    typeDesc = TypeDescriptor(BaseType::SINGLE);
                } else if (upperTypeName == "STRING") {
                    // For STRING variable declarations, use global mode
                    typeDesc = (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                        TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
                } else if (upperTypeName == "UBYTE") {
                    typeDesc = TypeDescriptor(BaseType::UBYTE);
                } else if (upperTypeName == "USHORT") {
                    typeDesc = TypeDescriptor(BaseType::USHORT);
                } else if (upperTypeName == "UINTEGER") {
                    typeDesc = TypeDescriptor(BaseType::UINTEGER);
                } else if (upperTypeName == "ULONG") {
                    typeDesc = TypeDescriptor(BaseType::ULONG);
                } else {
                    // Unknown built-in type name, default to DOUBLE
                    typeDesc = TypeDescriptor(BaseType::DOUBLE);
                }
            } else {
                // Infer from suffix or name
                typeDesc = inferTypeFromSuffixD(arrayDim.typeSuffix);
                if (typeDesc.baseType == BaseType::UNKNOWN) {
                    typeDesc = inferTypeFromNameD(arrayDim.name);
                }
            }
            
            VariableSymbol* sym = declareVariableD(arrayDim.name, typeDesc, stmt.location, true);
            // Scope is already set by declareVariableD() using getCurrentScope()
            continue;
        }
        
        // Check if already declared
        if (m_symbolTable.arrays.find(arrayDim.name) != m_symbolTable.arrays.end()) {
            error(SemanticErrorType::ARRAY_REDECLARED,
                  "Array '" + arrayDim.name + "' already declared",
                  stmt.location);
            continue;
        }
        
        // Calculate dimensions
        // NOTE: Since arrays compile to Lua tables (which are dynamic), we don't strictly
        // need compile-time constant dimensions. We'll try to evaluate as constants for
        // optimization hints, but allow variables too.
        std::vector<int> dimensions;
        int totalSize = 1;
        bool hasUnknownDimensions = false;
        
        for (const auto& dimExpr : arrayDim.dimensions) {
            // Check if this is a compile-time constant expression
            bool isConstant = isConstantExpression(*dimExpr);
            
            if (isConstant) {
                // Try to evaluate as constant expression for optimization
                try {
                    FasterBASIC::ConstantValue constVal = evaluateConstantExpression(*dimExpr);
                    
                    // Convert to integer size
                    int size = 0;
                    if (std::holds_alternative<int64_t>(constVal)) {
                        size = static_cast<int>(std::get<int64_t>(constVal));
                    } else if (std::holds_alternative<double>(constVal)) {
                        size = static_cast<int>(std::get<double>(constVal));
                    } else {
                        // Non-numeric constant - this is an error
                        error(SemanticErrorType::INVALID_ARRAY_INDEX,
                              "Array dimension must be numeric",
                              stmt.location);
                        size = 10;  // Default fallback
                    }
                    
                    if (size < 0) {
                        error(SemanticErrorType::INVALID_ARRAY_INDEX,
                              "Constant array dimension must be non-negative (got " + std::to_string(size) + ")",
                              stmt.location);
                        size = 1;
                    }
                    
                    // BASIC arrays: DIM A(N) creates array with indices 0 to N (inclusive)
                    // Store N+1 as the dimension size to allow N+1 elements
                    dimensions.push_back(size + 1);
                    totalSize *= (size + 1);
                } catch (...) {
                    // Evaluation failed even though it looked constant
                    dimensions.push_back(-1);
                    hasUnknownDimensions = true;
                }
            } else {
                // Non-constant dimension (e.g., variable) - allowed since Lua arrays are dynamic
                // Store -1 as a sentinel to indicate runtime-determined dimension
                dimensions.push_back(-1);
                hasUnknownDimensions = true;
                // Can't calculate total size if any dimension is unknown
            }
        }
        
        // Determine element type using TypeDescriptor
        TypeDescriptor elementType;
        
        // Check if this is a built-in type with AS keyword (preserves unsigned info)
        if (arrayDim.hasAsType && arrayDim.asTypeKeyword != TokenType::UNKNOWN) {
            // Use keywordToDescriptor to get correct unsigned type
            elementType = keywordToDescriptor(arrayDim.asTypeKeyword);
        } else if (arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
            // Check if the type is a CLASS first, then fall back to TYPE (UDT)
            const ClassSymbol* cls = m_symbolTable.lookupClass(arrayDim.asTypeName);
            if (cls) {
                // Array of CLASS instances — each element is a class-instance pointer
                elementType = TypeDescriptor::makeClassInstance(arrayDim.asTypeName);
            } else if (m_symbolTable.types.find(arrayDim.asTypeName) != m_symbolTable.types.end()) {
                elementType = TypeDescriptor(BaseType::USER_DEFINED);
                elementType.udtName = arrayDim.asTypeName;
                elementType.udtTypeId = m_symbolTable.allocateTypeId(arrayDim.asTypeName);
            } else {
                error(SemanticErrorType::UNDEFINED_TYPE,
                      "Type '" + arrayDim.asTypeName + "' not defined",
                      stmt.location);
                continue;
            }
        } else {
            // Built-in type - check for AS clause or infer from suffix/name
            if (arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
                std::string typeName = arrayDim.asTypeName;
                // Convert to uppercase for case-insensitive comparison
                std::string upperTypeName = typeName;
                std::transform(upperTypeName.begin(), upperTypeName.end(), upperTypeName.begin(), ::toupper);
                
                if (upperTypeName == "INTEGER" || upperTypeName == "INT") {
                    elementType = TypeDescriptor(BaseType::INTEGER);
                } else if (upperTypeName == "LONG") {
                    elementType = TypeDescriptor(BaseType::LONG);
                } else if (upperTypeName == "SHORT") {
                    elementType = TypeDescriptor(BaseType::SHORT);
                } else if (upperTypeName == "BYTE") {
                    elementType = TypeDescriptor(BaseType::BYTE);
                } else if (upperTypeName == "DOUBLE") {
                    elementType = TypeDescriptor(BaseType::DOUBLE);
                } else if (typeName == "FLOAT" || typeName == "SINGLE") {
                    elementType = TypeDescriptor(BaseType::SINGLE);
                } else if (upperTypeName == "STRING") {
                    // For STRING array declarations, use global mode
                    elementType = (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                        TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
                } else if (upperTypeName == "UBYTE") {
                    elementType = TypeDescriptor(BaseType::UBYTE);
                } else if (upperTypeName == "USHORT") {
                    elementType = TypeDescriptor(BaseType::USHORT);
                } else if (upperTypeName == "UINTEGER") {
                    elementType = TypeDescriptor(BaseType::UINTEGER);
                } else if (upperTypeName == "ULONG") {
                    elementType = TypeDescriptor(BaseType::ULONG);
                } else {
                    elementType = TypeDescriptor(BaseType::DOUBLE);
                }
            } else {
                // Infer from suffix or name
                elementType = inferTypeFromSuffixD(arrayDim.typeSuffix);
                if (elementType.baseType == BaseType::UNKNOWN) {
                    elementType = inferTypeFromNameD(arrayDim.name);
                }
            }
        }
        
        // Use new TypeDescriptor-based array declaration
        ArraySymbol* sym = declareArrayD(arrayDim.name, elementType, dimensions, stmt.location);
        if (!sym) {
            continue;
        }
        
        // Set additional properties
        sym->functionScope = m_currentFunctionName;
        if (hasUnknownDimensions) {
            sym->totalSize = -1;  // Runtime-determined
        } else {
            sym->totalSize = totalSize;
        }

    }
}

void SemanticAnalyzer::processDefStatement(const DefStatement& stmt) {
    // Check if already declared
    if (m_symbolTable.functions.find(stmt.functionName) != m_symbolTable.functions.end()) {
        error(SemanticErrorType::FUNCTION_REDECLARED,
              "Function FN" + stmt.functionName + " already declared",
              stmt.location);
        return;
    }
    
    FunctionSymbol sym;
    sym.name = stmt.functionName;
    sym.parameters = stmt.parameters;
    sym.body = stmt.body.get();
    sym.definition = stmt.location;
    
    // Infer return type from function name
    sym.returnTypeDesc = legacyTypeToDescriptor(inferTypeFromName(stmt.functionName));
    
    // Infer parameter types from parameter names AND suffixes
    for (size_t i = 0; i < stmt.parameters.size(); ++i) {
        const std::string& paramName = stmt.parameters[i];
        
        // Use the stored suffix if available, otherwise fall back to name inference
        TypeDescriptor paramTypeDesc;
        if (i < stmt.parameterSuffixes.size() && stmt.parameterSuffixes[i] != TokenType::UNKNOWN) {
            paramTypeDesc = inferTypeFromSuffixD(stmt.parameterSuffixes[i]);
        } else {
            paramTypeDesc = inferTypeFromNameD(paramName);
        }

        sym.parameterTypeDescs.push_back(paramTypeDesc);
        sym.parameterIsByRef.push_back(false);  // DEF FN parameters are always by value

        // Add parameter as a variable in the symbol table so it can be looked up
        // Create parameter with function scope
        Scope funcScope = Scope::makeFunction(stmt.functionName);
        VariableSymbol paramVar(paramName, paramTypeDesc, funcScope, true);
        paramVar.firstUse = stmt.location;
        m_symbolTable.insertVariable(paramName, paramVar);
    }
    
    m_symbolTable.functions[stmt.functionName] = sym;
}

void SemanticAnalyzer::processConstantStatement(const ConstantStatement& stmt) {
    // Check if constant already declared (case-insensitive)
    std::string lowerName = stmt.name;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
    
    if (m_symbolTable.constants.find(lowerName) != m_symbolTable.constants.end()) {
        error(SemanticErrorType::DUPLICATE_LABEL,  // Reusing error type for constants
              "Constant " + stmt.name + " already declared",
              stmt.location);
        return;
    }
    
    // Evaluate constant expression at compile time (supports full expressions now)
    FasterBASIC::ConstantValue evalResult = evaluateConstantExpression(*stmt.value);
    
    // Convert ConstantValue to ConstantSymbol
    ConstantSymbol constValue;
    if (std::holds_alternative<int64_t>(evalResult)) {
        constValue = ConstantSymbol(std::get<int64_t>(evalResult));
    } else if (std::holds_alternative<double>(evalResult)) {
        constValue = ConstantSymbol(std::get<double>(evalResult));
    } else if (std::holds_alternative<std::string>(evalResult)) {
        constValue = ConstantSymbol(std::get<std::string>(evalResult));
    }
    
    // Add to C++ ConstantsManager and get index
    int index = -1;
    if (std::holds_alternative<int64_t>(evalResult)) {
        index = m_constantsManager.addConstant(stmt.name, std::get<int64_t>(evalResult));
    } else if (std::holds_alternative<double>(evalResult)) {
        index = m_constantsManager.addConstant(stmt.name, std::get<double>(evalResult));
    } else if (std::holds_alternative<std::string>(evalResult)) {
        index = m_constantsManager.addConstant(stmt.name, std::get<std::string>(evalResult));
    }
    
    constValue.index = index;
    m_symbolTable.constants[lowerName] = constValue;
}

void SemanticAnalyzer::processDataStatement(const DataStatement& stmt, int lineNumber,
                                            const std::string& dataLabel) {
    // Get current index (where this DATA starts)
    size_t currentIndex = m_symbolTable.dataSegment.values.size();
    
    // Record restore point by line number (if present)
    if (lineNumber > 0) {
        m_symbolTable.dataSegment.restorePoints[lineNumber] = currentIndex;
        // DEBUG
        if (getenv("FASTERBASIC_DEBUG")) {
            fprintf(stderr, "[processDataStatement] Recorded line %d -> index %zu\n", 
                   lineNumber, currentIndex);
        }
    }
    
    // Record restore point by label (if present on this DATA line)
    if (!dataLabel.empty()) {
        m_symbolTable.dataSegment.labelRestorePoints[dataLabel] = currentIndex;
        // DEBUG
        if (getenv("FASTERBASIC_DEBUG")) {
            fprintf(stderr, "[processDataStatement] Recorded label '%s' -> index %zu\n", 
                   dataLabel.c_str(), currentIndex);
        }
    }
    
    // Add values to data segment
    for (const auto& value : stmt.values) {
        m_symbolTable.dataSegment.values.push_back(value);
    }
}

void SemanticAnalyzer::collectForEachVariables(Program& program) {
    // Collect FOR EACH variables so we can prevent them from being added to symbol table
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                const ForInStatement* forInStmt = static_cast<const ForInStatement*>(stmt.get());
                m_forEachVariables.insert(forInStmt->variable);
                if (!forInStmt->indexVariable.empty()) {
                    m_forEachVariables.insert(forInStmt->indexVariable);
                }
            }
        }
    }
}

// =============================================================================
// Pass 2: Validation
// =============================================================================

void SemanticAnalyzer::pass2_validate(Program& program) {
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] pass2_validate: processing " << program.lines.size() << " lines" << std::endl;
    }
    for (const auto& line : program.lines) {
        if (getenv("FASTERBASIC_DEBUG")) {
            std::cerr << "[DEBUG] pass2_validate: line " << line->lineNumber << " has " << line->statements.size() << " statements" << std::endl;
        }
        validateProgramLine(*line);
    }
}

void SemanticAnalyzer::validateProgramLine(const ProgramLine& line) {
    m_currentLineNumber = line.lineNumber;
    
    for (const auto& stmt : line.statements) {
        validateStatement(*stmt);
    }
}

void SemanticAnalyzer::validateStatement(const Statement& stmt) {
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] validateStatement called for type: " << (int)stmt.getType() << std::endl;
    }
    switch (stmt.getType()) {
        case ASTNodeType::STMT_TRY_CATCH:
            validateTryCatchStatement(static_cast<const TryCatchStatement&>(stmt));
            break;
        case ASTNodeType::STMT_THROW:
            validateThrowStatement(static_cast<const ThrowStatement&>(stmt));
            break;
        case ASTNodeType::STMT_PRINT:
            validatePrintStatement(static_cast<const PrintStatement&>(stmt));
            break;
        case ASTNodeType::STMT_CONSOLE:
            validateConsoleStatement(static_cast<const ConsoleStatement&>(stmt));
            break;
        case ASTNodeType::STMT_INPUT:
            validateInputStatement(static_cast<const InputStatement&>(stmt));
            break;
        case ASTNodeType::STMT_INPUT_AT:
            // Check if INPUT AT is being called from within a timer handler
            if (m_inTimerHandler) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "INPUT AT statement not allowed in timer event handlers. "
                      "Handlers must not block for user input.",
                      stmt.location);
            }
            break;
        case ASTNodeType::STMT_LET:
            validateLetStatement(static_cast<const LetStatement&>(stmt));
            break;
        case ASTNodeType::STMT_SLICE_ASSIGN:
            validateSliceAssignStatement(static_cast<const SliceAssignStatement&>(stmt));
            break;
        case ASTNodeType::STMT_GOTO:
            validateGotoStatement(static_cast<const GotoStatement&>(stmt));
            break;
        case ASTNodeType::STMT_GOSUB:
            validateGosubStatement(static_cast<const GosubStatement&>(stmt));
            break;
        case ASTNodeType::STMT_ON_GOTO:
            validateOnGotoStatement(static_cast<const OnGotoStatement&>(stmt));
            break;
        case ASTNodeType::STMT_ON_GOSUB:
            validateOnGosubStatement(static_cast<const OnGosubStatement&>(stmt));
            break;
        case ASTNodeType::STMT_IF:
            validateIfStatement(static_cast<const IfStatement&>(stmt));
            break;
        case ASTNodeType::STMT_FOR:
            validateForStatement(static_cast<const ForStatement&>(stmt));
            break;
        case ASTNodeType::STMT_FOR_IN:
            validateForInStatement(static_cast<ForInStatement&>(const_cast<Statement&>(stmt)));
            break;
        case ASTNodeType::STMT_NEXT:
            validateNextStatement(static_cast<const NextStatement&>(stmt));
            break;
        case ASTNodeType::STMT_WHILE:
            validateWhileStatement(static_cast<const WhileStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_WEND:
            validateWendStatement(static_cast<const WendStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_REPEAT:
            validateRepeatStatement(static_cast<const RepeatStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_UNTIL:
            validateUntilStatement(static_cast<const UntilStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_DO:
            validateDoStatement(static_cast<const DoStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_LOOP:
            validateLoopStatement(static_cast<const LoopStatement&>(stmt));
            break;
        case ASTNodeType::STMT_READ:
            validateReadStatement(static_cast<const ReadStatement&>(stmt));
            break;
        case ASTNodeType::STMT_RESTORE:
            validateRestoreStatement(static_cast<const RestoreStatement&>(stmt));
            break;
        case ASTNodeType::STMT_ON_EVENT:
            // ONEVENT is deprecated - use AFTER/EVERY instead
            // validateOnEventStatement(static_cast<const OnEventStatement&>(stmt));
            break;
            
        // Timer event statements
        case ASTNodeType::STMT_AFTER:
            validateAfterStatement(static_cast<const AfterStatement&>(stmt));
            break;
        case ASTNodeType::STMT_EVERY:
            validateEveryStatement(static_cast<const EveryStatement&>(stmt));
            break;
        case ASTNodeType::STMT_AFTERFRAMES:
            validateAfterFramesStatement(static_cast<const AfterFramesStatement&>(stmt));
            break;
        case ASTNodeType::STMT_EVERYFRAME:
            validateEveryFrameStatement(static_cast<const EveryFrameStatement&>(stmt));
            break;
        
        case ASTNodeType::STMT_RUN:
            validateRunStatement(static_cast<const RunStatement&>(stmt));
            break;
        case ASTNodeType::STMT_TIMER_STOP:
            validateTimerStopStatement(static_cast<const TimerStopStatement&>(stmt));
            break;
        case ASTNodeType::STMT_TIMER_INTERVAL:
            validateTimerIntervalStatement(static_cast<const TimerIntervalStatement&>(stmt));
            break;
            
        case ASTNodeType::STMT_COLOR:
        case ASTNodeType::STMT_WAIT:
        case ASTNodeType::STMT_WAIT_MS:
        case ASTNodeType::STMT_PSET:
        case ASTNodeType::STMT_LINE:
        case ASTNodeType::STMT_RECT:
        case ASTNodeType::STMT_CIRCLE:
        case ASTNodeType::STMT_CIRCLEF:
            validateExpressionStatement(static_cast<const ExpressionStatement&>(stmt));
            break;
        case ASTNodeType::STMT_DIM: {
            // DIM inside a FUNCTION/SUB body — register the declared variables
            // as local so validateVariableInFunction() accepts them.
            if (m_currentFunctionScope.inFunction) {
                const DimStatement& dimStmt = static_cast<const DimStatement&>(stmt);
                for (const auto& arrayDim : dimStmt.arrays) {
                    // Register the bare name
                    m_currentFunctionScope.localVariables.insert(arrayDim.name);
                    
                    // Also register normalized (suffixed) variants so that
                    // lookups like "temp_INT" succeed.
                    TypeDescriptor td;
                    if (arrayDim.hasAsType && !arrayDim.asTypeName.empty()) {
                        std::string upper = arrayDim.asTypeName;
                        std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
                        if (upper == "INTEGER" || upper == "INT") td = TypeDescriptor(BaseType::INTEGER);
                        else if (upper == "LONG") td = TypeDescriptor(BaseType::LONG);
                        else if (upper == "DOUBLE") td = TypeDescriptor(BaseType::DOUBLE);
                        else if (upper == "SINGLE" || upper == "FLOAT") td = TypeDescriptor(BaseType::SINGLE);
                        else if (upper == "STRING") td = TypeDescriptor(BaseType::STRING);
                        else if (upper == "SHORT") td = TypeDescriptor(BaseType::SHORT);
                        else if (upper == "BYTE") td = TypeDescriptor(BaseType::BYTE);
                        else if (m_symbolTable.classes.find(upper) != m_symbolTable.classes.end()) {
                            td = TypeDescriptor::makeClassInstance(upper);
                        } else {
                            td = TypeDescriptor(BaseType::USER_DEFINED);
                            td.udtName = arrayDim.asTypeName;
                        }
                    } else {
                        td = inferTypeFromSuffixD(arrayDim.typeSuffix);
                        if (td.baseType == BaseType::UNKNOWN) {
                            td = inferTypeFromNameD(arrayDim.name);
                        }
                    }
                    std::string normalized = normalizeVariableName(arrayDim.name, td);
                    m_currentFunctionScope.localVariables.insert(normalized);
                }
            }
            break;
        }
        case ASTNodeType::STMT_FUNCTION: {
            const FunctionStatement& funcStmt = static_cast<const FunctionStatement&>(stmt);
            std::string prevFuncName = m_currentFunctionName;
            bool prevInHandler = m_inTimerHandler;
            
            // Set up function scope
            FunctionScope prevScope = m_currentFunctionScope;
            m_currentFunctionScope = FunctionScope();
            m_currentFunctionScope.inFunction = true;
            m_currentFunctionScope.functionName = funcStmt.functionName;
            m_currentFunctionScope.isSub = false;  // This is a FUNCTION
            
            // Set expected return type
            auto* funcSym = lookupFunction(funcStmt.functionName);
            if (funcSym) {
                m_currentFunctionScope.expectedReturnType = funcSym->returnTypeDesc;
                m_currentFunctionScope.expectedReturnTypeName = funcSym->returnTypeName;
            }
            
            // Add parameters to scope
            for (const auto& param : funcStmt.parameters) {
                m_currentFunctionScope.parameters.insert(param);
            }
            
            m_currentFunctionName = funcStmt.functionName;
            m_inTimerHandler = (m_registeredHandlers.find(funcStmt.functionName) != m_registeredHandlers.end());
            
            // Validate function body (will collect LOCAL/SHARED and check usage)
            for (const auto& bodyStmt : funcStmt.body) {
                validateStatement(*bodyStmt);
            }
            
            // Restore previous scope
            m_currentFunctionScope = prevScope;
            m_currentFunctionName = prevFuncName;
            m_inTimerHandler = prevInHandler;
            break;
        }
        case ASTNodeType::STMT_SUB: {
            const SubStatement& subStmt = static_cast<const SubStatement&>(stmt);
            std::string prevFuncName = m_currentFunctionName;
            bool prevInHandler = m_inTimerHandler;
            
            // Set up function scope
            FunctionScope prevScope = m_currentFunctionScope;
            m_currentFunctionScope = FunctionScope();
            m_currentFunctionScope.inFunction = true;
            m_currentFunctionScope.functionName = subStmt.subName;
            m_currentFunctionScope.isSub = true;  // This is a SUB
            m_currentFunctionScope.expectedReturnType = TypeDescriptor(BaseType::VOID);
            
            // Add parameters to scope
            for (const auto& param : subStmt.parameters) {
                m_currentFunctionScope.parameters.insert(param);
            }
            
            m_currentFunctionName = subStmt.subName;
            m_inTimerHandler = (m_registeredHandlers.find(subStmt.subName) != m_registeredHandlers.end());
            
            // Validate sub body (will collect LOCAL/SHARED and check usage)
            for (const auto& bodyStmt : subStmt.body) {
                validateStatement(*bodyStmt);
            }
            
            // Restore previous scope
            m_currentFunctionScope = prevScope;
            m_currentFunctionName = prevFuncName;
            m_inTimerHandler = prevInHandler;
            break;
        }
        case ASTNodeType::STMT_LOCAL: {
            const LocalStatement& localStmt = static_cast<const LocalStatement&>(stmt);
            
            if (!m_currentFunctionScope.inFunction) {
                error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                      "LOCAL can only be used inside SUB or FUNCTION",
                      stmt.location);
            }
            
            // Add local variables to function scope AND symbol table
            for (const auto& var : localStmt.variables) {
                // Determine type descriptor first
                TypeDescriptor typeDesc;
                if (var.hasAsType && !var.asTypeName.empty()) {
                    // Has AS TypeName
                    std::string upperType = var.asTypeName;
                    std::transform(upperType.begin(), upperType.end(), upperType.begin(), ::toupper);
                    
                    if (upperType == "INTEGER" || upperType == "INT") {
                        typeDesc = TypeDescriptor(BaseType::INTEGER);
                    } else if (upperType == "DOUBLE") {
                        typeDesc = TypeDescriptor(BaseType::DOUBLE);
                    } else if (upperType == "SINGLE" || upperType == "FLOAT") {
                        typeDesc = TypeDescriptor(BaseType::SINGLE);
                    } else if (upperType == "STRING") {
                        typeDesc = TypeDescriptor(BaseType::STRING);
                    } else if (upperType == "LONG") {
                        typeDesc = TypeDescriptor(BaseType::LONG);
                    } else if (upperType == "BYTE") {
                        typeDesc = TypeDescriptor(BaseType::BYTE);
                    } else if (upperType == "SHORT") {
                        typeDesc = TypeDescriptor(BaseType::SHORT);
                    } else {
                        // User-defined type
                        if (m_symbolTable.types.find(var.asTypeName) == m_symbolTable.types.end()) {
                            error(SemanticErrorType::TYPE_ERROR,
                                  "Unknown type '" + var.asTypeName + "' for LOCAL variable " + var.name,
                                  stmt.location);
                        }
                        typeDesc = TypeDescriptor(BaseType::USER_DEFINED);
                        typeDesc.udtName = var.asTypeName;
                    }
                } else {
                    // Infer from suffix
                    typeDesc = legacyTypeToDescriptor(inferTypeFromSuffix(var.typeSuffix));
                }
                
                // Normalize the variable name to include proper type suffix
                std::string normalizedName = normalizeVariableName(var.name, typeDesc);
                
                // Check for duplicate declaration using normalized name
                if (m_currentFunctionScope.localVariables.count(normalizedName) ||
                    m_currentFunctionScope.sharedVariables.count(normalizedName)) {
                    error(SemanticErrorType::ARRAY_REDECLARED,
                          "Variable '" + normalizedName + "' already declared in this function",
                          stmt.location);
                }
                
                // Add normalized name to function scope
                m_currentFunctionScope.localVariables.insert(normalizedName);
                
                // Add to symbol table with type information
                // Use explicit scope for local variables
                Scope funcScope = getCurrentScope();
                
                VariableSymbol varSym;
                varSym.name = normalizedName;  // Use normalized name
                varSym.scope = funcScope;  // Set explicit function scope
                varSym.isDeclared = true;
                varSym.firstUse = stmt.location;
                varSym.isGlobal = false;
                varSym.typeDesc = typeDesc;
                // For UDT types, set typeName so codegen and validation can look up the UDT definition
                if (typeDesc.baseType == BaseType::USER_DEFINED && !typeDesc.udtName.empty()) {
                    varSym.typeName = typeDesc.udtName;
                }
                
                // Store with scope-aware insertion (using normalized name)
                m_symbolTable.insertVariable(normalizedName, varSym);
            }
            break;
        }
        case ASTNodeType::STMT_GLOBAL: {
            // GLOBAL declarations are already collected in pass1
            // Just verify they're not inside functions
            if (m_currentFunctionScope.inFunction) {
                error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                      "GLOBAL can only be used at global scope, not inside functions",
                      stmt.location);
            }
            break;
        }
        case ASTNodeType::STMT_SHARED: {
            const SharedStatement& sharedStmt = static_cast<const SharedStatement&>(stmt);
            
            if (!m_currentFunctionScope.inFunction) {
                error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                      "SHARED can only be used inside SUB or FUNCTION",
                      stmt.location);
            }
            
            // Add shared variables to function scope
            for (const auto& var : sharedStmt.variables) {
                // Check for duplicate declaration
                if (m_currentFunctionScope.localVariables.count(var.name) ||
                    m_currentFunctionScope.sharedVariables.count(var.name)) {
                    error(SemanticErrorType::ARRAY_REDECLARED,
                          "Variable '" + var.name + "' already declared in this function",
                          stmt.location);
                }
                
                // Verify the variable exists at module level
                if (!lookupVariable(var.name)) {
                    error(SemanticErrorType::UNDEFINED_VARIABLE,
                          "SHARED variable '" + var.name + "' is not defined at module level",
                          stmt.location);
                }
                
                m_currentFunctionScope.sharedVariables.insert(var.name);
            }
            break;
        }
        case ASTNodeType::STMT_RETURN:
            validateReturnStatement(static_cast<const ReturnStatement&>(stmt));
            break;
        case ASTNodeType::STMT_MATCH_TYPE: {
            const MatchTypeStatement& matchStmt = static_cast<const MatchTypeStatement&>(stmt);
            // Validate the match expression
            if (matchStmt.matchExpression) {
                validateExpression(*matchStmt.matchExpression);
            }
            // Validate statements inside each CASE arm
            for (const auto& arm : matchStmt.caseArms) {
                for (const auto& armStmt : arm.body) {
                    if (armStmt) {
                        validateStatement(*armStmt);
                    }
                }
            }
            // Validate statements inside CASE ELSE
            for (const auto& elseStmt : matchStmt.caseElseBody) {
                if (elseStmt) {
                    validateStatement(*elseStmt);
                }
            }
            break;
        }
        default:
            // Other statements don't need special validation
            break;
    }
}

void SemanticAnalyzer::validatePrintStatement(const PrintStatement& stmt) {
    for (const auto& item : stmt.items) {
        validateExpression(*item.expr);
    }
}

void SemanticAnalyzer::validateConsoleStatement(const ConsoleStatement& stmt) {
    for (const auto& item : stmt.items) {
        validateExpression(*item.expr);
    }
}

void SemanticAnalyzer::validateInputStatement(const InputStatement& stmt) {
    // Check if INPUT is being called from within a timer handler
    if (m_inTimerHandler) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "INPUT statement not allowed in timer event handlers. "
              "Handlers must not block for user input.",
              stmt.location);
    }
    
    for (const auto& varName : stmt.variables) {
        useVariable(varName, stmt.location);
    }
}

void SemanticAnalyzer::validateSliceAssignStatement(const SliceAssignStatement& stmt) {
    // Validate the variable exists and is a string type
    useVariable(stmt.variable, stmt.location);
    
    auto* varSym = lookupVariable(stmt.variable);
    if (varSym) {
        if (varSym->typeDesc.baseType != BaseType::STRING && varSym->typeDesc.baseType != BaseType::UNICODE) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Slice assignment can only be used on STRING variables, not " + 
                  varSym->typeDesc.toString(),
                  stmt.location);
            return;
        }
    }
    
    // Validate start and end expressions (must be numeric)
    if (stmt.start) {
        validateExpression(*stmt.start);
        VariableType startType = inferExpressionType(*stmt.start);
        if (!isNumericType(startType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Slice start index must be numeric, not " + std::string(typeToString(startType)),
                  stmt.location);
        }
    }
    
    if (stmt.end) {
        validateExpression(*stmt.end);
        VariableType endType = inferExpressionType(*stmt.end);
        if (!isNumericType(endType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Slice end index must be numeric, not " + std::string(typeToString(endType)),
                  stmt.location);
        }
    }
    
    // Validate replacement expression (must be string type)
    if (stmt.replacement) {
        validateExpression(*stmt.replacement);
        VariableType replacementType = inferExpressionType(*stmt.replacement);
        if (replacementType != VariableType::STRING && replacementType != VariableType::UNICODE) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Slice replacement value must be STRING, not " + std::string(typeToString(replacementType)),
                  stmt.location);
        }
    }
}

void SemanticAnalyzer::validateLetStatement(const LetStatement& stmt) {
    // Detect whole-array SIMD operations: A() = B() + C()
    // Check if left side is whole-array access (array with empty indices)
    if (!stmt.indices.empty() && stmt.indices.size() == 0) {
        // This is never true, but kept for clarity - empty() means size() == 0
    }
    
    // Check for whole-array assignment pattern
    bool isWholeArrayAssignment = false;
    if (stmt.indices.empty()) {
        // Could be either scalar variable or whole array
        // Check if this variable is declared as an array
        auto* arraySym = lookupArray(stmt.variable);
        if (arraySym) {
            isWholeArrayAssignment = true;
            
            // Check if the array is of a SIMD-capable type
            if (!arraySym->asTypeName.empty()) {
                auto* typeSym = lookupType(arraySym->asTypeName);
                if (typeSym && typeSym->simdType != TypeDeclarationStatement::SIMDType::NONE) {
                    // This is a SIMD-capable array assignment!
                    const char* simdTypeStr = (typeSym->simdType == TypeDeclarationStatement::SIMDType::PAIR) ? "PAIR" : "QUAD";
                    std::cout << "[SIMD] Detected whole-array assignment to SIMD type " 
                              << arraySym->asTypeName << " [" << simdTypeStr << "]: "
                              << stmt.variable << "() = <expression>" << std::endl;
                    
                    // Analyze right-hand side expression
                    analyzeArrayExpression(stmt.value.get(), typeSym->simdType);
                }
            }
        }
    }
    
    // Check if assigning to a FOR loop index variable (not allowed in compiled loops)
    if (stmt.indices.empty() && !isWholeArrayAssignment) {  // Only check simple variable assignment, not arrays
        // Check if this variable is an active FOR loop index
        std::stack<ForContext> tempStack = m_forStack;
        while (!tempStack.empty()) {
            const ForContext& ctx = tempStack.top();
            if (ctx.variable == stmt.variable) {
                // Found assignment to loop index!
                warning("Assignment to FOR loop index variable '" + stmt.variable + "' detected.\n"
                       "  This pattern does NOT work for early loop exit in compiled loops.\n"
                       "  The loop will continue to its original limit.\n"
                       "  SOLUTION: Use 'EXIT FOR' instead of '" + stmt.variable + " = <value>'",
                       stmt.location);
                break;
            }
            tempStack.pop();
        }
    }
    
    // Check if this is an object with subscript operator (like hashmap)
    auto* varSym = lookupVariable(stmt.variable);
    auto& registry = getRuntimeObjectRegistry();
    bool isObject = (varSym && registry.isObjectType(varSym->typeDesc));
    const ObjectTypeDescriptor* objDesc = isObject ? registry.getObjectType(varSym->typeDesc.objectTypeName) : nullptr;
    
    // Validate array/object indices if present
    for (const auto& index : stmt.indices) {
        validateExpression(*index);
        VariableType indexType = inferExpressionType(*index);
        
        // Objects with subscript operators allow their specified key type
        // Arrays require numeric indices
        if (isObject && objDesc && objDesc->hasSubscriptOperator) {
            // Object subscript - validate key type matches expected
            // (For now, just validate the expression, type conversion will happen in codegen)
        } else if (!isNumericType(indexType)) {
            error(SemanticErrorType::INVALID_ARRAY_INDEX,
                  "Array index must be numeric",
                  stmt.location);
        }
    }
    
    // Check if object subscript or array assignment
    if (!stmt.indices.empty()) {
        if (isObject && objDesc && objDesc->hasSubscriptOperator) {
            // Object subscript assignment - validate exactly one key
            if (stmt.indices.size() != 1) {
                error(SemanticErrorType::INVALID_ARRAY_INDEX,
                      "Object subscript requires exactly one key, got " + 
                      std::to_string(stmt.indices.size()),
                      stmt.location);
            }
        } else if (!isObject) {
            // Array assignment
            useArray(stmt.variable, stmt.indices.size(), stmt.location);
        }
    } else {
        // Check variable declaration in function context
        if (m_currentFunctionScope.inFunction) {
            validateVariableInFunction(stmt.variable, stmt.location);
        } else {
            useVariable(stmt.variable, stmt.location);
        }
    }
    
    // Validate value expression
    validateExpression(*stmt.value);
    
    // Type check
    VariableType targetType;
    
    // Handle member access (UDT field assignment)
    if (!stmt.memberChain.empty()) {
        // Check if this is array element member access or simple variable member access
        std::string baseTypeName;
        
        if (!stmt.indices.empty()) {
            // Array element with member access: Points(0).X = 42
            auto* arrSym = lookupArray(stmt.variable);
            if (!arrSym) {
                error(SemanticErrorType::UNDEFINED_VARIABLE,
                      "Variable '" + stmt.variable + "' not declared",
                      stmt.location);
                return;
            }
            
            if (arrSym->elementTypeDesc.baseType != BaseType::USER_DEFINED &&
                arrSym->elementTypeDesc.baseType != BaseType::CLASS_INSTANCE &&
                !arrSym->elementTypeDesc.isClassType) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "Cannot use member access on non-UDT array '" + stmt.variable + "'",
                      stmt.location);
                return;
            }
            
            baseTypeName = arrSym->asTypeName;
            if (baseTypeName.empty() && arrSym->elementTypeDesc.isClassType) {
                baseTypeName = arrSym->elementTypeDesc.className;
            }
        } else {
            // Simple variable with member access: Player.X = 42
            auto* varSym = lookupVariable(stmt.variable);
            if (!varSym) {
                error(SemanticErrorType::UNDEFINED_VARIABLE,
                      "Variable '" + stmt.variable + "' not declared",
                      stmt.location);
                return;
            }
            
            if (varSym->typeDesc.baseType != BaseType::USER_DEFINED &&
                varSym->typeDesc.baseType != BaseType::CLASS_INSTANCE &&
                !varSym->typeDesc.isClassType) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "Cannot use member access on non-UDT variable '" + stmt.variable + "'",
                      stmt.location);
                return;
            }
            
            baseTypeName = varSym->typeName;
            // Fall back to typeDesc.udtName if typeName is empty (e.g., for LOCAL or parameter UDT vars)
            if (baseTypeName.empty()) {
                baseTypeName = varSym->typeDesc.udtName;
            }
            // Fall back to className for CLASS instance variables
            if (baseTypeName.empty() && varSym->typeDesc.isClassType) {
                baseTypeName = varSym->typeDesc.className;
            }
        }
        
        // Look up the UDT type — check CLASS first, then TYPE
        const ClassSymbol* classSym = m_symbolTable.lookupClass(baseTypeName);
        if (classSym) {
            // CLASS member access — validate the field chain
            const ClassSymbol* currentClass = classSym;
            for (size_t i = 0; i < stmt.memberChain.size(); i++) {
                const std::string& memberName = stmt.memberChain[i];
                const ClassSymbol::FieldInfo* fieldInfo = currentClass->findField(memberName);
                if (!fieldInfo) {
                    error(SemanticErrorType::UNDEFINED_FIELD,
                          "CLASS '" + currentClass->name + "' has no field '" + memberName + "'",
                          stmt.location);
                    return;
                }
                // If this is not the last member in the chain, resolve the next type
                if (i + 1 < stmt.memberChain.size()) {
                    if (fieldInfo->typeDesc.isClassType) {
                        currentClass = m_symbolTable.lookupClass(fieldInfo->typeDesc.className);
                        if (!currentClass) {
                            error(SemanticErrorType::UNDEFINED_CLASS,
                                  "CLASS '" + fieldInfo->typeDesc.className + "' is not defined",
                                  stmt.location);
                            return;
                        }
                    } else if (fieldInfo->typeDesc.baseType == BaseType::USER_DEFINED) {
                        // Switch to TYPE-based member access for remaining chain
                        break;
                    } else {
                        error(SemanticErrorType::TYPE_MISMATCH,
                              "Field '" + memberName + "' is not a class or type — cannot access members",
                              stmt.location);
                        return;
                    }
                }
            }
            // Validate the assigned expression
            if (stmt.value) {
                validateExpression(*stmt.value);
            }
            return;
        }

        TypeSymbol* typeSymbol = lookupType(baseTypeName);
        if (!typeSymbol) {
            error(SemanticErrorType::UNDEFINED_TYPE,
                  "Type '" + baseTypeName + "' not defined",
                  stmt.location);
            return;
        }
        
        // Navigate through the member chain
        TypeSymbol* currentType = typeSymbol;
        for (size_t i = 0; i < stmt.memberChain.size(); ++i) {
            const std::string& memberName = stmt.memberChain[i];
            const TypeSymbol::Field* field = currentType->findField(memberName);
            
            if (!field) {
                error(SemanticErrorType::UNDEFINED_FIELD,
                      "Field '" + memberName + "' not found in type '" + currentType->name + "'",
                      stmt.location);
                return;
            }
            
            // If this is the last member, get its type
            if (i == stmt.memberChain.size() - 1) {
                targetType = field->isBuiltIn ? field->builtInType : VariableType::USER_DEFINED;
            } else {
                // This is a nested member, must be a UDT
                if (!field->isBuiltIn) {
                    currentType = lookupType(field->typeName);
                    if (!currentType) {
                        error(SemanticErrorType::UNDEFINED_TYPE,
                              "Type '" + field->typeName + "' not defined",
                              stmt.location);
                        return;
                    }
                } else {
                    error(SemanticErrorType::TYPE_MISMATCH,
                          "Cannot access member '" + stmt.memberChain[i+1] + "' of non-UDT field '" + memberName + "'",
                          stmt.location);
                    return;
                }
            }
        }
    } else if (!stmt.indices.empty()) {
        auto* arraySym = lookupArray(stmt.variable);
        targetType = arraySym ? descriptorToLegacyType(arraySym->elementTypeDesc) : VariableType::UNKNOWN;
    } else {
        auto* varSym = lookupVariable(stmt.variable);
        targetType = varSym ? descriptorToLegacyType(varSym->typeDesc) : VariableType::UNKNOWN;
    }
    
    VariableType valueType = inferExpressionType(*stmt.value);
    checkTypeCompatibility(targetType, valueType, stmt.location, "assignment");
}

void SemanticAnalyzer::validateGotoStatement(const GotoStatement& stmt) {
    if (stmt.isLabel) {
        // Symbolic label - resolve it
        auto* labelSym = lookupLabel(stmt.label);
        if (!labelSym) {
            error(SemanticErrorType::UNDEFINED_LABEL,
                  "GOTO target label :" + stmt.label + " does not exist",
                  stmt.location);
        } else {
            labelSym->references.push_back(stmt.location);
        }
    } else {
        // Line number
        auto* lineSym = lookupLine(stmt.lineNumber);
        if (!lineSym) {
            error(SemanticErrorType::UNDEFINED_LINE,
                  "GOTO target line " + std::to_string(stmt.lineNumber) + " does not exist",
                  stmt.location);
        } else {
            lineSym->references.push_back(stmt.location);
        }
    }
}

void SemanticAnalyzer::validateGosubStatement(const GosubStatement& stmt) {
    if (stmt.isLabel) {
        // Symbolic label - resolve it
        auto* labelSym = lookupLabel(stmt.label);
        if (!labelSym) {
            error(SemanticErrorType::UNDEFINED_LABEL,
                  "GOSUB target label :" + stmt.label + " does not exist",
                  stmt.location);
        } else {
            labelSym->references.push_back(stmt.location);
        }
    } else {
        // Line number
        auto* lineSym = lookupLine(stmt.lineNumber);
        if (!lineSym) {
            error(SemanticErrorType::UNDEFINED_LINE,
                  "GOSUB target line " + std::to_string(stmt.lineNumber) + " does not exist",
                  stmt.location);
        } else {
            lineSym->references.push_back(stmt.location);
        }
    }
}

void SemanticAnalyzer::validateOnGotoStatement(const OnGotoStatement& stmt) {
    // Validate the selector expression
    validateExpression(*stmt.selector);
    
    // Validate all targets
    for (size_t i = 0; i < stmt.isLabelList.size(); ++i) {
        if (stmt.isLabelList[i]) {
            // Symbolic label - resolve it
            auto* labelSym = lookupLabel(stmt.labels[i]);
            if (!labelSym) {
                error(SemanticErrorType::UNDEFINED_LABEL,
                      "ON GOTO target label :" + stmt.labels[i] + " does not exist",
                      stmt.location);
            } else {
                labelSym->references.push_back(stmt.location);
            }
        } else {
            // Line number
            auto* lineSym = lookupLine(stmt.lineNumbers[i]);
            if (!lineSym) {
                error(SemanticErrorType::UNDEFINED_LINE,
                      "ON GOTO target line " + std::to_string(stmt.lineNumbers[i]) + " does not exist",
                      stmt.location);
            } else {
                lineSym->references.push_back(stmt.location);
            }
        }
    }
}

void SemanticAnalyzer::validateOnGosubStatement(const OnGosubStatement& stmt) {
    // Validate the selector expression
    validateExpression(*stmt.selector);
    
    // Validate all targets
    for (size_t i = 0; i < stmt.isLabelList.size(); ++i) {
        if (stmt.isLabelList[i]) {
            // Symbolic label - resolve it
            auto* labelSym = lookupLabel(stmt.labels[i]);
            if (!labelSym) {
                error(SemanticErrorType::UNDEFINED_LABEL,
                      "ON GOSUB target label :" + stmt.labels[i] + " does not exist",
                      stmt.location);
            } else {
                labelSym->references.push_back(stmt.location);
            }
        } else {
            // Line number
            auto* lineSym = lookupLine(stmt.lineNumbers[i]);
            if (!lineSym) {
                error(SemanticErrorType::UNDEFINED_LINE,
                      "ON GOSUB target line " + std::to_string(stmt.lineNumbers[i]) + " does not exist",
                      stmt.location);
            } else {
                lineSym->references.push_back(stmt.location);
            }
        }
    }
}

void SemanticAnalyzer::validateIfStatement(const IfStatement& stmt) {
    validateExpression(*stmt.condition);
    
    if (stmt.hasGoto) {
        auto* lineSym = lookupLine(stmt.gotoLine);
        if (!lineSym) {
            error(SemanticErrorType::UNDEFINED_LINE,
                  "IF THEN target line " + std::to_string(stmt.gotoLine) + " does not exist",
                  stmt.location);
        } else {
            lineSym->references.push_back(stmt.location);
        }
    } else {
        for (const auto& thenStmt : stmt.thenStatements) {
            validateStatement(*thenStmt);
        }
    }
    
    for (const auto& elseStmt : stmt.elseStatements) {
        validateStatement(*elseStmt);
    }
}

void SemanticAnalyzer::validateForStatement(const ForStatement& stmt) {
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] validateForStatement called for variable: " << stmt.variable << std::endl;
    }
    // FOR loop variables ignore type suffixes completely
    // The parser has already stripped suffixes from stmt.variable
    // Type is determined by OPTION FOR setting, not by suffix
    std::string plainVarName = stmt.variable;
    
    // Determine type based on OPTION FOR setting
    BaseType forVarType = (m_options.forLoopType == CompilerOptions::ForLoopType::LONG)
                          ? BaseType::LONG : BaseType::INTEGER;
    
    // Create normalized variable name with correct integer suffix
    TypeDescriptor forTypeDesc(forVarType);
    std::string normalizedVarName = normalizeVariableName(plainVarName, forTypeDesc);
    
    // Register the variable in symbol table with normalized name and explicit scope
    Scope currentScope = getCurrentScope();
    VariableSymbol varSym(normalizedVarName, forTypeDesc, currentScope, true);
    varSym.firstUse = stmt.location;
    m_symbolTable.insertVariable(normalizedVarName, varSym);
    
    // Add normalized name to function's local variables set so validateVariableInFunction accepts it
    if (m_currentFunctionScope.inFunction) {
        m_currentFunctionScope.localVariables.insert(normalizedVarName);
    }
    
    // Validate expressions
    validateExpression(*stmt.start);
    validateExpression(*stmt.end);
    if (stmt.step) {
        validateExpression(*stmt.step);
    }
    
    // Type check
    VariableType startType = inferExpressionType(*stmt.start);
    VariableType endType = inferExpressionType(*stmt.end);
    
    if (!isNumericType(startType) || !isNumericType(endType)) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "FOR loop bounds must be numeric",
              stmt.location);
    }
    
    // Push to control flow stack before validating body (for nested loop checking)
    ForContext ctx;
    ctx.variable = plainVarName;
    ctx.location = stmt.location;
    m_forStack.push(ctx);
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] FOR stack PUSH at " << stmt.location.toString() << ", stack size now: " << m_forStack.size() << std::endl;
    }
    
    // Validate body statements
    for (const auto& bodyStmt : stmt.body) {
        validateStatement(*bodyStmt);
    }
    
    // Pop stack since NEXT is now consumed by parser and body is self-contained
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] FOR stack POP after body, stack size before pop: " << m_forStack.size() << std::endl;
    }
    m_forStack.pop();
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] FOR stack size after pop: " << m_forStack.size() << std::endl;
    }
}

void SemanticAnalyzer::validateForInStatement(ForInStatement& stmt) {
    // Validate the array expression
    validateExpression(*stmt.array);
    
    // Infer and store the element type in the AST node (cast to int for storage)
    stmt.inferredType = static_cast<int>(inferExpressionType(*stmt.array));
    
    // Note: We do NOT add the FOR EACH variable to the symbol table
    // It will be declared directly in codegen with the correct type
    
    // Push to control flow stack before validating body (for nested loop checking)
    ForContext ctx;
    ctx.variable = stmt.variable;
    ctx.location = stmt.location;
    m_forStack.push(ctx);
    
    // Validate body statements
    for (const auto& bodyStmt : stmt.body) {
        validateStatement(*bodyStmt);
    }
    
    // Pop stack since NEXT is now consumed by parser and body is self-contained
    m_forStack.pop();
}

void SemanticAnalyzer::validateNextStatement(const NextStatement& stmt) {
    if (m_forStack.empty()) {
        error(SemanticErrorType::NEXT_WITHOUT_FOR,
              "NEXT without matching FOR",
              stmt.location);
    } else {
        const auto& forCtx = m_forStack.top();
        
        // Check variable match if specified
        if (!stmt.variable.empty() && stmt.variable != forCtx.variable) {
            error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                  "NEXT variable '" + stmt.variable + "' does not match FOR variable '" + 
                  forCtx.variable + "'",
                  stmt.location);
        }
        
        m_forStack.pop();
    }
}

void SemanticAnalyzer::validateWhileStatement(const WhileStatement& stmt) {
    validateExpression(*stmt.condition);
    
    // Push to stack before validating body (for nested loop checking)
    m_whileStack.push(stmt.location);
    
    // Validate body statements
    for (const auto& bodyStmt : stmt.body) {
        validateStatement(*bodyStmt);
    }
    
    // Pop stack since WEND is now consumed by parser and body is self-contained
    m_whileStack.pop();
}

void SemanticAnalyzer::validateWendStatement(const WendStatement& stmt) {
    if (m_whileStack.empty()) {
        error(SemanticErrorType::WEND_WITHOUT_WHILE,
              "WEND without matching WHILE",
              stmt.location);
    } else {
        m_whileStack.pop();
    }
}

void SemanticAnalyzer::validateRepeatStatement(const RepeatStatement& stmt) {
    // Validate body statements
    for (const auto& bodyStmt : stmt.body) {
        validateStatement(*bodyStmt);
    }
    
    // Validate UNTIL condition
    if (stmt.condition) {
        validateExpression(*stmt.condition);
    }
    
    // NOTE: With new AST structure, REPEAT contains its body and UNTIL condition
    // No need to push/pop stack - the parser already handles loop structure
    // m_repeatStack.push(stmt.location);
}

void SemanticAnalyzer::validateUntilStatement(const UntilStatement& stmt) {
    // NOTE: With new AST structure, UNTIL should not appear as a separate statement
    // The parser collects REPEAT bodies and includes UNTIL condition in RepeatStatement
    // This case should only occur with old-style marker UNTIL statements (if any remain)
    if (m_repeatStack.empty()) {
        error(SemanticErrorType::UNTIL_WITHOUT_REPEAT,
              "UNTIL without matching REPEAT",
              stmt.location);
    } else {
        m_repeatStack.pop();
    }
    
    validateExpression(*stmt.condition);
}

void SemanticAnalyzer::validateDoStatement(const DoStatement& stmt) {
    // Validate pre-condition if present (DO WHILE or DO UNTIL)
    if (stmt.preCondition) {
        validateExpression(*stmt.preCondition);
    }
    
    // Validate post-condition if present (LOOP WHILE or LOOP UNTIL)
    if (stmt.postCondition) {
        validateExpression(*stmt.postCondition);
    }
    
    // Push to control flow stack before validating body (for nested loop checking)
    m_doStack.push(stmt.location);
    
    // Validate body statements
    for (const auto& bodyStmt : stmt.body) {
        validateStatement(*bodyStmt);
    }
    
    // Pop stack since LOOP is now consumed by parser and body is self-contained
    m_doStack.pop();
}

void SemanticAnalyzer::validateLoopStatement(const LoopStatement& stmt) {
    if (m_doStack.empty()) {
        error(SemanticErrorType::LOOP_WITHOUT_DO,
              "LOOP without matching DO",
              stmt.location);
    } else {
        m_doStack.pop();
    }
    
    // Validate condition if present (LOOP WHILE or LOOP UNTIL)
    if (stmt.condition) {
        validateExpression(*stmt.condition);
    }
}

void SemanticAnalyzer::validateReadStatement(const ReadStatement& stmt) {
    for (const auto& varName : stmt.variables) {
        useVariable(varName, stmt.location);
    }
}

void SemanticAnalyzer::validateRestoreStatement(const RestoreStatement& stmt) {
    // RESTORE targets can be:
    // 1. Regular labels/lines in the program (checked here)
    // 2. DATA labels/lines (handled by DataManager at runtime)
    // So we don't error if not found - just record the reference if it exists
    
    if (stmt.isLabel) {
        // Symbolic label - try to resolve it
        auto* labelSym = lookupLabel(stmt.label);
        if (labelSym) {
            // Found in symbol table - record reference
            labelSym->references.push_back(stmt.location);
        }
        // If not found, assume it's a DATA label - will be resolved at runtime
    } else if (stmt.lineNumber > 0) {
        auto* lineSym = lookupLine(stmt.lineNumber);
        // If not found, assume it's a DATA line - will be resolved at runtime
        // No error needed - DataManager will handle it
    }
}

void SemanticAnalyzer::validateExpressionStatement(const ExpressionStatement& stmt) {
    for (const auto& arg : stmt.arguments) {
        validateExpression(*arg);
    }
}

void SemanticAnalyzer::validateOnEventStatement(const OnEventStatement& stmt) {
    // ONEVENT is deprecated - use AFTER/EVERY instead
    // This function is kept for backwards compatibility but does nothing
    (void)stmt; // Suppress unused parameter warning
}

// =============================================================================
// Timer Event Statement Validation
// =============================================================================

void SemanticAnalyzer::validateAfterStatement(const AfterStatement& stmt) {
    // Validate duration expression
    if (stmt.duration) {
        validateExpression(*stmt.duration);
        VariableType durationType = inferExpressionType(*stmt.duration);
        
        if (!isNumericType(durationType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "AFTER duration must be numeric (milliseconds)",
                  stmt.location);
        }
        
        // Try to evaluate as constant and check if positive
        try {
            auto constVal = evaluateConstantExpression(*stmt.duration);
            double duration = 0.0;
            
            if (std::holds_alternative<int64_t>(constVal)) {
                duration = static_cast<double>(std::get<int64_t>(constVal));
            } else if (std::holds_alternative<double>(constVal)) {
                duration = std::get<double>(constVal);
            }
            
            if (duration < 0.0) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "AFTER duration must be non-negative",
                      stmt.location);
            }
        } catch (...) {
            // Not a constant expression - will be checked at runtime
        }
    }
    
    // Validate handler exists and is a SUB/FUNCTION
    if (!stmt.handlerName.empty()) {
        // If this is an inline handler (using DO...DONE syntax), register it as a function
        if (stmt.isInlineHandler) {
            // Create a function symbol for the inline handler
            FunctionSymbol funcSym;
            funcSym.name = stmt.handlerName;
            funcSym.returnTypeDesc = TypeDescriptor(BaseType::VOID);  // SUBs have no return type
            funcSym.definition = stmt.location;
            m_symbolTable.functions[stmt.handlerName] = funcSym;
            
            // Validate the inline body statements
            for (const auto& bodyStmt : stmt.inlineBody) {
                validateStatement(*bodyStmt);
            }
        } else {
            // External handler - must exist
            auto* funcSym = lookupFunction(stmt.handlerName);
            if (!funcSym) {
                error(SemanticErrorType::UNDEFINED_FUNCTION,
                      "AFTER handler '" + stmt.handlerName + "' is not defined. Handlers must be SUB or FUNCTION declarations.",
                      stmt.location);
            } else {
                // Handler should have zero parameters
                // Warn if handler has parameters
                if (!funcSym->parameters.empty()) {
                    warning("Timer handler '" + stmt.handlerName + "' has parameters but will be called with no arguments",
                           stmt.location);
                }
            }
        }
    }
}

void SemanticAnalyzer::validateEveryStatement(const EveryStatement& stmt) {
    // Validate duration expression
    if (stmt.duration) {
        validateExpression(*stmt.duration);
        VariableType durationType = inferExpressionType(*stmt.duration);
        
        if (!isNumericType(durationType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "EVERY interval must be numeric (milliseconds)",
                  stmt.location);
        }
    }
    
    // Validate handler exists
    if (!stmt.handlerName.empty()) {
        // If this is an inline handler (using DO...DONE syntax), register it as a function
        if (stmt.isInlineHandler) {
            // Create a function symbol for the inline handler
            FunctionSymbol funcSym;
            funcSym.name = stmt.handlerName;
            funcSym.returnTypeDesc = TypeDescriptor(BaseType::VOID);  // SUBs have no return type
            funcSym.definition = stmt.location;
            m_symbolTable.functions[stmt.handlerName] = funcSym;
            
            // Validate the inline body statements
            for (const auto& bodyStmt : stmt.inlineBody) {
                validateStatement(*bodyStmt);
            }
        } else {
            // External handler - must exist
            auto* funcSym = lookupFunction(stmt.handlerName);
            if (!funcSym) {
                error(SemanticErrorType::UNDEFINED_FUNCTION,
                      "EVERY handler '" + stmt.handlerName + "' is not defined. Handlers must be SUB or FUNCTION declarations.",
                      stmt.location);
            } else {
                // Handler should have zero parameters
                // Warn if handler has parameters
                if (!funcSym->parameters.empty()) {
                    warning("Timer handler '" + stmt.handlerName + "' has parameters but will be called with no arguments",
                           stmt.location);
                }
            }
        }
    }
}

void SemanticAnalyzer::validateAfterFramesStatement(const AfterFramesStatement& stmt) {
    // Validate frame count expression
    if (stmt.frameCount) {
        validateExpression(*stmt.frameCount);
        VariableType frameCountType = inferExpressionType(*stmt.frameCount);
        
        if (!isNumericType(frameCountType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "AFTERFRAMES count must be numeric (frames)",
                  stmt.location);
        }
    }
    
    // Validate handler exists
    if (!stmt.handlerName.empty()) {
        auto* funcSym = lookupFunction(stmt.handlerName);
        if (!funcSym) {
            error(SemanticErrorType::UNDEFINED_FUNCTION,
                  "AFTERFRAMES handler '" + stmt.handlerName + "' is not defined. Handlers must be SUB or FUNCTION declarations.",
                  stmt.location);
        } else {
            // Handler should have zero parameters
            // Warn if handler has parameters
            if (!funcSym->parameters.empty()) {
                warning("Timer handler '" + stmt.handlerName + "' has parameters but will be called with no arguments",
                       stmt.location);
            }
        }
    }
}

void SemanticAnalyzer::validateEveryFrameStatement(const EveryFrameStatement& stmt) {
    // Validate frame count expression
    if (stmt.frameCount) {
        validateExpression(*stmt.frameCount);
        VariableType frameCountType = inferExpressionType(*stmt.frameCount);
        
        if (!isNumericType(frameCountType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "EVERYFRAME count must be numeric (frames)",
                  stmt.location);
        }
    }
    
    // Validate handler exists
    if (!stmt.handlerName.empty()) {
        auto* funcSym = lookupFunction(stmt.handlerName);
        if (!funcSym) {
            error(SemanticErrorType::UNDEFINED_FUNCTION,
                  "EVERYFRAME handler '" + stmt.handlerName + "' is not defined. Handlers must be SUB or FUNCTION declarations.",
                  stmt.location);
        } else {
            // Handler should have zero parameters
            // Warn if handler has parameters
            if (!funcSym->parameters.empty()) {
                warning("Timer handler '" + stmt.handlerName + "' has parameters but will be called with no arguments",
                       stmt.location);
            }
        }
    }
}

void SemanticAnalyzer::validateRunStatement(const RunStatement& stmt) {
    // Validate UNTIL condition if present
    if (stmt.untilCondition) {
        validateExpression(*stmt.untilCondition);
        // Condition should be boolean/numeric (any type that can be evaluated as true/false)
        // No strict type checking needed - BASIC allows any type in conditions
    }
}

void SemanticAnalyzer::validateTimerStopStatement(const TimerStopStatement& stmt) {
    // Validate based on stop target type
    switch (stmt.targetType) {
        case TimerStopStatement::StopTarget::TIMER_ID:
            // Validate timer ID expression if present
            if (stmt.timerId) {
                validateExpression(*stmt.timerId);
                VariableType idType = inferExpressionType(*stmt.timerId);
                if (!isNumericType(idType)) {
                    error(SemanticErrorType::TYPE_MISMATCH,
                          "TIMER STOP timer ID must be numeric",
                          stmt.location);
                }
            }
            break;
            
        case TimerStopStatement::StopTarget::HANDLER:
            // Validate handler name exists
            if (!stmt.handlerName.empty()) {
                auto* funcSym = lookupFunction(stmt.handlerName);
                if (!funcSym) {
                    error(SemanticErrorType::UNDEFINED_FUNCTION,
                          "TIMER STOP handler '" + stmt.handlerName + "' is not defined",
                          stmt.location);
                }
            }
            break;
            
        case TimerStopStatement::StopTarget::ALL:
            // No validation needed for STOP ALL
            break;
    }
}

void SemanticAnalyzer::validateTimerIntervalStatement(const TimerIntervalStatement& stmt) {
    // Validate interval expression
    if (stmt.interval) {
        validateExpression(*stmt.interval);
        VariableType intervalType = inferExpressionType(*stmt.interval);
        
        if (!isNumericType(intervalType)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "TIMER INTERVAL must be numeric (instruction count)",
                  stmt.location);
        }
        
        // Try to evaluate as constant and check if positive
        try {
            auto constVal = evaluateConstantExpression(*stmt.interval);
            int64_t interval = 0;
            
            if (std::holds_alternative<int64_t>(constVal)) {
                interval = std::get<int64_t>(constVal);
            } else if (std::holds_alternative<double>(constVal)) {
                interval = static_cast<int64_t>(std::get<double>(constVal));
            }
            
            if (interval <= 0) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "TIMER INTERVAL must be positive",
                      stmt.location);
            }
            
            if (interval > 1000000) {
                warning("TIMER INTERVAL of " + std::to_string(interval) + 
                       " is very high - may reduce timer responsiveness significantly",
                       stmt.location);
            } else if (interval < 100) {
                warning("TIMER INTERVAL of " + std::to_string(interval) + 
                       " is very low - may increase CPU usage significantly",
                       stmt.location);
            }
        } catch (...) {
            // Not a constant expression - will be checked at runtime
        }
    }
}

// =============================================================================
// Expression Validation and Type Inference
// =============================================================================

void SemanticAnalyzer::analyzeArrayExpression(const Expression* expr, TypeDeclarationStatement::SIMDType targetSIMDType) {
    if (!expr) return;
    
    // For now, just detect simple array copy: A() = B()
    if (expr->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        auto* arrayAccess = static_cast<const ArrayAccessExpression*>(expr);
        if (arrayAccess->indices.empty()) {
            std::cout << "[SIMD] Detected whole-array copy: <target>() = " 
                      << arrayAccess->name << "()" << std::endl;
            
            // Check if source array is also SIMD-capable
            auto* arraySym = lookupArray(arrayAccess->name);
            if (arraySym && !arraySym->asTypeName.empty()) {
                auto* typeSym = lookupType(arraySym->asTypeName);
                if (typeSym && typeSym->simdType == targetSIMDType) {
                    std::cout << "[SIMD] Source and target are compatible SIMD types - can optimize!" << std::endl;
                }
            }
        }
    }
    
    // TODO: Detect binary operations on arrays (A() + B(), etc.)
    // This will require understanding how expressions are represented in the AST
}

void SemanticAnalyzer::validateExpression(const Expression& expr) {
    // This also performs type inference as a side effect
    inferExpressionType(expr);
}

void SemanticAnalyzer::validateReturnStatement(const ReturnStatement& stmt) {
    // RETURN can be used in two contexts:
    // 1. GOSUB/RETURN at program level (no return value)
    // 2. Inside FUNCTION/SUB (with or without value depending on type)
    
    // If we're not in a function/sub, this is a GOSUB RETURN
    if (!m_currentFunctionScope.inFunction) {
        // GOSUB RETURN must not have a return value
        if (stmt.returnValue) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "RETURN from GOSUB cannot return a value",
                  stmt.location);
        }
        // Otherwise, this is a valid GOSUB RETURN
        return;
    }
    
    // We're inside a FUNCTION or SUB
    if (m_currentFunctionScope.isSub) {
        // In a SUB - should not have a return value
        if (stmt.returnValue) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "SUB " + m_currentFunctionScope.functionName + " cannot return a value",
                  stmt.location);
        }
    } else {
        // In a FUNCTION - must have a return value
        if (!stmt.returnValue) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "FUNCTION " + m_currentFunctionScope.functionName + " must return a value",
                  stmt.location);
            return;
        }
        
        // Validate return value expression
        validateExpression(*stmt.returnValue);
        
        // Check return type compatibility
        VariableType returnType = inferExpressionType(*stmt.returnValue);
        VariableType expectedType = descriptorToLegacyType(m_currentFunctionScope.expectedReturnType);
        std::string expectedTypeName = m_currentFunctionScope.expectedReturnTypeName;
        
        // Skip validation if expected type is unknown
        if (expectedType == VariableType::UNKNOWN && expectedTypeName.empty()) {
            return;
        }
        
        // For user-defined return types
        if (!expectedTypeName.empty()) {
            // Returning a user-defined type
            // We need to check if the return expression is of the right user-defined type
            // For now, just ensure it's not a primitive type
            if (isNumericType(returnType) || returnType == VariableType::STRING) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "FUNCTION " + m_currentFunctionScope.functionName + 
                      " expects return type " + expectedTypeName + ", got " + typeToString(returnType),
                      stmt.location);
            }
        } else {
            // Built-in return type - check compatibility
            bool compatible = false;
            
            if (isNumericType(expectedType) && isNumericType(returnType)) {
                compatible = true;  // Allow numeric conversions
            } else if (expectedType == returnType) {
                compatible = true;  // Exact match
            } else if (expectedType == VariableType::STRING && 
                      (returnType == VariableType::STRING || returnType == VariableType::UNICODE)) {
                compatible = true;  // String types are compatible
            } else if (expectedType == VariableType::UNICODE && 
                      (returnType == VariableType::STRING || returnType == VariableType::UNICODE)) {
                compatible = true;
            }
            
            if (!compatible) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "FUNCTION " + m_currentFunctionScope.functionName + 
                      " expects return type " + typeToString(expectedType) + 
                      ", got " + typeToString(returnType),
                      stmt.location);
            }
        }
    }
}

void SemanticAnalyzer::validateTryCatchStatement(const TryCatchStatement& stmt) {
    // Validate TRY/CATCH/FINALLY structure
    
    // Rule 1: Must have at least one CATCH clause or a FINALLY block
    if (stmt.catchClauses.empty() && !stmt.hasFinally) {
        error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
              "TRY statement must have at least one CATCH clause or a FINALLY block",
              stmt.location);
        return;
    }
    
    // Rule 2: Validate each CATCH clause
    bool hasCatchAll = false;
    for (size_t i = 0; i < stmt.catchClauses.size(); i++) {
        const auto& clause = stmt.catchClauses[i];
        
        // Check for catch-all (empty error codes)
        if (clause.errorCodes.empty()) {
            hasCatchAll = true;
            
            // Catch-all must be the last CATCH clause
            if (i != stmt.catchClauses.size() - 1) {
                error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                      "Catch-all CATCH clause (with no error codes) must be the last CATCH clause",
                      stmt.location);
            }
        }
        
        // Validate error codes are positive integers
        for (int32_t code : clause.errorCodes) {
            if (code <= 0) {
                error(SemanticErrorType::TYPE_MISMATCH,
                      "Error code must be a positive integer, got " + std::to_string(code),
                      stmt.location);
            }
        }
        
        // Check for duplicate error codes within this CATCH
        std::set<int32_t> seenCodes;
        for (int32_t code : clause.errorCodes) {
            if (seenCodes.count(code)) {
                error(SemanticErrorType::CONTROL_FLOW_MISMATCH,
                      "Duplicate error code " + std::to_string(code) + " in CATCH clause",
                      stmt.location);
            }
            seenCodes.insert(code);
        }
        
        // Validate statements in CATCH block
        for (const auto& catchStmt : clause.block) {
            validateStatement(*catchStmt);
        }
    }
    
    // Rule 3: Validate TRY block statements
    for (const auto& tryStmt : stmt.tryBlock) {
        validateStatement(*tryStmt);
    }
    
    // Rule 4: Validate FINALLY block statements (if present)
    if (stmt.hasFinally) {
        for (const auto& finallyStmt : stmt.finallyBlock) {
            validateStatement(*finallyStmt);
        }
    }
}

void SemanticAnalyzer::validateThrowStatement(const ThrowStatement& stmt) {
    // THROW must have an error code expression
    if (!stmt.errorCode) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "THROW statement requires an error code expression",
              stmt.location);
        return;
    }
    
    // Validate the error code expression
    validateExpression(*stmt.errorCode);
    
    // Infer the type of the error code expression
    VariableType codeType = inferExpressionType(*stmt.errorCode);
    
    // Error code must be numeric (will be converted to integer at runtime)
    if (!isNumericType(codeType)) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "THROW error code must be numeric, got " + std::string(typeToString(codeType)),
              stmt.location);
    }
    
    // Warning: If the error code is a constant, validate it's positive
    if (isConstantExpression(*stmt.errorCode)) {
        auto constVal = evaluateConstantExpression(*stmt.errorCode);
        if (isConstantNumeric(constVal)) {
            int64_t code = getConstantAsInt(constVal);
            if (code <= 0) {
                warning("THROW error code should be positive, got " + std::to_string(code),
                       stmt.location);
            }
        }
    }
}

VariableType SemanticAnalyzer::inferExpressionType(const Expression& expr) {
    switch (expr.getType()) {
        case ASTNodeType::EXPR_NUMBER:
            return VariableType::FLOAT;
        
        case ASTNodeType::EXPR_STRING:
            // Return UNICODE type if in Unicode mode
            // For variable member access, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        
        case ASTNodeType::EXPR_VARIABLE:
            return inferVariableType(static_cast<const VariableExpression&>(expr));
        
        case ASTNodeType::EXPR_ARRAY_ACCESS:
            return inferArrayAccessType(static_cast<const ArrayAccessExpression&>(expr));
        
        case ASTNodeType::EXPR_FUNCTION_CALL:
            // Check if this is actually a RegistryFunctionExpression
            if (auto* regFunc = dynamic_cast<const RegistryFunctionExpression*>(&expr)) {
                return inferRegistryFunctionType(*regFunc);
            } else {
                return inferFunctionCallType(static_cast<const FunctionCallExpression&>(expr));
            }
        
        case ASTNodeType::EXPR_BINARY:
            return inferBinaryExpressionType(static_cast<const BinaryExpression&>(expr));
        
        case ASTNodeType::EXPR_UNARY:
            return inferUnaryExpressionType(static_cast<const UnaryExpression&>(expr));
        
        default:
            return VariableType::UNKNOWN;
    }
}

VariableType SemanticAnalyzer::inferMemberAccessType(const MemberAccessExpression& expr) {
    // Infer the type of a member access expression (e.g., point.X)
    
    // First, determine the type name of the base object
    std::string baseTypeName;
    
    // Check if the object is a variable
    if (expr.object->getType() == ASTNodeType::EXPR_VARIABLE) {
        const VariableExpression* varExpr = static_cast<const VariableExpression*>(expr.object.get());
        VariableSymbol* varSym = lookupVariable(varExpr->name);
        if (varSym && varSym->typeDesc.baseType == BaseType::USER_DEFINED) {
            // Get the UDT type name
            baseTypeName = varSym->typeName;
        } else {
            return VariableType::UNKNOWN;
        }
    } else if (expr.object->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        // Array element access
        const ArrayAccessExpression* arrayExpr = static_cast<const ArrayAccessExpression*>(expr.object.get());
        ArraySymbol* arraySym = lookupArray(arrayExpr->name);
        if (arraySym && arraySym->elementTypeDesc.baseType == BaseType::USER_DEFINED) {
            baseTypeName = arraySym->asTypeName;
        } else {
            return VariableType::UNKNOWN;
        }
    } else if (expr.object->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
        // Nested member access (e.g., a.b.c)
        // Recursively get the type of the nested member
        VariableType nestedType = inferMemberAccessType(*static_cast<const MemberAccessExpression*>(expr.object.get()));
        
        // If the nested member is a UDT, we need to resolve the actual field type
        // by traversing the member access chain from the root variable
        if (nestedType == VariableType::USER_DEFINED) {
            // Walk the nested member access chain to find the root variable and
            // collect intermediate member names
            std::vector<std::string> chainNames;
            const Expression* cur = expr.object.get();
            while (cur->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
                const auto* ma = static_cast<const MemberAccessExpression*>(cur);
                chainNames.push_back(ma->memberName);
                cur = ma->object.get();
            }
            std::reverse(chainNames.begin(), chainNames.end());

            // Determine root UDT type name
            std::string rootUDT;
            if (cur->getType() == ASTNodeType::EXPR_VARIABLE) {
                const auto* rootVar = static_cast<const VariableExpression*>(cur);
                VariableSymbol* rootSym = lookupVariable(rootVar->name);
                if (rootSym && rootSym->typeDesc.baseType == BaseType::USER_DEFINED) {
                    rootUDT = rootSym->typeName;
                }
            } else if (cur->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
                const auto* arrExpr = static_cast<const ArrayAccessExpression*>(cur);
                ArraySymbol* arrSym = lookupArray(arrExpr->name);
                if (arrSym && arrSym->elementTypeDesc.baseType == BaseType::USER_DEFINED) {
                    rootUDT = arrSym->asTypeName;
                }
            }

            if (!rootUDT.empty()) {
                // Traverse the chain to find the UDT type of the intermediate result
                std::string currentUDT = rootUDT;
                for (const auto& name : chainNames) {
                    TypeSymbol* ts = lookupType(currentUDT);
                    if (!ts) break;
                    const TypeSymbol::Field* fld = ts->findField(name);
                    if (!fld || fld->typeDesc.baseType != BaseType::USER_DEFINED) {
                        currentUDT.clear();
                        break;
                    }
                    currentUDT = fld->typeDesc.udtName;
                }
                if (!currentUDT.empty()) {
                    baseTypeName = currentUDT;
                    // Fall through to look up expr.memberName in baseTypeName below
                } else {
                    return nestedType;
                }
            } else {
                return nestedType;
            }
        } else {
            return nestedType;
        }
    } else {
        return VariableType::UNKNOWN;
    }
    
    // Look up the type definition
    if (baseTypeName.empty()) {
        return VariableType::UNKNOWN;
    }
    
    TypeSymbol* typeSymbol = lookupType(baseTypeName);
    if (!typeSymbol) {
        return VariableType::UNKNOWN;
    }
    
    // Find the field in the type
    const TypeSymbol::Field* field = typeSymbol->findField(expr.memberName);
    if (!field) {
        return VariableType::UNKNOWN;
    }
    
    // Return the field's type
    if (field->isBuiltIn) {
        return field->builtInType;
    } else {
        // Field is a nested UDT
        return VariableType::USER_DEFINED;
    }
}

VariableType SemanticAnalyzer::inferBinaryExpressionType(const BinaryExpression& expr) {
    VariableType leftType = inferExpressionType(*expr.left);
    VariableType rightType = inferExpressionType(*expr.right);
    
    // String concatenation
    if (leftType == VariableType::STRING || rightType == VariableType::STRING ||
        leftType == VariableType::UNICODE || rightType == VariableType::UNICODE) {
        if (expr.op == TokenType::PLUS) {
            // If either is UNICODE, result is UNICODE
            if (leftType == VariableType::UNICODE || rightType == VariableType::UNICODE) {
                return VariableType::UNICODE;
            }
            return VariableType::STRING;
        }
    }
    
    // Comparison operators return numeric
    if (expr.op >= TokenType::EQUAL && expr.op <= TokenType::GREATER_EQUAL) {
        return VariableType::FLOAT;
    }
    
    // Logical operators return numeric
    if (expr.op == TokenType::AND || expr.op == TokenType::OR) {
        return VariableType::FLOAT;
    }
    
    // Arithmetic operators
    return promoteTypes(leftType, rightType);
}

VariableType SemanticAnalyzer::inferUnaryExpressionType(const UnaryExpression& expr) {
    VariableType exprType = inferExpressionType(*expr.expr);
    
    if (expr.op == TokenType::NOT) {
        return VariableType::INT;  // NOT is bitwise, always returns integer
    }
    
    // Unary + or -
    return exprType;
}

VariableType SemanticAnalyzer::inferVariableType(const VariableExpression& expr) {
    // Check variable declaration in function context
    if (m_currentFunctionScope.inFunction) {
        validateVariableInFunction(expr.name, expr.location);
        
        // For LOCAL variables and parameters, look up actual type from symbol table first.
        // Fall back to name-based inference only if not found (shouldn't happen).
        if (m_currentFunctionScope.parameters.count(expr.name) ||
            m_currentFunctionScope.localVariables.count(expr.name)) {
            // Try to find the variable in the symbol table with proper scope
            const VariableSymbol* paramSym = lookupVariableScoped(expr.name, m_currentFunctionScope.functionName);
            if (paramSym) {
                return descriptorToLegacyType(paramSym->typeDesc);
            }
            // Try suffixed variants (DIM x AS INTEGER stores as x_INT)
            {
                static const char* suffixes[] = {"_INT", "_LONG", "_DOUBLE", "_FLOAT", "_STRING", "_BYTE", "_SHORT"};
                Scope funcScope = Scope::makeFunction(m_currentFunctionScope.functionName);
                for (const char* s : suffixes) {
                    const VariableSymbol* suffixed = m_symbolTable.lookupVariable(expr.name + s, funcScope);
                    if (suffixed) {
                        return descriptorToLegacyType(suffixed->typeDesc);
                    }
                }
            }
            // Fall back to name-based inference
            return inferTypeFromName(expr.name);
        }
        
        // For SHARED variables, look up in symbol table
        if (m_currentFunctionScope.sharedVariables.count(expr.name)) {
            auto* sym = lookupVariable(expr.name);
            if (sym) {
                return descriptorToLegacyType(sym->typeDesc);
            }
            return inferTypeFromName(expr.name);
        }
        
        // Function name (for return value assignment)
        if (expr.name == m_currentFunctionScope.functionName) {
            return inferTypeFromName(expr.name);
        }
    } else {
        useVariable(expr.name, expr.location);
        
        auto* sym = lookupVariable(expr.name);
        if (sym) {
            return descriptorToLegacyType(sym->typeDesc);
        }
    }
    
    return inferTypeFromName(expr.name);
}

VariableType SemanticAnalyzer::inferArrayAccessType(const ArrayAccessExpression& expr) {
    // Check if this is an object with subscript operator (like hashmap) FIRST
    // This must come before function/array checks to avoid treating objects as arrays
    auto* varSym = lookupVariable(expr.name);
    auto& registry = getRuntimeObjectRegistry();
    
    if (varSym && registry.isObjectType(varSym->typeDesc)) {
        auto* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
        if (objDesc && objDesc->hasSubscriptOperator) {
            // This is an object subscript access - validate that we have exactly one key
            if (expr.indices.size() != 1) {
                error(SemanticErrorType::INVALID_ARRAY_INDEX,
                      "Object subscript requires exactly one key, got " + 
                      std::to_string(expr.indices.size()),
                      expr.location);
            }
            
            // Validate the key expression
            if (!expr.indices.empty()) {
                validateExpression(*expr.indices[0]);
            }
            
            // Return the object's subscript return type
            return descriptorToLegacyType(objDesc->subscriptReturnType);
        }
    }
    
    // Mangle the name with its type suffix to match how functions are stored
    std::string mangledName = mangleNameWithSuffix(expr.name, expr.typeSuffix);
    
    // Check if this is a function/sub call (using mangled name)
    if (m_symbolTable.functions.find(mangledName) != m_symbolTable.functions.end()) {
        // It's a function or sub call - validate arguments but don't treat as array
        const auto& funcSym = m_symbolTable.functions.at(mangledName);
        for (const auto& arg : expr.indices) {
            validateExpression(*arg);
        }
        return descriptorToLegacyType(funcSym.returnTypeDesc);
    }
    
    // Check symbol table - if it's a declared array, treat as array access
    auto* arraySym = lookupArray(expr.name);
    if (arraySym) {
        // This is a declared array - validate as array access
        useArray(expr.name, expr.indices.size(), expr.location);
        
        // Validate indices
        for (const auto& index : expr.indices) {
            validateExpression(*index);
            VariableType indexType = inferExpressionType(*index);
            if (!isNumericType(indexType)) {
                error(SemanticErrorType::INVALID_ARRAY_INDEX,
                      "Array index must be numeric",
                      expr.location);
            }
        }
        
        return descriptorToLegacyType(arraySym->elementTypeDesc);
    }
    
    // Not a declared array - check if it's a built-in function call
    if (isBuiltinFunction(expr.name)) {
        // Validate argument count
        int expectedArgs = getBuiltinArgCount(expr.name);
        if (expectedArgs >= 0 && static_cast<int>(expr.indices.size()) != expectedArgs) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Built-in function " + expr.name + " expects " + 
                  std::to_string(expectedArgs) + " argument(s), got " + 
                  std::to_string(expr.indices.size()),
                  expr.location);
        }
        
        // Validate arguments
        for (const auto& index : expr.indices) {
            validateExpression(*index);
        }
        
        return getBuiltinReturnType(expr.name);
    }
    
    // Not an array and not a built-in function - treat as undeclared array
    // (useArray will create an implicit array symbol if needed)
    useArray(expr.name, expr.indices.size(), expr.location);
    
    // Validate indices for the implicit array
    for (const auto& index : expr.indices) {
        validateExpression(*index);
        VariableType indexType = inferExpressionType(*index);
        if (!isNumericType(indexType)) {
            error(SemanticErrorType::INVALID_ARRAY_INDEX,
                  "Array index must be numeric",
                  expr.location);
        }
    }
    
    // Return type for implicit array (lookup again after useArray)
    arraySym = lookupArray(expr.name);
    if (arraySym) {
        return descriptorToLegacyType(arraySym->elementTypeDesc);
    }
    return VariableType::UNKNOWN;
}

VariableType SemanticAnalyzer::inferFunctionCallType(const FunctionCallExpression& expr) {
    // Validate arguments
    for (const auto& arg : expr.arguments) {
        validateExpression(*arg);
    }
    
    if (expr.isFN) {
        // User-defined function (DEF FN or FUNCTION statement)
        auto* sym = lookupFunction(expr.name);
        if (sym) {
            // Validate parameter count
            if (expr.arguments.size() != sym->parameters.size()) {
                error(SemanticErrorType::ARGUMENT_COUNT_MISMATCH,
                      "Function " + expr.name + " expects " + std::to_string(sym->parameters.size()) +
                      " arguments, got " + std::to_string(expr.arguments.size()),
                      expr.location);
                return descriptorToLegacyType(sym->returnTypeDesc);
            }
            
            // Validate parameter types
            for (size_t i = 0; i < expr.arguments.size() && i < sym->parameterTypeDescs.size(); ++i) {
                VariableType argType = inferExpressionType(*expr.arguments[i]);
                const TypeDescriptor& paramTypeDesc = sym->parameterTypeDescs[i];
                VariableType paramType = descriptorToLegacyType(paramTypeDesc);
                std::string paramTypeName = paramTypeDesc.isUserDefined() ? paramTypeDesc.udtName : "";
                
                // Skip validation if parameter type is unknown (untyped parameter)
                if (paramType == VariableType::UNKNOWN && paramTypeName.empty()) {
                    continue;
                }
                
                // For user-defined types, check type compatibility
                if (!paramTypeName.empty()) {
                    // Parameter is a user-defined type
                    // Check if argument is also the same user-defined type
                    // For now, we need to track the type name of the argument expression
                    // This requires expression type tracking which we'll enhance
                    // For now, just ensure it's not a built-in numeric type when expecting user type
                    if (isNumericType(argType) || argType == VariableType::STRING) {
                        error(SemanticErrorType::TYPE_MISMATCH,
                              "Parameter " + std::to_string(i + 1) + " of function " + expr.name +
                              " expects user-defined type " + paramTypeName + ", got " + typeToString(argType),
                              expr.location);
                    }
                } else {
                    // Built-in type - check compatibility
                    // Allow implicit numeric conversions (INT -> FLOAT, etc.)
                    bool compatible = false;
                    if (isNumericType(paramType) && isNumericType(argType)) {
                        compatible = true;  // Allow numeric conversions
                    } else if (paramType == argType) {
                        compatible = true;  // Exact match
                    } else if (paramType == VariableType::STRING && 
                              (argType == VariableType::STRING || argType == VariableType::UNICODE)) {
                        compatible = true;  // String types are compatible
                    } else if (paramType == VariableType::UNICODE && 
                              (argType == VariableType::STRING || argType == VariableType::UNICODE)) {
                        compatible = true;
                    }
                    
                    if (!compatible) {
                        error(SemanticErrorType::TYPE_MISMATCH,
                              "Parameter " + std::to_string(i + 1) + " of function " + expr.name +
                              " expects " + typeToString(paramType) + ", got " + typeToString(argType),
                              expr.location);
                    }
                }
            }
            
            // Return the function's return type
            return descriptorToLegacyType(sym->returnTypeDesc);
        } else {
            error(SemanticErrorType::UNDEFINED_FUNCTION,
                  "Undefined function FN" + expr.name,
                  expr.location);
            return VariableType::UNKNOWN;
        }
    } else {
        // Built-in function - check for specific return types
        std::string upperName = expr.name;
        std::transform(upperName.begin(), upperName.end(), upperName.begin(), ::toupper);

        // Check for internal string slice function
        if (upperName == "__STRING_SLICE") {
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        }
        
        // Any built-in ending with $ or _STRING suffix returns a string/Unicode
        if (!upperName.empty() && upperName.back() == '$') {
            // For function calls, use global mode (string literal detection happens elsewhere)
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        }
        // Check for mangled string function names (e.g., STR_STRING, CHR_STRING)
        if (upperName.length() > 7 && upperName.substr(upperName.length() - 7) == "_STRING") {
            // For CHR$ and other string functions, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        }
        
        // Functions that return INT
        if (upperName == "FIX" || upperName == "CINT" || upperName == "INT" ||
            upperName == "SGN" || upperName == "ASC" || upperName == "INSTR" ||
            upperName == "LEN" || upperName == "STRTYPE") {
            return VariableType::INT;
        }
        
        // ABS returns the same type as its argument
        if (upperName == "ABS" && !expr.arguments.empty()) {
            return inferExpressionType(*expr.arguments[0]);
        }
        
        // MIN/MAX return the promoted type of their arguments
        if ((upperName == "MIN" || upperName == "MAX") && expr.arguments.size() >= 2) {
            VariableType leftType = inferExpressionType(*expr.arguments[0]);
            VariableType rightType = inferExpressionType(*expr.arguments[1]);
            return promoteTypes(leftType, rightType);
        }
        
        // Most other built-in functions return FLOAT
        return VariableType::FLOAT;
    }
}

VariableType SemanticAnalyzer::inferRegistryFunctionType(const RegistryFunctionExpression& expr) {
    // Validate arguments
    for (const auto& arg : expr.arguments) {
        validateExpression(*arg);
    }
    
    // Convert ModularCommands::ReturnType to VariableType
    switch (expr.returnType) {
        case FasterBASIC::ModularCommands::ReturnType::INT:
            return VariableType::INT;
        case FasterBASIC::ModularCommands::ReturnType::FLOAT:
            return VariableType::FLOAT;
        case FasterBASIC::ModularCommands::ReturnType::STRING:
            // For string concatenation, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        case FasterBASIC::ModularCommands::ReturnType::BOOL:
            return VariableType::INT; // BASIC treats booleans as integers
        case FasterBASIC::ModularCommands::ReturnType::VOID:
        default:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Registry function " + expr.name + " has invalid return type",
                  expr.location);
            return VariableType::UNKNOWN;
    }
}

// =============================================================================
// Type Checking
// =============================================================================

void SemanticAnalyzer::checkTypeCompatibility(VariableType expected, VariableType actual,
                                              const SourceLocation& loc, const std::string& context) {
    if (expected == VariableType::UNKNOWN || actual == VariableType::UNKNOWN) {
        return;  // Can't check
    }
    
    // String to numeric or vice versa is an error
    bool expectedString = (expected == VariableType::STRING || expected == VariableType::UNICODE);
    bool actualString = (actual == VariableType::STRING || actual == VariableType::UNICODE);
    
    if (expectedString != actualString) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "Type mismatch in " + context + ": cannot assign " +
              std::string(typeToString(actual)) + " to " + std::string(typeToString(expected)),
              loc);
    }
}

VariableType SemanticAnalyzer::promoteTypes(VariableType left, VariableType right) {
    // String/Unicode takes precedence
    if (left == VariableType::UNICODE || right == VariableType::UNICODE) {
        return VariableType::UNICODE;
    }
    if (left == VariableType::STRING || right == VariableType::STRING) {
        return VariableType::STRING;
    }
    
    // Numeric promotion
    if (left == VariableType::DOUBLE || right == VariableType::DOUBLE) {
        return VariableType::DOUBLE;
    }
    if (left == VariableType::FLOAT || right == VariableType::FLOAT) {
        return VariableType::FLOAT;
    }
    if (left == VariableType::INT || right == VariableType::INT) {
        return VariableType::INT;
    }
    
    return VariableType::FLOAT;
}

bool SemanticAnalyzer::isNumericType(VariableType type) {
    return type == VariableType::INT || 
           type == VariableType::FLOAT || 
           type == VariableType::DOUBLE;
}

// =============================================================================
// Symbol Table Management
// =============================================================================

VariableSymbol* SemanticAnalyzer::declareVariable(const std::string& name, VariableType type,
                                                  const SourceLocation& loc, bool isDeclared) {
    // Get current scope
    Scope currentScope = getCurrentScope();
    
    // Check if variable already exists in current scope
    VariableSymbol* existing = m_symbolTable.lookupVariable(name, currentScope);
    if (existing) {
        return existing;
    }
    
    // Create new variable with explicit scope
    VariableSymbol sym(name, legacyTypeToDescriptor(type), currentScope, isDeclared);
    sym.isUsed = false;
    sym.firstUse = loc;
    
    // Insert using scope-aware method
    m_symbolTable.insertVariable(name, sym);
    
    // Return pointer to inserted variable
    return m_symbolTable.lookupVariable(name, currentScope);
}

// New TypeDescriptor-based variable declaration
VariableSymbol* SemanticAnalyzer::declareVariableD(const std::string& name, const TypeDescriptor& typeDesc,
                                                   const SourceLocation& loc, bool isDeclared) {
    // Normalize the variable name to include proper type suffix
    std::string normalizedName = normalizeVariableName(name, typeDesc);
    
    // Get current scope
    Scope currentScope = getCurrentScope();
    
    // Check if variable already exists in current scope (using normalized name)
    VariableSymbol* existing = m_symbolTable.lookupVariable(normalizedName, currentScope);
    if (existing) {
        // Update existing variable with new type info
        existing->typeDesc = typeDesc;
        if (typeDesc.isUserDefined()) {
            existing->typeName = typeDesc.udtName;
        }
        return existing;
    }
    
    // Create new variable with explicit scope and normalized name
    VariableSymbol sym(normalizedName, typeDesc, currentScope, isDeclared);
    sym.firstUse = loc;
    
    // Insert using scope-aware method (with normalized name)
    m_symbolTable.insertVariable(normalizedName, sym);
    
    // Return pointer to inserted variable
    return m_symbolTable.lookupVariable(normalizedName, currentScope);
}

const VariableSymbol* SemanticAnalyzer::lookupVariableScoped(const std::string& varName, 
                                                              const std::string& functionScope) const {
    // Use legacy lookup for backward compatibility during migration
    return m_symbolTable.lookupVariableLegacy(varName, functionScope);
}

// Static helper to strip type suffix from variable name
// Handles both character suffixes (%, &, etc.) and text suffixes (_INT, _LONG, etc.)
std::string SemanticAnalyzer::stripTypeSuffix(const std::string& name) {
    if (name.empty()) return name;
    
    // Check for text suffixes first (from parser mangling)
    if (name.length() > 4 && name.substr(name.length() - 4) == "_INT") {
        return name.substr(0, name.length() - 4);
    }
    if (name.length() > 5 && name.substr(name.length() - 5) == "_LONG") {
        return name.substr(0, name.length() - 5);
    }
    if (name.length() > 7 && name.substr(name.length() - 7) == "_STRING") {
        return name.substr(0, name.length() - 7);
    }
    if (name.length() > 7 && name.substr(name.length() - 7) == "_DOUBLE") {
        return name.substr(0, name.length() - 7);
    }
    if (name.length() > 6 && name.substr(name.length() - 6) == "_FLOAT") {
        return name.substr(0, name.length() - 6);
    }
    if (name.length() > 5 && name.substr(name.length() - 5) == "_BYTE") {
        return name.substr(0, name.length() - 5);
    }
    if (name.length() > 6 && name.substr(name.length() - 6) == "_SHORT") {
        return name.substr(0, name.length() - 6);
    }

    
    // Check for character suffixes (if not already converted by parser)
    char lastChar = name.back();
    if (lastChar == '%' || lastChar == '&' || lastChar == '!' || 
        lastChar == '#' || lastChar == '$' || lastChar == '@' || lastChar == '^') {
        return name.substr(0, name.length() - 1);
    }
    
    return name;
}

// Get the correct integer suffix based on OPTION FOR setting
// Returns text suffix used by parser mangling (_INT or _LONG)
std::string SemanticAnalyzer::getForLoopIntegerSuffix() const {
    // Check the OPTION FOR setting
    if (m_options.forLoopType == CompilerOptions::ForLoopType::LONG) {
        return "_LONG";  // LONG suffix
    } else {
        return "_INT";   // INTEGER suffix (default)
    }
}

// Normalize FOR loop variable names: if varName references a FOR loop variable,
// return the base name with the correct integer suffix; otherwise return unchanged
std::string SemanticAnalyzer::normalizeForLoopVariable(const std::string& varName) const {
    if (varName.empty()) return varName;
    
    // Strip any existing suffix (both character and text forms)
    std::string baseName = stripTypeSuffix(varName);
    
    // Check if this is actually a FOR loop variable by looking for it in the symbol table
    // with integer suffix
    BaseType forVarType = (m_options.forLoopType == CompilerOptions::ForLoopType::LONG)
                          ? BaseType::LONG : BaseType::INTEGER;
    TypeDescriptor forTypeDesc(forVarType);
    std::string normalizedIntName = normalizeVariableName(baseName, forTypeDesc);
    
    // Check if this normalized name exists in the symbol table as an integer type
    auto it = m_symbolTable.variables.find(normalizedIntName);
    if (it != m_symbolTable.variables.end() && 
        (it->second.typeDesc.baseType == BaseType::INTEGER || 
         it->second.typeDesc.baseType == BaseType::LONG)) {
        return normalizedIntName;
    }
    
    // Not a FOR loop variable - return original name unchanged
    return varName;
}

VariableSymbol* SemanticAnalyzer::lookupVariable(const std::string& name) {
    // Use legacy lookup for backward compatibility during migration
    std::string functionScope = m_currentFunctionScope.inFunction ? m_currentFunctionScope.functionName : "";
    VariableSymbol* result = m_symbolTable.lookupVariableLegacy(name, functionScope);
    if (result) {
        return result;
    }
    // Also check arrays table - DIM x$ AS STRING creates a 0-dimensional array (scalar)
    // We need to treat it as a variable for assignment purposes
    // Special case: If the variable name matches a scalar (dimensionless) array, treat it as a variable
    auto arrIt = m_symbolTable.arrays.find(name);
    if (arrIt != m_symbolTable.arrays.end() && arrIt->second.dimensions.empty()) {
        // Found a scalar array - create a corresponding variable entry with current scope
        Scope currentScope = getCurrentScope();
        VariableSymbol sym(name, arrIt->second.elementTypeDesc, currentScope, true);
        sym.firstUse = arrIt->second.declaration;
        m_symbolTable.insertVariable(name, sym);
        return m_symbolTable.lookupVariable(name, currentScope);
    }
    
    return nullptr;
}

// New TypeDescriptor-based array declaration
ArraySymbol* SemanticAnalyzer::declareArrayD(const std::string& name, const TypeDescriptor& elementType,
                                             const std::vector<int>& dimensions,
                                             const SourceLocation& loc) {
    auto it = m_symbolTable.arrays.find(name);
    if (it != m_symbolTable.arrays.end()) {
        error(SemanticErrorType::ARRAY_REDECLARED,
              "Array '" + name + "' already declared",
              loc);
        return &it->second;
    }
    
    ArraySymbol sym(name, elementType, dimensions, true);
    sym.declaration = loc;
    
    m_symbolTable.arrays[name] = sym;
    return &m_symbolTable.arrays[name];
}

ArraySymbol* SemanticAnalyzer::lookupArray(const std::string& name) {
    auto it = m_symbolTable.arrays.find(name);
    if (it != m_symbolTable.arrays.end()) {
        return &it->second;
    }
    return nullptr;
}

// New TypeDescriptor-based function declaration
FunctionSymbol* SemanticAnalyzer::declareFunctionD(const std::string& name,
                                                   const std::vector<std::string>& params,
                                                   const std::vector<TypeDescriptor>& paramTypes,
                                                   const TypeDescriptor& returnType,
                                                   const Expression* body,
                                                   const SourceLocation& loc) {
    auto it = m_symbolTable.functions.find(name);
    if (it != m_symbolTable.functions.end()) {
        error(SemanticErrorType::FUNCTION_REDECLARED,
              "Function '" + name + "' already declared",
              loc);
        return &it->second;
    }
    
    FunctionSymbol sym(name, params, paramTypes, returnType);
    sym.body = body;
    sym.definition = loc;
    
    m_symbolTable.functions[name] = sym;
    return &m_symbolTable.functions[name];
}

FunctionSymbol* SemanticAnalyzer::lookupFunction(const std::string& name) {
    auto it = m_symbolTable.functions.find(name);
    if (it != m_symbolTable.functions.end()) {
        return &it->second;
    }
    return nullptr;
}

LineNumberSymbol* SemanticAnalyzer::lookupLine(int lineNumber) {
    auto it = m_symbolTable.lineNumbers.find(lineNumber);
    if (it != m_symbolTable.lineNumbers.end()) {
        return &it->second;
    }
    return nullptr;
}

LabelSymbol* SemanticAnalyzer::declareLabel(const std::string& name, size_t programLineIndex,
                                            const SourceLocation& loc) {
    // Check for duplicate labels
    if (m_symbolTable.labels.find(name) != m_symbolTable.labels.end()) {
        error(SemanticErrorType::DUPLICATE_LABEL,
              "Label :" + name + " already defined",
              loc);
        return nullptr;
    }
    
    LabelSymbol sym;
    sym.name = name;
    sym.labelId = m_symbolTable.nextLabelId++;
    sym.programLineIndex = programLineIndex;
    sym.definition = loc;
    m_symbolTable.labels[name] = sym;
    
    return &m_symbolTable.labels[name];
}

LabelSymbol* SemanticAnalyzer::lookupLabel(const std::string& name) {
    auto it = m_symbolTable.labels.find(name);
    if (it != m_symbolTable.labels.end()) {
        return &it->second;
    }
    return nullptr;
}

TypeSymbol* SemanticAnalyzer::lookupType(const std::string& name) {
    auto it = m_symbolTable.types.find(name);
    if (it != m_symbolTable.types.end()) {
        return &it->second;
    }
    return nullptr;
}

TypeSymbol* SemanticAnalyzer::declareType(const std::string& name, const SourceLocation& loc) {
    TypeSymbol typeSymbol(name);
    typeSymbol.declaration = loc;
    m_symbolTable.types[name] = typeSymbol;
    return &m_symbolTable.types[name];
}

int SemanticAnalyzer::resolveLabelToId(const std::string& name, const SourceLocation& loc) {
    auto* sym = lookupLabel(name);
    if (!sym) {
        error(SemanticErrorType::UNDEFINED_LABEL,
              "Undefined label: " + name,
              loc);
        return -1;  // Return invalid ID on error
    }
    
    // Track this reference
    sym->references.push_back(loc);
    return sym->labelId;
}

void SemanticAnalyzer::useVariable(const std::string& name, const SourceLocation& loc) {
    // First, check if this variable already exists in the current scope with ANY suffix
    // This is critical for FOR loop variables which are declared as INTEGER but referenced without suffix
    Scope currentScope = getCurrentScope();
    
    // Strip any existing suffix from the name
    std::string baseName = stripTypeSuffix(name);
    
    // Check if the name already has a suffix (parser mangled it)
    bool hasExplicitSuffix = (name != baseName);
    
    // If no explicit suffix, try to find the variable with any suffix in current scope
    if (!hasExplicitSuffix) {
        std::vector<std::string> suffixes = {"_INT", "_LONG", "_SHORT", "_BYTE", "_DOUBLE", "_FLOAT", "_STRING"};
        for (const auto& suffix : suffixes) {
            std::string candidate = baseName + suffix;
            auto* existingSym = m_symbolTable.lookupVariable(candidate, currentScope);
            if (existingSym) {
                // Found it! Use this existing variable
                existingSym->isUsed = true;
                return;
            }
        }
    }
    
    // Variable doesn't exist in current scope - infer type and create it
    TypeDescriptor typeDesc = inferTypeFromNameD(name);
    std::string normalizedName = normalizeVariableName(name, typeDesc);
    
    // Don't create symbol table entry for FOR EACH variables
    if (m_forEachVariables.count(normalizedName) > 0) {
        return;
    }
    
    auto* sym = lookupVariable(normalizedName);
    if (!sym) {
        // Implicitly declare using the inferred TypeDescriptor
        sym = declareVariableD(normalizedName, typeDesc, loc, false);
    }
    sym->isUsed = true;
}

void SemanticAnalyzer::useArray(const std::string& name, size_t dimensionCount, 
                                const SourceLocation& loc) {
    // Check if this is actually a function/sub call, not an array access
    if (m_symbolTable.functions.find(name) != m_symbolTable.functions.end()) {
        // It's a function or sub, not an array - skip array validation
        return;
    }
    
    // Check if this is a builtin function, not an array
    if (isBuiltinFunction(name)) {
        // It's a builtin function, not an array - skip array validation
        return;
    }
    
    // Check if this is an object with subscript operator (like hashmap)
    auto* varSym = lookupVariable(name);
    if (varSym && varSym->typeDesc.isObject()) {
        auto& registry = getRuntimeObjectRegistry();
        if (registry.isObjectType(varSym->typeDesc)) {
            auto* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
            if (objDesc && objDesc->hasSubscriptOperator) {
                // This is an object subscript operation, not an array - skip array validation
                return;
            }
        }
    }
    
    auto* sym = lookupArray(name);
    if (!sym) {
        if (m_requireExplicitDim) {
            error(SemanticErrorType::ARRAY_NOT_DECLARED,
                  "Array '" + name + "' used without DIM declaration",
                  loc);
        }
        return;
    }
    
    // Check dimension count
    // Allow dimensionCount == 0 for whole-array references like A() in array expressions
    if (dimensionCount != 0 && dimensionCount != sym->dimensions.size()) {
        error(SemanticErrorType::WRONG_DIMENSION_COUNT,
              "Array '" + name + "' expects " + std::to_string(sym->dimensions.size()) +
              " dimensions, got " + std::to_string(dimensionCount),
              loc);
    }
}

// =============================================================================
// Type Inference from Name/Suffix
// =============================================================================

VariableType SemanticAnalyzer::inferTypeFromSuffix(TokenType suffix) {
    switch (suffix) {
        case TokenType::TYPE_INT:    return VariableType::INT;
        case TokenType::PERCENT:     return VariableType::INT;    // % suffix
        case TokenType::AMPERSAND:   return VariableType::INT;    // & suffix (LONG — lossy, but best legacy enum can do)
        case TokenType::TYPE_FLOAT:  return VariableType::FLOAT;
        case TokenType::EXCLAMATION: return VariableType::FLOAT;  // ! suffix
        case TokenType::TYPE_DOUBLE: return VariableType::DOUBLE;
        case TokenType::TYPE_STRING: 
            // Return UNICODE type if in Unicode mode
            // For INPUT, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        default:                     return VariableType::UNKNOWN;
    }
}

VariableType SemanticAnalyzer::inferTypeFromName(const std::string& name) {
    // For 64-bit systems (ARM64/x86-64), DOUBLE is the natural numeric type
    // Modern CPUs handle 64-bit floats natively and efficiently
    if (name.empty()) return VariableType::DOUBLE;
    
    // Check for normalized suffixes first (e.g., A_STRING, B_INT, C_DOUBLE)
    if (name.length() > 7 && name.substr(name.length() - 7) == "_STRING") {
        // Default string type for unknown cases, use global mode
        return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
            VariableType::UNICODE : VariableType::STRING;
    }
    if (name.length() > 4 && name.substr(name.length() - 4) == "_INT") {
        return VariableType::INT;
    }
    if (name.length() > 7 && name.substr(name.length() - 7) == "_DOUBLE") {
        return VariableType::DOUBLE;
    }
    
    // Check for original BASIC suffixes ($, %, !, #)
    char lastChar = name.back();
    switch (lastChar) {
        case '$': 
            // Return UNICODE type if in Unicode mode
            // For string variables, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                VariableType::UNICODE : VariableType::STRING;
        case '%': return VariableType::INT;      // Integer (32/64-bit on modern systems)
        case '!': return VariableType::FLOAT;    // Single-precision (32-bit float)
        case '#': return VariableType::DOUBLE;   // Double-precision (64-bit float)
        default:  return VariableType::DOUBLE;   // Default: DOUBLE for 64-bit systems (ARM64/x86-64)
    }
}

std::string SemanticAnalyzer::mangleNameWithSuffix(const std::string& name, TokenType suffix) {
    // If no suffix, return name as-is
    if (suffix == TokenType::UNKNOWN) {
        return name;
    }
    
    // Mangle the name with the suffix (same as parser does for function declarations)
    switch (suffix) {
        case TokenType::TYPE_STRING:
            return name + "_STRING";
        case TokenType::TYPE_INT:
            return name + "_INT";
        case TokenType::TYPE_DOUBLE:
            return name + "_DOUBLE";
        case TokenType::TYPE_FLOAT:
            return name + "_FLOAT";
        default:
            return name;
    }
}

// Normalize a variable name to include the proper type suffix
// This is the canonical function that ensures consistency across the entire system
std::string SemanticAnalyzer::normalizeVariableName(const std::string& name, const TypeDescriptor& typeDesc) const {
    // Check if name already has a suffix
    std::string baseName = stripTypeSuffix(name);
    
    // Determine the suffix based on the type descriptor
    std::string suffix;
    switch (typeDesc.baseType) {
        case BaseType::INTEGER:
            suffix = "_INT";
            break;
        case BaseType::LONG:
            suffix = "_LONG";
            break;
        case BaseType::SHORT:
            suffix = "_SHORT";
            break;
        case BaseType::BYTE:
            suffix = "_BYTE";
            break;
        case BaseType::DOUBLE:
            suffix = "_DOUBLE";
            break;
        case BaseType::SINGLE:
            suffix = "_FLOAT";
            break;
        case BaseType::STRING:
        case BaseType::UNICODE:
            suffix = "_STRING";
            break;
        case BaseType::OBJECT:
            // Object types don't get a suffix (like USER_DEFINED types)
            return baseName;
        case BaseType::USER_DEFINED:
            // User-defined types don't get a suffix
            return baseName;
        default:
            // Unknown types return the base name
            return baseName;
    }
    
    return baseName + suffix;
}

// Normalize a variable name based on token suffix and optional AS type
std::string SemanticAnalyzer::normalizeVariableName(const std::string& name, TokenType suffix, const std::string& asTypeName) const {
    // If we have an AS type, use it to determine the type descriptor
    if (!asTypeName.empty()) {
        std::string upperType = asTypeName;
        std::transform(upperType.begin(), upperType.end(), upperType.begin(), ::toupper);
        
        TypeDescriptor typeDesc;
        if (upperType == "INTEGER" || upperType == "INT") {
            typeDesc = TypeDescriptor(BaseType::INTEGER);
        } else if (upperType == "DOUBLE") {
            typeDesc = TypeDescriptor(BaseType::DOUBLE);
        } else if (upperType == "SINGLE" || upperType == "FLOAT") {
            typeDesc = TypeDescriptor(BaseType::SINGLE);
        } else if (upperType == "STRING") {
            typeDesc = TypeDescriptor(BaseType::STRING);
        } else if (upperType == "LONG") {
            typeDesc = TypeDescriptor(BaseType::LONG);
        } else if (upperType == "BYTE") {
            typeDesc = TypeDescriptor(BaseType::BYTE);
        } else if (upperType == "SHORT") {
            typeDesc = TypeDescriptor(BaseType::SHORT);
        } else {
            // User-defined type - no suffix
            typeDesc = TypeDescriptor(BaseType::USER_DEFINED);
            typeDesc.udtName = asTypeName;
        }
        return normalizeVariableName(name, typeDesc);
    }
    
    // Otherwise use the token suffix
    if (suffix == TokenType::UNKNOWN) {
        // No type information - return name as-is (but strip any existing suffix first)
        return stripTypeSuffix(name);
    }
    
    // Convert token suffix to TypeDescriptor
    TypeDescriptor typeDesc = tokenSuffixToDescriptor(suffix);
    return normalizeVariableName(name, typeDesc);
}

// =============================================================================
// Control Flow and Final Validation
// =============================================================================

void SemanticAnalyzer::validateControlFlow(Program& program) {
    if (getenv("FASTERBASIC_DEBUG")) {
        std::cerr << "[DEBUG] validateControlFlow called, FOR stack size: " << m_forStack.size() << std::endl;
    }
    // Check for unclosed loops
    if (!m_forStack.empty()) {
        const auto& ctx = m_forStack.top();
        if (getenv("FASTERBASIC_DEBUG")) {
            std::cerr << "[DEBUG] FOR stack NOT empty! Top entry: " << ctx.location.toString() << std::endl;
        }
        error(SemanticErrorType::FOR_WITHOUT_NEXT,
              "FOR loop starting at " + ctx.location.toString() + " has no matching NEXT",
              ctx.location);
    }
    
    if (!m_whileStack.empty()) {
        const auto& loc = m_whileStack.top();
        error(SemanticErrorType::WHILE_WITHOUT_WEND,
              "WHILE loop starting at " + loc.toString() + " has no matching WEND",
              loc);
    }
    
    if (!m_repeatStack.empty()) {
        const auto& loc = m_repeatStack.top();
        error(SemanticErrorType::REPEAT_WITHOUT_UNTIL,
              "REPEAT loop starting at " + loc.toString() + " has no matching UNTIL",
              loc);
    }
}

void SemanticAnalyzer::checkUnusedVariables() {
    for (const auto& pair : m_symbolTable.variables) {
        const auto& sym = pair.second;
        if (!sym.isUsed && sym.isDeclared) {
            warning("Variable '" + sym.name + "' declared but never used", sym.firstUse);
        }
    }
}

// =============================================================================
// Error Reporting
// =============================================================================

void SemanticAnalyzer::error(SemanticErrorType type, const std::string& message,
                             const SourceLocation& loc) {
    m_errors.emplace_back(type, message, loc);
}

void SemanticAnalyzer::warning(const std::string& message, const SourceLocation& loc) {
    m_warnings.emplace_back(message, loc);
}

// =============================================================================
// Report Generation
// =============================================================================

std::string SemanticAnalyzer::generateReport() const {
    std::ostringstream oss;
    
    oss << "=== SEMANTIC ANALYSIS REPORT ===\n\n";
    
    // Summary
    oss << "Status: ";
    if (m_errors.empty()) {
        oss << "✓ PASSED\n";
    } else {
        oss << "✗ FAILED (" << m_errors.size() << " error(s))\n";
    }
    
    oss << "Errors: " << m_errors.size() << "\n";
    oss << "Warnings: " << m_warnings.size() << "\n";
    oss << "\n";
    
    // Symbol table summary
    oss << "Symbol Table Summary:\n";
    oss << "  Line Numbers: " << m_symbolTable.lineNumbers.size() << "\n";
    oss << "  Variables: " << m_symbolTable.variables.size() << "\n";
    oss << "  Arrays: " << m_symbolTable.arrays.size() << "\n";
    oss << "  Functions: " << m_symbolTable.functions.size() << "\n";
    oss << "  Data Values: " << m_symbolTable.dataSegment.values.size() << "\n";
    oss << "\n";
    
    // Errors
    if (!m_errors.empty()) {
        oss << "Errors:\n";
        for (const auto& err : m_errors) {
            oss << "  " << err.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Warnings
    if (!m_warnings.empty()) {
        oss << "Warnings:\n";
        for (const auto& warn : m_warnings) {
            oss << "  " << warn.toString() << "\n";
        }
        oss << "\n";
    }
    
    // Full symbol table
    oss << m_symbolTable.toString();
    
    oss << "=== END SEMANTIC ANALYSIS REPORT ===\n";
    
    return oss.str();
}

// =============================================================================
// Built-in Function Support
// =============================================================================

void SemanticAnalyzer::initializeBuiltinFunctions() {
    // Math functions (all take 1 argument, return FLOAT)
    m_builtinFunctions["ABS"] = 1;
    m_builtinFunctions["SIN"] = 1;
    m_builtinFunctions["COS"] = 1;
    m_builtinFunctions["TAN"] = 1;
    m_builtinFunctions["ATAN"] = 1;
    m_builtinFunctions["ATN"] = 1;    // Alias for ATAN
    m_builtinFunctions["SQRT"] = 1;
    m_builtinFunctions["SQR"] = 1;    // Alias for SQRT
    m_builtinFunctions["INT"] = 1;
    m_builtinFunctions["SGN"] = 1;
    m_builtinFunctions["LOG"] = 1;
    m_builtinFunctions["EXP"] = 1;
    m_builtinFunctions["POW"] = 2;    // Takes 2 arguments: base, exponent
    m_builtinFunctions["ATAN2"] = 2;  // Takes 2 arguments: y, x
    m_builtinFunctions["MIN"] = 2;    // Takes 2 arguments: returns minimum
    m_builtinFunctions["MAX"] = 2;    // Takes 2 arguments: returns maximum
    m_builtinFunctions["FIX"] = 1;    // Takes 1 argument: truncates to integer
    m_builtinFunctions["CINT"] = 1;   // Takes 1 argument: rounds to integer
    
    // RND takes 0 or 1 argument
    m_builtinFunctions["RND"] = -1;  // -1 = variable arg count
    
    // GETTICKS takes 0 arguments
    m_builtinFunctions["GETTICKS"] = 0;
    
    // String functions (register both $ and _STRING variants for parser compatibility)
    m_builtinFunctions["LEN"] = 1;    // Returns INT
    m_builtinFunctions["ASC"] = 1;    // Returns INT
    m_builtinFunctions["STRTYPE"] = 1; // Returns INT (encoding type: 0=ASCII, 1=UTF-32)
    m_builtinFunctions["CHR$"] = 1;   // Returns STRING
    m_builtinFunctions["CHR_STRING"] = 1;   // Parser converts CHR$ to CHR_STRING
    m_builtinFunctions["STR$"] = 1;   // Returns STRING
    m_builtinFunctions["STR_STRING"] = 1;   // Parser converts STR$ to STR_STRING
    m_builtinFunctions["VAL"] = 1;    // Returns FLOAT
    m_builtinFunctions["LEFT$"] = 2;  // Returns STRING
    m_builtinFunctions["LEFT_STRING"] = 2;  // Parser converts LEFT$ to LEFT_STRING
    m_builtinFunctions["RIGHT$"] = 2; // Returns STRING
    m_builtinFunctions["RIGHT_STRING"] = 2; // Parser converts RIGHT$ to RIGHT_STRING
    m_builtinFunctions["MID$"] = 3;   // Returns STRING (string, start, length)
    m_builtinFunctions["MID_STRING"] = 3;   // Parser converts MID$ to MID_STRING
    m_builtinFunctions["INSTR"] = -1;  // Returns INT - 2 args: (haystack$, needle$) or 3 args: (start, haystack$, needle$)
    m_builtinFunctions["STRING$"] = 2; // Returns STRING (count, char$ or ascii) - repeat character
    m_builtinFunctions["STRING_STRING"] = 2; // Parser converts STRING$ to STRING_STRING
    m_builtinFunctions["SPACE$"] = 1; // Returns STRING (count) - generate spaces
    m_builtinFunctions["SPACE_STRING"] = 1; // Parser converts SPACE$ to SPACE_STRING
    m_builtinFunctions["LCASE$"] = 1; // Returns STRING (lowercase)
    m_builtinFunctions["LCASE_STRING"] = 1; // Parser converts LCASE$ to LCASE_STRING
    m_builtinFunctions["UCASE$"] = 1; // Returns STRING (uppercase)
    m_builtinFunctions["UCASE_STRING"] = 1; // Parser converts UCASE$ to UCASE_STRING
    m_builtinFunctions["LTRIM$"] = 1; // Returns STRING (remove leading spaces)
    m_builtinFunctions["LTRIM_STRING"] = 1; // Parser converts LTRIM$ to LTRIM_STRING
    m_builtinFunctions["RTRIM$"] = 1; // Returns STRING (remove trailing spaces)
    m_builtinFunctions["RTRIM_STRING"] = 1; // Parser converts RTRIM$ to RTRIM_STRING
    m_builtinFunctions["TRIM$"] = 1;  // Returns STRING (remove leading and trailing spaces)
    m_builtinFunctions["TRIM_STRING"] = 1;  // Parser converts TRIM$ to TRIM_STRING
    m_builtinFunctions["REVERSE$"] = 1; // Returns STRING (reverse string)
    m_builtinFunctions["REVERSE_STRING"] = 1; // Parser converts REVERSE$ to REVERSE_STRING
    
    // File I/O functions
    m_builtinFunctions["EOF"] = 1;    // (file_number) Returns INT (bool)
    m_builtinFunctions["LOC"] = 1;    // (file_number) Returns INT (position)
    m_builtinFunctions["LOF"] = 1;    // (file_number) Returns INT (length)
    
    // Terminal I/O functions
    m_builtinFunctions["INKEY$"] = 0;    // Returns STRING (non-blocking keyboard input)
    m_builtinFunctions["INKEY_STRING"] = 0;  // Parser converts INKEY$ to INKEY_STRING
    m_builtinFunctions["CSRLIN"] = 0;    // Returns INT (current cursor row)
    m_builtinFunctions["POS"] = 1;       // (dummy) Returns INT (current cursor column)
    
    // Exception handling functions
    m_builtinFunctions["ERR"] = 0;       // Returns INT (current error code)
    m_builtinFunctions["ERL"] = 0;       // Returns INT (current error line)
    
    // Array bounds functions
    m_builtinFunctions["LBOUND"] = -1;  // (array) or (array, dimension) Returns INT
    m_builtinFunctions["UBOUND"] = -1;  // (array) or (array, dimension) Returns INT
    
    // =============================================================================
    // SuperTerminal Runtime API
    // =============================================================================
    
    // Text Layer
    m_builtinFunctions["TEXT_CLEAR"] = 0;           // void
    m_builtinFunctions["TEXT_CLEAR_REGION"] = 4;   // (x, y, w, h) void
    m_builtinFunctions["TEXT_PUT"] = 5;            // (x, y, text$, fg, bg) void
    m_builtinFunctions["TEXT_PUTCHAR"] = 5;        // (x, y, chr, fg, bg) void
    m_builtinFunctions["TEXT_SCROLL"] = 1;         // (lines) void
    m_builtinFunctions["TEXT_SET_SIZE"] = 2;       // (width, height) void
    m_builtinFunctions["TEXT_GET_WIDTH"] = 0;      // Returns INT
    m_builtinFunctions["TEXT_GET_HEIGHT"] = 0;     // Returns INT
    
    // Chunky Graphics Layer (palette index + background color)
    m_builtinFunctions["CHUNKY_CLEAR"] = 1;        // (bg_color) void
    m_builtinFunctions["CHUNKY_PSET"] = 4;         // (x, y, color_idx, bg) void
    m_builtinFunctions["CHUNKY_LINE"] = 6;         // (x1, y1, x2, y2, color_idx, bg) void
    m_builtinFunctions["CHUNKY_RECT"] = 6;         // (x, y, w, h, color_idx, bg) void
    m_builtinFunctions["CHUNKY_FILLRECT"] = 6;     // (x, y, w, h, color_idx, bg) void
    m_builtinFunctions["CHUNKY_HLINE"] = 5;        // (x, y, length, color_idx, bg) void
    m_builtinFunctions["CHUNKY_VLINE"] = 5;        // (x, y, length, color_idx, bg) void
    m_builtinFunctions["CHUNKY_GET_WIDTH"] = 0;    // Returns INT
    m_builtinFunctions["CHUNKY_GET_HEIGHT"] = 0;   // Returns INT
    
    // Smooth Graphics Layer (STColor + thickness for outlines)
    m_builtinFunctions["GFX_CLEAR"] = 0;           // void
    m_builtinFunctions["GFX_LINE"] = 6;            // (x1, y1, x2, y2, color, thickness) void
    m_builtinFunctions["GFX_RECT"] = 5;            // (x, y, w, h, color) void
    m_builtinFunctions["GFX_RECT_OUTLINE"] = 6;    // (x, y, w, h, color, thickness) void
    m_builtinFunctions["GFX_CIRCLE"] = 4;          // (x, y, radius, color) void
    m_builtinFunctions["GFX_CIRCLE_OUTLINE"] = 5;  // (x, y, radius, color, thickness) void
    m_builtinFunctions["GFX_POINT"] = 3;           // (x, y, color) void
    
    // Color Utilities
    m_builtinFunctions["COLOR_RGB"] = 3;           // (r, g, b) Returns INT
    m_builtinFunctions["COLOR_RGBA"] = 4;          // (r, g, b, a) Returns INT
    m_builtinFunctions["COLOR_HSV"] = 3;           // (h, s, v) Returns INT
    
    // Frame Synchronization & Timing
    m_builtinFunctions["FRAME_WAIT"] = 0;          // void
    m_builtinFunctions["FRAME_COUNT"] = 0;         // Returns INT
    m_builtinFunctions["TIME"] = 0;                // Returns FLOAT
    m_builtinFunctions["DELTA_TIME"] = 0;          // Returns FLOAT
    
    // Random Utilities
    m_builtinFunctions["RANDOM"] = 0;              // Returns FLOAT
    m_builtinFunctions["RANDOM_INT"] = 2;          // (min, max) Returns INT
    m_builtinFunctions["RANDOM_SEED"] = 1;         // (seed) void
    
    // =============================================================================
    // SuperTerminal API - Phase 2: Input & Sprites
    // =============================================================================
    
    // Keyboard Input
    m_builtinFunctions["KEY_PRESSED"] = 1;         // (keycode) Returns INT (bool)
    m_builtinFunctions["KEY_JUST_PRESSED"] = 1;    // (keycode) Returns INT (bool)
    m_builtinFunctions["KEY_JUST_RELEASED"] = 1;   // (keycode) Returns INT (bool)
    m_builtinFunctions["KEY_GET_CHAR"] = 0;        // Returns INT (char code)
    m_builtinFunctions["KEY_CLEAR_BUFFER"] = 0;    // void
    
    // Mouse Input
    m_builtinFunctions["MOUSE_X"] = 0;             // Returns INT (pixel x)
    m_builtinFunctions["MOUSE_Y"] = 0;             // Returns INT (pixel y)
    m_builtinFunctions["MOUSE_GRID_X"] = 0;        // Returns INT (grid column)
    m_builtinFunctions["MOUSE_GRID_Y"] = 0;        // Returns INT (grid row)
    m_builtinFunctions["MOUSE_BUTTON"] = 1;        // (button) Returns INT (bool)
    m_builtinFunctions["MOUSE_BUTTON_PRESSED"] = 1;    // (button) Returns INT (bool)
    m_builtinFunctions["MOUSE_BUTTON_RELEASED"] = 1;   // (button) Returns INT (bool)
    m_builtinFunctions["MOUSE_WHEEL_X"] = 0;       // Returns FLOAT (wheel delta x)
    m_builtinFunctions["MOUSE_WHEEL_Y"] = 0;       // Returns FLOAT (wheel delta y)
    
    // Sprites
    m_builtinFunctions["SPRITE_LOAD"] = 1;         // (filename$) Returns INT (sprite ID)
    m_builtinFunctions["SPRITE_LOAD_BUILTIN"] = 1; // (name$) Returns INT (sprite ID)
    m_builtinFunctions["DRAWINTOSPRITE"] = 2;      // (width, height) Returns INT (sprite ID)
    m_builtinFunctions["ENDDRAWINTOSPRITE"] = 0;   // void
    m_builtinFunctions["DRAWTOFILE"] = 3;          // (filename$, width, height) Returns BOOL
    m_builtinFunctions["ENDDRAWTOFILE"] = 0;       // Returns BOOL
    m_builtinFunctions["DRAWTOTILESET"] = 4;       // (tile_width, tile_height, columns, rows) Returns INT
    m_builtinFunctions["DRAWTILE"] = 1;            // (tile_index) Returns BOOL
    m_builtinFunctions["ENDDRAWTOTILESET"] = 0;    // Returns BOOL
    m_builtinFunctions["SPRITE_SHOW"] = 3;         // (id, x, y) void
    m_builtinFunctions["SPRITE_HIDE"] = 1;         // (id) void
    m_builtinFunctions["SPRITE_TRANSFORM"] = 6;    // (id, x, y, rot, sx, sy) void
    m_builtinFunctions["SPRITE_TINT"] = 2;         // (id, color) void
    m_builtinFunctions["SPRITE_UNLOAD"] = 1;       // (id) void
    
    // Layers
    m_builtinFunctions["LAYER_SET_VISIBLE"] = 2;   // (layer, visible) void
    m_builtinFunctions["LAYER_SET_ALPHA"] = 2;     // (layer, alpha) void
    m_builtinFunctions["LAYER_SET_ORDER"] = 2;     // (layer, order) void
    
    // Display queries
    m_builtinFunctions["DISPLAY_WIDTH"] = 0;       // Returns INT
    m_builtinFunctions["DISPLAY_HEIGHT"] = 0;      // Returns INT
    m_builtinFunctions["CELL_WIDTH"] = 0;          // Returns INT
    m_builtinFunctions["CELL_HEIGHT"] = 0;         // Returns INT
    
    // =============================================================================
    // SuperTerminal API - Phase 3: Audio
    // =============================================================================
    
    // Sound Effects
    m_builtinFunctions["SOUND_LOAD"] = 1;          // (filename$) Returns INT (sound ID)
    m_builtinFunctions["SOUND_LOAD_BUILTIN"] = 1;  // (name$) Returns INT (sound ID)
    m_builtinFunctions["SOUND_PLAY"] = 2;          // (id, volume) void
    m_builtinFunctions["SOUND_STOP"] = 1;          // (id) void
    m_builtinFunctions["SOUND_UNLOAD"] = 1;        // (id) void
    
    // Music and Audio - loaded from command registry
    
    // Synthesis
    m_builtinFunctions["SYNTH_NOTE"] = 3;          // (note, duration, volume) void
    m_builtinFunctions["SYNTH_FREQUENCY"] = 3;     // (freq, duration, volume) void
    m_builtinFunctions["SYNTH_SET_INSTRUMENT"] = 1; // (instrument) void
    
    // =============================================================================
    // SuperTerminal API - Phase 5: Asset Management
    // =============================================================================
    
    // Initialization
    m_builtinFunctions["ASSET_INIT"] = 2;          // (db_path$, max_cache_size) Returns INT (bool)
    m_builtinFunctions["ASSET_SHUTDOWN"] = 0;      // void
    m_builtinFunctions["ASSET_IS_INITIALIZED"] = 0; // Returns INT (bool)
    
    // Loading / Unloading
    m_builtinFunctions["ASSET_LOAD"] = 1;          // (name$) Returns INT (asset ID)
    m_builtinFunctions["ASSET_LOAD_FILE"] = 2;     // (path$, type) Returns INT (asset ID)
    m_builtinFunctions["ASSET_LOAD_BUILTIN"] = 2;  // (name$, type) Returns INT (asset ID)
    m_builtinFunctions["ASSET_UNLOAD"] = 1;        // (id) void
    m_builtinFunctions["ASSET_IS_LOADED"] = 1;     // (name$) Returns INT (bool)
    
    // Import / Export
    m_builtinFunctions["ASSET_IMPORT"] = 3;        // (file_path$, asset_name$, type) Returns INT (bool)
    m_builtinFunctions["ASSET_IMPORT_DIR"] = 2;    // (directory$, recursive) Returns INT (count)
    m_builtinFunctions["ASSET_EXPORT"] = 2;        // (asset_name$, file_path$) Returns INT (bool)
    m_builtinFunctions["ASSET_DELETE"] = 1;        // (asset_name$) Returns INT (bool)
    
    // Data Access
    m_builtinFunctions["ASSET_GET_SIZE"] = 1;      // (id) Returns INT
    m_builtinFunctions["ASSET_GET_TYPE"] = 1;      // (id) Returns INT
    m_builtinFunctions["ASSET_GET_NAME"] = 1;      // (id) Returns STRING
    
    // Queries
    m_builtinFunctions["ASSET_EXISTS"] = 1;        // (name$) Returns INT (bool)
    m_builtinFunctions["ASSET_GET_COUNT"] = 1;     // (type) Returns INT
    
    // Cache Management
    m_builtinFunctions["ASSET_CLEAR_CACHE"] = 0;   // void
    m_builtinFunctions["ASSET_GET_CACHE_SIZE"] = 0; // Returns INT
    m_builtinFunctions["ASSET_GET_CACHED_COUNT"] = 0; // Returns INT
    m_builtinFunctions["ASSET_SET_MAX_CACHE"] = 1; // (max_size) void
    
    // Statistics
    m_builtinFunctions["ASSET_GET_HIT_RATE"] = 0;  // Returns FLOAT
    m_builtinFunctions["ASSET_GET_DB_SIZE"] = 0;   // Returns INT
    
    // Error Handling
    m_builtinFunctions["ASSET_GET_ERROR"] = 0;     // Returns STRING
    m_builtinFunctions["ASSET_CLEAR_ERROR"] = 0;   // void
    
    // =============================================================================
    // SuperTerminal API - Phase 4: Tilemaps & Particles
    // =============================================================================
    
    // Tilemap System
    m_builtinFunctions["TILEMAP_INIT"] = 2;        // (viewport_w, viewport_h) Returns INT (bool)
    m_builtinFunctions["TILEMAP_SHUTDOWN"] = 0;    // void
    m_builtinFunctions["TILEMAP_CREATE"] = 4;      // (w, h, tile_w, tile_h) Returns INT (ID)
    m_builtinFunctions["TILEMAP_DESTROY"] = 1;     // (id) void
    m_builtinFunctions["TILEMAP_GET_WIDTH"] = 1;   // (id) Returns INT
    m_builtinFunctions["TILEMAP_GET_HEIGHT"] = 1;  // (id) Returns INT
    
    // Tileset
    m_builtinFunctions["TILESET_LOAD"] = 5;        // (path$, tw, th, margin, spacing) Returns INT (ID)
    m_builtinFunctions["TILESET_DESTROY"] = 1;     // (id) void
    m_builtinFunctions["TILESET_GET_COUNT"] = 1;   // (id) Returns INT
    
    // Layer Management
    m_builtinFunctions["TILEMAP_CREATE_LAYER"] = 1;     // (name$) Returns INT (layer ID)
    m_builtinFunctions["TILEMAP_DESTROY_LAYER"] = 1;    // (layer_id) void
    m_builtinFunctions["TILEMAP_LAYER_SET_MAP"] = 2;    // (layer_id, map_id) void
    m_builtinFunctions["TILEMAP_LAYER_SET_TILESET"] = 2; // (layer_id, tileset_id) void
    m_builtinFunctions["TILEMAP_LAYER_SET_PARALLAX"] = 3; // (layer_id, px, py) void
    m_builtinFunctions["TILEMAP_LAYER_SET_VISIBLE"] = 2;  // (layer_id, visible) void
    m_builtinFunctions["TILEMAP_LAYER_SET_Z_ORDER"] = 2;  // (layer_id, z) void
    
    // Tile Operations
    m_builtinFunctions["TILEMAP_SET_TILE"] = 4;    // (layer_id, x, y, tile_id) void
    m_builtinFunctions["TILEMAP_GET_TILE"] = 3;    // (layer_id, x, y) Returns INT
    m_builtinFunctions["TILEMAP_FILL_RECT"] = 6;   // (layer_id, x, y, w, h, tile_id) void
    m_builtinFunctions["TILEMAP_CLEAR"] = 1;       // (layer_id) void
    
    // Camera Control
    m_builtinFunctions["TILEMAP_SET_CAMERA"] = 2;  // (x, y) void
    m_builtinFunctions["TILEMAP_MOVE_CAMERA"] = 2; // (dx, dy) void
    m_builtinFunctions["TILEMAP_GET_CAMERA_X"] = 0; // Returns FLOAT
    m_builtinFunctions["TILEMAP_GET_CAMERA_Y"] = 0; // Returns FLOAT
    m_builtinFunctions["TILEMAP_SET_ZOOM"] = 1;    // (zoom) void
    m_builtinFunctions["TILEMAP_CAMERA_SHAKE"] = 2; // (magnitude, duration) void
    
    // Update
    m_builtinFunctions["TILEMAP_UPDATE"] = 1;      // (delta_time) void
    
    // Particle System
    m_builtinFunctions["PARTICLE_INIT"] = 1;       // (max_particles) Returns INT (bool)
    m_builtinFunctions["PARTICLE_SHUTDOWN"] = 0;   // void
    m_builtinFunctions["PARTICLE_IS_READY"] = 0;   // Returns INT (bool)
    m_builtinFunctions["PARTICLE_EXPLODE"] = 4;    // (x, y, count, color) Returns INT (bool)
    m_builtinFunctions["PARTICLE_EXPLODE_ADV"] = 7; // (x, y, count, color, force, gravity, fade) Returns INT
    m_builtinFunctions["PARTICLE_CLEAR"] = 0;      // void
    m_builtinFunctions["PARTICLE_PAUSE"] = 0;      // void
    m_builtinFunctions["PARTICLE_RESUME"] = 0;     // void
    m_builtinFunctions["PARTICLE_GET_COUNT"] = 0;  // Returns INT
}

bool SemanticAnalyzer::isBuiltinFunction(const std::string& name) const {
    std::string upper = name;
    std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
    return m_builtinFunctions.find(upper) != m_builtinFunctions.end();
}

VariableType SemanticAnalyzer::getBuiltinReturnType(const std::string& name) const {
    if (!isBuiltinFunction(name)) {
        return VariableType::UNKNOWN;
    }
    
    // String functions return STRING
    // Check for both $ suffix and _STRING suffix (mangled by parser)
    if (name.back() == '$' || 
        (name.length() > 7 && name.substr(name.length() - 7) == "_STRING")) {
        // Return UNICODE type if in Unicode mode
        // For string type names, use global mode
        return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
            VariableType::UNICODE : VariableType::STRING;
    }
    
    // LEN and ASC return INT
    if (name == "LEN" || name == "ASC" || name == "STRTYPE") {
        return VariableType::INT;
    }
    
    // SuperTerminal API functions that return INT
    if (name == "TEXT_GET_WIDTH" || name == "TEXT_GET_HEIGHT" ||
        name == "CHUNKY_GET_WIDTH" || name == "CHUNKY_GET_HEIGHT" ||
        name == "COLOR_RGB" || name == "COLOR_RGBA" || name == "COLOR_HSV" ||
        name == "FRAME_COUNT" || name == "RANDOM_INT" ||
        name == "KEY_PRESSED" || name == "KEY_JUST_PRESSED" || name == "KEY_JUST_RELEASED" ||
        name == "KEY_GET_CHAR" || 
        name == "MOUSE_X" || name == "MOUSE_Y" || 
        name == "MOUSE_GRID_X" || name == "MOUSE_GRID_Y" ||
        name == "MOUSE_BUTTON" || name == "MOUSE_BUTTON_PRESSED" || name == "MOUSE_BUTTON_RELEASED" ||
        name == "SPRITE_LOAD" || name == "SPRITE_LOAD_BUILTIN" || name == "DRAWINTOSPRITE" ||
        name == "DRAWTOFILE" || name == "ENDDRAWTOFILE" ||
        name == "DRAWTOTILESET" || name == "DRAWTILE" || name == "ENDDRAWTOTILESET" ||
        name == "DISPLAY_WIDTH" || name == "DISPLAY_HEIGHT" ||
        name == "CELL_WIDTH" || name == "CELL_HEIGHT" ||
        name == "SOUND_LOAD" || name == "SOUND_LOAD_BUILTIN" ||
        name == "MUSIC_IS_PLAYING" ||
        name == "TILEMAP_INIT" || name == "TILEMAP_CREATE" ||
        name == "TILEMAP_GET_WIDTH" || name == "TILEMAP_GET_HEIGHT" ||
        name == "TILESET_LOAD" || name == "TILESET_GET_COUNT" ||
        name == "TILEMAP_CREATE_LAYER" || name == "TILEMAP_GET_TILE" ||
        name == "PARTICLE_INIT" || name == "PARTICLE_IS_READY" ||
        name == "PARTICLE_EXPLODE" || name == "PARTICLE_EXPLODE_ADV" ||
        name == "PARTICLE_GET_COUNT" ||
        name == "ASSET_INIT" || name == "ASSET_IS_INITIALIZED" ||
        name == "ASSET_LOAD" || name == "ASSET_LOAD_FILE" || name == "ASSET_LOAD_BUILTIN" ||
        name == "ASSET_IS_LOADED" || name == "ASSET_IMPORT" || name == "ASSET_IMPORT_DIR" ||
        name == "ASSET_EXPORT" || name == "ASSET_DELETE" ||
        name == "ASSET_GET_SIZE" || name == "ASSET_GET_TYPE" ||
        name == "ASSET_EXISTS" || name == "ASSET_GET_COUNT" ||
        name == "ASSET_GET_CACHE_SIZE" || name == "ASSET_GET_CACHED_COUNT" ||
        name == "ASSET_GET_DB_SIZE") {
        return VariableType::INT;
    }
    
    // SuperTerminal API functions that return FLOAT
    if (name == "TIME" || name == "DELTA_TIME" || name == "RANDOM" ||
        name == "MOUSE_WHEEL_X" || name == "MOUSE_WHEEL_Y" ||
        name == "TILEMAP_GET_CAMERA_X" || name == "TILEMAP_GET_CAMERA_Y" ||
        name == "ASSET_GET_HIT_RATE") {
        return VariableType::FLOAT;
    }
    
    // SuperTerminal API void functions (no return type)
    if (name.find("TEXT_") == 0 || name.find("CHUNKY_") == 0 || 
        name.find("GFX_") == 0 || name.find("SPRITE_") == 0 ||
        name.find("LAYER_") == 0 || name.find("SOUND_") == 0 ||
        name.find("MUSIC_") == 0 || name.find("SYNTH_") == 0 ||
        name.find("TILEMAP_") == 0 || name.find("TILESET_") == 0 ||
        name.find("PARTICLE_") == 0 || name.find("ASSET_") == 0 ||
        name == "FRAME_WAIT" || name == "RANDOM_SEED" || 
        name == "KEY_CLEAR_BUFFER") {
        // These are void functions, but we need to return something
        // We'll return INT as a placeholder (value will be ignored)
        return VariableType::INT;
    }
    
    // Asset functions that return STRING
    if (name == "ASSET_GET_NAME" || name == "ASSET_GET_ERROR") {
        // These always return byte strings, not Unicode
        return VariableType::STRING;
    }
    
    // All other functions return FLOAT
    return VariableType::FLOAT;
}

int SemanticAnalyzer::getBuiltinArgCount(const std::string& name) const {
    std::string upper = name;
    std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
    auto it = m_builtinFunctions.find(upper);
    if (it != m_builtinFunctions.end()) {
        return it->second;
    }
    return 0;
}

void SemanticAnalyzer::loadFromCommandRegistry(const ModularCommands::CommandRegistry& registry) {
    // Get all commands and functions from the registry
    const auto& commands = registry.getAllCommands();
    
    for (const auto& pair : commands) {
        const std::string& name = pair.first;
        const ModularCommands::CommandDefinition& def = pair.second;
        
        // Add to builtin functions map with parameter count
        // Use required parameter count (commands may have optional parameters)
        int paramCount = static_cast<int>(def.getRequiredParameterCount());
        
        // Only add if not already present (don't override hardcoded core functions)
        if (m_builtinFunctions.find(name) == m_builtinFunctions.end()) {
            m_builtinFunctions[name] = paramCount;
        }
    }
}

// =============================================================================
// Constant Expression Evaluation (Compile-Time)
// =============================================================================

FasterBASIC::ConstantValue SemanticAnalyzer::evaluateConstantExpression(const Expression& expr) {
    switch (expr.getType()) {
        case ASTNodeType::EXPR_NUMBER: {
            const auto& number = static_cast<const NumberExpression&>(expr);
            double val = number.value;
            // Check if it's an integer
            if (val == std::floor(val) && val >= INT64_MIN && val <= INT64_MAX) {
                return static_cast<int64_t>(val);
            }
            return val;
        }
        
        case ASTNodeType::EXPR_STRING: {
            const auto& str = static_cast<const StringExpression&>(expr);
            return str.value;
        }
        
        case ASTNodeType::EXPR_BINARY:
            return evalConstantBinary(static_cast<const BinaryExpression&>(expr));
        
        case ASTNodeType::EXPR_UNARY:
            return evalConstantUnary(static_cast<const UnaryExpression&>(expr));
        
        case ASTNodeType::EXPR_FUNCTION_CALL:
            return evalConstantFunction(static_cast<const FunctionCallExpression&>(expr));
        
        case ASTNodeType::EXPR_VARIABLE:
            return evalConstantVariable(static_cast<const VariableExpression&>(expr));
        
        default:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Expression type not supported in constant evaluation",
                  expr.location);
            return static_cast<int64_t>(0);
    }
}

FasterBASIC::ConstantValue SemanticAnalyzer::evalConstantBinary(const BinaryExpression& expr) {
    FasterBASIC::ConstantValue left = evaluateConstantExpression(*expr.left);
    FasterBASIC::ConstantValue right = evaluateConstantExpression(*expr.right);
    
    // String concatenation
    if (expr.op == TokenType::PLUS && 
        (std::holds_alternative<std::string>(left) || std::holds_alternative<std::string>(right))) {
        std::string leftStr = std::holds_alternative<std::string>(left) ? 
            std::get<std::string>(left) : std::to_string(getConstantAsDouble(left));
        std::string rightStr = std::holds_alternative<std::string>(right) ? 
            std::get<std::string>(right) : std::to_string(getConstantAsDouble(right));
        return leftStr + rightStr;
    }
    
    // Numeric operations
    if (!isConstantNumeric(left) || !isConstantNumeric(right)) {
        error(SemanticErrorType::TYPE_MISMATCH,
              "Constant expression requires numeric operands",
              expr.location);
        return static_cast<int64_t>(0);
    }
    
    bool isInteger = (std::holds_alternative<int64_t>(left) && 
                      std::holds_alternative<int64_t>(right));
    
    switch (expr.op) {
        case TokenType::PLUS:
            if (isInteger) {
                return std::get<int64_t>(left) + std::get<int64_t>(right);
            }
            return getConstantAsDouble(left) + getConstantAsDouble(right);
        
        case TokenType::MINUS:
            if (isInteger) {
                return std::get<int64_t>(left) - std::get<int64_t>(right);
            }
            return getConstantAsDouble(left) - getConstantAsDouble(right);
        
        case TokenType::MULTIPLY:
            if (isInteger) {
                return std::get<int64_t>(left) * std::get<int64_t>(right);
            }
            return getConstantAsDouble(left) * getConstantAsDouble(right);
        
        case TokenType::DIVIDE:
            return getConstantAsDouble(left) / getConstantAsDouble(right);
        
        case TokenType::POWER:
            return std::pow(getConstantAsDouble(left), getConstantAsDouble(right));
        
        case TokenType::MOD:
            if (isInteger) {
                return std::get<int64_t>(left) % std::get<int64_t>(right);
            }
            return std::fmod(getConstantAsDouble(left), getConstantAsDouble(right));
        
        case TokenType::INT_DIVIDE: // Integer division
            return getConstantAsInt(left) / getConstantAsInt(right);
        
        case TokenType::AND:
            return getConstantAsInt(left) & getConstantAsInt(right);
        
        case TokenType::OR:
            return getConstantAsInt(left) | getConstantAsInt(right);
        
        case TokenType::XOR:
            return getConstantAsInt(left) ^ getConstantAsInt(right);
        
        default:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Operator not supported in constant expressions",
                  expr.location);
            return static_cast<int64_t>(0);
    }
}

FasterBASIC::ConstantValue SemanticAnalyzer::evalConstantUnary(const UnaryExpression& expr) {
    FasterBASIC::ConstantValue operand = evaluateConstantExpression(*expr.expr);
    
    switch (expr.op) {
        case TokenType::MINUS:
            if (std::holds_alternative<int64_t>(operand)) {
                return -std::get<int64_t>(operand);
            }
            return -std::get<double>(operand);
        
        case TokenType::PLUS:
            return operand;
        
        case TokenType::NOT:
            return ~getConstantAsInt(operand);
        
        default:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Unary operator not supported in constant expressions",
                  expr.location);
            return static_cast<int64_t>(0);
    }
}

FasterBASIC::ConstantValue SemanticAnalyzer::evalConstantFunction(const FunctionCallExpression& expr) {
    std::string funcName = expr.name;
    
    // Convert to uppercase for comparison
    for (auto& c : funcName) c = std::toupper(c);
    
    // Math functions (single argument)
    if (funcName == "ABS" && expr.arguments.size() == 1) {
        // ABS is treated as a floating-point builtin in codegen; keep the folded
        // result as double to avoid mixed int/double codegen paths (which caused
        // mismatched operand types in QBE for literals like ABS(5)).
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::fabs(getConstantAsDouble(arg));
    }
    
    if (funcName == "SIN" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::sin(getConstantAsDouble(arg));
    }
    
    if (funcName == "COS" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::cos(getConstantAsDouble(arg));
    }
    
    if (funcName == "TAN" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::tan(getConstantAsDouble(arg));
    }
    
    if (funcName == "ATN" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::atan(getConstantAsDouble(arg));
    }
    
    if (funcName == "EXP" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::exp(getConstantAsDouble(arg));
    }
    
    if (funcName == "LOG" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::log(getConstantAsDouble(arg));
    }
    
    if (funcName == "SQR" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return std::sqrt(getConstantAsDouble(arg));
    }
    
    if (funcName == "INT" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        return static_cast<int64_t>(std::floor(getConstantAsDouble(arg)));
    }
    
    if (funcName == "SGN" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        double val = getConstantAsDouble(arg);
        return static_cast<int64_t>(val > 0 ? 1 : (val < 0 ? -1 : 0));
    }
    
    if (funcName == "FIX" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        double val = getConstantAsDouble(arg);
        // FIX truncates toward zero (unlike INT which floors)
        return static_cast<int64_t>(val);
    }
    
    if (funcName == "CINT" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        double val = getConstantAsDouble(arg);
        // CINT rounds to nearest integer
        return static_cast<int64_t>(std::round(val));
    }
    
    // String functions
    if (funcName == "LEN" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        if (!std::holds_alternative<std::string>(arg)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "LEN requires string argument",
                  expr.location);
            return static_cast<int64_t>(0);
        }
        return static_cast<int64_t>(std::get<std::string>(arg).length());
    }
    
    if ((funcName == "LEFT$" || funcName == "LEFT") && expr.arguments.size() == 2) {
        FasterBASIC::ConstantValue str = evaluateConstantExpression(*expr.arguments[0]);
        FasterBASIC::ConstantValue len = evaluateConstantExpression(*expr.arguments[1]);
        if (!std::holds_alternative<std::string>(str)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "LEFT$ requires string argument",
                  expr.location);
            return std::string("");
        }
        int64_t n = getConstantAsInt(len);
        return std::get<std::string>(str).substr(0, std::max(int64_t(0), n));
    }
    
    if ((funcName == "RIGHT$" || funcName == "RIGHT") && expr.arguments.size() == 2) {
        FasterBASIC::ConstantValue str = evaluateConstantExpression(*expr.arguments[0]);
        FasterBASIC::ConstantValue len = evaluateConstantExpression(*expr.arguments[1]);
        if (!std::holds_alternative<std::string>(str)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "RIGHT$ requires string argument",
                  expr.location);
            return std::string("");
        }
        int64_t n = getConstantAsInt(len);
        std::string strVal = std::get<std::string>(str);
        size_t strLen = strVal.length();
        if (n >= static_cast<int64_t>(strLen)) {
            return str;
        }
        return strVal.substr(strLen - n);
    }
    
    if ((funcName == "MID$" || funcName == "MID") && 
        (expr.arguments.size() == 2 || expr.arguments.size() == 3)) {
        FasterBASIC::ConstantValue str = evaluateConstantExpression(*expr.arguments[0]);
        FasterBASIC::ConstantValue start = evaluateConstantExpression(*expr.arguments[1]);
        if (!std::holds_alternative<std::string>(str)) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "MID$ requires string argument",
                  expr.location);
            return std::string("");
        }
        int64_t startPos = getConstantAsInt(start) - 1; // BASIC is 1-indexed
        if (startPos < 0) startPos = 0;
        
        std::string strVal = std::get<std::string>(str);
        if (expr.arguments.size() == 3) {
            FasterBASIC::ConstantValue len = evaluateConstantExpression(*expr.arguments[2]);
            int64_t length = getConstantAsInt(len);
            return strVal.substr(startPos, length);
        } else {
            return strVal.substr(startPos);
        }
    }
    
    if ((funcName == "CHR$" || funcName == "CHR") && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        int64_t code = getConstantAsInt(arg);
        if (code < 0 || code > 255) {
            error(SemanticErrorType::TYPE_MISMATCH,
                  "CHR$ argument must be 0-255",
                  expr.location);
            return std::string("");
        }
        return std::string(1, static_cast<char>(code));
    }
    
    if (funcName == "STR$" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        if (std::holds_alternative<int64_t>(arg)) {
            return std::to_string(std::get<int64_t>(arg));
        } else if (std::holds_alternative<double>(arg)) {
            return std::to_string(std::get<double>(arg));
        }
        return arg; // Already a string
    }
    
    if (funcName == "VAL" && expr.arguments.size() == 1) {
        FasterBASIC::ConstantValue arg = evaluateConstantExpression(*expr.arguments[0]);
        if (!std::holds_alternative<std::string>(arg)) {
            return arg; // Already numeric
        }
        try {
            std::string strVal = std::get<std::string>(arg);
            // Try to parse as integer first
            size_t pos;
            int64_t intVal = std::stoll(strVal, &pos);
            if (pos == strVal.length()) {
                return intVal;
            }
            // Otherwise parse as double
            double dblVal = std::stod(strVal);
            return dblVal;
        } catch (...) {
            return 0.0;
        }
    }
    
    // Two-argument math functions
    if (funcName == "MIN" && expr.arguments.size() == 2) {
        FasterBASIC::ConstantValue arg1 = evaluateConstantExpression(*expr.arguments[0]);
        FasterBASIC::ConstantValue arg2 = evaluateConstantExpression(*expr.arguments[1]);
        double v1 = getConstantAsDouble(arg1);
        double v2 = getConstantAsDouble(arg2);
        return std::min(v1, v2);
    }
    
    if (funcName == "MAX" && expr.arguments.size() == 2) {
        FasterBASIC::ConstantValue arg1 = evaluateConstantExpression(*expr.arguments[0]);
        FasterBASIC::ConstantValue arg2 = evaluateConstantExpression(*expr.arguments[1]);
        double v1 = getConstantAsDouble(arg1);
        double v2 = getConstantAsDouble(arg2);
        return std::max(v1, v2);
    }
    
    error(SemanticErrorType::UNDEFINED_FUNCTION,
          "Function " + funcName + " not supported in constant expressions or wrong number of arguments",
          expr.location);
    return static_cast<int64_t>(0);
}

FasterBASIC::ConstantValue SemanticAnalyzer::evalConstantVariable(const VariableExpression& expr) {
    // Look up constant by name (case-insensitive)
    std::string lowerName = expr.name;
    std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
    
    auto it = m_symbolTable.constants.find(lowerName);
    if (it == m_symbolTable.constants.end()) {
        error(SemanticErrorType::UNDEFINED_VARIABLE,
              "Undefined constant: " + expr.name,
              expr.location);
        return static_cast<int64_t>(0);
    }
    
    const ConstantSymbol& sym = it->second;
    if (sym.type == ConstantSymbol::Type::INTEGER) {
        return sym.intValue;
    } else if (sym.type == ConstantSymbol::Type::DOUBLE) {
        return sym.doubleValue;
    } else {
        return sym.stringValue;
    }
}

bool SemanticAnalyzer::isConstantNumeric(const FasterBASIC::ConstantValue& val) {
    return std::holds_alternative<int64_t>(val) || std::holds_alternative<double>(val);
}

double SemanticAnalyzer::getConstantAsDouble(const FasterBASIC::ConstantValue& val) {
    if (std::holds_alternative<int64_t>(val)) {
        return static_cast<double>(std::get<int64_t>(val));
    } else if (std::holds_alternative<double>(val)) {
        return std::get<double>(val);
    }
    return 0.0;
}

int64_t SemanticAnalyzer::getConstantAsInt(const FasterBASIC::ConstantValue& val) {
    if (std::holds_alternative<int64_t>(val)) {
        return std::get<int64_t>(val);
    } else if (std::holds_alternative<double>(val)) {
        return static_cast<int64_t>(std::get<double>(val));
    }
    return 0;
}

bool SemanticAnalyzer::isConstantExpression(const Expression& expr) {
    // Check if an expression can be evaluated at compile time
    switch (expr.getType()) {
        case ASTNodeType::EXPR_NUMBER:
        case ASTNodeType::EXPR_STRING:
            return true;
        
        case ASTNodeType::EXPR_VARIABLE: {
            // Check if this variable is a declared constant (case-insensitive)
            const auto& varExpr = static_cast<const VariableExpression&>(expr);
            std::string lowerName = varExpr.name;
            std::transform(lowerName.begin(), lowerName.end(), lowerName.begin(), ::tolower);
            return m_symbolTable.constants.find(lowerName) != m_symbolTable.constants.end();
        }
        
        case ASTNodeType::EXPR_BINARY: {
            const auto& binExpr = static_cast<const BinaryExpression&>(expr);
            return isConstantExpression(*binExpr.left) && isConstantExpression(*binExpr.right);
        }
        
        case ASTNodeType::EXPR_UNARY: {
            const auto& unaryExpr = static_cast<const UnaryExpression&>(expr);
            return isConstantExpression(*unaryExpr.expr);
        }
        
        case ASTNodeType::EXPR_FUNCTION_CALL: {
            const auto& funcExpr = static_cast<const FunctionCallExpression&>(expr);
            // Check if all arguments are constant
            for (const auto& arg : funcExpr.arguments) {
                if (!isConstantExpression(*arg)) {
                    return false;
                }
            }
            return true;
        }
        
        default:
            return false;
    }
}

// =============================================================================
// Function Scope Variable Validation
// =============================================================================

void SemanticAnalyzer::validateVariableInFunction(const std::string& varName, 
                                                    const SourceLocation& loc) {
    if (!m_currentFunctionScope.inFunction) {
        // Not in a function - use normal variable lookup
        useVariable(varName, loc);
        return;
    }
    
    // Allow FUNCTION to assign to its own name (for return value)
    if (varName == m_currentFunctionScope.functionName) {
        return;
    }
    
    // Check if variable is declared in function scope (try bare name first)
    if (m_currentFunctionScope.parameters.count(varName) ||
        m_currentFunctionScope.localVariables.count(varName) ||
        m_currentFunctionScope.sharedVariables.count(varName)) {
        // Variable is properly declared
        return;
    }
    
    // Try with type suffixes (LOCAL i AS INTEGER stores as i_INT, but usage might be just 'i')
    const std::string suffixes[] = {"_INT", "_DOUBLE", "_FLOAT", "_STRING", "_LONG", "_BYTE", "_SHORT"};
    for (const auto& suffix : suffixes) {
        std::string mangledName = varName + suffix;
        if (m_currentFunctionScope.parameters.count(mangledName) ||
            m_currentFunctionScope.localVariables.count(mangledName) ||
            m_currentFunctionScope.sharedVariables.count(mangledName)) {
            // Found with mangled name
            return;
        }
    }
    
    // Variable not declared - ERROR!
    error(SemanticErrorType::UNDEFINED_VARIABLE,
          "Variable '" + varName + "' is not declared in " + 
          m_currentFunctionScope.functionName + ". " +
          "Use LOCAL or SHARED to declare it.",
          loc);
}

void SemanticAnalyzer::fixSymbolTableMangling() {
    std::cerr << "\n=== Fixing Symbol Table Mangling ===" << std::endl;
    
    // Build a map of old name -> new name for updating function scopes
    std::map<std::string, std::string> renames;
    
    for (auto& [key, varSym] : m_symbolTable.variables) {
        std::string expectedSuffix;
        bool needsSuffix = true;
        
        // Determine expected suffix based on type
        switch (varSym.typeDesc.baseType) {
            case BaseType::INTEGER:
                expectedSuffix = "_INT";
                break;
            case BaseType::LONG:
                expectedSuffix = "_LONG";
                break;
            case BaseType::SHORT:
                expectedSuffix = "_SHORT";
                break;
            case BaseType::BYTE:
                expectedSuffix = "_BYTE";
                break;
            case BaseType::DOUBLE:
                expectedSuffix = "_DOUBLE";
                break;
            case BaseType::SINGLE:
                expectedSuffix = "_FLOAT";
                break;
            case BaseType::STRING:
            case BaseType::UNICODE:
                expectedSuffix = "_STRING";
                break;
            case BaseType::USER_DEFINED:
                needsSuffix = false;  // UDTs don't need suffix
                break;
            default:
                needsSuffix = false;
                break;
        }
        
        if (needsSuffix) {
            // Check if variable name has the expected suffix
            bool hasSuffix = (varSym.name.length() > expectedSuffix.length() &&
                              varSym.name.substr(varSym.name.length() - expectedSuffix.length()) == expectedSuffix);
            
            if (!hasSuffix) {
                // Need to add suffix
                std::string oldName = varSym.name;
                std::string newName = varSym.name + expectedSuffix;
                std::cerr << "  Renaming: '" << oldName << "' -> '" << newName << "'" << std::endl;
                renames[oldName] = newName;
                varSym.name = newName;  // Update the symbol's name
            }
        }
    }
    
    // Update function scopes: We need to update the localVariables sets in all functions
    // For now, rebuild the localVariables set from the symbol table
    // (This is a simple approach that works for the current scope model)
    for (auto& [key, varSym] : m_symbolTable.variables) {
        if (varSym.scope.isFunction() && !varSym.isGlobal) {
            // This is a local variable - ensure it's in the function's localVariables set
            // Note: We can't directly access function scopes here, but validateVariableInFunction
            // will need to be updated to handle mangled names
        }
    }
    
    std::cerr << "  Fixed " << renames.size() << " variable names" << std::endl;
    std::cerr << "=== End Symbol Table Mangling Fix ===\n" << std::endl;
}

// =============================================================================
// TypeDescriptor-Based Type Inference (Phase 2)
// =============================================================================

TypeDescriptor SemanticAnalyzer::inferExpressionTypeD(const Expression& expr) {
    switch (expr.getType()) {
        case ASTNodeType::EXPR_NUMBER: {
            // Number literals default to DOUBLE unless they have a suffix
            const auto* numExpr = static_cast<const NumberExpression*>(&expr);
            // Check if it's an integer literal (no decimal point)
            if (numExpr->value == static_cast<int64_t>(numExpr->value)) {
                // Integer literal - infer based on magnitude
                int64_t val = static_cast<int64_t>(numExpr->value);
                if (val >= -128 && val <= 127) {
                    return TypeDescriptor(BaseType::BYTE);
                } else if (val >= -32768 && val <= 32767) {
                    return TypeDescriptor(BaseType::SHORT);
                } else if (val >= INT32_MIN && val <= INT32_MAX) {
                    return TypeDescriptor(BaseType::INTEGER);
                } else {
                    return TypeDescriptor(BaseType::LONG);
                }
            }
            return TypeDescriptor(BaseType::DOUBLE);
        }
        
        case ASTNodeType::EXPR_STRING: {
            // String literals: detect based on content if in DETECTSTRING mode
            const StringExpression* strExpr = static_cast<const StringExpression*>(&expr);
            BaseType stringType = m_symbolTable.getStringTypeForLiteral(strExpr->hasNonASCII);
            return TypeDescriptor(stringType);
        }
        
        case ASTNodeType::EXPR_VARIABLE:
            return inferVariableTypeD(static_cast<const VariableExpression&>(expr));
        
        case ASTNodeType::EXPR_BINARY:
            return inferBinaryExpressionTypeD(static_cast<const BinaryExpression&>(expr));
        
        case ASTNodeType::EXPR_UNARY:
            return inferUnaryExpressionTypeD(static_cast<const UnaryExpression&>(expr));
        
        case ASTNodeType::EXPR_ARRAY_ACCESS:
            return inferArrayAccessTypeD(static_cast<const ArrayAccessExpression&>(expr));
        
        case ASTNodeType::EXPR_FUNCTION_CALL:
            // Check if it's a registry function
            if (expr.getType() == ASTNodeType::EXPR_FUNCTION_CALL) {
                const auto* funcCall = static_cast<const FunctionCallExpression*>(&expr);
                // RegistryFunctionExpression is a subclass, check if we can handle it
                const auto* regFunc = dynamic_cast<const RegistryFunctionExpression*>(&expr);
                if (regFunc) {
                    return inferRegistryFunctionTypeD(*regFunc);
                }
                return inferFunctionCallTypeD(*funcCall);
            }
            return inferFunctionCallTypeD(static_cast<const FunctionCallExpression&>(expr));
        
        case ASTNodeType::EXPR_MEMBER_ACCESS:
            return inferMemberAccessTypeD(static_cast<const MemberAccessExpression&>(expr));
        
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

TypeDescriptor SemanticAnalyzer::inferBinaryExpressionTypeD(const BinaryExpression& expr) {
    TypeDescriptor leftType = inferExpressionTypeD(*expr.left);
    TypeDescriptor rightType = inferExpressionTypeD(*expr.right);
    
    // String operations
    if (leftType.isString() || rightType.isString()) {
        if (expr.op == TokenType::PLUS) {
            // String concatenation - result is UNICODE if either operand is UNICODE
            if (leftType.baseType == BaseType::UNICODE || rightType.baseType == BaseType::UNICODE) {
                return TypeDescriptor(BaseType::UNICODE);
            }
            return TypeDescriptor(BaseType::STRING);
        }
        // String comparison operators return INTEGER
        if (expr.op == TokenType::EQUAL || expr.op == TokenType::NOT_EQUAL ||
            expr.op == TokenType::LESS_THAN || expr.op == TokenType::GREATER_THAN ||
            expr.op == TokenType::LESS_EQUAL || expr.op == TokenType::GREATER_EQUAL) {
            return TypeDescriptor(BaseType::INTEGER);
        }
    }
    
    // Comparison operators return INTEGER
    if (expr.op == TokenType::EQUAL || expr.op == TokenType::NOT_EQUAL ||
        expr.op == TokenType::LESS_THAN || expr.op == TokenType::GREATER_THAN ||
        expr.op == TokenType::LESS_EQUAL || expr.op == TokenType::GREATER_EQUAL) {
        return TypeDescriptor(BaseType::INTEGER);
    }
    
    // Logical operators return INTEGER
    if (expr.op == TokenType::AND || expr.op == TokenType::OR || expr.op == TokenType::XOR) {
        return TypeDescriptor(BaseType::INTEGER);
    }
    
    // Arithmetic operators - promote types
    return promoteTypesD(leftType, rightType);
}

TypeDescriptor SemanticAnalyzer::inferUnaryExpressionTypeD(const UnaryExpression& expr) {
    TypeDescriptor exprType = inferExpressionTypeD(*expr.expr);
    
    if (expr.op == TokenType::NOT) {
        return TypeDescriptor(BaseType::INTEGER);
    }
    
    // Unary + or - preserve type
    return exprType;
}

TypeDescriptor SemanticAnalyzer::inferVariableTypeD(const VariableExpression& expr) {
    // Check function scope
    if (m_currentFunctionScope.inFunction) {
        if (m_currentFunctionScope.parameters.count(expr.name) ||
            m_currentFunctionScope.localVariables.count(expr.name)) {
            // Try to find the variable in the symbol table with proper scope
            const VariableSymbol* paramSym = lookupVariableScoped(expr.name, m_currentFunctionScope.functionName);
            if (paramSym) {
                return paramSym->typeDesc;
            }
            // Try suffixed variants (DIM x AS INTEGER stores as x_INT)
            {
                static const char* suffixes[] = {"_INT", "_LONG", "_DOUBLE", "_FLOAT", "_STRING", "_BYTE", "_SHORT"};
                Scope funcScope = Scope::makeFunction(m_currentFunctionScope.functionName);
                for (const char* s : suffixes) {
                    const VariableSymbol* suffixed = m_symbolTable.lookupVariable(expr.name + s, funcScope);
                    if (suffixed) {
                        return suffixed->typeDesc;
                    }
                }
            }
            // Fall back to name-based inference
            return inferTypeFromNameD(expr.name);
        }
    }
    
    // Look up in symbol table
    auto* varSym = lookupVariable(expr.name);
    if (varSym) {
        // Use new TypeDescriptor field directly
        return varSym->typeDesc;
    }
    
    // Infer from name
    return inferTypeFromNameD(expr.name);
}

TypeDescriptor SemanticAnalyzer::inferArrayAccessTypeD(const ArrayAccessExpression& expr) {
    std::string mangledName = mangleNameWithSuffix(expr.name, expr.typeSuffix);
    
    // Check if it's a function call
    if (m_symbolTable.functions.find(mangledName) != m_symbolTable.functions.end()) {
        const auto& funcSym = m_symbolTable.functions.at(mangledName);
        return funcSym.returnTypeDesc;
    }
    
    // Check if this is an object with subscript operator (like hashmap)
    auto* varSym = lookupVariable(expr.name);
    auto& registry = getRuntimeObjectRegistry();
    
    if (varSym && registry.isObjectType(varSym->typeDesc)) {
        auto* objDesc = registry.getObjectType(varSym->typeDesc.objectTypeName);
        if (objDesc && objDesc->hasSubscriptOperator) {
            // Object subscript operations return the value type (e.g., STRING for hashmap)
            // For now, hashmap values are always strings
            return TypeDescriptor(BaseType::STRING);
        }
    }
    
    // Check array symbol
    auto* arraySym = lookupArray(expr.name);
    if (arraySym) {
        // Use new TypeDescriptor field directly
        return arraySym->elementTypeDesc;
    }
    
    // Infer from name
    return inferTypeFromNameD(expr.name);
}

TypeDescriptor SemanticAnalyzer::inferFunctionCallTypeD(const FunctionCallExpression& expr) {
    auto* sym = lookupFunction(expr.name);
    if (sym) {
        // Use new TypeDescriptor field directly
        return sym->returnTypeDesc;
    }
    
    // Check built-in functions
    if (isBuiltinFunction(expr.name)) {
        return legacyTypeToDescriptor(getBuiltinReturnType(expr.name));
    }
    
    return TypeDescriptor(BaseType::UNKNOWN);
}

TypeDescriptor SemanticAnalyzer::inferRegistryFunctionTypeD(const RegistryFunctionExpression& expr) {
    switch (expr.returnType) {
        case FasterBASIC::ModularCommands::ReturnType::INT:
            return TypeDescriptor(BaseType::INTEGER);
        case FasterBASIC::ModularCommands::ReturnType::FLOAT:
            return TypeDescriptor(BaseType::DOUBLE);  // FLOAT in registry is treated as DOUBLE
        case FasterBASIC::ModularCommands::ReturnType::STRING:
            // For variable member access, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
        case FasterBASIC::ModularCommands::ReturnType::VOID:
            return TypeDescriptor(BaseType::VOID);
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

TypeDescriptor SemanticAnalyzer::inferMemberAccessTypeD(const MemberAccessExpression& expr) {
    // Determine base object type
    TypeDescriptor baseType = TypeDescriptor(BaseType::UNKNOWN);
    std::string baseTypeName;
    
    if (expr.object->getType() == ASTNodeType::EXPR_VARIABLE) {
        const auto* varExpr = static_cast<const VariableExpression*>(expr.object.get());
        auto* varSym = lookupVariable(varExpr->name);
        if (varSym && varSym->typeDesc.baseType == BaseType::USER_DEFINED) {
            baseTypeName = varSym->typeName;
            baseType.baseType = BaseType::USER_DEFINED;
            baseType.udtName = baseTypeName;
            baseType.udtTypeId = m_symbolTable.getTypeId(baseTypeName);
        }
    } else if (expr.object->getType() == ASTNodeType::EXPR_ARRAY_ACCESS) {
        const auto* arrExpr = static_cast<const ArrayAccessExpression*>(expr.object.get());
        auto* arrSym = lookupArray(arrExpr->name);
        if (arrSym && arrSym->elementTypeDesc.baseType == BaseType::USER_DEFINED) {
            baseTypeName = arrSym->asTypeName;
            baseType.baseType = BaseType::USER_DEFINED;
            baseType.udtName = baseTypeName;
            baseType.udtTypeId = m_symbolTable.getTypeId(baseTypeName);
        }
    } else if (expr.object->getType() == ASTNodeType::EXPR_MEMBER_ACCESS) {
        // Nested member access (e.g., O.Item.Value)
        // Recursively get the type of the base member access
        TypeDescriptor nestedDesc = inferMemberAccessTypeD(
            static_cast<const MemberAccessExpression&>(*expr.object));
        if (nestedDesc.baseType == BaseType::USER_DEFINED && !nestedDesc.udtName.empty()) {
            baseTypeName = nestedDesc.udtName;
            baseType = nestedDesc;
        }
    }
    
    // Look up field type
    if (!baseTypeName.empty()) {
        auto* typeSym = lookupType(baseTypeName);
        if (typeSym) {
            const auto* field = typeSym->findField(expr.memberName);
            if (field) {
                // Use new TypeDescriptor field directly
                return field->typeDesc;
            }
        }
    }
    
    return TypeDescriptor(BaseType::UNKNOWN);
}

// =============================================================================
// Type Coercion and Checking
// =============================================================================

SemanticAnalyzer::CoercionResult SemanticAnalyzer::checkCoercion(
    const TypeDescriptor& from, const TypeDescriptor& to) const {
    
    // Identical types
    if (from == to) {
        return CoercionResult::IDENTICAL;
    }
    
    // Cannot coerce from/to UNKNOWN
    if (from.baseType == BaseType::UNKNOWN || to.baseType == BaseType::UNKNOWN) {
        return CoercionResult::INCOMPATIBLE;
    }
    
    // String to string conversions
    if (from.isString() && to.isString()) {
        // STRING <-> UNICODE conversion is safe (runtime handles it)
        return CoercionResult::IMPLICIT_SAFE;
    }
    
    // Numeric conversions
    if (from.isNumeric() && to.isNumeric()) {
        return checkNumericCoercion(from, to);
    }
    
    // String <-> Numeric requires explicit conversion
    if ((from.isString() && to.isNumeric()) || (from.isNumeric() && to.isString())) {
        return CoercionResult::EXPLICIT_REQUIRED;
    }
    
    // UDT conversions - only identical UDT types are compatible
    if (from.isUserDefined() || to.isUserDefined()) {
        return CoercionResult::INCOMPATIBLE;
    }
    
    return CoercionResult::INCOMPATIBLE;
}

SemanticAnalyzer::CoercionResult SemanticAnalyzer::checkNumericCoercion(
    const TypeDescriptor& from, const TypeDescriptor& to) const {
    
    if (from.isInteger() && to.isInteger()) {
        int fromWidth = from.getBitWidth();
        int toWidth = to.getBitWidth();
        
        if (fromWidth < toWidth) {
            // Widening conversion - always safe
            return CoercionResult::IMPLICIT_SAFE;
        } else if (fromWidth == toWidth) {
            // Same width - check signed/unsigned
            if (from.isUnsigned() == to.isUnsigned()) {
                return CoercionResult::IDENTICAL;
            }
            // Signed <-> unsigned of same width is lossy
            return CoercionResult::IMPLICIT_LOSSY;
        } else {
            // Narrowing conversion - lossy
            return CoercionResult::IMPLICIT_LOSSY;
        }
    }
    
    if (from.isInteger() && to.isFloat()) {
        // Integer to float is generally safe (may lose precision for very large integers)
        if (from.getBitWidth() <= 32 && to.baseType == BaseType::DOUBLE) {
            return CoercionResult::IMPLICIT_SAFE;
        }
        return CoercionResult::IMPLICIT_LOSSY;
    }
    
    if (from.isFloat() && to.isInteger()) {
        // Float to integer truncates - requires explicit conversion
        return CoercionResult::EXPLICIT_REQUIRED;
    }
    
    if (from.isFloat() && to.isFloat()) {
        if (from.baseType == BaseType::SINGLE && to.baseType == BaseType::DOUBLE) {
            // SINGLE -> DOUBLE widening is safe
            return CoercionResult::IMPLICIT_SAFE;
        } else if (from.baseType == BaseType::DOUBLE && to.baseType == BaseType::SINGLE) {
            // DOUBLE -> SINGLE narrowing is lossy
            return CoercionResult::IMPLICIT_LOSSY;
        }
    }
    
    return CoercionResult::INCOMPATIBLE;
}

bool SemanticAnalyzer::validateAssignment(
    const TypeDescriptor& lhs, const TypeDescriptor& rhs, const SourceLocation& loc) {
    
    CoercionResult result = checkCoercion(rhs, lhs);
    
    switch (result) {
        case CoercionResult::IDENTICAL:
        case CoercionResult::IMPLICIT_SAFE:
            return true;
        
        case CoercionResult::IMPLICIT_LOSSY:
            warning("Implicit narrowing conversion from " + rhs.toString() + 
                   " to " + lhs.toString() + " may lose precision", loc);
            return true;
        
        case CoercionResult::EXPLICIT_REQUIRED:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Cannot implicitly convert " + rhs.toString() + " to " + lhs.toString() +
                  ". Use explicit conversion function (CINT, CLNG, CSNG, CDBL, STR$, VAL).",
                  loc);
            return false;
        
        case CoercionResult::INCOMPATIBLE:
            error(SemanticErrorType::TYPE_MISMATCH,
                  "Incompatible types: cannot convert " + rhs.toString() + " to " + lhs.toString(),
                  loc);
            return false;
    }
    
    return false;
}

TypeDescriptor SemanticAnalyzer::promoteTypesD(
    const TypeDescriptor& left, const TypeDescriptor& right) const {
    
    // If either is DOUBLE, result is DOUBLE
    if (left.baseType == BaseType::DOUBLE || right.baseType == BaseType::DOUBLE) {
        return TypeDescriptor(BaseType::DOUBLE);
    }
    
    // If either is SINGLE, result is SINGLE
    if (left.baseType == BaseType::SINGLE || right.baseType == BaseType::SINGLE) {
        return TypeDescriptor(BaseType::SINGLE);
    }
    
    // Integer promotion: use the wider type
    int leftWidth = left.getBitWidth();
    int rightWidth = right.getBitWidth();
    
    if (leftWidth >= rightWidth) {
        return left;
    } else {
        return right;
    }
}

// =============================================================================
// Type Inference Helpers
// =============================================================================

TypeDescriptor SemanticAnalyzer::inferTypeFromSuffixD(TokenType suffix) const {
    switch (suffix) {
        case TokenType::TYPE_INT:
            return TypeDescriptor(BaseType::INTEGER);
        case TokenType::TYPE_FLOAT:
            return TypeDescriptor(BaseType::SINGLE);
        case TokenType::TYPE_DOUBLE:
            return TypeDescriptor(BaseType::DOUBLE);
        case TokenType::TYPE_STRING:
            // For array member access, use global mode
            return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
                TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
        case TokenType::TYPE_BYTE:
            return TypeDescriptor(BaseType::BYTE);
        case TokenType::TYPE_SHORT:
            return TypeDescriptor(BaseType::SHORT);
        default:
            return TypeDescriptor(BaseType::UNKNOWN);
    }
}

TypeDescriptor SemanticAnalyzer::inferTypeFromSuffixD(char suffix) const {
    BaseType type = baseTypeFromSuffix(suffix);
    if (type == BaseType::STRING && m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) {
        type = BaseType::UNICODE;
    }
    return TypeDescriptor(type);
}

TypeDescriptor SemanticAnalyzer::inferTypeFromNameD(const std::string& name) const {
    if (name.empty()) {
        // For 64-bit systems (ARM64/x86-64), DOUBLE is the natural numeric type
        return TypeDescriptor(BaseType::DOUBLE);
    }
    
    // Check for normalized suffixes (e.g., A_STRING, B_INT)
    if (name.length() > 7 && name.substr(name.length() - 7) == "_STRING") {
        // For string coercion, use global mode
        return (m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) ?
            TypeDescriptor(BaseType::UNICODE) : TypeDescriptor(BaseType::STRING);
    }
    if (name.length() > 4 && name.substr(name.length() - 4) == "_INT") {
        return TypeDescriptor(BaseType::INTEGER);
    }
    if (name.length() > 7 && name.substr(name.length() - 7) == "_DOUBLE") {
        return TypeDescriptor(BaseType::DOUBLE);
    }
    if (name.length() > 6 && name.substr(name.length() - 6) == "_FLOAT") {
        return TypeDescriptor(BaseType::SINGLE);
    }
    if (name.length() > 5 && name.substr(name.length() - 5) == "_LONG") {
        return TypeDescriptor(BaseType::LONG);
    }
    if (name.length() > 5 && name.substr(name.length() - 5) == "_BYTE") {
        return TypeDescriptor(BaseType::BYTE);
    }
    if (name.length() > 6 && name.substr(name.length() - 6) == "_SHORT") {
        return TypeDescriptor(BaseType::SHORT);
    }
    
    // Check for type suffix characters
    char lastChar = name.back();
    BaseType type = baseTypeFromSuffix(lastChar);
    if (type != BaseType::UNKNOWN) {
        if (type == BaseType::STRING && m_symbolTable.stringMode == CompilerOptions::StringMode::UNICODE) {
            type = BaseType::UNICODE;
        }
        return TypeDescriptor(type);
    }
    
    // No suffix - default to DOUBLE for numeric (natural type for 64-bit systems)
    return TypeDescriptor(BaseType::DOUBLE);
}

} // namespace FasterBASIC