//
// example_math_plugin.c
// Example Math Plugin for FasterBASIC (C-Native)
//
// Demonstrates how to create a native C plugin for FasterBASIC's
// new C-ABI plugin system (no Lua dependency required).
//
// Build on macOS:
//   clang -shared -fPIC -o math_plugin.dylib example_math_plugin.c \
//         -I../fsh/FasterBASICT/src
//
// Build on Linux:
//   gcc -shared -fPIC -o math_plugin.so example_math_plugin.c \
//       -I../fsh/FasterBASICT/src
//
// Usage in BASIC:
//   LOADPLUGIN "math_plugin.dylib"
//   PRINT FACTORIAL(5)
//   IF ISPRIME(17) THEN PRINT "17 is prime"
//

#include "plugin_interface.h"
#include <stdio.h>
#include <math.h>

// =============================================================================
// Plugin Function Implementations
// =============================================================================

// FACTORIAL(n) - Calculate factorial
// Returns n! for integer n (0 <= n <= 20)
void factorial_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    // Validate input
    if (n < 0) {
        fb_set_error(ctx, "FACTORIAL: negative numbers not supported");
        return;
    }
    
    if (n > 20) {
        fb_set_error(ctx, "FACTORIAL: input too large (max 20 to avoid overflow)");
        return;
    }
    
    // Calculate factorial
    int64_t result = 1;
    for (int32_t i = 2; i <= n; i++) {
        result *= i;
    }
    
    // Return as LONG (64-bit to handle larger factorials)
    fb_return_long(ctx, result);
}

// ISPRIME(n) - Check if number is prime
// Returns -1 (TRUE) if n is prime, 0 (FALSE) otherwise
void isprime_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    // Handle special cases
    if (n < 2) {
        fb_return_int(ctx, 0);  // FALSE
        return;
    }
    
    if (n == 2) {
        fb_return_int(ctx, -1);  // TRUE
        return;
    }
    
    if (n % 2 == 0) {
        fb_return_int(ctx, 0);  // FALSE
        return;
    }
    
    // Check odd divisors up to sqrt(n)
    int32_t limit = (int32_t)sqrt((double)n);
    for (int32_t i = 3; i <= limit; i += 2) {
        if (n % i == 0) {
            fb_return_int(ctx, 0);  // FALSE - found a divisor
            return;
        }
    }
    
    fb_return_int(ctx, -1);  // TRUE - no divisors found
}

// GCD(a, b) - Greatest common divisor using Euclidean algorithm
void gcd_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    
    // Use absolute values
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    
    // Euclidean algorithm
    while (b != 0) {
        int32_t temp = b;
        b = a % b;
        a = temp;
    }
    
    fb_return_int(ctx, a);
}

// LCM(a, b) - Least common multiple
void lcm_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    
    // Use absolute values
    if (a < 0) a = -a;
    if (b < 0) b = -b;
    
    if (a == 0 || b == 0) {
        fb_return_int(ctx, 0);
        return;
    }
    
    // Calculate GCD first
    int32_t gcd_a = a;
    int32_t gcd_b = b;
    while (gcd_b != 0) {
        int32_t temp = gcd_b;
        gcd_b = gcd_a % gcd_b;
        gcd_a = temp;
    }
    
    // LCM(a,b) = |a*b| / GCD(a,b)
    int32_t lcm = (a / gcd_a) * b;
    fb_return_int(ctx, lcm);
}

// CLAMP(value, min, max) - Constrain value to range
void clamp_impl(FB_RuntimeContext* ctx) {
    double value = fb_get_double_param(ctx, 0);
    double min_val = fb_get_double_param(ctx, 1);
    double max_val = fb_get_double_param(ctx, 2);
    
    if (min_val > max_val) {
        fb_set_error(ctx, "CLAMP: min must be less than or equal to max");
        return;
    }
    
    if (value < min_val) {
        fb_return_double(ctx, min_val);
    } else if (value > max_val) {
        fb_return_double(ctx, max_val);
    } else {
        fb_return_double(ctx, value);
    }
}

// LERP(a, b, t) - Linear interpolation
void lerp_impl(FB_RuntimeContext* ctx) {
    double a = fb_get_double_param(ctx, 0);
    double b = fb_get_double_param(ctx, 1);
    double t = fb_get_double_param(ctx, 2);
    
    // Standard lerp formula: a + (b - a) * t
    double result = a + (b - a) * t;
    fb_return_double(ctx, result);
}

// FIB(n) - Fibonacci number (iterative for efficiency)
void fib_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    if (n < 0) {
        fb_set_error(ctx, "FIB: negative indices not supported");
        return;
    }
    
    if (n == 0) {
        fb_return_long(ctx, 0);
        return;
    }
    
    if (n == 1) {
        fb_return_long(ctx, 1);
        return;
    }
    
    // Iterative calculation (avoids stack overflow for large n)
    int64_t a = 0;
    int64_t b = 1;
    
    for (int32_t i = 2; i <= n; i++) {
        int64_t temp = a + b;
        
        // Check for overflow
        if (temp < 0) {
            fb_set_error(ctx, "FIB: result too large (overflow)");
            return;
        }
        
        a = b;
        b = temp;
    }
    
    fb_return_long(ctx, b);
}

// POW2(n) - Calculate 2^n (fast power of 2)
void pow2_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    if (n < 0) {
        fb_set_error(ctx, "POW2: negative exponents not supported");
        return;
    }
    
    if (n > 30) {
        fb_set_error(ctx, "POW2: exponent too large (max 30 to avoid overflow)");
        return;
    }
    
    // Calculate 2^n using bit shift
    int32_t result = 1 << n;
    fb_return_int(ctx, result);
}

// RANDOMSEED(seed) - Set random number generator seed
void randomseed_impl(FB_RuntimeContext* ctx) {
    int32_t seed = fb_get_int_param(ctx, 0);
    srand((unsigned int)seed);
    // No return value (command, not function)
}

// RANDOMINT(min, max) - Generate random integer in range [min, max]
void randomint_impl(FB_RuntimeContext* ctx) {
    int32_t min_val = fb_get_int_param(ctx, 0);
    int32_t max_val = fb_get_int_param(ctx, 1);
    
    if (min_val > max_val) {
        fb_set_error(ctx, "RANDOMINT: min must be less than or equal to max");
        return;
    }
    
    // Generate random number in range
    int32_t range = max_val - min_val + 1;
    int32_t result = min_val + (rand() % range);
    fb_return_int(ctx, result);
}

// =============================================================================
// Plugin Metadata
// =============================================================================

FB_PLUGIN_BEGIN("Math Extensions", "1.0.0", 
                "Extended math functions for FasterBASIC",
                "FasterBASIC Team")

// =============================================================================
// Plugin Initialization
// =============================================================================

FB_PLUGIN_INIT(callbacks) {
    // Register FACTORIAL function
    FB_BeginFunction(callbacks, "FACTORIAL", 
                    "Calculate factorial (n!)",
                    factorial_impl, FB_RETURN_LONG, "math")
        .addParameter("n", FB_PARAM_INT, "Integer (0-20)")
        .finish();
    
    // Register ISPRIME function
    FB_BeginFunction(callbacks, "ISPRIME",
                    "Check if number is prime",
                    isprime_impl, FB_RETURN_INT, "math")
        .addParameter("n", FB_PARAM_INT, "Number to test")
        .finish();
    
    // Register GCD function
    FB_BeginFunction(callbacks, "GCD",
                    "Greatest common divisor",
                    gcd_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    
    // Register LCM function
    FB_BeginFunction(callbacks, "LCM",
                    "Least common multiple",
                    lcm_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    
    // Register CLAMP function
    FB_BeginFunction(callbacks, "CLAMP",
                    "Constrain value to range",
                    clamp_impl, FB_RETURN_DOUBLE, "math")
        .addParameter("value", FB_PARAM_DOUBLE, "Value to clamp")
        .addParameter("min", FB_PARAM_DOUBLE, "Minimum value")
        .addParameter("max", FB_PARAM_DOUBLE, "Maximum value")
        .finish();
    
    // Register LERP function
    FB_BeginFunction(callbacks, "LERP",
                    "Linear interpolation",
                    lerp_impl, FB_RETURN_DOUBLE, "math")
        .addParameter("a", FB_PARAM_DOUBLE, "Start value")
        .addParameter("b", FB_PARAM_DOUBLE, "End value")
        .addParameter("t", FB_PARAM_DOUBLE, "Interpolation factor (0.0-1.0)")
        .finish();
    
    // Register FIB function
    FB_BeginFunction(callbacks, "FIB",
                    "Fibonacci number",
                    fib_impl, FB_RETURN_LONG, "math")
        .addParameter("n", FB_PARAM_INT, "Index (0-based)")
        .finish();
    
    // Register POW2 function
    FB_BeginFunction(callbacks, "POW2",
                    "Calculate 2^n",
                    pow2_impl, FB_RETURN_INT, "math")
        .addParameter("n", FB_PARAM_INT, "Exponent (0-30)")
        .finish();
    
    // Register RANDOMSEED command
    FB_BeginCommand(callbacks, "RANDOMSEED",
                   "Set random number generator seed",
                   randomseed_impl, "random")
        .addParameter("seed", FB_PARAM_INT, "Seed value")
        .finish();
    
    // Register RANDOMINT function
    FB_BeginFunction(callbacks, "RANDOMINT",
                    "Generate random integer in range",
                    randomint_impl, FB_RETURN_INT, "random")
        .addParameter("min", FB_PARAM_INT, "Minimum value")
        .addParameter("max", FB_PARAM_INT, "Maximum value")
        .finish();
    
    return 0;  // Success
}

// =============================================================================
// Plugin Shutdown
// =============================================================================

FB_PLUGIN_SHUTDOWN() {
    // No cleanup needed for this plugin
}

// =============================================================================
// Example BASIC Program Using This Plugin
// =============================================================================
/*

REM Math Plugin Demo
LOADPLUGIN "math_plugin.dylib"

PRINT "=== Math Extensions Plugin Demo ==="
PRINT ""

REM Test FACTORIAL
PRINT "Factorials:"
FOR i = 0 TO 10
    PRINT "  "; i; "! = "; FACTORIAL(i)
NEXT i
PRINT ""

REM Test ISPRIME
PRINT "Prime numbers from 1 to 50:"
FOR i = 1 TO 50
    IF ISPRIME(i) THEN
        PRINT i; " ";
    END IF
NEXT i
PRINT ""
PRINT ""

REM Test GCD and LCM
PRINT "GCD and LCM:"
PRINT "  GCD(48, 18) = "; GCD(48, 18)
PRINT "  LCM(48, 18) = "; LCM(48, 18)
PRINT ""

REM Test CLAMP
PRINT "Clamping values to [0, 100]:"
PRINT "  CLAMP(-10, 0, 100) = "; CLAMP(-10, 0, 100)
PRINT "  CLAMP(50, 0, 100) = "; CLAMP(50, 0, 100)
PRINT "  CLAMP(150, 0, 100) = "; CLAMP(150, 0, 100)
PRINT ""

REM Test LERP
PRINT "Linear interpolation from 0 to 100:"
FOR t = 0 TO 10
    PRINT "  t="; t/10; " -> "; LERP(0, 100, t/10)
NEXT t
PRINT ""

REM Test FIB
PRINT "Fibonacci numbers:"
FOR i = 0 TO 15
    PRINT "  FIB("; i; ") = "; FIB(i)
NEXT i
PRINT ""

REM Test POW2
PRINT "Powers of 2:"
FOR i = 0 TO 10
    PRINT "  2^"; i; " = "; POW2(i)
NEXT i
PRINT ""

REM Test random functions
RANDOMSEED 42
PRINT "Random integers between 1 and 100:"
FOR i = 1 TO 10
    PRINT "  "; RANDOMINT(1, 100)
NEXT i

*/