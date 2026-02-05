//
// cfg_builder.h
// FasterBASIC - Control Flow Graph Builder (Modular Architecture)
//
// MODULAR REDESIGN (February 2026)
// 
// This header defines the CFGBuilder class interface.
// Implementation is split across multiple source files for maintainability:
//
// - cfg_builder_core.cpp       : Constructor, main build() entry point
// - cfg_builder_blocks.cpp     : Block creation and edge management
// - cfg_builder_utils.cpp      : Utility functions (reports, type inference)
// - cfg_builder_jumptargets.cpp: Jump target pre-scan (Phase 0)
// - cfg_builder_statements.cpp : Statement dispatcher and block building
// - cfg_builder_jumps.cpp      : GOTO, GOSUB, ON GOTO/GOSUB, labels
// - cfg_builder_conditional.cpp: IF/THEN/ELSE, SELECT CASE
// - cfg_builder_loops.cpp      : FOR, WHILE, REPEAT, DO loops
// - cfg_builder_exception.cpp  : TRY/CATCH/FINALLY
// - cfg_builder_functions.cpp  : FUNCTION, DEF FN, SUB definitions
// - cfg_builder_edges.cpp      : Edge building (Phase 2), loop analysis
//
//
// EXAMPLE OF THE FIX:
// Old approach (BROKEN):
//   Phase 1: Create all blocks linearly [1][2][3][4][5]
//   Phase 2: Scan forward to find loop ends, add back-edges
//   Problem: By Phase 2, context is lost, scanning fails
//
// New approach (FIXED):
//   buildWhile(incoming) {
//     header = create(); body = create(); exit = create();
//     wire(incoming -> header);
//     wire(header -> body [true]); wire(header -> exit [false]);
//     bodyExit = buildStatements(body);
//     wire(bodyExit -> header);  // Back-edge created immediately!
//     return exit;  // Next statement connects here
//   }
//

#ifndef FASTERBASIC_CFG_BUILDER_H
#define FASTERBASIC_CFG_BUILDER_H

#include "../fasterbasic_ast.h"
#include "../fasterbasic_semantic.h"
#include <string>
#include <vector>
#include <map>
#include <memory>
#include <set>
#include <unordered_map>

namespace FasterBASIC {

// Forward declarations
class Statement;
class Program;
class CaseStatement;
class TryCatchStatement;

// =============================================================================
// Edge Types
// =============================================================================

enum class EdgeType {
    FALLTHROUGH,         // Natural flow to next block
    CONDITIONAL_TRUE,    // Condition evaluated to true
    CONDITIONAL_FALSE,   // Condition evaluated to false
    JUMP,               // Unconditional jump (GOTO)
    CALL,               // Subroutine call (GOSUB)
    RETURN,             // Return from subroutine
    EXCEPTION           // Exception/error handling
};

// =============================================================================
// CFG Edge
// =============================================================================

struct CFGEdge {
    int sourceBlock;
    int targetBlock;
    EdgeType type;
    std::string label;  // Optional label for debugging/visualization
    
    CFGEdge() : sourceBlock(-1), targetBlock(-1), type(EdgeType::FALLTHROUGH) {}
};

// =============================================================================
// Basic Block
// =============================================================================

class BasicBlock {
public:
    int id;
    std::string label;
    std::vector<const Statement*> statements;
    std::vector<int> successors;
    std::vector<int> predecessors;
    
    // Block flags
    bool isLoopHeader;
    bool isLoopExit;
    bool isTerminator;  // Ends with GOTO/RETURN/etc
    
    // Line number tracking
    std::set<int> lineNumbers;  // All line numbers in this block
    std::map<const Statement*, int> statementLineNumbers;  // Statement -> line number
    
    BasicBlock(int blockId, const std::string& blockLabel = "")
        : id(blockId), label(blockLabel), isLoopHeader(false), 
          isLoopExit(false), isTerminator(false) {}
    
    void addStatement(const Statement* stmt, int lineNumber = -1) {
        statements.push_back(stmt);
        if (lineNumber >= 0) {
            lineNumbers.insert(lineNumber);
            statementLineNumbers[stmt] = lineNumber;
        }
    }
};

// =============================================================================
// Control Flow Graph
// =============================================================================

class ControlFlowGraph {
public:
    std::string functionName;  // Function/SUB name, or "main" for main program
    std::vector<std::string> parameters;  // Function parameters
    std::vector<VariableType> parameterTypes;  // Parameter types
    VariableType returnType;   // Return type (UNKNOWN for SUBs)
    const DefStatement* defStatement;  // For DEF FN functions
    
    std::vector<std::unique_ptr<BasicBlock>> blocks;
    std::vector<CFGEdge> edges;
    int entryBlock;     // Entry point (usually block 0)
    int exitBlock;      // Exit point
    
    // GOSUB/RETURN tracking for sparse dispatch optimization
    std::set<int> gosubReturnBlocks;  // Block IDs that are GOSUB return points
    
    // DO loop tracking (for old codegen compatibility)
    struct DoLoopBlocks {
        int headerBlock;
        int bodyBlock;
        int exitBlock;
    };
    std::map<int, DoLoopBlocks> doLoopStructure;
    
    ControlFlowGraph() 
        : returnType(VariableType::UNKNOWN), defStatement(nullptr),
          entryBlock(-1), exitBlock(-1) {}
          
    explicit ControlFlowGraph(const std::string& name)
        : functionName(name), returnType(VariableType::UNKNOWN), 
          defStatement(nullptr), entryBlock(-1), exitBlock(-1) {}
};

// =============================================================================
// Program CFG (main + functions)
// =============================================================================

class ProgramCFG {
public:
    std::unique_ptr<ControlFlowGraph> mainCFG;  // Main program CFG
    std::unordered_map<std::string, std::unique_ptr<ControlFlowGraph>> functionCFGs;  // Function CFGs by name
    
    ProgramCFG() : mainCFG(std::make_unique<ControlFlowGraph>("main")) {}
    
    // Get or create a function CFG
    ControlFlowGraph* getFunctionCFG(const std::string& name) {
        auto it = functionCFGs.find(name);
        if (it != functionCFGs.end()) {
            return it->second.get();
        }
        
        // Create new function CFG
        auto cfg = std::make_unique<ControlFlowGraph>(name);
        ControlFlowGraph* ptr = cfg.get();
        functionCFGs[name] = std::move(cfg);
        return ptr;
    }
};

// =============================================================================
// CFGBuilder - Single-Pass Recursive CFG Construction
// =============================================================================

class CFGBuilder {
public:
    // Context structures for nested control flow
    // These replace the global stacks from the old implementation
    
    // Loop context: Tracks loop header/exit for CONTINUE/EXIT statements
    struct LoopContext {
        int headerBlockId;           // Loop header (for CONTINUE)
        int exitBlockId;             // Loop exit (for EXIT FOR/WHILE/DO)
        std::string loopType;        // "FOR", "WHILE", "DO", "REPEAT"
        LoopContext* outerLoop;      // Link to enclosing loop (nullptr if outermost)
        
        LoopContext()
            : headerBlockId(-1), exitBlockId(-1), outerLoop(nullptr) {}
    };
    
    // SELECT CASE context: Tracks exit point for EXIT SELECT
    struct SelectContext {
        int exitBlockId;             // Block to jump to on EXIT SELECT
        SelectContext* outerSelect;  // Link to enclosing SELECT (nullptr if outermost)
        
        SelectContext()
            : exitBlockId(-1), outerSelect(nullptr) {}
    };
    
    // TRY/CATCH context: Tracks catch/finally blocks for exception handling
    struct TryContext {
        int catchBlockId;            // Catch block (for THROW)
        int finallyBlockId;          // Finally block (always executed)
        TryContext* outerTry;        // Link to enclosing TRY (nullptr if outermost)
        
        TryContext()
            : catchBlockId(-1), finallyBlockId(-1), outerTry(nullptr) {}
    };
    
    // Subroutine context: Tracks GOSUB call sites for RETURN
    struct SubroutineContext {
        int returnBlockId;           // Block to return to
        SubroutineContext* outerSub; // Link to enclosing GOSUB (nullptr if outermost)
        
        SubroutineContext()
            : returnBlockId(-1), outerSub(nullptr) {}
    };

public:
    CFGBuilder();
    ~CFGBuilder();
    
    // Main entry point: Build CFG from validated AST
    // Returns: Complete CFG with all blocks and edges wired
    ControlFlowGraph* build(const std::vector<StatementPtr>& statements);
    
    // Adapter: Build CFG from Program structure (flattens ProgramLines)
    // This allows CFG v2 to work with the existing Program AST structure
    // Note: The Program should already have loop bodies populated by the parser
    ControlFlowGraph* buildFromProgram(const Program& program);
    
    // Build complete ProgramCFG with main program and all SUB/FUNCTION CFGs
    // This is the top-level entry point for building CFGs for entire programs
    ProgramCFG* buildProgramCFG(const Program& program);
    
    // Get the constructed CFG (transfers ownership)
    ControlFlowGraph* takeCFG();
    
    // Dump the CFG structure (can be called after build)
    void dumpCFG(const std::string& phase = "") const;
    
    // Set CFG for dumping purposes (does not take ownership)
    void setCFGForDump(ControlFlowGraph* cfg) { m_cfg = cfg; }
    
    // Public access to CFG for verification
    const ControlFlowGraph* getCFG() const { return m_cfg; }

private:
    // =============================================================================
    // Core Recursive Builder
    // =============================================================================
    
    // Build a range of statements starting from 'incoming' block
    // Returns: The "exit" block where control flows after executing all statements
    // 
    // This is the heart of the new architecture. It processes statements one by one,
    // and when it encounters a control structure, it calls the appropriate builder
    // function which recursively handles the nested structure.
    //
    // Context parameters are optional - pass nullptr if not in that context
    BasicBlock* buildStatementRange(
        const std::vector<StatementPtr>& statements,
        BasicBlock* incoming,
        LoopContext* currentLoop = nullptr,
        SelectContext* currentSelect = nullptr,
        TryContext* currentTry = nullptr,
        SubroutineContext* currentSub = nullptr
    );
    
    // =============================================================================
    // Control Structure Builders
    // =============================================================================
    // Each builder follows this contract:
    // - Accepts an incoming block (where control enters)
    // - Creates all necessary internal blocks
    // - Wires all edges (including back-edges for loops)
    // - Recursively processes nested statements
    // - Returns the exit block (where control leaves)
    //
    // If a structure never exits (e.g., infinite loop, GOTO), it returns an
    // unreachable block so subsequent statements can still be added (even if dead).
    // =============================================================================
    
    // IF...THEN...ELSE...END IF
    BasicBlock* buildIf(
        const IfStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // WHILE...WEND (pre-test loop)
    BasicBlock* buildWhile(
        const WhileStatement& stmt,
        BasicBlock* incoming,
        LoopContext* outerLoop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // FOR...NEXT (counted loop with optional STEP)
    BasicBlock* buildFor(
        const ForStatement& stmt,
        BasicBlock* incoming,
        LoopContext* outerLoop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // REPEAT...UNTIL (post-test loop)
    BasicBlock* buildRepeat(
        const RepeatStatement& stmt,
        BasicBlock* incoming,
        LoopContext* outerLoop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // DO...LOOP variants (WHILE/UNTIL, pre-test/post-test)
    BasicBlock* buildDo(
        const DoStatement& stmt,
        BasicBlock* incoming,
        LoopContext* outerLoop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // CASE...END CASE (SELECT CASE style)
    BasicBlock* buildSelectCase(
        const CaseStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* outerSelect,
        TryContext* tryCtx,
        SubroutineContext* sub
    );
    
    // TRY...CATCH...FINALLY...END TRY
    BasicBlock* buildTryCatch(
        const TryCatchStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select,
        TryContext* outerTry,
        SubroutineContext* sub
    );
    
    // =============================================================================
    // Function/Subroutine Builders
    // =============================================================================
    
    // Build CFG for a FUNCTION definition
    // Returns a complete ControlFlowGraph for the function
    ControlFlowGraph* buildFunction(const FunctionStatement& stmt);
    
    // Build CFG for a SUB definition
    // Returns a complete ControlFlowGraph for the subroutine
    ControlFlowGraph* buildSub(const SubStatement& stmt);
    
    // Build CFG for a DEF FN definition (single-expression function)
    // Returns a complete ControlFlowGraph for the inline function
    ControlFlowGraph* buildDefFn(const DefStatement& stmt);
    
    // =============================================================================
    // Terminator Handlers
    // =============================================================================
    // These handle statements that change control flow and don't return
    // (GOTO, RETURN, EXIT, etc.)
    // =============================================================================
    
    // GOTO line_number
    BasicBlock* handleGoto(
        const GotoStatement& stmt,
        BasicBlock* incoming
    );
    
    // GOSUB line_number (call subroutine)
    BasicBlock* handleGosub(
        const GosubStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* outerSub
    );
    
    // RETURN (from GOSUB)
    BasicBlock* handleReturn(
        const ReturnStatement& stmt,
        BasicBlock* incoming,
        SubroutineContext* sub
    );
    
    // ON...GOTO (computed goto with fallthrough)
    BasicBlock* handleOnGoto(
        const OnGotoStatement& stmt,
        BasicBlock* incoming
    );
    
    // ON...GOSUB (computed gosub with fallthrough)
    BasicBlock* handleOnGosub(
        const OnGosubStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* outerSub
    );
    
    // ON...CALL (computed call to named SUB with fallthrough)
    BasicBlock* handleOnCall(
        const OnCallStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select,
        TryContext* tryCtx,
        SubroutineContext* outerSub
    );
    
    // Unified EXIT handler (dispatches based on ExitStatement type)
    BasicBlock* handleExit(
        const ExitStatement& stmt,
        BasicBlock* incoming,
        LoopContext* loop,
        SelectContext* select
    );
    
    // EXIT FOR (exit current FOR loop)
    BasicBlock* handleExitFor(
        BasicBlock* incoming,
        LoopContext* loop
    );
    
    // EXIT WHILE (exit current WHILE loop)
    BasicBlock* handleExitWhile(
        BasicBlock* incoming,
        LoopContext* loop
    );
    
    // EXIT DO (exit current DO loop)
    BasicBlock* handleExitDo(
        BasicBlock* incoming,
        LoopContext* loop
    );
    
    // EXIT SELECT (exit current SELECT CASE)
    BasicBlock* handleExitSelect(
        BasicBlock* incoming,
        SelectContext* select
    );
    
    // CONTINUE (jump to loop header - if supported)
    BasicBlock* handleContinue(
        BasicBlock* incoming,
        LoopContext* loop
    );
    
    // END (program termination)
    BasicBlock* handleEnd(
        const EndStatement& stmt,
        BasicBlock* incoming
    );
    
    // THROW error_code (exception handling)
    BasicBlock* handleThrow(
        const ThrowStatement& stmt,
        BasicBlock* incoming,
        TryContext* tryCtx
    );
    
    // =============================================================================
    // Block and Edge Management
    // =============================================================================
    
    // Create a new basic block
    BasicBlock* createBlock(const std::string& label = "");
    
    // Create an unreachable block (for dead code after terminators)
    // This allows subsequent statements to be added even if they're unreachable
    BasicBlock* createUnreachableBlock();
    
    // Add an edge between two blocks
    void addEdge(int fromBlockId, int toBlockId, const std::string& label = "");
    
    // Add a conditional edge (for IF, WHILE conditions)
    void addConditionalEdge(int fromBlockId, int toBlockId, const std::string& condition);
    
    // Add an unconditional edge (for GOTO, loop back-edges)
    void addUnconditionalEdge(int fromBlockId, int toBlockId);
    
    // Mark a block as terminated (no fallthrough)
    void markTerminated(BasicBlock* block);
    
    // Check if a block is terminated
    bool isTerminated(const BasicBlock* block) const;
    
    // =============================================================================
    // Label and Line Number Resolution
    // =============================================================================
    
    // Resolve a BASIC line number to a block ID
    // (Used for GOTO, GOSUB, ON GOTO, etc.)
    int resolveLineNumberToBlock(int lineNumber);
    
    // Register a block as the target for a specific line number
    void registerLineNumberBlock(int lineNumber, int blockId);
    
    // Register a label as the target for a specific block
    void registerLabel(const std::string& label, int blockId);
    
    // Resolve a label to a block ID
    int resolveLabelToBlock(const std::string& label);
    
    // =============================================================================
    // Helper Functions
    // =============================================================================
    
    // Add a statement to a block with line number tracking
    void addStatementToBlock(BasicBlock* block, const Statement* stmt, int lineNumber = -1);
    
    // Find the innermost loop context of a specific type
    LoopContext* findLoopContext(LoopContext* ctx, const std::string& loopType);
    
    // Split a block if it already contains statements
    // Returns: The new block to continue building in
    BasicBlock* splitBlockIfNeeded(BasicBlock* block);
    
    // Get the current line number for a statement
    int getLineNumber(const Statement* stmt);
    
    // =============================================================================
    // Jump Target Collection (Phase 0)
    // =============================================================================
    
    // Collect all GOTO/GOSUB targets from statement list
    void collectJumpTargets(const std::vector<StatementPtr>& statements);
    
    // Collect all GOTO/GOSUB targets from Program structure
    void collectJumpTargetsFromProgram(const Program& program);
    
    // Recursively collect jump targets from a single statement
    void collectJumpTargetsFromStatement(const Statement* stmt);
    
    // Check if a line number is a jump target
    bool isJumpTarget(int lineNumber) const;
    
    // Resolve deferred edges (Phase 2) - forward GOTOs
    void resolveDeferredEdges();
    
private:
    // =============================================================================
    // Internal State
    // =============================================================================
    
    ControlFlowGraph* m_cfg;                          // The CFG being constructed
    int m_nextBlockId;                                // Next available block ID
    
    // Line number and label mappings
    std::map<int, int> m_lineNumberToBlock;           // Maps BASIC line numbers to blocks
    std::map<std::string, int> m_labelToBlock;        // Maps labels to blocks
    
    // Deferred edge resolution (for forward references)
    struct DeferredEdge {
        int sourceBlockId;
        int targetLineNumber;
        std::string targetLabel;  // For label-based targets
        std::string label;        // Edge label (e.g., "case_1")
    };
    std::vector<DeferredEdge> m_deferredEdges;        // Edges to resolve later
    
    // Statistics and debugging
    int m_totalBlocksCreated;
    int m_totalEdgesCreated;
    bool m_debugMode;                                 // Enable verbose logging
    
    // Program structure tracking
    BasicBlock* m_entryBlock;                         // Program entry point
    BasicBlock* m_exitBlock;                          // Program exit point
    
    // Unreachable code tracking
    std::vector<BasicBlock*> m_unreachableBlocks;     // Dead code blocks
    
    // Jump target tracking (Phase 0)
    std::set<int> m_jumpTargets;                      // Line numbers that are GOTO/GOSUB targets
};

} // namespace FasterBASIC

#endif // FASTERBASIC_CFG_BUILDER_H