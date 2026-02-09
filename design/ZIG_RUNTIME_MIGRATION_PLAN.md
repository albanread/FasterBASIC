# Zig Runtime Migration Plan

## Status: Phases 1–3 Complete

The SAMM subsystem has been fully migrated to Zig:

| Phase | File | Lines | Status |
|-------|------|------:|--------|
| 1 | `samm_pool.c` → `samm_pool.zig` | ~600 | ✅ Done |
| 2 | (new) `samm_scope.zig` | ~300 | ✅ Done |
| 3 | `samm_core.c` → `samm_core.zig` | ~900 | ✅ Done |

All 285/285 E2E tests and 412/412 unit tests pass. The pattern is proven:
Zig `build-lib` → static `.a` → linked by `main.zig` via `cc`.

---

## Remaining C Runtime Files

15 files, ~7,400 lines of C remain in `zig_compiler/runtime/`.

### Tier 1 — High Value (migrate next)

| File | Lines | Why | Dependencies |
|------|------:|-----|-------------|
| `string_utf32.c` | 1,639 | Largest file. UTF-8↔UTF-32 codec, all string builtins (MID$, LEFT$, INSTR, UCASE$, etc.). Zig's `std.unicode` provides free UTF validation. Comptime encoding dispatch replaces C macro hacks (`STR_CHAR`, `STR_SET_CHAR`). Already calls `samm_alloc_string()`. | `string_descriptor.h`, `samm_bridge.h`, `samm_pool.h`, `string_pool.h`, `basic_runtime.h` |
| `list_ops.c` | 1,163 | Linked-list engine with heterogeneous atom types. Heavy `void*` casting and manual type-dispatch — natural fit for Zig tagged unions and exhaustive `switch`. Already depends on `samm_pool.zig` and `samm_core.zig`. | `list_ops.h`, `string_descriptor.h`, `samm_bridge.h`, `samm_pool.h` |

**Combined: ~2,800 lines. Estimated effort: 2–3 sessions.**

### Tier 2 — Medium Value (quick wins)

| File | Lines | Why | Dependencies |
|------|------:|-----|-------------|
| `memory_mgmt.c` | 143 | Thin wrappers (`basic_malloc`, `basic_calloc`, `basic_free`) with optional debug counters. Trivial port. Could use Zig allocator interface internally. | `basic_runtime.h` |
| `class_runtime.c` | 225 | Object alloc/delete, vtable dispatch, `IS` type-check. Clean, tight SAMM integration. Zig pointer safety eliminates `void*` casts. | `class_runtime.h`, `samm_bridge.h` |
| `string_ops.c` | 374 | Legacy `BasicString*` ref-counted string ops. Straightforward malloc/free wrappers. | `basic_runtime.h` |
| `conversion_ops.c` | 147 | Type conversions (int↔string, float↔string). Uses `snprintf`/`atof`. Zig `std.fmt` removes format-string risk. | `basic_runtime.h` |

**Combined: ~890 lines. Estimated effort: 1 session.**

### Tier 3 — Low Value (migrate if needed)

| File | Lines | Why | Notes |
|------|------:|-----|-------|
| `array_ops.c` | 796 | Multi-dim array alloc, bounds check, REDIM. Uses `stdarg.h` varargs — awkward in Zig. | Port only if array system needs changes |
| `math_ops.c` | 423 | Thin wrappers over libm. Zig can call libm directly. | Negligible benefit |
| `io_ops.c` | 411 | Console/file I/O via printf/scanf/fopen. Heavy libc dependency. | Works fine as C |
| `io_ops_format.c` | 244 | PRINT USING formatter. Fiddly string parsing. | Works fine as C |
| `basic_data.c` | 128 | DATA/READ/RESTORE. Uses `__attribute__((weak))`. | Check Zig weak export support first |
| `fbc_bridge.c` | 177 | Non-inline wrappers for QBE codegen. Must stay in sync with codegen. | Migrate only if codegen changes |
| `array_descriptor_runtime.c` | 53 | `array_descriptor_erase` + `_destroy`. | Tiny, low risk either way |
| `basic_runtime.c` | 425 | Core init/cleanup, arena, exception/setjmp stack, file table. | **Migrate last** — touches everything |

### Already Dead

| File | Lines | Action |
|------|------:|--------|
| `string_pool.c` | 22 | Legacy stub. Can delete once no object files reference it. |

---

## Migration Order

```
  Tier 2 quick wins          Tier 1 big files
  (memory_mgmt.c,            (string_utf32.c,
   class_runtime.c,            list_ops.c)
   string_ops.c,                  │
   conversion_ops.c)              │
        │                         │
        ▼                         ▼
   libruntime_misc.a        libstring_utf32.a
        │                   liblist_ops.a
        │                         │
        └────────┬────────────────┘
                 ▼
          link via main.zig
          (same pattern as samm)
```

### Recommended sequence

1. **Tier 2 first** — low risk, builds confidence, proves the pattern
   generalises beyond SAMM.
2. **`string_utf32.c`** — highest single-file payoff. Zig's unicode
   support and comptime dispatch are a genuine upgrade.
3. **`list_ops.c`** — tagged unions eliminate the atom-type dispatch bugs.
   Completes the SAMM-adjacent cluster.
4. **Tier 3** — only if a file needs modification anyway. Don't migrate
   working code for the sake of it.

---

## Build Strategy

Each migrated file becomes a separate `zig build-lib` step in `build.zig`,
producing a static `.a` that `main.zig` discovers and passes to `cc`.
This is the same pattern used for `libsamm_pool.a`, `libsamm_scope.a`,
and `libsamm_core.a`.

### Naming convention

| C source | Zig source | Library |
|----------|-----------|---------|
| `memory_mgmt.c` | `memory_mgmt.zig` | `libmemory_mgmt.a` |
| `class_runtime.c` | `class_runtime.zig` | `libclass_runtime.a` |
| `string_ops.c` | `string_ops.zig` | `libstring_ops.a` |
| `conversion_ops.c` | `conversion_ops.zig` | `libconversion_ops.a` |
| `string_utf32.c` | `string_utf32.zig` | `libstring_utf32.a` |
| `list_ops.c` | `list_ops.zig` | `liblist_ops.a` |

### Alternative: consolidate libraries

Instead of one `.a` per file, group Tier 2 into a single
`libruntime_zig.a` to reduce link args. Decision deferred until
first Tier 2 file is ported.

---

## Technical Notes

### Lessons from Phases 1–3

1. **macOS stderr**: Use `extern const __stderrp: *anyopaque` with a
   `getStderr()` wrapper — not `c.stderr`.
2. **Variadic C functions**: Zig string literals (`[:0]const u8`) must be
   cast to `[*:0]const u8` before passing to C variadic functions like
   `fprintf`.
3. **Error handling in catch blocks**: When a catch block's value is
   assigned, use labeled breaks (`catch blk: { break :blk null; }`).
4. **Weak symbols**: `basic_data.c` uses `__attribute__((weak))`. Zig
   supports `@export` with `.linkage = .weak` — verify before migrating.
5. **`callconv(.c)`**: Zig 0.15 uses lowercase `.c` not `.C`.
6. **Thread-local**: `threadlocal var` works but can't be exported via
   `@export` — use a getter function instead.
7. **Build ordering**: Each `addSystemCommand` step in `build.zig` needs
   `dependOn` on the mkdir step to avoid race conditions.

### Risks per tier

| Tier | Risk | Mitigation |
|------|------|-----------|
| 2 | Very low — simple wrappers | Port one file, run full test suite |
| 1 (string_utf32) | Medium — encoding edge cases | Extensive existing test coverage for string ops |
| 1 (list_ops) | Medium — complex linked-list logic | SAMM integration already proven |
| 3 | Low–High (varies) | Don't migrate unless needed |

---

## Success Criteria (per file)

- [ ] `zig build` succeeds with no warnings
- [ ] Original `.c` renamed to `.c.bak`
- [ ] `bash run_e2e_tests.sh` — 285/285 pass
- [ ] `bash run_tests_parallel.sh` — 412/412 pass
- [ ] No `void*` casts in internal Zig code
- [ ] `.c.bak` preserved for reference
- [ ] Git commit with passing CI
