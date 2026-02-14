/*
 * hashmap_runtime.c — Native C hashmap for FasterBASIC JIT runtime
 *
 * This is a C equivalent of runtime/hashmap.qbe.  It implements the same
 * interface (hashmap_new, hashmap_insert, hashmap_lookup, …) so that JIT-
 * compiled code can call the hashmap functions without needing to compile
 * the QBE IL version.
 *
 * Data layout (must match hashmap.qbe):
 *   HashMap struct (32 bytes):
 *     offset  0: int64_t capacity
 *     offset  8: int64_t size
 *     offset 16: Entry*  entries
 *     offset 24: int64_t tombstones
 *
 *   Entry struct (24 bytes):
 *     offset  0: char*   key       (strdup'd C string)
 *     offset  8: void*   value
 *     offset 16: int32_t hash
 *     offset 20: int32_t state     (0=empty, 1=occupied, 2=tombstone)
 */

#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <stdio.h>

/* ── Constants (matching hashmap.qbe) ────────────────────────────────── */

#define HASHMAP_MIN_CAPACITY  16
#define ENTRY_EMPTY           0
#define ENTRY_OCCUPIED        1
#define ENTRY_TOMBSTONE       2

#define FNV_OFFSET 2166136261u
#define FNV_PRIME  16777619u

/* ── Data structures ─────────────────────────────────────────────────── */

typedef struct {
    char    *key;       /* offset  0 */
    void    *value;     /* offset  8 */
    int32_t  hash;      /* offset 16 */
    int32_t  state;     /* offset 20 */
} Entry;

typedef struct {
    int64_t  capacity;    /* offset  0 */
    int64_t  size;        /* offset  8 */
    Entry   *entries;     /* offset 16 */
    int64_t  tombstones;  /* offset 24 */
} HashMap;

/* ── Internal helpers ────────────────────────────────────────────────── */

static uint32_t hash_string(const char *key) {
    uint32_t h = FNV_OFFSET;
    if (!key) return h;
    for (const unsigned char *p = (const unsigned char *)key; *p; p++) {
        h ^= *p;
        h *= FNV_PRIME;
    }
    return h;
}

static int keys_equal(const char *a, const char *b) {
    if (a == b) return 1;
    if (!a || !b) return 0;
    return strcmp(a, b) == 0;
}

/*
 * Find the slot for a key.
 * If for_insert is true, returns the first empty/tombstone slot where we
 * can place a new entry (or an existing slot if the key already exists).
 * If for_insert is false, returns the slot containing the key, or NULL.
 */
static Entry *find_slot(HashMap *map, const char *key, uint32_t h, int for_insert) {
    int64_t cap = map->capacity;
    if (cap == 0) return NULL;

    int64_t idx = (uint32_t)h % (uint32_t)cap;
    Entry *first_tombstone = NULL;

    for (int64_t i = 0; i < cap; i++) {
        Entry *e = &map->entries[idx];

        if (e->state == ENTRY_EMPTY) {
            /* Slot is empty — key not present */
            if (for_insert) {
                return first_tombstone ? first_tombstone : e;
            }
            return NULL;
        }

        if (e->state == ENTRY_TOMBSTONE) {
            if (for_insert && !first_tombstone) {
                first_tombstone = e;
            }
        } else if (e->state == ENTRY_OCCUPIED) {
            if ((int32_t)h == e->hash && keys_equal(key, e->key)) {
                return e;  /* Found existing key */
            }
        }

        idx = (idx + 1) % cap;
    }

    /* Table is full (should not happen with proper load-factor management) */
    return first_tombstone;
}

static int needs_resize(HashMap *map) {
    /* Resize when (size + tombstones) * 10 >= capacity * 7 */
    int64_t used = map->size + map->tombstones;
    return (used * 10) >= (map->capacity * 7);
}

static int do_resize(HashMap *map, int64_t new_cap) {
    if (new_cap < HASHMAP_MIN_CAPACITY) new_cap = HASHMAP_MIN_CAPACITY;

    Entry *new_entries = (Entry *)calloc((size_t)new_cap, sizeof(Entry));
    if (!new_entries) return 0;

    Entry *old_entries = map->entries;
    int64_t old_cap = map->capacity;

    /* Temporarily swap in new table */
    map->entries = new_entries;
    map->capacity = new_cap;
    map->size = 0;
    map->tombstones = 0;

    /* Re-insert occupied entries */
    for (int64_t i = 0; i < old_cap; i++) {
        Entry *old = &old_entries[i];
        if (old->state != ENTRY_OCCUPIED) continue;

        uint32_t h = (uint32_t)old->hash;
        Entry *slot = find_slot(map, old->key, h, 1);
        if (slot) {
            slot->key   = old->key;   /* transfer ownership */
            slot->value = old->value;
            slot->hash  = old->hash;
            slot->state = ENTRY_OCCUPIED;
            map->size++;
        } else {
            /* Should not happen */
            free(old->key);
        }
    }

    free(old_entries);
    return 1;
}

/* ── Public API (matches hashmap.qbe exports) ────────────────────────── */

void *hashmap_new(int32_t initial_capacity) {
    int64_t cap = initial_capacity;
    if (cap < HASHMAP_MIN_CAPACITY) cap = HASHMAP_MIN_CAPACITY;

    HashMap *map = (HashMap *)malloc(sizeof(HashMap));
    if (!map) return NULL;

    map->entries = (Entry *)calloc((size_t)cap, sizeof(Entry));
    if (!map->entries) {
        free(map);
        return NULL;
    }

    map->capacity   = cap;
    map->size       = 0;
    map->tombstones = 0;

    return map;
}

void hashmap_free(void *map_ptr) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return;

    /* Free all key strings */
    for (int64_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].state == ENTRY_OCCUPIED && map->entries[i].key) {
            free(map->entries[i].key);
        }
    }

    free(map->entries);
    free(map);
}

int32_t hashmap_insert(void *map_ptr, const char *key, void *value) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return 0;

    uint32_t h = hash_string(key);

    /* Resize if needed */
    if (needs_resize(map)) {
        int64_t new_cap = map->capacity * 2;
        if (!do_resize(map, new_cap)) return 0;
    }

    Entry *slot = find_slot(map, key, h, 1);
    if (!slot) return 0;

    if (slot->state == ENTRY_OCCUPIED) {
        /* Update existing — free old key, replace */
        free(slot->key);
        slot->key   = key ? strdup(key) : NULL;
        slot->value = value;
        slot->hash  = (int32_t)h;
        return 1;
    }

    int was_tombstone = (slot->state == ENTRY_TOMBSTONE);

    slot->key   = key ? strdup(key) : NULL;
    slot->value = value;
    slot->hash  = (int32_t)h;
    slot->state = ENTRY_OCCUPIED;
    map->size++;

    if (was_tombstone) {
        map->tombstones--;
    }

    return 1;
}

void *hashmap_lookup(void *map_ptr, const char *key) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return NULL;

    uint32_t h = hash_string(key);
    Entry *slot = find_slot(map, key, h, 0);
    if (slot && slot->state == ENTRY_OCCUPIED) {
        return slot->value;
    }
    return NULL;
}

int32_t hashmap_has_key(void *map_ptr, const char *key) {
    return hashmap_lookup(map_ptr, key) != NULL ? 1 : 0;
}

int32_t hashmap_remove(void *map_ptr, const char *key) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return 0;

    uint32_t h = hash_string(key);
    Entry *slot = find_slot(map, key, h, 0);
    if (!slot || slot->state != ENTRY_OCCUPIED) return 0;

    /* Free key string */
    free(slot->key);
    slot->key   = NULL;
    slot->value = NULL;
    slot->hash  = 0;
    slot->state = ENTRY_TOMBSTONE;

    map->size--;
    map->tombstones++;

    return 1;
}

int64_t hashmap_size(void *map_ptr) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return 0;
    return map->size;
}

void hashmap_clear(void *map_ptr) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return;

    /* Free all key strings */
    for (int64_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].state == ENTRY_OCCUPIED && map->entries[i].key) {
            free(map->entries[i].key);
        }
    }

    memset(map->entries, 0, (size_t)map->capacity * sizeof(Entry));
    map->size = 0;
    map->tombstones = 0;
}

/*
 * Return a malloc'd null-terminated array of key pointers (char*).
 * The caller is responsible for freeing the array (but NOT the key
 * strings — they are owned by the hashmap).
 */
void *hashmap_keys(void *map_ptr) {
    HashMap *map = (HashMap *)map_ptr;
    if (!map) return NULL;

    int64_t count = map->size;
    char **arr = (char **)malloc((size_t)(count + 1) * sizeof(char *));
    if (!arr) return NULL;

    int64_t idx = 0;
    for (int64_t i = 0; i < map->capacity; i++) {
        if (map->entries[i].state == ENTRY_OCCUPIED) {
            arr[idx++] = map->entries[i].key;
        }
    }
    arr[idx] = NULL;  /* null terminator */

    return arr;
}