#include <stdlib.h>
// test_stubs.c — Weak stubs for extern symbols required by runtime unit tests.
// These satisfy the linker when running `zig build test` on runtime modules
// that declare extern functions from other runtime modules.
// Marked __attribute__((weak)) so that when the module under test itself
// exports a symbol (e.g. string_utf32 exports string_release), the real
// definition wins and there is no duplicate-symbol error.

#include <stddef.h>
#include <stdint.h>

#define WEAK __attribute__((weak))

// basic_runtime stubs
WEAK void basic_exit(int code) { exit(code); }
WEAK void basic_error_msg(const char *msg) { (void)msg; }
WEAK void basic_throw(int code) { (void)code; }

// string_ops stubs
WEAK void *str_new(const char *cstr) { (void)cstr; return NULL; }
WEAK void str_release(void *s) { (void)s; }
WEAK int str_to_int(void *s) { (void)s; return 0; }
WEAK double str_to_double(void *s) { (void)s; return 0.0; }

// string_utf32 stubs
WEAK void *string_mid(const void *str, int64_t start, int64_t length) {
    (void)str; (void)start; (void)length; return NULL;
}
WEAK void *string_left(const void *str, int64_t count) {
    (void)str; (void)count; return NULL;
}
WEAK void *string_right(const void *str, int64_t count) {
    (void)str; (void)count; return NULL;
}
WEAK void string_release(void *str) { (void)str; }
WEAK void string_retain(void *str) { (void)str; }
WEAK void *string_new_capacity(int64_t cap) { (void)cap; return NULL; }
WEAK int string_compare(const void *a, const void *b) { (void)a; (void)b; return 0; }
WEAK void *string_to_utf8(const void *str) { (void)str; return NULL; }
WEAK void *string_new_ascii(const char *s) { (void)s; return NULL; }
WEAK void *string_new_utf8(const char *s, int64_t len) { (void)s; (void)len; return NULL; }

// samm_core stubs
WEAK int samm_is_enabled(void) { return 0; }
WEAK void *samm_alloc_object(size_t size) { (void)size; return NULL; }
WEAK void samm_track_object(void *obj) { (void)obj; }
WEAK void samm_free_object(void *obj) { (void)obj; }
WEAK void *samm_alloc_list_atom(void) { return NULL; }
WEAK void *samm_alloc_list(void) { return NULL; }
WEAK void *samm_alloc_string(void) { return NULL; }
WEAK void samm_track(void *ptr, unsigned char type_id) { (void)ptr; (void)type_id; }
WEAK void samm_track_list(void *ptr) { (void)ptr; }
WEAK void samm_untrack(void *ptr) { (void)ptr; }
WEAK void samm_record_bytes_freed(size_t n) { (void)n; }

// samm_pool stubs (for files that extern these)
WEAK void samm_slab_pool_init(void *pool, unsigned slot_size, unsigned slots_per_slab, const char *name) {
    (void)pool; (void)slot_size; (void)slots_per_slab; (void)name;
}
WEAK void samm_slab_pool_destroy(void *pool) { (void)pool; }
WEAK void *samm_slab_pool_alloc(void *pool) { (void)pool; return NULL; }
WEAK void samm_slab_pool_free(void *pool, void *ptr) { (void)pool; (void)ptr; }
WEAK void samm_slab_pool_print_stats(const void *pool) { (void)pool; }
WEAK size_t samm_slab_pool_total_allocs(const void *pool) { (void)pool; return 0; }

// samm_scope stubs
WEAK void samm_scope_ensure_init(void) {}
WEAK void samm_scope_reset(int depth) { (void)depth; }
WEAK void samm_scope_add(int depth, void *ptr, unsigned char type_id, unsigned char sc) {
    (void)depth; (void)ptr; (void)type_id; (void)sc;
}
WEAK int samm_scope_remove(int depth, void *ptr, unsigned char *out_type, unsigned char *out_sc) {
    (void)depth; (void)ptr; (void)out_type; (void)out_sc; return 0;
}
WEAK int samm_scope_detach(int depth, void **out_ptrs, unsigned char **out_types, unsigned char **out_sc, size_t *out_count) {
    (void)depth; (void)out_ptrs; (void)out_types; (void)out_sc; (void)out_count; return 0;
}

// list_ops stubs
WEAK void list_free_from_samm(void *header_ptr) { (void)header_ptr; }
WEAK void list_atom_free_from_samm(void *atom_ptr) { (void)atom_ptr; }

// array_descriptor_runtime stubs
WEAK void array_descriptor_erase(void *desc) { (void)desc; }

// Extern global stubs for SAMM pools (weak)
// These are opaque pointers that tests should never actually dereference.
static char _dummy_pool[256];
WEAK void *g_string_desc_pool = _dummy_pool;
WEAK void *g_list_header_pool = _dummy_pool;
WEAK void *g_list_atom_pool = _dummy_pool;
WEAK void *g_object_pools[6] = {
    _dummy_pool, _dummy_pool, _dummy_pool,
    _dummy_pool, _dummy_pool, _dummy_pool,
};

// basic_runtime file registration stubs
WEAK void _basic_register_file(void *f) { (void)f; }
WEAK void _basic_unregister_file(void *f) { (void)f; }

// terminal_io paint mode stub (used by io_ops_format)
WEAK int basic_is_paint_mode(void) { return 0; }
