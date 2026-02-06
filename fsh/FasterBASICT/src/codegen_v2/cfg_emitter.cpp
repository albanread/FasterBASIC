#include "cfg_emitter.h"
#include "type_manager.h"
#include <algorithm>
#include <queue>

namespace fbc {

using namespace FasterBASIC;

CFGEmitter::CFGEmitter(QBEBuilder& builder, TypeManager& typeManager,
                       SymbolMapper& symbolMapper, ASTEmitter& astEmitter)
    : builder_(builder)
    , typeManager_(typeManager)
    , symbolMapper_(symbolMapper)
    , astEmitter_(astEmitter)
    , currentFunction_("")
{
}

// === CFG Emission ===

void CFGEmitter::emitCFG(const ControlFlowGraph* cfg, const std::string& functionName) {
    if (!cfg) {
        builder_.emitComment("ERROR: null CFG");
        return;
    }
    
    enterFunction(functionName);
    
    builder_.emitComment("CFG: " + (functionName.empty() ? "main" : functionName));
    builder_.emitComment("Blocks: " + std::to_string(cfg->blocks.size()));
    builder_.emitBlankLine();
    
    // Compute reachability
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
    
    // Add comment about block type
    std::string blockInfo = "Block " + std::to_string(blockId);
    if (!block->label.empty()) {
        blockInfo += " (label: " + block->label + ")";
    }
    
    builder_.emitComment(blockInfo);
    builder_.emitLabel(label);
    
    // If this is the entry block (block 0), allocate stack space for all local variables
    if (blockId == 0) {
        const auto& symbolTable = astEmitter_.getSymbolTable();
        
        // Get function parameters from CFG (these are the actual QBE parameter names)
        std::vector<std::string> cfgParams = cfg->parameters;
        
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
                    const auto& symbolTable = astEmitter_.getSymbolTable();
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
                bool isParameter = false;
                std::string qbeParamName;
                for (const auto& cfgParam : cfgParams) {
                    // Check if varSymbol.name starts with the CFG parameter name
                    // e.g., varSymbol.name="X_DOUBLE" should match cfgParam="X"
                    if (varSymbol.name.find(cfgParam) == 0 && 
                        (varSymbol.name.length() == cfgParam.length() || 
                         varSymbol.name[cfgParam.length()] == '_')) {
                        isParameter = true;
                        qbeParamName = cfgParam;  // Use the CFG parameter name (what QBE uses)
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
                        builder_.emitRaw("    storew " + qbeParam + ", " + mangledName);
                    } else if (size == 8) {
                        if (typeManager_.isString(varType)) {
                            builder_.emitRaw("    storel " + qbeParam + ", " + mangledName);
                        } else {
                            builder_.emitRaw("    stored " + qbeParam + ", " + mangledName);
                        }
                    }
                } else {
                    // Initialize to 0 (BASIC variables are implicitly initialized)
                    if (typeManager_.isString(varType)) {
                        // Strings initialized to null pointer
                        builder_.emitRaw("    storel 0, " + mangledName);
                    } else if (varType == BaseType::USER_DEFINED && size > 8) {
                        // UDT types: zero-initialize all bytes using memset
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

// === Edge Handling ===

// === Decomposed Terminator Helpers ===

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
        builder_.emitComment("Implicit return 0");
        builder_.emitReturn("0");
        return;
    }

    // Load and return the function's implicit return variable
    const auto& symbolTable = astEmitter_.getSymbolTable();
    auto funcIt = symbolTable.functions.find(currentFunction_);
    if (funcIt == symbolTable.functions.end()) {
        builder_.emitComment("WARNING: block with no out-edges (missing return?)");
        builder_.emitReturn();
        return;
    }

    const auto& funcSymbol = funcIt->second;
    BaseType returnType = funcSymbol.returnTypeDesc.baseType;

    // SUBs have VOID return type – just return without a value
    if (returnType == BaseType::VOID) {
        builder_.emitComment("SUB exit - no return value");
        builder_.emitReturn();
        return;
    }

    std::string qbeType = typeManager_.getQBEType(returnType);
    std::string returnVarName = typeManager_.getReturnVariableName(currentFunction_, returnType);
    std::string mangledName = symbolMapper_.mangleVariableName(returnVarName, false);
    std::string retTemp = builder_.newTemp();

    builder_.emitLoad(retTemp, qbeType, mangledName);
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
            int blockId = returnBlocks[i];
            std::string isMatch = builder_.newTemp();
            builder_.emitCompare(isMatch, "w", "eq", returnBlockIdTemp,
                                std::to_string(blockId));

            std::string targetLabel = getBlockLabel(blockId);
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
        // TODO: Get selector value from statement
        std::string selector = "1";  // Placeholder
        emitMultiway(selector, targets, defaultTarget);
        return;
    }

    // Unknown edge type – fallthrough to first edge
    builder_.emitComment("WARNING: unknown edge type, using fallthrough");
    if (!outEdges.empty()) emitFallthrough(outEdges[0].targetBlock);
}

// === Main Terminator (decomposed) ===

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

// === Block Ordering ===

std::vector<int> CFGEmitter::getEmissionOrder(const ControlFlowGraph* cfg) {
    std::vector<int> order;
    
    if (!cfg || cfg->blocks.empty()) {
        return order;
    }
    
    // Simple strategy: emit in block ID order
    // This ensures we emit all blocks, including UNREACHABLE ones
    // (needed for GOSUB/ON GOTO targets)
    for (size_t i = 0; i < cfg->blocks.size(); ++i) {
        if (cfg->blocks[i]) {
            order.push_back(cfg->blocks[i]->id);
        }
    }
    
    return order;
}

bool CFGEmitter::isBlockReachable(int blockId, const ControlFlowGraph* cfg) {
    if (reachabilityCache_.find(blockId) != reachabilityCache_.end()) {
        return reachabilityCache_[blockId];
    }
    
    // If not in cache, assume reachable (conservative)
    return true;
}

// === Label Management ===

std::string CFGEmitter::getBlockLabel(int blockId) {
    return symbolMapper_.getBlockLabel(blockId);
}

void CFGEmitter::registerLabel(int blockId) {
    requiredLabels_.insert(blockId);
}

bool CFGEmitter::isLabelEmitted(int blockId) {
    return emittedLabels_.find(blockId) != emittedLabels_.end();
}

// === Special Block Types ===

bool CFGEmitter::isLoopHeader(const BasicBlock* block, const ControlFlowGraph* cfg) {
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
    
    // Check if block has no successors
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);
    
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

// === Context Management ===

void CFGEmitter::enterFunction(const std::string& functionName) {
    currentFunction_ = functionName;
    emittedLabels_.clear();
    requiredLabels_.clear();
    reachabilityCache_.clear();
}

void CFGEmitter::exitFunction() {
    currentFunction_.clear();
}

void CFGEmitter::reset() {
    currentFunction_.clear();
    emittedLabels_.clear();
    requiredLabels_.clear();
    reachabilityCache_.clear();
}

// === Helper Methods ===

void CFGEmitter::emitBlockStatements(const BasicBlock* block) {
    if (!block) return;
    
    for (const Statement* stmt : block->statements) {
        if (stmt) {
            // Skip control flow terminators - they will be handled by emitBlockTerminator
            ASTNodeType stmtType = stmt->getType();
            if (stmtType == ASTNodeType::STMT_RETURN ||
                stmtType == ASTNodeType::STMT_ON_GOTO ||
                stmtType == ASTNodeType::STMT_ON_GOSUB) {
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

std::vector<CFGEdge> CFGEmitter::getOutEdges(const BasicBlock* block, 
                                              const ControlFlowGraph* cfg) {
    std::vector<CFGEdge> result;
    
    if (!block || !cfg) {
        return result;
    }
    
    // Find all edges where sourceBlock == block->id
    for (const auto& edge : cfg->edges) {
        if (edge.sourceBlock == block->id) {
            result.push_back(edge);
        }
    }
    
    return result;
}

void CFGEmitter::computeReachability(const ControlFlowGraph* cfg) {
    if (!cfg) return;
    
    reachabilityCache_.clear();
    
    // Mark all blocks as unreachable initially
    for (const auto& block : cfg->blocks) {
        if (block) {
            reachabilityCache_[block->id] = false;
        }
    }
    
    // DFS from entry block
    std::unordered_set<int> visited;
    dfsReachability(cfg->entryBlock, cfg, visited);
}

void CFGEmitter::dfsReachability(int blockId, 
                                 const ControlFlowGraph* cfg,
                                 std::unordered_set<int>& visited) {
    if (visited.find(blockId) != visited.end()) {
        return;  // Already visited
    }
    
    visited.insert(blockId);
    reachabilityCache_[blockId] = true;
    
    // Find the block
    const BasicBlock* block = nullptr;
    if (blockId >= 0 && blockId < static_cast<int>(cfg->blocks.size())) {
        block = cfg->blocks[blockId].get();
    }
    
    if (!block) return;
    
    // Visit all successors
    std::vector<CFGEdge> outEdges = getOutEdges(block, cfg);
    for (const auto& edge : outEdges) {
        dfsReachability(edge.targetBlock, cfg, visited);
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
            // Extract case number
            int caseNum = std::stoi(edge.label.substr(5));
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
        if (edge.label.substr(0, 5) == "call_") {
            // Extract case number
            int caseNum = std::stoi(edge.label.substr(5));
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
        if (edge.label.substr(0, 9) == "call_sub:") {
            // Extract SUB name and case number from label "call_sub:<name>:case_N"
            std::string remaining = edge.label.substr(9);
            size_t casePos = remaining.find(":case_");
            if (casePos != std::string::npos) {
                std::string subName = remaining.substr(0, casePos);
                int caseNum = std::stoi(remaining.substr(casePos + 6));
                
                // Ensure vector is large enough
                if (caseNum > (int)subNames.size()) {
                    subNames.resize(caseNum);
                }
                // Store SUB name (1-indexed to 0-indexed)
                subNames[caseNum - 1] = subName;
            }
            continuePoint = edge.targetBlock;
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