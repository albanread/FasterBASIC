//
// cfg_builder_loops.cpp
// FasterBASIC - Control Flow Graph Builder Loop Handlers (V2)
//
// Contains FOR, WHILE, REPEAT, and DO loop processing.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>

namespace FasterBASIC {

// =============================================================================
// WHILE Loop Handler (Pre-test loop)
// =============================================================================
//
// WHILE loop structure:
// incoming -> header [condition check]
//             header -> body [true]
//             header -> exit [false]
//             body -> header [back-edge]
//             return exit
//
// Key: Back-edge is created immediately after building body!
//
BasicBlock* CFGBuilder::buildWhile(
    const WhileStatement& stmt,
    BasicBlock* incoming,
    LoopContext* outerLoop,
    SelectContext* select,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building WHILE loop" << std::endl;
    }
    
    // 1. Create blocks
    BasicBlock* headerBlock = createBlock("While_Header");
    BasicBlock* bodyBlock = createBlock("While_Body");
    BasicBlock* exitBlock = createBlock("While_Exit");
    
    headerBlock->isLoopHeader = true;
    exitBlock->isLoopExit = true;
    
    // 2. Wire incoming to header
    if (!isTerminated(incoming)) {
        addUnconditionalEdge(incoming->id, headerBlock->id);
    }
    
    // 3. Add condition check to header
    addStatementToBlock(headerBlock, &stmt, getLineNumber(&stmt));
    
    // 4. Wire header to body (true) and exit (false)
    addConditionalEdge(headerBlock->id, bodyBlock->id, "true");
    addConditionalEdge(headerBlock->id, exitBlock->id, "false");
    
    // 5. Create loop context for EXIT WHILE and nested loops
    LoopContext loopCtx;
    loopCtx.headerBlockId = headerBlock->id;
    loopCtx.exitBlockId = exitBlock->id;
    loopCtx.loopType = "WHILE";
    loopCtx.outerLoop = outerLoop;
    
    // 6. Recursively build loop body
    // KEY FIX: Use the body field from the AST (pre-parsed by parser)
    // This handles nested structures automatically!
    BasicBlock* bodyExit = buildStatementRange(
        stmt.body,
        bodyBlock,
        &loopCtx,  // Pass loop context to nested statements
        select,
        tryCtx,
        sub
    );
    
    // 7. Wire body exit back to header (back-edge)
    // This is created immediately, not deferred!
    if (!isTerminated(bodyExit)) {
        addUnconditionalEdge(bodyExit->id, headerBlock->id);
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] WHILE loop complete, exit block: " << exitBlock->id << std::endl;
    }
    
    // 8. Return exit block for next statement
    return exitBlock;
}

// =============================================================================
// FOR Loop Handler (Pre-test loop with initialization)
// =============================================================================
//
// FOR loop structure:
// incoming -> init [var = start]
//             init -> header [condition check: var <= end or var >= end]
//             header -> body [true]
//             header -> exit [false]
//             body -> increment [var = var + step]
//             increment -> header [back-edge]
//             return exit
//
BasicBlock* CFGBuilder::buildFor(
    const ForStatement& stmt,
    BasicBlock* incoming,
    LoopContext* outerLoop,
    SelectContext* select,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building FOR loop" << std::endl;
    }
    
    // 1. Create blocks
    BasicBlock* initBlock = createBlock("For_Init");
    BasicBlock* headerBlock = createBlock("For_Header");
    BasicBlock* bodyBlock = createBlock("For_Body");
    BasicBlock* incrementBlock = createBlock("For_Increment");
    BasicBlock* exitBlock = createBlock("For_Exit");
    
    headerBlock->isLoopHeader = true;
    exitBlock->isLoopExit = true;
    
    // 2. Wire incoming to init
    if (!isTerminated(incoming)) {
        addUnconditionalEdge(incoming->id, initBlock->id);
    }
    
    // 3. Add initialization to init block (var = start value)
    // This represents: FOR i = 1 TO 10
    addStatementToBlock(initBlock, &stmt, getLineNumber(&stmt));
    
    // 4. Wire init to header
    addUnconditionalEdge(initBlock->id, headerBlock->id);
    
    // 5. Header contains the loop condition check (i <= 10 or i >= 10 depending on STEP)
    // Wire header to body (true) and exit (false)
    addConditionalEdge(headerBlock->id, bodyBlock->id, "true");
    addConditionalEdge(headerBlock->id, exitBlock->id, "false");
    
    // 6. Create loop context for EXIT FOR and nested loops
    LoopContext loopCtx;
    loopCtx.headerBlockId = headerBlock->id;
    loopCtx.exitBlockId = exitBlock->id;
    loopCtx.loopType = "FOR";
    loopCtx.outerLoop = outerLoop;
    
    // 7. Recursively build loop body
    BasicBlock* bodyExit = buildStatementRange(
        stmt.body,
        bodyBlock,
        &loopCtx,
        select,
        tryCtx,
        sub
    );
    
    // 8. Wire body exit to increment block (if not terminated)
    if (!isTerminated(bodyExit)) {
        addUnconditionalEdge(bodyExit->id, incrementBlock->id);
    }
    
    // 9. Increment block contains: var = var + STEP
    // Then wire back to header (back-edge)
    addUnconditionalEdge(incrementBlock->id, headerBlock->id);
    
    if (m_debugMode) {
        std::cout << "[CFG] FOR loop complete, exit block: " << exitBlock->id << std::endl;
    }
    
    // 10. Return exit block for next statement
    return exitBlock;
}

// =============================================================================
// REPEAT Loop Handler (Post-test loop)
// =============================================================================
//
// REPEAT...UNTIL loop structure:
// incoming -> body
//             body -> condition [check at end]
//             condition -> body [false - continue looping]
//             condition -> exit [true - condition met]
//             return exit
//
// KEY DIFFERENCE FROM WHILE: Body executes at least once!
//
BasicBlock* CFGBuilder::buildRepeat(
    const RepeatStatement& stmt,
    BasicBlock* incoming,
    LoopContext* outerLoop,
    SelectContext* select,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building REPEAT loop (post-test)" << std::endl;
    }
    
    // 1. Create blocks
    BasicBlock* bodyBlock = createBlock("Repeat_Body");
    BasicBlock* conditionBlock = createBlock("Repeat_Condition");
    BasicBlock* exitBlock = createBlock("Repeat_Exit");
    
    bodyBlock->isLoopHeader = true;  // Body is the "header" for post-test
    exitBlock->isLoopExit = true;
    
    // 2. Wire incoming to body (executes at least once)
    if (!isTerminated(incoming)) {
        addUnconditionalEdge(incoming->id, bodyBlock->id);
    }
    
    // 3. Create loop context for EXIT and nested loops
    // Use condition block as "header" for CONTINUE-like semantics
    LoopContext loopCtx;
    loopCtx.headerBlockId = conditionBlock->id;
    loopCtx.exitBlockId = exitBlock->id;
    loopCtx.loopType = "REPEAT";
    loopCtx.outerLoop = outerLoop;
    
    // 4. Recursively build loop body (using body field from AST)
    BasicBlock* bodyExit = buildStatementRange(
        stmt.body,
        bodyBlock,
        &loopCtx,
        select,
        tryCtx,
        sub
    );
    
    // 5. Wire body exit to condition block (if not terminated)
    if (!isTerminated(bodyExit)) {
        addUnconditionalEdge(bodyExit->id, conditionBlock->id);
    }
    
    // 6. Add UNTIL condition check to condition block
    // The condition is stored in RepeatStatement.condition
    addStatementToBlock(conditionBlock, &stmt, getLineNumber(&stmt));
    
    // 7. Wire condition to exit (true) and back to body (false)
    // UNTIL means: exit when condition is TRUE
    addConditionalEdge(conditionBlock->id, exitBlock->id, "true");
    addConditionalEdge(conditionBlock->id, bodyBlock->id, "false");
    
    if (m_debugMode) {
        std::cout << "[CFG] REPEAT loop complete, exit block: " << exitBlock->id << std::endl;
    }
    
    // 8. Return exit block for next statement
    return exitBlock;
}

// =============================================================================
// DO Loop Handler (Multiple variants)
// =============================================================================
//
// DO loop has multiple variants:
// 1. DO WHILE condition ... LOOP (pre-test, continue while true)
// 2. DO UNTIL condition ... LOOP (pre-test, continue until true)
// 3. DO ... LOOP WHILE condition (post-test, continue while true)
// 4. DO ... LOOP UNTIL condition (post-test, continue until true)
// 5. DO ... LOOP (infinite loop, needs EXIT DO)
//
BasicBlock* CFGBuilder::buildDo(
    const DoStatement& stmt,
    BasicBlock* incoming,
    LoopContext* outerLoop,
    SelectContext* select,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building DO loop" << std::endl;
    }
    
    // Determine loop variant from AST
    bool hasPreCondition = (stmt.preConditionType != DoStatement::ConditionType::NONE);
    bool hasPostCondition = (stmt.postConditionType != DoStatement::ConditionType::NONE);
    bool isPreWhile = (stmt.preConditionType == DoStatement::ConditionType::WHILE);
    bool isPostWhile = (stmt.postConditionType == DoStatement::ConditionType::WHILE);
    
    if (hasPreCondition) {
        // =====================================================================
        // PRE-TEST VARIANT (like WHILE)
        // =====================================================================
        // incoming -> header [condition check]
        //             header -> body [condition met]
        //             header -> exit [condition not met]
        //             body -> header [back-edge]
        
        BasicBlock* headerBlock = createBlock("Do_Header");
        BasicBlock* bodyBlock = createBlock("Do_Body");
        BasicBlock* exitBlock = createBlock("Do_Exit");
        
        headerBlock->isLoopHeader = true;
        exitBlock->isLoopExit = true;
        
        if (!isTerminated(incoming)) {
            addUnconditionalEdge(incoming->id, headerBlock->id);
        }
        
        addStatementToBlock(headerBlock, &stmt, getLineNumber(&stmt));
        
        // Wire header to body and exit based on WHILE vs UNTIL
        if (isPreWhile) {
            // DO WHILE: continue when true
            addConditionalEdge(headerBlock->id, bodyBlock->id, "true");
            addConditionalEdge(headerBlock->id, exitBlock->id, "false");
        } else {
            // DO UNTIL: continue when false (exit when true)
            addConditionalEdge(headerBlock->id, bodyBlock->id, "false");
            addConditionalEdge(headerBlock->id, exitBlock->id, "true");
        }
        
        LoopContext loopCtx;
        loopCtx.headerBlockId = headerBlock->id;
        loopCtx.exitBlockId = exitBlock->id;
        loopCtx.loopType = "DO";
        loopCtx.outerLoop = outerLoop;
        
        BasicBlock* bodyExit = buildStatementRange(
            stmt.body,
            bodyBlock,
            &loopCtx,
            select,
            tryCtx,
            sub
        );
        
        if (!isTerminated(bodyExit)) {
            addUnconditionalEdge(bodyExit->id, headerBlock->id);
        }
        
        if (m_debugMode) {
            std::cout << "[CFG] DO (pre-test) loop complete, exit block: " << exitBlock->id << std::endl;
        }
        
        return exitBlock;
        
    } else if (hasPostCondition) {
        // =====================================================================
        // POST-TEST VARIANT (like REPEAT)
        // =====================================================================
        // incoming -> body
        //             body -> condition [check at end]
        //             condition -> body [condition met]
        //             condition -> exit [condition not met]
        
        BasicBlock* bodyBlock = createBlock("Do_Body");
        BasicBlock* conditionBlock = createBlock("Do_Condition");
        BasicBlock* exitBlock = createBlock("Do_Exit");
        
        bodyBlock->isLoopHeader = true;
        exitBlock->isLoopExit = true;
        
        if (!isTerminated(incoming)) {
            addUnconditionalEdge(incoming->id, bodyBlock->id);
        }
        
        LoopContext loopCtx;
        loopCtx.headerBlockId = conditionBlock->id;
        loopCtx.exitBlockId = exitBlock->id;
        loopCtx.loopType = "DO";
        loopCtx.outerLoop = outerLoop;
        
        BasicBlock* bodyExit = buildStatementRange(
            stmt.body,
            bodyBlock,
            &loopCtx,
            select,
            tryCtx,
            sub
        );
        
        if (!isTerminated(bodyExit)) {
            addUnconditionalEdge(bodyExit->id, conditionBlock->id);
        }
        
        addStatementToBlock(conditionBlock, &stmt, getLineNumber(&stmt));
        
        // Wire condition based on WHILE vs UNTIL
        if (isPostWhile) {
            // LOOP WHILE: continue when true
            addConditionalEdge(conditionBlock->id, bodyBlock->id, "true");
            addConditionalEdge(conditionBlock->id, exitBlock->id, "false");
        } else {
            // LOOP UNTIL: continue when false (exit when true)
            addConditionalEdge(conditionBlock->id, exitBlock->id, "true");
            addConditionalEdge(conditionBlock->id, bodyBlock->id, "false");
        }
        
        if (m_debugMode) {
            std::cout << "[CFG] DO (post-test) loop complete, exit block: " << exitBlock->id << std::endl;
        }
        
        return exitBlock;
        
    } else {
        // =====================================================================
        // INFINITE LOOP VARIANT: DO ... LOOP (no condition)
        // =====================================================================
        // incoming -> body
        //             body -> body [back-edge]
        //             exit block is created but only reachable via EXIT DO
        
        BasicBlock* bodyBlock = createBlock("Do_Body");
        BasicBlock* exitBlock = createBlock("Do_Exit");
        
        bodyBlock->isLoopHeader = true;
        exitBlock->isLoopExit = true;
        
        if (!isTerminated(incoming)) {
            addUnconditionalEdge(incoming->id, bodyBlock->id);
        }
        
        LoopContext loopCtx;
        loopCtx.headerBlockId = bodyBlock->id;
        loopCtx.exitBlockId = exitBlock->id;
        loopCtx.loopType = "DO";
        loopCtx.outerLoop = outerLoop;
        
        BasicBlock* bodyExit = buildStatementRange(
            stmt.body,
            bodyBlock,
            &loopCtx,
            select,
            tryCtx,
            sub
        );
        
        if (!isTerminated(bodyExit)) {
            // Infinite loop: back-edge to body
            addUnconditionalEdge(bodyExit->id, bodyBlock->id);
        }
        
        if (m_debugMode) {
            std::cout << "[CFG] DO (infinite) loop complete, exit block: " << exitBlock->id << std::endl;
        }
        
        // Exit block is only reachable via EXIT DO
        return exitBlock;
    }
}

} // namespace FasterBASIC