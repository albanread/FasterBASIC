//
// plugin_runtime_context.h
// FasterBASIC Plugin Runtime Context
//
// This file defines the runtime context structure that is passed to plugin
// functions. The context contains parameter values, return value storage,
// error state, and temporary memory allocations.
//

#ifndef FASTERBASIC_PLUGIN_RUNTIME_CONTEXT_H
#define FASTERBASIC_PLUGIN_RUNTIME_CONTEXT_H

#include "plugin_interface.h"
#include <cstdint>
#include <cstddef>
#include <vector>
#include <string>

// =============================================================================
// Parameter Value Union
// =============================================================================

union FB_ParameterValue {
    int32_t int_value;
    int64_t long_value;
    float float_value;
    double double_value;
    const char* string_value;
    int bool_value;
};

// =============================================================================
// Parameter Storage
// =============================================================================

struct FB_Parameter {
    FB_ParameterType type;
    FB_ParameterValue value;
    
    FB_Parameter() : type(FB_PARAM_INT) {
        value.long_value = 0;
    }
};

// =============================================================================
// Return Value Storage
// =============================================================================

struct FB_ReturnValue {
    FB_ReturnType type;
    
    union {
        int32_t int_value;
        int64_t long_value;
        float float_value;
        double double_value;
        const char* string_value;
        int bool_value;
    } value;
    
    bool has_value;
    
    FB_ReturnValue() : type(FB_RETURN_VOID), has_value(false) {
        value.long_value = 0;
    }
};

// =============================================================================
// Runtime Context Structure
// =============================================================================

struct FB_RuntimeContext {
    // Parameter storage
    std::vector<FB_Parameter> parameters;
    
    // Return value storage
    FB_ReturnValue return_value;
    
    // Error state
    bool has_error;
    std::string error_message;
    
    // Temporary memory allocations (freed when context is destroyed)
    std::vector<void*> temp_allocations;
    
    // Temporary strings (freed when context is destroyed)
    std::vector<std::string> temp_strings;
    
    // Constructor
    FB_RuntimeContext() : has_error(false) {}
    
    // Destructor - frees all temporary allocations
    ~FB_RuntimeContext();
    
    // Reset context for reuse
    void reset();
    
    // Add a parameter
    void addParameter(FB_ParameterType type, const FB_ParameterValue& value);
    
    // Get parameter count
    int getParameterCount() const { return static_cast<int>(parameters.size()); }
    
    // Validate parameter index
    bool isValidParameterIndex(int index) const {
        return index >= 0 && index < static_cast<int>(parameters.size());
    }
    
    // Allocate temporary memory
    void* allocTemp(size_t size);
    
    // Create temporary string copy
    const char* createTempString(const char* str);
};

// =============================================================================
// Context Creation and Management
// =============================================================================

// Create a new runtime context
FB_RuntimeContext* fb_context_create();

// Destroy a runtime context
void fb_context_destroy(FB_RuntimeContext* ctx);

// Reset context for reuse
void fb_context_reset(FB_RuntimeContext* ctx);

// =============================================================================
// Parameter Access Implementation
// =============================================================================

// Get parameter by index
int32_t fb_get_int_param_impl(FB_RuntimeContext* ctx, int index);
int64_t fb_get_long_param_impl(FB_RuntimeContext* ctx, int index);
float fb_get_float_param_impl(FB_RuntimeContext* ctx, int index);
double fb_get_double_param_impl(FB_RuntimeContext* ctx, int index);
const char* fb_get_string_param_impl(FB_RuntimeContext* ctx, int index);
int fb_get_bool_param_impl(FB_RuntimeContext* ctx, int index);
int fb_param_count_impl(FB_RuntimeContext* ctx);

// =============================================================================
// Return Value Implementation
// =============================================================================

void fb_return_int_impl(FB_RuntimeContext* ctx, int32_t value);
void fb_return_long_impl(FB_RuntimeContext* ctx, int64_t value);
void fb_return_float_impl(FB_RuntimeContext* ctx, float value);
void fb_return_double_impl(FB_RuntimeContext* ctx, double value);
void fb_return_string_impl(FB_RuntimeContext* ctx, const char* value);
void fb_return_bool_impl(FB_RuntimeContext* ctx, int value);

// =============================================================================
// Error Handling Implementation
// =============================================================================

void fb_set_error_impl(FB_RuntimeContext* ctx, const char* message);
int fb_has_error_impl(FB_RuntimeContext* ctx);
const char* fb_get_error_message(FB_RuntimeContext* ctx);

// =============================================================================
// Memory Management Implementation
// =============================================================================

void* fb_alloc_impl(FB_RuntimeContext* ctx, size_t size);
const char* fb_create_string_impl(FB_RuntimeContext* ctx, const char* str);

// =============================================================================
// Helper Functions for Code Generation
// =============================================================================

// These functions are used by the code generator to set up parameters
// before calling a plugin function

// Set integer parameter
void fb_context_set_int_param(FB_RuntimeContext* ctx, int index, int32_t value);

// Set long parameter
void fb_context_set_long_param(FB_RuntimeContext* ctx, int index, int64_t value);

// Set float parameter
void fb_context_set_float_param(FB_RuntimeContext* ctx, int index, float value);

// Set double parameter
void fb_context_set_double_param(FB_RuntimeContext* ctx, int index, double value);

// Set string parameter (makes a copy)
void fb_context_set_string_param(FB_RuntimeContext* ctx, int index, const char* value);

// Set bool parameter
void fb_context_set_bool_param(FB_RuntimeContext* ctx, int index, int value);

// Add integer parameter (append)
void fb_context_add_int_param(FB_RuntimeContext* ctx, int32_t value);

// Add long parameter (append)
void fb_context_add_long_param(FB_RuntimeContext* ctx, int64_t value);

// Add float parameter (append)
void fb_context_add_float_param(FB_RuntimeContext* ctx, float value);

// Add double parameter (append)
void fb_context_add_double_param(FB_RuntimeContext* ctx, double value);

// Add string parameter (append, makes a copy)
void fb_context_add_string_param(FB_RuntimeContext* ctx, const char* value);

// Add bool parameter (append)
void fb_context_add_bool_param(FB_RuntimeContext* ctx, int value);

// Get return value type
FB_ReturnType fb_context_get_return_type(FB_RuntimeContext* ctx);

// Get return value as integer
int32_t fb_context_get_return_int(FB_RuntimeContext* ctx);

// Get return value as long
int64_t fb_context_get_return_long(FB_RuntimeContext* ctx);

// Get return value as float
float fb_context_get_return_float(FB_RuntimeContext* ctx);

// Get return value as double
double fb_context_get_return_double(FB_RuntimeContext* ctx);

// Get return value as string
const char* fb_context_get_return_string(FB_RuntimeContext* ctx);

// Get return value as bool
int fb_context_get_return_bool(FB_RuntimeContext* ctx);

#endif // FASTERBASIC_PLUGIN_RUNTIME_CONTEXT_H