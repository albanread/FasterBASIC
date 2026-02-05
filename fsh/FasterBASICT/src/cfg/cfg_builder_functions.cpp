//
// cfg_builder_functions.cpp
// FasterBASIC - Control Flow Graph Builder Function Handlers (V2)
//
// Implements CFG construction for SUB, FUNCTION, and DEF FN definitions.
// Each function/subroutine gets its own separate ControlFlowGraph.
//
// Part of modular CFG builder split (February 2026).
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>

namespace FasterBASIC {

// =============================================================================
// FUNCTION Builder
// =============================================================================
//
// Build a complete CFG for a FUNCTION definition.
// FUNCTION has a return value and uses FUNCTION name = value syntax or RETURN value
//
ControlFlowGraph* CFGBuilder::buildFunction(const FunctionStatement& stmt) {
    if (m_debugMode) {
        std::cout << "[CFG] Building FUNCTION " << stmt.functionName 
                  << " with " << stmt.parameters.size() << " parameters" << std::endl;
    }
    
    // Create a new CFG for this function
    ControlFlowGraph* funcCFG = new ControlFlowGraph(stmt.functionName);
    
    // Store function metadata
    funcCFG->functionName = stmt.functionName;
    funcCFG->parameters = stmt.parameters;
    
    // Convert parameter types from TokenType to VariableType
    funcCFG->parameterTypes.clear();
    for (size_t i = 0; i < stmt.parameterTypes.size(); ++i) {
        TokenType tokenType = stmt.parameterTypes[i];
        VariableType varType = VariableType::INT;  // Default
        
        switch (tokenType) {
            case TokenType::PERCENT:
            case TokenType::TYPE_INT:
                varType = VariableType::INT;
                break;
            case TokenType::AMPERSAND:
                varType = VariableType::INT;  // Long maps to INT
                break;
            case TokenType::EXCLAMATION:
                varType = VariableType::FLOAT;
                break;
            case TokenType::HASH:
            case TokenType::TYPE_DOUBLE:
                varType = VariableType::DOUBLE;
                break;
            case TokenType::TYPE_STRING:
                varType = VariableType::STRING;
                break;
            default:
                varType = VariableType::INT;
                break;
        }
        
        funcCFG->parameterTypes.push_back(varType);
    }
    
    // Determine return type from suffix
    VariableType returnType = VariableType::INT;  // Default
    switch (stmt.returnTypeSuffix) {
        case TokenType::PERCENT:
            returnType = VariableType::INT;
            break;
        case TokenType::AMPERSAND:
            returnType = VariableType::INT;  // Long maps to INT
            break;
        case TokenType::EXCLAMATION:
            returnType = VariableType::FLOAT;
            break;
        case TokenType::HASH:
            returnType = VariableType::DOUBLE;
            break;
        case TokenType::TYPE_STRING:
            returnType = VariableType::STRING;
            break;
        default:
            returnType = VariableType::INT;
            break;
    }
    funcCFG->returnType = returnType;
    
    // Save current CFG state and switch to function CFG
    ControlFlowGraph* savedCFG = m_cfg;
    int savedNextBlockId = m_nextBlockId;
    auto savedLineNumberToBlock = m_lineNumberToBlock;
    auto savedLabelToBlock = m_labelToBlock;
    auto savedDeferredEdges = m_deferredEdges;
    auto savedJumpTargets = m_jumpTargets;
    BasicBlock* savedEntryBlock = m_entryBlock;
    BasicBlock* savedExitBlock = m_exitBlock;
    
    // Switch to building the function CFG
    m_cfg = funcCFG;
    m_nextBlockId = 0;
    m_lineNumberToBlock.clear();
    m_labelToBlock.clear();
    m_deferredEdges.clear();
    m_jumpTargets.clear();
    
    // Pre-scan function body for jump targets
    collectJumpTargets(stmt.body);
    
    // Create function entry block
    m_entryBlock = createBlock("Entry");
    funcCFG->entryBlock = m_entryBlock->id;
    
    // Create function exit block
    m_exitBlock = createBlock("Exit");
    funcCFG->exitBlock = m_exitBlock->id;
    
    // Create subroutine context for RETURN handling
    SubroutineContext subCtx;
    subCtx.returnBlockId = m_exitBlock->id;
    subCtx.outerSub = nullptr;
    
    // Build the function body
    BasicBlock* bodyExit = buildStatementRange(
        stmt.body,
        m_entryBlock,
        nullptr,    // No loop context
        nullptr,    // No select context
        nullptr,    // No try context
        &subCtx     // Subroutine context for RETURN
    );
    
    // Wire body exit to function exit (if not already terminated)
    if (bodyExit && !isTerminated(bodyExit)) {
        addUnconditionalEdge(bodyExit->id, m_exitBlock->id);
    }
    
    // Resolve deferred edges
    resolveDeferredEdges();
    
    if (m_debugMode) {
        std::cout << "[CFG] FUNCTION " << stmt.functionName << " built successfully" << std::endl;
        std::cout << "[CFG]   Blocks: " << funcCFG->blocks.size() << std::endl;
        std::cout << "[CFG]   Edges: " << funcCFG->edges.size() << std::endl;
    }
    
    // Restore previous CFG state
    m_cfg = savedCFG;
    m_nextBlockId = savedNextBlockId;
    m_lineNumberToBlock = savedLineNumberToBlock;
    m_labelToBlock = savedLabelToBlock;
    m_deferredEdges = savedDeferredEdges;
    m_jumpTargets = savedJumpTargets;
    m_entryBlock = savedEntryBlock;
    m_exitBlock = savedExitBlock;
    
    return funcCFG;
}

// =============================================================================
// SUB Builder
// =============================================================================
//
// Build a complete CFG for a SUB definition.
// SUB is like FUNCTION but has no return value
//
ControlFlowGraph* CFGBuilder::buildSub(const SubStatement& stmt) {
    if (m_debugMode) {
        std::cout << "[CFG] Building SUB " << stmt.subName 
                  << " with " << stmt.parameters.size() << " parameters" << std::endl;
    }
    
    // Create a new CFG for this subroutine
    ControlFlowGraph* subCFG = new ControlFlowGraph(stmt.subName);
    
    // Store subroutine metadata
    subCFG->functionName = stmt.subName;
    subCFG->parameters = stmt.parameters;
    
    // Convert parameter types from TokenType to VariableType
    subCFG->parameterTypes.clear();
    for (size_t i = 0; i < stmt.parameterTypes.size(); ++i) {
        TokenType tokenType = stmt.parameterTypes[i];
        VariableType varType = VariableType::INT;  // Default
        
        switch (tokenType) {
            case TokenType::PERCENT:
            case TokenType::TYPE_INT:
                varType = VariableType::INT;
                break;
            case TokenType::AMPERSAND:
                varType = VariableType::INT;  // Long maps to INT
                break;
            case TokenType::EXCLAMATION:
                varType = VariableType::FLOAT;
                break;
            case TokenType::HASH:
            case TokenType::TYPE_DOUBLE:
                varType = VariableType::DOUBLE;
                break;
            case TokenType::TYPE_STRING:
                varType = VariableType::STRING;
                break;
            default:
                varType = VariableType::INT;
                break;
        }
        
        subCFG->parameterTypes.push_back(varType);
    }
    
    // SUBs have no return type
    subCFG->returnType = VariableType::VOID;
    
    // Save current CFG state and switch to subroutine CFG
    ControlFlowGraph* savedCFG = m_cfg;
    int savedNextBlockId = m_nextBlockId;
    auto savedLineNumberToBlock = m_lineNumberToBlock;
    auto savedLabelToBlock = m_labelToBlock;
    auto savedDeferredEdges = m_deferredEdges;
    auto savedJumpTargets = m_jumpTargets;
    BasicBlock* savedEntryBlock = m_entryBlock;
    BasicBlock* savedExitBlock = m_exitBlock;
    
    // Switch to building the subroutine CFG
    m_cfg = subCFG;
    m_nextBlockId = 0;
    m_lineNumberToBlock.clear();
    m_labelToBlock.clear();
    m_deferredEdges.clear();
    m_jumpTargets.clear();
    
    // Pre-scan subroutine body for jump targets
    collectJumpTargets(stmt.body);
    
    // Create subroutine entry block
    m_entryBlock = createBlock("Entry");
    subCFG->entryBlock = m_entryBlock->id;
    
    // Create subroutine exit block
    m_exitBlock = createBlock("Exit");
    subCFG->exitBlock = m_exitBlock->id;
    
    // Create subroutine context for RETURN handling
    SubroutineContext subCtx;
    subCtx.returnBlockId = m_exitBlock->id;
    subCtx.outerSub = nullptr;
    
    // Build the subroutine body
    BasicBlock* bodyExit = buildStatementRange(
        stmt.body,
        m_entryBlock,
        nullptr,    // No loop context
        nullptr,    // No select context
        nullptr,    // No try context
        &subCtx     // Subroutine context for RETURN
    );
    
    // Wire body exit to subroutine exit (if not already terminated)
    if (bodyExit && !isTerminated(bodyExit)) {
        addUnconditionalEdge(bodyExit->id, m_exitBlock->id);
    }
    
    // Resolve deferred edges
    resolveDeferredEdges();
    
    if (m_debugMode) {
        std::cout << "[CFG] SUB " << stmt.subName << " built successfully" << std::endl;
        std::cout << "[CFG]   Blocks: " << subCFG->blocks.size() << std::endl;
        std::cout << "[CFG]   Edges: " << subCFG->edges.size() << std::endl;
    }
    
    // Restore previous CFG state
    m_cfg = savedCFG;
    m_nextBlockId = savedNextBlockId;
    m_lineNumberToBlock = savedLineNumberToBlock;
    m_labelToBlock = savedLabelToBlock;
    m_deferredEdges = savedDeferredEdges;
    m_jumpTargets = savedJumpTargets;
    m_entryBlock = savedEntryBlock;
    m_exitBlock = savedExitBlock;
    
    return subCFG;
}

// =============================================================================
// DEF FN Builder
// =============================================================================
//
// Build a complete CFG for a DEF FN definition.
// DEF FN is a single-expression inline function (classic BASIC style)
//
ControlFlowGraph* CFGBuilder::buildDefFn(const DefStatement& stmt) {
    if (m_debugMode) {
        std::cout << "[CFG] Building DEF FN" << stmt.functionName 
                  << " with " << stmt.parameters.size() << " parameters" << std::endl;
    }
    
    // Create a new CFG for this inline function
    ControlFlowGraph* defCFG = new ControlFlowGraph("FN" + stmt.functionName);
    
    // Store function metadata
    defCFG->functionName = "FN" + stmt.functionName;
    defCFG->parameters = stmt.parameters;
    defCFG->defStatement = &stmt;
    
    // Convert parameter types from TokenType to VariableType
    defCFG->parameterTypes.clear();
    for (size_t i = 0; i < stmt.parameterSuffixes.size(); ++i) {
        TokenType tokenType = stmt.parameterSuffixes[i];
        VariableType varType = VariableType::INT;  // Default
        
        switch (tokenType) {
            case TokenType::PERCENT:
                varType = VariableType::INT;
                break;
            case TokenType::AMPERSAND:
                varType = VariableType::INT;  // Long maps to INT
                break;
            case TokenType::EXCLAMATION:
                varType = VariableType::FLOAT;
                break;
            case TokenType::HASH:
                varType = VariableType::DOUBLE;
                break;
        case TokenType::TYPE_STRING:
                varType = VariableType::STRING;
                break;
            default:
                varType = VariableType::INT;
                break;
        }
        
        defCFG->parameterTypes.push_back(varType);
    }
    
    // Return type is inferred from function name suffix
    // For now, default to DOUBLE (classic BASIC DEF FN behavior)
    defCFG->returnType = VariableType::DOUBLE;
    
    // Save current CFG state
    ControlFlowGraph* savedCFG = m_cfg;
    int savedNextBlockId = m_nextBlockId;
    BasicBlock* savedEntryBlock = m_entryBlock;
    BasicBlock* savedExitBlock = m_exitBlock;
    
    // Switch to building the DEF FN CFG
    m_cfg = defCFG;
    m_nextBlockId = 0;
    
    // Create entry and exit blocks
    m_entryBlock = createBlock("Entry");
    defCFG->entryBlock = m_entryBlock->id;
    
    m_exitBlock = createBlock("Exit");
    defCFG->exitBlock = m_exitBlock->id;
    
    // DEF FN has a single expression body, not statements
    // We create a synthetic evaluation block that computes the expression
    // and returns the result
    BasicBlock* evalBlock = createBlock("EvalExpression");
    addUnconditionalEdge(m_entryBlock->id, evalBlock->id);
    
    // Add the DEF statement itself to the eval block
    // (The codegen will extract the expression from it)
    addStatementToBlock(evalBlock, &stmt, 0);
    
    // Wire eval block to exit
    addUnconditionalEdge(evalBlock->id, m_exitBlock->id);
    
    if (m_debugMode) {
        std::cout << "[CFG] DEF FN" << stmt.functionName << " built successfully" << std::endl;
        std::cout << "[CFG]   Blocks: " << defCFG->blocks.size() << std::endl;
    }
    
    // Restore previous CFG state
    m_cfg = savedCFG;
    m_nextBlockId = savedNextBlockId;
    m_entryBlock = savedEntryBlock;
    m_exitBlock = savedExitBlock;
    
    return defCFG;
}

// =============================================================================
// Build Complete ProgramCFG
// =============================================================================
//
// Build a complete ProgramCFG with main program and all SUB/FUNCTION/DEF FN CFGs.
// This is the top-level entry point for building CFGs for entire programs.
//
ProgramCFG* CFGBuilder::buildProgramCFG(const Program& program) {
    if (m_debugMode) {
        std::cout << "[CFG] Building complete ProgramCFG..." << std::endl;
        std::cout << "[CFG] Program has " << program.lines.size() << " lines" << std::endl;
    }
    
    ProgramCFG* programCFG = new ProgramCFG();
    
    // First pass: Extract all SUB/FUNCTION/DEF FN definitions and build their CFGs
    std::set<const Statement*> functionDefinitions;
    
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            // Check for FUNCTION definition
            if (auto* funcStmt = dynamic_cast<const FunctionStatement*>(stmt.get())) {
                if (m_debugMode) {
                    std::cout << "[CFG] Found FUNCTION " << funcStmt->functionName << std::endl;
                }
                
                ControlFlowGraph* funcCFG = buildFunction(*funcStmt);
                programCFG->functionCFGs[funcStmt->functionName] = std::unique_ptr<ControlFlowGraph>(funcCFG);
                functionDefinitions.insert(stmt.get());
                continue;
            }
            
            // Check for SUB definition
            if (auto* subStmt = dynamic_cast<const SubStatement*>(stmt.get())) {
                if (m_debugMode) {
                    std::cout << "[CFG] Found SUB " << subStmt->subName << std::endl;
                }
                
                ControlFlowGraph* subCFG = buildSub(*subStmt);
                programCFG->functionCFGs[subStmt->subName] = std::unique_ptr<ControlFlowGraph>(subCFG);
                functionDefinitions.insert(stmt.get());
                continue;
            }
            
            // Check for DEF FN definition
            if (auto* defStmt = dynamic_cast<const DefStatement*>(stmt.get())) {
                if (m_debugMode) {
                    std::cout << "[CFG] Found DEF FN" << defStmt->functionName << std::endl;
                }
                
                ControlFlowGraph* defCFG = buildDefFn(*defStmt);
                programCFG->functionCFGs["FN" + defStmt->functionName] = std::unique_ptr<ControlFlowGraph>(defCFG);
                functionDefinitions.insert(stmt.get());
                continue;
            }
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Found " << functionDefinitions.size() << " function definitions" << std::endl;
        std::cout << "[CFG] Building main program CFG..." << std::endl;
    }
    
    // Second pass: Build main program CFG (skip function definitions)
    // We need to filter out SUB/FUNCTION/DEF FN definitions from the main program flow
    
    // Reset builder state
    m_cfg = programCFG->mainCFG.get();
    m_nextBlockId = 0;
    m_totalBlocksCreated = 0;
    m_totalEdgesCreated = 0;
    m_lineNumberToBlock.clear();
    m_labelToBlock.clear();
    m_deferredEdges.clear();
    m_jumpTargets.clear();
    m_unreachableBlocks.clear();
    
    // Pre-scan main program for jump targets (excluding function bodies)
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            // Skip function definitions during jump target collection
            if (functionDefinitions.count(stmt.get()) > 0) {
                continue;
            }
            
            collectJumpTargetsFromStatement(stmt.get());
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Pre-scan found " << m_jumpTargets.size() 
                  << " jump targets in main program" << std::endl;
    }
    
    // Create entry block for main program
    m_entryBlock = createBlock("Entry");
    m_cfg->entryBlock = m_entryBlock->id;
    
    // Create exit block BEFORE processing statements so END can jump to it
    m_exitBlock = createBlock("Exit");
    m_cfg->exitBlock = m_exitBlock->id;
    
    BasicBlock* currentBlock = m_entryBlock;
    
    // Process each line, skipping function definitions
    for (const auto& line : program.lines) {
        // Register line number if present and is a jump target
        if (line->lineNumber > 0) {
            if (isJumpTarget(line->lineNumber)) {
                if (!currentBlock->statements.empty() || currentBlock == m_entryBlock || isTerminated(currentBlock)) {
                    // Need to split - create new block for this line
                    BasicBlock* targetBlock = createBlock("Line_" + std::to_string(line->lineNumber));
                    
                    // Wire previous block to this one (if not terminated)
                    if (!isTerminated(currentBlock)) {
                        addUnconditionalEdge(currentBlock->id, targetBlock->id);
                    }
                    
                    currentBlock = targetBlock;
                }
                
                // Register this line number's block
                registerLineNumberBlock(line->lineNumber, currentBlock->id);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Line " << line->lineNumber 
                              << " mapped to block " << currentBlock->id << std::endl;
                }
            }
        }
        
        // Process statements, skipping function definitions
        for (const auto& stmt : line->statements) {
            // Skip function definitions - they're not part of main program flow
            if (functionDefinitions.count(stmt.get()) > 0) {
                if (m_debugMode) {
                    std::cout << "[CFG] Skipping function definition in main program flow" << std::endl;
                }
                continue;
            }
            
            // Check if we need to handle a control structure
            if (auto* ifStmt = dynamic_cast<const IfStatement*>(stmt.get())) {
                currentBlock = buildIf(*ifStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* whileStmt = dynamic_cast<const WhileStatement*>(stmt.get())) {
                currentBlock = buildWhile(*whileStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* forStmt = dynamic_cast<const ForStatement*>(stmt.get())) {
                currentBlock = buildFor(*forStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* repeatStmt = dynamic_cast<const RepeatStatement*>(stmt.get())) {
                currentBlock = buildRepeat(*repeatStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* doStmt = dynamic_cast<const DoStatement*>(stmt.get())) {
                currentBlock = buildDo(*doStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* selectStmt = dynamic_cast<const CaseStatement*>(stmt.get())) {
                currentBlock = buildSelectCase(*selectStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* gotoStmt = dynamic_cast<const GotoStatement*>(stmt.get())) {
                currentBlock = handleGoto(*gotoStmt, currentBlock);
                continue;
            }
            
            if (auto* gosubStmt = dynamic_cast<const GosubStatement*>(stmt.get())) {
                currentBlock = handleGosub(*gosubStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* onGotoStmt = dynamic_cast<const OnGotoStatement*>(stmt.get())) {
                currentBlock = handleOnGoto(*onGotoStmt, currentBlock);
                continue;
            }
            
            if (auto* onGosubStmt = dynamic_cast<const OnGosubStatement*>(stmt.get())) {
                currentBlock = handleOnGosub(*onGosubStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* onCallStmt = dynamic_cast<const OnCallStatement*>(stmt.get())) {
                currentBlock = handleOnCall(*onCallStmt, currentBlock, nullptr, nullptr, nullptr, nullptr);
                continue;
            }
            
            if (auto* returnStmt = dynamic_cast<const ReturnStatement*>(stmt.get())) {
                currentBlock = handleReturn(*returnStmt, currentBlock, nullptr);
                continue;
            }
            
            if (auto* endStmt = dynamic_cast<const EndStatement*>(stmt.get())) {
                currentBlock = handleEnd(*endStmt, currentBlock);
                continue;
            }
            
            // For other statements, add to current block
            if (isTerminated(currentBlock)) {
                // Previous statement was a terminator
                currentBlock = createUnreachableBlock();
                
                if (m_debugMode) {
                    std::cout << "[CFG] Created unreachable block " << currentBlock->id 
                              << " after terminator" << std::endl;
                }
            }
            
            // Add statement to current block
            addStatementToBlock(currentBlock, stmt.get(), line->lineNumber);
        }
    }
    
    // Wire final block to exit (if not already terminated)
    if (currentBlock && !isTerminated(currentBlock)) {
        addUnconditionalEdge(currentBlock->id, m_exitBlock->id);
    }
    
    // Resolve deferred edges
    resolveDeferredEdges();
    
    if (m_debugMode) {
        std::cout << "[CFG] Main program CFG built successfully" << std::endl;
        std::cout << "[CFG]   Blocks: " << m_cfg->blocks.size() << std::endl;
        std::cout << "[CFG]   Edges: " << m_cfg->edges.size() << std::endl;
        std::cout << "[CFG] ProgramCFG complete with " << programCFG->functionCFGs.size() 
                  << " functions/subs" << std::endl;
    }
    
    // Clear m_cfg pointer - ownership is in programCFG->mainCFG unique_ptr
    // Without this, CFGBuilder destructor will try to delete it (double-delete bug)
    m_cfg = nullptr;
    
    return programCFG;
}

} // namespace FasterBASIC