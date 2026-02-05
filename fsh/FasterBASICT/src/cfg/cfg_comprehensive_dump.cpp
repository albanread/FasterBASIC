//
// cfg_dump.cpp
// FasterBASIC - Comprehensive Control Flow Graph Report Generator
//
// Generates detailed CFG reports with:
// - Executive summary with key metrics
// - Detailed block-by-block analysis
// - Edge analysis and control flow patterns
// - Unreachable code detection
// - Complexity metrics
// - Compact format for test validation
//
// Part of modular CFG builder (February 2026)
// V2 IMPLEMENTATION: Single-pass recursive construction
//

#include "cfg_builder.h"
#include <iostream>
#include <iomanip>
#include <sstream>
#include <algorithm>
#include <set>
#include <map>
#include <queue>

namespace FasterBASIC {

// =============================================================================
// Helper Functions
// =============================================================================

// Calculate reachable blocks from entry using BFS
static std::set<int> calculateReachableBlocks(const ControlFlowGraph* cfg) {
    std::set<int> reachable;
    if (cfg->blocks.empty()) return reachable;
    
    std::queue<int> toVisit;
    toVisit.push(cfg->entryBlock);
    reachable.insert(cfg->entryBlock);
    
    while (!toVisit.empty()) {
        int current = toVisit.front();
        toVisit.pop();
        
        // Find the block
        for (const auto& block : cfg->blocks) {
            if (block->id == current) {
                for (int succ : block->successors) {
                    if (reachable.find(succ) == reachable.end()) {
                        reachable.insert(succ);
                        toVisit.push(succ);
                    }
                }
                break;
            }
        }
    }
    
    return reachable;
}

// Find blocks with no predecessors (except entry)
static std::vector<int> findOrphanBlocks(const ControlFlowGraph* cfg) {
    std::vector<int> orphans;
    for (const auto& block : cfg->blocks) {
        if (block->id != cfg->entryBlock && 
            block->predecessors.empty() && 
            !block->successors.empty()) {
            orphans.push_back(block->id);
        }
    }
    return orphans;
}

// Calculate cyclomatic complexity: E - N + 2P (where P=1 for single component)
static int calculateCyclomaticComplexity(const ControlFlowGraph* cfg) {
    int E = cfg->edges.size();
    int N = cfg->blocks.size();
    return E - N + 2;
}

// Count blocks by type
static std::map<std::string, int> categorizeBlocks(const ControlFlowGraph* cfg) {
    std::map<std::string, int> counts;
    counts["Total"] = cfg->blocks.size();
    counts["Empty"] = 0;
    counts["LoopHeader"] = 0;
    counts["LoopExit"] = 0;
    counts["Terminated"] = 0;
    counts["MultiPredecessor"] = 0;
    counts["MultiSuccessor"] = 0;
    
    for (const auto& block : cfg->blocks) {
        if (block->statements.empty()) counts["Empty"]++;
        if (block->isLoopHeader) counts["LoopHeader"]++;
        if (block->isLoopExit) counts["LoopExit"]++;
        if (block->isTerminator) counts["Terminated"]++;
        if (block->predecessors.size() > 1) counts["MultiPredecessor"]++;
        if (block->successors.size() > 1) counts["MultiSuccessor"]++;
    }
    
    return counts;
}

// =============================================================================
// Main CFG Dump Function
// =============================================================================

void CFGBuilder::dumpCFG(const std::string& phase) const {
    if (!m_cfg) {
        std::cerr << "\n========================================\n";
        std::cerr << "CFG DUMP ERROR: No CFG to dump\n";
        std::cerr << "========================================\n\n";
        return;
    }
    
    const ControlFlowGraph* cfg = m_cfg;
    
    // =============================================================================
    // EXECUTIVE SUMMARY
    // =============================================================================
    
    std::cerr << "\n+==========================================================================+\n";
    std::cerr << "|                       CFG ANALYSIS REPORT                                 |\n";
    std::cerr << "+==========================================================================╝\n\n";
    
    if (!phase.empty()) {
        std::cerr << "Phase: " << phase << "\n";
    }
    std::cerr << "Function: " << cfg->functionName << "\n";
    
    if (!cfg->parameters.empty()) {
        std::cerr << "Parameters: " << cfg->parameters.size() << " (";
        for (size_t i = 0; i < cfg->parameters.size(); ++i) {
            if (i > 0) std::cerr << ", ";
            std::cerr << cfg->parameters[i];
        }
        std::cerr << ")\n";
    }
    
    if (cfg->returnType != VariableType::UNKNOWN && cfg->returnType != VariableType::VOID) {
        std::cerr << "Return Type: ";
        switch (cfg->returnType) {
            case VariableType::INT: std::cerr << "INTEGER"; break;
            case VariableType::FLOAT: std::cerr << "FLOAT"; break;
            case VariableType::DOUBLE: std::cerr << "DOUBLE"; break;
            case VariableType::STRING: std::cerr << "STRING"; break;
            default: std::cerr << "OTHER"; break;
        }
        std::cerr << "\n";
    }
    
    std::cerr << "\n" << std::string(78, '-') << "\n";
    std::cerr << "SUMMARY METRICS\n";
    std::cerr << std::string(78, '-') << "\n";
    
    std::cerr << "  Basic Statistics:\n";
    std::cerr << "    Total Blocks:     " << std::setw(6) << cfg->blocks.size() << "\n";
    std::cerr << "    Total Edges:      " << std::setw(6) << cfg->edges.size() << "\n";
    std::cerr << "    Entry Block:      " << std::setw(6) << cfg->entryBlock << "\n";
    std::cerr << "    Exit Block:       " << std::setw(6) << cfg->exitBlock << "\n";
    
    // Count statements
    int totalStmts = 0;
    for (const auto& block : cfg->blocks) {
        totalStmts += block->statements.size();
    }
    std::cerr << "    Total Statements: " << std::setw(6) << totalStmts << "\n";
    
    // Reachability analysis
    auto reachable = calculateReachableBlocks(cfg);
    int unreachableCount = cfg->blocks.size() - reachable.size();
    
    // Calculate unexpected unreachable count (excluding exit block)
    int unexpectedUnreachableCount = unreachableCount;
    if (reachable.find(cfg->exitBlock) == reachable.end()) {
        // Exit block is unreachable - this is expected if program ends with terminator
        unexpectedUnreachableCount--;
    }
    
    std::cerr << "    Reachable Blocks: " << std::setw(6) << reachable.size() << "\n";
    std::cerr << "    Unreachable:      " << std::setw(6) << unreachableCount;
    if (unexpectedUnreachableCount > 0) std::cerr << " ⚠";
    std::cerr << "\n";
    
    // Complexity
    int complexity = calculateCyclomaticComplexity(cfg);
    std::cerr << "    Cyclomatic Complexity: " << complexity;
    if (complexity > 10) std::cerr << " (HIGH)";
    else if (complexity > 5) std::cerr << " (MEDIUM)";
    else std::cerr << " (LOW)";
    std::cerr << "\n";
    
    // Block categorization
    auto blockCats = categorizeBlocks(cfg);
    std::cerr << "\n  Block Categories:\n";
    std::cerr << "    Empty Blocks:     " << std::setw(6) << blockCats["Empty"] << "\n";
    std::cerr << "    Loop Headers:     " << std::setw(6) << blockCats["LoopHeader"] << "\n";
    std::cerr << "    Loop Exits:       " << std::setw(6) << blockCats["LoopExit"] << "\n";
    std::cerr << "    Terminated:       " << std::setw(6) << blockCats["Terminated"] << "\n";
    std::cerr << "    Multi-Pred:       " << std::setw(6) << blockCats["MultiPredecessor"] << "\n";
    std::cerr << "    Multi-Succ:       " << std::setw(6) << blockCats["MultiSuccessor"] << "\n";
    
    // Edge type breakdown
    std::map<EdgeType, int> edgeTypes;
    for (const auto& edge : cfg->edges) {
        edgeTypes[edge.type]++;
    }
    std::cerr << "\n  Edge Types:\n";
    if (edgeTypes[EdgeType::FALLTHROUGH] > 0)
        std::cerr << "    Fallthrough:      " << std::setw(6) << edgeTypes[EdgeType::FALLTHROUGH] << "\n";
    if (edgeTypes[EdgeType::CONDITIONAL_TRUE] > 0)
        std::cerr << "    Conditional True: " << std::setw(6) << edgeTypes[EdgeType::CONDITIONAL_TRUE] << "\n";
    if (edgeTypes[EdgeType::CONDITIONAL_FALSE] > 0)
        std::cerr << "    Conditional False:" << std::setw(6) << edgeTypes[EdgeType::CONDITIONAL_FALSE] << "\n";
    if (edgeTypes[EdgeType::JUMP] > 0)
        std::cerr << "    Jump:             " << std::setw(6) << edgeTypes[EdgeType::JUMP] << "\n";
    if (edgeTypes[EdgeType::CALL] > 0)
        std::cerr << "    Call:             " << std::setw(6) << edgeTypes[EdgeType::CALL] << "\n";
    if (edgeTypes[EdgeType::RETURN] > 0)
        std::cerr << "    Return:           " << std::setw(6) << edgeTypes[EdgeType::RETURN] << "\n";
    if (edgeTypes[EdgeType::EXCEPTION] > 0)
        std::cerr << "    Exception:        " << std::setw(6) << edgeTypes[EdgeType::EXCEPTION] << "\n";
    
    // =============================================================================
    // COMPACT TEST FORMAT
    // =============================================================================
    
    std::cerr << "\n" << std::string(78, '-') << "\n";
    std::cerr << "COMPACT FORMAT (for test validation)\n";
    std::cerr << std::string(78, '-') << "\n";
    
    std::cerr << "CFG:" << cfg->functionName << ":";
    std::cerr << "B" << cfg->blocks.size() << ":";
    std::cerr << "E" << cfg->edges.size() << ":";
    std::cerr << "S" << totalStmts << ":";
    std::cerr << "CC" << complexity << ":";
    std::cerr << "R" << reachable.size();
    if (unexpectedUnreachableCount > 0) std::cerr << "!";
    std::cerr << "\n";
    
    // Edge list (compact)
    std::cerr << "EDGES:";
    for (const auto& edge : cfg->edges) {
        std::cerr << " " << edge.sourceBlock << "->" << edge.targetBlock;
    }
    std::cerr << "\n";
    
    // =============================================================================
    // DETAILED BLOCK ANALYSIS
    // =============================================================================
    
    std::cerr << "\n" << std::string(78, '=') << "\n";
    std::cerr << "DETAILED BLOCK ANALYSIS\n";
    std::cerr << std::string(78, '=') << "\n\n";
    
    for (const auto& block : cfg->blocks) {
        // Block header with ID and label
        std::cerr << "+=== Block " << block->id << " (" << block->label << ") ";
        std::cerr << std::string(std::max(0, 60 - (int)block->label.length()), '=') << "+\n";
        
        // Flags
        std::cerr << "| Flags:";
        bool hasFlags = false;
        if (block->id == cfg->entryBlock) {
            std::cerr << " [ENTRY]";
            hasFlags = true;
        }
        if (block->id == cfg->exitBlock) {
            std::cerr << " [EXIT]";
            hasFlags = true;
        }
        if (block->isTerminator) {
            std::cerr << " [TERMINATED]";
            hasFlags = true;
        }
        if (block->isLoopHeader) {
            std::cerr << " [LOOP_HEADER]";
            hasFlags = true;
        }
        if (block->isLoopExit) {
            std::cerr << " [LOOP_EXIT]";
            hasFlags = true;
        }
        if (block->statements.empty()) {
            std::cerr << " [EMPTY]";
            hasFlags = true;
        }
        if (reachable.find(block->id) == reachable.end()) {
            std::cerr << " [UNREACHABLE]";
            hasFlags = true;
        }
        if (!hasFlags) {
            std::cerr << " [NORMAL]";
        }
        std::cerr << "\n";
        
        // Source lines
        if (!block->lineNumbers.empty()) {
            std::cerr << "| Source Lines:";
            int count = 0;
            for (int line : block->lineNumbers) {
                if (count > 0 && count % 10 == 0) {
                    std::cerr << "\n|              ";
                }
                std::cerr << " " << line;
                count++;
            }
            std::cerr << "\n";
        }
        
        // Statement count and types
        std::cerr << "| Statements: " << block->statements.size() << "\n";
        if (!block->statements.empty()) {
            std::map<std::string, int> stmtTypes;
            for (const Statement* stmt : block->statements) {
                std::string typeName = typeid(*stmt).name();
                // Demangle: Extract just the class name
                size_t pos = typeName.find("FasterBASIC");
                if (pos != std::string::npos) {
                    pos += 11; // strlen("FasterBASIC")
                    size_t end = typeName.find_first_not_of("0123456789", pos);
                    if (end != std::string::npos) {
                        int len = 0;
                        sscanf(typeName.c_str() + pos, "%d", &len);
                        if (len > 0 && pos + std::to_string(len).length() < typeName.length()) {
                            typeName = typeName.substr(pos + std::to_string(len).length(), len);
                        }
                    }
                }
                stmtTypes[typeName]++;
            }
            
            std::cerr << "|   Types:";
            bool first = true;
            for (const auto& [type, count] : stmtTypes) {
                if (!first) std::cerr << ",";
                std::cerr << " " << type;
                if (count > 1) std::cerr << "×" << count;
                first = false;
            }
            std::cerr << "\n";
            
            // Detailed statement list
            std::cerr << "|   Detail:\n";
            for (size_t i = 0; i < block->statements.size(); ++i) {
                const Statement* stmt = block->statements[i];
                std::string typeName = typeid(*stmt).name();
                size_t pos = typeName.find("FasterBASIC");
                if (pos != std::string::npos) {
                    pos += 11;
                    size_t end = typeName.find_first_not_of("0123456789", pos);
                    if (end != std::string::npos) {
                        int len = 0;
                        sscanf(typeName.c_str() + pos, "%d", &len);
                        if (len > 0) {
                            typeName = typeName.substr(pos + std::to_string(len).length(), len);
                        }
                    }
                }
                std::cerr << "|     [" << std::setw(2) << i << "] " << typeName;
                
                // Try to add helpful details
                auto it = block->statementLineNumbers.find(stmt);
                if (it != block->statementLineNumbers.end() && it->second > 0) {
                    std::cerr << " (line " << it->second << ")";
                }
                std::cerr << "\n";
            }
        }
        
        // Predecessors
        std::cerr << "| Predecessors (" << block->predecessors.size() << "):";
        if (block->predecessors.empty()) {
            std::cerr << " none\n";
        } else {
            for (size_t i = 0; i < block->predecessors.size(); ++i) {
                if (i > 0) std::cerr << ",";
                std::cerr << " " << block->predecessors[i];
            }
            std::cerr << "\n";
        }
        
        // Successors
        std::cerr << "| Successors (" << block->successors.size() << "):";
        if (block->successors.empty()) {
            std::cerr << " none\n";
        } else {
            for (size_t i = 0; i < block->successors.size(); ++i) {
                if (i > 0) std::cerr << ",";
                std::cerr << " " << block->successors[i];
            }
            std::cerr << "\n";
        }
        
        std::cerr << "+" << std::string(76, '=') << "╝\n\n";
    }
    
    // =============================================================================
    // DETAILED EDGE ANALYSIS
    // =============================================================================
    
    std::cerr << std::string(78, '-') << "\n";
    std::cerr << "DETAILED EDGE ANALYSIS\n";
    std::cerr << std::string(78, '-') << "\n\n";
    
    for (size_t i = 0; i < cfg->edges.size(); ++i) {
        const auto& edge = cfg->edges[i];
        std::cerr << "Edge " << std::setw(3) << i << ": ";
        std::cerr << "Block " << std::setw(3) << edge.sourceBlock;
        std::cerr << " --";
        
        // Edge type
        switch (edge.type) {
            case EdgeType::FALLTHROUGH:
                std::cerr << "[FALL]";
                break;
            case EdgeType::CONDITIONAL_TRUE:
                std::cerr << "[TRUE]";
                break;
            case EdgeType::CONDITIONAL_FALSE:
                std::cerr << "[FALSE]";
                break;
            case EdgeType::JUMP:
                std::cerr << "[JUMP]";
                break;
            case EdgeType::CALL:
                std::cerr << "[CALL]";
                break;
            case EdgeType::RETURN:
                std::cerr << "[RET]";
                break;
            case EdgeType::EXCEPTION:
                std::cerr << "[EXC]";
                break;
        }
        
        std::cerr << "--> Block " << std::setw(3) << edge.targetBlock;
        
        if (!edge.label.empty()) {
            std::cerr << " (\"" << edge.label << "\")";
        }
        
        // Detect back-edges (potential loops)
        if (edge.targetBlock <= edge.sourceBlock) {
            std::cerr << " <- BACK-EDGE";
        }
        
        std::cerr << "\n";
    }
    
    // =============================================================================
    // CONTROL FLOW ANALYSIS
    // =============================================================================
    
    std::cerr << "\n" << std::string(78, '-') << "\n";
    std::cerr << "CONTROL FLOW ANALYSIS\n";
    std::cerr << std::string(78, '-') << "\n\n";
    
    // Unreachable blocks (excluding exit block, which is expected to be unreachable
    // if the program ends with END/GOTO/RETURN)
    std::vector<const BasicBlock*> unexpectedUnreachableBlocks;
    
    for (const auto& block : cfg->blocks) {
        if (reachable.find(block->id) == reachable.end()) {
            // Skip exit block - it's expected to be unreachable if program ends with terminator
            if (block->id == cfg->exitBlock) {
                continue;
            }
            unexpectedUnreachableBlocks.push_back(block.get());
        }
    }
    
    if (!unexpectedUnreachableBlocks.empty()) {
        std::cerr << "⚠ UNREACHABLE BLOCKS DETECTED:\n";
        for (const auto* block : unexpectedUnreachableBlocks) {
            std::cerr << "  - Block " << block->id << " (" << block->label << ")";
            if (!block->statements.empty()) {
                std::cerr << " - contains " << block->statements.size() << " statement(s)";
            }
            std::cerr << "\n";
        }
        std::cerr << "\n";
    } else {
        std::cerr << "✓ All non-exit blocks are reachable from entry\n\n";
    }
    
    // Orphan blocks
    auto orphans = findOrphanBlocks(cfg);
    if (!orphans.empty()) {
        std::cerr << "⚠ ORPHAN BLOCKS (no predecessors but have successors):\n";
        for (int id : orphans) {
            std::cerr << "  - Block " << id << "\n";
        }
        std::cerr << "\n";
    }
    
    // Back edges (loops)
    std::vector<std::pair<int, int>> backEdges;
    for (const auto& edge : cfg->edges) {
        if (edge.targetBlock <= edge.sourceBlock) {
            backEdges.push_back({edge.sourceBlock, edge.targetBlock});
        }
    }
    if (!backEdges.empty()) {
        std::cerr << "DETECTED LOOPS (back-edges):\n";
        for (const auto& [src, tgt] : backEdges) {
            std::cerr << "  - Block " << src << " → Block " << tgt << "\n";
        }
        std::cerr << "\n";
    }
    
    // Terminal blocks (no successors, excluding exit)
    std::vector<int> terminals;
    for (const auto& block : cfg->blocks) {
        if (block->successors.empty() && block->id != cfg->exitBlock) {
            terminals.push_back(block->id);
        }
    }
    if (!terminals.empty()) {
        std::cerr << "TERMINAL BLOCKS (no successors, excluding exit):\n";
        for (int id : terminals) {
            std::cerr << "  - Block " << id;
            // Check if it's reachable
            if (reachable.find(id) == reachable.end()) {
                std::cerr << " (unreachable)";
            }
            std::cerr << "\n";
        }
        std::cerr << "\n";
    }
    
    // Decision points (blocks with multiple successors)
    int decisionPoints = 0;
    for (const auto& block : cfg->blocks) {
        if (block->successors.size() > 1) {
            decisionPoints++;
        }
    }
    if (decisionPoints > 0) {
        std::cerr << "DECISION POINTS (blocks with multiple successors): " << decisionPoints << "\n";
        for (const auto& block : cfg->blocks) {
            if (block->successors.size() > 1) {
                std::cerr << "  - Block " << block->id << " (" << block->label << ") → ";
                std::cerr << block->successors.size() << " paths\n";
            }
        }
        std::cerr << "\n";
    }
    
    // Join points (blocks with multiple predecessors)
    int joinPoints = 0;
    for (const auto& block : cfg->blocks) {
        if (block->predecessors.size() > 1) {
            joinPoints++;
        }
    }
    if (joinPoints > 0) {
        std::cerr << "JOIN POINTS (blocks with multiple predecessors): " << joinPoints << "\n";
        for (const auto& block : cfg->blocks) {
            if (block->predecessors.size() > 1) {
                std::cerr << "  - Block " << block->id << " (" << block->label << ") ← ";
                std::cerr << block->predecessors.size() << " paths\n";
            }
        }
        std::cerr << "\n";
    }
    
    // =============================================================================
    // FOOTER
    // =============================================================================
    
    std::cerr << std::string(78, '=') << "\n";
    std::cerr << "END OF CFG ANALYSIS REPORT\n";
    std::cerr << std::string(78, '=') << "\n\n";
}

} // namespace FasterBASIC