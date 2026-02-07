#ifndef CFG_EMITTER_H
#define CFG_EMITTER_H

#include <string>
#include <unordered_map>
#include <unordered_set>
#include <set>
#include <vector>
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
    // === SAMM Preamble ===
    
    /**
     * Type of SAMM preamble to emit at the start of block 0.
     * Set before calling emitCFG() so the preamble is emitted inside the
     * first labeled block (QBE requires all instructions to be inside a
     * labeled block — emitting them before @block_0 is illegal).
     */
    enum class SAMMPreamble {
        NONE,           // No SAMM preamble (default)
        MAIN_INIT,      // Emit samm_init()      — for main program
        SCOPE_ENTER     // Emit samm_enter_scope() — for FUNCTION / SUB
    };

    CFGEmitter(QBEBuilder& builder, TypeManager& typeManager,
               SymbolMapper& symbolMapper, ASTEmitter& astEmitter);
    ~CFGEmitter() = default;

    /**
     * Set the SAMM preamble to emit at the start of block 0.
     * Must be called BEFORE emitCFG(). Automatically reset to NONE
     * after emitCFG() completes.
     *
     * @param type   Preamble type (MAIN_INIT or SCOPE_ENTER)
     * @param label  Human-readable scope label for comments
     *               (e.g. "FUNCTION", "SUB", "main")
     */
    void setSAMMPreamble(SAMMPreamble type, const std::string& label = "");

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
     * @param cfg CFG (unused — kept for API compatibility; uses cached data)
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

    // === Edge Index (O(1) out-edge lookup) ===

    /**
     * Get all out-edges for a block using the precomputed index.
     * Falls back to a linear scan when no index has been built (should
     * not happen during normal emission).
     *
     * @param blockId Block ID
     * @return Reference to the vector of out-edges (empty vector if none)
     */
    const std::vector<FasterBASIC::CFGEdge>& getOutEdgesIndexed(int blockId) const;

private:
    QBEBuilder& builder_;
    TypeManager& typeManager_;
    SymbolMapper& symbolMapper_;
    ASTEmitter& astEmitter_;
    
    // Current function context
    std::string currentFunction_;
    
    // Pointer to the CFG currently being emitted (valid between
    // enterFunction / exitFunction pairs inside emitCFG).
    const FasterBASIC::ControlFlowGraph* currentCFG_ = nullptr;

    // Labels that have been emitted
    std::unordered_set<int> emittedLabels_;
    
    // Labels that need to be emitted
    std::unordered_set<int> requiredLabels_;
    
    // Block reachability cache
    std::unordered_map<int, bool> reachabilityCache_;
    
    // Current loop condition (for FOR/WHILE headers)
    std::string currentLoopCondition_;

    // SAMM preamble to emit at the start of block 0
    SAMMPreamble sammPreamble_ = SAMMPreamble::NONE;
    std::string  sammPreambleLabel_;

    // === NEON Phase 3: SIMD loop vectorization state ===

    // Set of block IDs whose normal content emission should be suppressed
    // because they belong to a FOR loop that was replaced by a NEON
    // vectorized loop.  Populated by emitBlock() when a FOR init block
    // is successfully vectorized; checked for header/body/increment blocks.
    std::set<int> simdReplacedBlocks_;

    // Pre-built index: blockId → vector of out-edges.
    // Built once per CFG in buildEdgeIndex() and used by every
    // getOutEdgesIndexed() call, turning O(E)-per-lookup into O(1).
    std::unordered_map<int, std::vector<FasterBASIC::CFGEdge>> outEdgeIndex_;

    // Sentinel empty vector returned by getOutEdgesIndexed when a block
    // has no out-edges in the index.
    static const std::vector<FasterBASIC::CFGEdge> emptyEdgeVec_;

    // === Helper Methods ===

    /**
     * Scan all blocks in the CFG for FOR and FOR EACH statements and
     * pre-allocate their internal stack slots (limit, step, index, etc.)
     * via ASTEmitter.  Must be called during entry-block (block 0)
     * emission so that the resulting alloc instructions land in QBE's
     * start block — a hard requirement of the QBE backend.
     *
     * @param cfg The control flow graph to scan
     */
    void preAllocateAllLoopSlots(const FasterBASIC::ControlFlowGraph* cfg);

    /**
     * Build the out-edge index for the given CFG.
     * Must be called once before any getOutEdgesIndexed() lookups.
     *
     * @param cfg The control flow graph to index
     */
    void buildEdgeIndex(const FasterBASIC::ControlFlowGraph* cfg);

    /**
     * Legacy wrapper — returns a copy of the out-edges for a block.
     * Prefer getOutEdgesIndexed() for new code.
     */
    std::vector<FasterBASIC::CFGEdge> getOutEdges(const FasterBASIC::BasicBlock* block,
                                                   const FasterBASIC::ControlFlowGraph* cfg);

    // === NEON Phase 3 helpers ===

    /**
     * Find the exit block of a FOR loop starting from its init block.
     * Follows init → FALLTHROUGH → header → CONDITIONAL_FALSE → exit.
     *
     * @param initBlock  The FOR init block
     * @param cfg        The CFG
     * @return Exit block ID, or -1 if not found
     */
    int findForExitBlock(const FasterBASIC::BasicBlock* initBlock,
                         const FasterBASIC::ControlFlowGraph* cfg);

    /**
     * Collect all block IDs that belong to a FOR loop (header, body,
     * increment) so their normal emission can be suppressed after NEON
     * vectorization replaces the loop.
     *
     * @param initBlock  The FOR init block
     * @param exitBlockId The exit block ID (not collected)
     * @param cfg        The CFG
     * @param outIds     Set to fill with block IDs to suppress
     */
    void collectForLoopBlocks(const FasterBASIC::BasicBlock* initBlock,
                              int exitBlockId,
                              const FasterBASIC::ControlFlowGraph* cfg,
                              std::set<int>& outIds);
    
    /**
     * Emit statements in a block
     * @param block Block containing statements
     */
    void emitBlockStatements(const FasterBASIC::BasicBlock* block);
    
    /**
     * Compute reachability from entry block
     * @param cfg CFG to analyze
     */
    void computeReachability(const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Perform depth-first search for reachability.
     * Uses the pre-built edge index (must call buildEdgeIndex first).
     *
     * @param blockId Current block
     * @param visited Set of visited blocks
     */
    void dfsReachability(int blockId,
                        std::unordered_set<int>& visited);
    
    /**
     * Get edge type name for debugging
     * @param edgeType Edge type
     * @return Human-readable name
     */
    std::string getEdgeTypeName(FasterBASIC::EdgeType edgeType);
    
    // === Decomposed Terminator Helpers ===
    
    /**
     * Scan a block's statements and extract control-flow-relevant statements.
     * Populates the four out-parameters with the first matching statement of
     * each kind found in the block (or nullptr if absent).
     */
    void scanControlFlowStatements(
        const FasterBASIC::BasicBlock* block,
        const FasterBASIC::ReturnStatement*& outReturn,
        const FasterBASIC::OnGotoStatement*& outOnGoto,
        const FasterBASIC::OnGosubStatement*& outOnGosub,
        const FasterBASIC::OnCallStatement*& outOnCall);
    
    /**
     * Handle a RETURN statement found inside a block: evaluate the return
     * expression (if any) and store it in the function's implicit return
     * variable.
     */
    void emitReturnStatementValue(const FasterBASIC::ReturnStatement* returnStmt);
    
    /**
     * Emit the terminator for an exit block (no out-edges).
     * For main this emits `ret 0`; for functions it loads and returns the
     * implicit return variable; for SUBs it emits a bare `ret`.
     */
    void emitExitBlockTerminator();
    
    /**
     * Emit the GOSUB call pattern: push the return-point block ID onto
     * the GOSUB return stack, then jump to the subroutine entry block.
     */
    void emitGosubCallEdge(const std::vector<FasterBASIC::CFGEdge>& outEdges,
                           const FasterBASIC::BasicBlock* block);
    
    /**
     * Emit the RETURN-from-GOSUB dispatch: pop the return stack and
     * branch to the correct return-point block via a comparison chain.
     */
    void emitGosubReturnEdge(const FasterBASIC::BasicBlock* block,
                             const FasterBASIC::ControlFlowGraph* cfg);
    
    /**
     * Emit terminators for simple edge types (FALLTHROUGH, JUMP,
     * CONDITIONAL, EXCEPTION, and generic multi-way).
     */
    void emitSimpleEdgeTerminator(
        const FasterBASIC::BasicBlock* block,
        const std::vector<FasterBASIC::CFGEdge>& outEdges,
        const FasterBASIC::ReturnStatement* returnStmt);

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

    // === Parsing Helpers ===

    /**
     * Safely parse an integer from a string.
     * Unlike std::stoi this never throws; returns false on failure.
     *
     * @param s   String to parse
     * @param out Receives the parsed value on success
     * @return true if the entire string was a valid integer
     */
    static bool tryParseInt(const std::string& s, int& out);
};

} // namespace fbc

#endif // CFG_EMITTER_H