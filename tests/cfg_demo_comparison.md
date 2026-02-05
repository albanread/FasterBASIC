# CFG Trace Comparison: Working vs. Broken

## Working Case: Nested WHILE Without IF

**Command**: `./qbe_basic -G tests/test_while_nested_simple.bas`

**Key Points**:
- Inner WHILE gets its own loop header (Block 3)
- Proper back-edge from WEND to loop header
- Two distinct loop structures visible in CFG

**CFG Structure**:
```
Block 1 (Outer WHILE Header) [LOOP HEADER]
  Statement [4]: WHILE
  Successors: 2 (body), 6 (exit)

Block 2 (Outer Loop Body)
  Statement [5]: PRINT
  Statement [6]: LET
  Successors: 3

Block 3 (Inner WHILE Header) [LOOP HEADER]  ← Inner loop visible!
  Statement [7]: WHILE
  Successors: 4 (body), 5 (exit)

Block 4 (Inner Loop Body)
  Statement [8]: PRINT
  Statement [9]: LET
  Statement [10]: WEND
  Successors: 3 (back to inner header)

Block 5 (After Inner WHILE)
  Statement [11]: LET
  Statement [12]: WEND
  Successors: 1 (back to outer header)
```

---

## Broken Case: WHILE Inside IF

**Command**: `./qbe_basic -G tests/test_while_if_nested.bas`

**Key Points**:
- Inner WHILE does NOT get its own block
- IF statement shows "then:9" - 9 nested statements trapped as children
- Only ONE loop structure in CFG (the outer loop)
- Inner WHILE/WEND invisible to CFG builder

**CFG Structure**:
```
Block 4 (Outer WHILE Header) [LOOP HEADER]
  Statement [10]: WHILE
  Successors: 5 (body), 6 (exit)

Block 5 (Outer Loop Body)
  Statement [11]: PRINT
  Statement [12]: IF - then:9 else:0  ← Inner WHILE trapped here!
  Statement [13]: LET
  Statement [14]: WEND
  Successors: 4 (back to outer header)

NO Block for inner WHILE header - it's missing!
The 9 statements inside IF (including inner WHILE and WEND)
are invisible to the CFG builder.
```

---

## Analysis

The difference is clear:
1. **Working case**: Statements processed sequentially by CFG builder
2. **Broken case**: IF statement's children never processed by CFG builder

This is why the inner loop only executes once - without proper CFG structure:
- No loop header block for condition check
- No back-edge from WEND to loop header
- Code generator can't create proper loop structure
