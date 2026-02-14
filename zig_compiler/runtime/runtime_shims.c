/*
 * runtime_shims.c — Thin wrappers for runtime functions that are either
 * declared as static inline in headers (so no symbol is emitted) or that
 * the QBE codegen emits under a legacy/alternate name.
 *
 * These are compiled into the fbc binary so the JIT linker can resolve
 * the symbols at runtime.
 */

#include <stdint.h>
#include <stddef.h>

/* ── Forward declarations (avoid pulling in full headers) ──────────── */

/* StringDescriptor layout (from string_descriptor.h):
 *   offset  0: void*   data
 *   offset  8: int64_t length
 *   offset 16: int64_t capacity
 *   offset 24: int32_t refcount
 *   ...
 */
typedef struct {
    void    *data;
    int64_t  length;
    int64_t  capacity;
    int32_t  refcount;
    /* remaining fields not needed here */
} StringDescriptorShim;

/* Functions implemented in terminal_io.zig */
extern void basic_cursor_hide(void);
extern void basic_cursor_show(void);
extern void basic_cursor_save(void);
extern void basic_cursor_restore(void);

/* Function implemented in list_ops.zig */
extern void list_remove(void *list, int64_t pos);

/* ── string_length ─────────────────────────────────────────────────── */
/*
 * In string_descriptor.h this is a static inline.  The QBE codegen
 * declares it as an extern call: `export function w $string_length(l %str)`
 * so we need an actual symbol.
 */
int64_t string_length(const void *str) {
    if (!str) return 0;
    const StringDescriptorShim *s = (const StringDescriptorShim *)str;
    return s->length;
}

/* ── basic_len ─────────────────────────────────────────────────────── */
/*
 * BASIC LEN() function — same as string_length but declared separately
 * by the codegen: `export function w $basic_len(l %str)`
 */
int64_t basic_len(const void *str) {
    return string_length(str);
}

/* ── list_erase ────────────────────────────────────────────────────── */
/*
 * The codegen emits calls to both list_remove and list_erase with the
 * same signature.  list_remove is the real implementation in list_ops.zig;
 * list_erase is just an alias.
 */
void list_erase(void *list, int64_t pos) {
    list_remove(list, pos);
}

/* ── Cursor legacy names ───────────────────────────────────────────── */
/*
 * The QBE codegen declares these with camelCase names (hideCursor, etc.)
 * but terminal_io.zig exports them as basic_cursor_hide, etc.
 * We provide wrappers under the legacy names.
 */
void hideCursor(void) {
    basic_cursor_hide();
}

void showCursor(void) {
    basic_cursor_show();
}

void saveCursor(void) {
    basic_cursor_save();
}

void restoreCursor(void) {
    basic_cursor_restore();
}