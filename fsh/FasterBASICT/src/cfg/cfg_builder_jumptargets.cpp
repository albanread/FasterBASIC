//
// cfg_builder_jumptargets.cpp
// FasterBASIC - Control Flow Graph Builder Jump Target Collection (V2)
//
// Contains Phase 0 jump target pre-scan to identify GOTO/GOSUB landing zones.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>

namespace FasterBASIC {

// =============================================================================
// Jump Target Collection (Phase 0)
// =============================================================================
//
// Before building the CFG, we need to know which line numbers are jump targets
// (GOTO/GOSUB destinations). This allows us to start new blocks at those lines.
//

void CFGBuilder::collectJumpTargets(const std::vector<StatementPtr>& statements) {
    for (const auto& stmt : statements) {
        if (stmt) {
            collectJumpTargetsFromStatement(stmt.get());
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Collected " << m_jumpTargets.size() << " jump targets" << std::endl;
    }
}

void CFGBuilder::collectJumpTargetsFromProgram(const Program& program) {
    for (const auto& line : program.lines) {
        for (const auto& stmt : line->statements) {
            if (stmt) {
                collectJumpTargetsFromStatement(stmt.get());
            }
        }
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Collected " << m_jumpTargets.size() << " jump targets from program" << std::endl;
    }
}

void CFGBuilder::collectJumpTargetsFromStatement(const Statement* stmt) {
    if (!stmt) return;
    
    // Check for GOTO statement
    if (auto* gotoStmt = dynamic_cast<const GotoStatement*>(stmt)) {
        m_jumpTargets.insert(gotoStmt->lineNumber);
        if (m_debugMode) {
            std::cout << "[CFG] Found GOTO target: line " << gotoStmt->lineNumber << std::endl;
        }
        return;
    }
    
    // Check for GOSUB statement
    if (auto* gosubStmt = dynamic_cast<const GosubStatement*>(stmt)) {
        m_jumpTargets.insert(gosubStmt->lineNumber);
        if (m_debugMode) {
            std::cout << "[CFG] Found GOSUB target: line " << gosubStmt->lineNumber << std::endl;
        }
        return;
    }
    
    // Check for ON GOTO statement
    if (auto* onGotoStmt = dynamic_cast<const OnGotoStatement*>(stmt)) {
        for (int target : onGotoStmt->lineNumbers) {
            m_jumpTargets.insert(target);
            if (m_debugMode) {
                std::cout << "[CFG] Found ON GOTO target: line " << target << std::endl;
            }
        }
        return;
    }
    
    // Check for ON GOSUB statement
    if (auto* onGosubStmt = dynamic_cast<const OnGosubStatement*>(stmt)) {
        for (int target : onGosubStmt->lineNumbers) {
            m_jumpTargets.insert(target);
            if (m_debugMode) {
                std::cout << "[CFG] Found ON GOSUB target: line " << target << std::endl;
            }
        }
        return;
    }
    
    // Recursively scan structured statements for nested GOTOs/GOSUBs
    
    if (auto* ifStmt = dynamic_cast<const IfStatement*>(stmt)) {
        for (const auto& thenStmt : ifStmt->thenStatements) {
            collectJumpTargetsFromStatement(thenStmt.get());
        }
        for (const auto& elseStmt : ifStmt->elseStatements) {
            collectJumpTargetsFromStatement(elseStmt.get());
        }
        return;
    }
    
    if (auto* whileStmt = dynamic_cast<const WhileStatement*>(stmt)) {
        for (const auto& bodyStmt : whileStmt->body) {
            collectJumpTargetsFromStatement(bodyStmt.get());
        }
        return;
    }
    
    if (auto* forStmt = dynamic_cast<const ForStatement*>(stmt)) {
        for (const auto& bodyStmt : forStmt->body) {
            collectJumpTargetsFromStatement(bodyStmt.get());
        }
        return;
    }
    
    if (auto* repeatStmt = dynamic_cast<const RepeatStatement*>(stmt)) {
        for (const auto& bodyStmt : repeatStmt->body) {
            collectJumpTargetsFromStatement(bodyStmt.get());
        }
        return;
    }
    
    if (auto* doStmt = dynamic_cast<const DoStatement*>(stmt)) {
        for (const auto& bodyStmt : doStmt->body) {
            collectJumpTargetsFromStatement(bodyStmt.get());
        }
        return;
    }
    
    if (auto* selectStmt = dynamic_cast<const CaseStatement*>(stmt)) {
        // Scan WHEN clauses for GOTOs
        for (const auto& whenClause : selectStmt->whenClauses) {
            for (const auto& whenStmt : whenClause.statements) {
                collectJumpTargetsFromStatement(whenStmt.get());
            }
        }
        // Scan OTHERWISE clause
        for (const auto& otherwiseStmt : selectStmt->otherwiseStatements) {
            collectJumpTargetsFromStatement(otherwiseStmt.get());
        }
        return;
    }
    
    if (auto* tryStmt = dynamic_cast<const TryCatchStatement*>(stmt)) {
        // Scan try block
        for (const auto& tryBlockStmt : tryStmt->tryBlock) {
            collectJumpTargetsFromStatement(tryBlockStmt.get());
        }
        // Scan catch clauses
        for (const auto& catchClause : tryStmt->catchClauses) {
            for (const auto& catchStmt : catchClause.block) {
                collectJumpTargetsFromStatement(catchStmt.get());
            }
        }
        // Scan finally block if present
        for (const auto& finallyStmt : tryStmt->finallyBlock) {
            collectJumpTargetsFromStatement(finallyStmt.get());
        }
        return;
    }
    
    // Other statements don't contain jump targets or nested structures
}

bool CFGBuilder::isJumpTarget(int lineNumber) const {
    return m_jumpTargets.find(lineNumber) != m_jumpTargets.end();
}

// =============================================================================
// Line Number and Label Resolution
// =============================================================================

int CFGBuilder::resolveLineNumberToBlock(int lineNumber) {
    auto it = m_lineNumberToBlock.find(lineNumber);
    if (it != m_lineNumberToBlock.end()) {
        return it->second;
    }
    
    // Line number not yet seen - will be resolved later
    if (m_debugMode) {
        std::cout << "[CFG] Line " << lineNumber << " not yet mapped (forward reference)" << std::endl;
    }
    return -1;
}

void CFGBuilder::registerLineNumberBlock(int lineNumber, int blockId) {
    m_lineNumberToBlock[lineNumber] = blockId;
    
    if (m_debugMode) {
        std::cout << "[CFG] Registered line " << lineNumber << " -> block " << blockId << std::endl;
    }
}

void CFGBuilder::registerLabel(const std::string& label, int blockId) {
    m_labelToBlock[label] = blockId;
    
    if (m_debugMode) {
        std::cout << "[CFG] Registered label '" << label << "' -> block " << blockId << std::endl;
    }
}

int CFGBuilder::resolveLabelToBlock(const std::string& label) {
    auto it = m_labelToBlock.find(label);
    if (it != m_labelToBlock.end()) {
        return it->second;
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Label '" << label << "' not found" << std::endl;
    }
    return -1;
}

// =============================================================================
// Deferred Edge Resolution
// =============================================================================

void CFGBuilder::resolveDeferredEdges() {
    if (m_deferredEdges.empty()) {
        return;
    }
    
    if (m_debugMode) {
        std::cout << "[CFG] Resolving " << m_deferredEdges.size() << " deferred edges" << std::endl;
    }
    
    // Resolve forward references (GOTOs to later line numbers or labels)
    for (const auto& deferred : m_deferredEdges) {
        int targetBlock = -1;
        
        // Check if this is a label-based target
        if (!deferred.targetLabel.empty()) {
            targetBlock = resolveLabelToBlock(deferred.targetLabel);
            if (targetBlock >= 0) {
                addEdge(deferred.sourceBlockId, targetBlock, deferred.label);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Resolved deferred edge: block " << deferred.sourceBlockId
                              << " -> label '" << deferred.targetLabel 
                              << "' (block " << targetBlock << ")" << std::endl;
                }
            } else {
                if (m_debugMode) {
                    std::cout << "[CFG] Warning: Could not resolve label '" 
                              << deferred.targetLabel << "' for deferred edge" << std::endl;
                }
            }
        } else {
            // Line number based target
            targetBlock = resolveLineNumberToBlock(deferred.targetLineNumber);
            if (targetBlock >= 0) {
                addEdge(deferred.sourceBlockId, targetBlock, deferred.label);
                
                if (m_debugMode) {
                    std::cout << "[CFG] Resolved deferred edge: block " << deferred.sourceBlockId
                              << " -> line " << deferred.targetLineNumber 
                              << " (block " << targetBlock << ")" << std::endl;
                }
            } else {
                if (m_debugMode) {
                    std::cout << "[CFG] Warning: Could not resolve line number " 
                              << deferred.targetLineNumber << " for deferred edge" << std::endl;
                }
            }
        }
    }
}

} // namespace FasterBASIC