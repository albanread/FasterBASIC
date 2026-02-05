//
// plugin_support.h
// FasterBASIC Plugin Support - Runtime API for Plugin Developers
//
// This header provides the runtime API that plugins can use to interact with
// the FasterBASIC runtime system. It includes functions for string manipulation,
// memory management, I/O, math operations, and other runtime services.
//
// Plugin developers should include this header to access FasterBASIC runtime
// functionality from their plugin functions.
//

#ifndef FASTERBASIC_PLUGIN_SUPPORT_H
#define FASTERBASIC_PLUGIN_SUPPORT_H

#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// =============================================================================
// Forward Declarations
// =============================================================================

// String descriptor (opaque to plugins)
typedef struct StringDescriptor StringDescriptor;

// Basic string type (opaque to plugins)
typedef struct BasicString BasicString;

// =============================================================================
// String Operations
// =============================================================================

// Create a new string from C string
BasicString* fb_str_new(const char* str);

// Create a new string with specific length
BasicString* fb_str_new_length(const char* str, size_t length);

// Get C string representation (valid until string is released)
const char* fb_str_cstr(BasicString* str);

// Get string length
int32_t fb_str_length(BasicString* str);

// Concatenate two strings
BasicString* fb_str_concat(BasicString* a, BasicString* b);

// Get substring (start is 0-based, length is number of characters)
BasicString* fb_str_substr(BasicString* str, int32_t start, int32_t length);

// Get leftmost characters
BasicString* fb_str_left(BasicString* str, int32_t count);

// Get rightmost characters
BasicString* fb_str_right(BasicString* str, int32_t count);

// Compare two strings (returns 0 if equal, <0 if a<b, >0 if a>b)
int32_t fb_str_compare(BasicString* a, BasicString* b);

// Convert string to uppercase
BasicString* fb_str_upper(BasicString* str);

// Convert string to lowercase
BasicString* fb_str_lower(BasicString* str);

// Trim whitespace from both ends
BasicString* fb_str_trim(BasicString* str);

// Find substring in string (returns 1-based index, or 0 if not found)
int32_t fb_str_instr(BasicString* haystack, BasicString* needle);

// Replace all occurrences of 'find' with 'replace' in 'str'
BasicString* fb_str_replace(BasicString* str, BasicString* find, BasicString* replace);

// Retain (increment reference count)
BasicString* fb_str_retain(BasicString* str);

// Release (decrement reference count, free if 0)
void fb_str_release(BasicString* str);

// =============================================================================
// String Conversion Operations
// =============================================================================

// Convert integer to string
BasicString* fb_int_to_str(int32_t value);

// Convert long to string
BasicString* fb_long_to_str(int64_t value);

// Convert float to string
BasicString* fb_float_to_str(float value);

// Convert double to string
BasicString* fb_double_to_str(double value);

// Convert string to integer
int32_t fb_str_to_int(BasicString* str);

// Convert string to long
int64_t fb_str_to_long(BasicString* str);

// Convert string to float
float fb_str_to_float(BasicString* str);

// Convert string to double
double fb_str_to_double(BasicString* str);

// Convert C string to integer
int32_t fb_cstr_to_int(const char* str);

// Convert C string to double
double fb_cstr_to_double(const char* str);

// =============================================================================
// Math Operations
// =============================================================================

// Absolute value
int32_t fb_abs_int(int32_t x);
double fb_abs_double(double x);

// Square root
double fb_sqrt(double x);

// Power functions
double fb_pow(double base, double exponent);
double fb_exp2(double x);  // 2^x
double fb_exp(double x);   // e^x

// Trigonometric functions
double fb_sin(double x);
double fb_cos(double x);
double fb_tan(double x);
double fb_asin(double x);
double fb_acos(double x);
double fb_atan(double x);
double fb_atan2(double y, double x);

// Hyperbolic functions
double fb_sinh(double x);
double fb_cosh(double x);
double fb_tanh(double x);

// Logarithmic functions
double fb_log(double x);      // Natural log
double fb_log10(double x);    // Base-10 log
double fb_log2(double x);     // Base-2 log

// Rounding functions
double fb_floor(double x);
double fb_ceil(double x);
double fb_round(double x);
double fb_trunc(double x);
int32_t fb_int(double x);     // Truncate to integer

// Sign and comparison
int32_t fb_sgn(int32_t x);    // Returns -1, 0, or 1
double fb_fmax(double a, double b);
double fb_fmin(double a, double b);

// Modulo operations
double fb_fmod(double x, double y);

// Clamp and interpolation
double fb_clamp(double value, double min, double max);
double fb_lerp(double a, double b, double t);

// =============================================================================
// Random Number Generation
// =============================================================================

// Generate random double in [0, 1)
double fb_rnd(void);

// Generate random integer in [min, max] inclusive
int32_t fb_rnd_int(int32_t min, int32_t max);

// Set random seed
void fb_randomize(int32_t seed);

// Generate random integer (full range)
int32_t fb_rand(void);

// =============================================================================
// Memory Management
// =============================================================================

// Allocate temporary memory (freed automatically by runtime context)
void* fb_alloc_temp(size_t size);

// Allocate memory (must be freed with fb_free)
void* fb_alloc(size_t size);

// Free allocated memory
void fb_free(void* ptr);

// =============================================================================
// Console I/O
// =============================================================================

// Print functions
void fb_print_int(int32_t value);
void fb_print_long(int64_t value);
void fb_print_float(float value);
void fb_print_double(double value);
void fb_print_string(BasicString* str);
void fb_print_cstr(const char* str);
void fb_print_newline(void);

// Input functions
BasicString* fb_input_string(void);
int32_t fb_input_int(void);
double fb_input_double(void);

// Screen control
void fb_cls(void);
void fb_locate(int32_t row, int32_t col);
void fb_color(int32_t foreground, int32_t background);

// =============================================================================
// Error Handling
// =============================================================================

// Error codes
#define FB_ERR_ILLEGAL_CALL     5
#define FB_ERR_OVERFLOW         6
#define FB_ERR_SUBSCRIPT        9
#define FB_ERR_DIV_ZERO        11
#define FB_ERR_TYPE_MISMATCH   13
#define FB_ERR_BAD_FILE        52
#define FB_ERR_FILE_NOT_FOUND  53
#define FB_ERR_DISK_FULL       61
#define FB_ERR_INPUT_PAST_END  62

// Raise a runtime error
void fb_error(int32_t error_code);

// Raise a runtime error with custom message
void fb_error_msg(const char* message);

// Get current error code (0 if no error)
int32_t fb_err(void);

// Get current error line number
int32_t fb_erl(void);

// =============================================================================
// Timer and Time Functions
// =============================================================================

// Get timer value in seconds since midnight
double fb_timer(void);

// Get timer value in milliseconds
int64_t fb_timer_ms(void);

// Sleep for specified milliseconds
void fb_sleep_ms(int64_t milliseconds);

// =============================================================================
// Advanced Math Functions
// =============================================================================

// Advanced trigonometry
double fb_hypot(double x, double y);  // sqrt(x^2 + y^2)

// Advanced exponential/log
double fb_expm1(double x);  // exp(x) - 1 (accurate for small x)
double fb_log1p(double x);  // log(1 + x) (accurate for small x)

// Cube root
double fb_cbrt(double x);

// Error functions
double fb_erf(double x);
double fb_erfc(double x);

// Gamma functions
double fb_tgamma(double x);
double fb_lgamma(double x);

// Copy sign
double fb_copysign(double mag, double sgn);

// Fused multiply-add
double fb_fma(double x, double y, double z);  // x * y + z

// =============================================================================
// Utility Functions
// =============================================================================

// Convert degrees to radians
double fb_deg_to_rad(double degrees);

// Convert radians to degrees
double fb_rad_to_deg(double radians);

// Factorial (for small integers)
double fb_factorial(int32_t n);

// =============================================================================
// Plugin Runtime Context Access
// =============================================================================
// These functions are for accessing the runtime context within plugin functions.
// They are implemented in plugin_runtime_context.cpp and declared here for
// plugin convenience.

#include "plugin_interface.h"  // For FB_RuntimeContext

// Parameter access (re-exported for convenience)
int32_t    fb_ctx_get_int_param(FB_RuntimeContext* ctx, int index);
int64_t    fb_ctx_get_long_param(FB_RuntimeContext* ctx, int index);
float      fb_ctx_get_float_param(FB_RuntimeContext* ctx, int index);
double     fb_ctx_get_double_param(FB_RuntimeContext* ctx, int index);
const char* fb_ctx_get_string_param(FB_RuntimeContext* ctx, int index);
int        fb_ctx_get_bool_param(FB_RuntimeContext* ctx, int index);
int        fb_ctx_param_count(FB_RuntimeContext* ctx);

// Return value functions (re-exported for convenience)
void fb_ctx_return_int(FB_RuntimeContext* ctx, int32_t value);
void fb_ctx_return_long(FB_RuntimeContext* ctx, int64_t value);
void fb_ctx_return_float(FB_RuntimeContext* ctx, float value);
void fb_ctx_return_double(FB_RuntimeContext* ctx, double value);
void fb_ctx_return_string(FB_RuntimeContext* ctx, const char* value);
void fb_ctx_return_bool(FB_RuntimeContext* ctx, int value);

// Error handling (re-exported for convenience)
void fb_ctx_set_error(FB_RuntimeContext* ctx, const char* message);
int  fb_ctx_has_error(FB_RuntimeContext* ctx);

// Memory management (re-exported for convenience)
void* fb_ctx_alloc(FB_RuntimeContext* ctx, size_t size);
const char* fb_ctx_create_string(FB_RuntimeContext* ctx, const char* str);

// =============================================================================
// Usage Notes
// =============================================================================
//
// String Memory Management:
// -------------------------
// - Strings returned by fb_str_* functions are reference-counted
// - Always call fb_str_release() when done with a string
// - Some functions return retained strings (already incremented)
// - Use fb_str_retain() if you need to keep a string longer
//
// Temporary Memory:
// -----------------
// - fb_alloc_temp() allocates memory tied to the current runtime context
// - Temporary memory is freed automatically when the plugin function returns
// - Use for scratch buffers and short-lived allocations
//
// Persistent Memory:
// ------------------
// - fb_alloc() allocates memory that persists beyond the function call
// - Must be freed explicitly with fb_free()
// - Use for plugin state that needs to persist
//
// Error Handling:
// ---------------
// - Call fb_error() or fb_error_msg() to report errors
// - Error codes match QBasic/QuickBASIC error codes where applicable
// - Errors propagate to BASIC's ON ERROR handler
//
// Thread Safety:
// --------------
// - FasterBASIC runtime is single-threaded
// - Plugins should not create threads or use thread-local storage
// - All plugin functions execute in the main thread
//
// Performance:
// ------------
// - String operations allocate memory; avoid in tight loops
// - Use fb_str_cstr() to access raw char* when read-only access is needed
// - Temporary allocations are fast but limited in scope
//

#ifdef __cplusplus
}
#endif

#endif // FASTERBASIC_PLUGIN_SUPPORT_H