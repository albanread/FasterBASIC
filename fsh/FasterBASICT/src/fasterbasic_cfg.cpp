//
// fasterbasic_cfg.cpp
// FasterBASIC - Control Flow Graph Builder Implementation
//
// Implements CFG construction from validated AST.
// Converts the tree structure into basic blocks connected by edges.
// This is Phase 4 of the compilation pipeline.
//

#include "fasterbasic_cfg.h"
#include <algorithm>
#include <sstream>
#include <iostream>
#include <functional>

namespace FasterBASIC {

// =============================================================================
// Constructor/Destructor
// =============================================================================

CFGBuilder::CFGBuilder()
    : m_program(nullptr)
    , m_symbols(nullptr)
    , m_currentBlock(nullptr)
    , m_nextBlockId(0)
    , m_createExitBlock(true)
    , m_mergeBlocks(false)
    , m_blocksCreated(0)
    , m_edgesCreated(0)
    , m_processingNestedStatements(false)
{
}

CFGBuilder::~CFGBuilder() = default;

// =============================================================================
// Main Build Entry Point
// =============================================================================

std::unique_ptr<ProgramCFG> CFGBuilder::build(const Program& program,
                                               const SymbolTable& symbols) {
    m_program = &program;
    m_symbols = &symbols;
    m_programCFG = std::make_unique<ProgramCFG>();
    m_blocksCreated = 0;
    m_edgesCreated = 0;
    m_loopStack.clear();
    
    // Build main program CFG
    m_currentCFG = m_programCFG->mainCFG.get();
    
    // Phase 0: Pre-scan to collect jump targets (main program only)
    std::set<int> jumpTargets = collectJumpTargets(program);
    
    // Phase 1: Build basic blocks (main program + extract functions)
    buildBlocks(program, jumpTargets);
    
    // Phase 2: Build control flow edges for main program
    buildEdges();
    
    // Phase 3: Build edges for each function
    for (auto& pair : m_programCFG->functionCFGs) {
        m_currentCFG = pair.second.get();
        buildEdges();
    }
    
    // Phase 4: Identify loop structures in main
    m_currentCFG = m_programCFG->mainCFG.get();
    identifyLoops();
    
    // Phase 5: Identify loop structures in functions
    for (auto& pair : m_programCFG->functionCFGs) {
        m_currentCFG = pair.second.get();
        identifyLoops();
    }
    
    // Phase 6: Identify subroutines in main
    m_currentCFG = m_programCFG->mainCFG.get();
    identifySubroutines();
    
    // Phase 7: Optimize CFG (optional)
    if (m_mergeBlocks) {
        m_currentCFG = m_programCFG->mainCFG.get();
        optimizeCFG();
        for (auto& pair : m_programCFG->functionCFGs) {
            m_currentCFG = pair.second.get();
            optimizeCFG();
        }
    }
    
    return std::move(m_programCFG);
}

// =============================================================================
// Phase 0: Pre-scan to collect jump targets
// =============================================================================

// Helper function to recursively collect jump targets from statements
void collectJumpTargetsFromStatements(const std::vector<std::unique_ptr<Statement>>& statements, 
                                      std::set<int>& targets) {
    for (const auto& stmt : statements) {
        ASTNodeType type = stmt->getType();
        
        switch (type) {
            case ASTNodeType::STMT_GOTO: {
                const auto& gotoStmt = static_cast<const GotoStatement&>(*stmt);
                targets.insert(gotoStmt.lineNumber);
                break;
            }
            
            case ASTNodeType::STMT_GOSUB: {
                const auto& gosubStmt = static_cast<const GosubStatement&>(*stmt);
                targets.insert(gosubStmt.lineNumber);
                break;
            }
            
            case ASTNodeType::STMT_ON_EVENT: {
                const auto& onEventStmt = static_cast<const OnEventStatement&>(*stmt);
                std::cout << "DEBUG: Found ON_EVENT statement, event=" << onEventStmt.eventName 
                          << ", handlerType=" << static_cast<int>(onEventStmt.handlerType)
                          << ", target=" << onEventStmt.target 
                          << ", isLineNumber=" << onEventStmt.isLineNumber << std::endl;
                if ((onEventStmt.handlerType == EventHandlerType::GOSUB || 
                     onEventStmt.handlerType == EventHandlerType::GOTO) && 
                    onEventStmt.isLineNumber) {
                    int lineNum = std::stoi(onEventStmt.target);
                    std::cout << "DEBUG: Adding event GOSUB/GOTO target: " << lineNum << std::endl;
                    targets.insert(lineNum);
                }
                break;
            }
            
            case ASTNodeType::STMT_ON_GOTO: {
                const auto& onGotoStmt = static_cast<const OnGotoStatement&>(*stmt);
                for (size_t i = 0; i < onGotoStmt.isLabelList.size(); ++i) {
                    if (!onGotoStmt.isLabelList[i]) {
                        // Line number target
                        targets.insert(onGotoStmt.lineNumbers[i]);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_ON_GOSUB: {
                const auto& onGosubStmt = static_cast<const OnGosubStatement&>(*stmt);
                for (size_t i = 0; i < onGosubStmt.isLabelList.size(); ++i) {
                    if (!onGosubStmt.isLabelList[i]) {
                        // Line number target
                        targets.insert(onGosubStmt.lineNumbers[i]);
                    }
                    // For labels, we don't add to targets here since labels are collected separately
                }
                break;
            }
            
            case ASTNodeType::STMT_LABEL: {
                // Labels are potential jump targets - but we handle them separately
                // since they are collected in the semantic analyzer
                break;
            }
            
            case ASTNodeType::STMT_IF: {
                const auto& ifStmt = static_cast<const IfStatement&>(*stmt);
                if (ifStmt.hasGoto) {
                    targets.insert(ifStmt.gotoLine);
                }
                // Recursively scan THEN and ELSE blocks
                collectJumpTargetsFromStatements(ifStmt.thenStatements, targets);
                collectJumpTargetsFromStatements(ifStmt.elseStatements, targets);
                break;
            }
            
            default:
                break;
        }
    }
}

std::set<int> CFGBuilder::collectJumpTargets(const Program& program) {
    std::set<int> targets;
    
    for (const auto& line : program.lines) {
        collectJumpTargetsFromStatements(line->statements, targets);
    }
    
    return targets;
}

// =============================================================================
// Phase 1: Build Basic Blocks
// =============================================================================

void CFGBuilder::buildBlocks(const Program& program, const std::set<int>& jumpTargets) {
    // Create entry block for main program
    BasicBlock* entryBlock = createNewBlock("Entry");
    m_currentCFG->entryBlock = entryBlock->id;
    m_currentBlock = entryBlock;
    
    // Track if we've hit an END statement - code after END is only reachable via GOSUB
    bool afterEnd = false;
    
    // Process each program line
    for (const auto& line : program.lines) {
        int lineNumber = line->lineNumber;
        
        // If this line is a jump target, start a new block
        if (lineNumber > 0 && jumpTargets.count(lineNumber) > 0) {
            // Only create new block if current block is not empty
            if (!m_currentBlock->statements.empty() || !m_currentBlock->lineNumbers.empty()) {
                BasicBlock* targetBlock = createNewBlock("Target_" + std::to_string(lineNumber));
                // Add fallthrough edge from previous block if it doesn't end with a jump
                // and we haven't encountered END yet
                if (!afterEnd && !m_currentBlock->statements.empty()) {
                    const Statement* lastStmt = m_currentBlock->statements.back();
                    ASTNodeType lastType = lastStmt->getType();
                    if (lastType != ASTNodeType::STMT_GOTO && 
                        lastType != ASTNodeType::STMT_END &&
                        lastType != ASTNodeType::STMT_RETURN &&
                        lastType != ASTNodeType::STMT_EXIT) {
                        // Fallthrough will be added in buildEdges phase
                    }
                }
                m_currentBlock = targetBlock;
            }
        }
        
        // Map line number to current block
        if (lineNumber > 0) {
            m_currentCFG->mapLineToBlock(lineNumber, m_currentBlock->id);
            m_currentBlock->addLineNumber(lineNumber);
        }
        
        // Process each statement in the line
        for (const auto& stmt : line->statements) {
            processStatement(*stmt, m_currentBlock, lineNumber);
            
            // Check if this statement is END - if so, subsequent code is only reachable via GOSUB
            // BUT: We need to distinguish standalone END from END IF, END SELECT, etc.
            // Check if this is truly a standalone END statement (EndStatement class)
            if (stmt->getType() == ASTNodeType::STMT_END) {
                // Check if it's actually an EndStatement object (not part of END IF, etc.)
                const EndStatement* endStmt = dynamic_cast<const EndStatement*>(stmt.get());
                if (endStmt != nullptr) {
                    afterEnd = true;
                }
            }
        }
    }
    
    // Create exit block if requested
    if (m_createExitBlock) {
        BasicBlock* exitBlock = createNewBlock("Exit");
        exitBlock->isTerminator = true;
        m_currentCFG->exitBlock = exitBlock->id;
        
        // Connect last block to exit
        if (m_currentBlock && m_currentBlock->id != exitBlock->id) {
            addFallthroughEdge(m_currentBlock->id, exitBlock->id);
        }
    }
}

// =============================================================================
// Statement Processing
// =============================================================================

void CFGBuilder::processStatement(const Statement& stmt, BasicBlock* currentBlock, int lineNumber) {
    // Handle control flow statements
    ASTNodeType type = stmt.getType();
    

    // Don't add FUNCTION/SUB/DEF statements to main CFG - they define separate CFGs
    // Add all statements to current block (except functions/subs)
    if (type != ASTNodeType::STMT_FUNCTION && type != ASTNodeType::STMT_SUB && type != ASTNodeType::STMT_DEF) {
        // Add statement to current block with its line number
        currentBlock->addStatement(&stmt, lineNumber);
    }
    
    switch (type) {
        case ASTNodeType::STMT_TRY_CATCH:
            processTryCatchStatement(static_cast<const TryCatchStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_LABEL:
            processLabelStatement(static_cast<const LabelStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_GOTO:
            processGotoStatement(static_cast<const GotoStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_GOSUB:
            processGosubStatement(static_cast<const GosubStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_ON_GOTO:
            processOnGotoStatement(static_cast<const OnGotoStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_ON_GOSUB:
            processOnGosubStatement(static_cast<const OnGosubStatement&>(stmt), currentBlock);
            currentBlock->isTerminator = true;
            break;
            
        case ASTNodeType::STMT_IF:
            processIfStatement(static_cast<const IfStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_FOR:
            processForStatement(static_cast<const ForStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_FOR_IN:
            processForInStatement(static_cast<const ForInStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_WHILE:
            processWhileStatement(static_cast<const WhileStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_REPEAT:
            processRepeatStatement(static_cast<const RepeatStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_DO:
            processDoStatement(static_cast<const DoStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_CASE:
            processCaseStatement(static_cast<const CaseStatement&>(stmt), currentBlock);
            break;
        
        case ASTNodeType::STMT_THROW:
            // THROW is a terminator (throws exception and doesn't return normally)
            currentBlock->isTerminator = true;
            break;
            
        case ASTNodeType::STMT_FUNCTION:
            processFunctionStatement(static_cast<const FunctionStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_SUB:
            processSubStatement(static_cast<const SubStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_DEF:
            processDefStatement(static_cast<const DefStatement&>(stmt), currentBlock);
            break;
            
        case ASTNodeType::STMT_NEXT:
            {
                // NEXT creates the incrementor block and the exit block
                // This is "The Closer" - where the loop structure is finalized
                const NextStatement& nextStmt = static_cast<const NextStatement&>(stmt);
                LoopContext* matchingLoop = nullptr;
                
                // Find the matching loop by variable name (or innermost if no variable specified)
                for (auto it = m_loopStack.rbegin(); it != m_loopStack.rend(); ++it) {
                    if (nextStmt.variable.empty() || it->variable == nextStmt.variable) {
                        matchingLoop = &(*it);
                        break;
                    }
                }
                
                if (matchingLoop) {
                    // 1. Create the NEXT block itself (the incrementor block)
                    BasicBlock* nextBlock = createNewBlock("FOR Next/Increment");
                    
                    // 2. Move the NEXT statement from current block to NEXT block
                    //    (it was already added to currentBlock at line 276)
                    if (!currentBlock->statements.empty() && currentBlock->statements.back() == &stmt) {
                        // Get the line number for this statement
                        int lineNum = 0;
                        auto it = currentBlock->statementLineNumbers.find(&stmt);
                        if (it != currentBlock->statementLineNumbers.end()) {
                            lineNum = it->second;
                        }
                        
                        // Remove from current block and add to NEXT block
                        currentBlock->statements.pop_back();
                        currentBlock->statementLineNumbers.erase(&stmt);
                        nextBlock->addStatement(&stmt, lineNum);
                    }
                    
                    // 3. Current block (end of loop body) flows into NEXT block
                    //    (unless it's a terminator)
                    if (!currentBlock->isTerminator && currentBlock->successors.empty()) {
                        addFallthroughEdge(currentBlock->id, nextBlock->id);
                    }
                    
                    // 4. Record the mapping from NEXT block to loop header for buildEdges
                    //    (NEXT block always jumps back to the Check block)
                    m_nextToHeaderMap[nextBlock->id] = matchingLoop->headerBlock;
                    
                    // 5. NOW create the Exit block - its ID will be higher than everything in the body
                    BasicBlock* loopExit = createNewBlock("After FOR");
                    loopExit->isLoopExit = true;
                    
                    // 6. Update the loop context with the exit block ID
                    matchingLoop->exitBlock = loopExit->id;
                    
                    // 7. Wire all pending EXIT FOR blocks to the exit block
                    for (int exitBlockId : matchingLoop->pendingExitBlocks) {
                        addFallthroughEdge(exitBlockId, loopExit->id);
                    }
                    
                    // 8. Update the FOR loop structure if it exists
                    for (auto& pair : m_currentCFG->forLoopStructure) {
                        if (pair.second.checkBlock == matchingLoop->headerBlock) {
                            pair.second.exitBlock = loopExit->id;
                            break;
                        }
                    }
                    
                    // 9. Switch to the exit block for subsequent statements
                    m_currentBlock = loopExit;
                    
                    // 10. Pop this loop context - we're done with this loop
                    m_loopStack.erase(std::remove_if(m_loopStack.begin(), m_loopStack.end(),
                        [matchingLoop](const LoopContext& ctx) { return &ctx == matchingLoop; }), 
                        m_loopStack.end());
                } else {
                    // Fallback: create a new block if no matching loop found
                    BasicBlock* afterLoop = createNewBlock("After NEXT");
                    m_currentBlock = afterLoop;
                }
            }
            break;
            
        case ASTNodeType::STMT_WEND:
            // WEND ends the loop body and starts a new block for code after the loop
            {
                BasicBlock* nextBlock = createNewBlock("After WHILE");
                m_currentBlock = nextBlock;
                
                // Don't pop loop context here - buildEdges() needs it to create back edge
            }
            break;
            
        case ASTNodeType::STMT_LOOP:
            // LOOP ends the loop body and starts a new block for code after the loop
            {
                BasicBlock* nextBlock = createNewBlock("After DO");
                m_currentBlock = nextBlock;
                // Don't pop loop context - buildEdges() needs it
            }
            break;
            
        case ASTNodeType::STMT_UNTIL:
            // UNTIL ends the loop body and starts a new block for code after the loop
            {
                BasicBlock* nextBlock = createNewBlock("After REPEAT");
                m_currentBlock = nextBlock;
                
                // Don't pop loop context here - buildEdges() needs it to create back edge
            }
            break;
            
        case ASTNodeType::STMT_RETURN:
        case ASTNodeType::STMT_END:
            // Only mark as terminator if we're not processing nested statements
            // (nested statements in IF branches shouldn't terminate the parent block)
            if (!m_processingNestedStatements) {
                currentBlock->isTerminator = true;
            }
            break;
            
        case ASTNodeType::STMT_EXIT:
            {
                // EXIT handling: for EXIT FOR, track pending exit blocks
                const ExitStatement& exitStmt = static_cast<const ExitStatement&>(stmt);
                
                if (exitStmt.exitType == ExitStatement::ExitType::FOR_LOOP) {
                    // EXIT FOR - add to pending exits for the innermost FOR loop
                    if (!m_loopStack.empty()) {
                        // Find innermost FOR loop
                        for (auto it = m_loopStack.rbegin(); it != m_loopStack.rend(); ++it) {
                            if (!it->variable.empty()) {  // FOR loops have a variable
                                it->pendingExitBlocks.push_back(currentBlock->id);
                                break;
                            }
                        }
                    }
                    // Create a new block after the EXIT FOR statement
                    // (this block will be unreachable but maintains CFG structure)
                    BasicBlock* afterExit = createNewBlock("After EXIT FOR");
                    m_currentBlock = afterExit;
                }
                
                // Mark as terminator if not processing nested statements
                if (!m_processingNestedStatements) {
                    currentBlock->isTerminator = true;
                }
            }
            break;
            
        default:
            // Regular statements don't affect control flow
            break;
    }
}

void CFGBuilder::processGotoStatement(const GotoStatement& stmt, BasicBlock* currentBlock) {
    // GOTO creates unconditional jump - start new block after this
    BasicBlock* nextBlock = createNewBlock();
    m_currentBlock = nextBlock;
    
    // Edge will be added in buildEdges phase when we know target block IDs
}

void CFGBuilder::processGosubStatement(const GosubStatement& stmt, BasicBlock* currentBlock) {
    // GOSUB is like a call - execution continues after it in a new block
    // Create a new block for the return point (statement after GOSUB)
    BasicBlock* nextBlock = createNewBlock();
    
    // Record the mapping from GOSUB block to its return continuation block
    // This is needed because blocks may not be sequential when GOSUB is inside IF/WHILE
    m_gosubReturnMap[currentBlock->id] = nextBlock->id;
    
    // Track this block as a GOSUB return point for optimization
    // This allows RETURN statements to only check reachable return blocks
    if (m_currentCFG) {
        m_currentCFG->gosubReturnBlocks.insert(nextBlock->id);
    }
    
    m_currentBlock = nextBlock;
    
    // Edge will be added in buildEdges phase when we know target block IDs
}

void CFGBuilder::processOnGotoStatement(const OnGotoStatement& stmt, BasicBlock* currentBlock) {
    // ON GOTO creates multiple potential jump targets - like GOTO, it's a terminator
    // If selector is out of range, execution continues to next statement
    BasicBlock* nextBlock = createNewBlock();
    m_currentBlock = nextBlock;
    
    // Edges will be added in buildEdges phase when we know target block IDs
}

void CFGBuilder::processOnGosubStatement(const OnGosubStatement& stmt, BasicBlock* currentBlock) {
    // ON GOSUB creates multiple potential subroutine calls - like GOSUB, execution can continue
    // If selector is out of range, execution continues to next statement
    // Since it's a terminator, start new block for next statement
    BasicBlock* nextBlock = createNewBlock();
    m_currentBlock = nextBlock;
    // Edges will be added in buildEdges phase
}

void CFGBuilder::processLabelStatement(const LabelStatement& stmt, BasicBlock* currentBlock) {
    // Labels are jump targets - start a new block for the label
    BasicBlock* labelBlock = createNewBlock("Label_" + stmt.labelName);
    m_currentBlock = labelBlock;
}

void CFGBuilder::processIfStatement(const IfStatement& stmt, BasicBlock* currentBlock) {
    // IF creates conditional branch
    std::cerr << "[DEBUG] processIfStatement called: isMultiLine=" << stmt.isMultiLine 
              << ", hasGoto=" << stmt.hasGoto 
              << ", thenStmts=" << stmt.thenStatements.size()
              << ", elseStmts=" << stmt.elseStatements.size() << "\n";

    if (stmt.hasGoto) {
        // IF ... THEN GOTO creates two-way branch
        BasicBlock* nextBlock = createNewBlock();
        m_currentBlock = nextBlock;
    } else if (stmt.isMultiLine) {
        // Multi-line IF...END IF: Create separate blocks for THEN/ELSE branches
        // Use proper block ordering: create convergence point AFTER nested statements
        std::cerr << "[DEBUG] Creating THEN/ELSE blocks for multiline IF\n";
        
        // 1. Create the branch targets
        BasicBlock* thenBlock = createNewBlock("IF THEN");
        BasicBlock* elseBlock = createNewBlock("IF ELSE");
        std::cerr << "[DEBUG] Created thenBlock=" << thenBlock->id << ", elseBlock=" << elseBlock->id << "\n";
        
        // 2. Link the IF header to both branches immediately
        addConditionalEdge(currentBlock->id, thenBlock->id, "true");
        addConditionalEdge(currentBlock->id, elseBlock->id, "false");
        
        // 3. Process the THEN branch
        // This might create many internal blocks if there are nested loops
        m_currentBlock = thenBlock;
        std::cerr << "[DEBUG] Processing THEN branch with " << stmt.thenStatements.size() << " statements\n";
        if (!stmt.thenStatements.empty()) {
            processNestedStatements(stmt.thenStatements, thenBlock, stmt.location.line);
        }
        std::cerr << "[DEBUG] THEN branch processed, m_currentBlock=" << m_currentBlock->id << "\n";
        // Capture the "exit tip" of the THEN branch
        BasicBlock* thenExitTip = m_currentBlock;
        
        // 4. Process the ELSE branch
        m_currentBlock = elseBlock;
        if (!stmt.elseStatements.empty()) {
            processNestedStatements(stmt.elseStatements, elseBlock, stmt.location.line);
        }
        // Capture the "exit tip" of the ELSE branch
        BasicBlock* elseExitTip = m_currentBlock;
        
        // 5. Create the convergence point (After IF)
        // By creating this AFTER the nested statements, it will naturally
        // have a higher ID than anything inside the THEN/ELSE blocks
        BasicBlock* afterIfBlock = createNewBlock("After IF");
        
        // 6. Bridge the exit tips to the convergence point
        // Only bridge if the branch didn't end in a terminator
        bool thenHasTerminator = !thenExitTip->statements.empty() && 
                                (thenExitTip->statements.back()->getType() == ASTNodeType::STMT_EXIT ||
                                 thenExitTip->statements.back()->getType() == ASTNodeType::STMT_RETURN ||
                                 thenExitTip->statements.back()->getType() == ASTNodeType::STMT_GOTO ||
                                 thenExitTip->statements.back()->getType() == ASTNodeType::STMT_END);
        
        bool elseHasTerminator = !elseExitTip->statements.empty() && 
                                (elseExitTip->statements.back()->getType() == ASTNodeType::STMT_EXIT ||
                                 elseExitTip->statements.back()->getType() == ASTNodeType::STMT_RETURN ||
                                 elseExitTip->statements.back()->getType() == ASTNodeType::STMT_GOTO ||
                                 elseExitTip->statements.back()->getType() == ASTNodeType::STMT_END);
        
        if (!thenHasTerminator) {
            addFallthroughEdge(thenExitTip->id, afterIfBlock->id);
        }
        if (!elseHasTerminator) {
            addFallthroughEdge(elseExitTip->id, afterIfBlock->id);
        }
        
        // 7. Update the builder's state
        m_currentBlock = afterIfBlock;
    } else {
        // Single-line IF: IF x THEN statement
        // Do NOT process nested statements here - leave them in the AST
        // The code generator will emit them with proper conditional branching
        // This is different from multi-line IF which uses CFG-driven branching
        
        // Single-line IF statements should be handled by emitIf() in codegen
        // which will emit: evaluate condition, jnz to then/else labels, emit statements
    }
}

// Helper method to recursively process nested statements (e.g., inside IF blocks)
void CFGBuilder::processNestedStatements(const std::vector<StatementPtr>& statements, 
                                         BasicBlock* currentBlock, int defaultLineNumber) {
    // Set flag to indicate we're processing nested statements
    bool wasProcessingNested = m_processingNestedStatements;
    m_processingNestedStatements = true;

    
    for (const auto& nestedStmt : statements) {
        // Get the line number for this nested statement
        // For multi-line IF blocks, nested statements might not have their own line numbers
        // so we use the parent IF's line number as a fallback
        int lineNumber = defaultLineNumber;
        
        // Check if this is a control-flow statement that needs CFG processing
        ASTNodeType type = nestedStmt->getType();
        
        bool isControlFlow = (type == ASTNodeType::STMT_IF ||
                             type == ASTNodeType::STMT_WHILE ||
                             type == ASTNodeType::STMT_FOR ||
                             type == ASTNodeType::STMT_FOR_IN ||
                             type == ASTNodeType::STMT_DO ||
                             type == ASTNodeType::STMT_REPEAT ||
                             type == ASTNodeType::STMT_CASE ||
                             type == ASTNodeType::STMT_TRY_CATCH ||
                             type == ASTNodeType::STMT_WEND ||
                             type == ASTNodeType::STMT_NEXT ||
                             type == ASTNodeType::STMT_LOOP ||
                             type == ASTNodeType::STMT_UNTIL ||
                             type == ASTNodeType::STMT_GOTO ||
                             type == ASTNodeType::STMT_GOSUB ||
                             type == ASTNodeType::STMT_ON_GOTO ||
                             type == ASTNodeType::STMT_ON_GOSUB ||
                             type == ASTNodeType::STMT_LABEL ||
                             type == ASTNodeType::STMT_RETURN ||
                             type == ASTNodeType::STMT_EXIT ||
                             // Note: STMT_END here includes END IF, END SELECT, etc.
                             // We should NOT treat these as program termination END
                             // type == ASTNodeType::STMT_END ||
                             type == ASTNodeType::STMT_THROW ||
                             type == ASTNodeType::STMT_FUNCTION ||
                             type == ASTNodeType::STMT_SUB ||
                             type == ASTNodeType::STMT_DEF);
        
        if (isControlFlow) {
            // Process control-flow statements through the regular processStatement method
            // This ensures they create proper CFG blocks and edges

            processStatement(*nestedStmt, m_currentBlock, lineNumber);
        } else {
            // For non-control-flow statements, just add them to the current block
            // (don't call processStatement to avoid double-adding)

            m_currentBlock->addStatement(nestedStmt.get(), lineNumber);
        }
    }
    
    // Restore flag
    m_processingNestedStatements = wasProcessingNested;
}

void CFGBuilder::processForStatement(const ForStatement& stmt, BasicBlock* currentBlock) {
    // FOR creates: init block (with FOR statement), check block, body block
    // Exit block is created later by NEXT to ensure proper block ordering
    // Structure: FOR init → check (condition) → body → NEXT (increment) → check
    
    // Init block contains the FOR statement (initialization)
    BasicBlock* initBlock = createNewBlock("FOR Init");
    
    // Create edge from current block to init block (for nested loops)
    // This ensures the outer loop body flows into the inner loop init
    if (currentBlock->id != initBlock->id) {
        addFallthroughEdge(currentBlock->id, initBlock->id);
    }
    
    // Move the FOR statement to the init block (it was already added to currentBlock)
    if (!currentBlock->statements.empty() && currentBlock->statements.back() == &stmt) {
        // Get the line number for this statement
        int lineNum = 0;
        auto it = currentBlock->statementLineNumbers.find(&stmt);
        if (it != currentBlock->statementLineNumbers.end()) {
            lineNum = it->second;
        }
        
        // Remove from current block and add to init
        currentBlock->statements.pop_back();
        currentBlock->statementLineNumbers.erase(&stmt);
        initBlock->addStatement(&stmt, lineNum);
    }
    
    // Check block evaluates the loop condition (var <= end for positive STEP)
    BasicBlock* loopCheck = createNewBlock("FOR Loop Check");
    loopCheck->isLoopHeader = true;  // The check block is the actual loop header
    
    BasicBlock* loopBody = createNewBlock("FOR Loop Body");
    
    // Track loop context - stores check block as header (for NEXT to jump back to)
    // Exit block will be set to -1 initially and created by NEXT
    LoopContext ctx;
    ctx.headerBlock = loopCheck->id;  // NEXT jumps back to check block
    ctx.exitBlock = -1;  // Will be created by NEXT processing
    ctx.variable = stmt.variable;
    m_loopStack.push_back(ctx);
    
    // Store FOR loop structure for buildEdges to use (exit block added later)
    ControlFlowGraph::ForLoopBlocks forBlocks;
    forBlocks.initBlock = initBlock->id;
    forBlocks.checkBlock = loopCheck->id;
    forBlocks.bodyBlock = loopBody->id;
    forBlocks.exitBlock = -1;  // Will be set by NEXT
    forBlocks.variable = stmt.variable;
    m_currentCFG->forLoopStructure[initBlock->id] = forBlocks;
    
    // Keep legacy mapping for backwards compatibility
    m_currentCFG->forLoopHeaders[initBlock->id] = loopCheck->id;
    m_currentCFG->forLoopHeaders[loopCheck->id] = loopBody->id;
    
    // Continue building in the loop body
    m_currentBlock = loopBody;
}

void CFGBuilder::processForInStatement(const ForInStatement& stmt, BasicBlock* currentBlock) {
    // FOR...IN creates loop header similar to FOR
    BasicBlock* loopHeader = createNewBlock("FOR...IN Loop Header");
    loopHeader->isLoopHeader = true;
    
    BasicBlock* loopBody = createNewBlock("FOR...IN Loop Body");
    BasicBlock* loopExit = createNewBlock("After FOR...IN");
    loopExit->isLoopExit = true;
    
    // Track loop context
    LoopContext ctx;
    ctx.headerBlock = loopHeader->id;
    ctx.exitBlock = loopExit->id;
    ctx.variable = stmt.variable;
    m_loopStack.push_back(ctx);
    
    // Remember this FOR...IN loop
    m_currentCFG->forLoopHeaders[loopHeader->id] = loopHeader->id;
    
    m_currentBlock = loopBody;
}

void CFGBuilder::processWhileStatement(const WhileStatement& stmt, BasicBlock* currentBlock) {
    // WHILE creates loop header with condition
    BasicBlock* loopHeader = createNewBlock("WHILE Loop Header");
    loopHeader->isLoopHeader = true;
    
    // Add the WHILE statement to the header block (it was already added to currentBlock)
    // We need to move it to the header block
    if (!currentBlock->statements.empty() && currentBlock->statements.back() == &stmt) {
        // Get the line number for this statement
        int lineNum = 0;
        auto it = currentBlock->statementLineNumbers.find(&stmt);
        if (it != currentBlock->statementLineNumbers.end()) {
            lineNum = it->second;
        }
        
        // Remove from current block and add to header
        currentBlock->statements.pop_back();
        currentBlock->statementLineNumbers.erase(&stmt);
        loopHeader->addStatement(&stmt, lineNum);
    }
    
    BasicBlock* loopBody = createNewBlock("WHILE Loop Body");
    
    // Track loop context
    LoopContext ctx;
    ctx.headerBlock = loopHeader->id;
    ctx.exitBlock = -1;  // Will be set when we encounter WEND
    m_loopStack.push_back(ctx);
    
    m_currentCFG->whileLoopHeaders[loopHeader->id] = loopHeader->id;
    
    m_currentBlock = loopBody;
}

void CFGBuilder::processCaseStatement(const CaseStatement& stmt, BasicBlock* currentBlock) {
    // SELECT CASE creates a multi-way branch structure
    // Structure:
    //   - SELECT block (current): Evaluates the SELECT CASE expression
    //   - Test blocks: One per CASE clause, contains comparison logic
    //   - Body blocks: One per CASE clause, executes CASE statements
    //   - ELSE block: Optional, for ELSE clause
    //   - Exit block: Continue after END SELECT
    
    // The SELECT statement stays in current block for expression evaluation
    
    // Create exit block
    BasicBlock* exitBlock = createNewBlock("After SELECT CASE");
    
    // For each CASE clause, create test block and body block
    std::vector<int> testBlockIds;
    std::vector<int> bodyBlockIds;
    
    for (size_t i = 0; i < stmt.whenClauses.size(); i++) {
        // Test block will contain the comparison logic
        BasicBlock* testBlock = createNewBlock("CASE " + std::to_string(i) + " Test");
        testBlockIds.push_back(testBlock->id);
        
        // Body block will contain the CASE statements
        BasicBlock* bodyBlock = createNewBlock("CASE " + std::to_string(i) + " Body");
        bodyBlockIds.push_back(bodyBlock->id);
        
        // Process statements in the body block
        m_currentBlock = bodyBlock;
        for (const auto& caseStmt : stmt.whenClauses[i].statements) {
            if (caseStmt) {
                processStatement(*caseStmt, bodyBlock, 0);
            }
        }
    }
    
    // Create ELSE block if there are OTHERWISE statements
    int elseBlockId = -1;
    if (!stmt.otherwiseStatements.empty()) {
        BasicBlock* elseBlock = createNewBlock("CASE ELSE");
        elseBlockId = elseBlock->id;
        
        m_currentBlock = elseBlock;
        for (const auto& elseStmt : stmt.otherwiseStatements) {
            if (elseStmt) {
                processStatement(*elseStmt, elseBlock, 0);
            }
        }
    }
    
    // Store SELECT CASE info for buildEdges phase
    SelectCaseContext ctx;
    ctx.selectBlock = currentBlock->id;
    ctx.testBlocks = testBlockIds;
    ctx.bodyBlocks = bodyBlockIds;
    ctx.elseBlock = elseBlockId;
    ctx.exitBlock = exitBlock->id;
    ctx.caseStatement = &stmt;
    m_selectCaseStack.push_back(ctx);
    
    // Continue with exit block
    m_currentBlock = exitBlock;
}

void CFGBuilder::processTryCatchStatement(const TryCatchStatement& stmt, BasicBlock* currentBlock) {
    // TRY/CATCH/FINALLY creates an exception handling structure
    // Structure:
    //   - TRY block (current): Sets up exception context (setjmp)
    //   - TRY body block: Executes TRY statements
    //   - Dispatch block: Checks error code and routes to appropriate CATCH
    //   - CATCH blocks: One per CATCH clause
    //   - FINALLY block: Optional, executes cleanup code
    //   - Exit block: Continue after END TRY
    
    // The TRY statement (setup) stays in current block
    int trySetupBlockId = currentBlock->id;
    
    // Create TRY body block
    BasicBlock* tryBodyBlock = createNewBlock("TRY Body");
    int tryBodyBlockId = tryBodyBlock->id;
    
    // Process TRY block statements
    m_currentBlock = tryBodyBlock;
    for (const auto& tryStmt : stmt.tryBlock) {
        if (tryStmt) {
            processStatement(*tryStmt, m_currentBlock, 0);
        }
    }
    
    // Create exception dispatch block
    BasicBlock* dispatchBlock = createNewBlock("Exception Dispatch");
    int dispatchBlockId = dispatchBlock->id;
    
    // Create CATCH blocks
    std::vector<int> catchBlockIds;
    for (size_t i = 0; i < stmt.catchClauses.size(); i++) {
        const auto& clause = stmt.catchClauses[i];
        
        std::string catchLabel = "CATCH";
        if (!clause.errorCodes.empty()) {
            catchLabel += " ";
            for (size_t j = 0; j < clause.errorCodes.size(); j++) {
                if (j > 0) catchLabel += ",";
                catchLabel += std::to_string(clause.errorCodes[j]);
            }
        } else {
            catchLabel += " (all)";
        }
        
        BasicBlock* catchBlock = createNewBlock(catchLabel);
        catchBlockIds.push_back(catchBlock->id);
        
        // Process CATCH block statements
        m_currentBlock = catchBlock;
        for (const auto& catchStmt : clause.block) {
            if (catchStmt) {
                processStatement(*catchStmt, m_currentBlock, 0);
            }
        }
    }
    
    // Create FINALLY block if present
    int finallyBlockId = -1;
    if (stmt.hasFinally) {
        BasicBlock* finallyBlock = createNewBlock("FINALLY");
        finallyBlockId = finallyBlock->id;
        
        // Process FINALLY block statements
        m_currentBlock = finallyBlock;
        for (const auto& finallyStmt : stmt.finallyBlock) {
            if (finallyStmt) {
                processStatement(*finallyStmt, m_currentBlock, 0);
            }
        }
    }
    
    // Create exit block
    BasicBlock* exitBlock = createNewBlock("After TRY");
    int exitBlockId = exitBlock->id;
    
    // Store TRY/CATCH structure info for buildEdges phase
    TryCatchContext ctx;
    ctx.tryBlock = trySetupBlockId;
    ctx.tryBodyBlock = tryBodyBlockId;
    ctx.dispatchBlock = dispatchBlockId;
    ctx.catchBlocks = catchBlockIds;
    ctx.finallyBlock = finallyBlockId;
    ctx.exitBlock = exitBlockId;
    ctx.hasFinally = stmt.hasFinally;
    ctx.tryStatement = &stmt;
    m_tryCatchStack.push_back(ctx);
    
    // Also store in the CFG for later reference
    ControlFlowGraph::TryCatchBlocks cfgBlocks;
    cfgBlocks.tryBlock = trySetupBlockId;
    cfgBlocks.tryBodyBlock = tryBodyBlockId;
    cfgBlocks.dispatchBlock = dispatchBlockId;
    cfgBlocks.catchBlocks = catchBlockIds;
    cfgBlocks.finallyBlock = finallyBlockId;
    cfgBlocks.exitBlock = exitBlockId;
    cfgBlocks.hasFinally = stmt.hasFinally;
    cfgBlocks.tryStatement = &stmt;
    m_currentCFG->tryCatchStructure[trySetupBlockId] = cfgBlocks;
    
    // Continue with exit block
    m_currentBlock = exitBlock;
}

void CFGBuilder::processRepeatStatement(const RepeatStatement& stmt, BasicBlock* currentBlock) {
    // REPEAT creates loop body
    BasicBlock* loopBody = createNewBlock("REPEAT Loop Body");
    loopBody->isLoopHeader = true;
    
    BasicBlock* loopExit = createNewBlock("After REPEAT");
    loopExit->isLoopExit = true;
    
    // Track loop context
    LoopContext ctx;
    ctx.headerBlock = loopBody->id;
    ctx.exitBlock = loopExit->id;
    m_loopStack.push_back(ctx);
    
    m_currentCFG->repeatLoopHeaders[loopBody->id] = loopBody->id;
    
    m_currentBlock = loopBody;
}

void CFGBuilder::processDoStatement(const DoStatement& stmt, BasicBlock* currentBlock) {
    // DO creates loop structure - behavior depends on condition type
    BasicBlock* loopHeader = createNewBlock("DO Loop Header");
    loopHeader->isLoopHeader = true;
    
    // Add the DO statement to the header block (it was already added to currentBlock)
    // We need to move it to the header block
    if (!currentBlock->statements.empty() && currentBlock->statements.back() == &stmt) {
        // Get the line number for this statement
        int lineNum = 0;
        auto it = currentBlock->statementLineNumbers.find(&stmt);
        if (it != currentBlock->statementLineNumbers.end()) {
            lineNum = it->second;
        }
        
        // Remove from current block and add to header
        currentBlock->statements.pop_back();
        currentBlock->statementLineNumbers.erase(&stmt);
        loopHeader->addStatement(&stmt, lineNum);
    }
    
    BasicBlock* loopBody = createNewBlock("DO Loop Body");
    BasicBlock* loopExit = createNewBlock("After DO");
    loopExit->isLoopExit = true;
    
    // Track loop context
    LoopContext ctx;
    ctx.headerBlock = loopHeader->id;
    ctx.exitBlock = loopExit->id;
    m_loopStack.push_back(ctx);
    
    m_currentCFG->doLoopHeaders[loopHeader->id] = loopHeader->id;
    
    // Store DO loop structure (similar to FOR loops)
    ControlFlowGraph::DoLoopBlocks doBlocks;
    doBlocks.headerBlock = loopHeader->id;
    doBlocks.bodyBlock = loopBody->id;
    doBlocks.exitBlock = loopExit->id;
    m_currentCFG->doLoopStructure[loopHeader->id] = doBlocks;
    
    m_currentBlock = loopBody;
}

void CFGBuilder::processFunctionStatement(const FunctionStatement& stmt, BasicBlock* currentBlock) {
    // Create a new CFG for this function
    ControlFlowGraph* funcCFG = m_programCFG->createFunctionCFG(stmt.functionName);
    
    // Store function metadata
    funcCFG->functionName = stmt.functionName;
    funcCFG->parameters = stmt.parameters;
    
    // Process parameter types - check both AS types and type suffixes
    for (size_t i = 0; i < stmt.parameters.size(); i++) {
        VariableType vt = VariableType::DOUBLE;  // Default type
        
        // First check if there's an AS typename declaration
        if (i < stmt.parameterAsTypes.size() && !stmt.parameterAsTypes[i].empty()) {
            std::string asType = stmt.parameterAsTypes[i];
            // Convert to uppercase for case-insensitive comparison
            std::string upperType = asType;
            std::transform(upperType.begin(), upperType.end(), upperType.begin(), ::toupper);
            
            if (upperType == "INTEGER" || upperType == "INT") {
                vt = VariableType::INT;
            } else if (upperType == "DOUBLE") {
                vt = VariableType::DOUBLE;
            } else if (upperType == "SINGLE" || upperType == "FLOAT") {
                vt = VariableType::FLOAT;
            } else if (upperType == "STRING") {
                vt = VariableType::STRING;
            } else if (upperType == "LONG") {
                vt = VariableType::INT;
            }
            // TODO: Handle user-defined types
        } else if (i < stmt.parameterTypes.size()) {
            // Check type suffix
            switch (stmt.parameterTypes[i]) {
                case TokenType::TYPE_INT: vt = VariableType::INT; break;
                case TokenType::TYPE_FLOAT: vt = VariableType::FLOAT; break;
                case TokenType::TYPE_DOUBLE: vt = VariableType::DOUBLE; break;
                case TokenType::TYPE_STRING: vt = VariableType::STRING; break;
                default: break;
            }
        }
        
        funcCFG->parameterTypes.push_back(vt);
    }
    
    // Set return type
    if (stmt.hasReturnAsType) {
        // TODO: Map returnTypeAsName to VariableType
        funcCFG->returnType = VariableType::INT; // Default for now
    } else {
        switch (stmt.returnTypeSuffix) {
            case TokenType::TYPE_INT: funcCFG->returnType = VariableType::INT; break;
            case TokenType::TYPE_FLOAT: funcCFG->returnType = VariableType::FLOAT; break;
            case TokenType::TYPE_DOUBLE: funcCFG->returnType = VariableType::DOUBLE; break;
            case TokenType::TYPE_STRING: funcCFG->returnType = VariableType::STRING; break;
            default: funcCFG->returnType = VariableType::INT; break;
        }
    }
    
    // Save current CFG context
    ControlFlowGraph* savedCFG = m_currentCFG;
    BasicBlock* savedBlock = m_currentBlock;
    
    // Switch to function CFG
    m_currentCFG = funcCFG;
    
    // Create entry block for function
    BasicBlock* entryBlock = createNewBlock("Function Entry");
    funcCFG->entryBlock = entryBlock->id;
    m_currentBlock = entryBlock;
    
    // Process function body statements
    for (const auto& bodyStmt : stmt.body) {
        if (bodyStmt) {
            processStatement(*bodyStmt, m_currentBlock, 0);
        }
    }
    
    // Create exit block
    if (m_createExitBlock) {
        BasicBlock* exitBlock = createNewBlock("Function Exit");
        exitBlock->isTerminator = true;
        funcCFG->exitBlock = exitBlock->id;
        
        if (m_currentBlock && m_currentBlock->id != exitBlock->id) {
            addFallthroughEdge(m_currentBlock->id, exitBlock->id);
        }
    }
    
    // Restore context
    m_currentCFG = savedCFG;
    m_currentBlock = savedBlock;
}

void CFGBuilder::processDefStatement(const DefStatement& stmt, BasicBlock* currentBlock) {
    // DEF FN creates a simple single-expression function
    // Create a new CFG for this function
    ControlFlowGraph* funcCFG = m_programCFG->createFunctionCFG(stmt.functionName);
    
    // Store function metadata
    funcCFG->functionName = stmt.functionName;
    funcCFG->parameters = stmt.parameters;
    funcCFG->defStatement = &stmt;  // Store pointer to statement for codegen
    
    // Get return type and parameter types from semantic analyzer symbol table
    // The semantic analyzer has already inferred these types correctly
    const FunctionSymbol* funcSymbol = nullptr;
    if (m_symbols) {
        auto it = m_symbols->functions.find(stmt.functionName);
        if (it != m_symbols->functions.end()) {
            funcSymbol = &it->second;
        }
    }
    
    if (funcSymbol) {
        // Use types from semantic analyzer (already validated)
        funcCFG->returnType = funcSymbol->returnType;
        funcCFG->parameterTypes = funcSymbol->parameterTypes;
    } else {
        // Fallback if semantic analyzer didn't process this (shouldn't happen)
        funcCFG->returnType = inferTypeFromName(stmt.functionName);
        for (size_t i = 0; i < stmt.parameters.size(); ++i) {
            funcCFG->parameterTypes.push_back(inferTypeFromName(stmt.parameters[i]));
        }
    }
    
    // Save current CFG context
    ControlFlowGraph* savedCFG = m_currentCFG;
    BasicBlock* savedBlock = m_currentBlock;
    
    // Switch to function CFG
    m_currentCFG = funcCFG;
    
    // Create entry block for function - this will contain the RETURN expression
    BasicBlock* entryBlock = createNewBlock("DEF FN Entry");
    funcCFG->entryBlock = entryBlock->id;
    m_currentBlock = entryBlock;
    
    // DEF FN body is just a single expression - we'll handle it in codegen
    // Store the expression in a synthetic RETURN statement
    // (The codegen will need to access stmt.body directly)
    
    // Create exit block
    if (m_createExitBlock) {
        BasicBlock* exitBlock = createNewBlock("DEF FN Exit");
        exitBlock->isTerminator = true;
        funcCFG->exitBlock = exitBlock->id;
        
        // Entry flows to exit
        addFallthroughEdge(entryBlock->id, exitBlock->id);
    }
    
    // Build edges for this simple CFG
    ControlFlowGraph* edgeCFG = m_currentCFG;
    m_currentCFG = savedCFG;
    m_currentBlock = savedBlock;
    
    // We need to build edges for the DEF FN CFG
    ControlFlowGraph* tmpCFG = m_currentCFG;
    m_currentCFG = edgeCFG;
    buildEdges();
    m_currentCFG = tmpCFG;
    
    // Restore context
    m_currentCFG = savedCFG;
    m_currentBlock = savedBlock;
}

void CFGBuilder::processSubStatement(const SubStatement& stmt, BasicBlock* currentBlock) {
    // Create a new CFG for this SUB (similar to FUNCTION but no return value)
    ControlFlowGraph* subCFG = m_programCFG->createFunctionCFG(stmt.subName);
    
    // Store SUB metadata
    subCFG->functionName = stmt.subName;
    subCFG->parameters = stmt.parameters;
    
    // Process parameter types - check both AS types and type suffixes
    for (size_t i = 0; i < stmt.parameters.size(); i++) {
        VariableType vt = VariableType::DOUBLE;  // Default type
        
        // First check if there's an AS typename declaration
        if (i < stmt.parameterAsTypes.size() && !stmt.parameterAsTypes[i].empty()) {
            std::string asType = stmt.parameterAsTypes[i];
            // Convert to uppercase for case-insensitive comparison
            std::string upperType = asType;
            std::transform(upperType.begin(), upperType.end(), upperType.begin(), ::toupper);
            
            if (upperType == "INTEGER" || upperType == "INT") {
                vt = VariableType::INT;
            } else if (upperType == "DOUBLE") {
                vt = VariableType::DOUBLE;
            } else if (upperType == "SINGLE" || upperType == "FLOAT") {
                vt = VariableType::FLOAT;
            } else if (upperType == "STRING") {
                vt = VariableType::STRING;
            } else if (upperType == "LONG") {
                vt = VariableType::INT;
            }
            // TODO: Handle user-defined types
        } else if (i < stmt.parameterTypes.size()) {
            // Check type suffix
            switch (stmt.parameterTypes[i]) {
                case TokenType::TYPE_INT: vt = VariableType::INT; break;
                case TokenType::TYPE_FLOAT: vt = VariableType::FLOAT; break;
                case TokenType::TYPE_DOUBLE: vt = VariableType::DOUBLE; break;
                case TokenType::TYPE_STRING: vt = VariableType::STRING; break;
                default: break;
            }
        }
        
        subCFG->parameterTypes.push_back(vt);
    }
    subCFG->returnType = VariableType::UNKNOWN; // SUBs don't return values
    
    // Save current CFG context
    ControlFlowGraph* savedCFG = m_currentCFG;
    BasicBlock* savedBlock = m_currentBlock;
    
    // Switch to SUB CFG
    m_currentCFG = subCFG;
    
    // Create entry block for SUB
    BasicBlock* entryBlock = createNewBlock("SUB Entry");
    subCFG->entryBlock = entryBlock->id;
    m_currentBlock = entryBlock;
    
    // Process SUB body statements
    for (const auto& bodyStmt : stmt.body) {
        if (bodyStmt) {
            processStatement(*bodyStmt, m_currentBlock, 0);
        }
    }
    
    // Create exit block
    if (m_createExitBlock) {
        BasicBlock* exitBlock = createNewBlock("SUB Exit");
        exitBlock->isTerminator = true;
        subCFG->exitBlock = exitBlock->id;
        
        if (m_currentBlock && m_currentBlock->id != exitBlock->id) {
            addFallthroughEdge(m_currentBlock->id, exitBlock->id);
        }
    }
    
    // Restore context
    m_currentCFG = savedCFG;
    m_currentBlock = savedBlock;
}

// =============================================================================
// Phase 2: Build Control Flow Edges
// =============================================================================

void CFGBuilder::buildEdges() {
    // Walk through blocks and create edges based on statements
    for (const auto& block : m_currentCFG->blocks) {
        // Check if this is a FOR loop init block
        auto forStructIt = m_currentCFG->forLoopStructure.find(block->id);
        if (forStructIt != m_currentCFG->forLoopStructure.end()) {
            const auto& forBlocks = forStructIt->second;
            
            // FOR init block: unconditional jump to check block
            addUnconditionalEdge(block->id, forBlocks.checkBlock);
            
            // Also need to ensure predecessor blocks connect to this init block
            // This handles nested FOR loops where the outer body should flow to inner init
            if (block->id > 0) {
                const auto& prevBlock = m_currentCFG->blocks[block->id - 1];
                // If previous block doesn't already have this block as a successor, add fallthrough
                if (std::find(prevBlock->successors.begin(), prevBlock->successors.end(), block->id) == prevBlock->successors.end()) {
                    // Check if previous block is a body block that should flow here
                    bool isPreviousBodyBlock = false;
                    for (const auto& pair : m_currentCFG->forLoopStructure) {
                        if (pair.second.bodyBlock == prevBlock->id) {
                            isPreviousBodyBlock = true;
                            break;
                        }
                    }
                    
                    // If it's not already handled and is not a terminator block, add fallthrough
                    if (!prevBlock->isTerminator && !prevBlock->statements.empty()) {
                        const Statement* lastStmt = prevBlock->statements.back();
                        ASTNodeType lastType = lastStmt->getType();
                        // If the last statement isn't a control flow statement, add fallthrough
                        if (lastType != ASTNodeType::STMT_GOTO && 
                            lastType != ASTNodeType::STMT_RETURN &&
                            lastType != ASTNodeType::STMT_END &&
                            lastType != ASTNodeType::STMT_EXIT &&
                            lastType != ASTNodeType::STMT_NEXT &&
                            lastType != ASTNodeType::STMT_WEND &&
                            lastType != ASTNodeType::STMT_LOOP &&
                            lastType != ASTNodeType::STMT_UNTIL) {
                            addFallthroughEdge(prevBlock->id, block->id);
                        }
                    }
                }
            }
            
            continue;  // Skip regular processing for FOR init blocks
        }
        
        // Check if this is a FOR loop check block
        bool isForCheckBlock = false;
        for (const auto& pair : m_currentCFG->forLoopStructure) {
            if (pair.second.checkBlock == block->id) {
                isForCheckBlock = true;
                const auto& forBlocks = pair.second;
                
                // FOR check block: conditional branch
                // True condition: go to body
                addConditionalEdge(block->id, forBlocks.bodyBlock, "true");
                // False condition: go to exit (should be set by NEXT processing)
                if (forBlocks.exitBlock >= 0) {
                    addConditionalEdge(block->id, forBlocks.exitBlock, "false");
                }
                break;
            }
        }
        if (isForCheckBlock) {
            continue;  // Skip regular processing for FOR check blocks
        }
        
        // Check if this is a SELECT CASE test block (empty but needs special handling)
        bool isSelectCaseTestBlock = false;
        for (const auto& ctx : m_selectCaseStack) {
            for (size_t i = 0; i < ctx.testBlocks.size(); i++) {
                if (block->id == ctx.testBlocks[i]) {
                    isSelectCaseTestBlock = true;
                    // Test block: conditional branch to body or next test/else/exit
                    // True: jump to body
                    addConditionalEdge(block->id, ctx.bodyBlocks[i], "true");
                    
                    // False: jump to next test, else, or exit
                    if (i + 1 < ctx.testBlocks.size()) {
                        // Next test block
                        addConditionalEdge(block->id, ctx.testBlocks[i + 1], "false");
                    } else if (ctx.elseBlock >= 0) {
                        // ELSE block
                        addConditionalEdge(block->id, ctx.elseBlock, "false");
                    } else {
                        // Exit (no match)
                        addConditionalEdge(block->id, ctx.exitBlock, "false");
                    }
                    break;
                }
            }
            if (isSelectCaseTestBlock) break;
        }
        
        if (isSelectCaseTestBlock) {
            continue;  // Skip regular processing for test blocks
        }
        
        // Check if this is a TRY/CATCH structure block (dispatch, catch, finally)
        bool isTryCatchBlock = false;
        for (const auto& ctx : m_tryCatchStack) {
            // Check if this is the dispatch block
            if (block->id == ctx.dispatchBlock) {
                isTryCatchBlock = true;
                // Dispatch block: conditional branches to each CATCH block based on error code
                // First, check each CATCH clause in order
                for (size_t i = 0; i < ctx.catchBlocks.size(); i++) {
                    addConditionalEdge(block->id, ctx.catchBlocks[i], "error matches");
                }
                // If no CATCH matches, re-throw (goes to outer handler or terminates)
                // We don't add an explicit edge here as it's handled by runtime
                break;
            }
            
            // Check if this is a TRY body block
            if (block->id == ctx.tryBodyBlock) {
                isTryCatchBlock = true;
                // TRY body on normal completion: jump to FINALLY or exit
                if (ctx.hasFinally) {
                    addFallthroughEdge(block->id, ctx.finallyBlock);
                } else {
                    addFallthroughEdge(block->id, ctx.exitBlock);
                }
                // Note: Exception dispatch is reached via longjmp, not normal CFG flow
                break;
            }
            
            // Check if this is a CATCH block
            for (size_t i = 0; i < ctx.catchBlocks.size(); i++) {
                if (block->id == ctx.catchBlocks[i]) {
                    isTryCatchBlock = true;
                    // CATCH block on completion: jump to FINALLY or exit
                    if (ctx.hasFinally) {
                        addFallthroughEdge(block->id, ctx.finallyBlock);
                    } else {
                        addFallthroughEdge(block->id, ctx.exitBlock);
                    }
                    break;
                }
            }
            if (isTryCatchBlock) break;
            
            // Check if this is a FINALLY block
            if (ctx.hasFinally && block->id == ctx.finallyBlock) {
                isTryCatchBlock = true;
                // FINALLY always jumps to exit
                addFallthroughEdge(block->id, ctx.exitBlock);
                break;
            }
        }
        
        if (isTryCatchBlock) {
            continue;  // Skip regular processing for TRY/CATCH blocks
        }
        
        if (block->statements.empty()) {
            // Empty block - fallthrough to next only if no explicit successors
            if (block->successors.empty() && 
                block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                addFallthroughEdge(block->id, block->id + 1);
            }
            continue;
        }
        
        // Check last statement in block for control flow
        const Statement* lastStmt = block->statements.back();
        ASTNodeType type = lastStmt->getType();
        
        switch (type) {
            case ASTNodeType::STMT_GOTO: {
                // Unconditional jump to target line (or next available line)
                const auto& gotoStmt = static_cast<const GotoStatement&>(*lastStmt);
                int targetBlock = m_currentCFG->getBlockForLineOrNext(gotoStmt.lineNumber);
                if (targetBlock >= 0) {
                    addUnconditionalEdge(block->id, targetBlock);
                }
                break;
            }
            
            case ASTNodeType::STMT_GOSUB: {
                // Call to subroutine (or next available line), then continue
                const auto& gosubStmt = static_cast<const GosubStatement&>(*lastStmt);
                int targetBlock = m_currentCFG->getBlockForLineOrNext(gosubStmt.lineNumber);
                if (targetBlock >= 0) {
                    addCallEdge(block->id, targetBlock);
                }
                // Continue to the return block that was created by processGosubStatement
                // Use the mapping instead of assuming block->id + 1
                auto it = m_gosubReturnMap.find(block->id);
                if (it != m_gosubReturnMap.end()) {
                    // Found the recorded return block
                    addFallthroughEdge(block->id, it->second);
                } else {
                    // Fallback to old behavior (shouldn't happen with proper processing)
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_ON_GOTO: {
                // Multiple potential jump targets based on selector expression
                const auto& onGotoStmt = static_cast<const OnGotoStatement&>(*lastStmt);
                
                // Add edges to all possible targets
                for (size_t i = 0; i < onGotoStmt.isLabelList.size(); ++i) {
                    int targetBlock = -1;
                    if (onGotoStmt.isLabelList[i]) {
                        // Symbolic label
                        if (m_symbols) {
                            auto it = m_symbols->labels.find(onGotoStmt.labels[i]);
                            if (it != m_symbols->labels.end()) {
                                int labelLine = it->second.programLineIndex;
                                if (labelLine >= 0) {
                                    targetBlock = m_currentCFG->getBlockForLine(labelLine);
                                }
                            }
                        }
                    } else {
                        // Line number
                        targetBlock = m_currentCFG->getBlockForLine(onGotoStmt.lineNumbers[i]);
                    }
                    
                    if (targetBlock >= 0) {
                        // Add conditional edge (selector == i+1)
                        addConditionalEdge(block->id, targetBlock, std::to_string(i + 1));
                    }
                }
                
                // If selector is out of range, continue to next block
                if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                    addConditionalEdge(block->id, block->id + 1, "default");
                }
                break;
            }
            
            case ASTNodeType::STMT_ON_GOSUB: {
                // Multiple potential subroutine calls based on selector expression
                const auto& onGosubStmt = static_cast<const OnGosubStatement&>(*lastStmt);
                
                // Add call edges to all possible targets
                for (size_t i = 0; i < onGosubStmt.isLabelList.size(); ++i) {
                    int targetBlock = -1;
                    if (onGosubStmt.isLabelList[i]) {
                        // Symbolic label
                        if (m_symbols) {
                            auto it = m_symbols->labels.find(onGosubStmt.labels[i]);
                            if (it != m_symbols->labels.end()) {
                                int labelLine = it->second.programLineIndex;
                                if (labelLine >= 0) {
                                    targetBlock = m_currentCFG->getBlockForLine(labelLine);
                                }
                            }
                        }
                    } else {
                        // Line number
                        targetBlock = m_currentCFG->getBlockForLine(onGosubStmt.lineNumbers[i]);
                    }
                    
                    if (targetBlock >= 0) {
                        // Add call edge (selector == i+1)
                        addCallEdge(block->id, targetBlock);
                    }
                }
                
                // If selector is out of range, continue to next block
                if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                    addFallthroughEdge(block->id, block->id + 1);
                }
                break;
            }
            
            case ASTNodeType::STMT_IF: {
                // Conditional branch
                const auto& ifStmt = static_cast<const IfStatement&>(*lastStmt);
                if (ifStmt.hasGoto) {
                    // Branch to line (or next available line) or continue
                    int targetBlock = m_currentCFG->getBlockForLineOrNext(ifStmt.gotoLine);
                    if (targetBlock >= 0) {
                        addConditionalEdge(block->id, targetBlock, "true");
                    }
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addConditionalEdge(block->id, block->id + 1, "false");
                    }
                } else if (ifStmt.isMultiLine) {
                    // Multi-line IF...END IF
                    // The successors were already set up in processIfStatement
                    // Nothing to do here - edges are already correct
                }
                break;
            }
            
            case ASTNodeType::STMT_WHILE: {
                // WHILE header with condition - needs conditional edges
                // Body should be the next block, exit will be found later
                auto it = m_currentCFG->whileLoopHeaders.find(block->id);
                if (it != m_currentCFG->whileLoopHeaders.end()) {
                    // This is a WHILE header
                    // True condition: go to body (next block)
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addConditionalEdge(block->id, block->id + 1, "true");
                    }
                    
                    // False condition: We need to find the exit block
                    // The exit block should be right after the matching WEND
                    // We need to count nesting levels to find the matching WEND
                    // IMPORTANT: We must look at ALL blocks, including empty ones, and
                    // check statements in the order they appear in blocks
                    int nestingLevel = 0;
                    bool foundWend = false;
                    for (size_t i = block->id + 1; i < m_currentCFG->blocks.size(); i++) {
                        const auto& futureBlock = m_currentCFG->blocks[i];
                        
                        // Check all statements in this block
                        for (const Statement* stmt : futureBlock->statements) {
                            if (stmt->getType() == ASTNodeType::STMT_WHILE) {
                                nestingLevel++;
                            } else if (stmt->getType() == ASTNodeType::STMT_WEND) {
                                if (nestingLevel == 0) {
                                    // Found the matching WEND
                                    // The WEND statement is in block i
                                    // After a WEND, the next block should be "After WHILE"
                                    // which is the exit block for this loop
                                    if (i + 1 < m_currentCFG->blocks.size()) {
                                        addConditionalEdge(block->id, i + 1, "false");
                                        foundWend = true;
                                    }
                                    goto found_wend;
                                }
                                nestingLevel--;
                            }
                        }
                    }
                    found_wend:
                    // If we didn't find a matching WEND, something is wrong
                    if (!foundWend && block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        // Fallback: exit to next block (shouldn't happen in well-formed code)
                        addConditionalEdge(block->id, block->id + 1, "false");
                    }
                } else {
                    // Fallthrough if not a loop header
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_DO: {
                // DO header - needs conditional or unconditional edges based on condition type
                auto it = m_currentCFG->doLoopHeaders.find(block->id);
                if (it != m_currentCFG->doLoopHeaders.end()) {
                    // This is a DO header
                    const auto& doStmt = static_cast<const DoStatement&>(*lastStmt);
                    
                    if (doStmt.conditionType == DoStatement::ConditionType::WHILE ||
                        doStmt.conditionType == DoStatement::ConditionType::UNTIL) {
                        // Pre-test loop: conditional edges
                        // True condition: go to body (next block)
                        if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                            addConditionalEdge(block->id, block->id + 1, "true");
                        }
                        
                        // False condition: find the exit block after matching LOOP
                        int nestingLevel = 0;
                        for (size_t i = block->id + 1; i < m_currentCFG->blocks.size(); i++) {
                            const auto& futureBlock = m_currentCFG->blocks[i];
                            if (!futureBlock->statements.empty()) {
                                for (const Statement* stmt : futureBlock->statements) {
                                    if (stmt->getType() == ASTNodeType::STMT_DO) {
                                        nestingLevel++;
                                    } else if (stmt->getType() == ASTNodeType::STMT_LOOP) {
                                        if (nestingLevel == 0) {
                                            // Found the matching LOOP
                                            // Exit is the block after LOOP
                                            if (i + 1 < m_currentCFG->blocks.size()) {
                                                addConditionalEdge(block->id, i + 1, "false");
                                            }
                                            goto found_loop;
                                        }
                                        nestingLevel--;
                                    }
                                }
                            }
                        }
                        found_loop:;
                    } else {
                        // Plain DO - unconditional jump to body (next block)
                        if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                            addUnconditionalEdge(block->id, block->id + 1);
                        }
                    }
                } else {
                    // Fallthrough if not a loop header
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_UNTIL: {
                // UNTIL is the end of a REPEAT loop
                // Need to create:
                // 1. Conditional edge to exit block (next block) when condition is TRUE
                // 2. Conditional edge back to loop header (REPEAT block) when condition is FALSE
                
                // Find the matching REPEAT by looking for loop context with this block in its range
                LoopContext* loopCtx = nullptr;
                for (auto& ctx : m_loopStack) {
                    // The UNTIL block can be the same as or after the header block
                    if (block->id >= ctx.headerBlock) {
                        loopCtx = &ctx;
                        break;
                    }
                }
                
                if (loopCtx) {
                    // When condition is TRUE, exit loop (go to next block)
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addConditionalEdge(block->id, block->id + 1, "true");
                    }
                    // When condition is FALSE, repeat (go back to loop header)
                    addConditionalEdge(block->id, loopCtx->headerBlock, "false");
                    
                    // Pop this loop context now that we've handled the UNTIL
                    m_loopStack.erase(std::remove_if(m_loopStack.begin(), m_loopStack.end(),
                        [loopCtx](const LoopContext& ctx) { return &ctx == loopCtx; }), 
                        m_loopStack.end());
                } else {
                    // UNTIL without REPEAT - fallthrough
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_LOOP: {
                // LOOP is the end of a DO loop
                // Need to create:
                // 1. Conditional edge to exit block (next block) based on condition
                // 2. Conditional or unconditional edge back to loop header
                
                // Find the matching DO by looking for loop context
                LoopContext* loopCtx = nullptr;
                for (auto& ctx : m_loopStack) {
                    // The LOOP block can be the same as or after the header block
                    if (block->id >= ctx.headerBlock) {
                        loopCtx = &ctx;
                        break;
                    }
                }
                
                if (loopCtx) {
                    // Get the LOOP statement to check condition type
                    const auto& loopStmt = static_cast<const LoopStatement&>(*lastStmt);
                    
                    if (loopStmt.conditionType == LoopStatement::ConditionType::NONE) {
                        // Plain LOOP - unconditional back edge
                        addUnconditionalEdge(block->id, loopCtx->headerBlock);
                    } else {
                        // LOOP WHILE/UNTIL - conditional edges
                        // When condition is TRUE, exit loop (go to next block)
                        if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                            addConditionalEdge(block->id, block->id + 1, "true");
                        }
                        // When condition is FALSE, repeat (go back to loop header)
                        addConditionalEdge(block->id, loopCtx->headerBlock, "false");
                    }
                    
                    // Pop this loop context
                    m_loopStack.erase(std::remove_if(m_loopStack.begin(), m_loopStack.end(),
                        [loopCtx](const LoopContext& ctx) { return &ctx == loopCtx; }), 
                        m_loopStack.end());
                } else {
                    // LOOP without DO - fallthrough
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_WEND: {
                // WEND is the end of a WHILE loop
                // Need to create:
                // 1. Unconditional back edge to loop header (WHILE condition block)
                
                // Find the matching WHILE by looking for loop context
                // Search backwards to find the innermost (most recent) loop
                // IMPORTANT: We need to find the loop that this WEND actually closes
                LoopContext* loopCtx = nullptr;
                int loopCtxIndex = -1;
                
                for (int idx = m_loopStack.size() - 1; idx >= 0; --idx) {
                    // The WEND block should be after the header block
                    if (block->id > m_loopStack[idx].headerBlock) {
                        loopCtx = &m_loopStack[idx];
                        loopCtxIndex = idx;
                        break;
                    }
                }
                
                if (loopCtx) {
                    // Unconditional back edge to WHILE header (condition check)
                    addUnconditionalEdge(block->id, loopCtx->headerBlock);
                    
                    // Pop this loop context
                    // Use index-based erase to avoid iterator invalidation
                    if (loopCtxIndex >= 0 && loopCtxIndex < static_cast<int>(m_loopStack.size())) {
                        m_loopStack.erase(m_loopStack.begin() + loopCtxIndex);
                    }
                } else {
                    // WEND without WHILE - fallthrough
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_NEXT: {
                // NEXT is the end of a FOR loop
                // Create unconditional back edge to loop check block
                // Use the mapping recorded in processStatement
                
                auto it = m_nextToHeaderMap.find(block->id);
                if (it != m_nextToHeaderMap.end()) {
                    // Found the target header block - create back edge
                    addUnconditionalEdge(block->id, it->second);
                } else {
                    // NEXT without matching FOR - fallthrough
                    if (block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
            }
            
            case ASTNodeType::STMT_CASE: {
                // SELECT CASE - multi-way branch
                // Find the matching SELECT CASE context
                SelectCaseContext* caseCtx = nullptr;
                for (auto& ctx : m_selectCaseStack) {
                    if (ctx.selectBlock == block->id) {
                        caseCtx = &ctx;
                        break;
                    }
                }
                
                if (caseCtx && !caseCtx->testBlocks.empty()) {
                    // From SELECT block, jump to first test block
                    addUnconditionalEdge(block->id, caseCtx->testBlocks[0]);
                }
                break;
            }
            
            case ASTNodeType::STMT_TRY_CATCH: {
                // TRY/CATCH - exception handling structure
                // Find the matching TRY/CATCH context
                TryCatchContext* tryCtx = nullptr;
                for (auto& ctx : m_tryCatchStack) {
                    if (ctx.tryBlock == block->id) {
                        tryCtx = &ctx;
                        break;
                    }
                }
                
                if (tryCtx) {
                    // From TRY setup block, conditional jump based on setjmp result
                    // If setjmp returns non-zero (exception), jump to dispatch
                    // If setjmp returns zero (normal), fall through to TRY body
                    addConditionalEdge(block->id, tryCtx->dispatchBlock, "exception");
                    addConditionalEdge(block->id, tryCtx->tryBodyBlock, "normal");
                }
                break;
            }
            
            case ASTNodeType::STMT_THROW:
                // THROW - terminates normal flow, jumps to exception handler
                // The actual exception routing is handled by setjmp/longjmp at runtime
                // In CFG, we mark this as terminator (already done in processStatement)
                break;
            
            case ASTNodeType::STMT_RETURN:
            case ASTNodeType::STMT_END:
                // Terminators - no outgoing edges (or return edge)
                if (m_currentCFG->exitBlock >= 0) {
                    addReturnEdge(block->id, m_currentCFG->exitBlock);
                }
                break;
                
            case ASTNodeType::STMT_EXIT:
                {
                    // EXIT statement handling
                    // For EXIT FOR, edges are already added by NEXT processing (pendingExitBlocks)
                    // For EXIT FUNCTION/SUB, add return edge to function exit
                    const ExitStatement* exitStmt = nullptr;
                    for (const Statement* stmt : block->statements) {
                        if (stmt->getType() == ASTNodeType::STMT_EXIT) {
                            exitStmt = static_cast<const ExitStatement*>(stmt);
                            break;
                        }
                    }
                    
                    if (exitStmt && 
                        (exitStmt->exitType == ExitStatement::ExitType::FUNCTION ||
                         exitStmt->exitType == ExitStatement::ExitType::SUB)) {
                        // EXIT FUNCTION/SUB - jump to function exit
                        if (m_currentCFG->exitBlock >= 0) {
                            addReturnEdge(block->id, m_currentCFG->exitBlock);
                        }
                    }
                    // EXIT FOR edges are already handled by pendingExitBlocks mechanism
                }
                break;
                
            default:
                // Check if this block is part of a SELECT CASE structure
                bool handledBySelectCase = false;
                
                for (const auto& ctx : m_selectCaseStack) {
                    // Check if this is a body block
                    for (size_t i = 0; i < ctx.bodyBlocks.size(); i++) {
                        if (block->id == ctx.bodyBlocks[i]) {
                            // Body block: jump to exit after executing
                            addUnconditionalEdge(block->id, ctx.exitBlock);
                            handledBySelectCase = true;
                            break;
                        }
                    }
                    
                    // Check if this is the else block
                    if (ctx.elseBlock >= 0 && block->id == ctx.elseBlock) {
                        // Else block: jump to exit after executing
                        addUnconditionalEdge(block->id, ctx.exitBlock);
                        handledBySelectCase = true;
                    }
                    
                    if (handledBySelectCase) break;
                }
                
                if (!handledBySelectCase) {
                    // Regular statement - fallthrough to next block
                    // Only add fallthrough if block doesn't already have explicit successors
                    if (block->successors.empty() && 
                        block->id + 1 < static_cast<int>(m_currentCFG->blocks.size())) {
                        addFallthroughEdge(block->id, block->id + 1);
                    }
                }
                break;
        }
    }
}

// =============================================================================
// Phase 3: Identify Loop Structures
// =============================================================================

void CFGBuilder::identifyLoops() {
    // Implement back-edge detection to identify GOTO-based loops
    // A back edge is an edge from block A to block B where B dominates A
    // or in simpler terms, B appears earlier in program order
    
    // For each edge, check if it's a back edge (target block has lower ID than source)
    for (const auto& edge : m_currentCFG->edges) {
        if (edge.type == EdgeType::UNCONDITIONAL && 
            edge.targetBlock < edge.sourceBlock) {
            // This is likely a back edge (GOTO to earlier line)
            BasicBlock* targetBlock = m_currentCFG->getBlock(edge.targetBlock);
            BasicBlock* sourceBlock = m_currentCFG->getBlock(edge.sourceBlock);
            
            if (targetBlock && sourceBlock) {
                // Mark the target as a loop header
                targetBlock->isLoopHeader = true;
                
                // Mark blocks in the loop body between target and source
                for (int blockId = edge.targetBlock; blockId <= edge.sourceBlock; blockId++) {
                    BasicBlock* loopBlock = m_currentCFG->getBlock(blockId);
                    if (loopBlock) {
                        // This block is part of a potential loop
                        // We'll use this information during code generation
                    }
                }
            }
        }
    }
    
    // Also detect cycles using simple DFS
    std::set<int> visited;
    std::set<int> recursionStack;
    
    std::function<void(int)> detectCycles = [&](int blockId) {
        if (recursionStack.count(blockId)) {
            // Found a cycle - mark the target block as a loop header
            BasicBlock* loopHeader = m_currentCFG->getBlock(blockId);
            if (loopHeader) {
                loopHeader->isLoopHeader = true;
            }
            return;
        }
        
        if (visited.count(blockId)) {
            return;
        }
        
        visited.insert(blockId);
        recursionStack.insert(blockId);
        
        BasicBlock* block = m_currentCFG->getBlock(blockId);
        if (block) {
            for (int successor : block->successors) {
                detectCycles(successor);
            }
        }
        
        recursionStack.erase(blockId);
    };
    
    // Start cycle detection from entry block
    if (m_currentCFG->entryBlock >= 0) {
        detectCycles(m_currentCFG->entryBlock);
    }
    
    // Populate CFG's selectCaseInfo map so codegen can look up which CaseStatement each test block belongs to
    for (const auto& ctx : m_selectCaseStack) {
        ControlFlowGraph::SelectCaseInfo info;
        info.selectBlock = ctx.selectBlock;
        info.testBlocks = ctx.testBlocks;
        info.bodyBlocks = ctx.bodyBlocks;
        info.elseBlock = ctx.elseBlock;
        info.exitBlock = ctx.exitBlock;
        info.caseStatement = ctx.caseStatement;
        
        // Map each test block to this SelectCaseInfo
        for (int testBlockId : ctx.testBlocks) {
            m_currentCFG->selectCaseInfo[testBlockId] = info;
        }
    }
}

// =============================================================================
// Phase 4: Identify Subroutines
// =============================================================================

void CFGBuilder::identifySubroutines() {
    // Mark blocks that are GOSUB targets as subroutines
    for (const auto& edge : m_currentCFG->edges) {
        if (edge.type == EdgeType::CALL) {
            BasicBlock* target = m_currentCFG->getBlock(edge.targetBlock);
            if (target) {
                target->isSubroutine = true;
            }
        }
    }
}

// =============================================================================
// Phase 5: Optimize CFG
// =============================================================================

void CFGBuilder::optimizeCFG() {
    // Potential optimizations:
    // - Merge sequential blocks with single predecessor/successor
    // - Remove empty blocks
    // - Simplify edges
    // Not implemented yet
}

// =============================================================================
// Block Management
// =============================================================================

BasicBlock* CFGBuilder::createNewBlock(const std::string& label) {
    auto* block = m_currentCFG->createBlock(label);
    m_blocksCreated++;
    return block;
}

void CFGBuilder::finalizeBlock(BasicBlock* block) {
    // Any finalization needed for a block
}

// =============================================================================
// Edge Creation Helpers
// =============================================================================

void CFGBuilder::addFallthroughEdge(int source, int target) {
    m_currentCFG->addEdge(source, target, EdgeType::FALLTHROUGH);
    m_edgesCreated++;
}

void CFGBuilder::addConditionalEdge(int source, int target, const std::string& label) {
    m_currentCFG->addEdge(source, target, EdgeType::CONDITIONAL, label);
    m_edgesCreated++;
}

void CFGBuilder::addUnconditionalEdge(int source, int target) {
    m_currentCFG->addEdge(source, target, EdgeType::UNCONDITIONAL);
    m_edgesCreated++;
}

void CFGBuilder::addCallEdge(int source, int target) {
    m_currentCFG->addEdge(source, target, EdgeType::CALL);
    m_edgesCreated++;
}

void CFGBuilder::addReturnEdge(int source, int target) {
    m_currentCFG->addEdge(source, target, EdgeType::RETURN);
    m_edgesCreated++;
}

// =============================================================================
// Report Generation
// =============================================================================

std::string CFGBuilder::generateReport(const ControlFlowGraph& cfg) const {
    std::ostringstream oss;
    
    oss << "=== CFG BUILDER REPORT ===\n\n";
    
    // Build statistics
    oss << "Build Statistics:\n";
    oss << "  Blocks Created: " << m_blocksCreated << "\n";
    oss << "  Edges Created: " << m_edgesCreated << "\n";
    oss << "  Loop Headers: " << cfg.getLoopCount() << "\n";
    oss << "\n";
    
    // CFG summary
    oss << "CFG Summary:\n";
    oss << "  Total Blocks: " << cfg.getBlockCount() << "\n";
    oss << "  Total Edges: " << cfg.getEdgeCount() << "\n";
    oss << "  Entry Block: " << cfg.entryBlock << "\n";
    oss << "  Exit Block: " << cfg.exitBlock << "\n";
    oss << "\n";
    
    // Block types
    int loopHeaders = 0;
    int loopExits = 0;
    int subroutines = 0;
    int terminators = 0;
    
    for (const auto& block : cfg.blocks) {
        if (block->isLoopHeader) loopHeaders++;
        if (block->isLoopExit) loopExits++;
        if (block->isSubroutine) subroutines++;
        if (block->isTerminator) terminators++;
    }
    
    oss << "Block Analysis:\n";
    oss << "  Loop Headers: " << loopHeaders << "\n";
    oss << "  Loop Exits: " << loopExits << "\n";
    oss << "  Subroutines: " << subroutines << "\n";
    oss << "  Terminators: " << terminators << "\n";
    oss << "\n";
    
    // Edge types
    int fallthroughEdges = 0;
    int conditionalEdges = 0;
    int unconditionalEdges = 0;
    int callEdges = 0;
    int returnEdges = 0;
    
    for (const auto& edge : cfg.edges) {
        switch (edge.type) {
            case EdgeType::FALLTHROUGH: fallthroughEdges++; break;
            case EdgeType::CONDITIONAL: conditionalEdges++; break;
            case EdgeType::UNCONDITIONAL: unconditionalEdges++; break;
            case EdgeType::CALL: callEdges++; break;
            case EdgeType::RETURN: returnEdges++; break;
        }
    }
    
    oss << "Edge Analysis:\n";
    oss << "  Fallthrough: " << fallthroughEdges << "\n";
    oss << "  Conditional: " << conditionalEdges << "\n";
    oss << "  Unconditional: " << unconditionalEdges << "\n";
    oss << "  Call: " << callEdges << "\n";
    oss << "  Return: " << returnEdges << "\n";
    oss << "\n";
    
    // Full CFG details
    oss << cfg.toString();
    
    oss << "=== END CFG BUILDER REPORT ===\n";
    
    return oss.str();
}

// Helper function to infer type from variable name (suffix-based)
// For 64-bit systems (ARM64/x86-64), DOUBLE is the natural numeric type
VariableType CFGBuilder::inferTypeFromName(const std::string& name) {
    if (name.empty()) return VariableType::DOUBLE;  // Default for 64-bit systems
    
    char lastChar = name.back();
    switch (lastChar) {
        case '%': return VariableType::INT;      // Integer (32/64-bit on modern systems)
        case '!': return VariableType::FLOAT;    // Single-precision (32-bit float)
        case '#': return VariableType::DOUBLE;   // Double-precision (64-bit float)
        case '$': return VariableType::STRING;
        default: return VariableType::DOUBLE;    // Default: DOUBLE for 64-bit systems (ARM64/x86-64)
    }
}

} // namespace FasterBASIC