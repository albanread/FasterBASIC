//
// cfg_builder_jumps.cpp
// FasterBASIC - Control Flow Graph Builder Jump Handlers (V2)
//
// Contains GOTO, GOSUB, RETURN, ON GOTO, ON GOSUB, and related jump statements.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>

namespace FasterBASIC {

// =============================================================================
// GOTO Handler
// =============================================================================
//
// GOTO is a terminator - unconditional jump to a line number
// Creates edge to target, marks block as terminated, returns unreachable block
//
BasicBlock* CFGBuilder::handleGoto(const GotoStatement& stmt, BasicBlock* incoming) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling GOTO to line " << stmt.lineNumber << std::endl;
    }
    
    // Add GOTO statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // Resolve target line to block ID
    int targetBlockId = resolveLineNumberToBlock(stmt.lineNumber);
    
    if (targetBlockId >= 0) {
        // Target already exists, wire directly
        addUnconditionalEdge(incoming->id, targetBlockId);
        
        if (m_debugMode) {
            std::cout << "[CFG] GOTO from block " << incoming->id 
                      << " to block " << targetBlockId << std::endl;
        }
    } else {
        // Forward reference - defer until Phase 2
        DeferredEdge edge;
        edge.sourceBlockId = incoming->id;
        edge.targetLineNumber = stmt.lineNumber;
        edge.label = "goto";
        m_deferredEdges.push_back(edge);
        
        if (m_debugMode) {
            std::cout << "[CFG] Deferred GOTO edge to line " << stmt.lineNumber << std::endl;
        }
    }
    
    // GOTO is a terminator - no fallthrough
    markTerminated(incoming);
    
    // Return the terminated block - caller will create unreachable block if needed
    return incoming;
}

// =============================================================================
// GOSUB Handler
// =============================================================================
//
// GOSUB is a subroutine call - jumps to line number and expects RETURN
// Creates two edges: call edge to target, fallthrough to return point
//
BasicBlock* CFGBuilder::handleGosub(const GosubStatement& stmt, BasicBlock* incoming,
                                    LoopContext* loop, SelectContext* select,
                                    TryContext* tryCtx, SubroutineContext* outerSub) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling GOSUB to line " << stmt.lineNumber << std::endl;
    }
    
    // Add GOSUB statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // Create the return point block (where execution continues after RETURN)
    BasicBlock* returnBlock = createBlock("Return_Point");
    
    // Track this block as a GOSUB return point for sparse dispatch optimization
    m_cfg->gosubReturnBlocks.insert(returnBlock->id);
    
    // Edge A: Call edge to subroutine target
    int targetBlockId = resolveLineNumberToBlock(stmt.lineNumber);
    
    if (targetBlockId >= 0) {
        // Target already exists, wire directly
        addEdge(incoming->id, targetBlockId, "call");
        
        if (m_debugMode) {
            std::cout << "[CFG] GOSUB call edge from block " << incoming->id 
                      << " to block " << targetBlockId << std::endl;
        }
    } else {
        // Forward reference - defer until Phase 2
        DeferredEdge edge;
        edge.sourceBlockId = incoming->id;
        edge.targetLineNumber = stmt.lineNumber;
        edge.label = "call";
        m_deferredEdges.push_back(edge);
        
        if (m_debugMode) {
            std::cout << "[CFG] Deferred GOSUB call edge to line " << stmt.lineNumber << std::endl;
        }
    }
    
    // Edge B: Fallthrough edge to return point
    // (Execution continues here after the subroutine RETURNs)
    addUnconditionalEdge(incoming->id, returnBlock->id);
    
    if (m_debugMode) {
        std::cout << "[CFG] GOSUB from block " << incoming->id 
                  << " with return point " << returnBlock->id << std::endl;
    }
    
    // Continue building from return point
    return returnBlock;
}

// =============================================================================
// RETURN Handler
// =============================================================================
//
// RETURN pops the subroutine call stack and returns to caller
// If we have subroutine context, wire back to return point
//
BasicBlock* CFGBuilder::handleReturn(const ReturnStatement& stmt, BasicBlock* incoming,
                                     SubroutineContext* sub) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling RETURN statement" << std::endl;
    }
    
    // Add RETURN statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // RETURN is a terminator - it pops the call stack and returns to caller
    if (sub && sub->returnBlockId >= 0) {
        // We're inside a GOSUB context - return to the caller's return point
        addUnconditionalEdge(incoming->id, sub->returnBlockId);
        
        if (m_debugMode) {
            std::cout << "[CFG] RETURN jumps to return point block " << sub->returnBlockId << std::endl;
        }
    } else {
        // RETURN from GOSUB - create a RETURN edge (no static target)
        // The code generator will emit runtime dispatch based on return stack
        CFGEdge edge;
        edge.sourceBlock = incoming->id;
        edge.targetBlock = -1;  // No static target - determined at runtime
        edge.type = EdgeType::RETURN;
        edge.label = "return";
        m_cfg->edges.push_back(edge);
        
        if (m_debugMode) {
            std::cout << "[CFG] RETURN creates dynamic return edge (GOSUB dispatch)" << std::endl;
        }
    }
    
    // Mark as terminator
    // RETURN is a terminator - no fallthrough
    markTerminated(incoming);
    
    // Return the terminated block - caller will create unreachable block if needed
    return incoming;
}

// =============================================================================
// ON...GOTO Handler (Computed GOTO)
// =============================================================================
//
// ON expression GOTO line1, line2, line3, ...
// Jumps to one of N targets based on expression value (1-indexed)
// If out of range, falls through to next statement
//
BasicBlock* CFGBuilder::handleOnGoto(const OnGotoStatement& stmt, BasicBlock* incoming) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling ON...GOTO with " << stmt.lineNumbers.size() 
                  << " targets" << std::endl;
    }
    
    // Add ON GOTO statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // ON GOTO is NOT a terminator! If the selector is out of range, 
    // execution falls through to the next statement
    
    // Create fallthrough block for out-of-range case
    BasicBlock* fallthroughBlock = createBlock("OnGoto_Fallthrough");
    
    // Add conditional edges to all targets
    for (size_t i = 0; i < stmt.isLabelList.size(); i++) {
        int targetBlockId = -1;
        
        if (stmt.isLabelList[i]) {
            // Target is a label
            const std::string& label = stmt.labels[i];
            targetBlockId = resolveLabelToBlock(label);
            
            if (targetBlockId < 0) {
                // Forward reference to label - defer
                DeferredEdge edge;
                edge.sourceBlockId = incoming->id;
                edge.targetLabel = label;
                edge.label = "case_" + std::to_string(i + 1);
                m_deferredEdges.push_back(edge);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Deferred ON GOTO case " << (i + 1) 
                              << " to label " << label << std::endl;
                }
                continue;
            }
        } else {
            // Target is a line number
            int targetLine = stmt.lineNumbers[i];
            targetBlockId = resolveLineNumberToBlock(targetLine);
            
            if (targetBlockId < 0) {
                // Forward reference to line number - defer
                DeferredEdge edge;
                edge.sourceBlockId = incoming->id;
                edge.targetLineNumber = targetLine;
                edge.label = "case_" + std::to_string(i + 1);
                m_deferredEdges.push_back(edge);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Deferred ON GOTO case " << (i + 1) 
                              << " to line " << targetLine << std::endl;
                }
                continue;
            }
        }
        
        // Target resolved - create edge
        if (targetBlockId >= 0) {
            addConditionalEdge(incoming->id, targetBlockId, 
                             "case_" + std::to_string(i + 1));
            
            if (m_debugMode) {
                std::cout << "[CFG] ON GOTO case " << (i + 1) 
                          << " -> block " << targetBlockId << std::endl;
            }
        }
    }
    
    // Add fallthrough edge for out-of-range selector
    addConditionalEdge(incoming->id, fallthroughBlock->id, "default");
    
    if (m_debugMode) {
        std::cout << "[CFG] ON...GOTO from block " << incoming->id 
                  << " with fallthrough to " << fallthroughBlock->id << std::endl;
    }
    
    return fallthroughBlock;
}

// =============================================================================
// ON...GOSUB Handler (Computed GOSUB)
// =============================================================================
//
// ON expression GOSUB line1, line2, line3, ...
// Calls one of N subroutines based on expression value (1-indexed)
// Always continues to next statement (after RETURN or if out of range)
//
BasicBlock* CFGBuilder::handleOnGosub(const OnGosubStatement& stmt, BasicBlock* incoming,
                                     LoopContext* loop, SelectContext* select,
                                     TryContext* tryCtx, SubroutineContext* outerSub) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling ON...GOSUB with " << stmt.lineNumbers.size() 
                  << " targets" << std::endl;
    }
    
    // Add ON GOSUB statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // ON GOSUB is like multiple GOSUB calls with a selector
    // It always continues to the next statement (either after RETURN or if out of range)
    
    // Create return point block
    BasicBlock* returnBlock = createBlock("OnGosub_Return_Point");
    
    // Track this block as a GOSUB return point for sparse dispatch optimization
    m_cfg->gosubReturnBlocks.insert(returnBlock->id);
    
    // Add call edges to all targets
    for (size_t i = 0; i < stmt.isLabelList.size(); i++) {
        int targetBlockId = -1;
        
        if (stmt.isLabelList[i]) {
            // Target is a label
            const std::string& label = stmt.labels[i];
            targetBlockId = resolveLabelToBlock(label);
            
            if (targetBlockId < 0) {
                // Forward reference to label - defer
                DeferredEdge edge;
                edge.sourceBlockId = incoming->id;
                edge.targetLabel = label;
                edge.label = "call_" + std::to_string(i + 1);
                m_deferredEdges.push_back(edge);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Deferred ON GOSUB case " << (i + 1) 
                              << " to label " << label << std::endl;
                }
                continue;
            }
        } else {
            // Target is a line number
            int targetLine = stmt.lineNumbers[i];
            targetBlockId = resolveLineNumberToBlock(targetLine);
            
            if (targetBlockId < 0) {
                // Forward reference to line number - defer
                DeferredEdge edge;
                edge.sourceBlockId = incoming->id;
                edge.targetLineNumber = targetLine;
                edge.label = "call_" + std::to_string(i + 1);
                m_deferredEdges.push_back(edge);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Deferred ON GOSUB case " << (i + 1) 
                              << " to line " << targetLine << std::endl;
                }
                continue;
            }
        }
        
        // Target resolved - create edge
        if (targetBlockId >= 0) {
            addConditionalEdge(incoming->id, targetBlockId, 
                             "call_" + std::to_string(i + 1));
            
            if (m_debugMode) {
                std::cout << "[CFG] ON GOSUB case " << (i + 1) 
                          << " -> block " << targetBlockId << std::endl;
            }
        }
    }
    
    // All paths (call + return, or out-of-range) lead to return block
    addUnconditionalEdge(incoming->id, returnBlock->id);
    
    if (m_debugMode) {
        std::cout << "[CFG] ON...GOSUB from block " << incoming->id 
                  << " with return point " << returnBlock->id << std::endl;
    }
    
    return returnBlock;
}

// =============================================================================
// ON...CALL Handler (Computed CALL to named SUB)
// =============================================================================
//
// ON expression CALL Sub1, Sub2, Sub3, ...
// Calls one of N named SUB procedures based on expression value (1-indexed)
// Always continues to next statement (after SUB returns or if out of range)
//
BasicBlock* CFGBuilder::handleOnCall(const OnCallStatement& stmt, BasicBlock* incoming,
                                    LoopContext* loop, SelectContext* select,
                                    TryContext* tryCtx, SubroutineContext* outerSub) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling ON...CALL with " << stmt.functionNames.size() 
                  << " targets" << std::endl;
    }
    
    // Add ON CALL statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // ON CALL is like multiple CALL statements with a selector
    // It always continues to the next statement (after return or if out of range)
    
    // Create continuation block (where execution resumes after any SUB call)
    BasicBlock* continueBlock = createBlock("OnCall_Continue");
    
    // For ON CALL, we create conditional edges to represent the dispatch
    // Each edge represents "if selector == N, call SubN"
    // The actual CALL codegen will be handled by the emitter based on these edges
    
    for (size_t i = 0; i < stmt.functionNames.size(); i++) {
        const std::string& subName = stmt.functionNames[i];
        
        // Create edge with label indicating which SUB to call
        // The label format "call_sub:<name>" tells the emitter this is a SUB call
        addConditionalEdge(incoming->id, continueBlock->id, 
                         "call_sub:" + subName + ":case_" + std::to_string(i + 1));
        
        if (m_debugMode) {
            std::cout << "[CFG] ON CALL case " << (i + 1) 
                      << " -> SUB " << subName << std::endl;
        }
    }
    
    // Fallthrough/out-of-range case also goes to continue block
    addConditionalEdge(incoming->id, continueBlock->id, "call_default");
    
    if (m_debugMode) {
        std::cout << "[CFG] ON...CALL from block " << incoming->id 
                  << " continues at block " << continueBlock->id << std::endl;
    }
    
    return continueBlock;
}

// =============================================================================
// EXIT Statement Handler (Unified Dispatcher)
// =============================================================================
//
// Dispatches to specific EXIT handler based on exit type
//
BasicBlock* CFGBuilder::handleExit(const ExitStatement& stmt, BasicBlock* incoming,
                                   LoopContext* loop, SelectContext* select) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling EXIT statement" << std::endl;
    }
    
    // Add EXIT statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // Dispatch based on exit type
    switch (stmt.exitType) {
        case ExitStatement::ExitType::FOR_LOOP:
            return handleExitFor(incoming, loop);
            
        case ExitStatement::ExitType::WHILE_LOOP:
            return handleExitWhile(incoming, loop);
            
        case ExitStatement::ExitType::DO_LOOP:
            return handleExitDo(incoming, loop);
            
        case ExitStatement::ExitType::REPEAT_LOOP:
            // REPEAT loops use same exit mechanism as DO loops
            return handleExitDo(incoming, loop);
            
        case ExitStatement::ExitType::FUNCTION:
        case ExitStatement::ExitType::SUB:
            // Function/Sub exit - just mark as terminator
            markTerminated(incoming);
            return incoming;
            
        default:
            if (m_debugMode) {
                std::cout << "[CFG] Warning: Unknown EXIT type" << std::endl;
            }
            markTerminated(incoming);
            return incoming;
    }
}

// =============================================================================
// EXIT FOR Handler
// =============================================================================
//
// Exits the current FOR loop - jumps to loop exit block
//
BasicBlock* CFGBuilder::handleExitFor(BasicBlock* incoming, LoopContext* loop) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling EXIT FOR" << std::endl;
    }
    
    // Find the innermost FOR loop
    LoopContext* forLoop = findLoopContext(loop, "FOR");
    
    if (!forLoop || forLoop->exitBlockId < 0) {
        if (m_debugMode) {
            std::cout << "[CFG] Warning: EXIT FOR outside of FOR loop" << std::endl;
        }
        markTerminated(incoming);
        return incoming;
    }
    
    // Jump to loop exit
    addUnconditionalEdge(incoming->id, forLoop->exitBlockId);
    markTerminated(incoming);
    
    if (m_debugMode) {
        std::cout << "[CFG] EXIT FOR from block " << incoming->id 
                  << " to exit block " << forLoop->exitBlockId << std::endl;
    }
    
    return incoming;
}

// =============================================================================
// EXIT WHILE Handler
// =============================================================================
//
// Exits the current WHILE loop - jumps to loop exit block
//
BasicBlock* CFGBuilder::handleExitWhile(BasicBlock* incoming, LoopContext* loop) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling EXIT WHILE" << std::endl;
    }
    
    // Find the innermost WHILE loop
    LoopContext* whileLoop = findLoopContext(loop, "WHILE");
    
    if (!whileLoop || whileLoop->exitBlockId < 0) {
        if (m_debugMode) {
            std::cout << "[CFG] Warning: EXIT WHILE outside of WHILE loop" << std::endl;
        }
        markTerminated(incoming);
        return incoming;
    }
    
    // Jump to loop exit
    addUnconditionalEdge(incoming->id, whileLoop->exitBlockId);
    markTerminated(incoming);
    
    if (m_debugMode) {
        std::cout << "[CFG] EXIT WHILE from block " << incoming->id 
                  << " to exit block " << whileLoop->exitBlockId << std::endl;
    }
    
    return incoming;
}

// =============================================================================
// EXIT DO Handler
// =============================================================================
//
// Exits the current DO loop - jumps to loop exit block
//
BasicBlock* CFGBuilder::handleExitDo(BasicBlock* incoming, LoopContext* loop) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling EXIT DO" << std::endl;
    }
    
    // Find the innermost DO loop
    LoopContext* doLoop = findLoopContext(loop, "DO");
    
    if (!doLoop || doLoop->exitBlockId < 0) {
        if (m_debugMode) {
            std::cout << "[CFG] Warning: EXIT DO outside of DO loop" << std::endl;
        }
        markTerminated(incoming);
        return incoming;
    }
    
    // Jump to loop exit
    addUnconditionalEdge(incoming->id, doLoop->exitBlockId);
    markTerminated(incoming);
    
    if (m_debugMode) {
        std::cout << "[CFG] EXIT DO from block " << incoming->id 
                  << " to exit block " << doLoop->exitBlockId << std::endl;
    }
    
    return incoming;
}

// =============================================================================
// EXIT SELECT Handler
// =============================================================================
//
// Exits the current SELECT CASE - jumps to select exit block
//
BasicBlock* CFGBuilder::handleExitSelect(BasicBlock* incoming, SelectContext* select) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling EXIT SELECT" << std::endl;
    }
    
    if (!select || select->exitBlockId < 0) {
        if (m_debugMode) {
            std::cout << "[CFG] Warning: EXIT SELECT outside of SELECT CASE" << std::endl;
        }
        markTerminated(incoming);
        return incoming;
    }
    
    // Jump to select exit
    addUnconditionalEdge(incoming->id, select->exitBlockId);
    markTerminated(incoming);
    
    if (m_debugMode) {
        std::cout << "[CFG] EXIT SELECT from block " << incoming->id 
                  << " to exit block " << select->exitBlockId << std::endl;
    }
    
    return incoming;
}

// =============================================================================
// CONTINUE Handler
// =============================================================================
//
// Jumps back to loop header (for languages that support CONTINUE)
//
BasicBlock* CFGBuilder::handleContinue(BasicBlock* incoming, LoopContext* loop) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling CONTINUE" << std::endl;
    }
    
    if (!loop || loop->headerBlockId < 0) {
        if (m_debugMode) {
            std::cout << "[CFG] Warning: CONTINUE outside of loop" << std::endl;
        }
        markTerminated(incoming);
        return incoming;
    }
    
    // Jump to loop header
    addUnconditionalEdge(incoming->id, loop->headerBlockId);
    markTerminated(incoming);
    
    if (m_debugMode) {
        std::cout << "[CFG] CONTINUE from block " << incoming->id 
                  << " to header block " << loop->headerBlockId << std::endl;
    }
    
    return incoming;
}

// =============================================================================
// END Handler
// =============================================================================
//
// END statement terminates program execution
//
BasicBlock* CFGBuilder::handleEnd(const EndStatement& stmt, BasicBlock* incoming) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling END statement - jumping to exit" << std::endl;
    }
    
    // Add END statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // END jumps to the program exit block (if it exists)
    if (m_exitBlock) {
        addUnconditionalEdge(incoming->id, m_exitBlock->id);
        
        if (m_debugMode) {
            std::cout << "[CFG] END in block " << incoming->id << " jumps to exit block " << m_exitBlock->id << std::endl;
        }
    }
    
    // Mark as terminated so no fall-through
    markTerminated(incoming);
    
    // Return the terminated block - caller will create unreachable block if needed
    return incoming;
}

// =============================================================================
// THROW Handler
// =============================================================================
//
// THROW statement raises an exception
// If we're in a TRY context, jumps to catch block
// Otherwise, terminates (unhandled exception)
//
BasicBlock* CFGBuilder::handleThrow(const ThrowStatement& stmt, BasicBlock* incoming,
                                    TryContext* tryCtx) {
    if (m_debugMode) {
        std::cout << "[CFG] Handling THROW statement" << std::endl;
    }
    
    // Add THROW statement to current block
    addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
    
    // THROW is a terminator - control goes to exception handler
    if (tryCtx && tryCtx->catchBlockId >= 0) {
        // We're inside a TRY context - jump to catch block
        addUnconditionalEdge(incoming->id, tryCtx->catchBlockId);
        
        if (m_debugMode) {
            std::cout << "[CFG] THROW jumps to catch block " << tryCtx->catchBlockId << std::endl;
        }
    } else {
        // No TRY context - unhandled exception (program terminates)
        if (m_debugMode) {
            std::cout << "[CFG] Warning: THROW outside of TRY context (unhandled exception)" << std::endl;
        }
    }
    
    // Mark as terminator
    // THROW is a terminator - no fallthrough
    markTerminated(incoming);
    
    // Return the terminated block - caller will create unreachable block if needed
    return incoming;
}

} // namespace FasterBASIC