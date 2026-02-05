//
// cfg_builder_core.cpp
// FasterBASIC - Control Flow Graph Builder Core (V2)
//
// Contains constructor, main build() entry point, and CFG lifecycle management.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>

namespace FasterBASIC {

// =============================================================================
// Constructor / Destructor
// =============================================================================

CFGBuilder::CFGBuilder()
    : m_cfg(nullptr)
    , m_nextBlockId(0)
    , m_totalBlocksCreated(0)
    , m_totalEdgesCreated(0)
    , m_debugMode(false)
    , m_entryBlock(nullptr)
    , m_exitBlock(nullptr)
{
}

CFGBuilder::~CFGBuilder() {
    // Note: m_cfg ownership is transferred via takeCFG()
    // If not transferred, we should clean it up
    if (m_cfg) {
        delete m_cfg;
        m_cfg = nullptr;
    }
}

// =============================================================================
// Main Entry Point
// =============================================================================

ControlFlowGraph* CFGBuilder::build(const std::vector<StatementPtr>& statements) {
    if (m_debugMode) {
        std::cout << "[CFG] Starting CFG construction..." << std::endl;
        std::cout << "[CFG] Total statements to process: " << statements.size() << std::endl;
    }
    
    // Create the CFG
    m_cfg = new ControlFlowGraph();
    m_nextBlockId = 0;
    m_totalBlocksCreated = 0;
    m_totalEdgesCreated = 0;
    m_lineNumberToBlock.clear();
    m_labelToBlock.clear();
    m_deferredEdges.clear();
    m_jumpTargets.clear();
    m_unreachableBlocks.clear();
    
    // PHASE 0: Pre-scan to collect all GOTO/GOSUB targets
    // This identifies "landing zones" that require block boundaries
    collectJumpTargets(statements);
    
    if (m_debugMode) {
        std::cout << "[CFG] Pre-scan found " << m_jumpTargets.size() 
                  << " jump targets" << std::endl;
    }
    
    // Create entry block
    m_entryBlock = createBlock("Entry");
    m_cfg->entryBlock = m_entryBlock->id;
    
    // Build the main program body
    // No context parameters (not in any loop/select/try)
    BasicBlock* finalBlock = buildStatementRange(
        statements,
        m_entryBlock,
        nullptr,  // No loop context
        nullptr,  // No select context
        nullptr,  // No try context
        nullptr   // No subroutine context
    );
    
    // Create exit block
    m_exitBlock = createBlock("Exit");
    m_cfg->exitBlock = m_exitBlock->id;
    
    // Wire final block to exit (if not already terminated)
    if (finalBlock && !isTerminated(finalBlock)) {
        addUnconditionalEdge(finalBlock->id, m_exitBlock->id);
    }
    
    // PHASE 2: Resolve any deferred edges (forward GOTOs)
    resolveDeferredEdges();
    
    if (m_debugMode) {
        std::cout << "[CFG] CFG construction complete" << std::endl;
        std::cout << "[CFG] Total blocks created: " << m_totalBlocksCreated << std::endl;
        std::cout << "[CFG] Total edges created: " << m_totalEdgesCreated << std::endl;
        dumpCFG("Final");
    }
    
    return m_cfg;
}

// =============================================================================
// Adapter: Build CFG from Program Structure
// =============================================================================

ControlFlowGraph* CFGBuilder::buildFromProgram(const Program& program) {
    if (m_debugMode) {
        std::cout << "[CFG] Building CFG from Program with " 
                  << program.lines.size() << " lines" << std::endl;
    }
    
    // Create the CFG
    m_cfg = new ControlFlowGraph("main");
    m_nextBlockId = 0;
    m_totalBlocksCreated = 0;
    m_totalEdgesCreated = 0;
    m_lineNumberToBlock.clear();
    m_labelToBlock.clear();
    m_deferredEdges.clear();
    m_jumpTargets.clear();
    m_unreachableBlocks.clear();
    
    // PHASE 0: Pre-scan to collect all GOTO/GOSUB targets from the Program
    collectJumpTargetsFromProgram(program);
    
    if (m_debugMode) {
        std::cout << "[CFG] Pre-scan found " << m_jumpTargets.size() 
                  << " jump targets" << std::endl;
    }
    
    // Create entry block
    m_entryBlock = createBlock("Entry");
    m_cfg->entryBlock = m_entryBlock->id;
    
    // Create exit block BEFORE processing statements so END can jump to it
    m_exitBlock = createBlock("Exit");
    m_cfg->exitBlock = m_exitBlock->id;
    
    // Build statement list from Program structure
    // The Program contains ProgramLines, each with statements
    BasicBlock* currentBlock = m_entryBlock;
    
    for (const auto& line : program.lines) {
        // Register this line number's block
        if (line->lineNumber > 0) {
            // If this line is a jump target, start a new block
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
        
        // Process each statement in the line
        for (const auto& stmt : line->statements) {
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
                // Previous statement was a terminator (GOTO/RETURN)
                // Create unreachable block for following code
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
    
    // PHASE 2: Resolve any deferred edges (forward GOTOs)
    resolveDeferredEdges();
    
    if (m_debugMode) {
        std::cout << "[CFG] CFG construction complete" << std::endl;
        std::cout << "[CFG] Total blocks created: " << m_totalBlocksCreated << std::endl;
        std::cout << "[CFG] Total edges created: " << m_totalEdgesCreated << std::endl;
        dumpCFG("Final");
    }
    
    return m_cfg;
}

// =============================================================================
// CFG Ownership Transfer
// =============================================================================

ControlFlowGraph* CFGBuilder::takeCFG() {
    ControlFlowGraph* result = m_cfg;
    m_cfg = nullptr;
    return result;
}

} // namespace FasterBASIC