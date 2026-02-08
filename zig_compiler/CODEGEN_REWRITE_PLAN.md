# Codegen Rewrite Plan: CFG-Driven Code Generation

## Problem Statement

The current `codegen.zig` was developed before the CFG (`cfg.zig`) was complete. It walks
the AST directly and **re-derives control flow** by manually creating labels and branches
inside each statement emitter (`emitIfStatement`, `emitForStatement`, `emitWhileStatement`,
etc.). The CFG is built in the pipeline (Phase 4b in `main.zig`) but is only used for
diagnostics (unreachable-code warnings). The codegen ignores it entirely.

This is architecturally wrong. The CFG already encodes:
- Basic blocks with their contained statements
- All control flow edges (fallthrough, branch_true/false, back_edge, loop_exit, etc.)
- Loop structure (headers, back-edges, exits, nesting)
- Reverse-postorder traversal order (ideal for forward code generation)
- Reachability (skip dead blocks)
- Branch conditions attached to conditional blocks

The codegen should consume the CFG, not re-derive the information the CFG already provides.

---

## Current Architecture

### `codegen.zig` (~2200 lines, 6 structs + tests)

| Struct            | Lines     | Role                                              | Verdict       |
|-------------------|-----------|---------------------------------------------------|---------------|
| `QBEBuilder`      | 35–369    | Low-level QBE IL text emission                    | **KEEP**      |
| `TypeManager`     | 377–466   | Maps FasterBASIC types → QBE types/sizes          | **KEEP**      |
| `SymbolMapper`    | 474–597   | Name mangling for variables, functions, classes    | **KEEP**      |
| `RuntimeLibrary`  | 605–694   | Runtime function declarations + call helpers      | **KEEP**      |
| `Emitter`         | 702–1667  | AST → IL (expressions **and** statements)         | **SPLIT**     |
| `CodeGenerator`   | 1681–1953 | Top-level orchestrator, walks AST linearly         | **REPLACE**   |
| Tests             | 1959–2208 | Unit tests for Builder, TypeManager, SymbolMapper  | **KEEP/UPDATE**|

### `cfg.zig` (~2240 lines)

Already provides everything needed:
- `BasicBlock.statements` — references to AST statements (zero-copy)
- `BasicBlock.branch_condition` — condition expression for conditional blocks
- `BasicBlock.kind` — semantic role (entry, exit, loop_header, if_then, merge, etc.)
- `Edge.kind` — edge semantics (fallthrough, branch_true, branch_false, back_edge, etc.)
- `CFG.iterRPO()` — blocks in reverse-postorder
- `CFG.loops` — detected loop info with headers, exits, nesting depth
- `CFGBuilder.function_cfgs` — separate CFG per FUNCTION/SUB

### `main.zig` pipeline (Phase 5, lines 820–835)

Current:
```
var gen = CodeGenerator.init(&analyzer, allocator);
const il = gen.generate(&program);   // walks AST, ignores CFG
```

Needs to become:
```
var gen = CFGCodeGenerator.init(&analyzer, &program_cfg, &cfg_builder, allocator);
const il = gen.generate(&program);   // walks CFG blocks in RPO
```

---

## What to Keep from the Old Emitter

### Expression emission — KEEP AS-IS

All `emitExpression` sub-methods are pure data-flow (no control-flow manipulation) and
can be reused verbatim:

- `emitExpression` (dispatch)
- `emitNumberLiteral`
- `emitStringLiteral`
- `emitVariableLoad`
- `emitBinaryExpr`
- `emitUnaryExpr`
- `emitFunctionCall`
- `emitMemberAccess`
- `emitMethodCall`
- `emitArrayAccess`
- `emitCreate`, `emitNew`
- `emitMe`, `emitNothing`
- `emitIsType`, `emitSuperCall`
- `emitListConstructor`
- `emitArrayBinop`
- `emitRegistryFunction`

**Exception:** `emitIIF` creates its own labels/branches (it's an inline conditional
expression). This needs special treatment — either keep it as a self-contained micro-CFG
within a block, or lower IIF to a phi-like pattern using QBE's `phi` (if available) or
a stack slot + two stores. For now, keep the existing approach since IIF is expression-level,
not statement-level control flow.

### Statement emission — PARTIAL KEEP

"Leaf" statement emitters that don't create control flow can be reused:

- `emitPrintStatement`
- `emitConsoleStatement`
- `emitLetStatement`
- `emitDimStatement`
- `emitIncDec`
- `emitSwapStatement`
- `emitCallStatement`
- `emitReturnStatement`

### Statement emission — DISCARD (replaced by CFG traversal)

These methods manually create labels and branches. In the new design, the CFG structure
replaces them entirely:

- `emitIfStatement` — replaced by CFG diamond (if_then / if_else / merge blocks + edges)
- `emitForStatement` — replaced by CFG loop (loop_header / loop_body / loop_increment / loop_exit)
- `emitWhileStatement` — replaced by CFG loop pattern
- `emitDoStatement` — replaced by CFG loop pattern
- `emitRepeatStatement` — replaced by CFG loop pattern
- `emitCaseStatement` — replaced by CFG case_test / case_body / merge blocks
- `emitTryCatchStatement` — replaced by CFG try_body / catch_handler / finally blocks
- `emitForInStatement` — replaced by CFG loop pattern
- `emitFunctionDef` — replaced by per-function CFG traversal
- `emitSubDef` — replaced by per-function CFG traversal

### `emitStatement` dispatch — REPLACE

The old `emitStatement` dispatches on `stmt.data` and calls the control-flow emitters.
The new version only needs to handle leaf statements because the CFG already broke
control flow into blocks. Control-flow statements (IF, FOR, WHILE, etc.) will never
appear as "statements to emit" — they exist only as CFG structure.

---

## New Architecture

### File Layout

```
codegen.zig (new)
├── QBEBuilder          (copied from v1, unchanged)
├── TypeManager         (copied from v1, unchanged)
├── SymbolMapper        (copied from v1, unchanged)
├── RuntimeLibrary      (copied from v1, unchanged)
├── ExprEmitter         (extracted from v1 Emitter — expression methods only)
├── BlockEmitter        (NEW — emits statements within a single basic block)
├── CFGCodeGenerator    (NEW — top-level, walks CFG in RPO order)
└── Tests               (updated)
```

### `ExprEmitter`

Extracted from the old `Emitter`. Contains only expression emission and type inference.

```
pub const ExprEmitter = struct {
    builder: *QBEBuilder,
    type_manager: *const TypeManager,
    symbol_mapper: *SymbolMapper,
    runtime: *RuntimeLibrary,
    symbol_table: *const semantic.SymbolTable,
    allocator: std.mem.Allocator,

    // Expression emission (all methods from old Emitter)
    pub fn emitExpression(...)
    fn emitNumberLiteral(...)
    fn emitStringLiteral(...)
    fn emitVariableLoad(...)
    fn emitBinaryExpr(...)
    fn emitUnaryExpr(...)
    fn emitFunctionCall(...)
    fn emitIIF(...)
    // ... etc

    // Type inference
    fn inferExprType(...)
    fn typeFromSuffix(...)
};
```

### `BlockEmitter`

Emits the non-control-flow statements within a single basic block and the block's
terminator based on CFG edges.

```
pub const BlockEmitter = struct {
    expr_emitter: *ExprEmitter,
    builder: *QBEBuilder,
    runtime: *RuntimeLibrary,
    symbol_mapper: *SymbolMapper,
    cfg: *const cfg_mod.CFG,
    allocator: std.mem.Allocator,

    /// Emit all statements in a basic block (non-control-flow only).
    pub fn emitBlockStatements(self: *BlockEmitter, block: *const BasicBlock) !void

    /// Emit the block terminator (branch/jump) based on outgoing CFG edges.
    pub fn emitTerminator(self: *BlockEmitter, block: *const BasicBlock) !void

    // Leaf statement emitters (from old Emitter)
    fn emitPrintStatement(...)
    fn emitLetStatement(...)
    fn emitDimStatement(...)
    fn emitCallStatement(...)
    fn emitReturnStatement(...)
    fn emitIncDec(...)
    fn emitSwapStatement(...)
    fn emitConsoleStatement(...)
};
```

### `CFGCodeGenerator`

The new top-level orchestrator. Replaces the old `CodeGenerator`.

```
pub const CFGCodeGenerator = struct {
    builder: QBEBuilder,
    type_manager: TypeManager,
    symbol_mapper: SymbolMapper,
    runtime: RuntimeLibrary,
    expr_emitter: ?ExprEmitter,
    block_emitter: ?BlockEmitter,

    semantic: *const semantic.SemanticAnalyzer,
    program_cfg: *const cfg_mod.CFG,
    cfg_builder: *const cfg_mod.CFGBuilder,
    allocator: std.mem.Allocator,

    verbose: bool,
    samm_enabled: bool,

    pub fn init(sem, program_cfg, cfg_builder, allocator) CFGCodeGenerator
    pub fn deinit(self) void
    pub fn generate(self, program) ![]const u8

    // Internal phases
    fn emitFileHeader(self) !void
    fn emitGlobalVariables(self) !void
    fn emitGlobalArrays(self) !void
    fn emitCFGFunction(self, cfg, func_name, return_type, params) !void
    fn emitBlock(self, block) !void
    fn collectStringLiterals(self, program) !void
    fn blockLabel(block) []const u8    // derive QBE label from block name/index
};
```

---

## Core Algorithm: `emitCFGFunction`

This is the heart of the new codegen. For a given CFG (main body or a function/sub):

```
fn emitCFGFunction(self, the_cfg, name, ret_type, params) !void {
    // 1. Emit function start
    self.builder.emitFunctionStart(name, ret_type, params);

    // 2. Walk blocks in reverse-postorder
    for (the_cfg.iterRPO()) |block_idx| {
        const block = the_cfg.getBlockConst(block_idx);

        // Skip unreachable blocks
        if (!block.reachable) continue;

        // 3. Emit block label
        self.builder.emitLabel(blockLabel(block));

        // 4. Emit statements in this block
        self.block_emitter.emitBlockStatements(block);

        // 5. Emit terminator based on outgoing edges
        self.block_emitter.emitTerminator(block);
    }

    // 6. Emit function end
    self.builder.emitFunctionEnd();
}
```

### Terminator Emission Logic

```
fn emitTerminator(self, block) !void {
    const successors = block.successors.items;

    // Exit block: emit return
    if (block.kind == .exit_block) {
        self.builder.emitReturn(...);
        return;
    }

    // No successors: unreachable / implicit return
    if (successors.len == 0) return;

    // Find outgoing edges from this block
    const edges = self.cfg.edgesFrom(block.index);

    // Conditional branch: look for branch_true / branch_false edge pair
    if (block.branch_condition) |cond| {
        var true_target: ?u32 = null;
        var false_target: ?u32 = null;
        for (edges) |edge| {
            if (edge.kind == .branch_true) true_target = edge.to;
            if (edge.kind == .branch_false) false_target = edge.to;
        }
        if (true_target != null and false_target != null) {
            const cond_val = self.expr_emitter.emitExpression(cond);
            const cond_int = convert_to_int(cond_val);
            self.builder.emitBranch(cond_int,
                blockLabel(true_target),
                blockLabel(false_target));
            return;
        }
    }

    // Case dispatch: multiple case_match / case_next edges
    // (emit chained comparisons)

    // Single successor: unconditional jump or fallthrough
    if (successors.len == 1) {
        self.builder.emitJump(blockLabel(successors[0]));
        return;
    }

    // Back-edge: jump to loop header
    for (edges) |edge| {
        if (edge.kind == .back_edge) {
            self.builder.emitJump(blockLabel(edge.to));
            return;
        }
    }

    // Fallthrough to next RPO block (emit explicit jump for QBE)
    self.builder.emitJump(blockLabel(successors[0]));
}
```

---

## Statement Handling in Blocks

When the CFG builder places statements into blocks, control-flow statements (IF, FOR,
WHILE, DO, CASE, TRY) are decomposed into their constituent parts:

- The **condition expression** goes into the block's `branch_condition` field
- The **body statements** go into separate blocks (loop_body, if_then, etc.)
- The **increment** goes into a loop_increment block
- The **edges** encode the branch structure

So the `BlockEmitter.emitBlockStatements` only sees leaf/action statements:

```
fn emitBlockStatements(self, block) !void {
    for (block.statements.items) |stmt| {
        switch (stmt.data) {
            // Leaf statements — emit directly
            .print      => |pr| self.emitPrintStatement(&pr),
            .let        => |lt| self.emitLetStatement(&lt),
            .dim        => |dm| self.emitDimStatement(&dm),
            .call       => |cs| self.emitCallStatement(&cs),
            .return_stmt=> |rs| self.emitReturnStatement(&rs),
            .inc        => |id| self.emitIncDec(&id, true),
            .dec        => |id| self.emitIncDec(&id, false),
            .swap       => |sw| self.emitSwapStatement(&sw),
            .console    => |cn| self.emitConsoleStatement(&cn),
            .end_stmt   => {},  // handled by edge to exit block
            .rem        => {},  // comment, skip
            .option     => {},  // compile-time only
            .label      => {},  // labels are block boundaries, already emitted
            .type_decl  => {},  // declarations, no code
            .class      => {},  // declarations, no code
            .data_stmt  => {},  // data segment, no code

            // Control-flow statements that appear in blocks because the CFG
            // builder put them there as "the statement that begins this block"
            // — their bodies are in successor blocks, so we only need to handle
            // any initialisation they require.
            .for_stmt   => |fs| self.emitForInit(&fs),   // emit loop var init
            .goto_stmt  => {},  // edge already in CFG
            .exit_stmt  => {},  // edge already in CFG

            // Function/sub definitions handled separately via function_cfgs
            .function, .sub => {},

            else => self.builder.emitComment("TODO: unhandled statement"),
        }
    }
}
```

### Special: FOR loop initialisation

The FOR statement's initialisation (set loop variable to start value) must still be
emitted. This happens in the block that contains the FOR statement (typically just
before the loop header). The condition check and increment are in their own blocks.

```
fn emitForInit(self, fs) !void {
    const start_val = self.expr_emitter.emitExpression(fs.start);
    const var_name = self.symbol_mapper.globalVarName(fs.variable, null);
    self.builder.emitStore("d", start_val, "$" ++ var_name);

    // Also store end value for the condition block to use
    const end_val = self.expr_emitter.emitExpression(fs.end_expr);
    // Store in a temp alloc for the loop
    ...
}
```

---

## Function/Sub Handling

The `CFGBuilder` creates separate CFGs for each FUNCTION/SUB in `function_cfgs`.
The new codegen iterates these:

```
fn generate(self, program) ![]const u8 {
    // Phase 1: File header
    self.emitFileHeader();

    // Phase 2: String constant pool
    self.collectStringLiterals(program);
    self.builder.emitStringPool();

    // Phase 3: Global data
    self.emitGlobalVariables();
    self.emitGlobalArrays();

    // Phase 4: Runtime declarations
    self.runtime.emitDeclarations();

    // Phase 5: Main function (from program_cfg)
    self.emitCFGFunction(self.program_cfg, "main", "w", "");

    // Phase 6: Function/Sub definitions (from cfg_builder.function_cfgs)
    var it = self.cfg_builder.function_cfgs.iterator();
    while (it.next()) |entry| {
        const func_name = entry.key_ptr.*;
        const func_cfg = entry.value_ptr;
        // Look up return type and parameters from semantic info
        const func_sym = self.semantic.getSymbolTable().lookupFunction(func_name);
        self.emitCFGFunction(func_cfg, mangled_name, ret_type, params);
    }

    // Phase 7: Late string pool
    self.builder.emitLateStringPool();

    return self.builder.getIL();
}
```

---

## Implementation Steps

### Step 1: Archive

- Copy `codegen.zig` → `codegen_v1.zig` (archived, not imported by anything)

### Step 2: Create new `codegen.zig`

Build the file in sections:

1. **Copy infrastructure verbatim** from v1:
   - `QBEBuilder` (lines 35–369)
   - `TypeManager` (lines 377–466)
   - `SymbolMapper` (lines 474–597)
   - `RuntimeLibrary` (lines 605–694)

2. **Extract `ExprEmitter`** from v1's `Emitter`:
   - Copy `emitExpression` and all `emitXxxExpr/Literal/Load` methods
   - Copy `inferExprType`, `typeFromSuffix`, `ExprType` enum
   - Remove statement methods

3. **Write `BlockEmitter`** (new):
   - Copy leaf statement emitters from v1's `Emitter`
   - Write `emitBlockStatements` — iterates block's statements
   - Write `emitTerminator` — reads CFG edges to emit branch/jump
   - Write `emitForInit` — special init for FOR loops

4. **Write `CFGCodeGenerator`** (new):
   - `init` / `deinit` — takes semantic + CFG + CFGBuilder
   - `generate` — phases 1–7 as above
   - `emitCFGFunction` — RPO block walk
   - `emitFileHeader`, `emitGlobalVariables`, `emitGlobalArrays` — from v1
   - `collectStringLiterals` — from v1
   - `blockLabel` — maps block index/name to QBE label string

5. **Copy and adapt tests** from v1:
   - Infrastructure tests (QBEBuilder, TypeManager, SymbolMapper) stay the same
   - Add new tests for CFG-driven emission

### Step 3: Update `main.zig`

Change Phase 5:

```zig
// Before:
var gen = CodeGenerator.init(&analyzer, allocator);
const il = gen.generate(&program);

// After:
var gen = codegen.CFGCodeGenerator.init(&analyzer, &program_cfg, &cfg_builder, allocator);
const il = gen.generate(&program);
```

The CFG builder and program CFG must be passed to the codegen instead of being
discarded after diagnostics.

### Step 4: Update `build.zig` if needed

If `codegen_v1.zig` causes build issues (it shouldn't since it's not imported),
either exclude it or keep it as a reference file.

### Step 5: Validate

- Run existing tests: `zig build test`
- Run full pipeline tests in `main.zig` (hello world, arithmetic, for loop, etc.)
- Compare generated QBE IL output against v1 for simple programs
- Verify `--trace-cfg` still works (it's independent of codegen)

---

## Edge Cases and Considerations

### 1. GOTO / GOSUB with forward references

The CFG already handles this via `pending_jumps` and `resolvePendingJumps`. The
codegen just needs to emit jumps to the target block's label.

### 2. ON GOTO / ON GOSUB (computed branches)

These produce `computed_branch` edges in the CFG. The codegen needs to emit a
dispatch sequence (compare selector against 1, 2, 3, ... and branch accordingly).
The values and targets are encoded in the edges.

### 3. EXIT FOR / EXIT WHILE / EXIT DO

These produce `loop_exit` edges to the loop's exit block. The codegen emits an
unconditional jump to that block's label.

### 4. SAMM scope management

`samm_enter_scope` / `samm_exit_scope` calls should be emitted at function/sub
entry/exit and possibly at loop boundaries. The CFG's block kinds make these
insertion points explicit.

### 5. Exception handling (TRY/CATCH/FINALLY)

The CFG has `try_body`, `catch_handler`, `finally_handler` block kinds and
`exception`/`finally` edge kinds. The codegen needs to emit setjmp/longjmp or
equivalent runtime calls. This is a TODO in v1 as well.

### 6. String in loop header conditions

When a FOR loop has `fs.end_expr`, it needs to be evaluated once and stored. The
CFG's loop_header block is where the condition check happens, but the end value
must be computed before entering the loop. This initialisation must happen in the
block that precedes the loop header (the block containing the FOR statement).

### 7. Block naming for QBE labels

QBE requires unique label names within a function. Use `@block_{index}` or the
block's existing `.name` field (which is already unique, e.g. "entry", "for_cond_0",
"if_then_1", etc.).

---

## Risk Assessment

| Risk | Mitigation |
|------|-----------|
| CFG blocks don't contain all needed statements | CFGBuilder already puts statements in blocks; verify coverage |
| FOR init not in the right block | Inspect CFGBuilder.processForStatement to confirm placement |
| Expression side effects across block boundaries | Expressions are self-contained within blocks (no cross-block temps) |
| IIF expression creates inline control flow | Keep existing approach (self-contained micro-CFG within a block) |
| function_cfgs naming doesn't match semantic table | Use consistent name mangling via SymbolMapper |
| Generated IL differs from v1 | Expected — CFG order may differ from linear AST order, but semantics preserved |

---

## Summary

The rewrite replaces the **Emitter** (statement emission + control flow) and
**CodeGenerator** (AST-linear orchestrator) with a **CFG-driven** approach while
preserving all infrastructure (`QBEBuilder`, `TypeManager`, `SymbolMapper`,
`RuntimeLibrary`) and expression emission unchanged.

The key insight: **the CFG already did the hard work** of decomposing control flow
into basic blocks with typed edges. The codegen should just walk blocks in RPO and
emit terminators based on edge kinds, rather than re-deriving this structure from
the AST.