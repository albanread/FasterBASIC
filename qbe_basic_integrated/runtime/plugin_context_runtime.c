//
// plugin_context_runtime.c
// FasterBASIC Runtime - Plugin Context Implementation
//
// Provides the runtime context API for native C plugins.
// This allows plugins to access parameters and return values
// through a well-defined ABI.
//

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "string_descriptor.h"
#include "string_pool.h"

// Maximum number of parameters a plugin function can accept
#define FB_MAX_PARAMS 16

// Maximum number of temporary allocations
#define FB_MAX_TEMP_ALLOCS 64

// Parameter type enumeration
typedef enum {
    FB_PARAM_TYPE_INT,
    FB_PARAM_TYPE_LONG,
    FB_PARAM_TYPE_FLOAT,
    FB_PARAM_TYPE_DOUBLE,
    FB_PARAM_TYPE_STRING,
    FB_PARAM_TYPE_BOOL
} FB_ParameterTypeEnum;

// Parameter value union
typedef union {
    int32_t intValue;
    int64_t longValue;
    float floatValue;
    double doubleValue;
    const char* stringValue;  // NULL-terminated C string
    int boolValue;
} FB_ParameterValue;

// Parameter structure
typedef struct {
    FB_ParameterTypeEnum type;
    FB_ParameterValue value;
} FB_Parameter;

// Return value structure
typedef struct {
    FB_ParameterTypeEnum type;
    FB_ParameterValue value;
} FB_ReturnValue;

// Runtime context structure
struct FB_RuntimeContext {
    // Parameters
    FB_Parameter params[FB_MAX_PARAMS];
    int paramCount;
    
    // Return value
    FB_ReturnValue returnValue;
    int hasReturnValue;
    
    // Error state
    int hasError;
    char errorMessage[512];
    
    // Temporary allocations (freed on context destroy)
    void* tempAllocations[FB_MAX_TEMP_ALLOCS];
    int tempAllocCount;
    
    // Temporary string storage (for converted strings)
    char* tempStrings[FB_MAX_TEMP_ALLOCS];
    int tempStringCount;
};

// Forward declaration
typedef struct FB_RuntimeContext FB_RuntimeContext;

// =============================================================================
// Context Lifecycle
// =============================================================================

FB_RuntimeContext* fb_context_create(void) {
    FB_RuntimeContext* ctx = (FB_RuntimeContext*)calloc(1, sizeof(FB_RuntimeContext));
    if (!ctx) {
        fprintf(stderr, "ERROR: Failed to allocate plugin runtime context\n");
        return NULL;
    }
    
    ctx->paramCount = 0;
    ctx->hasReturnValue = 0;
    ctx->hasError = 0;
    ctx->errorMessage[0] = '\0';
    ctx->tempAllocCount = 0;
    ctx->tempStringCount = 0;
    
    return ctx;
}

void fb_context_destroy(FB_RuntimeContext* ctx) {
    if (!ctx) return;
    
    // Free temporary allocations
    for (int i = 0; i < ctx->tempAllocCount; i++) {
        if (ctx->tempAllocations[i]) {
            free(ctx->tempAllocations[i]);
        }
    }
    
    // Free temporary strings
    for (int i = 0; i < ctx->tempStringCount; i++) {
        if (ctx->tempStrings[i]) {
            free(ctx->tempStrings[i]);
        }
    }
    
    // Free the context itself
    free(ctx);
}

// =============================================================================
// Parameter Setting (used by code generator)
// =============================================================================

void fb_context_add_int_param(FB_RuntimeContext* ctx, int32_t value) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_INT;
    ctx->params[ctx->paramCount].value.intValue = value;
    ctx->paramCount++;
}

void fb_context_add_long_param(FB_RuntimeContext* ctx, int64_t value) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_LONG;
    ctx->params[ctx->paramCount].value.longValue = value;
    ctx->paramCount++;
}

void fb_context_add_float_param(FB_RuntimeContext* ctx, float value) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_FLOAT;
    ctx->params[ctx->paramCount].value.floatValue = value;
    ctx->paramCount++;
}

void fb_context_add_double_param(FB_RuntimeContext* ctx, double value) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_DOUBLE;
    ctx->params[ctx->paramCount].value.doubleValue = value;
    ctx->paramCount++;
}

void fb_context_add_string_param(FB_RuntimeContext* ctx, StringDescriptor* strDesc) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    // Convert string descriptor to NULL-terminated C string
    const char* cStr = "";
    if (strDesc && strDesc->data) {
        // Allocate temporary buffer for C string
        size_t len = strDesc->length;
        char* temp = (char*)malloc(len + 1);
        if (temp) {
            memcpy(temp, strDesc->data, len);
            temp[len] = '\0';
            cStr = temp;
            
            // Store in temporary string array for cleanup
            if (ctx->tempStringCount < FB_MAX_TEMP_ALLOCS) {
                ctx->tempStrings[ctx->tempStringCount++] = temp;
            }
        }
    }
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_STRING;
    ctx->params[ctx->paramCount].value.stringValue = cStr;
    ctx->paramCount++;
}

void fb_context_add_bool_param(FB_RuntimeContext* ctx, int value) {
    if (!ctx || ctx->paramCount >= FB_MAX_PARAMS) return;
    
    ctx->params[ctx->paramCount].type = FB_PARAM_TYPE_BOOL;
    ctx->params[ctx->paramCount].value.boolValue = value ? 1 : 0;
    ctx->paramCount++;
}

// =============================================================================
// Parameter Getting (used by plugin functions)
// =============================================================================

int32_t fb_get_int_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return 0;
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    switch (param->type) {
        case FB_PARAM_TYPE_INT:
            return param->value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (int32_t)param->value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (int32_t)param->value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (int32_t)param->value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return param->value.boolValue;
        default:
            return 0;
    }
}

int64_t fb_get_long_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return 0;
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    switch (param->type) {
        case FB_PARAM_TYPE_INT:
            return (int64_t)param->value.intValue;
        case FB_PARAM_TYPE_LONG:
            return param->value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (int64_t)param->value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (int64_t)param->value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (int64_t)param->value.boolValue;
        default:
            return 0;
    }
}

float fb_get_float_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return 0.0f;
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    switch (param->type) {
        case FB_PARAM_TYPE_INT:
            return (float)param->value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (float)param->value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return param->value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (float)param->value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (float)param->value.boolValue;
        default:
            return 0.0f;
    }
}

double fb_get_double_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return 0.0;
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    switch (param->type) {
        case FB_PARAM_TYPE_INT:
            return (double)param->value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (double)param->value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (double)param->value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return param->value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (double)param->value.boolValue;
        default:
            return 0.0;
    }
}

const char* fb_get_string_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return "";
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    if (param->type == FB_PARAM_TYPE_STRING) {
        return param->value.stringValue ? param->value.stringValue : "";
    }
    
    // For non-string types, return empty string
    return "";
}

int fb_get_bool_param(FB_RuntimeContext* ctx, int index) {
    if (!ctx || index < 0 || index >= ctx->paramCount) {
        return 0;
    }
    
    FB_Parameter* param = &ctx->params[index];
    
    switch (param->type) {
        case FB_PARAM_TYPE_INT:
            return param->value.intValue != 0;
        case FB_PARAM_TYPE_LONG:
            return param->value.longValue != 0;
        case FB_PARAM_TYPE_FLOAT:
            return param->value.floatValue != 0.0f;
        case FB_PARAM_TYPE_DOUBLE:
            return param->value.doubleValue != 0.0;
        case FB_PARAM_TYPE_BOOL:
            return param->value.boolValue;
        case FB_PARAM_TYPE_STRING:
            return param->value.stringValue && param->value.stringValue[0] != '\0';
        default:
            return 0;
    }
}

int fb_param_count(FB_RuntimeContext* ctx) {
    return ctx ? ctx->paramCount : 0;
}

// =============================================================================
// Return Value Setting (used by plugin functions)
// =============================================================================

void fb_return_int(FB_RuntimeContext* ctx, int32_t value) {
    if (!ctx) return;
    
    ctx->returnValue.type = FB_PARAM_TYPE_INT;
    ctx->returnValue.value.intValue = value;
    ctx->hasReturnValue = 1;
}

void fb_return_long(FB_RuntimeContext* ctx, int64_t value) {
    if (!ctx) return;
    
    ctx->returnValue.type = FB_PARAM_TYPE_LONG;
    ctx->returnValue.value.longValue = value;
    ctx->hasReturnValue = 1;
}

void fb_return_float(FB_RuntimeContext* ctx, float value) {
    if (!ctx) return;
    
    ctx->returnValue.type = FB_PARAM_TYPE_FLOAT;
    ctx->returnValue.value.floatValue = value;
    ctx->hasReturnValue = 1;
}

void fb_return_double(FB_RuntimeContext* ctx, double value) {
    if (!ctx) return;
    
    ctx->returnValue.type = FB_PARAM_TYPE_DOUBLE;
    ctx->returnValue.value.doubleValue = value;
    ctx->hasReturnValue = 1;
}

void fb_return_string(FB_RuntimeContext* ctx, const char* value) {
    if (!ctx) return;
    
    // Make a copy of the string in temporary storage
    const char* storedValue = "";
    if (value) {
        size_t len = strlen(value);
        char* temp = (char*)malloc(len + 1);
        if (temp) {
            strcpy(temp, value);
            storedValue = temp;
            
            // Store in temporary string array for cleanup
            if (ctx->tempStringCount < FB_MAX_TEMP_ALLOCS) {
                ctx->tempStrings[ctx->tempStringCount++] = temp;
            }
        }
    }
    
    ctx->returnValue.type = FB_PARAM_TYPE_STRING;
    ctx->returnValue.value.stringValue = storedValue;
    ctx->hasReturnValue = 1;
}

void fb_return_bool(FB_RuntimeContext* ctx, int value) {
    if (!ctx) return;
    
    ctx->returnValue.type = FB_PARAM_TYPE_BOOL;
    ctx->returnValue.value.boolValue = value ? 1 : 0;
    ctx->hasReturnValue = 1;
}

// =============================================================================
// Return Value Getting (used by code generator)
// =============================================================================

int32_t fb_context_get_return_int(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasReturnValue) return 0;
    
    switch (ctx->returnValue.type) {
        case FB_PARAM_TYPE_INT:
            return ctx->returnValue.value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (int32_t)ctx->returnValue.value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (int32_t)ctx->returnValue.value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (int32_t)ctx->returnValue.value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return ctx->returnValue.value.boolValue;
        default:
            return 0;
    }
}

int64_t fb_context_get_return_long(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasReturnValue) return 0;
    
    switch (ctx->returnValue.type) {
        case FB_PARAM_TYPE_INT:
            return (int64_t)ctx->returnValue.value.intValue;
        case FB_PARAM_TYPE_LONG:
            return ctx->returnValue.value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (int64_t)ctx->returnValue.value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (int64_t)ctx->returnValue.value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (int64_t)ctx->returnValue.value.boolValue;
        default:
            return 0;
    }
}

float fb_context_get_return_float(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasReturnValue) return 0.0f;
    
    switch (ctx->returnValue.type) {
        case FB_PARAM_TYPE_INT:
            return (float)ctx->returnValue.value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (float)ctx->returnValue.value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return ctx->returnValue.value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return (float)ctx->returnValue.value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (float)ctx->returnValue.value.boolValue;
        default:
            return 0.0f;
    }
}

double fb_context_get_return_double(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasReturnValue) return 0.0;
    
    switch (ctx->returnValue.type) {
        case FB_PARAM_TYPE_INT:
            return (double)ctx->returnValue.value.intValue;
        case FB_PARAM_TYPE_LONG:
            return (double)ctx->returnValue.value.longValue;
        case FB_PARAM_TYPE_FLOAT:
            return (double)ctx->returnValue.value.floatValue;
        case FB_PARAM_TYPE_DOUBLE:
            return ctx->returnValue.value.doubleValue;
        case FB_PARAM_TYPE_BOOL:
            return (double)ctx->returnValue.value.boolValue;
        default:
            return 0.0;
    }
}

StringDescriptor* fb_context_get_return_string(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasReturnValue) {
        return string_new_utf8("");
    }
    
    if (ctx->returnValue.type == FB_PARAM_TYPE_STRING) {
        const char* str = ctx->returnValue.value.stringValue;
        return string_new_utf8(str ? str : "");
    }
    
    // For non-string types, return empty string
    return string_new_utf8("");
}

// =============================================================================
// Error Handling
// =============================================================================

void fb_set_error(FB_RuntimeContext* ctx, const char* message) {
    if (!ctx) return;
    
    ctx->hasError = 1;
    
    if (message) {
        strncpy(ctx->errorMessage, message, sizeof(ctx->errorMessage) - 1);
        ctx->errorMessage[sizeof(ctx->errorMessage) - 1] = '\0';
    } else {
        ctx->errorMessage[0] = '\0';
    }
}

int fb_has_error(FB_RuntimeContext* ctx) {
    return ctx ? ctx->hasError : 0;
}

int fb_context_has_error(FB_RuntimeContext* ctx) {
    return fb_has_error(ctx);
}

StringDescriptor* fb_context_get_error(FB_RuntimeContext* ctx) {
    if (!ctx || !ctx->hasError) {
        return string_new_utf8("");
    }
    
    return string_new_utf8(ctx->errorMessage);
}

// =============================================================================
// Memory Management (for plugin use)
// =============================================================================

void* fb_alloc(FB_RuntimeContext* ctx, size_t size) {
    if (!ctx || ctx->tempAllocCount >= FB_MAX_TEMP_ALLOCS) {
        return NULL;
    }
    
    void* ptr = malloc(size);
    if (ptr) {
        ctx->tempAllocations[ctx->tempAllocCount++] = ptr;
    }
    
    return ptr;
}

const char* fb_create_string(FB_RuntimeContext* ctx, const char* str) {
    if (!ctx || !str) return "";
    
    size_t len = strlen(str);
    char* temp = (char*)malloc(len + 1);
    if (!temp) return "";
    
    strcpy(temp, str);
    
    // Store in temporary string array for cleanup
    if (ctx->tempStringCount < FB_MAX_TEMP_ALLOCS) {
        ctx->tempStrings[ctx->tempStringCount++] = temp;
    }
    
    return temp;
}