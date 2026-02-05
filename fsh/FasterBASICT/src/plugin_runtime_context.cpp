//
// plugin_runtime_context.cpp
// FasterBASIC Plugin Runtime Context Implementation
//
// Implements the runtime context that is passed to plugin functions,
// including parameter access, return values, error handling, and
// temporary memory management.
//

#include "plugin_runtime_context.h"
#include <cstring>
#include <cstdlib>

// =============================================================================
// FB_RuntimeContext Destructor
// =============================================================================

FB_RuntimeContext::~FB_RuntimeContext() {
    // Free all temporary allocations
    for (void* ptr : temp_allocations) {
        if (ptr) {
            free(ptr);
        }
    }
    temp_allocations.clear();
    temp_strings.clear();
}

// =============================================================================
// FB_RuntimeContext Methods
// =============================================================================

void FB_RuntimeContext::reset() {
    // Free temporary allocations
    for (void* ptr : temp_allocations) {
        if (ptr) {
            free(ptr);
        }
    }
    temp_allocations.clear();
    temp_strings.clear();
    
    // Clear parameters and return value
    parameters.clear();
    return_value = FB_ReturnValue();
    
    // Clear error state
    has_error = false;
    error_message.clear();
}

void FB_RuntimeContext::addParameter(FB_ParameterType type, const FB_ParameterValue& value) {
    FB_Parameter param;
    param.type = type;
    param.value = value;
    parameters.push_back(param);
}

void* FB_RuntimeContext::allocTemp(size_t size) {
    void* ptr = malloc(size);
    if (ptr) {
        temp_allocations.push_back(ptr);
    }
    return ptr;
}

const char* FB_RuntimeContext::createTempString(const char* str) {
    if (!str) {
        return nullptr;
    }
    
    temp_strings.push_back(std::string(str));
    return temp_strings.back().c_str();
}

// =============================================================================
// Context Creation and Management
// =============================================================================

FB_RuntimeContext* fb_context_create() {
    return new FB_RuntimeContext();
}

void fb_context_destroy(FB_RuntimeContext* ctx) {
    if (ctx) {
        delete ctx;
    }
}

void fb_context_reset(FB_RuntimeContext* ctx) {
    if (ctx) {
        ctx->reset();
    }
}

// =============================================================================
// Parameter Access Implementation
// =============================================================================

int32_t fb_get_int_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return 0;
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    // Type conversion if needed
    switch (param.type) {
        case FB_PARAM_INT:
            return param.value.int_value;
        case FB_PARAM_LONG:
            return static_cast<int32_t>(param.value.long_value);
        case FB_PARAM_FLOAT:
            return static_cast<int32_t>(param.value.float_value);
        case FB_PARAM_DOUBLE:
            return static_cast<int32_t>(param.value.double_value);
        case FB_PARAM_BOOL:
            return param.value.bool_value ? 1 : 0;
        default:
            return 0;
    }
}

int64_t fb_get_long_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return 0;
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    // Type conversion if needed
    switch (param.type) {
        case FB_PARAM_INT:
            return static_cast<int64_t>(param.value.int_value);
        case FB_PARAM_LONG:
            return param.value.long_value;
        case FB_PARAM_FLOAT:
            return static_cast<int64_t>(param.value.float_value);
        case FB_PARAM_DOUBLE:
            return static_cast<int64_t>(param.value.double_value);
        case FB_PARAM_BOOL:
            return param.value.bool_value ? 1 : 0;
        default:
            return 0;
    }
}

float fb_get_float_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return 0.0f;
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    // Type conversion if needed
    switch (param.type) {
        case FB_PARAM_INT:
            return static_cast<float>(param.value.int_value);
        case FB_PARAM_LONG:
            return static_cast<float>(param.value.long_value);
        case FB_PARAM_FLOAT:
            return param.value.float_value;
        case FB_PARAM_DOUBLE:
            return static_cast<float>(param.value.double_value);
        case FB_PARAM_BOOL:
            return param.value.bool_value ? 1.0f : 0.0f;
        default:
            return 0.0f;
    }
}

double fb_get_double_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return 0.0;
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    // Type conversion if needed
    switch (param.type) {
        case FB_PARAM_INT:
            return static_cast<double>(param.value.int_value);
        case FB_PARAM_LONG:
            return static_cast<double>(param.value.long_value);
        case FB_PARAM_FLOAT:
            return static_cast<double>(param.value.float_value);
        case FB_PARAM_DOUBLE:
            return param.value.double_value;
        case FB_PARAM_BOOL:
            return param.value.bool_value ? 1.0 : 0.0;
        default:
            return 0.0;
    }
}

const char* fb_get_string_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return "";
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    if (param.type == FB_PARAM_STRING && param.value.string_value) {
        return param.value.string_value;
    }
    
    return "";
}

int fb_get_bool_param_impl(FB_RuntimeContext* ctx, int index) {
    if (!ctx || !ctx->isValidParameterIndex(index)) {
        return 0;
    }
    
    const FB_Parameter& param = ctx->parameters[index];
    
    // Type conversion if needed
    switch (param.type) {
        case FB_PARAM_INT:
            return param.value.int_value != 0;
        case FB_PARAM_LONG:
            return param.value.long_value != 0;
        case FB_PARAM_FLOAT:
            return param.value.float_value != 0.0f;
        case FB_PARAM_DOUBLE:
            return param.value.double_value != 0.0;
        case FB_PARAM_BOOL:
            return param.value.bool_value;
        case FB_PARAM_STRING:
            return param.value.string_value && param.value.string_value[0] != '\0';
        default:
            return 0;
    }
}

int fb_param_count_impl(FB_RuntimeContext* ctx) {
    if (!ctx) {
        return 0;
    }
    return ctx->getParameterCount();
}

// =============================================================================
// Return Value Implementation
// =============================================================================

void fb_return_int_impl(FB_RuntimeContext* ctx, int32_t value) {
    if (!ctx) return;
    
    ctx->return_value.type = FB_RETURN_INT;
    ctx->return_value.value.int_value = value;
    ctx->return_value.has_value = true;
}

void fb_return_long_impl(FB_RuntimeContext* ctx, int64_t value) {
    if (!ctx) return;
    
    ctx->return_value.type = FB_RETURN_LONG;
    ctx->return_value.value.long_value = value;
    ctx->return_value.has_value = true;
}

void fb_return_float_impl(FB_RuntimeContext* ctx, float value) {
    if (!ctx) return;
    
    ctx->return_value.type = FB_RETURN_FLOAT;
    ctx->return_value.value.float_value = value;
    ctx->return_value.has_value = true;
}

void fb_return_double_impl(FB_RuntimeContext* ctx, double value) {
    if (!ctx) return;
    
    ctx->return_value.type = FB_RETURN_DOUBLE;
    ctx->return_value.value.double_value = value;
    ctx->return_value.has_value = true;
}

void fb_return_string_impl(FB_RuntimeContext* ctx, const char* value) {
    if (!ctx) return;
    
    // Make a copy of the string in temporary storage
    const char* temp_str = ctx->createTempString(value ? value : "");
    
    ctx->return_value.type = FB_RETURN_STRING;
    ctx->return_value.value.string_value = temp_str;
    ctx->return_value.has_value = true;
}

void fb_return_bool_impl(FB_RuntimeContext* ctx, int value) {
    if (!ctx) return;
    
    ctx->return_value.type = FB_RETURN_BOOL;
    ctx->return_value.value.bool_value = value ? 1 : 0;
    ctx->return_value.has_value = true;
}

// =============================================================================
// Error Handling Implementation
// =============================================================================

void fb_set_error_impl(FB_RuntimeContext* ctx, const char* message) {
    if (!ctx) return;
    
    ctx->has_error = true;
    ctx->error_message = message ? message : "Unknown error";
}

int fb_has_error_impl(FB_RuntimeContext* ctx) {
    if (!ctx) return 0;
    return ctx->has_error ? 1 : 0;
}

const char* fb_get_error_message(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->has_error) {
        return nullptr;
    }
    return ctx->error_message.c_str();
}

// =============================================================================
// Memory Management Implementation
// =============================================================================

void* fb_alloc_impl(FB_RuntimeContext* ctx, size_t size) {
    if (!ctx) return nullptr;
    return ctx->allocTemp(size);
}

const char* fb_create_string_impl(FB_RuntimeContext* ctx, const char* str) {
    if (!ctx) return nullptr;
    return ctx->createTempString(str);
}

// =============================================================================
// C API Wrappers (exported in plugin_interface.h)
// =============================================================================

extern "C" {

int32_t fb_get_int_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_int_param_impl(ctx, index);
}

int64_t fb_get_long_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_long_param_impl(ctx, index);
}

float fb_get_float_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_float_param_impl(ctx, index);
}

double fb_get_double_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_double_param_impl(ctx, index);
}

const char* fb_get_string_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_string_param_impl(ctx, index);
}

int fb_get_bool_param(FB_RuntimeContext* ctx, int index) {
    return fb_get_bool_param_impl(ctx, index);
}

int fb_param_count(FB_RuntimeContext* ctx) {
    return fb_param_count_impl(ctx);
}

void fb_return_int(FB_RuntimeContext* ctx, int32_t value) {
    fb_return_int_impl(ctx, value);
}

void fb_return_long(FB_RuntimeContext* ctx, int64_t value) {
    fb_return_long_impl(ctx, value);
}

void fb_return_float(FB_RuntimeContext* ctx, float value) {
    fb_return_float_impl(ctx, value);
}

void fb_return_double(FB_RuntimeContext* ctx, double value) {
    fb_return_double_impl(ctx, value);
}

void fb_return_string(FB_RuntimeContext* ctx, const char* value) {
    fb_return_string_impl(ctx, value);
}

void fb_return_bool(FB_RuntimeContext* ctx, int value) {
    fb_return_bool_impl(ctx, value);
}

void fb_set_error(FB_RuntimeContext* ctx, const char* message) {
    fb_set_error_impl(ctx, message);
}

int fb_has_error(FB_RuntimeContext* ctx) {
    return fb_has_error_impl(ctx);
}

void* fb_alloc(FB_RuntimeContext* ctx, size_t size) {
    return fb_alloc_impl(ctx, size);
}

const char* fb_create_string(FB_RuntimeContext* ctx, const char* str) {
    return fb_create_string_impl(ctx, str);
}

} // extern "C"

// =============================================================================
// Helper Functions for Code Generation
// =============================================================================

void fb_context_set_int_param(FB_RuntimeContext* ctx, int index, int32_t value) {
    if (!ctx) return;
    
    // Ensure we have enough parameters
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    ctx->parameters[index].type = FB_PARAM_INT;
    ctx->parameters[index].value.int_value = value;
}

void fb_context_set_long_param(FB_RuntimeContext* ctx, int index, int64_t value) {
    if (!ctx) return;
    
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    ctx->parameters[index].type = FB_PARAM_LONG;
    ctx->parameters[index].value.long_value = value;
}

void fb_context_set_float_param(FB_RuntimeContext* ctx, int index, float value) {
    if (!ctx) return;
    
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    ctx->parameters[index].type = FB_PARAM_FLOAT;
    ctx->parameters[index].value.float_value = value;
}

void fb_context_set_double_param(FB_RuntimeContext* ctx, int index, double value) {
    if (!ctx) return;
    
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    ctx->parameters[index].type = FB_PARAM_DOUBLE;
    ctx->parameters[index].value.double_value = value;
}

void fb_context_set_string_param(FB_RuntimeContext* ctx, int index, const char* value) {
    if (!ctx) return;
    
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    // Make a copy of the string in temporary storage
    const char* temp_str = ctx->createTempString(value ? value : "");
    
    ctx->parameters[index].type = FB_PARAM_STRING;
    ctx->parameters[index].value.string_value = temp_str;
}

void fb_context_set_bool_param(FB_RuntimeContext* ctx, int index, int value) {
    if (!ctx) return;
    
    while (static_cast<int>(ctx->parameters.size()) <= index) {
        ctx->parameters.push_back(FB_Parameter());
    }
    
    ctx->parameters[index].type = FB_PARAM_BOOL;
    ctx->parameters[index].value.bool_value = value ? 1 : 0;
}

void fb_context_add_int_param(FB_RuntimeContext* ctx, int32_t value) {
    if (!ctx) return;
    
    FB_ParameterValue val;
    val.int_value = value;
    ctx->addParameter(FB_PARAM_INT, val);
}

void fb_context_add_long_param(FB_RuntimeContext* ctx, int64_t value) {
    if (!ctx) return;
    
    FB_ParameterValue val;
    val.long_value = value;
    ctx->addParameter(FB_PARAM_LONG, val);
}

void fb_context_add_float_param(FB_RuntimeContext* ctx, float value) {
    if (!ctx) return;
    
    FB_ParameterValue val;
    val.float_value = value;
    ctx->addParameter(FB_PARAM_FLOAT, val);
}

void fb_context_add_double_param(FB_RuntimeContext* ctx, double value) {
    if (!ctx) return;
    
    FB_ParameterValue val;
    val.double_value = value;
    ctx->addParameter(FB_PARAM_DOUBLE, val);
}

void fb_context_add_string_param(FB_RuntimeContext* ctx, const char* value) {
    if (!ctx) return;
    
    // Make a copy of the string in temporary storage
    const char* temp_str = ctx->createTempString(value ? value : "");
    
    FB_ParameterValue val;
    val.string_value = temp_str;
    ctx->addParameter(FB_PARAM_STRING, val);
}

void fb_context_add_bool_param(FB_RuntimeContext* ctx, int value) {
    if (!ctx) return;
    
    FB_ParameterValue val;
    val.bool_value = value ? 1 : 0;
    ctx->addParameter(FB_PARAM_BOOL, val);
}

FB_ReturnType fb_context_get_return_type(FB_RuntimeContext* ctx) {
    if (!ctx) return FB_RETURN_VOID;
    return ctx->return_value.type;
}

int32_t fb_context_get_return_int(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return 0;
    
    // Type conversion if needed
    switch (ctx->return_value.type) {
        case FB_RETURN_INT:
            return ctx->return_value.value.int_value;
        case FB_RETURN_LONG:
            return static_cast<int32_t>(ctx->return_value.value.long_value);
        case FB_RETURN_FLOAT:
            return static_cast<int32_t>(ctx->return_value.value.float_value);
        case FB_RETURN_DOUBLE:
            return static_cast<int32_t>(ctx->return_value.value.double_value);
        case FB_RETURN_BOOL:
            return ctx->return_value.value.bool_value;
        default:
            return 0;
    }
}

int64_t fb_context_get_return_long(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return 0;
    
    switch (ctx->return_value.type) {
        case FB_RETURN_INT:
            return static_cast<int64_t>(ctx->return_value.value.int_value);
        case FB_RETURN_LONG:
            return ctx->return_value.value.long_value;
        case FB_RETURN_FLOAT:
            return static_cast<int64_t>(ctx->return_value.value.float_value);
        case FB_RETURN_DOUBLE:
            return static_cast<int64_t>(ctx->return_value.value.double_value);
        case FB_RETURN_BOOL:
            return ctx->return_value.value.bool_value;
        default:
            return 0;
    }
}

float fb_context_get_return_float(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return 0.0f;
    
    switch (ctx->return_value.type) {
        case FB_RETURN_INT:
            return static_cast<float>(ctx->return_value.value.int_value);
        case FB_RETURN_LONG:
            return static_cast<float>(ctx->return_value.value.long_value);
        case FB_RETURN_FLOAT:
            return ctx->return_value.value.float_value;
        case FB_RETURN_DOUBLE:
            return static_cast<float>(ctx->return_value.value.double_value);
        case FB_RETURN_BOOL:
            return ctx->return_value.value.bool_value ? 1.0f : 0.0f;
        default:
            return 0.0f;
    }
}

double fb_context_get_return_double(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return 0.0;
    
    switch (ctx->return_value.type) {
        case FB_RETURN_INT:
            return static_cast<double>(ctx->return_value.value.int_value);
        case FB_RETURN_LONG:
            return static_cast<double>(ctx->return_value.value.long_value);
        case FB_RETURN_FLOAT:
            return static_cast<double>(ctx->return_value.value.float_value);
        case FB_RETURN_DOUBLE:
            return ctx->return_value.value.double_value;
        case FB_RETURN_BOOL:
            return ctx->return_value.value.bool_value ? 1.0 : 0.0;
        default:
            return 0.0;
    }
}

const char* fb_context_get_return_string(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return "";
    
    if (ctx->return_value.type == FB_RETURN_STRING && ctx->return_value.value.string_value) {
        return ctx->return_value.value.string_value;
    }
    
    return "";
}

int fb_context_get_return_bool(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->return_value.has_value) return 0;
    
    switch (ctx->return_value.type) {
        case FB_RETURN_INT:
            return ctx->return_value.value.int_value != 0;
        case FB_RETURN_LONG:
            return ctx->return_value.value.long_value != 0;
        case FB_RETURN_FLOAT:
            return ctx->return_value.value.float_value != 0.0f;
        case FB_RETURN_DOUBLE:
            return ctx->return_value.value.double_value != 0.0;
        case FB_RETURN_BOOL:
            return ctx->return_value.value.bool_value;
        case FB_RETURN_STRING:
            return ctx->return_value.value.string_value && 
                   ctx->return_value.value.string_value[0] != '\0';
        default:
            return 0;
    }
}