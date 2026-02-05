# Rosetta Code Tests

This directory contains implementations of Rosetta Code challenges in FasterBASIC.

## Tests

### 1. 100 Doors
**File:** `hundred_doors.bas`
**Challenge:** https://rosettacode.org/wiki/100_doors

Classic problem: 100 doors, all initially closed. Make 100 passes:
- Pass 1: Toggle every door (1, 2, 3, ...)
- Pass 2: Toggle every 2nd door (2, 4, 6, ...)
- Pass 3: Toggle every 3rd door (3, 6, 9, ...)
- Pass N: Toggle every Nth door

Question: Which doors are open after all passes?

**Algorithm:** A door is toggled once for each divisor it has. Only perfect squares have an odd number of divisors, so only doors 1, 4, 9, 16, 25, 36, 49, 64, 81, and 100 end up open.

**Features demonstrated:**
- Arrays (100-element integer array)
- Nested loops (100 passes × variable doors per pass)
- WHILE loops for stepping through doors
- Mathematical verification using SQR() function
- Pattern recognition and algorithm analysis

**Expected Output:** `hundred_doors.expected`

### 2. Levenshtein Distance
**File:** `levenshtein_distance.bas`  
**Challenge:** https://rosettacode.org/wiki/Levenshtein_distance

Calculates the minimum edit distance between two strings using dynamic programming.

### 3. GOSUB/RETURN Control Flow
**File:** `gosub_if_control_flow.bas`  
**Purpose:** Regression test for GOSUB/RETURN in multiline IF blocks

Tests that GOSUB/RETURN works correctly when called from within:
- Multiline IF...END IF blocks
- Nested IF statements
- WHILE loops containing IF blocks
- Multiple GOSUBs in the same IF block

This test validates the fix for a compiler bug where RETURN would incorrectly jump to after END IF instead of continuing execution within the IF block.

**Expected Output:** `gosub_if_control_flow.expected`

### 4. Ackermann Function
**File:** `ackermann.bas`
**Challenge:** https://rosettacode.org/wiki/Ackermann_function

The Ackermann function is a classic example of a recursive function that is not primitive recursive. It demonstrates deep recursion and extremely rapid growth.

**Definition:**
```
A(m, n) = n + 1                  if m = 0
A(m, n) = A(m-1, 1)              if m > 0 and n = 0
A(m, n) = A(m-1, A(m, n-1))      if m > 0 and n > 0
```

**Features demonstrated:**
- Recursive FUNCTION calls
- Deep recursion (function calls itself multiple times)
- LOCAL variables in functions
- Nested IF/THEN/ELSE logic
- Pattern verification with computed results

**Test Case:** Computes A(m,n) for m=0 to 3, n=0 to 4
**Notable Results:**
- A(0, n) = n + 1
- A(1, n) = n + 2
- A(2, n) = 2*n + 3
- A(3, n) = 2^(n+3) - 3

**Expected Output:** `ackermann.expected`

### 5. Mersenne Number Factors
**File:** `mersenne_factors.bas`  
**Challenge:** https://rosettacode.org/wiki/Factors_of_a_Mersenne_number

Finds factors of Mersenne numbers (2^P - 1) using optimized trial division with:
- Binary exponentiation for modular arithmetic
- Mersenne number properties (q = 2kP+1, q ≡ 1 or 7 mod 8)
- Primality testing

**Test Case:** Finds a factor of M929 (2^929 - 1)  
**Result:** Factor 13007 (k=7)  
**Expected Output:** `mersenne_factors.expected`

### 6. Addition Chain Exponentiation
**File:** `addition_chain_exponentiation.bas`
**Challenge:** https://rosettacode.org/wiki/Addition-chain_exponentiation

Efficient exponentiation using addition chains to minimize the number of multiplications.

### 7. Euler Method
**File:** `euler_method.bas` and `euler_method_v2.bas`
**Challenge:** https://rosettacode.org/wiki/Euler_method

Numerical solution of differential equations using Euler's method.

## Running Tests

### Run a single test:
```bash
./qbe_basic -o test_name tests/rosetta/test_name.bas
./test_name
```

### Verify expected output:
```bash
./test_name > actual.txt
diff -u tests/rosetta/test_name.expected actual.txt
```

### Run all rosetta tests:
```bash
./scripts/run_tests_simple.sh
```

## Test Format

Each test should include:
- `.bas` file - The FasterBASIC source code
- `.expected` file - Expected output for verification
- Comments at the top describing the challenge and algorithm
