//
// fasterbasic_options.h
// FasterBASIC - Compiler Options
//
// Holds compiler directives from OPTION statements.
// These are set during initial parsing and affect all compilation phases.
//

#ifndef FASTERBASIC_OPTIONS_H
#define FASTERBASIC_OPTIONS_H

namespace FasterBASIC {

// =============================================================================
// Compiler Options Structure
// =============================================================================

struct CompilerOptions {
    // String encoding mode
    enum class StringMode {
        ASCII,         // OPTION ASCII - all strings are byte sequences, non-ASCII is error
        UNICODE,       // OPTION UNICODE - all strings are Unicode codepoint arrays
        DETECTSTRING   // OPTION DETECTSTRING - detect per-literal (ASCII if all bytes < 128, else Unicode)
    };
    
    // FOR loop variable type
    enum class ForLoopType {
        INTEGER,       // OPTION FOR INTEGER - FOR loop variables are 32-bit integers (w)
        LONG           // OPTION FOR LONG - FOR loop variables are 64-bit integers (l)
    };
    
    // Array indexing: OPTION BASE 0 or OPTION BASE 1
    // Default is 1 (matches Lua's 1-based indexing)
    int arrayBase = 1;
    
    // String encoding: OPTION UNICODE / OPTION ASCII / OPTION DETECTSTRING
    // ASCII: strings are byte sequences, non-ASCII characters are errors
    // UNICODE: all strings are Unicode codepoint arrays
    // DETECTSTRING: automatically detect based on literal content (default)
    StringMode stringMode = StringMode::DETECTSTRING;
    
    // FOR loop variable type: OPTION FOR INTEGER / OPTION FOR LONG
    // INTEGER: FOR loop variables are 32-bit integers (default, matches QBasic)
    // LONG: FOR loop variables are 64-bit integers (for large ranges)
    ForLoopType forLoopType = ForLoopType::INTEGER;
    
    // Loop cancellation: OPTION CANCELLABLE ON/OFF
    // When true, inject script cancellation checks into loops
    // Default is true for safety (allows users to turn off for maximum speed)
    bool cancellableLoops = true;
    
    // Array bounds checking: OPTION BOUNDS_CHECK ON/OFF
    // When true, emit runtime bounds checking for array accesses
    // When false, skip bounds checks (faster but unsafe)
    // Default is true for safety
    bool boundsChecking = true;
    
    // Error tracking: OPTION ERROR
    // When true, emit _LINE tracking for better error messages
    // Default is true for better UX (shows BASIC line numbers in runtime errors)
    bool errorTracking = true;
    
    // Operator behavior: OPTION BITWISE vs OPTION LOGICAL
    // When true, AND/OR/XOR are bitwise operators
    // When false, AND/OR/XOR are logical operators (default BASIC behavior)
    bool bitwiseOperators = false;
    
    // Variable declaration: OPTION EXPLICIT
    // When true, all variables must be explicitly declared (DIM/LOCAL)
    // When false, variables can be implicitly declared on first use
    bool explicitDeclarations = false;
    
    // Forced yielding: OPTION FORCE_YIELD [budget]
    // When enabled, timer handlers are automatically yielded after N instructions
    // This prevents long-running handlers from blocking the main program
    bool forceYieldEnabled = false;
    int forceYieldBudget = 10000;  // Default: yield every 10,000 instructions
    
    // Constructor with defaults
    CompilerOptions() = default;
    
    // Reset to defaults
    void reset() {
        arrayBase = 1;
        stringMode = StringMode::DETECTSTRING;
        forLoopType = ForLoopType::INTEGER;
        cancellableLoops = true;   // Default to enabled for safety
        boundsChecking = true;     // Default to enabled for safety
        errorTracking = true;      // Default to enabled for better UX
        bitwiseOperators = false;
        explicitDeclarations = false;
        forceYieldEnabled = false;
        forceYieldBudget = 10000;
    }
};

} // namespace FasterBASIC

#endif // FASTERBASIC_OPTIONS_H