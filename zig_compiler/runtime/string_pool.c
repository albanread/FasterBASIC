//
// string_pool.c
// FasterBASIC Runtime - String Descriptor Pool (Phase 4 migration stub)
//
// The string descriptor pool has been migrated to the generic SammSlabPool
// infrastructure.  All pool logic is now handled by:
//
//   g_string_desc_pool   (SammSlabPool, defined in samm_pool.c)
//   string_desc_alloc()  (inline, defined in string_pool.h)
//   string_desc_free()   (inline, defined in string_pool.h)
//
// This file exists only to provide the legacy g_string_pool symbol for
// backward compatibility with call sites that still reference it.
// The StringDescriptorPool type is now a placeholder struct with no
// functional members — all operations are forwarded to g_string_desc_pool
// via inline wrappers in string_pool.h.
//

#include "string_pool.h"

// Legacy global — kept for link compatibility.
// No longer functional; all operations go through g_string_desc_pool.
StringDescriptorPool g_string_pool = {0};