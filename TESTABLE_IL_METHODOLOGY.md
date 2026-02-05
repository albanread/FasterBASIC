# Methodology for Writing Testable QBE IL Code

## Overview

We've discovered a systematic approach for writing complex, debuggable code in QBE Intermediate Language (IL) by treating it as a software engineering problem rather than just assembly programming.

**Key Insight:** Low-level IL code can be engineered with the same rigor as high-level code by breaking it into small, testable units.

---

## The Problem with Traditional IL Development

### Typical Approach (What NOT to do)
- Write large monolithic functions (100+ lines)
- Mix multiple concerns in one function
- No way to test individual pieces
- Debug by staring at assembly output
- Rely on printf debugging or GDB
- Fix bugs by trial-and-error

### Why This Fails
1. **Cognitive overload** - Too much to hold in your head
2. **Poor isolation** - Can't tell which part is broken
3. **Debugging difficulty** - Bug could be anywhere
4. **Integration hell** - Everything breaks at once
5. **Slow iteration** - Full recompile to test each change

---

## The Testable IL Methodology

### Core Principles

#### 1. **Granular Decomposition**
Break every complex function into the smallest possible units.

**Bad:** One 200-line function that does everything
```qbe
function l $hashmap_find_slot(...) {
    # 200 lines of complex logic
    # Hash calculation, probing, comparison, wrapping...
}
```

**Good:** Many 5-20 line functions, each doing ONE thing
```qbe
export function w $hashmap_compute_index(w %hash, w %capacity) {
    %index =w rem %hash, %capacity
    ret %index
}

export function l $hashmap_get_entry_at_index(l %entries, w %index) {
    %idx_l =l extsw %index
    %offset =l mul %idx_l, 24
    %entry =l add %entries, %offset
    ret %entry
}
```

#### 2. **Export Everything for Testing**
Make ALL helper functions `export` so they can be called from C test code.

**Rationale:**
- You can test each piece independently
- Verify assumptions at every level
- Isolate bugs to specific functions
- Build confidence from bottom up

**Example:**
```qbe
# Even "internal" helpers are exported
export function w $hashmap_load_entry_state(l %entry) {
    %state_ptr =l add %entry, 20
    %state =w loadw %state_ptr
    ret %state
}
```

#### 3. **One Responsibility Per Function**
Each function should do exactly ONE thing.

**Examples of Single-Responsibility Functions:**
- Compute hash % capacity
- Get entry pointer at index
- Load one field from a struct
- Store one field to a struct
- Compare two strings
- Increment a counter

#### 4. **Clear Input/Output Contracts**
Every function should have:
- Well-defined inputs (types, ranges)
- Predictable outputs
- No hidden side effects (when possible)
- Documented memory layout assumptions

#### 5. **Comprehensive C Test Harness**
For every IL module, create extensive C tests.

**Test Structure:**
```c
// Test each helper individually
TEST(compute_index_basic) {
    uint32_t index = hashmap_compute_index(280767167, 16);
    ASSERT_EQ(index, 15, "apple hash mod 16 should be 15");
}

TEST(get_entry_at_index) {
    char entries[96];
    void* entry1 = hashmap_get_entry_at_index(entries, 1);
    ASSERT_PTR_EQ(entry1, entries + 24, "entry 1 at offset 24");
}
```

---

## Step-by-Step Process

### Phase 1: Design (Before Writing IL)

1. **Identify the high-level operations**
   - What does the user call? (API functions)
   - Example: `hashmap_insert`, `hashmap_lookup`, `hashmap_remove`

2. **Break down into sub-problems**
   - What smaller operations are needed?
   - Example: compute index, find slot, load entry, store entry

3. **Define data structures**
   - Document memory layouts with offsets
   - Example: entry at offset 0: key, offset 8: value, etc.

4. **Create function signatures**
   - Name each helper
   - Define inputs and outputs
   - Keep types simple and consistent

### Phase 2: Implement Bottom-Up

1. **Start with the simplest helpers**
   - Arithmetic operations (hash % capacity)
   - Memory access (load/store single fields)
   - No control flow yet

2. **Write C tests for each helper**
   - Test correct behavior
   - Test edge cases
   - Test with various inputs

3. **Verify each helper before moving on**
   - Must pass all tests before building on it
   - Fix bugs immediately while context is fresh

4. **Build up in layers**
   - Layer 1: Arithmetic and memory access
   - Layer 2: Simple algorithms (find entry at index)
   - Layer 3: Control flow (linear probe with loop)
   - Layer 4: High-level operations (insert, lookup)

### Phase 3: Integration Testing

1. **Test combinations of helpers**
   - Do they work together?
   - Example: compute_index + get_entry_at_index

2. **Test full workflows**
   - Insert then lookup
   - Multiple inserts
   - Updates and removals

3. **Test edge cases at integration level**
   - Empty structures
   - Full structures
   - Boundary conditions

### Phase 4: Refinement

1. **Profile and optimize hot paths**
   - Now that it works, make it fast
   - But keep tests passing!

2. **Consolidate if beneficial**
   - Some helpers might be inlined
   - But keep exports for testing

3. **Document thoroughly**
   - What each function does
   - Memory layouts
   - Assumptions and invariants

---

## Practical Guidelines

### Naming Conventions

**Prefix by module:**
```qbe
export function l $hashmap_new(w %capacity)
export function w $hashmap_insert(l %map, l %key, l %value)
export function l $hashmap_lookup(l %map, l %key)
```

**Action verbs for operations:**
- `compute_*` - Calculate a value
- `load_*` - Read from memory
- `store_*` - Write to memory
- `get_*` - Retrieve something
- `set_*` - Update something
- `check_*` - Boolean test

**Descriptive names:**
```qbe
# Good: Clear what it does
export function w $hashmap_compute_index(w %hash, w %capacity)

# Bad: Unclear
export function w $hash_idx(w %h, w %c)
```

### Type Discipline

**Be explicit about sizes:**
- `w` (32-bit) for: indices, hashes, states, small integers
- `l` (64-bit) for: pointers, large counts, sizes
- `s` (single float), `d` (double) for floating point

**Use sign extension explicitly:**
```qbe
%idx_l =l extsw %index    # Extend 32-bit to 64-bit
```

**Match comparison types:**
```qbe
# Both operands are w (32-bit)
%cmp =w cultw %index, %capacity

# Both operands are l (64-bit)
%cmp =w cultl %size, %total
```

### Memory Layout Documentation

**Always document struct layouts:**
```qbe
# HashMap struct (32 bytes):
#   offset  0: l capacity      - allocated slots
#   offset  8: l size          - entries in use
#   offset 16: l entries       - pointer to entry array
#   offset 24: l tombstones    - tombstone count
```

**Create helper functions for each field:**
```qbe
export function l $hashmap_load_capacity(l %map) {
    %capacity =l loadl %map    # offset 0
    ret %capacity
}

export function l $hashmap_load_size(l %map) {
    %size_ptr =l add %map, 8
    %size =l loadl %size_ptr
    ret %size
}
```

### Control Flow Patterns

**Always use explicit jumps (no fall-through):**
```qbe
@check_condition
    %is_empty =w ceqw %state, %empty
    jnz %is_empty, @handle_empty, @check_next

@handle_empty
    # ... handle it ...
    ret %result    # or jmp to next section

@check_next
    # ... continue ...
```

**Wrap-around loops:**
```qbe
@next_probe
    %index =w add %index, 1
    %at_end =w cugew %index, %capacity
    jnz %at_end, @wrap, @no_wrap

@wrap
    %index =w copy 0
    jmp @continue    # Explicit jump!

@no_wrap
@continue
    %probes =w add %probes, 1
    jmp @probe_loop
```

---

## Testing Patterns

### Unit Test Template

```c
#include <stdio.h>
#include <assert.h>

// External QBE functions
extern uint32_t module_helper_function(uint32_t arg);

#define ASSERT_EQ(actual, expected, msg) \
    do { \
        if ((actual) != (expected)) { \
            printf("FAIL: %s\n", msg); \
            printf("  Expected: %u, Got: %u\n", expected, actual); \
            return 1; \
        } \
    } while(0)

int test_helper_function() {
    uint32_t result = module_helper_function(42);
    ASSERT_EQ(result, 84, "should double input");
    printf("PASS: test_helper_function\n");
    return 0;
}

int main() {
    int failures = 0;
    failures += test_helper_function();
    // ... more tests ...
    return failures;
}
```

### Integration Test Template

```c
int test_full_workflow() {
    // Setup
    MyStruct* obj = module_create(16);
    
    // Test operations
    module_insert(obj, "key1", (void*)1);
    module_insert(obj, "key2", (void*)2);
    
    // Verify results
    void* val1 = module_lookup(obj, "key1");
    ASSERT_EQ((long)val1, 1, "lookup key1");
    
    void* val2 = module_lookup(obj, "key2");
    ASSERT_EQ((long)val2, 2, "lookup key2");
    
    // Cleanup
    module_free(obj);
    return 0;
}
```

### Test Coverage Goals

**Aim for:**
- ✅ Every exported function has at least one test
- ✅ Every control flow path is exercised
- ✅ Edge cases: 0, 1, max values, boundaries
- ✅ Error conditions: NULL, invalid input, overflow
- ✅ Integration: multiple functions working together
- ✅ Stress tests: many operations, large data

---

## Example: Hash Table Implementation

### Bad Approach (Monolithic)

```qbe
# One giant function doing everything
function l $hashmap_find_slot(l %map, l %key, w %hash, w %for_insert) {
@start
    # Load map fields
    # Compute index
    # Loop through slots
    # Check empty/occupied/tombstone
    # Compare keys with strcmp
    # Handle wrap-around
    # Return result
    # ... 150 lines of intertwined logic ...
}
```

**Problems:**
- Can't test index computation separately
- Can't verify entry access logic
- Can't check key comparison alone
- Bug could be in any of 20 different operations
- Takes hours to debug

### Good Approach (Modular)

```qbe
# Layer 1: Basic operations
export function w $hashmap_compute_index(w %hash, w %capacity) {
    %index =w rem %hash, %capacity
    ret %index
}

export function l $hashmap_get_entry_at_index(l %entries, w %index) {
    %idx_l =l extsw %index
    %offset =l mul %idx_l, 24
    %entry =l add %entries, %offset
    ret %entry
}

export function w $hashmap_load_entry_state(l %entry) {
    %state_ptr =l add %entry, 20
    %state =w loadw %state_ptr
    ret %state
}

export function l $hashmap_load_entry_key(l %entry) {
    %key =l loadl %entry
    ret %key
}

# Layer 2: Use helpers in algorithm
export function l $hashmap_find_slot_simple(l %map, l %key, w %hash, w %for_insert) {
@start
    %capacity =l call $hashmap_load_capacity(l %map)
    %entries =l call $hashmap_load_entries(l %map)
    %cap_w =w copy %capacity
    
    %index =w call $hashmap_compute_index(w %hash, w %cap_w)
    # ... loop using helpers ...
}
```

**Benefits:**
- Each helper can be tested in isolation
- Bug in index computation? Test shows it immediately
- Bug in entry access? Test shows it immediately
- Build confidence layer by layer
- Takes minutes to debug (not hours)

---

## Real-World Results

### Case Study: QBE Hashmap Implementation

**Initial Approach:**
- Large monolithic `find_slot` function
- Took hours to debug
- Found bugs by trial and error
- Still had subtle bugs after "fixing"

**After Refactoring to Testable IL:**
- Created 15+ helper functions
- Wrote 13 unit tests
- All tests passed
- Integration test passed on first try
- **Total debug time: ~30 minutes after refactor**

**Bugs Found Through Granular Testing:**
1. Premature resize (wrong comparison operator)
2. Type size mismatches (64-bit vs 32-bit)
3. Missing explicit jumps (fall-through)

**Each bug isolated to specific function by tests!**

---

## Benefits Summary

### Development Speed
- ⏱️ **Faster debugging** - Isolate bugs to 5-line functions
- ⏱️ **Faster iteration** - Test small changes quickly
- ⏱️ **Faster learning** - Understand code in small chunks

### Code Quality
- ✅ **Higher confidence** - Every piece is verified
- ✅ **Better documentation** - Function names self-document
- ✅ **Easier maintenance** - Clear what each piece does
- ✅ **Fewer regressions** - Tests catch breakage

### Collaboration
- 👥 **Easier code review** - Review one function at a time
- 👥 **Knowledge transfer** - New developers can understand pieces
- 👥 **Parallel development** - Multiple people work on different helpers

---

## Applicability

### This methodology works for:
- ✅ Data structure implementations (hash tables, trees, queues)
- ✅ Algorithm implementations (sorting, searching, parsing)
- ✅ Runtime systems (memory allocators, GC, schedulers)
- ✅ Standard library functions (string ops, math, I/O)
- ✅ Compiler backends (code generation, optimization)

### Prerequisites:
- Target language supports functions (QBE, LLVM IR, etc.)
- Can export symbols for testing
- Have a higher-level language for tests (C, C++, etc.)
- Can link IL object files with test harness

---

## Conclusion

**Key Takeaway:** Don't write IL code like assembly. Write it like software.

**The Three Rules:**
1. **Break it down** - Small, single-purpose functions
2. **Export everything** - Make all helpers testable
3. **Test bottom-up** - Verify each piece before building on it

**Result:** Complex low-level code that's actually debuggable, maintainable, and reliable.

---

## Quick Reference

### Checklist for New IL Module

- [ ] Define high-level API functions
- [ ] Break down into helper functions
- [ ] Document memory layouts
- [ ] Implement simplest helpers first
- [ ] Export all helpers
- [ ] Write C test for each helper
- [ ] Verify tests pass before moving on
- [ ] Build up in layers
- [ ] Write integration tests
- [ ] Document each function
- [ ] Performance profiling (optional)
- [ ] Optimize hot paths (optional)

### Red Flags (Signs You're Doing It Wrong)

- 🚩 Functions over 50 lines
- 🚩 Can't explain what function does in one sentence
- 🚩 No way to test a piece independently
- 🚩 Debugging by commenting out code
- 🚩 "It works but I don't know why"
- 🚩 Fixing one bug creates two more
- 🚩 No one else can understand your code

### Green Lights (You're Doing It Right)

- ✅ Every function has a clear purpose
- ✅ Can test each function in isolation
- ✅ Tests fail when you introduce bugs
- ✅ New features are easy to add
- ✅ Code is easy to review
- ✅ Bugs are caught quickly
- ✅ You feel confident in your code

---

**Remember:** Low-level doesn't mean low-quality. Engineering principles apply at every level!