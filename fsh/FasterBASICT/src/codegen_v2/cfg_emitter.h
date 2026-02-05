#ifndef CFG_EMITTER_H
#define CFG_EMITTER_H

#include <string>
#include <unordered_map>
#include <unordered_set>
#include "../fasterbasic_cfg.h"
#include "qbe_builder.h"
#include "type_manager.h"
#include "symbol_mapper.h"
#include "ast_emitter.h"

namespace fbc {

/**
 * CFGEmitter - CFG-aware block and edge emission
 * 
 * Responsible for:
 * - Block traversal (emit all blocks, including UNREACHABLE)
 * - Edge-based control flow (FALLTHROUGH, CONDITIONAL, MULTIWAY, RETURN)
 * - Proper terminator emission (jmp, jnz, ret)
 * - Label generation and resolution
 * 
 * This is the key component that makes the generator CFG-v2-aware.
 * It uses explicit edges rather than sequential block numbering.
 */
class CFGEmitter {
public:
    CFGEmitter(QBEBuilder& builder, TypeManager& typeManager,
               SymbolMapper& symbolMapper, ASTEmitter& astEmitter);
    ~CFGEmitter() = default;

    // === CFG Emission ===
    
    /**
     * Emit code for an entire CFG (function/program)
     * @param cfg Control flow graph to emit
     * @param functionName Name of function (empty for main program)
     */
    void emitCFG(const FasterBASIC::ControlFlowGraph* cfg, 
                 const std::string& functionName = "");
    
    /**
     * Emit a single basic block
     * @param block Block to emit
     * @param cfg CFG containing the block (for edge lookup)
     */
    void emitBlock(const FasterBASIC::BasicBlock* block,
                   const FasterBASIC::ControlFlowGraph* cfg);

    // === Edge Handling ===
    
    /**
     * Emit the terminator for a block based on its out-edges
     * @param block Block to emit terminator for
     * @param cfg CFG containing the block
     */
    void emitBlockTerminator(const FasterBASIC::BasicBlock* block,
                            const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Emit a FALLTHROUGH edge (unconditional jump to next block)
     * @param targetBlockId Target block ID
     */
    void emitFallthrough(int targetBlockId);
    
    /**
     * Emit a CONDITIONAL edge (branch on condition)
     * @param condition Condition temporary
     * @param trueBlockId Block ID if condition is true
     * @param falseBlockId Block ID if condition is false
     */
    void emitConditional(const std::string& condition,
                        int trueBlockId, int falseBlockId);
    
    /**
     * Emit a MULTIWAY edge (computed jump for ON GOTO/GOSUB/SELECT)
     * @param selector Selector value temporary
     * @param targetBlockIds List of target block IDs
     * @param defaultBlockId Default block if selector out of range
     */
    void emitMultiway(const std::string& selector,
                     const std::vector<int>& targetBlockIds,
                     int defaultBlockId);
    
    /**
     * Emit a RETURN edge (function return)
     * @param returnValue Return value temporary (empty for void)
     */
    void emitReturn(const std::string& returnValue = "");

    // === Block Ordering ===
    
    /**
     * Determine the order to emit blocks (topological sort with special handling)
     * @param cfg CFG to analyze
     * @return Ordered list of block IDs
     */
    std::vector<int> getEmissionOrder(const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Check if a block is reachable
     * @param blockId Block ID
     * @param cfg CFG
     * @return true if reachable from entry
     */
    bool isBlockReachable(int blockId, const FasterBASIC::ControlFlowGraph* cfg);

    // === Label Management ===
    
    /**
     * Get the QBE label name for a CFG block
     * @param blockId Block ID
     * @return Label name
     */
    std::string getBlockLabel(int blockId);
    
    /**
     * Register a label that needs to be emitted
     * @param blockId Block ID
     */
    void registerLabel(int blockId);
    
    /**
     * Check if a label has been emitted
     * @param blockId Block ID
     * @return true if label already emitted
     */
    bool isLabelEmitted(int blockId);

    // === Special Block Types ===
    
    /**
     * Check if a block is a loop header
     * @param block Block to check
     * @param cfg CFG
     * @return true if this block is a loop header
     */
    bool isLoopHeader(const FasterBASIC::BasicBlock* block,
                     const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Check if a block is an exit block
     * @param block Block to check
     * @param cfg CFG
     * @return true if this block has no successors or only returns
     */
    bool isExitBlock(const FasterBASIC::BasicBlock* block,
                    const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Find the ForStatement associated with a loop header block
     * @param headerBlock Loop header block
     * @param cfg CFG
     * @return ForStatement pointer or nullptr
     */
    const FasterBASIC::ForStatement* findForStatementForHeader(
        const FasterBASIC::BasicBlock* headerBlock,
        const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Find ForStatement in a loop by searching predecessors
     * @param block Block to search from
     * @param cfg CFG
     * @return ForStatement pointer or nullptr
     */
    const FasterBASIC::ForStatement* findForStatementInLoop(
        const FasterBASIC::BasicBlock* block,
        const FasterBASIC::ControlFlowGraph* cfg);

    // === Context Management ===
    
    /**
     * Enter a new function context
     * @param functionName Function name
     */
    void enterFunction(const std::string& functionName);
    
    /**
     * Exit current function context
     */
    void exitFunction();
    
    /**
     * Reset emitter state (for testing)
     */
    void reset();

private:
    QBEBuilder& builder_;
    TypeManager& typeManager_;
    SymbolMapper& symbolMapper_;
    ASTEmitter& astEmitter_;
    
    // Current function context
    std::string currentFunction_;
    
    // Labels that have been emitted
    std::unordered_set<int> emittedLabels_;
    
    // Labels that need to be emitted
    std::unordered_set<int> requiredLabels_;
    
    // Block reachability cache
    std::unordered_map<int, bool> reachabilityCache_;
    
    // Current loop condition (for FOR/WHILE headers)
    std::string currentLoopCondition_;
    
    // === Helper Methods ===
    
    /**
     * Emit statements in a block
     * @param block Block containing statements
     */
    void emitBlockStatements(const FasterBASIC::BasicBlock* block);
    
    /**
     * Get all out-edges from a block
     * @param block Block
     * @param cfg CFG
     * @return List of out-edges
     */
    std::vector<FasterBASIC::CFGEdge> getOutEdges(const FasterBASIC::BasicBlock* block,
                                                   const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Compute reachability from entry block
     * @param cfg CFG to analyze
     */
    void computeReachability(const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Perform depth-first search for reachability
     * @param blockId Current block
     * @param cfg CFG
     * @param visited Set of visited blocks
     */
    void dfsReachability(int blockId, 
                        const FasterBASIC::ControlFlowGraph* cfg,
                        std::unordered_set<int>& visited);
    
    /**
     * Get edge type name for debugging
     * @param edgeType Edge type
     * @return Human-readable name
     */
    std::string getEdgeTypeName(FasterBASIC::EdgeType edgeType);
    
    // === ON GOTO/GOSUB Helpers ===
    
    /**
     * Evaluate selector expression and normalize to word type
     * @param expr Selector expression
     * @return Temporary containing word-type selector
     */
    std::string emitSelectorWord(const FasterBASIC::Expression* expr);
    
    /**
     * Emit code to push a return block ID onto the GOSUB return stack
     * @param returnBlockId Block ID to push
     */
    void emitPushReturnBlock(int returnBlockId);
    
    /**
     * Emit ON GOTO terminator (switch-based dispatch)
     * @param stmt ON GOTO statement
     * @param block Current block
     * @param cfg CFG
     */
    void emitOnGotoTerminator(const FasterBASIC::OnGotoStatement* stmt,
                             const FasterBASIC::BasicBlock* block,
                             const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Emit ON GOSUB terminator (switch-based dispatch to trampolines)
     * @param stmt ON GOSUB statement
     * @param block Current block
     * @param cfg CFG
     */
    void emitOnGosubTerminator(const FasterBASIC::OnGosubStatement* stmt,
                              const FasterBASIC::BasicBlock* block,
                              const FasterBASIC::ControlFlowGraph* cfg);

    /**
     * Emit ON CALL terminator (computed call to named SUB)
     * @param stmt ON CALL statement
     * @param block Current basic block
     * @param cfg CFG
     */
    void emitOnCallTerminator(const FasterBASIC::OnCallStatement* stmt,
                             const FasterBASIC::BasicBlock* block,
                             const FasterBASIC::ControlFlowGraph* cfg);
};

} // namespace fbc

#endif // CFG_EMITTER_H