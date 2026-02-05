//
// cfg_builder_exception.cpp
// FasterBASIC - Control Flow Graph Builder Exception Handler (V2)
//
// Contains TRY...CATCH...FINALLY statement processing.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>

namespace FasterBASIC {

// =============================================================================
// TRY...CATCH...FINALLY Handler
// =============================================================================
//
// TRY...CATCH...FINALLY...END TRY
// Creates blocks for try body, catch clauses, finally block, and exit
// Exception edges connect throw points to catch handlers
//
BasicBlock* CFGBuilder::buildTryCatch(
    const TryCatchStatement& stmt,
    BasicBlock* incoming,
    LoopContext* loop,
    SelectContext* select,
    TryContext* outerTry,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building TRY...CATCH...FINALLY statement" << std::endl;
    }
    
    // TRY...CATCH...FINALLY structure:
    // 1. TRY block - normal execution path
    // 2. CATCH blocks - exception handlers (one per catch clause)
    // 3. FINALLY block - always executes (cleanup code)
    // 4. EXIT block - where control flows after try/catch/finally
    
    // Add TRY statement to incoming block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // 1. Create blocks
    BasicBlock* tryBlock = createBlock("Try_Block");
    BasicBlock* finallyBlock = stmt.finallyBlock.empty() ? nullptr : createBlock("Finally_Block");
    BasicBlock* exitBlock = createBlock("Try_Exit");
    
    // 2. Wire incoming to try block
    if (!isTerminated(incoming)) {
        addUnconditionalEdge(incoming->id, tryBlock->id);
    }
    
    // 3. Create catch blocks (one per catch clause)
    std::vector<BasicBlock*> catchBlocks;
    for (size_t i = 0; i < stmt.catchClauses.size(); i++) {
        BasicBlock* catchBlock = createBlock("Catch_" + std::to_string(i));
        catchBlocks.push_back(catchBlock);
    }
    
    // If no catch blocks, create a default one
    BasicBlock* defaultCatchBlock = nullptr;
    if (catchBlocks.empty()) {
        defaultCatchBlock = createBlock("Catch_Default");
        catchBlocks.push_back(defaultCatchBlock);
    }
    
    // 4. Create TRY context for nested THROW statements
    TryContext tryCtx;
    tryCtx.catchBlockId = catchBlocks[0]->id;  // Default to first catch block
    tryCtx.finallyBlockId = finallyBlock ? finallyBlock->id : -1;
    tryCtx.outerTry = outerTry;
    
    // 5. Recursively build TRY block with exception context
    BasicBlock* tryExit = buildStatementRange(
        stmt.tryBlock,
        tryBlock,
        loop,
        select,
        &tryCtx,  // Pass try context to nested statements
        sub
    );
    
    // 6. If TRY completes normally (no exception), go to FINALLY or EXIT
    if (!isTerminated(tryExit)) {
        if (finallyBlock) {
            addUnconditionalEdge(tryExit->id, finallyBlock->id);
        } else {
            addUnconditionalEdge(tryExit->id, exitBlock->id);
        }
    }
    
    // 7. Process each CATCH clause
    for (size_t i = 0; i < stmt.catchClauses.size(); i++) {
        const auto& catchClause = stmt.catchClauses[i];
        BasicBlock* catchBlock = catchBlocks[i];
        
        if (m_debugMode) {
            std::cout << "[CFG] Processing CATCH clause " << i;
            if (!catchClause.errorCodes.empty()) {
                std::cout << " (error codes: ";
                for (size_t j = 0; j < catchClause.errorCodes.size(); j++) {
                    if (j > 0) std::cout << ", ";
                    std::cout << catchClause.errorCodes[j];
                }
                std::cout << ")";
            }
            std::cout << std::endl;
        }
        
        // Recursively build catch block
        BasicBlock* catchExit = buildStatementRange(
            catchClause.block,
            catchBlock,
            loop,
            select,
            &tryCtx,  // Nested try/catch is possible
            sub
        );
        
        // After catch, go to FINALLY or EXIT
        if (!isTerminated(catchExit)) {
            if (finallyBlock) {
                addUnconditionalEdge(catchExit->id, finallyBlock->id);
            } else {
                addUnconditionalEdge(catchExit->id, exitBlock->id);
            }
        }
    }
    
    // 8. Process FINALLY block (if present)
    if (finallyBlock) {
        if (m_debugMode) {
            std::cout << "[CFG] Processing FINALLY block" << std::endl;
        }
        
        // FINALLY always executes, regardless of exception
        BasicBlock* finallyExit = buildStatementRange(
            stmt.finallyBlock,
            finallyBlock,
            loop,
            select,
            &tryCtx,
            sub
        );
        
        // After finally, go to exit
        if (!isTerminated(finallyExit)) {
            addUnconditionalEdge(finallyExit->id, exitBlock->id);
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] TRY...CATCH...FINALLY complete, exit block: " 
                  << exitBlock->id << std::endl;
    }
    
    // 9. Return exit block
    return exitBlock;
}

} // namespace FasterBASIC