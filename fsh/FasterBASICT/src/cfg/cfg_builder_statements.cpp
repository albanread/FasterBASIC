//
// cfg_builder_statements.cpp
// FasterBASIC - Control Flow Graph Builder Statement Dispatcher (V2)
//
// Contains the recursive statement range builder - the heart of v2 architecture.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>

namespace FasterBASIC {

// =============================================================================
// Core Recursive Statement Range Builder
// =============================================================================
//
// This is the heart of the v2 architecture. It processes statements one by one,
// and when it encounters a control structure, it calls the appropriate builder
// function which recursively handles the nested structure.
//
// The key insight: Each control structure builder returns the EXIT block where
// control continues after that structure. This block becomes the "incoming"
// block for the next statement.
//
BasicBlock* CFGBuilder::buildStatementRange(
    const std::vector<StatementPtr>& statements,
    BasicBlock* incoming,
    LoopContext* currentLoop,
    SelectContext* currentSelect,
    TryContext* currentTry,
    SubroutineContext* currentSub
) {
    if (!incoming) {
        throw std::runtime_error("CFG: incoming block is null in buildStatementRange");
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] buildStatementRange: " << statements.size() 
                  << " statements, incoming block " << incoming->id << std::endl;
    }
    
    BasicBlock* currentBlock = incoming;
    
    // Process each statement in sequence
    for (const auto& stmt : statements) {
        if (!stmt) continue;
        
        // If current block is terminated (GOTO, RETURN, etc.),
        // create a new unreachable block for subsequent statements
        if (isTerminated(currentBlock)) {
            if (m_debugMode) {
                std::cout << "[CFG] Current block is terminated, creating unreachable block" << std::endl;
            }
            currentBlock = createUnreachableBlock();
        }
        
        // Dispatch based on statement type using dynamic_cast
        // Each builder returns the exit block for the next statement
        
        // =============================================================================
        // Function/Subroutine Definitions (skip - handled at top level)
        // =============================================================================
        
        // SUB, FUNCTION, and DEF FN definitions should not appear in nested contexts
        // They are top-level declarations that are processed separately by buildProgramCFG()
        if (dynamic_cast<const SubStatement*>(stmt.get()) ||
            dynamic_cast<const FunctionStatement*>(stmt.get()) ||
            dynamic_cast<const DefStatement*>(stmt.get())) {
            if (m_debugMode) {
                std::cout << "[CFG] Skipping function/sub definition (should be top-level)" << std::endl;
            }
            continue;
        }
        
        // =============================================================================
        // Control Structures (recursive builders)
        // =============================================================================
        
        if (auto* ifStmt = dynamic_cast<const IfStatement*>(stmt.get())) {
            currentBlock = buildIf(
                *ifStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* whileStmt = dynamic_cast<const WhileStatement*>(stmt.get())) {
            currentBlock = buildWhile(
                *whileStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* forStmt = dynamic_cast<const ForStatement*>(stmt.get())) {
            currentBlock = buildFor(
                *forStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* repeatStmt = dynamic_cast<const RepeatStatement*>(stmt.get())) {
            currentBlock = buildRepeat(
                *repeatStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* doStmt = dynamic_cast<const DoStatement*>(stmt.get())) {
            currentBlock = buildDo(
                *doStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* selectStmt = dynamic_cast<const CaseStatement*>(stmt.get())) {
            currentBlock = buildSelectCase(
                *selectStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* tryStmt = dynamic_cast<const TryCatchStatement*>(stmt.get())) {
            currentBlock = buildTryCatch(
                *tryStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        // =============================================================================
        // Jump Statements (terminators)
        // =============================================================================
        
        if (auto* gotoStmt = dynamic_cast<const GotoStatement*>(stmt.get())) {
            currentBlock = handleGoto(*gotoStmt, currentBlock);
            continue;
        }
        
        if (auto* gosubStmt = dynamic_cast<const GosubStatement*>(stmt.get())) {
            currentBlock = handleGosub(
                *gosubStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        if (auto* returnStmt = dynamic_cast<const ReturnStatement*>(stmt.get())) {
            currentBlock = handleReturn(*returnStmt, currentBlock, currentSub);
            continue;
        }
        
        if (auto* onGotoStmt = dynamic_cast<const OnGotoStatement*>(stmt.get())) {
            currentBlock = handleOnGoto(*onGotoStmt, currentBlock);
            continue;
        }
        
        if (auto* onGosubStmt = dynamic_cast<const OnGosubStatement*>(stmt.get())) {
            currentBlock = handleOnGosub(
                *onGosubStmt,
                currentBlock,
                currentLoop,
                currentSelect,
                currentTry,
                currentSub
            );
            continue;
        }
        
        // =============================================================================
        // EXIT Statements (loop exits)
        // =============================================================================
        
        if (auto* exitStmt = dynamic_cast<const ExitStatement*>(stmt.get())) {
            // Dispatch based on exit type (no select parameter needed)
            currentBlock = handleExit(*exitStmt, currentBlock, currentLoop, nullptr);
            continue;
        }
        
        // =============================================================================
        // Special Statements
        // =============================================================================
        
        if (auto* endStmt = dynamic_cast<const EndStatement*>(stmt.get())) {
            currentBlock = handleEnd(*endStmt, currentBlock);
            continue;
        }
        
        if (auto* throwStmt = dynamic_cast<const ThrowStatement*>(stmt.get())) {
            currentBlock = handleThrow(*throwStmt, currentBlock, currentTry);
            continue;
        }
        
        // =============================================================================
        // Loop End Markers (skip - already handled by loop builders)
        // =============================================================================
        
        if (dynamic_cast<const WendStatement*>(stmt.get()) ||
            dynamic_cast<const NextStatement*>(stmt.get()) ||
            dynamic_cast<const UntilStatement*>(stmt.get()) ||
            dynamic_cast<const LoopStatement*>(stmt.get())) {
            // These are end markers that the parser includes
            // The v2 loop builders handle them implicitly via stmt.body
            // So we skip them here
            if (m_debugMode) {
                std::cout << "[CFG] Skipping loop end marker statement" << std::endl;
            }
            continue;
        }
        
        // =============================================================================
        // Regular Statements (LET, PRINT, DIM, etc.)
        // =============================================================================
        // For all other statements, just add them to the current block
        // These include: assignment, PRINT, INPUT, DIM, REDIM, function calls, etc.
        
        addStatementToBlock(currentBlock, stmt.get(), getLineNumber(stmt.get()));
        
        if (m_debugMode) {
            std::cout << "[CFG] Added regular statement to block " << currentBlock->id << std::endl;
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] buildStatementRange complete, exit block: " << currentBlock->id << std::endl;
    }
    
    return currentBlock;
}

} // namespace FasterBASIC