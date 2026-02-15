//
// test_math_plugin.c
// FasterBASIC Test Plugin - Simple Math Functions
//
// This is a minimal test plugin to verify Phase 3 code generation works.
// Compile: cc -shared -fPIC -o test_math.so test_math_plugin.c
//

#include "../fsh/FasterBASICT/src/plugin_interface.h"
#include <stdio.h>
#include <math.h>

// =============================================================================
// Plugin Function Implementations
// =============================================================================

// DOUBLE(x) - Return x * 2
void double_impl(FB_RuntimeContext* ctx) {
    int32_t value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 2);
}

// TRIPLE(x) - Return x * 3
void triple_impl(FB_RuntimeContext* ctx) {
    int32_t value = fb_get_int_param(ctx, 0);
    fb_return_int(ctx, value * 3);
}

// ADD(a, b) - Return a + b
void add_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    fb_return_int(ctx, a + b);
}

// MULTIPLY(a, b) - Return a * b
void multiply_impl(FB_RuntimeContext* ctx) {
    int32_t a = fb_get_int_param(ctx, 0);
    int32_t b = fb_get_int_param(ctx, 1);
    fb_return_int(ctx, a * b);
}

// AVERAGE(a, b) - Return (a + b) / 2.0 as float
void average_impl(FB_RuntimeContext* ctx) {
    float a = fb_get_float_param(ctx, 0);
    float b = fb_get_float_param(ctx, 1);
    fb_return_float(ctx, (a + b) / 2.0f);
}

// POWER(base, exp) - Return base^exp
void power_impl(FB_RuntimeContext* ctx) {
    double base = fb_get_double_param(ctx, 0);
    double exp = fb_get_double_param(ctx, 1);
    
    if (base < 0 && exp != floor(exp)) {
        fb_set_error(ctx, "Cannot raise negative number to non-integer power");
        return;
    }
    
    fb_return_double(ctx, pow(base, exp));
}

// FACTORIAL(n) - Return n! (with error checking)
void factorial_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    
    if (n < 0) {
        fb_set_error(ctx, "Factorial not defined for negative numbers");
        return;
    }
    
    if (n > 20) {
        fb_set_error(ctx, "Factorial overflow: n must be <= 20");
        return;
    }
    
    int64_t result = 1;
    for (int32_t i = 2; i <= n; i++) {
        result *= i;
    }
    
    fb_return_int(ctx, (int32_t)result);
}

// REPEAT$(s, count) - Repeat string s, count times
void repeat_impl(FB_RuntimeContext* ctx) {
    const char* str = fb_get_string_param(ctx, 0);
    int32_t count = fb_get_int_param(ctx, 1);
    
    if (count < 0) {
        fb_set_error(ctx, "Repeat count must be non-negative");
        return;
    }
    
    if (count == 0) {
        fb_return_string(ctx, "");
        return;
    }
    
    // Calculate total length
    size_t len = strlen(str);
    size_t total = len * count;
    
    if (total > 10000) {
        fb_set_error(ctx, "Result string too long (max 10000 chars)");
        return;
    }
    
    // Allocate result buffer
    char* result = (char*)fb_alloc(ctx, total + 1);
    if (!result) {
        fb_set_error(ctx, "Memory allocation failed");
        return;
    }
    
    // Build result
    char* p = result;
    for (int32_t i = 0; i < count; i++) {
        strcpy(p, str);
        p += len;
    }
    *p = '\0';
    
    fb_return_string(ctx, result);
}

// IS_EVEN(n) - Return true if n is even
void is_even_impl(FB_RuntimeContext* ctx) {
    int32_t n = fb_get_int_param(ctx, 0);
    fb_return_bool(ctx, (n % 2) == 0);
}

// DEBUG_PRINT message$ - Print debug message (command, not function)
void debug_print_impl(FB_RuntimeContext* ctx) {
    const char* msg = fb_get_string_param(ctx, 0);
    printf("[DEBUG] %s\n", msg);
}

// =============================================================================
// Plugin Metadata
// =============================================================================

FB_PLUGIN_BEGIN(
    "Test Math Plugin",
    "1.0.0",
    "Simple math functions for testing Phase 3 code generation",
    "FasterBASIC Team"
)

// =============================================================================
// Plugin Initialization
// =============================================================================

FB_PLUGIN_INIT(callbacks) {
    // Register functions
    
    FB_BeginFunction(callbacks, "DOUBLE", "Return x * 2", 
                     double_impl, FB_RETURN_INT, "math")
        .addParameter("x", FB_PARAM_INT, "Value to double")
        .finish();
    
    FB_BeginFunction(callbacks, "TRIPLE", "Return x * 3", 
                     triple_impl, FB_RETURN_INT, "math")
        .addParameter("x", FB_PARAM_INT, "Value to triple")
        .finish();
    
    FB_BeginFunction(callbacks, "ADD", "Add two numbers", 
                     add_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    
    FB_BeginFunction(callbacks, "MULTIPLY", "Multiply two numbers", 
                     multiply_impl, FB_RETURN_INT, "math")
        .addParameter("a", FB_PARAM_INT, "First number")
        .addParameter("b", FB_PARAM_INT, "Second number")
        .finish();
    
    FB_BeginFunction(callbacks, "AVERAGE", "Average of two numbers", 
                     average_impl, FB_RETURN_FLOAT, "math")
        .addParameter("a", FB_PARAM_FLOAT, "First number")
        .addParameter("b", FB_PARAM_FLOAT, "Second number")
        .finish();
    
    FB_BeginFunction(callbacks, "POWER", "Raise base to exponent", 
                     power_impl, FB_RETURN_DOUBLE, "math")
        .addParameter("base", FB_PARAM_DOUBLE, "Base value")
        .addParameter("exp", FB_PARAM_DOUBLE, "Exponent")
        .finish();
    
    FB_BeginFunction(callbacks, "FACTORIAL", "Calculate factorial (with error checking)", 
                     factorial_impl, FB_RETURN_INT, "math")
        .addParameter("n", FB_PARAM_INT, "Number (0-20)")
        .finish();
    
    FB_BeginFunction(callbacks, "REPEAT$", "Repeat string n times", 
                     repeat_impl, FB_RETURN_STRING, "string")
        .addParameter("str", FB_PARAM_STRING, "String to repeat")
        .addParameter("count", FB_PARAM_INT, "Number of repetitions")
        .finish();
    
    FB_BeginFunction(callbacks, "IS_EVEN", "Check if number is even", 
                     is_even_impl, FB_RETURN_BOOL, "math")
        .addParameter("n", FB_PARAM_INT, "Number to check")
        .finish();
    
    // Register commands (void return)
    
    FB_BeginCommand(callbacks, "DEBUG_PRINT", "Print debug message", 
                    debug_print_impl, "debug")
        .addParameter("message", FB_PARAM_STRING, "Message to print")
        .finish();
    
    return 0;
}

// =============================================================================
// Plugin Shutdown
// =============================================================================

FB_PLUGIN_SHUTDOWN() {
    // Nothing to clean up
}