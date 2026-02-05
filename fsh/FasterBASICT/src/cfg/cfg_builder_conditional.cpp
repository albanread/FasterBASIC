//
// cfg_builder_conditional.cpp
// FasterBASIC - Control Flow Graph Builder Conditional Handlers (V2)
//
// Contains IF...THEN...ELSE and SELECT CASE statement processing.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>
#include <stdexcept>
#include <memory>

namespace FasterBASIC {

// =============================================================================
// SELECT CASE Helper Functions
// =============================================================================

namespace {

// Helper to clone an expression (deep copy)
ExpressionPtr cloneExpression(const Expression* expr) {
    if (!expr) return nullptr;
    
    switch (expr->getType()) {
        case ASTNodeType::EXPR_NUMBER: {
            const auto* num = static_cast<const NumberExpression*>(expr);
            return std::make_unique<NumberExpression>(num->value);
        }
        case ASTNodeType::EXPR_STRING: {
            const auto* str = static_cast<const StringExpression*>(expr);
            return std::make_unique<StringExpression>(str->value, str->hasNonASCII);
        }
        case ASTNodeType::EXPR_VARIABLE: {
            const auto* var = static_cast<const VariableExpression*>(expr);
            return std::make_unique<VariableExpression>(var->name, var->typeSuffix);
        }
        case ASTNodeType::EXPR_BINARY: {
            const auto* bin = static_cast<const BinaryExpression*>(expr);
            return std::make_unique<BinaryExpression>(
                cloneExpression(bin->left.get()),
                bin->op,
                cloneExpression(bin->right.get())
            );
        }
        case ASTNodeType::EXPR_UNARY: {
            const auto* un = static_cast<const UnaryExpression*>(expr);
            return std::make_unique<UnaryExpression>(un->op, cloneExpression(un->expr.get()));
        }
        case ASTNodeType::EXPR_FUNCTION_CALL: {
            const auto* func = static_cast<const FunctionCallExpression*>(expr);
            auto clone = std::make_unique<FunctionCallExpression>(func->name, func->isFN);
            for (const auto& arg : func->arguments) {
                clone->addArgument(cloneExpression(arg.get()));
            }
            return clone;
        }
        case ASTNodeType::EXPR_ARRAY_ACCESS: {
            const auto* arr = static_cast<const ArrayAccessExpression*>(expr);
            auto clone = std::make_unique<ArrayAccessExpression>(arr->name, arr->typeSuffix);
            for (const auto& idx : arr->indices) {
                clone->addIndex(cloneExpression(idx.get()));
            }
            return clone;
        }
        default:
            // For unsupported expression types, return nullptr
            // The caller should handle this gracefully
            return nullptr;
    }
}

// Create a comparison expression: left == right
ExpressionPtr createEqualityCheck(ExpressionPtr left, ExpressionPtr right) {
    return std::make_unique<BinaryExpression>(
        std::move(left),
        TokenType::EQUAL,
        std::move(right)
    );
}

// Create an OR expression: left OR right
ExpressionPtr createOrExpression(ExpressionPtr left, ExpressionPtr right) {
    return std::make_unique<BinaryExpression>(
        std::move(left),
        TokenType::OR,
        std::move(right)
    );
}

// Create an AND expression: left AND right
ExpressionPtr createAndExpression(ExpressionPtr left, ExpressionPtr right) {
    return std::make_unique<BinaryExpression>(
        std::move(left),
        TokenType::AND,
        std::move(right)
    );
}

// Create a range check: selector >= start AND selector <= end
ExpressionPtr createRangeCheck(const Expression* selector, const Expression* start, const Expression* end) {
    auto selectorClone1 = cloneExpression(selector);
    auto selectorClone2 = cloneExpression(selector);
    auto startClone = cloneExpression(start);
    auto endClone = cloneExpression(end);
    
    if (!selectorClone1 || !selectorClone2 || !startClone || !endClone) {
        return nullptr;
    }
    
    // selector >= start
    auto geCheck = std::make_unique<BinaryExpression>(
        std::move(selectorClone1),
        TokenType::GREATER_EQUAL,
        std::move(startClone)
    );
    
    // selector <= end
    auto leCheck = std::make_unique<BinaryExpression>(
        std::move(selectorClone2),
        TokenType::LESS_EQUAL,
        std::move(endClone)
    );
    
    // (selector >= start) AND (selector <= end)
    return createAndExpression(std::move(geCheck), std::move(leCheck));
}

// Create a CASE IS check: selector <op> value
ExpressionPtr createCaseIsCheck(const Expression* selector, TokenType op, const Expression* value) {
    auto selectorClone = cloneExpression(selector);
    auto valueClone = cloneExpression(value);
    
    if (!selectorClone || !valueClone) {
        return nullptr;
    }
    
    return std::make_unique<BinaryExpression>(
        std::move(selectorClone),
        op,
        std::move(valueClone)
    );
}

// Create the condition for a WHEN clause
// Returns: selector == value1 OR selector == value2 OR ... (or range/CASE IS checks)
ExpressionPtr createWhenCondition(const CaseStatement& stmt, const CaseStatement::WhenClause& clause) {
    if (!stmt.caseExpression) {
        return nullptr;
    }
    
    ExpressionPtr condition = nullptr;
    
    // Handle CASE IS: selector <op> value
    if (clause.isCaseIs && clause.caseIsRightExpr) {
        condition = createCaseIsCheck(
            stmt.caseExpression.get(),
            clause.caseIsOperator,
            clause.caseIsRightExpr.get()
        );
    }
    // Handle range: selector >= start AND selector <= end
    else if (clause.isRange && clause.rangeStart && clause.rangeEnd) {
        condition = createRangeCheck(
            stmt.caseExpression.get(),
            clause.rangeStart.get(),
            clause.rangeEnd.get()
        );
    }
    // Handle multiple values: selector == value1 OR selector == value2 OR ...
    else if (!clause.values.empty()) {
        for (const auto& value : clause.values) {
            auto selectorClone = cloneExpression(stmt.caseExpression.get());
            if (!selectorClone) continue;
            
            auto check = createEqualityCheck(std::move(selectorClone), cloneExpression(value.get()));
            
            if (!condition) {
                condition = std::move(check);
            } else {
                condition = createOrExpression(std::move(condition), std::move(check));
            }
        }
    }
    
    return condition;
}

} // anonymous namespace

// =============================================================================
// IF Statement Handler
// =============================================================================
//
// IF...THEN...ELSE...END IF
// Creates blocks for condition, then branch, else branch, and merge point
// Recursively processes nested statements in each branch
//
BasicBlock* CFGBuilder::buildIf(
    const IfStatement& stmt,
    BasicBlock* incoming,
    LoopContext* loop,
    SelectContext* select,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building IF statement" << std::endl;
    }
    
    // Check if this is a single-line IF with GOTO
    if (stmt.hasGoto && stmt.thenStatements.empty() && stmt.elseStatements.empty()) {
        // Single-line IF...THEN GOTO line_number
        // This is just a conditional branch, handle inline
        if (m_debugMode) {
            std::cout << "[CFG] Single-line IF GOTO to line " << stmt.gotoLine << std::endl;
        }
        
        addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
        
        // Create merge block for fallthrough (when condition is false)
        BasicBlock* mergeBlock = createBlock("If_Merge");
        
        // Add conditional edge to GOTO target (when true)
        int targetBlock = resolveLineNumberToBlock(stmt.gotoLine);
        if (targetBlock >= 0) {
            addConditionalEdge(incoming->id, targetBlock, "true");
        } else {
            // Forward reference - defer
            DeferredEdge edge;
            edge.sourceBlockId = incoming->id;
            edge.targetLineNumber = stmt.gotoLine;
            edge.label = "true";
            m_deferredEdges.push_back(edge);
        }
        
        // Add fallthrough edge (when false)
        addConditionalEdge(incoming->id, mergeBlock->id, "false");
        
        if (m_debugMode) {
            std::cout << "[CFG] IF GOTO complete, merge block: " << mergeBlock->id << std::endl;
        }
        
        return mergeBlock;
    }
    
    // Check if this is a single-line IF with inline statements
    if (!stmt.isMultiLine && !stmt.thenStatements.empty()) {
        // Single-line IF...THEN statement [ELSE statement]
        // e.g., IF x > 5 THEN PRINT "yes" ELSE PRINT "no"
        if (m_debugMode) {
            std::cout << "[CFG] Single-line IF with inline statements" << std::endl;
        }
        
        addStatementToBlock(incoming, &stmt, getLineNumber(&stmt));
        
        // Create blocks for then/else/merge
        BasicBlock* thenBlock = createBlock("If_Then");
        BasicBlock* elseBlock = stmt.elseStatements.empty() ? nullptr : createBlock("If_Else");
        BasicBlock* mergeBlock = createBlock("If_Merge");
        
        // Wire condition to branches
        addConditionalEdge(incoming->id, thenBlock->id, "true");
        
        if (elseBlock) {
            addConditionalEdge(incoming->id, elseBlock->id, "false");
        } else {
            addConditionalEdge(incoming->id, mergeBlock->id, "false");
        }
        
        // Build THEN branch
        BasicBlock* thenExit = buildStatementRange(
            stmt.thenStatements,
            thenBlock,
            loop,
            select,
            tryCtx,
            sub
        );
        
        bool thenTerminated = isTerminated(thenExit);
        
        // Wire THEN to merge
        if (!thenTerminated) {
            addUnconditionalEdge(thenExit->id, mergeBlock->id);
        }
        
        // Build ELSE branch if present
        bool elseTerminated = false;
        if (elseBlock) {
            BasicBlock* elseExit = buildStatementRange(
                stmt.elseStatements,
                elseBlock,
                loop,
                select,
                tryCtx,
                sub
            );
            
            elseTerminated = isTerminated(elseExit);
            
            if (!elseTerminated) {
                addUnconditionalEdge(elseExit->id, mergeBlock->id);
            }
        }
        
        if (m_debugMode) {
            std::cout << "[CFG] Single-line IF complete, merge block: " << mergeBlock->id << std::endl;
        }
        
        // If both branches are terminated (or only THEN exists and is terminated),
        // the merge block is unreachable. Return an unreachable block for subsequent statements.
        // Cases:
        // - THEN terminated AND ELSE terminated → merge unreachable
        // - THEN terminated AND no ELSE → false path reaches merge → merge reachable
        // - THEN not terminated → merge reachable
        if (thenTerminated && elseBlock && elseTerminated) {
            if (m_debugMode) {
                std::cout << "[CFG] Both IF branches terminated, returning unreachable block" << std::endl;
            }
            return createUnreachableBlock();
        }
        
        return mergeBlock;
    }
    
    // Multi-line IF...THEN...ELSE...END IF
    if (m_debugMode) {
        std::cout << "[CFG] Multi-line IF statement" << std::endl;
    }
    
    // 1. Setup blocks
    BasicBlock* conditionBlock = incoming;
    BasicBlock* thenEntry = createBlock("If_Then");
    BasicBlock* elseEntry = stmt.elseStatements.empty() ? nullptr : createBlock("If_Else");
    BasicBlock* mergeBlock = createBlock("If_Merge");
    
    // 2. Add condition check to incoming block
    addStatementToBlock(conditionBlock, &stmt, getLineNumber(&stmt));
    
    // 3. Wire condition to branches
    addConditionalEdge(conditionBlock->id, thenEntry->id, "true");
    
    if (elseEntry) {
        addConditionalEdge(conditionBlock->id, elseEntry->id, "false");
    } else {
        // No ELSE branch: false goes directly to merge
        addConditionalEdge(conditionBlock->id, mergeBlock->id, "false");
    }
    
    // 4. Recursively build THEN branch
    // KEY FIX: This handles nested loops/IFs automatically!
    BasicBlock* thenExit = buildStatementRange(
        stmt.thenStatements,
        thenEntry,
        loop,
        select,
        tryCtx,
        sub
    );
    
    // 5. Wire THEN exit to merge (if not terminated by GOTO/RETURN)
    if (!isTerminated(thenExit)) {
        addUnconditionalEdge(thenExit->id, mergeBlock->id);
    }
    
    // 6. Recursively build ELSE branch (if exists)
    if (elseEntry) {
        BasicBlock* elseExit = buildStatementRange(
            stmt.elseStatements,
            elseEntry,
            loop,
            select,
            tryCtx,
            sub
        );
        
        // Wire ELSE exit to merge (if not terminated)
        if (!isTerminated(elseExit)) {
            addUnconditionalEdge(elseExit->id, mergeBlock->id);
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Multi-line IF complete, merge block: " << mergeBlock->id << std::endl;
    }
    
    // 7. Return merge point
    // The next statement in the outer scope connects here
    return mergeBlock;
}

// =============================================================================
// SELECT CASE Statement Handler
// =============================================================================
//
// SELECT CASE expression
//   CASE value1, value2, ...
//     statements
//   CASE ELSE
//     statements
// END SELECT
//
// Strategy: Create synthetic IF statements for each WHEN clause check.
// Each check block contains an IF with the condition (selector == value1 OR ...)
// This allows the CFG emitter to handle SELECT CASE like any other conditional.
//
BasicBlock* CFGBuilder::buildSelectCase(
    const CaseStatement& stmt,
    BasicBlock* incoming,
    LoopContext* loop,
    SelectContext* outerSelect,
    TryContext* tryCtx,
    SubroutineContext* sub
) {
    if (m_debugMode) {
        std::cout << "[CFG] Building SELECT CASE statement with " 
                  << stmt.whenClauses.size() << " when clauses" << std::endl;
    }
    
    // Validate that we have a selector expression
    if (!stmt.caseExpression) {
        if (m_debugMode) {
            std::cout << "[CFG] ERROR: SELECT CASE without selector expression" << std::endl;
        }
        return incoming;
    }
    
    // 1. Create exit block for the entire SELECT
    BasicBlock* exitBlock = createBlock("Select_Exit");
    
    // 2. Create SELECT context
    SelectContext selectCtx;
    selectCtx.exitBlockId = exitBlock->id;
    selectCtx.outerSelect = outerSelect;
    
    // 3. Process each WHEN clause
    BasicBlock* previousCaseCheck = incoming;
    
    for (size_t i = 0; i < stmt.whenClauses.size(); i++) {
        const auto& whenClause = stmt.whenClauses[i];
        
        if (m_debugMode) {
            std::cout << "[CFG] Processing WHEN clause " << i << std::endl;
        }
        
        // Create synthetic IF statement for this WHEN check
        // This IF will compare the selector against the WHEN values
        auto syntheticIf = std::make_unique<IfStatement>();
        syntheticIf->condition = createWhenCondition(stmt, whenClause);
        syntheticIf->isMultiLine = false;  // Treat as single-line for simplicity
        
        if (!syntheticIf->condition) {
            if (m_debugMode) {
                std::cout << "[CFG] WARNING: Could not create condition for WHEN clause " << i << std::endl;
            }
            // Skip this clause or use a default true condition
            syntheticIf->condition = std::make_unique<NumberExpression>(1.0);
        }
        
        // Add the synthetic IF to the check block
        addStatementToBlock(previousCaseCheck, syntheticIf.get(), getLineNumber(&stmt));
        
        // Store the synthetic IF in the CFG so it stays alive
        // (We'll use the incoming block's statements vector to keep it alive)
        previousCaseCheck->statements.back() = syntheticIf.release();
        
        // Create block for this when's body
        BasicBlock* whenBlock = createBlock("When_Body_" + std::to_string(i));
        
        // Create block for next when check (or otherwise check for last when)
        BasicBlock* nextCheck = nullptr;
        if (i < stmt.whenClauses.size() - 1) {
            nextCheck = createBlock("When_Check_" + std::to_string(i + 1));
        } else {
            // Last clause - next check goes to OTHERWISE or exit
            if (!stmt.otherwiseStatements.empty()) {
                nextCheck = createBlock("Otherwise");
            } else {
                nextCheck = exitBlock;
            }
        }
        
        // Wire conditional edges: true -> when body, false -> next check
        addConditionalEdge(previousCaseCheck->id, whenBlock->id, "true");
        addConditionalEdge(previousCaseCheck->id, nextCheck->id, "false");
        
        // Recursively build when body statements
        BasicBlock* whenExit = buildStatementRange(
            whenClause.statements,
            whenBlock,
            loop,
            &selectCtx,
            tryCtx,
            sub
        );
        
        // Wire when exit to SELECT exit (if not terminated)
        // Note: Cases don't fall through in BASIC
        if (!isTerminated(whenExit)) {
            addUnconditionalEdge(whenExit->id, exitBlock->id);
        }
        
        // Move to next when check
        previousCaseCheck = nextCheck;
    }
    
    // 4. Process OTHERWISE clause if present
    if (!stmt.otherwiseStatements.empty()) {
        // previousCaseCheck now points to the Otherwise block (created above)
        BasicBlock* otherwiseBlock = previousCaseCheck;
        
        BasicBlock* otherwiseExit = buildStatementRange(
            stmt.otherwiseStatements,
            otherwiseBlock,
            loop,
            &selectCtx,
            tryCtx,
            sub
        );
        
        if (!isTerminated(otherwiseExit)) {
            addUnconditionalEdge(otherwiseExit->id, exitBlock->id);
        }
    }
    // Note: If no OTHERWISE, previousCaseCheck already points to exitBlock
    
    if (m_debugMode) {
        std::cout << "[CFG] SELECT CASE complete, exit block: " << exitBlock->id << std::endl;
    }
    
    // 5. Return exit block
    return exitBlock;
}

} // namespace FasterBASIC