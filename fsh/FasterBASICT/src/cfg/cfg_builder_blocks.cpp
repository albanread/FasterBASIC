//
// cfg_builder_blocks.cpp
// FasterBASIC - Control Flow Graph Builder Block and Edge Management (V2)
//
// Contains block creation and edge wiring functions.
// Part of modular CFG builder split (February 2026).
//
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"
#include <iostream>

namespace FasterBASIC {

// =============================================================================
// Block Creation
// =============================================================================

BasicBlock* CFGBuilder::createBlock(const std::string& label) {
    // Create new block with unique_ptr ownership
    auto block = std::make_unique<BasicBlock>(m_nextBlockId++, label);
    BasicBlock* blockPtr = block.get();
    
    // Add to CFG
    m_cfg->blocks.push_back(std::move(block));
    m_totalBlocksCreated++;
    
    if (m_debugMode) {
        std::cout << "[CFG] Created block " << blockPtr->id << " (" << label << ")" << std::endl;
    }
    
    return blockPtr;
}

BasicBlock* CFGBuilder::createUnreachableBlock() {
    BasicBlock* block = createBlock("Unreachable");
    m_unreachableBlocks.push_back(block);
    return block;
}

// =============================================================================
// Edge Management
// =============================================================================

void CFGBuilder::addEdge(int fromBlockId, int toBlockId, const std::string& label) {
    // Create edge structure
    CFGEdge edge;
    edge.sourceBlock = fromBlockId;
    edge.targetBlock = toBlockId;
    
    // Set edge type based on label
    if (label == "call") {
        edge.type = EdgeType::CALL;
    } else {
        edge.type = EdgeType::FALLTHROUGH;
    }
    edge.label = label;
    
    m_cfg->edges.push_back(edge);
    
    // Update block successor/predecessor lists
    if (fromBlockId >= 0 && fromBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[fromBlockId]->successors.push_back(toBlockId);
    }
    if (toBlockId >= 0 && toBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[toBlockId]->predecessors.push_back(fromBlockId);
    }
    
    m_totalEdgesCreated++;
    
    if (m_debugMode) {
        std::cout << "[CFG] Added edge: Block " << fromBlockId 
                  << " -> Block " << toBlockId;
        if (!label.empty()) {
            std::cout << " [" << label << "]";
        }
        std::cout << std::endl;
    }
}

void CFGBuilder::addConditionalEdge(int fromBlockId, int toBlockId, const std::string& condition) {
    // Create conditional edge
    CFGEdge edge;
    edge.sourceBlock = fromBlockId;
    edge.targetBlock = toBlockId;
    // Set edge type based on condition label
    if (condition == "false" || condition == "else") {
        edge.type = EdgeType::CONDITIONAL_FALSE;
    } else {
        edge.type = EdgeType::CONDITIONAL_TRUE;
    }
    edge.label = condition;
    
    m_cfg->edges.push_back(edge);
    
    // Update block successor/predecessor lists
    if (fromBlockId >= 0 && fromBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[fromBlockId]->successors.push_back(toBlockId);
    }
    if (toBlockId >= 0 && toBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[toBlockId]->predecessors.push_back(fromBlockId);
    }
    
    m_totalEdgesCreated++;
    
    if (m_debugMode) {
        std::cout << "[CFG] Added conditional edge: Block " << fromBlockId 
                  << " -> Block " << toBlockId << " [" << condition << "]" << std::endl;
    }
}

void CFGBuilder::addUnconditionalEdge(int fromBlockId, int toBlockId) {
    // Create unconditional edge (JUMP type for GOTOs, FALLTHROUGH for normal flow)
    CFGEdge edge;
    edge.sourceBlock = fromBlockId;
    edge.targetBlock = toBlockId;
    edge.type = EdgeType::JUMP;
    edge.label = "";
    
    m_cfg->edges.push_back(edge);
    
    // Update block successor/predecessor lists
    if (fromBlockId >= 0 && fromBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[fromBlockId]->successors.push_back(toBlockId);
    }
    if (toBlockId >= 0 && toBlockId < static_cast<int>(m_cfg->blocks.size())) {
        m_cfg->blocks[toBlockId]->predecessors.push_back(fromBlockId);
    }
    
    m_totalEdgesCreated++;
    
    if (m_debugMode) {
        std::cout << "[CFG] Added unconditional edge: Block " << fromBlockId 
                  << " -> Block " << toBlockId << std::endl;
    }
}

// =============================================================================
// Block State Management
// =============================================================================

void CFGBuilder::markTerminated(BasicBlock* block) {
    if (block) {
        block->isTerminator = true;
        
        if (m_debugMode) {
            std::cout << "[CFG] Marked block " << block->id << " as terminated" << std::endl;
        }
    }
}

bool CFGBuilder::isTerminated(const BasicBlock* block) const {
    return block && block->isTerminator;
}

// =============================================================================
// Statement Management
// =============================================================================

void CFGBuilder::addStatementToBlock(BasicBlock* block, const Statement* stmt, int lineNumber) {
    if (!block || !stmt) return;
    
    block->addStatement(stmt, lineNumber);
    
    if (m_debugMode && lineNumber >= 0) {
        std::cout << "[CFG] Added statement from line " << lineNumber 
                  << " to block " << block->id << std::endl;
    }
}

int CFGBuilder::getLineNumber(const Statement* stmt) {
    // Extract line number from statement metadata
    if (!stmt) return -1;
    
    // Statement doesn't store line number directly in v2
    // Line numbers are tracked at the block level when statements are added
    // Return -1 to indicate unknown (caller should provide line number)
    return -1;
}

// =============================================================================
// Helper Functions
// =============================================================================

BasicBlock* CFGBuilder::splitBlockIfNeeded(BasicBlock* block) {
    if (!block->statements.empty()) {
        // Block already has statements, create a new one
        BasicBlock* newBlock = createBlock(block->label + "_Split");
        addUnconditionalEdge(block->id, newBlock->id);
        return newBlock;
    }
    return block;
}

CFGBuilder::LoopContext* CFGBuilder::findLoopContext(LoopContext* ctx, const std::string& loopType) {
    while (ctx) {
        if (ctx->loopType == loopType) {
            return ctx;
        }
        ctx = ctx->outerLoop;
    }
    return nullptr;
}

} // namespace FasterBASIC