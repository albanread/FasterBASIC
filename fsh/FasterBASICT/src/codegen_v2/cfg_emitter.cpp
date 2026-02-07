#include "cfg_emitter.h"
#include "type_manager.h"
#include <algorithm>
#include <queue>
#include <set>
#include <cstdlib>
#include <cerrno>
#include <climits>

namespace fbc {

using namespace FasterBASIC;

// Static sentinel for getOutEdgesIndexed when blockId not in index
const std::vector<CFGEdge> CFGEmitter::emptyEdgeVec_;

CFGEmitter::CFGEmitter(QBEBuilder& builder, TypeManager& typeManager,
                       SymbolMapper& symbolMapper, ASTEmitter& astEmitter)
    : builder_(builder)
    , typeManager_(typeManager)
    , symbolMapper_(symbolMapper)
    , astEmitter_(astEmitter)
    , currentFunction_("")
    , currentCFG_(nullptr)
    , sammPreamble_(SAMMPreamble::NONE)
    , sammPreambleLabel_()
{
}

void CFGEmitter::setSAMMPreamble(SAMMPreamble type, const std::string& label) {
    sammPreamble_ = type;
    sammPreambleLabel_ = label;
}

// =============================================================================
// Parsing Helpers
// =============================================================================

bool CFGEmitter::tryParseInt(const std::string& s, int& out) {
    if (s.empty()) return false;
    const char* begin = s.c_str();
    char* end = nullptr;
    errno = 0;
    long val = std::strtol(begin, &end, 10);
    if (end == begin || *end != '\0') return false;          // not fully consumed
    if (errno == ERANGE || val < INT_MIN || val > INT_MAX) return false;
    out = static_cast<int>(val);
    return true;
}

// =============================================================================
// Edge Index
// =============================================================================

void CFGEmitter::buildEdgeIndex(const ControlFlowGraph* cfg) {
    outEdgeIndex_.clear();
    if (!cfg) return;

    // Pre-size buckets for every block so lookups never miss
    for (const auto& block : cfg->blocks) {
        if (block) {
            outEdgeIndex_[block->id];  // insert empty vector
        }
    }

    for (const auto& edge : cfg->edges) {
        outEdgeIndex_[edge.sourceBlock].push_back(edge);
    }
}

const std::vector<CFGEdge>& CFGEmitter::getOutEdgesIndexed(int blockId) const {
    auto it = outEdgeIndex_.find(blockId);
    if (it != outEdgeIndex_.end()) {
        return it->second;
    }
    return emptyEdgeVec_;
}

// Legacy wrapper — delegates to the index when available, falls back to
// linear scan only if the index hasn't been built (shouldn't happen in
// normal emission but keeps old call-sites safe).
std::vector<CFGEdge> CFGEmitter::getOutEdges(const BasicBlock* block,
                                              const ControlFlowGraph* cfg) {
    if (!block) return {};

    if (!outEdgeIndex_.empty()) {
        // Return a *copy* — callers may mutate the result
        const auto& ref = getOutEdgesIndexed(block->id);
        return ref;
    }

    // Fallback: linear scan (should not be reached during normal emission)
    std::vector<CFGEdge> result;
    if (!cfg) return result;
    for (const auto& edge : cfg->edges) {
        if (edge.sourceBlock == block->id) {
            result.push_back(edge);
        }
    }
    return result;
}

// =============================================================================
// CFG Emission
// =============================================================================

void CFGEmitter::emitCFG(const ControlFlowGraph* cfg, const std::string& functionName) {
    if (!cfg) {
        builder_.emitComment("ERROR: null CFG");
        return;
    }
    
    enterFunction(functionName);
    currentCFG_ = cfg;
    
    builder_.emitComment("CFG: " + (functionName.empty() ? "main" : functionName));
    builder_.emitComment("Blocks: " + std::to_string(cfg->blocks.size()));
    builder_.emitBlankLine();
    
    // Build O(1) edge lookup index — used by every subsequent getOutEdges /
    // getOutEdgesIndexed call for this CFG.
    buildEdgeIndex(cfg);

    // Compute reachability (now cheap thanks to the edge index)
    computeReachability(cfg);
    
    // Get block emission order
    std::vector<int> emissionOrder = getEmissionOrder(cfg);
    
    builder_.emitComment("Emission order computed: " + std::to_string(emissionOrder.size()) + " blocks");
    
    // Emit all blocks in order
    for (int blockId : emissionOrder) {
        if (blockId >= 0 && blockId < static_cast<int>(cfg->blocks.size())) {
            const BasicBlock* block = cfg->blocks[blockId].get();
            if (block) {
                emitBlock(block, cfg);
            }
        }
    }
    
    currentCFG_ = nullptr;
    sammPreamble_ = SAMMPreamble::NONE;
    sammPreambleLabel_.clear();
    exitFunction();
}

void CFGEmitter::emitBlock(const BasicBlock* block, const ControlFlowGraph* cfg) {
    if (!block) {
        builder_.emitComment("ERROR: null block");
        return;
    }
    
    int blockId = block->id;
    
    // Emit label for this block
    std::string label = getBlockLabel(blockId);
    
    // Add comment about block type (annotate unreachable blocks)
    std::string blockInfo = "Block " + std::to_string(blockId);
    if (!block->label.empty()) {
        blockInfo += " (label: " + block->label + ")";
    }
    if (!isBlockReachable(blockId, cfg)) {
        blockInfo += " [UNREACHABLE]";
    }
    
    builder_.emitComment(blockInfo);
    builder_.emitLabel(label);
    
    // If this is the entry block (block 0), emit SAMM preamble (if set)
    // and allocate stack space for all local variables.
    // The preamble MUST be emitted after the label because QBE requires
    // all instructions to be inside a labeled block.
    if (blockId == 0) {
        if (sammPreamble_ == SAMMPreamble::MAIN_INIT && astEmitter_.isSAMMEnabled()) {
            builder_.emitComment("SAMM: Initialise scope-aware memory management");
            builder_.emitCall("", "", "samm_init", "");
        } else if (sammPreamble_ == SAMMPreamble::SCOPE_ENTER && astEmitter_.isSAMMEnabled()) {
            builder_.emitComment("SAMM: Enter " + sammPreambleLabel_ + " scope");
            builder_.emitCall("", "", "samm_enter_scope", "");
        }
        const auto& symbolTable = astEmitter_.getSymbolTable();
        
        // Get function parameters from CFG (these are the actual QBE parameter names)
        std::vector<std::string> cfgParams = cfg->parameters;

        // Sort parameters longest-first so that a parameter named "X_Y"
        // is tried before one named "X" when prefix-matching symbol names.
        // This prevents "X_Y_DOUBLE" from incorrectly matching "X".
        std::sort(cfgParams.begin(), cfgParams.end(),
                  [](const std::string& a, const std::string& b) {
                      return a.length() > b.length();
                  });
        
        for (const auto& pair : symbolTable.variables) {
            const auto& varSymbol = pair.second;
            
            // Allocate variables that belong to current function scope
            bool shouldAllocate = false;
            if (currentFunction_ == "main" && !varSymbol.isGlobal && varSymbol.scope.isGlobal()) {
                // Main program: allocate global-scope non-GLOBAL variables
                // UDT types should be true globals (data section), not stack locals
                if (varSymbol.typeDesc.baseType == BaseType::USER_DEFINED) {
                    continue;  // Skip - UDTs will be emitted as global data
                }
                shouldAllocate = true;
            } else if (currentFunction_ != "main" && varSymbol.scope.isFunction() && 
                       varSymbol.scope.name == currentFunction_) {
                // SUB/FUNCTION: allocate variables that belong to this function
                shouldAllocate = true;
            }
            
            if (shouldAllocate) {
                // This is a local variable - allocate on stack
                // Use variable name from symbol, not the scoped key
                std::string mangledName = symbolMapper_.mangleVariableName(varSymbol.name, false);
                BaseType varType = varSymbol.typeDesc.baseType;
                std::string qbeType = typeManager_.getQBEType(varType);
                int64_t size = typeManager_.getTypeSize(varType);
                
                // OBJECT types (like HASHMAP) should be globals, not stack locals
                // Skip stack allocation for them - they'll be handled as globals
                if (varType == BaseType::OBJECT) {
                    continue;
                }
                
                // For UDT types, calculate actual struct size from field definitions (including nested UDTs)
                if (varType == BaseType::USER_DEFINED) {
                    auto udtIt = symbolTable.types.find(varSymbol.typeName);
                    if (udtIt != symbolTable.types.end()) {
                        size = typeManager_.getUDTSizeRecursive(udtIt->second, symbolTable.types);
                    }
                }
                
                if (size == 4) {
                    builder_.emitRaw("    " + mangledName + " =l alloc4 4");
                } else if (size == 8) {
                    builder_.emitRaw("    " + mangledName + " =l alloc8 8");
                } else {
                    builder_.emitRaw("    " + mangledName + " =l alloc8 " + std::to_string(size));
                }
                
                // Check if this variable is a function parameter
                // Parameters in symbol table are normalized (e.g., X_DOUBLE)
                // CFG parameters are bare names (e.g., X)
                // cfgParams is already sorted longest-first so the most
                // specific parameter wins.
                bool isParameter = false;
                std::string qbeParamName;
                for (const auto& cfgParam : cfgParams) {
                    if (varSymbol.name.find(cfgParam) == 0 && 
                        (varSymbol.name.length() == cfgParam.length() || 
                         varSymbol.name[cfgParam.length()] == '_')) {
                        isParameter = true;
                        qbeParamName = cfgParam;
                        break;
                    }
                }
                
                if (isParameter) {
                    // This is a parameter - store the QBE parameter value
                    std::string qbeParam = "%" + qbeParamName;
                    if (varType == BaseType::USER_DEFINED) {
                        // UDT parameter passed by pointer - store the pointer (long)
                        builder_.emitRaw("    storel " + qbeParam + ", " + mangledName);
                    } else if (size == 4) {
                        if (varType == BaseType::SINGLE) {
                            // SINGLE — store as 32-bit float
                            builder_.emitRaw("    stores " + qbeParam + ", " + mangledName);
                        } else {
                            builder_.emitRaw("    storew " + qbeParam + ", " + mangledName);
                        }
                    } else if (size == 8) {
                        if (typeManager_.isString(varType) || typeManager_.isIntegral(varType) ||
                            varType == BaseType::CLASS_INSTANCE || varType == BaseType::OBJECT ||
                            varType == BaseType::POINTER || varType == BaseType::ARRAY_DESC) {
                            // Strings, LONG, ULONG, CLASS instances, OBJECTs, pointers — store as 64-bit integer / pointer
                            builder_.emitRaw("    storel " + qbeParam + ", " + mangledName);
                        } else {
                            // DOUBLE — store as 64-bit float
                            builder_.emitRaw("    stored " + qbeParam + ", " + mangledName);
                        }
                    }
                } else {
                    // Initialize to 0 (BASIC variables are implicitly initialized)
                    if (typeManager_.isString(varType)) {
                        // Strings initialized to null pointer
                        builder_.emitRaw("    storel 0, " + mangledName);
                    } else if (varType == BaseType::USER_DEFINED) {
                        // UDT types: always zero-initialize all bytes using memset
                        // (covers any field size combination including BYTE/SHORT fields)
                        builder_.emitComment("Zero-initialize UDT (" + std::to_string(size) + " bytes)");
                        builder_.emitRaw("    call $memset(l " + mangledName + ", w 0, l " + std::to_string(size) + ")");
                    } else if (size == 4) {
                        builder_.emitRaw("    storew 0, " + mangledName);
                    } else if (size == 8) {
                        builder_.emitRaw("    storel 0, " + mangledName);
                    }
                }
            }
        }
    }
    
    // Pre-allocate stack slots for ALL FOR / FOR EACH loops in the function.
    // QBE requires alloc instructions to be in the start block; loops that
    // are nested inside other loops would otherwise emit allocs in non-start
    // blocks, triggering a QBE filllive assertion.
    if (blockId == 0) {
        preAllocateAllLoopSlots(cfg);
    }

    // Check if this block was replaced by a NEON vectorized loop — if so,
    // emit only the label (for branch targets) but skip all content and
    // emit a jump to the exit block instead.
    if (simdReplacedBlocks_.count(block->id)) {
        builder_.emitComment("NEON Phase 3: skipped (replaced by vectorized loop)");
        // Emit a fallthrough to the next block so the label is not dangling.
        // The block's normal terminator edges still exist; emit a jump to the
        // first successor so QBE doesn't complain about a missing terminator.
        if (!block->successors.empty()) {
            builder_.emitJump(getBlockLabel(block->successors[0]));
        }
        builder_.emitBlankLine();
        emittedLabels_.insert(blockId);
        return;
    }

    // Check if this is a FOR loop header - emit condition check
    if (block->isLoopHeader && block->label.find("For_Header") != std::string::npos) {
        // Find the ForStatement in the predecessor init block
        const ForStatement* forStmt = findForStatementForHeader(block, cfg);
        if (forStmt) {
            std::string condition = astEmitter_.emitForCondition(forStmt);
            // Store condition for use by terminator
            currentLoopCondition_ = condition;
        }
    }
    
    // Check if this is a FOR...IN loop header - emit condition check
    if (block->isLoopHeader && block->label.find("ForIn_Header") != std::string::npos) {
        // Find the ForInStatement in the predecessor ForIn_Init block
        for (int predId : block->predecessors) {
            if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
                const BasicBlock* predBlock = cfg->blocks[predId].get();
                if (predBlock && predBlock->label.find("ForIn_Init") != std::string::npos) {
                    for (const Statement* stmt : predBlock->statements) {
                        if (stmt && stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                            const ForInStatement* forInStmt = static_cast<const ForInStatement*>(stmt);
                            std::string condition = astEmitter_.emitForEachCondition(forInStmt);
                            currentLoopCondition_ = condition;
                            break;
                        }
                    }
                }
            }
        }
    }
    
    // Check if this is a WHILE loop header - emit condition check
    if (block->isLoopHeader && block->label.find("While_Header") != std::string::npos) {
        // The WhileStatement is in this block
        for (const Statement* stmt : block->statements) {
            if (stmt && stmt->getType() == ASTNodeType::STMT_WHILE) {
                const WhileStatement* whileStmt = static_cast<const WhileStatement*>(stmt);
                std::string condition = astEmitter_.emitWhileCondition(whileStmt);
                // Store condition for use by terminator
                currentLoopCondition_ = condition;
                break;
            }
        }
    }
    
    // Check if this is a DO loop header - emit pre-condition check
    if (block->isLoopHeader && block->label.find("Do_Header") != std::string::npos) {
        // The DoStatement is in this block
        for (const Statement* stmt : block->statements) {
            if (stmt && stmt->getType() == ASTNodeType::STMT_DO) {
                const DoStatement* doStmt = static_cast<const DoStatement*>(stmt);
                std::string condition = astEmitter_.emitDoPreCondition(doStmt);
                // Store condition for use by terminator (empty string if no pre-condition)
                currentLoopCondition_ = condition;
                break;
            }
        }
    }
    
    // Check if this is a DO loop condition block (for post-test DO loops)
    if (block->label.find("Do_Condition") != std::string::npos) {
        // The DoStatement with postCondition is in this block
        for (const Statement* stmt : block->statements) {
            if (stmt && stmt->getType() == ASTNodeType::STMT_DO) {
                const DoStatement* doStmt = static_cast<const DoStatement*>(stmt);
                // Emit the post-condition from the DoStatement
                if (doStmt->postConditionType != DoStatement::ConditionType::NONE && doStmt->postCondition) {
                    std::string condition = astEmitter_.emitExpression(doStmt->postCondition.get());
                    currentLoopCondition_ = condition;
                }
                break;
            }
        }
    }
    
    // Check if this is a FOR loop increment block - emit increment
    if (block->label.find("For_Increment") != std::string::npos) {
        // Find the ForStatement by searching predecessors
        const ForStatement* forStmt = findForStatementInLoop(block, cfg);
        if (forStmt) {
            astEmitter_.emitForIncrement(forStmt);
        }
    }
    
    // Check if this is a FOR...IN loop increment block - emit increment
    if (block->label.find("ForIn_Increment") != std::string::npos) {
        // Find the ForInStatement by following back-edge to header, then to init
        for (int succId : block->successors) {
            if (succId >= 0 && succId < static_cast<int>(cfg->blocks.size())) {
                const BasicBlock* headerBlock = cfg->blocks[succId].get();
                if (headerBlock && headerBlock->label.find("ForIn_Header") != std::string::npos) {
                    for (int predId : headerBlock->predecessors) {
                        if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
                            const BasicBlock* initBlock = cfg->blocks[predId].get();
                            if (initBlock && initBlock->label.find("ForIn_Init") != std::string::npos) {
                                for (const Statement* stmt : initBlock->statements) {
                                    if (stmt && stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                                        const ForInStatement* forInStmt = static_cast<const ForInStatement*>(stmt);
                                        astEmitter_.emitForEachIncrement(forInStmt);
                                        goto forin_increment_done;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        forin_increment_done: ;
    }
    
    // Check if this is a FOR...IN loop body block - emit body preamble
    // (load current array element into loop variable) before statements
    if (block->label.find("ForIn_Body") != std::string::npos) {
        // Find the ForInStatement by going body -> header -> init
        for (int predId : block->predecessors) {
            if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
                const BasicBlock* headerBlock = cfg->blocks[predId].get();
                if (headerBlock && headerBlock->label.find("ForIn_Header") != std::string::npos) {
                    for (int hpredId : headerBlock->predecessors) {
                        if (hpredId >= 0 && hpredId < static_cast<int>(cfg->blocks.size())) {
                            const BasicBlock* initBlock = cfg->blocks[hpredId].get();
                            if (initBlock && initBlock->label.find("ForIn_Init") != std::string::npos) {
                                for (const Statement* stmt : initBlock->statements) {
                                    if (stmt && stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                                        const ForInStatement* forInStmt = static_cast<const ForInStatement*>(stmt);
                                        astEmitter_.emitForEachBodyPreamble(forInStmt);
                                        astEmitter_.setCurrentForEachStmt(forInStmt);
                                        goto forin_preamble_done;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        forin_preamble_done: ;
    }
    
    // Check if this is a FOR...IN loop exit block - emit cleanup
    // (frees the hashmap keys array allocated during init, if applicable)
    if (block->label.find("ForIn_Exit") != std::string::npos) {
        // Trace back to the header (predecessor of exit via false edge),
        // then to the init block (predecessor of header) to find the ForInStatement.
        for (int predId : block->predecessors) {
            if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
                const BasicBlock* headerBlock = cfg->blocks[predId].get();
                if (headerBlock && headerBlock->label.find("ForIn_Header") != std::string::npos) {
                    for (int hpredId : headerBlock->predecessors) {
                        if (hpredId >= 0 && hpredId < static_cast<int>(cfg->blocks.size())) {
                            const BasicBlock* initBlock = cfg->blocks[hpredId].get();
                            if (initBlock && initBlock->label.find("ForIn_Init") != std::string::npos) {
                                for (const Statement* stmt : initBlock->statements) {
                                    if (stmt && stmt->getType() == ASTNodeType::STMT_FOR_IN) {
                                        const ForInStatement* forInStmt = static_cast<const ForInStatement*>(stmt);
                                        astEmitter_.setCurrentForEachStmt(nullptr);
                                        astEmitter_.emitForEachCleanup(forInStmt);
                                        goto forin_cleanup_done;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        forin_cleanup_done: ;
    }

    // === NEON Phase 3: try to vectorize FOR loops ===
    // When we are about to emit the statements of a FOR init block (the
    // block whose statements contain the STMT_FOR), analyse the loop body.
    // If it matches a vectorizable pattern, emit a NEON loop and mark the
    // header/body/increment blocks for suppression.
    {
        const ForStatement* forStmtForSIMD = nullptr;
        for (const Statement* s : block->statements) {
            if (s && s->getType() == ASTNodeType::STMT_FOR) {
                forStmtForSIMD = static_cast<const ForStatement*>(s);
                break;
            }
        }
        if (forStmtForSIMD) {
            SIMDLoopInfo loopInfo = astEmitter_.analyzeSIMDLoop(forStmtForSIMD);
            if (loopInfo.isVectorizable) {
                int exitBlockId = findForExitBlock(block, cfg);
                if (exitBlockId >= 0) {
                    std::string exitLabel = getBlockLabel(exitBlockId);

                    builder_.emitComment("NEON Phase 3: vectorizable FOR loop detected — emitting NEON loop");
                    astEmitter_.emitSIMDLoop(forStmtForSIMD, loopInfo, exitLabel);

                    // Collect header/body/increment blocks and mark them for suppression
                    collectForLoopBlocks(block, exitBlockId, cfg, simdReplacedBlocks_);

                    // Skip the normal statement emission for this init block
                    // (we already emitted the NEON loop in its place).
                    // Still need to emit the terminator-skip and mark block.
                    builder_.emitBlankLine();
                    emittedLabels_.insert(blockId);
                    return;
                }
            }
        }
    }

    // BASIC variables have function scope, not block scope — no SAMM
    // loop-iteration scoping is needed.  Allocations inside loops are
    // cleaned up when the enclosing function/sub scope exits.

    // Emit statements in this block
    emitBlockStatements(block);
    
    // Check if block contains an END statement - if so, skip emitting terminator
    // since END already terminates execution
    bool hasEndStatement = false;
    for (const Statement* stmt : block->statements) {
        if (stmt && stmt->getType() == ASTNodeType::STMT_END) {
            hasEndStatement = true;
            break;
        }
    }
    
    // Emit terminator (control flow) only if block doesn't have END
    if (!hasEndStatement) {
        emitBlockTerminator(block, cfg);
    }
    
    builder_.emitBlankLine();
    
    // Mark label as emitted
    emittedLabels_.insert(blockId);
}

// =============================================================================
// Decomposed Terminator Helpers
// =============================================================================

void CFGEmitter::scanControlFlowStatements(
    const BasicBlock* block,
    const ReturnStatement*& outReturn,
    const OnGotoStatement*& outOnGoto,
    const OnGosubStatement*& outOnGosub,
    const OnCallStatement*& outOnCall)
{
    outReturn = nullptr;
    outOnGoto = nullptr;
    outOnGosub = nullptr;
    outOnCall = nullptr;

    for (const Statement* stmt : block->statements) {
        if (!stmt) continue;
        ASTNodeType stmtType = stmt->getType();

        if (stmtType == ASTNodeType::STMT_RETURN) {
            outReturn = static_cast<const ReturnStatement*>(stmt);
        } else if (stmtType == ASTNodeType::STMT_ON_GOTO) {
            outOnGoto = static_cast<const OnGotoStatement*>(stmt);
        } else if (stmtType == ASTNodeType::STMT_ON_GOSUB) {
            outOnGosub = static_cast<const OnGosubStatement*>(stmt);
        } else if (stmtType == ASTNodeType::STMT_ON_CALL) {
            outOnCall = static_cast<const OnCallStatement*>(stmt);
        }
    }
}

void CFGEmitter::emitReturnStatementValue(const ReturnStatement* returnStmt) {
    if (!returnStmt || !returnStmt->returnValue) return;

    // FUNCTION return – evaluate expression and store in the implicit return variable
    std::string value = astEmitter_.emitExpression(returnStmt->returnValue.get());

    const auto& symbolTable = astEmitter_.getSymbolTable();
    auto funcIt = symbolTable.functions.find(currentFunction_);
    if (funcIt != symbolTable.functions.end()) {
        BaseType returnType = funcIt->second.returnTypeDesc.baseType;
        std::string returnVarName = typeManager_.getReturnVariableName(currentFunction_, returnType);
        astEmitter_.storeVariable(returnVarName, value);
    }
}

void CFGEmitter::emitExitBlockTerminator() {
    if (currentFunction_.empty() || currentFunction_ == "main") {
        // SAMM: Shutdown scope-aware memory management before program exit.
        // This drains the cleanup queue, stops the background worker, and
        // ensures all destructors have run before the process terminates.
        if (astEmitter_.isSAMMEnabled()) {
            builder_.emitComment("SAMM: Shutdown scope-aware memory management");
            builder_.emitCall("", "", "samm_shutdown", "");
        }

        builder_.emitComment("Implicit return 0");
        builder_.emitReturn("0");
        return;
    }

    // Load and return the function's implicit return variable
    const auto& symbolTable = astEmitter_.getSymbolTable();
    auto funcIt = symbolTable.functions.find(currentFunction_);
    if (funcIt == symbolTable.functions.end()) {
        // Unknown function — still exit scope to avoid leak
        if (astEmitter_.isSAMMEnabled()) {
            builder_.emitComment("SAMM: Exit scope (unknown function)");
            builder_.emitCall("", "", "samm_exit_scope", "");
        }

        builder_.emitComment("WARNING: block with no out-edges (missing return?)");
        builder_.emitReturn();
        return;
    }

    const auto& funcSymbol = funcIt->second;
    BaseType returnType = funcSymbol.returnTypeDesc.baseType;

    // SUBs have VOID return type – just return without a value
    if (returnType == BaseType::VOID) {
        // SAMM: Exit SUB scope before returning
        if (astEmitter_.isSAMMEnabled()) {
            builder_.emitComment("SAMM: Exit SUB scope");
            builder_.emitCall("", "", "samm_exit_scope", "");
        }

        builder_.emitComment("SUB exit - no return value");
        builder_.emitReturn();
        return;
    }

    std::string qbeType = typeManager_.getQBEType(returnType);
    std::string returnVarName = typeManager_.getReturnVariableName(currentFunction_, returnType);
    std::string mangledName = symbolMapper_.mangleVariableName(returnVarName, false);
    std::string retTemp = builder_.newTemp();

    builder_.emitLoad(retTemp, qbeType, mangledName);

    // SAMM: If returning a CLASS instance, RETAIN it to the parent scope
    // so it survives the current scope's cleanup. This is essential for
    // factory functions that create and return objects.
    if (returnType == BaseType::CLASS_INSTANCE && astEmitter_.isSAMMEnabled()) {
        builder_.emitComment("SAMM: RETAIN returned CLASS instance to parent scope");
        builder_.emitCall("", "", "samm_retain_parent", "l " + retTemp);
    }

    // SAMM: If returning a STRING, RETAIN it to the parent scope so it
    // survives the current scope's cleanup.  String descriptors are now
    // auto-tracked by SAMM in every scope, so without RETAIN the
    // returned string would be released on scope exit before the caller
    // can use it.
    if (returnType == BaseType::STRING && astEmitter_.isSAMMEnabled()) {
        builder_.emitComment("SAMM: RETAIN returned STRING to parent scope");
        builder_.emitCall("", "", "samm_retain_parent", "l " + retTemp);
    }

    // SAMM: Exit FUNCTION scope before returning.
    // Tracked allocations (except RETAINed ones) are queued for cleanup.
    if (astEmitter_.isSAMMEnabled()) {
        builder_.emitComment("SAMM: Exit FUNCTION scope");
        builder_.emitCall("", "", "samm_exit_scope", "");
    }

    builder_.emitReturn(retTemp);
}

void CFGEmitter::emitGosubCallEdge(const std::vector<CFGEdge>& outEdges,
                                    const BasicBlock* block) {
    if (outEdges.size() < 2) {
        builder_.emitComment("ERROR: GOSUB should have 2 out-edges (call + return point)");
        return;
    }

    int callTarget = -1;
    int returnPoint = -1;

    for (const auto& edge : outEdges) {
        if (edge.type == EdgeType::CALL) {
            callTarget = edge.targetBlock;
        } else if (edge.type == EdgeType::FALLTHROUGH || edge.type == EdgeType::JUMP) {
            returnPoint = edge.targetBlock;
        }
    }

    if (callTarget < 0 || returnPoint < 0) {
        builder_.emitComment("ERROR: Could not find GOSUB call target or return point");
        return;
    }

    builder_.emitComment("GOSUB: push return point, jump to subroutine");
    emitPushReturnBlock(returnPoint);
    emitFallthrough(callTarget);
}

void CFGEmitter::emitGosubReturnEdge(const BasicBlock* block,
                                      const ControlFlowGraph* cfg) {
    builder_.emitComment("RETURN from GOSUB - sparse dispatch");

    // 1. Load current stack pointer
    std::string spTemp = builder_.newTemp();
    builder_.emitLoad(spTemp, "w", "$gosub_return_sp");

    // 2. Decrement stack pointer
    std::string newSp = builder_.newTemp();
    builder_.emitBinary(newSp, "w", "sub", spTemp, "1");
    builder_.emitStore("w", newSp, "$gosub_return_sp");

    // 3. Convert new SP to long for address calculation
    std::string newSpLong = builder_.newTemp();
    builder_.emitExtend(newSpLong, "l", "extsw", newSp);

    // 4. Calculate byte offset: SP * GOSUB_ENTRY_BYTES
    std::string byteOffset = builder_.newTemp();
    builder_.emitBinary(byteOffset, "l", "mul", newSpLong,
                        std::to_string(GOSUB_ENTRY_BYTES));

    // 5. Calculate stack address
    std::string stackAddr = builder_.newTemp();
    builder_.emitBinary(stackAddr, "l", "add", "$gosub_return_stack", byteOffset);

    // 6. Load return block ID
    std::string returnBlockIdTemp = builder_.newTemp();
    builder_.emitLoad(returnBlockIdTemp, "w", stackAddr);

    // 7. Sparse dispatch – compare against known GOSUB return points
    if (cfg && !cfg->gosubReturnBlocks.empty()) {
        builder_.emitComment("Sparse RETURN dispatch - checking " +
                            std::to_string(cfg->gosubReturnBlocks.size()) +
                            " return points");

        std::vector<int> returnBlocks(cfg->gosubReturnBlocks.begin(),
                                      cfg->gosubReturnBlocks.end());
        std::sort(returnBlocks.begin(), returnBlocks.end());

        for (size_t i = 0; i < returnBlocks.size(); ++i) {
            int blkId = returnBlocks[i];
            std::string isMatch = builder_.newTemp();
            builder_.emitCompare(isMatch, "w", "eq", returnBlockIdTemp,
                                std::to_string(blkId));

            std::string targetLabel = getBlockLabel(blkId);
            bool isLast = (i + 1 == returnBlocks.size());

            if (isLast) {
                std::string errorLabel = "return_error_" + std::to_string(block->id);
                builder_.emitBranch(isMatch, targetLabel, errorLabel);
            } else {
                std::string nextCheckLabel = "return_check_" + std::to_string(block->id) +
                                            "_" + std::to_string(i + 1);
                builder_.emitBranch(isMatch, targetLabel, nextCheckLabel);
                builder_.emitLabel(nextCheckLabel);
            }
        }

        builder_.emitLabel("return_error_" + std::to_string(block->id));
        builder_.emitComment("RETURN error: invalid return address");
    } else {
        builder_.emitComment("WARNING: No GOSUB return blocks found");
    }

    builder_.emitComment("RETURN stack error - exiting program");
    builder_.emitReturn("0");
}

void CFGEmitter::emitSimpleEdgeTerminator(
    const BasicBlock* block,
    const std::vector<CFGEdge>& outEdges,
    const ReturnStatement* returnStmt)
{
    EdgeType edgeType = outEdges[0].type;

    if (edgeType == EdgeType::FALLTHROUGH || edgeType == EdgeType::JUMP) {
        if (outEdges.size() == 1) {
            if (returnStmt) {
                builder_.emitComment("RETURN statement - jump to exit");
            } else {
                builder_.emitComment(edgeType == EdgeType::FALLTHROUGH ? "Fallthrough edge" : "Jump edge");
            }
            emitFallthrough(outEdges[0].targetBlock);
        } else {
            builder_.emitComment("ERROR: multiple FALLTHROUGH edges");
            emitFallthrough(outEdges[0].targetBlock);
        }
        return;
    }

    if (edgeType == EdgeType::CONDITIONAL_TRUE || edgeType == EdgeType::CONDITIONAL_FALSE) {
        if (outEdges.size() == 2) {
            builder_.emitComment("Conditional edge");

            std::string condition;
            if (!currentLoopCondition_.empty()) {
                condition = currentLoopCondition_;
                currentLoopCondition_.clear();
            } else if (!block->statements.empty()) {
                const Statement* lastStmt = block->statements.back();
                if (lastStmt && lastStmt->getType() == ASTNodeType::STMT_IF) {
                    const IfStatement* ifStmt = static_cast<const IfStatement*>(lastStmt);
                    condition = astEmitter_.emitIfCondition(ifStmt);
                } else {
                    builder_.emitComment("WARNING: conditional without IF statement");
                    condition = "1";
                }
            } else {
                condition = "1";
            }

            int trueTarget = -1;
            int falseTarget = -1;
            for (const auto& edge : outEdges) {
                if (edge.type == EdgeType::CONDITIONAL_TRUE)  trueTarget  = edge.targetBlock;
                if (edge.type == EdgeType::CONDITIONAL_FALSE) falseTarget = edge.targetBlock;
            }
            if (trueTarget  == -1) trueTarget  = outEdges[0].targetBlock;
            if (falseTarget == -1) falseTarget = outEdges[1].targetBlock;

            emitConditional(condition, trueTarget, falseTarget);
        } else {
            builder_.emitComment("ERROR: conditional with != 2 edges");
            if (!outEdges.empty()) emitFallthrough(outEdges[0].targetBlock);
        }
        return;
    }

    if (edgeType == EdgeType::EXCEPTION) {
        builder_.emitComment("Exception edge");
        if (!outEdges.empty()) emitFallthrough(outEdges[0].targetBlock);
        return;
    }

    // Multiple edges without clear type – treat as multiway
    if (outEdges.size() > 2) {
        builder_.emitComment("Multiway edge (" + std::to_string(outEdges.size()) + " targets)");

        std::vector<int> targets;
        int defaultTarget = -1;
        for (const auto& edge : outEdges) {
            if (edge.label == "default" || edge.label == "otherwise") {
                defaultTarget = edge.targetBlock;
            } else {
                targets.push_back(edge.targetBlock);
            }
        }
        if (defaultTarget == -1 && !targets.empty()) {
            defaultTarget = targets.back();
        }

        // Try to find a SELECT CASE statement in the block to use as the
        // selector expression.  Previously this was a hard-coded "1"
        // placeholder that always jumped to case 1.
        std::string selector;
        for (const Statement* stmt : block->statements) {
            if (stmt && stmt->getType() == ASTNodeType::STMT_CASE) {
                const CaseStatement* caseStmt = static_cast<const CaseStatement*>(stmt);
                if (caseStmt->caseExpression) {
                    selector = emitSelectorWord(caseStmt->caseExpression.get());
                    break;
                }
            }
        }
        if (selector.empty()) {
            builder_.emitComment("WARNING: multiway without selector statement – defaulting to 1");
            selector = "1";
        }

        emitMultiway(selector, targets, defaultTarget);
        return;
    }

    // Unknown edge type – fallthrough to first edge
    builder_.emitComment("WARNING: unknown edge type, using fallthrough");
    if (!outEdges.empty()) emitFallthrough(outEdges[0].targetBlock);
}

// =============================================================================
// Main Terminator (decomposed)
// =============================================================================

void CFGEmitter::emitBlockTerminator(const BasicBlock* block, const ControlFlowGraph* cfg) {
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);

    // 1. Scan the block for control-flow-relevant statements
    const ReturnStatement* returnStmt = nullptr;
    const OnGotoStatement* onGotoStmt = nullptr;
    const OnGosubStatement* onGosubStmt = nullptr;
    const OnCallStatement* onCallStmt = nullptr;
    scanControlFlowStatements(block, returnStmt, onGotoStmt, onGosubStmt, onCallStmt);

    // 2. ON GOTO / ON GOSUB / ON CALL take priority
    if (onGotoStmt)  { emitOnGotoTerminator(onGotoStmt, block, cfg);   return; }
    if (onGosubStmt) { emitOnGosubTerminator(onGosubStmt, block, cfg); return; }
    if (onCallStmt)  { emitOnCallTerminator(onCallStmt, block, cfg);   return; }

    // 3. Process RETURN statement value (store into implicit return var)
    if (returnStmt) {
        emitReturnStatementValue(returnStmt);
    }

    // 4. Exit block (no out-edges)
    if (outEdges.empty()) {
        emitExitBlockTerminator();
        return;
    }

    // 5. Check for CALL / RETURN edges (GOSUB pattern)
    bool hasCallEdge = false;
    bool hasReturnEdge = false;
    for (const auto& edge : outEdges) {
        if (edge.type == EdgeType::CALL)   hasCallEdge   = true;
        if (edge.type == EdgeType::RETURN) hasReturnEdge = true;
    }

    if (hasCallEdge)   { emitGosubCallEdge(outEdges, block);    return; }
    if (hasReturnEdge) { emitGosubReturnEdge(block, cfg);       return; }

    // 6. Simple edges (fallthrough, conditional, exception, multiway)
    emitSimpleEdgeTerminator(block, outEdges, returnStmt);
}

void CFGEmitter::emitFallthrough(int targetBlockId) {
    std::string targetLabel = getBlockLabel(targetBlockId);
    builder_.emitJump(targetLabel);
}

void CFGEmitter::emitConditional(const std::string& condition,
                                int trueBlockId, int falseBlockId) {
    std::string trueLabel = getBlockLabel(trueBlockId);
    std::string falseLabel = getBlockLabel(falseBlockId);
    builder_.emitBranch(condition, trueLabel, falseLabel);
}

void CFGEmitter::emitMultiway(const std::string& selector,
                             const std::vector<int>& targetBlockIds,
                             int defaultBlockId) {
    // Emit a switch-like structure using conditional jumps
    builder_.emitComment("Multiway dispatch");
    
    std::string defaultLabel = getBlockLabel(defaultBlockId);
    
    for (size_t i = 0; i < targetBlockIds.size(); ++i) {
        std::string caseValue = std::to_string(i + 1);
        std::string targetLabel = getBlockLabel(targetBlockIds[i]);
        
        // Compare selector with case value
        std::string cmpResult = builder_.newTemp();
        builder_.emitCompare(cmpResult, "w", "eq", selector, caseValue);
        
        // If match, jump to target; otherwise continue
        std::string nextCaseLabel = symbolMapper_.getUniqueLabel("case_next");
        builder_.emitBranch(cmpResult, targetLabel, nextCaseLabel);
        builder_.emitLabel(nextCaseLabel);
    }
    
    // No match - jump to default
    builder_.emitJump(defaultLabel);
}

void CFGEmitter::emitReturn(const std::string& returnValue) {
    builder_.emitReturn(returnValue);
}

// =============================================================================
// Block Ordering
// =============================================================================

std::vector<int> CFGEmitter::getEmissionOrder(const ControlFlowGraph* cfg) {
    std::vector<int> order;
    
    if (!cfg || cfg->blocks.empty()) {
        return order;
    }
    
    // Emit all blocks in ID order.
    // We must include UNREACHABLE blocks as well because GOSUB / ON GOTO
    // targets are resolved via edges that the reachability DFS may not
    // traverse (e.g. RETURN edges).  Unreachable blocks are annotated
    // in the emitted IL with a comment so they're easy to spot.
    for (size_t i = 0; i < cfg->blocks.size(); ++i) {
        if (cfg->blocks[i]) {
            order.push_back(cfg->blocks[i]->id);
        }
    }
    
    return order;
}

bool CFGEmitter::isBlockReachable(int blockId, const ControlFlowGraph* /*cfg*/) {
    auto it = reachabilityCache_.find(blockId);
    if (it != reachabilityCache_.end()) {
        return it->second;
    }
    
    // If not in cache, assume reachable (conservative)
    return true;
}

// =============================================================================
// Label Management
// =============================================================================

std::string CFGEmitter::getBlockLabel(int blockId) {
    return symbolMapper_.getBlockLabel(blockId);
}

void CFGEmitter::registerLabel(int blockId) {
    requiredLabels_.insert(blockId);
}

bool CFGEmitter::isLabelEmitted(int blockId) {
    return emittedLabels_.find(blockId) != emittedLabels_.end();
}

// =============================================================================
// Special Block Types
// =============================================================================

bool CFGEmitter::isLoopHeader(const BasicBlock* block, const ControlFlowGraph* /*cfg*/) {
    if (!block) return false;
    return block->isLoopHeader;
}

const ForStatement* CFGEmitter::findForStatementInLoop(const BasicBlock* block, const ControlFlowGraph* cfg) {
    if (!block || !cfg) return nullptr;
    
    // For a For_Increment block, we need to find the corresponding For_Init block
    // The structure is: For_Init -> For_Header -> For_Body -> For_Increment -> For_Header (back-edge)
    // Strategy: Follow the successor (back-edge to header), then find the For_Init predecessor
    
    // First, check if this is a For_Increment block
    if (block->label.find("For_Increment") == std::string::npos) {
        // Not an increment block, fall back to general search
        std::set<int> visited;
        std::queue<int> toVisit;
        toVisit.push(block->id);
        
        while (!toVisit.empty()) {
            int currentId = toVisit.front();
            toVisit.pop();
            
            if (visited.count(currentId)) continue;
            visited.insert(currentId);
            
            if (currentId >= 0 && currentId < static_cast<int>(cfg->blocks.size())) {
                const BasicBlock* currentBlock = cfg->blocks[currentId].get();
                if (currentBlock) {
                    for (const Statement* stmt : currentBlock->statements) {
                        if (stmt && stmt->getType() == ASTNodeType::STMT_FOR) {
                            return static_cast<const ForStatement*>(stmt);
                        }
                    }
                    
                    for (int predId : currentBlock->predecessors) {
                        if (!visited.count(predId)) {
                            toVisit.push(predId);
                        }
                    }
                }
            }
        }
        return nullptr;
    }
    
    // This is a For_Increment block - follow the back-edge to the header
    // The increment block should have exactly one successor (the header)
    if (block->successors.size() != 1) {
        return nullptr;  // Malformed loop
    }
    
    int headerId = block->successors[0];
    if (headerId < 0 || headerId >= static_cast<int>(cfg->blocks.size())) {
        return nullptr;
    }
    
    const BasicBlock* headerBlock = cfg->blocks[headerId].get();
    if (!headerBlock || headerBlock->label.find("For_Header") == std::string::npos) {
        return nullptr;  // Not a valid header
    }
    
    // Now find the For_Init block among the header's predecessors
    // The For_Init block is the one with "For_Init" in its label
    for (int predId : headerBlock->predecessors) {
        if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
            const BasicBlock* predBlock = cfg->blocks[predId].get();
            if (predBlock && predBlock->label.find("For_Init") != std::string::npos) {
                // Found the init block - look for ForStatement in it
                for (const Statement* stmt : predBlock->statements) {
                    if (stmt && stmt->getType() == ASTNodeType::STMT_FOR) {
                        return static_cast<const ForStatement*>(stmt);
                    }
                }
            }
        }
    }
    
    return nullptr;
}

bool CFGEmitter::isExitBlock(const BasicBlock* block, const ControlFlowGraph* cfg) {
    if (!block) return false;
    
    const auto& outEdges = getOutEdgesIndexed(block->id);
    
    if (outEdges.empty()) {
        return true;
    }
    
    // Check if all edges are RETURN edges
    for (const auto& edge : outEdges) {
        if (edge.type != EdgeType::RETURN) {
            return false;
        }
    }
    
    return true;
}

// =============================================================================
// Context Management
// =============================================================================

void CFGEmitter::enterFunction(const std::string& functionName) {
    currentFunction_ = functionName;
    emittedLabels_.clear();
    requiredLabels_.clear();
    reachabilityCache_.clear();
    outEdgeIndex_.clear();
    simdReplacedBlocks_.clear();
}

void CFGEmitter::exitFunction() {
    currentFunction_.clear();
}

void CFGEmitter::reset() {
    currentFunction_.clear();
    emittedLabels_.clear();
    requiredLabels_.clear();
    reachabilityCache_.clear();
    outEdgeIndex_.clear();
    simdReplacedBlocks_.clear();
    currentCFG_ = nullptr;
}

void CFGEmitter::preAllocateAllLoopSlots(const FasterBASIC::ControlFlowGraph* cfg) {
    // Pre-allocate shared scratch buffers (bounds array for DIM,
    // indices array for array access) so that no alloc instructions
    // are emitted in non-start blocks.
    astEmitter_.preAllocateSharedBuffers();

    // Scan every block in the CFG for FOR and FOR EACH statements.
    // For each one found, call the ASTEmitter pre-allocation method so
    // that the alloc instructions are emitted in the current (entry) block.
    for (const auto& blockPtr : cfg->blocks) {
        if (!blockPtr) continue;
        for (const FasterBASIC::Statement* stmt : blockPtr->statements) {
            if (!stmt) continue;
            if (stmt->getType() == FasterBASIC::ASTNodeType::STMT_FOR_IN) {
                const auto* forInStmt = static_cast<const FasterBASIC::ForInStatement*>(stmt);
                astEmitter_.preAllocateForEachSlots(forInStmt);
            } else if (stmt->getType() == FasterBASIC::ASTNodeType::STMT_FOR) {
                const auto* forStmt = static_cast<const FasterBASIC::ForStatement*>(stmt);
                astEmitter_.preAllocateForSlots(forStmt);
            }
        }
    }
}

// =============================================================================
// Helper Methods
// =============================================================================

void CFGEmitter::emitBlockStatements(const BasicBlock* block) {
    if (!block) return;
    
    for (const Statement* stmt : block->statements) {
        if (stmt) {
            // Skip control flow terminators - they will be handled by emitBlockTerminator
            // Skip GOTO and LABEL - they are handled by CFG edges and block structure
            ASTNodeType stmtType = stmt->getType();
            if (stmtType == ASTNodeType::STMT_RETURN ||
                stmtType == ASTNodeType::STMT_ON_GOTO ||
                stmtType == ASTNodeType::STMT_ON_GOSUB ||
                stmtType == ASTNodeType::STMT_ON_CALL ||
                stmtType == ASTNodeType::STMT_GOTO ||
                stmtType == ASTNodeType::STMT_LABEL) {
                continue;
            }
            astEmitter_.emitStatement(stmt);
        }
    }
}

const ForStatement* CFGEmitter::findForStatementForHeader(const BasicBlock* headerBlock, const ControlFlowGraph* cfg) {
    if (!headerBlock || !cfg) return nullptr;
    
    // The FOR statement is in the init block (predecessor of header)
    for (int predId : headerBlock->predecessors) {
        if (predId >= 0 && predId < static_cast<int>(cfg->blocks.size())) {
            const BasicBlock* predBlock = cfg->blocks[predId].get();
            if (predBlock && predBlock->label.find("For_Init") != std::string::npos) {
                // Found the init block, look for ForStatement
                for (const Statement* stmt : predBlock->statements) {
                    if (stmt && stmt->getType() == ASTNodeType::STMT_FOR) {
                        return static_cast<const ForStatement*>(stmt);
                    }
                }
            }
        }
    }
    return nullptr;
}

// =============================================================================
// NEON Phase 3: FOR-loop exit block finder
// =============================================================================

int CFGEmitter::findForExitBlock(const FasterBASIC::BasicBlock* initBlock,
                                  const FasterBASIC::ControlFlowGraph* cfg) {
    if (!initBlock || !cfg) return -1;

    // Step 1: follow FALLTHROUGH from init block to the header block
    int headerBlockId = -1;
    const auto& initEdges = getOutEdgesIndexed(initBlock->id);
    for (const auto& e : initEdges) {
        if (e.type == FasterBASIC::EdgeType::FALLTHROUGH ||
            e.type == FasterBASIC::EdgeType::JUMP) {
            headerBlockId = e.targetBlock;
            break;
        }
    }
    if (headerBlockId < 0) return -1;

    // Step 2: from the header, find the CONDITIONAL_FALSE edge → exit block
    const auto& headerEdges = getOutEdgesIndexed(headerBlockId);
    for (const auto& e : headerEdges) {
        if (e.type == FasterBASIC::EdgeType::CONDITIONAL_FALSE) {
            return e.targetBlock;
        }
    }
    return -1;
}

// =============================================================================
// NEON Phase 3: collect all blocks belonging to a FOR loop
// =============================================================================

void CFGEmitter::collectForLoopBlocks(const FasterBASIC::BasicBlock* initBlock,
                                       int exitBlockId,
                                       const FasterBASIC::ControlFlowGraph* cfg,
                                       std::set<int>& outIds) {
    if (!initBlock || !cfg) return;

    // We do a simple BFS/DFS from the init block's successors, stopping at
    // the exit block.  Every block reached that is NOT the exit block is
    // part of the loop and should be suppressed.
    std::set<int> visited;
    std::vector<int> worklist;

    // Seed with init block's successors
    for (const auto& e : getOutEdgesIndexed(initBlock->id)) {
        if (e.targetBlock != exitBlockId) {
            worklist.push_back(e.targetBlock);
        }
    }

    while (!worklist.empty()) {
        int bid = worklist.back();
        worklist.pop_back();
        if (bid == exitBlockId) continue;
        if (bid == initBlock->id) continue;  // don't loop back to init
        if (visited.count(bid)) continue;
        visited.insert(bid);
        outIds.insert(bid);

        // Follow successors
        const auto& edges = getOutEdgesIndexed(bid);
        for (const auto& e : edges) {
            if (!visited.count(e.targetBlock) && e.targetBlock != exitBlockId) {
                worklist.push_back(e.targetBlock);
            }
        }
    }
}

void CFGEmitter::computeReachability(const FasterBASIC::ControlFlowGraph* cfg) {
    if (!cfg) return;
    
    reachabilityCache_.clear();
    
    // Mark all blocks as unreachable initially
    for (const auto& block : cfg->blocks) {
        if (block) {
            reachabilityCache_[block->id] = false;
        }
    }
    
    // DFS from entry block (uses the pre-built edge index)
    std::unordered_set<int> visited;
    dfsReachability(cfg->entryBlock, visited);
}

void CFGEmitter::dfsReachability(int blockId,
                                 std::unordered_set<int>& visited) {
    if (visited.count(blockId)) {
        return;  // Already visited
    }
    
    visited.insert(blockId);
    reachabilityCache_[blockId] = true;
    
    // Use the pre-built edge index for O(1) lookup
    const auto& outEdges = getOutEdgesIndexed(blockId);
    for (const auto& edge : outEdges) {
        dfsReachability(edge.targetBlock, visited);
    }
}

std::string CFGEmitter::getEdgeTypeName(EdgeType edgeType) {
    switch (edgeType) {
        case EdgeType::FALLTHROUGH: return "FALLTHROUGH";
        case EdgeType::CONDITIONAL_TRUE: return "CONDITIONAL_TRUE";
        case EdgeType::CONDITIONAL_FALSE: return "CONDITIONAL_FALSE";
        case EdgeType::JUMP: return "JUMP";
        case EdgeType::CALL: return "CALL";
        case EdgeType::RETURN: return "RETURN";
        case EdgeType::EXCEPTION: return "EXCEPTION";
        default: return "UNKNOWN";
    }
}

// =============================================================================
// ON GOTO/GOSUB Helpers
// =============================================================================

std::string CFGEmitter::emitSelectorWord(const Expression* expr) {
    // Evaluate the selector expression
    std::string selector = astEmitter_.emitExpression(expr);

    // Get the expression type
    BaseType exprType = astEmitter_.getExpressionType(expr);

    // If already an integer type, ensure it's a word (w)
    if (exprType == BaseType::INTEGER || exprType == BaseType::LONG ||
        exprType == BaseType::SHORT || exprType == BaseType::BYTE) {
        if (exprType == BaseType::INTEGER) {
            return selector;  // Already word
        }
        std::string wordTemp = builder_.newTemp();
        if (exprType == BaseType::LONG) {
            builder_.emitTrunc(wordTemp, "w", selector);
        } else if (exprType == BaseType::SHORT) {
            builder_.emitExtend(wordTemp, "w", "extsh", selector);
        } else if (exprType == BaseType::BYTE) {
            builder_.emitExtend(wordTemp, "w", "extsb", selector);
        }
        return wordTemp;
    }

    // Convert floating point to word
    std::string wordTemp = builder_.newTemp();
    if (exprType == BaseType::DOUBLE) {
        builder_.emitConvert(wordTemp, "w", "dtosi", selector);
    } else if (exprType == BaseType::SINGLE) {
        builder_.emitConvert(wordTemp, "w", "stosi", selector);
    } else {
        // Default: truncate / copy as word
        builder_.emitTrunc(wordTemp, "w", selector);
    }

    return wordTemp;
}

void CFGEmitter::emitPushReturnBlock(int returnBlockId) {
    builder_.emitComment("Push return block " + std::to_string(returnBlockId) + " onto GOSUB return stack");

    // 1. Load current stack pointer
    std::string spTemp = builder_.newTemp();
    builder_.emitLoad(spTemp, "w", "$gosub_return_sp");

    // 2. Convert SP to long for address calculation
    std::string spLong = builder_.newTemp();
    builder_.emitExtend(spLong, "l", "extsw", spTemp);

    // 3. Calculate byte offset: SP * GOSUB_ENTRY_BYTES
    std::string byteOffset = builder_.newTemp();
    builder_.emitBinary(byteOffset, "l", "mul", spLong,
                        std::to_string(GOSUB_ENTRY_BYTES));

    // 4. Calculate stack address: $gosub_return_stack + offset
    std::string stackAddr = builder_.newTemp();
    builder_.emitBinary(stackAddr, "l", "add", "$gosub_return_stack", byteOffset);

    // 5. Store return block ID at that address
    builder_.emitStore("w", std::to_string(returnBlockId), stackAddr);

    // 6. Increment stack pointer
    std::string newSp = builder_.newTemp();
    builder_.emitBinary(newSp, "w", "add", spTemp, "1");
    builder_.emitStore("w", newSp, "$gosub_return_sp");
}

void CFGEmitter::emitOnGotoTerminator(const OnGotoStatement* stmt, 
                                      const BasicBlock* block,
                                      const ControlFlowGraph* cfg) {
    builder_.emitComment("ON GOTO statement - switch dispatch");
    
    // Get out edges
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);
    
    builder_.emitComment("DEBUG: Found " + std::to_string(outEdges.size()) + " out edges");
    for (const auto& edge : outEdges) {
        builder_.emitComment("  Edge to block " + std::to_string(edge.targetBlock) + 
                           " type=" + getEdgeTypeName(edge.type) + 
                           " label='" + edge.label + "'");
    }
    
    // Find case edges and default edge
    std::vector<int> caseTargets;
    int defaultTarget = -1;
    
    for (const auto& edge : outEdges) {
        if (edge.label.length() >= 5 && edge.label.substr(0, 5) == "case_") {
            int caseNum = 0;
            std::string numPart = edge.label.substr(5);
            if (!tryParseInt(numPart, caseNum) || caseNum < 1) {
                builder_.emitComment("WARNING: malformed case label '" + edge.label + "' – skipped");
                continue;
            }
            // Ensure vector is large enough
            if (caseNum > (int)caseTargets.size()) {
                caseTargets.resize(caseNum, -1);
            }
            // Store target (1-indexed to 0-indexed)
            caseTargets[caseNum - 1] = edge.targetBlock;
        } else if (edge.label == "default") {
            defaultTarget = edge.targetBlock;
        }
    }
    
    // If no default found, look for fallthrough edge
    if (defaultTarget == -1) {
        for (const auto& edge : outEdges) {
            if (edge.type == EdgeType::FALLTHROUGH || edge.type == EdgeType::JUMP) {
                defaultTarget = edge.targetBlock;
                break;
            }
        }
    }
    
    if (defaultTarget == -1 || caseTargets.empty()) {
        builder_.emitComment("ERROR: ON GOTO without valid targets or default");
        builder_.emitReturn("0");
        return;
    }
    
    // Evaluate and normalize selector
    std::string selector = emitSelectorWord(stmt->selector.get());
    
    // Subtract 1 to convert from 1-based (BASIC) to 0-based (QBE switch)
    std::string zeroBasedSelector = builder_.newTemp();
    builder_.emitBinary(zeroBasedSelector, "w", "sub", selector, "1");
    
    // Build case label list
    std::vector<std::string> caseLabels;
    for (int targetId : caseTargets) {
        if (targetId >= 0) {
            caseLabels.push_back(getBlockLabel(targetId));
        } else {
            // Gap in cases - use default
            caseLabels.push_back(getBlockLabel(defaultTarget));
        }
    }
    
    // Emit switch instruction
    builder_.emitSwitch("w", zeroBasedSelector, getBlockLabel(defaultTarget), caseLabels);
}

void CFGEmitter::emitOnGosubTerminator(const OnGosubStatement* stmt,
                                       const BasicBlock* block,
                                       const ControlFlowGraph* cfg) {
    builder_.emitComment("ON GOSUB statement - switch dispatch to trampolines");
    
    // Get out edges
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);
    
    // Find call edges and return point
    std::vector<int> callTargets;
    int returnPoint = -1;
    
    for (const auto& edge : outEdges) {
        if (edge.label.length() >= 5 && edge.label.substr(0, 5) == "call_") {
            int caseNum = 0;
            std::string numPart = edge.label.substr(5);
            if (!tryParseInt(numPart, caseNum) || caseNum < 1) {
                builder_.emitComment("WARNING: malformed call label '" + edge.label + "' – skipped");
                continue;
            }
            // Ensure vector is large enough
            if (caseNum > (int)callTargets.size()) {
                callTargets.resize(caseNum, -1);
            }
            // Store target (1-indexed to 0-indexed)
            callTargets[caseNum - 1] = edge.targetBlock;
        } else if (edge.type == EdgeType::JUMP || edge.type == EdgeType::FALLTHROUGH) {
            returnPoint = edge.targetBlock;
        }
    }
    
    if (returnPoint == -1 || callTargets.empty()) {
        builder_.emitComment("ERROR: ON GOSUB without valid targets or return point");
        builder_.emitReturn("0");
        return;
    }
    
    // Evaluate and normalize selector
    std::string selector = emitSelectorWord(stmt->selector.get());
    
    // Subtract 1 to convert from 1-based (BASIC) to 0-based (QBE switch)
    std::string zeroBasedSelector = builder_.newTemp();
    builder_.emitBinary(zeroBasedSelector, "w", "sub", selector, "1");
    
    // Build trampoline labels - each trampoline will push return point and jump to target
    std::vector<std::string> trampolineLabels;
    for (size_t i = 0; i < callTargets.size(); i++) {
        if (callTargets[i] >= 0) {
            std::string trampolineLabel = "on_gosub_trampoline_" + std::to_string(block->id) + 
                                         "_case_" + std::to_string(i);
            trampolineLabels.push_back(trampolineLabel);
        } else {
            // Gap in cases - jump directly to return point (skip the call)
            trampolineLabels.push_back(getBlockLabel(returnPoint));
        }
    }
    
    // Emit switch instruction to trampolines
    builder_.emitSwitch("w", zeroBasedSelector, getBlockLabel(returnPoint), trampolineLabels);
    
    // Emit trampolines
    for (size_t i = 0; i < callTargets.size(); i++) {
        if (callTargets[i] >= 0) {
            std::string trampolineLabel = trampolineLabels[i];
            builder_.emitLabel(trampolineLabel);
            builder_.emitComment("Trampoline for ON GOSUB case " + std::to_string(i + 1));
            
            // Push return point
            emitPushReturnBlock(returnPoint);
            
            // Jump to target
            builder_.emitJump(getBlockLabel(callTargets[i]));
        }
    }
}

// =============================================================================
// ON CALL Terminator
// =============================================================================

void CFGEmitter::emitOnCallTerminator(const OnCallStatement* stmt,
                                      const BasicBlock* block,
                                      const ControlFlowGraph* cfg) {
    builder_.emitComment("ON CALL statement - switch dispatch to SUB calls");
    
    // Get out edges
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);
    
    // Find SUB call edges and continuation point
    std::vector<std::string> subNames;
    int continuePoint = -1;
    
    for (const auto& edge : outEdges) {
        if (edge.label.length() >= 9 && edge.label.substr(0, 9) == "call_sub:") {
            // Extract SUB name and case number from label "call_sub:<name>:case_N"
            std::string remaining = edge.label.substr(9);
            size_t casePos = remaining.find(":case_");
            if (casePos != std::string::npos) {
                std::string subName = remaining.substr(0, casePos);
                std::string numPart = remaining.substr(casePos + 6);
                int caseNum = 0;
                if (!tryParseInt(numPart, caseNum) || caseNum < 1) {
                    builder_.emitComment("WARNING: malformed call_sub label '" + edge.label + "' – skipped");
                    continue;
                }
                
                // Ensure vector is large enough
                if (caseNum > (int)subNames.size()) {
                    subNames.resize(caseNum);
                }
                // Store SUB name (1-indexed to 0-indexed)
                subNames[caseNum - 1] = subName;
            }
            // Note: continuePoint is NOT set here — only the "call_default"
            // edge carries the correct continuation block.
        } else if (edge.label == "call_default") {
            continuePoint = edge.targetBlock;
        }
    }
    
    if (continuePoint == -1 || subNames.empty()) {
        builder_.emitComment("ERROR: ON CALL without valid targets or continuation");
        builder_.emitJump(getBlockLabel(continuePoint >= 0 ? continuePoint : block->id + 1));
        return;
    }
    
    // Evaluate and normalize selector
    std::string selector = emitSelectorWord(stmt->selector.get());
    
    // Subtract 1 to convert from 1-based (BASIC) to 0-based (QBE switch)
    std::string zeroBasedSelector = builder_.newTemp();
    builder_.emitBinary(zeroBasedSelector, "w", "sub", selector, "1");
    
    // Build trampoline labels - each trampoline will call the SUB
    std::vector<std::string> trampolineLabels;
    for (size_t i = 0; i < subNames.size(); i++) {
        if (!subNames[i].empty()) {
            std::string trampolineLabel = "on_call_trampoline_" + std::to_string(block->id) + 
                                         "_case_" + std::to_string(i);
            trampolineLabels.push_back(trampolineLabel);
        } else {
            // Gap in cases - jump directly to continuation (skip the call)
            trampolineLabels.push_back(getBlockLabel(continuePoint));
        }
    }
    
    // Emit switch instruction to trampolines
    builder_.emitSwitch("w", zeroBasedSelector, getBlockLabel(continuePoint), trampolineLabels);
    
    // Emit trampolines
    for (size_t i = 0; i < subNames.size(); i++) {
        if (!subNames[i].empty()) {
            std::string trampolineLabel = trampolineLabels[i];
            builder_.emitLabel(trampolineLabel);
            builder_.emitComment("Trampoline for ON CALL case " + std::to_string(i + 1) + " -> SUB " + subNames[i]);
            
            // Call the SUB (no arguments in current simple implementation)
            // Format: call $sub_SubName()
            builder_.emitCall("", "", "sub_" + subNames[i], "");
            
            // Continue to next statement
            builder_.emitJump(getBlockLabel(continuePoint));
        }
    }
}

} // namespace fbc