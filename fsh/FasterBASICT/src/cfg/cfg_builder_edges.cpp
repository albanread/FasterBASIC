//
// cfg_builder_edges.cpp
// FasterBASIC - Control Flow Graph Builder Edge Management (V2)
//
// This file is STUBBED OUT in v2 implementation.
// The v2 architecture builds edges immediately during construction,
// so there is no separate "Phase 2" edge building phase.
//
// All edge creation happens in the recursive builders:
// - cfg_builder_loops.cpp (loop back-edges)
// - cfg_builder_conditional.cpp (branch edges)
// - cfg_builder_jumps.cpp (goto/gosub edges)
// - cfg_builder_exception.cpp (exception edges)
//
// Part of modular CFG builder split (February 2026).
// V2 IMPLEMENTATION: Single-pass recursive construction with immediate edge wiring
//

#include "cfg_builder.h"

namespace FasterBASIC {

// This file intentionally left empty - v2 does not use deferred edge building.
// All edges are created immediately by the recursive statement builders.

} // namespace FasterBASIC